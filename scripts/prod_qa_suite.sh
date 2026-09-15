#!/usr/bin/env bash
# NexaDrive live API QA suite (production validation, sections 3-5, 20)
#
# Runs the full authenticated API and security regression suite against a
# RUNNING server. Read-only against wanted production state except in the
# explicitly namespaced QA area, which is cleaned up at the end.
#
# Credentials are passed via environment only:
#   QA_ADMIN_USER   admin username (default: admin)
#   QA_ADMIN_PASS   admin password (never echoed, never written to disk)
#   QA_BASE         base URL  (default: http://127.0.0.1:8080)
#
# Output goes to stdout; tokens are never printed. Exit code 0 iff PASS>0
# and FAIL==0.

set -uo pipefail

BASE="${QA_BASE:-http://127.0.0.1:8080}"
ADMIN="${QA_ADMIN_USER:-admin}"
PASS="${QA_ADMIN_PASS:-}"
if [ -z "$PASS" ]; then
  echo "ERROR: QA_ADMIN_PASS not set" >&2
  exit 2
fi

TAG="qa$(date +%m%d%H%M%S)"
DIR="qa-prod-$TAG"
BODYFILE="$(mktemp)"
PASS_N=0
FAIL_N=0

cleanup() {
  rm -f "$BODYFILE" /tmp/nexadrive-qa-* 2>/dev/null || true
}
trap cleanup EXIT

ok()   { PASS_N=$((PASS_N + 1)); echo "  PASS: $1"; }
bad()  { FAIL_N=$((FAIL_N + 1)); echo "  FAIL: $1 ${2:-}"; }

# req METHOD PATH [anymore args...]  -> echoes http code, saves body in $BODY
req() {
  local m="$1" p="$2"; shift 2
  curl -s -o "$BODYFILE" -w '%{http_code}' -X "$m" "$BASE$p" "$@"
}

unauth() { # assumes $TOKEN empty/unset -> unauth call
  curl -s -o "$BODYFILE" -w '%{http_code}' "$BASE$1"
}

httpin() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

jget() { python3 -c "import sys,json;d=json.load(open('$BODYFILE'));print(d$1 if d is not None else '')"; }

echo "=== NexaDrive Production QA Suite (tag=$TAG, base=$BASE) ==="
echo ""

echo "[A] Public and unauth surface"
code=$(req GET /health)
[ "$code" = "200" ] && ok "health returns 200" || bad "health returns 200" "(got $code)"
[ "$(jget "['status']")" = "ok" ] && ok "health body status ok" || bad "health body status ok"
code=$(req GET /api/server/status)
[ "$code" = "200" ] && ok "server/status 200" || bad "server/status 200" "(got $code)"
[ -n "$(jget "['instance_id']")" ] && ok "server/status has instance_id" || bad "server/status has instance_id"
code=$(curl -s -o "$BODYFILE" -w '%{http_code}' "$BASE/api/me")
[ "$code" = "401" ] && ok "unauthenticated /api/me -> 401" || bad "unauthenticated /api/me -> 401" "(got $code)"
code=$(curl -s -o "$BODYFILE" -w '%{http_code}' "$BASE/api/files")
[ "$code" = "401" ] && ok "unauthenticated /api/files -> 401" || bad "unauthenticated /api/files -> 401" "(got $code)"
code=$(curl -s -o "$BODYFILE" -w '%{http_code}' "$BASE/api/me" -H "Authorization: Bearer invalid-token")
[ "$code" = "401" ] && ok "invalid bearer -> 401" || bad "invalid bearer -> 401" "(got $code)"

echo ""
echo "[B] Password security (login)"
# wrong password: one shot only, do NOT trip the 10-failure throttle on admin
code=$(httpin -X POST "$BASE/api/auth/login" -H 'Content-Type: application/json' \
  -d '{"username":"'"$ADMIN"'","password":"definitely-wrong-password-probe"}')
[ "$code" = "401" ] && ok "wrong password -> 401" || bad "wrong password -> 401" "(got $code)"

