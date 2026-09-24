// حذف الحساب ذاتياً والصفحات القانونية (server/account_delete.js، server/legal_pages.js):
// الصفحات العامة بلا سكربت، سجل الموافقة، موانع الحذف، التحقق من كلمة السر، الحذف الناعم مع حفظ السجلات المالية،
// تدوير كلمة السر في النواة وحذف الجلسات، حجز الاسم المحذوف، الاسترداد المعلّق للرصيد الموجب، والكنس بعد 30 يوماً.
// النواة وهمية ومرتبطة بجدول users (كما في الخادم الحقيقي): /register و/login و/recover بعبارة استرداد.
import Fastify from 'fastify';
import pg from 'pg';
import fs from 'node:fs';
import crypto from 'node:crypto';
process.env.NASLIFE_HEALTH_BRIDGE = '0';
const OPS = new URL('./ops-test', import.meta.url).pathname;
fs.rmSync(OPS, { recursive: true, force: true });
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query(`DROP TABLE IF EXISTS login_aliases, account_recovery, legal_consents, account_deletions, sessions, profiles, push_subscriptions, contacts, user_flags, admins, team_members CASCADE`);
await pool.query(`DROP TABLE IF EXISTS wallet_tx, wallet_accounts, market_orders, market_listings, map_posts, map_post_likes, events, tickets, biz, biz_claims, biz_orders, admin_audit CASCADE`);
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("ALTER TABLE users ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ");
await pool.query("DELETE FROM users");
await pool.query(`CREATE TABLE sessions (token TEXT PRIMARY KEY, user_id TEXT NOT NULL, created_at TIMESTAMPTZ DEFAULT now());
  CREATE TABLE profiles (user_id TEXT PRIMARY KEY, bio TEXT NOT NULL DEFAULT '', skills TEXT[] DEFAULT '{}', is_public BOOLEAN DEFAULT true);
  CREATE TABLE push_subscriptions (endpoint TEXT PRIMARY KEY, user_id TEXT NOT NULL, subscription JSONB);
  CREATE TABLE contacts (user_id TEXT NOT NULL, contact_id TEXT NOT NULL);
  CREATE TABLE user_flags (user_id TEXT PRIMARY KEY, suspended BOOLEAN NOT NULL DEFAULT false, note TEXT NOT NULL DEFAULT '', updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
  CREATE TABLE admins (user_id TEXT PRIMARY KEY);
  CREATE TABLE admin_audit (id UUID PRIMARY KEY, admin_id TEXT, action TEXT, target TEXT, details JSONB, created_at TIMESTAMPTZ DEFAULT now());
  CREATE TABLE wallet_accounts (user_id TEXT PRIMARY KEY, balance BIGINT NOT NULL DEFAULT 0, points INT NOT NULL DEFAULT 0, updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
  CREATE TABLE wallet_tx (id UUID PRIMARY KEY, user_id TEXT NOT NULL, kind TEXT NOT NULL, amount BIGINT NOT NULL, peer_id TEXT, ref TEXT, note TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
  CREATE TABLE market_listings (id UUID PRIMARY KEY, seller_id TEXT NOT NULL, title TEXT, status TEXT NOT NULL DEFAULT 'active');
  CREATE TABLE market_orders (id UUID PRIMARY KEY, listing_id UUID, buyer_id TEXT NOT NULL, seller_id TEXT NOT NULL, total BIGINT NOT NULL DEFAULT 0, note TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'paid', courier_id TEXT);
  CREATE TABLE map_posts (id UUID PRIMARY KEY, user_id TEXT NOT NULL, media_url TEXT, audio_url TEXT, status TEXT NOT NULL DEFAULT 'active');
  CREATE TABLE map_post_likes (post_id UUID, user_id TEXT);
  CREATE TABLE events (id UUID PRIMARY KEY, host_id TEXT NOT NULL, starts_at TIMESTAMPTZ NOT NULL, cancelled BOOLEAN NOT NULL DEFAULT false);
  CREATE TABLE tickets (id UUID PRIMARY KEY, event_id UUID NOT NULL, user_id TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'valid');
  CREATE TABLE biz (id TEXT PRIMARY KEY, name TEXT, owner_id TEXT, active BOOLEAN NOT NULL DEFAULT true);
  CREATE TABLE biz_claims (biz_id TEXT NOT NULL, user_id TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'approved', PRIMARY KEY (biz_id, user_id));`);

