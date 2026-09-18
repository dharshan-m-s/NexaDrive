import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'thumbnail_cache.dart';

/// Which rendition of a stored image a request is for.
///
/// The two renditions are deliberately distinct value types rather than a
/// boolean flag: it makes "the viewer accidentally rendered a thumbnail"
/// unrepresentable instead of merely discouraged.
enum ImageRendition {
  /// Server-generated, downscaled preview used for grids and placeholders.
  thumbnail,

  /// The exact bytes the user uploaded. Never downscaled, never recompressed,
  /// never substituted. This is what the photo viewer must render.
  original,
}

/// Identity of one cached image rendition.
///
/// A key includes the [rendition], so a thumbnail can never satisfy an
/// original request even when the same path is requested in both qualities.
/// [fingerprint] carries the server's `modified_at`/`size` for the file, so an
/// edited file is never served from a stale cache entry.
@immutable
class ImageKey {
  const ImageKey({
    required this.namespace,
    required this.path,
    required this.rendition,
    this.fingerprint = '',
    this.maxEdge = 0,
  });

  /// Cache namespace: normalised server URL **plus** the signed-in account
  /// (see `Session.cacheNamespace`). Two accounts on one server therefore
  /// never share cached bytes.
  final String namespace;
  final String path;
  final ImageRendition rendition;

  /// Server-side version marker (`modified_at` + size). Empty means "unknown",
  /// in which case the key is still safe to use, just less precise.
  final String fingerprint;

  /// Requested longest edge for thumbnails; 0 for originals.
  final int maxEdge;

  ImageKey copyWithPath(String newPath) => ImageKey(
        namespace: namespace,
        path: newPath,
        rendition: rendition,
        fingerprint: fingerprint,
        maxEdge: maxEdge,
      );

  ImageKey withMaxEdge(int max) => ImageKey(
        namespace: namespace,
        path: path,
        rendition: rendition,
        fingerprint: fingerprint,
        maxEdge: max,
      );

  @override
  bool operator ==(Object other) =>
      other is ImageKey &&
      other.namespace == namespace &&
      other.path == path &&
      other.rendition == rendition &&
      other.fingerprint == fingerprint &&
      other.maxEdge == maxEdge;

  @override
  int get hashCode =>
      Object.hash(namespace, path, rendition, fingerprint, maxEdge);

  @override
  String toString() => 'ImageKey(${rendition.name}, $path, max=$maxEdge)';
}

/// Result of a successful image fetch: the bytes plus the key they were
/// resolved for, so a caller can assert which rendition it received.
@immutable
class ImageData {
  const ImageData(this.bytes, {required this.key});

  final Uint8List bytes;
  final ImageKey key;

  bool get isOriginal => key.rendition == ImageRendition.original;
}

/// Raised when the server cannot produce a thumbnail for a format (HEIC/AVIF
/// without a codec). Callers must handle this explicitly rather than silently
/// substituting a poor-quality representation.
class ThumbnailUnavailable implements Exception {
  const ThumbnailUnavailable(this.path);
  final String path;
  @override
  String toString() => 'No thumbnail available for $path';
}

/// Centralized image acquisition and caching for NexaDrive.
///
/// ## Image quality contract
///
/// 1. [original] fetches `/api/files/download` and returns those bytes
///    **unmodified**; nothing here decodes, resizes or re-encodes them.
/// 2. [thumbnail] fetches `/api/files/thumbnail` and is only ever used for
///    grids and as a low-cost placeholder.
/// 3. Cache entries are keyed by [ImageKey], which includes the rendition, so
///    the two qualities occupy disjoint key spaces. A thumbnail can never be
///    returned for an original request.
/// 4. Both in-memory caches are bounded (entries *and* bytes), so browsing a
///    large library cannot exhaust memory. Originals are bounded separately
///    and much more tightly than thumbnails.
class ImageRepository {
  ImageRepository(
    this.api, {
    this.diskCache,
    this.maxThumbBytes = 24 * 1024 * 1024,
    this.maxOriginalBytes = 96 * 1024 * 1024,
    this.maxThumbEntries = 256,
    this.maxOriginalEntries = 6,
  });

