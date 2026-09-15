#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/server/.env"

if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
fi
cd "$ROOT"

export DATABASE_PATH="${DATABASE_PATH:-$ROOT/data/nexadrive.db}"
export STORAGE_ROOT="${STORAGE_ROOT:-$ROOT/storage}"
export BIND_ADDR="${BIND_ADDR:-127.0.0.1:8080}"
export ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"
export ADMIN_DISPLAY_NAME="${ADMIN_DISPLAY_NAME:-Administrator}"
export RUST_LOG="${RUST_LOG:-info,nexadrive_server=debug}"
export ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"

if [[ -z "$ADMIN_PASSWORD" ]]; then
  echo "Set ADMIN_PASSWORD before first start (for example: export ADMIN_PASSWORD="a-long-random-password")" >&2
  exit 1
fi

if [[ ! -x "$ROOT/server/target/release/nexadrive-server" ]]; then
  echo "Building NexaDrive server..."
  cargo build --release --manifest-path "$ROOT/server/Cargo.toml"
fi

mkdir -p "$(dirname "$DATABASE_PATH")" "$STORAGE_ROOT"

cleanup() {
  if [[ -n "${SERVER_PID:-}" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

"$ROOT/server/target/release/nexadrive-server" &
SERVER_PID=$!

for _ in {1..50}; do
  if curl -fsS "http://$BIND_ADDR/health" >/dev/null 2>&1; then
    break
  fi
  sleep 0.2
done

if ! curl -fsS "http://$BIND_ADDR/health" >/dev/null 2>&1; then
  echo "NexaDrive server failed to start." >&2
  exit 1
fi

echo "NexaDrive server is running at http://$BIND_ADDR"

echo "The SQLite database is managed by the server and no PostgreSQL service is required."

echo "Press Ctrl+C to stop NexaDrive and release the database/storage handles."
wait "$SERVER_PID"
