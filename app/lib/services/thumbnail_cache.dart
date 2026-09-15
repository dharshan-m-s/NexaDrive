import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// Small disk-backed cache for generated photo thumbnails.
///
/// Thumbnails are cheap to regenerate server-side, so the cache only exists
/// to avoid re-downloading the same preview bytes on every app launch. It is
/// keyed by (server + path) so switching servers never leaks files. Entries
/// older than [_maxAge] are pruned lazily, and on startup the cache is capped
/// at [_maxEntries] newest files.
class ThumbnailCache {
  static const _cacheDirName = 'thumbnails';
  static const _maxAge = Duration(days: 7);
  static const _maxEntries = 512;

  ThumbnailCache._(this._dir);

  final Directory _dir;

  static Future<ThumbnailCache> open() async {
    final base = await getApplicationCacheDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}$_cacheDirName');
    await dir.create(recursive: true);
    final cache = ThumbnailCache._(dir);
    await cache._shrink();
    return cache;
  }

  static String _key(String serverUrl, String path) {
    final digest = md5.convert('${serverUrl.trim()}|$path'.codeUnits);
    return digest.toString();
  }

  String _fileFor(String serverUrl, String path) {
    return '${_dir.path}${Platform.pathSeparator}${_key(serverUrl, path)}.jpg';
  }

  /// Synchronous read (called from build-time image resolution). Returns
  /// null on miss, expiry, or IO error.
  Uint8List? readSync(String serverUrl, String path) {
    final file = File(_fileFor(serverUrl, path));
    try {
      if (!file.existsSync()) return null;
      if (DateTime.now().difference(file.lastModifiedSync()) > _maxAge) {
        unawaited(file.delete().catchError((_) => file));
        return null;
      }
      return file.readAsBytesSync();
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String serverUrl, String path, Uint8List bytes) async {
    final file = File(_fileFor(serverUrl, path));
    try {
      await file.writeAsBytes(bytes, flush: true);
    } catch (_) {}
  }

  /// Keeps at most [_maxEntries] files by deleting oldest first.
  Future<void> _shrink() async {
    try {
      final entities = await _dir.list().toList();
      final files = <File>[];
      for (final e in entities) {
        if (e is File) files.add(e);
      }
      if (files.length <= _maxEntries) return;
      files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
      final excess = files.length - _maxEntries;
      for (var i = 0; i < excess; i++) {
        await files[i].delete();
      }
    } catch (_) {}
  }
}