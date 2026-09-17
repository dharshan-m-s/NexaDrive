#!/usr/bin/env bash
# NexaDrive image-quality end-to-end verification.
#
# Traces ONE real high-resolution photo through the same path the apps use:
#
#   generate -> upload -> storage -> /api/photos -> /api/files/thumbnail
#            -> /api/files/download -> byte/format assertions
#
# It starts a throwaway server (own temp database, storage and port), so it
# never touches a real deployment, and it exits non-zero if any link of the
# chain loses quality.
#
# Requirements: the release binary (or `cargo build --release`), curl, python3,
# and ImageMagick (`convert`) or `magick` to author the fixture. If neither is
# available the script falls back to a committed sample photo.
#
# Usage: scripts/verify-image-quality.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${NEXADRIVE_BIN:-$REPO_ROOT/server/target/release/nexadrive-server}"
PORT="${QA_PORT:-18099}"
BASE="http://127.0.0.1:$PORT"
ADMIN_USER="qa-admin"
ADMIN_PASS="qa-image-$RANDOM-$RANDOM-long-enough"

TMP="$(mktemp -d)"
PASS=0
FAIL=0
SERVER_PID=""

cleanup() {
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT

ok()  { PASS=$((PASS + 1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1 ${2:-}"; }
check() { # desc expected actual
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "(expected=$2 actual=$3)"; fi
}

if [ ! -x "$BIN" ]; then
  echo "Building the release server binary..." >&2
  (cd "$REPO_ROOT/server" && cargo build --release --locked) || {
    echo "FAIL: could not build the server" >&2; exit 1; }
fi

echo "=== NexaDrive image-quality verification ==="
echo ""

# ---------------------------------------------------------------- fixture
SRC="$TMP/original.jpg"
if command -v convert >/dev/null 2>&1; then
  convert -size 4000x3000 plasma:fractal \
    -quality 94 -sampling-factor 4:4:4 "$SRC" 2>/dev/null
elif command -v magick >/dev/null 2>&1; then
  magick -size 4000x3000 plasma:fractal -quality 94 "$SRC" 2>/dev/null
else
  SRC="$(ls "$REPO_ROOT"/storage/*/IMG-*.jpg 2>/dev/null | head -1)"
  [ -n "$SRC" ] || { echo "FAIL: no way to create a test image" >&2; exit 1; }
  echo "  (ImageMagick unavailable; using $SRC)"
fi

read -r SRC_W SRC_H < <(python3 - "$SRC" <<'PY'
import struct, sys
# Minimal JPEG SOF parser: enough to read width/height without dependencies.
data = open(sys.argv[1], 'rb').read()
i = 2
while i < len(data) - 9:
    if data[i] != 0xFF:
        i += 1
        continue
    marker = data[i + 1]
    if marker in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB):
        h, w = struct.unpack('>HH', data[i + 5:i + 9])
        print(w, h)
        break
    if marker in (0xD8, 0xD9) or 0xD0 <= marker <= 0xD7:
        i += 2
        continue
    seg = struct.unpack('>H', data[i + 2:i + 4])[0]
    i += 2 + seg
PY
)
SRC_SHA=$(sha256sum "$SRC" | awk '{print $1}')
SRC_BYTES=$(stat -c%s "$SRC")
echo "  Fixture: ${SRC_W}x${SRC_H}, $SRC_BYTES bytes, sha256 ${SRC_SHA:0:12}..."
echo ""

# ------------------------------------------------------------ throwaway server
mkdir -p "$TMP/data" "$TMP/storage"
(
  cd "$TMP" || exit 1
  DATABASE_PATH="$TMP/data/nexadrive.db" \
  STORAGE_ROOT="$TMP/storage" \
  BIND_ADDR="127.0.0.1:$PORT" \
  ADMIN_USERNAME="$ADMIN_USER" \
  ADMIN_DISPLAY_NAME="QA" \
  ADMIN_PASSWORD="$ADMIN_PASS" \
  RUST_LOG=warn \
  "$BIN" >"$TMP/server.log" 2>&1 &
  echo $! >"$TMP/server.pid"
)
SERVER_PID="$(cat "$TMP/server.pid")"

for _ in $(seq 1 60); do
  if [ "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/health" 2>/dev/null)" = "200" ]; then
    break
  fi
  sleep 0.5
done
if [ "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/health")" != "200" ]; then
  echo "FAIL: the QA server did not start; log follows" >&2
  cat "$TMP/server.log" >&2
  exit 1
fi
ok "throwaway server is up on port $PORT"

TOKEN=$(curl -s -X POST "$BASE/api/auth/login" \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASS\"}" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin).get("token",""))')
[ -n "$TOKEN" ] && ok "authenticated" || { bad "authenticated"; exit 1; }

AUTH=(-H "Authorization: Bearer $TOKEN")

# ----------------------------------------------------------------- upload
UP_CODE=$(curl -s -o "$TMP/upload.json" -w '%{http_code}' \
  -X POST "$BASE/api/files/upload" "${AUTH[@]}" \
  -F "path=" -F "upload_id=$(uuidgen 2>/dev/null || echo qa-upload-1)" \
  -F "file=@$SRC;filename=qa-original.jpg")
check "upload succeeds" "200" "$UP_CODE"

LIST=$(curl -s "$BASE/api/files" "${AUTH[@]}")
echo "$LIST" | grep -q 'qa-original.jpg' \
  && ok "uploaded file is listed" || bad "uploaded file is listed"

# --------------------------------------------------- original byte fidelity
curl -s -o "$TMP/downloaded.jpg" -D "$TMP/download.headers" \
  "$BASE/api/files/download?path=qa-original.jpg" "${AUTH[@]}"
DL_SHA=$(sha256sum "$TMP/downloaded.jpg" | awk '{print $1}')
DL_BYTES=$(stat -c%s "$TMP/downloaded.jpg")

[ "$DL_SHA" = "$SRC_SHA" ] \
  && ok "download returns the ORIGINAL bytes byte-for-byte (sha256 match)" \
  || bad "download returns the ORIGINAL bytes" "(src=$SRC_SHA dl=$DL_SHA)"
check "download preserves the byte count" "$SRC_BYTES" "$DL_BYTES"

read -r DL_W DL_H < <(python3 - "$TMP/downloaded.jpg" <<'PY'
import struct, sys
data = open(sys.argv[1], 'rb').read()
i = 2
while i < len(data) - 9:
    if data[i] != 0xFF:
        i += 1
        continue
    marker = data[i + 1]
    if marker in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB):
        h, w = struct.unpack('>HH', data[i + 5:i + 9])
        print(w, h)
        break
    if marker in (0xD8, 0xD9) or 0xD0 <= marker <= 0xD7:
        i += 2
        continue
    seg = struct.unpack('>H', data[i + 2:i + 4])[0]
    i += 2 + seg
PY
)
check "download keeps the original width" "$SRC_W" "$DL_W"
check "download keeps the original height" "$SRC_H" "$DL_H"

grep -qi '^content-type: image/jpeg' "$TMP/download.headers" \
  && ok "download declares the real MIME type" \
  || bad "download declares the real MIME type" "$(grep -i '^content-type' "$TMP/download.headers")"

# -------------------------------------------------------------- thumbnail
THUMB_CODE=$(curl -s -o "$TMP/thumb.jpg" -w '%{http_code}' \
  "$BASE/api/files/thumbnail?path=qa-original.jpg&max=512" "${AUTH[@]}")
check "thumbnail endpoint returns 200" "200" "$THUMB_CODE"

THUMB_SHA=$(sha256sum "$TMP/thumb.jpg" | awk '{print $1}')
THUMB_BYTES=$(stat -c%s "$TMP/thumb.jpg")
read -r T_W T_H < <(python3 - "$TMP/thumb.jpg" <<'PY'
import struct, sys
data = open(sys.argv[1], 'rb').read()
i = 2
while i < len(data) - 9:
    if data[i] != 0xFF:
        i += 1
        continue
    marker = data[i + 1]
    if marker in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB):
        h, w = struct.unpack('>HH', data[i + 5:i + 9])
        print(w, h)
        break
    if marker in (0xD8, 0xD9) or 0xD0 <= marker <= 0xD7:
        i += 2
        continue
    seg = struct.unpack('>H', data[i + 2:i + 4])[0]
    i += 2 + seg
PY
)

