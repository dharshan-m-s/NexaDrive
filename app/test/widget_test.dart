import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexadrive/main.dart';
import 'package:nexadrive/services/session.dart';
import 'package:nexadrive/ui/widgets/nexa_bottom_nav.dart';
import 'package:nexadrive/ui/widgets/nexa_liquid_glass.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Session signedInSession() {
    final session = Session();
    session.serverUrl = 'https://example.test';
    session.token = 'test-token';
    session.displayName = 'Administrator';
    session.username = 'admin';
    session.role = 'admin';
    return session;
  }

  testWidgets('NexaDrive app starts signed out with a login screen',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(NexaDriveApp(session: Session(), prefs: prefs));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to your cloud'), findsOneWidget);
  });

  testWidgets('signed-in desktop layout shows a wide sidebar', (tester) async {
    tester.view.physicalSize = const Size(2560, 1800);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final prefs = await SharedPreferences.getInstance();
    await tester
        .pumpWidget(NexaDriveApp(session: signedInSession(), prefs: prefs));
    await tester.pumpAndSettle();

    expect(find.text('NexaDrive'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('My files'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('narrow layout shows a compact More Liquid Glass sheet', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final prefs = await SharedPreferences.getInstance();
    await tester
        .pumpWidget(NexaDriveApp(session: signedInSession(), prefs: prefs));
    await tester.pumpAndSettle();

    // The redesign replaces the Material NavigationBar with an iOS tab bar.
    expect(find.byType(NexaBottomNav), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Photos'), findsOneWidget);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();

    // More is a content-sized modal bottom sheet. Its optical glass is
    // retained, while primary destinations stay in the navigation dock.
    final sheet = find.ancestor(
      of: find.text('Tools and activity'),
      matching: find.byType(NexaLiquidGlass),
    );
    Finder inSheet(String label) =>
        find.descendant(of: sheet, matching: find.text(label));
    expect(sheet, findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      tester.getSize(find.byType(BottomSheet)).height,
      lessThan(500),
      reason: 'More must remain compact rather than filling the screen',
    );
    expect(
      find.descendant(of: sheet, matching: find.byType(GridView)),
      findsOneWidget,
    );
    for (final label in [
      'Scan document',
      'Transfers',
      'Trash',
      'Sync center',
      'Notifications',
      'Settings',
    ]) {
      expect(inSheet(label), findsOneWidget);
    }
    expect(inSheet('Storage insights'), findsNothing);
    expect(inSheet('My files'), findsNothing);
    expect(inSheet('Shared'), findsNothing);
  });
}
