#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# NexaDrive — generate `nexadrive-update-manifest.json` for a GitHub release.
#
# Usage:
#   scripts/update-manifest.sh <version> [prerelease] [dist_dir] [notes.json]
#
#   <version>     1.2.0 or 1.2.0-rc.1     (no leading v)
#   <prerelease>  1 when the release is a pre-release, else 0 (default)
#   <dist_dir>    directory with the release artifacts; defaults to ./dist
#   <notes.json>  optional JSON object of { "Section": ["bullet", ...] }
#                 embedded as the manifest's releaseNotes (rendered by the
#                 Update Center). Absent → empty object.
#
# Environment:
#   NEXADRIVE_RELEASE_REPO  GitHub owner/repo that hosts the release
#                           (default: dharshan-m-s/NexaDrive — the canonical
#                           production repository). Must stay on github.com —
#                           the client's host allowlist rejects any other
#                           origin.
#   NEXADRIVE_MIN_SERVER_VERSION  optional minimum server release this client
#                           works with. Client warns "update your server" when
#                           the running server is older.
#   NEXADRIVE_SERVER_API_VERSION  optional server API-surface token the client
#                           reports (e.g. the server's API_VERSION constant).
#
# The script only ever emits HTTPS URLs on github.com (the client's host
# allowlist). It validates every referenced artifact on disk (exists,
# non-empty) and embeds the exact SHA-256 the client will verify against, so
# a mangled or truncated upload cannot ship undetected.
#
# Artifact naming (must match .github/workflows/release.yml and
# docs/UPDATE_SYSTEM.md):
#   NexaDrive-<ver>.apk
#   NexaDrive-<ver>-windows-x64-setup.exe
#   NexaDrive-<ver>-windows-x64.zip
#   NexaDrive-<ver>-linux-x86_64.AppImage
#   NexaDrive-<ver>-linux-amd64.deb
# ---------------------------------------------------------------------------
set -euo pipefail

VERSION="${1:?Usage: $0 <version> [prerelease] [dist_dir] [notes.json]}"
PRERELEASE="${2:-0}"
DIST="${3:-dist}"
NOTES_FILE="${4:-}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="${NEXADRIVE_RELEASE_REPO:-dharshan-m-s/NexaDrive}"

