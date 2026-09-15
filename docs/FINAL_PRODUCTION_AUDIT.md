# FINAL PRODUCTION AUDIT

Audit date: 2026-09-14 · Deployment model: **private, single-family** ·
Target: NexaDrive 1.1.0 (fresh install of the release artifacts)

This is the operator-facing checklist for standing up a production instance
from the shipped release artifacts, plus the verified production facts of the
dev box.

---

## 1. Deployment topology (authoritative)

```
Clients (Android / Windows / Linux)
        │  HTTPS
        ▼
Tailscale Serve  (preferred)
   or trusted TLS reverse proxy (nginx/caddy)
        │
        ▼
nexadrive-server   [ binds 127.0.0.1:8080 by default ]
        ├── SQLite  data/nexadrive.db   (WAL; never on the network)
        └── user files  storage/<user-uuid>/   (real filesystem files)
```

- SQLite is **embedded**; no PostgreSQL/Docker/VM.
- The HTTP listener must never sit directly on the internet (no HTTPS on the
  raw listener; it was designed to sit behind Tailscale Serve / a proxy).
- Do **not** use Tailscale Funnel for the default private deployment.

## 2. Fresh server install

1. Put `NexaDrive-<ver>-server-linux-x86_64` (or `-aarch64`) on the host.
2. Run the installer as root (recommended):

   ```bash
   sudo bash deploy/install-server.sh /opt/nexadrive
   ```

   Creates: `nexadrive` service user, `/opt/nexadrive/{data,storage,backups,temp,logs}`,
   systemd unit `/etc/systemd/system/nexadrive.service`, and
   `/etc/nexadrive/server.env` (mode 0600, **placeholder values**).

3. **Before first start**, edit `/etc/nexadrive/server.env`:
   - `ADMIN_PASSWORD=` → long random password (Argon2id hashed on first boot).
   - `PUBLIC_URL=` → the address clients type, e.g.
     `https://<machine>.<tailnet>.ts.net` or `http://<lan-ip>:8080`.
   - Confirm `DATABASE_PATH=/opt/nexadrive/data/nexadrive.db`,
     `STORAGE_ROOT=/opt/nexadrive/storage`, `BIND_ADDR=127.0.0.1:8080`.
4. Start and verify:

   ```bash
   sudo systemctl enable --now nexadrive
   curl -s http://127.0.0.1:8080/health            # {"status":"ok"}
   curl -s http://127.0.0.1:8080/api/server/status
   ```

5. Front it: `sudo tailscale serve --https=443 http://127.0.0.1:8080`.

## 3. Client install

| Platform | Artifact | Notes |
|---|---|---|
| Android | `NexaDrive-<ver>.apk` | Sideload for first install; later updates flow through the in-app Update Center. Signed with the project keystore (tag CI fails without it). |
| Windows | `*windows-x64-setup.exe` | Inno installer (`{autopf}\NexaDrive`). Portable `*-windows-x64.zip` also available. |
| Linux | `*linux-x86_64.AppImage` or `*-linux-amd64.deb` | AppImage: `chmod +x`, run. deb: `sudo apt install ./…-linux-amd64.deb`. |

Clients enter the server URL once (remembered). Client gives `PUBLIC_URL`
guidance; a URL with no scheme defaults to **https** (an explicit
`http://` is honored for LAN deployments).

## 4. Production security facts (from `docs/SECURITY.md` and audits)

- Argon2id password hashing; **nothing stored in plaintext**.
- Session tokens stored hashed (SHA-256).
- Login throttling: 10 failures ⇒ 15-minute lockout (per account);
  share endpoints throttled.
- Security headers on every response (`nosniff`, `X-Frame-Options: DENY`,
  no-referrer, `Cache-Control: no-store` except opt-in thumbnails).
- Streamed downloads/uploads, atomic rename finalization, durable resumable
  uploads, server-side quota enforcement.
- Thumbnails generated server-side from full images; originals never
  rewritten.

## 5. Backups

- Back up `data/` (SQLite + WAL) and `storage/`; together they rebuild a
  complete instance.
- Options: filesystem-level copy (see `docs/DEPLOYMENT.md` for a
  transactional SQLite snapshot recipe) or Restic integration
  (`RESTIC_REPOSITORY`, `RESTIC_PASSWORD_FILE`, `RESTIC_BIN`).
