/// NexaDrive dimension tokens.
///
/// THE REFERENCE: Apple's platform metrics. The scale is an 8pt grid with the
/// four-point half-steps UIKit actually uses; page gutters match the iOS
/// standard 16–20pt margin; touch targets honour the 44pt minimum; radii are
/// generous but never uniform capsules.
///
/// Two naming families are provided:
///  * numeric (`space16`, `radiusCard`) — the canonical scale;
///  * semantic (`spaceSm`, `spaceLg`) — the small set used by layout code.
/// Both resolve to the same grid.
abstract final class AppDimens {
  // -------------------------------------------------------------- spacing
  static const double space1 = 1;
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
  static const double space56 = 56;

  // Semantic spacing aliases.
  static const double space2xs = space4;
  static const double spaceXs = space8;
  static const double spaceSm = space12;
  static const double spaceMd = space16;
  static const double spaceLg = space20;
  static const double spaceXl = space24;
  static const double space2xl = space32;

  // ---------------------------------------------------------- page margins
  /// Horizontal page gutter (phone): the iOS 16pt content margin.
  static const double pageMargin = 16;

  /// Horizontal page gutter on large screens.
  static const double pageMarginWide = 24;

  /// Readable content width ceiling on desktop/tablet.
  static const double contentMaxWidth = 1000;

  /// Inset used by grouped-list rows before their leading content.
  static const double rowInset = 16;

  /// Stacked list/tile heights.
  static const double listHeight = 52;
  static const double listHeightNarrow = 44;
  static const double listHeightLarge = 56;
  static const double listHeightHero = 72;

  /// Preferred grouped-panel radius (iOS inset-grouped style): generous.
  static const double panelRadius = 16;

  // ------------------------------------------------------------ radii
  /// Small radius (chips, small controls, inputs).
  static const double radiusSmall = 8;

  /// Standard radius (list rows, small containers).
  static const double radiusStandard = 10;

  /// Inner radius for nested containers within tiles.
  static const double radiusInner = 12;

  /// Medium radius (cards, grouped panels).
  static const double radiusMedium = 16;

  /// Large radius (hero surfaces).
  static const double radiusLarge = 20;

  /// Tile radius for grouped list rows / media.
  static const double radiusTile = 12;

  /// Radius for cards that group a block of related content.
  static const double radiusCard = 16;

  /// Radius for the hero surfaces (Home storage hero, spotlight blocks).
  static const double radiusHero = 24;

  /// Radius for popovers / anchored context panels.
  static const double radiusPopup = 14;

  /// Radius for bottom sheets / large surfaces.
  static const double radiusSheet = 24;

  /// Extra-large radius (hero surfaces, full-screen sheets).
  static const double radiusXLarge = 24;

  /// Radius for dialogs.
  static const double radiusDialog = 20;

  /// Pill radius (buttons, search bars, segmented controls).
  static const double radiusPill = 999;

  // ---------------------------------------------------------- breakpoints
  static const double breakpointCompactMax = 600;
  static const double breakpointMediumMax = 900;
  static const double breakpointExpandedMax = 1200;
  static const double breakpointLargeMin = 1200;

  // -------------------------------------------------------------- chrome
  static const double navRailWidth = 236;
  static const double bottomNavHeight = 56;
  static const double navBarHeight = 49;
  static const double navBarHeightLarge = 83;
  static const double toolbarHeight = 44;
  static const double toolbarHeightLarge = 96;
  static const double statusBarHeight = 47;
  static const double contextualBarHeight = 60;
  static const double segmentedHeight = 32;

  // ---------------------------------------------------------- touch sizes
  /// Minimum hit target. 44pt is Apple's floor; 48 is used because the
  /// project's own accessibility tests assert a 48dp minimum.
  static const double touchTarget = 48;
  static const double touchTargetLarge = 48;

  // ------------------------------------------------------------- icon sizes
  static const double iconSmall = 18;
  static const double iconSm = 18;
  static const double iconMedium = 22;
  static const double iconMd = 22;
  static const double iconLarge = 28;
  static const double iconLg = 28;
  static const double iconTile = 40;
  static const double iconTileLarge = 44;
  static const double iconHero = 60;

  // ------------------------------------------------------------ elevation
  static const double elevationNone = 0;
  static const double elevationSubtle = 1;
  static const double elevationLevel1 = 0;
  static const double elevationLevel2 = 4;
  static const double elevationLevel3 = 12;
  static const double elevationLevel4 = 24;
  static const double elevationSheet = 24;

  // ---------------------------------------------------------------- blur
  /// Backdrop blur radii for frosted/glass materials.
  static const double blurLight = 12;
  static const double blurStandard = 24;
  static const double blurHeavy = 40;

  // ------------------------------------------------------------- density
  /// Row unit heights by density.
  static double listHeightFor(AppDensity density) => switch (density) {
        AppDensity.comfortable => listHeight,
        AppDensity.compact => listHeightNarrow,
        AppDensity.immersive => listHeight,
      };
}

/// Three content densities (Comfortable / Compact / Immersive).
enum AppDensity { comfortable, compact, immersive }
