#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# NexaDrive — package the Flutter Linux release bundle as .deb and .AppImage.
#
# Usage:  scripts/package-linux.sh <version> [output_dir]
#
# Prereqs: an existing release bundle at app/build/linux/x64/release/bundle
#          (produce it with:  cd app && flutter build linux --release)
#          and dpkg-deb on PATH (present on Ubuntu runners / Debian systems).
#
# The AppImage tool is downloaded once into the output directory from the
# official AppImage/appimagetool continuous channel.
# ---------------------------------------------------------------------------
set -euo pipefail

VERSION="${1:?Usage: $0 <version> [output_dir]}"
OUT="${2:-dist}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="$ROOT/app/build/linux/x64/release/bundle"
ICON="$ROOT/app/linux/runner/resources/app_icon.png"
APPIMAGE_TOOL_URL="https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"

[ -d "$BUNDLE" ] || {
  echo "ERROR: Flutter Linux bundle not found at $BUNDLE." >&2
  echo "Build it first with: cd app && flutter build linux --release" >&2
  exit 1
}

mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

ARCH="x86_64"
DEB_ARCH="amd64"
DESKTOP='[Desktop Entry]
Type=Application
Name=NexaDrive
Comment=Private cloud storage for your family
Exec=nexadrive
Icon=nexadrive
Terminal=false
Categories=Utility;Network;Office;'

ICON_DIR_DEB="usr/share/icons/hicolor/256x256/apps"

# --- .deb --------------------------------------------------------------------
DEB_ROOT="$OUT/deb-root"
rm -rf "$DEB_ROOT"
mkdir -p "$DEB_ROOT/DEBIAN"
mkdir -p "$DEB_ROOT/usr/lib/nexadrive" "$DEB_ROOT/usr/bin" "$DEB_ROOT/usr/share/applications" "$DEB_ROOT/$ICON_DIR_DEB"

cp -r "$BUNDLE/." "$DEB_ROOT/usr/lib/nexadrive/"

cat > "$DEB_ROOT/usr/bin/nexadrive" <<'EOF'
#!/bin/sh
exec /usr/lib/nexadrive/nexadrive "$@"
EOF
chmod 755 "$DEB_ROOT/usr/bin/nexadrive"

printf '%s' "$DESKTOP" > "$DEB_ROOT/usr/share/applications/nexadrive.desktop"
cp "$ICON" "$DEB_ROOT/$ICON_DIR_DEB/nexadrive.png"

INSTALLED_SIZE="$(du -sk "$DEB_ROOT" | cut -f1)"
cat > "$DEB_ROOT/DEBIAN/control" <<EOF
Package: nexadrive
Version: ${VERSION}
Section: net
Priority: optional
Architecture: ${DEB_ARCH}
Maintainer: NexaDrive Project
Installed-Size: ${INSTALLED_SIZE}
Depends: libgtk-3-0 (>= 3.24)
Description: NexaDrive - private cloud storage for your family
 Self-hosted file server for photos, music and documents, with a
 Flutter client for Android, Windows and Linux. User files are stored
 as plain files on the server; the SQLite index never listens on the
 network.
EOF

dpkg-deb --build --root-owner-group "$DEB_ROOT" "$OUT/NexaDrive-$VERSION-linux-$DEB_ARCH.deb" >/dev/null
rm -rf "$DEB_ROOT"
echo "Wrote $OUT/NexaDrive-$VERSION-linux-$DEB_ARCH.deb"

# --- .AppImage ----------------------------------------------------------------
APP_DIR="$OUT/AppDir"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"

# Keep the bundle's layout on the AppDir root: the binary's $ORIGIN/lib rpath
# and its data/ resources then keep working inside the mounted AppImage.
cp -r "$BUNDLE/." "$APP_DIR/"
chmod +x "$APP_DIR/nexadrive"

printf '%s' "$DESKTOP" > "$APP_DIR/nexadrive.desktop"
mkdir -p "$APP_DIR/$ICON_DIR_DEB"
cp "$ICON" "$APP_DIR/$ICON_DIR_DEB/nexadrive.png"

# Keep the packaging tool in a scratch dir OUTSIDE the output directory:
# everything in $OUT becomes a release asset, and appimagetool (~10 MB) must
# not ship alongside the artifacts.
TOOL_DIR="$(mktemp -d)"
trap 'rm -rf "$TOOL_DIR"' EXIT
APPIMAGE_TOOL="$TOOL_DIR/appimagetool"
if [ ! -x "$APPIMAGE_TOOL" ]; then
  echo "Downloading appimagetool (continuous channel)..."
  curl -fsSL -o "$APPIMAGE_TOOL" "$APPIMAGE_TOOL_URL"
  chmod +x "$APPIMAGE_TOOL"
fi

ARCH="$ARCH" "$APPIMAGE_TOOL" --appimage-extract-and-run \
  "$APP_DIR" "$OUT/NexaDrive-$VERSION-linux-$ARCH.AppImage" >/dev/null
rm -rf "$APP_DIR"
echo "Wrote $OUT/NexaDrive-$VERSION-linux-$ARCH.AppImage"