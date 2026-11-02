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

  testWidgets('narrow layout shows the More glass launcher', (tester) async {
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

    // More is a floating 3x3 glass launcher, not a bottom sheet. Scope the
    // assertions to that launcher because the background can reuse labels.
    final launcher = find.ancestor(
      of: find.text('Your tools and destinations'),
      matching: find.byType(NexaLiquidGlass),
    );
    Finder inLauncher(String label) => find.descendant(
          of: launcher,
          matching: find.text(label),
        );
    expect(launcher, findsOneWidget);
    expect(
      find.descendant(of: launcher, matching: find.byType(GridView)),
      findsOneWidget,
    );
    expect(inLauncher('Scan document'), findsOneWidget);
    expect(inLauncher('Transfers'), findsOneWidget);
    expect(inLauncher('Trash'), findsOneWidget);
    expect(inLauncher('Sync center'), findsOneWidget);
    expect(inLauncher('Notifications'), findsOneWidget);
    expect(inLauncher('Settings'), findsOneWidget);
    expect(inLauncher('Storage insights'), findsOneWidget);
    expect(inLauncher('My files'), findsOneWidget);
    expect(inLauncher('Shared'), findsOneWidget);
  });
}
