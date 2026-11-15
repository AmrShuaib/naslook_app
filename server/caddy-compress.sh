#!/usr/bin/env bash
# تفعيل ضغط الردود لموقع naslife.app في Caddy (آمن للتكرار).
# السبب: فحص 15 نوفمبر 2026 أظهر أن الموقع الحي يرسل main.dart.js (نحو 7 ميغابايت) بلا ضغط: لا ترويسة content-encoding
# ولا «vary: Accept-Encoding»، فكل فتح أول للتطبيق ينزّل الملف كاملاً. مع الضغط يصير نحو 2 ميغابايت.
# ماذا يفعل: يضيف السطر «encode zstd gzip» داخل كتلة naslife.app إن لم يكن موجوداً، يتحقق من الإعداد، يعيد تحميل Caddy،
# ويتراجع إلى النسخة الاحتياطية إن فشل التحقق. لا يلمس كتلة areebd.sa ولا أي شيء آخر.
# التشغيل (من جهازك، بعلامات اقتباس مفردة):
#   ssh root@91.108.111.246 'curl -fsSL https://raw.githubusercontent.com/AmrShuaib/naslook_app/claude/intelligent-hypatia-owb3fk/server/caddy-compress.sh | bash'
set -euo pipefail

CADDYFILE="${CADDYFILE:-/etc/caddy/Caddyfile}"
log() { printf '[caddy-compress] %s\n' "$*"; }
check() { curl -sS -m 30 -o /dev/null -D - -H 'Accept-Encoding: gzip' https://naslife.app/flutter_bootstrap.js | tr -d '\r' | grep -i '^content-encoding:' || true; }

command -v caddy >/dev/null || { log "caddy غير مثبّت"; exit 1; }
[[ -f "$CADDYFILE" ]] || { log "لم أجد $CADDYFILE"; exit 1; }

START=$(grep -nE '^[[:space:]]*naslife\.app[[:space:],{]' "$CADDYFILE" | head -1 | cut -d: -f1 || true)
[[ -n "$START" ]] || { log "لم أجد كتلة naslife.app في $CADDYFILE؛ لم أغيّر شيئاً"; exit 1; }
# نهاية الكتلة: أول سطر «}» في أول العمود بعد بدايتها
END=$(awk -v s="$START" 'NR>s && /^}/ {print NR; exit}' "$CADDYFILE")
[[ -n "$END" ]] || { log "لم أجد نهاية كتلة naslife.app؛ لم أغيّر شيئاً"; exit 1; }

log "قبل: $(check | head -1 || true)"
if sed -n "${START},${END}p" "$CADDYFILE" | grep -qE '^[[:space:]]*encode([[:space:]]|$)'; then
  log "السطر encode موجود أصلاً في الكتلة؛ سأعيد التحميل فقط"
else
  BACKUP="$CADDYFILE.bak.compress.$(date +%Y%m%d%H%M%S)"; cp "$CADDYFILE" "$BACKUP"; log "نسخة احتياطية: $BACKUP"
  awk -v s="$START" '{print} NR==s {print "\tencode zstd gzip"}' "$CADDYFILE" > "$CADDYFILE.tmp" && cat "$CADDYFILE.tmp" > "$CADDYFILE" && rm -f "$CADDYFILE.tmp"
  log "أضفت «encode zstd gzip» إلى كتلة naslife.app"
fi

if ! caddy validate --config "$CADDYFILE" --adapter caddyfile >/dev/null 2>&1; then
  [[ -n "${BACKUP:-}" ]] && cp "$BACKUP" "$CADDYFILE" && log "فشل التحقق من الإعداد؛ أعدت النسخة الاحتياطية ولم يتغير شيء"
  exit 1
fi
systemctl reload caddy || systemctl restart caddy
sleep 3
AFTER="$(check | head -1 || true)"
log "بعد: ${AFTER:-لا ترويسة content-encoding}"
if [[ -n "$AFTER" ]]; then log "تم: الضغط يعمل"; else log "الضغط لم يظهر بعد. الكتلة الحالية:"; sed -n "${START},$((END + 1))p" "$CADDYFILE"; fi
log "الموقع: $(curl -sS -m 20 -o /dev/null -w '%{http_code}' https://naslife.app/settings/public || echo 'لم يستجب')"
