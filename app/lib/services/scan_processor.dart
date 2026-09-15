import 'dart:ui' show Rect;
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Document scan post-processing, run entirely on the client.
///
/// Each captured photo becomes a [ScanPage]: an unmodified original plus a set
/// of non-destructive edits. Render functions produce the finished JPEG for a
/// page, and [buildPdf] assembles a multi-page PDF for upload.
class ScanPage {
  ScanPage({required this.original, required this.number});

  /// The photo as captured (already EXIF-oriented + downscaled for the UI).
  Uint8List original;

  /// 1-based page number used for ordering and the default PDF name.
  int number;

  /// Clockwise right-turn count (0..3).
  int rightTurns = 0;

  /// Normalized crop rectangle in original-image space (0..1). Null = full page.
  Rect? crop;

  /// Color / grayscale / black-and-white rendering.
  ScanFilter filter = ScanFilter.color;
}

enum ScanFilter { color, grayscale, blackAndWhite }

/// Client-side processing + PDF assembly for scanned documents.
abstract final class ScanProcessor {
  /// Quick decode to get width/height without rendering — used by the crop
  /// overlay to compute the image aspect ratio cheaply.
  static img.Image? decodeForAspect(Uint8List bytes) {
    final src = img.decodeImage(bytes);
    if (src == null) return null;
    return img.bakeOrientation(src);
  }

  /// Downscale the camera bytes for the editor while keeping the original
  /// EXIF orientation baked in, so downstream math matches what the user saw.
  static Uint8List prepareOriginal(Uint8List bytes, {int maxEdge = 2000}) {
    final src = img.decodeImage(bytes);
    if (src == null) return bytes;
    final oriented = img.bakeOrientation(src);
    final scaled = _fit(oriented, maxEdge);
    return img.encodeJpg(scaled, quality: 90);
  }

  /// Renders the page with all edits applied.
  ///
  /// [applyCrop] can be false in the live editor so the crop box overlays the
  /// same (uncropped) image the user is adjusting.
  static Uint8List renderPage(
    ScanPage page, {
    bool applyCrop = true,
    int maxEdge = 2200,
    int quality = 88,
  }) {
    final src = img.decodeImage(page.original);
    if (src == null) return page.original;

    var image = _edited(src, page, applyCrop: applyCrop);
    image = _fit(image, maxEdge);
    return img.encodeJpg(image, quality: quality);
  }

  /// Low-res thumbnail for filmstrips and page grids.
  static Uint8List renderThumb(ScanPage page, {int maxEdge = 480}) {
    final src = img.decodeImage(page.original);
    if (src == null) return page.original;
    var image = _edited(src, page, applyCrop: true);
    image = _fit(image, maxEdge);
    return img.encodeJpg(image, quality: 78);
  }

  /// Auto-detects the content bounding box on a dark/white assumption and
  /// returns a normalized crop rect, or null if the page is already tight.
  static Rect? autoDetectCrop(ScanPage page) {
    final src = img.decodeImage(page.original);
    if (src == null) return null;
    var image = _edited(src, page, applyCrop: true);

    final w = image.width;
    final h = image.height;
    // Sample a coarse grid of luminance to find the "ink" bounding box.
    const step = 16;
    var left = w, top = h, right = 0, bottom = 0, hits = 0;

    for (var y = 0; y < h; y += step) {
      for (var x = 0; x < w; x += step) {
        final p = image.getPixel(x, y);
        final lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
        final nearWhite = lum > 236 && p.a > 0;
        if (!nearWhite) {
          if (x < left) left = x;
          if (x > right) right = x;
          if (y < top) top = y;
          if (y > bottom) bottom = y;
          hits++;
        }
      }
    }

    if (hits == 0) return null;
    // Feather so the crop never slices content at the very edge.
    const feather = 0.01;
    var l = ((left / w) - feather).clamp(0.0, 1.0);
    var t = ((top / h) - feather).clamp(0.0, 1.0);
    var r = ((right / w) + feather).clamp(0.0, 1.0);
    var b = ((bottom / h) + feather).clamp(0.0, 1.0);

    // If content already fills most of the page, don't crop at all.
    if (r - l > 0.94 && b - t > 0.94) return null;
    return Rect.fromLTRB(l, t, r, b);
  }

  static img.Image _edited(
    img.Image src,
    ScanPage page, {
    required bool applyCrop,
  }) {
    var image = img.bakeOrientation(src);

    for (var i = 0; i < (page.rightTurns % 4); i++) {
      image = img.copyRotate(image, angle: 90);
    }

    final crop = page.crop;
    if (applyCrop && crop != null && crop.width > 0.004 && crop.height > 0.004) {
      final x = (crop.left * image.width).round().clamp(0, image.width - 1);
      final y = (crop.top * image.height).round().clamp(0, image.height - 1);
      final w = math.max(1, (crop.width * image.width).round().clamp(1, image.width - x));
      final h = math.max(1, (crop.height * image.height).round().clamp(1, image.height - y));
      image = img.copyCrop(image, x: x, y: y, width: w, height: h);
    }

    switch (page.filter) {
      case ScanFilter.grayscale:
        image = img.grayscale(image);
      case ScanFilter.blackAndWhite:
        image = img.grayscale(image);
        image = img.luminanceThreshold(image, threshold: 0.55);
      case ScanFilter.color:
        break;
    }
    return image;
  }

  static img.Image _fit(img.Image image, int maxEdge) {
    final edge = math.max(image.width, image.height);
    if (edge <= maxEdge) return image;
    final s = maxEdge / edge;
    return img.copyResize(
      image,
      width: (image.width * s).round(),
      height: (image.height * s).round(),
      interpolation: img.Interpolation.average,
    );
  }

  /// Assembles [renderedPages] (final JPEGs) into a single PDF.
  static Future<Uint8List> buildPdf(List<Uint8List> renderedPages) async {
    final doc = pw.Document();
    for (final jpeg in renderedPages) {
      final decoded = img.decodeImage(jpeg);
      if (decoded == null) continue;
      final landscape = decoded.width > decoded.height;
      doc.addPage(
        pw.Page(
          pageFormat: landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(5 * PdfPageFormat.mm),
          build: (context) => pw.Center(
            child: pw.Image(
              pw.MemoryImage(jpeg),
              fit: pw.BoxFit.contain,
              alignment: pw.Alignment.center,
            ),
          ),
        ),
      );
    }
    return doc.save();
  }
}