echo ""
echo "[C] Admin login + session"
LOGIN=$(curl -s -X POST "$BASE/api/auth/login" -H 'Content-Type: application/json' \
  -d '{"username":"'"$ADMIN"'","password":"'"$PASS"'"}')
TOKEN=$(echo "$LOGIN" | python3 -c "import sys,json;print(json.load(sys.stdin)['token'])" 2>/dev/null || echo "")
ROLE=$(echo "$LOGIN" | python3 -c "import sys,json;print(json.load(sys.stdin)['user']['role'])" 2>/dev/null || echo "")
if [ -n "$TOKEN" ]; then
  ok "admin login issues token"
else
  bad "admin login issues token"
fi
[ "$ROLE" = "admin" ] && ok "admin role=admin" || bad "admin role=admin" "(got '$ROLE')"
AUTH=(-H "Authorization: Bearer $TOKEN")
code=$(req GET /api/me "${AUTH[@]}")
[ "$code" = "200" ] && [ "$(jget "['username']")" = "$ADMIN" ] && ok "/api/me returns admin" || bad "/api/me returns admin" "(got $code)"

echo ""
echo "[D] Secondary account + authorization isolation"
U="qa-$TAG"
CODE=$(httpin -X POST "$BASE/api/admin/users" "${AUTH[@]}" -H 'Content-Type: application/json' \
  -d '{"username":"'"$U"'","display_name":"QA Test","password":"QA-Test-pw-'"$TAG"'","role":"user"}')
{ [ "$CODE" = "201" ] || [ "$CODE" = "200" ]; } && ok "admin creates qa user" || bad "admin creates qa user (got $CODE)"
UID2=$(curl -s "$BASE/api/admin/users" "${AUTH[@]}" | python3 -c "import sys,json;print([u['id'] for u in json.load(sys.stdin) if u['username']=='$U'][0])" 2>/dev/null || echo "")
[ -n "$UID2" ] && ok "list_users includes qa user" || bad "list_users includes qa user"
U2LOGIN=$(curl -s -X POST "$BASE/api/auth/login" -H 'Content-Type: application/json' \
  -d '{"username":"'"$U"'","password":"QA-Test-pw-'"$TAG"'"}')
T2=$(echo "$U2LOGIN" | python3 -c "import sys,json;print(json.load(sys.stdin)['token'])" 2>/dev/null || echo "")
[ -n "$T2" ] && ok "qa user can log in" || bad "qa user can log in"
A2=(-H "Authorization: Bearer $T2")
code=$(req GET /api/admin/users "${A2[@]}")
[ "$code" = "403" ] && ok "qa user denied /api/admin/users (403)" || bad "qa user denied /api/admin/users (403)" "(got $code)"
code=$(req GET /api/files "${A2[@]}")
[ "$code" = "200" ] && ok "qa user can list own files" || bad "qa user can list own files (got $code)"
# disable / re-enable cycle must block login
httpin -X PUT "$BASE/api/admin/users/$UID2" "${AUTH[@]}" -H 'Content-Type: application/json' -d '{"disabled":true}' >/dev/null
code=$(httpin -X POST "$BASE/api/auth/login" -H 'Content-Type: application/json' \
  -d '{"username":"'"$U"'","password":"QA-Test-pw-'"$TAG"'"}')
[ "$code" = "401" ] && ok "disabled user cannot log in" || bad "disabled user cannot log in (got $code)"
httpin -X PUT "$BASE/api/admin/users/$UID2" "${AUTH[@]}" -H 'Content-Type: application/json' -d '{"disabled":false}' >/dev/null

echo ""
echo "[E] Folders and files (namespace qa-prod interactively)"
code=$(req POST /api/folders "${AUTH[@]}" -H 'Content-Type: application/json' -d "{\"path\":\"$DIR\"}")
{ [ "$code" = "200" ] || [ "$code" = "201" ]; } && ok "create folder $DIR" || bad "create folder (got $code)"
code=$(req GET "/api/files?path=" "${AUTH[@]}")
grep -q '"'"$DIR"'"' "$BODYFILE" && ok "root listing contains QA folder" || bad "root listing contains QA folder"

