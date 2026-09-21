#!/usr/bin/env bash
# استعادة موقع naslife.app في Caddy بعد أن فُقد من الإعداد الجاري (آمن للتكرار).
# الأعراض: https://naslife.app يفشل في TLS (لا شهادة) و http://naslife.app يعرض «Caddy works!».
# السبب المعتاد: إعداد naslife لم يكن محفوظاً في /etc/caddy/Caddyfile فأُعيد تحميل الملف الافتراضي عند إضافة موقع آخر.
# التشغيل على الخادم:  ssh root@91.108.111.246 "bash -s" < server/restore-caddy.sh
#   أو:  curl -fsSL https://raw.githubusercontent.com/AmrShuaib/naslook_app/claude/intelligent-hypatia-owb3fk/server/restore-caddy.sh | bash
# متغيرات اختيارية: NASLIFE_PORT (منفذ خدمة Node، الافتراضي من وحدة systemd ثم 4000)، CADDYFILE، NASLIFE_ADMIN_HOST=1 لإضافة admin.naslife.app
set -euo pipefail

CADDYFILE="${CADDYFILE:-/etc/caddy/Caddyfile}"
PORT="${NASLIFE_PORT:-$(systemctl show naslife -p Environment --value 2>/dev/null | tr ' ' '\n' | grep '^PORT=' | head -1 | cut -d= -f2 || true)}"
PORT="${PORT:-4000}"
log() { printf '[restore-caddy] %s\n' "$*"; }

command -v caddy >/dev/null || { log "caddy غير مثبّت"; exit 1; }
[[ -f "$CADDYFILE" ]] || { log "لم أجد $CADDYFILE"; exit 1; }

log "خدمة naslife: $(systemctl is-active naslife 2>/dev/null || echo unknown) · المنفذ $PORT"
if curl -fsS -m 5 "http://127.0.0.1:$PORT/settings/public" >/dev/null 2>&1; then log "Node يرد على 127.0.0.1:$PORT"; else log "تحذير: Node لا يرد على 127.0.0.1:$PORT (سأكمل إعداد Caddy، وأعد تشغيل naslife بعدها إن لزم)"; fi

log "ملفات فيها naslife.app (للمعرفة فقط):"
grep -rl "naslife.app" /etc/caddy /opt/naslife /root 2>/dev/null | grep -v "\.bak" | sed 's/^/  /' || echo "  لا شيء"
ls -1 "$CADDYFILE".bak* 2>/dev/null | sed 's/^/  نسخة احتياطية: /' || true

if grep -Eq '^[[:space:]]*(naslife\.app|www\.naslife\.app)[[:space:],{]' "$CADDYFILE"; then
  log "كتلة naslife.app موجودة أصلاً في $CADDYFILE؛ سأتحقق من الإعداد وأعيد التحميل فقط"
else
  BACKUP="$CADDYFILE.bak.restore.$(date +%Y%m%d%H%M%S)"; cp "$CADDYFILE" "$BACKUP"; log "نسخة احتياطية: $BACKUP"
  # إزالة كتلة الافتراضي «:80 { root * /usr/share/caddy ... }» إن كانت هي كتلة الحزمة القياسية
  if grep -q '^:80 {' "$CADDYFILE" && grep -q '/usr/share/caddy' "$CADDYFILE"; then
    awk 'BEGIN{skip=0} /^:80 \{/{skip=1} skip&&/^}/{skip=0; next} !skip{print}' "$CADDYFILE" > "$CADDYFILE.tmp" && cat "$CADDYFILE.tmp" > "$CADDYFILE" && rm -f "$CADDYFILE.tmp"
    log "أزلت كتلة :80 الافتراضية (صفحة Caddy works!)"
  fi
  CSP="default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob: https://server.arcgisonline.com; media-src 'self' blob:; font-src 'self' data: https://fonts.gstatic.com; connect-src 'self' wss://naslife.app wss://www.naslife.app https://server.arcgisonline.com https://fonts.gstatic.com; worker-src 'self' blob:; manifest-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'; object-src 'none'"
  cat >> "$CADDYFILE" <<BLOCK

# --- naslife.app (managed by server/restore-caddy.sh in naslook_app) ---
www.naslife.app {
	redir https://naslife.app{uri} permanent
}

naslife.app {
	encode zstd gzip
	header {
		Content-Security-Policy "$CSP"
		X-Content-Type-Options "nosniff"
		Referrer-Policy "strict-origin-when-cross-origin"
		-Server
	}
	reverse_proxy 127.0.0.1:$PORT
}
# --- end naslife.app ---
BLOCK
  if [[ "${NASLIFE_ADMIN_HOST:-0}" == "1" ]] && ! grep -q '^admin\.naslife\.app' "$CADDYFILE"; then
    printf '\nadmin.naslife.app {\n\treverse_proxy 127.0.0.1:%s\n}\n' "$PORT" >> "$CADDYFILE"
  fi
  log "أُضيفت كتلة naslife.app إلى $CADDYFILE"
fi

if ! caddy validate --config "$CADDYFILE" --adapter caddyfile; then
  [[ -n "${BACKUP:-}" ]] && cp "$BACKUP" "$CADDYFILE" && log "فشل التحقق؛ أعدت $BACKUP"
  exit 1
fi
systemctl reload caddy || systemctl restart caddy
sleep 4
log "فحص: $(curl -sS -m 20 -o /dev/null -w 'https://naslife.app/settings/public → %{http_code}' https://naslife.app/settings/public || echo 'لم يستجب بعد؛ إصدار الشهادة قد يستغرق دقيقة، أعد الفحص: curl -I https://naslife.app')"
log "فحص: $(curl -sS -m 20 -o /dev/null -w 'https://areebd.sa → %{http_code}' https://areebd.sa/ || echo 'areebd.sa لم يستجب')"
