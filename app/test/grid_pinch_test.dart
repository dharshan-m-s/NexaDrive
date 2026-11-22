import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexadrive/core/design/app_theme.dart';
import 'package:nexadrive/services/api.dart';
import 'package:nexadrive/services/session.dart';
import 'package:nexadrive/ui/screens/files/files_screen.dart';
import 'package:nexadrive/ui/screens/photos/photos_screen.dart';

/// Focused regression tests for grid pinch density.
///
/// The callbacks are invoked directly with Flutter's scale details because the
/// bug was in their handler: the recognizer commonly accepts with one pointer,
/// so a base captured only in `onScaleStart` stayed null and pinching did
/// nothing. Driving the callbacks deterministically reproduces that state.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Session makeSession() => Session()
    ..serverUrl = 'https://example.test'
    ..token = 'tok'
    ..username = 'ada'
    ..userId = '1';

  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: Scaffold(body: screen)),
    );
    await tester.pumpAndSettle();
  }

  GestureDetector pinchDetector(WidgetTester tester) =>
      tester.widget<GestureDetector>(
        find.byWidgetPredicate(
          (widget) => widget is GestureDetector && widget.onScaleUpdate != null,
        ),
      );

  int photoColumns(WidgetTester tester) =>
      (tester.widget<SliverGrid>(find.byType(SliverGrid).first).gridDelegate
              as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount;

  group('Photos grid pinch', () {
    testWidgets('two-finger update changes columns when the base was null',
        (tester) async {
      final selectionCalls = <bool>[];
      await pumpScreen(
        tester,
        PhotosScreen(
          api: _GridApi(),
          session: makeSession(),
          onSelectionChanged: selectionCalls.add,
        ),
      );

      final detector = pinchDetector(tester);
      expect(photoColumns(tester), 3);

      // Flutter accepts the recognizer with one pointer, so the base is still
      // null after this callback.
      detector.onScaleStart?.call(ScaleStartDetails(pointerCount: 1));
      expect(photoColumns(tester), 3);

      detector.onScaleUpdate?.call(
        ScaleUpdateDetails(pointerCount: 2, scale: 0.5),
      );
      await tester.pump();

      // base 3 / scale 0.5 => 6 columns, saved when the gesture ends.
      expect(photoColumns(tester), 6);
      detector.onScaleEnd?.call(ScaleEndDetails());
      await tester.pump();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('nexadrive.photos.grid_columns'), 6);

      // No selection state was created or destroyed by the density change.
      expect(selectionCalls, isEmpty);
      expect(find.byTooltip('Cancel selection'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('pinching during drag selection leaves selection intact',
        (tester) async {
      final selectionCalls = <bool>[];
      await pumpScreen(
        tester,
        PhotosScreen(
          api: _GridApi(),
          session: makeSession(),
          onSelectionChanged: selectionCalls.add,
        ),
      );

      final cell = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == 'Photo: a.jpg',
      );
      expect(cell, findsOneWidget);

      final detector = pinchDetector(tester);
      final hold = await tester.startGesture(tester.getCenter(cell));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(find.byTooltip('Cancel selection'), findsOneWidget);
      expect(selectionCalls, [true]);

      // While a drag-select is active the density must not move at all.
      detector.onScaleUpdate?.call(
        ScaleUpdateDetails(pointerCount: 2, scale: 0.5),
      );
      await tester.pump();
      expect(photoColumns(tester), 3);
      expect(find.text('1 item'), findsWidgets);
      expect(selectionCalls, [true]);

      await hold.up();
      await tester.pump();

      // Once the drag ends the same two-finger update engages normally.
      detector.onScaleUpdate?.call(
        ScaleUpdateDetails(pointerCount: 2, scale: 0.5),
      );
      await tester.pump();
      expect(photoColumns(tester), 6);
      expect(selectionCalls, [true]);
      detector.onScaleEnd?.call(ScaleEndDetails());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('Files grid pinch', () {
    testWidgets('two-finger update switches to grid and captures a null base',
        (tester) async {
      final selectionCalls = <bool>[];
      await pumpScreen(
        tester,
        FilesScreen(
          api: _GridApi(),
          onSelectionChanged: selectionCalls.add,
        ),
      );

      final detector = pinchDetector(tester);
      expect(find.byType(SliverGrid), findsNothing);
      expect(find.byType(CustomScrollView), findsWidgets);

      // One-finger accept leaves the base null; the two-finger update must
      // switch to grid *before* capturing it.
      detector.onScaleStart?.call(ScaleStartDetails(pointerCount: 1));
      detector.onScaleUpdate?.call(
        ScaleUpdateDetails(pointerCount: 2, scale: 0.5),
      );
      await tester.pump();

      expect(find.byType(SliverGrid), findsOneWidget);
      final delegate = tester
          .widget<SliverGrid>(find.byType(SliverGrid))
          .gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      // base 2 / scale 0.5 => 4 columns.
      expect(delegate.crossAxisCount, 4);

      detector.onScaleEnd?.call(ScaleEndDetails());
      await tester.pump();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('nexadrive.files.grid_columns'), 4);
      expect(selectionCalls, isEmpty);
      expect(find.byTooltip('Cancel selection'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}

/// Serves a tiny library so both screens have real grid content to re-lay out.
class _GridApi extends Api {
  _GridApi() : super(_session());

  static Session _session() => Session()
    ..serverUrl = 'https://example.test'
    ..token = 'tok'
    ..username = 'ada'
    ..userId = '1';

  @override
  Future<List<Map<String, dynamic>>> photos() async => const [
        {
          'name': 'a.jpg',
          'path': 'Pictures/a.jpg',
          'kind': 'file',
          'size': 1024,
          'modified_at': '2026-11-20T10:00:00Z',
        },
        {
          'name': 'b.jpg',
          'path': 'Pictures/b.jpg',
          'kind': 'file',
          'size': 2048,
          'modified_at': '2026-11-19T10:00:00Z',
        },
      ];

  @override
  Future<List<Map<String, dynamic>>> listFiles(String path) async {
    if (path.isNotEmpty) return const [];
    return const [
      {'name': 'a.txt', 'path': 'a.txt', 'kind': 'file', 'size': 16},
      {'name': 'b.txt', 'path': 'b.txt', 'kind': 'file', 'size': 32},
    ];
  }

  @override
  Future<Uint8List> thumbnail(String path, {int max = 512}) async {
    throw ApiException(415, 'Thumbnail not available');
  }
}