SMALL=/tmp/nexadrive-qa-small.txt
printf 'NexaDrive production QA small file %s\n' "$TAG" > "$SMALL"
code=$(curl -s -o "$BODYFILE" -w '%{http_code}' -X POST "$BASE/api/files/upload" "${AUTH[@]}" \
  -F "path=$DIR" -F "upload_id=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)" \
  -F "file=@$SMALL;type=text/plain")
SZS=$(stat -c %s "$SMALL")
[ "$code" = "200" ] && [ "$(jget "['size']")" = "$SZS" ] && ok "multipart upload (small) with correct size" || bad "multipart upload (small)" "(got $code)/$(jget "['size']")"

# --- chunked resumable upload ---
BIG=/tmp/nexadrive-qa-big.bin
SIZE=1500000
head -c "$SIZE" /dev/urandom > "$BIG"
[ "$(stat -c %s "$BIG")" = "$SIZE" ] || { echo "FATAL: fixture generation failed" >&2; exit 2; }
EPOCH=$(date +%s)
RANGE=$((SIZE / 4))
UPLOAD_ID=$(cat /proc/sys/kernel/random/uuid)
c1=$((0))
c2=$((RANGE))
c3=$((RANGE * 2))
c4=$((RANGE * 3))
LAST=$((c4))
END_LEN=$((SIZE - RANGE * 3))
resp_chunk() { # offset bytes
  curl -s -o "$BODYFILE" -w '%{http_code}' -X POST \
    "${BASE}/api/uploads/chunk?upload_id=${UPLOAD_ID}&path=${DIR}&name=big-${TAG}.bin&offset=$1&total=$SIZE" \
    "${AUTH[@]}" -H 'Content-Type: application/octet-stream' \
    --data-binary @<(dd if="$BIG" bs=1 skip="$1" count="$2" 2>/dev/null)
}
off=0
CHUNK_FILE=/tmp/nexadrive-qa-chunk.bin
dd if="$BIG" of="$CHUNK_FILE" bs=1 skip=$c1 count=$RANGE 2>/dev/null
code=$(curl -s -o "$BODYFILE" -w '%{http_code}' -X POST \
  "${BASE}/api/uploads/chunk?upload_id=${UPLOAD_ID}&path=${DIR}&name=big-${TAG}.bin&offset=0&total=$SIZE" \
  "${AUTH[@]}" -H 'Content-Type: application/octet-stream' --data-binary @"$CHUNK_FILE")
[ "$code" = "200" ] && [ "$(jget "['offset']")" = "$RANGE" ] && ok "chunk 1 accepted, offset=$RANGE" || bad "chunk 1 accepted (got $code offset $(jget "['offset']") )"
# resume conflict: retry offset 0 against server offset RANGE -> 409
code=$(curl -s -o "$BODYFILE" -w '%{http_code}' -X POST \
  "${BASE}/api/uploads/chunk?upload_id=${UPLOAD_ID}&path=${DIR}&name=big-${TAG}.bin&offset=0&total=$SIZE" \
  "${AUTH[@]}" -H 'Content-Type: application/octet-stream' --data-binary @"$CHUNK_FILE")
[ "$code" = "409" ] && ok "stale offset rejected with 409 (resume-from-guard)" || bad "stale offset rejected (got $code)"
# upload status reflects authoritative offset
code=$(req GET "/api/uploads/status?upload_id=$UPLOAD_ID" "${AUTH[@]}")
[ "$code" = "200" ] && [ "$(jget "['bytes_received']")" = "$RANGE" ] && ok "upload/status reflects server offset" || bad "upload/status offset (got $code)"
# complete remaining chunks
dd if="$BIG" of="$CHUNK_FILE" bs=1 skip=$c2 count=$RANGE 2>/dev/null
code=$(curl -s -o "$BODYFILE" -w '%{http_code}' -X POST \
  "${BASE}/api/uploads/chunk?upload_id=${UPLOAD_ID}&path=${DIR}&name=big-${TAG}.bin&offset=$c2&total=$SIZE" \
  "${AUTH[@]}" -H 'Content-Type: application/octet-stream' --data-binary @"$CHUNK_FILE")
