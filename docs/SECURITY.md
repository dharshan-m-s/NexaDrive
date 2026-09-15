# NexaDrive security

NexaDrive uses Argon2id password hashing, hashed bearer sessions, hashed public-share tokens, path/symlink protections, streamed downloads, atomic upload finalization, durable resumable transfers, and server-side quota checks. Public-share secrets are only returned at creation time and are not stored in plaintext after migration.

Authentication has a lightweight in-process login abuse limiter. For public internet deployments, place NexaDrive behind an upstream rate limiter/WAF as well. The intended deployment is private Tailscale access.

The server defaults to `127.0.0.1:8080`. Expose it through Tailscale Serve or a trusted TLS reverse proxy; do not expose the raw HTTP listener directly to the internet.

CORS is empty/restrictive by default. Configure `CORS_ORIGINS` only with known browser origins.

Restic restores are non-destructive and are written below `.restic-restores`. Keep the Restic repository and password file outside the NexaDrive storage tree.

The repository CI is the compiler/test gate. A separate penetration test is still recommended before exposing the service to an untrusted network.
