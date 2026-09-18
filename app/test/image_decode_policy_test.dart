import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:nexadrive/services/api.dart';
import 'package:nexadrive/services/image_decode_policy.dart';
import 'package:nexadrive/services/image_decoder.dart';
import 'package:nexadrive/services/image_pipeline.dart';
import 'package:nexadrive/services/session.dart';
import 'package:nexadrive/ui/screens/photos/photo_viewer.dart';

/// Decode-path regression tests.
///
/// The symptom these lock down: opening a photo showed a *blurred* image
/// instead of the photo. Two independent causes had to be fixed:
///
/// 1. **A swallowed decode failure.** The old viewer's `_decode` returned
///    `null` on failure and removed the error entry, so a photo the local
///    codec could not render left the viewer sitting on the loading
///    placeholder — a dimmed grid thumbnail behind a spinner. That is
///    indistinguishable from "the viewer is showing me a blurry image".
///    A failure must now surface an explicit error with Retry.
/// 2. **Sampler choice.** `FilterQuality.high` is Skia's *bicubic* sampler,
///    which has no mipmaps; minifying a multi-megapixel photo into a phone
///    viewport with it aliases and reads as soft. Downscaling must use the
///    mipmapped sampler.
///
/// Both are pinned below, plus the "decode at natural size" guarantee that
/// makes zoom reveal real pixels.
///
/// A photo descriptor as the server's listing returns it.
Map<String, dynamic> viewerPhoto({
  String path = 'Camera/broken.jpg',
  int size = 4096,
}) =>
    {
      'name': path.split('/').last,
      'path': path,
      'type': 'file',
      'size': size,
      'modified_at': '2026-09-16T10:00:00Z',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ImageDecodePolicy: photos are decoded at full resolution', () {
    test('a normal phone photo is decoded at its natural size', () {
      // 4032x3024 = 12.2 MP, the standard iPhone/Android camera output.
      expect(ImageDecodePolicy.shouldUseNaturalSize(4032, 3024), isTrue);
      // 4000x3000 = 12 MP.
      expect(ImageDecodePolicy.shouldUseNaturalSize(4000, 3000), isTrue);
      // Tiny images are obviously fine too.
      expect(ImageDecodePolicy.shouldUseNaturalSize(640, 480), isTrue);
    });

    test('only genuinely huge photos take the bounded path', () {
      // The limit is 24 MP, so a 24 MP photo still decodes at natural size.
      expect(ImageDecodePolicy.shouldUseNaturalSize(6000, 4000), isTrue);
      // 28 MP is past the limit; 108 MP is far past it.
      expect(ImageDecodePolicy.shouldUseNaturalSize(7000, 4000), isFalse);
      expect(ImageDecodePolicy.shouldUseNaturalSize(12000, 9000), isFalse);
    });

    test('unknown dimensions do not force a downscale', () {
      expect(ImageDecodePolicy.shouldUseNaturalSize(0, 0), isTrue);
    });

    test('a bounded decode never upscales and never drops below 4K', () {
      // A 108 MP photo viewed on a 1080p phone: the bounded target must still
      // be at least 4096 on the long edge, not the 1080 the screen could show.
      final width = ImageDecodePolicy.boundedTargetWidth(
        width: 12000,
        height: 9000,
        viewportLongestEdge: 900,
        devicePixelRatio: 2.75,
      );
      expect(width, greaterThanOrEqualTo(4096));
      expect(width, lessThanOrEqualTo(12000));

      // Portrait sources keep their orientation and stay proportional.
      final portrait = ImageDecodePolicy.boundedTargetWidth(
        width: 9000,
        height: 12000,
        viewportLongestEdge: 900,
        devicePixelRatio: 2.75,
      );
      expect(portrait, lessThan(9000));
      // The *long* edge (height) is the one the policy targets, so recover it
      // from the returned width and check it is still at least 4K.
      final portraitLongEdge = portrait * (12000 / 9000);
      expect(portraitLongEdge, greaterThanOrEqualTo(4096));
      expect(portraitLongEdge, lessThanOrEqualTo(12000));
    });

    test('a source smaller than the target is returned untouched', () {
      expect(
        ImageDecodePolicy.boundedTargetWidth(
          width: 1600,
          height: 1200,
          viewportLongestEdge: 1000,
          devicePixelRatio: 3,
        ),
        1600,
      );
    });
  });

  group('ImageDecodePolicy: the sampler never softens a downscaled photo', () {
    test('minifying uses the mipmapped sampler, not bicubic', () {
      // This is the actual blur fix. Flutter maps `high` to Skia's bicubic
      // sampler which has NO mipmaps: shrinking 4032px into 400px with it
      // aliases badly and looks soft. `medium` is mipmapped bilinear.
      expect(
        ImageDecodePolicy.filterQualityForScale(0.1),
        FilterQuality.medium,
      );
      expect(
        ImageDecodePolicy.filterQualityForScale(0.5),
        FilterQuality.medium,
      );
      expect(
        ImageDecodePolicy.filterQualityForScale(0.94),
        FilterQuality.medium,
      );
      // Displayed at or above 1:1, bicubic is the sharper sampler.
      expect(ImageDecodePolicy.filterQualityForScale(1.0), FilterQuality.high);
      expect(ImageDecodePolicy.filterQualityForScale(3.0), FilterQuality.high);
    });

    test('a degenerate scale falls back to the safe sampler', () {
      expect(ImageDecodePolicy.filterQualityForScale(0), FilterQuality.medium);
      expect(ImageDecodePolicy.filterQualityForScale(-1), FilterQuality.medium);
      expect(
        ImageDecodePolicy.filterQualityForScale(double.nan),
        FilterQuality.medium,
      );
    });
  });

  group('ImageDecodePolicy: decoded frames are bounded', () {
    test('neighbours are dropped once the pixel budget is spent', () {
      expect(
        ImageDecodePolicy.canKeepDecodedFrame(
          pixels: 12 * 1000 * 1000,
          currentlyHeldPixels: 0,
        ),
        isTrue,
      );
      expect(
        ImageDecodePolicy.canKeepDecodedFrame(
          pixels: 12 * 1000 * 1000,
          currentlyHeldPixels: 12 * 1000 * 1000,
        ),
        isFalse,
      );
    });

    test('the budget leaves headroom on a low-end phone', () {
      // 18 MP x 4 bytes = ~72 MB of decoded frames, on top of the byte caches.
      expect(
        ImageDecodePolicy.decodedFramePixelBudget * 4,
        lessThan(96 * 1024 * 1024),
      );
    });
  });

  group('ImageDecoder: original pixels reach the GPU', () {
    late Uint8List jpeg1600;

    setUpAll(() {
      final source = img.Image(width: 1600, height: 1200);
      for (var y = 0; y < 1200; y++) {
        for (var x = 0; x < 1600; x++) {
          source.setPixelRgb(x, y, x * 255 ~/ 1600, y * 255 ~/ 1200, 128);
        }
      }
      jpeg1600 = Uint8List.fromList(img.encodeJpg(source, quality: 95));
    });

    test('decodes at natural size even when the viewport is much smaller',
        () async {
      const decoder = ImageDecoder();
      // A small phone viewport must NOT shrink the decode: the photo still
      // carries 1600x1200 pixels so pinching in shows real texture.
      final image = await decoder.decode(
        jpeg1600,
        path: 'Camera/a.jpg',
        viewportLongestEdge: 640,
        devicePixelRatio: 2,
      );
      addTearDown(image.dispose);
      expect(image.width, 1600);
      expect(image.height, 1200);
      expect(image.width * image.height, 1920000);
    });

    test(
        'a genuinely huge photo degrades to a large bounded size, not a thumbnail',
        () async {
      const decoder = ImageDecoder();
      // 25 MP > the 24 MP natural limit, so the bounded path runs.
      final huge = img.Image(width: 5000, height: 5000);
      img.fill(huge, color: img.ColorRgb8(30, 90, 160));
      final bytes = Uint8List.fromList(img.encodePng(huge));

      final image = await decoder.decode(
        bytes,
        path: 'Camera/huge.png',
        viewportLongestEdge: 900,
        devicePixelRatio: 2.75,
      );
      addTearDown(image.dispose);

      expect(image.width, lessThanOrEqualTo(5000));
      expect(
        image.width,
        greaterThanOrEqualTo(4096),
        reason: 'a bounded decode must stay at least 4K, never a thumbnail',
      );
      expect(image.height / image.width, closeTo(1.0, 0.01));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('undecodable bytes raise a typed error instead of returning null',
        () async {
      const decoder = ImageDecoder();
      final garbage =
          Uint8List.fromList(List<int>.generate(2048, (i) => i % 251));
      await expectLater(
        decoder.decode(
          garbage,
          path: 'Camera/broken.jpg',
          viewportLongestEdge: 400,
          devicePixelRatio: 1,
        ),
        throwsA(isA<ImageDecodeException>()),
      );
    });
  });

  group('the viewer never gets stuck on a blurred placeholder', () {
    /// Serves bytes that are NOT a decodable image while still returning 200,
    /// exactly like a stored file the local codec cannot render.
    Api apiReturningUndecodableBytes(Session session) {
      final garbage =
          Uint8List.fromList(List<int>.generate(4096, (i) => (i * 7) % 256));
      return Api(
        session,
        client: MockClient((request) async {
          return http.Response.bytes(
            garbage,
            200,
            headers: {'content-type': 'application/octet-stream'},
          );
        }),
      );
    }

    testWidgets('an undecodable original shows an error with Retry, not a blur',
        (tester) async {
      final session = Session()
        ..serverUrl = 'https://cloud.example.test'
        ..username = 'tester'
        ..token = 't';
      final api = apiReturningUndecodableBytes(session);
      // A grid thumbnail IS available: the old code dimmed it behind a spinner
      // and then never replaced it, which is what "blurry image instead of the
      // photo" looked like on device.
      final thumb = Uint8List.fromList(
        img.encodeJpg(img.Image(width: 64, height: 48), quality: 80),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PhotoViewer(
            photos: [viewerPhoto()],
            initialIndex: 0,
            api: api,
            images: ImageRepository(api),
            thumbnailLookup: (_) => thumb,
          ),
        ),
      );

      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // The failure is reported, and it is actionable.
      expect(find.text('Can\u2019t open this photo'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      // Crucially, the spinner is gone: the viewer is not still "loading".
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Retry re-attempts the fetch instead of giving up permanently',
        (tester) async {
      final session = Session()
        ..serverUrl = 'https://cloud.example.test'
        ..username = 'tester'
        ..token = 't';
      var requests = 0;
      final garbage =
          Uint8List.fromList(List<int>.generate(4096, (i) => (i * 7) % 256));
      final api = Api(
        session,
        client: MockClient((request) async {
          requests++;
          return http.Response.bytes(
            garbage,
            200,
            headers: {'content-type': 'application/octet-stream'},
          );
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PhotoViewer(
            photos: [viewerPhoto()],
            initialIndex: 0,
            api: api,
            images: ImageRepository(api),
          ),
        ),
      );
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Retry'), findsOneWidget);
      final before = requests;

      await tester.tap(find.text('Retry'));
      await tester.pump();
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(requests, greaterThan(before));
      // Still reported honestly rather than silently blank.
      expect(find.text('Can\u2019t open this photo'), findsOneWidget);
    });

    testWidgets(
        'the loading placeholder is a blurred preview that is then replaced',
        (tester) async {
      final session = Session()
        ..serverUrl = 'https://cloud.example.test'
        ..username = 'tester'
        ..token = 't';
      final source = img.Image(width: 1600, height: 1200);
      img.fill(source, color: img.ColorRgb8(20, 120, 200));
      final original = Uint8List.fromList(img.encodeJpg(source, quality: 95));
      final api = Api(
        session,
        client: MockClient((request) async => http.Response.bytes(
              original,
              200,
              headers: {'content-type': 'image/jpeg'},
            )),
      );
      final thumb = Uint8List.fromList(
        img.encodeJpg(img.Image(width: 64, height: 48), quality: 80),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PhotoViewer(
            photos: [
              viewerPhoto(path: 'Camera/slow.jpg', size: original.length),
            ],
            initialIndex: 0,
            api: api,
            images: ImageRepository(api),
            thumbnailLookup: (_) => thumb,
          ),
        ),
      );
      await tester.pump();

      // While loading, the grid thumbnail is drawn BLURRED behind a progress
      // indicator, so a sharp-but-small preview can never be mistaken for the
      // photo and there is no mistaking the state for "done".
      expect(find.byType(ImageFiltered), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);

      // ...and the placeholder is genuinely temporary: the original replaces
      // it. This is the assertion that would have caught the stuck-blur bug.
      //
      // The download and the engine-side decode complete on the real event
      // loop, so they need `runAsync` rather than the fake clock.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump();

      expect(find.byType(ImageFiltered), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(RawImage), findsOneWidget);
    });
  });
}
