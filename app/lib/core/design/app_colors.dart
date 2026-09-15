import 'package:flutter/material.dart';

/// NexaDrive One UI color tokens (Samsung One UI 6.x palette).
///
/// THE REFERENCE: Samsung's One UI color language.
/// - Light surfaces are soft near-white; the page background is a very light
///   neutral so surfaces read as lifted, not flat.
/// - Dark surfaces are deep neutral gray-black (One UI's signature dark rhythm),
///   NOT a simple inversion. Text and accents are tuned for the dark.
/// - The accent is the One UI application blue, with a container variant used
///   for emphasis (selection, current folder, toggle-on backgrounds).
///
/// Every color in NexaDrive must come from this file. No hardcoded
/// `Color(...)` literals in widgets.
abstract final class AppColors {
  // --------------------------------------------------------------- accent
  /// One UI application blue (light mode).
  static const Color accent = Color(0xFF0B87D0);

  /// Accent used on dark surfaces — lifted blue, readable on near-black.
  static const Color accentDark = Color(0xFF6CC4F7);

  /// Soft blue fill behind the accent (selected row, toggle-on, badge).
  static const Color accentContainerLight = Color(0xFFE1F1FA);
  static const Color accentContainerDark = Color(0xFF123A55);

  /// Strong blue text/icons on the container fill.
  static const Color onAccentContainerLight = Color(0xFF0A5E8F);
  static const Color onAccentContainerDark = Color(0xFF9AD4F7);

  /// Deep shade of blue for pressed/active accents.
  static const Color accentPressedLight = Color(0xFF08679F);
  static const Color accentPressedDark = Color(0xFF4FA8DF);

  /// Accent safe for *text and icons on plain surfaces* (meets 4.5:1).
  /// One UI keeps accent for fills; text-on-surface uses a deeper hue.
  static const Color accentHighEmphasisLight = Color(0xFF0A5E8F);
  static const Color accentHighEmphasisDark = Color(0xFF9AD4F7);

  /// The softest accent tint — used behind icon tiles & quiet highlights.
  static const Color accentSubtleLight = Color(0xFFEDF6FC);
  static const Color accentSubtleDark = Color(0xFF173044);

  // ------------------------------------------------------------ surfaces
  /// Page background (light) — very light neutral, cooler than white.
  static const Color backgroundLight = Color(0xFFF7F8FA);

  /// Page background (dark) — One UI true-black viewing base.
  static const Color backgroundDark = Color(0xFF000000);

