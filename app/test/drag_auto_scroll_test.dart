import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexadrive/core/design/app_theme.dart';
import 'package:nexadrive/services/api.dart';
import 'package:nexadrive/services/session.dart';
import 'package:nexadrive/ui/screens/files/files_screen.dart';
import 'package:nexadrive/ui/screens/photos/photos_screen.dart';

/// Regression coverage for range drag selection at a scroll viewport edge.
///
/// The content must keep scrolling while the pointer rests near the bottom and
/// the range must keep growing as new cells move under the pointer.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Session session() => Session()
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

  /// The page header can contain its own scrollables, so always resolve the
  /// viewport from a cell rather than taking the first Scrollable on screen.
  Finder scrollableOf(WidgetTester tester, Finder cell) => find
      .ancestor(
        of: cell,
        matching: find.byType(Scrollable),
      )
      .first;

  ScrollableState scrollableState(WidgetTester tester, Finder cell) =>
      tester.state<ScrollableState>(scrollableOf(tester, cell));

  /// The gallery keeps its own count in the contextual bar while the header
  /// still shows the library total, so the smaller count is the selection.
  int selectedCount(WidgetTester tester) {
    final counts = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) {
          final match = RegExp(r'^(\d+) items?$').firstMatch(text.data ?? '');
          return match == null ? null : int.parse(match.group(1)!);
        })
        .whereType<int>()
        .toList();
    if (counts.isEmpty) {
      throw StateError('No selection count found on screen.');
    }
    return counts.fold(counts.first, (a, b) => a < b ? a : b);
  }

  Future<void> holdAtBottomEdge(
    WidgetTester tester,
    TestGesture gesture,
    Rect viewport,
  ) async {
    // Close enough to trigger edge auto-scroll, but above the trailing
    // clearance sliver so cells still move under the pointer.
    await gesture.moveTo(
      Offset(viewport.center.dx, viewport.bottom - 32),
    );
    for (var frame = 0; frame < 16; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  group('Photos drag selection auto-scroll', () {
    testWidgets('keeps scrolling and extending the range at the bottom edge',
        (tester) async {
      await pumpScreen(
        tester,
        PhotosScreen(api: _ScrollApi(), session: session()),
      );

      final first = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Photo: item01.jpg',
      );
      expect(first, findsOneWidget);
      final before = scrollableState(tester, first).position.pixels;
      final gesture = await tester.startGesture(tester.getCenter(first));
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byTooltip('Cancel selection'), findsWidgets);
      final scrollState = scrollableState(tester, first);
      final viewport = tester.getRect(scrollableOf(tester, first));
      final selectedBefore = selectedCount(tester);

      await holdAtBottomEdge(tester, gesture, viewport);

      expect(scrollState.position.pixels, greaterThan(before + 20));
      expect(selectedCount(tester), greaterThan(selectedBefore));

      await gesture.up();
      await tester.pumpAndSettle();
      final stopped = scrollState.position.pixels;
      await tester.pump(const Duration(milliseconds: 300));
      expect(scrollState.position.pixels, stopped);
      expect(tester.takeException(), isNull);
    });
  });

  group('Files drag selection auto-scroll', () {
    testWidgets('keeps scrolling and extending the range at the bottom edge',
        (tester) async {
      await pumpScreen(
        tester,
        FilesScreen(api: _ScrollApi()),
      );

      final first = find.text('item00.txt');
      expect(first, findsOneWidget);
      final before = scrollableState(tester, first).position.pixels;
      final gesture = await tester.startGesture(tester.getCenter(first));
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byTooltip('Cancel selection'), findsWidgets);
      final scrollState = scrollableState(tester, first);
      final viewport = tester.getRect(scrollableOf(tester, first));
      final selectedBefore = selectedCount(tester);

      await holdAtBottomEdge(tester, gesture, viewport);

      expect(scrollState.position.pixels, greaterThan(before + 20));
      expect(selectedCount(tester), greaterThan(selectedBefore));

      await gesture.up();
      await tester.pumpAndSettle();
      final stopped = scrollState.position.pixels;
      await tester.pump(const Duration(milliseconds: 300));
      expect(scrollState.position.pixels, stopped);
      expect(tester.takeException(), isNull);
    });
  });
}

/// Serves enough content to guarantee a scrollable viewport on both screens.
class _ScrollApi extends Api {
  _ScrollApi() : super(_session());

  static Session _session() => Session()
    ..serverUrl = 'https://example.test'
    ..token = 'tok'
    ..username = 'ada'
    ..userId = '1';

  static const _photoCount = 60;
  static const _fileCount = 40;

  @override
  Future<List<Map<String, dynamic>>> photos() async => [
        for (var i = 0; i < _photoCount; i++)
          {
            'name': 'item${i.toString().padLeft(2, '0')}.jpg',
            'path': 'Pictures/item${i.toString().padLeft(2, '0')}.jpg',
            'kind': 'file',
            'size': 1024 + i,
            'modified_at': '2026-11-20T10:00:00Z',
          },
      ];

  @override
  Future<List<Map<String, dynamic>>> listFiles(String path) async {
    if (path.isNotEmpty) return const [];
    return [
      for (var i = 0; i < _fileCount; i++)
        {
          'name': 'item${i.toString().padLeft(2, '0')}.txt',
          'path': 'item${i.toString().padLeft(2, '0')}.txt',
          'kind': 'file',
          'size': 16 + i,
        },
    ];
  }

  @override
  Future<Uint8List> thumbnail(String path, {int max = 512}) async {
    throw ApiException(415, 'Thumbnail not available');
  }
}