if [ -z "${T_W:-}" ]; then
  bad "thumbnail decodes" "(unreadable)"
else
  [ "$T_W" -lt "$SRC_W" ] \
    && ok "thumbnail is narrower than the original ($T_W < $SRC_W)" \
    || bad "thumbnail is narrower than the original" "($T_W vs $SRC_W)"
  [ "$T_H" -lt "$SRC_H" ] \
    && ok "thumbnail is shorter than the original ($T_H < $SRC_H)" \
    || bad "thumbnail is shorter than the original" "($T_H vs $SRC_H)"
  [ "${T_W:-0}" -le 512 ] && [ "${T_H:-0}" -le 512 ] \
    && ok "thumbnail respects the requested maximum edge" \
    || bad "thumbnail respects the requested maximum edge" "(${T_W}x${T_H})"
fi

[ "$THUMB_SHA" != "$SRC_SHA" ] \
  && ok "thumbnail is a separate rendition from the original" \
  || bad "thumbnail is a separate rendition from the original"
[ "$THUMB_BYTES" -lt "$SRC_BYTES" ] \
  && ok "thumbnail is smaller than the original ($THUMB_BYTES < $SRC_BYTES)" \
  || bad "thumbnail is smaller than the original"
[ "$THUMB_BYTES" -ne "$DL_BYTES" ] \
  && ok "thumbnail bytes differ from original bytes (viewer cannot be fed the preview)" \
  || bad "thumbnail bytes differ from original bytes"

