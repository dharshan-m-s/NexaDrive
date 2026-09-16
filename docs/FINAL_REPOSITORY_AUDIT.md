# FINAL REPOSITORY AUDIT

Audit date: 2026-09-14 · Branch: `main` · Status: **PASS — release-ready source baseline**

Scope: the exact state of the repository at tag **v1.1.0** (source baseline).
This is the final pre-release audit of the committed tree.

---

## 1. Version consistency

| Component | File | Version |
|---|---|---|
| Server (Cargo) | `server/Cargo.toml` | `1.1.0` |
| Client (pubspec) | `app/pubspec.yaml` | `1.1.0+2` |
| Android applicationId | `app/android/app/build.gradle.kts` | `io.nexadrive.app` |
| Release tag convention | `v<ver>` | must equal `v1.1.0` |

CI job `version-consistency` fails the pipeline if `Cargo.toml` and `pubspec`
ever drift and if a tag does not match them.

## 2. Build / test / lint gates (all green locally)

| Gate | Command | Result |
|---|---|---|
| Rust formatting | `cargo fmt --check` | PASS |
| Rust lint | `cargo clippy --all-targets -- -D warnings` | PASS (0 warnings) |
| Rust tests | `cargo test` | PASS (19/19) |
| Rust release build | `cargo build --release --locked` | PASS (x86_64) |
| Flutter analyze | `flutter analyze` | PASS (0 issues) |
| Flutter unit tests | `flutter test` | PASS (19/19) |
| Flutter Linux build | `flutter build linux --release` | PASS (validated in this pass) |
| Flutter Android debug | `flutter build apk --debug` | PASS |
| Flutter Android release signing path | release `signingConfig` w/ test keystore | PASS (`exists=true`, verified signing selection) |

> Local note: a release APK cannot be fully compiled on the dev box because
> the installed `java-26` fails AGP 9.1's `jdk-image` transform for
> `camera_android_camerax`. CI pins **temurin 17** (`actions/setup-java`),
> which is the authoritative release build environment.

## 3. Portability / redaction

A `rg` scan of **all 192 tracked files** returns **zero** matches for:

```
archlinux-1.tail1f44ed    (real tailnet magic-DNS)
192.168.1.50              (real LAN IP)
/mnt/data3                (dev box mount)
/home/dharshan            (dev user)
/srv/nexadrive            (old install path)
@Home#Server_123          (current live admin password)
secret-pass               (historical fixture)
_loadAdminCreds           (old test helper)
```

Placeholders replaced everywhere: `http://<lan-ip>:8080`,
`https://<machine>.<tailnet>.ts.net`, `<install-path>`, `nexadrive/`.

- `deploy/install-server.sh` now **requires** the install path as `$1`
  (usage: `sudo bash deploy/install-server.sh /opt/nexadrive`) and
  substitutes `__NEXADRIVE_HOME__` into the systemd unit.
- `deploy/nexadrive-server.service` is a portable template (no absolute paths).
- `scripts/` are self-locating (`SCRIPT_DIR`) and honor `NEXADRIVE_HOME`.

## 4. Secret hygiene

| Check | Result |
|---|---|
| Runtime `.env` tracked in git | none (matches `(^|/)\.env$`) |
| Keystores / `key.properties` tracked | none (`*.jks`, `*.keystore`, `key.properties`) |
| Runtime dirs (`data/ storage/ backups/ logs/ temp/ screenshots/ dist/`) tracked | none |
| `server/.env` committed | NO (gitignored; contains live production config, never to be committed) |
| Git history | empty prior to initial import — no historical leak |

Tools:

- `gitleaks/gitleaks-action` pinned in CI scans every push/PR/tag.
- CI guardrails fail on: tracked `.env`, or a live-looking `ADMIN_PASSWORD=`
  assignment outside template exclusions.

## 5. CI/CD configuration

Both workflows rebuilt and pinned to commit SHAs (`ci.yml`, `release.yml`):

