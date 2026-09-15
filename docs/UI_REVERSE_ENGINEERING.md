# NexaDrive UI — Reverse-Engineering Reference

> Status: line-accurate documentation of the **current** app as of 2026-09-11.
> This document describes what exists today so a future agent can write a One UI 9-inspired
> design spec without guessing. Every value is taken from source unless marked **[EST]**.
> No design changes were made to produce this document.

---

## 1. Project inventory

Top-level layout of the repo relevant to UI:

```
nexadrive/
├── app/                      Flutter client (mobile + desktop, single codebase)
│   ├── pubspec.yaml          name: nexadrive, version: 1.1.0+2
│   ├── lib/
│   │   ├── main.dart         App entry, image-cache tuning, theme wiring
│   │   ├── core/
│   │   │   ├── design/       app_colors.dart, app_dimensions.dart,
│   │   │   │                 app_typography.dart, app_motion.dart, app_theme.dart
│   │   │   ├── models/       file_entry.dart  (FileEntry, StorageInfo, ServerStatus)
│   │   │   └── utils/        file_kind.dart, format.dart
│   │   ├── services/         api.dart, session.dart, transfer_queue.dart,
│   │   │                     sync_service.dart, background_transfer_service.dart,
│   │   │                     thumbnail_cache.dart
│   │   └── ui/
│   │       ├── shell/        app_shell.dart, navigation.dart
│   │       ├── widgets/      9 reusable widgets (see Component Inventory)
│   │       └── screens/      login, home, files(+2 sheets), shared(+1 browse),
│   │                         photos(+viewer), trash, settings, transfers, sync,
│   │                         notifications, admin(users, audit), viewers(text, pdf),
│   │                         media(audio, video)
│   ├── test/widget_test.dart          3 widget tests
│   ├── integration_test/              4 live-server integration tests
│   └── android/ linux/ macOS.../      platform shells
├── server/                  Rust/Axum + SQLite backend (no UI, but owns auth/data)
├── docs/                    All docs (this series + prior audits)
└── screenshots/             PNG captures written by integration_test/capture_test.dart
```

**Client stack (from `app/pubspec.yaml`, v1.1.0):**
- Flutter SDK `>=3.5.0 <4.0.0`; built/analyzed with Flutter 3.47.2 during this pass
- Dependencies: `http ^1.2.2`, `file_picker ^11.0.3`, `shared_preferences ^2.3.2`,
  `flutter_secure_storage ^10.3.1`, `path_provider ^2.1.6`, `crypto ^3.0.7`,
  `uuid ^4.5.1`, `workmanager ^0.10.9`, `cupertino_icons ^1.0.8`
- Dev: `flutter_test`, `integration_test`, `flutter_lints ^4.0.0`
- **Notably absent** (deliberate): `video_player`, `audioplayers`, `pdf`, `google_fonts`.
  Video/audio/PDF are download-first; the system font is used everywhere.

**Theme system:** `MaterialApp` in `main.dart` uses `AppTheme.light()` / `AppTheme.dark()`
with `themeMode` from `Session.themeMode` (`'system' | 'light' | 'dark'`).
`useMaterial3: true` is set; the One UI look is applied through a Material 3
`ColorScheme` + per-component `ThemeData` overrides.

---

## 2. Screen inventory (complete)

Main-shell pages (swap in place, index 0–5):

| # | Page | Class | File |
|---|------|-------|------|
| 0 | Home | `HomeScreen` | `ui/screens/home/home_screen.dart` |
| 1 | My files | `FilesScreen` | `ui/screens/files/files_screen.dart` |
| 2 | Shared | `SharedScreen` | `ui/screens/shared/shared_screen.dart` |
| 3 | Photos | `PhotosScreen` | `ui/screens/photos/photos_screen.dart` |
| 4 | Trash | `TrashScreen` | `ui/screens/trash/trash_screen.dart` |
| 5 | Settings | `SettingsScreen` | `ui/screens/settings/settings_screen.dart` |

Pushed routes (own `Scaffold` unless noted):

