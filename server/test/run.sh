#!/bin/bash
# يشغّل حزمة اختبار واحدة أو كلها على Postgres 16 المحلي (قاعدة naslife_test، المستخدم postgres/pg).
# الاستخدام: server/test/run.sh harness_market_b.mjs   |   server/test/run.sh all
# NASLIFE_TEST_DB=naslife_test_x يوجّه الحزم إلى قاعدة مستقلة (للجلسات المتوازية) عبر db_env.mjs، وسجلاتها في /tmp/$NASLIFE_TEST_DB/
set -e
cd "$(dirname "$0")"
[ -d node_modules ] || npm install --silent
if command -v pg_lsclusters >/dev/null; then pg_lsclusters | grep -q online || sudo -n pg_ctlcluster 16 main start 2>/dev/null || pg_ctlcluster 16 main start; fi
DB="${NASLIFE_TEST_DB:-naslife_test}"
PGPASSWORD=pg psql -h 127.0.0.1 -U postgres -tc "SELECT 1 FROM pg_database WHERE datname='$DB'" | grep -q 1 || PGPASSWORD=pg createdb -h 127.0.0.1 -U postgres "$DB"
LOGS=/tmp; if [ -n "$NASLIFE_TEST_DB" ]; then LOGS="/tmp/$NASLIFE_TEST_DB"; mkdir -p "$LOGS"; fi
if [ "${1:-all}" = "all" ]; then
  fails=0
  for f in harness*.mjs; do echo "=== $f"; node --import ./db_env.mjs "$f" > "$LOGS/$f.log" 2>&1 && grep -qE "ALL .*OK|ALL .*PASSED|0 FAILED|^ALL OK" "$LOGS/$f.log" && echo "OK  $f" || { echo "FAIL $f (see $LOGS/$f.log)"; fails=$((fails+1)); }; done
  echo "failed: $fails"; exit $fails
else
  node --import ./db_env.mjs "$1"
fi
