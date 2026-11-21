import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'api.dart';
import 'download_service.dart';
import 'foreground_transfer_service.dart';

/// State of one durable download. Only queued work may be driven by a worker.
enum DurableDownloadState {
  queued,
  downloading,
  paused,
  failed,
  cancelled,
  completed;

  bool get isTerminal =>
      this == DurableDownloadState.completed ||
      this == DurableDownloadState.cancelled;
}

/// A download the app must finish even if the process dies mid-transfer.
///
/// The journal deliberately holds no token, header or credential: the session
/// is reloaded from the platform keystore by the caller before a worker starts.
class DurableDownloadItem {
  const DurableDownloadItem({
    required this.id,
    required this.remotePath,
    required this.targetPath,
    required this.received,
    this.total,
    required this.state,
    this.error,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String remotePath;
  final String targetPath;
  final int received;
  final int? total;
  final DurableDownloadState state;
  final String? error;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> encode() => <String, Object?>{
        'id': id,
        'remotePath': remotePath,
        'targetPath': targetPath,
        'received': received,
        'total': total,
        'state': state.name,
        'error': error,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  static DurableDownloadItem? decode(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'] as String?;
    final remotePath = raw['remotePath'] as String?;
    final targetPath = raw['targetPath'] as String?;
    final createdAt = DateTime.tryParse(raw['createdAt']?.toString() ?? '');
    final updatedAt = DateTime.tryParse(raw['updatedAt']?.toString() ?? '');
    if (id == null || remotePath == null || targetPath == null) return null;
    if (createdAt == null || updatedAt == null) return null;
    final state = DurableDownloadState.values
        .where((DurableDownloadState value) => value.name == raw['state'])
        .firstOrNull;
    if (state == null) return null;
    return DurableDownloadItem(
      id: id,
      remotePath: remotePath,
      targetPath: targetPath,
      received: (raw['received'] as num?)?.toInt() ?? 0,
      total: (raw['total'] as num?)?.toInt(),
      state: state,
      error: raw['error']?.toString(),
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  DurableDownloadItem copyWith({
    int? received,
    int? total,
    bool clearTotal = false,
    DurableDownloadState? state,
    String? error,
    bool clearError = false,
    DateTime? updatedAt,
  }) {
    return DurableDownloadItem(
      id: id,
      remotePath: remotePath,
      targetPath: targetPath,
      received: received ?? this.received,
      total: clearTotal ? null : (total ?? this.total),
      state: state ?? this.state,
      error: clearError ? null : (error ?? this.error),
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}

/// Append-only journal of durable downloads, following the upload store's
/// pattern: one line per state change, last line wins, corrupt lines are skipped.
class DurableDownloadStore {
  DurableDownloadStore(this.file);

  final File file;
  static const int compactAfterLines = 2000;

  Future<void> _lock = Future<void>.value();
  RandomAccessFile? _handle;
  int _lines = 0;
  final Map<String, DurableDownloadItem> _latest =
      <String, DurableDownloadItem>{};

  Future<List<DurableDownloadItem>> load() async {
    _latest.clear();
    if (!await file.exists()) return <DurableDownloadItem>[];
    List<String> lines;
    try {
      lines = await file.readAsLines();
    } catch (_) {
      return <DurableDownloadItem>[];
    }
    _lines = lines.length;
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is! Map) continue;
        final id = decoded['id'] as String?;
        if (id == null) continue;
        if (decoded['deleted'] == true) {
          _latest.remove(id);
          continue;
        }
        final item = DurableDownloadItem.decode(decoded['item']);
        if (item != null) _latest[id] = item;
      } catch (_) {
        // A truncated line must never cost the user the whole queue.
      }
    }
    return _latest.values.toList(growable: false);
  }

  Future<void> append(DurableDownloadItem item) {
    _latest[item.id] = item;
    return _write(jsonEncode(<String, Object?>{
      'id': item.id,
      'item': item.encode(),
    }));
  }

  Future<void> remove(String id) {
    _latest.remove(id);
    return _write(jsonEncode(<String, Object?>{'id': id, 'deleted': true}));
  }

  Future<void> clear() => _serialized(() async {
        _latest.clear();
        await _closeHandle();
        final temp = File('${file.path}.tmp');
        await temp.writeAsString('', flush: true);
        await temp.rename(file.path);
        _lines = 0;
      });

  Future<void> dispose() => _serialized(_closeHandle);

  Future<void> _write(String line) => _serialized(() async {
        final handle = await _openHandle();
        await handle.writeString('$line\n');
        _lines++;
        if (_lines > compactAfterLines) {
          await _compactLocked(_latest.values.toList(growable: false));
        }
      });

  Future<void> _compactLocked(List<DurableDownloadItem> snapshot) async {
    await _closeHandle();
    final buffer = StringBuffer();
    for (final item in snapshot) {
      buffer.writeln(jsonEncode(<String, Object?>{
        'id': item.id,
        'item': item.encode(),
      }));
    }
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(buffer.toString(), flush: true);
    await temp.rename(file.path);
    _lines = snapshot.length;
  }

  Future<void> _serialized(Future<void> Function() action) {
    final completer = Completer<void>();
    final previous = _lock;
    _lock = completer.future;
    previous.catchError((Object _) {}).whenComplete(() async {
      try {
        await action();
        completer.complete();
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  Future<RandomAccessFile> _openHandle() async {
    final existing = _handle;
    if (existing != null) return existing;
    final parent = file.parent;
    if (!await parent.exists()) await parent.create(recursive: true);
    final handle = await file.open(mode: FileMode.append);
    _handle = handle;
    return handle;
  }

  Future<void> _closeHandle() async {
    final handle = _handle;
    _handle = null;
    try {
      await handle?.close();
    } catch (_) {}
  }
}

/// Internal signal for a pause observed by an active worker. The caller waiting
/// on the transfer is released, but the journal row stays paused.
class _DownloadPaused implements Exception {
  const _DownloadPaused();
}

/// Drives durable downloads in this process and from WorkManager.
///
/// The foreground app and the worker never run the same queue at once: an
/// owner lock with a heartbeat is refreshed while work is pending, and the
/// background worker bails out when a live owner is present.
class DurableDownloadManager {
  DurableDownloadManager._({
    required this.store,
    Api? api,
    ForegroundTransferService? transfers,
    this.scheduleResume,
  })  : _api = api,
        _transfers = transfers ?? ForegroundTransferService.instance;

  static DurableDownloadManager? _instance;

  /// The process-wide manager. Journals live beside the upload journal so a
  /// process death cannot lose an in-flight file.
  static DurableDownloadManager get instance {
    final existing = _instance;
    if (existing != null) return existing;
    final created = DurableDownloadManager._(
      store: DurableDownloadStore(File(_journalPathFallback())),
      scheduleResume: null,
    );
    _instance = created;
    unawaited(created._bootstrap());
    return created;
  }

  /// A worker's manager. The API client is attached by the dispatcher after
  /// the session has been reloaded from the keystore.
  static DurableDownloadManager background() => instance;

  /// Injects the WorkManager one-off scheduler. Registered by
  /// [BackgroundTransferService.initialize] so downloads can be scheduled
  /// without a circular dependency between the two services.
  static Future<void> Function()? _resumeScheduler;

  static void registerResumeScheduler(Future<void> Function() scheduler) {
    _resumeScheduler = scheduler;
  }

  /// Test seam with an injected journal, API client, ledger and scheduler.
  @visibleForTesting
  DurableDownloadManager.forTesting({
    required File journal,
    Api? api,
    ForegroundTransferService? transfers,
    this.scheduleResume,
  })  : store = DurableDownloadStore(journal),
        _api = api,
        _transfers = transfers ?? ForegroundTransferService.instance {
    _instance = this;
    unawaited(_bootstrapForTesting());
  }

  DurableDownloadStore store;
  final ForegroundTransferService _transfers;

  /// Explicit scheduler (tests) or null to use the registered WorkManager hook.
  final Future<void> Function()? scheduleResume;

  Api? _api;

  final Map<String, DurableDownloadItem> _items =
      <String, DurableDownloadItem>{};
  final Map<String, CancelToken> _cancelTokens = <String, CancelToken>{};
  final Map<String, void Function(int received, int? total)>
      _progressCallbacks = <String, void Function(int, int?)>{};
  final Map<String, Duration> _timeouts = <String, Duration>{};
  final Set<String> _cancelledIds = <String>{};
  final Map<String, DateTime> _lastPersisted = <String, DateTime>{};
  final Map<String, Completer<void>> _waiters = <String, Completer<void>>{};
  final Map<String, Object?> _terminal = <String, Object?>{};

  final Completer<void> _readyCompleter = Completer<void>();

  Future<void> get ready => _readyCompleter.future;

  /// WorkManager one-off task that resumes the durable download journal after
  /// the app process was killed mid-transfer.
  static const String resumeTaskName = 'nexadrive.resumeDownloads';

  static const Duration progressInterval = Duration(milliseconds: 250);
  static const Duration ownerHeartbeat = Duration(seconds: 30);
  static const Duration ownerLockTtl = Duration(seconds: 90);

  Timer? _ownerTimer;
  File? _ownerFile;

  /// The owner lock exists only to keep WorkManager from racing the foreground
  /// process. With no scheduler registered (unit tests, plain Dart clients)
  /// there is no second worker, so the lock must never block local work.
  bool get _workerEnabled => scheduleResume != null || _resumeScheduler != null;

  /// Queued or interrupted downloads. Paused rows are excluded so WorkManager
  /// does not spin on work the user intentionally held back.
  int get pendingCount => _items.values
      .where(
        (DurableDownloadItem item) =>
            item.state == DurableDownloadState.queued ||
            item.state == DurableDownloadState.downloading,
      )
      .length;

  /// Binds the queue to an API client. A new login reloads the journal because
  /// the previous session's credentials no longer apply.
  void attach(Api api) {
    if (identical(_api, api)) return;
    _api = api;
    unawaited(_reload());
  }

  Future<void> _bootstrap() async {
    try {
      final file = await journalFile();
      if (file.path != store.file.path) {
        await store.dispose();
        store = DurableDownloadStore(file);
      }
    } catch (_) {
      // Keep the fallback journal.
    }
    await _reload();
    if (pendingCount > 0) unawaited(_enqueueDrive());
  }

  Future<void> _bootstrapForTesting() async {
    await _reload();
  }

  Future<File> get ownerFile async {
    final file = File('${store.file.path}.owner');
    _ownerFile = file;
    return file;
  }

  static Future<File> journalFile() async {
    try {
      final directory = await getApplicationSupportDirectory();
      final folder =
          Directory('${directory.path}${Platform.pathSeparator}downloads');
      if (!await folder.exists()) await folder.create(recursive: true);
      return File('${folder.path}${Platform.pathSeparator}queue.jsonl');
    } catch (_) {
      return File(_journalPathFallback());
    }
  }

  static String _journalPathFallback() {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    return '$home${Platform.pathSeparator}.nexadrive_download_queue.jsonl';
  }

  Future<void> _reload() {
    final next = _reloadChain.then((_) => _loadFromJournal());
    _reloadChain = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<void> _reloadChain = Future<void>.value();

  Future<void> _loadFromJournal() async {
    final loaded = await store.load();
    _items.clear();
    for (final item in loaded) {
      if (item.state.isTerminal) {
        await store.remove(item.id);
        continue;
      }
      var current = item;
      if (current.state == DurableDownloadState.downloading) {
        // No worker from the dead process is left; the `.part` file holds the
        // authoritative byte count and the server confirms the Range offset.
        current = current.copyWith(state: DurableDownloadState.queued);
        await _persist(current);
      }
      _items[current.id] = current;
    }
    if (!_readyCompleter.isCompleted) _readyCompleter.complete();
  }

  /// Queues a download, then drives it in this process. The journal entry and
  /// WorkManager task are written before any byte is requested.
  Future<String> enqueue({
    required String remotePath,
    required String targetPath,
    int? total,
    Duration timeout = const Duration(minutes: 30),
    void Function(int received, int? total)? onProgress,
    CancelToken? cancel,
    String? id,
  }) async {
    await ready;
    if (_api == null) throw StateError('The download queue has no API client');
    final now = DateTime.now();
    final item = DurableDownloadItem(
      id: id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      remotePath: remotePath,
      targetPath: targetPath,
      received: 0,
      total: total,
      state: DurableDownloadState.queued,
      createdAt: now,
      updatedAt: now,
    );
    _items[item.id] = item;
    _timeouts[item.id] = timeout;
    if (cancel != null) _cancelTokens[item.id] = cancel;
    if (onProgress != null) _progressCallbacks[item.id] = onProgress;
    await _persist(item);
    unawaited(_scheduleResumeSafely());
    unawaited(_enqueueDrive());
    return item.id;
  }

  /// Waits until a queued transfer reaches a terminal state.
  ///
  /// Errors are replayed with their original user-visible type; a paused
  /// transfer simply releases the waiter without claiming success.
  Future<void> waitFor(String id) async {
    await ready;
    if (_terminal.containsKey(id)) {
      final error = _terminal[id];
      if (error == null || error is _DownloadPaused) return;
      throw error;
    }
    final waiter = _waiters.putIfAbsent(id, Completer<void>.new);
    return waiter.future;
  }

  /// Holds a transfer without deleting its confirmed `.part` bytes.
  Future<void> pause(String id) async {
    final item = _items[id];
    if (item == null || item.state.isTerminal) return;
    final paused = item.copyWith(state: DurableDownloadState.paused);
    _items[id] = paused;
    await _persist(paused);
  }

  /// Releases a paused transfer. The Range request resumes from the `.part`.
  Future<void> resume(String id) async {
    final item = _items[id];
    if (item == null || item.state != DurableDownloadState.paused) return;
    final queued = item.copyWith(state: DurableDownloadState.queued);
    _items[id] = queued;
    await _persist(queued);
    unawaited(_scheduleResumeSafely());
    unawaited(_enqueueDrive());
  }

  /// Cancels a transfer and removes its partial file. The ledger lease is
  /// released by the worker's `finally` even if no chunk is in flight.
  Future<void> cancel(String id) async {
    _cancelledIds.add(id);
    final item = _items[id];
    if (item == null) {
      _finish(id, const SaveCancelled());
      return;
    }
    final cancelled = item.copyWith(state: DurableDownloadState.cancelled);
    _items[id] = cancelled;
    await _persist(cancelled);
    await _deletePart(item);
    if (!_active.contains(id)) {
      _items.remove(id);
      await store.remove(id);
      _finish(id, const SaveCancelled());
    }
  }

  /// Allows a failed transfer to retry from its `.part` file.
  Future<void> retry(String id) async {
    final item = _items[id];
    if (item == null ||
        (item.state != DurableDownloadState.failed &&
            item.state != DurableDownloadState.cancelled)) {
      return;
    }
    final queued =
        item.copyWith(state: DurableDownloadState.queued, clearError: true);
    _items[id] = queued;
    await _persist(queued);
    unawaited(_scheduleResumeSafely());
    unawaited(_enqueueDrive());
  }

  /// Drops every durable download (used on logout/session expiry). Partial
  /// files are deleted; any active worker releases its lease in `finally`.
  Future<void> discardAll() async {
    await ready;
    final ids = _items.keys.toList(growable: false);
    for (final item in _items.values.toList(growable: false)) {
      _cancelledIds.add(item.id);
      await _deletePart(item);
    }
    _items.clear();
    _cancelTokens.clear();
    _progressCallbacks.clear();
    _timeouts.clear();
    await store.clear();
    for (final id in ids) {
      _finish(id, const SaveCancelled());
    }
    _releaseOwner();
  }

  /// Background entry point. Drives queued rows and reports whether any are
  /// left so WorkManager can retry instead of reporting success too early.
  Future<int> resumePending() async {
    await ready;
    await _enqueueDrive();
    return pendingCount;
  }

  /// True when on-disk work still needs a worker, used at app startup.
  Future<bool> hasPendingOnDisk() async {
    await ready;
    return pendingCount > 0;
  }

  /// Whether a live foreground/main isolate owns the queue right now.
  Future<bool> isForegroundOwnerAlive() async {
    try {
      final file = await ownerFile;
      if (!await file.exists()) return false;
      final lines = await file.readAsLines();
      if (lines.length < 2) return false;
      final stamp = DateTime.tryParse(lines.first.trim());
      final ownerPid = int.tryParse(lines[1].trim());
      if (stamp == null || ownerPid == null) return false;
      if (DateTime.now().difference(stamp) >= ownerLockTtl) return false;
      if (ownerPid == pid) return true;
      // A killed process leaves a fresh-looking lock behind. On Android the
      // kernel exposes liveness directly, so the worker need not wait for TTL.
      if (Platform.isAndroid && !File('/proc/$ownerPid').existsSync()) {
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _claimOwner() async {
    final file = await ownerFile;
    _ownerFile = file;
    await file.writeAsString(
      '${DateTime.now().toIso8601String()}\n$pid\n',
      flush: true,
    );
    _ownerTimer ??= Timer.periodic(ownerHeartbeat, (_) {
      unawaited(file.writeAsString(
        '${DateTime.now().toIso8601String()}\n$pid\n',
        flush: true,
      ));
    });
  }

  void _releaseOwner() {
    _ownerTimer?.cancel();
    _ownerTimer = null;
    final file = _ownerFile;
    _ownerFile = null;
    try {
      if (file != null && file.existsSync()) file.deleteSync();
    } catch (_) {
      // A stale lock expires on its own.
    }
  }

  Future<void> _scheduleResumeSafely() async {
    final scheduler = scheduleResume ?? _resumeScheduler;
    if (scheduler == null) return;
    try {
      await scheduler();
    } catch (error) {
      debugPrint('NexaDrive download resume scheduling failed: $error');
    }
  }

  Future<void> _enqueueDrive() {
    final next = _driveChain.then((_) => drive());
    _driveChain = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<void> _driveChain = Future<void>.value();
  final Set<String> _active = <String>{};

  Future<void> drive() async {
    await ready;
    if (_workerEnabled && await isForegroundOwnerAlive()) return;
    if (_workerEnabled) await _claimOwner();
    while (true) {
      final next = _items.values
          .where((DurableDownloadItem item) =>
              item.state == DurableDownloadState.queued)
          .firstOrNull;
      if (next == null) break;
      await _run(next);
    }
    if (_workerEnabled && pendingCount == 0) _releaseOwner();
  }

  Future<void> _run(DurableDownloadItem queued) async {
    final api = _api;
    if (api == null) return;
    final current = _items[queued.id];
    if (current == null || current.state != DurableDownloadState.queued) return;

    final lease = _transfers.acquireDownload();
    _active.add(queued.id);
    var item = current;
    final cancel = _cancelTokens[queued.id];
    final onProgress = _progressCallbacks[queued.id];
    final timeout = _timeouts[queued.id] ?? const Duration(minutes: 30);
    final part = File(_partPath(item));
    final target = File(item.targetPath);
    StreamSubscription<List<int>>? subscription;
    IOSink? sink;
    var sinkClosed = false;

    try {
      // The `.part` file, not the journal hint, is the authoritative offset.
      var start = await part.exists() ? await part.length() : 0;
      if (item.total != null && start > item.total!) start = 0;
      if (start != item.received ||
          item.state != DurableDownloadState.downloading) {
        item = item.copyWith(
          received: start,
          state: DurableDownloadState.downloading,
        );
        _items[item.id] = item;
        await _persist(item);
      }

      http.StreamedResponse response = await _send(api, item, start, timeout);
      var total = item.total;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await response.stream.bytesToString();
        throw SaveException(Api.messageFromBody(body, response.statusCode));
      }
      if (start > 0 &&
          (response.statusCode != 206 ||
              _rangeStart(response.headers['content-range']) != start)) {
        // The server ignored the Range, sent a different offset (the file may
        // have changed) or omitted Content-Range. Restart from zero instead of
        // appending bytes to the wrong position or faking progress.
        await response.stream.drain<void>().catchError((Object _) {});
        await _deletePart(item);
        start = 0;
        item = item.copyWith(received: 0, clearTotal: true);
        _items[item.id] = item;
        await _persist(item);
        response = await _send(api, item, 0, timeout);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          final body = await response.stream.bytesToString();
          throw SaveException(Api.messageFromBody(body, response.statusCode));
        }
        total = null;
      }
      final contentLength = response.contentLength;
      if (response.statusCode == 206) {
        total = _rangeTotal(response.headers['content-range'], start) ??
            (contentLength == null ? null : start + contentLength);
      } else {
        total = contentLength;
      }
      final expectedTotal = total;
      if (expectedTotal != null && start > expectedTotal) {
        throw const SaveException(
            'The server returned an invalid download range.');
      }

      sink = part.openWrite(mode: start > 0 ? FileMode.append : FileMode.write);
      var received = start;
      final completer = Completer<void>();
      subscription = response.stream.listen(
        (List<int> chunk) {
          final live = _items[item.id];
          if (_cancelledIds.contains(item.id) ||
              cancel?.isCancelled == true ||
              live?.state == DurableDownloadState.cancelled) {
            subscription?.cancel();
            if (!completer.isCompleted) {
              completer.completeError(const SaveCancelled());
            }
            return;
          }
          if (live?.state == DurableDownloadState.paused) {
            subscription?.cancel();
            if (!completer.isCompleted) {
              completer.completeError(const _DownloadPaused());
            }
            return;
          }
          received += chunk.length;
          sink?.add(chunk);
          onProgress?.call(received, total);
          unawaited(_persistProgress(item.id, received, total));
        },
        onError: (Object error) {
          if (!completer.isCompleted) {
            completer.completeError(
              error is SaveException
                  ? error
                  : SaveException(_friendlyNetworkError(error)),
            );
          }
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );
      await completer.future.timeout(timeout);
      await sink.flush();
      await sink.close();
      sinkClosed = true;

      final actual = await part.length();
      if (actual != received ||
          (expectedTotal != null && received != expectedTotal)) {
        throw const SaveException(
          'The download ended early. It will resume from the last confirmed byte.',
        );
      }
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
      final done = (_items[item.id] ?? item).copyWith(
        state: DurableDownloadState.completed,
        received: received,
        total: total,
        clearError: true,
      );
      _items[item.id] = done;
      await store.remove(item.id);
      _finish(item.id, null);
    } catch (error) {
      final live = _items[item.id];
      if (error is SaveCancelled ||
          live?.state == DurableDownloadState.cancelled ||
          _cancelledIds.contains(item.id)) {
        _cancelledIds.remove(item.id);
        await _deletePart(item);
        _items.remove(item.id);
        await store.remove(item.id);
        _finish(item.id, const SaveCancelled());
      } else if (error is _DownloadPaused) {
        _finish(item.id, error);
      } else {
        final message = error is SaveException
            ? error.message
            : _friendlyNetworkError(error);
        final failed = (live ?? item).copyWith(
          state: DurableDownloadState.failed,
          error: message,
        );
        _items[item.id] = failed;
        await _persist(failed);
        _finish(item.id, SaveException(message));
      }
    } finally {
      if (!sinkClosed) {
        try {
          await sink?.close();
        } catch (_) {}
      }
      await subscription?.cancel();
      _active.remove(queued.id);
      _cancelTokens.remove(queued.id);
      _progressCallbacks.remove(queued.id);
      _timeouts.remove(queued.id);
      lease.release();
    }
  }

  Future<http.StreamedResponse> _send(
    Api api,
    DurableDownloadItem item,
    int start,
    Duration timeout,
  ) async {
    final request = http.Request('GET', api.fileDownloadUri(item.remotePath));
    request.headers.addAll(api.authHeaders);
    if (start > 0) request.headers['Range'] = 'bytes=$start-';
    return api.rawClient.send(request).timeout(
          timeout,
          onTimeout: () => throw const SaveException(
            'The server took too long to respond. Check the connection and try again.',
          ),
        );
  }

  int? _rangeStart(String? contentRange) {
    final match = _rangeMatch(contentRange);
    return match == null ? null : int.tryParse(match.group(1) ?? '');
  }

  int? _rangeTotal(String? contentRange, int start) {
    final match = _rangeMatch(contentRange);
    if (match == null) return null;
    if (int.tryParse(match.group(1) ?? '') != start) return null;
    return int.tryParse(match.group(3) ?? '');
  }

  RegExpMatch? _rangeMatch(String? contentRange) {
    if (contentRange == null) return null;
    // Servers send `bytes 3-5/6` for an open-ended request; an empty end is
    // tolerated as well.
    return RegExp(r'^bytes\s+(\d+)-(\d*)/(\d+)$')
        .firstMatch(contentRange.trim());
  }

  Future<void> _persistProgress(String id, int received, int? total) async {
    final item = _items[id];
    if (item == null || item.state != DurableDownloadState.downloading) return;
    final updated = item.copyWith(received: received, total: total);
    _items[id] = updated;
    final last = _lastPersisted[id];
    final now = DateTime.now();
    if (last != null && now.difference(last) < progressInterval) return;
    _lastPersisted[id] = now;
    await _persist(updated);
  }

  Future<void> _persist(DurableDownloadItem item) async {
    try {
      await store.append(item);
      _lastPersisted[item.id] = DateTime.now();
    } catch (error) {
      // A journal write must never abort a transfer that is already running.
      debugPrint('NexaDrive download journal write failed: $error');
    }
  }

  void _finish(String id, Object? error) {
    final waiter = _waiters.remove(id);
    if (error == null || error is _DownloadPaused) {
      waiter?.complete();
    } else {
      waiter?.completeError(error);
    }
    _terminal[id] = error;
    Timer(const Duration(minutes: 1), () => _terminal.remove(id));
  }

  String _partPath(DurableDownloadItem item) {
    final file = File(item.targetPath);
    final name = _baseName(item.targetPath);
    return '${file.parent.path}${Platform.pathSeparator}.$name.nexadrive-${item.id}.part';
  }

  Future<void> _deletePart(DurableDownloadItem item) async {
    try {
      final part = File(_partPath(item));
      if (await part.exists()) await part.delete();
    } catch (_) {}
  }

  String _baseName(String path) {
    final clean = path.replaceAll('\\', '/');
    final i = clean.lastIndexOf('/');
    return i < 0 ? clean : clean.substring(i + 1);
  }

  String _friendlyNetworkError(Object error) {
    if (error is SocketException) {
      return 'The connection dropped while downloading. Check the network and try again.';
    }
    if (error is TimeoutException) {
      return 'The download stalled and was stopped. Try again.';
    }
    return 'The download failed: $error';
  }
}
