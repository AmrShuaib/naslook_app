#!/bin/bash
# يبني نسخة الويب للنشر. الاستخدام: tools/build_web.sh   ثم   tools/publish_bundle.sh "رسالة"
# - بلا Service Worker (--pwa-strategy=none) حتى يصل كل تحديث فوراً.
# - معرّف بناء مضمّن (NASLIFE_BUILD) يكتبه publish_bundle.sh في build.json، فيعرف التطبيق المفتوح أنه قديم حتى لو
#   جاءت صفحته نفسها من مخزن قديم (lib/core/update/app_update.dart).
# - web/sw_reset.js فوق flutter_service_worker.js (Flutter يكتبه فارغاً): يُطفئ عامل الخدمة الذي سجّلته نسخ قديمة.
set -e
ROOT="$(git rev-parse --show-toplevel)"; cd "$ROOT"
ID="$(git rev-parse --short HEAD)-$(date -u +%Y%m%d%H%M%S)"
${FLUTTER:-flutter} build web --release --pwa-strategy=none --dart-define=NASLIFE_BUILD="$ID" -o build/web "$@"
echo "$ID" > build/web/build_id.txt
cp web/sw_reset.js build/web/flutter_service_worker.js
echo "build id: $ID"
