import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexadrive/core/design/app_theme.dart';
import 'package:nexadrive/core/design/app_typography.dart';
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

/// Regression guard for the "unintended underlines across normal UI text"
/// report on the Update Center and Users screens.
///
/// Two mechanisms can draw a line under text:
///
///  1. A real `TextDecoration.underline` in a style (none exists in
///     NexaDrive's tokens; this file pins that at the widget level).
///  2. Flutter's *debug* baseline visualisation
///     (`debugPaintBaselinesEnabled`), which paints the alphabetic baseline in
///     `0x00FF00` (green) and the ideographic baseline in `0xFFFFD000` (amber)
///     beneath every glyph — the actual root cause of the original report.
///     The paint sites are assert-gated, so they cannot render in a release
///     build, and `main()` clears the flags at startup.
///
/// Both rebuilt screens are pinned here in light and dark, across their main
/// states, so neither a typography regression nor a leaked debug flag can
/// return unnoticed.
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
          UpdateStatus.failed,
          UpdateStatus.offline,
          UpdateStatus.needsUserAction,
        ]) {
          final controller = await buildController();
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
          await pump(
              tester, theme.value, UpdateCenterScreen(controller: controller));
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
        await pump(
            tester, theme.value, UpdateCenterScreen(controller: controller));
        for (final label in const [
          'Update center',
          'CURRENT',
          'LATEST',
          'v1.2.1',
          'v1.4.0',
          'Update available',
          'Download & install',
        ]) {
          expect(find.text(label), findsOneWidget, reason: label);
        }
        expectNoUnderline(tester);
      });

      testWidgets('users admin text has no underline decoration',
          (tester) async {
        await pump(tester, theme.value, UsersScreen(api: _FakeApi()));
        expect(debugPaintBaselinesEnabled, isFalse,
            reason: 'The debug baseline overlay paints a line under every '
                'line of text and must not be on during a normal render.');
        expectNoUnderline(tester);
      });

      testWidgets('users admin representative labels render clean',
          (tester) async {
        await pump(tester, theme.value, UsersScreen(api: _FakeApi()));
        expect(find.text('Ada Lovelace'), findsOneWidget);
        expect(find.text('Grace Hopper'), findsOneWidget);
        expect(find.text('Admin'), findsOneWidget);
        expect(find.textContaining('@grace'), findsOneWidget);
        expect(find.text('You'), findsOneWidget);
        expectNoUnderline(tester);
      });
    });
  }

  // Root cause found 2026-09-26, after three earlier passes wrongly blamed the
  // debug baseline overlay. When a page is pushed as a bare route it has no
  // Scaffold, and therefore no Material ancestor. Text outside a Material
  // inherits MaterialApp's diagnostic fallback style (`_errorTextStyle` in
  // material/app.dart): monospace, 48px, and a *double* underline in pure
  // yellow 0xFFFFFF00, labelled "fallback style; consider putting your text in
  // a Material". The routed Update Center and Users pages have no Scaffold of
  // their own, so in a real release APK their headers rendered with a yellow
  // double underline. `OneUiPage` now provides a transparent Material.
  //
  // Every other test in this file wraps the screen in a Scaffold, which
  // supplies a Material and therefore masks the bug. These tests reproduce the
  // shape the app actually ships.
  group('routed pages with no Scaffold do not inherit the fallback style', () {
    for (final theme in {
      'light': AppTheme.light(),
      'dark': AppTheme.dark(),
    }.entries) {
      testWidgets('${theme.key}: update center renders with no underline',
          (tester) async {
        final controller = await buildController();
        controller.status = UpdateStatus.updateAvailable;
        await pumpRouted(
            tester, theme.value, UpdateCenterScreen(controller: controller));
        expect(find.text('Update center'), findsOneWidget);
        expectNoUnderline(tester);
      });

      testWidgets('${theme.key}: users renders with no underline',
          (tester) async {
        await pumpRouted(tester, theme.value, UsersScreen(api: _FakeApi()));
        expect(find.text('Users'), findsOneWidget);
        expectNoUnderline(tester);
      });
    }
  });

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
  const sha =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
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

/// Pumps [screen] the way the app actually ships it: as the body of a bare
/// `MaterialPageRoute`, with no Scaffold and therefore no Material ancestor.
/// This is the only shape in which Flutter's fallback `DefaultTextStyle` can
/// reach the text, so decoration checks must run through this helper too.
Future<void> pumpRouted(
    WidgetTester tester, ThemeData theme, Widget screen) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: screen,
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
