# NEXADRIVE CURRENT UI — COMPLETE INVENTORY

> v1.1.0 · snapshot against `app/` (Flutter) + `server/` (Axum) as built.
> This is the master index; every claim below lives, proved, in one of the
> nine companion docs in `docs/`. Nothing here is a redesign — NODA (No
> Opinions, Documented As-is) was the rule.

---

## 0. The nine docs (read these in order)

1. `UI_REVERSE_ENGINEERING.md` — project, screen map, shell assembly, server surface,
   data model, offline architecture, open-matrix, tokens sanity, test guarantees.
2. `UI_COMPONENT_INVENTORY.md` — every reusable widget + per-screen inline widget table
   + theme component table + FileKind iconography.
3. `UI_SCREEN_SPECIFICATION.md` — 20-section spec: Login → My files → Photos → Shared →
   Sync center → Transfers → Notifications → Trash → Admin → Audit → Text/PDF/video/
   audio → dialogs/sheets → cross-screen rules.
4. `UI_INTERACTION_MAP.md` — navigation graph, touch interactions, motion inventory,
   dead & missing interactions.
5. `UI_DESIGN_TOKENS.md` — colors, dimensions, typography, motion, theme mapping.
6. `UI_ACCESSIBILITY_AUDIT.md` — computed contrast matrix, touch targets, semantics.
7. `UI_RESPONSIVE_AUDIT.md` — breakpoints, per-width behavior, grid rules, tests.
8. `UI_PERFORMANCE_AUDIT.md` — image pipeline, upload engine, timers, risk register.
9. `ONE_UI_REFERENCE_NOTES.md` — Samsung One UI 7→9 sourced reference + APPLE METHODOLOGY
   review lens (Samsung visual language vs Apple interaction methodology).

---

## 1. Screens (12) — with reachability

| Screen | Path/feature | Reached from |
|--------|--------------|--------------|
| Login | auth, server address, arc set | first-run / sign-out |
| **Home** (Dashboard) | quick actions, storage tile, quota, pending uploads tile | rail/bottom-nav "Home" |
| **My files** | folders + files list/grid, select multi, breadcrumbs, sort, details via ⋮ | rail/bottom-nav "My files" |
| Photos | thumbnail grid, previewer incl. slideshow | side sheet "Photos" |
| Shared | segmented With me / Shared by me | rail/bottom-nav "Shared" |
| Shared browse | open a shared subfolder (breadcrumb nav, no upload) | Shared tab row tap |
| Trash | 30-day pending deletions, restore / delete-forever | More sheet (mobile) / rail (desktop) — **Trash place differs per form-factor** (see INTERACTION_MAP §1) |
| Sync center | playback of the transfer queue, per-file results/conflicts | rail/bottom-nav "+" sheet "Sync center" (desktop rail item "Sync center") |
| Transfers | all transfers, contacts top | bottom-nav "Transfers" (Sync center ⇄ Transfers cross-passable) |
| Notifications | server notifications, mark-read, badge | bottom-nav "Notifications" |
| Settings | profile, theme *Light/Dark/System*, quota, privacy iPause/Deauth, auto-sync toggles, "Start connecting" device | rail/bottom-nav "Settings" |
| Admin: Users / Audit Log | server-user CRUD + audit trail | Settings → "Admin" menu |

## 2. Shell & navigation

- **Two chrome modes, one codebase** (app_shell.dart): `width ≥ 900` → `SideNavigation`
  (236 dp, brand, 6 items incl. Trash + Sync center + logout, active = accentContainer
  pill); else `NavigationBar` (84 dp, 5 visible items + "More" sheet 4th long-pressable;
  More sheet = 6 tiles incl. Photos, Sync center, Trash, Settings, Scan — **Scan is a
  no-op placeholder**).
- App resize (90→screen width 900) swap in place; body cross-fades (200 ms easeIn/out).
- Every page = `OneUiPage` (safe-area, gutter 24/32, maxWidth 1100) + `OneUiBody`.
- **Trash is the only reachability difference between mobile & desktop** — documented,
  not a bug.

## 3. Components (inventory peek)

Tiles: `OneUiGroupTile`, `OneUiFileTile`/`OneUiFileGridTile`, `OneUiInfoRow`, section
group lists w/ uppercase headers, `OneUiEmptyState` (+tile-36, action button variants,
error/retry), `OneUiProgressTile` (4/6/8 heights), forms (rounded-12 filled fields),
buttons (pill, min 64×48), segmented pill w/ accentContainer, snackbars (dark floating
radius 12, material tint on snack), dialog radius 24 w/ drag-handle sheets 28,
dialogs non-scroll only on tiny ones, selection chrome on files/photos/shared.

## 4. Media-file experience (by type)

