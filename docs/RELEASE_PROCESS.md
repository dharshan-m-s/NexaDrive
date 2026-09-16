# NexaDrive Release Process

How releases are built, verified, and published.

---

## Prerequisites

- A clean working tree on `main` (or any branch whose code you want to ship).
- The version is chosen in the GitHub UI when you start the workflow — it is
  **not** read from `pubspec.yaml` / `Cargo.toml` (those keep dev defaults).
- For a production Android APK: `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`,
  `KEY_ALIAS`, and `KEY_PASSWORD` must be set as GitHub Actions secrets
  (a real release without them is refused).

---

## 1. Choose the version

Releases are `MAJOR.MINOR.PATCH` with an optional `-prerelease` suffix and an
optional `+N` build number:

| Form | Meaning |
| --- | --- |
| `1.6.0` | final release → tag `v1.6.0`, versionCode `1006000` (derived) |
| `1.6.0+24` | final release with Android versionCode `24` |
| `1.7.0-rc.1+21` | pre-release → tag `v1.7.0-rc.1`, versionCode `21` (must be explicit) |

Only `+N` is a build number; it never appears in the tag or cross-platform
version strings. A `-prerelease` version **must** carry an explicit `+N` so its
versionCode cannot collide with the final release, and it must be released with
the "Publish as a GitHub prerelease" checkbox ticked.

Add a `CHANGELOG.md` section for the new version before starting the run.

---

## 2. Start the release

**Actions → Release → Run workflow** on the branch you want to ship
(usually `main`), type the version, and run it. This triggers
`.github/workflows/release.yml` which:

1. Validates the version (SemVer, prerelease checkbox agreement, versionCode
   derivation) and fails fast if tag `v<version>` or its release already
   exists — all **before** anything is compiled.
2. Runs `cargo fmt --check`, `cargo clippy -D warnings`, `cargo test`.
3. Runs `flutter analyze` and `flutter test`.
4. Builds the server binary (x86_64 + aarch64), Android APK, Linux AppImage/DEB,
   Windows ZIP/EXE — injecting the typed version into every build.
5. Generates `SHA256SUMS.txt` and `nexadrive-update-manifest.json`.
6. Verifies every artifact hash and URL against the on-disk artifacts.
7. Creates the `v<version>` tag and publishes everything as a GitHub Release.

A test run (untick `publish_release`) compiles every artifact but creates no
tag, release, or manifest — files land in the run's workflow-artifacts tab.

---

## 3. Android signing (CI only)

The release workflow creates `app/android/key.properties` from CI secrets at build time:

```
storePassword = <KEYSTORE_PASSWORD>
keyPassword   = <KEY_PASSWORD>
keyAlias      = <KEY_ALIAS>
storeFile     = /tmp/release.keystore
```

The keystore is decoded from `KEYSTORE_BASE64` and deleted after the build. A debug-signed APK is never published from a real release. A test run with `publish_release` unticked skips the keystore check and produces debug-signed APKs suitable for sideload testing only.

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

On CI the verifier is pointed at the release tag explicitly
(`GITHUB_REF_NAME=v<version>`). For manual local testing, the verifier falls
back to `git describe` when `GITHUB_REF_NAME` is unset.

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
