# NexaDrive security, correctness and UI audit

Audit target: Phase 9 source tree after the Phase 9 implementation, reviewed and hardened on 2026-09-06.

## Executive result

No critical remote code-execution, authentication-bypass, or path-traversal defect was found in the reviewed request paths. Several real correctness/security issues were found and fixed in this audit pass.

## Fixed findings

### High — disabled users could retain active sessions
The bearer middleware previously checked only the session row. A disabled user with an unexpired token could continue making authenticated requests. The middleware now joins `users` and requires `disabled = FALSE`.

### High — sync delta cursor used filesystem timestamps as event timestamps
The delta query compared the sync cursor to `modified_at`, which is a file property rather than a server event clock. A change to a file with an older mtime could be omitted. `sync_file_fingerprints.updated_at` was added and delta queries now use it.

### High — resumable upload total was not bounded by the upload limit
Request-body limits applied to individual chunks, but the declared `total` could exceed `MAX_UPLOAD_BYTES`. The server now rejects totals above the configured maximum before staging data.

### Medium — plaintext share tokens were stored in SQLite
New share tokens are now stored only as SHA-256 hashes. Migration logic automatically hashes legacy plaintext tokens at startup before use. The raw token is returned only at share creation time.

### Medium — client API compatibility defects
The app used `FilePicker.platform.pickFiles/saveFile`, which is inconsistent with file_picker 11's static API. These calls are now `FilePicker.pickFiles/saveFile`.

### Medium — desktop downloads buffered entire files
Desktop downloads now stream to disk through a temporary file and atomically finalize the destination, avoiding large memory spikes and partial final files.

## Security controls reviewed

- Argon2id password hashing.
- SHA-256 hashed bearer sessions.
- 30-day server-side session expiry.
- Disabled-account enforcement.
- Login throttling per normalized username.
- Path normalization rejecting absolute paths, `..`, and `.trash`.
- Symlink rejection in file operations and sync scans.
- Atomic upload staging/finalization.
- SQLite advisory locking for resumable chunks.
- Expiring recipient shares and random download-link tokens.
- Admin-only user/backup management.
- Configurable CORS, with an empty default rather than permissive browser access.
- `nosniff`, `frame-ancestors`-equivalent X-Frame-Options, referrer, permissions and no-store response headers.
- Audit logging for account, file, share, sync and backup actions.
- Systemd hardening (`NoNewPrivileges`, `ProtectSystem`, `ProtectHome`, `PrivateTmp`).

## Remaining risks / recommendations

### Medium — transport security depends on deployment
The Axum process is intentionally plain HTTP on localhost, relying on Tailscale Serve (or another trusted TLS reverse proxy) for HTTPS. Do not bind the service directly to an untrusted interface without TLS.

### Medium — brute-force protection is process-local
Login throttling is in memory and resets after a server restart. For internet-facing use, prefer an upstream rate limiter or a distributed store. The intended NexaDrive deployment is private/Tailscale-scoped.

### Medium — quota_bytes is stored but not enforced
The database has an optional per-user quota field, but upload paths do not currently enforce it. Until that feature is implemented, treat quotas as metadata rather than an effective storage limit.

### Low — public share link recovery
Because share tokens are now hashed, existing share URLs cannot be reconstructed from the database. Users should save a link when it is created; the safer design is intentional.

### Low — full Android bidirectional sync is intentionally absent
Android remains a transfer/photo-backup client rather than a full filesystem sync client.

## UI/UX audit

### Consistency
The app uses one Material 3 theme, shared card radii, shared input treatments, consistent page framing, and semantic color roles across the major screens.

### Responsive layout
Desktop uses a persistent sidebar; mobile uses a five-destination bottom navigation plus More for lower-frequency destinations. Files uses responsive list/grid modes and desktop action density without changing the underlying interaction model.

### Accessibility-oriented review
Controls use Material semantics and standard components, touch targets are generally comfortable, labels and tooltips are present on icon-only actions, and destructive actions are visually distinguished.

### Remaining polish
- Settings currently follows the system theme and does not yet expose manual Light/Dark selection.
- The Home page is intentionally simple; a future recent-files/transfer summary would make the dashboard more useful.
- Sync Center could eventually split large sections into tabs on very narrow desktop windows.

## Toolchain validation

The execution environment used for this audit does not contain Flutter/Dart/Cargo. Static source checks, route/function consistency, migration inspection, brace/parenthesis balancing, dependency/API verification and targeted code review were performed. The GitHub Actions CI remains the final compiler/test gate.

## External dependency verification

file_picker 11.0.3 uses static `FilePicker.pickFiles`, `FilePicker.getDirectoryPath`, and `FilePicker.saveFile` APIs; this matches the corrected source. citeturn620106search1turn620106search2

workmanager 0.10.9 supports Dart 3.5 and includes recent Android 16 background-execution fixes; the current dependency declaration is compatible with that minimum Dart SDK. citeturn620106search3turn620106search5
