#!/bin/bash
# يجلب صورة لكل عرض من loremflickr بوسومه، يمنع التكرار، ويعيد ترميزها 640×480 إلى web/seed/market/<slug>.jpg
cd /home/user/naslook_app
OUT=web/seed/market; mkdir -p "$OUT" /tmp/mkt
node -e 'import("./server/market_seed_data.js").then(({LISTINGS})=>{for(const l of LISTINGS)console.log(l.slug+"\t"+l.photo)})' > /tmp/mkt/list.tsv
declare -A seen; n=0; ok=0; fail=0
while IFS=$'\t' read -r slug photo; do
  n=$((n+1)); dest="$OUT/$slug.jpg"; [ -s "$dest" ] && { ok=$((ok+1)); continue; }
  tags=$(echo "$photo" | tr 'A-Z' 'a-z' | sed 's/ //g'); first=${tags%%,*}
  got=""; IFS=',' read -ra parts <<< "$tags"
  urls=("https://loremflickr.com/640/480/$tags/all?lock=$n" "https://loremflickr.com/640/480/$tags?lock=$n")
  for t in "${parts[@]}"; do urls+=("https://loremflickr.com/640/480/$t?lock=$n" "https://loremflickr.com/640/480/$t?lock=$((n+53))"); done
  urls+=("https://loremflickr.com/640/480/$first" "https://loremflickr.com/640/480/product")
  for url in "${urls[@]}"; do
    curl -sS -m 40 -L -o /tmp/mkt/raw.jpg "$url" 2>/dev/null </dev/null || continue
    sz=$(stat -c %s /tmp/mkt/raw.jpg 2>/dev/null || echo 0); [ "$sz" -lt 6000 ] && continue
    file /tmp/mkt/raw.jpg </dev/null | grep -q "JPEG\|PNG\|WebP" || continue
    h=$(md5sum /tmp/mkt/raw.jpg | cut -c1-12); [ -n "${seen[$h]}" ] && continue
    seen[$h]=1; got=$url; break
  done
  if [ -z "$got" ]; then echo "FAIL $slug ($photo)"; fail=$((fail+1)); continue; fi
  ffmpeg -nostdin -loglevel error -y -i /tmp/mkt/raw.jpg -vf "scale=640:480:force_original_aspect_ratio=increase,crop=640:480" -q:v 5 "$dest" && ok=$((ok+1)) && echo "OK $slug $(stat -c %s "$dest") $got" || { echo "FAIL-ENC $slug"; fail=$((fail+1)); }
  sleep 0.4
done < /tmp/mkt/list.tsv
echo "DONE ok=$ok fail=$fail total=$n"; du -sh "$OUT"
