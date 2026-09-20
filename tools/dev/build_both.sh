#!/usr/bin/env bash
S="${NASLIFE_SCRATCH:-$(git rev-parse --show-toplevel)/.scratch}"; mkdir -p "$S"
cd /home/user/naslook_app
${FLUTTER:-flutter} build web --release --pwa-strategy=none --dart-define=NASLIFE_API_BASE=http://127.0.0.1:8090 -o $S/web-mock > $S/build_mock6.log 2>&1
echo "MOCK_DONE $?" >> $S/build_both.status
${FLUTTER:-flutter} build web --release --pwa-strategy=none -o build/web > $S/build_prod_comm2.log 2>&1
echo "PROD_DONE $?" >> $S/build_both.status
