# NexaDrive UI Redesign Audit

> Phase 1 audit of the complete NexaDrive application prior to the Samsung One UI redesign.
> Date: 2026-09-10

---

## 1. Current Screen Inventory

All screens live in two files:

| Screen | File | Lines | Purpose |
|---|---|---|---|
| `LoginScreen` | `app/lib/screens/login_screen.dart` | 185 | Server/username/password login |
| `AppShell` | `app/lib/screens/app_shell.dart` | 201 | Root scaffold: sidebar + bottom nav + "More" sheet |
| `HomePage` | `app/lib/screens/app_shell.dart` | 235 | Dashboard: greeting, storage bar, quick actions, recent files, activity |
| `FilesPage` | `app/lib/screens/app_shell.dart` | 550 | File browser: list/grid, breadcrumb, upload, rename, delete, multi-select, download, share |
| `SharedPage` | `app/lib/screens/app_shell.dart` | 157 | "Shared with me" / "My shares" toggle |
| `SharedBrowsePage` | `app/lib/screens/app_shell.dart` | 106 | Browse inside a shared folder link |
| `PhotosPage` | `app/lib/screens/app_shell.dart` | 133 | Photo grid with eager thumbnail loading |
| `PhotoViewer` | `app/lib/screens/app_shell.dart` | 111 | Full-screen swipeable photo viewer |
| `TrashPage` | `app/lib/screens/app_shell.dart` | 140 | Trash list with restore / permanent delete |
| `SyncCenterPage` | `app/lib/screens/app_shell.dart` | 219 | Local folder sync, device management |
| `SettingsPage` | `app/lib/screens/app_shell.dart` | 169 | Profile, theme, admin links, sign out |
| `AdminUsersPage` | `app/lib/screens/app_shell.dart` | 225 | User CRUD (admin) |
| `AuditLogPage` | `app/lib/screens/app_shell.dart` | 75 | Read-only audit log |
| `NotificationsPage` | `app/lib/screens/app_shell.dart` | 133 | Notification list |
| `_UploadProgressDialog` | `app/lib/screens/app_shell.dart` | 246 | Per-file upload progress |

**Missing screens the product needs:**
- No PDF viewer / document view
- No video player
- No audio player / mini-player
- No camera capture
- No document scanner
- No uploads/transfers management screen
- No offline queue status screen
- No search screen
- No share-link creation UI (folded into Files)
- No file details panel/sheet
- No trash browsing by folder

## 2. Current Navigation Inventory

| Mechanism | Where | Detail |
|---|---|---|
| Imperative `Navigator.push` | Throughout | No named routes, GoRouter, or auto_route |
| Tab index `setState` | `AppShell` | Home / Files / Shared / Photos / More |
| `NavigationBar` (Material 3) | Mobile < 900px | 5 tabs |
| Sidebar (plain list) | Desktop >= 900px | 6 items in a 252px card |
| "More" bottom sheet | Mobile overflow | Trash, Sync center, Notifications, Settings |
| `AnimatedSwitcher(180ms)` | `app_shell.dart:172` | Page transition |

**Issues:**
- No Android back-button orientation for pushed pages
- No deep-linkable routes
- Media (photo viewer) is pushed full-screen without shared-element transitions
- Bottom interaction area is not used for actions (numbers/settings are reachability-focused already, but no FAB-style action palette)
- No persistent surfaced way to see transfer status

## 3. Current Component Inventory

All reusable widgets are private classes inside `app_shell.dart`:

| Widget | Lines | Notes |
|---|---|---|
| `Sidebar` | 89 | Desktop rail |
| `PageFrame` | 54 | Header + body |
| `_QuickActionIcon` | 40 | Home quick actions |
| `_RecentFileCard` | 55 | Home recent file card |
| `_ActivityItem` | 41 | Home activity stat |

Theme components (`app_theme.dart`):
- `CardThemeData` (radius 24, elevation 0)
- `ElevatedButtonThemeData` (accent bg, radius 12)
- `OutlinedButtonThemeData` (accent, radius 12)
- `InputDecorationTheme` (filled, radius 12)
- `NavigationBarThemeData` (standard)
- `SnackBarThemeData` (floating, dark)

