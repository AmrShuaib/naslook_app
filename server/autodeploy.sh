#!/usr/bin/env bash
# نشر تلقائي لـ Naslife: يسحب webapp-build عند تغيّرها، ويثبّت إضافات الخادم من server/ ويعيد التشغيل عند الحاجة.
# يُشغَّل بمؤقّت systemd كل دقيقتين. السجل: /opt/naslife/ops/autodeploy.log
# فرع الكود يُقرأ من /opt/naslife/ops/branch (يكتبه install-autodeploy.sh) أو من NASLIFE_BRANCH.
set -euo pipefail
REPO="https://github.com/AmrShuaib/naslook_app.git"
ROOT="/opt/naslife"
DEFAULT_BRANCH="claude/intelligent-hypatia-owb3fk"
CODE_BRANCH="${NASLIFE_BRANCH:-$(cat "$ROOT/ops/branch" 2>/dev/null || echo "$DEFAULT_BRANCH")}"
BUILD_BRANCH="webapp-build"
STATE="$ROOT/ops/autodeploy.state"
LOG="$ROOT/ops/autodeploy.log"
mkdir -p "$ROOT/ops" "$ROOT/src"; touch "$STATE"
log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

build_sha=$(git ls-remote "$REPO" "refs/heads/$BUILD_BRANCH" | cut -f1)
code_sha=$(git ls-remote "$REPO" "refs/heads/$CODE_BRANCH" | cut -f1)
last_build=$(grep '^build=' "$STATE" | cut -d= -f2 || true)
last_code=$(grep '^code=' "$STATE" | cut -d= -f2- || true)
restart=0

if [[ -n "$build_sha" && "$build_sha" != "$last_build" ]]; then
  tmp=$(mktemp -d); git clone -q --depth 1 -b "$BUILD_BRANCH" "$REPO" "$tmp/web"
  rm -rf "$tmp/web/.git"   # لا نقدّم مستودع git ضمن الملفات الثابتة
  rm -rf "$ROOT/webapp.old"; [[ -d "$ROOT/webapp" ]] && mv "$ROOT/webapp" "$ROOT/webapp.old"
  mv "$tmp/web" "$ROOT/webapp"; rm -rf "$ROOT/webapp.old" "$tmp"
  log "webapp updated to $build_sha"
fi

# مفتاح الحالة يتضمن اسم الفرع حتى يُعاد النشر عند تغييره
code_key="$CODE_BRANCH@$code_sha"
if [[ -n "$code_sha" && "$code_key" != "$last_code" ]]; then
  tmp=$(mktemp -d); git clone -q --depth 1 -b "$CODE_BRANCH" "$REPO" "$tmp/code"
  if [[ -d "$tmp/code/server" ]]; then
    mkdir -p "$ROOT/ops/rollback"; rm -f "$ROOT/ops/rollback"/*
    for f in "$tmp/code/server"/*.js; do
      [[ -e "$f" ]] || continue
      name=$(basename "$f")
      if ! cmp -s "$f" "$ROOT/src/$name"; then
        # نحتفظ بالنسخة السابقة (أو علامة "كان غير موجود") للتراجع إن فشل التشغيل
        if [[ -f "$ROOT/src/$name" ]]; then cp "$ROOT/src/$name" "$ROOT/ops/rollback/$name"; else : > "$ROOT/ops/rollback/$name.absent"; fi
        cp "$f" "$ROOT/src/$name"; restart=1; log "server plugin $name updated ($CODE_BRANCH)"
      fi
    done
    if [[ -f "$tmp/code/server/register.txt" && -f "$ROOT/src/index.js" ]]; then
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        mod=$(echo "$line" | grep -o '\./[a-z_]*\.js' | head -1)
        [[ -z "$mod" ]] && continue
        if ! grep -qF "$mod" "$ROOT/src/index.js"; then
          if grep -q 'NASLIFE_NO_LISTEN' "$ROOT/src/index.js"; then
            cp "$ROOT/src/index.js" "$ROOT/src/index.js.bak-$(date +%s)"
            [[ -f "$ROOT/ops/rollback/index.js" ]] || cp "$ROOT/src/index.js" "$ROOT/ops/rollback/index.js"
            sed -i "/NASLIFE_NO_LISTEN/i $line" "$ROOT/src/index.js"; restart=1; log "registered $mod"
          else
            log "WARNING: NASLIFE_NO_LISTEN marker not found in index.js; cannot register $mod automatically"
          fi
        fi
      done < "$tmp/code/server/register.txt"
    fi
  fi
  rm -rf "$tmp"
fi

if [[ $restart -eq 1 ]]; then
  if node --check "$ROOT/src/index.js" 2>>"$LOG"; then
    systemctl restart naslife && log "naslife restarted"
    # فحص صحي: إن لم تستقر الخدمة خلال 60 ثانية نتراجع عن تغييرات الخادم ونعيد التشغيل
    ok=0
    # منفذ التطبيق: من NASLIFE_PORT أو من بيئة وحدة systemd (PORT=...) ثم المنافذ الشائعة
    unit_port=$(systemctl show naslife -p Environment --value 2>/dev/null | tr ' ' '\n' | grep '^PORT=' | head -1 | cut -d= -f2 || true)
    for i in $(seq 1 12); do
      sleep 5
      systemctl is-active --quiet naslife || continue
      for p in ${NASLIFE_PORT:-} ${unit_port:-} 4000 3000 8080; do
        if curl -fsS -m 5 "http://127.0.0.1:$p/health" >/dev/null 2>&1; then ok=1; log "health ok on port $p"; break 2; fi
      done
    done
    if [[ $ok -eq 0 ]] && systemctl is-active --quiet naslife && [[ -z "$(command -v curl)" ]]; then ok=1; fi
    if [[ $ok -eq 0 ]]; then
      log "HEALTH CHECK FAILED after restart; rolling back server changes"
      for b in "$ROOT/ops/rollback"/*; do
        [[ -e "$b" ]] || continue
        bn=$(basename "$b")
        if [[ "$bn" == *.absent ]]; then rm -f "$ROOT/src/${bn%.absent}"; else cp "$b" "$ROOT/src/$bn"; fi
      done
      systemctl restart naslife && log "naslife restarted after rollback ($(systemctl is-active naslife))"
      # لا نحدّث حالة الكود حتى تُعاد المحاولة مع الدفعة التالية
      code_key="$last_code"
    fi
  else
    log "SYNTAX ERROR in index.js, restart skipped"
  fi
fi
printf 'build=%s\ncode=%s\n' "$build_sha" "$code_key" > "$STATE"
