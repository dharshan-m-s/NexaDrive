import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexadrive/core/design/app_theme.dart';
import 'package:nexadrive/services/api.dart';
import 'package:nexadrive/services/session.dart';
import 'package:nexadrive/ui/screens/admin/users_screen.dart';
import 'package:nexadrive/ui/screens/settings/update_center_screen.dart';
import 'package:nexadrive/update/app_platform.dart';
import 'package:nexadrive/update/semver.dart';
import 'package:nexadrive/update/update_controller.dart';
import 'package:nexadrive/update/update_downloader.dart';
import 'package:nexadrive/update/update_manifest.dart';
import 'package:nexadrive/update/update_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Real-layout QA sweep for the rebuilt screens, executed through the actual
/// Flutter layout/render pipeline (not goldens, which this repo's CI cannot
/// reproduce bit-exact). Every state is pumped at every window size in both
/// themes; any overflow, unconstrained-flex error, layout exception or paint
/// exception fails the run.
///
/// Sizes cover narrow desktop, short-height, standard, wide and very wide —
/// the shapes the manual window-resize QA pass exercises.
void main() {
  final sizes = <String, Size>{
    'narrow (500x600)': const Size(500, 600),
    'short (800x480)': const Size(800, 480),
    'standard (1280x800)': const Size(1280, 800),
    'wide (1920x1080)': const Size(1920, 1080),
    'very wide (2560x1440)': const Size(2560, 1440),
  };

  for (final themeEntry in {
    'light': AppTheme.light(),
    'dark': AppTheme.dark(),
  }.entries) {
    group('update center layout QA (${themeEntry.key})', () {
      for (final sizeEntry in sizes.entries) {
        testWidgets('no layout errors at ${sizeEntry.key}', (tester) async {
          final controller = await buildController();
          for (final status in const [
            UpdateStatus.idle,
            UpdateStatus.checking,
            UpdateStatus.upToDate,
            UpdateStatus.updateAvailable,
            UpdateStatus.mandatory,
            UpdateStatus.paused,
            UpdateStatus.readyToInstall,
            UpdateStatus.installingHandoff,
            UpdateStatus.completed,
            UpdateStatus.failed,
            UpdateStatus.offline,
            UpdateStatus.unsupported,
            UpdateStatus.needsUserAction,
            UpdateStatus.cancelled,
          ]) {
            controller.status = status;
            if (status == UpdateStatus.paused) {
              controller.receivedBytes = 18874368;
              controller.totalBytes = 52428800;
              controller.progress = 18874368 / 52428800;
            }
            if (status == UpdateStatus.failed) {
              controller.selectedArtifact = null;
              controller.errorMessage = 'The download failed verification.';
            }
            await tester.binding.setSurfaceSize(sizeEntry.value);
            addTearDown(() => tester.binding.setSurfaceSize(null));
            await tester.pumpWidget(
              MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: themeEntry.value,
                home:
                    Scaffold(body: UpdateCenterScreen(controller: controller)),
              ),
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 120));
            final exception = tester.takeException();
            expect(exception, isNull,
                reason:
                    '${themeEntry.key} ${sizeEntry.key} $status: $exception');
          }
        });
      }
    });

    group('users layout QA (${themeEntry.key})', () {
      for (final sizeEntry in sizes.entries) {
        testWidgets('no layout errors at ${sizeEntry.key}', (tester) async {
          final api = _ScriptedApi();
          await tester.binding.setSurfaceSize(sizeEntry.value);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: themeEntry.value,
              home: Scaffold(body: UsersScreen(api: api)),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 120));
          final loadingException = tester.takeException();
          expect(loadingException, isNull,
              reason: '${themeEntry.key} ${sizeEntry.key} loading');

          await tester.pumpAndSettle();
          final populatedException = tester.takeException();
          expect(populatedException, isNull,
              reason: '${themeEntry.key} ${sizeEntry.key} populated');

          // The editor sheet: the layout most at risk on narrow windows.
          await tester.tap(find.text('Grace Hopper'));
          await tester.pumpAndSettle();
          final sheetException = tester.takeException();
          expect(sheetException, isNull,
              reason: '${themeEntry.key} ${sizeEntry.key} editor sheet');

          // The actions sheet with a long, unbroken protection note.
          await tester.tap(find.byTooltip('Account actions').at(0));
          await tester.pumpAndSettle();
          final actionsException = tester.takeException();
          expect(actionsException, isNull,
              reason: '${themeEntry.key} ${sizeEntry.key} actions sheet');
        });
      }
    });
  }

  group('users overflow resilience', () {
    testWidgets('long usernames and emails never overflow a row',
        (tester) async {
      final api = _ScriptedApi(
        overrideUsers: [
          {
            'id': 'self',
            'username':
                'extremely-long-username-that-keeps-going-and-going-and-going',
            'display_name':
                'Bartholomew Montgomery Fitzgerald Von Hohenzollern-Sigmaringen',
            'role': 'admin',
            'disabled': false,
            'quota_bytes': 27 * 1024 * 1024 * 1024,
          },
          {
            'id': '2',
            'username': 'user.with.an.extremely.long.email.like.name@'
                'some-very-long-corporate-subdomain.example-corporation.com',
            'display_name': 'Email Edge Case',
            'role': 'user',
            'disabled': false,
            'quota_bytes': null,
          },
        ],
      );
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home: Scaffold(body: UsersScreen(api: api)),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'a 360px window with pathological names must not overflow');
    });
  });
}

