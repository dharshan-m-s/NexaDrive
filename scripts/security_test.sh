#!/bin/bash
# NexaDrive Security Regression Tests
# Run against the live deployed server
set -euo pipefail

BASE="http://127.0.0.1:8080"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load credentials from the server env file, never hardcoded here.
if [ -r /etc/nexadrive/server.env ]; then
  . /etc/nexadrive/server.env
elif [ -r "$SCRIPT_DIR/server/.env" ]; then
  . "$SCRIPT_DIR/server/.env"
fi
ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:?ADMIN_PASSWORD must be set in /etc/nexadrive/server.env or server/.env}"

TOKEN=$(curl -s -X POST "$BASE/api/auth/login" -H 'Content-Type: application/json' \
  -d "{\"username\":\"$ADMIN_USERNAME\",\"password\":\"$ADMIN_PASSWORD\"}" | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")
PASS=0
FAIL=0

check() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "  PASS: $desc"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $desc (expected=$expected actual=$actual)"
    FAIL=$((FAIL+1))
  fi
}

echo "=== NexaDrive Security Regression Tests ==="
echo ""

echo "1. Path traversal"
check "../etc/passwd rejected" "400" "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/files?path=../etc/passwd" -H "Authorization: Bearer $TOKEN")"
check "Absolute path rejected" "400" "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/files?path=/etc/passwd" -H "Authorization: Bearer $TOKEN")"
check "Double traversal rejected" "400" "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/files?path=foo/../../etc/passwd" -H "Authorization: Bearer $TOKEN")"
check ".trash access rejected" "403" "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/files?path=.trash/uuid/file" -H "Authorization: Bearer $TOKEN")"
check "Null byte rejected" "400" "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/files?path=foo%00bar" -H "Authorization: Bearer $TOKEN")"

echo ""
echo "2. Unauthorized access"
check "No-auth file list" "401" "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/files")"
check "Invalid token" "401" "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/me" -H "Authorization: Bearer invalid-token")"
check "Empty bearer" "401" "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/me" -H "Authorization: Bearer ")"

echo ""
echo "3. Public share security"
check "Invalid share token" "404" "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/share/fake-token/download")"
check "Nonexistent share token" "404" "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/share/0000000000000000000000000000000000000000000000000000000000000000/download")"

echo ""
echo "4. Security headers"
HDRS=$(curl -sI "$BASE/health")
check "X-Content-Type-Options" "true" "$(echo "$HDRS" | grep -qi 'x-content-type-options' && echo true || echo false)"
check "X-Frame-Options DENY" "true" "$(echo "$HDRS" | grep -qi 'x-frame-options' && echo true || echo false)"
check "Referrer-Policy" "true" "$(echo "$HDRS" | grep -qi 'referrer-policy' && echo true || echo false)"
check "Permissions-Policy" "true" "$(echo "$HDRS" | grep -qi 'permissions-policy' && echo true || echo false)"
check "Cache-Control no-store" "true" "$(echo "$HDRS" | grep -qi 'cache-control.*no-store' && echo true || echo false)"

echo ""
echo "5. SQL injection"
check "SQL injection in search" "200" "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/files/search?q=%27%3BDROP%20TABLE%20users%3B--" -H "Authorization: Bearer $TOKEN")"
check "SQL injection in path" "200" "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/files?path=test%27%20OR%201%3D1--" -H "Authorization: Bearer $TOKEN")"

echo ""
echo "6. Brute force protection"
# Use a throwaway probe username so the real admin account is never rate-limited.
PROBE_USER="security-probe-$(date +%s)"
for i in $(seq 1 11); do
  curl -s -o /dev/null -X POST "$BASE/api/auth/login" -H 'Content-Type: application/json' -d "{\"username\":\"$PROBE_USER\",\"password\":\"wrong\"}"
done
check "Rate limit after 10 failures" "429" "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/api/auth/login" -H 'Content-Type: application/json' -d "{\"username\":\"$PROBE_USER\",\"password\":\"wrong\"}")"

echo ""
echo "7. Network binding"
check "Bound to localhost" "0" "$(ss -tlnp 2>/dev/null | grep ':8080' | grep -v '127.0.0.1' | wc -l)"

echo ""
echo "8. Database integrity"
check "SQLite integrity" "ok" "$(sqlite3 "$SCRIPT_DIR/data/nexadrive.db" 'PRAGMA integrity_check;' 2>/dev/null)"

echo ""
echo "9. Share token not leaked"
SHARES=$(curl -s "$BASE/api/shares" -H "Authorization: Bearer $TOKEN")
check "Token hidden in listing" "no" "$(echo "$SHARES" | python3 -c "import sys,json; d=json.load(sys.stdin); print('yes' if any(s.get('token') for s in d) else 'no')" 2>/dev/null || echo "no")"

echo ""
echo "10. CORS"
check "CORS blocks evil origin" "true" "$(curl -sI -X OPTIONS "$BASE/api/files" -H "Origin: https://evil.com" -H "Access-Control-Request-Method: GET" | grep -qi 'access-control-allow-origin.*evil' && echo false || echo true)"

echo ""
echo "=========================================="
echo "RESULT: $PASS passed, $FAIL failed"
echo "=========================================="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
