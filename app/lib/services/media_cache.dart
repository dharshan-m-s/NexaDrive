import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'api.dart';
import 'download_service.dart';

/// Bounded on-disk cache for media that must be played by a platform backend
/// (audio). Files are streamed to disk by [DownloadService], so memory usage
/// stays flat no matter how large the track is, and the OS player can seek
/// inside a real file.
///
/// The cache is keyed by account namespace + path + the file's server-side
/// fingerprint, so an edited file is never served from a stale entry, and
/// switching accounts never leaks another user's media on a shared device.
class MediaCache {
  MediaCache._(this._dir, this._downloads);

  static const _dirName = 'media';
  static const _maxBytes = 512 * 1024 * 1024;
  static const _maxEntryBytes = 256 * 1024 * 1024;
  static const _maxAge = Duration(days: 14);

  final Directory _dir;
  final DownloadService _downloads;

  static Future<MediaCache> open(Api api) async {
    final base = await getApplicationCacheDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}$_dirName');
    await dir.create(recursive: true);
    final cache = MediaCache._(dir, DownloadService(api));
    unawaited(cache.prune());
    return cache;
  }

  /// Path a cached entry would occupy. Exposed for tests and diagnostics.
  String pathFor({
    required String namespace,
    required String remotePath,
    required String fingerprint,
  }) {
    final digest = md5.convert('$namespace|$fingerprint|$remotePath'.codeUnits);
    final ext = _extension(remotePath);
    return '${_dir.path}${Platform.pathSeparator}$digest$ext';
  }

  static String _extension(String path) {
    final clean = path.replaceAll('\\', '/');
    final name = clean.substring(clean.lastIndexOf('/') + 1);
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    final ext = name.substring(dot);
    // Keep only plausible extensions so a strange name cannot create a path
    // with separators in it.
    return RegExp(r'^\.[A-Za-z0-9]{1,8}$').hasMatch(ext) ? ext : '';
  }

  /// Returns the cached file for [remotePath] if it is already fully present.
  File? cached({
    required String namespace,
    required String remotePath,
    required String fingerprint,
  }) {
    final file = File(pathFor(
      namespace: namespace,
      remotePath: remotePath,
      fingerprint: fingerprint,
    ));
    return file.existsSync() ? file : null;
  }

  /// Ensures [remotePath] exists on disk, downloading it if needed.
  ///
  /// Reports byte progress so the UI can show an honest buffering state. Files
  /// larger than [_maxEntryBytes] are still playable through the returned file
  /// for this session, but are not retained by [prune].
  Future<File> fetch({
    required String namespace,
    required String remotePath,
    required String fingerprint,
    void Function(int received, int? total)? onProgress,
    CancelToken? cancel,
  }) async {
    final target = File(pathFor(
      namespace: namespace,
      remotePath: remotePath,
      fingerprint: fingerprint,
    ));
    if (target.existsSync()) {
      // Touch so the LRU keeps recently played tracks.
      try {
        target.setLastModifiedSync(DateTime.now());
      } catch (_) {}
      return target;
    }
    await _downloads.downloadToFile(
      remotePath,
      target.path,
      onProgress: onProgress,
      cancel: cancel,
    );
    unawaited(prune());
    return target;
  }

  /// Enforces the age and size budget by deleting the least recently used
  /// entries first. Best-effort: failures never surface to the user.
  Future<void> prune() async {
    try {
      final entities = await _dir.list().toList();
      final files = <File>[];
      var total = 0;
      final now = DateTime.now();
      for (final entity in entities) {
        if (entity is! File) continue;
        try {
          final stat = entity.statSync();
          if (now.difference(stat.modified) > _maxAge ||
              stat.size > _maxEntryBytes) {
            await entity.delete();
            continue;
          }
          total += stat.size;
          files.add(entity);
        } catch (_) {}
      }
      if (total <= _maxBytes) return;
      files.sort((a, b) {
        try {
          return a.lastModifiedSync().compareTo(b.lastModifiedSync());
        } catch (_) {
          return 0;
        }
      });
      for (final file in files) {
        if (total <= _maxBytes) break;
        try {
          final size = file.lengthSync();
          await file.delete();
          total -= size;
        } catch (_) {}
      }
    } catch (_) {
      // Cache maintenance is never allowed to break playback.
    }
  }

  /// Removes everything. Called on sign-out so one account's cached media does
  /// not survive into another's session.
  Future<void> clear() async {
    try {
      await _dir.delete(recursive: true);
      await _dir.create(recursive: true);
    } catch (_) {}
  }
}
