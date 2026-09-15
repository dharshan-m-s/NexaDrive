# NexaDrive Deployment Guide

## Architecture

```
Internet → Tailscale (HTTPS) → localhost:8080 (Axum)
                                       |
                                  SQLite (WAL)
                                       |
                                  <install-path>/storage
```

- **Server:** Rust/Axum binary bound to `127.0.0.1:8080`
- **TLS:** Tailscale Serve terminates TLS; Funnel is NOT used
- **Database:** SQLite with WAL mode, 5 connection pool, 10s busy timeout
- **Service:** systemd manages the process

> Throughout this guide `<install-path>` is wherever the NexaDrive directory
> lives (the reference production machine keeps it on a dedicated data disk).
> The repo is portable — copy it anywhere and pass the location as the first
> argument to `deploy/install-server.sh`.

## Filesystem Layout

```
nexadrive/
├── AGENTS.md              # Engineering rules
├── CHANGELOG.md           # Version history
├── README.md              # Project overview
├── .github/workflows/     # CI/CD pipelines (ci.yml, release.yml)
├── app/                   # Flutter client source
├── server/                # Rust server source + binary
│   ├── src/main.rs        # Server source
│   ├── migrations/        # SQLite migrations
│   ├── .env               # Dev environment config (0600)
│   ├── .env.example       # Config template
│   └── target/release/    # Compiled binaries
├── data/
│   └── nexadrive.db       # SQLite database
├── storage/               # User files (per-user UUID dirs)
│   ├── .trash/            # Soft-deleted files
│   └── {uuid}/            # User storage
├── backups/               # Restic backup destination (optional)
├── scripts/               # Deployment and utility scripts
├── deploy/                # Deployment templates
├── docs/                  # Documentation
└── temp/                  # Temporary files
```

## systemd Service

**Live unit:** `/etc/systemd/system/nexadrive.service`  
**Template:** `deploy/nexadrive-server.service`

```ini
[Unit]
Description=NexaDrive private cloud server
After=network-online.target
Wants=network-online.target
# RequiresMountsFor=<data-disk-mount>   # uncomment when data lives on its own disk

[Service]
Type=simple
User=nexadrive
Group=nexadrive

WorkingDirectory=<install-path>/server
EnvironmentFile=/etc/nexadrive/server.env
ExecStart=<install-path>/server/target/release/nexadrive-server

Restart=on-failure
RestartSec=3

NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true

ReadWritePaths=<install-path>/data
ReadWritePaths=<install-path>/storage
ReadWritePaths=<install-path>/backups
ReadWritePaths=<install-path>/temp
ReadWritePaths=<install-path>/logs

LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```

### Hardening Features
- **NoNewPrivileges:** Process cannot gain privileges
- **PrivateTmp:** Isolated /tmp namespace
- **ProtectSystem=strict:** Root filesystem is read-only
- **ProtectHome:** /home, /root, /run/user are not accessible
- **ReadWritePaths:** Explicitly whitelist only necessary directories
- **RequiresMountsFor:** (used when the data disk is a separate mount) ensures it is mounted before starting

## Tailscale

```bash
# Verify Tailscale Serve is active
tailscale serve status

# Expected output:
# https://<machine>.<tailnet>.ts.net (tailnet only)
# |-- / proxy http://127.0.0.1:8080
```

Tailscale Funnel is NOT used. The server is only accessible from within the tailnet.

## Secrets Management

| Secret | Location | Permissions | Status |
|--------|----------|-------------|--------|
| Admin password | `/etc/nexadrive/server.env` | 0600 root:root | Implemented |
| Admin password (dev) | `server/.env` | 0600 user:user | Implemented |
| Session tokens | SQLite (SHA-256 hashed) | Database-level | Implemented |
| Share tokens | SQLite (SHA-256 hashed) | Database-level | Implemented |
| Restic password | `/etc/nexadrive/restic-password` | 0600 root:root | Documented, not configured |

- Never commit `.env` files to version control
- Production secrets come from environment variables
- API tokens are 64-char random alphanumeric, SHA-256 hashed before storage

## Backup

### Current Status

**Documented but NOT configured.** The Restic integration is implemented in the server code but the required environment variables are commented out in `/etc/nexadrive/server.env`.

### Prerequisites

1. **Restic installed:** `/usr/bin/restic` (v0.19.1 — verified installed)
2. **Backup repository:** A directory or remote location for restic to store snapshots
3. **Password file:** A file containing the restic repository password

### Required Environment Variables

Add to `/etc/nexadrive/server.env`:

```bash
# Path to the restic repository (directory, SFTP, S3, etc.)
RESTIC_REPOSITORY=/path/to/backup/repository

# Path to a file containing the restic repository password
RESTIC_PASSWORD_FILE=/etc/nexadrive/restic-password

# Path to restic binary (optional, defaults to "restic")
RESTIC_BIN=/usr/bin/restic
```

### Recommended Backup Storage

- **NOT on the same disk** as your NexaDrive data — a disk failure would destroy both data and backups
- Recommended: A separate mounted volume, NAS, or off-machine target (SFTP, S3-compatible)
- Example: `RESTIC_REPOSITORY=ssh:backup-host:/backups/nexadrive-restic`
- The `backups/` directory under `<install-path>/` is available for local testing but does NOT protect against disk failure

### Backup Safety (Implemented and Verified)

The backup implementation is production-safe:

