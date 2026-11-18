// بطاقة الدعوة (invite.js) على Postgres المحلي: رمز ثابت لكل مستخدم، صفحة الترحيب (عامة، باسم الداعي، رمز مجهول، تهريب HTML،
// بلا سكربت مضمّن)، وقبول الدعوة (حساب جديد فقط، مرة واحدة، لا يدعو نفسه، متابعة الداعي، إشعاره).
import Fastify from 'fastify';
import pg from 'pg';
import { CODE_RE, NEW_ACCOUNT_DAYS, newCode, welcomeHtml, APP_JS } from '../invite.js';
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: process.env.NASLIFE_TEST_DB || 'naslife_test' });
const AMR = 'SA0000881', NEWBIE = 'SA0000882', OLD = 'SA0000883', EVIL = 'SA0000884', NEW2 = 'SA0000885';
const OURS = [AMR, NEWBIE, OLD, EVIL, NEW2];
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query(`INSERT INTO users(id,nickname,created_at) VALUES('${AMR}','ivamr',now()-interval '90 days'),('${NEWBIE}','ivnew',now()),('${OLD}','ivold',now()-interval '${NEW_ACCOUNT_DAYS + 1} days'),
  ('${EVIL}','<b>x</b>"''',now()-interval '90 days'),('${NEW2}','ivnew2',now()) ON CONFLICT (id) DO UPDATE SET nickname=EXCLUDED.nickname, created_at=EXCLUDED.created_at`);
await pool.query("CREATE TABLE IF NOT EXISTS user_follows (follower_id TEXT NOT NULL, user_id TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (follower_id, user_id))");
await pool.query("CREATE TABLE IF NOT EXISTS profile_ext (user_id TEXT PRIMARY KEY, display_name TEXT NOT NULL DEFAULT '')");
await pool.query("INSERT INTO profile_ext(user_id, display_name) VALUES($1,'عمرو') ON CONFLICT (user_id) DO UPDATE SET display_name='عمرو'", [AMR]);
for (const sql of ['DELETE FROM invite_codes WHERE user_id = ANY($1)', 'DELETE FROM invite_joins WHERE invitee_id = ANY($1) OR inviter_id = ANY($1)', 'DELETE FROM user_follows WHERE follower_id = ANY($1)']) {
  try { await pool.query(sql, [OURS]); } catch { /* أول تشغيل */ }
}
const notes = []; globalThis.naslifeNotify = async (ids, p) => { notes.push({ ids: [].concat(ids), ...p }); };
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
app.register((await import('../invite.js')).default, { pool, auth });
await app.ready();
let fails = 0;
const check = (c, l, extra = '') => { if (!c) fails++; console.log((c ? 'OK  ' : 'FAIL') + ' ' + l + (extra ? ' ' + extra : '')); };
const call = async (method, url, { body, user } = {}) => {
  const r = await app.inject({ method, url, headers: user ? { 'x-user': user } : {}, payload: body });
  let json = null; try { json = JSON.parse(r.body); } catch { /* صفحة */ }
  return { status: r.statusCode, json, text: r.body, headers: r.headers };
};

// ---- الرمز
check(CODE_RE.test(newCode()) && newCode() !== newCode(), 'code: 8 unambiguous characters, random');
check((await call('GET', '/me/invite')).status === 401, 'me/invite: needs a session');
const mine = await call('GET', '/me/invite', { user: AMR });
check(mine.status === 200 && CODE_RE.test(mine.json.code) && mine.json.url.endsWith('/hi/' + mine.json.code) && mine.json.joined === 0, 'me/invite: code, url, zero joined', JSON.stringify(mine.json));
const again = await call('GET', '/me/invite', { user: AMR });
check(again.json.code === mine.json.code, 'me/invite: the code is stable');
const many = await Promise.all(Array.from({ length: 6 }, () => call('GET', '/me/invite', { user: EVIL })));
check(new Set(many.map((r) => r.json?.code)).size === 1 && many.every((r) => r.status === 200), 'me/invite: concurrent first calls give one code');
const code = mine.json.code, evilCode = many[0].json.code;

