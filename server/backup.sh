#!/usr/bin/env bash
# النسخ الاحتياطي الليلي لناس لايف (آمن للتكرار): pg_dump مضغوط مع بصمة sha256، لقطة للوسائط بروابط صلبة (rsync --link-dest)،
# نسخة من ملفات الإعداد (مفتاح التشفير، Caddyfile، نواة Node خارج git، وحدات systemd)، تدوير، مزامنة خارج الخادم إن ضُبطت،
# وملف حالة JSON تقرأه لوحة الإدارة (server/backups.js). يُشغَّل بمؤقّت systemd كل ليلة (server/install-backup.sh)، ويعمل أيضاً
# بلا صلاحيات في الاختبارات (server/test/harness_backups.mjs).
#   backup.sh            نسخة كاملة
#   backup.sh --drill    تمرين استعادة: يستعيد أحدث نسخة في قاعدة مؤقتة ويعدّ الجداول والصفوف ثم يحذفها (الأحد أسبوعياً)
# المتغيرات (كلها اختيارية، وتُقرأ أولاً من BACKUP_ENV=/opt/naslife/ops/backup.env إن وُجد؛ ما في البيئة له الأولوية):
#   BACKUP_DIR=/opt/naslife/backups  BACKUP_STATUS=/opt/naslife/ops/backup/last.json  BACKUP_LOG=/opt/naslife/ops/backup/backup.log
#   KEEP_DAYS=14 (نسخ القاعدة)  KEEP_MEDIA=7 (لقطات الوسائط ومجموعات الإعداد)  DRILL_DB=naslife_restore_drill
#   MEDIA_DIR   مجلد الوسائط (يُكتشف تلقائياً من /opt/naslife/media|data|uploads أو /var/lib/naslife؛ فارغ = تخطٍّ)
#   CONFIG_PATHS مسارات تُنسخ (المجلدات تُضغط بلا node_modules؛ "" = تخطٍّ)
#   DATABASE_URL رابط القاعدة (وإلا: بيئة وحدة naslife في systemd، ثم /opt/naslife/.env، ثم sudo -u postgres على أول قاعدة naslife%)
#   NO_SUDO=1   يمنع احتياط sudo -u postgres
#   BACKUP_RCLONE_REMOTE=b2:naslife-backups  أو  BACKUP_SSH_TARGET=user@host:/path [+ BACKUP_SSH_OPTS="-p 23"]  (نسخة خارج الخادم)
#       rclone: يرفع db/ وconfig/ كما هما وشجرة وسائط واحدة (أحدث لقطة) إلى media/؛ ssh: مرآة كاملة للمجلد مع حفظ الروابط الصلبة (-H)
# الخروج: 0 نجاح، 1 فشل (الحالة تُكتب بـ ok:false والخطأ)، 2 النسخة المحلية سليمة لكن المزامنة خارج الخادم فشلت.
set -Eeuo pipefail

MODE=normal
for a in "$@"; do
  case "$a" in
    --drill) MODE=drill ;;
    -h|--help) sed -n '2,/^set -/p' "$0" | sed '$d'; exit 0 ;;
    *) echo "unknown argument: $a" >&2; exit 1 ;;
  esac
done
# مجلد عمل يقرؤه كل مستخدم حتى لا يشكو sudo -u postgres من مجلد غير مقروء
cd /