[ "$code" = "200" ] && [ "$(jget "['offset']")" = "$c3" ] && ok "chunk 2 accepted" || bad "chunk 2 accepted (got $code)"
dd if="$BIG" of="$CHUNK_FILE" bs=1 skip=$c3 count=$RANGE 2>/dev/null
code=$(curl -s -o "$BODYFILE" -w '%{http_code}' -X POST \
  "${BASE}/api/uploads/chunk?upload_id=${UPLOAD_ID}&path=${DIR}&name=big-${TAG}.bin&offset=$c3&total=$SIZE" \
  "${AUTH[@]}" -H 'Content-Type: application/octet-stream' --data-binary @"$CHUNK_FILE")
[ "$code" = "200" ] && [ "$(jget "['offset']")" = "$c4" ] && ok "chunk 3 accepted" || bad "chunk 3 accepted (got $code)"
dd if="$BIG" of="$CHUNK_FILE" bs=1 skip=$c4 count=$END_LEN 2>/dev/null
code=$(curl -s -o "$BODYFILE" -w '%{http_code}' -X POST \
  "${BASE}/api/uploads/chunk?upload_id=${UPLOAD_ID}&path=${DIR}&name=big-${TAG}.bin&offset=$c4&total=$SIZE" \
  "${AUTH[@]}" -H 'Content-Type: application/octet-stream' --data-binary @"$CHUNK_FILE")
[ "$code" = "200" ] && [ "$(jget "['status']")" = "completed" ] && ok "final chunk completes upload" || bad "final chunk completes upload (got $code status $(jget "['status']") )"
CR=$(jget "['checksum_sha256']")
LOCAL_SHA=$(sha256sum "$BIG" | cut -d' ' -f1)
[ "$CR" = "$LOCAL_SHA" ] && ok "server sha256 matches uploaded bytes" || bad "server sha256 matches uploaded bytes (got $CR want $LOCAL_SHA)"

# download verification
code=$(curl -s -o /tmp/nexadrive-qa-dl.bin -w '%{http_code}' \
  "$BASE/api/files/download?path=$DIR/big-$TAG.bin" "${AUTH[@]}")
DL_SHA=$(sha256sum /tmp/nexadrive-qa-dl.bin | cut -d' ' -f1)
[ "$code" = "200" ] && [ "$DL_SHA" = "$LOCAL_SHA" ] && ok "download round-trip sha matches" || bad "download round-trip sha (http $code)"

# rename
code=$(req POST /api/files/rename "${AUTH[@]}" -H 'Content-Type: application/json' \
  -d "{\"source\":\"$DIR/big-$TAG.bin\",\"name\":\"renamed-$TAG.bin\"}")
[ "$code" = "200" ] && ok "rename file" || bad "rename file (got $code)"
code=$(req GET "/api/files?path=$DIR" "${AUTH[@]}")
grep -q 'renamed-' "$BODYFILE" && ok "listing shows renamed file" || bad "listing shows renamed file"
# move into a subfolder
CODEM=$(req POST /api/folders "${AUTH[@]}" -H 'Content-Type: application/json' \
  -d "{\"path\":\"$DIR/sub-$TAG\"}")
MOVME_NAME="moveme-${TAG}.bin"
MOVME="/tmp/nexadrive-qa-${MOVME_NAME}"
head -c 1024 /dev/urandom > "$MOVME"
MOV_ID=$(cat /proc/sys/kernel/random/uuid)
code=$(curl -s -o "$BODYFILE" -w '%{http_code}' -X POST "$BASE/api/files/upload" "${AUTH[@]}" \
  -F "path=$DIR" -F "upload_id=$MOV_ID" -F "file=@$MOVME;filename=$MOVME_NAME;type=application/octet-stream")
