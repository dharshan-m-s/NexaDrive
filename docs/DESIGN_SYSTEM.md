# NexaDrive Design System — Samsung One UI

> The single source of truth for how the Flutter client looks and behaves.
> Governs `lib/core/design/` (tokens) and `lib/ui/widgets/` (primitives).
> Design authority order (per AGENTS.md design review): explicit spec rules >
> Samsung One UI principles > NexaDrive tokens > Apple methodology (review lens
> only) > Flutter capabilities. Apple's visual language is intentionally absent.

## 1. Design pillars

1. **Clear hierarchy.** Viewing area (title, context, status) at top; interaction
   area (controls that matter) near the reach-thumb at the bottom.
2. **Whitespace.** 24dp page gutters, generous section spacing, breathing room
   over dense chrome.
3. **Restrained motion.** Critically damped springs, fast settle, no idle looping.
4. **Large legible type.** Hero titles, clear weights, size-specific tracking.
5. **Consistent roundness.** Radii come only from `AppDimens` (`radiusInner`
   18 · `radiusTile` 22 · `radiusCard` 28 · `radiusSheet` 24 · `radiusPill` 999).
6. **Honest materials.** Tonal layering (surface hierarchy L0–L4) with restrained
   shadow at L3+, not fake embossing.
7. **One accent.** Samsung-application blue, tonal containers, never rainbow.

## 2. Tokens

| Token file | Provides | Notes |
|---|---|---|
| `app_colors.dart` | `accent`, `accentSubtle`, `accentContainer`, `accentPressed`, surface/background L0–L4, status (success/warning/error + containers), `textPrimary/Secondary/Tertiary`, `divider`, `heroTextOnGradient` | Every color is resolved with `*For(Brightness)` — never a bare constant in a widget. |
| `app_dimensions.dart` | gutters (24), radii (18/22/28/24), `iconSmall/Medium/Large`, `iconTileLarge`, `spaceN`, `elevation*`, `contentMaxWidth = 1100` | Spacing multiples of 4. |
| `app_typography.dart` | `pageTitle`, `heroTitle` (38), `sectionHeader`, `metricValue` (26), `statValue` (18), `rowTitle`, `rowSubtitle`, `listHeader`, `chipLabel` (12), `micro`, `caption`, `dialogTitle`, `buttonSmall` | Weight + size + leading as a set; fixed sizes scale with the platform text scaler. |
| `app_motion.dart` | durations `micro/fast/normal/slow`, curves `standard/enter/exit/fade`, springs (`response 0.35 / damping 1.0` critical), `reducedMotion(context)` helpers | Every animation duration in the app must come from here or `AppMotion.resolve(...)`. |
| `app_gradients.dart` | `GradientFamily.vivid/soft/pageWash/storageHero` | Cloud/secure/storage/media/success families; page washes stay subtle. |
| `app_shadows.dart` | `none`, `level1..level4` | Tone-based, restrained. |
| `app_transitions.dart` | `OneUiPageTransitionsBuilder`, `kOneUiPageTransitions` | Glide-up + settle + cross-fade; skips entirely under reduced motion. |
| `app_theme.dart` | `buildAppTheme(brightness)` — scheme + component themes (filled/outlined chip/searchBar/bottomAppBar/navigationBar/bottomSheet/pageTransitions) | Single place the theme is composed. |

### Surface hierarchy

| Level | Token | Use |
|---|---|---|
| L0 background | `backgroundDark/Light` | Page behind everything |
| L1 surface | `surfaceDark/Light` | Cards, rows, sheets |
| L2 grouped/alt | `surfaceAltDark/Light` | Selected rows, grouped surfaces, unread rows |
| L3 elevated/floating | `surfaceElevatedDark/Light` | Floating bars, action bars |
| L4 modal | dialog/sheet surfaces | Highest priority |

## 3. Layout doctrine

- **24dp page gutters** (`AppDimens.pageMargin`) on all interactive screens.
- **Interaction area rule:** in app body layout, place bottom-area the actions
  users reach for; keep labels/context in the viewing area (see SCREEN_SPECIFICATIONS.md).
- **1100dp cap:** interaction content never exceeds `AppDimens.contentMaxWidth`,
  centered on wide screens (enforced globally in `app_shell.dart`).
- **Reachability:** primary actions live at the bottom (action bar, bottom nav);
  secondary status at top.

## 4. Conventions

- Colors: always `Theme.of(context).brightness` → `AppColors.xFor(brightness)`.
- Text: always an `AppTextStyle.*` base, `.copyWith` for adjustments.
- Surfaces: prefer `OneUiSurface(level:)` over hand-built `Container` decorations.
- Icons: `IconData` from Material Icons; filled when selected, outlined when idle.
- List rows under a decorated surface: wrap the `ListTile` in
  `Material(type: MaterialType.transparency)` to avoid the
  "ListTile background color or ink splashes may be invisible" assertion.
- Motion while an element is touched: animate from the live value, never a
  hard-cut target; no two consecutive springs in opposite directions.
- No emoji, no confetti: honest materials and calm motion are the delight.