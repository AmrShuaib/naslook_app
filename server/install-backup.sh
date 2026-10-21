#!/usr/bin/env bash
# تثبيت/تحديث النسخ الاحتياطي الليلي على الخادم (آمن للتكرار). يُشغَّل مرة واحدة من أي جهاز (علامات اقتباس مفردة وبلا $):
#   ssh root@91.108.111.246 'curl -fsSL https://raw.githubusercontent.com/AmrShuaib/naslook_app/claude/intelligent-hypatia-owb3fk/server/install-backup.sh | bash'
# ماذا يفعل: ينزّل backup.sh إلى /opt/naslife/ops/backup.sh (من الفرع في /opt/naslife/ops/branch أو NASLIFE_BRANCH، أو ينسخه من
# NASLIFE_BACKUP_SRC إن ضُبط)، يثبّت rsync إن غاب، يكتب /opt/naslife/ops/backup.env من قالب معلّق إن لم يوجد (ولا يلمسه إن وُجد)،
# يكتب وحدتي systemd ومؤقّتيهما (النسخة 03:30 كل ليلة والتمرين الأحد 04:30 بتوقيت الرياض، مع Persistent لتعويض ما فات)،
# يفعّلهما، يشغّل أول نسخة فوراً ويطبع ملخصها ومواعيد المؤقّتين. التفاصيل والاستعادة: docs/ops-backup.md
set -euo pipefail

