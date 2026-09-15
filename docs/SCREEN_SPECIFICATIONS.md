# NexaDrive Screen Specifications (Redesigned)

> Per-screen One UI destination spec for the redesigned client. Each entry names
> the owning file, its structure, and the design rules that apply. All file paths
> under `app/lib/`.

## Shell & navigation

### `ui/shell/app_shell.dart` + `ui/shell/navigation.dart`
- **Desktop (≥900px):** 236dp sidebar rail — brand mark + primary destinations
  (`SideNavItem`, tokenized `accentContainerFor` fill + `onAccentContainerFor`
  content when selected), utility destinations pinned (Transfers / Sync center /
  Notifications), Settings pinned bottom. Content centered and capped at
  `contentMaxWidth = 1100`.
- **Mobile (<900px):** `OneUiBottomNav` (five destinations; fifth = More sheet).
  Selecting More opens `OneUiSheet` with Scan document / Transfers / Trash /
  Sync center / Notifications / Settings.
- Queue lifecycle: 30s timer + app resume + server-instance check feed
  `TransferQueue.process`; session-expiry cancels background transfers and
  returns to Login. Desktop auto-sync runs on start/resume.
- Scan document pushes `ScannerScreen` (real camera), not a tab swap.

## Home (`ui/screens/home/home_screen.dart`)
- `OneUiHero` storage hero (gradient family per brightness, `heroTextOnGradient`
  text, metric + storage bar, ring accent).
- `_QuickActionsGrid`: vertical `OneUiFocusBlock`s (Upload / Scan / Photos /
  Shared / Transfers) in the interaction area.
- Real recent files: `api.listFiles('/')` filtered/sorted by modified; pending
  uploads surface as `OneUiStatusPod`.

## My Files (`ui/screens/files/files_screen.dart`)
- `_GroupHeader` section headers ("Folders" / "Files") inside `OneUiGroupedList`.
- Rows via `OneUiFileTile` (accent folder icon, size/time subtitle, token
  selection state).
- Long-press selection → `OneUiActionBar` (Trash / Move / Copy / Share / Save).
- File menu + unsupported-type sheets via `OneUiSheet`.
- Header search action opens `screens/search/search_screen.dart`.

## Photos (`ui/screens/photos/photos_screen.dart`)
- Month-grouped gallery (`_MonthHeader`, `_groups`, count-driven subtitle).
- Long-press multi-select → `OneUiActionBar` (Share via `FileShareSheet`, Trash
  via `api.batch(action:'delete')`).
- `_PhotoCell` / `_SelectedOverlay` token-driven cells; thumbnails from
  `thumbnail_cache` with full-download fallback.

## Search (`ui/screens/search/search_screen.dart`)
- Debounced (350ms) `api.searchFiles`, grouped Folders/Files, opens the matching
  viewer (Photo/Video/Audio/PDF/Text).

## Shared (`ui/screens/shared/shared_screen.dart`)
- Shared-with-me views; already conforms to tokens; grouped list + empty state.

## Scanner (`ui/screens/scanner/scanner_screen.dart`)
- Real `CameraController` preview (back lens, `ResolutionPreset.high`), shutter
  ring (`_Shutter`), torch toggle, capture → `PlatformFile(name, size, bytes)` →
  `api.upload(folder: '')` with `scan-<ts>` uploadId; black chrome throughout.
- No-camera / permission-denied / desktop → pick-from-disk flow (`_ScanMode.picker`)
  so the entry is never dead. Sensor-fits preview, `SafeArea`, close action.

## Viewers (`ui/screens/viewers`, `ui/screens/media`)
- **PDF** (`viewers/pdf_viewer_screen.dart`): real renderer via `pdfx`
  (`PdfViewPinch` + `PdfControllerPinch`), full-file download to bytes first,
  pinch-zoom. Platforms without native PDF support (Linux desktop) fall back to
  a Download flow (`DownloadToViewScreen`).
- **Audio** (`viewers/audio_viewer_screen.dart`): streams via `downloadToFile` to
  temp then `audioplayers` `DeviceFileSource`; play/pause, ±10s skip, progress
  slider (accent), duration via `Format.duration`.
- **Video** (`media/video_player_screen.dart`): `VideoPlayerController.networkUrl`
  with `authHeaders`, play/pause overlay, scrubber, position/duration; black
  chrome; falls back to Download when the platform media backend is unavailable.

## Transfers (`ui/screens/transfers/transfers_screen.dart`)
- Grouped: Uploading (with byte progress + accent `LinearProgressIndicator`),
  Needs attention (retry/remove), Completed (clear).
- Rows are `OneUiSurface` (L1) tiles; empty state = offline hint.

## Sync center (`ui/screens/sync/sync_center_screen.dart`)
- `OneUiSurface` folder card (Choose/Unlink), Sync now (52dp filled), result
  stats, warning banner (conflicted files), linked-device list with revoke.
- Powered by real `SyncManager` (delta + SHA-256 + conflicts, desktop platforms).

## Settings (`ui/screens/settings/settings_screen.dart`)
- `OneUiPage` + grouped lists: General (Appearance/Sync center/Transfers/
  Notifications), Server (Connected to), Admin (Users/Audit log for admins),
  About; sign-out outlined button. Profile avatar + role caption.

## Admin / Notifications / Trash
- **Users** (`ui/screens/admin/admin_users_screen.dart`): token rows
  (`OneUiSurface` + `Material.transparency` + `ListTile`), create-user dialog,
  disable toggle.
- **Notifications** (`ui/screens/notifications/notifications_screen.dart`):
  All/Unread segmented filter; unread rows tinted (`accentContainerLight` /
  `surfaceAltDark`); mark-read.
- **Trash** (`ui/screens/trash/trash_screen.dart`): `OneUiPage` + restore /
  delete-forever actions with confirmation.

## Data & service layer (unchanged contracts)
`services/api.dart`, `services/transfer_queue.dart` (chunked resumable upload via
`api.uploadStatus`), `services/background_transfer_service.dart` (Android
WorkManager every 15 min), `services/sync_service.dart` (desktop two-way sync),
`core/models/file_entry.dart` (`offlineAvailable` metadata).