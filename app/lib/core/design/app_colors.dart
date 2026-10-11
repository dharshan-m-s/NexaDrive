import 'package:flutter/material.dart';

/// NexaDrive semantic color system.
///
/// THE REFERENCE: Apple's platform color language (iOS/macOS semantic colors).
/// The visual hierarchy is built the way UIKit builds it:
///
///  * **Layered backgrounds** — a grouped page background sits *behind* white
///    content surfaces, so a list reads as a raised plane rather than as flat
///    Material canvas.
///  * **Label opacities** — primary/secondary/tertiary text are one ink at
///    decreasing opacity, which keeps hierarchy legible in both appearances
///    instead of introducing unrelated grays.
///  * **One deliberate accent** — system blue, with a lifted variant for dark
///    mode (iOS raises accent luminance on black).
///
/// Every color in NexaDrive must come from this file. No hardcoded
/// `Color(...)` literals in widgets.
abstract final class AppColors {
  // --------------------------------------------------------------- accent
  /// System blue (light). iOS `systemBlue`.
  static const Color accent = Color(0xFF007AFF);

  /// System blue (dark) — lifted so it stays legible on near-black.
  static const Color accentDark = Color(0xFF0A84FF);

  /// Soft blue fill behind the accent (selection, toggle-on, badge).
  static const Color accentContainerLight = Color(0x1F007AFF);
  static const Color accentContainerDark = Color(0x330A84FF);

  /// Strong blue text/icons on the container fill.
  static const Color onAccentContainerLight = Color(0xFF0040DD);
  static const Color onAccentContainerDark = Color(0xFF7AB8FF);

  /// Deep shade of blue for pressed/active accents.
  static const Color accentPressedLight = Color(0xFF0062CC);
  static const Color accentPressedDark = Color(0xFF409CFF);

  /// Accent safe for *text and icons on plain surfaces* (meets contrast).
  static const Color accentHighEmphasisLight = Color(0xFF0062CC);
  static const Color accentHighEmphasisDark = Color(0xFF409CFF);

  /// The softest accent tint — behind icon tiles and quiet highlights.
  static const Color accentSubtleLight = Color(0x14007AFF);
  static const Color accentSubtleDark = Color(0x260A84FF);

  // ------------------------------------------------------------ surfaces
  /// Page background (light) — iOS `systemGroupedBackground`.
  static const Color backgroundLight = Color(0xFFF2F2F7);

  /// Page background (dark) — true black, the iOS grouped canvas.
  static const Color backgroundDark = Color(0xFF000000);

