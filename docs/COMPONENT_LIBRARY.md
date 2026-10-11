# NexaDrive Component Library — `Nexa*` Primitives

> The `Nexa*` widgets in `app/lib/ui/widgets/` are the only building blocks new
> screens should use. Every component is token-driven (the `App*` tokens in
> `app/lib/core/design/`), themable through the app theme, and honours reduced
> motion via `AppMotion`.
>
> In an earlier design-system pass this library was called `OneUi*`. The rename
> is complete: `one_ui_*.dart` no longer exists and nothing references it.
> If you find a stale `OneUi`/`one_ui` reference, migrate it to the `Nexa*`
> equivalent below — do not reintroduce a second component system.
>
> The canonical export surface for consumption is `nexa_components.dart`
> (`app/lib/ui/widgets/nexa_components.dart`). The table below maps each
> component to its source file; the source is the ground truth for constructor
> parameters.

## Page scaffold

| Component | File | Contract |
|---|---|---|
| `NexaPage` | `nexa_page.dart` | Standard screen shell: viewing area (title/subtitle, header/trailing actions) above a scrollable or fixed body, sticky bottom bar support. |
| `NexaImmersivePage` | `nexa_page.dart` | Headerless immersive variant for full-screen content (viewers, fullscreen media). |
| `NexaPageBody` | `nexa_page.dart` | Horizontally padded, centered, max-width body column used by `NexaPage`. |
| `NexaPageContainer` | `nexa_grouped_list.dart` | Constrained-width page container for wider screens. |

## Layout & surface

| Component | File | Contract |
|---|---|---|
| `NexaSurface`, `NexaSurfaceLevel`, `nexaSurfaceColor` | `nexa_surface.dart` → `core/design/nexa_surfaces.dart` | The surface primitive; `NexaSurfaceLevel` picks L0–L4 colour+shadow, optional tap/long-press makes it an ink surface. Base of cards, rows and tiles. |
| `NexaGroupedList` / `NexaGroupTile` | `nexa_grouped_list.dart` / `nexa_list_tile.dart` | Grouped-settings-list composer: section header + tiles; tile is icon + title + subtitle + chevron/trailing. |
| `NexaFocusBlock` | `nexa_focus_block.dart` | Tappable card (`onTap`), vertical variant for home quick actions, horizontal for stacked lists. |
| `NexaListTile`, `NexaGroupTile` | `nexa_list_tile.dart` | Shared list row primitives. |
| `NexaAvatar`, `NexaAvatarWithStatus` | `nexa_avatar.dart` | User/entity avatars with optional presence state. |
| `NexaBadge`, `NexaStatusIndicator` | `nexa_badge.dart` | Count/badge and inline status indicators. |
| `NexaDivider`, `NexaVerticalDivider` | `nexa_divider.dart` | Horizontal / vertical hairline dividers. |
| `NexaHero` | `nexa_hero.dart` | Prominent header hero content. |

## Interaction & feedback

| Component | File | Contract |
|---|---|---|
| `NexaActionBar`, `NexaActionItem`, `NexaIconActionItem` | `nexa_action_bar.dart` | Bottom contextual action bar (`title`/`leading`, horizontally scrollable action pills, optional floating card). Powers selection modes. |
| `NexaSearchField` | `nexa_search_field.dart` | Debounced search input; owns its controller, exposes `onChanged`; theme-aware. |
| `NexaStatusPod` | `nexa_status_pod.dart` | Inline status row (icon + label + optional trailing), e.g. "N items waiting to upload". |
| `NexaEmptyState`, `NexaEmptyStateFullScreen`, `NexaRefreshableEmptyState` | `nexa_empty_state.dart` | Icons + title + hint (+ action / pull-to-refresh) for empty/offline states. |
| `NexaErrorState`, `NexaErrorStateFullScreen` | `nexa_error_state.dart` | Error presentation variant of empty state. |
| `NexaLoadingBlock`, `NexaLoadingState`, `NexaSkeletonList`, `NexaSkeletonGrid` | `nexa_loading_state.dart` | Loading blocks, spinners and skeleton placeholders. |
| `showNexaSheet`, `NexaSheetHeader`, `NexaSheetBody`, `NexaSheetAction`, `showNexaConfirmation`, `showNexaActionSheet`, `NexaConfirmationDialog` | `nexa_sheet.dart` | Bottom sheet choreography (transparent body so `ListTile`s ink correctly) + confirmation dialog. |
| `NexaFilledButton`, `NexaOutlinedButton`, `NexaTextButton`, `NexaDestructiveButton`, `NexaIconButton`, `NexaBackButton`, `NexaFilledIconButton`, `NexaSegmentedControl` | `nexa_button.dart` | The complete button family plus the segmented control. |
| `NexaChip`, `NexaSectionHeader` | `nexa_chip.dart` | Chips and section headers. |
| `NexaCircularProgress`, `NexaProgressIndicator`, `NexaSpinner` | `nexa_progress.dart` | Indeterminate progress/spinner primitives. |
| `NexaTextField` | `nexa_text_field.dart` | Themed text input field. |
| `NexaFileTile`, `NexaFileGridTile` | `nexa_file_tile.dart` | File/folder list and grid tiles. |
| `NexaBottomNav`, `NexaBottomNavItem`, `NexaBottomNavItems` | `nexa_bottom_nav.dart` | The floating bottom navigation pill (see `app/lib/ui/shell/navigation.dart`). |

## Rules

1. Screens compose these components; they never re-implement their styling.
2. All visual values come from `App*` tokens — no hard-coded colours, radii,
   durations or text styles in screens.
3. Do not create screen-specific variants. Prefer a shared component change.