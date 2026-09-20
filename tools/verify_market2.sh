#!/bin/bash
# فحص حي لسوق الإصدار الثاني بعد النشر
T="${NASLIFE_TOKEN:?ضع رمز جلسة المؤسس في NASLIFE_TOKEN}"; B=https://naslife.app; Q="lat=21.5433&lng=39.1728"
echo "bundle md5: $(curl -sS -m 30 $B/main.dart.js | md5sum | cut -c1-12)  local: $(md5sum /home/user/naslook_app/build/web/main.dart.js | cut -c1-12)"
curl -sS -m 20 -H "x-token: $T" "$B/market/home?$Q" | python3 -c '
import json,sys; d=json.load(sys.stdin)
print("home keys:", sorted(d.keys()))
print("spotlight:", len(d.get("spotlight") or []), "popular:", len(d.get("popular") or []), "nearby:", len(d.get("nearby") or []), "categories:", d.get("categories"), "wantedOpen:", d.get("wantedOpen"), "price/day:", d.get("spotlightPricePerDay"), "commission%:", d.get("commissionPct"))'
curl -sS -m 20 -H "x-token: $T" "$B/market?category=food&sub=sweets&sort=near&$Q" | python3 -c '
import json,sys; l=json.load(sys.stdin); print("food/sweets near:", len(l), [(x["title"][:22], x.get("subcategory"), x.get("distanceKm"), x.get("sellerBadges")) for x in l[:3]])'
curl -sS -m 20 -H "x-token: $T" "$B/market?sort=cheap&delivery=1&max=5000&$Q" | python3 -c '
import json,sys; l=json.load(sys.stdin); print("cheap+delivery<=50:", len(l), [ (x["title"][:22], x["price"]) for x in l[:3]])'
curl -sS -m 20 -H "x-token: $T" "$B/market/spotlight/price" ; echo
curl -sS -m 20 -H "x-token: $T" "$B/market/spotlight?$Q" | python3 -c 'import json,sys; l=json.load(sys.stdin); print("spotlight strip:", len(l), [x.get("listing",{}).get("title","")[:20] for x in l[:4]])'
curl -sS -m 20 -H "x-token: $T" "$B/market/wanted?$Q" | python3 -c 'import json,sys; l=json.load(sys.stdin); print("wanted:", len(l))'
SID=$(curl -sS -m 20 -H "x-token: $T" "$B/market?category=coffee&$Q" | python3 -c 'import json,sys; l=json.load(sys.stdin); print(l[0]["seller"]["id"] if l else "")')
[ -n "$SID" ] && curl -sS -m 20 -H "x-token: $T" "$B/market/sellers/$SID" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("seller:", (d.get("user") or d.get("seller") or {}).get("nickname"), "badges", d.get("badges"), "listings", len(d.get("listings") or []), "rating", d.get("ratingAvg"), "followers", d.get("followers"))'
curl -sS -m 20 -H "x-token: $T" "$B/adminapi/market/overview" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("admin overview:", {k: d.get(k) for k in ("listings","ordersOpen","disputesOpen","gmv30","commission30","spotlightActive")})'
curl -sS -m 20 -H "x-token: $T" "$B/adminapi/settings" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("settings:", {k: d.get(k) for k in ("marketCommissionPct","spotlightPricePerDay","spotlightMaxDays","spotlightMaxActive","marketReviewNewAccounts","marketBlockContacts")})'
curl -sS -m 15 -o /dev/null -w "share page /l/: %{http_code}\n" "$B/l/$(curl -sS -m 20 -H "x-token: $T" "$B/market?$Q" | python3 -c 'import json,sys; l=json.load(sys.stdin); print(l[0]["id"] if l else "x")')"
