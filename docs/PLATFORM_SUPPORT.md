# NexaDrive Platform Support

Supported platforms, install types, and the update flow per platform.

---

## Supported platforms

| Platform | Arch | Install type | Update mechanism |
| --- | --- | --- | --- |
| Android | arm64-v8a, armeabi-v7a, x86, x86_64 | APK (single universal build) | System package installer via FileProvider |
| Windows | x64 | Installed (Inno Setup) | .exe installer |
| Windows | x64 | Portable (ZIP) | Staged unpack + detached swap helper |
| Linux | x86_64 | AppImage | Atomic rename over live image |
| Linux | x86_64 | .deb | System package manager (user action required) |
| Linux | x86_64 | Source/dev build | No updates — development only |

Linux aarch64 is not currently shipped; it appears in the manifest schema for forward compatibility.

---

## How the updater detects your install type

### Windows

The updater checks these locations relative to the running `nexadrive.exe`:

| Test | Result |
| --- | --- |
| `%LOCALAPPDATA%\Programs\nexadrive` or `C:\Program Files*\NexaDrive` | Installed — offers the `.exe` installer |
| `unins*.exe` or `Uninstall NexaDrive.exe` in the app directory | Installed |
| None of the above | Portable — offers the `.zip` update |

### Linux

| Test | Result |
| --- | --- |
| `$APPIMAGE` environment variable is set | AppImage — offers atomic rename update |
| `/usr/lib/nexadrive/nexadrive` exists, or `dpkg -s nexadrive` succeeds | .deb — shows install command + "Open package" |
| Neither | Source/unknown — shows "Choose your Linux package" (AppImage/DEB buttons) |

Your choice in the package chooser is remembered for future checks.

### Android

Android is always detected as APK — the only supported install type.

---

## Windows portable update lifecycle

Because a running Windows `.exe` cannot overwrite itself, portable updates use a two-step handoff:

1. **Download** `NexaDrive-<ver>-windows-x64.zip` → verify SHA-256.
2. **Stage** the ZIP into `.nexadrive-stage-<ts>` next to the running exe.
3. **Write** `nexadrive-finish-update.cmd` (batch script):
   - Waits for the running `nexadrive.exe` to exit
   - Copies staged files over the app directory (`xcopy /Y /E`)
   - Relaunches `nexadrive.exe`
   - Deletes itself
4. **Launch** the helper detached. The Update Center shows:
   *"Download complete — restart NexaDrive to finish the update."*
5. **User exits** the app; the helper completes the swap.

**Validation**: the staged ZIP must contain `nexadrive.exe` (non-empty) and `data/flutter_assets/AssetManifest.bin`. A payload that doesn't match these markers is rejected with a clear error message.

**Failure modes**:
- Helper can't be started → Update Center stays at "ready to install" with the same message.
- Staging fails → `UpdateStatus.failed` with retryable flag.
- Incomplete swap (e.g. exe still running) → the helper waits up to 30 seconds, then aborts cleanly; the app remains functional.

---

## Linux AppImage atomic update

When running as an AppImage in a writable folder:

1. Stage a copy of the new AppImage in the same directory.
2. `chmod +x` the staged copy.
3. Rename the old image aside.
4. `rename(2)` the staged image to the live path.
5. Drop the backup.

The running binary stays valid throughout; a failure at any step rolls back to the original.

**Not writable**: the Update Center says so plainly and shows the verified file path for manual replacement.

---

## Linux .deb update

The updater downloads the `.deb` and shows:
- The package file path (copyable).
- The `sudo dpkg -i <path>` command (copyable).
- An "Open package" button (launches `xdg-open`, which on GNOME/KDE opens the Software Center).

The updater never runs `sudo` — privileged installation is left to the user's package manager.

---

## Source / development builds

If `resolveInstallationKind()` returns `InstallationKind.source` (Linux), `checkForUpdates()` immediately returns `UpdateStatus.unsupported` with the message:

> "You are running a development/source build. Install a released binary to receive updates."

No network requests are made. To get updates, build a release binary or install an AppImage/DEB.

---

## Server version compatibility

The manifest can declare `minimumServerVersion` (a SemVer). On each check the client compares this against the server's reported version (`GET /api/server/status` → `version`).

| Condition | Behaviour |
| --- | --- |
| Server version ≥ minimumServerVersion | Normal update flow |
| Server version < minimumServerVersion | A warning banner in the Update Center: *"This release needs a newer server. Update your server installation before installing this app version."* |
| Server version unknown (can't reach status endpoint) | No warning — the update is not blocked by unknown state |

This is advisory only — the updater never blocks a client update based on server state. It prevents users from pairing an incompatible client/server combination and seeing obscure errors.

---

## Timeout and stall protection

All network operations in the updater have bounded timeouts:

| Operation | Timeout | Behaviour |
| --- | --- | --- |
| Manifest fetch (body read) | 30s (HTTP-level) | `network` error, retryable |
| Manifest body read | Same window | `.timeout()` on the body stream |
| `PackageInfo.fromPlatform()` | 5s | Falls back to `0.0.0` |
| Android `resolveAbi()` channel call | 5s | Falls back to null (unknown arch) |
| Download stream | 60s idle watchdog (5s polling) | `network` error: *"The download stalled and was stopped."* |

---

## Testing the updater locally

```bash
# Full update test suite:
cd app && flutter test test/update/

# Verify manifest generation pipeline:
scripts/update-manifest.sh X.Y.Z 0 dist
python3 scripts/verify-update-manifest.py dist/nexadrive-update-manifest.json
```