**Issues:**
- Zero reusable widget files (no `widgets/` directory)
- No `DialogTheme`, `BottomSheetTheme`, `ListTileTheme`, `SwitchTheme`, `TabBarTheme`, `AppBarTheme`, `ChipTheme`
- Every page repeats loading/error/empty boilerplate
- No `TextTheme` — all text is hardcoded inline

## 4. Current Design Inconsistencies

1. **Theme contradicts itself**: `CardThemeData` declares radius 24, but every `ListTile` in lists forces `RoundedRectangleBorder(borderRadius: 0)` — card theme is rendered inert inside lists.
2. **Three duplicate byte formatters**: `HomePage.bytes()`, top-level `_formatBytes()`, and `TransferItem._formatBytes` — near-identical code.
3. **Hardcoded quota**: 50 GB (`53687091200`) walled into `HomePage` line 463; "50% free" text line 481. Server returns quota (`/api/storage`) but it isn't used.
4. **Hardcoded colors** inline (e.g. `Color(0x334F6BED)`) instead of theme tokens.
5. **Mixed border-radius language**: 8/12/24/32 used inconsistently across screens.
6. **Hardcoded production hostname**: `'https://<machine>.<tailnet>.ts.net'` embedded in `login_screen.dart`.
7. **Two simultaneous navigation metaphors** on desktop (sidebar list) and mobile (bottom bar) share no visual or motion language.
8. **Photos eager-loads full resolution** into a `Map<String, Uint8List>` — memory bomb.
9. **Material 3 `NavigationBar`** with generic Material indicator pill — does not feel One UI.
10. **No `SafeArea`** on pushed pages (SyncCenter, AdminUsers, Audit, Notifications, PhotoViewer).

## 5. Current Performance Bottlenecks (Flutter)

| # | Bottleneck | Location | Impact |
|---|---|---|---|
| P1 | `app_shell.dart` single 3,066-line monolith | whole file | Build cost, maintenance, hot-reload cost |
| P1 | Full-res photo bytes cached in RAM | `PhotosPage._thumbCache` | OOM on large photo libraries |
| P2 | No image caching library | photos | Every grid rebuild re-decodes network images |
| P2 | No pagination for photos / files / shared / trash | all lists | Whole-list API calls |
| P2 | Rebuild storms: `ListenableBuilder` on `Session` rebuilds `MaterialApp` | `main.dart:30` | Whole-tree rebuild on theme change |
| P3 | `setState` spam in upload dialog at 8 MiB chunk granularity | upload dialog | Excessive widget rebuilds |
| P3 | 30s `Timer.periodic` polling in `AppShell` | app shell | Battery/scheduling |
| P3 | No request cancellation on page swap | api layer | Stale response overwrites state |

## 6. Current Server-Side Bottlenecks (Rust)

| # | Bottleneck | Location | Impact |
|---|---|---|---|
| S1 | `tree_stats()` O(n) walk on **every** upload/copy | `main.rs` | Latency per upload with many files |
| S1 | `search_files()` full fs walk, no index | `main.rs` | Slow search, unbounded stat calls |
| S1 | `list_photos()` full fs walk | `main.rs` | Slow gallery load |
| S2 | `sync_manifest()` full walk + per-file hash | `main.rs` | Expensive initial sync |
| S2 | No thumbnail generation endpoint | — | Clients must load full-res images |
| S3 | SHA-256 computed synchronously (1 MiB buffer) | `main.rs` | Blocks async thread on large files |
| S3 | SQLite pool limited to 5 connections | `main.rs` | Contention under concurrency |
| S3 | Rate-limit map is in-memory, lost on restart | `main.rs` | Brute-force window resets |
| S4 | `copy_entry()` serial one-file-at-a-time | `main.rs` | Slow multi-file copies |

## 7. Current Missing Functionality

