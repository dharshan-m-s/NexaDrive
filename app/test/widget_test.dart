import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexadrive/main.dart';
import 'package:nexadrive/services/session.dart';
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
    expect(find.text('Welcome to NexaDrive'), findsOneWidget);
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

  testWidgets('signed-in narrow layout shows bottom navigation and More sheet',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final prefs = await SharedPreferences.getInstance();
    await tester
        .pumpWidget(NexaDriveApp(session: signedInSession(), prefs: prefs));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Photos'), findsOneWidget);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();

    // Scoped to the sheet: the destinations behind it (Home's shortcuts, the
    // navigation bar) legitimately reuse some of these labels.
    Finder inSheet(String label) => find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text(label),
        );
    expect(inSheet('Scan document'), findsOneWidget);
    expect(inSheet('Transfers'), findsOneWidget);
    expect(inSheet('Trash'), findsOneWidget);
    expect(inSheet('Sync center'), findsOneWidget);
    expect(inSheet('Notifications'), findsOneWidget);
    expect(inSheet('Settings'), findsOneWidget);
  });
}