// ---- نواة وهمية تقرأ الأسماء من جدول users (فتغيير الاسم في القاعدة يُلغي الدخول بالاسم القديم)
const secrets = new Map(); // id -> {password, phrase}
let seq = 100, phraseSeq = 0;
const newPhrase = () => 'عبارة ' + (++phraseSeq) + ' كلمات ست متتالية هنا';
const byNick = async (nick) => (await pool.query('SELECT id FROM users WHERE nickname=$1', [nick])).rows[0]?.id ?? null;
const issue = async (id) => { await pool.query('DELETE FROM sessions WHERE user_id=$1', [id]); const t = 'tok-' + id + '-' + (++seq); await pool.query('INSERT INTO sessions(token,user_id) VALUES($1,$2)', [t, id]); return t; };
const app = Fastify();
app.post('/register', async (req, reply) => { const { nickname, password } = req.body ?? {}; if (await byNick(nickname)) return reply.code(409).send({ error: 'nickname-taken' }); const id = 'SA00' + String(++seq).padStart(5, '0'); await pool.query('INSERT INTO users(id,nickname) VALUES($1,$2)', [id, nickname]); secrets.set(id, { password, phrase: newPhrase() }); return { id, nickname, token: await issue(id), recoveryPhrase: secrets.get(id).phrase }; });
app.post('/login', async (req, reply) => { const { handle, password } = req.body ?? {}; const id = await byNick(handle); if (id && secrets.get(id)?.password === password) return { id, nickname: handle, token: await issue(id) }; return reply.code(401).send({ error: 'bad-credentials' }); });
app.post('/recover', async (req, reply) => { const { handle, recoveryPhrase, newPassword } = req.body ?? {}; const id = await byNick(handle); const s = id && secrets.get(id); if (!s || s.phrase !== recoveryPhrase) return reply.code(401).send({ error: 'bad-code' }); s.password = newPassword; s.phrase = newPhrase(); return { id, nickname: handle, token: await issue(id), recoveryPhrase: s.phrase }; });
const auth = async (req) => { const t = req.headers['x-token']; if (!t) return null; return (await pool.query('SELECT user_id FROM sessions WHERE token=$1', [t])).rows[0]?.user_id ?? null; };
const deletedMedia = [];
globalThis.naslifeMediaDelete = async (u) => { deletedMedia.push(u); return true; };
const adminNotes = [];
globalThis.naslifeNotifyAdmins = async (p) => { adminNotes.push(p); };
globalThis.naslifeIsAdmin = async (uid) => (await pool.query('SELECT 1 FROM admins WHERE user_id=$1', [uid])).rowCount > 0;
globalThis.naslifeSettings = { supportHandle: 'naslife_help' };
app.register((await import('../auth_alias.js')).default, { pool, auth, opsDir: OPS });
app.register((await import('../legal_pages.js')).default, { pool, auth });
app.register((await import('../account_delete.js')).default, { pool, auth, opsDir: OPS });
await app.ready();

let fails = 0;
const check = (c, l, extra = '') => { if (!c) fails++; console.log((c ? 'OK  ' : 'FAIL') + ' ' + l + (extra ? ' ' + extra : '')); };
const call = async (method, url, { body, token } = {}) => { const r = await app.inject({ method, url, headers: { 'content-type': 'application/json', ...(token ? { 'x-token': token } : {}) }, payload: body ? JSON.stringify(body) : undefined }); let j; try { j = r.json(); } catch { j = r.body; } return { code: r.statusCode, json: j, headers: r.headers, body: r.body }; };
const n = async (sql, p = []) => (await pool.query(sql, p)).rows[0]?.n ?? 0;

