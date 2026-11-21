import 'package:flutter/material.dart';

/// NexaDrive typography — editorial hierarchy over Material roles.
///
/// The platform font is kept deliberately: it stays native, scales with the
/// user's text-size setting and carries optical tuning for every size. The
/// hierarchy comes from tighter display tracking, heavier headings, generous
/// leading for body copy and a clear separation between filename and metadata.
abstract final class AppTextStyle {
  // ------------------------------------------------------- display / hero
  /// Editorial display type. Large text is tightened; small text stays open.
  static const TextStyle display = TextStyle(
    fontSize: 42,
    height: 46 / 42,
    fontWeight: FontWeight.w600,
    letterSpacing: -1.2,
  );

  static const TextStyle largeTitle = display;

  /// The largest in-page heading.
  static const TextStyle heroTitle = TextStyle(
    fontSize: 34,
    height: 38 / 34,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.8,
  );

  /// Storage / metric figures.
  static const TextStyle metricValue = TextStyle(
    fontSize: 40,
    height: 44 / 40,
    fontWeight: FontWeight.w600,
    letterSpacing: -1,
  );

  static const TextStyle statValue = TextStyle(
    fontSize: 26,
    height: 32 / 26,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
  );

  // -------------------------------------------------------------- titles
  static const TextStyle title1 = TextStyle(
    fontSize: 30,
    height: 36 / 30,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.6,
  );

  static const TextStyle title2 = TextStyle(
    fontSize: 25,
    height: 31 / 25,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
  );

  static const TextStyle title3 = TextStyle(
    fontSize: 21,
    height: 27 / 21,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );

  /// The strongest text inside a row or section.
  static const TextStyle headline = TextStyle(
    fontSize: 16,
    height: 22 / 16,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );

  /// Uppercase overline. Widgets apply the uppercase transform.
  static const TextStyle sectionHeader = TextStyle(
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.1,
  );

  /// Legacy grouped-list header alias.
  static const TextStyle listHeader = sectionHeader;

  static const TextStyle rowTitle = headline;
  static const TextStyle rowSubtitle = subheadline;

  // --------------------------------------------------------------- body
  static const TextStyle body = TextStyle(
    fontSize: 14.5,
    height: 21 / 14.5,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
  );

  static const TextStyle bodyEmphasized = TextStyle(
    fontSize: 14.5,
    height: 21 / 14.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  );

  static const TextStyle callout = TextStyle(
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );

  /// Secondary metadata. Never competes with [rowTitle].
  static const TextStyle subheadline = TextStyle(
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
  );

  static const TextStyle footnote = TextStyle(
    fontSize: 12,
    height: 17 / 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 11,
    height: 15 / 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.3,
  );

  static const TextStyle caption1 = caption;
  static const TextStyle caption2 = caption;
  static const TextStyle micro = caption;

  // ------------------------------------------------------------------ code
  static const TextStyle code = TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: <String>[
      'Roboto Mono',
      'SF Mono',
      'Menlo',
      'DejaVu Sans Mono',
      'Consolas',
    ],
    fontSize: 13,
    height: 1.5,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle codeSmall = TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: <String>[
      'Roboto Mono',
      'SF Mono',
      'Menlo',
      'DejaVu Sans Mono',
      'Consolas',
    ],
    fontSize: 12,
    height: 1.45,
    fontWeight: FontWeight.w400,
  );

  /// Navigation pill label. Kept at Material's 12dp minimum for legibility.
  static const TextStyle navLabel = TextStyle(
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );

  /// Filter / status chip label.
  static const TextStyle chipLabel = TextStyle(
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );

  // --------------------------------------------------------------- buttons
  static const TextStyle button = TextStyle(
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  );

  static const TextStyle buttonSmall = TextStyle(
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );

  // --------------------------------------------------- Material role aliases
  static const TextStyle pageTitle = title2;
  static const TextStyle headlineSmall = title3;
  static const TextStyle titleLarge = title3;
  static const TextStyle titleMedium = headline;
  static const TextStyle titleSmall = callout;
  static const TextStyle bodyLarge = body;
  static const TextStyle bodyMedium = subheadline;
  static const TextStyle bodySmall = footnote;
  static const TextStyle labelLarge = button;
  static const TextStyle labelMedium = chipLabel;
  static const TextStyle labelSmall = caption;

  // -------------------------------------------------------------- dialogs
  static const TextStyle dialogTitle = title2;

  // --------------------------------------------------------------- helpers
  static TextStyle withColor(Color color, [TextStyle? base]) =>
      (base ?? rowTitle).copyWith(color: color);
}