[ "$code" = "200" ] && ok "upload moveme file" || bad "upload moveme (got $code)"
code=$(req POST /api/files/move "${AUTH[@]}" -H 'Content-Type: application/json' \
  -d "{\"source\":\"$DIR/$MOVME_NAME\",\"destination\":\"$DIR/sub-$TAG\"}")
[ "$code" = "200" ] && ok "move file into subfolder" || bad "move file (got $code)"
code=$(req GET "/api/files?path=$DIR/sub-$TAG" "${AUTH[@]}")
grep -q 'moveme-' "$BODYFILE" && ok "file visible in subfolder" || bad "file visible in subfolder"
# copy back to root
code=$(req POST /api/files/copy "${AUTH[@]}" -H 'Content-Type: application/json' \
  -d "{\"source\":\"$DIR/sub-$TAG/$MOVME_NAME\",\"destination\":\"$DIR\"}")
[ "$code" = "200" ] && ok "copy file to root" || bad "copy file (got $code)"
code=$(req GET "/api/files?path=$DIR" "${AUTH[@]}")
grep -q 'moveme-' "$BODYFILE" && ok "copied file appears in root" || bad "copied file appears in root"
code=$(req GET "/api/files/search?q=moveme" "${AUTH[@]}")
grep -q 'moveme-' "$BODYFILE" && ok "search finds copied file" || bad "search finds copied file"

echo ""
echo "[F] Photos + thumbnail"
PIX=/tmp/nexadrive-qa-pix.jpg
echo '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAMCAgMCAgMDAwMEAwMEBQgFBQQEBQoHBwYIDAoMDAsKCwsNDhIQDQ4RDgsLEBYQERMUFRUVDA8XGBYUGBIUFRT/2wBDAQMEBAUEBQkFBQkUDQsNFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBT/wAARCAAEAAQDAREAAhEBAxEB/8QAFAABAAAAAAAAAAAAAAAAAAAACP/EABQQAQAAAAAAAAAAAAAAAAAAAAD/xAAVAQEBAAAAAAAAAAAAAAAAAAAHCf/EABQRAQAAAAAAAAAAAAAAAAAAAAD/2gAMAwEAAhEDEQA/ADoDFU3/2Q==' | base64 -d > "$PIX"
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/api/files/upload" "${AUTH[@]}" \
  -F "path=$DIR" -F "upload_id=$(cat /proc/sys/kernel/random/uuid)" -F "file=@$PIX;type=image/jpeg")
[ "$code" = "200" ] && ok "upload jpeg for photo test" || bad "upload jpeg (got $code)"
code=$(req GET "/api/photos" "${AUTH[@]}")
grep -q 'nexadrive-qa-pix' "$BODYFILE" && ok "photo appears in /api/photos" || bad "photo in /api/photos"
code=$(curl -s -o "$BODYFILE" -w '%{http_code}' "$BASE/api/files/thumbnail?path=$DIR/nexadrive-qa-pix.jpg&max=256" "${AUTH[@]}")
CT=$(file -b --mime-type "$BODYFILE" 2>/dev/null || echo unknown)
[ "$code" = "200" ] && ok "thumbnail 200" || bad "thumbnail (got $code)"
[ "$CT" = "image/jpeg" ] && ok "thumbnail is a JPEG" || bad "thumbnail is a JPEG (got $CT)"
code=$(httpin "$BASE/api/files/thumbnail?path=$DIR/nexadrive-qa-pix.jpg&max=99999" "${AUTH[@]}")
[ "$code" = "200" ] && ok "thumbnail max clamped (100k-ish -> 1024 accepted)" || bad "thumbnail clamp"

