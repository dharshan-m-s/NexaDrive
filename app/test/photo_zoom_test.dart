import 'dart:math' as math;
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

/// Focused checks for the photo zoom policy. These are pure math tests on the
/// exact helpers `_ZoomablePhotoState` uses, so they do not need a live image,
/// a mocked server or a rendered viewer.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const viewport = Size(400, 800);
  const photo = Size(4000, 3000);

  /// Applies a 2D affine [matrix] to [point] without pulling in vector_math.
  Offset mapPoint(Matrix4 matrix, Offset point) {
    final s = matrix.storage;
    final w = s[3] * point.dx + s[7] * point.dy + s[15];
    return Offset(
      (s[0] * point.dx + s[4] * point.dy + s[12]) / w,
      (s[1] * point.dx + s[5] * point.dy + s[13]) / w,
    );
  }

  test('a fitted photo can never zoom out below fit', () {
    final fit = PhotoZoomPolicy.fitFor(viewport, photo);
    expect(fit, greaterThan(0));

    // The viewer's bounds are exactly [fit, fit * 8] with no absolute floor.
    expect(PhotoZoomPolicy.minScale(fit), fit);
    expect(PhotoZoomPolicy.maxScale(fit), fit * 8);

    // Infinite boundaries disable InteractiveViewer's hidden cover-scale
    // floor, which used to surface as a ~1.2x lock for near-viewport ratios.
    expect(
      PhotoZoomPolicy.boundaryMargin,
      EdgeInsets.all(double.infinity),
    );

    // Every reachable scale and every zoom-toggle target respects that floor.
    for (final scale in [fit, fit * 1.001, fit * 2, fit * 8]) {
      expect(
        PhotoZoomPolicy.toggleTarget(scale, fit),
        greaterThanOrEqualTo(fit),
      );
    }
  });

  test('the old cover floor is specifically removed for tall photos', () {
    // This photo is only 20% taller than the fit ratio, which is exactly the
    // case where InteractiveViewer's cover scale used to block zoom-out.
    final tall = Size(1200, 2000);
    final fit = PhotoZoomPolicy.fitFor(viewport, tall);
    final cover = math.max(
      viewport.width / tall.width,
      viewport.height / tall.height,
    );
    expect(cover / fit, closeTo(1.2, 0.001));

    // The hidden floor is gone: the only floor the viewer applies is fit.
    expect(PhotoZoomPolicy.minScale(fit), fit);
    expect(PhotoZoomPolicy.boundaryMargin.left, double.infinity);
    expect(PhotoZoomPolicy.boundaryMargin.top, double.infinity);
  });

  test('double tap near fit returns to an exactly centred fit matrix', () {
    final fit = PhotoZoomPolicy.fitFor(viewport, photo);
    final imageCenter = Offset(photo.width / 2, photo.height / 2);

    // A photo that pinch drifted just above fit must go back to fit, not 3x.
    final target = PhotoZoomPolicy.toggleTarget(fit * 1.02, fit);
    expect(target, fit);
    final centered = PhotoZoomPolicy.matrixFor(target, viewport, photo);
    expect(centered.getMaxScaleOnAxis(), closeTo(fit, 1e-9));
    final mapped = mapPoint(centered, imageCenter);
    expect(mapped.dx, closeTo(viewport.width / 2, 1e-6));
    expect(mapped.dy, closeTo(viewport.height / 2, 1e-6));

    // Even the smallest real zoom returns to fit instead of jumping to 3x.
    expect(
      PhotoZoomPolicy.toggleTarget(
          fit * (1 + 2 * PhotoZoomPolicy.zoomEpsilon), fit),
      fit,
    );

    // From fit, the same toggle zooms in and stays centred.
    final zoomedTarget = PhotoZoomPolicy.toggleTarget(fit, fit);
    expect(zoomedTarget, fit * 3);
    final zoomed = PhotoZoomPolicy.matrixFor(zoomedTarget, viewport, photo);
    final zoomedCenter = mapPoint(zoomed, imageCenter);
    expect(zoomedCenter.dx, closeTo(viewport.width / 2, 1e-6));
    expect(zoomedCenter.dy, closeTo(viewport.height / 2, 1e-6));
  });

  test('any real zoom locks panning, page swipes and swipe dismissal', () {
    final fit = PhotoZoomPolicy.fitFor(viewport, photo);

    expect(PhotoZoomPolicy.isZoomed(fit, fit), isFalse);
    expect(
      PhotoZoomPolicy.isZoomed(
          fit * (1 + PhotoZoomPolicy.zoomEpsilon / 2), fit),
      isFalse,
    );
    expect(
      PhotoZoomPolicy.isZoomed(
          fit * (1 + 2 * PhotoZoomPolicy.zoomEpsilon), fit),
      isTrue,
    );
    // Panning and the parent's browsing lock share the same threshold, so
    // there is no longer a 1.25x window where a zoomed photo can be swiped.
    expect(PhotoZoomPolicy.canPan(fit * 1.02, fit), isTrue);
  });

  test('settling at fit recentres a drifted photo exactly', () {
    final fit = PhotoZoomPolicy.fitFor(viewport, photo);
    final drifted = PhotoZoomPolicy.matrixFor(fit, viewport, photo)
      ..translateByDouble(120, 40, 0, 1);

    final settled = PhotoZoomPolicy.settle(drifted, viewport, photo, fit);
    expect(settled.getMaxScaleOnAxis(), closeTo(fit, 1e-9));
    final mapped = mapPoint(settled, Offset(photo.width / 2, photo.height / 2));
    expect(mapped.dx, closeTo(viewport.width / 2, 1e-6));
    expect(mapped.dy, closeTo(viewport.height / 2, 1e-6));
  });

  test('a zoomed photo is clamped so it cannot be dragged off screen', () {
    final fit = PhotoZoomPolicy.fitFor(viewport, photo);
    final scale = fit * 3;
    const scaled = Size(1200, 900);
    final zoomed = PhotoZoomPolicy.matrixFor(scale, viewport, photo)
      ..translateByDouble(2000, 1000, 0, 1);

    final clamped = PhotoZoomPolicy.clampTranslation(zoomed, viewport, photo);
    final translation = clamped.getTranslation();
    expect(clamped.getMaxScaleOnAxis(), closeTo(scale, 1e-9));
    expect(translation.x, lessThanOrEqualTo(0.0));
    expect(translation.x, greaterThanOrEqualTo(viewport.width - scaled.width));
    expect(translation.y, lessThanOrEqualTo(0.0));
    expect(
        translation.y, greaterThanOrEqualTo(viewport.height - scaled.height));
  });

  testWidgets('a single swipe browses, a pinch never does', (tester) async {
    final source = img.Image(width: 800, height: 600);
    img.fill(source, color: img.ColorRgb8(120, 140, 180));
    final bytes = Uint8List.fromList(img.encodeJpg(source, quality: 90));

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

    // Image bytes and engine-side decode happen on the real event loop.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    InteractiveViewer viewer() =>
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    PageView pageView() => tester.widget<PageView>(find.byType(PageView));

    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(viewer().boundaryMargin, EdgeInsets.all(double.infinity));
    expect(viewer().minScale, 1.0);
    expect(pageView().physics, isA<NeverScrollableScrollPhysics>());

    await tester.tap(find.byTooltip('Photo options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zoom in'));
    await tester.pumpAndSettle();

    // PageView never owns a gesture; raw pointer tracking gates browsing on
    // one finger and zoom on two. Pinch/pan follows the real scale.
    expect(pageView().physics, isA<NeverScrollableScrollPhysics>());
    expect(viewer().panEnabled, isTrue);
    expect(viewer().transformationController!.value.getMaxScaleOnAxis(),
        greaterThan(1.0));

    await tester.tap(find.byTooltip('Photo options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zoom out'));
    await tester.pumpAndSettle();

    expect(viewer().panEnabled, isFalse);
    expect(viewer().transformationController!.value.getMaxScaleOnAxis(),
        closeTo(1.0, 1e-6));

    final controller = pageView().controller!;

    // One finger still browses, even though PageView has no scroll physics.
    final swipe =
        await tester.startGesture(const Offset(680, 300), pointer: 11);
    for (var i = 1; i <= 6; i++) {
      await swipe.moveTo(Offset(680 - i * 45, 300));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await swipe.up();
    await tester.pumpAndSettle();
    expect(controller.page, closeTo(1.0, 0.01));

    // Two fingers moving together are a pinch attempt, not a page swipe.
    final left = await tester.startGesture(const Offset(300, 300), pointer: 12);
    final right =
        await tester.startGesture(const Offset(360, 300), pointer: 13);
    await tester.pump();
    for (var i = 1; i <= 6; i++) {
      await left.moveBy(const Offset(-35, 0));
      await right.moveBy(const Offset(-35, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await left.up();
    await right.up();
    await tester.pumpAndSettle();
    expect(controller.page, closeTo(1.0, 0.01));
  });
}
