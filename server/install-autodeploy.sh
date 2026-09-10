#!/usr/bin/env bash
# تثبيت النشر التلقائي (مرة واحدة): curl -fsSL <raw>/server/install-autodeploy.sh | bash
set -euo pipefail
RAW="https://raw.githubusercontent.com/AmrShuaib/naslook_app/claude/naslife-v2-flutter-web-2e4p9u/server"
mkdir -p /opt/naslife/ops
curl -fsSL "$RAW/autodeploy.sh" -o /opt/naslife/ops/autodeploy.sh
chmod +x /opt/naslife/ops/autodeploy.sh
cat > /etc/systemd/system/naslife-autodeploy.service <<'UNIT'
[Unit]
Description=Naslife auto-deploy from GitHub
After=network-online.target
[Service]
Type=oneshot
ExecStart=/opt/naslife/ops/autodeploy.sh
UNIT
cat > /etc/systemd/system/naslife-autodeploy.timer <<'UNIT'
[Unit]
Description=Run Naslife auto-deploy every 2 minutes
[Timer]
OnBootSec=1min
OnUnitActiveSec=2min
AccuracySec=20s
[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now naslife-autodeploy.timer
/opt/naslife/ops/autodeploy.sh
echo "AUTODEPLOY INSTALLED"; tail -5 /opt/naslife/ops/autodeploy.log; systemctl is-active naslife
