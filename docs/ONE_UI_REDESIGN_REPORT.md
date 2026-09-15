# One UI Redesign Report

NexaDrive's client was rebuilt around Samsung One UI's interaction language.
This report summarizes what changed, why, and the design-token system that now
governs the Flutter app.

Related: [UI_REDESIGN_AUDIT.md](UI_REDESIGN_AUDIT.md) (pre-change audit) and
[FILE_FORMAT_SUPPORT.md](FILE_FORMAT_SUPPORT.md) (format/player scope).

## Goals

- Match One UI's calm, grouped visual style: flat surfaces with subtle
  depth, a single restrained accent, softly-rounded grouped rows.
- Keep interactions accessible: 48dp touch targets, readable contrast on both
  themes, reduced motion respected via app-level motion tokens.
- Do **not** copy Apple's design language. The apple-design skill was used only
  for interaction quality (gesture continuity, sheet behavior), never for
  Apple-specific visuals.
- Keep a single Flutter codebase for desktop + mobile (AGENTS.md requirement).

## What changed

### Architecture

Old layout was a monolithic `screens/app_shell.dart` plus a bespoke theme.
That has been retired. The new structure is token-driven:

```
lib/
  core/
    design/     app_colors, app_dimensions, app_typography, app_motion, app_theme
    models/     file_entry (FileEntry, StorageInfo, ServerStatus)
    utils/      format, file_kind (Category enum)
  services/     api, session, transfer_queue, sync_service, background_transfer_service
  ui/
    shell/      app_shell, navigation (SideNavigation, OneUiBottomNav)
    widgets/    one_ui_page, one_ui_grouped_list, one_ui_empty_state, one_ui_file_tile,
                folder_picker, upload_progress_dialog, file_details_sheet,
                file_share_sheet, download_to_view
    screens/
      home, files, photos, shared, trash, settings, sync,
      notifications, transfers, admin, login, media, viewers
  main.dart     -> materialApp, theme switching, background upload hook
```

`main.dart` now consumes the new `AppTheme`, `LoginScreen`, and `AppShell`.
No widget hardcodes a color — everything resolves through `AppColors`
(e.g. `AppColors.accentFor(brightness)`).

### Design tokens

| Token file | Contents |
|---|---|
| `app_colors.dart` | Accent (One UI blue `#0B87D0` light / `#6CC4F7` dark), surfaces, text tiers, dividers, status colors, plus `*For(brightness)` helpers such as `successFor`, `errorFor`, `accentContainerFor`. |
| `app_dimensions.dart` | Spacing scale, page margins (24/32), radii (tile 18, card 22, sheet 28, dialog 24, pill 999), touch targets, icon sizes, elevation. |
| `app_typography.dart` | Page title, display, section header, row title/subtitle, caption, micro, button, dialog title. System font only. |
| `app_motion.dart` | Motion durations/curves for the "fluid but controlled" One UI feel. |
| `app_theme.dart` | `AppTheme.light()`/`dark()` building the full `ThemeData` (color scheme, components, page transitions). |

### Screens

- **Home** — greeting, storage progress tile, quick-action tiles, offline upload
  queue banner, recent-file entry point. Quick actions navigate into Files/Photos.
- **Files** — breadcrumbed browser with list/grid toggle, long-press multi-select
  and a contextual action bar (Trash/Move/Copy/Share/Save), rename, new folder,
  sort, upload-progress dialog, details sheet, share sheet.
  Move/Copy use a server-aware `FolderPicker` (server-relative destination).
- **Photos** — grid of camera photos, tapping opens a full-bleed `PhotoViewer`
  with swipe, share/download from within.
- **Shared** — switch between "Shared with me" and "My shares", browse a shared
  folder tree in `SharedBrowseScreen`.
- **Trash** — restore or permanently delete.
- **Settings** — appearance (theme mode), sync center, transfers, notifications,
  admin (users, audit log), sign out. Theme changes rebuild the `MaterialApp`
  theme via the session's `themeMode`.
- **Sync center / Notifications / Transfers** — push full-screen pages with
  their own app bars.
- **Login** — 'Welcome to NexaDrive' title, keeps two-factor + throttling
  expectations.
- **Viewers** — in-app text reader; PDF/video/audio are download-first via
  `DownloadToViewScreen` (see FILE_FORMAT_SUPPORT.md).

### Navigation

- Desktop (>= 900dp): persistent 236dp `SideNavigation` rail with brand,
  primary destinations (Home, My files, Shared, Photos, Trash), utility items
  (Transfers, Sync center, Notifications) pinned above Settings. No bottom bar.
- Mobile/tablet (< 900dp): Material `NavigationBar` with five destinations,
  the fifth ("More") opening a bottom sheet (Scan, Transfers, Trash, Sync
  center, Notifications, Settings). Sheet content scrolls on short screens.

## Design rules applied

- **Grouped lists** — related rows live in a softly-rounded group panel
  (`OneUiGroupedList`/`OneUiGroupTile`) rather than endless floating cards.
- **One accent** — blue used sparingly: primary actions, selection, active tab.
- **Flat with depth** — shadows only where genuinely needed (modal sheets,
  dialogs); navigation surfaces use hairline dividers not elevation.
- **Calm file icons** — a single neutral document glyph tinted by a muted
  category color (`FileKind.tint`) instead of a rainbow of extension icons.
- **Motion tokens everywhere** — durations/curves come from `AppMotion`, so a
  reduced-motion system setting can be honored in one place.
- **Accessibility** — 48dp min targets (`AppDimens.touchTarget`), semantic
  labels/tooltips on icon actions, contrast-tuned text tiers per theme.

## Testing

- `flutter analyze` clean.
- `flutter test` green:
  - signed-out start shows the 'Welcome to NexaDrive' login.
  - Desktop layout shows sidebar entries and no `NavigationBar`.
  - Narrow layout shows the bottom `NavigationBar`, 'Photos', and the More sheet
    with Trash / Sync center / Notifications / Settings.
- Integration tests were updated to the new shell import path and the new
  `UploadProgressDialog.show(...)` entry point (upload flow unchanged).

## Security preservation

The redesign touched UI only. The server still owns authorization (permissions
are validated server-side; shares resolve to `read`/`write` on the backend),
passwords remain hashed (Argon2id), session tokens stay non-plaintext, and the
SQLite database still never listens on the network. Move/copy destinations are
server-relative paths chosen via `FolderPicker` and validated by the server.