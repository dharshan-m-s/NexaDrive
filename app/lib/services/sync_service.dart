import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'api.dart';
import 'transfer_queue.dart';

class SyncResult {
  final int uploaded;
  final int downloaded;
  final int deleted;
  final int conflicts;
  final int errors;
  final String? error;
  const SyncResult({this.uploaded = 0, this.downloaded = 0, this.deleted = 0, this.conflicts = 0, this.errors = 0, this.error});
}

class SyncManager {
  static const _folderKey = 'sync_folder_v1';
  static const _deviceKey = 'sync_device_id_v1';
  static const _deviceNameKey = 'sync_device_name_v1';
  static const _stateKey = 'sync_state_v1';
  final Api api;
  SyncManager(this.api);

  Future<String?> folder() async => (await SharedPreferences.getInstance()).getString(_folderKey);

  Future<void> setFolder(String path) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_folderKey, path);
  }

  Future<void> clearFolder() async => (await SharedPreferences.getInstance()).remove(_folderKey);

  /// Memoised in-flight resolution, so concurrent callers cannot each generate
  /// their own id. Reading `getString` and then writing is only safe because
  /// everyone shares this one future.
  static Future<String>? _deviceIdInFlight;

  /// This machine's stable sync identity, generated locally on first use.
  ///
  /// Generated and persisted *before* any request is made, so two syncs that
  /// start together on a fresh install both send the same id. Previously the id
  /// only came into existence from the server's reply, so a concurrent
  /// first-run pair both sent `device_id: null` and the server registered this
  /// machine twice — which is why the Sync Center listed repeated, identical
  /// "NexaDrive desktop" entries with no way to tell them apart.
  static Future<String> ensureDeviceId() {
    final running = _deviceIdInFlight;
    if (running != null) return running;
    final started = _loadOrCreateDeviceId();
    _deviceIdInFlight = started;
    return started;
  }

  static Future<String> _loadOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final created = const Uuid().v4();
    await prefs.setString(_deviceKey, created);
    return created;
  }

  /// Records the id the server confirmed and re-points the memo at it, so every
  /// later reader agrees with what is on disk.
  static Future<void> _adoptDeviceId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deviceKey, id);
    _deviceIdInFlight = Future<String>.value(id);
  }

  /// Drops the memo so a test can observe first-run behaviour again.
  @visibleForTesting
  static void resetDeviceIdCache() => _deviceIdInFlight = null;

  /// The id the Sync Center uses to mark "this device".
  ///
  /// Delegates to [ensureDeviceId] so reading it is also what makes it stable.
  Future<String> deviceId() => ensureDeviceId();

  Future<String> deviceDisplayName() => _deviceName();

  /// Renames this machine; the next sync pushes the new name to the server
  /// along with the device id, so the change is visible on every device.
  Future<void> setDeviceName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final bounded = String.fromCharCodes(trimmed.runes.take(64));
    await prefs.setString(_deviceNameKey, bounded);
  }

  /// When the last sync finished on this device, or null if never.
  Future<DateTime?> lastSyncAt() async {
    final state = await _state();
    return DateTime.tryParse(
      state['__meta__']?['lastSyncAt']?.toString() ?? '',
    )?.toLocal();
  }

  /// The platform string the server stores for this device.
  static String platformName() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    return 'unknown';
  }

  Future<Map<String, Map<String, dynamic>>> _state() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_stateKey);
    if (raw == null) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)));
  }

  Future<void> _saveState(Map<String, Map<String, dynamic>> state) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_stateKey, jsonEncode(state));
  }


  Future<String> _deviceName() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceNameKey);
    if (existing != null && existing.trim().isNotEmpty) return existing;
    var name = 'NexaDrive desktop';
    try {
      name = Platform.localHostname.trim().isEmpty ? name : Platform.localHostname.trim();
    } catch (_) {}
    await prefs.setString(_deviceNameKey, name);
    return name;
  }

  Future<Map<String, Map<String, dynamic>>> _scanLocal(Directory root, Map<String, Map<String, dynamic>> state) async {
    final result = <String, Map<String, dynamic>>{};
    final pending = <Directory>[root];
    while (pending.isNotEmpty) {
      final dir = pending.removeLast();
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is Link) continue;
        final rel = _relative(root.path, entity.path);
        if (entity is Directory) {
          result[rel] = {'kind': 'folder', 'size': 0, 'sha256': null};
          pending.add(entity);
        } else if (entity is File) {
          final stat = await entity.stat();
          final base = state[rel];
          final modifiedMs = stat.modified.millisecondsSinceEpoch;
          final cachedHash = base?['localHash']?.toString();
          final cachedSize = (base?['localSize'] as num?)?.toInt();
          final cachedModifiedMs = (base?['localModifiedMs'] as num?)?.toInt();
          final hash = cachedHash != null && cachedSize == stat.size && cachedModifiedMs == modifiedMs
              ? cachedHash
              : await _sha256(entity);
          result[rel] = {'kind': 'file', 'size': stat.size, 'sha256': hash, 'modifiedMs': modifiedMs};
        }
      }
    }
    return result;
  }

  String _relative(String root, String value) {
    var out = value.substring(root.length);
    if (out.startsWith(Platform.pathSeparator)) out = out.substring(1);
    return out.replaceAll('\\', '/');
  }

  String _localPath(String root, String rel) => [root, ...rel.split('/')].join(Platform.pathSeparator);

  Future<String> _sha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  Future<void> _ensureParent(String path) async => Directory(File(path).parent.path).create(recursive: true);

  Future<void> _download(String remotePath, String target) async {
    await _ensureParent(target);
    final temp = '$target.nexadrive-sync-${DateTime.now().microsecondsSinceEpoch}.tmp';
    try {
      await api.downloadToFile(remotePath, temp);
      final file = File(temp);
      final destination = File(target);
      if (await destination.exists()) await destination.delete();
      await file.rename(target);
    } finally {
      try { await File(temp).delete(); } catch (_) {}
    }
  }

  /// Chunk size for sync-driven uploads, matching [TransferQueue.chunkSize] so
  /// a file already partially staged by a manual transfer resumes on the same
  /// boundaries.
  static const _chunkSize = 8 * 1024 * 1024;

  /// Total attempts per file (1 try + 3 retries) before the sync reports it.
  static const _maxUploadAttempts = 4;

  /// Streams [localPath] to [remotePath], resuming from the offset the server
  /// reports and retrying transient failures with backoff.
  ///
  /// Deliberately does *not* go through [TransferQueue]. That queue is the
  /// user's manual transfer list, and driving it from the sync had three
  /// consequences: every synced file left a permanent "completed" row behind
  /// (so the Transfers list grew without bound and was re-parsed on every
  /// queue pass); `process()` operates on the whole queue, so a *failed* sync
  /// upload was silently retried as a side effect of the next file's upload,
  /// making a reported failure succeed behind the engine's back; and a
  /// background sync could re-drive transfers the user had queued themselves.
  Future<void> _uploadFile(String localPath, String remotePath) async {
    final file = File(localPath);
    final parts = remotePath.split('/');
    final name = parts.removeLast();
    final folder = parts.join('/');
    final size = await file.length();
    final uploadId = const Uuid().v4();

    for (var attempt = 1;; attempt++) {
      try {
        final remote = await api.uploadStatus(uploadId);
        // A freshly minted id is only ever 'completed' if one of our own
        // earlier attempts finished and the response was lost.
        if (remote['status'] == 'completed') return;
        var offset = (remote['bytes_received'] as num?)?.toInt() ?? 0;
        if (offset < 0 || offset > size) offset = 0;

        if (size == 0) {
          await api.uploadChunk(
            uploadId: uploadId,
            folder: folder,
            name: name,
            offset: 0,
            total: 0,
            bytes: const Stream<List<int>>.empty(),
            contentLength: 0,
          );
          return;
        }

        while (offset < size) {
          final end = offset + _chunkSize > size ? size : offset + _chunkSize;
          final result = await api.uploadChunk(
            uploadId: uploadId,
            folder: folder,
            name: name,
            offset: offset,
            total: size,
            // Streamed from disk, so a multi-gigabyte file never needs to be
            // resident in memory.
            bytes: file.openRead(offset, end),
            contentLength: end - offset,
          );
          offset = (result['offset'] as num?)?.toInt() ?? end;
        }
        return;
      } catch (e) {
        if (!TransferQueue.isTransient(e) || attempt >= _maxUploadAttempts) {
          rethrow;
        }
        await Future<void>.delayed(Duration(seconds: 2 * attempt));
      }
    }
  }

  /// Only one sync may run at a time, process-wide.
  ///
  /// `sync()` is reached from the shell's startup path and from the Sync Center
  /// on demand, and each call site constructs its own [SyncManager], so an
  /// instance field would not be enough. A second caller joins the run already
  /// in flight (and therefore uses the first caller's `onProgress`) rather than
  /// starting a competing one.
  static Future<SyncResult>? _inFlight;

  /// Runs a sync, or joins the one already running.
  Future<SyncResult> sync({void Function(String)? onProgress}) {
    final running = _inFlight;
    if (running != null) return running;
    final started = _runSync(onProgress: onProgress);
    _inFlight = started;
    // Clear the guard on completion either way; swallow nothing, since
    // `_runSync` reports failures through `SyncResult` instead of throwing.
    unawaited(started.whenComplete(() {
      _inFlight = null;
    }));
    return started;
  }

  Future<SyncResult> _runSync({void Function(String)? onProgress}) async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      return const SyncResult(errors: 1, error: 'Desktop folder sync is available on Windows, Linux and macOS. Android photo backup remains a separate workflow.');
    }
    final folderPath = await folder();
    if (folderPath == null || folderPath.isEmpty) return const SyncResult(errors: 1, error: 'Choose a local sync folder first.');
    final root = Directory(folderPath);
    if (!await root.exists()) return const SyncResult(errors: 1, error: 'The selected sync folder no longer exists.');

    try {
      onProgress?.call('Reading the local sync folder…');
      final state = await _state();
      final local = await _scanLocal(root, state);
      // Stable before the request, not after the reply — see [ensureDeviceId].
      final existingDeviceId = await ensureDeviceId();
      final previousServerCursor = state['__meta__']?['lastServerSyncAt']?.toString();
      final deviceName = await _deviceName();
      final response = previousServerCursor == null
          ? await api.syncManifest(
              deviceId: existingDeviceId,
              deviceName: deviceName,
              platform: platformName(),
            )
          : await api.syncDelta(
              since: previousServerCursor,
              deviceId: existingDeviceId,
              deviceName: deviceName,
              platform: platformName(),
            );
      // The server echoes the id we sent (or mints one if we somehow had none);
      // adopt its answer so both sides agree on this machine's identity.
      final confirmedId = response['device_id']?.toString();
      if (confirmedId != null && confirmedId.isNotEmpty) {
        await _adoptDeviceId(confirmedId);
      }

      final remote = <String, Map<String, dynamic>>{};
      final isDelta = previousServerCursor != null;
      if (isDelta) {
        // Reconstruct the last-known remote view from the durable sync baseline.
        for (final entry in state.entries) {
          if (entry.key == '__meta__' || entry.value['remoteExists'] != true) continue;
          remote[entry.key] = {
            'path': entry.key,
            'kind': entry.value['kind'] ?? 'file',
            'size': entry.value['remoteSize'] ?? 0,
            'sha256': entry.value['remoteHash'],
            'modified_at': entry.value['remoteModifiedAt'],
          };
        }
      }
      final tombstones = Set<String>.from(((response['tombstones'] as List?) ?? const []).map((e) => e.toString()));
      for (final tombstone in tombstones.toList()) {
        remote.removeWhere((path, _) => path == tombstone || path.startsWith('$tombstone/'));
      }
      for (final e in (response['entries'] as List)) {
        final m = Map<String, dynamic>.from(e as Map);
        remote[m['path'] as String] = m;
      }
      var uploaded = 0, downloaded = 0, deleted = 0, conflicts = 0, errors = 0;
      final paths = <String>{...local.keys, ...remote.keys, ...state.keys};

      // Folders first. Deletion is propagated only when the folder was previously synced.
      final folders = paths.where((p) => (local[p]?['kind'] ?? remote[p]?['kind'] ?? state[p]?['kind']) == 'folder').toList()
        ..sort((a,b) => a.length.compareTo(b.length));
      for (final path in folders) {
        final l = local[path];
        final r = remote[path];
        final base = state[path];
        try {
          if (l != null && r == null) {
            final localChanged = base == null || base['localExists'] != true;
            final remoteWasSynced = base != null && base['remoteExists'] == true;
            if (remoteWasSynced && !tombstones.contains(path) && localChanged) {
              await api.createFolder(path);
              uploaded++;
            } else if (remoteWasSynced && !localChanged && tombstones.contains(path)) {
              await Directory(_localPath(root.path, path)).delete(recursive: true);
              deleted++;
              state.remove(path);
            } else if (remoteWasSynced && !localChanged) {
              await api.syncDelete(path);
              deleted++;
              state.remove(path);
            } else {
              await api.createFolder(path);
              uploaded++;
            }
          } else if (r != null && l == null) {
            final remoteChanged = base == null || base['remoteExists'] != true;
            final localWasSynced = base != null && base['localExists'] == true;
            if (localWasSynced && !remoteChanged) {
              await api.syncDelete(path);
              deleted++;
              state.remove(path);
            } else {
              await Directory(_localPath(root.path, path)).create(recursive: true);
              downloaded++;
            }
          }
          if (local.containsKey(path) || remote.containsKey(path)) {
            state[path] = {'kind':'folder','localExists': local.containsKey(path),'remoteExists': remote.containsKey(path)};
          }
        } catch (e) {
          if (!e.toString().contains('already exists')) errors++;
        }
      }

      for (final path in paths.where((p) => (local[p]?['kind'] ?? remote[p]?['kind'] ?? state[p]?['kind']) == 'file')) {
        final l = local[path];
        final r = remote[path];
        final base = state[path];
        final localHash = l?['sha256']?.toString();
        final remoteHash = r?['sha256']?.toString();
        final baseLocal = base?['localHash']?.toString();
        final baseRemote = base?['remoteHash']?.toString();

        try {
          if (l == null && r == null) {
            state.remove(path);
            continue;
          }
          if (l == null && r != null) {
            final remoteChanged = baseRemote == null || remoteHash != baseRemote;
            final localWasSynced = baseLocal != null;
            if (localWasSynced && !remoteChanged && tombstones.contains(path)) {
              // Remote deletion is already recorded; remove the unchanged local copy.
              try { await File(_localPath(root.path, path)).delete(); } catch (_) {}
              deleted++;
              state.remove(path);
            } else if (localWasSynced && !remoteChanged) {
              await api.syncDelete(path);
              deleted++;
              state.remove(path);
            } else {
              onProgress?.call('Downloading $path');
              await _download(path, _localPath(root.path, path));
              downloaded++;
              state[path] = {'kind':'file','localHash':remoteHash,'remoteHash':remoteHash,'localSize':r['size'] ?? 0,'remoteSize':r['size'] ?? 0,'localModifiedMs':DateTime.tryParse(r['modified_at']?.toString() ?? '')?.millisecondsSinceEpoch,'remoteModifiedAt':r['modified_at'],'localExists':true,'remoteExists':true};
            }
            continue;
          }
          if (l != null && r == null) {
            final localChanged = baseLocal == null || localHash != baseLocal;
            final remoteWasSynced = baseRemote != null;
            if (remoteWasSynced && !localChanged && tombstones.contains(path)) {
              // Another device deleted this file and the server confirmed it
              // with a tombstone, so the unchanged local copy is stale: remove
              // it. Leaving it in place dropped our baseline without deleting
              // anything, and the next sync then re-uploaded the file, silently
              // undoing the deletion.
              try { await File(_localPath(root.path, path)).delete(); } catch (_) {}
              deleted++;
              state.remove(path);
            } else if (remoteWasSynced && !localChanged) {
              // The remote copy is gone without a tombstone — an incomplete
              // delta view, or a row removed out of band. Keep the local file
              // as the source of truth and restore it, rather than dropping our
              // baseline: dropping it re-uploaded the file on the next run
              // anyway, just without recording that it had.
              onProgress?.call('Restoring $path');
              await _uploadFile(_localPath(root.path, path), path);
              uploaded++;
              state[path] = {'kind':'file','localHash':localHash,'remoteHash':localHash,'localSize':l['size'] ?? 0,'remoteSize':l['size'] ?? 0,'localModifiedMs':l['modifiedMs'],'remoteModifiedAt':DateTime.now().toUtc().toIso8601String(),'localExists':true,'remoteExists':true};
            } else if (remoteWasSynced && tombstones.contains(path) && localChanged) {
              // Local edit wins over a prior remote tombstone: recreate the file.
              onProgress?.call('Re-uploading $path');
              await _uploadFile(_localPath(root.path, path), path);
              uploaded++;
              state[path] = {'kind':'file','localHash':localHash,'remoteHash':localHash,'localSize':l['size'] ?? 0,'remoteSize':l['size'] ?? 0,'localModifiedMs':l['modifiedMs'],'remoteModifiedAt':DateTime.now().toUtc().toIso8601String(),'localExists':true,'remoteExists':true};
            } else {
              onProgress?.call('Uploading $path');
              await _uploadFile(_localPath(root.path, path), path);
              uploaded++;
              state[path] = {'kind':'file','localHash':localHash,'remoteHash':localHash,'localSize':l['size'] ?? 0,'remoteSize':l['size'] ?? 0,'localModifiedMs':l['modifiedMs'],'remoteModifiedAt':DateTime.now().toUtc().toIso8601String(),'localExists':true,'remoteExists':true};
            }
            continue;
          }
          if (l == null || r == null) continue;
          if (base?['conflict'] == true) {
            conflicts++;
            continue;
          }
          if (localHash == remoteHash) {
            state[path] = {'kind':'file','localHash':localHash,'remoteHash':remoteHash,'localSize':l['size'] ?? 0,'localModifiedMs':l['modifiedMs'],'remoteSize':r['size'] ?? 0,'remoteModifiedAt':r['modified_at'],'localExists':true,'remoteExists':true};
            continue;
          }
          final localChanged = baseLocal == null || localHash != baseLocal;
          final remoteChanged = baseRemote == null || remoteHash != baseRemote;
          if (localChanged && remoteChanged) {
            conflicts++;
            final conflict = '${_localPath(root.path, path)}.conflict-${DateTime.now().millisecondsSinceEpoch}';
            onProgress?.call('Conflict: $path');
            await _download(path, conflict);
            state[path] = {'kind':'file','localHash':localHash,'remoteHash':remoteHash,'localSize':l['size'] ?? 0,'localModifiedMs':l['modifiedMs'],'remoteSize':r['size'] ?? 0,'remoteModifiedAt':r['modified_at'],'localExists':true,'remoteExists':true,'conflict':true,'conflictPath':conflict};
          } else if (localChanged) {
            onProgress?.call('Uploading $path');
            await _uploadFile(_localPath(root.path, path), path);
            uploaded++;
            state[path] = {'kind':'file','localHash':localHash,'remoteHash':localHash,'localSize':l['size'] ?? 0,'remoteSize':l['size'] ?? 0,'localModifiedMs':l['modifiedMs'],'remoteModifiedAt':DateTime.now().toUtc().toIso8601String(),'localExists':true,'remoteExists':true};
          } else {
            onProgress?.call('Downloading $path');
            await _download(path, _localPath(root.path, path));
            downloaded++;
            state[path] = {'kind':'file','localHash':remoteHash,'remoteHash':remoteHash,'localSize':r['size'] ?? 0,'remoteSize':r['size'] ?? 0,'localModifiedMs':DateTime.tryParse(r['modified_at']?.toString() ?? '')?.millisecondsSinceEpoch,'remoteModifiedAt':r['modified_at'],'localExists':true,'remoteExists':true};
          }
        } catch (_) {
          errors++;
        }
      }
      state['__meta__'] = {...?state['__meta__'], 'lastSyncAt': DateTime.now().toUtc().toIso8601String(), 'lastServerSyncAt': response['server_time']?.toString() ?? DateTime.now().toUtc().toIso8601String()};
      await _saveState(state);
      return SyncResult(uploaded: uploaded, downloaded: downloaded, deleted: deleted, conflicts: conflicts, errors: errors);
    } catch (e) {
      return SyncResult(errors: 1, error: e.toString());
    }
  }

  Future<String?> pickAndSetFolder() async {
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose NexaDrive sync folder',
      windowsOptions: const WindowsOptions(lockParentWindow: true),
    );
    if (path != null) await setFolder(path);
    return path;
  }

  Future<int> conflictCount() async {
    final state = await _state();
    return state.values.where((e) => e['conflict'] == true).length;
  }

  Future<List<Map<String, String>>> conflicts() async {
    final state = await _state();
    return state.entries
        .where((e) => e.value['conflict'] == true)
        .map((e) => {
              'path': e.key,
              'conflictPath': (e.value['conflictPath'] ?? '').toString(),
            })
        .toList();
  }

  Future<void> resolveConflictKeepLocal(String path) async {
    final state = await _state();
    final item = state[path];
    final folderPath = await folder();
    if (item == null || folderPath == null) throw Exception('Conflict is no longer available');
    await _uploadFile(_localPath(folderPath, path), path);
    final conflictPath = item['conflictPath']?.toString();
    if (conflictPath != null && conflictPath.isNotEmpty) { try { await File(conflictPath).delete(); } catch (_) {} }
    final hash = await _sha256(File(_localPath(folderPath, path)));
    item['localHash'] = hash;
    item['remoteHash'] = hash;
    final stat = await File(_localPath(folderPath, path)).stat();
    item['localSize'] = stat.size;
    item['localModifiedMs'] = stat.modified.millisecondsSinceEpoch;
    item['remoteSize'] = stat.size;
    item['remoteModifiedAt'] = DateTime.now().toUtc().toIso8601String();
    item['localExists'] = true;
    item['remoteExists'] = true;
    item.remove('conflict'); item.remove('conflictPath');
    state[path] = item;
    await _saveState(state);
  }

  Future<void> resolveConflictKeepRemote(String path) async {
    final state = await _state();
    final item = state[path];
    final folderPath = await folder();
    if (item == null || folderPath == null) throw Exception('Conflict is no longer available');
    await _download(path, _localPath(folderPath, path));
    final conflictPath = item['conflictPath']?.toString();
    if (conflictPath != null && conflictPath.isNotEmpty) { try { await File(conflictPath).delete(); } catch (_) {} }
    final hash = await _sha256(File(_localPath(folderPath, path)));
    item['localHash'] = hash;
    item['remoteHash'] = hash;
    final stat = await File(_localPath(folderPath, path)).stat();
    item['localSize'] = stat.size;
    item['localModifiedMs'] = stat.modified.millisecondsSinceEpoch;
    item['remoteSize'] = stat.size;
    item['remoteModifiedAt'] = DateTime.now().toUtc().toIso8601String();
    item['localExists'] = true;
    item['remoteExists'] = true;
    item.remove('conflict'); item.remove('conflictPath');
    state[path] = item;
    await _saveState(state);
  }

  Future<void> resolveConflictKeepBoth(String path) async {
    final state = await _state();
    final item = state[path];
    final folderPath = await folder();
    if (item == null || folderPath == null) throw Exception('Conflict is no longer available');
    // Keep the current local file as the canonical remote version; the existing
    // conflict copy already preserves the remote version locally.
    await _uploadFile(_localPath(folderPath, path), path);
    final hash = await _sha256(File(_localPath(folderPath, path)));
    item['localHash'] = hash;
    item['remoteHash'] = hash;
    final stat = await File(_localPath(folderPath, path)).stat();
    item['localSize'] = stat.size;
    item['localModifiedMs'] = stat.modified.millisecondsSinceEpoch;
    item['remoteSize'] = stat.size;
    item['remoteModifiedAt'] = DateTime.now().toUtc().toIso8601String();
    item['localExists'] = true;
    item['remoteExists'] = true;
    item.remove('conflict');
    // Intentionally keep conflictPath on disk as the preserved second copy.
    state[path] = item;
    await _saveState(state);
  }
}