// ================= الصفحات القانونية =================
for (const [path, must] of [['/privacy', ['سياسة الخصوصية', 'id="delete-account"', 'Privacy Policy', 'ميسر']], ['/terms', ['لا تسامح مطلقاً', 'zero tolerance', 'أنظمة المملكة العربية السعودية']], ['/support', ['support@naslife.app', '@naslife_help', 'id="report"', 'id="delete-account"']]]) {
  const r = await call('GET', path);
  check(r.code === 200 && /text\/html/.test(r.headers['content-type']) && must.every((m) => r.body.includes(m)), `${path}: 200 html with required sections`);
  check(!/<script/i.test(r.body) && !/(src|href)="https?:\/\/(?!naslife\.app)/i.test(r.body.replace(/href="mailto:[^"]+"/g, '')), `${path}: no script and no external resources (CSP-safe)`);
  check(r.body.includes('dir="rtl"') && r.body.includes('id="en"'), `${path}: Arabic RTL with an English section`);
}
let r = await call('GET', '/legal');
check(r.code === 301 && r.headers.location === '/privacy', '/legal redirects to /privacy');
r = await call('GET', '/legal/version');
check(r.code === 200 && /^\d{4}-\d{2}-\d{2}$/.test(r.json.version) && r.json.urls.support === 'https://naslife.app/support', 'legal version and store URLs', JSON.stringify(r.json));
const VERSION = r.json.version;
globalThis.naslifeSettings.supportEmail = 'help@areebd.sa';
r = await call('GET', '/support');
check(r.body.includes('help@areebd.sa') && !r.body.includes('support@naslife.app'), 'support email follows the admin setting');
delete globalThis.naslifeSettings.supportEmail;

// ================= التسجيل مع الموافقة =================
r = await call('POST', '/auth/register', { body: { email: 'mona@example.com', nickname: 'mona', password: 'Password1', acceptTerms: true } });
check(r.code === 200 && r.json.token, 'register mona with acceptTerms', JSON.stringify(r.json).slice(0, 120));
let mona = r.json.id, monaTok = r.json.token;
check(await n("SELECT count(*)::int AS n FROM legal_consents WHERE user_id=$1 AND version=$2 AND source='register'", [mona, VERSION]) === 2, 'register consent recorded for terms and privacy');
r = await call('GET', '/legal/consent', { token: monaTok });
check(r.code === 200 && r.json.needs === false, 'consent not needed after registering with acceptTerms');
r = await call('POST', '/auth/register', { body: { email: 'old@example.com', nickname: 'olduser', password: 'Password1' } });
const old = r.json.id, oldTok = r.json.token;
r = await call('GET', '/legal/consent', { token: oldTok });
check(r.code === 200 && r.json.needs === true, 'existing user without consent must accept');
r = await call('POST', '/legal/consent', { token: oldTok, body: { version: '2000-01-01' } });
check(r.code === 409 && r.json.error === 'stale-version', 'stale consent version refused');
r = await call('POST', '/legal/consent', { token: oldTok, body: { version: VERSION, source: 'ios' } });
check(r.code === 200 && r.json.ok === true, 'consent accepted');
r = await call('GET', '/legal/consent', { token: oldTok });
check(r.json.needs === false, 'consent no longer needed');
r = await call('GET', '/legal/consent');
check(r.code === 401, 'consent requires auth');

