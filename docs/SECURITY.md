# NexaDrive security

NexaDrive uses Argon2id password hashing, hashed bearer sessions, hashed public-share tokens, path/symlink protections, streamed downloads, atomic upload finalization, durable resumable transfers, and server-side quota checks. Public-share secrets are only returned at creation time and are not stored in plaintext after migration.

Authentication has a lightweight in-process login abuse limiter. For public internet deployments, place NexaDrive behind an upstream rate limiter/WAF as well. The intended deployment is private Tailscale access.

The server defaults to `127.0.0.1:8080`. Expose it through Tailscale Serve or a trusted TLS reverse proxy; do not expose the raw HTTP listener directly to the internet.

CORS is empty/restrictive by default. Configure `CORS_ORIGINS` only with known browser origins.

Restic restores are non-destructive and are written below `.restic-restores`. Keep the Restic repository and password file outside the NexaDrive storage tree.

The repository CI is the compiler/test gate. A separate penetration test is still recommended before exposing the service to an untrusted network.

## Dependency audit

`cargo audit` in CI scans `server/Cargo.lock` against the live RustSec
database. The audit job is advisory (`continue-on-error: true`), but the lock
is kept free of actionable vulnerabilities.

The previous lock pinned `libsqlite3-sys 0.30.1`, which RustSec flags as
RUSTSEC-2026-0459 (`libsqlite3-sys` via C SQLite CVE-2026-119375, fixed in
`0.39.0`). `sqlx 0.9.1` accepts `libsqlite3-sys >=0.30.1, <0.41.0`, so the lock
now pins `0.39.0`. No application code changed: the SQLite feature set is the
same, only the bundled C SQLite sources are patched.

Two informational "unmaintained" warnings remain with no fixed upstream
release:

- `chrono 0.4.x` (RUSTSEC-2026-0543), used through `sqlx`'s optional chrono
  support.
- `paste 1.0.15` (RUSTSEC-2024-0436), a build-time proc-macro reached through
  `image` → `exr`/`rav1e` → `pulp`. It is not in the runtime request path.

These are warnings, not vulnerabilities, so `cargo audit` exits successfully.
Re-evaluate the advisory output on every `sqlx`, `chrono` or `image` upgrade.