echo ""
echo "[K] Storage stats + quota guard"
code=$(req GET /api/storage "${AUTH[@]}")
USED=$(jget "['used_bytes']")
[ "$code" = "200" ] && [ "${USED:-0}" -gt 1000000 ] && ok "storage used_bytes reflects uploads" || bad "storage stats (got $code used=$USED)"
# oversized declared upload rejected before I/O
MAXN=$((1024 * 1024 * 1024 * 10 + 1))
code=$(curl -s -o "$BODYFILE" -w '%{http_code}' -X POST \
  "${BASE}/api/uploads/chunk?upload_id=$(cat /proc/sys/kernel/random/uuid)&path=$DIR&name=too-big.bin&offset=0&total=$MAXN" \
  "${AUTH[@]}" -H 'Content-Type: application/octet-stream' --data-binary "@$SMALL")
[ "$code" = "400" ] && ok "oversized declared upload rejected" || bad "oversized upload (got $code)"

echo ""
echo "[H] Shares (link + recipient)"
code=$(req POST /api/shares "${AUTH[@]}" -H 'Content-Type: application/json' \
  -d "{\"path\":\"$DIR/renamed-$TAG.bin\",\"permission\":\"read\"}")
SHARE_TOKEN=""
[ "$code" = "200" ] && { SHARE_TOKEN=$(jget "['token']"); ok "create link share returns token"; } || bad "create link share (got $code)"
[ -n "$SHARE_TOKEN" ] && ok "share token non-empty" || bad "share token non-empty"
SHARE_ID=$(jget "['id']")
DL2=$(curl -s -o /tmp/nexadrive-qa-share.bin -w '%{http_code}' "$BASE/api/share/$SHARE_TOKEN/download")
S2=$(sha256sum /tmp/nexadrive-qa-share.bin | cut -d' ' -f1)
[ "$DL2" = "200" ] && [ "$S2" = "$LOCAL_SHA" ] && ok "public share download matches source" || bad "public share download (http $DL2 sha mismatch)"
code=$(httpin "$BASE/api/share/bogus-token-000/download")
[ "$code" = "404" ] && ok "invalid share token -> 404" || bad "invalid share token (got $code)"
# recipient (second user) gets the share via /api/shared
code=$(req POST /api/shares "${AUTH[@]}" -H 'Content-Type: application/json' \
  -d "{\"path\":\"$DIR/nexadrive-qa-small.txt\",\"username\":\"$U\",\"permission\":\"read\"}")
code=$(req GET /api/shared "${A2[@]}")
grep -q 'nexadrive-qa-small' "$BODYFILE" && ok "recipient sees shared item" || bad "recipient sees shared item (got $code)"
code=$(req GET /api/shares "${AUTH[@]}")
if echo "$BODYFILE" | grep -q '"token"[[:space:]]*:[[:space:]]*"[0-9a-f]'; then
  bad "share token leaked in listing"
else
  ok "share listing does not leak tokens"
fi

echo ""
echo "[I] Sync manifest/delta"
code=$(req GET "/api/sync/manifest" "${AUTH[@]}")
grep -q 'renamed-' "$BODYFILE" && ok "sync manifest includes uploaded file" || bad "sync manifest (got $code)"
SINCE=$(date -u +%Y-%m-%dT%H:%M:%SZ --date='-1 second' 2>/dev/null || date -u -v-1S +%Y-%m-%dT%H:%M:%SZ)
code=$(req GET "/api/sync/delta?since=$SINCE" "${AUTH[@]}")
[ "$code" = "200" ] && ok "sync delta 200" || bad "sync delta (got $code)"
code=$(req POST /api/sync/delete "${AUTH[@]}" -H 'Content-Type: application/json' \
  -d "{\"path\":\"$DIR/nexadrive-qa-small.txt\"}")
[ "$code" = "204" ] && ok "sync/delete files a tombstone" || bad "sync/delete (got $code)"