// ================= موانع الحذف =================
r = await call('GET', '/me/account/delete/preview');
check(r.code === 401, 'preview requires auth');
r = await call('GET', '/me/account/delete/preview', { token: monaTok });
check(r.code === 200 && r.json.canDelete === true && r.json.confirmWord === 'حذف' && r.json.hasRecovery === true, 'clean account can be deleted', JSON.stringify(r.json));
const listing = crypto.randomUUID(), order = crypto.randomUUID();
await pool.query("INSERT INTO market_listings(id,seller_id,title) VALUES($1,'SA0000009','lamp')", [listing]);
await pool.query("INSERT INTO market_orders(id,listing_id,buyer_id,seller_id,total,status) VALUES($1,$2,$3,'SA0000009',5000,'paid')", [order, listing, mona]);
r = await call('GET', '/me/account/delete/preview', { token: monaTok });
check(r.json.canDelete === false && r.json.blockers.some((b) => b.code === 'open-orders'), 'open order blocks deletion');
r = await call('POST', '/me/account/delete', { token: monaTok, body: { password: 'Password1', confirm: 'حذف' } });
check(r.code === 409 && r.json.error === 'blocked' && r.json.blockers[0].code === 'open-orders', 'delete refused while an order is open');
await pool.query("UPDATE market_orders SET status='completed', note='شارع الأمير سلطان، بيت 12' WHERE id=$1", [order]);
const ev = crypto.randomUUID();
await pool.query("INSERT INTO events(id,host_id,starts_at) VALUES($1,$2,now()+interval '3 days')", [ev, mona]);
await pool.query("INSERT INTO tickets(id,event_id,user_id) VALUES($1,$2,'SA0000009')", [crypto.randomUUID(), ev]);
r = await call('GET', '/me/account/delete/preview', { token: monaTok });
check(r.json.blockers.some((b) => b.code === 'hosted-events'), 'hosted future event with sold tickets blocks deletion');
await pool.query("UPDATE tickets SET status='refunded'");
await pool.query("INSERT INTO wallet_accounts(user_id,balance) VALUES($1,-500)", [mona]);
r = await call('GET', '/me/account/delete/preview', { token: monaTok });
check(r.json.blockers.some((b) => b.code === 'wallet-debt'), 'negative balance blocks deletion');
await pool.query("UPDATE wallet_accounts SET balance=2500 WHERE user_id=$1", [mona]);
await pool.query("INSERT INTO wallet_tx(id,user_id,kind,amount) VALUES($1,$2,'topup',3000),($3,$2,'market',-500)", [crypto.randomUUID(), mona, crypto.randomUUID()]);
r = await call('GET', '/me/account/delete/preview', { token: monaTok });
check(r.json.canDelete === true && r.json.warnings.some((w) => w.code === 'wallet-balance') && r.json.balance === 2500, 'positive balance is a warning in preview (refund option)');
r = await call('POST', '/me/account/delete', { token: monaTok, body: { password: 'Password1', confirm: 'حذف' } });
check(r.code === 409 && r.json.blockers.some((b) => b.code === 'wallet-balance'), 'positive balance needs refund:true');
await pool.query("INSERT INTO admins(user_id) VALUES($1)", [old]);
r = await call('GET', '/me/account/delete/preview', { token: oldTok });
check(r.json.blockers.some((b) => b.code === 'staff-account'), 'admin/staff account cannot self-delete');
await pool.query("DELETE FROM admins");

// ================= التحقق =================
r = await call('POST', '/me/account/delete', { token: monaTok, body: { password: 'Password1', confirm: 'نعم' } });
check(r.code === 400 && r.json.error === 'confirm-mismatch', 'wrong confirmation word refused');
r = await call('POST', '/me/account/delete', { token: monaTok, body: { password: 'wrong-pass', confirm: 'حذف', refund: true } });
check(r.code === 403 && r.json.error === 'bad-password', 'wrong password refused');
monaTok = (await pool.query('SELECT token FROM sessions WHERE user_id=$1', [mona])).rows[0]?.token ?? monaTok; // لا يُصدر الدخول الفاشل جلسة جديدة