// ---- الصفحة
const gen = await call('GET', '/hi');
check(gen.status === 200 && /text\/html/.test(gen.headers['content-type']) && gen.text.includes('أهلاً بك في ناس لايف') && gen.text.includes('href="/#/hi"'), 'page: generic welcome, join opens the app sign-up');
check(gen.headers['cache-control'] === 'no-store' && /noindex/.test(gen.headers['x-robots-tag']), 'page: not cached, not indexed');
const pg1 = await call('GET', '/hi/' + code);
check(pg1.text.includes('وصلتك دعوة من <b>عمرو</b>') && pg1.text.includes(`href="/#/hi/${code}"`), 'page: greets with the inviter display name and carries the code');
check((await call('GET', '/hi/' + code.toUpperCase())).text.includes('عمرو'), 'page: the code is case-insensitive');
const unk = await call('GET', '/hi/zzzzzzzz');
check(unk.status === 200 && unk.text.includes('أهلاً بك في ناس لايف') && !unk.text.includes('zzzzzzzz'), 'page: unknown code falls back to the generic page');
check((await call('GET', '/hi/%3Cscript%3E')).text.includes('<script src="/hi/app.js">') , 'page: junk code is the generic page');
const evil = await call('GET', '/hi/' + evilCode);
check(evil.text.includes('&lt;b&gt;x&lt;/b&gt;&quot;&#39;') && !evil.text.includes('<b>x</b>'), 'page: the inviter name is escaped');
for (const p of [gen, pg1, evil]) check((p.text.match(/<script/g) || []).length === 1 && !/<script(?![^>]*src="\/hi\/app\.js")/.test(p.text) && !/ on[a-z]+=/.test(p.text) && !/(?:src|href)="https?:/.test(p.text), 'page: one same-origin script file, no inline handlers, no external resources');
check(welcomeHtml({ inviter: 'س', code: 'abcdef12' }).includes('/#/hi/abcdef12'), 'page: builder is pure');
const js = await call('GET', '/hi/app.js');
check(js.status === 200 && /javascript/.test(js.headers['content-type']) && js.text === APP_JS && (() => { try { new Function(APP_JS); return true; } catch { return false; } })(), 'script: served as a file and parses');

// ---- القبول
check((await call('POST', '/invite/accept', { body: { code } })).status === 401, 'accept: needs a session');
check((await call('POST', '/invite/accept', { body: { code: 'zzzzzzzz' }, user: NEWBIE })).status === 404, 'accept: unknown code');
check((await call('POST', '/invite/accept', { body: { code: '../x' }, user: NEWBIE })).status === 404, 'accept: junk code');
check((await call('POST', '/invite/accept', { body: { code }, user: AMR })).json?.error === 'self', 'accept: cannot invite yourself');
const old = await call('POST', '/invite/accept', { body: { code }, user: OLD });
check(old.status === 409 && old.json.error === 'not-new' && notes.length === 0, 'accept: an older account is not an invitee');
const ok = await call('POST', '/invite/accept', { body: { code: code.toUpperCase() + ' ' }, user: NEWBIE });
check(ok.status === 200 && ok.json.ok && ok.json.inviter.id === AMR && ok.json.inviter.name === 'عمرو' && !ok.json.already, 'accept: a new account is recorded', JSON.stringify(ok.json));
check((await pool.query('SELECT 1 FROM user_follows WHERE follower_id=$1 AND user_id=$2', [NEWBIE, AMR])).rowCount === 1, 'accept: the newcomer follows the inviter');
check(notes.length === 1 && notes[0].ids[0] === AMR && notes[0].kind === 'invite_joined' && notes[0].body.includes('ivnew') && notes[0].data.userId === NEWBIE, 'accept: the inviter is notified', JSON.stringify(notes));
const twice = await call('POST', '/invite/accept', { body: { code }, user: NEWBIE });
check(twice.status === 200 && twice.json.already === true && notes.length === 1, 'accept: second time changes nothing');
const other = await call('POST', '/invite/accept', { body: { code: evilCode }, user: NEWBIE });
check(other.json.already === true && (await pool.query('SELECT inviter_id FROM invite_joins WHERE invitee_id=$1', [NEWBIE])).rows[0].inviter_id === AMR, 'accept: one inviter per invitee');
const race = await Promise.all(Array.from({ length: 5 }, () => call('POST', '/invite/accept', { body: { code }, user: NEW2 })));
check(race.filter((r) => r.json && !r.json.already).length === 1 && notes.length === 2, 'accept: concurrent accepts count once');
check((await call('GET', '/me/invite', { user: AMR })).json.joined === 2, 'me/invite: joined count');

console.log(fails ? `${fails} FAILED` : 'ALL OK');
await app.close(); await pool.end(); process.exit(fails ? 1 : 0);