  final Api api;

  /// Optional persistent thumbnail cache. Assignable so a screen can attach
  /// it once the async directory lookup resolves without dropping the memory
  /// cache it has already warmed.
  ThumbnailCache? diskCache;

  /// Byte budgets for the two disjoint in-memory caches.
  final int maxThumbBytes;
  final int maxOriginalBytes;

  /// Entry ceilings, so many tiny entries cannot pin memory either.
  final int maxThumbEntries;
  final int maxOriginalEntries;

  final _LruByteCache _thumbs = _LruByteCache();
  final _LruByteCache _originals = _LruByteCache();

  /// Resolved failures, so a broken file does not retry on every rebuild.
  final Set<ImageKey> _failedOriginals = <ImageKey>{};
  final Set<ImageKey> _failedThumbs = <ImageKey>{};

  /// Builds the canonical key for a photo descriptor returned by the server.
  static ImageKey keyFor(
    Map<String, dynamic> photo, {
    required String namespace,
    required ImageRendition rendition,
    int maxEdge = 512,
  }) {
    final path = (photo['path'] ?? '').toString();
    return ImageKey(
      namespace: namespace,
      path: path,
      rendition: rendition,
      fingerprint: imageFingerprint(photo),
      maxEdge: rendition == ImageRendition.thumbnail ? maxEdge : 0,
    );
  }

  /// Version marker for a file: modification time plus size. Both are present
  /// in file listings and change whenever the file's content changes.
  static String imageFingerprint(Map<String, dynamic> entry) {
    final modified = (entry['modified_at'] ?? '').toString();
    final size = (entry['size'] ?? '').toString();
    return '$modified|$size';
  }

  /// Cached thumbnail bytes for [key], or null on miss. Never consults the
  /// original cache.
  Uint8List? peekThumbnail(ImageKey key) {
    assert(key.rendition == ImageRendition.thumbnail);
    return _thumbs.get(key);
  }

  /// Cached original bytes for [key], or null on miss. Never consults the
  /// thumbnail cache: this is the guarantee the photo viewer depends on.
  Uint8List? peekOriginal(ImageKey key) {
    assert(key.rendition == ImageRendition.original);
    return _originals.get(key);
  }

  /// True when this rendition already failed; callers can render an error
  /// state instead of retrying from a build callback.
  bool hasFailed(ImageKey key) => key.rendition == ImageRendition.original
      ? _failedOriginals.contains(key)
      : _failedThumbs.contains(key);

  /// Clears a recorded failure so the user can retry explicitly.
  void clearFailure(ImageKey key) {
    _failedOriginals.remove(key);
    _failedThumbs.remove(key);
  }

  /// Fully forgets [key]: cached bytes *and* any recorded failure.
  ///
  /// This is what an explicit Retry must use. Re-decoding the same cached bytes
  /// fails identically, so a Retry that only cleared the failure flag would be a
  /// button that can never succeed — for instance when a transfer was truncated
  /// in flight. Dropping the bytes forces a real re-download.
  void forget(ImageKey key) {
    _failedOriginals.remove(key);
    _failedThumbs.remove(key);
    if (key.rendition == ImageRendition.original) {
      _originals.remove(key);
    } else {
      _thumbs.remove(key);
    }
  }

  /// Fetches the FULL-RESOLUTION original for [key].
  ///
  /// The returned bytes are exactly what the server stored; no client-side
  /// transformation is applied. Bounded LRU caching keeps only the newest few
  /// originals in memory.
  Future<ImageData> original(ImageKey key) async {
    assert(key.rendition == ImageRendition.original);
    final cached = _originals.get(key);
    if (cached != null) return ImageData(cached, key: key);
    try {
      final bytes = await api.download(key.path);
      if (bytes.isEmpty) {
        throw ApiException(502, 'The server returned an empty image.');
      }
      _originals.put(
        key,
        bytes,
        maxEntries: maxOriginalEntries,
        maxBytes: maxOriginalBytes,
      );
      _failedOriginals.remove(key);
      return ImageData(bytes, key: key);
    } catch (e) {
      _failedOriginals.add(key);
      rethrow;
    }
  }

