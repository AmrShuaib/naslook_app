#!/bin/bash
# ينشر build/web إلى فرع webapp-build (الخادم يسحبه تلقائياً كل دقيقتين).
# الاستخدام: tools/publish_bundle.sh "رسالة النشر"   (بعد flutter build web --release --pwa-strategy=none -o build/web)
set -e
ROOT="$(git rev-parse --show-toplevel)"; WB="${NASLIFE_WB:-$ROOT/.wb}"; MSG="${1:-Web build}"
[ -f "$ROOT/build/web/main.dart.js" ] || { echo "لا يوجد build/web؛ ابنِ الويب أولاً"; exit 1; }
cd "$ROOT" && git fetch -q origin webapp-build
if [ ! -d "$WB/.git" ] && [ ! -f "$WB/.git" ]; then git worktree add -q --detach "$WB" origin/webapp-build; fi
cd "$WB" && git checkout -q --detach origin/webapp-build && find . -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} + && cp -r "$ROOT/build/web/." .
git add -A && git commit -q -m "$MSG" && git push -q origin HEAD:webapp-build && git log --oneline -1 && md5sum main.dart.js | cut -c1-12
