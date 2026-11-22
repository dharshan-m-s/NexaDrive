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

/// A page swipe often has a small downward arc. The raw pointer layer must own
/// that gesture completely: the photo may advance, but the parallel vertical
/// recognizer must not also pop the viewer after a few such swipes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('five diagonal page swipes do not dismiss the viewer',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final source = img.Image(width: 24, height: 18);
    img.fill(source, color: img.ColorRgb8(120, 140, 180));
    final bytes = Uint8List.fromList(img.encodeJpg(source, quality: 85));

    final session = Session()
      ..serverUrl = 'https://cloud.example.test'
      ..username = 'tester'
      ..token = 'test-token';
    final api = Api(
      session,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/api/files/thumbnail') ||
            request.url.path.endsWith('/api/files/download')) {
          return http.Response.bytes(
            bytes,
            200,
            headers: {'content-type': 'image/jpeg'},
          );
        }
        return http.Response(
          '{"error":"not found"}',
          404,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Center(child: Text('gallery'))),
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute(
        builder: (_) => PhotoViewer(
          photos: List.generate(
            6,
            (index) => {
              'name': 'photo-$index.jpg',
              'path': 'Camera/photo-$index.jpg',
              'type': 'file',
              'size': bytes.length,
              'modified_at': '2026-11-21T10:00:00Z',
            },
          ),
          initialIndex: 0,
          api: api,
          images: ImageRepository(api),
        ),
      ),
    );
    // Image bytes and the engine-side decode finish on the real event loop.
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final controller =
        tester.widget<PageView>(find.byType(PageView)).controller!;

    for (var page = 1; page <= 5; page++) {
      final gesture = await tester.startGesture(const Offset(360, 320),
          pointer: 100 + page);
      for (var step = 1; step <= 6; step++) {
        // dx dominates so this is a page swipe, but dy exceeds the dismissal
        // distance threshold and used to pop the viewer on late vertical end.
        await gesture.moveTo(Offset(360 - step * 34, 320 + step * 24));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      // Page animation and finger-offset settle both use AppMotion.normal.
      for (var frame = 0; frame < 24; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(find.byType(PhotoViewer), findsOneWidget,
          reason: 'diagonal page swipe $page dismissed the viewer');
      expect(controller.page, closeTo(page.toDouble(), 0.01));
    }

    expect(find.text('gallery'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
