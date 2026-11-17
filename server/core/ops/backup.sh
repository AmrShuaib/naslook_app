#!/usr/bin/env bash
# Daily backup of the Naslife server. Installed at /opt/naslife/backup.sh, run by /etc/cron.d/naslife-backup.
#   naslife-YYYY-MM-DD-HHMM.sql.gz.gpg    Postgres dump (plain SQL, gzipped, AES-256 encrypted)
#   uploads-YYYY-MM-DD-HHMM.tar.gz.gpg    uploaded media
#   server-YYYY-MM-DD-HHMM.tar.gz.gpg     server source + ops (NO secrets)
#   secrets-YYYY-MM-DD-HHMM.tar.gz.gpg    .env + systemd unit, encrypted separately
# Passphrase: /root/.naslife-backup-pass (generated once; copy it somewhere safe — without it the backups are useless).
# Off-site copy: server/ops/pull-backups.ps1 from a PC (encrypted files, so any storage will do).
# Restore test:  backup.sh --verify   restores the newest dump into a scratch database and checks row counts.
set -euo pipefail
DEST=/opt/naslife/backups
KEEP_DAYS=14
PASS=/root/.naslife-backup-pass
STAMP=$(date +%Y-%m-%d-%H%M)
mkdir -p "$DEST" && chmod 700 "$DEST"
if [ ! -s "$PASS" ]; then (umask 077; openssl rand -base64 48 > "$PASS"); echo "NEW backup passphrase written to $PASS — copy it off this machine now"; fi
enc() { gpg --batch --yes --quiet --symmetric --cipher-algo AES256 --passphrase-file "$PASS" -o "$1.gpg" "$1" && rm -f "$1"; }

verify() {
  local dump; dump=$(ls -t "$DEST"/naslife-*.sql.gz.gpg 2>/dev/null | head -1)
  [ -n "$dump" ] || { echo "verify: no dump found" >&2; exit 1; }
  local tmp; tmp=$(mktemp -d); trap 'rm -rf "$tmp"' RETURN
  gpg --batch --quiet --passphrase-file "$PASS" -d "$dump" | gunzip -c > "$tmp/restore.sql"
  sudo -u postgres psql -qtAc "DROP DATABASE IF EXISTS naslife_restore_test" >/dev/null
  sudo -u postgres createdb -O naslife naslife_restore_test
  sudo -u postgres psql -q -v ON_ERROR_STOP=1 -d naslife_restore_test < "$tmp/restore.sql" >/dev/null   # stdin: postgres cannot read root's tmp dir
  local users msgs live
  users=$(sudo -u postgres psql -tAc "SELECT count(*) FROM users" naslife_restore_test)
  msgs=$(sudo -u postgres psql -tAc "SELECT count(*) FROM messages" naslife_restore_test)
  live=$(sudo -u postgres psql -tAc "SELECT count(*) FROM users" naslife)
  sudo -u postgres psql -qtAc "DROP DATABASE naslife_restore_test" >/dev/null
  [ "$users" -gt 0 ] && [ "$users" -ge $((live - 5)) ] || { echo "restore test FAILED: users=$users live=$live" >&2; exit 1; }
  echo "restore test ok $(basename "$dump"): users=$users messages=$msgs"
}
if [ "${1:-}" = "--verify" ]; then verify; exit 0; fi

# 1) database
sudo -u postgres pg_dump --no-owner --no-acl naslife | gzip -9 > "$DEST/naslife-$STAMP.sql.gz"
# (grep without -q: with pipefail an early exit would look like a gunzip failure)
[ "$(gunzip -c "$DEST/naslife-$STAMP.sql.gz" | grep -c "CREATE TABLE public.users")" -ge 1 ] || { echo "backup verify FAILED" >&2; exit 1; }
enc "$DEST/naslife-$STAMP.sql.gz"
# 2) uploaded media
tar -czf "$DEST/uploads-$STAMP.tar.gz" -C /opt/naslife uploads && enc "$DEST/uploads-$STAMP.tar.gz"
# 3) server source + ops, without secrets
tar -czf "$DEST/server-$STAMP.tar.gz" -C /opt/naslife src db package.json package-lock.json ops backup.sh && enc "$DEST/server-$STAMP.tar.gz"
# 4) secrets on their own
tar -czf "$DEST/secrets-$STAMP.tar.gz" -C /opt/naslife .env -C /etc/systemd/system naslife.service && enc "$DEST/secrets-$STAMP.tar.gz"
# 5) rotate + checksums
find "$DEST" -type f -mtime +"$KEEP_DAYS" -delete
( cd "$DEST" && sha256sum ./*-"$STAMP".*.gpg > "checksums-$STAMP.txt" )
echo "naslife backup ok $STAMP: $(du -sh "$DEST" | cut -f1) total in $DEST"
