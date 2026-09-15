# NexaDrive UI — Responsive Behavior Audit

> Factual account of how the 1.1.0 UI behaves across widths/heights, with the
> breakpoints that actually exist in code and the test coverage that guards them.

---

## 1. Breakpoints actually used (exhaustive list from source)

| Threshold | Where | Effect |
|-----------|-------|--------|
| `width >= 900` | `app_shell.dart:255` | Switch to desktop: `SideNavigation` (236) shown, `NavigationBar` hidden |
| `width < 700` | `login_screen.dart:100` | compact: page gutter 24 & short hint text; else gutter 32 + extended hint |
| `maxWidth >= 800` → 4 else 2 | `home_screen.dart:249` | Quick-action columns ground |
| `maxWidth >= 420` → 2 else 2 | `home_screen.dart:251` | (dead branch — both arms are 2) |
| inset-padding `MediaQuery.padding` | many & SafeArea | system insets (notch/nav bars) |
| `MediaQuery.padding` for walls | none | no orientation-lock handling; rotates freely |

Everything else is fluid (gutter 24 fixed, content maxWidth 1100, grid `SliverGridDelegate
WithMaxCrossAxisExtent`).

---

## 2. Behavior snapshots by width (computed from code)

### < 700 (phones, portrait)
- Bottom `NavigationBar` (84 tall) + 5 destinations w/ labels; More sheet for page 4+.
- Login single column, gutter 24, maxWidth 440, compact hint.
- Photos grid: `maxCrossAxisExtent 190` fills 1~2 cols (240px-wide phone → 1 col of ~150px).
- Files grid: `maxCrossAxisExtent 170` → 2 cols on a 360dp phone (≈ (360−48−12)/2 = 150px).
- Home quick actions: 2 columns (tiles ≈ (W−48−12)/2).

### 700–899 (large phones / small landscape tablets)
- Still mobile chrome (bottom nav). Login switches to wide hint text + gutter 32.
- Quick actions still 2 (the ≥800 branch not yet active at 799).
- Photos → 2–3 cols; files → 2–3; widget test covers 800×1280 to assert no exceptions.

### 900–1099 (tablets / small desktop windows)
- Sidebar appears; page area = W−236. Content centered ≤1100.
- Quick actions hit 4 columns (≥800 available after 236 rail: a 900 window → 664 body
  → still 2 columns; 1136+ window → 900 body → 4 columns).
- Files grid max-cross 170 → ~4 cols in 900px body.

### ≥ 1100 (typical desktop)
- Sidebar + content capped at 1100 (OneUiBody default). Home/file lists breathe.

**Nav semantics:** mobile index 4 (More) is not itself a page; Trash is index 4 page but
shown only through More sheet on mobile, while desktop has Trash in the rail list. This
is the single design inconsistency between platforms (Trash reachability).

---

## 3. Grid behaviors in detail

| Grid | Delegate | Notes |
|------|----------|-------|
| Photos | `MaxCrossAxisExtent(190)`, gap 4 | 1:1 tiles, radius 12; padding only bottom 24 + page gutter 0 (tiles bleed to the 24 gutter? — actually grid has NO horizontal page gutter; tiles span the full width incl. 0 gutter). **Fact:** Photos grid uses `padding: EdgeInsets.only(bottom:24)` — tiles touch the screen edges (radius 12 tiles with 4px gaps = near-full-bleed, maxCross 190 centers them). |
| Files grid | `MaxCrossAxisExtent(170)`, gap 12, aspect 0.95 | proper page gutter 24. |
| Home quick actions | `LayoutBuilder` fixed 2/4 col with 12-gap | tile width computed from constraints, wraps to full width rows (Wrap). |

---

## 4. Height behavior / scrolling

- Home, files, shared (both tabs), trash, settings, transfers, notifications, photos,
  users, audit, sync center, browse, viewer(text/pdf/audio/video), login: all
  screen-scrollable (ListView/SingleChildScrollView). **No fixed-height grids that
  overflow at small heights.**
- PhotoViewer: landscape fullscreen; `extendBodyBehindAppBar`; bottom bar sits over
  image (SafeArea aware). In landscape with system gesture bar, bar+image coexist.
- Dialogs (New folder, Rename, New user) wrap content in SingleChildScrollView (New
  user does; Rename/New folder don't but are 2 fields `[EST]` no overflow risk at
  typical small heights).
- Upload dialog: content `Flexible` list + fixed progress; width 380 — on <400 logical
  phones, 380 + dialog insets could approach screen width `[EST]`; tested at 400×800
  (widget test passes for app shell, integration sweep 400×800 fine).

---

## 5. Safety margins & overflow risks (checked spots)

- Headers: `Row(title Expanded, actions)` — long titles ellipsize (title Text has no
  maxLines wrapper but sits in Expanded; pageTitle wraps instead of truncating — a very
  long server path in My files subtitle is `maxLines:1`).
- `_ViewArea` selection count + "Back to My files" + close button: narrow widths OK.
- Share sheet: SegmentedButton + 2 buttons row; on ≤360 the two Expanded buttons +
  12 gap still fit (labels "Remove link"/"Create link" at 16px might wrap `[EST]`).
- Folder picker button label "Move to <path>" truncates at 1 line (no maxLines/ellipsis
  set → wraps, FilledButton grows `[EST]`).
- Availability: no hard-coded landscape layouts; portrait-only assumptions none except
  quick-action column count.

---

## 6. Test coverage (from source)

- `widget_test.dart`:
  - 2560×1800 @DPR2 → desktop: asserts sidebar words (NexaDrive/Home/My files/Settings)
    and **absence of NavigationBar**.
  - 400×800 → mobile: asserts NavigationBar + "More" sheet contents.
- `integration_test/responsive_test.dart`: walks the 7 sizes (400×800, 600×960,
  800×1280, 1280×720, 1280×900, 1366×768, 1920×1080) over the 6 shell pages and asserts
  `takeException() == null` — guards overflow regressions only.
- No test is pixel-render-based except `capture_test.dart` (screenshots at 7 sizes for
  the docs; see PERFORMANCE/REVERSE notes).

**Coverage gap:** no assertion for the ≥1100 four-column quick actions, no fold/tablet
navigation assertions, no text-boldster (max textScaleFactor) sweep, no RTL session.

---

## 7. Platform difference facts

- Android/iOS: bottom nav + More sheet; `SafeArea` everywhere; FadeForwards (Android) /
  Zoom (iOS) route transitions.
- Windows/Linux/macOS: sidebar rail, sync desktop-only features shown; auto-sync runs on
  desktops only; Workmanager (background uploads) is Android-only, silently absent on
  other platforms (no in-app notice).
- Width, not pointer type, drives layout — a 900-wide tablet window gets the sidebar and
  a resized phone also gets it; behavior is deterministic and testable.