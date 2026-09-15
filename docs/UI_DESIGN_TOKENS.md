# NexaDrive UI — Design Tokens (exact source values)

> Single source of truth for every design token as compiled in 1.1.0.
> Files: `app/lib/core/design/{app_colors,app_dimensions,app_typography,app_motion,app_theme}.dart`
> Contrast ratios are computed from the hex values (WCAG relative luminance, sRGB);
> marked **[EST]** where the surface pairing is composite/alpha-blended.

---

## 1. Color tokens — `AppColors` (app_colors.dart)

### 1.1 Accent family
| Token | Light | Dark | Used for |
|-------|-------|------|----------|
| `accent` | `#0B87D0` | — | light primary/filled buttons, links, selected nav, toggles |
| `accentDark` | — | `#6CC4F7` | accent on dark surfaces, actionText in snackbars |
| `accentContainer` | `#E1F1FA` | `#123A55` | selected rows, segmented selected, nav pill, badge, unread notif |
| `onAccentContainer` | `#0A5E8F` | `#9AD4F7` | text/icons on the container |
| `accentPressed` | `#08679F` | `#4FA8DF` | pressed/active accent (defined but unused in tree) |

### 1.2 Surfaces
| Token | Light | Dark | Role |
|-------|-------|------|------|
| `background` | `#F7F8FA` | `#000000` | page scaffold bg |
| `surface` | `#FFFFFF` | `#1D1E1F` | cards, sheets, tiles, dialogs, list panels |
| `surfaceAlt` | `#F2F3F5` | `#232425` | input fill, progress track, hover alt, thumb placeholder |
| `surfaceElevated` | `#FFFFFF` | `#232425` | nav bar, selection bar |

### 1.3 Text
| Token | Light | Dark | Contrast on own surface* |
|-------|-------|------|--------------------------|
| `textPrimary` | `#1A1C1E` | `#F6F7F8` | ~16.2:1 on white / ~17.6:1 on #1D1E1F **[EST]** |
| `textSecondary` | `#5B5F66` | `#B8BDC3` | 6.4:1 on white / ~11:1 on black **[EST]** |
| `textTertiary` | `#8A9099` | `#7D838C` | 3.2:1 on white / ~5.5:1 on black; ~4.4:1 on surfaceDark **[EST]** |
| `textOnPrimary` | `#FFFFFF` | `#001D33` | white 3.9:1 on `#0B87D0`; `#001D33` ~11.0:1 on `#6CC4F7` |
| `textLink` | = accent | = accentDark | |

\* See ACCESSIBILITY_AUDIT for the computed numbers.

### 1.4 Dividers / scrims / shadows
| Token | Value |
|-------|-------|
| `divider` | `0x1F000000` (light, = 12% black) / `0x1FFFFFFF` (dark) |
| `scrim` (modal-sheet dim) | `0x66000000` (= ~40% black) |
| `shadowColorStrong` | `0x1A000000` (10% black) |
| `shadowColorSoft` | `0x0F000000` (6% black) — default elevation shadow |

### 1.5 Status colors
| Token | Light | Dark |
|-------|-------|------|
| `success` | `#23641E` | `#7BD46A` |
| `warning` | `#B25E00` | `#F1AD56` |
| `error` | `#B3261E` | `#FF5449` |
| `info` | = accent | = accentDark |

### 1.6 FileKind category tints (fixed across modes)
folder `#0B87D0` · image `#B25E00` · video `#8E24AA` · audio `#00897B` · pdf `#C62828`
· document `#5B5F66` · archive `#6D4C41` · text `#455A64` · unknown `#8A9099`.
Tile fill = tint @ 12% (light) / @ 20% (dark) — see UI_COMPONENT_INVENTORY §5.

---

## 2. Dimension tokens — `AppDimens` (app_dimensions.dart)

### 2.1 Spacing scale
2, 4, 6, 8, 10, 12, 16, 20, 24, 28, 32, 40, 48.

### 2.2 Page & layout
| Token | Value |
|-------|-------|
| `pageMargin` | 24 |
| `pageMarginWide` | 32 |
| `contentMaxWidth` | 1100 |
| `listHeight` / `listHeightNarrow` | 60 / 56 |

### 2.3 Radii
| Token | Value | Used for |
|-------|-------|----------|
| `radiusTile` | 18 | list rows, file tiles, rail items, transfers rows, notification rows |
| `radiusInner` | 12 | chips, icon tiles, inputs, small previews, snackbars, popover menus |
| `radiusCard` | 22 | Home storage/quick-action/pending cards, sync cards, sheet/tile panels, empty-state tile, brand/photo tiles |
| `radiusSheet` | 28 | bottom-sheet top corners |
| `radiusDialog` | 24 | dialogs |
| `radiusPill` | 999 | buttons, segmented, progress tracks, search bars, nav indicator |

### 2.4 Touch & icon & elevation
| Token | Value |
|-------|-------|
| `touchTarget` / `touchTargetLarge` | 48 / 56 |
| `iconTile` / `iconTileLarge` | 40 / 48 |
| `iconSmall` / `iconMedium` | 20 / 24 |
| `elevationNone` / `elevationSubtle` / `elevationSheet` | 0 / 1 / 16 |

