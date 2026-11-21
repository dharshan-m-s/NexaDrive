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

/// Real multi-touch regression: a pinch must work on the first attempt, after
/// a full zoom cycle, and after browsing to another photo. The raw-pointer
/// layer must never let the first finger's movement start a page change.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('pinch zoom survives repeated cycles and a page change',
      (tester) async {
    final source = img.Image(width: 800, height: 600);
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
    Map<String, dynamic> entry(String name) => {
          'name': name,
          'path': 'Camera/$name',
          'type': 'file',
          'size': bytes.length,
          'modified_at': '2026-11-21T10:00:00Z',
        };

    await tester.pumpWidget(
      MaterialApp(
        home: PhotoViewer(
          photos: [entry('one.jpg'), entry('two.jpg')],
          initialIndex: 0,
          api: api,
          images: ImageRepository(api),
        ),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    double scale() => tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!
        .value
        .getMaxScaleOnAxis();

    var pointer = 1;
    Future<void> pinch({
      required double startGap,
      required double endGap,
    }) async {
      const centerX = 400.0;
      const centerY = 300.0;
      final start = startGap / 2;
      final end = endGap / 2;
      final left = await tester.startGesture(
        Offset(centerX - start, centerY),
        pointer: pointer++,
      );
      final right = await tester.startGesture(
        Offset(centerX + start, centerY),
        pointer: pointer++,
      );
      await tester.pump();
      for (var step = 1; step <= 8; step++) {
        final t = step / 8;
        final half = start + (end - start) * t;
        await left.moveTo(Offset(centerX - half, centerY));
        await right.moveTo(Offset(centerX + half, centerY));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await left.up();
      await right.up();
      await tester.pumpAndSettle();
    }

    expect(scale(), closeTo(1.0, 1e-6));

    // Zoom in/out twice on the same photo: the second attempt must not be
    // swallowed by a stale scroll recognizer or a leftover zoom flag.
    await pinch(startGap: 40, endGap: 320);
    expect(scale(), greaterThan(2.0));
    await pinch(startGap: 320, endGap: 40);
    expect(scale(), closeTo(1.0, 1e-6));
    await pinch(startGap: 40, endGap: 320);
    expect(scale(), greaterThan(2.0));
    await pinch(startGap: 320, endGap: 40);
    expect(scale(), closeTo(1.0, 1e-6));

    // Browse with one finger, then pinch the new photo.
    final swipe =
        await tester.startGesture(const Offset(680, 300), pointer: pointer++);
    for (var step = 1; step <= 6; step++) {
      await swipe.moveTo(Offset(680 - step * 45, 300));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await swipe.up();
    await tester.pumpAndSettle();

    final controller =
        tester.widget<PageView>(find.byType(PageView)).controller!;
    expect(controller.page, closeTo(1.0, 0.01));

    await pinch(startGap: 40, endGap: 320);
    expect(scale(), greaterThan(2.0));
    await pinch(startGap: 320, endGap: 40);
    expect(scale(), closeTo(1.0, 1e-6));
  });
}
