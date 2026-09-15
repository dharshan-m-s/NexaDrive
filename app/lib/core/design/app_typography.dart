import 'package:flutter/material.dart';

/// NexaDrive One UI typography scale.
///
/// One UI type rhythm (Samsung guidance):
/// - Page title (viewing area): large, semibold/bold, tight leading.
/// - Section header within a page: uppercase micro-label, letter-spaced.
/// - Primary text (list titles): 16–17, weight 400–500.
/// - Secondary text (list subtitles): 13–14, weight 400, secondary color.
/// - Caption/metadata: 12–13, tertiary.
///
/// The system font is deliberately used (Roboto/Samsung One on Galaxy,
/// Noto Sans on desktop) so text renders natively on each platform and scales
/// correctly with system font-size settings.
abstract final class AppTextStyle {
  // -------------------------------------------------------------- display
  /// Large viewing-area page title (One UI "page" headers).
  static const TextStyle pageTitle = TextStyle(
    fontSize: 28,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
  );

  /// Extra-large greeting / hero title.
  static const TextStyle display = TextStyle(
    fontSize: 34,
    height: 1.15,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
  );

  /// Hero title for brand moments (Home greeting, Login masthead).
  static const TextStyle heroTitle = TextStyle(
    fontSize: 38,
    height: 1.1,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.6,
  );

  /// Storage / metric figures (big numbers with a unit aside).
  static const TextStyle metricValue = TextStyle(
    fontSize: 26,
    height: 1.1,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
  );

  /// Secondary stat figures inside hero/status surfaces.
  static const TextStyle statValue = TextStyle(
    fontSize: 18,
    height: 1.2,
    fontWeight: FontWeight.w700,
  );

  // --------------------------------------------------------------- titles
  /// Section header inside a page body.
  static const TextStyle sectionHeader = TextStyle(
    fontSize: 17,
    height: 1.3,
    fontWeight: FontWeight.w600,
  );

  /// Grouped-list micro header (uppercase label above a grouped panel).
  static const TextStyle listHeader = TextStyle(
    fontSize: 13,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.4,
  );

  /// Primary list row title.
  static const TextStyle rowTitle = TextStyle(
    fontSize: 16,
    height: 1.3,
    fontWeight: FontWeight.w500,
  );

  /// Secondary list row line.
  static const TextStyle rowSubtitle = TextStyle(
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w400,
  );

  /// Tertiary metadata / caption.
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w400,
  );

  /// Smallest legal metadata (badges, byte counts in tight rows).
  static const TextStyle micro = TextStyle(
    fontSize: 11,
    height: 1.2,
    fontWeight: FontWeight.w400,
  );

  /// Navigation rail / focus-pill label.
  static const TextStyle navLabel = TextStyle(
    fontSize: 13,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  );

  /// Filter / status chip label.
  static const TextStyle chipLabel = TextStyle(
    fontSize: 12,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  );

  // --------------------------------------------------------------- buttons
  static const TextStyle button = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  );

  static const TextStyle buttonSmall = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );

  // -------------------------------------------------------------- dialogs
  static const TextStyle dialogTitle = TextStyle(
    fontSize: 20,
    height: 1.3,
    fontWeight: FontWeight.w600,
  );

  // --------------------------------------------------------------- helpers
  /// Copies the base style with a color override.
  static TextStyle withColor(Color color, [TextStyle? base]) =>
      (base ?? rowTitle).copyWith(color: color);
}