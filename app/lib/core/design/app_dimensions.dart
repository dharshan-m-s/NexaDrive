/// NexaDrive dimension tokens — editorial Material 3.
///
/// Layout uses a 4dp grid with an 8dp section rhythm. Shape is restrained:
/// content containers use 12–18dp corners, the floating navigation keeps its
/// signature pill, and touch targets never fall below 48dp.
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

  static const double space2xs = space4;
  static const double spaceXs = space8;
  static const double spaceSm = space12;
  static const double spaceMd = space16;
  static const double spaceLg = space20;
  static const double spaceXl = space24;
  static const double space2xl = space32;

  // ---------------------------------------------------------- page margins
  static const double pageMargin = 20;
  static const double pageMarginWide = 28;
  static const double contentMaxWidth = 1080;
  static const double rowInset = 20;

  // ------------------------------------------------------------- row sizes
  static const double listHeight = 68;
  static const double listHeightNarrow = 60;
  static const double listHeightLarge = 72;
  static const double listHeightHero = 76;
  static const double panelRadius = 14;

  // ------------------------------------------------------- restrained shape
  /// 4dp — tiny marks and selection dots.
  static const double radiusExtraSmall = 4;

  /// 8dp — compact chips and inner marks.
  static const double radiusSmall = 8;

  /// 12dp — document artwork and tight containers.
  static const double radiusStandard = 12;

  /// 14dp — nested surfaces.
  static const double radiusInner = 14;

  /// 18dp — grouped surfaces and controls.
  static const double radiusMedium = 18;

  /// 24dp — sheets and hero panels.
  static const double radiusLarge = 24;

  static const double radiusTile = 12;
  static const double radiusCard = 14;
  static const double radiusHero = 24;
  static const double radiusPopup = 14;
  static const double radiusSheet = 28;
  static const double radiusXLarge = 28;
  static const double radiusDialog = 24;
  static const double radiusPill = 999;

  // ---------------------------------------------------------- breakpoints
  static const double breakpointCompactMax = 600;
  static const double breakpointMediumMax = 900;
  static const double breakpointExpandedMax = 1200;
  static const double breakpointLargeMin = 1200;

  // -------------------------------------------------------------- chrome
  static const double navRailWidth = 248;

  /// The floating pill is compact and thumb-reachable, not a full-width dock.
  static const double bottomNavHeight = 72;
  static const double bottomNavMaxWidth = 400;
  static const double navBarHeight = 72;
  static const double navBarHeightLarge = 72;
  static const double toolbarHeight = 64;
  static const double toolbarHeightLarge = 88;
  static const double statusBarHeight = 24;
  static const double contextualBarHeight = 60;
  static const double segmentedHeight = 40;
  static const double componentHeight = 40;

  /// Dashboard gallery strip thumbnail.
  static const double photoStripTile = 104;

  // ---------------------------------------------------------- touch sizes
  static const double touchTarget = 48;
  static const double touchTargetLarge = 56;

  // ------------------------------------------------------------- icon sizes
  static const double iconSmall = 18;
  static const double iconSm = 18;
  static const double iconMedium = 24;
  static const double iconMd = 24;
  static const double iconLarge = 28;
  static const double iconLg = 28;
  static const double iconTile = 44;
  static const double iconTileLarge = 52;
  static const double iconHero = 64;

  // ------------------------------------------------------------ elevation
  /// Elevation is used only for floating navigation and modals. Content is
  /// separated by tone and hairline dividers instead of shadows.
  static const double elevationNone = 0;
  static const double elevationSubtle = 1;
  static const double elevationLevel1 = 1;
  static const double elevationLevel2 = 2;
  static const double elevationLevel3 = 4;
  static const double elevationLevel4 = 6;
  static const double elevationSheet = 6;

  // ---------------------------------------------------------------- blur
  /// Compatibility-only. The default NexaDrive surface system is opaque;
  /// translucency is reserved for moments where it genuinely aids legibility.
  static const double blurLight = 8;
  static const double blurStandard = 16;
  static const double blurHeavy = 24;

  // ------------------------------------------------------------- density
  static double listHeightFor(AppDensity density) => switch (density) {
        AppDensity.comfortable => listHeight,
        AppDensity.compact => listHeightNarrow,
        AppDensity.immersive => listHeight,
      };
}

/// Three content densities (Comfortable / Compact / Immersive).
enum AppDensity { comfortable, compact, immersive }
