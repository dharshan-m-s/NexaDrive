import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexadrive/services/api.dart';
import 'package:nexadrive/services/session.dart';
import 'package:nexadrive/services/sync_service.dart';
import 'package:nexadrive/services/transfer_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// An in-process stand-in for the `/api/sync/*`, `/api/folders`,
/// `/api/uploads/*` and `/api/files/download` endpoints, implementing the same
/// contract the Rust server does closely enough to exercise the real client
/// sync engine end to end:
///
///  * `manifest` returns the full live tree plus a `server_time` cursor;
///  * `delta` returns only what changed after that cursor, plus tombstones;
///  * `sha256` is computed from the stored bytes, because the engine's entire
///    change-vs-conflict decision depends on it comparing equal to the local
///    hash after a successful transfer;
///  * chunked uploads resume strictly from the byte offset the server reports.
class FakeSyncServer {
  final Map<String, List<int>> files = {};
  final Set<String> folders = {};
  final Map<String, DateTime> _modified = {};
  final Map<String, DateTime> _deleted = {};
  final Map<String, _OpenUpload> _uploads = {};

  /// Request counters, so a test can assert that "no work" really means no
  /// network traffic rather than merely a zeroed result struct.
  int manifestCalls = 0;
  int deltaCalls = 0;
  int chunkCalls = 0;
  int downloadCalls = 0;
  int createFolderCalls = 0;
  int syncDeleteCalls = 0;

  /// Upload ids the server accepted, in order — used to assert chunk ordering.
  final List<String> uploadOrder = [];

  /// Device ids the client announced, in order.
  final List<String> announcedDeviceIds = [];

  /// When set, the next chunk for a file with this remote name is rejected
  /// with a non-transient 400 so the failure path is reached without waiting
  /// out the client's multi-second retry backoff.
  String? rejectChunkFor;
  int rejectionsRemaining = 0;

  /// Byte offsets the client sent, so a test can prove it did not restart a
  /// partially transferred upload from zero.
  final List<int> chunkOffsets = [];

  int _clock = 0;

  DateTime _stamp() => DateTime.utc(2026).add(Duration(seconds: ++_clock));

  static String sha(List<int> bytes) => sha256.convert(bytes).toString();

  void put(String path, String content) {
    final bytes = utf8.encode(content);
    files[path] = bytes;
    _modified[path] = _stamp();
    _deleted.remove(path);
  }

  void mkdir(String path) {
    folders.add(path);
    _modified[path] = _stamp();
    _deleted.remove(path);
  }

  /// Deletes remotely, recording a tombstone exactly as the server does.
  void remoteDelete(String path) {
    final removed = files.remove(path) != null || folders.remove(path);
    if (!removed) return;
    _deleted[path] = _stamp();
  }

  String? contentAt(String path) {
    final bytes = files[path];
    return bytes == null ? null : utf8.decode(bytes);
  }

  bool has(String path) => files.containsKey(path) || folders.contains(path);

  Set<String> get livePaths => {...files.keys, ...folders};

  DateTime? _since(Map<String, String> q) {
    final raw = q['since'];
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  List<Map<String, dynamic>> _entries(DateTime? since) {
    final out = <Map<String, dynamic>>[];
    for (final path in livePaths) {
      final when = _modified[path];
      if (when == null) continue;
      if (since != null && !when.isAfter(since)) continue;
      final bytes = files[path];
      out.add({
        'path': path,
        'kind': bytes == null ? 'folder' : 'file',
        'size': bytes?.length ?? 0,
        'sha256': bytes == null ? null : sha(bytes),
        'modified_at': when.toIso8601String(),
      });
    }
    out.sort((a, b) => (a['path'] as String).compareTo(b['path'] as String));
    return out;
  }

  List<String> _tombstones(DateTime? since) {
    final out = <String>[];
    _deleted.forEach((path, when) {
      if (since == null || when.isAfter(since)) out.add(path);
    });
    out.sort();
    return out;
  }

  http.Response _json(Object body, [int status = 200]) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );

  http.Response manifest(Map<String, String> q) {
    manifestCalls++;
    announcedDeviceIds.add(q['device_id'] ?? '');
    return _json({
      // The server echoes the id it was given (it only mints one when the
      // client had none), which is what makes concurrent first syncs converge
      // on a single identity.
      'device_id': q['device_id'] ?? 'server-minted-id',
      'entries': _entries(null),
      'tombstones': _tombstones(null),
      'server_time': _stamp().toIso8601String(),
    });
  }

