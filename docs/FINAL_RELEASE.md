# NexaDrive 1.1.0

NexaDrive 1.1.0 is the self-contained release baseline.

## Architecture

- Flutter Android/Windows/Linux client
- Rust/Axum server
- Embedded SQLite metadata database
- Ordinary filesystem storage
- Tailscale/Tailscale Serve for private networking
- Restic for optional backups

PostgreSQL is not required and no database daemon is part of the deployment.

## Startup model

The server creates its SQLite database, schema and storage directories automatically on first start. For local development use:

```bash
./scripts/start-nexadrive.sh
```

For a production server use the supplied systemd service. The service starts only NexaDrive; there is no PostgreSQL dependency.

## Mount/unmount rule

Stop NexaDrive before unmounting the data filesystem (the mount containing its database and storage). SQLite WAL mode may keep `*.db-wal` and `*.db-shm` files beside the database while the process is active.

## Backup

Restic backups include the normal storage and a consistent SQLite database snapshot. Restic restore remains non-destructive and restores into `.restic-restores`.

## Update Center

The client updates itself in place across Android (APK), Windows (installed `.exe` and portable ZIP), and Linux (AppImage atomic swap and `.deb`). The update system is fully independent of the NexaDrive server; the client validates everything against a signed-off, SHA-256-pinned manifest fetched from GitHub Releases.

Key properties:

- **One manifest** (`nexadrive-update-manifest.json`) drives all platforms; every artifact is pinned by SHA-256 and size, and re-verified on-disk at download time.
- **Install-type detection** picks the correct install mechanism per copy of the app (Windows installed vs portable; Linux AppImage vs deb vs source).
- **Bounded network**: manifest body reads, version probes, and download streams all have hard timeouts; a 60 s idle watchdog aborts stalled downloads instead of hanging forever.
- **Server compatibility**: the manifest may declare `minimumServerVersion`/`serverApiVersion`; the Update Center compares them with the live server's status and warns the user (never blocks).
- **No privilege escalation**: no silent install, no sudo, no security-setting changes. The Update Center hands off to the OS package installer/manager in every flow.
- **Updater tests**: `app/test/update/` (97+ Flutter tests) plus the release-manifest verifier run in CI on every commit; only real published releases ship a manifest.

See `docs/UPDATE_SYSTEM.md` for the architecture, `docs/PLATFORM_SUPPORT.md` for per-platform flows, `docs/UPDATER_TROUBLESHOOTING.md` for diagnosis, and `docs/RELEASE_PROCESS.md` for the release procedure.
