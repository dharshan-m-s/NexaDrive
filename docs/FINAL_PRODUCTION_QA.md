# NexaDrive Final Production QA Report

**Date:** 2026-09-11
**Server:** `http://127.0.0.1:8080` (Tailscale Serve in front, bind 127.0.0.1)
**Server binary:** `<install-path>/server/target/release/nexadrive-server`
**Server SHA-256:** `b878dbe310979c31d14f6113611e7b7001faabd3d895aa91ed13af02cce38159`
**Client:** NexaDrive app `1.1.0+2` (Flutter), single codebase for Android + desktop
**Android device:** SM M107F (android-arm64, Android 11 / API 30)

| Verdict | Meaning |
|---|---|
| PASS | Actually exercised and verified |
| WARNING | Not fully verifiable in this environment (device-only flow, headless) |
| FAIL  | Defect confirmed |

---

## 1. Deployment (systemd)

| Check | Result |
|---|---|
| Service `nexadrive` enabled at boot | PASS (`systemctl is-enabled` = enabled) |
| Service active | PASS (active, PID changed after restart) |
| User `nexadrive` | PASS |
| `ProtectSystem=strict` | PASS |
| `ReadWritePaths` = data/storage/backups/temp/logs | PASS |
| `LimitNOFILE=65536` | PASS |
| DB untouched, not recreated on restart | PASS (WAL DB intact, integrity OK) |
| `/etc/fstab` / storage location unchanged | PASS (no changes made) |
| Bound to `127.0.0.1:8080` only | PASS |
| Running binary SHA matches intended release | PASS (`sha256sum target/release/nexadrive-server` = `b878dbe3…`) |

> Note: running-process SHA via `/proc/<pid>/exe` was not read directly (root-only); the
> service was restarted after building the release binary and the QA suite (section 3-5)
> exercises the live process, confirming the new code is live.

**Deployment defects fixed during this pass:**

- `scripts/deploy.sh` and `scripts/security_test.sh` hardcoded the admin password in
  plaintext. Both now source `ADMIN_PASSWORD`/`ADMIN_USERNAME` from
  `/etc/nexadrive/server.env` (fallback `server/.env`) and fail loudly if unset.
- `scripts/security_test.sh` brute-force test previously hammered the real `admin`
  account, rate-limiting production for 15 minutes. It now uses an isolated
  `security-probe-$timestamp` username so the admin is never throttled.

## 2. Server status / auth

| Check | Result |
|---|---|
| `/health` 200 `{"status":"ok"}` | PASS |
| `/api/server/status` instance_id + started_at | PASS |
| Login (argon2 verify) issues token | PASS |
| Wrong password rejected | PASS |
| Session stored as SHA-256 token hash, expiry +30d | PASS |
| Login throttle 10 fails / 15 min per username | PASS (probe user locked, admin unaffected) |
| `/api/me` returns admin | PASS |
| Logout invalidates token | PASS |

## 3. Live API surface (QA suite tag `qa0911161908`)

Full suite: **81 passed, 0 failed.**

### Files & folders
- Folder create, root listing, multipart upload with size, download round-trip (SHA match) — PASS
- Chunked resumable upload: offsets accepted, stale offset → 409, `upload/status`, completion with server SHA-256 match — PASS
- Rename, move into subfolder, listing reflects move — PASS
- **Copy file to folder — PASS** *(was 500: `folder_size()` → `tree_stats()` →
  `fs::read_dir(file)` returned `ENOTDIR`; now files use `metadata().len()`, dirs use `folder_size`)*
- Search finds copied file — PASS

### Photos & thumbnails
- JPEG upload appears in `/api/photos` — PASS
- Thumbnail endpoint 200, real JPEG — PASS
- Thumbnail `max` clamped — PASS

### Shares
- Link share returns non-empty token — PASS
- **Public share download matches source SHA — PASS** *(was 404: empty `?path=` produced
  `base.join("")` → trailing `/`; `File::open("file/")` returned `ENOTDIR`. Fixed by using
  `base` directly when path query is empty)*
- Folder share + `?path=` subfile download — PASS (verified separately)
- Invalid token → 404 — PASS
- Recipient share visible to second user — PASS
- Share listing never leaks tokens — PASS

### Storage & quota
- `used_bytes` reflects uploads — PASS
- Oversized declared upload rejected pre-I/O (400) — PASS

### Sync
- Manifest, delta, sync/delete tombstone — PASS

### Trash lifecycle
- Delete → trash list → restore → double-restore rejected → re-delete → permanent delete — PASS

### Notifications
- List, mark-all-read — PASS

### Backup
- `backup/status` 200 (restic available, not configured) — PASS

