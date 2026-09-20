#!/bin/bash
# لقطات حية بعد النشر: السوق (من زر «السوق» في الرئيسية) وصفحة مستخدم في لوحة الإدارة، بجلسة المؤسس
S="${NASLIFE_SCRATCH:-$(git rev-parse --show-toplevel)/.scratch}"; mkdir -p "$S"
export LIVE_TOKEN="${NASLIFE_TOKEN:?}" LIVE_ID="${NASLIFE_ID:-SA9954961}" LIVE_NICK="${NASLIFE_NICK:-jeddahh}" BOOT_MS=16000
cd $S && node probe_live_auth.mjs "https://naslife.app/" "$S/seed_market" '[{"click":[80,372],"wait":6000,"shot":"market"},{"wheel":[0,900],"wait":2500,"shot":"market-scrolled"},{"wheel":[0,900],"wait":2500,"shot":"market-scrolled2"}]' 2>&1 | tail -3
VIEWPORT_W=900 VIEWPORT_H=1500 node probe_live_auth.mjs "https://naslife.app/admin/users/SA9954961" "$S/seed_admin" '[{"wait":5000,"shot":"user"},{"wheel":[0,700],"wait":2000,"shot":"user-scrolled"}]' 2>&1 | tail -3
ls -la $S/seed_market-*.png $S/seed_admin-*.png 2>/dev/null | awk '{print $5, $9}'
