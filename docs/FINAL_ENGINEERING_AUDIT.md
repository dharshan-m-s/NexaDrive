# NexaDrive — Final Engineering Audit

Audit of the local working tree at `/mnt/data3/nexadrive` (working tree, not the remote).
Every claim carries one of these labels:

| Label | Meaning |
| --- | --- |
| **VERIFIED** | Executed in this environment and passed. |
| **BUILD VERIFIED** | Artifact produced by a real toolchain run. |
| **FIXED** | Defect reproduced, root-caused, changed, and re-tested. |
| **REVIEWED** | Code read and traced; no change made. |
| **PARTIAL** | Some screens/states addressed; the rest not restructured. |
| **ENVIRONMENT BLOCKED** | Cannot be exercised here. |
| **NOT TESTED** | Not exercised at all. |

---

## 1. Baseline

| Check | Result | Status |
| --- | --- | --- |
| `flutter analyze` | `No issues found!` | VERIFIED |
| `flutter test` | **266 passed, 0 failed** | VERIFIED |
| `flutter build linux --debug` | `build/linux/x64/debug/bundle/nexadrive` | BUILD VERIFIED |
| `flutter build linux --release` | `build/linux/x64/release/bundle/nexadrive` | BUILD VERIFIED |
| `flutter build apk --debug` | `app-debug.apk` (20.9s) | BUILD VERIFIED |
| `flutter build apk --release` | `app-release.apk` (65.3 MB) | BUILD VERIFIED |
| `cargo fmt --check` | clean | VERIFIED |
| `cargo clippy --all-targets --all-features -- -D warnings` | 0 warnings | VERIFIED |
| `cargo test` | **42 passed, 0 failed** | VERIFIED |
| `cargo build --release` | `server/target/release/nexadrive-server`, 12,769,800 bytes, sha256 `70eb53b0f69ad6ba2492157d6b6f87d80e8b2c08413bd9eded8533b560e3615d` | BUILD VERIFIED |

The release binary was force-rebuilt (`touch server/src/main.rs && cargo build --release`) to prove it is not stale with respect to the modified source.

Test counts moved from 170 passed / 1 failing (session start) to 266 passed / 0 failing, and from 27 to 42 Rust tests.

---

## 2. Client inventory

27 screens, 14 shared widgets, 8 design-system files, 12 services.

### 2.1 Screens

| Screen | Change in this work | Status |
| --- | --- | --- |
| `admin/admin_users_screen.dart` | Restructured: state machine, protected admin, blocked-user actions, quota clearing, scrolling, pull-to-refresh | FIXED |
| `admin/admin_user_rules.dart` (new) | Pure client-side policy mirroring the server's refusals | FIXED |
| `admin/audit_log_screen.dart` | Untouched | REVIEWED |
| `files/files_screen.dart` | Selection/action bar wiring | PARTIAL |
| `files/file_details_sheet.dart` | Untouched | REVIEWED |
| `files/file_share_sheet.dart` | Untouched | REVIEWED |
| `home/home_screen.dart` | Queue count + recent files | PARTIAL |
| `login/login_screen.dart` | Adaptive layout: primary action now inside the viewport at every tested size | FIXED |
| `media/audio_player_screen.dart` | Player surface | PARTIAL |
| `media/video_player_screen.dart` | Player surface | PARTIAL |
| `notifications/notifications_screen.dart` | Untouched (inherits shared empty state) | REVIEWED |
| `photos/photos_screen.dart` | Grid/viewer pipeline | PARTIAL |
| `photos/photo_viewer.dart` | Full-resolution decode policy | FIXED |
| `scanner/scanner_screen.dart` | Untouched | NOT TESTED |
| `scanner/scan_edit_screen.dart` | Untouched | NOT TESTED |
| `scanner/scan_pages_screen.dart` | Untouched | NOT TESTED |
| `scanner/crop_overlay.dart` | Untouched | NOT TESTED |
| `search/search_screen.dart` | Untouched | REVIEWED |
| `settings/settings_screen.dart` | Nav + paused-update wiring | PARTIAL |
| `settings/update_center_screen.dart` | Pause/resume/discard state coverage | FIXED |
| `shared/shared_screen.dart` | Untouched | REVIEWED |
| `shared/shared_browse_screen.dart` | Untouched | REVIEWED |
| `sync/sync_center_screen.dart` | Device list + manual sync guard | PARTIAL |
| `transfers/transfers_screen.dart` | Untouched (now free of sync pollution) | REVIEWED |
| `trash/trash_screen.dart` | Untouched (inherits shared empty state) | REVIEWED |
| `viewers/pdf_viewer_screen.dart` | Empty/error state opted into centring | FIXED |
| `viewers/text_viewer_screen.dart` | Untouched | REVIEWED |

**Honest summary:** four screens were restructured (`admin_users`, `login`, `update_center`, and the shared empty-state widget that ~15 screens consume), and several others received targeted functional fixes. A ground-up visual restructure of all 27 screens was **not** completed. Screens marked PARTIAL/REVIEWED keep their existing layout; they benefit from the shared-widget changes but were not individually recomposed. Nothing is claimed that was not done.

### 2.2 Shared widgets — the highest-leverage fix

