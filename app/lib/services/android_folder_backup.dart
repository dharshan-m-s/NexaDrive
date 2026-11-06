import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'api.dart';
import 'content_source.dart';

/// Android's selected Storage Access Framework tree is a one-way backup
/// source. It never mirrors cloud deletions back onto the phone and never
/// downloads cloud content into the selected tree.
class AndroidFolderBackup {
  AndroidFolderBackup(this.api);

  final Api api;

  static const _treeKey = 'android_sync_tree_uri_v1';
  static const _nameKey = 'android_sync_tree_name_v1';
  static const _stateKey = 'android_sync_backup_state_v1';
  static const _lastSyncKey = 'android_sync_last_backup_at_v1';
  static const _channel = MethodChannel('nexadrive/folder_picker');
  static const _chunkSize = 8 * 1024 * 1024;
  static const _maxAttempts = 4;

  Future<DateTime?> lastSyncAt() async {
    final prefs = await SharedPreferences.getInstance();
    return DateTime.tryParse(prefs.getString(_lastSyncKey) ?? '')?.toLocal();
  }

  Future<String?> folderLabel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_nameKey);
  }

  Future<String?> pickAndSetFolder() async {
    final uri = await _channel.invokeMethod<String>('pickFolder');
    if (uri == null || uri.isEmpty) return null;

    // Verify that the saved grant can actually enumerate the selected tree
    // before replacing the previously configured folder.
    final payload = await _channel.invokeMapMethod<String, dynamic>(
      'listFolder',
      <String, Object>{'uri': uri},
    );
    if (payload == null) {
      throw StateError('Android could not read the selected folder.');
    }

    final name = (payload['name'] as String?)?.trim();
    final safeName = name == null || name.isEmpty ? 'Phone backup' : name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_treeKey, uri);
    await prefs.setString(_nameKey, safeName);
    await prefs.remove(_stateKey);
    await prefs.remove(_lastSyncKey);
    return safeName;
  }

  Future<void> clearFolder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_treeKey);
    await prefs.remove(_nameKey);
    await prefs.remove(_stateKey);
    await prefs.remove(_lastSyncKey);
  }

  Future<Map<String, Map<String, dynamic>>> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_stateKey);
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map(
      (key, value) =>
          MapEntry(key, Map<String, dynamic>.from(value as Map)),
    );
  }

  Future<void> _saveState(
    Map<String, Map<String, dynamic>> state,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_stateKey, jsonEncode(state));
  }

  /// Reads a bounded range from a SAF document. The native bridge owns the
  /// provider descriptor and closes it even if hashing or upload is cancelled.
  Stream<List<int>> _readUri(
    String uri,
    int offset,
    int length,
  ) async* {
    if (length == 0) return;
    final sessionId = await ContentSource.openStream(uri, offset);
    var remaining = length;
    try {
      while (remaining > 0) {
        final count = remaining < ContentSource.maxRange
            ? remaining
            : ContentSource.maxRange;
        final bytes = await ContentSource.readNext(sessionId, count);
        if (bytes.isEmpty) {
          throw const FormatException(
            'The selected file changed or ended while it was being read.',
          );
        }
        if (bytes.length > remaining) {
          throw const FormatException('The document provider returned too much data.');
        }
        remaining -= bytes.length;
        yield bytes;
      }
    } finally {
      await ContentSource.closeStream(sessionId);
    }
  }

  Future<String> _hashUri(String uri, int size) async {
    if (size == 0) return sha256.convert(const <int>[]).toString();
    return sha256.bind(_readUri(uri, 0, size)).first.then((digest) => digest.toString());
  }

  Future<void> _ensureRemoteFolder(
    String path,
    Set<String> created,
  ) async {
    if (path.isEmpty || created.contains(path)) return;
    try {
      await api.createFolder(path);
    } on ApiException catch (error) {
      // Existing directories are normal on every subsequent manual sync.
      if (error.status != 409 &&
          !error.message.toLowerCase().contains('already exists')) {
        rethrow;
      }
    }
    created.add(path);
  }

  Future<void> _uploadDocument({
    required String uri,
    required int size,
    required String name,
    required String remoteFolder,
  }) async {
    final uploadId = const Uuid().v4();

    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        final remote = await api.uploadStatus(uploadId);
        if (remote['status'] == 'completed') return;
        var offset = (remote['bytes_received'] as num?)?.toInt() ?? 0;
        if (offset < 0 || offset > size) offset = 0;

        if (size == 0) {
          await api.uploadChunk(
            uploadId: uploadId,
            folder: remoteFolder,
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
            folder: remoteFolder,
            name: name,
            offset: offset,
            total: size,
            bytes: _readUri(uri, offset, end - offset),
            contentLength: end - offset,
          );
          final next = (result['offset'] as num?)?.toInt() ?? end;
          if (next <= offset || next > size) {
            throw StateError('The server returned an invalid upload offset.');
          }
          offset = next;
        }
        return;
      } catch (_) {
        if (attempt == _maxAttempts) rethrow;
        await Future<void>.delayed(Duration(seconds: attempt * 2));
      }
    }
  }

  /// Returns a SyncResult-shaped record so the existing Sync Center can
  /// display the result without changing the desktop sync engine.
  Future<({int uploaded, int errors, String? error})> sync({
    void Function(String)? onProgress,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final treeUri = prefs.getString(_treeKey);
    final rootName = prefs.getString(_nameKey);
    if (treeUri == null || treeUri.isEmpty || rootName == null) {
      return (uploaded: 0, errors: 1, error: 'Choose a folder to back up first.');
    }

    try {
      onProgress?.call('Reading the selected phone folder…');
      final payload = await _channel.invokeMapMethod<String, dynamic>(
        'listFolder',
        <String, Object>{'uri': treeUri},
      );
      if (payload == null) {
        return (
          uploaded: 0,
          errors: 1,
          error: 'The selected folder is no longer accessible. Select it again.',
        );
      }

      final rawFiles = payload['files'];
      if (rawFiles is! List) {
        throw const FormatException('Android returned an invalid folder listing.');
      }

      final state = await _loadState();
      final createdFolders = <String>{};
      await _ensureRemoteFolder(rootName, createdFolders);
      var uploaded = 0;
      var errors = 0;
      var processed = 0;

      for (final item in rawFiles) {
        if (item is! Map) continue;
        final file = Map<String, dynamic>.from(item);
        final uri = file['sourceUri']?.toString();
        final relative = file['path']?.toString() ?? '';
        final name = file['name']?.toString() ?? '';
        final size = (file['size'] as num?)?.toInt();
        if (uri == null || uri.isEmpty || name.isEmpty || size == null || size < 0) {
          errors++;
          continue;
        }

        final segments = relative
            .split('/')
            .where((part) => part.isNotEmpty)
            .toList(growable: false);
        if (segments.isEmpty) {
          errors++;
          continue;
        }
        final fileName = segments.last;
        final relativeDirectory = segments.length > 1
            ? segments.sublist(0, segments.length - 1).join('/')
            : '';
        final remoteFolder = relativeDirectory.isEmpty
            ? rootName
            : '$rootName/$relativeDirectory';
        final stateKey = relative;
        processed++;

        try {
          onProgress?.call('Checking $relative');
          final hash = await _hashUri(uri, size);
          final previous = state[stateKey];
          if (previous?['sha256'] == hash &&
              (previous?['size'] as num?)?.toInt() == size) {
            continue;
          }

          var current = rootName;
          for (final segment in relativeDirectory.split('/').where((p) => p.isNotEmpty)) {
            current = '$current/$segment';
            await _ensureRemoteFolder(current, createdFolders);
          }

          onProgress?.call('Uploading $relative');
          await _uploadDocument(
            uri: uri,
            size: size,
            name: fileName,
            remoteFolder: remoteFolder,
          );
          state[stateKey] = {
            'sha256': hash,
            'size': size,
            'remotePath': '$remoteFolder/$fileName',
          };
          await _saveState(state);
          uploaded++;
        } catch (error) {
          errors++;
          onProgress?.call('Could not back up $relative: $error');
        }
      }

      // An empty folder is still a valid backup target. A zero-file scan does
      // not imply deletion: cloud contents and saved fingerprints are retained.
      await _saveState(state);
      await prefs.setString(_lastSyncKey, DateTime.now().toUtc().toIso8601String());
      return (
        uploaded: uploaded,
        errors: errors,
        error: errors > 0
            ? 'Backup checked $processed file(s); $errors could not be processed.'
            : null,
      );
    } on PlatformException catch (error) {
      return (
        uploaded: 0,
        errors: 1,
        error: error.code == 'open_failed' || error.code == 'read_failed'
            ? 'Android could not read the selected folder. Re-select it in Sync Center to restore access.'
            : (error.message ?? 'The selected folder could not be read.'),
      );
    } catch (error) {
      return (uploaded: 0, errors: 1, error: error.toString());
    }
  }
}
