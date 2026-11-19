# NexaDrive design system

NexaDrive uses **Material 3 (Material You)** as its single visual language.
The design system lives in `app/lib/core/design/` (`App*` tokens) and
`app/lib/ui/widgets/` (`Nexa*` components). No screen may introduce a parallel
palette, type scale, shadow system or custom navigation idiom.

## Foundations

### Color

One seed color (`AppColors.seed`, currently `#6750A4`) generates the tonal
palettes. `ColorScheme.fromSeed` is the runtime source of truth; `AppColors`
exposes stable role names over it. Use roles, never raw hex:

- `primary` / `onPrimary` / `primaryContainer` / `onPrimaryContainer`
- `secondary`, `tertiary` and their containers
- `surface`, `surfaceContainerLowest`, `surfaceContainerLow`,
  `surfaceContainer`, `surfaceContainerHigh`, `surfaceContainerHighest`
- `onSurface`, `onSurfaceVariant`, `outline`, `outlineVariant`
- `error` / `errorContainer`, plus tuned success/warning pairs

Light mode uses a near-white seeded surface; dark mode uses the seeded dark
surface. Contrast floors: 4.5:1 for body text, 3:1 for large text and icons.
Status is never conveyed by color alone.

### Typography

`AppTextStyle` maps to the Material 3 scale:

| Role | Size / line height / weight |
| --- | --- |
| `display` | 36 / 44 / 400 |
| `headlineSmall` (`title3`) | 24 / 32 / 400 |
| `titleLarge` | 22 / 28 / 400 |
| `titleMedium` (`headline`, `rowTitle`) | 16 / 24 / 500 |
| `titleSmall` (`callout`) | 14 / 20 / 500 |
| `bodyLarge` (`body`) | 16 / 24 / 400 |
| `bodyMedium` (`subheadline`) | 14 / 20 / 400 |
| `bodySmall` (`footnote`) | 12 / 16 / 400 |
| `labelLarge` (`button`) | 14 / 20 / 500 |
| `labelMedium` (`chipLabel`) | 12 / 16 / 500 |
| `labelSmall` (`caption`) | 11 / 16 / 500 |

The platform font is intentional; it honours system font-size settings and
stays native on Android, Windows and Linux.

### Shape and elevation

Shape comes from `AppDimens`: extraSmall 4, small 8, medium 12, large 16,
extraLarge 28, full pill 999. Buttons, chips and search bars use a stadium
shape. Elevation is carried first by tonal surface roles; shadows are only for
menus, the floating navigation pill and modals (level 3).

### Motion

`AppMotion` holds Material standard/entering/exiting curves and short
durations. Springs are reserved for the one signature interaction: the
floating navigation pill's travelling selection. Reduced motion replaces
springs and slides with immediate state changes or cross-fades.

## Navigation

- Width `>= 900`: Material 3 navigation rail (`SideNavigation`) + content.
- Narrower: the **floating pill** (`NexaBottomNav`) is the primary navigation.
  Keep it; it is the deliberate NexaDrive signature. It now uses tonal M3
  surfaces and Material state layers, not optical glass.
- Pushed routes use the shared Material 3 fade-forward transition.

## Accessibility and craft

- 48dp minimum touch targets; 56dp list rows.
- Semantic labels on every icon-only control.
- Respect reduced motion, increased contrast and system text scaling.
- One signature element per screen; everything else stays quiet.
- Loading, empty and error states are part of the design, not afterthoughts.

## Non-goals

- No Apple/iOS chrome, no Cupertino theme, no custom Liquid Glass claims.
- No hardcoded colors or font sizes in screens.
- No third design system beside `App*` + `Nexa*`.