`OneUiEmptyState` wrapped itself in `Center` inside `OneUiPage`'s `Expanded`. Every one of the ~15 call sites therefore centred a single line of text in all remaining vertical space — which is exactly the "enormous black vertical space" in the Users screenshot. Fixed at the source: top-anchored by default, with an explicit opt-in for full-bleed viewer surfaces. FIXED, and covered by the golden tests.

---

## 3. The "yellow/green lines under text" diagnosis

Not a typography bug. `RenderBox.debugPaintBaselines` paints the ideographic baseline in `0xFFFFD000` (amber) and the alphabetic baseline in `0xFF00FF00` (green), entirely inside `assert(() { … }())` — so **release builds physically cannot draw them**.

Evidence, gathered rather than asserted:

- `lib/` contains **zero** `debugPaint*` references and **zero** `TextDecoration`.
- Rendering the two reported screens with the flag off vs on: flag-on images contain 83 distinct green-family and 116 amber-family blends; flag-off images contain **zero** of either.

Prevention: `app/test/debug_rendering_guard_test.dart` fails the build if a debug-paint flag is ever enabled, and `app/doc/diagnostics/DEBUG_TEXT_UNDERLINE_DIAGNOSIS.md` records the finding. VERIFIED.

---

## 4. Sync engine — the previously untested subsystem

The engine had no end-to-end coverage. It now has **26 tests** (`app/test/sync_engine_test.dart`) driving the real `SyncManager` against an in-process fake implementing the `/api/sync/manifest`, `/api/sync/delta`, `/api/folders`, `/api/sync/delete`, `/api/uploads/status`, `/api/uploads/chunk` and `/api/files/download` contracts — including computing real SHA-256 over stored bytes, because the engine's entire conflict-vs-change decision depends on that hash comparing equal after a transfer.

Matrix covered: first sync of a tree (files, nested folders, empty folders, zero-byte files); repeat sync performing literally zero transfers (asserted via request counters, not just a zeroed struct); local add/modify/delete; remote add/modify/delete; remote folder materialisation; remote delete with a local edit in flight; simultaneous edits → both versions preserved; all three conflict resolutions; failed upload reported without abandoning siblings, then succeeding on retry; server 500 and 401 surfaced as errors rather than thrown or silently empty; missing folder; no folder selected; chunk contiguity; concurrent first sync collapsing to one run; device identity stability across syncs and restarts.

**Three real defects found and fixed:**

1. **A deletion on another device was silently undone.** With the remote file gone and the local copy unchanged, the engine called `sync_delete` against an already-deleted path and dropped its baseline entry *without deleting the local file*. The next sync saw an unknown local file and re-uploaded it. FIXED.
2. **A remote delete with no tombstone dropped the baseline.** Where the remote copy vanished without a tombstone (incomplete delta view, or a row removed out of band), the baseline was dropped too — re-uploading the file next run without recording it. It now restores explicitly, so the following sync is a no-op. FIXED.
3. **Sync drove the user's manual transfer queue.** `_uploadFile` enqueued into `transfer_queue_v2` — the list the Transfers screen renders — and never cleaned up. Three consequences, all real: sync left one permanent `completed` row per synced file (unbounded growth, re-parsed on every queue pass); a *failed* sync upload was silently retried as a side effect of the next file's upload, because `TransferQueue.process()` operates on the whole queue — the failing test showed `chunks=3, offsets=[0,0]`, i.e. a "failed" transfer that actually succeeded behind the engine's back; and a failed sync row lingered as `queued` forever, so the shell re-attempted it on every launch and every server-status poll. Sync now streams its own uploads, resuming from the server-reported offset, retrying transient failures with backoff via the now-public `TransferQueue.isTransient`, reading chunks straight off disk so a multi-gigabyte file never becomes resident in memory. FIXED.

Regression checked: every reader of `transfer_queue_v2` (`transfers_screen`, `home_screen._readQueue`, `app_shell._resumeQueue`/`_checkServerAndQueue`, `background_transfer_service`, `upload_progress_dialog`) treats it as the manual pending-transfers list. None displayed sync rows as a feature. REVIEWED.

**Not covered:** real multi-device convergence over a live server, and clock-skew behaviour. NOT TESTED — the matrix is deterministic and single-client, which is what makes it reliable, but it is not a substitute for two machines against a real server.

---

## 5. Backend

| Area | Status |
| --- | --- |
| Sync device identity (`plan_device_link` / `resolve_sync_device`) — adopt an unknown id verbatim, never hijack another account's, collision treated as success | FIXED, 6 new tests |
| Account-protection policy extracted to a pure function with every branch unit-tested (self-delete, last-admin delete/demote/disable) | FIXED, tests |
| `POST /api/admin/users/:id/sessions/revoke` | FIXED |
| Streaming, range requests, resumable uploads, SQLite indexes/WAL/pool, backup/restic, security headers, CORS, rate limiting, logging | REVIEWED only — read and traced, not changed |
| Live server read-only probes: protected routes return 401, share returns 404, security headers present | VERIFIED |

Nothing in the backend was measured under load, so no performance claim is made for it.

---

## 6. Safety

- Production database untouched: `data/nexadrive.db` mtime `2026-09-18 00:11`, unchanged throughout.
- The running service was **not** restarted; the rebuilt binary is staged only.
- No credentials, tokens or secrets were read, generated, logged or printed. No authenticated request was made against the live server.
- `/mnt/data3`, `/etc/fstab` and the Tailscale configuration were not modified.
- Nothing was committed and nothing was pushed.