  http.Response delta(Map<String, String> q) {
    deltaCalls++;
    announcedDeviceIds.add(q['device_id'] ?? '');
    final since = _since(q);
    return _json({
      'device_id': q['device_id'] ?? 'server-minted-id',
      'entries': _entries(since),
      'tombstones': _tombstones(since),
      'server_time': _stamp().toIso8601String(),
    });
  }

  http.Response chunk(Map<String, String> q, List<int> body) {
    chunkCalls++;
    final id = q['upload_id']!;
    final offset = int.parse(q['offset']!);
    final total = int.parse(q['total']!);
    final name = q['name']!;
    final folder = q['path'] ?? '';
    final remote = folder.isEmpty ? name : '$folder/$name';
    if (rejectionsRemaining > 0 && rejectChunkFor == name) {
      rejectionsRemaining--;
      return _json({'error': 'rejected by test'}, 400);
    }
    final open = _uploads.putIfAbsent(id, () => _OpenUpload(remote));
    if (offset == 0) open.bytes.clear();
    chunkOffsets.add(offset);
    open.bytes.addAll(body);
    if (total == 0 || open.bytes.length >= total) {
      files[remote] = List<int>.from(open.bytes);
      _modified[remote] = _stamp();
      _deleted.remove(remote);
      _uploads.remove(id);
      return _json({'status': 'completed', 'offset': open.bytes.length});
    }
    return _json({'status': 'uploading', 'offset': open.bytes.length});
  }

  http.Client client() => MockClient((request) async {
        final path = request.url.path;
        final q = request.url.queryParameters;

        if (request.method == 'GET' && path == '/api/sync/manifest') {
          return manifest(q);
        }
        if (request.method == 'GET' && path == '/api/sync/delta') {
          return delta(q);
        }
        if (request.method == 'GET' && path == '/api/uploads/status') {
          // An unknown upload id means "a new upload starts at zero", never
          // "already finished" — reporting completed here would let the client
          // skip the transfer entirely and still record a synced baseline.
          final open = _uploads[q['upload_id']];
          return _json({
            'status': 'uploading',
            'bytes_received': open?.bytes.length ?? 0,
          });
        }
        if (request.method == 'POST' && path == '/api/uploads/chunk') {
          return chunk(q, request.bodyBytes);
        }
        if (request.method == 'POST' && path == '/api/folders') {
          createFolderCalls++;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          mkdir(body['path'] as String);
          return _json({'ok': true});
        }
        if (request.method == 'POST' && path == '/api/sync/delete') {
          syncDeleteCalls++;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          remoteDelete(body['path'] as String);
          _deleted[body['path'] as String] = _stamp();
          return _json({'ok': true});
        }
        if (request.method == 'GET' && path == '/api/files/download') {
          downloadCalls++;
          final bytes = files[q['path']];
          if (bytes == null) return _json({'error': 'not found'}, 404);
          return http.Response.bytes(bytes, 200,
              headers: {'content-type': 'application/octet-stream'});
        }
        return _json({'error': 'unexpected ${request.method} $path'}, 500);
      });
}

