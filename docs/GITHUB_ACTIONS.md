# GitHub Actions: CI/CD

NexaDrive ships two workflows under `.github/workflows/`:

| Workflow | When | What it does |
|---|---|---|
| `ci.yml` | every push/PR to `main`, manual dispatch | version consistency, secret scans (gitleaks + guardrails), `flutter analyze`/`test`, Flutter Linux debug + Windows release builds, `cargo fmt`/`clippy -D warnings`/`test`, release-mode server build, advisory `cargo-audit` scan |
| `release.yml` | pushing a tag like `v1.1.0` | verifies the source, builds server binaries (Linux x86_64 + aarch64), Android release APK, Linux AppImage + deb, Windows ZIP + Inno Setup installer, and publishes a GitHub Release with `SHA256SUMS.txt` |

Both workflows bake the canonical production repository
(`dharshan-m-s/NexaDrive`) into every client binary via
`--dart-define=NEXADRIVE_UPDATE_REPO=...` so published builds check the right
release regardless of any later default change.

All third-party actions are pinned to full commit SHAs (the human-readable
tag is kept in a trailing comment). Flutter is pinned to the same version
used in development (`3.47.2`); bump `env.FLUTTER_VERSION` in both workflows
together when upgrading. The Rust toolchain is pinned to `1.98.1` in both
workflows so builds are reproducible.

## Manual (workflow_dispatch) runs

`release.yml` accepts `workflow_dispatch` for pre-release testing. Manual runs
build every artifact but **never create a GitHub Release** — the release step
and the manifest finalize step are gated to `github.ref_type == 'tag'`, so a
push to a branch cannot publish branch-suffixed junk releases. Inspect the
uploaded workflow artifacts instead.

## Running CI locally before pushing

```bash
# Server
cd server && cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo test

# App
cd app && flutter pub get && flutter analyze && flutter test
```

## Releasing

1. Bump the version consistently in three places (CI enforces the match):
   - `server/Cargo.toml` → `version = "1.2.0"`
   - `app/pubspec.yaml` → `version: 1.2.0+3`
   - a `v1.2.0` tag
2. Push the tag:

   ```bash
   git tag v1.2.0
   git push origin v1.2.0
   ```

3. The release workflow publishes a GitHub Release with:
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
     https://github.com/dharshan-m-s/NexaDrive/releases/download/v1.2.0/NexaDrive-1.2.0-server-linux-x86_64
   chmod +x nexadrive-server
   # put it in place and:
   sudo systemctl restart nexadrive
   ```

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
unset, a **tag** build fails outright (an APK signed with a different key can
never install over an existing one), and a manual `workflow_dispatch` build
warns and falls back to the debug key for testing only.

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