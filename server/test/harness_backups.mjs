// النسخ الاحتياطي (server/backups.js + server/backup.sh): الوحدة الخالصة backupsInfo (ملف غائب → installed:false، ملف تالف →
// نص خطأ بلا رمي، 40 ساعة → stale، ok:false → stale، حديث مع rclone وتمرين قريب → سليم، ssh فاشل وتمرين قديم، قائمة النسخ
// الأحدث أولاً)، المسار /adminapi/backups (401 بلا مستخدم، 403 لغير المدير، 200)، ثم السكربت الحقيقي في مجلد مؤقت: نسخة كاملة
// (dump + sha256 + لقطة وسائط + سطر سجل)، تمرين استعادة في قاعدة مؤقتة يطابق عدد المستخدمين الحي ويحذفها، التدوير (نسخة
// عمرها 20 يوماً تُحذف وKEEP_MEDIA يقلّم اللقطات)، الفشل (قاعدة غير موجودة → خروج غير صفري وok:false مع نص الخطأ وبقاء drill)،
// ملف البيئة (MEDIA_DIR فارغ يتخطى الوسائط)، وتمرين بلا نسخة يفشل برسالة.
import Fastify from 'fastify';
import pg from 'pg';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { backupsInfo, STALE_HOURS, DRILL_STALE_DAYS, MAX_DUMPS } from '../backups.js';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0';
let fails = 0;
const check = (c, l, extra = '') => { if (!c) fails++; console.log((c ? 'OK  ' : 'FAIL') + ' ' + l + (extra ? ' ' + extra : '')); };

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'naslife-backups-'));
const statusPath = path.join(tmp, 'last.json'), backupDir = path.join(tmp, 'backups'), logPath = path.join(tmp, 'backup.log');
process.env.NASLIFE_BACKUP_STATUS = statusPath; process.env.NASLIFE_BACKUP_DIR = backupDir;
const DB = process.env.NASLIFE_TEST_DB || 'naslife_test';
const DB_URL = `postgres://postgres:pg@127.0.0.1:5432/${DB}`;
const script = new URL('../backup.sh', import.meta.url).pathname;
const iso = (hoursAgo) => new Date(Date.now() - hoursAgo * 3600000).toISOString();
const writeStatus = (o) => fs.writeFileSync(statusPath, JSON.stringify(o));
const readStatus = () => JSON.parse(fs.readFileSync(statusPath, 'utf8'));
const baseStatus = (over = {}) => ({ version: 1, startedAt: iso(1), finishedAt: iso(1), ok: true, error: null, durationSec: 12, db: { file: backupDir + '/db/naslife-x.dump', bytes: 1234, sha256: 'ab' }, media: { source: '/opt/naslife/media', dir: null, files: 7, bytes: 99 }, config: { files: ['auth-key'] }, offsite: { kind: 'none', ok: false, error: null }, kept: { dumps: 3, mediaSnapshots: 2 }, drill: null, ...over });
const dumpsIn = () => (fs.existsSync(path.join(backupDir, 'db')) ? fs.readdirSync(path.join(backupDir, 'db')).filter((n) => n.endsWith('.dump')) : []);
const snapsIn = () => (fs.existsSync(path.join(backupDir, 'media')) ? fs.readdirSync(path.join(backupDir, 'media')).filter((n) => n !== 'latest') : []);