class _OpenUpload {
  _OpenUpload(this.remote);
  final String remote;
  final List<int> bytes = [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late FakeSyncServer server;
  late Api api;
  late SyncManager sync;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SyncManager.resetDeviceIdCache();
    root = await Directory.systemTemp.createTemp('nexadrive-sync-test-');
    server = FakeSyncServer();
    final session = Session()
      ..serverUrl = 'https://example.com'
      ..token = 'test-token';
    api = Api(session, client: server.client());
    sync = SyncManager(api);
    await sync.setFolder(root.path);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<void> writeLocal(String rel, String content) async {
    final file = File('${root.path}${Platform.pathSeparator}$rel');
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  String? readLocal(String rel) {
    final file = File('${root.path}${Platform.pathSeparator}$rel');
    return file.existsSync() ? file.readAsStringSync() : null;
  }

  bool existsLocal(String rel) =>
      File('${root.path}${Platform.pathSeparator}$rel').existsSync();

  group('first and repeat sync', () {
    test('first sync uploads the local tree and creates remote folders',
        () async {
      await writeLocal('alpha.txt', 'alpha-content');
      await writeLocal('docs/beta.txt', 'beta-content');
      await Directory('${root.path}${Platform.pathSeparator}empty')
          .create(recursive: true);

      final result = await sync.sync();

      expect(result.error, isNull);
      expect(result.errors, 0);
      expect(result.uploaded, 4,
          reason: '2 files + the "docs" and "empty" folders');
      expect(server.contentAt('alpha.txt'), 'alpha-content');
      expect(server.contentAt('docs/beta.txt'), 'beta-content');
      expect(server.folders, containsAll(<String>['docs', 'empty']));
    });

    test('a repeat sync with nothing changed does no work at all', () async {
      await writeLocal('alpha.txt', 'alpha-content');
      await sync.sync();

      final chunksAfterFirst = server.chunkCalls;
      final downloadsAfterFirst = server.downloadCalls;

      final second = await sync.sync();

      expect(second.uploaded, 0);
      expect(second.downloaded, 0);
      expect(second.deleted, 0);
      expect(second.conflicts, 0);
      expect(second.errors, 0);
      expect(server.chunkCalls, chunksAfterFirst,
          reason: 'an unchanged file must not be re-uploaded');
      expect(server.downloadCalls, downloadsAfterFirst);
      expect(server.deltaCalls, 1,
          reason: 'the second sync should use the delta cursor, not a manifest');
    });

    test('an empty local folder is created remotely and stays a folder',
        () async {
      await Directory('${root.path}${Platform.pathSeparator}photos')
          .create(recursive: true);
      await sync.sync();
      expect(server.folders, contains('photos'));

      final again = await sync.sync();
      expect(again.uploaded, 0,
          reason: 'an existing remote folder must not be re-created');
    });

    test('a zero-byte file round-trips', () async {
      await writeLocal('empty.bin', '');
      final result = await sync.sync();
      expect(result.errors, 0);
      expect(server.files.containsKey('empty.bin'), isTrue);
      expect(server.files['empty.bin'], isEmpty);
    });
  });

  group('local changes', () {
    test('a locally modified file is uploaded', () async {
      await writeLocal('alpha.txt', 'first');
      await sync.sync();

      await writeLocal('alpha.txt', 'second-and-longer');
      final result = await sync.sync();

      expect(result.uploaded, 1);
      expect(result.errors, 0);
      expect(server.contentAt('alpha.txt'), 'second-and-longer');
    });

    test('deleting a file locally propagates a remote delete', () async {
      await writeLocal('alpha.txt', 'alpha');
      await sync.sync();
      expect(server.has('alpha.txt'), isTrue);

      await File('${root.path}${Platform.pathSeparator}alpha.txt').delete();
      final result = await sync.sync();

      expect(result.deleted, 1);
      expect(server.has('alpha.txt'), isFalse);
      expect(server.syncDeleteCalls, 1);
    });
  });

  group('remote changes', () {
    test('a file added on another device is downloaded', () async {
      await sync.sync();
      server.put('from-phone.txt', 'written on the phone');

      final result = await sync.sync();

      expect(result.downloaded, 1);
      expect(readLocal('from-phone.txt'), 'written on the phone');
    });

    test('a remotely modified file overwrites the unchanged local copy',
        () async {
      await writeLocal('alpha.txt', 'original');
      await sync.sync();

      server.put('alpha.txt', 'changed-on-another-device');
      final result = await sync.sync();

      expect(result.downloaded, 1);
      expect(result.conflicts, 0);
      expect(readLocal('alpha.txt'), 'changed-on-another-device');
    });

    test('a remote folder is materialised locally', () async {
      await sync.sync();
      server.mkdir('shared');
      server.put('shared/notes.txt', 'hello');

      final result = await sync.sync();

      expect(result.errors, 0);
      expect(Directory('${root.path}${Platform.pathSeparator}shared')
          .existsSync(), isTrue);
      expect(readLocal('shared/notes.txt'), 'hello');
    });

    test('a deletion on another device removes the unchanged local file',
        () async {
      await writeLocal('alpha.txt', 'alpha');
      await sync.sync();

      server.remoteDelete('alpha.txt');
      final result = await sync.sync();

      expect(result.deleted, 1);
      expect(existsLocal('alpha.txt'), isFalse,
          reason: 'another device deleting a file must not leave a local copy');

      // The regression this guards: dropping the baseline without removing the
      // local file made the very next sync upload it again, silently undoing
      // the deletion.
      final after = await sync.sync();
      expect(after.uploaded, 0);
      expect(server.has('alpha.txt'), isFalse,
          reason: 'a remotely deleted file must not be resurrected');
    });

    test('a remote delete of a file edited locally keeps the local edit',
        () async {
      await writeLocal('alpha.txt', 'original');
      await sync.sync();

      server.remoteDelete('alpha.txt');
      await writeLocal('alpha.txt', 'edited-locally-meanwhile');

      final result = await sync.sync();

      expect(result.errors, 0);
      expect(result.uploaded, 1,
          reason: 'a local edit is newer intent than a remote tombstone');
      expect(server.contentAt('alpha.txt'), 'edited-locally-meanwhile');
    });
  });

  group('conflicts', () {
    Future<void> establishConflict() async {
      await writeLocal('doc.txt', 'base');
      await sync.sync();
      await writeLocal('doc.txt', 'local-edit-wins');
      server.put('doc.txt', 'remote-edit-differs');
    }

    test('simultaneous edits preserve both versions and touch neither side',
        () async {
      await establishConflict();

      final result = await sync.sync();

      expect(result.conflicts, 1);
      expect(readLocal('doc.txt'), 'local-edit-wins',
          reason: 'the local file must not be clobbered by the conflict copy');
      expect(server.contentAt('doc.txt'), 'remote-edit-differs',
          reason: 'the remote version must not be overwritten either');
      expect(await sync.conflictCount(), 1);

      final copies = Directory(root.path)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.contains('.conflict-'))
          .toList();
      expect(copies, hasLength(1),
          reason: 'the remote version is preserved as one conflict copy');
      expect(copies.single.readAsStringSync(), 'remote-edit-differs');
    });

    test('keep local uploads the local version and clears the conflict',
        () async {
      await establishConflict();
      await sync.sync();

      await sync.resolveConflictKeepLocal('doc.txt');

      expect(server.contentAt('doc.txt'), 'local-edit-wins');
      expect(await sync.conflictCount(), 0);
      expect(readLocal('doc.txt'), 'local-edit-wins');

      final settled = await sync.sync();
      expect(settled.conflicts, 0, reason: 'a resolved conflict must not recur');
    });

    test('keep remote restores the remote version and clears the conflict',
        () async {
      await establishConflict();
      await sync.sync();

      await sync.resolveConflictKeepRemote('doc.txt');

      expect(readLocal('doc.txt'), 'remote-edit-differs');
      expect(await sync.conflictCount(), 0);
    });

    test('keep both keeps the local file and leaves the remote untouched',
        () async {
      await establishConflict();
      await sync.sync();

      await sync.resolveConflictKeepBoth('doc.txt');

      expect(readLocal('doc.txt'), 'local-edit-wins');
      expect(server.contentAt('doc.txt'), 'local-edit-wins');
      expect(await sync.conflictCount(), 0);

      final copies = Directory(root.path)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.contains('.conflict-'))
          .toList();
      expect(copies, hasLength(1),
          reason: 'keep-both must physically preserve the second copy');
    });
  });