# -------------------------------------------------------- range requests
RANGE_CODE=$(curl -s -o "$TMP/range.bin" -w '%{http_code}' \
  -H "Range: bytes=0-1023" "$BASE/api/files/download?path=qa-original.jpg" "${AUTH[@]}")
check "range request returns 206" "206" "$RANGE_CODE"
check "range response is exactly the requested length" "1024" "$(stat -c%s "$TMP/range.bin")"

# ------------------------------------------------------------------- photos
curl -s "$BASE/api/photos" "${AUTH[@]}" | grep -q 'qa-original.jpg' \
  && ok "photo listing includes the upload" || bad "photo listing includes the upload"

# ------------------------------------------------------------ share safety
FOLDER_CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/api/shares" \
  "${AUTH[@]}" -H 'Content-Type: application/json' \
  -d '{"path":"","permission":"read"}')
[ "$FOLDER_CODE" = "400" ] || [ "$FOLDER_CODE" = "404" ] \
  && ok "sharing the root is refused ($FOLDER_CODE)" \
  || bad "sharing the root is refused" "(got $FOLDER_CODE)"

SHARE_JSON=$(curl -s -X POST "$BASE/api/shares" "${AUTH[@]}" \
  -H 'Content-Type: application/json' \
  -d '{"path":"qa-original.jpg","permission":"read"}')
SHARE_TOKEN=$(echo "$SHARE_JSON" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("token") or "")')
SHARE_ID=$(echo "$SHARE_JSON" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("id") or "")')
[ -n "$SHARE_TOKEN" ] && ok "share link created" || bad "share link created" "$SHARE_JSON"

if [ -n "$SHARE_TOKEN" ]; then
  PUBLIC_SHA=$(curl -s "$BASE/api/share/$SHARE_TOKEN/download" | sha256sum | awk '{print $1}')
  [ "$PUBLIC_SHA" = "$SRC_SHA" ] \
    && ok "public share link serves the original bytes" \
    || bad "public share link serves the original bytes"

  curl -s -o /dev/null -X DELETE "$BASE/api/shares?id=$SHARE_ID" "${AUTH[@]}"
  AFTER=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/share/$SHARE_TOKEN/download")
  check "a revoked share link stops working" "404" "$AFTER"
fi

echo ""
echo "=== image quality: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
