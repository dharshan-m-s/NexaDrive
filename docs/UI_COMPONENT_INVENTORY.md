# NexaDrive UI — Component Inventory

> Exact inventory of every visual/interactive component as built in 1.1.0.
> Values come straight from source; `[EST]` marks estimates. No design changes.

---

## 1. Design-system widgets (`app/lib/ui/widgets/`)

### 1.1 OneUiPage (129 lines)
Screen skeleton: title + optional subtitle/action in a viewing area, then a body.
- Padding default: `fromLTRB(24, 0, 24, 24)`; scrollable body wrapped in
  `SingleChildScrollView` with default padding, `alignment: topLeft`.
- Viewing area padding: `LTRB(24, 24, 24, 12)`; pageTitle 28/w700/height1.2/ls −0.3
  colored `textPrimaryFor`; subtitle rowSubtitle (13) colored `textSecondaryFor`;
  4px gap; action right-aligned with 12px gap.

### 1.2 OneUiBody (in `one_ui_page.dart`)
Horizontally padded column; default padding `symmetric(horizontal: 24)`;
optional `maxWidth: 1100` centering via `ConstrainedBox` + `Center`.

### 1.3 OneUiEmptyState (155 lines) — used for empty/error/offline states
- 72×72 accent-tinted rounded tile (radius `radiusCard` = 22; icon 36, accent).
- Title `sectionHeader` (17/w600); hint `rowSubtitle` secondary, 8px above.
- Optional `FilledButton.icon` action (icon `Icons.add_rounded` 20) + `secondary` slot.
- Text is always centered; outer padding 32 all around.

### 1.4 OneUiProgressTile (in `one_ui_empty_state.dart`)
Title row (`sectionHeader` + right-aligned `caption` label), then a pill
`LinearProgressIndicator` (minHeight 6, radiusPill, accent value, surfaceAlt track),
then a `micro` detail line. Padding `LTRB(16,16,16,20)`.

### 1.5 OneUiGroupedList (247 lines) — the defining One UI list rhythm
- Optional dashed-header row: label `.toUpperCase()`, `listHeader` (13/w600/ls 0.4
  → uprated to 0.8 here), `textTertiary`, padding `LTRB(4,8,4,8)`.
- Panel body: `Container` colored `surfaceFor(brightness)`, radius `radiusCard` (22),
  `clipBehavior: antiAlias`, inner vertical padding 4 (default).
- Dividers between children: 1px `dividerFor`, height 1, inset `left = 16` normally,
  or `16 + 48 + 12 = 76` when the preceding child is a `OneUiGroupTile` with
  `iconDividerInset` (skips over the leading icon tile).
- Optional footer 12px below the panel; final 4px bottom spacer.
- Header text uses font `listHeader` when `withDividers=true` grouping style.

### 1.6 OneUiGroupTile (in `one_ui_grouped_list.dart`)
One row: optional 48×48 icon tile (radius 12, accent-tinted @ 12% light / 18% dark),
title `rowTitle` (16/w500, w600 when selected), optional `caption` subtitle secondary,
trailing = chevron (`chevron_right_rounded`, 24, textTertiary) or custom.
- `minTileHeight: 60`; `selectedTileColor: accent @ 10%`; disabled state greyed to
  `textTertiary`. `actionKey` prop exists for tests.

### 1.7 OneUiInfoRow (in `one_ui_grouped_list.dart`)
label (`caption` secondary) left, value (`rowSubtitle` w500 primary) right;
padding `horizontal:16, vertical:12`; optional leading widget 12px gap.

### 1.8 OneUiFileTile (241 lines) — file browser list row (used by My files)
- Leading: 48×48 image thumb placeholder (surfaceAlt fill, image_rounded icon) for
  images, else `_FileIconTile` (category icon in tileFill, radius 12, icon 24 tinted).
- Title rowTitle primary, w600 if selected; subtitle = custom or default
  (`'Folder'` / `Format.bytes(size)` / `'File'`), caption style, secondary color.
- Trailing: `chevron_right_rounded` for folders (if `showChevron`) or custom widget.
- Selection mode: leading replaced by 22px check/radio (`check_circle_rounded` /
  `radio_button_unchecked_rounded`, accent / textTertiary); row border accent 1.5 when
  selected; selectedTile tint accent @ 10%.
- `onLongPress` opens selection.

### 1.9 OneUiFileGridTile (in `one_ui_file_tile.dart`) — grid tile
- White/black surface rounded 18; padding 12; icon tile 48 top-left, selection badge
  20px top-right in selection mode; name max 2 lines (`rowSubtitle` w500 primary);
  size `micro` secondary; selected border accent 1.8 (transparent 1.8 otherwise).

