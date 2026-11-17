#!/usr/bin/env bash
# Runs ON the VPS as root after the release tarball was copied to /opt/naslife/release.tgz
# (tools/deploy-server.sh on a workstation does the copy). Steps:
#   unpack to a staging dir -> node --check -> npm ci only if the lockfile changed -> keep a rollback copy ->
#   swap src/ db/ into place -> restart -> health check (10 s) -> on failure restore the previous release and restart.
# Never restarts production before the new code has at least parsed.
set -euo pipefail
APP=/opt/naslife
cd "$APP"
STAMP=$(date +%Y%m%d-%H%M%S)
STAGE="$APP/staging"; PREV="$APP/releases/prev-$STAMP"
rm -rf "$STAGE"; mkdir -p "$STAGE" "$APP/releases"
tar -xzf "$APP/release.tgz" -C "$STAGE" && rm -f "$APP/release.tgz"
[ -f "$STAGE/src/index.js" ] || { echo "release has no src/index.js"; exit 1; }
for f in "$STAGE"/src/*.js; do node --check "$f"; done
echo "syntax ok"

# secrets: generated once, readable by root and the service group only
if ! grep -q VAPID_PUBLIC .env; then
  node -e 'const w=require("web-push");const k=w.generateVAPIDKeys();console.log("VAPID_PUBLIC="+k.publicKey);console.log("VAPID_PRIVATE="+k.privateKey);console.log("VAPID_SUBJECT=mailto:admin@naslife.app")' >> .env
fi
chown root:naslife .env 2>/dev/null || true; chmod 640 .env

# dependencies: exactly the lockfile, only when it changed; installed in staging first so a failed
# install never leaves production without node_modules
if ! cmp -s "$STAGE/package-lock.json" package-lock.json || [ ! -d node_modules ]; then
  ( cd "$STAGE" && npm ci --omit=dev --no-audit --no-fund 2>&1 | tail -1 )
  [ -d "$STAGE/node_modules/fastify" ] || { echo "npm ci did not produce node_modules"; exit 1; }
  chown -R root:naslife "$STAGE/node_modules" && chmod -R o-rwx "$STAGE/node_modules"
  cp "$STAGE/package.json" "$STAGE/package-lock.json" .
  rm -rf node_modules.old; [ -d node_modules ] && mv node_modules node_modules.old; mv "$STAGE/node_modules" node_modules; rm -rf node_modules.old
fi

# rollback copy, then swap
mkdir -p "$PREV"; cp -a src "$PREV/src"; [ -d db ] && cp -a db "$PREV/db" || true
rm -rf src.new db.new; cp -a "$STAGE/src" src.new; cp -a "$STAGE/db" db.new
chown -R root:naslife src.new db.new; chmod -R o-rwx src.new db.new
rm -rf src.old db.old; mv src src.old; mv src.new src; [ -d db ] && mv db db.old || true; mv db.new db
rm -rf src.old db.old "$STAGE"
ls -dt "$APP"/releases/prev-* 2>/dev/null | tail -n +6 | xargs -r rm -rf   # keep 5 rollback copies

systemctl restart naslife
ok=0
for i in $(seq 1 10); do sleep 1; if curl -fsS http://127.0.0.1:4000/health 2>/dev/null | grep -q '"ok":true'; then ok=1; break; fi; done
if [ "$ok" = 1 ]; then
  echo "deploy ok ($STAMP): $(curl -s http://127.0.0.1:4000/health | cut -c1-60)"
else
  echo "HEALTH CHECK FAILED — rolling back to $PREV" >&2
  journalctl -u naslife --since "-30s" --no-pager | tail -15 >&2
  rm -rf src db; cp -a "$PREV/src" src; [ -d "$PREV/db" ] && cp -a "$PREV/db" db
  chown -R root:naslife src db; systemctl restart naslife; sleep 3
  curl -fsS http://127.0.0.1:4000/health >/dev/null && echo "rolled back, previous release healthy" || echo "rollback ALSO unhealthy — investigate now" >&2
  exit 1
fi