  /// Fetches a server-generated thumbnail for [key].
  ///
  /// Consults the memory cache first, then the disk cache (which survives
  /// restarts), then the network. Throws [ThumbnailUnavailable] when the
  /// server cannot produce one; callers must handle that explicitly.
  Future<ImageData> thumbnail(ImageKey key, {int max = 512}) async {
    assert(key.rendition == ImageRendition.thumbnail);
    final resolved = key.maxEdge == max ? key : key.withMaxEdge(max);
    final memory = _thumbs.get(resolved);
    if (memory != null) return ImageData(memory, key: resolved);

    final disk = diskCache;
    final namespace = api.session.cacheNamespace;
    if (disk != null) {
      final cached = disk.readSync(namespace, _diskKey(resolved));
      if (cached != null) {
        _thumbs.put(
          resolved,
          cached,
          maxEntries: maxThumbEntries,
          maxBytes: maxThumbBytes,
        );
        return ImageData(cached, key: resolved);
      }
    }

    try {
      final bytes = await api.thumbnail(resolved.path, max: max);
      _thumbs.put(
        resolved,
        bytes,
        maxEntries: maxThumbEntries,
        maxBytes: maxThumbBytes,
      );
      _failedThumbs.remove(resolved);
      unawaited(disk?.write(namespace, _diskKey(resolved), bytes));
      return ImageData(bytes, key: resolved);
    } on ApiException catch (e) {
      _failedThumbs.add(resolved);
      if (e.status == 415) throw ThumbnailUnavailable(resolved.path);
      rethrow;
    } catch (_) {
      _failedThumbs.add(resolved);
      rethrow;
    }
  }

  /// Disk-cache namespace. Includes the rendition and the max edge so a
  /// thumbnail cached at 512 is never served for a request at another size.
  String _diskKey(ImageKey key) =>
      '${key.rendition.name}|${key.maxEdge}|${key.fingerprint}|${key.path}';

  /// Drops everything. Used on sign-out so one account's images never leak
  /// into another's session.
  void clear() {
    _thumbs.clear();
    _originals.clear();
    _failedOriginals.clear();
    _failedThumbs.clear();
  }

  /// Approximate bytes currently held in memory (both caches).
  int get memoryBytes => _thumbs.bytes + _originals.bytes;
}

/// Minimal insertion-ordered LRU with both an entry and a byte budget.
class _LruByteCache {
  final LinkedHashMap<ImageKey, Uint8List> _entries = LinkedHashMap();
  int _bytes = 0;

  int get bytes => _bytes;
  int get length => _entries.length;

  Uint8List? get(ImageKey key) {
    final value = _entries.remove(key);
    if (value == null) return null;
    _entries[key] = value; // re-insert as most recently used
    return value;
  }

  void put(
    ImageKey key,
    Uint8List value, {
    required int maxEntries,
    required int maxBytes,
  }) {
    final previous = _entries.remove(key);
    if (previous != null) _bytes -= previous.length;
    _entries[key] = value;
    _bytes += value.length;
    // Evict least-recently-used first. Always keep at least one entry so a
    // single image larger than the budget is still usable.
    while (_entries.length > maxEntries ||
        (_bytes > maxBytes && _entries.length > 1)) {
      final oldest = _entries.keys.first;
      final removed = _entries.remove(oldest);
      if (removed != null) _bytes -= removed.length;
    }
  }

  void remove(ImageKey key) {
    final removed = _entries.remove(key);
    if (removed != null) _bytes -= removed.length;
  }

  void clear() {
    _entries.clear();
    _bytes = 0;
  }
}
