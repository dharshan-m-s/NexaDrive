import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:nexadrive/services/api.dart';
import 'package:nexadrive/services/image_pipeline.dart';
import 'package:nexadrive/services/session.dart';
import 'package:nexadrive/ui/screens/photos/photo_viewer.dart';

/// NexaDrive image-quality regression suite.
///
/// This file exists because the application once displayed blurred photos:
/// the viewer rendered a server thumbnail (or a downscaled decode) instead of
/// the original pixels. Every assertion below pins one link of the chain
/// UPLOAD -> STORAGE -> THUMBNAIL -> GRID -> VIEWER -> DECODE -> RENDER.
///
/// If a future change makes the viewer request, cache, or decode anything
/// other than the original bytes, these tests fail.
const int kOriginalWidth = 1600;
const int kOriginalHeight = 1200;
const int kThumbnailMaxEdge = 512;

/// Account namespace the test session signs in as: the API keys caches by
/// server URL **and** account, so the assertion keys must match.
const String kNamespace = 'https://cloud.example.test#tester';

/// A deterministic, high-entropy image. Real pixel variance matters: a flat
/// colour would make a "blurry" bug invisible.
img.Image buildTestImage({int width = kOriginalWidth, int height = kOriginalHeight}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final r = (x * 255 ~/ width);
      final g = (y * 255 ~/ height);
      final b = ((x ~/ 16 + y ~/ 16).isEven) ? 200 : 60;
      image.setPixelRgb(x, y, r, g, b);
    }
  }
  return image;
}

/// Mimics the server's thumbnail endpoint: longest edge clamped to 512,
/// re-encoded as JPEG. Deliberately lossy and small so the test can prove the
/// viewer never gets these bytes.
Uint8List serverThumbnail(Uint8List originalBytes) {
  final decoded = img.decodeImage(originalBytes);
  if (decoded == null) throw StateError('test fixture is not decodable');
  final thumb = decoded.width >= decoded.height
      ? img.copyResize(decoded, width: kThumbnailMaxEdge, interpolation: img.Interpolation.average)
      : img.copyResize(decoded, height: kThumbnailMaxEdge, interpolation: img.Interpolation.average);
  return img.encodeJpg(thumb, quality: 84);
}

/// Records which endpoints were hit so a test can assert the viewer never
/// touched the thumbnail endpoint (and vice versa).
class _RecordingApi {
  final List<String> hits = <String>[];

  int get downloadCount => hits.where((h) => h == 'download').length;
  int get thumbnailCount => hits.where((h) => h == 'thumbnail').length;

  Api build({
    required Uint8List originalBytes,
    Uint8List? thumbnailBytes,
    int thumbnailStatus = 200,
    Map<String, dynamic>? entryOverride,
  }) {
    final session = Session()
      ..serverUrl = 'https://cloud.example.test'
      ..username = 'tester'
      ..token = 'test-token';

    final client = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/api/files/download')) {
        hits.add('download');
        return http.Response.bytes(
          originalBytes,
          200,
          headers: {'content-type': 'application/octet-stream'},
        );
      }
      if (path.endsWith('/api/files/thumbnail')) {
        hits.add('thumbnail');
        if (thumbnailStatus != 200 || thumbnailBytes == null) {
          return http.Response(
            '{"error":"Thumbnail not available"}',
            thumbnailStatus,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response.bytes(
          thumbnailBytes,
          200,
          headers: {'content-type': 'image/jpeg'},
        );
      }
      return http.Response('{"error":"not found"}', 404);
    });

    return Api(session, client: client);
  }
}

