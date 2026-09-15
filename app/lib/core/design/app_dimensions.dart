/// NexaDrive One UI dimension tokens.
///
/// One UI spacing philosophy: generous horizontal margins, comfortable touch
/// targets (48dp minimum, 52–56 for frequent actions), and grouped focus
/// blocks with soft rounded corners instead of endless tiny cards.
abstract final class AppDimens {
  // -------------------------------------------------------------- spacing
  static const double space2 = 2;
  static const double space4 = 4;
  static const double space6 = 6;
  static const double space8 = 8;
  static const double space10 = 10;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space20 = 20;
  static const double space24 = 24;
  static const double space28 = 28;
  static const double space32 = 32;
  static const double space40 = 40;
  static const double space48 = 48;

  // ---------------------------------------------------------- page margins
  /// Horizontal page gutter (phone): One UI's comfortable 24dp.
  static const double pageMargin = 24;

  /// Horizontal page gutter on large screens.
  static const double pageMarginWide = 32;

  /// Readable content width ceiling on desktop/tablet.
  static const double contentMaxWidth = 1100;

  /// Stacked list/tile height for One UI list rows.
  static const double listHeight = 60;
  static const double listHeightNarrow = 56;

  // ------------------------------------------------------------ radii
  /// Soft tile radius for grouped list rows / media (One UI rows are softly
  /// rounded rectangles, not hard-edged).
  static const double radiusTile = 18;

  /// Radius for nested container within tiles (chips, small previews).
  static const double radiusInner = 12;

  /// Radius for cards that genuinely group a block of related content.
  static const double radiusCard = 22;

  /// Radius for the hero surfaces (Home storage hero, spotlight blocks).
  static const double radiusHero = 28;

  /// Radius for popovers / anchored context panels.
  static const double radiusPopup = 16;

  /// Radius for bottom sheets / large surfaces.
  static const double radiusSheet = 28;

  /// Radius for dialogs.
  static const double radiusDialog = 24;

  /// Pill radius (buttons, search bars, segmented controls).
  static const double radiusPill = 999;

  // ---------------------------------------------------------- breakpoints
  /// One UI large-screen tiers (Samsung guidance): compact phone, medium
  /// fold/small tablet, expanded tablet/desktop.
  static const double breakpointCompactMax = 600;
  static const double breakpointMediumMax = 900;

  // -------------------------------------------------------------- chrome
  static const double navRailWidth = 236;
  static const double bottomNavHeight = 80;
  static const double contextualBarHeight = 64;

  // ---------------------------------------------------------- touch sizes
  static const double touchTarget = 48;
  static const double touchTargetLarge = 56;

  // ------------------------------------------------------------- icon sizes
  static const double iconTile = 40;
  static const double iconTileLarge = 48;
  static const double iconSmall = 20;
  static const double iconMedium = 24;

  // ------------------------------------------------------------ elevation
  /// One UI is famously "flat with depth". Use these sparingly.
  static const double elevationNone = 0;
  static const double elevationSubtle = 1;
  static const double elevationSheet = 16;

  // ------------------------------------------------------------- density
  /// Row unit heights by density.
  static double listHeightFor(AppDensity density) => switch (density) {
        AppDensity.comfortable => listHeight,
        AppDensity.compact => listHeightNarrow,
        AppDensity.immersive => listHeight,
      };
}

/// Three content densities (One UI "Comfortable / Compact / Immersive").
enum AppDensity { comfortable, compact, immersive }