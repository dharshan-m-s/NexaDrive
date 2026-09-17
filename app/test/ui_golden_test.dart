import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexadrive/core/design/app_theme.dart';
import 'package:nexadrive/services/api.dart';
import 'package:nexadrive/services/session.dart';
import 'package:nexadrive/ui/screens/admin/admin_users_screen.dart';
import 'package:nexadrive/ui/screens/settings/update_center_screen.dart';
import 'package:nexadrive/update/app_platform.dart';
import 'package:nexadrive/update/semver.dart';
import 'package:nexadrive/update/update_controller.dart';
import 'package:nexadrive/update/update_downloader.dart';
import 'package:nexadrive/update/update_manifest.dart';
import 'package:nexadrive/update/update_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<String> _flutterRoot() async {
  final result = await Process.run('which', ['flutter']);
  final bin = result.stdout.toString().trim();
  try {
    final resolved = await File(bin).resolveSymbolicLinks();
    return File(resolved).parent.parent.path;
  } catch (_) {
    return '/opt/flutter';
  }
}

Future<ByteData> _font(File file) async {
  final bytes = await file.readAsBytes();
  return bytes.buffer.asByteData();
}

/// Renders [UpdateCenterScreen] and [AdminUsersScreen] to PNG goldens so the
/// real layout can be inspected visually without a device. Run with
/// `flutter test --update-goldens test/ui_golden_test.dart`.
void main() {
  setUpAll(() async {
    final flutterRoot = await _flutterRoot();
    final fontDir = Directory(
      '$flutterRoot/bin/cache/artifacts/material_fonts',
    );
    if (fontDir.existsSync()) {
      final robo = <String, String>{
        'Roboto-Regular.ttf': 'Roboto',
        'Roboto-Medium.ttf': 'Roboto',
        'Roboto-Bold.ttf': 'Roboto',
        'Roboto-Italic.ttf': 'Roboto',
      };
      for (final entry in robo.entries) {
        final file = File('${fontDir.path}/${entry.key}');
        if (!file.existsSync()) continue;
        final loader = FontLoader(entry.value)
          ..addFont(_font(file).then((value) => Future<ByteData>.value(value)));
        await loader.load();
      }
      final iconsFile = File('${fontDir.path}/MaterialIcons-Regular.otf');
      if (iconsFile.existsSync()) {
        final loader = FontLoader('MaterialIcons')
          ..addFont(_font(iconsFile).then((value) => Future<ByteData>.value(value)));
        await loader.load();
      }
    }
  });

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
    const sha = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    controller.manifest = UpdateManifest.fromJson(const {
      'version': '1.4.0',
      'tag': 'v1.4.0',
      'releaseDate': '2026-09-10T12:00:00Z',
      'prerelease': false,
      'minimumSupportedVersion': '1.0.0',
      'releaseNotes': {
        'New features': ['Faster background sync', 'Folder navigation shortcuts'],
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

  ThemeData lightTheme() => AppTheme.light();

  Future<void> pumpScreen(
    WidgetTester tester,
    Widget home,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: lightTheme(),
        home: Scaffold(body: home),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
  }

  testWidgets('update center golden', (tester) async {
    await pumpScreen(tester, UpdateCenterScreen(controller: await buildController()));
    await expectLater(
      find.byType(UpdateCenterScreen),
      matchesGoldenFile('goldens/update_center_light.png'),
    );
  });

  testWidgets('users admin golden', (tester) async {
    await pumpScreen(tester, AdminUsersScreen(api: _FakeApi()));
    await expectLater(
      find.byType(AdminUsersScreen),
      matchesGoldenFile('goldens/admin_users_light.png'),
    );
  });
}

class _FakeApi extends Api {
  _FakeApi() : super(_mockSession());

  static Session _mockSession() {
    final session = Session();
    session.serverUrl = 'https://example.com';
    session.token = 'tok';
    return session;
  }

  @override
  Future<List<Map<String, dynamic>>> users() async => const [
        {
          'id': '1',
          'username': 'ada',
          'display_name': 'Ada Lovelace',
          'role': 'admin',
          'quota_bytes': 26843545600,
          'disabled': false,
        },
        {
          'id': '2',
          'username': 'grace',
          'display_name': 'Grace Hopper',
          'role': 'user',
          'quota_bytes': null,
          'disabled': false,
        },
        {
          'id': '3',
          'username': 'alex',
          'display_name': 'Alex',
          'role': 'user',
          'quota_bytes': 5368709120,
          'disabled': true,
        },
      ];
}