Map<String, dynamic> photoEntry({int size = 500000, String modified = '2026-09-16T10:00:00Z'}) => {
      'name': 'photo.jpg',
      'path': 'Camera/photo.jpg',
      'type': 'file',
      'size': size,
      'modified_at': modified,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late img.Image source;
  late Uint8List jpegBytes;
  late Uint8List pngBytes;
  late Uint8List webpBytes;
  late Uint8List jpegThumbBytes;

  setUpAll(() {
    source = buildTestImage();
    jpegBytes = img.encodeJpg(source, quality: 95);
    pngBytes = Uint8List.fromList(img.encodePng(source));
    webpBytes = Uint8List.fromList(img.encodeWebP(source));
    jpegThumbBytes = serverThumbnail(jpegBytes);
  });

  group('fixtures are genuinely high resolution', () {
    test('the encoded original decodes at full size', () {
      for (final bytes in [jpegBytes, pngBytes, webpBytes]) {
        final decoded = img.decodeImage(bytes);
        expect(decoded, isNotNull);
        expect(decoded!.width, kOriginalWidth);
        expect(decoded.height, kOriginalHeight);
      }
    });

    test('the server thumbnail is strictly smaller than the original', () {
      final thumb = img.decodeImage(jpegThumbBytes);
      expect(thumb, isNotNull);
      expect(thumb!.width, lessThan(kOriginalWidth));
      expect(thumb.height, lessThan(kOriginalHeight));
      expect(thumb.width, lessThanOrEqualTo(kThumbnailMaxEdge));
      expect(jpegThumbBytes.length, lessThan(jpegBytes.length));
    });
  });

  group('ImageKey keeps the two renditions in disjoint key spaces', () {
    test('thumbnail and original keys are never equal', () {
      final original = ImageRepository.keyFor(
        photoEntry(),
        namespace: 'https://a',
        rendition: ImageRendition.original,
      );
      final thumb = ImageRepository.keyFor(
        photoEntry(),
        namespace: 'https://a',
        rendition: ImageRendition.thumbnail,
      );
      expect(original, isNot(equals(thumb)));
      expect(original.hashCode, isNot(equals(thumb.hashCode)));
    });

    test('a different file fingerprint is a different key', () {
      final a = ImageRepository.keyFor(
        photoEntry(modified: '2026-09-16T10:00:00Z'),
        namespace: 'https://a',
        rendition: ImageRendition.original,
      );
      final b = ImageRepository.keyFor(
        photoEntry(modified: '2026-09-17T10:00:00Z'),
        namespace: 'https://a',
        rendition: ImageRendition.original,
      );
      expect(a, isNot(equals(b)));
    });

    test('a different server is a different key', () {
      final a = ImageRepository.keyFor(
        photoEntry(),
        namespace: 'https://a',
        rendition: ImageRendition.original,
      );
      final b = ImageRepository.keyFor(
        photoEntry(),
        namespace: 'https://b',
        rendition: ImageRendition.original,
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('original bytes are preserved exactly', () {
    for (final format in const ['JPEG', 'PNG', 'WebP']) {
      test('$format survives the pipeline byte-for-byte', () async {
        final bytes = switch (format) {
          'JPEG' => jpegBytes,
          'PNG' => pngBytes,
          _ => webpBytes,
        };
        final recorder = _RecordingApi();
        final api = recorder.build(originalBytes: bytes);
        final repo = ImageRepository(api);

        final key = ImageRepository.keyFor(
          photoEntry(size: bytes.length),
          namespace: kNamespace,
          rendition: ImageRendition.original,
        );
        final data = await repo.original(key);

        // Byte-for-byte identical: no recompression, no downscale.
        expect(data.bytes.length, bytes.length);
        expect(data.bytes, equals(bytes));

        // And it still decodes at the original resolution.
        final decoded = img.decodeImage(data.bytes);
        expect(decoded!.width, kOriginalWidth);
        expect(decoded.height, kOriginalHeight);

        // Only the download endpoint was consulted.
        expect(recorder.downloadCount, 1);
        expect(recorder.thumbnailCount, 0);
      });
    }

    test('a re-fetch after cache eviction still returns the original', () async {
      final recorder = _RecordingApi();
      final api = recorder.build(originalBytes: jpegBytes);
      final repo = ImageRepository(api, maxOriginalEntries: 1);
      final key = ImageRepository.keyFor(
        photoEntry(size: jpegBytes.length),
        namespace: kNamespace,
        rendition: ImageRendition.original,
      );
      await repo.original(key);
      // Push the entry out of the bounded cache, then reload it.
      await repo.original(key.copyWithPath('Camera/other.jpg'));
      expect(repo.peekOriginal(key), isNull);
      final again = await repo.original(key);
      expect(again.bytes, equals(jpegBytes));
      expect(recorder.thumbnailCount, 0);
    });
  });

  group('thumbnails and originals never cross over', () {
    test('the thumbnail comes from the thumbnail endpoint only', () async {
      final recorder = _RecordingApi();
      final api = recorder.build(
        originalBytes: jpegBytes,
        thumbnailBytes: jpegThumbBytes,
      );
      final repo = ImageRepository(api);
      final key = ImageRepository.keyFor(
        photoEntry(size: jpegBytes.length),
        namespace: kNamespace,
        rendition: ImageRendition.thumbnail,
        maxEdge: kThumbnailMaxEdge,
      );

      final data = await repo.thumbnail(key, max: kThumbnailMaxEdge);
      expect(data.bytes, equals(jpegThumbBytes));
      expect(data.isOriginal, isFalse);
      expect(recorder.thumbnailCount, 1);
      expect(recorder.downloadCount, 0);
    });

    test('with BOTH renditions cached, the original request returns the '
        'original bytes (the exact blur regression)', () async {
      final recorder = _RecordingApi();
      final api = recorder.build(
        originalBytes: jpegBytes,
        thumbnailBytes: jpegThumbBytes,
      );
      final repo = ImageRepository(api);
      final originalKey = ImageRepository.keyFor(
        photoEntry(size: jpegBytes.length),
        namespace: kNamespace,
        rendition: ImageRendition.original,
      );
      final thumbKey = ImageRepository.keyFor(
        photoEntry(size: jpegBytes.length),
        namespace: kNamespace,
        rendition: ImageRendition.thumbnail,
        maxEdge: kThumbnailMaxEdge,
      );

      // Warm the thumbnail cache FIRST, exactly like scrolling the grid does.
      await repo.thumbnail(thumbKey, max: kThumbnailMaxEdge);
      expect(repo.peekThumbnail(thumbKey), equals(jpegThumbBytes));

      final original = await repo.original(originalKey);
      expect(original.bytes, equals(jpegBytes));
      expect(original.bytes, isNot(equals(jpegThumbBytes)));
      expect(original.isOriginal, isTrue);

      // The original cache never holds the thumbnail, and vice versa.
      expect(repo.peekOriginal(originalKey), equals(jpegBytes));
      expect(repo.peekOriginal(originalKey), isNot(equals(jpegThumbBytes)));
      expect(repo.peekThumbnail(thumbKey), isNot(equals(jpegBytes)));
    });

    test('an unsupported format fails gracefully instead of substituting', () async {
      final recorder = _RecordingApi();
      final api = recorder.build(originalBytes: jpegBytes, thumbnailStatus: 415);
      final repo = ImageRepository(api);
      final key = ImageRepository.keyFor(
        photoEntry(),
        namespace: kNamespace,
        rendition: ImageRendition.thumbnail,
      );
      await expectLater(
        repo.thumbnail(key),
        throwsA(isA<ThumbnailUnavailable>()),
      );
      // No silent fallback to the original download.
      expect(recorder.downloadCount, 0);
      expect(repo.hasFailed(key), isTrue);
    });
  });

  group('caches are bounded', () {
    ImageKey originalKeyFor(String path) => ImageKey(
          namespace: kNamespace,
          path: path,
          rendition: ImageRendition.original,
        );

    ImageKey thumbKeyFor(String path) => ImageKey(
          namespace: kNamespace,
          path: path,
          rendition: ImageRendition.thumbnail,
          maxEdge: kThumbnailMaxEdge,
        );

    test('originals respect the byte budget', () async {
      final recorder = _RecordingApi();
      final api = recorder.build(originalBytes: jpegBytes);
      final repo = ImageRepository(
        api,
        maxOriginalBytes: jpegBytes.length,
        maxOriginalEntries: 64,
      );

      for (var i = 0; i < 6; i++) {
        await repo.original(originalKeyFor('Camera/$i.jpg'));
      }
      // Never more than a couple of images' worth once the budget is exceeded.
      expect(repo.memoryBytes, lessThanOrEqualTo(jpegBytes.length * 2));
      expect(repo.peekOriginal(originalKeyFor('Camera/0.jpg')), isNull);
      expect(
        repo.peekOriginal(originalKeyFor('Camera/5.jpg')),
        isNotNull,
        reason: 'the most recently used entry must survive eviction',
      );
    });

    test('thumbnails respect the entry ceiling', () async {
      final recorder = _RecordingApi();
      final api = recorder.build(
        originalBytes: jpegBytes,
        thumbnailBytes: jpegThumbBytes,
      );
      final repo = ImageRepository(
        api,
        maxThumbEntries: 4,
        maxThumbBytes: 64 * 1024 * 1024,
      );
      for (var i = 0; i < 10; i++) {
        await repo.thumbnail(thumbKeyFor('Camera/$i.jpg'), max: kThumbnailMaxEdge);
      }
      var hits = 0;
      for (var i = 0; i < 10; i++) {
        if (repo.peekThumbnail(thumbKeyFor('Camera/$i.jpg')) != null) hits++;
      }
      expect(hits, lessThanOrEqualTo(4));
    });
  });

  group('the photo viewer requests originals, never thumbnails', () {
    testWidgets('viewer fetches /api/files/download and not the thumbnail endpoint',
        (tester) async {
      final recorder = _RecordingApi();
      final api = recorder.build(
        originalBytes: jpegBytes,
        thumbnailBytes: jpegThumbBytes,
      );
      final repo = ImageRepository(api);
      final entry = photoEntry(size: jpegBytes.length);

      await tester.pumpWidget(
        MaterialApp(
          home: PhotoViewer(
            photos: [entry],
            initialIndex: 0,
            api: api,
            images: repo,
            // A grid thumbnail is offered; the viewer must still load the
            // original for display and only use this as a placeholder.
            thumbnailLookup: (_) => jpegThumbBytes,
          ),
        ),
      );

      // Let the fetch and decode complete.
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(recorder.downloadCount, greaterThanOrEqualTo(1));
      expect(recorder.thumbnailCount, 0);

      final originalKey = ImageRepository.keyFor(
        entry,
        namespace: kNamespace,
        rendition: ImageRendition.original,
      );
      expect(repo.peekOriginal(originalKey), equals(jpegBytes));
      expect(find.text('1 of 1'), findsOneWidget);
    });

    testWidgets('viewer surfaces a retryable error instead of a blank frame',
        (tester) async {
      final session = Session()
        ..serverUrl = 'https://cloud.example.test'
        ..token = 't';
      var attempts = 0;
      final api = Api(
        session,
        client: MockClient((request) async {
          attempts++;
          return http.Response(
            jsonEncode({'error': 'The file is gone'}),
            404,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PhotoViewer(
            photos: [photoEntry()],
            initialIndex: 0,
            api: api,
            images: ImageRepository(api),
          ),
        ),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.text('Can\u2019t open this photo'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(attempts, greaterThanOrEqualTo(1));
    });
  });
}
