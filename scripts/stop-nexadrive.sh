#!/usr/bin/env bash
set -euo pipefail
# Stop the NexaDrive server, whether running under systemd or as a plain
# background process spawned by scripts/start-nexadrive.sh.
if systemctl list-units --type=service --all 2>/dev/null | grep -q '^nexadrive.service'; then
  sudo systemctl stop nexadrive || true
fi
pkill -TERM -f 'nexadrive-server' 2>/dev/null || true
echo 'NexaDrive server stopped.'