| Route | Class | File |
|-------|-------|------|
| Login | `LoginScreen` | `ui/screens/login/login_screen.dart` |
| Photo fullscreen viewer | `PhotoViewer` | `ui/screens/photos/photo_viewer.dart` |
| Shared folder browse | `SharedBrowseScreen` | `ui/screens/shared/shared_browse_screen.dart` |
| Transfers (queue) | `TransfersScreen` | `ui/screens/transfers/transfers_screen.dart` |
| Sync center | `SyncCenterScreen` | `ui/screens/sync/sync_center_screen.dart` |
| Notifications | `NotificationsScreen` | `ui/screens/notifications/notifications_screen.dart` |
| Users (admin) | `AdminUsersScreen` | `ui/screens/admin/admin_users_screen.dart` |
| Audit log (admin) | `AuditLogScreen` | `ui/screens/admin/audit_log_screen.dart` |
| Text viewer | `TextViewerScreen` | `ui/screens/viewers/text_viewer_screen.dart` |
| PDF download-to-view | `PdfViewerScreen` | `ui/screens/viewers/pdf_viewer_screen.dart` |
| Audio download-to-view | `AudioPlayerScreen` | `ui/screens/media/audio_player_screen.dart` |
| Video download-to-view | `VideoPlayerScreen` | `ui/screens/media/video_player_screen.dart` |

Regexable note: `Pdf/Audio/Video` screens subclass `DownloadToViewScreen`
(`ui/widgets/download_to_view.dart`), which renders an AppBar + centered 96×96 icon tile +
file name + "Download" button + "Saved to …" confirmation.

Modal surfaces (bottom sheets / dialogs):

| Surface | Class | File |
|---------|-------|------|
| Mobile "More" sheet | inline `_SheetTile` list | `shell/app_shell.dart` |
| File row menu | inline `_SheetAction` list | `screens/files/files_screen.dart` |
| Unsupported-format sheet | inline | `screens/files/files_screen.dart` |
| File details sheet | `FileDetailsSheet` | `screens/files/file_details_sheet.dart` |
| Share sheet | `FileShareSheet` | `screens/files/file_share_sheet.dart` |
| Folder picker sheet | `FolderPicker.pick` / `FolderPickerBody` | `widgets/folder_picker.dart` |
| Upload progress dialog | `UploadProgressDialog` | `widgets/upload_progress_dialog.dart` |
| Dialogs: New folder, Rename, Move-to-Trash confirm, Delete-forever confirm, Remove share, Sign out confirm, Theme picker, Server info, About, New user, Remove upload, Settings "Connected to" | inline | various files |

Empty/error states are a shared widget: `OneUiEmptyState`.

---

## 3. How the UI is assembled

### 3.1 App entry (`main.dart`)
- `PaintingBinding.instance.imageCache` set to `maximumSizeBytes = 384 MiB`,
  `maximumSize = 400` before `runApp`.
- `Session.load()` runs first; if a token exists, `BackgroundTransferService.schedule()`
  registers the 15-min Android periodic workmanager task.
- `NexaDriveApp` rebuilds the `MaterialApp` on `Session` changes via `ListenableBuilder`;
  `home` is `LoginScreen` when `session.token == null`, else `AppShell`.

### 3.2 Shell (`app_shell.dart`)
- `_AppShellState` holds `int index` (0–5), creates one `Api`, wires `api.onUnauthorized`
  → session clear + root-navigate to Login.
- Timers: `Timer.periodic(30s)` → `_resumeQueue()`; post-frame callback →
  `_checkServerAndQueue()` + `_autoSync()` (desktop platforms only).
- Lifecycle: on `AppLifecycleState.resumed` → resume queue + auto-sync.
- Layout: `MediaQuery.width >= 900` → desktop `Row` with `SideNavigation` (236dp) +
  `_PageHost(pages[index])`; else mobile `Stack` with `_PageHost` + `OneUiBottomNav`.
- `_PageHost` wraps each page in `AnimatedSwitcher` (200 ms, `easeOut`/`easeIn`,
  not the tokenized `AppMotion` values — see Design Debt).
- Mobile nav: `OneUiBottomNav` maps `index >= 4 ? 4 : index`; tapping destination 4
  (`More`) opens `_showMoreSheet()` (a modal bottom sheet with Scan document, Transfers,
  Trash, Sync center, Notifications, Settings).
- Session-expiration handling cancels background work, clears session, toasts
  "Session expired. Please sign in again.", and pushes Login with `pushAndRemoveUntil`.

### 3.3 Navigation (`navigation.dart`)
- `SideNavigation` (desktop): brand block (38×38 accent cloud tile) on top; ListView of
  `SideNavItem` Home/My files/Shared/Photos/Trash + `_UtilityNavItem` Transfers/Sync
  center/Notifications; Settings pinned at bottom. Width 236, horizontal padding 12.
- `SideNavItem`: `ListTile`, `visualDensity: compact`, leading icon 24, selected state =
  accent icon + accent text + w600 weight + `selectedTileColor: accent@10%`, row radius 18.
- `OneUiBottomNav`: Material `NavigationBar` with `labelBehavior: alwaysShow`,
  5 destinations. Labels `['Home','Files','Shared','Photos','More']`; outlined icons
  unselected, filled rounded icons selected.

