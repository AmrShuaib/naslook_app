#!/bin/bash
# فحص حي بعد النشر: الحزمة، صور التمهيد، عروض السوق، تفاصيل مستخدم في الإدارة
T="${NASLIFE_TOKEN:?ضع رمز جلسة المؤسس في NASLIFE_TOKEN}"; B=https://naslife.app
echo "bundle md5: $(curl -sS -m 30 $B/main.dart.js | md5sum | cut -c1-12)  local: $(md5sum /home/user/naslook_app/build/web/main.dart.js | cut -c1-12)"
curl -sS -m 15 -o /dev/null -w "seed image kabsa: %{http_code} %{content_type} %{size_download}B\n" $B/seed/market/kabsa-tray-large.jpg
curl -sS -m 15 -o /dev/null -w "credits.json: %{http_code}\n" $B/seed/market/credits.json
curl -sS -m 20 -H "x-token: $T" "$B/market" | python3 -c '
import json,sys; l=json.load(sys.stdin); seed=[x for x in l if "/seed/market/" in (x.get("imageUrl") or "")]
cats={}; sellers=set()
for x in seed: cats[x["category"]]=cats.get(x["category"],0)+1; sellers.add(x["seller"]["nickname"])
print("market total", len(l), "seeded", len(seed), "sellers", len(sellers)); print("by category", cats)
print("sample:", [(x["title"][:30], x["price"]//100, x["placeName"]) for x in seed[:3]])'
curl -sS -m 20 -H "x-token: $T" "$B/adminapi/users?q=um_fahad" | python3 -c 'import json,sys; l=json.load(sys.stdin); print("um_fahad_kitchen:", [(u["id"], u["nickname"], u.get("email")) for u in l])'
curl -sS -m 20 -H "x-token: $T" "$B/adminapi/users/SA9954961" | python3 -c '
import json,sys; d=json.load(sys.stdin); print("detail keys", [k for k in ("personal","profile","emails","recovery","sessions","counts") if k in d]); print("emails", d.get("emails")); print("personal keys", list((d.get("personal") or {}).keys())); print("profile keys", list((d.get("profile") or {}).keys())); print("sessions", d.get("sessions")); print("counts", d.get("counts"))'
