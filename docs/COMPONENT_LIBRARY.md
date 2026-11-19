# Nexa component library

`app/lib/ui/widgets/nexa_components.dart` is the barrel. Every component is
built from `App*` tokens and Material 3 widgets. Do not create screen-specific
variants; extend a `Nexa*` component instead.

## Shell and layout

| Component | Material 3 basis |
| --- | --- |
| `NexaPage`, `NexaPageBody` | M3 page scaffold with tonal header surface |
| `NexaImmersivePage` | Full-bleed viewer scaffold |
| `NexaSurface` | Surface container roles, M3 shape and elevation |
| `NexaGroupedList` | Tonal grouped list with M3 overline label |
| `NexaListTile`, `NexaGroupTile` | M3 `ListTile` geometry and state layer |
| `NexaFocusBlock` | Tonal quick-action card |

## Navigation

| Component | Material 3 basis |
| --- | --- |
| `NexaBottomNav` | **Signature**: floating pill, `secondaryContainer` selection, spring travel |
| `SideNavigation` | Material 3 navigation rail for wide layouts |
| `NexaActionBar` | Contextual action bar with tonal surface |
| `NexaRevealBar` | Animated breadcrumb/selection strip |

## Actions and inputs

| Component | Material 3 basis |
| --- | --- |
| `NexaFilledButton` | `FilledButton` |
| `NexaTextButton` | `TextButton` |
| `NexaBackButton` | `IconButton` with tooltip |
| `NexaOutlinedButton`, `NexaDestructiveButton` | `OutlinedButton` / error-toned button |
| `NexaIconButton`, `NexaFilledIconButton` | M3 icon buttons |
| `NexaSegmentedControl` | `SegmentedButton` |
| `NexaTextField` | Filled `TextField` / `InputDecoration` |
| `NexaSearchField` | `SearchBar`-style tonal field |
| `NexaChip`, `NexaSectionHeader` | `FilterChip`/`InputChip`, M3 label type |
| `NexaSwitch`-style controls | `Switch`, `Checkbox`, `Radio` from `ThemeData` |

## Feedback and state

| Component | Material 3 basis |
| --- | --- |
| `NexaBadge`, `NexaStatusIndicator` | `Badge`, M3 status colors + text/icon |
| `NexaAvatar`, `NexaAvatarWithStatus` | Tonal avatar with `primaryContainer` |
| `NexaStatusPod` | Tonal status card |
| `NexaProgressIndicator`, `NexaCircularProgress`, `NexaSpinner` | M3 linear/circular indicators |
| `NexaStateSwitcher`, `NexaLoadingBlock`, `NexaSkeletonList` | M3 loading/empty/error choreography |
| `NexaEmptyState`, `NexaErrorState` | M3 illustrative empty/error layouts |
| `showNexaSheet`, `showNexaFormSheet`, `NexaConfirmationDialog` | M3 bottom sheets and dialogs |

## Content

| Component | Material 3 basis |
| --- | --- |
| `NexaHero` | M3 large card with metric/headline roles |
| `NexaFileTile`, `NexaFileGridTile` | M3 list/grid tiles with state layers |
| `NexaDivider`, `NexaVerticalDivider` | `Divider` with `outlineVariant` |
| `NexaPressable` | Compatibility press scale; prefer InkWell state layers |

## Rules

- Use `Theme.of(context).colorScheme` for every tint.
- Use `AppTextStyle` role names; no raw `TextStyle(fontSize: ...)`.
- Use `AppDimens` radii and spacing.
- Keep 48dp touch targets and semantics.
- The floating pill stays; everything else follows standard Material 3.