### 3.4 Page skeleton (`one_ui_page.dart`)
- `OneUiPage` = `Column[ _ViewingArea, Expanded(body) ]`.
- `_ViewingArea`: `pageTitle` (28/w700) title + optional `rowSubtitle` subtitle, top
  padding 24/12 bottom, horizontal `pageMargin` (24). Header action sits right-aligned.
- `OneUiBody`: horizontal `pageMargin` padding; optional `maxWidth 1100` centering.

---

## 4. Server surface that affects the UI

The client drives everything through `Api` (`services/api.dart`, 510 lines). Endpoints
used by the UI and their handlers (verified against `server/src/main.rs` route table,
lines ~474–530):

- `GET /api/server/status` → Home instance-id toast on restart; returns `public_url`.
- `POST /api/auth/login` / `logout`; `GET /api/me`.
- `GET /api/files?path=` → MY FILES list; `DELETE /api/files`; `GET /api/files/search`;
  `POST /api/files/rename|move|copy|batch|upload`; `GET /api/files/download` (+ shared
  variant); `GET /api/files/thumbnail?path=&max=` (added 2026-09-11, JPEG q84 or 415);
  `POST /api/folders`; `POST /api/uploads/chunk`; `GET /api/uploads/status`.
- `GET /api/storage` → Home storage tile.
- `POST /api/trash`? no — `GET /api/trash`, `POST /api/trash/restore`, `DELETE /api/trash`.
- `GET /api/photos` → Photos grid.
- `GET /api/shares`, `POST|DELETE /api/shares`, `GET /api/shared`,
  `GET /api/shared/items`, `GET|POST /api/shared/download|action`.
- `GET /api/sync/manifest|delta|devices`, `DELETE /api/sync/devices`, `POST /api/sync/delete`.
- `GET /api/notifications` (+`?unread=true`), `POST /api/notifications/read`.
- `GET /api/backup/status|snapshots`, `POST /api/backup/run|restore|check`.
- `GET|POST /api/admin/users`, `PUT /api/admin/users/{id}`, `GET /api/admin/audit`.
- No admin backup UI exists in the client despite backup APIs being present.

**Auth model:** every request sends `Authorization: Bearer <token>`; token stored in
`FlutterSecureStorage` (not SharedPreferences), legacy plaintext token migrated on load.
Any 401 fires `api.onUnauthorized` → hard redirect to Login. Server owns authorization
(client never trusts the client for permissions; admin sections render solely based on
`session.role == 'admin'`).

**Session persistence (`services/session.dart`):**
- `serverUrl`, `displayName`, `username`, `role`, `themeMode` in SharedPreferences.
- `token` in secure storage. `normalizeServerUrl`: trims, collapses trailing `/`, and
  **defaults to `https://` when no scheme is present** (an explicit `http://` is
  preserved for HTTP-only LAN servers).
- `clear()` wipes all keys + secure token; login screen then reactivates with empty fields
  (server/username prefill only from an existing session object).

---

## 5. Data model & formatting used at render time

- `FileEntry` (`core/models/file_entry.dart`): name/path/type('file'|'folder')/size/
  modifiedAt/pinned/offlineAvailable. `category` derived via `FileKind.category`.
- `StorageInfo`: usedBytes/fileCount/quotaBytes; `usageFraction`, `freeBytes`.
- `Format` (`core/utils/format.dart`): `bytes()` (B/KB/MB/GB/TB, 1024-based, 0 or 1
  decimal), `relTime()` ("Just now", "Nm ago", "Nh ago", "Nd ago", then "Jan 5" or
  "2026/09/10"), `shortDateTime()` ("2026-09-10 14:30"), `count()` pluralizer.
- `FileKind` (`core/utils/file_kind.dart`): extension→`Category` mapping
  (folder, image, video, audio, pdf, document, archive, text, unknown), per-category
  icon + fixed tint hex + `tileFill` (tint @12% light / @20% dark) + human label +
  `isPreviewable` (image/text/pdf true) + `isPlayable` (video/audio true).

---

## 6. Offline / upload-queue architecture (behind the UI)

- `TransferQueue` (`services/transfer_queue.dart`): persisted to SharedPreferences key
  `transfer_queue_v2`; items have id (uuid v4), local `path`, name, folder, size,
  `transferred`, status (`queued`/`uploading`/`completed`/`queued+error`), error, createdAt.
  Resumable uploads via `/api/uploads/chunk` with **8 MiB chunks**
  (`TransferQueue.chunkSize = 8 * 1024 * 1024`) and `/api/uploads/status` offset resume.
  Pause = in-memory `_paused` set; `reset()` zeroes and requeues.
