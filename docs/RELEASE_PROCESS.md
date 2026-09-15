# NexaDrive Release Process

How releases are built, verified, and published.

---

## Prerequisites

- A clean working tree on `main` (or `main-rc` for pre-releases).
- Both `app/pubspec.yaml` version and `server/Cargo.toml` version must match exactly — CI fails otherwise.
- For production Android: `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, and `KEY_PASSWORD` must be set as GitHub Actions secrets.

---

## 1. Bump versions

Update both files to the same `MAJOR.MINOR.PATCH[-prerelease]`:

- `app/pubspec.yaml` → `version: X.Y.Z+N` (the `+N` build number increments independently)
- `server/Cargo.toml` → `version = "X.Y.Z"`

Update `CHANGELOG.md` with a section for the new version.

---

## 2. Tag and push

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

This triggers `.github/workflows/release.yml` which:

1. Verifies version agreement across `pubspec.yaml`, `Cargo.toml`, and the git tag.
2. Runs `cargo fmt --check`, `cargo clippy -D warnings`, `cargo test`.
3. Runs `flutter analyze` and `flutter test`.
4. Builds the server binary (x86_64 + aarch64), Android APK, Linux AppImage/DEB, Windows ZIP/EXE.
5. Generates `SHA256SUMS.txt` and `nexadrive-update-manifest.json`.
6. Verifies every artifact hash and URL against the on-disk artifacts.
7. Publishes everything as a GitHub Release.

---

## 3. Android signing (CI only)

The release workflow creates `app/android/key.properties` from CI secrets at build time:

```
storePassword = <KEYSTORE_PASSWORD>
keyPassword   = <KEY_PASSWORD>
keyAlias      = <KEY_ALIAS>
storeFile     = /tmp/release.keystore
```

The keystore is decoded from `KEYSTORE_BASE64` and deleted after the build. A debug-signed APK is never published from a tag release. Manual `workflow_dispatch` builds skip the keystore check and produce debug-signed APKs suitable for sideload testing only.

---

## 4. Manifest pipeline

`scripts/update-manifest.sh` (called by CI and usable locally):

```bash
# Produce a manifest for a tagged release with all artifacts in ./dist:
scripts/update-manifest.sh X.Y.Z 0 dist release-notes.json

# Optional: specify a minimum server version requirement:
NEXADRIVE_MIN_SERVER_VERSION="1.2.0" \
NEXADRIVE_SERVER_API_VERSION="1.0.0" \
scripts/update-manifest.sh X.Y.Z 0 dist
```

`scripts/verify-update-manifest.py` runs immediately after and fails the release if any artifact is missing, empty, mismatched in hash or size, or hosted outside the `github.com` allowlist.

For manual local testing, the verifier skips the git-tag check when `GITHUB_REF_NAME` is unset.

---

## 5. Version compatibility

The manifest can declare two server-side compatibility fields:

| Field | Meaning |
| --- | ---|
| `minimumServerVersion` | The oldest server release the client version can talk to. Compared against `GET /api/server/status` → `version`. The Update Center warns (never blocks) if the server is older. |
| `serverApiVersion` | The server's API surface contract token (`/api/server/status` → `api_version`). For future use; currently informational. |

Set them via environment variables when calling `scripts/update-manifest.sh`:

```bash
NEXADRIVE_MIN_SERVER_VERSION="1.2.0" \
scripts/update-manifest.sh X.Y.Z 0 dist
```

---

## 6. Local pre-release testing

```bash
# Build the desktop binary:
cd app && flutter build linux --release && cd ..

# Package the AppImage/DEB:
scripts/package-linux.sh X.Y.Z dist

# Generate the manifest (point at a test repo):
NEXADRIVE_RELEASE_REPO=your-user/nexadrive-test \
scripts/update-manifest.sh X.Y.Z 0 dist

# Verify it:
python3 scripts/verify-update-manifest.py dist/nexadrive-update-manifest.json

# Point the client at the test repo:
# Settings → Developer → Update repo → your-user/nexadrive-test
# Or: --dart-define=NEXADRIVE_UPDATE_REPO=your-user/nexadrive-test
```

---

## 7. Post-release

- Monitor the GitHub Release page for download counts.
- The `finalize-update-manifest.sh` script (used by CI) re-uploads the manifest after GitHub auto-generates the release notes body.
- If a critical regression is found, yank the release on GitHub (revoke the tag) and issue a patched version — the Update Center will pick up the new manifest on the next check.
