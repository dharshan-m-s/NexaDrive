#!/bin/bash
# NexaDrive Deployment Script
# Usage: ./deploy.sh [deploy|rollback|health|status]
set -euo pipefail

NEXADRIVE_HOME="${NEXADRIVE_HOME:-/opt/nexadrive}"
SERVER_DIR="$NEXADRIVE_HOME/server"
BINARY="$SERVER_DIR/target/release/nexadrive-server"
BACKUP_BINARY="$SERVER_DIR/target/release/nexadrive-server.bak"
SERVICE="nexadrive"

# Credentials are read from the server env file, never hardcoded here.
load_credentials() {
  if [ -r /etc/nexadrive/server.env ]; then
    . /etc/nexadrive/server.env
  elif [ -r "$SERVER_DIR/.env" ]; then
    . "$SERVER_DIR/.env"
  fi
  : "${ADMIN_USERNAME:=admin}"
  : "${ADMIN_PASSWORD:?ADMIN_PASSWORD must be set in /etc/nexadrive/server.env or server/.env}"
}

deploy() {
  echo "=== NexaDrive Deployment ==="

  # Pre-deployment checks
  if [ ! -f "$BINARY" ]; then
    echo "ERROR: No new binary found at $BINARY"
    exit 1
  fi

  # Save current running binary as backup
  if systemctl is-active --quiet "$SERVICE" 2>/dev/null; then
    PID=$(systemctl show "$SERVICE" -p MainPID --value)
    CURRENT_SHA=$(sha256sum "$BINARY" | cut -d' ' -f1)
    echo "Current binary SHA-256: $CURRENT_SHA (PID: $PID)"
    cp "$BINARY" "$BACKUP_BINARY" 2>/dev/null || true
  fi

  # Build new binary
  echo "Building release binary..."
  cd "$SERVER_DIR"
  cargo build --release 2>&1

  # Run tests
  echo "Running tests..."
  cargo test 2>&1

  NEW_SHA=$(sha256sum "$BINARY" | cut -d' ' -f1)
  echo "New binary SHA-256: $NEW_SHA"

  # Restart service
  echo "Restarting service..."
  systemctl restart "$SERVICE"

  # Wait for startup
  sleep 3

  # Health check
  echo "Running health check..."
  for i in 1 2 3 4 5; do
    if curl -sf http://127.0.0.1:8080/health > /dev/null 2>&1; then
      echo "Health check: OK"
      break
    fi
    if [ "$i" -eq 5 ]; then
      echo "Health check FAILED after 5 attempts"
      echo "Rolling back..."
      rollback
      exit 1
    fi
    sleep 2
  done

  # Authenticated smoke test
  echo "Running authenticated smoke test..."
  load_credentials
  TOKEN=$(curl -s -X POST http://127.0.0.1:8080/api/auth/login \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"$ADMIN_USERNAME\",\"password\":\"$ADMIN_PASSWORD\"}" | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])" 2>/dev/null || echo "")
  if [ -n "$TOKEN" ]; then
    ME=$(curl -s http://127.0.0.1:8080/api/me -H "Authorization: Bearer $TOKEN" | python3 -c "import sys,json; print(json.load(sys.stdin)['username'])" 2>/dev/null || echo "")
    if [ "$ME" = "$ADMIN_USERNAME" ]; then
      echo "Authenticated smoke test: OK (user=$ME)"
    else
      echo "Authenticated smoke test: FAILED"
      rollback
      exit 1
    fi
  else
    echo "Could not obtain auth token, skipping smoke test"
  fi

  # Security headers check
  HEADERS=$(curl -sI http://127.0.0.1:8080/health)
  echo "Security headers: $(echo "$HEADERS" | grep -ci 'x-content-type-options\|x-frame-options\|referrer-policy') present"

  NEW_PID=$(systemctl show "$SERVICE" -p MainPID --value)
  echo ""
  echo "=== Deployment Complete ==="
  echo "Binary: $BINARY"
  echo "SHA-256: $NEW_SHA"
  echo "PID: $NEW_PID"
  echo "Service: $(systemctl is-active "$SERVICE")"
}

rollback() {
  echo "=== Rolling Back ==="
  if [ -f "$BACKUP_BINARY" ]; then
    cp "$BACKUP_BINARY" "$BINARY"
    systemctl restart "$SERVICE"
    sleep 2
    if curl -sf http://127.0.0.1:8080/health > /dev/null 2>&1; then
      echo "Rollback successful. Server is healthy."
    else
      echo "ERROR: Rollback failed. Server is not responding."
      exit 1
    fi
  else
    echo "No backup binary found at $BACKUP_BINARY"
    echo "Attempting to restart the current binary..."
    systemctl restart "$SERVICE"
    sleep 2
    if curl -sf http://127.0.0.1:8080/health > /dev/null 2>&1; then
      echo "Restart successful."
    else
      echo "ERROR: Server is not responding."
      exit 1
    fi
  fi
}

health() {
  echo "=== NexaDrive Health Check ==="
  echo "Service: $(systemctl is-active "$SERVICE")"
  echo "PID: $(systemctl show "$SERVICE" -p MainPID --value)"
  echo "Memory: $(systemctl show "$SERVICE" -p MemoryCurrent --value)"
  echo "Health: $(curl -s http://127.0.0.1:8080/health 2>/dev/null || echo 'unreachable')"
  echo "Binary: $(sha256sum "$BINARY" 2>/dev/null || echo 'not found')"
  echo "DB: $(sqlite3 "$NEXADRIVE_HOME/data/nexadrive.db" 'PRAGMA quick_check;' 2>/dev/null || echo 'error')"
  echo "Tailscale: $(tailscale status --self 2>/dev/null | head -1 || echo 'unavailable')"
  echo "Binding: $(ss -tlnp | grep 8080 | head -1 || echo 'not found')"
}

status() {
  echo "=== NexaDrive Status ==="
  systemctl status "$SERVICE" --no-pager -l 2>/dev/null || true
  echo ""
  echo "Binary: $BINARY"
  echo "SHA-256: $(sha256sum "$BINARY" 2>/dev/null || echo 'not found')"
  echo "Backup: $BACKUP_BINARY"
  if [ -f "$BACKUP_BINARY" ]; then
    echo "Backup SHA-256: $(sha256sum "$BACKUP_BINARY")"
  fi
}

case "${1:-deploy}" in
  deploy)  deploy ;;
  rollback) rollback ;;
  health)  health ;;
  status)  status ;;
  *)       echo "Usage: $0 [deploy|rollback|health|status]" ;;
esac
