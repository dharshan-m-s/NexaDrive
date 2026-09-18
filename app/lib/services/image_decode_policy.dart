import 'dart:ui' as ui;

/// Pure decode decisions for the photo viewer and image widgets.
///
/// Kept separate from the widgets so every rule is unit-tested: these choices
/// are what make a photo look sharp (or soft), and getting one wrong is
/// invisible in code review but obvious on a phone.
abstract final class ImageDecodePolicy {
  /// Photos up to this many pixels are decoded at their natural size, so every
  /// original pixel reaches the GPU. A 12 MP phone photo is ~12 M pixels and a
  /// 4000x3000 upload is 12 M, so normal photos always take the full-quality
  /// path.
  static const int maxNaturalPixels = 24 * 1000 * 1000;

  /// Lowest long edge a bounded (non-natural) decode will ever target. 4096
  /// keeps the image at least 4K on its long edge, which is 1:1 or better on
  /// any phone or desktop display and still sharp when pinched to 2x.
  static const int minBoundedLongEdge = 4096;

  /// Decoded RGBA frames the viewer keeps resident for neighbouring pages.
  /// Frames are `width * height * 4` bytes, so 18 M pixels is ~72 MB, which
  /// leaves room on a low-end phone. The *visible* page is always decoded
  /// regardless of this budget; only speculative neighbours are constrained.
  static const int decodedFramePixelBudget = 18 * 1000 * 1000;

  /// True when the source can be decoded at 1:1 without risking an out-of-
  /// memory failure on a low-end device.
  static bool shouldUseNaturalSize(int width, int height) {
    if (width <= 0 || height <= 0) return true;
    return width * height <= maxNaturalPixels;
  }

  /// Width to hand to `instantiateCodec` for a bounded decode.
  ///
  /// Derived from the source's long edge so the aspect ratio is preserved by
  /// the engine, and never larger than the source itself (upscaling a photo
  /// wastes memory and adds nothing).
  static int boundedTargetWidth({
    required int width,
    required int height,
    required int viewportLongestEdge,
    required double devicePixelRatio,
  }) {
    if (width <= 0 || height <= 0) return 0;
    final sourceLongest = width >= height ? width : height;

    // Aim for twice the viewport's physical long edge: pinching to 2x still
    // shows real pixels, and everything beyond that is beyond what the panel
    // can resolve anyway.
    final viewportPhysical =
        (viewportLongestEdge * (devicePixelRatio <= 0 ? 1 : devicePixelRatio))
            .round();
    final wanted = viewportPhysical * 2;
    final targetLongest =
        wanted < minBoundedLongEdge ? minBoundedLongEdge : wanted;

    if (targetLongest >= sourceLongest) return width;
    return width >= height
        ? targetLongest
        : ((width * targetLongest) / sourceLongest).round().clamp(1, width);
  }

  /// Filter quality for the current on-screen scale.
  ///
  /// Flutter maps [ui.FilterQuality.high] to Skia's bicubic sampler, which has
  /// **no mipmaps**: minifying a 4000 px photo into a 400 px viewport with it
  /// aliases and reads as soft. [ui.FilterQuality.medium] is mipmapped bilinear
  /// and is the correct choice while downscaling. Once the image is at or above
  /// 1:1, bicubic is the sharper sampler.
  static ui.FilterQuality filterQualityForScale(double scale) {
    if (scale.isNaN || scale <= 0) return ui.FilterQuality.medium;
    return scale < 0.95 ? ui.FilterQuality.medium : ui.FilterQuality.high;
  }

  /// Whether a neighbouring page's decoded frame may stay resident alongside
  /// the visible one.
  static bool canKeepDecodedFrame({
    required int pixels,
    required int currentlyHeldPixels,
  }) {
    if (pixels <= 0) return false;
    return currentlyHeldPixels + pixels <= decodedFramePixelBudget;
  }
}
