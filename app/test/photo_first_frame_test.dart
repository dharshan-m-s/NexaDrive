import 'dart:async';
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

/// A photo's first painted frame must already be fitted to the viewport. The
/// old post-frame correction showed a portrait original full-screen for one
/// frame before it snapped to its real orientation.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an opened portrait photo is orientation-correct on frame one',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final source = img.Image(width: 600, height: 800);
    img.fill(source, color: img.ColorRgb8(120, 140, 180));
    final bytes = Uint8List.fromList(img.encodeJpg(source, quality: 90));
    final session = Session()
      ..serverUrl = 'https://cloud.example.test'
      ..username = 'tester'
      ..token = 't';
    final api = Api(
      session,
      client: MockClient((request) async => http.Response.bytes(
            bytes,
            200,
            headers: {'content-type': 'image/jpeg'},
          )),
    );
    final entry = {
      'name': 'portrait.jpg',
      'path': 'Camera/portrait.jpg',
      'type': 'file',
      'size': bytes.length,
      'modified_at': '2026-11-21T10:00:00Z',
    };

    await tester.pumpWidget(
      MaterialApp(
        home: PhotoViewer(
          photos: [entry],
          initialIndex: 0,
          api: api,
          images: ImageRepository(api),
        ),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });

    // The frame that first shows the decoded image is the one under test. Do
    // not pump again before checking: a late correction would hide the glitch.
    await tester.pump();

    // No shared-element flight: it used to land in the full viewport and swap
    // to the fitted photo afterwards, which looked like a zoom-and-shrink.
    expect(find.byType(Hero), findsNothing);
    expect(find.byType(HeroMode), findsNothing);

    final transform = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!
        .value;
    expect(transform.getMaxScaleOnAxis(), closeTo(400 / 600, 1e-6));

    final rect = tester.getRect(find.byType(RawImage));
    expect(rect.width, closeTo(400, 1));
    expect(rect.height, closeTo(800 * (400 / 600), 1));
    expect(rect.left, closeTo(0, 1));
    expect(rect.top, closeTo((800 - rect.height) / 2, 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the loading thumbnail keeps its aspect instead of covering the viewport',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final thumbSource = img.Image(width: 300, height: 400);
    img.fill(thumbSource, color: img.ColorRgb8(90, 120, 160));
    final thumb = Uint8List.fromList(img.encodeJpg(thumbSource, quality: 80));

    // Keep the preview request pending so the viewer stays on its loading page.
    final pending = Completer<http.Response>();
    final session = Session()
      ..serverUrl = 'https://cloud.example.test'
      ..username = 'tester'
      ..token = 't';
    final api = Api(
      session,
      client: MockClient((request) => pending.future),
    );
    final entry = {
      'name': 'portrait.jpg',
      'path': 'Camera/portrait.jpg',
      'type': 'file',
      'size': thumb.length,
      'modified_at': '2026-11-21T10:00:00Z',
    };

    await tester.pumpWidget(
      MaterialApp(
        home: PhotoViewer(
          photos: [entry],
          initialIndex: 0,
          api: api,
          images: ImageRepository(api),
          thumbnailLookup: (_) => thumb,
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (widget) => widget is FittedBox && widget.fit == BoxFit.contain,
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.fit == BoxFit.cover,
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);

    // Complete the held request so the API's 30-second timeout timer is
    // cancelled before the test ends.
    pending.complete(http.Response('test complete', 500));
    await tester.pump();
  });
}