main() {
  local OPS=/opt/naslife/ops
  local BRANCH="${NASLIFE_BRANCH:-$(cat "$OPS/branch" 2>/dev/null || echo claude/intelligent-hypatia-owb3fk)}"
  local RAW="https://raw.githubusercontent.com/AmrShuaib/naslook_app/$BRANCH/server"
  mkdir -p "$OPS/backup" /opt/naslife/backups
  chmod 700 /opt/naslife/backups
  if [[ -n "${NASLIFE_BACKUP_SRC:-}" && -f "$NASLIFE_BACKUP_SRC" ]]; then
    cp "$NASLIFE_BACKUP_SRC" "$OPS/backup.sh.new"
  else
    curl -fsSL "$RAW/backup.sh" -o "$OPS/backup.sh.new"
  fi
  bash -n "$OPS/backup.sh.new"
  mv "$OPS/backup.sh.new" "$OPS/backup.sh"
  chmod 700 "$OPS/backup.sh"
  # rsync يلزم للقطات الوسائط بروابط صلبة وللنسخ عبر ssh؛ بدونه يسقط السكربت إلى نسخة كاملة
  if ! command -v rsync >/dev/null 2>&1; then
    (apt-get update -qq && apt-get install -y -qq rsync) >/dev/null 2>&1 || echo "WARNING: rsync could not be installed; media snapshots will be full copies"
  fi
  if [[ ! -f "$OPS/backup.env" ]]; then
    cat > "$OPS/backup.env" <<'ENV'
# إعدادات النسخ الاحتياطي لناس لايف (يقرؤه /opt/naslife/ops/backup.sh). الأسطر المعلّقة بـ # تُهمل.
# نسخة خارج الخادم (اختر واحداً واتركه فارغاً إن لم يُضبط بعد؛ البطاقة في لوحة الإدارة تنبّه حتى يُضبط):
#   rclone (Backblaze B2 ونحوه): اسم الوجهة كما في rclone config، مثل b2:naslife-backups
BACKUP_RCLONE_REMOTE=
#   أو rsync عبر ssh بمفتاح بلا كلمة سر، مثل u123456@u123456.your-storagebox.de:naslife-backups (Hetzner على المنفذ 23)
BACKUP_SSH_TARGET=
#BACKUP_SSH_OPTS=-p 23
# الاحتفاظ: أيام نسخ القاعدة، وعدد لقطات الوسائط ومجموعات الإعداد
#KEEP_DAYS=14
#KEEP_MEDIA=7
# مجلد الوسائط إن لم يُكتشف تلقائياً (/opt/naslife/media أو data أو uploads أو /var/lib/naslife)
#MEDIA_DIR=/opt/naslife/media
# رابط القاعدة إن لم يُقرأ من وحدة systemd أو /opt/naslife/.env (وإلا يُستخدم sudo -u postgres)
#DATABASE_URL=postgres://user:pass@127.0.0.1:5432/naslife
ENV
    chmod 600 "$OPS/backup.env"
  fi
  cat > /etc/systemd/system/naslife-backup.service <<'UNIT'
[Unit]
Description=Naslife nightly backup (database, media, config)
After=network-online.target postgresql.service
[Service]
Type=oneshot
ExecStart=/opt/naslife/ops/backup.sh
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
UNIT
  cat > /etc/systemd/system/naslife-backup.timer <<'UNIT'
[Unit]
Description=Run the Naslife backup every night at 03:30 Riyadh time
[Timer]
OnCalendar=*-*-* 03:30:00 Asia/Riyadh
Persistent=true
RandomizedDelaySec=5min
[Install]
WantedBy=timers.target
UNIT
  cat > /etc/systemd/system/naslife-backup-drill.service <<'UNIT'
[Unit]
Description=Naslife weekly restore drill (restores the newest dump into a scratch database)
After=network-online.target postgresql.service
[Service]
Type=oneshot
ExecStart=/opt/naslife/ops/backup.sh --drill
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
UNIT
  cat > /etc/systemd/system/naslife-backup-drill.timer <<'UNIT'
[Unit]
Description=Run the Naslife restore drill every Sunday at 04:30 Riyadh time
[Timer]
OnCalendar=Sun *-*-* 04:30:00 Asia/Riyadh
Persistent=true
RandomizedDelaySec=5min
[Install]
WantedBy=timers.target
UNIT
  systemctl daemon-reload
  systemctl enable --now naslife-backup.timer naslife-backup-drill.timer
  echo "running the first backup now (this may take a minute)..."
  local rc=0
  "$OPS/backup.sh" || rc=$?
  # ملخص من ملف الحالة (node موجود على الخادم؛ python3 احتياطاً)
  local STATUS="$OPS/backup/last.json"
  if [[ -f "$STATUS" ]]; then
    if command -v node >/dev/null 2>&1; then
      node -e 'const s=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); console.log(`status ok=${s.ok} dump=${s.db?.file??"-"} (${((s.db?.bytes??0)/1048576).toFixed(1)} MB) media=${s.media?.files??0} files config=${(s.config?.files??[]).length} offsite=${s.offsite?.kind??"none"}/${s.offsite?.ok}${s.error?" error="+s.error:""}${s.offsite?.error?" offsite-error="+s.offsite.error:""}`)' "$STATUS"
    elif command -v python3 >/dev/null 2>&1; then
      python3 -I -c 'import json,sys; s=json.load(open(sys.argv[1],encoding="utf8")); print("status ok=%s dump=%s (%.1f MB) media=%s files offsite=%s/%s %s" % (s.get("ok"), (s.get("db") or {}).get("file"), ((s.get("db") or {}).get("bytes") or 0)/1048576, (s.get("media") or {}).get("files"), (s.get("offsite") or {}).get("kind"), (s.get("offsite") or {}).get("ok"), s.get("error") or ""))' "$STATUS"
    else
      cat "$STATUS"
    fi
  else
    echo "WARNING: no status file at $STATUS (see $OPS/backup/backup.log)"
  fi
  tail -3 "$OPS/backup/backup.log" 2>/dev/null || true
  systemctl list-timers --no-pager 'naslife-backup*' || true
  if grep -q '^BACKUP_RCLONE_REMOTE=$' "$OPS/backup.env" && grep -q '^BACKUP_SSH_TARGET=$' "$OPS/backup.env"; then
    echo "NOTE: no offsite copy configured yet; edit $OPS/backup.env (docs/ops-backup.md)"
  fi
  echo "BACKUP INSTALLED (branch: $BRANCH, first run exit: $rc)"
}

# يُستدعى مع stdin مغلق حتى لا تلتهم الأوامر بقية السكربت عند تمريره عبر ssh/pipe
main "$@" </dev/null
