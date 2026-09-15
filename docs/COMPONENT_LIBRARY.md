# NexaDrive Component Library — `OneUi*` Primitives

> These widgets in `lib/ui/widgets/` are the only building blocks a new screen
> should need. All are token-driven (design tokens in `core/design/`), themable
> via `Theme`, and honor reduced motion through `AppMotion.resolve`.

## Page scaffold

| Widget | File | Contract |
|---|---|---|
| `OneUiPage` | `one_ui_page.dart` | Screen skeleton: viewing area (title + subtitle + optional header/trailing action) above a scrollable or fixed body. `scrollable` controls single-column scrolling. |
| `OneUiBody` | `one_ui_page.dart` | Horizontally padded, centered, max-width (`contentMaxWidth` default) column for body content. |

## Layout & surface

| Widget | File | Contract |
|---|---|---|
| `OneUiSurface` | `one_ui_surface.dart` | The surface primitive. `level` picks L0/L1/L2/L3/L4 color+shadow; optional `onTap`/`onLongPress` turns it into an `InkWell`; animates visual state with a fast token duration. Use for cards, rows, tiles. |
| `OneUiGroupedList` / `OneUiGroupTile` | `one_ui_grouped_list.dart` | Grouped-settings-list composer: header + rows; tile is icon + title + subtitle + chevron/trailing. Used by Settings. |
| `OneUiFocusBlock` | `one_ui_focus_block.dart` | Tappable card (`onTap`), vertical variant for home quick actions, horizontal variant for stacked lists. |

## Interaction & feedback

| Widget | File | Contract |
|---|---|---|
| `OneUiActionBar` | `one_ui_action_bar.dart` | Bottom contextual bar: `title`/`leading`, horizontal scrolling `OneUiActionItem` pills (52dp min height), optional `floating` (pill card centered, ≤720dp). Items carry `label` for `Semantics`. Used by My Files/Photos selection mode. |
| `OneUiSearchField` | `one_ui_search_field.dart` | Debounced search input; owns its controller, exposes `onChanged`; uses the global searchBar theme (`autoFocus` parameter). |
| `OneUiStatusPod` | `one_ui_status_pod.dart` | Inline status row: icon + label + optional trailing; used for "N items waiting to upload" on Home. Milliseconds-normal duration. |
| `OneUiEmptyState` | `one_ui_empty_state.dart` | Icons + title + hint (+ action button) for empty/error/offline states. |
| `OneUiSheet` | `one_ui_sheet.dart` | `showOneUiSheet(context, builder)` bottom sheet + `OneUiSheetHeader` / `OneUiSheetBody` (Material-transparency body so ListTiles ink correctly) / `OneUiSheetAction`. Powers the More sheet, file menus, unsupported-type prompts. |
| `OneUiHero` | `one_ui_hero.dart` | Gradient hero band (storage hero on Home) with `heroTextOnGradient` color, ring accent, tap handler. `Ink` (no `borderRadius` param) used for the press overlay. |
| `OneUiPage` transitions | `app_transitions.dart` | Global `kOneUiPageTransitions` (glide + fade) built into the theme. |
| `OneUiFileTile` | `one_ui_file_tile.dart` | File/folder row: icon (folder=accent), name, subtitle (size/time), selection highlight via `accentContainerFor` + `onAccentContainerFor` + border. |

## Rules of composition

1. Screens are built from these primitives — no ad-hoc `Container` boxes with
   hard-coded colors.
2. A visual state change animated with `Animated*` must use
   `AppMotion.resolve(context, AppMotion.x)` for its `duration`.
3. Icon-only controls need a `tooltip` (and `Semantics` where there is no
   adjacent text label).
4. Tappable area ≥ 48dp (action pills enforce 52dp; icon buttons 48dp).
5. Empty/loading/error states come from `OneUiEmptyState` + the circular
   progress indicator (strokeWidth 2), never bespoke layouts.