/// Compatibility aliases over [AppTextStyle].
abstract final class NexaTextStyle {
  static const TextStyle largeTitle = AppTextStyle.largeTitle;
  static const TextStyle display = AppTextStyle.display;
  static const TextStyle title1 = AppTextStyle.title1;
  static const TextStyle title2 = AppTextStyle.title2;
  static const TextStyle title3 = AppTextStyle.title3;
  static const TextStyle headline = AppTextStyle.headline;
  static const TextStyle body = AppTextStyle.body;
  static const TextStyle bodyEmphasized = AppTextStyle.bodyEmphasized;
  static const TextStyle callout = AppTextStyle.callout;
  static const TextStyle subheadline = AppTextStyle.subheadline;
  static const TextStyle footnote = AppTextStyle.footnote;
  static const TextStyle caption1 = AppTextStyle.caption1;
  static const TextStyle caption2 = AppTextStyle.caption2;
  static const TextStyle pageTitle = AppTextStyle.title2;
  static const TextStyle sectionHeader = AppTextStyle.sectionHeader;
  static const TextStyle listHeader = AppTextStyle.listHeader;
  static const TextStyle rowTitle = AppTextStyle.rowTitle;
  static const TextStyle rowSubtitle = AppTextStyle.rowSubtitle;
  static const TextStyle chipLabel = AppTextStyle.chipLabel;
  static const TextStyle caption = AppTextStyle.caption;
  static const TextStyle micro = AppTextStyle.micro;
  static const TextStyle button = AppTextStyle.button;
  static const TextStyle buttonSmall = AppTextStyle.buttonSmall;
  static const TextStyle monospace = AppTextStyle.code;
  static const TextStyle monospaceSmall = AppTextStyle.codeSmall;

  static TextStyle withColor(Color color, [TextStyle? base]) =>
      AppTextStyle.withColor(color, base);
}

/// Flat compatibility alias over [AppTextStyle].
abstract final class NexaTypography {
  static const TextStyle display = AppTextStyle.display;
  static const TextStyle largeTitle = AppTextStyle.largeTitle;
  static const TextStyle title1 = AppTextStyle.title1;
  static const TextStyle title2 = AppTextStyle.title2;
  static const TextStyle title3 = AppTextStyle.title3;
  static const TextStyle headline = AppTextStyle.headline;
  static const TextStyle body = AppTextStyle.body;
  static const TextStyle callout = AppTextStyle.callout;
  static const TextStyle subheadline = AppTextStyle.subheadline;
  static const TextStyle footnote = AppTextStyle.footnote;
  static const TextStyle caption1 = AppTextStyle.caption1;
  static const TextStyle caption2 = AppTextStyle.caption2;
  static const TextStyle pageTitle = AppTextStyle.title2;
  static const TextStyle sectionHeader = AppTextStyle.sectionHeader;
  static const TextStyle listHeader = AppTextStyle.listHeader;
  static const TextStyle rowTitle = AppTextStyle.rowTitle;
  static const TextStyle rowSubtitle = AppTextStyle.rowSubtitle;
  static const TextStyle chipLabel = AppTextStyle.chipLabel;
  static const TextStyle caption = AppTextStyle.caption;
  static const TextStyle micro = AppTextStyle.micro;
  static const TextStyle metricValue = AppTextStyle.metricValue;
  static const TextStyle statValue = AppTextStyle.statValue;
  static const TextStyle button = AppTextStyle.button;
  static const TextStyle buttonSmall = AppTextStyle.buttonSmall;
  static const TextStyle code = AppTextStyle.code;
}
