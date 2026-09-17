# Changelog

## Unreleased

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
- New `app/test/image_pipeline_test.dart` — 16 assertions covering JPEG, PNG
  and WebP round-trips byte-for-byte, thumbnail/original key separation,
  cache bounding, graceful failure for unrenderable formats, and a widget
  test proving the viewer calls `/api/files/download` and never the
  thumbnail endpoint.
- New `scripts/verify-image-quality.sh` — 23 runtime assertions against a
  throwaway server (real 4000x3000 photo, byte-for-byte download, smaller
  thumbnail, range requests, share revocation). Now part of CI.

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
