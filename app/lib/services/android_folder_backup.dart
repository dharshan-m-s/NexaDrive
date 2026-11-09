import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'api.dart';
import 'content_source.dart';

/// Android's selected Storage Access Framework trees are one-way backup
/// sources. Every tree is tracked independently and backed up into a normal
/// folder in the user's NexaDrive Files root.
class AndroidFolderBackup {
  AndroidFolderBackup(this.api);

  final Api api;

  static const _treeKey = 'android_sync_tree_uri_v1';
  static const _nameKey = 'android_sync_tree_name_v1';
  static const _foldersKey = 'android_sync_folders_v2';
  static const _stateKey = 'android_sync_backup_state_v1';
  static const _stateFormatKey = 'android_sync_backup_state_format_v2';
  static const _lastSyncKey = 'android_sync_last_backup_at_v1';
  static const _channel = MethodChannel('nexadrive/folder_picker');
  static const _chunkSize = 8 * 1024 * 1024;
  static const _maxAttempts = 4;

  Future<DateTime?> lastSyncAt() async {
    final prefs = await SharedPreferences.getInstance();
    return DateTime.tryParse(prefs.getString(_lastSyncKey) ?? '')?.toLocal();
  }

  /// A copy of the configured sources. URI is the stable identity; labels are
  /// display/remote folder names and can be changed without losing permission.
  Future<List<Map<String, String>>> folderRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_foldersKey);
    if (raw != null && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((entry) {
              final map = Map<String, dynamic>.from(entry);
              return <String, String>{
                'uri': map['uri']?.toString() ?? '',
                'name': map['name']?.toString() ?? 'Phone backup',
                'remoteName': map['remoteName']?.toString() ??
                    map['name']?.toString() ??
                    'Phone backup',
              };
            })
            .where((entry) => entry['uri']!.isNotEmpty)
            .toList();
      }
    }

    // Upgrade installations that used the original single-folder setting.
    final legacyUri = prefs.getString(_treeKey);
    if (legacyUri == null || legacyUri.isEmpty) return const [];
    final legacyName = prefs.getString(_nameKey) ?? 'Phone backup';
    final record = <String, String>{
      'uri': legacyUri,
      'name': legacyName,
      'remoteName': _safeFolderName(legacyName),
    };
    await _saveFolderRecords([record]);
    return [record];
  }

  Future<void> _saveFolderRecords(List<Map<String, String>> records) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_foldersKey, jsonEncode(records));
    // Keep the legacy keys in sync for older builds rolling back safely.
    if (records.isNotEmpty) {
      await prefs.setString(_treeKey, records.first['uri']!);
      await prefs.setString(_nameKey, records.first['name']!);
    } else {
      await prefs.remove(_treeKey);
      await prefs.remove(_nameKey);
    }
  }

  String _safeFolderName(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[/\\:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty || cleaned == '.' || cleaned == '..'
        ? 'Phone backup'
        : cleaned;
  }

  String _safePathSegment(String value) {
    final cleaned = value.replaceAll(RegExp(r'[/\\]'), '_').trim();
    return cleaned.isEmpty || cleaned == '.' || cleaned == '..' ? '_' : cleaned;
  }

  Future<String?> folderLabel() async {
    final records = await folderRecords();
    if (records.isEmpty) return null;
    return records.map((entry) => entry['name']).join(' • ');
  }

  Future<String?> pickAndAddFolder() async {
    final uri = await _channel.invokeMethod<String>('pickFolder');
    if (uri == null || uri.isEmpty) return null;

    final payload = await _channel.invokeMapMethod<String, dynamic>(
      'listFolder',
      <String, Object>{'uri': uri},
    );
    if (payload == null || payload['files'] is! List) {
      throw StateError('Android could not read the selected folder.');
    }

    final name = (payload['name'] as String?)?.trim();
    final safeName = name == null || name.isEmpty ? 'Phone backup' : name;
    final records = await folderRecords();
    if (records.any((entry) => entry['uri'] == uri)) {
      return safeName;
    }
    // If this installation is upgrading from the original one-folder
    // setting, migrate its fingerprints before a second source is added.
    if (records.length == 1) {
      final state = await _loadState();
      await _migrateLegacyState(records, state);
    }

    final base = _safeFolderName(safeName);
    final used = records
        .map((entry) => entry['remoteName']!.toLowerCase())
        .toSet();
    // Do not silently merge a phone backup into an unrelated folder that
    // already exists in My Files. If the server is temporarily unreachable,
    // still allow the folder to be configured; the actual sync will report
    // the network error rather than losing the user's selection.
    try {
      final existing = await api.listFiles('');
      used.addAll(
        existing
            .map((entry) => entry['name']?.toString().toLowerCase() ?? '')
            .where((name) => name.isNotEmpty),
      );
    } catch (_) {}
    var remoteName = base;
    var suffix = 2;
    while (used.contains(remoteName.toLowerCase())) {
      remoteName = '$base (Phone Backup $suffix)';
      suffix++;
    }
    records.add({
      'uri': uri,
      'name': safeName,
      'remoteName': remoteName,
    });
    await _saveFolderRecords(records);
    return safeName;
  }

  /// Kept as an alias for existing callers; Android now adds rather than
  /// replacing a configured source.
  Future<String?> pickAndSetFolder() => pickAndAddFolder();

  Future<void> removeFolder(String uri) async {
    final records = await folderRecords();
    records.removeWhere((entry) => entry['uri'] == uri);
    await _saveFolderRecords(records);
    // Drop fingerprints for a removed source. If it is added again later,
    // it may receive a collision-safe new destination folder and must be
    // populated there rather than incorrectly skipped as already uploaded.
    final state = await _loadState();
    state.removeWhere((key, _) => key.startsWith('$uri::'));
    await _saveState(state);
  }

  Future<void> clearFolder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_foldersKey);
    await prefs.remove(_treeKey);
    await prefs.remove(_nameKey);
    await prefs.remove(_stateKey);
    await prefs.remove(_stateFormatKey);
    await prefs.remove(_lastSyncKey);
  }

  Future<Map<String, Map<String, dynamic>>> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_stateKey);
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map(
      (key, value) => MapEntry(key, Map<String, dynamic>.from(value as Map)),
    );
  }

  Future<void> _saveState(
    Map<String, Map<String, dynamic>> state,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_stateKey, jsonEncode(state));
    await prefs.setString(_stateFormatKey, '2');
  }

  /// Migrates the original one-folder fingerprint keys so upgrading does not
  /// force a complete duplicate upload on the first run after this release.
  Future<void> _migrateLegacyState(
    List<Map<String, String>> records,
    Map<String, Map<String, dynamic>> state,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_stateFormatKey) == '2' || records.length != 1) return;
    final uri = records.single['uri']!;
    final migrated = <String, Map<String, dynamic>>{};
    for (final entry in state.entries) {
      if (!entry.key.contains('::')) {
        migrated['$uri::${entry.key}'] = entry.value;
      } else {
        migrated[entry.key] = entry.value;
      }
    }
    state
      ..clear()
      ..addAll(migrated);
    await _saveState(state);
  }

  /// Reads a bounded range from a SAF document. The native bridge owns the
  /// provider descriptor and closes it even if hashing or upload is cancelled.
  Stream<List<int>> _readUri(String uri, int offset, int length) async* {
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
          throw const FormatException(
            'The document provider returned too much data.',
          );
        }
        remaining -= bytes.length;
        yield bytes;
      }
    } finally {
      await ContentSource.closeStream(sessionId);
    }
  }

  Stream<List<int>> _readSession(String sessionId, int length) async* {
    var remaining = length;
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
        throw const FormatException(
          'The document provider returned too much data.',
        );
      }
      remaining -= bytes.length;
      yield bytes;
    }
  }

  Future<String> _hashUri(String uri, int size) async {
    if (size == 0) return sha256.convert(const <int>[]).toString();
    final digest = await sha256.bind(_readUri(uri, 0, size)).first;
    return digest.toString();
  }

  Future<void> _ensureRemoteFolder(String path, Set<String> created) async {
    if (path.isEmpty || created.contains(path)) return;
    try {
      await api.createFolder(path);
    } on ApiException catch (error) {
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
      String? sourceSession;
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
        sourceSession = await ContentSource.openStream(uri, offset);
        while (offset < size) {
          final end = offset + _chunkSize > size ? size : offset + _chunkSize;
          final result = await api.uploadChunk(
            uploadId: uploadId,
            folder: remoteFolder,
            name: name,
            offset: offset,
            total: size,
            bytes: _readSession(sourceSession, end - offset),
            contentLength: end - offset,
          );
          final next = (result['offset'] as num?)?.toInt() ?? end;
          if (next <= offset || next > size) {
            throw StateError('The server returned an invalid upload offset.');
          }
          offset = next;
        }
        await ContentSource.closeStream(sourceSession);
        sourceSession = null;
        return;
      } catch (_) {
        if (sourceSession != null) {
          try {
            await ContentSource.closeStream(sourceSession);
          } catch (_) {}
        }
        if (attempt == _maxAttempts) rethrow;
        await Future<void>.delayed(Duration(seconds: attempt * 2));
      }
    }
  }

  Future<({int uploaded, int checked, int errors})> _syncOneFolder({
    required Map<String, String> folder,
    required Map<String, Map<String, dynamic>> state,
    required Set<String> createdFolders,
    required void Function(String)? onProgress,
  }) async {
    final uri = folder['uri']!;
    final sourceName = folder['name']!;
    final rootName = folder['remoteName']!;
    onProgress?.call('Scanning $sourceName…');
    final payload = await _channel.invokeMapMethod<String, dynamic>(
      'listFolder',
      <String, Object>{'uri': uri},
    );
    if (payload == null || payload['files'] is! List) {
      throw StateError(
        '“$sourceName” is no longer accessible. Remove it and add it again.',
      );
    }
    final rawFiles = payload['files'] as List;
    await _ensureRemoteFolder(rootName, createdFolders);
    var uploaded = 0;
    var errors = 0;
    var checked = 0;

    for (final item in rawFiles) {
      if (item is! Map) continue;
      final file = Map<String, dynamic>.from(item);
      final sourceUri = file['sourceUri']?.toString();
      final relative = file['path']?.toString() ?? '';
      final name = file['name']?.toString() ?? '';
      final size = (file['size'] as num?)?.toInt();
      if (sourceUri == null ||
          sourceUri.isEmpty ||
          name.isEmpty ||
          size == null ||
          size < 0) {
        errors++;
        onProgress?.call('Skipping unreadable item in $sourceName');
        continue;
      }
      final segments = relative
          .split('/')
          .where((part) => part.isNotEmpty)
          .map(_safePathSegment)
          .toList(growable: false);
      if (segments.isEmpty) {
        errors++;
        continue;
      }
      final fileName = _safePathSegment(segments.last);
      final relativeDirectory = segments.length > 1
          ? segments.sublist(0, segments.length - 1).join('/')
          : '';
      final remoteFolder =
          relativeDirectory.isEmpty ? rootName : '$rootName/$relativeDirectory';
      final stateKey = '$uri::$relative';
      checked++;

      try {
        onProgress?.call('Checking $sourceName/$relative');
        final hash = await _hashUri(sourceUri, size);
        final previous = state[stateKey];
        if (previous?['sha256'] == hash &&
            (previous?['size'] as num?)?.toInt() == size) {
          continue;
        }
        var current = rootName;
        for (final segment
            in relativeDirectory.split('/').where((part) => part.isNotEmpty)) {
          current = '$current/$segment';
          await _ensureRemoteFolder(current, createdFolders);
        }
        onProgress?.call('Uploading $sourceName/$relative');
        await _uploadDocument(
          uri: sourceUri,
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
        onProgress?.call('Could not back up $sourceName/$relative: $error');
      }
    }
    return (uploaded: uploaded, checked: checked, errors: errors);
  }

  /// Manually backs up every configured folder. Existing files are checked by
  /// content hash; new or modified files upload. Local deletions never delete
  /// their server copies, and cloud files are never downloaded to the phone.
  Future<({int uploaded, int errors, String? error})> sync({
    void Function(String)? onProgress,
  }) async {
    final records = await folderRecords();
    if (records.isEmpty) {
      return (
        uploaded: 0,
        errors: 1,
        error: 'Add at least one phone folder to back up first.',
      );
    }
    try {
      final state = await _loadState();
      await _migrateLegacyState(records, state);
      final createdFolders = <String>{};
      var uploaded = 0;
      var errors = 0;
      var checked = 0;
      for (final folder in records) {
        try {
          final result = await _syncOneFolder(
            folder: folder,
            state: state,
            createdFolders: createdFolders,
            onProgress: onProgress,
          );
          uploaded += result.uploaded;
          checked += result.checked;
          errors += result.errors;
          await _saveState(state);
        } catch (error) {
          errors++;
          onProgress?.call('Could not scan ${folder['name']}: $error');
        }
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _lastSyncKey,
        DateTime.now().toUtc().toIso8601String(),
      );
      onProgress?.call(
        uploaded == 0
            ? 'Checked $checked file(s); no new or changed files.'
            : 'Uploaded $uploaded file(s); checked $checked file(s).',
      );
      return (
        uploaded: uploaded,
        errors: errors,
        error: errors > 0
            ? 'Checked $checked file(s), uploaded $uploaded, and encountered $errors error(s).'
            : null,
      );
    } on PlatformException catch (error) {
      return (
        uploaded: 0,
        errors: 1,
        error: error.code == 'open_failed' || error.code == 'read_failed'
            ? 'Android could not read a selected folder. Re-select that folder in Sync Center.'
            : (error.message ?? 'The selected folder could not be read.'),
      );
    } catch (error) {
      return (uploaded: 0, errors: 1, error: error.toString());
    }
  }
}
