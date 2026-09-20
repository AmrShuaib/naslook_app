#!/bin/bash
# يبني صفحات مصغّرات (5×4) لكل صور السوق مع أرقام لمراجعتها، ويطبع خريطة الرقم → الاسم
cd /home/user/naslook_app/web/seed/market
rm -rf /tmp/mkt/sheets; mkdir -p /tmp/mkt/sheets
ls *.jpg | sort > /tmp/mkt/all.txt
i=0; while read -r f; do i=$((i+1)); n=$(printf %03d $i)
  ffmpeg -nostdin -loglevel error -y -i "$f" -vf "scale=320:240,drawbox=0:0:60:26:black@0.7:t=fill,drawtext=text='$i':x=6:y=4:fontsize=20:fontcolor=white" /tmp/mkt/sheets/$n.jpg
  echo "$i ${f%.jpg}"
done < /tmp/mkt/all.txt > /tmp/mkt/index.txt
total=$i; s=0; start=1
while [ $start -le $total ]; do s=$((s+1)); ffmpeg -nostdin -loglevel error -y -start_number $start -i /tmp/mkt/sheets/%03d.jpg -frames:v 1 -filter_complex "tile=5x4" /tmp/mkt/sheet_$s.jpg 2>/dev/null; start=$((start+20)); done
echo "sheets: $s total: $total"
