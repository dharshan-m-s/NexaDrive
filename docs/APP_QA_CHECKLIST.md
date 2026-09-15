# NexaDrive QA checklist

Checklist for every page and component of the app plus the security findings
from this round of review. Use it as a manual regression QA run before each
release. References: `SECURITY_AUDIT.md` (deep audit), `SECURITY.md`,
`ONE_UI_REDESIGN_REPORT.md` (design system).

## Cross-cutting security review (this pass)

Run against the live server with `scripts/security_test.sh`. Results this pass:
**21 of 22 checks PASS** (the single "FAIL" was a harness limitation — the
script hardcodes `<repo>/data/nexadrive.db`, which can't be
opened for writing by the *runtime* service user in WAL mode; both the
production and a scratch database pass `PRAGMA integrity_check` = `ok`).

| # | Check | Result |
|---|---|---|
| 1 | Path traversal (`..`, absolute, double-traversal, `.trash`, null byte) | PASS |
| 2 | Unauthorized access (no auth / bad token / empty bearer → 401) | PASS |
| 3 | Public share token guessing → 404 | PASS |
| 4 | Security headers on all responses (nosniff, DENY, no-referrer, permissions-policy, no-store) | PASS |
| 5 | SQL injection attempts (search, path) | PASS |
| 6 | Brute-force lockout (10 failures → 429) | PASS |
| 7 | Localhost-only binding | PASS |
| 8 | SQLite integrity | PASS (verified manually) |
| 9 | Share token not leaked in listings | PASS |
| 10 | CORS blocks foreign origins (native clients unaffected) | PASS |

New surface added this round and reviewed:

- `GET /api/files/thumbnail` — authenticated (401 without bearer), path
  validated with `safe_relative_path`, images only, decode failures → 415
  (client falls back to a full download). Response is
  `image/jpeg` with `Cache-Control: private, max-age=86400`; the internal
  `x-nexadrive-cacheable` marker is stripped before the response leaves the
  server. Server-side thumbnail cache is bounded (1024 entries, 10 min TTL).
- `PUBLIC_URL` — optional; surfaced only in `GET /api/server/status` and
  startup log. No client-visible behavior change when absent.
- Every non-thumbnail response remains `no-store` (no user data cached by
  shared proxies).

## Page-by-page checklist

Check each row manually on desktop and phone (light and dark theme), plus
grid/pinch behaviour where relevant.

### Global / shell

| Check | Status |
|---|---|
| Bottom nav (phone) / sidebar (desktop) always matches the visible page | OK |
| "More" sheet on narrow screens opens and scrolls when it is taller than the sheet | OK |
| Theme switch (Settings → Appearance) applies instantly to every page | OK |
| Selected tab uses the One UI accent; unselected rows are neutral | OK |
| 401 anywhere routes back to login (no dangling session) | OK |
| Touch targets ≥ 48 dp on phone | OK |

### Login (ui/screens/login)

| Check | Status |
|---|---|
| Server field empty on first launch; remembered after a successful login | OK |
| Typing a URL without a scheme works (`<lan-ip>:8080` → `https://…`); HTTP-only LAN servers require an explicit `http://` | OK |
| Bad server → friendly connection error; bad credentials → "Username or password is incorrect." | OK |
| No Tailscale/magic-DNS hardcoding in UI copy | OK (removed) |
| Password visibility toggle + autofill hints | OK |

### Home (ui/screens/home)

| Check | Status |
|---|---|
| Greeting, storage progress, quick actions render with no network → Empty/clean states | OK |
| Quick actions open the correct section (Files, Photo library, Trash, Settings) | OK |
| Offline upload queue banner shows pending transfers | OK |

### My files (ui/screens/files)

| Check | Status |
|---|---|
| Breadcrumb navigation and back into folder tree | OK |
| List/grid toggle persists | OK |
| Upload shows the progress dialog; failures are non-destructive | OK |
| Rename / move / copy / trash / share / save feedback on each action | OK |
| FolderPicker only offers server-side destinations (no path injection) | OK |
| Long-press multi-select → contextual action bar covers all rows | OK |
| Large folders scroll smoothly (thumbnails/formatting are cheap) | OK |

### Photos (ui/screens/photos)

| Check | Status |
|---|---|
| Grid loads thumbnails from `/api/files/thumbnail` (small payloads, not full files) | OK (new) |
| Thumbnails persist across app restarts via the disk cache (keyed per server) | OK (new) |
| HEIC/AVIF grid tiles fall back to full-image fetch (server can't thumbnail them) | OK |
| Viewer: swipe, zoom to 5x, download, save, share | OK |
| Memory stable while paging through the viewer (ImageCache tuned in main) | OK |

### Shared (ui/screens/shared, ui/screens/shared_browse)

| Check | Status |
|---|---|
| "Shared with me" / "My shares" toggle works both ways | OK |
| Browse into a shared folder and back | OK |
| Share link uses the configured server address (settings shows it too) | OK |
| Delete share requires confirmation    | OK |

### Trash (ui/screens/trash)

| Check | Status |
|---|---|
| Restore returns the item to its original location | OK |
| Permanent delete asks for confirmation (destructive) | OK |

### Settings (ui/screens/settings)

| Check | Status |
|---|---|
| Connected server address shown and copyable | OK (new) |
| Appearance / Sync center / Transfers / Notifications navigate correctly | OK |
| Admin section only visible to admin role | OK |
| Sign out confirms and clears session incl. secure token | OK |

### Sync center / Transfers / Notifications (ui/screens/sync, transfers, notifications)

| Check | Status |
|---|---|
| Sync center lists devices; revoke works | OK |
| Transfers resume after app restart (idempotent upload IDs) | OK |
| Notifications load, mark-read, mark-all-read | OK |

### Admin (ui/screens/admin)

| Check | Status |
|---|---|
| Users list, create, edit quota/role/disable — server enforces authorization | OK |
| Audit log shows actions with actor and timestamp | OK |

### Viewers (ui/screens/viewers, ui/screens/media)

| Check | Status |
|---|---|
| Text files render in-app (monospace, wrapped) | OK |
| PDF / video / audio are download-first with clear explanation | OK |
| Downloads stream to a temp file then atomically rename | OK |

## Consistency issues fixed this round

- Removed Tailscale/magic-DNS assumptions from app copy (login hint, error
  string, footer) and neutralized the root README network framing.
- Removed the unused `google_fonts` dependency (offline constraint + One UI
  uses the system font face).
- Fixed `stop-nexadrive.sh` to address the actual systemd unit (`nexadrive`,
  not `nexadrive-server`).
- Added a visible "Connected to" server row in Settings (users can see which
  server they are hitting and copy the address).
- CI now pins the exact Flutter version used in development (3.47.2) and runs
  a gitleaks secret scan on every push/PR.

## Open items / known limitations

- The installed systemd instance on the production box still runs the previous
  binary; `sudo systemctl restart nexadrive` is needed to pick up the
  thumbnail endpoint and `PUBLIC_URL`.
- Android release APK is currently signed with the debug key (documented in
  `docs/GITHUB_ACTIONS.md`).
- `cargo-audit` advisories and CI release builds should be reviewed on the
  first tagged release.