// ---- الوحدة الخالصة
check(STALE_HOURS === 30 && DRILL_STALE_DAYS === 10 && MAX_DUMPS === 20, 'thresholds');
let info = await backupsInfo({ statusPath, dir: backupDir });
check(info.installed === false && info.status === null && info.stale === true && info.offsite === false && info.drill === null && info.drillStale === true && Array.isArray(info.dumps) && info.dumps.length === 0 && info.error === null && info.ageHours === null, 'missing status file → installed:false shape', JSON.stringify(info).slice(0, 200));
fs.writeFileSync(statusPath, '{not json');
info = await backupsInfo({ statusPath, dir: backupDir });
check(info.installed === true && info.status === null && typeof info.error === 'string' && info.error.startsWith('status-unreadable') && info.stale === true, 'garbled status → error string, no throw', info.error);
fs.writeFileSync(statusPath, '[1,2]');
info = await backupsInfo({ statusPath, dir: backupDir });
check(info.installed === true && info.status === null && typeof info.error === 'string', 'non-object status → error string');
writeStatus(baseStatus({ finishedAt: iso(40) }));
info = await backupsInfo({ statusPath, dir: backupDir });
check(info.installed && info.stale === true && info.ageHours >= 39.9 && info.ageHours <= 40.1 && info.error === null, 'finishedAt 40h ago → stale', String(info.ageHours));
writeStatus(baseStatus({ ok: false, error: 'pg_dump failed' }));
info = await backupsInfo({ statusPath, dir: backupDir });
check(info.stale === true && info.status.error === 'pg_dump failed' && info.ageHours <= 1.1, 'ok:false → stale even when fresh');
writeStatus(baseStatus({ offsite: { kind: 'rclone', ok: true, error: null }, drill: { at: iso(3 * 24), ok: true, error: null, tables: 90, rows: { users: 10 }, liveUsers: 10, durationSec: 5 } }));
info = await backupsInfo({ statusPath, dir: backupDir });
check(info.stale === false && info.ageHours >= 0.9 && info.ageHours <= 1.1 && info.offsite === true && info.offsiteError === null && info.drill?.ok === true && Math.round(info.drill.ageDays) === 3 && info.drillStale === false, 'fresh + offsite + recent drill', JSON.stringify({ a: info.ageHours, d: info.drill }));
writeStatus(baseStatus({ offsite: { kind: 'ssh', ok: false, error: 'ssh: timeout' }, drill: { at: iso(12 * 24), ok: true } }));
info = await backupsInfo({ statusPath, dir: backupDir });
check(info.offsite === false && info.offsiteError === 'ssh: timeout' && info.drillStale === true && info.drill.ageDays === 12, 'failed offsite and a drill older than 10 days');
writeStatus(baseStatus({ drill: { at: iso(1), ok: false, error: 'users mismatch' } }));
info = await backupsInfo({ statusPath, dir: backupDir });
check(info.drill?.ok === false && info.drill.error === 'users mismatch' && info.drillStale === false, 'failed drill is reported with its error');
fs.mkdirSync(path.join(backupDir, 'db'), { recursive: true });
for (const [n, ago] of [['naslife-20261001-0330.dump', 20], ['naslife-20261020-0330.dump', 1], ['naslife-20261010-0330.dump', 11], ['notes.txt', 0]]) { const p = path.join(backupDir, 'db', n); fs.writeFileSync(p, n); const t = new Date(Date.now() - ago * 86400000); fs.utimesSync(p, t, t); }
info = await backupsInfo({ statusPath, dir: backupDir });
check(info.dumps.map((d) => d.file).join(',') === 'naslife-20261020-0330.dump,naslife-20261010-0330.dump,naslife-20261001-0330.dump' && info.dumps[0].bytes === 26 && typeof info.dumps[0].at === 'string', 'dumps newest first, .dump files only', info.dumps.map((d) => d.file).join(','));
fs.rmSync(path.join(backupDir, 'db'), { recursive: true, force: true }); fs.rmSync(statusPath, { force: true });

