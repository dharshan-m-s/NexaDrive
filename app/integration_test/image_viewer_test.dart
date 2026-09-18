import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nexadrive/services/api.dart';
import 'package:nexadrive/services/image_decode_policy.dart';
import 'package:nexadrive/services/image_decoder.dart';
import 'package:nexadrive/services/image_pipeline.dart';
import 'package:nexadrive/services/session.dart';
import 'package:nexadrive/ui/screens/photos/photo_viewer.dart';

/// On-device verification of the photo pipeline, run against the phone's real
/// image codecs rather than the host's.
///
/// The reported bug was "photos look blurry instead of showing". The fixes are
/// unit-tested on the host, but the decode itself is done by the engine, and
/// the engine differs per platform (Impeller on Android). This test therefore
/// runs on the device and asserts the two things a user actually sees:
///
///   1. a large original is decoded at its natural size, not downscaled to the
///      viewport;
///   2. the viewer renders those ORIGINAL pixels, and never touches the
///      thumbnail endpoint.
///
/// It needs no live server: a loopback HTTP server inside the test provides the
/// bytes, exactly as `/api/files/download` and `/api/files/thumbnail` would.
///
/// Run with a device attached:
///
/// ```sh
/// flutter test integration_test/image_viewer_test.dart -d <device-id>
/// ```
const int kOriginalWidth = 3200;
const int kOriginalHeight = 2400;
const int kThumbWidth = 64;
const int kThumbHeight = 48;

/// Authors a real PNG of the requested size using the engine itself, so the
/// test needs no image package and no fixture on disk. The pattern is
/// high-frequency on purpose: a downscaled decode would blur it visibly.
Future<Uint8List> authorPng(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint();
  final full = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
  canvas.drawRect(full, paint..color = const Color(0xFF1B2A3A));
  const stripe = 24;
  for (var x = 0; x < width; x += stripe * 2) {
    paint.color = (x ~/ stripe).isEven
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF0A0F14);
    canvas.drawRect(
      Rect.fromLTWH(x.toDouble(), 0, stripe.toDouble(), height.toDouble()),
      paint,
    );
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  if (data == null) throw StateError('could not author the test image');
  return data.buffer.asUint8List();
}

/// Serves the two image endpoints on loopback and records which were used.
class _FakeServer {
  _FakeServer(this.original, this.thumbnail);

  final Uint8List original;
  final Uint8List thumbnail;
  late final HttpServer _server;
  int downloadHits = 0;
  int thumbnailHits = 0;

  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((request) {
      final path = request.uri.path;
      if (path.endsWith('/api/files/download')) {
        downloadHits++;
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType('image', 'png')
          ..headers.contentLength = original.length;
        request.response.add(original);
      } else if (path.endsWith('/api/files/thumbnail')) {
        thumbnailHits++;
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType('image', 'png');
        request.response.add(thumbnail);
      } else {
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write('[]');
      }
      unawaited(request.response.close());
    });
  }

  Future<void> stop() => _server.close(force: true);
}

/// A photo descriptor as the server's listing returns it.
Map<String, dynamic> photo(String path, int size) => {
      'name': path.split('/').last,
      'path': path,
      'type': 'file',
      'size': size,
      'modified_at': '2026-09-17T10:00:00Z',
    };

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List originalPng;
  late Uint8List thumbnailPng;

  setUpAll(() async {
    originalPng = await authorPng(kOriginalWidth, kOriginalHeight);
    thumbnailPng = await authorPng(kThumbWidth, kThumbHeight);
  });

  testWidgets('the device decodes a large photo at its natural size', (tester) async {
    const decoder = ImageDecoder();
    // A small viewport must NOT shrink the decode: zooming in has to reveal
    // real pixels, which is only possible if the frame keeps its full size.
    final image = await decoder.decode(
      originalPng,
      path: 'Camera/device-test.png',
      viewportLongestEdge: 640,
      devicePixelRatio: 1.0,
    );
    addTearDown(image.dispose);
    expect(image.width, kOriginalWidth);
    expect(image.height, kOriginalHeight);

    // And the photos the policy also allows must never be shrunk to a preview.
    expect(
      ImageDecodePolicy.shouldUseNaturalSize(kOriginalWidth, kOriginalHeight),
      isTrue,
    );
  });

  testWidgets('the viewer renders the ORIGINAL, never the thumbnail',
      (tester) async {
    final server = _FakeServer(originalPng, thumbnailPng);
    await server.start();
    addTearDown(server.stop);

    final session = Session()
      ..serverUrl = server.baseUrl
      ..username = 'device-tester'
      ..token = 'device-token';
    final api = Api(session);
    final images = ImageRepository(api);

    await tester.pumpWidget(
      MaterialApp(
        home: PhotoViewer(
          photos: [photo('Camera/device-test.png', originalPng.length)],
          initialIndex: 0,
          api: api,
          images: images,
          // A grid thumbnail is offered; it may only ever be the placeholder.
          thumbnailLookup: (_) => thumbnailPng,
        ),
      ),
    );

    // Let the download and the engine-side decode finish.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(
      find.text('Can\u2019t open this photo'),
      findsNothing,
      reason: 'the original must decode on this device',
    );
    expect(server.downloadHits, greaterThanOrEqualTo(1));
    expect(
      server.thumbnailHits,
      0,
      reason: 'the viewer must never fetch a thumbnail',
    );

    // The strongest assertion available: the frame actually on screen carries
    // the original's pixel dimensions. Exactly one image is on screen, so this
    // cannot accidentally match the placeholder's thumbnail.
    expect(find.byType(RawImage), findsOneWidget);
    final raw = tester.widget<RawImage>(find.byType(RawImage));
    expect(raw.image, isNotNull);
    expect(raw.image!.width, kOriginalWidth);
    expect(raw.image!.height, kOriginalHeight);
  });

  testWidgets('an unrenderable original is reported, not left as a blur',
      (tester) async {
    final server = _FakeServer(
      // Bytes that are not an image at all.
      Uint8List.fromList(List<int>.generate(4096, (i) => (i * 7) % 256)),
      thumbnailPng,
    );
    await server.start();
    addTearDown(server.stop);

    final session = Session()
      ..serverUrl = server.baseUrl
      ..username = 'device-tester'
      ..token = 'device-token';
    final api = Api(session);

    await tester.pumpWidget(
      MaterialApp(
        home: PhotoViewer(
          photos: [photo('Camera/broken.jpg', 4096)],
          initialIndex: 0,
          api: api,
          images: ImageRepository(api),
          thumbnailLookup: (_) => thumbnailPng,
        ),
      ),
    );

    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // The failure is actionable: an error and a retry, not a blurred preview
    // behind a spinner that never resolves.
    expect(find.text('Can\u2019t open this photo'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