  group('failure and recovery', () {
    test('a failed upload is reported and is not recorded as synced', () async {
      await writeLocal('alpha.txt', 'alpha-good');
      await writeLocal('bravo.txt', 'bravo-rejected');
      server.rejectChunkFor = 'bravo.txt';
      server.rejectionsRemaining = 1;

      final result = await sync.sync();

      expect(result.errors, 1);
      expect(server.contentAt('alpha.txt'), 'alpha-good',
          reason: 'one file failing must not abandon the others');
      expect(server.has('bravo.txt'), isFalse,
          reason: 'files=${server.files.keys.toList()} '
              'folders=${server.folders.toList()} '
              'offsets=${server.chunkOffsets} chunks=${server.chunkCalls}');

      // The retry is automatic on the next run, and the missing baseline means
      // the file is treated as new rather than as already-synced.
      server.rejectChunkFor = null;
      final retry = await sync.sync();
      expect(retry.uploaded, 1);
      expect(retry.errors, 0);
      expect(server.contentAt('bravo.txt'), 'bravo-rejected');
    });

    test('a server error surfaces as a sync error rather than silent success',
        () async {
      await writeLocal('alpha.txt', 'alpha');
      final failing = MockClient((_) async => http.Response('boom', 500));
      final broken = SyncManager(Api(
        Session()
          ..serverUrl = 'https://example.com'
          ..token = 't',
        client: failing,
      ));
      await broken.setFolder(root.path);

      final result = await broken.sync();

      expect(result.errors, 1);
      expect(result.error, isNotNull);
      expect(result.uploaded, 0);
      expect(server.has('alpha.txt'), isFalse);
    });

    test('a request for a folder that no longer exists is reported, not thrown',
        () async {
      await sync.setFolder('${root.path}${Platform.pathSeparator}gone-forever');
      final result = await sync.sync();
      expect(result.errors, 1);
      expect(result.error, contains('no longer exists'));
    });

    test('no sync folder selected is reported, not thrown', () async {
      await sync.clearFolder();
      final result = await sync.sync();
      expect(result.errors, 1);
      expect(result.error, contains('Choose a local sync folder'));
    });

    test('an upload is assembled from contiguous chunks, not restarted',
        () async {
      final bytes = List<int>.generate(200, (i) => i % 251);
      final file = File('${root.path}${Platform.pathSeparator}video.bin');
      await file.writeAsBytes(bytes);

      final result = await sync.sync();
      expect(result.errors, 0);
      expect(server.files['video.bin'], bytes);

      // Every chunk is sent at the offset the server reported, so the file is
      // assembled exactly once with no gap and no duplicated region.
      expect(server.chunkOffsets, [0]);
      expect(server.files['video.bin']!.length, 200);
    });
  });

