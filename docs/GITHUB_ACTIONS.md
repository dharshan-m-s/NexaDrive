# GitHub Actions: CI/CD

NexaDrive ships two workflows under `.github/workflows/`:

| Workflow | When | What it does |
|---|---|---|
| `ci.yml` | every push/PR to `main`, manual dispatch | version consistency, secret scans (gitleaks + guardrails), `flutter analyze`/`test`, Flutter Linux debug + Windows release builds, `cargo fmt`/`clippy -D warnings`/`test`, release-mode server build, advisory `cargo-audit` scan |
| `release.yml` | manual **Actions → Release → Run workflow** (you type the version) | validates the version & source, builds server binaries (Linux x86_64 + aarch64), Android release APK, Linux AppImage + deb, Windows ZIP + Inno Setup installer, and publishes a GitHub Release with `SHA256SUMS.txt` |

Both workflows bake the canonical production repository
(`dharshan-m-s/NexaDrive`) into every client binary via
`--dart-define=NEXADRIVE_UPDATE_REPO=...` so published builds check the right
release regardless of any later default change.

All third-party actions are pinned to full commit SHAs (the human-readable
tag is kept in a trailing comment). Flutter is pinned to the same version
used in development (`3.47.2`); bump `env.FLUTTER_VERSION` in both workflows
together when upgrading. The Rust toolchain is pinned to `1.98.1` in both
workflows so builds are reproducible.

## How a release is started

`release.yml` is triggered **by hand** from the GitHub UI:

**Actions → Release → Run workflow** → type the version (e.g. `1.6.0`,
`1.7.0-rc.1`, or `1.7.0+24`) and press the green button. The version you type:

- is validated as SemVer **before anything is compiled** (a malformed version,
  an already-shipped `v<version>` tag/release, or a prerelease without an
  explicit `+N` build number fails fast with a clear error),
- is injected into every build (`--build-name` / `--build-number`),
- becomes the release tag `v<version>` and the GitHub Release title,
- drives the in-app Update Center manifest so installed clients update from it.

The tag is created by the workflow's release step — you never push `v*` tags.
The `+N` suffix is **only** the Android build number / versionCode; it never
appears in the tag, the manifest, or cross-platform version strings.

Two checkboxes are offered on the form:

| Input | Default | What it does |
|---|---|---|
| `version` | — (required) | `MAJOR.MINOR.PATCH[-prerelease][+N]` to ship; see above. |
| `publish_release` | `true` | Unticking builds every artifact as a **test** run: no tag/release is created, no manifest is published, and the keystore is not required (debug-signed APK). |
| `prerelease` | `false` | Marks the GitHub Release as a pre-release (hidden from `/releases/latest`, skipped by the auto-updater). Must match the version: tick it exactly when the version has a `-suffix`. |

## Running CI locally before pushing

```bash
# Server
cd server && cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo test

# App
cd app && flutter pub get && flutter analyze && flutter test
```

## Releasing

1. Make sure the code you want to ship is pushed to the branch (usually `main`).
   The version you type on the Actions page is independent of `pubspec.yaml` /
   `Cargo.toml` — those stay at their dev defaults.
2. **Actions → Release → Run workflow** and type the version,
   e.g. `1.6.0`. For a release candidate, type `1.6.0-rc.1+21` *and* tick
   "Publish as a GitHub prerelease".
3. The workflow publishes a GitHub Release with:
   - `NexaDrive-<ver>-server-linux-x86_64`, `NexaDrive-<ver>-server-linux-aarch64`
   - `NexaDrive-<ver>.apk`
   - `NexaDrive-<ver>-linux-x86_64.AppImage`, `NexaDrive-<ver>-linux-amd64.deb`
   - `NexaDrive-<ver>-windows-x64.zip`, `NexaDrive-<ver>-windows-x64-setup.exe`
   - `nexadrive-update-manifest.json` — consumed by the in-app Update Center
   - `SHA256SUMS.txt` — checksums for every platform artifact (the manifest is
     excluded: it is re-uploaded by the finalize step after release notes are
     merged, which would make its digest stale)
4. Deploy the server binary:

   ```bash
   curl -L -o nexadrive-server \
     https://github.com/dharshan-m-s/NexaDrive/releases/download/v1.6.0/NexaDrive-1.6.0-server-linux-x86_64
   chmod +x nexadrive-server
   # put it in place and:
   sudo systemctl restart nexadrive
   ```

> **Already released?** If tag `v1.6.0` (or its release) already exists the run
> fails fast *before compiling* — enter the next version instead.

## Android signing

Add these repository secrets so release APKs are signed with the project
key, not the Flutter debug key:

| Secret | Value |
|---|---|
| `KEYSTORE_BASE64` | `base64 -w0` of your `.jks`/`.keystore` file |
| `KEYSTORE_PASSWORD` | keystore password |
| `KEY_ALIAS` | signing key alias |
| `KEY_PASSWORD` | signing key password |

On release, the workflow decodes the keystore, writes `app/android/key.properties`
from the secrets, and verifies it with `keytool -list`. If `KEYSTORE_BASE64` is
unset, a **real release** fails outright (an APK signed with a different key can
never install over an existing one), and a test run with `publish_release`
unticked warns and falls back to the debug key for testing only.

Generate a keystore locally (tools are JDK built-ins):

```bash
keytool -genkey -v \
  -keystore nexadrive-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias nexadrive
base64 -w0 nexadrive-release.jks   # -> set as KEYSTORE_BASE64
```

Both `key.properties` and `*.jks` are excluded by the root `.gitignore`.
Never commit keystores or passwords.

## Secrets management

Workflows rely on the ambient `GITHUB_TOKEN` plus the keystore secrets above.
Never put `server/.env`, tokens, passwords or real LAN IPs in the repo.

## Guardrails baked into CI

- `gitleaks` scans every push/PR/tag for accidental secrets.
- A guardrail fails if any runtime `.env` file is tracked by git.
- A guardrail fails if a live-looking `ADMIN_PASSWORD=` assignment appears in
  tracked source (placeholders like `.env.example`, docs and the installer's
  help text are excluded).
- `cargo-audit` reports known-vulnerable crates. It runs advisory-only and
  does **not** fail the pipeline — review its log occasionally.
- The root `.gitignore` keeps `data/`, `storage/`, `server/.env`, `target/`,
  `build/`, keystores, and editor files out of the repository entirely.