import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nexadrive/main.dart';
import 'package:nexadrive/ui/shell/app_shell.dart';
import 'package:nexadrive/services/session.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_config.dart';

/// Pumps the widget tree for up to [timeout], repeatedly, until [finder]
/// matches at least one widget. This lets real async HTTP settle without a
/// hardcoded pumpAndSettle that could time out on long-running animations.
Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real Linux UI flow: login -> home -> logout (live server)',
      (tester) async {
    final config = LiveTestConfig.require();

    // Fresh session with no token -> NexaDriveApp renders LoginScreen.
    final session = Session();
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(NexaDriveApp(session: session, prefs: prefs));
    await tester.pumpAndSettle();

    // Login screen present.
    expect(find.text('Welcome to NexaDrive'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);

    // Enter the live server address + credentials from the environment.
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3));
    await tester.enterText(fields.at(0), config.serverUrl);
    await tester.enterText(fields.at(1), config.username);
    await tester.enterText(fields.at(2), config.password);

    // Submit login. This performs a real authenticated request to the live
    // server and navigates to AppShell (Home) on success.
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));

    // Wait for the app shell to replace the login screen and Home to render
    // the signed-in account name from /api/me + /api/storage.
    await _pumpUntilFound(tester, find.byType(AppShell), timeout: const Duration(seconds: 45));
    await _pumpUntilFound(tester, find.textContaining(config.username == 'admin' ? 'Administrator' : config.username),
        timeout: const Duration(seconds: 30));

    // Desktop sidebar -> Settings, then Sign out. This performs a real
    // authenticated POST /api/auth/logout and returns to the login screen.
    await tester.tap(find.text('Settings'));
    await _pumpUntilFound(tester, find.text('Sign out'), timeout: const Duration(seconds: 30));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
    await _pumpUntilFound(tester, find.byKey(const Key('signout_confirm')),
        timeout: const Duration(seconds: 30));
    await tester.tap(find.byKey(const Key('signout_confirm')));
    await _pumpUntilFound(tester, find.text('Welcome to NexaDrive'), timeout: const Duration(seconds: 45));
  });
}