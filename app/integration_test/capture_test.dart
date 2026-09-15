import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

Future<void> _snap(GlobalKey boundaryKey, String name) async {
  await Future<void>.delayed(const Duration(milliseconds: 600));
  final boundary = boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1.0);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  final dir = Platform.environment['NEXADRIVE_TEST_SCREENSHOT_DIR'] ?? 'screenshots';
  final out = File('$dir/$name.png');
  out.parent.createSync(recursive: true);
  out.writeAsBytesSync(byteData!.buffer.asUint8List());
  // ignore: avoid_print
  print('CAPTURED $name -> $out (${out.lengthSync()} bytes)');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final boundaryKey = GlobalKey();

  testWidgets('capture screens for visual audit', (tester) async {
    final config = LiveTestConfig.require();
    final session = Session();
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(RepaintBoundary(key: boundaryKey, child: NexaDriveApp(session: session, prefs: prefs)));
    await tester.pumpAndSettle();
    await _snap(boundaryKey, '01_login');

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3));
    await tester.enterText(fields.at(0), config.serverUrl);
    await tester.enterText(fields.at(1), config.username);
    await tester.enterText(fields.at(2), config.password);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await _pumpUntilFound(tester, find.byType(AppShell), timeout: const Duration(seconds: 45));
    await _pumpUntilFound(tester, find.textContaining(config.username == 'admin' ? 'Administrator' : config.username),
        timeout: const Duration(seconds: 30));
    await _snap(boundaryKey, '02_home');

    await tester.tap(find.text('My files'));
    await _pumpUntilFound(tester, find.text('My files').last, timeout: const Duration(seconds: 15));
    await _snap(boundaryKey, '03_files');

    await tester.tap(find.text('Shared'));
    await Future<void>.delayed(const Duration(seconds: 3));
    await _snap(boundaryKey, '04_shared');

    await tester.tap(find.text('Photos'));
    await _pumpUntilFound(tester, find.text('My files').last, timeout: const Duration(seconds: 15));
    await Future<void>.delayed(const Duration(seconds: 2));
    await _snap(boundaryKey, '05_photos');

    await tester.tap(find.text('Trash'));
    await Future<void>.delayed(const Duration(seconds: 2));
    await _snap(boundaryKey, '06_trash');

    await tester.tap(find.text('Settings'));
    await _pumpUntilFound(tester, find.text('Sign out'), timeout: const Duration(seconds: 15));
    await _snap(boundaryKey, '07_settings');
  });
}