// ---- التجهيز: جدول users للتمرين، ومصادقة وهمية بترويسة x-user
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("INSERT INTO users(id,nickname) VALUES('SA0000001','amr'),('SA0000002','sara'),('SA0000003','khalid') ON CONFLICT DO NOTHING");
globalThis.naslifeIsAdmin = async (uid) => uid === 'SA0000001';
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
app.register((await import('../backups.js')).default, { pool, auth });
await app.ready();
check(typeof globalThis.naslifeBackupsInfo === 'function' && (await globalThis.naslifeBackupsInfo()).installed === false, 'globalThis.naslifeBackupsInfo exposed');
const call = async (method, url, { user = 'SA0000001', expect } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), host: 'naslife.app', 'x-forwarded-proto': 'https' } });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url} [${user}] -> ${r.statusCode}`, r.statusCode === expect ? '' : String(typeof j === 'string' ? j : JSON.stringify(j)).slice(0, 160));
  return j;
};
await call('GET', '/adminapi/backups', { user: null, expect: 401 });
await call('GET', '/adminapi/backups', { user: 'SA0000002', expect: 403 });
let r = await call('GET', '/adminapi/backups', { expect: 200 });
check(r.installed === false && r.stale === true && r.dir === backupDir && r.dumps.length === 0, 'route: not installed');
writeStatus(baseStatus({ finishedAt: iso(40) })); r = await call('GET', '/adminapi/backups', { expect: 200 });
check(r.stale === true && r.ageHours > 39 && r.installed === true, 'route: 40h old → stale');
writeStatus(baseStatus()); r = await call('GET', '/adminapi/backups', { expect: 200 });
check(r.stale === false && r.status.ok === true && r.offsite === false, 'route: fresh');
fs.rmSync(statusPath, { force: true });

// ---- السكربت الحقيقي
const mediaDir = path.join(tmp, 'media');
fs.mkdirSync(path.join(mediaDir, 'sub'), { recursive: true }); fs.writeFileSync(path.join(mediaDir, 'a.jpg'), 'aaaa'); fs.writeFileSync(path.join(mediaDir, 'sub', 'b.mp4'), 'bbbbbb');
const env = { ...process.env, BACKUP_DIR: backupDir, BACKUP_STATUS: statusPath, BACKUP_LOG: logPath, MEDIA_DIR: mediaDir, CONFIG_PATHS: '', DATABASE_URL: DB_URL, NO_SUDO: '1', BACKUP_ENV: path.join(tmp, 'absent.env'), PATH: '/usr/bin:/bin:' + (process.env.PATH || '') };
delete env.BACKUP_RCLONE_REMOTE; delete env.BACKUP_SSH_TARGET;
const run = (args = [], extra = {}) => spawnSync('bash', [script, ...args], { env: { ...env, ...extra }, encoding: 'utf8' });
let p = run();
check(p.status === 0, 'backup.sh exits 0', (p.stderr || '').slice(0, 300));
let st = readStatus();
let dumps = dumpsIn();
check(dumps.length === 1 && st.ok === true && st.error === null && st.db.file === path.join(backupDir, 'db', dumps[0]) && st.db.bytes > 0 && /^naslife-\d{8}-\d{4}(\d{2})?\.dump$/.test(dumps[0]), 'one dump, status ok', dumps.join(','));
const sha = crypto.createHash('sha256').update(fs.readFileSync(st.db.file)).digest('hex');
check(st.db.sha256 === sha && fs.readFileSync(st.db.file + '.sha256', 'utf8').startsWith(`${sha}  ${dumps[0]}`), 'sha256 file matches the dump');
check(st.media.files === 2 && st.media.source === mediaDir && st.media.bytes === 10 && fs.existsSync(path.join(st.media.dir, 'sub', 'b.mp4')) && fs.readlinkSync(path.join(backupDir, 'media', 'latest')) === path.basename(st.media.dir), 'media snapshot with 2 files and a latest symlink', JSON.stringify(st.media));
check(st.version === 1 && st.offsite.kind === 'none' && st.offsite.ok === false && st.offsite.error === null && st.config.files.length === 0 && st.kept.dumps === 1 && st.kept.mediaSnapshots === 1 && st.drill === null && typeof st.durationSec === 'number' && !Number.isNaN(Date.parse(st.startedAt)) && !Number.isNaN(Date.parse(st.finishedAt)), 'status keys (version 1)', JSON.stringify(st).slice(0, 200));
let log = fs.readFileSync(logPath, 'utf8').trim().split('\n');
check(log.length === 1 && / ok db=naslife-.* kept=1\/1 /.test(log[0]), 'exactly one log line per run', log[0]);
r = await call('GET', '/adminapi/backups', { expect: 200 });
check(r.installed && !r.stale && r.dumps.length === 1 && r.dumps[0].file === dumps[0] && r.dumps[0].bytes === st.db.bytes && r.ageHours <= 0.1 && r.drill === null && r.drillStale === true, 'route reads the real status and lists the dump');

// ---- التمرين
const live = Number((await pool.query('SELECT count(*)::int AS n FROM users')).rows[0].n);
p = run(['--drill'], { DRILL_DB: `${DB}_drill` });
check(p.status === 0, 'drill exits 0', (p.stderr || '').slice(0, 300));
st = readStatus();
check(st.drill?.ok === true && st.drill.error === null && st.drill.rows.users === live && st.drill.liveUsers === live && st.drill.tables >= 1 && !Number.isNaN(Date.parse(st.drill.at)) && typeof st.drill.durationSec === 'number', 'drill restored users = live count', JSON.stringify(st.drill));
check(st.ok === true && st.db.sha256 === sha && st.kept.dumps === 1, 'drill merged only the drill key');
check(Number((await pool.query('SELECT count(*)::int AS n FROM pg_database WHERE datname=$1', [`${DB}_drill`])).rows[0].n) === 0, 'drill database dropped afterwards');
check(fs.readFileSync(logPath, 'utf8').trim().split('\n').length === 2, 'drill appended one log line');
r = await call('GET', '/adminapi/backups', { expect: 200 });
check(r.drill?.ok === true && r.drillStale === false && r.drill.ageDays === 0 && r.stale === false, 'route shows the drill');

// ---- التدوير: نسخة عمرها 20 يوماً تُحذف، وKEEP_MEDIA=1 يُبقي أحدث لقطة فقط
const oldDump = path.join(backupDir, 'db', 'naslife-20200101-0000.dump');
fs.writeFileSync(oldDump, 'old'); fs.writeFileSync(oldDump + '.sha256', 'x');
const old = new Date(Date.now() - 20 * 86400000); fs.utimesSync(oldDump, old, old);
fs.writeFileSync(path.join(mediaDir, 'c.txt'), 'c');
p = run([], { KEEP_MEDIA: '1' });
st = readStatus(); dumps = dumpsIn();
check(p.status === 0 && !fs.existsSync(oldDump) && !fs.existsSync(oldDump + '.sha256') && dumps.length === 2 && st.kept.dumps === 2, 'dump older than KEEP_DAYS removed, kept.dumps right', `${dumps.length}/${st.kept.dumps}`);
const snaps = snapsIn();
check(st.kept.mediaSnapshots === 1 && snaps.length === 1 && snaps[0] === path.basename(st.media.dir) && st.media.files === 3 && fs.existsSync(path.join(backupDir, 'media', 'latest', 'c.txt')), 'media snapshots pruned to KEEP_MEDIA, latest points at the newest', snaps.join(','));
check(st.drill?.ok === true && st.drill.rows.users === live, 'drill preserved across normal runs');
check(fs.readFileSync(logPath, 'utf8').includes('rotated naslife-20200101-0000.dump'), 'rotation noted in the log line');

// ---- الفشل: قاعدة غير موجودة
p = run([], { DATABASE_URL: `postgres://postgres:pg@127.0.0.1:5432/${DB}_nope` });
st = readStatus();
check(p.status !== 0 && st.ok === false && typeof st.error === 'string' && /does not exist/.test(st.error) && st.error.startsWith('pg_dump failed'), 'wrong database → non-zero exit and ok:false with the error text', st.error);
check(st.drill?.ok === true && st.db.file === null && dumpsIn().length === 2, 'failed run keeps the drill and leaves no partial dump');
r = await call('GET', '/adminapi/backups', { expect: 200 });
check(r.installed && r.stale === true && r.status.error === st.error && r.dumps.length === 2, 'route: failed run is stale with the error');
// الموضع نفسه في وضع التمرين: قاعدة غير موجودة → drill.ok=false بنص الخطأ، وبقية الحالة كما هي
p = run(['--drill'], { DRILL_DB: `${DB}_drill`, DATABASE_URL: `postgres://postgres:pg@127.0.0.1:5432/${DB}_nope` });
st = readStatus();
check(p.status !== 0 && st.drill.ok === false && /does not exist|failed/.test(st.drill.error) && st.ok === false && st.error.startsWith('pg_dump failed'), 'drill against a missing database fails and touches only the drill key', st.drill.error);