- `BackgroundTransferService` (Android only, `workmanager`): periodic 15-min task with
  `networkType: connected`, `requiresBatteryNotLow: true`, tag `nexadrive-transfers`.
- `SyncManager` (`services/sync_service.dart`): desktop-only (Windows/Linux/macOS) folder
  sync via manifest/delta/tombstones; sha256; conflict copies saved as
  `<path>.conflict-<epoch>`; durable state in SharedPreferences key `sync_state_v1`;
  device id/name keys `sync_device_id_v1`, `sync_device_name_v1`; folder key
  `sync_folder_v1`.
- `ThumbnailCache` (`services/thumbnail_cache.dart`): disk cache under
  `getApplicationCacheDirectory()/thumbnails`, file keys = `md5('<serverUrl>|<path>')`,
  `.jpg`, 7-day TTL, 512-entry cap (pruned oldest-first at open), `readSync` for
  build-time resolution. Server URL is part of the key so switching servers never leaks.

---

## 7. File-type → open behavior matrix

| Category | Detection (FileKind ext sets) | Tap behavior |
|----------|-------------------------------|--------------|
| folder | `type == 'folder'` | navigate into folder |
| image | jpg jpeg png gif webp bmp heic heif tif tiff | `PhotoViewer` (paged, from current folder's images) |
| video | mp4 mov mkv webm avi m4v 3gp | `VideoPlayerScreen` → DownloadToView |
| audio | mp3 aac m4a wav flac ogg opus aiff wma | `AudioPlayerScreen` → DownloadToView |
| pdf | pdf | `PdfViewerScreen` → DownloadToView |
| document | doc docx odt rtf pages | unsupported sheet (Download) |
| archive | zip tar gz tgz 7z rar bz2 xz zst | unsupported sheet (Download) |
| text | txt md markdown log json xml yaml yml conf ini cfg toml csv html htm css js ts dart rs py rb go java c h cpp hpp sh sql nfo | `TextViewerScreen` (in-app) |
| unknown | everything else | unsupported sheet (Download) |

`shared_browse_screen.dart` does **not** reuse this matrix: any non-folder item taps → download
(dialog with file picker save). `showFilesMenuFor` exists for shared-browse reuse but only
opens the PhotoViewer for a single image.

---

## 8. Colors sanity (light/dark mapping source)

Brightness-conditional accessors used across the app (`AppColors.*For(Brightness)`):
accent, accentContainer, onAccentContainer, textPrimary/Secondary/Tertiary, divider,
success, warning, error, info. Shell and page headers call `Theme.of(context).brightness`
directly (not `ThemeMode`), so pages follow the resolved system/app theme.

---

## 9. Test-driven behavior guarantees (must not regress)

`test/widget_test.dart` (3 tests, all green):
1. Signed-out → Login shows `'Welcome to NexaDrive'`.
2. 2560×1800 (DPR 2) → desktop: `'NexaDrive'`, `'Home'`, `'My files'`, `'Settings'` present,
   NO `NavigationBar`.
3. 400×800 → mobile: `NavigationBar` present, `'Photos'` single; tapping `'More'` reveals
   Trash, Sync center, Notifications, Settings.

`integration_test/*` (run against the live Tailscale server):
- `app_flow_test.dart`: desktop login→home→settings→sign-out round trip;
  server field prefilled with `https://<machine>.<tailnet>.ts.net`.
- `upload_test.dart`: 20 MB multi-chunk upload through `UploadProgressDialog`, progress
  text visible, terminal "Upload complete", close, remote listing, byte-identical
  SHA-256 download round-trip, cleanup.
- `responsive_test.dart`: walks 7 sizes (400×800 … 1920×1080) × 6 pages with
  `takeException() == null` on every stop.
- `capture_test.dart`: writes `screenshots/01_login … 07_settings.png` from a
  `RepaintBoundary` (DPR 1.0).

---

## 10. Performance posture (measured in code)

- Image cache: 384 MiB / 400 entries (thumbnails survive across screens; full-size
  viewer decodes have room).
- Photos: first 40 thumbnails prefetched at 512 px via `/api/files/thumbnail` after
  the list loads; disk cache consulted synchronously at build; 415 → full-download
  fallback. PhotoViewer prefetches current ±1 page of full originals into an in-memory
  `Map`, cleared on dispose.
- Server thumbnails: bounded in-memory cache (1024 entries, 10 min TTL), JPEG q84,
  `Cache-Control: private, max-age=86400` (opt-in via `x-nexadrive-cacheable` marker;
  all other responses `no-store`).
- Upload dialog polls `TransferQueue.items()` every 700 ms; shell queue timer every 30 s.
- Workmanager queues+processes transfers every 15 min on Android (battery-aware).