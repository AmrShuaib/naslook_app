#!/usr/bin/env bash
# يفعّل لوحة الإدارة على نطاق فرعي (الافتراضي admin.naslife.app) عبر Caddy: يعيد توجيه جذر النطاق الفرعي إلى /admin
# ويمرّر بقية الطلبات إلى تطبيق Naslife. يُشغَّل مرة واحدة على الخادم بعد إضافة سجل DNS من نوع A للنطاق الفرعي:
#   ssh root@91.108.111.246 "curl -fsSL https://raw.githubusercontent.com/AmrShuaib/naslook_app/claude/intelligent-hypatia-owb3fk/server/install-admin-subdomain.sh | bash"
# متغيرات اختيارية: NASLIFE_ADMIN_HOST (النطاق الفرعي)، NASLIFE_PORT (منفذ التطبيق، الافتراضي من وحدة systemd أو 4000).
set -euo pipefail
HOST="${NASLIFE_ADMIN_HOST:-admin.naslife.app}"
PORT="${NASLIFE_PORT:-$(systemctl show naslife -p Environment --value 2>/dev/null | tr ' ' '\n' | grep '^PORT=' | head -1 | cut -d= -f2 || true)}"
PORT="${PORT:-4000}"
CADDYFILE="${CADDYFILE:-/etc/caddy/Caddyfile}"
command -v caddy >/dev/null || { echo "caddy غير مثبّت على هذا الخادم"; exit 1; }
[[ -f "$CADDYFILE" ]] || { echo "لم أجد $CADDYFILE"; exit 1; }
if grep -q "^$HOST" "$CADDYFILE"; then
  echo "$HOST موجود مسبقاً في $CADDYFILE؛ لم يتغير شيء"
else
  cp "$CADDYFILE" "$CADDYFILE.bak-$(date +%s)"
  cat >> "$CADDYFILE" <<BLOCK

# لوحة إدارة Naslife (أُضيف بواسطة install-admin-subdomain.sh)
$HOST {
	encode gzip
	@root path /
	rewrite @root /admin
	reverse_proxy 127.0.0.1:$PORT
}
BLOCK
  caddy validate --config "$CADDYFILE" --adapter caddyfile
  systemctl reload caddy
  echo "أُضيف $HOST إلى Caddy وأُعيد التحميل؛ الشهادة تُصدر تلقائياً عند أول زيارة"
fi
echo "الرمز الأول لإعداد المدير (إن لم يُستخدم بعد):"; cat /opt/naslife/ops/admin-setup-code 2>/dev/null || echo "(لا رمز: تم الإعداد أو لم تُشغَّل الإضافة بعد)"