class _ScriptedApi extends Api {
  _ScriptedApi({this.overrideUsers}) : super(_session());

  final List<Map<String, dynamic>>? overrideUsers;

  static Session _session() {
    final s = Session()
      ..serverUrl = 'https://example.com'
      ..token = 'tok'
      ..username = 'root';
    s.userId = 'self';
    return s;
  }

  @override
  Future<List<Map<String, dynamic>>> users() async =>
      overrideUsers ??
      [
        {
          'id': 'self',
          'username': 'root',
          'display_name': 'Administrator',
          'role': 'admin',
          'disabled': false,
          'quota_bytes': 25 * 1024 * 1024 * 1024,
        },
        {
          'id': '2',
          'username': 'grace',
          'display_name': 'Grace Hopper',
          'role': 'user',
          'disabled': false,
          'quota_bytes': 10 * 1024 * 1024 * 1024,
        },
        {
          'id': '3',
          'username': 'alex',
          'display_name': 'Alex',
          'role': 'user',
          'disabled': true,
          'quota_bytes': null,
        },
      ];
}

Future<UpdateController> buildController() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final source = UpdateSource(baseUrl: 'https://example.com/manifest.json');
  final controller = UpdateController(
    source: source,
    downloader: UpdateDownloader(source: source),
    detector: const AppPlatformDetector(),
    selector: const ArtifactSelector(),
    preferences: UpdatePreferences(prefs),
    router: const UpdateRouter(),
    loadCurrentVersion: () async => '1.2.1',
  );
  controller.status = UpdateStatus.updateAvailable;
  controller.currentVersion = SemVersion.tryParse('1.2.1');
  controller.archLabel = 'arm64-v8a';
  controller.selectedArtifact = const ArtifactInfo(
    'https://example.com/releases/nexadrive_1.4.0.apk',
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    52428800,
  );
  const sha =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  controller.manifest = UpdateManifest.fromJson(const {
    'version': '1.4.0',
    'tag': 'v1.4.0',
    'releaseDate': '2026-09-10T12:00:00Z',
    'prerelease': false,
    'minimumSupportedVersion': '1.0.0',
    'releaseNotes': {
      'New features': [
        'Faster background sync with a fairly long description to wrap',
        'Folder navigation shortcuts',
      ],
      'Fixes': [
        'Photos now open at full resolution',
        'Uploads retry automatically when the network drops',
        'Fixed a crash on very large folders',
      ],
    },
    'artifacts': {
      'android': {
        'arm64-v8a': {
          'apk': {
            'url': 'https://example.com/releases/nexadrive_1.4.0.apk',
            'sha256': sha,
            'size': 52428800,
          },
        },
      },
    },
  });
  return controller;
}
