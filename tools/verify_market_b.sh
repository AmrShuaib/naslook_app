#!/bin/bash
# فحص حي للمرحلة (ب): الإضافة مسجّلة، البازارات، إعداد الدفع، بطاقة الشات، معاينة الترقية، صفحة المشاركة
T="${NASLIFE_TOKEN:?ضع رمز جلسة المؤسس في NASLIFE_TOKEN}"; B=https://naslife.app; Q="lat=21.5433&lng=39.1728"
echo "bundle md5: $(curl -sS -m 30 $B/main.dart.js | md5sum | cut -c1-12)  local: $(md5sum /home/user/naslook_app/build/web/main.dart.js | cut -c1-12)"
curl -sS -m 20 -H "x-token: $T" "$B/market/bazaars" | head -c 300; echo
curl -sS -m 20 -H "x-token: $T" "$B/pay/config"; echo
curl -sS -m 20 -H "x-token: $T" "$B/market/seller/upgrade" | head -c 300; echo
curl -sS -m 20 -H "x-token: $T" "$B/market/home?$Q" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("home: spotlight", len(d["spotlight"]), "bazaars", d.get("bazaars"))'
LID=$(curl -sS -m 20 -H "x-token: $T" "$B/market?$Q" | python3 -c 'import json,sys; l=json.load(sys.stdin); print(l[0]["id"])')
curl -sS -m 20 -H "x-token: $T" "$B/chat/cards?refs=%23mk/$LID" | python3 -c 'import json,sys; d=json.load(sys.stdin); c=list(d["refs"].values())[0]; print("chat card:", {k: c.get(k) for k in ("title","subtitle","price","kind","verified","left")})'
curl -sS -m 15 -o /dev/null -w "share page /l/: %{http_code}\n" "$B/l/$LID"
curl -sS -m 20 -H "x-token: $T" "$B/adminapi/market/bazaars" | head -c 200; echo
curl -sS -m 20 -H "x-token: $T" "$B/adminapi/payments" | head -c 200; echo
