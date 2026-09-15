# NexaDrive client

Flutter app for Android, Windows and Linux. One codebase, responsive
Samsung One UI-inspired design (bottom navigation on phones, sidebar on
desktop, light/dark themes).

## Setup

```bash
cd app
flutter pub get
flutter run                # picks a connected device
flutter run -d linux       # Linux desktop
flutter run -d windows     # Windows desktop
flutter run -d <device-id> # Android device/emulator
```

## Tests

```bash
flutter analyze   # static analysis
flutter test      # unit/widget tests
```

## Live end-to-end tests

`integration_test/` contains live tests against a running server. They are
**not** part of CI. Run them with a reachable instance:

```bash
cd app
NEXADRIVE_TEST_SERVER=http://127.0.0.1:8080 \
NEXADRIVE_TEST_USERNAME=admin \
NEXADRIVE_TEST_PASSWORD=your-password \
flutter test integration_test
```

Options:

- `NEXADRIVE_TEST_SERVER` — base URL of the server (default shown above).
- `NEXADRIVE_TEST_USERNAME` / `NEXADRIVE_TEST_PASSWORD` — credentials.
- `NEXADRIVE_TEST_SCREENSHOT_DIR` — directory for `capture_test.dart`
  screenshots (default `screenshots/`).

## Building release artifacts

Release APK, Linux bundle, Windows bundle and installer are produced by the
GitHub Actions release workflow (see `docs/GITHUB_ACTIONS.md`). Locally:

```bash
flutter build apk --release   # Android; signing via app/android/key.properties
flutter build linux --release # Linux bundle; see scripts/package-linux.sh
flutter build windows --release
```

Android release signing is optional **for local builds**. Without
`app/android/key.properties` the build falls back to the Flutter debug key
(fine for sideloading, not for Play Store or for upgrades over an existing
install). CI refuses to publish a tag release without the production
keystore.

## Updating the app

The client updates itself through **Settings → About → Update Center**
(manual check, or a silent check at most once per day). It fetches a
CI-generated manifest from GitHub Releases, verifies the artifact's SHA-256,
and hands the installer to the platform (system APK installer, Inno Setup,
AppImage swap, or the package manager). Full documentation:
`docs/UPDATE_SYSTEM.md`.

## Platform setup

See `PLATFORM_SETUP.md` for detailed platform prerequisites (Android SDK,
Visual Studio, Linux toolchain).