  /// Primary content surface (cards, sheets, tiles) — LEVEL 1.
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF1C1C1E);

  /// Grouped/alt surface used inside panels to separate rows or hover fills
  /// — LEVEL 2 (`secondarySystemGroupedBackground`).
  static const Color surfaceAltLight = Color(0xFFF2F2F7);
  static const Color surfaceAltDark = Color(0xFF2C2C2E);

  /// Slightly deeper surface for headers/toolbars over content — LEVEL 3.
  static const Color surfaceElevatedLight = Color(0xFFFFFFFF);
  static const Color surfaceElevatedDark = Color(0xFF2C2C2E);

  /// Deepest inset surface — pressed rows, selection bar over content.
  static const Color surfacePressedLight = Color(0xFFE5E5EA);
  static const Color surfacePressedDark = Color(0xFF3A3A3C);

  // --------------------------------------------------------------- text
  /// `label` — the one ink, at full strength.
  static const Color textPrimaryLight = Color(0xFF000000);
  static const Color textPrimaryDark = Color(0xFFFFFFFF);

  /// `secondaryLabel` — 60% of the ink.
  static const Color textSecondaryLight = Color(0x993C3C43);
  static const Color textSecondaryDark = Color(0x99EBEBF5);

  /// `tertiaryLabel` — 30% of the ink.
  static const Color textTertiaryLight = Color(0x4D3C3C43);
  static const Color textTertiaryDark = Color(0x66EBEBF5);

  static const Color textOnPrimaryLight = Color(0xFFFFFFFF);
  static const Color textOnPrimaryDark = Color(0xFFFFFFFF);

  static const Color textLink = accent;
  static const Color textLinkDark = accentDark;

  // ------------------------------------------------------------ dividers
  /// `separator` — a hairline that reads as a rule, not a border.
  static const Color dividerLight = Color(0x1F3C3C43);
  static const Color dividerDark = Color(0x2E545456);

  // ------------------------------------------------------------ status
  static const Color successLight = Color(0xFF34C759);
  static const Color successDark = Color(0xFF30D158);
  static const Color warningLight = Color(0xFFFF9F0A);
  static const Color warningDark = Color(0xFFFF9F0A);
  static const Color errorLight = Color(0xFFFF3B30);
  static const Color errorDark = Color(0xFFFF453A);
  static const Color infoLight = accent;
  static const Color infoDark = accentDark;

  // ------------------------------------------------- status containers
  /// Tonal status backgrounds + their on-colors (status chips/rows).
  static const Color successContainerLight = Color(0xFFE3F8E7);
  static const Color onSuccessContainerLight = Color(0xFF1B7A32);
  static const Color successContainerDark = Color(0xFF1E3B24);
  static const Color onSuccessContainerDark = Color(0xFF9DE8AC);

  static const Color warningContainerLight = Color(0xFFFFF0DC);
  static const Color onWarningContainerLight = Color(0xFF9A5B00);
  static const Color warningContainerDark = Color(0xFF4A3320);
  static const Color onWarningContainerDark = Color(0xFFFFD08A);

  static const Color errorContainerLight = Color(0xFFFFE3E1);
  static const Color onErrorContainerLight = Color(0xFFC7261D);
  static const Color errorContainerDark = Color(0xFF472126);
  static const Color onErrorContainerDark = Color(0xFFFFB3AB);

  static const Color infoContainerLight = accentContainerLight;
  static const Color onInfoContainerLight = onAccentContainerLight;
  static const Color infoContainerDark = accentContainerDark;
  static const Color onInfoContainerDark = onAccentContainerDark;

  // ------------------------------------------------------------ shadows
  /// iOS keeps depth subtle: a single soft ambient shadow for floating
  /// surfaces, plus a slightly stronger one for modals.
  static const Color shadowColorStrong = Color(0x26000000);
  static const Color shadowColorSoft = Color(0x1A000000);

  // ------------------------------------------------------------ scrims
  /// Dim behind modal sheets (iOS darkens ~40%).
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

  /// Page background for the given brightness.
  static Color backgroundFor(Brightness b) =>
      b == Brightness.dark ? backgroundDark : backgroundLight;

  /// Foreground that sits on an accent fill (system blue). On iOS this is
  /// always white, including dark appearance.
  static Color onAccentFor(Brightness b) => Colors.white;

  /// Returns the accent container color for the given brightness.
  static Color accentContainerFor(Brightness b) =>
      b == Brightness.dark ? accentContainerDark : accentContainerLight;

  /// Returns the on-accent-container color for the given brightness.
  static Color onAccentContainerFor(Brightness b) =>
      b == Brightness.dark ? onAccentContainerDark : onAccentContainerLight;

  static Color textPrimaryFor(Brightness b) =>
      b == Brightness.dark ? textPrimaryDark : textPrimaryLight;

  /// Primary interactive surface (cards, panels) for the given brightness.
  static Color surfaceFor(Brightness b) =>
      b == Brightness.dark ? surfaceDark : surfaceLight;

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

  /// Elevated surface (bars, toolbars) for the given brightness.
  static Color surfaceElevatedFor(Brightness b) =>
      b == Brightness.dark ? surfaceElevatedDark : surfaceElevatedLight;

  // --------------------------------------------- grouped / semantic aliases
  // These mirror Apple's grouped-surface and label vocabulary and are the
  // canonical names for the surface stack. The older names above remain for
  // source compatibility.

  /// `systemBackground` — the primary content plane.
  static Color systemBackgroundFor(Brightness b) => surfaceFor(b);

  /// `secondarySystemBackground`.
  static Color secondaryBackgroundFor(Brightness b) => surfaceAltFor(b);

  /// Grouped content plane (`secondarySystemGroupedBackground`).
  static Color surfaceGroupedFor(Brightness b) =>
      b == Brightness.dark ? surfaceGroupedDark : surfaceGroupedLight;

  static const Color surfaceGroupedLight = Color(0xFFFFFFFF);
  static const Color surfaceGroupedDark = Color(0xFF1C1C1E);

  /// Tertiary grouped plane.
  static Color surfaceGroupedAltFor(Brightness b) =>
      b == Brightness.dark ? surfaceGroupedAltDark : surfaceGroupedAltLight;

  static const Color surfaceGroupedAltLight = Color(0xFFF2F2F7);
  static const Color surfaceGroupedAltDark = Color(0xFF2C2C2E);

  /// Alternate surface alias used by panel internals.
  static Color surfaceAltFor(Brightness b) =>
      b == Brightness.dark ? surfaceAltDark : surfaceAltLight;

  static Color labelPrimaryFor(Brightness b) => textPrimaryFor(b);
  static Color labelSecondaryFor(Brightness b) => textSecondaryFor(b);
  static Color labelTertiaryFor(Brightness b) => textTertiaryFor(b);
  static Color labelQuaternaryFor(Brightness b) =>
      b == Brightness.dark ? const Color(0x33EBEBF5) : const Color(0x333C3C43);

  /// `separator` (translucent hairline).
  static Color separatorFor(Brightness b) => dividerFor(b);

  /// `opaqueSeparator`.
  static Color separatorOpaqueFor(Brightness b) =>
      b == Brightness.dark ? const Color(0xFF38383A) : const Color(0xFFC6C6C8);

  /// System fill — input backgrounds and quiet chips.
  static Color fillFor(Brightness b) =>
      b == Brightness.dark ? const Color(0x1FFFFFFF) : const Color(0x1F000000);

  static Color fillSecondaryFor(Brightness b) =>
      b == Brightness.dark ? const Color(0x1AFFFFFF) : const Color(0x1A000000);

  static Color fillTertiaryFor(Brightness b) =>
      b == Brightness.dark ? const Color(0x33FFFFFF) : const Color(0x33000000);

  static Color shadowColorFor(Brightness b) =>
      b == Brightness.dark ? shadowColorStrong : shadowColorSoft;

  static Color scrimFor(Brightness b) => scrim;

  // ------------------------------------------------------- on-gradient text
  /// Text/icons placed on a vivid gradient hero. Light mode uses deep navy on
  /// the calm sky→ocean face (high contrast); dark mode reads near-white.
  static const Color onGradientLight = Color(0xFF06283D);
  static const Color onGradientDark = Color(0xFFF2FAFF);

  static Color heroTextOnGradient(Brightness b) =>
      b == Brightness.dark ? onGradientDark : onGradientLight;
}
