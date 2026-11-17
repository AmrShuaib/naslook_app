#!/usr/bin/env bash
# Every 5 minutes (cron): if the API or its database is unhealthy, restart the service once and record it.
# Log: /var/log/naslife-health.log — tail it, or ship it to any external monitor (UptimeRobot/healthchecks.io
# hitting https://naslife.app/health is the recommended second pair of eyes; it needs an account, so it is not
# set up from here).
set -uo pipefail
LOG=/var/log/naslife-health.log
now() { date "+%Y-%m-%d %H:%M:%S"; }
body=$(curl -fsS -m 8 http://127.0.0.1:4000/health 2>/dev/null || true)
if echo "$body" | grep -q '"ok":true'; then exit 0; fi
echo "$(now) UNHEALTHY: ${body:-no answer} — restarting naslife" >> "$LOG"
systemctl restart naslife
sleep 5
after=$(curl -fsS -m 8 http://127.0.0.1:4000/health 2>/dev/null || true)
if echo "$after" | grep -q '"ok":true'; then echo "$(now) recovered after restart" >> "$LOG"
else echo "$(now) STILL DOWN after restart: ${after:-no answer}; last log lines:" >> "$LOG"; journalctl -u naslife -n 10 --no-pager >> "$LOG" 2>&1; fi