# ---- ملف البيئة: يملأ ما لم يُضبط في البيئة فقط (البيئة تغلب الملف)
BACKUP_ENV="${BACKUP_ENV:-/opt/naslife/ops/backup.env}"
if [[ -f "$BACKUP_ENV" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"; line="${line#export }"
    if [[ -z "$line" || "$line" == \#* || "$line" != *=* ]]; then continue; fi
    k="${line%%=*}"; v="${line#*=}"; k="${k//[[:space:]]/}"
    if [[ ! "$k" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then continue; fi
    v="${v%"${v##*[![:space:]]}"}"
    if [[ "$v" == \"*\" || "$v" == \'*\' ]]; then v="${v:1:${#v}-2}"; fi
    if [[ -z "${!k+x}" ]]; then export "$k=$v"; fi
  done < "$BACKUP_ENV"
fi

BACKUP_DIR="${BACKUP_DIR:-/opt/naslife/backups}"
BACKUP_STATUS="${BACKUP_STATUS:-/opt/naslife/ops/backup/last.json}"
BACKUP_LOG="${BACKUP_LOG:-/opt/naslife/ops/backup/backup.log}"
KEEP_DAYS="${KEEP_DAYS:-14}"
KEEP_MEDIA="${KEEP_MEDIA:-7}"
DRILL_DB="${DRILL_DB:-naslife_restore_drill}"
NO_SUDO="${NO_SUDO:-0}"
# المسار الافتراضي لملفات الإعداد؛ ضبطه فارغاً صراحةً يعني التخطي
if [[ -z "${CONFIG_PATHS+x}" ]]; then
  CONFIG_PATHS="/opt/naslife/ops/auth-key /etc/caddy/Caddyfile /opt/naslife/src /etc/systemd/system/naslife.service /etc/systemd/system/naslife-autodeploy.service /etc/systemd/system/naslife-autodeploy.timer"
fi
if [[ -z "${MEDIA_DIR+x}" ]]; then
  MEDIA_DIR=""
  for d in /opt/naslife/media /opt/naslife/data /opt/naslife/uploads /var/lib/naslife; do if [[ -d "$d" ]]; then MEDIA_DIR="$d"; break; fi; done
fi

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
START_EPOCH=$(date +%s); STARTED_AT=$(now_iso)
ERRF=$(mktemp); trap 'rm -f "$ERRF"' EXIT
NOTES=(); note() { NOTES+=("$*"); echo "[backup] $*"; }
log() { mkdir -p "$(dirname "$BACKUP_LOG")"; echo "$(date '+%F %T') $*" >> "$BACKUP_LOG"; }
err_text() { tr '\n' ' ' < "$ERRF" | sed 's/  */ /g; s/ *$//' | tail -c 400; }

# ---- حالة التشغيل (تُكتب في JSON في النهاية أو عند أول فشل)
STEP="start"; S_OK=false; S_ERROR=""
S_DB_FILE=""; S_DB_BYTES=""; S_DB_SHA=""
S_MEDIA_SRC=""; S_MEDIA_DIR=""; S_MEDIA_FILES=0; S_MEDIA_BYTES=0
S_CONFIG_FILES=""
S_OFF_KIND=none; S_OFF_OK=false; S_OFF_ERROR=""
S_KEPT_DUMPS=0; S_KEPT_MEDIA=0
D_AT=""; D_OK=false; D_ERROR=""; D_TABLES=""; D_ROWS=""; D_LIVE_USERS=""
# يصبح 1 بعد أن يجتاز اسم قاعدة التمرين الحارس؛ قبل ذلك لا يُستدعى dropdb أبداً (ولا من مسار الفشل)
DRILL_SAFE=0

# ---- كتابة JSON ذرياً (tmp ثم mv) عبر node أو python3؛ القيم تمر بالبيئة فلا تكسرها علامات الاقتباس.
# في الوضع العادي يُحفظ مفتاح drill من الملف السابق؛ في وضع التمرين لا يُبدَّل إلا مفتاح drill.
write_status() {
  local mode="$1" tmp
  mkdir -p "$(dirname "$BACKUP_STATUS")"; tmp="$BACKUP_STATUS.tmp.$$"
  local dur=$(( $(date +%s) - START_EPOCH ))
  export W_MODE="$mode" W_PREV="$BACKUP_STATUS" W_OUT="$tmp" W_DUR="$dur" W_STARTED="$STARTED_AT" W_FINISHED="$(now_iso)" \
    S_OK S_ERROR S_DB_FILE S_DB_BYTES S_DB_SHA S_MEDIA_SRC S_MEDIA_DIR S_MEDIA_FILES S_MEDIA_BYTES S_CONFIG_FILES \
    S_OFF_KIND S_OFF_OK S_OFF_ERROR S_KEPT_DUMPS S_KEPT_MEDIA D_AT D_OK D_ERROR D_TABLES D_ROWS D_LIVE_USERS
  if command -v node >/dev/null 2>&1; then
    node -e '
      const fs = require("fs"), e = process.env;
      const n = (v) => (v === "" || v == null ? null : Number(v)), b = (v) => v === "true", s = (v) => (v === "" || v == null ? null : String(v));
      const lines = (v) => String(v ?? "").split("\n").filter(Boolean);
      let prev = {}; try { prev = JSON.parse(fs.readFileSync(e.W_PREV, "utf8")); if (!prev || typeof prev !== "object") prev = {}; } catch { prev = {}; }
      let o;
      if (e.W_MODE === "drill") {
        const rows = {}; for (const l of lines(e.D_ROWS)) { const i = l.indexOf("="); rows[l.slice(0, i)] = Number(l.slice(i + 1)); }
        const drill = { at: e.D_AT, ok: b(e.D_OK), error: s(e.D_ERROR), tables: n(e.D_TABLES), rows, liveUsers: n(e.D_LIVE_USERS), durationSec: n(e.W_DUR) };
        o = { ...(prev.version ? prev : { version: 1 }), drill };
      } else {
        o = { version: 1, startedAt: e.W_STARTED, finishedAt: e.W_FINISHED, ok: b(e.S_OK), error: s(e.S_ERROR), durationSec: n(e.W_DUR),
          db: { file: s(e.S_DB_FILE), bytes: n(e.S_DB_BYTES) ?? 0, sha256: s(e.S_DB_SHA) },
          media: { source: s(e.S_MEDIA_SRC), dir: s(e.S_MEDIA_DIR), files: n(e.S_MEDIA_FILES) ?? 0, bytes: n(e.S_MEDIA_BYTES) ?? 0 },
          config: { files: lines(e.S_CONFIG_FILES) },
          offsite: { kind: e.S_OFF_KIND || "none", ok: b(e.S_OFF_OK), error: s(e.S_OFF_ERROR) },
          kept: { dumps: n(e.S_KEPT_DUMPS) ?? 0, mediaSnapshots: n(e.S_KEPT_MEDIA) ?? 0 },
          drill: prev.drill && typeof prev.drill === "object" ? prev.drill : null };
      }
      fs.writeFileSync(e.W_OUT, JSON.stringify(o, null, 2) + "\n");
    '
  elif command -v python3 >/dev/null 2>&1; then
    python3 -I -c '
import json, os
e = os.environ
n = lambda v: None if v in ("", None) else float(v) if "." in v else int(v)
b = lambda v: v == "true"
s = lambda v: None if v in ("", None) else str(v)
lines = lambda v: [l for l in (v or "").split("\n") if l]
try:
    with open(e["W_PREV"], encoding="utf8") as f: prev = json.load(f)
    if not isinstance(prev, dict): prev = {}
except Exception: prev = {}
if e["W_MODE"] == "drill":
    rows = {}
    for l in lines(e.get("D_ROWS")):
        k, _, v = l.partition("="); rows[k] = int(v)
    drill = {"at": e["D_AT"], "ok": b(e["D_OK"]), "error": s(e["D_ERROR"]), "tables": n(e["D_TABLES"]), "rows": rows, "liveUsers": n(e["D_LIVE_USERS"]), "durationSec": n(e["W_DUR"])}
    o = dict(prev if prev.get("version") else {"version": 1}); o["drill"] = drill
else:
    o = {"version": 1, "startedAt": e["W_STARTED"], "finishedAt": e["W_FINISHED"], "ok": b(e["S_OK"]), "error": s(e["S_ERROR"]), "durationSec": n(e["W_DUR"]),
         "db": {"file": s(e["S_DB_FILE"]), "bytes": n(e["S_DB_BYTES"]) or 0, "sha256": s(e["S_DB_SHA"])},
         "media": {"source": s(e["S_MEDIA_SRC"]), "dir": s(e["S_MEDIA_DIR"]), "files": n(e["S_MEDIA_FILES"]) or 0, "bytes": n(e["S_MEDIA_BYTES"]) or 0},
         "config": {"files": lines(e.get("S_CONFIG_FILES"))},
         "offsite": {"kind": e["S_OFF_KIND"] or "none", "ok": b(e["S_OFF_OK"]), "error": s(e["S_OFF_ERROR"])},
         "kept": {"dumps": n(e["S_KEPT_DUMPS"]) or 0, "mediaSnapshots": n(e["S_KEPT_MEDIA"]) or 0},
         "drill": prev.get("drill") if isinstance(prev.get("drill"), dict) else None}
with open(e["W_OUT"], "w", encoding="utf8") as f: json.dump(o, f, ensure_ascii=False, indent=2); f.write("\n")
'
  else
    echo "neither node nor python3 is available to write the status file" >&2; return 1
  fi
  mv -f "$tmp" "$BACKUP_STATUS"
}

# ---- أي فشل: نسجّل الحالة بـ ok:false ونصّ الخطأ ثم نخرج بغير صفر
on_fail() {
  local rc=$? msg
  trap - ERR
  msg="$STEP failed (exit $rc): $(err_text)"; msg="${msg%: }"
  if [[ "$MODE" == drill ]]; then
    D_OK=false; D_ERROR="$msg"; D_AT="${D_AT:-$(now_iso)}"
    # لا حذف لقاعدة التمرين إلا إن اجتاز اسمها الحارس؛ فشل الحارس نفسه (DRILL_DB = القاعدة الحية) كان يصل هنا ويحذف القاعدة الحية
    if [[ "$DRILL_SAFE" == 1 ]]; then drill_cleanup || true; fi
    write_status drill || true
    log "DRILL FAILED: $msg"
  else
    S_OK=false; S_ERROR="$msg"
    # نسخة ناقصة من pg_dump فشل في منتصفه لا تُترك على القرص (التدوير لا يراها)
    if [[ -n "${DUMP:-}" ]]; then rm -f "$DUMP.part"; fi
    write_status normal || true
    log "FAILED: $msg"
  fi
  echo "[backup] $msg" >&2
  exit "$rc"
}
trap on_fail ERR

# ---- اكتشاف الاتصال بالقاعدة: url | pgenv (PG* مصدّرة) | sudo (postgres المحلي)
DB_MODE=""; DB_CONN=""; DB_NAME=""
url_dbname() { local p="${1#*://}"; p="${p#*/}"; p="${p%%\?*}"; echo "$p"; }
url_with_db() { # يبدّل اسم القاعدة في الرابط (أو يضيفه إن غاب)
  local u="$1" db="$2" scheme rest q=""
  scheme="${u%%://*}"; rest="${u#*://}"
  if [[ "$rest" == *\?* ]]; then q="?${rest#*\?}"; rest="${rest%%\?*}"; fi
  rest="${rest%%/*}"
  echo "$scheme://$rest/$db$q"
}
set_url() { DB_MODE=url; DB_CONN="$1"; DB_NAME=$(url_dbname "$1"); }
detect_db() {
  STEP="detect-db"
  if [[ -n "${DATABASE_URL:-}" ]]; then set_url "$DATABASE_URL"; return 0; fi
  local envs="" line
  envs=$(systemctl show naslife -p Environment --value 2>/dev/null | tr ' ' '\n' || true)
  line=$(printf '%s\n' "$envs" | grep '^DATABASE_URL=' | head -1 || true)
  if [[ -n "$line" ]]; then set_url "${line#DATABASE_URL=}"; return 0; fi
  if printf '%s\n' "$envs" | grep -q '^PG\(HOST\|PORT\|USER\|PASSWORD\|DATABASE\)='; then
    while IFS= read -r line; do if [[ "$line" == PG* ]]; then export "$line"; fi; done <<< "$envs"
    DB_MODE=pgenv; DB_NAME="${PGDATABASE:-naslife}"; DB_CONN="$DB_NAME"; return 0
  fi
  for f in /opt/naslife/.env /opt/naslife/src/.env; do
    if [[ ! -f "$f" ]]; then continue; fi
    line=$(grep -E '^\s*(export\s+)?DATABASE_URL=' "$f" | head -1 | sed -E 's/^\s*(export\s+)?DATABASE_URL=//; s/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/' || true)
    if [[ -n "$line" ]]; then set_url "$line"; return 0; fi
  done
  if [[ "$NO_SUDO" != "1" ]] && command -v sudo >/dev/null 2>&1 && id postgres >/dev/null 2>&1; then
    DB_NAME=$(sudo -n -u postgres psql -Atc "SELECT datname FROM pg_database WHERE datname LIKE 'naslife%' ORDER BY datname LIMIT 1" 2>"$ERRF" || true)
    if [[ -n "$DB_NAME" ]]; then DB_MODE=sudo; DB_CONN="$DB_NAME"; return 0; fi
  fi
  echo "no database connection found (set DATABASE_URL)" > "$ERRF"; false
}
# تنفيذ أداة Postgres بالاتصال المكتشف (في وضع sudo تمر الملفات عبر stdin/stdout لأن مجلد النسخ 700 للجذر)
pgx() { if [[ "$DB_MODE" == sudo ]]; then sudo -n -u postgres "$@"; else "$@"; fi; }
# اتصال بقاعدة أخرى على الخادم نفسه (لقاعدة التمرين)
conn_for() { if [[ "$DB_MODE" == url ]]; then url_with_db "$DB_CONN" "$1"; else echo "$1"; fi; }
sql() { pgx psql "$1" -Atq -v ON_ERROR_STOP=1 -c "$2" 2>"$ERRF"; }

# ---- تمرين الاستعادة
# حذف قاعدة التمرين: يرفض بنفسه اسماً فارغاً أو اسم القاعدة الحية، ويتصل عبر القاعدة الحية (--maintenance-db في كل الأوضاع)
# فيرفض Postgres بدوره حذف القاعدة المفتوحة لو تسلّل الاسم بطريقة ما (خط دفاع ثانٍ)
drill_cleanup() {
  if [[ -z "${DB_MODE:-}" ]]; then return 0; fi
  if [[ -z "$DRILL_DB" || "$DRILL_DB" == "$DB_NAME" ]]; then echo "refusing to drop '$DRILL_DB': it is the live database" >> "$ERRF"; return 1; fi
  pgx dropdb --if-exists --maintenance-db="$DB_CONN" "$DRILL_DB" 2>>"$ERRF"
}
run_drill() {
  D_AT=$(now_iso)
  detect_db
  STEP="drill-guard"
  if [[ -z "$DRILL_DB" ]]; then echo "DRILL_DB is empty" > "$ERRF"; false; fi
  if [[ "$DRILL_DB" == "$DB_NAME" ]]; then echo "DRILL_DB equals the live database ($DB_NAME)" > "$ERRF"; false; fi
  case "$DRILL_DB" in postgres|template0|template1) echo "DRILL_DB may not be a system database ($DRILL_DB)" > "$ERRF"; false ;; esac
  DRILL_SAFE=1
  STEP="find-dump"
  local dump; dump=$(ls -1t "$BACKUP_DIR"/db/naslife-*.dump 2>/dev/null | head -1 || true)
  if [[ -z "$dump" ]]; then echo "no dump found in $BACKUP_DIR/db" > "$ERRF"; false; fi
  if [[ -f "$dump.sha256" ]]; then STEP="verify-sha256"; (cd "$(dirname "$dump")" && sha256sum -c --quiet "$(basename "$dump").sha256") 2>"$ERRF"; fi
  STEP="drill-createdb"
  drill_cleanup
  pgx createdb --maintenance-db="$DB_CONN" "$DRILL_DB" 2>"$ERRF"
  local dconn; dconn=$(conn_for "$DRILL_DB")
  STEP="pg_restore"
  pgx pg_restore --no-owner --no-privileges -d "$dconn" < "$dump" 2>"$ERRF"
  STEP="drill-count"
  D_TABLES=$(sql "$dconn" "SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE'")
  D_ROWS=""
  local t
  for t in users wallet_tx market_orders map_posts; do
    if [[ "$(sql "$dconn" "SELECT to_regclass('public.$t') IS NOT NULL")" == t ]]; then D_ROWS+="$t=$(sql "$dconn" "SELECT count(*) FROM $t")"$'\n'; fi
  done
  D_LIVE_USERS=""
  if [[ "$(sql "$DB_CONN" "SELECT to_regclass('public.users') IS NOT NULL")" == t ]]; then D_LIVE_USERS=$(sql "$DB_CONN" "SELECT count(*) FROM users"); fi
  STEP="drill-dropdb"
  drill_cleanup
  local restored; restored=$(printf '%s' "$D_ROWS" | grep '^users=' | cut -d= -f2 || true)
  # الفرق المسموح بين النسخة والقاعدة الحية (مستخدمون جدد أو حسابات حُذفت بين النسخة والتمرين): 2% أو 10 أيهما أكبر
  if [[ "${D_TABLES:-0}" -lt 1 ]]; then D_OK=false; D_ERROR="restored database has no tables"
  elif [[ -n "$restored" && -n "$D_LIVE_USERS" ]]; then
    local tol=$(( D_LIVE_USERS / 50 )); if (( tol < 10 )); then tol=10; fi
    local diff=$(( D_LIVE_USERS - restored )); if (( diff < 0 )); then diff=$(( -diff )); fi
    if (( diff > tol )); then D_OK=false; D_ERROR="users mismatch: restored $restored, live $D_LIVE_USERS"; else D_OK=true; fi
  else D_OK=true; fi
  write_status drill
  log "drill $([[ "$D_OK" == true ]] && echo ok || echo FAILED) dump=$(basename "$dump") tables=$D_TABLES users=${restored:-?}/${D_LIVE_USERS:-?} durationSec=$(( $(date +%s) - START_EPOCH ))${D_ERROR:+ error=\"$D_ERROR\"}"
  echo "[backup] drill ok=$D_OK tables=$D_TABLES users=${restored:-?}/${D_LIVE_USERS:-?}${D_ERROR:+ ($D_ERROR)}"
}

if [[ "$MODE" == drill ]]; then
  run_drill; trap - ERR
  if [[ "$D_OK" == true ]]; then exit 0; fi
  exit 1
fi

# ---- 1) المجلدات والقفل (لا نسختان في وقت واحد)
STEP="prepare"
mkdir -p "$BACKUP_DIR/db" "$BACKUP_DIR/media" "$BACKUP_DIR/config" "$(dirname "$BACKUP_STATUS")" "$(dirname "$BACKUP_LOG")"
chmod 700 "$BACKUP_DIR"
exec 9>"$BACKUP_DIR/.lock"
if ! flock -n 9; then echo "another backup is still running" > "$ERRF"; false; fi
TS=$(date +%Y%m%d-%H%M)
# تشغيلان في الدقيقة نفسها (اختبارات): نضيف الثواني بدل الكتابة فوق النسخة السابقة
if [[ -e "$BACKUP_DIR/db/naslife-$TS.dump" || -e "$BACKUP_DIR/media/$TS" || -e "$BACKUP_DIR/config/$TS" ]]; then TS=$(date +%Y%m%d-%H%M%S); fi
detect_db
note "database: $DB_MODE ($DB_NAME)"

# ---- 2) قاعدة البيانات
STEP="pg_dump"
DUMP="$BACKUP_DIR/db/naslife-$TS.dump"
pgx pg_dump -Fc "$DB_CONN" > "$DUMP.part" 2>"$ERRF"
mv -f "$DUMP.part" "$DUMP"
chmod 600 "$DUMP" 2>/dev/null || true
STEP="sha256"
(cd "$BACKUP_DIR/db" && sha256sum "$(basename "$DUMP")" > "$(basename "$DUMP").sha256") 2>"$ERRF"
S_DB_FILE="$DUMP"; S_DB_BYTES=$(stat -c %s "$DUMP"); S_DB_SHA=$(cut -d' ' -f1 "$DUMP.sha256")
note "db: $(basename "$DUMP") ($S_DB_BYTES bytes)"

# ---- 3) الوسائط: لقطة بروابط صلبة إلى اللقطة السابقة فلا تُنسخ إلا الملفات الجديدة
STEP="media"
if [[ -n "$MEDIA_DIR" && -d "$MEDIA_DIR" ]]; then
  SNAP="$BACKUP_DIR/media/$TS"; PREV=""
  if [[ -L "$BACKUP_DIR/media/latest" ]]; then PREV=$(readlink -f "$BACKUP_DIR/media/latest" || true); fi
  if [[ -z "$PREV" || ! -d "$PREV" ]]; then PREV=""; fi
  mkdir -p "$SNAP"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete ${PREV:+--link-dest="$PREV"} "$MEDIA_DIR/" "$SNAP/" 2>"$ERRF"
  else
    # بلا rsync (حاويات الاختبار): نسخة كاملة؛ على الخادم يثبّته install-backup.sh
    cp -a "$MEDIA_DIR/." "$SNAP/" 2>"$ERRF"; note "media: rsync missing, full copy"
  fi
  ln -sfn "$TS" "$BACKUP_DIR/media/latest"
  S_MEDIA_SRC="$MEDIA_DIR"; S_MEDIA_DIR="$SNAP"
  S_MEDIA_FILES=$(find "$SNAP" -type f | wc -l | tr -d ' '); S_MEDIA_BYTES=$(du -sb "$SNAP" | cut -f1)
  note "media: $S_MEDIA_FILES files from $MEDIA_DIR"
else
  if [[ -n "$MEDIA_DIR" ]]; then note "media: skipped ($MEDIA_DIR does not exist)"; else note "media: skipped (no media directory)"; fi
fi

# ---- 4) ملفات الإعداد: الملفات تُنسخ، والمجلدات تُضغط بلا node_modules (نواة Node ليست في git)
STEP="config"
if [[ -n "$CONFIG_PATHS" ]]; then
  CDIR="$BACKUP_DIR/config/$TS"; mkdir -p "$CDIR"
  for p in $CONFIG_PATHS; do
    name=$(basename "$p")
    if [[ -f "$p" ]]; then cp -p "$p" "$CDIR/$name" 2>"$ERRF"; S_CONFIG_FILES+="$name"$'\n'
    elif [[ -d "$p" ]]; then tar -czf "$CDIR/$name.tar.gz" --exclude=node_modules -C "$(dirname "$p")" "$name" 2>"$ERRF"; S_CONFIG_FILES+="$name.tar.gz"$'\n'
    else note "config: $p not found"; fi
  done
  chmod -R go-rwx "$CDIR" 2>/dev/null || true
fi

# ---- 5) التدوير: نسخ القاعدة الأقدم من KEEP_DAYS، وأحدث KEEP_MEDIA لقطة/مجموعة إعداد فقط
STEP="rotate"
while IFS= read -r old; do if [[ -n "$old" ]]; then rm -f "$old" "$old.sha256"; note "rotated $(basename "$old")"; fi; done < <(find "$BACKUP_DIR/db" -maxdepth 1 -name 'naslife-*.dump' -mmin +"$(( KEEP_DAYS * 1440 ))" 2>/dev/null)
# بقايا .part من تشغيل سابق فشل في منتصفه (القفل يضمن ألا يكون لتشغيل جارٍ، ونسخة هذا التشغيل سُمّيت قبل الوصول هنا): لا قيمة لها
while IFS= read -r old; do if [[ -n "$old" ]]; then rm -f "$old"; note "removed partial $(basename "$old")"; fi; done < <(find "$BACKUP_DIR/db" -maxdepth 1 -name 'naslife-*.dump.part' 2>/dev/null)
prune_dirs() { # $1 المجلد الأب: يحذف كل المجلدات الفرعية ما عدا أحدث KEEP_MEDIA (الأسماء طوابع زمنية فترتيبها زمني)
  local parent="$1" d
  while IFS= read -r d; do if [[ -n "$d" && -d "$parent/$d" && ! -L "$parent/$d" ]]; then rm -rf "${parent:?}/$d"; fi; done < <(find "$parent" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -r | tail -n +"$(( KEEP_MEDIA + 1 ))")
}
prune_dirs "$BACKUP_DIR/media"; prune_dirs "$BACKUP_DIR/config"
S_KEPT_DUMPS=$(find "$BACKUP_DIR/db" -maxdepth 1 -name 'naslife-*.dump' | wc -l | tr -d ' ')
S_KEPT_MEDIA=$(find "$BACKUP_DIR/media" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')

# ---- 6) خارج الخادم: rclone (B2 ونحوه) أو rsync عبر ssh؛ فشله لا يُفسد النسخة المحلية لكنه يُبلَّغ ويخرج بالرمز 2
STEP="offsite"
if [[ -n "${BACKUP_RCLONE_REMOTE:-}" ]]; then
  S_OFF_KIND=rclone
  if command -v rclone >/dev/null 2>&1; then
    # rclone لا يعرف الروابط الصلبة: مزامنة كل اللقطات ترفع الوسائط كاملة كل ليلة وتخزّنها KEEP_MEDIA مرة.
    # لذا تُرفع نسخ القاعدة والإعداد كما هي، وشجرة وسائط واحدة فقط (لقطة هذه الليلة = latest) إلى media/ فلا يُنقل إلا ما تغيّر.
    REMOTE="${BACKUP_RCLONE_REMOTE%/}"
    rclone_sync() { if rclone sync "$1" "$2" --exclude '*.part' -q 2>"$ERRF"; then return 0; fi; S_OFF_ERROR="${S_OFF_ERROR:-rclone ($2): $(err_text)}"; return 1; }
    S_OFF_OK=true
    rclone_sync "$BACKUP_DIR/db" "$REMOTE/db" || S_OFF_OK=false
    if [[ -d "$BACKUP_DIR/config" ]]; then rclone_sync "$BACKUP_DIR/config" "$REMOTE/config" || S_OFF_OK=false; fi
    if [[ -n "$S_MEDIA_DIR" && -d "$S_MEDIA_DIR" ]]; then rclone_sync "$S_MEDIA_DIR" "$REMOTE/media" || S_OFF_OK=false; fi
  else S_OFF_ERROR="rclone is not installed"; fi
elif [[ -n "${BACKUP_SSH_TARGET:-}" ]]; then
  S_OFF_KIND=ssh
  if command -v rsync >/dev/null 2>&1; then
    # -H يعيد إنشاء الروابط الصلبة بين لقطات الوسائط على الوجهة فلا يُنقل ولا يُخزَّن إلا ما تغيّر؛ BACKUP_SSH_OPTS اختيارية (مثل "-p 23" لصندوق Hetzner)
    if rsync -azH --delete --exclude .lock --exclude '*.part' -e "ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new ${BACKUP_SSH_OPTS:-}" "$BACKUP_DIR/" "$BACKUP_SSH_TARGET/" 2>"$ERRF"; then S_OFF_OK=true; else S_OFF_ERROR="rsync/ssh: $(err_text)"; fi
  else S_OFF_ERROR="rsync is not installed"; fi
fi
if [[ -n "$S_OFF_ERROR" ]]; then note "offsite: $S_OFF_ERROR"; fi

# ---- 7) الحالة والسجل (سطر واحد لكل تشغيل)
STEP="status"
S_OK=true
write_status normal
trap - ERR
DUR=$(( $(date +%s) - START_EPOCH ))
joined=""; for n in "${NOTES[@]}"; do joined+="${joined:+; }$n"; done
log "ok db=$(basename "$DUMP") bytes=$S_DB_BYTES media=$S_MEDIA_FILES config=$(printf '%s' "$S_CONFIG_FILES" | grep -c . || true) offsite=$S_OFF_KIND/$S_OFF_OK kept=$S_KEPT_DUMPS/$S_KEPT_MEDIA durationSec=$DUR notes=\"$joined\""
echo "[backup] done in ${DUR}s: $(basename "$DUMP")"
if [[ "$S_OFF_KIND" != none && "$S_OFF_OK" != true ]]; then exit 2; fi
