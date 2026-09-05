#!/usr/bin/env bash
# بناء نسخة الويب ورفعها إلى خادم Naslife.
# الاستخدام: ./deploy.sh            (بناء + رفع)
#            ./deploy.sh --no-build  (رفع build/web الموجود فقط)
set -euo pipefail

HOST="${NASLIFE_HOST:-root@91.108.111.246}"
DEST="${NASLIFE_WEBAPP_DIR:-/opt/naslife/webapp}"

if [[ "${1:-}" != "--no-build" ]]; then
  flutter build web --release
fi

[[ -f build/web/index.html ]] || { echo "build/web غير موجود؛ شغّل flutter build web أولاً" >&2; exit 1; }

ssh "$HOST" "mkdir -p '$DEST'"
# رفع مؤقت ثم تبديل ذرّي حتى لا يرى المستخدمون نسخة نصف مرفوعة
scp -r build/web "$HOST:$DEST.new"
ssh "$HOST" "rm -rf '$DEST.old' && { [ -d '$DEST' ] && mv '$DEST' '$DEST.old' || true; } && mv '$DEST.new' '$DEST' && rm -rf '$DEST.old'"
echo "تم الرفع إلى $HOST:$DEST (الملفات ثابتة؛ لا حاجة لإعادة تشغيل خدمة naslife)"
