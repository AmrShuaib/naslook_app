#!/bin/bash
# ينشر build/web إلى فرع webapp-build (الخادم يسحبه تلقائياً كل دقيقتين).
# الاستخدام: tools/publish_bundle.sh "رسالة النشر"   (بعد tools/build_web.sh)
set -e
ROOT="$(git rev-parse --show-toplevel)"; WB="${NASLIFE_WB:-$ROOT/.wb}"; MSG="${1:-Web build}"
[ -f "$ROOT/build/web/main.dart.js" ] || { echo "لا يوجد build/web؛ ابنِ الويب أولاً"; exit 1; }
cd "$ROOT" && git fetch -q origin webapp-build
if [ ! -d "$WB/.git" ] && [ ! -f "$WB/.git" ]; then git worktree add -q --detach "$WB" origin/webapp-build; fi
cd "$WB" && git checkout -q --detach origin/webapp-build && find . -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} + && cp -r "$ROOT/build/web/." .
# مفتاح إطفاء عامل الخدمة القديم (web/sw_reset.js) مكان الملف الفارغ الذي يكتبه Flutter، حتى لو بُني بلا tools/build_web.sh
cp "$ROOT/web/sw_reset.js" flutter_service_worker.js
# معرّف البناء لا يُكتب إلا إن كان مضمّناً فعلاً في main.dart.js؛ معرّف لا يطابق الحزمة يُظهر شريط التحديث بلا نهاية
ID="$(cat build_id.txt 2>/dev/null || true)"
if [ -n "$ID" ] && ! grep -qF "$ID" main.dart.js; then echo "تنبيه: build_id.txt لا يطابق main.dart.js؛ يُنشر بلا معرّف"; ID=""; fi
[ -n "$ID" ] || echo "تنبيه: بلا معرّف بناء (ابنِ بـ tools/build_web.sh)؛ التطبيق يقارن بصمة أول قراءة فقط"
# بصمة الحزمة للتطبيق المفتوح (lib/core/update/app_update.dart يقارنها كل عشر دقائق وعند العودة ويعرض «تحديث الآن»)
printf '{"bundle":"%s","id":"%s","code":"%s","at":"%s"}\n' "$(md5sum main.dart.js | cut -c1-12)" "$ID" "$(git -C "$ROOT" rev-parse --short HEAD)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > build.json
git add -A && git commit -q -m "$MSG" && git push -q origin HEAD:webapp-build && git log --oneline -1 && md5sum main.dart.js | cut -c1-12
