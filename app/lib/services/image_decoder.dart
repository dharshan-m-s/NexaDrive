import 'dart:typed_data';
import 'dart:ui' as ui;

import 'image_decode_policy.dart';

/// Raised when the bytes cannot be decoded at all (corrupt file, or a format
/// this platform has no codec for). Distinct from a bounded fallback, which
/// still succeeds.
class ImageDecodeException implements Exception {
  const ImageDecodeException(this.path, [this.cause]);
  final String path;
  final Object? cause;
  @override
  String toString() =>
      'Could not decode $path${cause == null ? '' : ' ($cause)'}';
}

/// Turns encoded photo bytes into a [ui.Image] for display.
///
/// ## Quality contract
///
/// 1. Photos within [ImageDecodePolicy.maxNaturalPixels] are decoded at their
///    **natural size** — no `targetWidth`, so every original pixel reaches the
///    GPU and zooming reveals real texture.
/// 2. Dimensions are read through [ui.ImageDescriptor], which parses only the
///    header. The viewer therefore knows how big a photo is *before* committing
///    the memory to decode it.
/// 3. Genuinely huge photos (and any photo whose natural decode fails on a
///    memory-constrained device) are decoded to a bounded long edge that is
///    still at least 4K and at least twice the viewport. That is a graceful
///    degradation to "as sharp as this screen can show", never to a thumbnail.
/// 4. Failures are reported, never swallowed: a swallowed failure is what makes
///    a viewer sit on a placeholder forever and look blurry.
class ImageDecoder {
  const ImageDecoder();

  /// Decodes [bytes] for a viewport whose longest edge is [viewportLongestEdge]
  /// logical pixels.
  ///
  /// Throws [ImageDecodeException] when no decode succeeds.
  Future<ui.Image> decode(
    Uint8List bytes, {
    required String path,
    required int viewportLongestEdge,
    required double devicePixelRatio,
  }) async {
    final dimensions = await _dimensions(bytes, path);

    if (ImageDecodePolicy.shouldUseNaturalSize(
      dimensions.width,
      dimensions.height,
    )) {
      try {
        // Full resolution: no target size is passed, so the engine produces
        // every original pixel.
        return await _decodeWith(bytes, path: path);
      } catch (error) {
        // Some devices cannot hold a full-resolution frame (low-memory
        // Android). Fall back to the largest bounded decode rather than
        // showing nothing at all.
        final width = ImageDecodePolicy.boundedTargetWidth(
          width: dimensions.width,
          height: dimensions.height,
          viewportLongestEdge: viewportLongestEdge,
          devicePixelRatio: devicePixelRatio,
        );
        try {
          return await _decodeWith(bytes, path: path, targetWidth: width);
        } catch (_) {
          throw ImageDecodeException(path, error);
        }
      }
    }

    final width = ImageDecodePolicy.boundedTargetWidth(
      width: dimensions.width,
      height: dimensions.height,
      viewportLongestEdge: viewportLongestEdge,
      devicePixelRatio: devicePixelRatio,
    );
    try {
      return await _decodeWith(bytes, path: path, targetWidth: width);
    } catch (error) {
      throw ImageDecodeException(path, error);
    }
  }

  /// Reads the encoded dimensions without decoding any pixels.
  Future<({int width, int height})> _dimensions(
    Uint8List bytes,
    String path,
  ) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      return (width: descriptor.width, height: descriptor.height);
    } catch (error) {
      throw ImageDecodeException(path, error);
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  Future<ui.Image> _decodeWith(
    Uint8List bytes, {
    required String path,
    int? targetWidth,
  }) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      codec = targetWidth == null
          // Natural size: no targetWidth/height, so no resampling at all.
          ? await descriptor.instantiateCodec()
          : await descriptor.instantiateCodec(targetWidth: targetWidth);
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}
