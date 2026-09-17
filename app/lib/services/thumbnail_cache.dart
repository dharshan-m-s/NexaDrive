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
/// older than [_maxAge] are pruned lazily, and on startup (and after every
/// write) the cache is capped at [_maxEntries] newest files and [_maxBytes]
/// total disk usage — a recently-viewed large album cannot balloon the app
/// cache, and the heaviest thumbnails are dropped first when over budget.
class ThumbnailCache {
  static const _cacheDirName = 'thumbnails';
  static const _maxAge = Duration(days: 7);
  static const _maxEntries = 512;

  /// Hard ceiling on total thumbnail cache size. 64 MB fits the roughly
  /// 256 KB server previews of several thousand photos, while bounding the
  /// app's on-disk footprint regardless of library size.
  static const _maxBytes = 64 * 1024 * 1024;

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
  /// null on miss, expiry, or IO error. A hit refreshes the entry's modified
  /// time so _shrink evicts least-recently-used thumbnails first.
  Uint8List? readSync(String serverUrl, String path) {
    final file = File(_fileFor(serverUrl, path));
    try {
      if (!file.existsSync()) return null;
      if (DateTime.now().difference(file.lastModifiedSync()) > _maxAge) {
        unawaited(file.delete().catchError((_) => file));
        return null;
      }
      final bytes = file.readAsBytesSync();
      // Touch to make _shrink's "oldest first" behave like LRU.
      file.setLastModifiedSync(DateTime.now());
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String serverUrl, String path, Uint8List bytes) async {
    final file = File(_fileFor(serverUrl, path));
    try {
      await file.writeAsBytes(bytes, flush: true);
    } catch (_) {}
    await _shrink();
  }

  /// Deletes every cached thumbnail. Used on sign-out so a shared device does
  /// not keep one account's previews around for the next one.
  Future<void> clear() async {
    try {
      final entities = await _dir.list().toList();
      for (final entity in entities) {
        try {
          await entity.delete(recursive: true);
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Enforces [ThumbnailCache._maxBytes] and [ThumbnailCache._maxEntries] by
  /// deleting the oldest entries first. Called on open and after every write,
  /// so the budget can never slip for long.
  Future<void> _shrink() async {
    try {
      final entities = await _dir.list().toList();
      final files = <File>[];
      var total = 0;
      for (final e in entities) {
        if (e is File) {
          files.add(e);
          try {
            total += e.lengthSync();
          } catch (_) {}
        }
      }
      if (files.length <= _maxEntries && total <= _maxBytes) return;

      files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));

      var i = 0;
      while (files.length - i > _maxEntries || total > _maxBytes) {
        if (i >= files.length) break;
        final f = files[i];
        try {
          total -= f.lengthSync();
          await f.delete();
        } catch (_) {}
        i++;
      }
    } catch (_) {}
  }
}