if [[ "$DIST" = /* ]]; then
  OUT="$(cd "$DIST" && pwd)"
else
  OUT="$ROOT/$DIST"
fi

# SemVer 2.0.0 core with an optional prerelease suffix (no build metadata in
# tags: it is ignored for precedence and would only invite confusion).
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || {
  echo "ERROR: version must be MAJOR.MINOR.PATCH[-prerelease], got '$VERSION'." >&2
  exit 1
}
case "$PRERELEASE" in 0|1) ;; *) echo "ERROR: prerelease must be 0 or 1" >&2; exit 1;; esac

[[ "$NOTES_FILE" = "" || -f "$NOTES_FILE" ]] || {
  echo "ERROR: release-notes file not found: $NOTES_FILE" >&2
  exit 1
}

cd "$OUT"

# sha <file> -> lowercase sha256
sha() { sha256sum "$1" | awk '{print tolower($1)}'; }
# size <file> -> bytes
size() { stat -c %s "$1"; }

# Required client artifacts (the Release workflow uploads exactly these).
APK="NexaDrive-$VERSION.apk"
EXE="NexaDrive-$VERSION-windows-x64-setup.exe"
ZIP="NexaDrive-$VERSION-windows-x64.zip"
APPIMAGE="NexaDrive-$VERSION-linux-x86_64.AppImage"
DEB="NexaDrive-$VERSION-linux-amd64.deb"

for f in "$APK" "$EXE" "$ZIP" "$APPIMAGE" "$DEB"; do
  [ -f "$f" ] && [ -s "$f" ] || {
    echo "ERROR: required artifact missing or empty: $f" >&2
    exit 1
  }
done

if [ -n "$NOTES_FILE" ]; then
  NOTES_JSON="$(python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$NOTES_FILE" && cat "$NOTES_FILE")"
else
  NOTES_JSON="{}"
fi

MANIFEST="nexadrive-update-manifest.json"

NEXADRIVE_RELEASE_REPO="$REPO" \
NOTES_JSON="$NOTES_JSON" \
NEXADRIVE_MIN_SERVER_VERSION="${NEXADRIVE_MIN_SERVER_VERSION:-}" \
NEXADRIVE_SERVER_API_VERSION="${NEXADRIVE_SERVER_API_VERSION:-}" \
python3 - "$PRERELEASE" "$VERSION" \
  "$APK" "$(sha "$APK")" "$(size "$APK")" \
  "$EXE" "$(sha "$EXE")" "$(size "$EXE")" \
  "$ZIP" "$(sha "$ZIP")" "$(size "$ZIP")" \
  "$APPIMAGE" "$(sha "$APPIMAGE")" "$(size "$APPIMAGE")" \
  "$DEB" "$(sha "$DEB")" "$(size "$DEB")" > "$MANIFEST" <<'PY'
import json, os, sys, datetime

prerelease, version, arg = sys.argv[1], sys.argv[2], ""
args = sys.argv[3:]

def take():
    global args
    value, args = args[0], args[1:]
    return value

apk_name, apk_sha, apk_size = take(), take(), int(take())
exe_name, exe_sha, exe_size = take(), take(), int(take())
zip_name, zip_sha, zip_size = take(), take(), int(take())
ai_name, ai_sha, ai_size = take(), take(), int(take())
deb_name, deb_sha, deb_size = take(), take(), int(take())

repo = os.environ.get("NEXADRIVE_RELEASE_REPO", "dharshan-m-s/NexaDrive")
base = f"https://github.com/{repo}/releases/download/v{version}/"

def art(name, digest, bsize):
    return {"url": base + name, "sha256": digest, "size": bsize}

# Structured release notes: { "What's new": [...], "Bug fixes": [...] }.
# Rendered as inert plain-text bullets by the Update Center; never HTML.
notes = json.loads(os.environ.get("NOTES_JSON") or "{}")
if not isinstance(notes, dict):
    sys.exit("releaseNotes must be a JSON object")
clean_notes = {}
for section, items in notes.items():
    if not isinstance(items, list) or not all(isinstance(i, str) for i in items):
        sys.exit(f'releaseNotes["{section}"] must be a list of strings')
    if items:
        clean_notes[str(section)] = [i for i in items if i.strip()]

manifest = {
    "version": version,
    "tag": f"v{version}",
    "releaseDate": datetime.datetime.now(datetime.timezone.utc)
        .replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "prerelease": prerelease == "1",
    "minimumSupportedVersion": None,
    "minimumServerVersion": os.environ.get("NEXADRIVE_MIN_SERVER_VERSION") or None,
    "serverApiVersion": os.environ.get("NEXADRIVE_SERVER_API_VERSION") or None,
    "releaseNotes": clean_notes,
    "artifacts": {
        # A single universal APK is published; the client selects it for any
        # Android ABI. Keys must match AppPlatformDetector/ArchNames.
        "android": {abi: {"apk": art(apk_name, apk_sha, apk_size)} for abi in
                    ("arm64-v8a", "armeabi-v7a", "x86", "x86_64")},
        "windows": {"x64": {
            "installer": art(exe_name, exe_sha, exe_size),
            "zip": art(zip_name, zip_sha, zip_size),
        }},
        "linux": {"x64": {
            "appimage": art(ai_name, ai_sha, ai_size),
            "deb": art(deb_name, deb_sha, deb_size),
        }},
    },
}

sys.stdout.write(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
PY

# Independent gate (defense in depth): re-derive every digest from disk and
# confirm the manifest references exactly the artifacts beside it.
python3 - "$VERSION" "$MANIFEST" <<'PY'
import hashlib, json, os, sys

version, path = sys.argv[1], sys.argv[2]
with open(path) as fh:
    data = json.load(fh)

assert data["version"] == version, (data["version"], version)
assert data["tag"] == "v" + version
assert data["prerelease"] is (version.split("-")[1:] != [])

for platform, archs in data["artifacts"].items():
    assert archs, f"empty platform {platform}"
    for arch, kinds in archs.items():
        assert kinds, f"empty arch {platform}/{arch}"
        for kind, art in kinds.items():
            name = art["url"].rsplit("/", 1)[1]
            assert art["url"].startswith("https://github.com/"), art["url"]
            assert os.path.isfile(name) and os.path.getsize(name) > 0, name
            with open(name, "rb") as fh:
                digest = hashlib.sha256(fh.read()).hexdigest()
            assert art["sha256"] == digest, f"sha mismatch for {name}"
            assert art["size"] == os.path.getsize(name), f"size mismatch for {name}"

# The client requires exactly one installable artifact per platform it ships.
assert "apk" in data["artifacts"]["android"]["arm64-v8a"]
assert "installer" in data["artifacts"]["windows"]["x64"]
assert "appimage" in data["artifacts"]["linux"]["x64"]
assert "deb" in data["artifacts"]["linux"]["x64"]
print(f"Verification OK: {path} matches on-disk artifacts for v{version}")
PY

echo "Wrote $OUT/$MANIFEST"
