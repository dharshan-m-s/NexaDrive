import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexadrive/core/design/app_dimensions.dart';
import 'package:nexadrive/core/design/app_motion.dart';
import 'package:nexadrive/core/design/app_theme.dart';
import 'package:nexadrive/services/api.dart';
import 'package:nexadrive/services/session.dart';
import 'package:nexadrive/ui/screens/files/files_screen.dart';
import 'package:nexadrive/ui/screens/photos/photos_screen.dart';
import 'package:nexadrive/ui/widgets/nexa_page.dart';
import 'package:nexadrive/ui/widgets/nexa_scroll_aware_header.dart';

/// The floating header tracks the finger 1:1, then glides from its live
/// position to the edge implied by the scroll direction when the gesture ends.
/// A small upward scroll from the bottom reveals it fully; a downward scroll
/// carries it away. A new gesture can grab it mid-settle.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppMotion.resetMotionPreferenceForTesting();
  });

  final header = find.byKey(
    const ValueKey<String>('nexa_scroll_aware_header'),
    skipOffstage: false,
  );

  Future<void> pumpAtPhoneSize(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: Scaffold(body: screen)),
    );
    await tester.pumpAndSettle();
  }

  ScrollableState scrollPosition(WidgetTester tester) {
    final scrollables = find.byType(Scrollable, skipOffstage: false);
    ScrollableState? best;
    for (var i = 0; i < scrollables.evaluate().length; i++) {
      final state = tester.state<ScrollableState>(scrollables.at(i));
      if (state.position.axis != Axis.vertical) continue;
      if (best == null ||
          state.position.maxScrollExtent > best.position.maxScrollExtent) {
        best = state;
      }
    }
    if (best == null) throw StateError('No scrollable content was found.');
    return best;
  }

  Future<void> scrollToBottom(WidgetTester tester) async {
    // A single enormous drag is not a realistic fling and can make elastic
    // physics bounce all the way back to the top. Land on the extent directly
    // so the tests exercise the header state at the bottom, not the spring.
    final position = scrollPosition(tester).position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'a shared NexaPage header glides away and returns from the bottom',
      (tester) async {
    await pumpAtPhoneSize(
      tester,
      NexaPage(
        title: 'Files',
        bottomSafeArea: false,
        scrollable: true,
        body: Column(
          children: [
            for (var i = 0; i < 60; i++)
              Padding(
                padding: const EdgeInsets.all(AppDimens.space16),
                child: Text('item${i.toString().padLeft(2, '0')}.txt'),
              ),
          ],
        ),
      ),
    );

    final initial = tester.getRect(header);
    expect(initial.top, closeTo(0, 1));
    expect(initial.height, greaterThan(40));

    final scrollable = find.byType(NestedScrollView);

    // While the finger is down the header is glued to it, not animated to a
    // target. Releasing snaps that same surface fully out of view once the
    // gesture has passed the header's snap threshold.
    final gesture = await tester.startGesture(tester.getCenter(scrollable));
    await gesture.moveBy(const Offset(0, -60));
    await tester.pump();
    final during = tester.getRect(header);
    expect(during.top, closeTo(initial.top - 60, 3));
    expect(during.height, closeTo(initial.height, 1));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(header, findsOneWidget);
    expect(tester.getRect(header).bottom, lessThan(1));
    expect(
      tester.getRect(find.text('item00.txt')).top,
      lessThan(40),
      reason: 'the reserved header slot must collapse with the snap',
    );

    // The reserved slot collapses with the snap, so content sits at the top
    // instead of leaving a blank bar where the chrome used to be.
    await tester.drag(scrollable, const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(tester.getRect(header).bottom, lessThan(1));

    // Content painted in the vacated header slot must stay interactive.
    final beforeTopSwipe = scrollPosition(tester).position.pixels;
    final topGesture = await tester.startGesture(const Offset(200, 20));
    await topGesture.moveBy(const Offset(0, 30));
    await topGesture.up();
    await tester.pumpAndSettle();
    expect(
      scrollPosition(tester).position.pixels,
      lessThan(beforeTopSwipe),
      reason: 'a swipe in the vacated header slot must still scroll',
    );

    await scrollToBottom(tester);
    final hidden = tester.getRect(header);
    expect(hidden.bottom, lessThan(1));

    // A short upward scroll at the very bottom still returns the whole header.
    await tester.drag(scrollable, const Offset(0, 24));
    await tester.pumpAndSettle();
    final restored = tester.getRect(header);
    expect(restored.top, closeTo(initial.top, 2));
    expect(restored.height, closeTo(initial.height, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the header survives orientation changes', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: NexaPage(
            title: 'Files',
            bottomSafeArea: false,
            scrollable: true,
            body: Column(
              children: [
                for (var i = 0; i < 60; i++)
                  Padding(
                    padding: const EdgeInsets.all(AppDimens.space16),
                    child: Text('item${i.toString().padLeft(2, '0')}.txt'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final portrait = tester.getRect(header);
    tester.view.physicalSize = const Size(780, 360);
    await tester.pumpAndSettle();
    final landscape = tester.getRect(header);
    expect(landscape.top, closeTo(0, 1));
    expect(landscape.height, greaterThan(40));
    expect(find.text('item00.txt'), findsOneWidget);

    tester.view.physicalSize = const Size(360, 780);
    await tester.pumpAndSettle();
    final back = tester.getRect(header);
    expect(back.top, closeTo(0, 1));
    expect(back.height, closeTo(portrait.height, 2));
    expect(find.text('item00.txt'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('returning to a cached page restores its header', (tester) async {
    final reset = ValueNotifier<int>(0);
    addTearDown(reset.dispose);
    await pumpAtPhoneSize(
      tester,
      NexaHeaderResetScope(
        notifier: reset,
        child: NexaPage(
          title: 'Files',
          bottomSafeArea: false,
          scrollable: true,
          body: Column(
            children: [
              for (var i = 0; i < 60; i++)
                Padding(
                  padding: const EdgeInsets.all(AppDimens.space16),
                  child: Text('item${i.toString().padLeft(2, '0')}.txt'),
                ),
            ],
          ),
        ),
      ),
    );

    final initial = tester.getRect(header);
    await tester.drag(find.byType(NestedScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(tester.getRect(header).bottom, lessThan(1));

    // A tab switch keeps the page alive but broadcasts a new entry token.
    reset.value++;
    await tester.pumpAndSettle();
    final restored = tester.getRect(header);
    expect(restored.top, closeTo(initial.top, 1));
    expect(restored.height, closeTo(initial.height, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Files header glides away and returns from a long folder',
      (tester) async {
    await pumpAtPhoneSize(tester, FilesScreen(api: _ScrollApi()));

    final initial = tester.getRect(header);
    expect(initial.top, closeTo(0, 1));
    expect(initial.height, greaterThan(100));
    expect(find.byTooltip('Search files'), findsOneWidget);

    final scrollable = find.byType(CustomScrollView);
    await tester.drag(scrollable, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(header, findsOneWidget);
    expect(tester.getRect(header).bottom, lessThan(1));

    await scrollToBottom(tester);
    final hidden = tester.getRect(header);
    final deepOffset = scrollPosition(tester).position.pixels;
    expect(deepOffset,
        greaterThan(scrollPosition(tester).position.minScrollExtent));
    expect(hidden.bottom, lessThan(1));

    await tester.drag(scrollable, const Offset(0, 24));
    await tester.pumpAndSettle();
    final restored = tester.getRect(header);
    expect(restored.top, closeTo(initial.top, 2));
    expect(restored.height, closeTo(initial.height, 1));
    expect(
      scrollPosition(tester).position.pixels,
      greaterThan(deepOffset * 0.8),
      reason: 'revealing the chrome must not teleport a deep list to the top',
    );
    expect(find.byTooltip('Search files'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Photos header hides over the grid and returns',
      (tester) async {
    await pumpAtPhoneSize(
      tester,
      PhotosScreen(api: _PhotosScrollApi(), session: _scrollSession()),
    );

    final initial = tester.getRect(header);
    expect(initial.top, closeTo(0, 1));
    expect(initial.height, greaterThan(40));
    // The chrome is an opaque Material surface, never a translucent strip that
    // lets grid cells bleed through while it is partly dismissed.
    final surface = tester.widget<Material>(header);
    expect(surface.color?.a, 1.0);
    expect(surface.surfaceTintColor, Colors.transparent);

    final scrollable = find.byType(CustomScrollView);
    await tester.drag(scrollable, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(tester.getRect(header).bottom, lessThan(1));

    await scrollToBottom(tester);
    expect(tester.getRect(header).bottom, lessThan(1));
    final deepOffset = scrollPosition(tester).position.pixels;

    await tester.drag(scrollable, const Offset(0, 24));
    await tester.pumpAndSettle();
    final restored = tester.getRect(header);
    expect(restored.top, closeTo(initial.top, 2));
    expect(restored.height, closeTo(initial.height, 1));
    expect(
      scrollPosition(tester).position.pixels,
      greaterThan(deepOffset * 0.8),
      reason: 'the gallery must stay where it was while chrome returns',
    );
    expect(tester.takeException(), isNull);
  });

  Future<void> pumpWithInsets(
    WidgetTester tester,
    Widget screen, {
    required EdgeInsets padding,
  }) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(padding: padding),
            child: screen,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('device insets: Files chrome clears status bar and hides fully',
      (tester) async {
    await pumpWithInsets(
      tester,
      FilesScreen(api: _ScrollApi()),
      padding: const EdgeInsets.fromLTRB(0, 44, 0, 24),
    );
    final content = find.byKey(
      const ValueKey<String>('nexa_scroll_aware_header_content'),
    );
    expect(tester.getTopLeft(content).dy, closeTo(44, 1));
    expect(
      tester.getBottomRight(content).dy,
      closeTo(tester.getBottomRight(header).dy, 1),
      reason: 'the Files chrome must not reserve a blank band',
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(tester.getRect(header).bottom, lessThanOrEqualTo(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('device insets: Photos chrome clears status bar and hides fully',
      (tester) async {
    await pumpWithInsets(
      tester,
      PhotosScreen(api: _PhotosScrollApi(), session: _scrollSession()),
      padding: const EdgeInsets.fromLTRB(0, 44, 0, 24),
    );
    final content = find.byKey(
      const ValueKey<String>('nexa_scroll_aware_header_content'),
    );
    expect(tester.getTopLeft(content).dy, closeTo(44, 1));
    expect(
      tester.getBottomRight(content).dy,
      closeTo(tester.getBottomRight(header).dy, 1),
      reason: 'the Photos chrome must not reserve a blank band',
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(tester.getRect(header).bottom, lessThanOrEqualTo(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Photos keeps scrolling after the chrome hides', (tester) async {
    await pumpWithInsets(
      tester,
      PhotosScreen(api: _PhotosScrollApi(), session: _scrollSession()),
      padding: const EdgeInsets.fromLTRB(0, 44, 0, 24),
    );
    final scrollable = find.byType(CustomScrollView);
    final initial = scrollPosition(tester).position.pixels;

    await tester.drag(scrollable, const Offset(0, -120));
    await tester.pumpAndSettle();
    final first = scrollPosition(tester).position.pixels;
    expect(tester.getRect(header).bottom, lessThanOrEqualTo(1));
    expect(first, greaterThan(initial));

    await tester.drag(scrollable, const Offset(0, -120));
    await tester.pumpAndSettle();
    final second = scrollPosition(tester).position.pixels;
    expect(
      second,
      greaterThan(first + 60),
      reason: 'a second swipe must advance the grid, not reveal the chrome',
    );
    expect(tester.getRect(header).bottom, lessThanOrEqualTo(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Files row separators are centred in the page gutters',
      (tester) async {
    await pumpAtPhoneSize(tester, FilesScreen(api: _ScrollApi()));

    final separators = find.byWidgetPredicate(
      (widget) => widget is Divider && widget.height == 1,
    );
    expect(separators, findsWidgets);
    final divider = tester.widget<Divider>(separators.first);
    expect(divider.indent, AppDimens.rowInset);
    expect(divider.endIndent, AppDimens.rowInset);
    // Divider's own box spans the row; the decorated box carries the inset.
    final line = find.descendant(
      of: separators.first,
      matching: find.byType(DecoratedBox),
    );
    final rect = tester.getRect(line);
    expect(rect.left, closeTo(AppDimens.rowInset, 1));
    expect(rect.right, closeTo(400 - AppDimens.rowInset, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Files list rubber-bands at the top edge', (tester) async {
    await pumpAtPhoneSize(tester, FilesScreen(api: _ScrollApi()));
    final scrollable = find.byType(CustomScrollView);
    expect(scrollPosition(tester).position.pixels, 0);

    await tester.drag(scrollable, const Offset(0, 80));
    await tester.pump();
    expect(
      scrollPosition(tester).position.pixels,
      lessThan(0),
      reason: 'a downward pull must stretch past the top edge',
    );

    await tester.pumpAndSettle();
    expect(scrollPosition(tester).position.pixels, closeTo(0, 1));
    expect(tester.getRect(header).top, closeTo(0, 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Photos grid rubber-bands at the top edge', (tester) async {
    await pumpAtPhoneSize(
      tester,
      PhotosScreen(api: _PhotosScrollApi(), session: _scrollSession()),
    );
    final scrollable = find.byType(CustomScrollView);
    expect(scrollPosition(tester).position.pixels, 0);

    await tester.drag(scrollable, const Offset(0, 80));
    await tester.pump();
    expect(
      scrollPosition(tester).position.pixels,
      lessThan(0),
      reason: 'the gallery must stretch past the top edge like Files',
    );

    await tester.pumpAndSettle();
    expect(scrollPosition(tester).position.pixels, closeTo(0, 1));
    expect(tester.getRect(header).top, closeTo(0, 2));
    expect(tester.takeException(), isNull);
  });
}

Session _scrollSession() => Session()
  ..serverUrl = 'https://example.test'
  ..token = 'tok'
  ..username = 'ada'
  ..userId = '1';

class _ScrollApi extends Api {
  _ScrollApi() : super(_scrollSession());

  @override
  Future<List<Map<String, dynamic>>> listFiles(String path) async {
    if (path.isNotEmpty) return const [];
    return [
      for (var i = 0; i < 40; i++)
        {
          'name': 'item${i.toString().padLeft(2, '0')}.txt',
          'path': 'item${i.toString().padLeft(2, '0')}.txt',
          'kind': 'file',
          'size': 16 + i,
        },
    ];
  }
}

class _PhotosScrollApi extends Api {
  _PhotosScrollApi() : super(_scrollSession());

  @override
  Future<List<Map<String, dynamic>>> photos() async => [
        for (var i = 0; i < 40; i++)
          {
            'name': 'photo${i.toString().padLeft(2, '0')}.jpg',
            'path': 'Camera/photo${i.toString().padLeft(2, '0')}.jpg',
            'kind': 'file',
            'size': 1024 + i,
            'modified_at': '2026-11-20T10:00:00Z',
          },
      ];

  @override
  Future<List<Map<String, dynamic>>> listFiles(String path) async => const [];
}
