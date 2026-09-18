# Changelog

## Unreleased

### Sync engine: three real defects found by a deterministic test matrix

The sync engine had no end-to-end coverage — every previous claim about it rested
on reading the code. It now has 26 tests driving the real `SyncManager` against a
faithful in-process fake of the `/api/sync/*`, `/api/folders`, `/api/uploads/*`
and `/api/files/download` endpoints, covering first sync, repeat sync, local and
remote add/modify/delete, both directions of folder propagation, simultaneous
edits, all three conflict resolutions, failed transfers and their retry,
concurrent first sync, expired sessions and device-identity stability.

Writing it exposed three genuine bugs:

- **A deletion on another device was silently undone.** When a remote file was
deleted and the local copy was unchanged, the engine called `sync_delete` (a
no-op against an already-deleted path) and dropped its baseline entry *without
deleting the local file*. The next sync therefore saw an unknown local file and
re-uploaded it, resurrecting the deletion. The local copy is now removed when the
server confirms the deletion with a tombstone.
- **A remote delete with no tombstone dropped the baseline.** Where the remote
copy vanished without a tombstone (an incomplete delta view, or a row removed out
of band), the engine also dropped its baseline — which re-uploaded the file on
the next run without recording that it had. It now treats the local file as the
source of truth and restores it explicitly, so the following sync is a no-op.
- **Sync drove the user's manual transfer queue.** `_uploadFile` enqueued into
`transfer_queue_v2` — the list the Transfers screen renders — and never cleaned
up. Three consequences: every synced file left a permanent `completed` row
behind, so the list grew without bound and was re-parsed on every queue pass; a
*failed* sync upload was silently retried as a side effect of the next file's
upload, because `TransferQueue.process()` operates on the whole queue, so a
reported failure succeeded behind the engine's back (`chunks=3`, `offsets=[0,0]`
in the failing test); and a failed sync row lingered as `queued` forever, so the
shell re-attempted it on every launch and every server-status poll.
Sync now streams its own uploads — resuming from the server-reported offset,
retrying transient failures with backoff, reusing `TransferQueue.isTransient` (now
public) as the single source of truth for what is retryable, and reading chunks
straight off disk so a multi-gigabyte file never becomes resident in memory.

### Duplicate sync devices — root cause fixed on both sides

