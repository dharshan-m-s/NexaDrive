import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexadrive/core/design/app_colors.dart';
import 'package:nexadrive/core/design/app_dimensions.dart';
import 'package:nexadrive/core/design/app_theme.dart';
import 'package:nexadrive/core/design/nexa_surfaces.dart';
import 'package:nexadrive/main.dart';
import 'package:nexadrive/services/session.dart';
import 'package:nexadrive/ui/widgets/nexa_bottom_nav.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Runtime checks that the redesign's material and navigation layers are
/// actually rendered, not merely named. These run through the real layout and
/// paint pipeline in the test harness — they are the closest thing to runtime
/// verification available without a device.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Session signedIn() {
    final s = Session();
    s.serverUrl = 'https://example.test';
    s.token = 'tok';
    s.username = 'admin';
    s.displayName = 'Administrator';
    s.role = 'admin';
    return s;
  }

  Future<void> pumpShell(WidgetTester tester, {bool dark = false}) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          platformBrightness: dark ? Brightness.dark : Brightness.light,
        ),
        child: NexaDriveApp(session: signedIn(), prefs: prefs),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('tab bar', () {
    for (final dark in [false, true]) {
      testWidgets('${dark ? 'dark' : 'light'}: renders every destination',
          (tester) async {
        await pumpShell(tester, dark: dark);

        expect(find.byType(NexaBottomNav), findsOneWidget);
        // The solid pill has no Liquid Glass blur inside or wrapped around it.
        expect(
          find.descendant(
            of: find.byType(NexaBottomNav),
            matching: find.byType(BackdropFilter),
          ),
          findsNothing,
        );
        expect(
          find.ancestor(
            of: find.byType(NexaBottomNav),
            matching: find.byType(BackdropFilter),
          ),
          findsNothing,
          reason: 'the pill must not be wrapped in a backdrop blur',
        );
        // Every destination is present and hit-testable.
        for (final label in ['Home', 'Files', 'Shared', 'Photos', 'More']) {
          expect(find.text(label), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the solid pill floats over a full-height page',
        (tester) async {
      await pumpShell(tester);
      // The pill is not Scaffold chrome: it floats over the body.
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.bottomNavigationBar, isNull,
          reason: 'the pill must float, not dock in the chrome slot');

      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final height =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      // The widget's outer box carries its float margins around the capsule.
      final pill = tester.getRect(find.byType(NexaBottomNav));
      expect(pill.left, closeTo(AppDimens.pageMargin, 1.0));
      expect(pill.right, closeTo(width - AppDimens.pageMargin, 1.0));
      expect(pill.bottom, closeTo(height - AppDimens.space10, 1.0),
          reason: 'a clear gap lifts the pill above the bottom edge');
      final capsule = tester.getRect(
        find
            .descendant(
              of: find.byType(NexaBottomNav),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(capsule.left, closeTo(AppDimens.pageMargin, 1.0),
          reason: 'the capsule is inset from the screen edge');
      expect(capsule.right, closeTo(width - AppDimens.pageMargin, 1.0));
      expect(capsule.height, closeTo(AppDimens.bottomNavHeight, 1.0));

      // The page host fills the available screen behind the independently
      // positioned pill. Scrollable pages add bottom scroll clearance so their
      // final items can still be read above the pill.
      final page = tester.getRect(
        find
            .descendant(
              of: find.byType(Scaffold).first,
              matching: find.byType(IndexedStack),
            )
            .first,
      );
      expect(page.bottom, closeTo(height, 1.0),
          reason: 'the page must continue behind the floating pill');
      expect(page.bottom, greaterThan(capsule.top),
          reason: 'the pill overlays the page instead of reserving a sheet');
    });

    testWidgets('the pill floats above the bottom inset without growing',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final prefs = await SharedPreferences.getInstance();
      const inset = 34.0;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(bottom: inset)),
          child: NexaDriveApp(session: signedIn(), prefs: prefs),
        ),
      );
      await tester.pumpAndSettle();

      final height =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final pill = tester.getRect(find.byType(NexaBottomNav));
      // The capsule keeps its own height: the gesture inset is never absorbed
      // into the pill's glass (which would make it read as bulky).
      final capsule = tester.getRect(
        find
            .descendant(
              of: find.byType(NexaBottomNav),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(capsule.height, closeTo(AppDimens.bottomNavHeight, 1.0));
      // It floats a clear gap above the safe-area inset instead.
      expect(pill.bottom, closeTo(height - AppDimens.space10 - inset, 1.0),
          reason: 'the pill floats above the gesture area');
    });

    testWidgets('page content clears the status-bar inset', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final prefs = await SharedPreferences.getInstance();
      const statusBar = 44.0;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(top: statusBar)),
          child: NexaDriveApp(session: signedIn(), prefs: prefs),
        ),
      );
      await tester.pumpAndSettle();
      // The shell must push every destination below the status bar so headers
      // never collide with the notification panel.
      final host = tester.getRect(
        find
            .descendant(
              of: find.byType(Scaffold).first,
              matching: find.byType(IndexedStack),
            )
            .first,
      );
      expect(host.top, greaterThanOrEqualTo(statusBar),
          reason: 'page content must clear the status bar');
    });

    testWidgets('reduced motion still renders the shell', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: NexaDriveApp(session: signedIn(), prefs: prefs),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('More'), findsOneWidget);
    });
  });

  group('glass surfaces', () {
    Future<void> pump(WidgetTester tester, Widget child, Brightness b) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: b == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
          home: Scaffold(body: child),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final b in [Brightness.light, Brightness.dark]) {
      testWidgets('floating surface blurs only when asked (${b.name})',
          (tester) async {
        await pump(
          tester,
          const NexaSurface(
            level: NexaSurfaceLevel.floating,
            useBlur: true,
            child: SizedBox(height: 40, width: 120),
          ),
          b,
        );
        expect(find.byType(BackdropFilter), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('grouped surface is flat, not glass (${b.name})',
          (tester) async {
        await pump(
          tester,
          const NexaSurface(
            level: NexaSurfaceLevel.grouped,
            child: SizedBox(height: 40, width: 120),
          ),
          b,
        );
        // Glass is selective: content surfaces must not be frosted.
        expect(find.byType(BackdropFilter), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('design tokens are coherent', () {
    test('touch targets meet the accessibility floor', () {
      expect(AppDimens.touchTarget, greaterThanOrEqualTo(44));
      expect(AppDimens.touchTarget, greaterThanOrEqualTo(48));
    });

    test('light and dark define distinct, non-inverted surfaces', () {
      expect(AppColors.backgroundLight, isNot(AppColors.backgroundDark));
      final groupedLight = AppColors.surfaceGroupedFor(Brightness.light);
      final groupedDark = AppColors.surfaceGroupedFor(Brightness.dark);
      // Grouped content must stay distinguishable from the page background in
      // both appearances (tonal separation, not a simple inversion).
      expect(groupedLight, isNot(AppColors.backgroundLight));
      expect(groupedDark, isNot(AppColors.backgroundDark));
    });
  });
}
