#!/usr/bin/env bash
# تثبيت/تحديث النشر التلقائي على الخادم (آمن للتكرار). يُشغَّل بإحدى الطريقتين:
#   من GitHub Actions: ssh root@HOST "NASLIFE_BRANCH=<branch> bash -s" < server/install-autodeploy.sh
#   يدوياً من أي جهاز:  ssh root@91.108.111.246 "curl -fsSL https://raw.githubusercontent.com/AmrShuaib/naslook_app/<branch>/server/install-autodeploy.sh | NASLIFE_BRANCH=<branch> bash"
# متغيرات اختيارية:
#   NASLIFE_BRANCH         فرع الكود الذي يسحبه الخادم (الافتراضي أدناه)
#   NASLIFE_AUTODEPLOY_SRC مسار نسخة محلية من autodeploy.sh تُستخدم بدل تنزيلها من GitHub
set -euo pipefail

main() {
  local BRANCH="${NASLIFE_BRANCH:-claude/intelligent-hypatia-owb3fk}"
  local RAW="https://raw.githubusercontent.com/AmrShuaib/naslook_app/$BRANCH/server"
  local OPS=/opt/naslife/ops
  mkdir -p "$OPS"
  printf '%s\n' "$BRANCH" > "$OPS/branch"
  if [[ -n "${NASLIFE_AUTODEPLOY_SRC:-}" && -f "$NASLIFE_AUTODEPLOY_SRC" ]]; then
    cp "$NASLIFE_AUTODEPLOY_SRC" "$OPS/autodeploy.sh.new"
  else
    curl -fsSL "$RAW/autodeploy.sh" -o "$OPS/autodeploy.sh.new"
  fi
  bash -n "$OPS/autodeploy.sh.new"
  mv "$OPS/autodeploy.sh.new" "$OPS/autodeploy.sh"
  chmod +x "$OPS/autodeploy.sh"
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
  "$OPS/autodeploy.sh"
  echo "AUTODEPLOY INSTALLED (branch: $BRANCH)"
  tail -5 "$OPS/autodeploy.log" || true
  echo "naslife: $(systemctl is-active naslife || true) | timer: $(systemctl is-active naslife-autodeploy.timer || true)"
}

# يُستدعى مع stdin مغلق حتى لا تلتهم الأوامر بقية السكربت عند تمريره عبر ssh/pipe
main "$@" </dev/null