  /// Primary interactive surface (cards, sheets, tiles, dialogs)—LEVEL 1.
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF1D1E1F);

  /// Grouped/alt surface used inside panels to separate rows or hover fills
  /// — LEVEL 2 (grouped lists, input fills, inset chips).
  static const Color surfaceAltLight = Color(0xFFF2F3F5);
  static const Color surfaceAltDark = Color(0xFF232425);

  /// Slightly deeper surface for headers/toolbars over content — LEVEL 3.
  static const Color surfaceElevatedLight = Color(0xFFFFFFFF);
  static const Color surfaceElevatedDark = Color(0xFF232425);

  /// Deepest inset surface — pressed rows, selection bar over content.
  static const Color surfacePressedLight = Color(0xFFE9EBEE);
  static const Color surfacePressedDark = Color(0xFF2D2E30);

  // --------------------------------------------------------------- text
  static const Color textPrimaryLight = Color(0xFF1A1C1E);
  static const Color textPrimaryDark = Color(0xFFF6F7F8);

  static const Color textSecondaryLight = Color(0xFF5B5F66);
  static const Color textSecondaryDark = Color(0xFFB8BDC3);

  static const Color textTertiaryLight = Color(0xFF8A9099);
  static const Color textTertiaryDark = Color(0xFF7D838C);

  static const Color textOnPrimaryLight = Color(0xFFFFFFFF);
  static const Color textOnPrimaryDark = Color(0xFF001D33);

  static const Color textLink = accent;
  static const Color textLinkDark = accentDark;

  // ------------------------------------------------------------ dividers
  static const Color dividerLight = Color(0x1F000000);
  static const Color dividerDark = Color(0x1FFFFFFF);

  // ------------------------------------------------------------ status
  static const Color successLight = Color(0xFF23641E);
  static const Color successDark = Color(0xFF7BD46A);
  static const Color warningLight = Color(0xFFB25E00);
  static const Color warningDark = Color(0xFFF1AD56);
  static const Color errorLight = Color(0xFFB3261E);
  static const Color errorDark = Color(0xFFFF5449);
  static const Color infoLight = accent;
  static const Color infoDark = accentDark;

  // ------------------------------------------------- status containers
  /// Tonal status backgrounds + their on-colors (One UI status chips/rows).
  static const Color successContainerLight = Color(0xFFD9F0DC);
  static const Color onSuccessContainerLight = Color(0xFF15541F);
  static const Color successContainerDark = Color(0xFF1E3B24);
  static const Color onSuccessContainerDark = Color(0xFFB8E9C2);

  static const Color warningContainerLight = Color(0xFFFFEBD8);
  static const Color onWarningContainerLight = Color(0xFF7A3E00);
  static const Color warningContainerDark = Color(0xFF4A3320);
  static const Color onWarningContainerDark = Color(0xFFFFD9B0);

  static const Color errorContainerLight = Color(0xFFFADCD6);
  static const Color onErrorContainerLight = Color(0xFF8C1A14);
  static const Color errorContainerDark = Color(0xFF472126);
  static const Color onErrorContainerDark = Color(0xFFFFB3AB);

  static const Color infoContainerLight = accentContainerLight;
  static const Color onInfoContainerLight = onAccentContainerLight;
  static const Color infoContainerDark = accentContainerDark;
  static const Color onInfoContainerDark = onAccentContainerDark;

  // ------------------------------------------------------------ shadows
  /// One UI keeps depth subtle: low-opacity neutral shadows, small blur.
  static const Color shadowColorStrong = Color(0x1A000000);
  static const Color shadowColorSoft = Color(0x0F000000);

  // ------------------------------------------------------------ scrims
  /// Dim behind modal sheets (One UI darkens ~40%).
  static const Color scrim = Color(0x66000000);

  // ----------------------------------------------------------------- api
  /// Returns the accent color for the given brightness.
  static Color accentFor(Brightness b) =>
      b == Brightness.dark ? accentDark : accent;

  /// Returns a contrast-safe accent for text/icons on plain surfaces.
  static Color accentTextFor(Brightness b) =>
      b == Brightness.dark ? accentHighEmphasisDark : accentHighEmphasisLight;

  /// Returns the soft accent tint (behind icon tiles).
  static Color accentSubtleFor(Brightness b) =>
      b == Brightness.dark ? accentSubtleDark : accentSubtleLight;

  /// Returns the accent container color for the given brightness.
  static Color accentContainerFor(Brightness b) =>
      b == Brightness.dark ? accentContainerDark : accentContainerLight;

  /// Returns the on-accent-container color for the given brightness.
  static Color onAccentContainerFor(Brightness b) =>
      b == Brightness.dark ? onAccentContainerDark : onAccentContainerLight;

  static Color textPrimaryFor(Brightness b) =>
      b == Brightness.dark ? textPrimaryDark : textPrimaryLight;

  static Color textSecondaryFor(Brightness b) =>
      b == Brightness.dark ? textSecondaryDark : textSecondaryLight;

  static Color textTertiaryFor(Brightness b) =>
      b == Brightness.dark ? textTertiaryDark : textTertiaryLight;

  static Color dividerFor(Brightness b) =>
      b == Brightness.dark ? dividerDark : dividerLight;

  static Color successFor(Brightness b) =>
      b == Brightness.dark ? successDark : successLight;

  static Color warningFor(Brightness b) =>
      b == Brightness.dark ? warningDark : warningLight;

  static Color errorFor(Brightness b) =>
      b == Brightness.dark ? errorDark : errorLight;

  static Color infoFor(Brightness b) =>
      b == Brightness.dark ? infoDark : infoLight;

  static Color successContainerFor(Brightness b) =>
      b == Brightness.dark ? successContainerDark : successContainerLight;

  static Color onSuccessContainerFor(Brightness b) =>
      b == Brightness.dark ? onSuccessContainerDark : onSuccessContainerLight;

  static Color warningContainerFor(Brightness b) =>
      b == Brightness.dark ? warningContainerDark : warningContainerLight;

  static Color onWarningContainerFor(Brightness b) =>
      b == Brightness.dark ? onWarningContainerDark : onWarningContainerLight;

  static Color errorContainerFor(Brightness b) =>
      b == Brightness.dark ? errorContainerDark : errorContainerLight;

  static Color onErrorContainerFor(Brightness b) =>
      b == Brightness.dark ? onErrorContainerDark : onErrorContainerLight;

  static Color infoContainerFor(Brightness b) =>
      b == Brightness.dark ? infoContainerDark : infoContainerLight;

  static Color onInfoContainerFor(Brightness b) =>
      b == Brightness.dark ? onInfoContainerDark : onInfoContainerLight;

  static Color surfacePressedFor(Brightness b) =>
      b == Brightness.dark ? surfacePressedDark : surfacePressedLight;

  // ------------------------------------------------------- on-gradient text
  /// Text/icons placed on a vivid gradient hero. Light mode uses deep navy on
  /// the calm sky→ocean face (high contrast); dark mode reads near-white.
  static const Color onGradientLight = Color(0xFF06283D);
  static const Color onGradientDark = Color(0xFFF2FAFF);

  static Color heroTextOnGradient(Brightness b) =>
      b == Brightness.dark ? onGradientDark : onGradientLight;
}