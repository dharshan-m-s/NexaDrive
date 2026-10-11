import 'package:flutter/material.dart';

/// NexaDrive typography scale.
///
/// THE REFERENCE: Apple's text styles (largeTitle → caption2) and SF Pro's
/// vertical metrics. Hierarchy is carried by size, weight and colour, not
/// decoration; letter spacing tightens as type grows, exactly as iOS does.
///
/// The platform system font is used deliberately — SF on Apple platforms,
/// Roboto on Android, Noto on desktop — so text renders natively and honours
/// the user's font-size setting.
///
/// Two naming families are provided: the canonical token names (`pageTitle`,
/// `rowTitle`) and the iOS style names (`largeTitle`, `headline`, `body`).
abstract final class AppTextStyle {
  // -------------------------------------------------------------- large titles
  /// iOS `largeTitle` — only for top-level navigation headers that benefit
  /// from the oversized treatment (Settings, a top-level section).
  static const TextStyle largeTitle = TextStyle(
    fontSize: 34,
    height: 1.15,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
  );

  /// Standard page heading, used where a large title would be excessive.
  static const TextStyle pageTitle = TextStyle(
    fontSize: 22,
    height: 1.25,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );

  /// Extra-large greeting / hero title for brand moments.
  static const TextStyle display = TextStyle(
    fontSize: 34,
    height: 1.15,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
  );

  /// Hero title for brand moments (Home greeting, Login masthead).
  static const TextStyle heroTitle = TextStyle(
    fontSize: 32,
    height: 1.1,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
  );

  /// Storage / metric figures (big numbers with a unit aside).
  static const TextStyle metricValue = TextStyle(
    fontSize: 28,
    height: 1.1,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
  );

  /// Secondary stat figures inside hero/status surfaces.
  static const TextStyle statValue = TextStyle(
    fontSize: 20,
    height: 1.2,
    fontWeight: FontWeight.w600,
  );

  // --------------------------------------------------------------- titles
  /// iOS `title1`.
  static const TextStyle title1 = TextStyle(
    fontSize: 22,
    height: 1.25,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );

  /// iOS `title2`.
  static const TextStyle title2 = TextStyle(
    fontSize: 20,
    height: 1.25,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );

  /// iOS `title3`.
  static const TextStyle title3 = TextStyle(
    fontSize: 18,
    height: 1.25,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.05,
  );

  /// iOS `headline` — section header inside a page body.
  static const TextStyle headline = TextStyle(
    fontSize: 17,
    height: 1.3,
    fontWeight: FontWeight.w600,
  );

  /// Section header inside a page body.
  static const TextStyle sectionHeader = TextStyle(
    fontSize: 17,
    height: 1.3,
    fontWeight: FontWeight.w600,
  );

  /// Grouped-list micro header (label above a grouped panel).
  static const TextStyle listHeader = TextStyle(
    fontSize: 13,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.03,
  );

  /// Primary list row title.
  static const TextStyle rowTitle = TextStyle(
    fontSize: 17,
    height: 1.3,
    fontWeight: FontWeight.w400,
  );

  /// Secondary list row line.
  static const TextStyle rowSubtitle = TextStyle(
    fontSize: 15,
    height: 1.3,
    fontWeight: FontWeight.w400,
  );

  // --------------------------------------------------------------- body
  /// iOS `body`.
  static const TextStyle body = TextStyle(
    fontSize: 17,
    height: 1.4,
    fontWeight: FontWeight.w400,
  );

  /// iOS `body` with emphasis.
  static const TextStyle bodyEmphasized = TextStyle(
    fontSize: 17,
    height: 1.4,
    fontWeight: FontWeight.w500,
  );

  /// iOS `callout`.
  static const TextStyle callout = TextStyle(
    fontSize: 16,
    height: 1.35,
    fontWeight: FontWeight.w400,
  );

  /// iOS `subheadline`.
  static const TextStyle subheadline = TextStyle(
    fontSize: 15,
    height: 1.35,
    fontWeight: FontWeight.w400,
  );

  /// iOS `footnote`.
  static const TextStyle footnote = TextStyle(
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w400,
  );

  /// Metadata / caption.
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w400,
  );

  /// iOS `caption1`.
  static const TextStyle caption1 = TextStyle(
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w400,
  );

  /// iOS `caption2` — smallest legal metadata.
  static const TextStyle caption2 = TextStyle(
    fontSize: 11,
    height: 1.2,
    fontWeight: FontWeight.w400,
  );

  /// Smallest legal metadata (badges, byte counts in tight rows).
  static const TextStyle micro = TextStyle(
    fontSize: 11,
    height: 1.2,
    fontWeight: FontWeight.w400,
  );

  // ------------------------------------------------------------------ code
  /// Monospaced body for verbatim content: the text reader, log tails and
  /// source files. Leading is generous because code needs the air, and the
  /// family is generic so it resolves to the platform's true monospace face.
  static const TextStyle code = TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: <String>[
      'SF Mono',
      'Menlo',
      'DejaVu Sans Mono',
      'Consolas'
    ],
    fontSize: 13,
    height: 1.5,
    fontWeight: FontWeight.w400,
  );

  /// Monospaced at caption scale, for code in dense panels.
  static const TextStyle codeSmall = TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: <String>[
      'SF Mono',
      'Menlo',
      'DejaVu Sans Mono',
      'Consolas'
    ],
    fontSize: 11.5,
    height: 1.45,
    fontWeight: FontWeight.w400,
  );

  /// Navigation pill label.
  static const TextStyle navLabel = TextStyle(
    fontSize: 10,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.05,
  );

  /// Filter / status chip label.
  static const TextStyle chipLabel = TextStyle(
    fontSize: 12,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.05,
  );

  // --------------------------------------------------------------- buttons
  static const TextStyle button = TextStyle(
    fontSize: 17,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );

  static const TextStyle buttonSmall = TextStyle(
    fontSize: 15,
    height: 1.2,
    fontWeight: FontWeight.w600,
  );

  // -------------------------------------------------------------- dialogs
  static const TextStyle dialogTitle = TextStyle(
    fontSize: 19,
    height: 1.3,
    fontWeight: FontWeight.w600,
  );

  // --------------------------------------------------------------- helpers
  /// Copies the base style with a color override.
  static TextStyle withColor(Color color, [TextStyle? base]) =>
      (base ?? rowTitle).copyWith(color: color);
}

/// iOS-named aliases over [AppTextStyle]. Provided so layout code can read in
/// Apple's vocabulary while resolving to the same single scale.
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

  // Canonical aliases (kept so migrated screens resolve).
  static const TextStyle pageTitle = AppTextStyle.pageTitle;
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

/// Flat alias over [AppTextStyle] with the iOS style names, for code that was
/// written against the older Nexa vocabulary.
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
  static const TextStyle pageTitle = AppTextStyle.pageTitle;
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