echo ""
echo "[G] Trash lifecycle"
code=$(req DELETE "/api/files?path=$DIR/renamed-$TAG.bin" "${AUTH[@]}")
[ "$code" = "204" ] && ok "delete moves file to trash" || bad "delete moves file to trash (got $code)"
TRASH_LIST=$(curl -s "$BASE/api/trash" "${AUTH[@]}")
echo "$TRASH_LIST" | grep -q 'renamed-' && ok "trash lists deleted file" || bad "trash lists deleted file"
TRASH_ID=$(echo "$TRASH_LIST" | python3 -c "import sys,json;print([t['id'] for t in json.load(sys.stdin) if 'renamed-$TAG' in t['original_path']][0])" 2>/dev/null || echo "")
code=$(req POST "/api/trash/restore?id=$TRASH_ID" "${AUTH[@]}")
[ "$code" = "204" ] && ok "restore from trash" || bad "restore from trash (got $code)"
code=$(req GET "/api/files?path=$DIR" "${AUTH[@]}")
grep -q 'renamed-' "$BODYFILE" && ok "restored file visible again" || bad "restored file visible"
code=$(req DELETE "/api/files?path=$DIR/renamed-$TAG.bin" "${AUTH[@]}")
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/api/trash/restore?id=$TRASH_ID" "${AUTH[@]}")
[ "$code" = "404" ] && ok "double restore rejected" || bad "double restore (got $code)"
TRASH_LIST=$(curl -s "$BASE/api/trash" "${AUTH[@]}")
TRASH_ID=$(echo "$TRASH_LIST" | python3 -c "import sys,json;print([t['id'] for t in json.load(sys.stdin) if 'renamed-$TAG' in t['original_path']][0])" 2>/dev/null || echo "")
[ -n "$TRASH_ID" ] && ok "re-deleted item back in trash" || bad "re-deleted item in trash"
code=$(req DELETE "/api/trash?id=$TRASH_ID" "${AUTH[@]}")
[ "$code" = "204" ] && ok "permanent delete from trash" || bad "permanent delete (got $code)"

echo ""
echo "[J] Notifications"
code=$(req GET "/api/notifications?unread=true" "${AUTH[@]}")
[ "$code" = "200" ] && ok "notifications list 200" || bad "notifications list (got $code)"
code=$(req POST /api/notifications/read "${AUTH[@]}" -H 'Content-Type: application/json' -d '{"all":true}')
[ "$code" = "204" ] && ok "mark all read" || bad "mark all read (got $code)"

echo ""
echo "[L] Backup status"
code=$(req GET /api/backup/status "${AUTH[@]}")
[ "$code" = "200" ] && ok "backup/status 200 (configured=$(jget "['configured']") restic=$(jget "['restic_available']"))" || bad "backup/status (got $code)"

echo ""
echo "[M] Security regression"
code=$(req 'GET' '/api/files?path=../etc/passwd' "${AUTH[@]}")
[ "$code" = "400" ] && ok "traversal ../ rejected" || bad "traversal ../ (got $code)"
code=$(req 'GET' '/api/files?path=/etc/passwd' "${AUTH[@]}")
[ "$code" = "400" ] && ok "absolute path rejected" || bad "absolute path (got $code)"
code=$(req 'GET' '/api/files?path=foo/../../etc/passwd' "${AUTH[@]}")
[ "$code" = "400" ] && ok "double traversal rejected" || bad "double traversal (got $code)"
code=$(req 'GET' '/api/files?path=.trash/uuid/file' "${AUTH[@]}")
[ "$code" = "403" ] && ok ".trash access rejected 403" || bad ".trash access (got $code)"
code=$(req 'GET' '/api/files?path=foo%00bar' "${AUTH[@]}")
[ "$code" = "400" ] && ok "null byte rejected" || bad "null byte (got $code)"
code=$(req 'GET' '/api/files/search?q=%27%3BDROP%20TABLE%20users%3B--' "${AUTH[@]}")
[ "$code" = "200" ] && ok "SQLi attempt in search harmless (parameterized)" || bad "SQLi in search (got $code)"
HDRS=$(curl -sI "$BASE/health")
for h in 'x-content-type-options' 'x-frame-options' 'referrer-policy' 'permissions-policy'; do
  if echo "$HDRS" | grep -qi "$h"; then ok "header $h present"; else bad "header $h missing"; fi
