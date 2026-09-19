import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexadrive/core/design/app_theme.dart';
import 'package:nexadrive/ui/screens/settings/update_center_screen.dart';
import 'package:nexadrive/update/app_platform.dart';
import 'package:nexadrive/update/semver.dart';
import 'package:nexadrive/update/update_controller.dart';
import 'package:nexadrive/update/update_downloader.dart';
import 'package:nexadrive/update/update_manifest.dart';
import 'package:nexadrive/update/update_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Guards the Update Center's primary action.
///
/// The icon variant ("Resume download") used to wrap a `FilledButton.icon`
/// inside an outer `FilledButton`. That painted two stacked pill surfaces for
/// one action and gave the same tap two claimants, so the state that offers a
/// resume button is the one worth pinning.
void main() {
  testWidgets('the primary action is exactly one button, never nested',
      (tester) async {
    for (final status in const [
      UpdateStatus.updateAvailable, // text-shaped action
      UpdateStatus.paused, // icon-shaped action
    ]) {
      final controller = await _controller();
      controller.status = status;
      if (status == UpdateStatus.paused) {
        controller.receivedBytes = 1024;
        controller.totalBytes = 4096;
        controller.progress = 0.25;
      }
      await _pump(tester, controller);

      expect(
        find.descendant(
          of: find.byType(FilledButton),
          matching: find.byType(FilledButton),
        ),
        findsNothing,
        reason: '$status: an action must never nest one button inside another',
      );
      expect(
        find.byType(FilledButton),
        findsOneWidget,
        reason: '$status: exactly one primary action is offered',
      );
    }
  });

  testWidgets('tapping Resume download fires resume exactly once',
      (tester) async {
    final controller = await _controller();
    controller.status = UpdateStatus.paused;
    controller.receivedBytes = 1024;
    controller.totalBytes = 4096;
    controller.progress = 0.25;
    await _pump(tester, controller);

    final button = find.widgetWithText(FilledButton, 'Resume download');
    expect(button, findsOneWidget);

    await tester.tap(button);
    await tester.pump();

    expect(controller.resumeCalls, 1,
        reason: 'one tap must dispatch one action, not one per stacked button');
    expect(tester.takeException(), isNull);
  });
}

Future<_CountingController> _controller() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final source = UpdateSource(baseUrl: 'https://example.com/manifest.json');
  final controller = _CountingController(
    source: source,
    downloader: UpdateDownloader(source: source),
    detector: const AppPlatformDetector(),
    selector: const ArtifactSelector(),
    preferences: UpdatePreferences(prefs),
    router: const UpdateRouter(),
  );
  controller.currentVersion = SemVersion.tryParse('1.2.1');
  controller.archLabel = 'arm64-v8a';
  controller.selectedArtifact = const ArtifactInfo(
    'https://example.com/releases/nexadrive_1.4.0.apk',
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    52428800,
  );
  controller.manifest = UpdateManifest.fromJson(const {
    'version': '1.4.0',
    'tag': 'v1.4.0',
    'releaseDate': '2026-09-10T12:00:00Z',
    'prerelease': false,
    'minimumSupportedVersion': '1.0.0',
    'releaseNotes': {
      'New features': ['Faster background sync'],
      'Fixes': ['Uploads retry automatically when the network drops'],
    },
    'artifacts': {
      'android': {
        'arm64-v8a': {
          'apk': {
            'url': 'https://example.com/releases/nexadrive_1.4.0.apk',
            'sha256':
                'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            'size': 52428800,
          },
        },
      },
    },
  });
  return controller;
}

Future<void> _pump(WidgetTester tester, UpdateController controller) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Scaffold(body: UpdateCenterScreen(controller: controller)),
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}

/// Counts resume attempts so a double-dispatch bug is visible as a number
/// rather than as a silently duplicated download.
class _CountingController extends UpdateController {
  _CountingController({
    required super.source,
    required super.downloader,
    required super.detector,
    required super.selector,
    required super.preferences,
    required super.router,
  }) : super(loadCurrentVersion: () async => '1.2.1');

  int resumeCalls = 0;

  @override
  Future<void> resume() async {
    resumeCalls++;
  }
}