// ================= الحذف الناعم =================
await pool.query("INSERT INTO profiles(user_id,bio,skills) VALUES($1,'أحب القهوة','{design}')", [mona]);
await pool.query("UPDATE users SET avatar_url='/chat/media/avatar1-0123456789abcdef01234567.jpg' WHERE id=$1", [mona]);
await pool.query("INSERT INTO push_subscriptions(endpoint,user_id) VALUES('https://push.example/1',$1)", [mona]);
await pool.query("INSERT INTO contacts VALUES($1,'SA0000009'),('SA0000009',$1)", [mona]);
const post = crypto.randomUUID();
await pool.query("INSERT INTO map_posts(id,user_id,media_url) VALUES($1,$2,'/chat/media/post001-0123456789abcdef01234567.jpg')", [post, mona]);
await pool.query("INSERT INTO market_listings(id,seller_id,title) VALUES($1,$2,'chair')", [crypto.randomUUID(), mona]);
await pool.query("INSERT INTO biz(id,name,owner_id) VALUES('mine','my shop',$1),('seeded','Seeded Cafe',$1)", [mona]);
await pool.query("INSERT INTO biz_claims(biz_id,user_id) VALUES('seeded',$1)", [mona]);
const walletSumBefore = await n('SELECT COALESCE(sum(amount),0)::bigint AS n FROM wallet_tx');
const txBefore = await n('SELECT count(*)::int AS n FROM wallet_tx WHERE user_id=$1', [mona]);
r = await call('POST', '/me/account/delete', { token: monaTok, body: { password: 'Password1', confirm: 'حذف', refund: true, reason: 'test' } });
check(r.code === 200 && r.json.status === 'pending_refund' && r.json.refundDays === 30, 'delete succeeds with refund pending', JSON.stringify(r.json));
check(r.json.steps?.passwordRotated === true, 'core password rotated with the stored recovery phrase');
const u = (await pool.query('SELECT * FROM users WHERE id=$1', [mona])).rows[0];
check(/^deleted_[0-9a-f]{12}$/.test(u.nickname) && u.avatar_url === null && u.deleted_at, 'user row anonymised (nickname, avatar, deleted_at)', u.nickname);
check(await n('SELECT count(*)::int AS n FROM profiles WHERE user_id=$1', [mona]) === 0, 'profile row removed');
check(await n('SELECT count(*)::int AS n FROM login_aliases WHERE user_id=$1', [mona]) === 0 && await n('SELECT count(*)::int AS n FROM account_recovery WHERE user_id=$1', [mona]) === 0, 'email alias and recovery phrase removed');
check(await n('SELECT count(*)::int AS n FROM sessions WHERE user_id=$1', [mona]) === 0, 'all sessions revoked');
check(await n('SELECT count(*)::int AS n FROM push_subscriptions WHERE user_id=$1', [mona]) === 0 && await n('SELECT count(*)::int AS n FROM contacts WHERE user_id=$1 OR contact_id=$1', [mona]) === 0, 'push subscriptions and contacts removed');
check((await pool.query('SELECT status FROM map_posts WHERE id=$1', [post])).rows[0].status === 'hidden' && await n("SELECT count(*)::int AS n FROM market_listings WHERE seller_id=$1 AND status='hidden'", [mona]) === 1, 'posts and listings hidden');
const bz = Object.fromEntries((await pool.query('SELECT id, owner_id, active FROM biz')).rows.map((x) => [x.id, x]));
check(bz.mine.active === false && bz.mine.owner_id === null && bz.seeded.active === true && bz.seeded.owner_id === null, 'own circle deactivated, claimed seeded circle released', JSON.stringify(bz));
check((await pool.query('SELECT cancelled FROM events WHERE id=$1', [ev])).rows[0].cancelled === true, 'future hosted event cancelled');
check((await pool.query('SELECT note FROM market_orders WHERE id=$1', [order])).rows[0].note === '', 'address in finished order note erased');
check(await n('SELECT count(*)::int AS n FROM wallet_tx WHERE user_id=$1', [mona]) === txBefore && await n('SELECT COALESCE(sum(amount),0)::bigint AS n FROM wallet_tx') === walletSumBefore, 'ledger rows and global sum untouched');
check(await n('SELECT count(*)::int AS n FROM market_orders WHERE buyer_id=$1', [mona]) === 1, 'order record kept for the seller');
check((await pool.query('SELECT suspended, note FROM user_flags WHERE user_id=$1', [mona])).rows[0]?.note === 'account-deleted', 'account flagged as deleted and suspended');
check(deletedMedia.includes('/chat/media/avatar1-0123456789abcdef01234567.jpg'), 'avatar file deleted');
check(adminNotes.some((x) => x.kind === 'account_refund'), 'admins notified about the pending refund');
check(await n("SELECT count(*)::int AS n FROM admin_audit WHERE action='user.self_delete' AND target=$1", [mona]) === 1, 'self deletion audited');
// لا دخول بعد الحذف
r = await call('POST', '/auth/login', { body: { handle: 'mona@example.com', password: 'Password1' } });
check(r.code === 401, 'old email no longer logs in');
r = await call('POST', '/auth/login', { body: { handle: 'mona', password: 'Password1' } });
check(r.code === 401, 'old nickname no longer logs in');
r = await call('POST', '/auth/login', { body: { handle: u.nickname, password: 'Password1' } });
check(r.code === 401, 'new pseudonymous nickname does not accept the old password');
r = await call('GET', '/me/account/delete/preview', { token: monaTok });
check(r.code === 401, 'old session token rejected');
// الاسم محجوز
r = await call('GET', '/auth/nickname-available?nickname=mona');
check(r.json.available === false && r.json.reason === 'reserved', 'deleted nickname reserved');
r = await call('POST', '/auth/register', { body: { email: 'imposter@example.com', nickname: 'mona', password: 'Password1', acceptTerms: true } });
check(r.code === 409 && r.json.error === 'nickname-taken', 'deleted nickname cannot be re-registered');
r = await call('POST', '/auth/register', { body: { email: 'x@example.com', nickname: 'deleted_abc', password: 'Password1' } });
check(r.code === 400 && r.json.error === 'invalid-nickname', 'deleted_ prefix refused at registration');
r = await call('POST', '/auth/register', { body: { email: 'mona@example.com', nickname: 'mona2', password: 'Password1', acceptTerms: true } });
check(r.code === 200, 'the email is free to register a new account');

