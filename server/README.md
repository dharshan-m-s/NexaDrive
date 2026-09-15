# NexaDrive server

The NexaDrive server is a single static Rust binary packing an embedded SQLite
database and a private HTTP API. It is designed to run **inside your own
network** and, by default, binds to `127.0.0.1` — it never listens on the
public internet and the database never listens on the network at all.

- **Language / stack:** Rust (tokio + axum), SQLite via sqlx, Argon2id password
  hashing, bearer-token sessions with throttle protection.
- **Requires:** a Rust toolchain to build, no PostgreSQL, no other services.

---

## 1. Configuration

All configuration lives in `server/.env` (or `/etc/nexadrive/server.env` when
installed as a systemd service). Copy the template first:

```bash
cp server/.env.example server/.env
```

| Variable | Meaning |
|---|---|
| `DATABASE_PATH` | Path of the SQLite database file |
| `STORAGE_ROOT` | Directory where user files are stored |
| `BIND_ADDR` | Listen address. `127.0.0.1:8080` = local only (recommended); change only if you deliberately expose the server |
| `PUBLIC_URL` | **The address your clients type into the app.** There is no magic-DNS default — every network differs. On your Tailscale tailnet that is `https://<machine>.<tailnet>.ts.net`; on a LAN it might be `http://<lan-ip>:8080` or a reverse-proxy hostname. Optional — if unset, clients simply enter their address manually once. Exposed via `GET /api/server/status` |
| `ADMIN_USERNAME` | Initial administrator username (created on first boot) |
| `ADMIN_DISPLAY_NAME` | Display name for that account |
| `ADMIN_PASSWORD` | **Required on first start.** Set a long random password before the first boot and never commit it |
| `MAX_UPLOAD_BYTES` | Max request/upload body size in bytes |
| `CORS_ORIGINS` | Comma-separated origins for browser clients, or `*`. Leave empty for the native clients |
| `RESTIC_REPOSITORY` / `RESTIC_PASSWORD_FILE` / `RESTIC_BIN` | Optional restic backup integration |
| `RUST_LOG` | Log level |

> Never commit `server/.env`. It is ignored via the root `.gitignore`.

---

## 2. Build

```bash
cd server
cargo build --release
```

The binary is written to `server/target/release/nexadrive-server`.

> The **application** (client) update system is entirely separate: the
> NexaDrive app updates itself from GitHub Releases and never needs this
> server to be online. See `docs/UPDATE_SYSTEM.md`. Server releases ride the
> same tag pipeline (`docs/GITHUB_ACTIONS.md`).

---

## 3. Run from the terminal

```bash
# Build checked? Start in the foreground (Ctrl+C to stop):
export ADMIN_PASSWORD='a-long-random-password'
cargo run --release
```

Or use the bundled helper (builds on first use, waits for `/health`, stops on
Ctrl+C):

```bash
./scripts/start-nexadrive.sh
```

Stop from another terminal:

```bash
./scripts/stop-nexadrive.sh
```

---

## 4. Install as a systemd service (recommended)

The installer sets up a hardened service under the `nexadrive` user:

```bash
sudo bash deploy/install-server.sh
```

This:

1. creates the `nexadrive` service user and directory layout
   (`data/`, `storage/`, `backups/`, `temp/`, `logs/`);
2. installs `deploy/nexadrive-server.service` as `nexadrive.service`;
3. writes `/etc/nexadrive/server.env` from the template (edit `ADMIN_PASSWORD`
   and `PUBLIC_URL` **before first start**).

### Start / stop / status / logs

```bash
# Forever (enable on boot + start now)
sudo systemctl enable --now nexadrive

# Stop
sudo systemctl stop nexadrive

# Start again
sudo systemctl start nexadrive

# Restart
sudo systemctl restart nexadrive

# Status
systemctl status nexadrive

# Live logs
sudo journalctl -u nexadrive -f
```

### Health check

```bash
curl -s http://127.0.0.1:8080/health            # {"status":"ok"}
curl -s http://127.0.0.1:8080/api/server/status # instance info + PUBLIC_URL
```

---

## 5. Making the server reachable to clients

The server listens on `127.0.0.1` only. Put something in front of it that your
network can reach, and set `PUBLIC_URL` to match:

- **Tailscale (recommended for a private network):**
  `sudo tailscale serve --https=443 http://127.0.0.1:8080`
  then `PUBLIC_URL=https://<machine>.<tailnet>.ts.net`. The magic DNS name is
  specific to *your* tailnet — on another machine/network the name (and
  `PUBLIC_URL`) is different.
- **LAN reverse proxy:** point nginx/caddy at `127.0.0.1:8080`, set
  `PUBLIC_URL` to the hostname clients use.
- **Plain LAN (testing only):** change `BIND_ADDR=0.0.0.0:8080` and use
  `http://<lan-ip>:8080` as `PUBLIC_URL`. This exposes the API to every host on
  that LAN and is **not** recommended for the default private deployment.

Clients authenticate with their username/password and a bearer token;
`sessions` and share links still require the token or a valid share token,
regardless of which front-end you use.

---

## 6. Data layout

| Path | Contents |
|---|---|
| `data/nexadrive.db` (+ `-wal`/`-shm`) | SQLite database: users, shares, sessions, audit log |
| `storage/<user-uuid>/` | Actual user files (real filesystem files) |
| `storage/.trash/<user-uuid>/` | Trashed items waiting for restore/permanent delete |
| `backups/` | Restic backups (if configured) |
| `logs/`, `temp/` | Runtime logging and upload staging |

Back up `data/` and `storage/`; the two are enough to rebuild everything.

---

## 7. Security notes

- Passwords are hashed with Argon2id. Never stored in plaintext.
- Session tokens are stored hashed server-side.
- Login attempts are throttled per account (10 failures ⇒ 15 min lockout);
  share downloads are throttled too.
- The server sets strict headers (`nosniff`, `DENY` frame, no-referrer,
  `no-store` Cache-Control) on every response except opt-in thumbnail caching.
- Thumbnails (`GET /api/files/thumbnail`) are generated on the server from
  full images; uploaded originals are never rewritten.

See `docs/SECURITY_AUDIT.md` and `docs/APP_QA_CHECKLIST.md` for the full audit.