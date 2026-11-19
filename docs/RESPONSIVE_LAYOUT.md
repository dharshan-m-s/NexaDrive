# NexaDrive Responsive Layout Specification

> One Flutter codebase, three form-factor families: phone, tablet/foldable, and
> desktop. The rules below are enforced centrally in `ui/shell/app_shell.dart`
> plus the `Nexa*` primitives; widget tests lock the two breakpoints. Shell chrome
> follows the Material 3 design system (`DESIGN_SYSTEM.md`): a floating Material
> pill on mobile and a Material navigation rail on desktop.

## 1. Breakpoints & shells

| Window width | Shell | Notes |
|---|---|---|
| < 900px | Floating Material pill (`NexaBottomNav`, 5 slots, 5th = More sheet) + full-height page stack | Reachability-first; actions in the bottom action bar; 48dp touch targets |
| ≥ 900px | 236dp `SideNavigation` Material navigation rail + content | No bottom pill; utility destinations pinned in the rail |

Both shells render the same six page widgets; only the chrome changes.

## 2. Reading / interaction area

- Interaction content is centered and capped at `AppDimens.contentMaxWidth = 1100`
  on wide screens (enforced in the desktop `Expanded` branch of `app_shell.dart`).
- Screens keep the viewing area (title/subtitle) top and interaction area
  (action bar, upload/sync buttons, play controls) bottom — the reach zone.

## 3. Grids (Photos, My Files)

- Photos uses a responsive grid whose columns scale with available width
  (album grid, not fixed-count). Cell size and count adapt by layout width.
- The 1100dp cap keeps very wide monitors from stretching rows absurdly.

## 4. Desktop specifics

- `SideNavigation` is a Material navigation rail using seeded ColorScheme
  `surfaceContainer` roles with `ListTile`-based items and Material state layers
  for selection. Content is `SafeArea` within the centered, capped page
  (see DESIGN_SYSTEM.md "Layout doctrine").
- The widget test fixes: desktop logical width 1280 shows the `NexaDrive` brand,
  `Home`, `My files`, `Settings` in the rail and **no** `NavigationBar`.

## 5. Mobile specifics

- Floating Material pill (`NexaBottomNav`): tonal `surfaceContainer` surface,
  Material state layers, slot icons with always-show labels, 48dp touch targets.
- The widget test fixes: narrow 400×800 shows the pill (`NavigationBar`), visible
  `Photos`, and a More sheet containing Trash / Sync center / Notifications /
  Settings.

## 6. Tablet / foldable

- Tablets inherit the ≥900 shell (sidebar rail) but content still caps at 1100.
- Foldable considerations: three-way split is future scope. Optical glass and
  elastic effects are not part of the Material 3 system; the floating pill uses
  tonal `surfaceContainer` surfaces and Material state layers. Ensure `SafeArea`
  on all chrome so book-cover displays and cutouts never overlap controls.

## 7. Text & touch scale

- Font sizes fixed in `AppTextStyle` still scale with the platform text scaler
  (Flutter default); avoid hard `maxLines` that clip large text in critical rows.
- All interactive targets ≥ 48dp (action pills 52dp min).
- Use `MediaQuery.sizeOf` (not `MediaQuery.of(context).size`) in layout code.

## 8. Verification

- `test/widget_test.dart` covers both shells (desktop Material rail content +
  absence of the floating pill; narrow: pill + More sheet contents).
- Run `flutter build linux --debug` and `flutter build apk --debug` to confirm
  both platforms compile the responsive shell.