**Client:**
- PDF viewer (no support at all)
- Video player
- Audio player (no mini-player, no now-playing)
- Camera capture / photo upload
- Document scanner / PDF creation
- Offline/durable upload queue UI (exists internally in `TransferQueue` but no visible status)
- Connectivity-state awareness (can't distinguish internet vs Tailscale vs server vs auth failures)
- Search UI
- Dedicated share management screen
- File details panel
- Grid-view file browsing only in Files (no sort/filter controls surface)
- Download progress UI (background `downloadToFile` has no visual)
- Offline-mode read of previously viewed/thumbnailed content
- No model classes (raw `Map<String, dynamic>` everywhere)

**Server:**
- No thumbnail endpoint / generation
- No search index
- No database-backed quota cache (always full walk)
- No session cleanup job
- No `CSP` / `HSTS` security headers (partially)
- No Content-Range support signaling for video streaming (download endpoint streams full file; no `Range` header handling — video seeking will suffer)

## 8. Current Accessibility Issues

| # | Issue | Evidence |
|---|---|---|
| A1 | Zero `Semantics` widgets | grep count = 0 |
| A2 | Icon-only actions rely on `tooltip:` only (15 total) | tooltips not accessible on touch |
| A3 | No `MediaQuery.textScaler` handling beyond Flutter default | large fonts overflow fixed-height rows |
| A4 | No focus management / keyboard navigation | `FocusNode` count = 0 |
| A5 | No reduced-motion handling | `MediaQuery.disableAnimations` / `prefers-reduced-motion` never consulted |
| A6 | No screen-reader announcements for progress | upload dialog updates silently |
| A7 | Hardcoded `Color(0x334F6BED)` empty-state icons may fail contrast | — |
| A8 | Text contrast: `textOnSurfaceVariant #94A3B8` on `#FFFFFF` surface | ratio ~2.6:1, below 4.5:1 WCAG AA |
| A9 | No `tapTargetSize` handling | default 48px only |
| A10 | No focus outline on desktop keyboard nav | — |

## 9. Current Offline Limitations

1. `TransferQueue` persists chunked uploads but has **no visible UI**; failures just retry in a workmanager loop every 15 min.
2. No offline read cache for thumbnails or file metadata.
3. No queue status surfacing ("3 items waiting to upload").
4. No distinguishing of network types — all errors read "Request failed".
5. Desktop (Linux) has no background transfer (Platform.isAndroid gate) — a minimized desktop app silently stops uploading.
6. No retry with exponential backoff (fixed workmanager 15-min cadence).
7. Queue not structured into typed states (queued/uploading/paused/failed/completed/cancelled) at the UI layer.

## 10. Current File-Format Limitations

- **No preview/rendering of any file type beyond photos.** Files open nothing; only photo grid decodes images.
- No PDF, text, office-document, archive, audio, or video handling of any kind.
- The backend has no MIME detection (`mime_guess` not present) — sends `application/octet-stream` on download and multipart form browsing.
- No "Open with…" external-app fallback.
- No capability detection (is-downloadable vs is-previewable vs is-playable) stored or exposed.

## 11. Current Media Limitations

- Photos: grid + full-screen viewer with `InteractiveViewer` (maxScale 5) and swipe `PageView`. **No thumbnail endpoint; full-res decoded into memory for the whole library.**
- Video: none.
- Audio: none.
- Camera: none.
- Scanner: none.

## 12. Tests Audit

| Suite | Location | Count | Note |
|---|---|---|---|
| Flutter unit tests | `app/test/*.dart` | 20 | API client + widget layout |
| Flutter integration | `app/integration_test/*.dart` | 4 suites | Live-server E2E (login, upload, capture screenshots, responsive) |
| Rust unit tests | `server/src/main.rs` | 19 | Path/token/name security |
| Security regression | `scripts/security_test.sh` | ~22 | Live-server HTTP security |

**Gaps:** no widget tests for the redesigned navigation, selection mode, media players, offline queue, settings, dark mode, large fonts, or responsive/pane layouts.

---

## 13. Proposed Architecture Changes

### Flutter client

**Restructure into a layered architecture:**

```
lib/
  main.dart
  app.dart                       # MaterialApp, routes, theme wiring
  core/
    models/                      # typed data classes
    services/                    # Api, Auth, Storage, Transfers, Sync, Connectivity
    design/                      # One UI design system tokens
    utils/                       # formatBytes, date, mimetype, capability
  ui/
    shell/                       # AppShell, Sidebar, BottomNav, PageFrame
    screens/
      home/                      # Home screen
      files/                     # Files explorer, list/grid, selection, details
      photos/                    # Gallery, viewer
      media/                     # video player, audio player, mini-player
      scanner/                   # document scanner
      camera/                    # photo capture
      shared/
      trash/
      transfers/                 # uploads + offline queue
      search/
      settings/
      account/
      login/
      sync/
      admin/
    widgets/                     # OneUiButton, OneUiListTile, OneUiSheet, etc.
```

**Key architectural changes:**
1. Split `app_shell.dart` monolith into per-screen files.
2. Introduce typed models (`FileEntry`, `ShareItem`, `User`, `NotificationItem`, `TransferItem`, `PhotoItem`, `ServerStatus`).
3. Keep `ChangeNotifier` + `ListenableBuilder` (it works and is testable) but add lightweight scoped providers manually (no new dependency needed).
4. Add a `TransfersController` (ChangeNotifier) surfaced via a bottom status strip / sheet — the offline queue's UI face.
5. Add `ConnectivityStatus` service that classifies outages (internet vs tailscale vs server vs auth) with human messages.
6. Replace eager image bytes with a thumbnail-aware `ImageProvider` cache (bounded LRU) + platform decode. Prefer server thumbnail endpoint (see server section).
7. Add named routes (imperative `Navigator` is fine; introduce a simple route table + `GoRouterSession` not needed).
8. Add `SafeArea` to all pushed pages.

### Rust server

1. **Add `/api/thumbnails` endpoint** — generate cached JPEG/WebP thumbnails (e.g. 256px) for images/video frames where feasible; store in a per-user thumbnail cache dir keyed by content hash + size; serve with `Cache-Control` using the hash so invalidation is automatic.
2. **Add MIME detection** via `mime_guess` crate; include `content_type` in file listings and set correct `Content-Type` on download.
3. **Add HTTP `Range` header support** in download handler for byte-range video streaming (`Content-Range`, `206 Partial Content`) — required for video seek.
4. **Fix `tree_stats()` on upload path**: introduce a `storage_usage` cache table (user_id, bytes, file_count, updated_at) refreshed lazily/deltas instead of walking the whole tree per upload.
5. **Add a `file_index` table** (user_id, path, name_lower, extension, mime, size, created, modified) maintained on every mutation, used by search/photos/list instead of walking fs. This is the single biggest server win.
6. **Local thumbnail cache patrol**: background job prunes thumbnails older than N days / above a size cap.
7. **Session cleanup job** (delete expired sessions daily).
8. **CSP + HSTS headers** (non-breaking additions).
9. Keep the single-file `main.rs` initially; extract modules only if it helps the thumbnail/search changes (goals first — no gratuitous refactor that risks regression).

## 14. Proposed One UI Design System

### Principles
- **Focus on the task.** Top region = title + context. Bottom region = actions + content.
- **Generous horizontal margins.** Never cram content edge to edge.
- **Grouped focus blocks**, not endless tiny cards.
- **Restraint**: minimal gradient, minimal glassmorphism, minimal shadow. One UI uses depth carefully.
- **True dark mode**, not inverted light. Comfortable dark surfaces preserving media readability.
- **Visual hierarchy** via weight + size + spacing, not via colored containers.

### Color tokens (One UI-inspired)

| Token | Light | Dark |
|---|---|---|
| `background` | `#F7F8FA` (cool page tone) | `#000000` (Galaxy black) |
| `surface` | `#FFFFFF` | `#1D1E1F` (One UI dark surface) |
| `surfaceContainer` | `#EFF1F4` (subtle grouping) | `#232425` |
| `surfaceContainerHigh` | `#E4E6EA` | `#2A2B2C` |
| `accent` (One UI blue `ic_blue`) | `#0B87D0` (One UI primary blue per Samsung palette) | `#6CC4F7` (accent in dark) |
| `accentContainer` | `#D3EAF8` (light blue emphasis) | `#123A55` |
| `onAccentContainer` | `#0A5E8F` | `#9AD4F7` |
| `textPrimary` | `#1A1C1E` | `#F6F7F8` |
| `textSecondary` | `#5B5F66` | `#B8BDC3` |
| `textTertiary` | `#8A9099` | `#7D838C` |
| `divider` | `#E3E5E8` | `#2E3033` |
| `error` | `#B3261E` | `#FF5449` |
| `warning` | `#B25E00` | `#F1AD56` |
| `success` | `#23641E` | `#7BD46A` |

Accent uses the Samsung **One UI blue** family (the exact values Samsung ships in One UI 6/7 apps: primary action `#0B87D0`).

### Typography (One UI font language)

One UI uses **Roboto/Samsung One** with these key patterns:
- **Viewing-area title (page title)**: 28–34px, weight 600–700, tight leading. Extra-large page title one line, generous top margin.
- **Section header (grouped list header)**: 14–16px, weight 600, uppercase-ish small caps feel — one UI uses small colored/normal headers.
- **Primary text (list titles)**: 16–17px, weight 400–500.
- **Secondary text (list subtitles)**: 13–14px, weight 400, secondary color.
- **Metadata / captions**: 12–13px, tertiary.

### Spacing
- Base unit 4dp. Page side margins: **24dp phone / 32dp tablet-desktop**.
- Grouped list row: **56–64dp height**, 16dp horizontal padding, tile-to-tile divider 1dp.
- Section spacing: 24dp between groups.
- Touch target minimum: **48dp**; prefer 52–56 for common actions.

### Corner radii
- Rows / list items: **16–18dp** rounded-rect (One UI quirk: rows have soft rounded shape).
- Sheets/dialogs: **24–28dp** top radius; dialogs 20–24dp.
- Buttons: **full-bleed pill or 22–24dp** rounded (One UI pills).
- Images/media: **16dp**.
- Small chips: **12–16dp**.

### Motion
- **Page transitions**: Android spring-like ease; 250–350ms; mobile uses forward slide + fade; desktop is fade+slight scale. Back press reverses.
- **Bottom sheets**: One UI panel slide-up with 300ms ease-out + parallax dim; dismissal reverses.
- **State changes**: 150–200ms ease-out fades/scale, confirmed by saturation on press.
- **Reduced motion**: cross-fade only.

### Component language
- **Grouped list rows** (the One UI hallmark): surface-toned, rounded-16 grouped panels; end-icon chevron; icon in a **40dp soft tile** (no hard color).
- **Selection mode**: top contextual bar shows count + actions in the lower interaction area.
- **Bottom sheets**: for destructive/создание actions and multi-file ops.
- **Dialogs**: small pill-confirmed; AlertDialog with outlined short confirm.
- **Quick actions on Home**: rounded tiles with icon + label, 2-3 columns, not dashboard cards.
- **Storage overview**: a One UI-style progress bar row (labeled used/total), not a giant ring.
- **Media viewers**: full-screen immersive, controls overlay with translucent dark chrome.

### Icon language
- One UI uses soft rounded line icons. Prefer `material-icons` **rounded** variant where possible; keep stroke consistency; no outline fills mixed.

### Empty / error / offline states
- Illustration-free, human copy following One UI writing guidance:
  - Empty: icon in soft surface tile + title + one-line hint + primary action button.
  - Error: what happened + what user can do (Retry / Check connection).
  - Offline: "Can't reach NexaDrive — your files are safe. We'll retry automatically." + Last-connected time.
- No infinite spinners; every loading state has a fallback.

## 15. Final Note: Scope Guard

- Client remains a **single Flutter codebase** shared by Android + Linux desktop (per AGENTS.md).
- Server remains **embedded SQLite** (WAL, FK, busy_timeout). No PostgreSQL regression.
- Backend stays **the authorization authority**. No security regressions.
- Phased delivery: design system → navigation → screens → media → scanner → offline → performance → accessibility → QA.