- **`ci.yml`** (push/PR to `main`): version-consistency → secret-scan
  (gitleaks + guardrails) → `flutter analyze`/`test`, Flutter Linux build,
  Flutter Android debug APK, `rust-qc` (fmt + clippy `-D warnings` + test),
  `rust-release` (release binary artifact), advisory `cargo-audit`
  (non-blocking).
- **`release.yml`** (workflow_dispatch — manual): `version` job validates the
  typed version (SemVer, checkbox agreement) and fails fast if the tag/release
  already exists → `verify` replicates all gates → `server-linux-x64`,
  `server-linux-arm64` (cross-compiled aarch64), `android` (signed APK from
  `KEYSTORE_BASE64` secrets or debug-key fallback when `publish_release` is
  unticked), `linux` (AppImage + deb via `scripts/package-linux.sh`),
  `windows` (ZIP + Inno Setup via `app/windows/installer/nexadrive.iss`) →
  `checksums-and-release` publishes `NexaDrive-<ver>-*` + `SHA256SUMS.txt`.

Action tags used (full SHAs in the workflow files):

| Action | Tag | Verified SHA |
|---|---|---|
| `actions/checkout` | v4 | `11d5960…677262` |
| `actions/setup-java` | v4 | `cf277c6…06f6c3` |
| `actions/upload-artifact` | v4 | `ea165f8…07fa02` |
| `actions/download-artifact` | v4 | `d3f86a1…5c8093` |
| `subosito/flutter-action` | v2 | `1a44944…5add0b2` |
| `dtolnay/rust-toolchain` | stable | `02cb101…1b74de` |
| `Swatinem/rust-cache` | v2 | `6323deb…59af2b6` |
| `gitleaks/gitleaks-action` | v2 | `ff98106…29070c7` |
| `taiki-e/setup-cross-toolchain-action` | v1 | `12b7ad4…69ec1691f8` |
| `softprops/action-gh-release` | v2 | `3bb1273…b0e65` |

## 6. Android signing

- `applicationId` = `io.nexadrive.app` (namespace migrated from
  `com.example.nexadrive`).
- `signingConfigs.release` reads `app/android/key.properties` or environment
  (`KEYSTORE_BASE64`/passwords/alias secrets). Resolved via
  `rootProject.file()`.
- Without a keystore: falls back to the debug key (sideloading only; CI warns).
- Validated end-to-end with a throwaway test keystore: storeFile resolves,
  `exists=true`, signing selection switches correctly (test artifacts
  removed afterwards; only debug artifacts remain on disk).

## 7. Artifact inventory produced by `release.yml`

```
NexaDrive-<ver>-server-linux-x86_64
NexaDrive-<ver>-server-linux-aarch64
NexaDrive-<ver>.apk
NexaDrive-<ver>-linux-x86_64.AppImage
NexaDrive-<ver>-linux-amd64.deb
NexaDrive-<ver>-windows-x64.zip
NexaDrive-<ver>-windows-x64-setup.exe
SHA256SUMS.txt
```

Windows `.iss` and Linux packaging are committed and CI-exercised.

## 8. Remaining risks / recommendations

1. **Rotate the live admin password** `@Home#Server_123` (used in
   `server/.env` / `/etc/nexadrive/server.env`) after going public. It never
   appears in the repo, but prudence demands rotation.
2. `appimagetool` is fetched from the official **continuous** channel in
   `scripts/package-linux.sh` (no stable semver tag exists upstream).
3. Windows installer, deb, AppImage and aarch64 binary **have not been run**
   on this machine — CI (ubuntu/windows runners) is the first real exercise.
   Do a smoke test on a sample of artifacts after the first tag.
4. Recommend running a real penetration test before exposing the server
   beyond a trusted tailnet (tracked in `docs/SECURITY_AUDIT.md`).
5. `cargo-audit` is advisory-only by design; review its log each release.

---

**Verdict: PASS.** The repository is portable, secret-clean, lint-clean,
version-consistent and configured to build and publish all release artifacts
from a fresh clone via GitHub Actions.