- Restores are **non-destructive** (written below `.restic-restores`).

## 6. Dev-box production state (sanity)

- Live DB `data/nexadrive.db`: integrity check PASS (via read-only temp copy).
- Accounts: 1 admin + 6 disabled `qa-*` test accounts.
- No deployment activity was performed during this audit; production runbooks
  unchanged.

## 7. Post-deployment hygiene checklist

- [ ] Rotate `ADMIN_PASSWORD` on any machine where the pre-rotation value
      `@Home#Server_123` was ever used (the dev box qualifies).
- [ ] Confirm `server/.env` / `/etc/nexadrive/server.env` are **not** in git
      (`git ls-files | rg '(^|/)\.env$'` → empty) and never appear in CI logs.
- [ ] Smoke-test the *actual* artifacts of the first release tag: run the
      Windows installer, mount the AppImage, `dpkg -i` the deb, sideload the
      APK, `chmod +x` the aarch64 binary on ARM hardware.
- [ ] Set the CI secrets `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`,
      `KEY_ALIAS`, `KEY_PASSWORD` so future APKs are truly release-signed.
- [ ] Verify `SHA256SUMS.txt` against downloaded artifacts:
      `sha256sum -c SHA256SUMS.txt`.
- [ ] Consider an external penetration test before widening access beyond a
      trusted tailnet.

---

## 8. Update Center (application self-update)

Full design and threat model: `docs/UPDATE_SYSTEM.md`.

- **Update Center**: Settings → About → Update Center. Manual check always
  available; silent background check at most once per 24 h; a subtle Settings
  indicator appears only when an update exists. No polling loops.
- **Version detection**: SemVer 2.0.0 comparison (never lexical);
  prereleases sort below their release; older releases are never offered.
- **Release manifest**: `nexadrive-update-manifest.json` generated and
  verified by CI on every tag; schema documented in `docs/UPDATE_SYSTEM.md`;
  URLs restricted to HTTPS github.com; checksums and sizes embedded.
- **Android updates**: verified APK → system package installer via FileProvider
  content URI; user confirms in the stock dialog; no silent install, no root.
  Missing "install unknown apps" consent surfaces a permission state with a
  deep link to the per-source settings screen. Tag CI fails without the
  release keystore, so published APKs always carry the production signing
  identity.
- **Windows updates**: verified Inno Setup installer launched detached; the
  user completes it; Windows handles elevation.
- **Linux updates**: AppImage self-replace via staged copy + atomic rename
  when the folder is writable (clear guidance otherwise); .deb offered to the
  system installer / package manager — the app never runs sudo.
- **Checksum validation**: SHA-256 computed in-stream over the exact written
  bytes, compared to the manifest before anything is installed; mismatched
  downloads are deleted, never executed. Redirect hops are re-validated
  against the HTTPS github.com allowlist.
- **Security**: official-source-only URLs, sanitized flat filenames, bounded
  app-private cache (300 MB / 21 days, pruned on start and after install),
  no credentials sent to the update service, release notes rendered as
  sanitized plain text, no automatic privilege escalation.
- **Offline behavior**: distinct offline state with manual retry; a cached
  manifest (ETag/Last-Modified, 304 support) keeps last-known info visible;
  NexaDrive server availability is irrelevant to app updates.
- **Cache cleanup**: old installers/APKs/AppImages, stale `.part` files, and
  obsolete temp files removed automatically.
- **CI/CD**: version consistency (Cargo.toml ↔ pubspec.yaml ↔ tag), artifact
  re-verification (`sha256sum --check --strict`), manifest generation +
  independent verification gate, release-notes finalization; any failure
  fails the release.
- **Testing**: 61 unit tests under `app/test/update/` (semver, manifest,
  source, downloader, controller) plus negative-path coverage in the CI
  manifest verifier; mocked-HTTP integration flows; no live-GitHub
  dependency in CI.
- **Known platform limitations**: Android and Windows installs complete in
  OS-owned dialogs (user confirmation is required by the platform; the app
  reports completion on return, not silently); Linux .deb installation needs
  the user's package manager/privileges; Windows ARM64 and Linux aarch64
  desktop builds are not yet published, so those devices show an explicit
  unsupported-architecture state.

---

**Verdict: PASS with actions.** Deployment is straightforward and the
security fundamentals are in place; rotate the shared admin password and
smoke-test the untested-in-CI artifact formats at first release.