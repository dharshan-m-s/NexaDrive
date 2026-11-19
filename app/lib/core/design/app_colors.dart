import 'package:flutter/material.dart';

/// NexaDrive colour system — warm editorial Material 3.
///
/// The app keeps Material's role vocabulary (`primary`, `surfaceContainer*`,
/// `onSurfaceVariant`, `outlineVariant`, and so on) but the seed and every
/// canvas role are tuned to the NexaDrive palette. Screens never own raw
/// colours: they resolve roles here or through [Theme.of].
abstract final class AppColors {
  /// The brand seed. Forest green, used sparingly for emphasis.
  static const Color seed = Color(0xFF355C46);

  // ------------------------------------------------------- brand foundation
  static const Color canvasLight = Color(0xFFF7F6F0);
  static const Color canvasSecondaryLight = Color(0xFFEFEEE6);
  static const Color inkLight = Color(0xFF242820);
  static const Color inkMutedLight = Color(0xFF85877D);
  static const Color separatorLight = Color(0xFFE5E3D9);
  static const Color selectionLight = Color(0xFFE3EBE1);
  static const Color forestLight = Color(0xFF355C46);
  static const Color forestDeepLight = Color(0xFF2A4836);
  static const Color forestSoftLight = Color(0xFF9CC4A9);

  /// Dark counterparts keep the same warmth and hierarchy.
  static const Color canvasDark = Color(0xFF1D201A);
  static const Color canvasSecondaryDark = Color(0xFF282C24);
  static const Color inkDark = Color(0xFFF2F1E8);
  static const Color inkMutedDark = Color(0xFFA8AB9F);
  static const Color separatorDark = Color(0xFF353A31);
  static const Color selectionDark = Color(0xFF31483A);
  static const Color forestDark = Color(0xFF9CC4A9);
  static const Color forestDeepDark = Color(0xFFD6E8D9);
  static const Color forestSoftDark = Color(0xFF6F9A7E);

