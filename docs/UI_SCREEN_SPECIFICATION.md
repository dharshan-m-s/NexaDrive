# NexaDrive UI — Screen Specification

> Line-accurate spec of every screen as built today (1.1.0). `[EST]` = estimate.
> Default font: system (Roboto/Samsung One on Android Galaxy, Noto Sans on Linux).

Legend: primary = textPrimary, secondary = textSecondary, tertiary = textTertiary,
accent = FileKind/AppColors accent-for-brightness; menu/sheet padding LTRB = `(24,0,24,24)`
unless noted; page gutter = 24.

---

## 0. Login screen (`login_screen.dart`)

Layout: centered `SingleChildScrollView` (maxWidth 440, vertical padding 32) on
`scaffoldBackgroundColor`, page gutter 24 (compact <700) / 32 (wider).
1. Brand: 62×62 accent tile radius 22, `cloud_rounded` 32 (white on light /
   `textOnPrimaryDark` on dark). 28px below.
2. Title "Welcome to NexaDrive" — `display` 34/w700/ls −0.5, primary. 6px.
3. Tagline "Your files. Your server. Your private cloud." — rowSubtitle secondary. 32px.
4. TextFields (filled surfaceAlt, radius 12, prefix icons, content h16 v16):
   - Server address: `keyboardType url`, autofill `url`; hint differs by width
     (compact: "https://server.example.com";
     wide: "https://server.example.com or http://<lan-ip>:8080").
   - Username: `next`, autofill `username`, prefix `person_outline_rounded`.   - Password: obscure (toggle suffix `visibility/visibility_off`, tooltip "Show/Hide
     password"), `done` submits, autofill `password`, prefix `lock_outline_rounded`.
   12px gaps.
5. Error banner (on failure): error @10% fill radius 12, `error_outline_rounded` 20,
   caption text primary. Error text friendly-mapped (connect/timeout →
   "Can't reach that server…"; 401/invalid → "Username or password is incorrect.").
6. Sign in button: full-width 56px FilledButton; loading → inside 22px spinner (stroke 2),
   no label.
7. Footnote (tertiary caption, centered): "Private cloud on hardware you control. Enter
   the address of your NexaDrive server."
Prefill: server address and/or username from last session (server wins).
On success: `BackgroundTransferService.schedule()`, `pushReplacement` → AppShell.

---

## 1. AppShell (`app_shell.dart`) — chrome, not a page

- Desktop (`width ≥ 900`): Row = SideNavigation (236) + `_PageHost` (AnimatedSwitcher,
  200 ms easeOut/easeIn, SafeArea). Mobile: `_PageHost` Stack + `OneUiBottomNav`.
- Background page cross-fade; nav taps set `index` 0–5.
- AppBar-less pages (Home/Files/Shared/Photos/Trash/Settings all have their own headers).
- Lifecycle timers as in REVERSE_ENGINEERING §3.2.

---

## 2. Home (`home_screen.dart`)

Header: "Good morning/afternoon/evening, <name>" (displayName or username or "there");
subtitle = "<n> used · <m> files" or "Your private cloud" while storage null.
Body (scrollable, gutter 24, content max 1100):
1. Storage tile (radius 22): 40px icon tile accent@12% (`data_usage_rounded`), "Storage"
   sectionHeader, used bytes right (rowSubtitle w600); animated pill progress
   (300 ms; minHeight 6; accent on surfaceAlt track); caption detail
   ("<free> free of <quota>" | "Storage quota is not set on this server").
   Loading state = 96px surface tile with centered spinner.
2. "Quick actions" sectionHeader + 12px + grid of 4 tiles (2 cols <420–800 width,
   4 cols ≥800): Upload / New folder / Photo library / Files — `_QuickActionTile`
   (radius 18, padding 16, 40px accent tile, w600 label). Wrapped 12px spacing.      - Upload → page 1 (Files); New folder → page 1; Photo library → page 3; Files → page 1.
3. If pending queue > 0: `_PendingTile` (warning @10/16%, radius 22, cloud_upload icon,
   "N items waiting to upload" + "Your files are safe.") → tap opens Transfers screen.
   24px gaps between blocks.
4. "Recent": if file-count > 0 shows OneUiEmptyState variant "Your files are ready /
   Browse everything stored in your private cloud." + "Open My files" button; else a
   surface radius-22 card: `cloud_done_outlined` 40 accent, "Nothing here yet", caption
   "Upload your first files to get started."
Refresh: no pull-to-refresh on Home (loads once; queue status static until rebuild, `[EST]`).

---

## 3. My files (`files_screen.dart`)

Header (pageMargin, `LTRB(24,20,24,8)`): title = crumb last-segment (`'My files'` at
root) (pageTitle primary); selecting → "N items" in accent. Subtitle (caption secondary,
1-line ellipsis): browse path when deep / "Browse your private cloud" at root; in selection
mode replaced by "Back to My files" TextButton.icon. Right controls (IconButtons w/ tooltips):
- Not selecting: list/grid toggle (`view_list_outlined`/`grid_view_outlined` at top),
  new folder (`create_new_folder_outlined`), upload (`upload_outlined`); plus
  `arrow_upward_rounded` ("Up to My files") when deep.
- Selecting: close (`close_rounded`, "Cancel selection").
Breadcrumb strip (deep only, height 40, horizontal list, gutter 24): "My files" + segments,
16px chevrons, ancestor = accent w500, current = primary w600; tapping non-final jumps.
Body:
- Loading: centered spinner stroke 2.
- Error: OneUiEmptyState `cloud_off_rounded` "Can't reach NexaDrive" + "Retry".
- Empty: pull-to-refresh + empty ListView (40px spacer).
- List (default): gutter 24 (top 4 bottom 24), rows = OneUiFileTile (radius 18, subtle
  separators none between rows — rows float with no divider). Sorting: folders first, then
  files, both A→Z case-insensitive (display name). Row long-press → selection.
  Row trailing (not selecting): `more_vert_rounded` IconButton ("More options") → sheet.
- Grid: `GridView` maxCrossAxisExtent 170, spacing 12, aspect 0.95, OneUiFileGridTile.
Selection contextual bar (bottom, `surfaceElevated`, top border 0.5 divider, safe area):
Trash / Move / Copy / Share / Save (`delete_outline`, `drive_file_move`, `copy_rounded`,
`share_outlined`, `download_outlined`; accent 24 icons + micro labels) + close (accent).
File-row menu sheet (trigger: trailing ⋮): header = file name sectionHeader; rows
Details (`info_outline_rounded`) → details sheet; Share → share sheet; Download (files
only) → save-file picker; Move (folders only) → folder picker; Rename → dialog;
Move to Trash (destructive) → confirm.
Unsupported sheet (tapping a non-previewable file): name header, copy
"'Documents, can't be opened inside NexaDrive. Download it and open it with another app.'"
then full-width FilledButton.icon Download.
File open behavior matrix — image → PhotoViewer (all images in current folder as the
paged set); video/audio/pdf → download-to-view; text → TextViewerScreen.

---

## 4. Shared (`shared_screen.dart`)

Header: title "Shared with me" / "My shares"; subtitle "Files and folders shared with you"
/ "Links and access you have granted".
Header action: `SegmentedButton<bool>` With me / Mine (pill; selected = accentContainer;
`showSelectedIcon: false`).
Body:
- Loading / error (`cloud_off_rounded` "Can't load shares" + Retry) / empty
  (`inbox_rounded` "Nothing shared with you" | `link_rounded` "No shares yet" + hints).
- List (OneUiGroupTile rows):
  - With me: `inbox_rounded` tile, title = leaf name, subtitle "Shared by <owner>"; tap →
    load share items → push SharedBrowseScreen.
  - Mine: `link_rounded` tile, subtitle "Read only" / "Read & write"; trailing delete
    (error) → Remove share dialog; tap disabled.
Pull-to-refresh.

---

## 5. Shared browse (`shared_browse_screen.dart`)

Pushed Scaffold; AppBar (56, transparent-on-content): title = share display name at root /
current segment deep; action `arrow_upward_rounded` (accent) when not root (one level up).
Body: error → OneUiEmptyState "Can't load this folder" + Retry; empty → "This folder is
empty"; list (gutter 24) of bare ListTiles (radius 18, title w500):
- Folder row: accent folder icon in accent-tinted 48-tile, chevron trailing → navigate in.
- File row: neutral icon tile, size (12px secondary), trailing download IconButton;
  tap = download run (save dialog + "Download started…" → "Downloaded").
Note: shared browsing does NOT preview images or text (every non-folder item downloads);
permission writes not exposed in UI.

---

## 6. Photos (`photos_screen.dart`)

Header: "Photos", subtitle "All your photos in one place", action `refresh_rounded` (accent).
Body: loading / error (`cloud_off_rounded` + Retry) / empty (`photo_library_outlined`
"No photos yet", hint, Refresh action). Grid: `SliverGridDelegateWithMaxCrossAxisExtent`
190, gap 4, tiles radius 12 (`ClipRRect`); each tile 1:1 from server 512px thumbnail
(page `max` param) shown via `Image.memory` cover `gaplessPlayback`, placeholder =
surfaceAlt + spinner; tap → PhotoViewer at index. Pull-to-refresh. Thumbnails prefetched
first 40 post-load, disk read synchronous at build (Photos-specific).

---

## 7. Photo viewer (`photo_viewer.dart`)

Fullscreen `Scaffold`, background #000000, `extendBodyBehindAppBar`; AppBar transparent,
white fg, title "N of M" (current+1 … total).
PageView of full original images (in-memory cache per path, prefetched ±1 page); while
loading a page: centered white54 spinner; loaded: `InteractiveViewer` maxScale 5 with
contain-fit image. Bottom translucent bar: `BackdropFilter` blur sigma 12 over
white @ 6% fill, `SpaceEvenly` row of white IconButtons — Download (`download_outlined`),
Save to My files (`save_alt_rounded`) both running the same save-to-picker handler, Share
(`share_outlined`) → FileShareSheet for that photo. No count badge change on swipe is
animated; no pinch-to-zoom indicator; no double-tap zoom built in (InteractiveViewer 5×).

---

## 8. Trash (`trash_screen.dart`)

Header: "Trash" / "Deleted items are kept for 30 days".
Body: loading / empty (`delete_outline_rounded` "Trash is empty") / pull-to-refresh list of
surface tiles (radius 18): folder/file icon (folder accent), name w500,
"Deleted <relTime>" subtitle; trailing Restore (`restore_rounded` accent) and Delete
forever (`delete_forever_outlined` error) IconButtons → dialogs:
- Restore: direct API call, no confirm.
- Delete forever: AlertDialog "Delete forever?" / "This cannot be undone. The file will be
  permanently removed." / Cancel + Delete forever (FilledButton).

---

## 9. Settings (`settings_screen.dart`)

Header: "Settings" / username.
Body (scrollable, gutter 24, centered content):
1. Profile: 68px circle accent @12/18% with initial (`display` 30px accent, A–Z), 12px,
   name sectionHeader w600, 4px, "Administrator" / username caption secondary.
2. GroupedList "GENERAL": Appearance (subtitle = Light/Dark/System default) → SimpleDialog
   with 3 options (icon + "System"/"Light"/"Dark"); Sync center → screen; Transfers →
   screen; Notifications → screen.
3. GroupedList "SERVER": Connected to (subtitle = server URL) → dialog with URL (max 4
   lines), "Copy address" (clipboard + snackbar) / "Done".
4. Admin group (only if `session.role == 'admin'`): Users → AdminUsersScreen; Audit log →
   AuditLogScreen.
5. "ABOUT": About NexaDrive → `showAboutDialog` (NexaDrive 1.1.0, tagline legalese).
6. Sign out: 52px OutlinedButton.icon (`logout_rounded`); confirm dialog "Sign out" →
   "Are you sure you want to sign out?" Cancel + Sign out; on confirm → api.logout +
   navigate back to Login (pushAndRemoveUntil). Test key `signout_confirm`.

---

## 10. Transfers (`transfers_screen.dart`)

Pushed Scaffold, AppBar "Transfers". Actions: Process queue (`play_arrow_rounded` /
`hourglass_top_rounded` while running) + Clear completed (`delete_sweep_outlined`,
only when any completed). Body: loading / empty (`cloud_upload_outlined` "No transfers",
hint). Grouped sections in order: "UPLOADING" (title + "X of Y"), "NEEDS ATTENTION"
("N failed"), "COMPLETED" ("N done") — headers listHeader tertiary + micro detail.
Rows `_TransferRow` (surface radius 18): leading status (spinner when uploading /
`schedule_rounded` waiting / `error_outline_rounded` failed / `check_circle_outline`
completed); name + status caption (failed shows error string in statusColor); 4px
progress bar when uploading; trailing: failed = retry + remove (IconButtons), uploading =
pause, completed = remove. Row tap: on failed = reset+process; on queued = pause; remove
always via trailing ×. Remove dialog "Remove upload" / 'Remove "name" from the queue?'.
Process queue runs `TransferQueue.process`.

---

## 11. Sync center (`sync_center_screen.dart`)

Pushed Scaffold, AppBar "Sync center".
Body (ListView gutter 24):
1. Selected folder card (radius 22): "Selected folder" sectionHeader w600, path caption
   secondary (or "No folder selected"), Choose (OutlinedButton.icon, pick local folder) +
   Unlink when set.
2. "Sync now" FilledButton.icon 52px (spinner while syncing; caption progress below,
   e.g. "Downloading 3 of 12" — string from SyncManager progress).
3. Result card (after a run): Uploaded / Downloaded / Deleted / Conflicts (error-colored if
   >0) / Errors (error-colored if >0) — label rowSubtitle secondary, count rowTitle w700.
4. Conflicts card (when >0): warning @14% fill, `warning_amber_rounded`, "N conflicted
   files to resolve".
5. "LINKED DEVICES" listHeader + device rows (surface radius 18, `devices_rounded` leading,
   name w500, "Last seen <relTime>" 12px, revoke `link_off_rounded` error → revoke).
Empty: "No devices linked yet. Run sync from another device to link it." caption.
Sync is desktop-only in the UI path (auto-sync skipped on Android, but the screen still
reachable on mobile; `pickAndSetFolder` uses native folder picker `[EST]`).

---

## 12. Notifications (`notifications_screen.dart`)

Pushed Scaffold, AppBar "Notifications" + action Mark all read (`done_all_rounded`).
Filter row (gutter 24): "Filter" text + SegmentedButton All / Unread.
Body: loading / empty hammer (`notifications_none_rounded` "No notifications") / list of
tiles (radius 18): unread = accentContainer fill + icon accent + title w600; read =
surface fill + icon tertiary + title w400; subtitle "message · reltime" caption; trailing
Mark read (`mark_email_read_outlined` accent) for unread. Icon map: backup_completed →
`backup_rounded`; backup_restore_ready → `restore_rounded`; backup_failed /
backup_restore_failed → `error_outline_rounded`; else `notifications_none_rounded`.

---

## 13. Admin Users (`admin_users_screen.dart`)

Pushed Scaffold, AppBar "Users" + action New user (`person_add_alt_rounded`).
Rows: CircleAvatar accent@14% initial; title display_name w600; subtitle 12px
"@username · Role · X.XX / Y GB · Disabled" (quota omitted if none); trailing lock
toggle (`lock_outline` error when enabled → disable action; `lock_open_rounded` success
when disabled → re-enable). Disabled rows render `enabled:false`.
New-user dialog: Username, Display name, Password (obscure; ≥8 chars enforced client-side
with snackbar), Role DropdownButtonFormField (User/Admin), Quota GB optional →
`Create`; `Cancel`. All fields `InputDecoration` label style per theme.

---

## 14. Audit log (`audit_log_screen.dart`)

Pushed Scaffold, AppBar "Audit log" + Refresh (`refresh_rounded`).
Rows (bare ListTile, minVertical 12): CircleAvatar r16 accent@14% initial; title
"<action> <path>" (rowTitle, 1-line); subtitle "username · yyyy-MM-dd HH:mm"
(caption secondary). Dividers 1px between rows. Empty state `receipt_long_outlined`.

---

## 15. Text viewer (`text_viewer_screen.dart`)

Pushed Scaffold, AppBar = file name. Body: loading / error (rowSubtitle error) / white
(or surfaceDark) surface with `SingleChildScrollView`, padding 24, `SelectableText`
monospace 13 / height 1.5 / primary — content is utf8-allowMalformed with U+FFFD stripped.
No line numbers, no wrap toggle, no search.

## 16–18. PDF / Video / Audio (`pdf_player`, `video_player`, `audio_player` screens)
All subclass `DownloadToViewScreen`: AppBar + centered 96px icon tile
(`picture_as_pdf_rounded` / `movie_rounded` / `music_note_rounded`), name, subtitle
("PDF document – download to view" etc. `[EST]` wording from per-screen subtitle), size · date,
Download button. **No in-app rendering, no seek, no playback controls — download-first.**

---

## 19. Dialogs & sheets — master list

| MrSurface | Trigger | Title | Actions (left→right) | Notes |
|-----------|---------|-------|----------------------|-------|
| New folder | Files ⊞ | New folder | Cancel / Create | autofocus, submit-on-enter |
| Rename | row ▾ → Rename | Rename | Cancel / Rename | prefilled name, select-all not forced |
| Move to Trash | row ▾ / selection | Move to Trash | Cancel / Trash | "N items" plural |
| Delete forever | Trash row | Delete forever? | Cancel / Delete forever | destructive copy |
| Remove share | Mine share ▾→ × | Remove share | Cancel / Remove | |
| Remove upload | Transfers × | Remove upload | Cancel / Remove | names the file |
| Sign out | Settings | Sign out | Cancel / Sign out | Key `signout_confirm` |
| Connected to | Settings row | Connected to | Copy address / Done | URL 4-line max |
| Appearance | Settings row | Appearance | System / Light / Dark | SimpleDialog |
| New user | Admin ➕ | New user | Cancel / Create | StatefulBuilder dialog |
| About | Settings row | About | (variant) | showAboutDialog |
| Share sheet | Share | Share "file" / Share N items | Create link (+Close) → after: Remove link(+Close) | Segmented view/download |
| Details sheet | ▾ → Details | (icon) file name | — | no actions, info only |
| Unsupported | tap file | name | Download | fixed copy |
| File menu | row ⋮ | name | Details/Share/Download/Move/Rename/Trash | destructive last |
| More sheet | nav More | More | Scan/Transfers/Trash/Sync/Notifs/Settings | Scan = no-op |
| Folder picker | Move/Copy | Move to / Copy to | back+check header, bottom Move-to button | |
| Upload progress | Upload | live status | Cancel or Done/Close | non-dismissible |
| Pending tile | Home (queue>0) | → Transfers push | — | not a sheet |

All dialogs: radius 24, title 20/w600, actions pill-styled (TextButton/FilledButton).
All sheets: top radius 28, drag handle 36×4 divider-colored, gutter 24.

---

## 20. Cross-screen consistency facts

- Every list row is either a standalone surface tile (radius 18) with 2px gap or a
  OneUiGroupedList panel (radius 22) with instance dividers — never a hard-edged row.
- Header gutter = 24, header bottom padding 8–12, list top 4–12, list bottom 24.
- All progress bars are pill (radiusPill), heights 4 / 6 / 8, accent value on surfaceAlt.
- Empty/error/offline reuse the same three-part state with "-friendly" copy.
- Snackbars: floating, radius 12, inset 16×12, dark bg — consistent app-wide.