### 1.10 FolderPicker / FolderPickerBody (268 lines)
`FolderPicker.pick()` shows a modal bottom sheet (`isScrollControlled: true`);
`FolderPickerBody` lists only folders for the current path.
- Header: back/`arrow_upward_rounded` when deeper than root (or `folder_outlined`),
  path as title (`sectionHeader`), check button + disabled while loading, all 24px gutters.
- Helper line "Moving here keeps your files on this server path." (caption, secondary).
- Body list height 180 (loading spinner / empty / error); rows = folder_rounded accent icon +
  name + chevron, tap navigates deeper.
- Bottom: full-width 48px `FilledButton` "Move to `<title>`" / “Use this folder”
  (`check_rounded` in header also confirms). Returns server path "" for My files root.

### 1.11 UploadProgressDialog (316 lines)
Modal (non-dismissible) dialog while uploading; per-file rows + summary.
- Created via `UploadProgressDialog.show` → enqueues every picked file in the
  `TransferQueue`, then `showDialog` with `barrierDismissible:false`.
- Polls queue every 700 ms; status icon/title cross-fades (AnimatedSwitcher 180 ms):
  spinner+"Uploading…" → `check_circle_rounded` (success)+"Upload complete" → error icon+
  "Upload finished with issues".
- Summary: "N files uploaded to <folder>", pill progress bar (minHeight 8), "X of Y".
- Row: 20px leading icon — check (success) / error / scheduler "Waiting…" /
  cloud_upload "X / Y" (accent, with 4px mini progress bar); retry `refresh_rounded`
  button for failed rows; text `caption` w600.
- Back press: `PopScope(canPop: !isActive)` → cancels (+ removes non-completed uploads).
- Actions: `Cancel` (TextButton) while active, else `Done`/`Close` (FilledButton).
- Content width fixed at 380, list `shrinkWrap` inside `Flexible`.

### 1.12 DownloadToViewScreen (149 lines) — base for PDF/Video/Audio screens
Full-screen Scaffold + AppBar; centered 96×96 accent-tinted tile (radius 22; icon 44),
file name (`sectionHeader` w600), subtitle, "size · date" caption line, full-width
52px `FilledButton.icon` "Download" → `FilePicker.saveFile`, `_busy` spinner
(18px white in icon slot, label "Downloading…"), then "Saved to <path>"
`caption` success text. Errors → snackbar.

---

## 2. Navigation (shell)

### 2.1 SideNavigation (236 lines total file)
Desktop sidebar, exact width **236**; surface fill; brand row padding
`LTRB(20,24,20,20)`: 38×38 accent `cloud_rounded` (icon 22, color = page surface) +
"NexaDrive" (`sectionHeader` primary). ListView horizontal padding 12 containing
`SideNavItem`: Home / My files / Shared / Photos / Trash. Then 12px gap, `_UtilityNavItem`:
Transfers (`cloud_upload_outlined`), Sync center (`sync_rounded`), Notifications
(`notifications_outlined`). Settings pinned bottom (`settings_outlined`), padding
`LTRB(12,8,12,16)`.

### 2.2 SideNavItem / _UtilityNavItem
`ListTile`, `visualDensity: compact`, `minLeadingWidth: 28`, contentPadding
`symmetric(horizontal: 12)`; leading 24 icon = accent when selected (else textSecondary);
title rowTitle = accent + w600 when selected (else textPrimary/w500);
selectedTileColor accent @ 10%; shape radius 18. Utility items never selected-styled.

### 2.3 OneUiBottomNav + More sheet
- Material `NavigationBar`: `labelBehavior: alwaysShow`; height =
  `kBottomNavigationBarHeight + 4` (80 + 4 = **84** on most platforms [EST typography
  variance]); background `surfaceElevatedFor`; pill indicator = accentContainer; selected
  label 11/w600/accent, unselected 11/w500/textSecondary; icons 24 (filled rounded when
  selected, outlined otherwise).
- Destinations + labels: Home / Files / Shared / Photos / **More** (`more_horiz_rounded`).
- More sheet: title "More" (`sectionHeader`), 6 `_SheetTile` rows height 60 —
  Scan document (`camera_alt_outlined`, **no-op → only pops sheet**), Transfers,
  Trash (jumps to page 4), Sync center, Notifications, Settings (page 5).

### 2.4 _SheetTile (app_shell.dart)
`InkWell` radius 12, height 60, padding horizontal 8; accent 24px icon + 16px gap +
`rowTitle` primary label.

---

## 3. Inline components (per-screen)

