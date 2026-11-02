import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexadrive/main.dart';
import 'package:nexadrive/services/session.dart';
import 'package:nexadrive/ui/widgets/nexa_bottom_nav.dart';
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

  testWidgets('narrow layout shows the restored compact More action sheet',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final prefs = await SharedPreferences.getInstance();
    await tester
        .pumpWidget(NexaDriveApp(session: signedInSession(), prefs: prefs));
    await tester.pumpAndSettle();

    expect(find.byType(NexaBottomNav), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Photos'), findsOneWidget);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      tester.getSize(find.byType(BottomSheet)).height,
      lessThan(500),
      reason: 'More must remain compact rather than filling the screen',
    );
    expect(find.text('Tools and activity'), findsNothing);
    expect(find.byType(GridView), findsNothing);
    for (final label in [
      'Scan document',
      'Transfers',
      'Trash',
      'Sync center',
      'Notifications',
      'Settings',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Storage Insights'), findsNothing);
    expect(find.text('My files'), findsNothing);
    expect(find.text('Shared'), findsNothing);
  });
}
