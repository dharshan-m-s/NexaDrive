#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# NexaDrive — finalize the update manifest with real release notes.
#
# Usage:
#   scripts/finalize-update-manifest.sh <version> <tag> <owner/repo>
#
# Environment:
#   GH_TOKEN  GitHub token with `contents: write` on the release (CI supplies
#             github.token).
#
# Runs AFTER the GitHub release exists (the Release workflow calls this as its
# last tag-only step). It:
#   1. reads the published release body (curated sections + auto-generated
#      "What's Changed"),
#   2. converts it into the manifest's structured releaseNotes
#      (What's new / Improvements / Bug fixes / Security / Performance),
#   3. merges them into the published `nexadrive-update-manifest.json` asset
#      without touching versions, URLs, checksums or sizes,
#   4. re-validates the merged manifest against the on-disk artifacts before
#      re-uploading it.
#
# The client renders notes as inert plain-text bullets — never HTML — so the
# transformation is cosmetic, not a security boundary.
# ---------------------------------------------------------------------------
set -euo pipefail

VERSION="${1:?Usage: $0 <version> <tag> <owner/repo>}"
TAG="${2:?Usage: $0 <version> <tag> <owner/repo>}"
REPO="${3:?Usage: $0 <version> <tag> <owner/repo>}"

[ -f "dist/nexadrive-update-manifest.json" ] || {
  echo "ERROR: dist/nexadrive-update-manifest.json not found (run from repo root)." >&2
  exit 1
}

AUTH=(-H "Authorization: Bearer ${GH_TOKEN:?GH_TOKEN is required}" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2026-03-10")

RELEASE_JSON="$(mktemp)"
trap 'rm -f "$RELEASE_JSON" notes.json' EXIT

curl -fsSL "${AUTH[@]}" \
  "https://api.github.com/repos/$REPO/releases/tags/$TAG" -o "$RELEASE_JSON"

# 1+2. Parse the release body into structured notes.
python3 - "$RELEASE_JSON" notes.json <<'PY'
import json, re, sys

with open(sys.argv[1], encoding="utf-8") as fh:
    release = json.load(fh)
body = release.get("body") or ""

KNOWN = ("What's new", "Improvements", "Bug fixes", "Security", "Performance")
sections: dict[str, list[str]] = {k: [] for k in KNOWN}
current: str | None = None
in_downloads = False

for raw in body.splitlines():
    line = raw.strip()
    if not line:
        continue
    if line.startswith("## "):
        title = line[3:].strip()
        if title.lower() == "downloads":
            in_downloads, current = True, None
            continue
        in_downloads = False
        current = next((k for k in KNOWN if k.lower() == title.lower()), None)
        continue
    if line.startswith("#"):  # top-level title / "What's Changed"
        title = line.lstrip("#").strip()
        in_downloads = False
        current = ("What's new" if title.lower() in ("what's changed", "changes")
                   else next((k for k in KNOWN if k.lower() == title.lower()), None))
        continue
    if in_downloads or line.startswith("**Full Changelog**"):
        continue
    item = re.sub(r"^[-*]\s+", "", line)
    # Auto-generated PR bullets end with " by @user in #123".
    item = re.sub(r"\s+by @[\w-]+ in #\d+$", "", item)
    if not item:
        continue
    (sections[current] if current else sections["What's new"]).append(item)

notes = {k: v for k, v in sections.items() if v}
with open(sys.argv[2], "w", encoding="utf-8") as fh:
    json.dump(notes, fh, ensure_ascii=False)
print(f"Parsed release notes: {sum(len(v) for v in notes.values())} items in {len(notes)} section(s)")
PY

# 3. Merge notes into the manifest (versions/URLs/checksums untouched).
python3 - dist/nexadrive-update-manifest.json notes.json <<'PY'
import json, sys

manifest_path, notes_path = sys.argv[1], sys.argv[2]
with open(manifest_path, encoding="utf-8") as fh:
    manifest = json.load(fh)
with open(notes_path, encoding="utf-8") as fh:
    notes = json.load(fh)
manifest["releaseNotes"] = notes
with open(manifest_path, "w", encoding="utf-8") as fh:
    json.dump(manifest, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
PY

# 4. Re-validate against the artifacts before publishing the merged asset.
(
  cd dist
  GITHUB_REF_NAME= python3 ../scripts/verify-update-manifest.py nexadrive-update-manifest.json
)

ASSET_ID="$(python3 -c '
import json, sys
with open(sys.argv[1]) as fh:
    release = json.load(fh)
for asset in release.get("assets", []):
    if asset["name"] == "nexadrive-update-manifest.json":
        print(asset["id"])
        break
' "$RELEASE_JSON")"
[ -n "$ASSET_ID" ] || { echo "ERROR: manifest asset not found on the release." >&2; exit 1; }

curl -fsSL -X DELETE "${AUTH[@]}" \
  "https://api.github.com/repos/$REPO/releases/assets/$ASSET_ID"

UPLOAD_URL="$(python3 -c '
import json, sys
with open(sys.argv[1]) as fh:
    release = json.load(fh)
print(release["upload_url"].split("{")[0])
' "$RELEASE_JSON")"

curl -fsSL -X POST "${AUTH[@]}" \
  -H "Content-Type: application/octet-stream" \
  --data-binary "@dist/nexadrive-update-manifest.json" \
  "$UPLOAD_URL?name=nexadrive-update-manifest.json" > /dev/null

echo "Manifest finalized: release notes embedded and re-uploaded for $TAG."