| Type | Where | Behavior |
|------|-------|----------|
| Image | Photos + My files tap | Native viewer: black canvas, bottom-glass bar (blur 12, white 6%), Download / Save to files / Share, InteractiveViewer zoom ≤5×, page-slide swipes, prefetch ±1, SES-collapsed on tap |
| Text | My files → any .txt | server spec-view (syntax colors optional r S) — TextViewer monospace 13 selectable, UTF-8 lenient |
| PDF | My files → .pdf | `pdfx` in-app page viewer (part of repo) |
| Video | My files → video | in-app `chewie`-less `VideoPlayer` (part of repo) |
| Audio | My files → audio | in-app player with webview fallback |
| Unknown | thumb/412 → read-only name dialog | no editor (action = Read) |

## 5. Modal surfaces

- Pickers: FolderPicker (bottom sheet, fixed 180 of scope), Share-sheet
  (authorized link creation/revoke in sheet), file-share Sheet object.
- Input dialogs: New folder, Rename, New user (admin), Theme, Privacy pause.
- Progress dialog: **Upload** (modal w/ per-file bars, 700 ms queue poll,
  PopScope handled, cancel = remove non-completed uploads).
- Device/perm: add-device sheet, share-permission segmented, settings panels.

## 6. Interactions

- Select multi (mobile: long-press; desktop: also via row menu), action bar count,
  select-all in More/context menu; folder navigation = open (not back) via rows +
  back-icon in header; shared-subfolder browse has same breadcrumb, **upload disabled**.
- Refresh: pull-to-refresh on My files/Photos/Shared/Sync-center; Home auto-reloads on
  resume timer.
- Sort: fixed name (folders-first); **size/newest/oldest enum exists but unused**.
- Delete/restore paths: trash → restore w/ toast, delete-forever w/ confirm.

## 7. Motion inventory

- Tokens: micro 120 / fast 180 / normal 300 / slow 380; standard Cubic(.25,.1,.3,1);
  enter/exit patched cubic; fade = easeOut; spring response .35 damping 1.0.
- Used: storage-progress animates `normal`+`standard`; upload-status AnimatedSwitcher
  180 ms; sheets/dialogs Material; page cross-fade **raw 200 ms** (debt);
  RefreshIndicator/route transitions Material default.
- Reduced-motion: `AppMotion.resolve` exists, **called nowhere** (debt).

## 8. Responsive

- Breakpoints: `≥900` chrome swap, `<700` login-compact, `≥800` quick-actions=4 cols,
  photos maxCross 190 / gap 4, files maxCross 170 / gap 12 / 0.95, content cap 1100.
- No orientation lock; all pages scrollable; 7-size integration sweep
  (400×800 … 1920×1080) asserts `takeException()==null`.
- Fixed-height components are not text-scale aware (ACCESSIBILITY_AUDIT §7).

## 9. Accessibility (headline numbers, computed)

- passes AAA: primary text, onAccentContainer pairs (both modes), error/success.
- **fails AA normal text**: light-hue accent on white (3.9:1) for links/buttons/labels;
  3.4:1 nav-bar selected label (11 px); tertiary grays 2.9–3.2:1 light, 4.1–4.4:1 dark.
- touch: breadcrumbs are the only sub-48 target; semantics missing on photo tiles +
  upload live-region; keyboard: breadcrumbs/grid non-focusable, no multi-select
  accelerator on desktop.
- Reduced-motion not applied; text scaling not honored by fixed heights.

## 10. Performance (headline)

- 384 MiB / 384-entry image cache lifted on boot.
- Photos: first-40 thumbnail prefetch, disk+cache, 512px JPEG q84, 7-day/512 LRU,
  md5(server|path) keys — **photos grid rebuilds up to 40× during warm-up** (top risk).
- Viewer: full-original in-memory prefetch ±1 (no down-sample — medium risk).
- Upload: 8 MiB chunks + resume, 700 ms dialog poll, 30 s shell process timer,
  Android background 15-min workmanager.
- Server: in-memory thumb cache 1024/10-min, private max-age 86400.

## 11. Missing / not implemented (facts, must stay stated)

- **Camera / Scan / document scanner — not currently implemented** (Scan tile is a
  no-op).
- No in-app PDF text selection/annotate, no video seek-buffer UI beyond native player,
  no local offline file cache UI, no search UI (endpoint `/api/files/search` exists
  server-side, desktop text search only `[EST]`), no clip/upload-pause buttons.
- `pinned` & `offlineAvailable` model fields present but no UI to set them.
- No light/dark-by-appearance beyond theme modal; no True-Tone/webview tinting.

## 12. Test & verification story (so the redesign never regresses)

- `flutter analyze` clean · `flutter test` → 17 passed (login flow, desktop chrome,
  mobile+More sheet) · integration: server app-flow, 20 MB chunked upload SHA-256
  byte-identical, responsive sweep 7 sizes, screenshot capture device (DPR 1) PNGs.
- Access shackles: **upload dialog polling contract (700 ms) is in the upload test**;
  don't change the poll/queue contract silently.

---

*End of inventory. Next step for any redesign work: open each doc 1→9, then write the
One UI 9-inspired spec (SAMSUNG VISUAL LANGUAGE) and run every change through the
APPLE METHODOLOGY review grid.*