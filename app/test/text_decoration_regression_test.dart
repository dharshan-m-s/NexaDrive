import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexadrive/core/design/app_theme.dart';
import 'package:nexadrive/core/design/app_typography.dart';
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

/// Regression guard for the "unintended underlines across normal UI text"
/// report on the Update Center and Users screens.
///
/// The diagnosis is in `doc/diagnostics/DEBUG_TEXT_UNDERLINE_DIAGNOSIS.md`: no
/// `TextDecoration.underline` exists anywhere in NexaDrive's styles. The "green
/// or yellow line under every line of text" users saw is Flutter's *debug*
/// baseline visualisation (`debugPaintBaselinesEnabled`), which paints the
/// alphabetic baseline in `0x00FF00` and the ideographic baseline in
/// `0xFFFFD000` beneath every glyph. The paint sites are assert-gated, so they
/// cannot render in a release build, and `main()` clears the flags at startup.
///
/// These tests pin both screens at the widget level so a shared typography
/// regression (either a real underline decoration or a leaked debug flag)
/// cannot return unnoticed:
///  - every rendered `Text` widget must carry an effective style whose
///    decoration is neither underline nor line-through, in light and dark;
///  - the baseline debug flag must be off while the screens render;
///  - the shared `AppTextStyle` tokens used by both screens are decorations
///    free (the component-level style set, distinct from the ThemeData
///    `textTheme` already covered by `debug_rendering_guard_test.dart`).
void main() {
  for (final theme in {
    'light': AppTheme.light(),
    'dark': AppTheme.dark(),
  }.entries) {
    group('${theme.key} theme', () {
      testWidgets(
          'update center text has no underline decoration in every state',
          (tester) async {
        for (final status in const [
          UpdateStatus.idle,
          UpdateStatus.updateAvailable,
          UpdateStatus.paused,
          UpdateStatus.cancelled,
        ]) {
          final controller = await buildController();
          controller.status = status;
          if (status == UpdateStatus.paused) {
            controller.receivedBytes = 18874368;
            controller.totalBytes = 52428800;
            controller.progress = 18874368 / 52428800;
          }
          await pump(tester, theme.value,
              UpdateCenterScreen(controller: controller));
          expect(debugPaintBaselinesEnabled, isFalse,
              reason: 'The debug baseline overlay paints a line under every '
                  'line of text and must not be on during a normal render.');
          expectNoUnderline(tester);
        }
      });

      testWidgets('update center representative labels render clean',
          (tester) async {
        final controller = await buildController();
        controller.status = UpdateStatus.updateAvailable;
        await pump(tester, theme.value,
            UpdateCenterScreen(controller: controller));
        for (final label in const [
          'Update center',
          'Current version',
          'RELEASE DETAILS',
          'Update available',
          '1.4.0',
        ]) {
          expect(find.text(label), findsOneWidget, reason: label);
        }
        expectNoUnderline(tester);
      });

      testWidgets('users admin text has no underline decoration',
          (tester) async {
        await pump(tester, theme.value, AdminUsersScreen(api: _FakeApi()));
        expect(debugPaintBaselinesEnabled, isFalse,
            reason: 'The debug baseline overlay paints a line under every '
                'line of text and must not be on during a normal render.');
        expectNoUnderline(tester);
      });

      testWidgets('users admin representative labels render clean',
          (tester) async {
        await pump(tester, theme.value, AdminUsersScreen(api: _FakeApi()));
        expect(find.text('Ada Lovelace'), findsOneWidget);
        expect(find.text('Grace Hopper'), findsOneWidget);
        expect(find.text('Admin'), findsOneWidget);
        expect(find.text('@grace · Unlimited storage'), findsOneWidget);
        expect(find.text('You'), findsOneWidget);
        expectNoUnderline(tester);
      });
    });
  }

  group('shared AppTextStyle tokens carry no text decoration', () {
    test('no token uses underline or line-through', () {
      const composition = <String, TextStyle>{
        'pageTitle': AppTextStyle.pageTitle,
        'display': AppTextStyle.display,
        'heroTitle': AppTextStyle.heroTitle,
        'metricValue': AppTextStyle.metricValue,
        'statValue': AppTextStyle.statValue,
        'sectionHeader': AppTextStyle.sectionHeader,
        'listHeader': AppTextStyle.listHeader,
        'rowTitle': AppTextStyle.rowTitle,
        'rowSubtitle': AppTextStyle.rowSubtitle,
        'caption': AppTextStyle.caption,
        'micro': AppTextStyle.micro,
        'navLabel': AppTextStyle.navLabel,
        'chipLabel': AppTextStyle.chipLabel,
        'button': AppTextStyle.button,
        'buttonSmall': AppTextStyle.buttonSmall,
        'dialogTitle': AppTextStyle.dialogTitle,
      };
      final offenders = <String>[];
      for (final entry in composition.entries) {
        final decoration = entry.value.decoration;
        if (decoration == TextDecoration.underline ||
            decoration == TextDecoration.lineThrough) {
          offenders.add('${entry.key}: $decoration');
        }
      }
      expect(offenders, isEmpty,
          reason: 'AppTextStyle is the shared style source for both screens; '
              'an underline here would underline every consumer.');
    });
  });
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

Future<void> pump(WidgetTester tester, ThemeData theme, Widget screen) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Scaffold(body: screen),
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}

/// Asserts that every `Text` widget rendered on screen resolves to a style
/// with no underline or line-through decoration. The effective style is the
/// inherited `DefaultTextStyle` merged with the widget's own `style`, which is
/// exactly what the renderer uses for the glyphs.
void expectNoUnderline(WidgetTester tester) {
  final texts = find.byType(Text);
  expect(texts, findsWidgets,
      reason: 'The screen must render text before decoration can be checked.');
  final offenders = <String>[];
  for (final element in texts.evaluate()) {
    final text = element.widget as Text;
    final effective = DefaultTextStyle.of(element).style.merge(text.style);
    final decoration = effective.decoration;
    if (decoration == TextDecoration.underline ||
        decoration == TextDecoration.lineThrough) {
      offenders.add('${text.data ?? text.textSpan?.toPlainText()}: '
          '$decoration');
    }
  }
  expect(offenders, isEmpty,
      reason: 'Normal UI text must never render with an underline or '
          'line-through decoration.');
}

class _FakeApi extends Api {
  _FakeApi() : super(_mockSession());

  static Session _mockSession() {
    final session = Session();
    session.serverUrl = 'https://example.com';
    session.token = 'tok';
    session.username = 'ada';
    session.userId = '1';
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