(Other exact geometry not tokenized: sidebar width 236; AppBar height 56; nav-bar height
84; photo grid gap 4 / max-extent 190; files grid max-extent 170 / gap 12 / aspect 0.95;
empty-state tile 72; download-tile 96; share-file tile 48; storage icon-tile 40; progress
bar heights 4·6·8; drag handle 36×4; details label width 90.)

---

## 3. Typography tokens — `AppTextStyle` (app_typography.dart)
System font only. Exact styles:

| Style | Size/Height/Wght/LS | Role |
|-------|---------------------|------|
| `pageTitle` | 28 / 1.2 / **w700** / −0.3 | page headers |
| `display` | 34 / 1.15 / **w700** / −0.5 | login hero, profile initial sized 30 via copyWith |
| `sectionHeader` | 17 / 1.3 / **w600** / — | in-page section titles |
| `listHeader` | 13 / 1.2 / **w600** / 0.4 (uprated 0.6–0.8 in use) | uppercase group headers (callers apply `.toUpperCase()`) |
| `rowTitle` | 16 / 1.3 / **w500** | list row names; w600 when selected/emphasis |
| `rowSubtitle` | 13 / 1.3 / w400 | secondary lines |
| `caption` | 12 / 1.3 / w400 | metadata |
| `micro` | 11 / 1.2 / w400 | badges / tight rows |
| `button` | 16 / — / **w600** / 0.1 | Filled/Outlined primary |
| `buttonSmall` | 14 / — / w600 | TextButton / admin avatar initial |
| `dialogTitle` | 20 / 1.3 / w600 | dialogs |

Material text-theme mapping (app_theme `_textTheme`): displayMedium 26/w600,
titleLarge 20/w600/h1.3, bodyLarge 16/w400/h1.4 — see COMPONENT_INVENTORY §4.

Note: `AppBar` title is fixed 18/w600 (not a token). Reserved-but-unused tokens: none
confirmed — every style above is referenced somewhere `[EST]`.

---

## 4. Motion tokens — `AppMotion` (app_motion.dart)

| Token | Value |
|-------|-------|
| `micro` / `fast` / `normal` / `slow` | 120 / 180 / 300 / 380 ms |
| `standard` curve | Cubic(0.25, 0.1, 0.3, 1) |
| `enter` curve | Cubic(0.15, 0.85, 0.25, 1) |
| `exit` curve | Cubic(0.45, 0.05, 0.85, 0.2) |
| `fade` curve | Curves.easeOut |
| spring response / damping | 0.35 / 1.0 (critically damped) |
| helpers | `defaultSwitcher` (fast, enter/exit), `reducedMotion(ctx)`, `resolve(ctx, d)` → Duration.zero when reduced |

**Adoption audit:** tokenized motion is used ONLY by the Home storage bar
(`AppMotion.normal` + `standard`). The shell page cross-fade (200ms easeOut/in), upload
dialog AnimatedSwitcher (180ms), sheets/dialogs, RefreshIndicator, and route transitions
are Material defaults or raw literals — not sourced from `AppMotion`.

---

## 5. Theme-to-component mapping (app_theme.dart — the effective tokens)

Those values surface as:
- **swim-fill styles**: FilledButton accent / out accent / text accent pill, min 64×48,
  padding h24 v12, text `button`.
- **input**: fill surfaceAlt, radius 12, dense h16 v16 padding; focus border accent width 2;
  error border error 1.5.
- **nav bar**: height 84, surfaceElevated, no tint/elevation, indicator accentContainer pill,
  label 11 (w600 selected accent / w500 textSecondary), icons 24.
- **switch**: on = accent, off = divider@60%, outline none, thumb white always.
- **segmented**: selected accentContainer/onAccentContainer, unselected transparent/textSecondary,
  border divider, pill, text 13.
- **dialogs/sheets**: as §2.3; snackbar dark surfaces `#1A1C1E`/`#2D2E30` radius 12 white 14.
- **tooltips/scrim/scrollbar** per COMPONENT_INVENTORY §4.

---

## 6. Notable literal values outside the token files (facts to know)

| Where | Value |
|-------|-------|
| photo viewer bg | `#000000` |
| photo bar tint | `#FFFFFF` @ 6%, blur sigma 12 |
| selection badge | 22px (list) / 20px (grid) |
| empty-state icon | 36 in 72 tile |
| download-tile icon | 44 in 96 tile |
| upload dialog width | 380 |
| sheet title padding | 8 / 8/ 8 / 12–16 |
| login card max width | 440 |
| hero brand tile | 62, radius 22, icon 32 |
| settings avatar | 68 circle (radius ∞) |
| admin avatar | CircleAvatar r16 / ListTile radius 18 |
| progress min-heights | 4·6·8 (upload row / storage & pending & progress-tile / upload dialog) |
| image-cache | 384 MiB / 400 entries |
| thumbnails | 512px max, JPEG q84, 7-day/512 disk TTL, `md5(server|path)` key |
| chunk | 8 MiB upload chunks |