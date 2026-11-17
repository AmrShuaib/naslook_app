#!/usr/bin/env bash
# Move the Naslife service from root to a dedicated system user with a hardened systemd unit.
# Idempotent; run as root on the VPS:  bash /opt/naslife/ops/install-service.sh
# Rolls back to the previous unit automatically if the service does not come up healthy.
set -euo pipefail
APP=/opt/naslife
UNIT=/etc/systemd/system/naslife.service

id -u naslife >/dev/null 2>&1 || useradd --system --home-dir "$APP" --shell /usr/sbin/nologin naslife
echo "user: $(id naslife)"

# ownership: code read-only for the service, uploads writable, secrets readable by the service only
chown -R root:naslife "$APP/src" "$APP/node_modules" "$APP/package.json" "$APP/package-lock.json" 2>/dev/null || true
chmod -R o-rwx "$APP/src" "$APP/node_modules"
chown root:naslife "$APP/.env" && chmod 640 "$APP/.env"
chown -R naslife:naslife "$APP/uploads" && chmod 750 "$APP/uploads" && find "$APP/uploads" -type f -exec chmod 640 {} +
chown -R root:naslife "$APP/webapp" && find "$APP/webapp" -type d -exec chmod 750 {} + && find "$APP/webapp" -type f -exec chmod 640 {} +
chmod 700 "$APP/backups"                          # backups stay root-only
chown root:naslife "$APP" && chmod 750 "$APP"

# Postgres: the service keeps using the naslife role over TCP (password in .env), nothing to change there.

cp "$UNIT" "$UNIT.bak-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
install -m 644 "$APP/ops/naslife.service" "$UNIT"
systemctl daemon-reload
systemctl restart naslife
sleep 3
if systemctl is-active --quiet naslife && curl -fsS http://127.0.0.1:4000/health >/dev/null; then
  echo "service healthy as user: $(ps -o user= -p "$(systemctl show -p MainPID --value naslife)")"
  ls -la --time-style=+%H:%M "$APP/uploads/.incoming" | head -2
else
  echo "service failed under the new unit; rolling back"; journalctl -u naslife --since "-1min" --no-pager | tail -20
  latest=$(ls -t "$UNIT".bak-* | head -1); cp "$latest" "$UNIT"; systemctl daemon-reload; systemctl restart naslife
  exit 1
fi
