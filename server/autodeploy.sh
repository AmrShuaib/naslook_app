#!/usr/bin/env bash
# نشر تلقائي لـ Naslife: يسحب webapp-build عند تغيّرها، ويثبّت إضافات الخادم من server/ ويعيد التشغيل عند الحاجة.
# يُشغَّل بمؤقّت systemd كل دقيقتين. السجل: /opt/naslife/ops/autodeploy.log
set -euo pipefail
REPO="https://github.com/AmrShuaib/naslook_app.git"
CODE_BRANCH="claude/naslife-v2-flutter-web-2e4p9u"
BUILD_BRANCH="webapp-build"
ROOT="/opt/naslife"
STATE="$ROOT/ops/autodeploy.state"
LOG="$ROOT/ops/autodeploy.log"
mkdir -p "$ROOT/ops"; touch "$STATE"
log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

build_sha=$(git ls-remote "$REPO" "refs/heads/$BUILD_BRANCH" | cut -f1)
code_sha=$(git ls-remote "$REPO" "refs/heads/$CODE_BRANCH" | cut -f1)
last_build=$(grep '^build=' "$STATE" | cut -d= -f2 || true)
last_code=$(grep '^code=' "$STATE" | cut -d= -f2 || true)
restart=0

if [[ -n "$build_sha" && "$build_sha" != "$last_build" ]]; then
  tmp=$(mktemp -d); git clone -q --depth 1 -b "$BUILD_BRANCH" "$REPO" "$tmp/web"
  rm -rf "$ROOT/webapp.old"; [[ -d "$ROOT/webapp" ]] && mv "$ROOT/webapp" "$ROOT/webapp.old"
  mv "$tmp/web" "$ROOT/webapp"; rm -rf "$ROOT/webapp.old" "$tmp"
  log "webapp updated to $build_sha"
fi

if [[ -n "$code_sha" && "$code_sha" != "$last_code" ]]; then
  tmp=$(mktemp -d); git clone -q --depth 1 -b "$CODE_BRANCH" "$REPO" "$tmp/code"
  if [[ -d "$tmp/code/server" ]]; then
    for f in "$tmp/code/server"/*.js; do
      [[ -e "$f" ]] || continue
      name=$(basename "$f")
      if ! cmp -s "$f" "$ROOT/src/$name"; then cp "$f" "$ROOT/src/$name"; restart=1; log "server plugin $name updated"; fi
    done
    if [[ -f "$tmp/code/server/register.txt" ]]; then
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        mod=$(echo "$line" | grep -o '\./[a-z_]*\.js' | head -1)
        if ! grep -qF "$mod" "$ROOT/src/index.js"; then
          cp "$ROOT/src/index.js" "$ROOT/src/index.js.bak-$(date +%s)"
          sed -i "/NASLIFE_NO_LISTEN/i $line" "$ROOT/src/index.js"; restart=1; log "registered $mod"
        fi
      done < "$tmp/code/server/register.txt"
    fi
  fi
  rm -rf "$tmp"
fi

if [[ $restart -eq 1 ]]; then
  if node --check "$ROOT/src/index.js" 2>>"$LOG"; then systemctl restart naslife && log "naslife restarted"; else log "SYNTAX ERROR in index.js, restart skipped"; fi
fi
printf 'build=%s\ncode=%s\n' "$build_sha" "$code_sha" > "$STATE"
