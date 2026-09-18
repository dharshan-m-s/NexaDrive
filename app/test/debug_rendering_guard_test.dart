import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexadrive/core/design/app_theme.dart';

/// Guards the two ways a "line under every line of text" can reach a user.
///
/// 1. A real typography bug: an underline `TextDecoration` baked into the
///    design system or a component theme.
/// 2. Flutter's *debug* visualisation of text baselines
///    (`debugPaintBaselinesEnabled`), which paints the alphabetic baseline in
///    `0x00FF00` and the ideographic baseline in `0xFFFFD000` beneath every
///    line of text. The paint sites are wrapped in `assert(() { ... }())`, so
///    they cannot render in a release build — but they are easy to mistake for
///    a typography regression while running in debug.
///
/// See `doc/diagnostics/DEBUG_TEXT_UNDERLINE_DIAGNOSIS.md`.
void main() {
  group('no debug visualisation leaks into the shipped UI', () {
    test('no rendering debug variable is left enabled', () {
      expect(debugPaintBaselinesEnabled, isFalse,
          reason: 'debugPaintBaselinesEnabled paints green/amber underlines '
              'beneath every line of text and must never be enabled.');
      expect(debugPaintSizeEnabled, isFalse);
      expect(debugPaintLayerBordersEnabled, isFalse);
      expect(debugPaintPointersEnabled, isFalse);
      expect(debugRepaintRainbowEnabled, isFalse);
      expect(debugDisableClipLayers, isFalse);
      expect(debugDisablePhysicalShapeLayers, isFalse);
    });

    test('no source file enables a debug paint flag', () {
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        for (final flag in const [
          'debugPaintBaselinesEnabled = true',
          'debugPaintSizeEnabled = true',
          'debugPaintLayerBordersEnabled = true',
          'debugPaintPointersEnabled = true',
          'debugRepaintRainbowEnabled = true',
        ]) {
          if (source.replaceAll(RegExp(r'\s+'), ' ').contains(flag)) {
            offenders.add('${entity.path}: $flag');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'Diagnostic rendering must not be committed; it produced the '
              'false "yellow/green underline" typography report.');
    });
  });

  group('text styles carry no underline decoration', () {
    for (final entry in {
      'light': AppTheme.light(),
      'dark': AppTheme.dark(),
    }.entries) {
      test('${entry.key} theme textTheme is clean', () {
        final offenders = <String>[];
        for (final style in _allTextStyles(entry.value)) {
          if (style.decoration == null) continue;
          if (style.decoration == TextDecoration.none) continue;
          offenders.add('${style.fontSize} ${style.fontWeight} '
              '${style.decoration}');
        }
        expect(offenders, isEmpty,
            reason: 'Every line of text in the ${entry.key} theme would be '
                'underlined, which is never intended.');
      });
    }
  });
}

/// Every [TextStyle] reachable from a [ThemeData] — the text theme plus the
/// component themes that app bar/button/input/dialog/tab text flows through.
Iterable<TextStyle> _allTextStyles(ThemeData theme) sync* {
  final named = <TextStyle?>[
    theme.textTheme.displayLarge,
    theme.textTheme.displayMedium,
    theme.textTheme.displaySmall,
    theme.textTheme.headlineLarge,
    theme.textTheme.headlineMedium,
    theme.textTheme.headlineSmall,
    theme.textTheme.titleLarge,
    theme.textTheme.titleMedium,
    theme.textTheme.titleSmall,
    theme.textTheme.bodyLarge,
    theme.textTheme.bodyMedium,
    theme.textTheme.bodySmall,
    theme.textTheme.labelLarge,
    theme.textTheme.labelMedium,
    theme.textTheme.labelSmall,
    theme.appBarTheme.titleTextStyle,
    theme.appBarTheme.toolbarTextStyle,
    theme.dialogTheme.titleTextStyle,
    theme.dialogTheme.contentTextStyle,
    theme.tabBarTheme.labelStyle,
    theme.tabBarTheme.unselectedLabelStyle,
    theme.listTileTheme.titleTextStyle,
    theme.listTileTheme.subtitleTextStyle,
    theme.filledButtonTheme.style?.textStyle?.resolve({}),
    theme.outlinedButtonTheme.style?.textStyle?.resolve({}),
    theme.textButtonTheme.style?.textStyle?.resolve({}),
    theme.inputDecorationTheme.labelStyle,
    theme.inputDecorationTheme.hintStyle,
    theme.inputDecorationTheme.helperStyle,
    theme.inputDecorationTheme.errorStyle,
  ];
  for (final style in named) {
    if (style != null) yield style;
  }
}