// ---- ملف البيئة: MEDIA_DIR فارغ صراحةً يتخطى الوسائط، والبيئة تغلب الملف
fs.writeFileSync(path.join(tmp, 'backup.env'), '# تجربة\nexport MEDIA_DIR=\nKEEP_DAYS="30"\nBACKUP_LOG=' + path.join(tmp, 'other.log') + '\nBACKUP_STATUS=' + path.join(tmp, 'ignored.json') + '\n');
const envFromFile = { ...env, BACKUP_ENV: path.join(tmp, 'backup.env') }; delete envFromFile.MEDIA_DIR; delete envFromFile.BACKUP_LOG;
p = spawnSync('bash', [script], { env: envFromFile, encoding: 'utf8' });
st = readStatus();
check(p.status === 0 && st.ok === true && st.media.source === null && st.media.files === 0, 'env file: empty MEDIA_DIR skips media', (p.stderr || '').slice(0, 200));
check(fs.existsSync(path.join(tmp, 'other.log')) && fs.readFileSync(logPath, 'utf8').trim().split('\n').length === 5, 'BACKUP_LOG from the file applies when the environment leaves it unset');
check(!fs.existsSync(path.join(tmp, 'ignored.json')) && st.media.files === 0, 'an explicit environment variable wins over the file (BACKUP_STATUS)');

// ---- تمرين بلا أي نسخة
fs.rmSync(path.join(backupDir, 'db'), { recursive: true, force: true });
p = run(['--drill'], { DRILL_DB: `${DB}_drill` });
st = readStatus();
check(p.status !== 0 && st.drill.ok === false && /no dump found/.test(st.drill.error) && st.ok === true, 'drill without a dump fails with a clear message and keeps the last status');
check(Number((await pool.query('SELECT count(*)::int AS n FROM pg_database WHERE datname=$1', [`${DB}_drill`])).rows[0].n) === 0, 'no drill database left behind');

await app.close(); await pool.end();
fs.rmSync(tmp, { recursive: true, force: true });
console.log(fails ? `${fails} FAILED` : 'ALL OK');
process.exit(fails ? 1 : 0);
