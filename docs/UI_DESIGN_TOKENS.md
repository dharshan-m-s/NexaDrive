# UI design tokens

All visual values come from `app/lib/core/design/`. Screens and components
consume these tokens; they never declare their own palette, type scale or
motion curve.

## `AppColors` — Material 3 roles

- Seed: `AppColors.seed = #6750A4`. `ColorScheme.fromSeed` builds light and
  dark schemes; `AppColors.scheme(brightness)` returns the runtime scheme.
- Primary family: `accent` / `accentDark`, `accentContainerLight/Dark`,
  `onAccentContainerLight/Dark`, `accentTextFor`, `accentSubtleFor`.
- Secondary and tertiary: `secondaryFor`, `secondaryContainerFor`,
  `onSecondaryContainerFor`, `tertiaryFor`, `tertiaryContainerFor`,
  `onTertiaryContainerFor`.
- Surfaces: `backgroundFor`, `surfaceFor`, `surfaceAltFor`,
  `surfaceElevatedFor`, `surfacePressedFor`, `surfaceGroupedFor`,
  `surfaceGroupedAltFor`. Prefer the `ColorScheme.surfaceContainer*` roles in
  new code.
- Ink: `textPrimaryFor`, `textSecondaryFor`, `textTertiaryFor`,
  `labelPrimaryFor`, `labelSecondaryFor`, `labelTertiaryFor`.
- Lines/fills: `dividerFor`, `separatorFor`, `separatorOpaqueFor`, `fillFor`,
  `fillTertiaryFor`.
- Status: `errorFor`, `errorContainerFor`, `onErrorContainerFor`, plus tuned
  `success*`, `warning*` and `info*` families.
- Charts: `analyticsPaletteFor(brightness)` — six contrast-checked hues.
- Scrim/shadow: `scrim`, `shadowColorFor`.

Never use `Color(0xFF...)` in a widget. The only defensible exceptions are
user-supplied media colors and data series that must remain distinguishable;
use the analytics palette for the latter.

## `AppDimens` — layout and shape

- Spacing: `space1`…`space56`, semantic aliases `space2xs`…`space2xl`
  (4dp grid, 8dp rhythm).
- Page: `pageMargin` 16, `pageMarginWide` 24, `contentMaxWidth` 1000.
- Rows: `listHeight` 56, `listHeightNarrow` 48, `listHeightLarge` 64.
- Shape: `radiusExtraSmall` 4, `radiusSmall` 8, `radiusStandard` 12,
  `radiusMedium` 16, `radiusLarge` 28, `radiusSheet` 28, `radiusDialog` 28,
  `radiusPill` 999.
- Chrome: `bottomNavHeight` 80, `toolbarHeight` 64, `navRailWidth` 256.
- Touch: `touchTarget` 48, `touchTargetLarge` 56.
- Icons: `iconSmall` 18, `iconMedium` 24, `iconLarge` 28, `iconTile` 40.
- Elevation: `elevationLevel1` 1 through `elevationLevel4` 8.

## `AppTextStyle` — type roles

Canonical Material names are available (`display`, `headlineSmall`,
`titleLarge`, `titleMedium`, `titleSmall`, `bodyLarge`, `bodyMedium`,
`bodySmall`, `labelLarge`, `labelMedium`, `labelSmall`) alongside legacy
aliases (`pageTitle`, `rowTitle`, `rowSubtitle`, `caption`, `button`,
`navLabel`, `chipLabel`, `metricValue`, `code`). Both resolve to the same M3
scale. Never set `fontSize` directly in a screen.

## `AppMotion` — duration and curves

- Durations: `micro` 100ms, `fast` 150ms, `normal`/`navigation` 300ms,
  `slow` 500ms.
- Curves: `standard` (0.2, 0, 0, 1), `enter` (0, 0, 0, 1),
  `exit` (0.4, 0, 1, 1).
- Springs: only `glassSpring` for the floating pill selection; other springs
  are compatibility handles.
- Always call `AppMotion.resolve(context, duration)` and
  `AppMotion.curveFor(context, curve)`.

## `AppShadows` — elevation

`level1`–`level5` follow Material geometry (small offset, tight blur, low
alpha). Prefer tonal surfaces; use level 3 for the pill and menus.

## Surface primitive

`NexaSurface` maps `NexaSurfaceLevel` to M3 container roles:

| Level | Color | Radius | Elevation |
| --- | --- | --- | --- |
| `background` | `surface` | 0 | 0 |
| `surface` | `surfaceContainerLow` | 16 | 0 |
| `grouped` | `surfaceContainer` | 16 | 0 |
| `floating` | `surfaceContainerHigh` | 16 | 3 |
| `modal` | `surfaceContainerHigh` | 28 | 3 |

`NexaLiquidGlass` is now a compatibility wrapper that renders the same tonal
Material surface; it no longer uses the glass shaders.
