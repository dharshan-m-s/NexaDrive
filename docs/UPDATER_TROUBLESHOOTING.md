# NexaDrive Update Troubleshooting

Detailed guide for diagnosing and fixing updater issues per platform.

---

## Android

### "Permission needed" / "Install unknown apps"

Android blocks installs from non-store sources by default.

1. Tap the "Open settings" button in the Update Center.
2. In **Settings → Install unknown apps → NexaDrive**, toggle **Allow from this source**.
3. Return to NexaDrive and tap **Install** again.

This is a per-source consent; it does not affect other apps.

### "App not installed" after the system dialog

The APK was not signed with the same key as the currently installed copy, or the `applicationId` doesn't match.

- **Release APKs** must be signed with the production keystore (`io.nexadrive.app`). CI handles this automatically when `KEYSTORE_BASE64` is set.
- **Debug/testing APKs** installed from `workflow_dispatch` use a debug key and will not upgrade a production install. Uninstall first (user data will be lost).

### Download stalled / "The download stalled and was stopped"

The 60-second idle watchdog detected no data flow. Causes:
- Network went offline mid-download.
- GitHub rate-limited the connection.
- A VPN/proxy is dropping the connection.

Tap **Try again** — the manifest is re-fetched before downloading.

### "SHA-256 mismatch" / "The file was corrupted"

The downloaded bytes don't match the manifest digest. The partial file is deleted automatically. Tap **Try again**. If it recurs, a proxy or firewall may be modifying the response.

### "Version didn't change" after installing

The update installed correctly but you're still looking at the old process. **Fully exit** NexaDrive (swipe it away from the app switcher) and relaunch it.

---

## Windows — Installed (Inno Setup)

### Installer didn't appear

The `.exe` was downloaded but Windows SmartScreen or UAC may have blocked it silently.

1. Open the **Update Center** → **Release details** → note the file path.
2. Navigate to that path in Explorer and double-click the `.exe`.
3. If SmartScreen shows "Windows protected your PC", click **More info → Run anyway** (the file is SHA-256 verified by the app before launch).

### "Windows has protected your PC" (SmartScreen)

SmartScreen flags unsigned or rarely-downloaded executables. The NexaDrive installer is code-signed in CI. If you see this, you're running a fresh or manually-built copy. Click **More info → Run anyway**.

### Update installed but version shows old

The installer completed but the old process was still running. **Exit NexaDrive completely** (check the system tray), then relaunch.

### Start Menu entry disappeared after update

The Inno Setup installer recreates the shortcut on upgrade. If it's missing:
- Re-run the installer from the Update Center → it's safe to run over an existing install.
- Or create a new shortcut manually: right-click `nexadrive.exe` → **Pin to Start**.

---

## Windows — Portable (ZIP)

### "Download complete — restart NexaDrive to finish the update"

This is the normal state after a successful portable update download. Exit the app; the background helper (`nexadrive-finish-update.cmd`) completes the swap and relaunches automatically.

### Helper didn't run / still shows "ready to install"

If the batch helper couldn't be started (e.g. antivirus blocked it):

1. Open the **Update Center** → **Release details** → note the staged folder path (`.nexadrive-stage-*` next to your `nexadrive.exe`).
2. Manually extract the contents over your `nexadrive` folder, replacing all files.
3. Delete the `.nexadrive-stage-*` folder.

### "Not a valid NexaDrive payload"

The downloaded ZIP doesn't contain `nexadrive.exe` at the root, or the `data/flutter_assets/AssetManifest.bin` marker is missing. This means the URL pointed at a non-NexaDrive ZIP. The file is deleted; the download will be retried from a fresh manifest fetch.

### Portable update stalled (download watchdog)

The 60-second idle watchdog detected no data flow. Tap **Try again** — the network connection will be re-established.

---

## Linux — AppImage

### "The AppImage folder is not writable"

The live AppImage sits in a read-only directory (e.g. `/opt` or a system mount).

- Move the AppImage to `~/Applications` or another writable path, then retry.
- Or update manually: download the new `.AppImage` from the Update Center link and `chmod +x` it over the old file.

### Update replaced the AppImage but it won't launch

The `chmod +x` or `rename(2)` may have failed partway. Check:
- `ls -la` the AppImage — it should be executable (`-rwxr-xr-x`).
- If not: `chmod +x /path/to/NexaDrive-*.AppImage`

### Running from a read-only mount (Live USB, Snap, Flatpak)

The AppImage update path requires a writable parent. On a read-only mount, the Update Center will show the verified file path for manual replacement. Consider installing to `~/Applications` on a persistent partition.

---

## Linux — .deb

### `sudo dpkg -i` fails with dependency errors

Install dependencies first:
```bash
sudo apt update && sudo apt install -f
```
Then retry the `dpkg -i` command. Alternatively, use `gdebi`:
```bash
sudo gdebi NexaDrive-*.deb
```

### "Open package" button does nothing

`xdg-open` may not have a handler for `.deb` files on your desktop environment. Install the package manually:
```bash
sudo dpkg -i /path/to/NexaDrive-*.deb
```

### Update Center still says "deb ready" after installing

The updater detects the deb path from the filesystem check. After installing, restart NexaDrive — the next launch will re-detect the installation type.

---

## Source / development builds

### "You are running a development/source build"

This appears when the updater detects `InstallationKind.source` (Linux) or cannot determine the install type. To receive updates:

1. **Build a release binary**: `flutter build linux --release`
2. **Or install an AppImage/DEB** from the GitHub Releases page.

Development builds are not tracked by the update manifest and will never auto-update.

---

## Server version warnings

### "This release needs a newer server"

The manifest declares `minimumServerVersion` and your server is older. To resolve:

1. Note the minimum version shown in the Update Center.
2. Update the NexaDrive server binary to at least that version.
3. Restart the server.
4. Return to the Update Center — the warning will clear on the next check.

This is advisory only: the client update is not blocked, but installing it against an old server may cause API errors.

---

## Network / offline issues

### "No internet connection"

- Check your network connection.
- If on a corporate network, ensure `github.com` and `*.githubusercontent.com` are not blocked.
- The updater uses the same HTTP client as the rest of the app — no separate network stack.

### "The update server returned HTTP 403"

GitHub is rate-limiting the manifest request (unauthenticated, 60 req/hour). Wait and retry. The silent auto-check backs off for 24 hours after a failure.

### "The update server returned HTTP 404"

No releases exist yet, or the repo name is wrong. Check **Settings → Developer → Update repo** (must be `owner/repo` format).

### Manifest check succeeds but download fails repeatedly

- GitHub may be throttling large artifact downloads.
- Try downloading the artifact manually from the GitHub Releases page and placing it in the app's cache directory.
- Check available disk space — the updater needs roughly the artifact size free.

---

## Clearing the update cache

The updater stores downloads in the platform's app-private cache directory:

- **Android**: `<app-cache>/nexadrive_updates/`
- **Linux**: `~/.cache/nexadrive/updates/`
- **Windows**: `%LOCALAPPDATA%\nexadrive\cache\updates\`

To clear all cached update data, delete the contents of these directories. The next check will re-download the manifest.

---

## Getting help

If none of the above resolves the issue:

1. Check `CHANGELOG.md` for known issues in the current version.
2. File an issue at the project's GitHub Issues page with:
   - NexaDrive version (`Settings → About`)
   - Platform and OS version
   - The exact error message from the Update Center
   - Whether you're running an installed, portable, AppImage, or deb build