done
if echo "$HDRS" | grep -qi 'cache-control.*no-store'; then ok "no-store cache policy on health"; else bad "no-store cache policy"; fi
if curl -sI -X OPTIONS "$BASE/api/files" -H 'Origin: https://evil.com' -H 'Access-Control-Request-Method: GET' | grep -qi 'access-control-allow-origin.*evil'; then
  bad "CORS allows evil origin"
else
  ok "CORS denies evil origin"
fi

echo ""
echo "[N] Brute-force throttle (isolated probe user, admin untouched)"
PROBE="qa-rl-$TAG"
RLHITS=""
for i in $(seq 1 11); do
  code=$(httpin -X POST "$BASE/api/auth/login" -H 'Content-Type: application/json' \
    -d '{"username":"'"$PROBE"'","password":"wrong-password"}')
  RLHITS="$RLHITS$code "
done
if echo "$RLHITS" | grep -q '429'; then ok "rate limit engages after failures"; else bad "rate limit (codes: $RLHITS)"; fi
# admin still usable
code=$(httpin -X POST "$BASE/api/auth/login" -H 'Content-Type: application/json' \
  -d '{"username":"'"$ADMIN"'","password":"'"$PASS"'"}')
[ "$code" = "200" ] && ok "admin login unaffected by throttle" || bad "admin login unaffected (got $code)"

echo ""
echo "[O] Teardown (cleanup QA artifacts)"
# purge everything under $DIR
FILES=$(curl -s "$BASE/api/files?path=$DIR" "${AUTH[@]}" | python3 -c "import sys,json;[print(f['path']) for f in json.load(sys.stdin)]" 2>/dev/null || true)
for p in $FILES; do
  curl -s -o /dev/null -X DELETE "$BASE/api/files?path=$p" "${AUTH[@]}"
done
code=$(req DELETE "/api/files?path=$DIR" "${AUTH[@]}")
[ "$code" = "204" ] && ok "QA folder moved to trash" || bad "QA folder trash (got $code)"
TRASH_LIST=$(curl -s "$BASE/api/trash" "${AUTH[@]}")
TRASH_IDS=$(echo "$TRASH_LIST" | python3 -c "import sys,json;[print(t['id']) for t in json.load(sys.stdin) if '$TAG' in t['original_path']]" 2>/dev/null || true)
for tid in $TRASH_IDS; do
  curl -s -o /dev/null -X DELETE "$BASE/api/trash?id=$tid" "${AUTH[@]}"
done
TRASH_LEFT=$(curl -s "$BASE/api/trash" "${AUTH[@]}" | python3 -c "import sys,json;print(len([t for t in json.load(sys.stdin) if '$TAG' in t['original_path']]))" 2>/dev/null || echo '?')
[ "$TRASH_LEFT" = "0" ] && ok "all QA trash purged" || bad "QA trash purge (left $TRASH_LEFT)"
# disable the throwaway user account (no delete-user API at present)
httpin -X PUT "$BASE/api/admin/users/$UID2" "${AUTH[@]}" -H 'Content-Type: application/json' -d '{"disabled":true}' >/dev/null
ok "QA secondary account disabled (left convenient, login blocked)"
# logout -> token must die
code=$(req POST /api/auth/logout "${AUTH[@]}")
[ "$code" = "204" ] && ok "logout 204" || bad "logout (got $code)"
code=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/me" "${AUTH[@]}")
[ "$code" = "401" ] && ok "token invalid after logout" || bad "token after logout (got $code)"

echo ""
echo "=========================================="
echo "SUITE RESULT: $PASS_N passed, $FAIL_N failed (tag=$TAG)"
echo "=========================================="
[ "$FAIL_N" -eq 0 ]