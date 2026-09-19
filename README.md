<p align="center">
  <img src="applogo.png" alt="NexaDrive logo" width="140"/>
</p>

# NexaDrive

A private personal cloud/file server for Android, Windows and Linux.

[![Download NexaDrive](https://img.shields.io/badge/Download-NexaDrive-0066ff?style=flat&logo=github&logoColor=white)](https://github.com/dharshan-m-s/NexaDrive/releases/latest)

Grab the newest pre-built bundles (APK, Windows installer, Linux AppImage/deb,
server binaries) from the **Releases page** — the badge opens the latest
release. The in-app Update Center upgrades installed clients from the same
release automatically.

## Architecture

```text
Android / Windows / Linux
          │
       Flutter
          │ HTTPS
          ▼
 Your network edge
 (Tailscale Serve, a reverse proxy, or a LAN — your choice)
          │
          ▼
    Rust + Axum API
       │       │
       │       └── SQLite: users, sessions, metadata
       │
       └──────── filesystem: real files
```

The server binds to `127.0.0.1` by default and the SQLite database never
listens on the network. You control how clients reach it — Tailscale is an
optional convenience, not a dependency. There is **no built-in VPN** and no
hardcoded network/DNS default: the address clients use is configured through
`PUBLIC_URL` in `server/.env` (see `server/README.md`).

## Current implementation

This repository is a complete runnable MVP foundation:

- Rust/Axum server
- Embedded SQLite metadata database (no PostgreSQL service)
- Argon2id password hashing
- Random bearer sessions with SHA-256 token storage
- User/admin bootstrap
- File/folder listing
- Folder creation
- Multipart file upload
- File download
- File deletion to Trash
- Trash restore/permanent delete
- Rename, move and copy
- Recursive server-side search
- Batch file actions
- Persisted grid/list view preference
- File-type aware UI
- Storage usage endpoint
- Audit log table
- CORS and request body limit
- Systemd service
- Optional Tailscale Serve / reverse proxy exposure (no hardcoded DNS)
- Flutter Android/Windows/Linux client
- One UI-inspired responsive design
- Light/dark mode
- Search/filter UI
- GitHub Actions checks
- In-app Update Center with manifest-based auto-updates (Android APK, Windows EXE/ZIP, Linux AppImage/deb)

## Release status

**NexaDrive 1.1.0** is the finalized source baseline for the current project scope. It includes authentication, file management, trash, sharing, photos, resumable transfers, desktop sync, conflict handling, notifications, device management, Restic backup/restore, quota enforcement, appearance preferences and GitHub Actions release automation.

For deployment and security requirements, see [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md)
and [`docs/SECURITY.md`](docs/SECURITY.md).

## Installation overview

| Component | Command / artifact | Notes |
|---|---|---|
| Server binary | `NexaDrive-<ver>-server-linux-x86_64` (or `-aarch64`) | Single static binary; no PostgreSQL. |
| Systemd install | `sudo bash deploy/install-server.sh /opt/nexadrive` | Creates `nexadrive` user, dirs, service and env template. |
| Android APK | `NexaDrive-<ver>.apk` | Signed with project keystore in CI; releases refuse to build without it. Updates via the in-app Update Center. |
| Windows installer | `NexaDrive-<ver>-windows-x64-setup.exe` | Inno Setup; also `*-windows-x64.zip` for a portable bundle. |
| Linux desktop | `NexaDrive-<ver>-linux-x86_64.AppImage` / `*-linux-amd64.deb` | See `scripts/package-linux.sh`. In-app updates via the Update Center. |

---

## 1. Server prerequisites

PostgreSQL is **not required**. NexaDrive uses an embedded SQLite database, so there is no database daemon to keep running and no PostgreSQL service to start/stop.

Install only the server toolchain:

```bash
sudo pacman -S --needed rustup
rustup default stable
```

The server automatically creates its SQLite database and storage directories on first start.

## 2. Configure server

```bash
cd server
cp .env.example .env
```

Edit `.env`:

```env
DATABASE_PATH=./data/nexadrive.db
STORAGE_ROOT=./storage
BIND_ADDR=127.0.0.1:8080
ADMIN_USERNAME=admin
ADMIN_DISPLAY_NAME=Administrator
ADMIN_PASSWORD=CHANGE_THIS_TO_A_LONG_PASSWORD
```

The admin password is only used when the database has no users yet. SQLite uses WAL mode and a busy timeout for safe concurrent client/server access.

## 3. Run server manually

```bash
cd server
cargo run
```

Health:

```bash
curl http://127.0.0.1:8080/health
```

## 4. Run through systemd

The installer creates the `nexadrive` user, directory layout, systemd unit
and `/etc/nexadrive/server.env` (edit that file **before** first start to set
`ADMIN_PASSWORD` and `PUBLIC_URL`):

```bash
sudo bash deploy/install-server.sh /opt/nexadrive
```

Then:

```bash
sudo systemctl enable --now nexadrive
sudo systemctl status nexadrive
journalctl -u nexadrive -f
```

Start / stop / restart:

```bash
sudo systemctl start nexadrive
sudo systemctl stop nexadrive
sudo systemctl restart nexadrive
```

## 5. Reach the server from your devices

The server intentionally binds to localhost by default. Pick one way to put it
in front of your network and set `PUBLIC_URL` in the env file to match.

### Option A: Tailscale (recommended for private networks)

```bash
sudo tailscale serve --https=443 http://127.0.0.1:8080
tailscale serve status
```

Clients then connect to `https://<machine>.<tailnet>.ts.net`. That magic-DNS
name is specific to *your* tailnet — compute it from `tailscale serve status`,
never assume the same name elsewhere. Do NOT use Tailscale Funnel for this
private server.

### Option B: LAN reverse proxy

Point nginx/caddy at `127.0.0.1:8080` and set `PUBLIC_URL` to the hostname you
configure (`https://cloud.example.com` or `http://<lan-ip>:8080`).

### Option C: Plain LAN (testing only)

`BIND_ADDR=0.0.0.0:8080` with `PUBLIC_URL=http://<lan-ip>:8080`. This exposes
the API to the whole LAN — not recommended for the default private deployment.

## 6. Flutter client

Install Flutter, then:

```bash
cd app
flutter pub get
flutter run
```

Linux:

```bash
flutter run -d linux
```

Windows:

```bash
flutter run -d windows
```

Android:

```bash
flutter devices
flutter run -d <device-id>
```

The login screen asks for:

- Server URL — the address of *your* server. It is remembered on later launches,
  so you only type it once. A bare hostname is accepted and assumed HTTPS; an
  HTTP-only LAN server must be typed with its scheme (`http://<lan-ip>:8080`).
- Username
- Password

All three are validated on the device before anything is sent, so a mistyped
address is reported as a form error rather than surfacing as a network failure.

Example (a Tailscale tailnet; your name will differ):

```text
https://<machine>.<tailnet>.ts.net
```

## 7. GitHub Actions

CI (`ci.yml`) runs formatting, analyzer, tests and builds for the Flutter app
and `cargo fmt/check/test`, Rust dependency audits and a gitleaks secret scan.
Releases (`release.yml`) are created from the Actions page — no tag-pushing:
**Actions → Release → Run workflow**, type the version you want to ship
(e.g. `1.6.0`), tick "Publish as a GitHub prerelease" for an RC, and CI compiles
every format, verifies it, and publishes a GitHub Release you can download.
See `docs/GITHUB_ACTIONS.md`.

## Design direction

The client uses a Samsung One UI-inspired visual language:

- large readable headers
- generous spacing
- rounded surfaces
- comfortable touch targets
- bottom navigation on phones
- sidebar navigation on desktop
- light/dark themes
- responsive layouts

The supplied Apple Design Skill repository is used as a cross-platform UX review methodology, not as the visual language. Its README explicitly describes it as framework-agnostic and usable with Flutter, with guidance covering layout, accessibility, typography, motion, search, settings and other UX areas.

Design skill:
https://github.com/dickwu/apple-design-skill

## Data layout

```text
<install>/storage/
└── <user UUID>/
    ├── Documents/
    ├── Photos/
    └── ...
```

Database stores metadata and security state; the filesystem stores the actual file bytes.

## Recovery principle

The storage directory is intentionally ordinary filesystem data. Do not manually rename user UUID directories while the server is running. For backup, the server ships a Restic integration (`/api/backup/*`, driven from the app's Settings screen): configure `RESTIC_REPOSITORY` and `RESTIC_PASSWORD_FILE` and set `RESTIC_BIN` if `restic` is not on `PATH`.

## API

Every request is authenticated with a bearer session token except the health
probe, the server status endpoint, login, and a public share link:

```text
GET  /health
GET  /api/server/status
POST /api/auth/login
GET  /api/share/{token}/download

Authorization: Bearer <session-token>
```

The rest of the surface covers files and folders, resumable uploads, Trash,
photos, sharing (named users and public links), desktop sync, notifications,
account administration, audit logging and Restic backups.

**The full endpoint contract — every route, its parameters, status codes and
path-safety rules — is in [`docs/API.md`](docs/API.md).**

## Documentation

The current reference docs are:

- [`docs/API.md`](docs/API.md) — the complete HTTP contract.
- [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) — server deployment, storage layout, Tailscale Serve.
- [`docs/SECURITY.md`](docs/SECURITY.md) — the security model and product rules.
- [`docs/UPDATE_SYSTEM.md`](docs/UPDATE_SYSTEM.md) — updater architecture, manifest schema, security model.
- [`docs/UPDATER_TROUBLESHOOTING.md`](docs/UPDATER_TROUBLESHOOTING.md) — updater error diagnosis and fixes.
- [`docs/PLATFORM_SUPPORT.md`](docs/PLATFORM_SUPPORT.md) — supported platforms, install types, per-platform update flows.
- [`docs/RELEASE_PROCESS.md`](docs/RELEASE_PROCESS.md) — how releases are built, verified, and published.
- [`docs/GITHUB_ACTIONS.md`](docs/GITHUB_ACTIONS.md) — the CI/CD workflows.

`docs/README.md` indexes the rest, including the historical build logs
(`docs/PHASE*.md`) and the point-in-time audit snapshots, which are kept as a
record of how the project got here rather than as current specifications.

## 1.1.0 release

This tag is the finalized source baseline for the current feature scope.
See [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) for deployment and security
details and [`docs/GITHUB_ACTIONS.md`](docs/GITHUB_ACTIONS.md) for how CI/CD
produces the release artifacts.