// ================= متابعة الاسترداد (للمديرين) =================
await pool.query("INSERT INTO admins(user_id) VALUES($1)", [old]);
r = await call('GET', '/adminapi/deletions', { token: oldTok });
check(r.code === 200 && r.json.items[0]?.userId === mona && r.json.items[0].status === 'pending_refund' && r.json.items[0].balance === 2500, 'admin sees the pending refund');
r = await call('POST', `/adminapi/deletions/${mona}/complete`, { token: oldTok, body: {} });
check(r.code === 400, 'refund reference required');
r = await call('POST', `/adminapi/deletions/${mona}/complete`, { token: oldTok, body: { refundRef: 'moyasar-rf-123' } });
check(r.code === 200 && (await pool.query('SELECT status FROM account_deletions WHERE user_id=$1', [mona])).rows[0].status === 'done', 'refund marked done');
r = await call('GET', '/adminapi/deletions', { token: (await call('POST', '/auth/login', { body: { handle: 'mona2', password: 'Password1' } })).json.token });
check(r.code === 403, 'non-admin cannot list deletions');

// ================= الكنس بعد 30 يوماً =================
await pool.query("UPDATE account_deletions SET purge_after=now() - interval '1 minute' WHERE user_id=$1", [mona]);
await globalThis.naslifeAccountSweep();
check(await n('SELECT count(*)::int AS n FROM map_posts WHERE id=$1', [post]) === 0 && deletedMedia.includes('/chat/media/post001-0123456789abcdef01234567.jpg'), 'hidden post and its media purged after 30 days');
check((await pool.query('SELECT purged_at FROM account_deletions WHERE user_id=$1', [mona])).rows[0].purged_at !== null, 'purge recorded');

console.log(fails ? `${fails} FAILED` : 'ALL OK');
await app.close();
// جداول هذه الحزمة مختصرة؛ تُحذف كي تنشئها الإضافات كاملة في الحزم التالية (run.sh all)
await pool.query(`DROP TABLE IF EXISTS sessions, profiles, push_subscriptions, contacts, user_flags, admins, team_members, admin_audit, wallet_tx, wallet_accounts, market_orders, market_listings, map_posts, map_post_likes, events, tickets, biz, biz_claims, biz_orders CASCADE`);
await pool.end();
process.exit(fails ? 1 : 0);
