# Phase 8 — Production hardening

Phase 8 hardens NexaDrive for real-world operation while keeping user data as ordinary filesystem files.

## Security

- `CORS_ORIGINS` replaces the previous always-open CORS policy.
- Security response headers: `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`, and a restrictive `Permissions-Policy`.
- Login abuse protection blocks repeated failures for a username/IP key for a cooling window.
- Tokens remain hashed in SQLite and normal session expiry continues to apply.

## Reliability and operations

- Persistent notifications store backup failures, backup successes, and restore results.
- Sync devices can be listed and revoked.
- Desktop sync registers a stable local device name.
- Restic snapshots can be inspected from the client.
- Restic restore is deliberately non-destructive: every restore goes to `STORAGE_ROOT/.restic-restores/<timestamp>-<snapshot>`.

## Phase 7 fixes carried forward

- Restored the missing `ServerStatus` response type.
- Fixed the sync fingerprint scan timestamp scope so stale fingerprints can be removed after a complete scan.

## Safe deployment

Recommended production values:

```env
BIND_ADDR=127.0.0.1:8080
CORS_ORIGINS=https://your-trusted-origin.example
RESTIC_REPOSITORY=/backup/nexadrive-restic
RESTIC_PASSWORD_FILE=/etc/nexadrive/restic-password
```

For the intended private-cloud setup, keep the HTTP listener local and use Tailscale Serve for remote access. Do not expose port 8080 directly to the Internet.
