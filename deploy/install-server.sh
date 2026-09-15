#!/usr/bin/env bash
set -euo pipefail

# NexaDrive Production Installer
#
# Installs NexaDrive under the chosen install path.
# The server binary, database, user files, backups, and all runtime data live
# under <install-path>. The repo is portable — pass a custom path as the first
# argument, e.g.:  sudo bash deploy/install-server.sh /data/nexadrive
#
# Prerequisites:
#   - the install path must be writable
#   - restic must be installed (for optional backup support)
#   - tailscale must be configured (for optional network access)

NEXADRIVE_HOME="${1:?Usage: $0 <install-path, e.g. /opt/nexadrive>}"
SERVICE_USER=nexadrive
SERVICE_GROUP=nexadrive

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0 ${NEXADRIVE_HOME}"
  exit 1
fi

# Create service user if it doesn't exist
id "$SERVICE_USER" >/dev/null 2>&1 || useradd --system --home-dir "$NEXADRIVE_HOME" --shell /usr/bin/nologin "$SERVICE_USER"

# Ensure directory structure
mkdir -p "$NEXADRIVE_HOME/data"
mkdir -p "$NEXADRIVE_HOME/storage"
mkdir -p "$NEXADRIVE_HOME/backups"
mkdir -p "$NEXADRIVE_HOME/temp"
mkdir -p "$NEXADRIVE_HOME/logs"

# Install the service unit with the chosen path substituted in
tmp_unit="$(mktemp)"
trap 'rm -f "$tmp_unit"' EXIT
sed "s#__NEXADRIVE_HOME__#$NEXADRIVE_HOME#g" \
  "$(dirname "$0")/nexadrive-server.service" > "$tmp_unit"
install -m 0644 "$tmp_unit" /etc/systemd/system/nexadrive.service

# Create /etc/nexadrive/server.env if it doesn't exist
if [[ ! -f /etc/nexadrive/server.env ]]; then
  mkdir -p /etc/nexadrive
  install -m 0600 "$(dirname "$0")/../server/.env.example" /etc/nexadrive/server.env
  sed -i "s#DATABASE_PATH=.*#DATABASE_PATH=$NEXADRIVE_HOME/data/nexadrive.db#" /etc/nexadrive/server.env
  sed -i "s#STORAGE_ROOT=.*#STORAGE_ROOT=$NEXADRIVE_HOME/storage#" /etc/nexadrive/server.env
  echo "Created /etc/nexadrive/server.env."
  echo "Before first start, edit it and set:"
  echo "  ADMIN_PASSWORD=<a long random password>"
  echo "  PUBLIC_URL=https://<machine>.<your-network>.ts.net (or your LAN/reverse-proxy host)"
fi

# Set ownership
chown -R "$SERVICE_USER:$SERVICE_GROUP" "$NEXADRIVE_HOME/data"
chown -R "$SERVICE_USER:$SERVICE_GROUP" "$NEXADRIVE_HOME/storage"
chown -R "$SERVICE_USER:$SERVICE_GROUP" "$NEXADRIVE_HOME/backups"
chown -R "$SERVICE_USER:$SERVICE_GROUP" "$NEXADRIVE_HOME/temp"
chown -R "$SERVICE_USER:$SERVICE_GROUP" "$NEXADRIVE_HOME/logs"

systemctl daemon-reload
echo "Installed NexaDrive at $NEXADRIVE_HOME. Start with: sudo systemctl enable --now nexadrive"