The Sync Center listed repeated, indistinguishable entries ("NexaDrive desktop /
Last seen 6d ago") because one machine really had been registered more than once.

- **The client's device identity did not exist until the server replied.**
  `SyncManager.sync()` persists `device_id` *after* the response, and it is
  reached from two independent call sites — the shell's startup sync
  (`app_shell.dart`) and the Sync Center's manual sync — each constructing its
  own `SyncManager`. On a fresh install both read `device_id == null` before
  either persisted it, so both announced a new machine. The server then minted a
  fresh random id for each, and one machine became two (or more) rows with
  identical names and no way to tell them apart.
- **The identity is now created locally, before any request**
  (`SyncManager.ensureDeviceId`), memoised through a single shared future so
  concurrent callers cannot each generate their own, and reused for the UI's
  "this device" marker. Both call sites now send the same id and converge on one
  row.
- **`sync()` is guarded process-wide** (`SyncManager._inFlight`), so a second
  caller joins the run already in flight instead of starting a competing one.
- **Server: an unknown client id is adopted instead of replaced.**
  `plan_device_link` / `resolve_sync_device` now bind identity as: a known id is
  refreshed in place; a supplied id that is free is adopted verbatim (which is
  what makes two concurrent first syncs idempotent — the loser's primary-key
  collision is treated as success, not an error); an id owned by **another
  account is never hijacked**, and a fresh one is minted instead; and a request
  with no id at all reuses the newest row for the same name+platform rather than
  appending another. 6 new tests cover every branch.

### Login was unreachable on a short viewport

The sign-in form was a centred `SingleChildScrollView`. That made it
*technically* scrollable while leaving the primary action off-screen at the
sizes that actually occur:

| Viewport | "Sign in" bottom | Overflow |
| --- | --- | --- |
| 1280×464 (a small Linux window) | y=538 | **74px past the fold** |
| 640×360 (phone in landscape) | y=538 | **178px past the fold** |

An integration run had reported exactly this (`a tap target outside the Linux
root`, `Offset(640.0, 510.0) ... outside the bounds of the root of the render
tree, Size(1280.0, 240.0)`). The layout is now adaptive: above 620px of
available height the centred composition is kept, and below it the fields scroll
while the primary action is pinned to the bottom of the visible area. Because a
`Scaffold` shrinks its body when the keyboard opens, that also keeps **Sign in
above the on-screen keyboard**. `app/test/login_layout_test.dart` asserts the
button is fully inside the viewport and actually hit-testable at 1280×464,
640×360, 360×640, 390×844, 800×1280, 1920×1080, a 240px-tall viewport, and 1.5×
and 2.0× accessibility text scales — 9 tests, all of which failed before.

### The "yellow/green underline under every line of text" report — closed

Not a typography bug, and nothing in the app was changed for it. The lines are
Flutter's **debug baseline visualisation** (`debugPaintBaselinesEnabled`), which
paints the alphabetic baseline in `0x00FF00` and the ideographic baseline in
`0xFFFFD000` beneath every line of text. Both call sites live inside
`assert(() { … }())` in the framework, so they are compiled out of release
builds entirely. Nothing in this repository ever enables it — it is a toggle in
the Flutter Inspector / DevTools.

Proven rather than asserted: the two reported screens were rendered to PNG with
the flag off and on. Only the "on" renders contain the colours (83 distinct
green-family and 116 amber-family blends, zero of either in the "off" renders).
The evidence and the reproduction steps are in
`app/doc/diagnostics/DEBUG_TEXT_UNDERLINE_DIAGNOSIS.md`, with the before/after
images alongside it.

`app/test/debug_rendering_guard_test.dart` now fails the build if a diagnostic
flag is ever left enabled, if a source file turns one on, or if any `TextStyle`
reachable from the light or dark theme gains an underline decoration.

### Users (admin) — rebuilt around real state, not a count

- **A failed request could present itself as "0 accounts".** The screen set
  `_users = []` on error and kept rendering the empty state, so a 500, a 403 or
  a dropped connection was indistinguishable from a wiped database. There are
  now six distinct bodies — loading, loaded, empty, unauthorized, forbidden,
  network/server failure — and the account count is only ever rendered from a
  successful response.
- **Blocked accounts could not be administered at all.** The row was rendered
  with `enabled: false`, which switches off `ListTile.onTap`, and its trailing
  buttons were `onPressed: null` with a tooltip that read "Deleted user". A
  blocked account therefore could not be unblocked, edited, re-quota'd or
  deleted from the app. Rows now stay fully actionable and simply advertise the
  blocked state with a chip.
- **The list could not scroll.** The body was a non-scrollable `Column` inside
  a `RefreshIndicator`, so pull-to-refresh did nothing and a long list would
  overflow. It is now a real scrollable list.
- **Deleting was one tap away from a red bin next to a pencil.** Both are
  replaced by a single labelled contextual menu: Edit, Block/Unblock, Sign out
  everywhere, Delete.
- **Administrator protection is now enforced in the UI and in Flutter logic,
  not only on the server.** `app/lib/ui/screens/admin/admin_user_rules.dart`
  mirrors the server's three rules so a protected action is explained *before*
  anything is attempted: you cannot delete the account you are signed in with,
  and the last enabled administrator cannot be deleted, blocked or demoted.
  Selecting a protected action opens an explanation that says why and what to do
  instead. The server remains the authority and still rejects all of it.
- **A quota could be set but never cleared.** The edit dialog's empty quota
  field sent no `quota_bytes`, which the server reads as "leave unchanged".
  Clearing now sends `clear_quota: true`, so "unlimited storage" is reachable.
- Search, a count summary (`3 accounts · 1 administrator · 1 blocked`), a
  labelled Add-user action, and a first-run composition that explains the two
  roles instead of centring an icon in an empty viewport.
- The create/edit dialog now submits in place: validation errors and server
  rejections (400/409) are shown against the offending field and the dialog
  stays open, so typed input is never lost to a toast after the form closed.
- Fixed a real overflow the new widget tests caught: the role dropdown was
  `RenderFlex`-overflowing by 7.9px at 390dp.

### New server endpoint: revoke an account's sessions

`POST /api/admin/users/{id}/revoke-sessions` — signs an account out of every
device without touching its password, for a lost or shared device. Admin-only,
audited, and it returns how many sessions were revoked. Surfaced in the account
menu as **Sign out everywhere**.

### Server: the account-protection policy has one home and full test coverage

The rule lived inline in `delete_user` and `update_user` as two subtly
different SQL-count guards. It is now a single dependency-free function,
`protection_refusal(action, is_self, target_is_active_admin, active_admin_count)`,
which the handlers supply facts to and which is unit-tested on every branch
(9 new tests, 36 total, up from 27). The wire statuses are unchanged: self-
directed refusals stay `400`, structural ones stay `409`. The client-side
`AdminUserRules` mirrors exactly these three rules.

### Update centre — paused downloads are real

- `UpdateStatus.paused` is a genuine state, not a label: the downloader now
  supports **resumable downloads**. Pausing flushes and keeps the `.part` file
  and reports the checkpoint; resuming continues with an HTTP
  `Range: bytes=N-` request and re-hashes the bytes already on disk so the final
  SHA-256 still covers the whole artifact.
- Checkpoints are validated, not trusted: a `resumeFrom` that does not match the
  byte length actually on disk restarts cleanly, and a server that answers a
  ranged request with `200` and the full body is detected and restarted rather
  than appended to. Cancel still discards the partial; only pause keeps it.
- 5 new downloader tests and 3 new controller tests cover pause, resume over
  `Range` (byte-identical, checksum-valid reassembly), the ignore-Range
  recovery, the bogus-checkpoint restart, and pause → resume → `readyToInstall`.
- Fixed a bug the new golden found: a paused download was rendering an
  *indeterminate* progress bar, which both read as "still working" and animated
  forever. A paused download has a known position, so the bar is determinate.
- Fixed "Discard": it routed through `cancelDownload()`, which returns early
  because no request is in flight while paused — the button did nothing.

### Design system: empty states no longer float in a void

`OneUiEmptyState` wrapped itself in `Center`, so any screen that put it in a
page body centred its message in all remaining vertical space. On a tall phone
that is a large dead void between the header and a mid-screen icon, and it is
the shape of a failure rather than a state. The widget is now **top-anchored and
content-sized by default**, with an explicit `centered: true` opt-in used only
by the full-bleed document viewer, where centring is correct. This corrects
~15 screens at once.

### Image quality — the two root causes of "blurry photos"

Two independent defects produced the reported symptom. Both are fixed and
both are now regression-tested.

- **A swallowed decode failure left the viewer stuck on the placeholder.**
  `_decode` returned `null` on failure and the caller then *cleared* the error
  entry, so any photo the local codec could not render left the viewer sitting
  on the loading state: a dimmed grid thumbnail behind a spinner. On a phone
  that is indistinguishable from "the viewer is showing me a blurry image".
  Decoding now lives in `app/lib/services/image_decoder.dart` and raises a
  typed `ImageDecodeException` that the viewer renders as an actionable error
  with **Retry**.
- **The sampler was wrong for a minified photo.** The viewer used
  `FilterQuality.high`, which Flutter maps to Skia's *bicubic* sampler. Bicubic
  has no mipmaps, so shrinking a 4032px photo into a ~400px viewport aliased
  badly and read as soft. `ImageDecodePolicy.filterQualityForScale` now picks
  the mipmapped sampler while minifying and switches to bicubic once the image
  is at or above 1:1, so both the fitted view and the zoomed view are sharp.
- Decoding goes through `ui.ImageDescriptor` + `instantiateCodec()` with **no
  target size** for any photo up to 24 MP, so every original pixel reaches the
  GPU. Only genuinely huge photos — or a natural decode that fails on a
  low-memory device — fall back to a bounded size that is still at least 4K and
  at least twice the viewport, never a thumbnail.
- The viewer's decoded frames are budgeted (18 MP of RGBA ≈ 72 MB) and the
  frames furthest from the visible page are released first; the visible page is
  never evicted. Retry now *re-downloads* (`ImageRepository.forget`) instead of
  re-decoding the same cached bytes, which would have made the button
  incapable of ever succeeding.
- New `app/test/image_decode_policy_test.dart` — 15 assertions over the decode
  policy, the decoder (natural size preserved at a 640px viewport, huge photos
  bounded to ≥4K, undecodable bytes typed), and widget tests proving an
  undecodable original surfaces an error rather than a permanent blur, that
  Retry re-fetches, and that the placeholder is replaced by the original.

### Image quality

- **One image pipeline, two incompatible renditions.** Image handling now
  lives in `app/lib/services/image_pipeline.dart`. `ImageRendition.original`
  fetches `/api/files/download` and returns those bytes untouched;
  `ImageRendition.thumbnail` fetches the server's generated preview. Every
  cache key carries the rendition, so a thumbnail can no longer satisfy an
  original request — the class of bug behind the blurred photo viewer is now
  unrepresentable rather than merely fixed.
- Both in-memory caches are bounded by entries *and* bytes (24 MB of
  thumbnails, 96 MB of originals), and the grid decodes at tile size via
  `cacheWidth`, so browsing a large library no longer grows memory without
  limit.
- On-disk caches are keyed by **account**, not just server: two users on one
  server have identical relative paths, so the previous key let one account
  read another's cached previews on a shared device.
- Photo viewer: originals only, an explicit retryable error state instead of
  a blank frame, previous/next controls, move-to-trash, and a dimmed
  thumbnail placeholder that cannot be mistaken for the final image.
- New `app/test/image_pipeline_test.dart` — covering JPEG, PNG
  and WebP round-trips byte-for-byte, thumbnail/original key separation,
  cache bounding, graceful failure for unrenderable formats, and a widget
  test proving the viewer calls `/api/files/download` and never the
  thumbnail endpoint.
- New `scripts/verify-image-quality.sh` — 23 runtime assertions against a
  throwaway server (real 4000x3000 photo, byte-for-byte download, smaller
  thumbnail, range requests, share revocation). Now part of CI.

### Navigation and interaction correctness

- **Tab switching no longer destroys the page.** The shell rendered
  `pages[index]` inside an `AnimatedSwitcher` keyed by the index, so every tab
  change rebuilt the screen from scratch: My files forgot the folder you were
  browsing, Photos lost its scroll position, and returning to a tab re-issued
  its request. Destinations now live in a lazy `IndexedStack`, so a visited tab
  keeps its state and costs nothing until it is first opened. Covered by a test
  that asserts returning to My files does not re-list the folder.
- **Home's shortcuts now perform the action they name.** "Upload" and
  "New folder" previously only switched to the My files tab, leaving the user
  to find the button again. The shell passes a `FilesIntent` and My files runs
  it, on first open or on update. Covered by a test.
- Recent files on Home open the file itself rather than dropping the user in
  the root of My files.
- Home has a real error state. A failed load previously cleared the spinner
  and rendered nothing where the storage hero belongs — an unexplained empty
  gap instead of a message.
- Video player: the auto-hide countdown was restarted by the controller
  listener on every playback tick, so the controls never actually hid. Only
  explicit interaction resets it now.
- Audio player: the elapsed-time label was frozen while scrubbing, because
  `onChanged` was ignored. Dragging now tracks the position live.
- Photo grid: month grouping and the Files sort order are computed once per
  listing instead of inside `build`, where every arriving thumbnail re-ran a
  full sort of the library. The viewer's thumbnail lookup is now O(1) rather
  than a scan of every photo per frame.
- Session storage tolerates a platform without a secret service (headless or
  minimal Linux, where libsecret has no running keyring). Previously the
  session load could throw before the first frame, which looks exactly like a
  broken build. There is deliberately no plaintext fallback: without a keystore
  the session is memory-only and the user signs in again next launch.

### Server

- Downloads return real MIME types, advertise `Accept-Ranges`, and honour a
  single `Range` request with `206`, so video and audio seeking works. HTML,
  SVG and JavaScript are always forced to `attachment`.
- Thumbnails apply EXIF orientation, so phone photos no longer preview
  sideways.
- Sync devices record their platform; `PATCH /api/sync/devices` renames one,
  and `DELETE` revokes it. A revoked device re-registers on its next sync
  instead of failing forever.
- **Sharing honesty**: a directory can no longer be turned into a public
  link that could never resolve — the request is refused up front in favour
  of sharing with a named user.

### Fixes & polish

- **Folder navigation**: the server serializes file entries with a `kind`
  field, but the client read `type` everywhere, so every folder was treated
  as a file and tapping one offered to download/deny instead of opening it.
  `FileEntry` and the Shared/Trash screens now accept both keys — folders
  open again. (`files`, `shared browse`, `trash`)
- **Photo viewer sharpness**: images were rendered at screen resolution and
  then magnified by the zoom gesture, producing blur beyond 100%. Full
  resolution images now render inside a `FittedBox`, so zooming into the
  viewer reveals real pixels (filter quality raised across the Photos grid
  too).
- **Upload resilience**: chunks now retry automatically with 2s/5s/10s
  backoff on transient failures (network blips, 408/429/5xx) before a
  transfer needs manual attention, resuming from the server-recorded offset.
- **User management**: server gains `DELETE /api/admin/users/{id}` (removes
  the account, its files on disk, trash, shares, sync data and sessions via
  schema cascades) and `PUT /api/admin/users/{id}` now accepts an optional
  `password` that re-hashes and revokes every active session. The Users
  screen gains an Edit dialog and a Delete action with destructive
  confirmation, and was rebuilt on the One UI grouped-list pattern.
- **Update Center redesign**: the screen now leads with a single semantic
  hero (status icon, current → new version pills) that carries the live
  download progress + percentage, with quieter notices and clearer actions —
  no more stacked colored boxes.
- **Installer cache hygiene**: after a confirmed update the whole update
  cache (APK/ZIP/AppImage, stray `.part` files) is cleared, not just the
  consumed file; the "APK stays in your cache" message is gone. Thumbnail
  cache now enforces a 64 MB disk budget and evicts least-recently-used
  thumbnails.

### Update Center (application self-update)

- **Settings → About → Update Center**: check for updates, see the current
  and latest version, release date, download size, compatibility info and
  structured release notes; download and install with one action.
- Semantic version comparison (SemVer 2.0.0; prereleases sort below their
  release); older versions are never offered; optional
  `minimumSupportedVersion` triggers a mandatory-update state.
- Update source is the project's GitHub Releases via a CI-generated,
  checksum-verified manifest; URLs are restricted to HTTPS github.com;
  redirects to other hosts are rejected. ETag/Last-Modified caching with 304
  support; silent checks at most once per day; manual checks bypass the
  cache with an anti-hammer floor.
- Streaming downloads to the app-private cache with live progress,
  cancellation, retry with backoff, in-stream SHA-256 verification and
  atomic finalize-on-verify; artifacts are deleted on mismatch and never
  executed. Bounded cache (300 MB / 21 days) with automatic pruning.
- Android: verified APK handed to the system package installer via
  FileProvider (no silent install, no root); missing "install unknown apps"
  consent shows a permission state with a deep link to the per-source
  settings screen; completion confirmed on app resume. CI now **fails** a
  tag build without the release keystore.
- Windows: verified Inno Setup installer launched with user confirmation and
  OS-handled elevation.
- Linux: AppImage self-update via staged copy + atomic rename when the
  folder is writable (clear manual-replacement guidance otherwise); .deb
  offered to the system package manager — never automatic sudo.
- Robust states with actionable errors (offline, server/GitHub unavailable,
  unsupported platform/architecture, checksum mismatch, permission needed,
  cancelled) — cancel and retry paths are explicit; cancelling a mandatory
  download keeps it mandatory.
- Release pipeline: artifacts re-verified against `SHA256SUMS.txt`
  (`--strict`), manifest generated by `scripts/update-manifest.sh`, gated by
  `scripts/verify-update-manifest.py` (schema, HTTPS allowlist, sizes,
  digests, version↔tag), release notes finalized into the manifest after
  publishing (`scripts/finalize-update-manifest.sh`).
- Docs: `docs/UPDATE_SYSTEM.md` (architecture, manifest schema, security
  model, troubleshooting) and an Update Center section in
  `docs/FINAL_PRODUCTION_AUDIT.md`.
- Tests: 61 update tests (`app/test/update/`) covering semver, manifest
  parsing/rejection, download engine (mismatch/cancel/redirects), controller
  state machine and check policy; CI manifest gates negative-tested.

### Fixes

- Fixed the Linux AppImage self-replace flow never actually swapping the
  running image (the staged copy was renamed onto itself).
- Downloaded artifacts are written with sanitized flat filenames
  (path-traversal defense) and stored in the platform app-private cache
  directory (Android previously used the shared temp dir, which FileProvider
  does not expose).
- `appimagetool` no longer leaks into published release assets.
- Update-check requests no longer duplicate DNS lookups for artifacts
  (shared HTTP client, validated redirects).

## 1.1.0

- Replaced PostgreSQL with embedded SQLite.
- SQLite uses WAL mode, foreign-key enforcement and a busy timeout.
- No PostgreSQL installation or daemon is required.
- Server automatically creates the database and schema on first start.
- Added one-command local startup script that starts the server and cleans it up on exit.
- Production systemd service no longer depends on PostgreSQL.
- Restic backup now includes a transactionally consistent SQLite database snapshot.
- Updated deployment documentation and release verification for the embedded database architecture.
- Retained authentication, sharing, resumable uploads, sync, conflicts, notifications, device management and backup/restore features.

### Engineering / release pipeline

- **Portable repository:** removed machine-specific paths, hostnames and LAN
  IPs from all committed files; deploy scripts now take an install path.
- **Android application ID:** `io.nexadrive.app`; release APKs can be signed
  in CI from `KEYSTORE_BASE64` secrets (falls back to the debug key).
- **CI/CD rebuild:** all GitHub Actions pinned to commit SHAs; CI enforces
  `cargo clippy -D warnings`, version consistency (`Cargo.toml` ↔
  `pubspec.yaml` ↔ tag), and fixed secret-scan guardrails.
- **Release artifacts:** server binaries for Linux x86_64 **and** aarch64,
  Android APK, Linux AppImage + deb, and Windows ZIP + Inno Setup installer,
  each with `SHA256SUMS.txt`.
- **Client hardening:** HTTP timeouts for every API call, HTTPS-by-default
  server-URL normalization, lower image-cache budget, bounded full-size
  photo cache, and a fix for the audio viewer's hardcoded `/tmp` path.
- **Server linting:** all `clippy` warnings resolved (let-chains, removed
  needless borrows, `Reverse` sort).
