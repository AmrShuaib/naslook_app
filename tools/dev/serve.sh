#!/usr/bin/env bash
# يعيد تشغيل خادم الملفات الثابتة (8091) وخادم API الوهمي (8090) بلا pkill: نجد PID من المنفذ عبر /proc.
S=$(cd "$(dirname "$0")" && pwd)
kill_port() { local hex; hex=$(printf '%04X' "$1"); for inode in $(awk -v h=":$hex" '$2 ~ h && $4=="0A" {print $10}' /proc/net/tcp /proc/net/tcp6 2>/dev/null); do for fd in /proc/[0-9]*/fd/*; do if [ "$(readlink "$fd" 2>/dev/null)" = "socket:[$inode]" ]; then pid=${fd#/proc/}; pid=${pid%%/*}; [ "$pid" != "$$" ] && kill "$pid" 2>/dev/null && echo "killed $pid on port $1"; fi; done; done; }
kill_port 8091; kill_port 8090; sleep 1
(cd "$S/web-mock" && setsid nohup python3 -m http.server 8091 --bind 127.0.0.1 > "$S/http2.log" 2>&1 < /dev/null &)
(cd "$S" && setsid nohup node mockapi.mjs > "$S/mockapi.log" 2>&1 < /dev/null &)
sleep 1.5
curl -sS -o /dev/null -w "static 8091: %{http_code}\n" http://127.0.0.1:8091/flutter_bootstrap.js
curl -sS -o /dev/null -w "api 8090: %{http_code}\n" http://127.0.0.1:8090/messages/SA0000002
