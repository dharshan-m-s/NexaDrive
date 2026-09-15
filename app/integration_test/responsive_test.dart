import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nexadrive/main.dart';
import 'package:nexadrive/ui/shell/app_shell.dart';
import 'package:nexadrive/services/session.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_config.dart';

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

  const sizes = <(String, Size)>[
    ('400x800', Size(400, 800)),
    ('600x960', Size(600, 960)),
    ('800x1280', Size(800, 1280)),
    ('1280x720', Size(1280, 720)),
    ('1280x900', Size(1280, 900)),
    ('1366x768', Size(1366, 768)),
    ('1920x1080', Size(1920, 1080)),
  ];

  testWidgets('responsive walk: all sizes x main pages, no layout exceptions',
      (tester) async {
    final config = LiveTestConfig.require();
    final session = Session();
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(NexaDriveApp(session: session, prefs: prefs));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3));
    await tester.enterText(fields.at(0), config.serverUrl);
    await tester.enterText(fields.at(1), config.username);
    await tester.enterText(fields.at(2), config.password);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await _pumpUntilFound(tester, find.byType(AppShell),
        timeout: const Duration(seconds: 45));

    for (final (label, size) in sizes) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$label: initial login shell');

      final desktop = size.width >= 900;

      // Home
      if (find.text('Home').evaluate().isNotEmpty) await tester.tap(find.text('Home').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$label Home');

      // Files
      if (desktop) {
        await tester.tap(find.text('My files').first);
      } else {
        await tester.tap(find.text('Files').first);
      }
      await _pumpUntilFound(tester, find.text('My files'), timeout: const Duration(seconds: 15));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$label Files');

      // Shared
      await tester.tap(find.text('Shared').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$label Shared');

      // Photos
      await tester.tap(find.text('Photos').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$label Photos');

      // Trash (desktop sidebar / mobile More sheet)
      if (desktop) {
        await tester.tap(find.text('Trash').first);
      } else {
        await tester.tap(find.text('More'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Trash'));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$label Trash');

      // Settings (desktop sidebar / mobile More sheet)
      if (desktop) {
        await tester.tap(find.text('Settings').first);
      } else {
        await tester.tap(find.text('More'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Settings'));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$label Settings');
    }
    // ignore: avoid_print
    print('RESPONSIVE WALK PASSED: ${sizes.map((s) => s.$1).join(', ')}');

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}