  static final ColorScheme lightScheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: Brightness.light,
  ).copyWith(
    primary: forestLight,
    onPrimary: Colors.white,
    primaryContainer: selectionLight,
    onPrimaryContainer: forestDeepLight,
    secondary: const Color(0xFF6F7467),
    onSecondary: Colors.white,
    secondaryContainer: canvasSecondaryLight,
    onSecondaryContainer: inkLight,
    tertiary: const Color(0xFFA4654B),
    onTertiary: Colors.white,
    tertiaryContainer: const Color(0xFFF2E1D7),
    onTertiaryContainer: const Color(0xFF5E3222),
    surface: canvasLight,
    surfaceTint: Colors.transparent,
    onSurface: inkLight,
    onSurfaceVariant: inkMutedLight,
    surfaceContainerLowest: canvasLight,
    surfaceContainerLow: canvasSecondaryLight,
    surfaceContainer: canvasSecondaryLight,
    surfaceContainerHigh: const Color(0xFFFAF9F4),
    surfaceContainerHighest: separatorLight,
    outline: const Color(0xFFBFC2B6),
    outlineVariant: separatorLight,
    error: const Color(0xFF9C4F40),
    onError: Colors.white,
    errorContainer: const Color(0xFFF4DED7),
    onErrorContainer: const Color(0xFF5B241A),
    inverseSurface: inkLight,
    onInverseSurface: canvasLight,
    inversePrimary: forestSoftLight,
    shadow: const Color(0x2A242820),
    scrim: const Color(0x66201F1A),
  );

  static final ColorScheme darkScheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: Brightness.dark,
  ).copyWith(
    primary: forestDark,
    onPrimary: const Color(0xFF142219),
    primaryContainer: selectionDark,
    onPrimaryContainer: forestDeepDark,
    secondary: const Color(0xFFB7BBAE),
    onSecondary: canvasDark,
    secondaryContainer: canvasSecondaryDark,
    onSecondaryContainer: inkDark,
    tertiary: const Color(0xFFD5A28C),
    onTertiary: canvasDark,
    tertiaryContainer: const Color(0xFF5A3A2E),
    onTertiaryContainer: const Color(0xFFF4DED7),
    surface: canvasDark,
    surfaceTint: Colors.transparent,
    onSurface: inkDark,
    onSurfaceVariant: inkMutedDark,
    surfaceContainerLowest: const Color(0xFF181B16),
    surfaceContainerLow: const Color(0xFF22261F),
    surfaceContainer: canvasSecondaryDark,
    surfaceContainerHigh: const Color(0xFF30352B),
    surfaceContainerHighest: separatorDark,
    outline: const Color(0xFF777C70),
    outlineVariant: separatorDark,
    error: const Color(0xFFE09283),
    onError: const Color(0xFF4A1D15),
    errorContainer: const Color(0xFF5B3028),
    onErrorContainer: const Color(0xFFF4DED7),
    inverseSurface: const Color(0xFFECEBE2),
    onInverseSurface: canvasDark,
    inversePrimary: forestLight,
    shadow: const Color(0x52000000),
    scrim: const Color(0x660D0E0B),
  );

  static ColorScheme scheme(Brightness brightness) =>
      brightness == Brightness.dark ? darkScheme : lightScheme;

  // --------------------------------------------------------------- primary
  /// Compatibility aliases. [scheme] remains authoritative at runtime.
  static const Color accent = forestLight;
  static const Color accentDark = forestSoftLight;
  static const Color primary = forestLight;
  static const Color primaryDark = forestSoftLight;

  static const Color accentContainerLight = selectionLight;
  static const Color accentContainerDark = selectionDark;
  static const Color onAccentContainerLight = forestDeepLight;
  static const Color onAccentContainerDark = forestDeepDark;

  static const Color accentPressedLight = forestDeepLight;
  static const Color accentPressedDark = forestSoftLight;

  /// Contrast-safe accent for text and icons on plain surfaces.
  static const Color accentHighEmphasisLight = forestDeepLight;
  static const Color accentHighEmphasisDark = forestSoftLight;

  static const Color accentSubtleLight = selectionLight;
  static const Color accentSubtleDark = selectionDark;

  // ------------------------------------------------------------- secondary
  static const Color secondaryLight = Color(0xFF6F7467);
  static const Color secondaryDark = Color(0xFFB7BBAE);
  static const Color secondaryContainerLight = canvasSecondaryLight;
  static const Color secondaryContainerDark = canvasSecondaryDark;
  static const Color onSecondaryContainerLight = inkLight;
  static const Color onSecondaryContainerDark = inkDark;

  // -------------------------------------------------------------- tertiary
  /// A restrained terracotta used only for warm semantic emphasis.
  static const Color tertiaryLight = Color(0xFFA4654B);
  static const Color tertiaryDark = Color(0xFFD5A28C);
  static const Color tertiaryContainerLight = Color(0xFFF2E1D7);
  static const Color tertiaryContainerDark = Color(0xFF5A3A2E);
  static const Color onTertiaryContainerLight = Color(0xFF5E3222);
  static const Color onTertiaryContainerDark = Color(0xFFF4DED7);

  // ------------------------------------------------------------ surfaces
  static const Color backgroundLight = canvasLight;
  static const Color backgroundDark = canvasDark;

  static const Color surfaceLight = canvasLight;
  static const Color surfaceDark = canvasDark;

  static const Color surfaceAltLight = canvasSecondaryLight;
  static const Color surfaceAltDark = canvasSecondaryDark;

  static const Color surfaceElevatedLight = Color(0xFFFAF9F4);
  static const Color surfaceElevatedDark = Color(0xFF30352B);

  static const Color surfacePressedLight = Color(0xFFE6E7DC);
  static const Color surfacePressedDark = Color(0xFF383D33);

  /// Grouped content uses the warm secondary canvas, never purple tinting.
  static Color get surfaceGroupedLight => lightScheme.surfaceContainerLow;
  static Color get surfaceGroupedDark => darkScheme.surfaceContainerLow;
  static Color get surfaceGroupedAltLight => lightScheme.surfaceContainer;
  static Color get surfaceGroupedAltDark => darkScheme.surfaceContainer;

  // ----------------------------------------------------------------- ink
  static const Color textPrimaryLight = inkLight;
  static const Color textPrimaryDark = inkDark;

  static const Color textSecondaryLight = inkMutedLight;
  static const Color textSecondaryDark = inkMutedDark;

  static const Color textTertiaryLight = Color(0xFF9A9C92);
  static const Color textTertiaryDark = Color(0xFF8F9388);

  static const Color textOnPrimaryLight = Colors.white;
  static const Color textOnPrimaryDark = Color(0xFF142219);

  static const Color textLink = forestLight;
  static const Color textLinkDark = forestSoftLight;

  // ------------------------------------------------------------ dividers
  static const Color dividerLight = separatorLight;
  static const Color dividerDark = separatorDark;

  // ------------------------------------------------------------ status
  /// Status colours stay in the warm family so they never read as a second
  /// brand. Success shares the forest accent; error uses muted terracotta.
  static const Color successLight = Color(0xFF3F6B4F);
  static const Color successDark = Color(0xFF9CC4A9);
  static const Color warningLight = Color(0xFF9A6B32);
  static const Color warningDark = Color(0xFFD8B27E);
  static const Color errorLight = Color(0xFF9C4F40);
  static const Color errorDark = Color(0xFFE09283);
  static const Color infoLight = forestLight;
  static const Color infoDark = forestSoftLight;

  static const Color successContainerLight = Color(0xFFE1EBE1);
  static const Color onSuccessContainerLight = Color(0xFF294735);
  static const Color successContainerDark = Color(0xFF2E4937);
  static const Color onSuccessContainerDark = Color(0xFFD6E8D9);

  static const Color warningContainerLight = Color(0xFFF2E7D5);
  static const Color onWarningContainerLight = Color(0xFF5E4423);
  static const Color warningContainerDark = Color(0xFF55432B);
  static const Color onWarningContainerDark = Color(0xFFF2E7D5);

  static const Color errorContainerLight = Color(0xFFF4DED7);
  static const Color onErrorContainerLight = Color(0xFF5B241A);
  static const Color errorContainerDark = Color(0xFF5B3028);
  static const Color onErrorContainerDark = Color(0xFFF4DED7);

  static const Color infoContainerLight = selectionLight;
  static const Color onInfoContainerLight = forestDeepLight;
  static const Color infoContainerDark = selectionDark;
  static const Color onInfoContainerDark = forestDeepDark;

  // ------------------------------------------- elevated chrome / selection
  /// Compatibility surface wrapper paints a solid warm surface. No optical
  /// glass material is used by the NexaDrive design system.
  static const Color glassSurfaceLight = Color(0xFFFAF9F4);
  static const Color glassSurfaceDark = Color(0xFF30352B);
  static const Color glassHighlightLight = Color(0x00000000);
  static const Color glassHighlightDark = Color(0x00000000);
  static const Color glassBorderLight = Color(0x40E5E3D9);
  static const Color glassBorderDark = Color(0x40353A31);
  static const Color glassSelectionLight = selectionLight;
  static const Color glassSelectionDark = selectionDark;

  static Color glassSurfaceFor(Brightness b) =>
      b == Brightness.dark ? glassSurfaceDark : glassSurfaceLight;
  static Color glassHighlightFor(Brightness b) =>
      b == Brightness.dark ? glassHighlightDark : glassHighlightLight;
  static Color glassBorderFor(Brightness b) =>
      b == Brightness.dark ? glassBorderDark : glassBorderLight;
  static Color glassSelectionFor(Brightness b) =>
      b == Brightness.dark ? glassSelectionDark : glassSelectionLight;

  // ---------------------------------------------------------- analytics
  /// Muted, warm qualitative hues. No blue/purple family, no rainbow.
  static const List<Color> analyticsPaletteLight = [
    Color(0xFF355C46),
    Color(0xFFA4654B),
    Color(0xFFB4874B),
    Color(0xFF738D6E),
    Color(0xFF8A7A52),
    Color(0xFFA97678),
  ];

  static const List<Color> analyticsPaletteDark = [
    Color(0xFF9CC4A9),
    Color(0xFFD5A28C),
    Color(0xFFD8B27E),
    Color(0xFFA8C2A1),
    Color(0xFFC1B38B),
    Color(0xFFD3A0A1),
  ];

  static List<Color> analyticsPaletteFor(Brightness brightness) =>
      brightness == Brightness.dark
          ? analyticsPaletteDark
          : analyticsPaletteLight;

  // ------------------------------------------------------------ file icons
  /// Restrained format identities shared by list, grid, search, shared and
  /// dashboard presentation. Dark variants stay legible on warm dark surfaces.
  static const Color filePdfLight = Color(0xFF9B5B4C);
  static const Color filePdfDark = Color(0xFFD9A092);
  static const Color fileArchiveLight = Color(0xFFB4874B);
  static const Color fileArchiveDark = Color(0xFFD8B27E);
  static const Color fileWordLight = Color(0xFF315B45);
  static const Color fileWordDark = Color(0xFF9CC4A9);
  static const Color fileSheetLight = Color(0xFF6F8B6B);
  static const Color fileSheetDark = Color(0xFFA8C2A1);
  static const Color fileSlidesLight = Color(0xFFB5714F);
  static const Color fileSlidesDark = Color(0xFFDCA988);
  static const Color fileTextLight = Color(0xFF777A70);
  static const Color fileTextDark = Color(0xFFB7BBAE);
  static const Color fileCodeLight = Color(0xFF343A34);
  static const Color fileCodeDark = Color(0xFFD7D9CF);
  static const Color fileAudioLight = Color(0xFFA97678);
  static const Color fileAudioDark = Color(0xFFD3A0A1);
  static const Color fileVideoLight = Color(0xFF767F55);
  static const Color fileVideoDark = Color(0xFFB3BC8E);
  static const Color fileImageLight = Color(0xFF738D6E);
  static const Color fileImageDark = Color(0xFFA8C2A1);
  static const Color folderOchreLight = Color(0xFFB08A5A);
  static const Color folderOchreDark = Color(0xFFD4B284);
  static const Color folderSageLight = Color(0xFF8BA48A);
  static const Color folderSageDark = Color(0xFFAFC9AC);

  // ------------------------------------------------------------ shadows
  static const Color shadowColorStrong = Color(0x4A1B1F18);
  static const Color shadowColorSoft = Color(0x241B1F18);

  // ------------------------------------------------------------ scrims
  static const Color scrim = Color(0x66201F1A);

  // ----------------------------------------------------------------- api
  static Color accentFor(Brightness b) =>
      b == Brightness.dark ? accentDark : accent;

  static Color accentTextFor(Brightness b) =>
      b == Brightness.dark ? accentHighEmphasisDark : accentHighEmphasisLight;

  static Color accentSubtleFor(Brightness b) =>
      b == Brightness.dark ? accentSubtleDark : accentSubtleLight;

  static Color backgroundFor(Brightness b) =>
      b == Brightness.dark ? backgroundDark : backgroundLight;

  static Color onAccentFor(Brightness b) =>
      b == Brightness.dark ? textOnPrimaryDark : textOnPrimaryLight;

  static Color accentContainerFor(Brightness b) =>
      b == Brightness.dark ? accentContainerDark : accentContainerLight;

  static Color onAccentContainerFor(Brightness b) =>
      b == Brightness.dark ? onAccentContainerDark : onAccentContainerLight;

  static Color textPrimaryFor(Brightness b) =>
      b == Brightness.dark ? textPrimaryDark : textPrimaryLight;

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

  static Color surfaceElevatedFor(Brightness b) =>
      b == Brightness.dark ? surfaceElevatedDark : surfaceElevatedLight;

  // ------------------------------------------------------ surface aliases
  static Color systemBackgroundFor(Brightness b) => surfaceFor(b);
  static Color secondaryBackgroundFor(Brightness b) => surfaceAltFor(b);
  static Color surfaceGroupedFor(Brightness b) =>
      b == Brightness.dark ? surfaceGroupedDark : surfaceGroupedLight;
  static Color surfaceGroupedAltFor(Brightness b) =>
      b == Brightness.dark ? surfaceGroupedAltDark : surfaceGroupedAltLight;
  static Color surfaceAltFor(Brightness b) =>
      b == Brightness.dark ? surfaceAltDark : surfaceAltLight;

  static Color labelPrimaryFor(Brightness b) => textPrimaryFor(b);
  static Color labelSecondaryFor(Brightness b) => textSecondaryFor(b);
  static Color labelTertiaryFor(Brightness b) => textTertiaryFor(b);
  static Color labelQuaternaryFor(Brightness b) => textTertiaryFor(b);

  static Color separatorFor(Brightness b) => dividerFor(b);
  static Color separatorOpaqueFor(Brightness b) =>
      b == Brightness.dark ? separatorDark : separatorLight;

  static Color fillFor(Brightness b) => surfaceAltFor(b);
  static Color fillSecondaryFor(Brightness b) => surfaceAltFor(b);
  static Color fillTertiaryFor(Brightness b) => surfacePressedFor(b);

  static Color shadowColorFor(Brightness b) =>
      b == Brightness.dark ? shadowColorStrong : shadowColorSoft;
  static Color scrimFor(Brightness b) => scrim;

  // ------------------------------------------------------- flat hero text
  /// Kept for compatibility with legacy hero code. Storage now uses a flat
  /// editorial summary, so these resolve to ordinary ink rather than gradient
  /// contrast.
  static const Color onGradientLight = inkLight;
  static const Color onGradientDark = inkDark;

  static Color heroTextOnGradient(Brightness b) =>
      b == Brightness.dark ? onGradientDark : onGradientLight;

  // ------------------------------------------------------ M3 role helpers
  static Color primaryFor(Brightness b) => accentFor(b);
  static Color onPrimaryFor(Brightness b) => onAccentFor(b);
  static Color primaryContainerFor(Brightness b) => accentContainerFor(b);
  static Color onPrimaryContainerFor(Brightness b) => onAccentContainerFor(b);
  static Color secondaryFor(Brightness b) =>
      b == Brightness.dark ? secondaryDark : secondaryLight;
  static Color secondaryContainerFor(Brightness b) =>
      b == Brightness.dark ? secondaryContainerDark : secondaryContainerLight;
  static Color onSecondaryContainerFor(Brightness b) => b == Brightness.dark
      ? onSecondaryContainerDark
      : onSecondaryContainerLight;
  static Color tertiaryFor(Brightness b) =>
      b == Brightness.dark ? tertiaryDark : tertiaryLight;
  static Color tertiaryContainerFor(Brightness b) =>
      b == Brightness.dark ? tertiaryContainerDark : tertiaryContainerLight;
  static Color onTertiaryContainerFor(Brightness b) =>
      b == Brightness.dark ? onTertiaryContainerDark : onTertiaryContainerLight;
  static Color surfaceVariantFor(Brightness b) =>
      b == Brightness.dark ? surfaceAltDark : surfaceAltLight;
  static Color outlineFor(Brightness b) => separatorOpaqueFor(b);
  static Color inversePrimaryFor(Brightness b) =>
      b == Brightness.dark ? forestSoftDark : forestSoftLight;
}