  group('concurrent and expired sessions', () {
    test('two concurrent first syncs collapse into a single run', () async {
      await writeLocal('alpha.txt', 'alpha');

      // This is the shape that used to register one machine twice: the shell's
      // startup sync and the Sync Center's manual sync overlapping on a fresh
      // install. They must produce one run, one device record, one upload.
      final results = await Future.wait([sync.sync(), sync.sync()]);

      expect(results, hasLength(2));
      expect(server.manifestCalls + server.deltaCalls, 1,
          reason: 'the second caller must join the run, not start a second one');
      expect(server.announcedDeviceIds.toSet(), hasLength(1));
      expect(server.contentAt('alpha.txt'), 'alpha');
    });

    test('an expired session is reported as a sync error, not thrown',
        () async {
      await writeLocal('alpha.txt', 'alpha');
      // A 401 must not silently look like "nothing to sync".
      final expired = MockClient(
          (_) async => http.Response('{"error":"invalid token"}', 401));
      final manager = SyncManager(Api(
        Session()
          ..serverUrl = 'https://example.com'
          ..token = 'stale-token',
        client: expired,
      ));
      await manager.setFolder(root.path);

      final result = await manager.sync();

      expect(result.errors, 1);
      expect(result.error, isNotNull);
      expect(result.uploaded, 0);
    });
  });

  group('device identity across syncs', () {
    test('the same device id is announced on every sync', () async {
      await writeLocal('alpha.txt', 'alpha');
      await sync.sync();
      await sync.sync();
      await sync.sync();

      expect(server.announcedDeviceIds, hasLength(3));
      expect(server.announcedDeviceIds.toSet(), hasLength(1),
          reason: 'three syncs from one machine must announce one identity');
      expect(server.announcedDeviceIds.first, isNotEmpty);
    });

    test('a device id owned by the account is reused, never regenerated',
        () async {
      await writeLocal('alpha.txt', 'alpha');
      await sync.sync();
      final chosen = server.announcedDeviceIds.first;

      // A brand-new manager instance, as after an app restart.
      final restarted = SyncManager(api);
      await restarted.setFolder(root.path);
      await restarted.sync();

      expect(server.announcedDeviceIds.last, chosen,
          reason: 'restarting the app must not register a second device');
    });
  });

  group('manual transfer queue is not polluted by sync', () {
    test('sync uploads do not accumulate rows in the transfer list', () async {
      await writeLocal('one.txt', 'first');
      await writeLocal('two.txt', 'second');

      await sync.sync();
      await writeLocal('three.txt', 'third');
      await sync.sync();

      // The Transfers screen reads this queue. Every sync used to leave one
      // permanent "completed" row behind, so the list grew without bound and
      // was re-parsed on every queue pass.
      final items = await TransferQueue(api).items();
      expect(items, isEmpty,
          reason: 'sync drives its own transfers and must clean up after them');
    });

    test('a failed sync upload also leaves no row behind', () async {
      await writeLocal('bravo.txt', 'bravo-rejected');
      server.rejectChunkFor = 'bravo.txt';
      server.rejectionsRemaining = 1;

      await sync.sync();

      expect(await TransferQueue(api).items(), isEmpty);
    });
  });
}
