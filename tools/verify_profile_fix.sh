#!/bin/bash
# تحقق حي: حساب جديد بلا صف ملف → تعديل النبذة من الإدارة يُنشئ الصف → ثم حذف نهائي
T="${NASLIFE_TOKEN:?ضع رمز جلسة المؤسس في NASLIFE_TOKEN}"
B=https://naslife.app
N=probe_zz_0917c
sleep 150
echo "== register"
R=$(curl -sS -m 20 -H 'content-type: application/json' -d "{\"handle\":\"$N\",\"nickname\":\"$N\",\"password\":\"Probe-Pass-2026\"}" $B/register)
echo "$R" | head -c 300; echo
ID=$(echo "$R" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("id") or d.get("user",{}).get("id",""))')
PT=$(echo "$R" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("token",""))')
echo "id=$ID"
[ -z "$ID" ] && exit 1
echo "== profile before"; curl -sS -m 20 -H "x-token: $PT" $B/profiles/$ID | head -c 300; echo
echo "== admin patch"; curl -sS -m 20 -X PATCH -H "x-token: $T" -H 'content-type: application/json' -d '{"bio":"نبذة كتبتها الإدارة","isPublic":false}' $B/adminapi/users/$ID | head -c 300; echo
echo "== profile after (own token)"; curl -sS -m 20 -H "x-token: $PT" $B/profiles/$ID | head -c 300; echo
echo "== profile after (admin token)"; curl -sS -m 20 -H "x-token: $T" $B/profiles/$ID | head -c 300; echo
echo "== delete"; curl -sS -m 20 -X DELETE -H "x-token: $T" -H 'content-type: application/json' -d "{\"confirm\":\"$N\"}" $B/adminapi/users/$ID | head -c 400; echo
echo "== nickname free?"; curl -sS -m 20 "$B/auth/nickname-available?nickname=$N" | head -c 200; echo
