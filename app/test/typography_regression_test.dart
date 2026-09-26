import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexadrive/core/design/app_theme.dart';
import 'package:nexadrive/core/design/app_typography.dart';

/// Typography regression test for the design system in isolation.
///
/// This exercises the text-rendering chain that every screen shares — the
/// shared [AppTextStyle] tokens, the light/dark [ThemeData] and Material
/// component text (buttons, disabled labels) — without depending on any
/// particular screen. It is the controlled experiment for "is the visible line
/// a real `TextDecoration`?", and it pins the rule the whole product relies on:
///
///   * normal text is never decorated — headings, body copy, labels, button
///     text, version numbers, rich text and disabled text are all plain;
///   * only an explicitly designated link may carry a decoration.
///
/// If a shared token, a theme slot, or a component theme ever grows an
/// underline, this fails immediately and points at the offending widget.
void main() {
  const linkKey = Key('designated-link');
  const version = '1.1.0';

  Widget subject(ThemeData theme) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Heading.
                const Text('Update center', style: AppTextStyle.pageTitle),
                // Body text.
                const Text('You are on the latest version.',
                    style: AppTextStyle.rowTitle),
                const Text('Downloads resume automatically.',
                    style: AppTextStyle.rowSubtitle),
                // Label / metadata.
                const Text('RELEASE DETAILS', style: AppTextStyle.listHeader),
                const Text('Last checked: just now',
                    style: AppTextStyle.caption),
                const Text('arm64-v8a', style: AppTextStyle.micro),
                // Version number.
                const Text(version, style: AppTextStyle.metricValue),
                // Rich text (TextSpan tree).
                const Text.rich(
                  TextSpan(
                    style: AppTextStyle.rowSubtitle,
                    children: [
                      TextSpan(text: 'Minimum server version '),
                      TextSpan(
                          text: '1.0.0',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                // Button text (enabled) and disabled text (disabled button).
                FilledButton(
                    onPressed: () {}, child: const Text('Check again')),
                const FilledButton(onPressed: null, child: Text('Unavailable')),
                // The ONE intentionally decorated element: a designated link.
                Text('Release notes',
                    key: linkKey,
                    style: AppTextStyle.rowSubtitle
                        .copyWith(decoration: TextDecoration.underline)),
              ],
            ),
          ),
        ),
      );

  for (final theme in {
    'light': AppTheme.light(),
    'dark': AppTheme.dark(),
  }.entries) {
    testWidgets('${theme.key}: only the designated link is decorated',
        (tester) async {
      await tester.pumpWidget(subject(theme.value));
      await tester.pump();

      final decorated = <String>[];
      var sawLink = false;
      var sawDisabled = false;

      for (final element in find.byType(Text).evaluate()) {
        final text = element.widget as Text;
        final label = text.data ?? text.textSpan?.toPlainText() ?? '';
        final effective = DefaultTextStyle.of(element).style.merge(text.style);
        final decoration = effective.decoration;
        final isLink = element.widget.key == linkKey;
        if (isLink) sawLink = true;
        if (label == 'Unavailable') sawDisabled = true;
        if (decoration == TextDecoration.underline ||
            decoration == TextDecoration.lineThrough) {
          if (isLink) {
            // Allowed: this is the designated link.
          } else {
            decorated.add('$label -> $decoration');
          }
        }
      }

      // The designated link must actually be present and decorated, proving the
      // exemption is exercised rather than vacuous.
      expect(sawLink, isTrue, reason: 'designated link missing from the probe');
      expect(find.byKey(linkKey), findsOneWidget);
      // Ensure the disabled label was actually rendered so the disabled text
      // path is covered, not skipped.
      expect(sawDisabled, isTrue, reason: 'disabled label missing from probe');
      // Every non-link text must be decoration free.
      expect(decorated, isEmpty,
          reason: 'Only the designated link may be decorated; these were not: '
              '${decorated.join(", ")}');
    });

    testWidgets('${theme.key}: every shared AppTextStyle token is clean',
        (tester) async {
      const tokens = <String, TextStyle>{
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
      for (final e in tokens.entries) {
        final d = e.value.decoration;
        if (d == TextDecoration.underline || d == TextDecoration.lineThrough) {
          offenders.add('${e.key}: $d');
        }
      }
      expect(offenders, isEmpty);
    });
  }
}