| Component | Where | Spec |
|-----------|-------|------|
| `_SheetAction` | files_screen sheet menu | height 52 row, 24 icon + 16 gap + `rowTitle`; `destructive` → errorFor color, else textPrimary |
| `_ViewArea` | files_screen header | title swaps to "N items"; up / list/grid toggle / new-folder / upload `IconButton`s (tooltips); selecting: close (exit) |
| `_Breadcrumb` | files_screen | 40px horizontal ListView; crumbs caption 12, last = primary/w600, ancestors = accent/w500; 16px chevron separators; starts "My files" |
| `_SelectionBar` | files_screen selection | elevated surface, top border 0.5 divider; 5 `_BarAction`s (Trash/Move/Copy/Share/Save) + close IconButton; `spaceEvenly` |
| `_BarAction` | files_screen | InkWell → 24px accent icon over `micro` label (secondary), 6px padding |
| `_IconTile` | grouped_list | 48×48 radius-12 tile, tinted bg, 24px icon |
| `_InfoRow` | file_details_sheet | label (caption secondary, width 90) + value (`rowTitle` primary), vertical 6px padding |
| `_ErrorBanner` | login | error color @10% fill, radius 12, error icon 20 + caption primary text |
| `_QuickActionTile` | home | surface tile radius 18, padding 16; 40×40 accent@12% icon tile (radius 12, icon 22), 12px, `rowTitle` w600 label |
| `_StorageTile` | home | surface radius 22, padding 20; 40×40 icon tile accent @12% (`data_usage_rounded`), title + used bytes w600; animated progress (300 ms standard curve) minHeight 6; caption detail |
| `_PendingTile` | home | warning color @10/16% fill radius 22, padding 16, cloud_upload icon, "N items waiting to upload" rowTitle w600 + "Your files are safe." caption warning; tap → Transfers |
| `_Section` / `_TransferRow` | transfers | Section = listHeader title (ls 0.6) + micro detail, tertiary. Row = surface tile radius 18, margin bottom 8; 22px status (spinner/schedule/check/error), name + caption status, 4px progress bar when uploading; trailing retry/pause/remove IconButtons (tooltips) |
| Share rows | shared_screen | `OneUiGroupTile`, folders use `inbox_rounded`, share rows `link_rounded` + icon tint; "My shares" rows show delete (error) trailing, no tap |
| Notification row | notifications | tile radius 18; unread = accentContainer fill, read = surface; icon 24 (category mapped); title rowTitle (w600 unread / w400 read); "message · reltime" caption; unread trailing "mark read" IconButton |
| Device row | sync_center | surface tile radius 18, listTile, title w500, subtitle 12px, error-colored revoke IconButton |
| Admin user row | admin_users | surface tile radius 18; CircleAvatar accent@14% with initial (`buttonSmall` accent); title w600; subtitle 12px "@user · Role · X.XX / Y GB · Disabled"; trailing lock toggle (disabled → success color, enabled → error). Disabled row disabled. |
| Audit row | audit_log | plain `ListTile`, avatar radius 16 accent@14% initial, title `rowTitle` "action path", subtitle caption secondary "username · date"; divider 1px between, item padding minVertical 12 |
| Trash row | trash | surface tile radius 18 + ListTile; folder/file icon 24 (folder accent); "Deleted <relTime>" subtitle; restore + delete-forever IconButtons (accent / error) |
| Shared-browse row | shared_browse_screen | ROW is a bare `ListTile` (radius 18); leading 48 accent@12/18% tile with folder/file icon; title name (w500); size 12px; trailing chevron (folder) or download IconButton (file) |
| Folder-picker row | folder_picker | InkWell radius 12, horizontal 4, vertical 10 padding; folder_rounded accent 24, name rowTitle, chevron secondary |

---

## 4. Global theme components (`app_theme.dart`)

