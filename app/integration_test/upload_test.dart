import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nexadrive/main.dart';
import 'package:nexadrive/ui/shell/app_shell.dart';
import 'package:nexadrive/ui/widgets/upload_progress_dialog.dart';
import 'package:nexadrive/services/api.dart';
import 'package:nexadrive/services/session.dart';
import 'package:nexadrive/services/transfer_queue.dart';
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

Future<String> _sha256File(File file) async {
  return sha256.bind(file.openRead()).join();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'real MULTI-CHUNK (20 MB) upload through the progress dialog + download round-trip (live server)',
      (tester) async {
    final config = LiveTestConfig.require();
    final session = Session();

    await tester.pumpWidget(NexaDriveApp(session: session, prefs: await SharedPreferences.getInstance()));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3));
    await tester.enterText(fields.at(0), config.serverUrl);
    await tester.enterText(fields.at(1), config.username);
    await tester.enterText(fields.at(2), config.password);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await _pumpUntilFound(tester, find.byType(AppShell), timeout: const Duration(seconds: 45));
    await _pumpUntilFound(tester, find.textContaining('Administrator'), timeout: const Duration(seconds: 30));

    final api = Api(session);
    const name = 'upload-e2e-20mb.bin';
    final tmpDir = await Directory.systemTemp.createTemp('nexadrive-e2e');
    final src = File('${tmpDir.path}/$name');
    final rng = Random(42);
    // 20 MB deterministic file -> exercises the 8 MB chunked/resumable path.
    final writeSink = src.openWrite();
    for (var i = 0; i < 20; i++) {
      final block = List<int>.generate(1 << 20, (_) => rng.nextInt(256));
      writeSink.add(block);
    }
    await writeSink.close();
    final size = src.lengthSync();
    expect(size, greaterThan(TransferQueue.chunkSize),
        reason: 'file must span at least two chunks (TransferQueue.chunkSize = 8 MB)');
    final expectedDigest = (await _sha256File(src));

    // Drive the upload-progress dialog for a real multi-chunk upload to root.
    final context = tester.element(find.byType(AppShell));
    unawaited(UploadProgressDialog.showPaths(
      context,
      api: api,
      paths: [src.path],
      folder: '',
    ));

    await _pumpUntilFound(tester, find.byType(AlertDialog), timeout: const Duration(seconds: 15));

    // Watch progress advance: bytes text should move beyond 0 to confirm chunking.
    bool sawProgress = false;
    final doneText = find.byWidgetPredicate(
      (w) =>
          w is Text &&
          (w.data == 'Upload complete' || w.data == 'Upload finished with issues'),
    );
    bool terminal = false;
    final end = DateTime.now().add(const Duration(seconds: 120));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 250));
      final match = doneText.evaluate();
      if (match.isNotEmpty) {
        terminal = true;
        break;
      }
      if (find.textContaining(' MB of ').evaluate().isNotEmpty) {
        sawProgress = true;
      }
    }

    debugPrint('=== DIALOG TEXTS @ terminal=$terminal sawProgress=$sawProgress ===');
    for (final e in find
        .descendant(of: find.byType(AlertDialog), matching: find.byType(Text))
        .evaluate()) {
      debugPrint('TEXT: ${(e.widget as Text).data}');
    }
    final items = await TransferQueue(api).items();
    debugPrint('=== QUEUE ITEMS (${items.length}) ===');
    for (final item in items) {
      debugPrint('${item.name} status=${item.status} err=${item.error} bytes=${item.transferred}/${item.size}');
    }

    expect(sawProgress, isTrue, reason: 'progress text should be observed during a 20 MB upload');
    expect(terminal, isTrue, reason: 'upload dialog must reach a terminal state');
    expect(find.text('Upload complete'), findsOneWidget,
        reason: 'upload must succeed, not report issues');
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    // The file must be listed remotely.
    final entries = await api.listFiles('');
    final names = entries.map((e) => (e['name'] ?? '').toString()).toList();
    expect(names.contains(name), isTrue, reason: 'uploaded file should be listed at server root');

    // Full download round-trip: bytes and SHA-256 must match the source.
    final dl = File('${tmpDir.path}/dl-$name');
    await api.downloadToFile(name, dl.path);
    final remoteDigest = (await _sha256File(dl));
    expect(remoteDigest, expectedDigest, reason: 'downloaded file must be byte-identical');
    // ignore: avoid_print
    print('ROUND-TRIP OK: $size bytes, sha256=$remoteDigest, chunks=${(size / TransferQueue.chunkSize).ceil()}');

    // Clean up: trash + purge the test file.
    await api.delete(name);
    final trash = await api.trash();
    String? id;
    for (final e in trash) {
      if ((e['name'] ?? '').toString() == name) {
        id = (e['id'] ?? '').toString();
        break;
      }
    }
    if (id != null && id.isNotEmpty) await api.permanentlyDeleteTrash(id);
    dl.deleteSync();
    try {
      tmpDir.deleteSync(recursive: true);
    } catch (_) {}
  });
}