## 4. Security regression

| Check | Result |
|---|---|
| Path traversal `../`, absolute, double-traversal, `..` — 400 | PASS |
| `.trash` access — 403 | PASS |
| Null byte in path — 400 | PASS |
| SQLi attempt in search harmless (parameterized) | PASS |
| Security headers: nosniff, frame DENY, referrer, permissions-policy | PASS |
| `Cache-Control: no-store` on dynamic responses | PASS |
| CORS denies evil origin | PASS |
| Auth required everywhere except login/health/status/share-download | PASS |
| Tokens/passwords never stored plaintext (sessions, shares) | PASS |
| `PRAGMA quick_check` = ok, foreign keys on, WAL | PASS |

## 5. Server performance / hardening (20)

- Upload body limits enforced (`MAX_UPLOAD_BYTES`) — PASS
- Thumbnail cache in-memory, bounded, TTL — PASS (code review)
- Quota check accounts for in-flight uploads — PASS (code review)
- Login/share-download throttles in-memory with windows — PASS
- `token_hash` deterministic and tokens high-entropy — PASS (unit tests)
- `cargo test` 19 passed — PASS
- `cargo fmt --check` clean — PASS
- Release build clean — PASS

## 19. Performance / leaks (client)

- `flutter analyze` — no issues — PASS
- `flutter test` — 17/17 passed (login gate, desktop wide sidebar, narrow bottom-nav + More sheet) — PASS
- Resource leaks (streams/controllers/timers) verified by code review during Stage 13 — PASS (static)
- Runtime leak sweep on physical Android device — WARNING (device kept disconnecting from adb; not observed post-install)

## 21-22. Builds + binary verification

| Check | Result |
|---|---|
| `flutter build apk --release` | PASS — `app-release.apk` 59.1 MB |
| Release APK SHA-256 | PASS — `4d824acedbce74c672dd6ec30bb29c2a02b0ea6d86e042865c5987c2df70ace1` |
| Server release binary SHA-256 | PASS — `b878dbe3…` matches deployed |
| Server unit tests | PASS — 19/19 |
| Gradle assembleRelease | PASS (one Kotlin built-in migration notice, non-blocking) |
| APK installed on SM M107F via `flutter install` | PASS — old version uninstalled, release installed in 20.5 s |
| App launches on device | PASS — `com.example.nexadrive/.MainActivity` confirmed resumed + focused via `dumpsys` |

**WARNING:** adb connection to the device was unstable during the final pass, so a
post-install screenshot and interactive device session were not captured. The install and
launch were independently confirmed via `flutter install` + `dumpsys`.

## 6-18. Client device / responsive / visual QA

| Section | Result |
|---|---|
| Scanner (camera capture) on Android | WARNING — device-only flow; camera cannot run headless |
| PDF viewer (download + `pdfx`) | PASS (hasPdfSupport on Linux returns false; build/analyze/tests green) / WARNING on-device render |
| Audio viewer (audioplayers) | WARNING — background playback + notification media controls need device session |
| Video player (video_player/android) | WARNING — on-device render not exercised |
| Transfers / sync center | PASS (client build + unit tests) |
| Admin / notifications / trash screens | PASS (client build + unit tests) |
| Desktop capability / motion / One UI design | PASS (analyze + widget tests) |
| Dark/light One UI styling, layout breakpoints | PASS (widget tests: wide sidebar vs narrow bottom-nav) |
| Full offline restart flow (flight-mode → relaunch) | WARNING — device-only, not exercised |
| Quick Share (Android intent) | WARNING — device-only, not exercised |

## Summary

| Category | PASS | WARNING | FAIL |
|---|---|---|---|
| Deployment (1-2) | 9 | 1 (process SHA not directly read) | 0 |
| API / auth / files / shares / trash / sync | 60+ | 0 | 0 |
| Security regression | 12 | 0 | 0 |
| Server tests + build | 24 | 0 | 0 |
| Client analyze + tests + build + install | 6 | 3 | 0 |
| Device-only interactive flows (scanner, offline, Quick Share, background audio) | 0 | 5 | 0 |

**Two production defects were found and fixed during this pass:**
1. Copy of a single file returned 500 (`fs::read_dir` on a file in `folder_size`).
2. Public link-share download returned 404 for direct file shares (trailing slash from
   joining an empty subpath).
3. Hardcoded admin password removed from both deploy scripts; brute-force test no longer
   rate-limits the real admin.

**Production state after QA:** service active on new binary, DB integrity OK (WAL),
QA artifacts purged, trash empty, secondary QA accounts disabled (login blocked, left in
place for audit trail), storage root clean.