| Component | Key styling |
|-----------|-------------|
| AppBar | transparent bg, fg onSurface, elevation 0 (scrolledUnder 1), centerTitle **false**, title 18/w600/onSurface, toolbarHeight **56** |
| Card | surface color, no tint/elevation/margin, radius `radiusTile` 18 |
| ListTile (global) | leading width 48, padding `h16 v4`, title onSurface, subtitle height 1.2 secondary, radius 18 |
| FilledButton | accent bg; fg white (light) / `textOnPrimaryDark #001D33` (dark); disabled bg accent@40%, fg white@80%; min size 64×48; padding `h24 v12`; radius **pill 999**; text **16/w600/ls 0.1** |
| OutlinedButton | accent fg; min 64×48; padding `h24 v12`; border accent 1.2; radius pill; text `button` |
| TextButton | accent fg; radius pill; text 14/w600 |
| InputDecoration | **filled**, fill surfaceAlt, `isDense`, content padding `h16 v16`; radius **12 (radiusInner)**; borderless; enabled border none; focused border accent 2; error border error 1.5; hint tertiary, label secondary, floating label accent/w600 |
| Dialog | surface, no tint, elevation 16, radius **24**, title `dialogTitle` (20/w600) onSurface, content rowSubtitle secondary |
| BottomSheet | surface, no tint, elevation 16, **top radius 28** (sides square), `showDragHandle: true`, handle color divider, 36×4 |
| SnackBar | floating, radius 12, dark bg `#1A1C1E` (light) / `#2D2E30` (dark), content 14 white, action accentDark, inset `h16 v12` |
| Divider | dividerFor 1px, space 1 |
| NavigationBar | see §2.3 |
| Switch | track accent when selected / `divider@60%` otherwise; outline transparent; thumb always white |
| SegmentedButton | selected segment = accentContainer bg + onAccentContainer fg; unselected transparent + textSecondary; global side divider 1; radius **pill**; text 13 |
| ProgressIndicator | determin color = accent; track surfaceAlt (linear + circular) |
| Scrollbar | thumb textTertiary @50%, radius 4 |
| PopupMenu | surface, no tint, radius 12, text rowTitle 14 onSurface |
| Tooltip | dark bg (#1A1C1E / #2D2E30), radius 8, 13px white, wait 400 ms |
| Splash | `InkSparkle.splashFactory` |
| Page transitions | Android/Linux/Windows = `FadeForwardsPageTransitionsBuilder`; iOS/macOS = `ZoomPageTransitionsBuilder` |
| TextTheme | displayLarge 32/w700, displayMedium 26/w600, displaySmall 34/w700 (display), headlineLarge 28 (pageTitle), headlineMedium 17 (sectionHeader), titleLarge 20/w600, titleMedium = rowTitle (16/w500), bodyLarge 16/w400/h1.4, bodyMedium = rowSubtitle 13, bodySmall = caption 12, labelLarge = button, labelMedium = 14 buttonSmall, labelSmall = micro 11; body/display colors onSurface |

---

## 5. File-category iconography (FileKind)

| Category | Icon | Tint | Tile fill (light / dark) | Extensions |
|----------|------|------|--------------------------|------------|
| folder | `folder_rounded` | #0B87D0 | 12% / 20% of tint | type folder |
| image | `image_rounded` | #B25E00 (amber) | … | jpg jpeg png gif webp bmp heic heif tif tiff |
| video | `movie_rounded` | #8E24AA (purple) | … | mp4 mov mkv webm avi m4v 3gp |
| audio | `music_note_rounded` | #00897B (teal) | … | mp3 aac m4a wav flac ogg opus aiff wma |
| pdf | `picture_as_pdf_rounded` | #C62828 (error-red) | … | pdf |
| document | `description_rounded` | #5B5F66 (gray) | … | doc docx odt rtf pages + xls xlsx ods csv + ppt pptx odp key |
| archive | `folder_zip_rounded` | #6D4C41 (brown) | … | zip tar gz tgz 7z rar bz2 xz zst |
| text | `article_rounded` | #455A64 (slate) | … | txt md markdown log json xml yaml yml conf ini cfg toml csv html htm css js ts dart rs py rb go java c h cpp hpp sh sql nfo |
| unknown | `insert_drive_file_rounded` | #8A9099 | … | everything else |

Note the tint set is **intentionally invariant across light/dark**; only the tile-fill
translucency changes (dark 20% vs light 12%). `isPreviewable` = image/text/pdf;
`isPlayable` = video/audio.

---

## 6. Reusable-but-private surface types inventory

- `showModalBottomSheet` is used for: More sheet, file menu (files_screen §uni), file
  details, share sheet, unsupported format, folder picker — all top-radius 28, drag
  handle, gutters `pageMargin`.
- `AlertDialog` used for: New folder, Rename, Move to Trash, Remove share, Sign out,
  Connected to, About (via `showAboutDialog`), Appearance (SimpleDialog), Delete
  forever, Remove upload, New user — all radius 24.
- `showAboutDialog`: material names "NexaDrive" v1.1.0 with legalese tagline.
- `SnackBar` (floating) used for: error surfaces, "Download started…", "Downloaded",
  "Saved to …", "Server address copied", "Session expired", sync summaries, server-restart
  toast, "Upload failed to start".
- Contextual `OneUiEmptyState` used on: files (error), shared, photos, trash, transfers,
  notifications, users, audit, shared_browse, folder picker. It doubles as the initial
  empty state and the offline/error state consistent with One UI's "say what happened,
  say what to do" tone.