1. **SQLite snapshot consistency:** `VACUUM INTO` creates a transactionally consistent snapshot before restic reads files
2. **Exclusions:** `.trash` directory and `**/.nexadrive-upload-*` temp files are excluded
3. **Non-destructive restore:** Restored files go to a new timestamped directory; no live files are overwritten
4. **Snapshot ID validation:** Only alphanumeric characters, hyphens, and underscores; max 128 chars
5. **No command injection:** No user-controlled strings are interpolated into shell commands
6. **Temp snapshot cleanup:** The `.nexadrive-db-backup-*.db` file is removed after backup completes

### Backup Commands

**Via API (admin only):**

```bash
# Authenticate
TOKEN=$(curl -s -X POST http://127.0.0.1:8080/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"YOUR_PASSWORD"}' | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")

# Run backup (without pruning)
curl -X POST http://127.0.0.1:8080/api/backup/run \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"prune": false}'

# Run backup with pruning (applies retention policy)
curl -X POST http://127.0.0.1:8080/api/backup/run \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"prune": true}'

# List snapshots
curl http://127.0.0.1:8080/api/backup/snapshots \
  -H "Authorization: Bearer $TOKEN"

# Verify backup (checks 5% data subset)
curl -X POST http://127.0.0.1:8080/api/backup/check \
  -H "Authorization: Bearer $TOKEN"

# Restore a snapshot (non-destructive, creates new directory)
curl -X POST http://127.0.0.1:8080/api/backup/restore \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"snapshot_id":"SNAPSHOT_ID"}'

# Check backup configuration status
curl http://127.0.0.1:8080/api/backup/status \
  -H "Authorization: Bearer $TOKEN"
```

**Via restic directly (for disaster recovery):**

```bash
export RESTIC_REPOSITORY=/path/to/repository
export RESTIC_PASSWORD_FILE=/etc/nexadrive/restic-password

# List snapshots
restic snapshots

# Restore a snapshot
restic restore SNAPSHOT_ID --target /tmp/nexadrive-restore

# Verify repository integrity
restic check --read-data-subset=5%
```

### Retention Policy (When Pruning Is Enabled)

| Policy | Value |
|--------|-------|
| Keep last | 7 snapshots |
| Keep daily | 14 days |
| Keep weekly | 8 weeks |
| Keep monthly | 12 months |

### What Must NOT Be Backed Up Unnecessarily

- `<install-path>/server/target/` — compiled binaries (regenerable from source)
- `<install-path>/app/build/` — Flutter build artifacts (regenerable)
- `<install-path>/storage/.trash/` — deleted files (excluded by restic)
- `<install-path>/storage/**/.nexadrive-upload-*` — temp upload files (excluded by restic)

The backup implementation already excludes `.trash` and upload temp files.

## Logging

### Current Mechanism

**Implemented and verified.** All logs go to systemd journal (stdout/stderr via `tracing-subscriber`).

### Journal Configuration

The system uses default journald settings. For production, consider adding to `/etc/systemd/journald.conf`:

```ini
[Journal]
# Retain 30 days of logs, cap at 500M
SystemMaxUse=500M
SystemMaxRetentionSec=30day
MaxFileSec=1day
```

Then restart: `sudo systemctl restart systemd-journald`

### Log Commands

```bash
# View recent logs
journalctl -u nexadrive -n 50

# Follow logs in real time
journalctl -u nexadrive -f

# View logs since last boot
journalctl -u nexadrive -b

# View disk usage
journalctl --disk-usage
```

### Status

**Currently documented but not configured.** The default journald settings are in use. The recommended retention settings above are for operator consideration — they are NOT automatically applied.

## Rate Limiting

### Current Implementation

**Implemented and verified.** In-memory rate limiting for:

- Login: 10 failures per username per 15-minute window
- Public share downloads: 30 failures per token hash per 15-minute window

### Appropriate For

The current in-memory implementation is appropriate for:
- Single-instance deployment behind Tailscale Serve
- Personal cloud with a small number of users
- The Tailscale network boundary provides additional protection

### Future Requirements

If NexaDrive becomes multi-instance (e.g., behind a load balancer):
- Rate limiting must move to a shared store (Redis, SQLite with TTL columns)
- Or a reverse proxy rate limiter should be used
- The current implementation does NOT prevent distributed brute-force across restarts

## Deployment

### Deploy New Release

```bash
cd <install-path>
bash scripts/deploy.sh deploy
```

This will:
1. Build the release binary
2. Run tests
3. Save the current binary as backup
4. Restart the service
5. Run health check and authenticated smoke test
6. Roll back automatically if checks fail

### Rollback

```bash
bash scripts/deploy.sh rollback
```

### Health Check

```bash
bash scripts/deploy.sh health
```

### CI/CD Pipeline

GitHub Actions workflows in `.github/workflows/`:
- **ci.yml:** Runs on push/PR — flutter analyze, test, build; rust fmt, check, test, build; dependency audit; secret scanning
- **release.yml:** Runs on tag push — builds all targets, creates GitHub release with artifacts and SHA-256 checksums

### Deployment Validation

After deployment, verify:
1. `curl http://127.0.0.1:8080/health` returns `{"status":"ok"}`
2. Login succeeds and returns a token
3. Security headers are present
4. Traversal attempts are rejected
5. Database integrity check passes

## Recovery Procedure

1. **Service won't start:** `journalctl -u nexadrive -n 50`
2. **Database corruption:** `sqlite3 data/nexadrive.db 'PRAGMA integrity_check;'`
3. **Binary issues:** `bash scripts/deploy.sh rollback`
4. **Full recovery:** Restore from restic backup (see Backup section)
5. **Disk issues:** stop the service and unmount the data filesystem
   (`sudo systemctl stop nexadrive`, `sudo umount <data-disk-mount>`), then run
   `e2fsck`/`fsck` on the device before remounting and starting again.
