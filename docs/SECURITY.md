# NexaDrive security

NexaDrive uses Argon2id password hashing, hashed bearer sessions, hashed public-share tokens, path/symlink protections, streamed downloads, atomic upload finalization, durable resumable transfers, and server-side quota checks. Public-share secrets are only returned at creation time and are not stored in plaintext after migration.

Authentication has a lightweight in-process login abuse limiter. For public internet deployments, place NexaDrive behind an upstream rate limiter/WAF as well. The intended deployment is private Tailscale access.

The server defaults to `127.0.0.1:8080`. Expose it through Tailscale Serve or a trusted TLS reverse proxy; do not expose the raw HTTP listener directly to the internet.

CORS is empty/restrictive by default. Configure `CORS_ORIGINS` only with known browser origins.

Restic restores are non-destructive and are written below `.restic-restores`. Keep the Restic repository and password file outside the NexaDrive storage tree.

The repository CI is the compiler/test gate. A separate penetration test is still recommended before exposing the service to an untrusted network.

## Known dependency advisories

Analyzed 2026-09-19 against the RustSec database (`cargo audit` in CI,
329 locked crates). Two entries are reported. Neither is fixed, and neither is
claimed to be fixed here.

### RUSTSEC-2023-0071 — `rsa 0.9.10`, "Marvin Attack" (medium, 5.9)

**Not compiled, not linked, not reachable.** The advisory's own solution line
reads "No fixed upgrade is available", so there is no version to move to.

`rsa` is a *lockfile-only* entry. It is an optional dependency of `sqlx-mysql`,
and the server enables `sqlx` with `default-features = false` and the `sqlite`
driver alone (`server/Cargo.toml`), so no MySQL driver is ever built. Verified:

```text
cargo tree -i rsa                       # nothing to print
cargo tree --all-features --target all -i rsa   # nothing to print
cargo tree | grep -c sqlx-mysql         # 0
ls target/{debug,release}/deps | grep -c mysql  # 0 (no artifacts)
```

The vulnerable code path is RSA PKCS#1 v1.5 decryption during a MySQL
`caching_sha2_password` handshake. NexaDrive has no MySQL driver and no MySQL
database — the index is embedded SQLite — so the path cannot be reached.

`strings nexadrive-server | grep rsa_` does match some lines; these are Rust
symbol-mangling fragments inside names such as `nexadrive_server`, not RSA code.

### RUSTSEC-2024-0436 — `paste 1.0.15`, unmaintained (informational)

A build-time proc-macro, reached through `image` → `exr`/`rav1e` → `pulp` for
AVIF/EXR encoding support. It is not part of the server's runtime request path.
This is an *unmaintained* warning, not a vulnerability: there is no known
soundness or security defect, and no drop-in replacement for the macro is
offered by the crates that depend on it.

### Why the CI job shows red

The `Dependency audit (advisory)` job in `ci.yml` runs `cargo audit` with
`continue-on-error: true` and is deliberately excluded from the gate, so these
two entries never fail the build. The job is expected to show a failure until
`rsa` gains a fixed release or `sqlx` changes how it resolves driver
dependencies. Re-evaluate on any `sqlx` upgrade.
