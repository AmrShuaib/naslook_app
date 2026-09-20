// اختبارات الأمان والإشراف (server/safety.js): الكتم، الكلمات المحظورة عبر الإضافات، تصفية المحظورين، وبلاغات المحتوى
// مع الإخفاء التلقائي وإشعارات المالك والإدارة.
import Fastify from 'fastify';
import pg from 'pg';
import { parseWords, findBanned } from '../safety.js';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0';
let fails = 0;
const check = (cond, label, extra = '') => { if (!cond) fails++; console.log((cond ? 'OK  ' : 'FAIL') + ' ' + label + (extra ? ' ' + extra : '')); };
// وحدات
check(parseWords('احتيال, نصب\nغش،  ').join('|') === 'احتيال|نصب|غش', 'parseWords splits and normalizes', parseWords('احتيال, نصب\nغش،  ').join('|'));
check(findBanned(parseWords('احتيال'), 'هذا العرض إحتيالٌ واضح') === 'احتيال', 'findBanned ignores hamza/tashkeel');
check(findBanned(parseWords('scam'), 'Great SCAM here') === 'scam' && findBanned(parseWords('scam'), 'clean text') === null, 'findBanned case-insensitive');

const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("INSERT INTO users(id,nickname) VALUES('SA0000001','amr'),('SA0000002','sara'),('SA0000003','khalid'),('SA0000004','nora') ON CONFLICT DO NOTHING");
await pool.query("CREATE TABLE IF NOT EXISTS user_blocks (user_id TEXT NOT NULL, blocked_id TEXT NOT NULL, created_at TIMESTAMPTZ DEFAULT now(), PRIMARY KEY (user_id, blocked_id))");
for (const sql of ['DELETE FROM user_blocks', 'DROP TABLE IF EXISTS chat_mutes, content_reports', 'DELETE FROM app_notifications', "INSERT INTO admins(user_id,granted_by) VALUES('SA0000004','test') ON CONFLICT DO NOTHING", 'DELETE FROM map_posts', 'DELETE FROM market_listings']) { try { await pool.query(sql); } catch { /* أول تشغيل */ } }
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
const dir = new URL('.', import.meta.url).pathname;
app.register((await import('../notify.js')).default, { pool, auth, pollMs: 3600000, opsDir: dir + 'ops' });
app.register((await import('../commerce.js')).default, { pool, auth });
app.register((await import('../business.js')).default, { pool, auth });
app.register((await import('../map_posts.js')).default, { pool, auth });
app.register((await import('../safety.js')).default, { pool, auth });
app.register((await import('../admin.js')).default, { pool, auth, webappDir: dir + 'webapp', opsDir: dir + 'ops' });
await app.ready(); await new Promise((r) => setTimeout(r, 500));
const call = async (method, url, { body = {}, user = 'SA0000001', expect } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json', host: 'naslife.app' }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url} -> ${r.statusCode}`, r.statusCode === expect ? '' : JSON.stringify(j).slice(0, 160));
  return j;
};
const st = await call('GET', '/safety/status', { user: null, expect: 200 });
check(st.blocks === true && st.blocksTable === 'user_blocks' && st.threshold === 3, 'status: blocks table discovered, default threshold', JSON.stringify(st));

// ---- الكتم
await call('POST', '/safety/mutes', { body: { peerId: 'SA0000002' }, user: null, expect: 401 });
await call('POST', '/safety/mutes', { body: { peerId: 'SA0000001' }, expect: 400 });
let m = await call('POST', '/safety/mutes', { body: { peerId: 'sa0000002' }, expect: 200 });
check(m.peerId === 'SA0000002' && m.until === null, 'mute forever (id upper-cased)', JSON.stringify(m));
m = await call('POST', '/safety/mutes', { body: { peerId: 'SA0000003', hours: 8 }, expect: 200 });
check(m.until && new Date(m.until) - Date.now() > 7 * 3600e3, 'mute 8 hours', m.until);
let list = await call('GET', '/safety/mutes', { expect: 200 });
check(list.length === 2, 'list mutes');
await pool.query("UPDATE chat_mutes SET until = now() - interval '1 minute' WHERE peer_id='SA0000003'");
list = await call('GET', '/safety/mutes', { expect: 200 });
check(list.length === 1 && list[0].peerId === 'SA0000002', 'expired mute dropped');
await call('DELETE', '/safety/mutes/SA0000002', { expect: 200 });
check(!(await call('GET', '/safety/mutes', { expect: 200 })).length, 'unmute');

// ---- الكلمات المحظورة عبر الإعدادات
await call('POST', '/adminapi/settings', { body: { bannedWords: 'احتيال, نصب', reportThreshold: 2 }, user: 'SA0000004', expect: 200 });
let w = await call('GET', '/safety/words', { expect: 200 });
check(w.words.join('|') === 'احتيال|نصب' && w.threshold === 2, 'words + threshold from admin settings', JSON.stringify(w));
check((await call('POST', '/safety/check', { body: { text: 'عرض نَصْب' }, expect: 200 })).word === 'نصب', 'check endpoint');
let e = await call('POST', '/mapposts', { body: { kind: 'text', bg: '#000000', caption: 'اشترِ الآن', overlays: [{ type: 'text', text: 'بدون إحتيال' }], lat: 21.5, lng: 39.2 }, expect: 400 });
check(e.error === 'banned-words' && e.word === 'احتيال', 'map post rejected on overlay text', JSON.stringify(e));
e = await call('POST', '/market', { body: { kind: 'product', category: 'food', title: 'برجر', description: 'نصب محترم', price: 500 }, expect: 400 });
check(e.error === 'banned-words', 'market listing rejected');
e = await call('POST', '/biz/biz-ikea/reviews', { body: { rating: 4, text: 'احتيال' }, expect: 400 });
check(e.error === 'banned-words', 'review rejected');
const okPost = await call('POST', '/mapposts', { body: { kind: 'text', bg: '#000000', caption: 'عرض نظيف', lat: 21.5, lng: 39.2 }, user: 'SA0000002', expect: 200 });
e = await call('PATCH', `/mapposts/${okPost.id}`, { body: { caption: 'صار نصب' }, user: 'SA0000002', expect: 400 });
check(e.error === 'banned-words', 'patch rejected');
await call('POST', '/adminapi/settings', { body: { bannedWords: '' }, user: 'SA0000004', expect: 200 });
check((await call('POST', '/safety/check', { body: { text: 'نصب' }, expect: 200 })).ok === true, 'empty list allows everything');

// ---- تصفية المحظورين في قائمة المنشورات
const p3 = await call('POST', '/mapposts', { body: { kind: 'text', bg: '#000000', caption: 'من خالد', lat: 21.5, lng: 39.2 }, user: 'SA0000003', expect: 200 });
list = await call('GET', '/mapposts', { expect: 200 });
check(list.some((p) => p.id === p3.id) && list.some((p) => p.id === okPost.id), 'both posts visible before block');
await pool.query("INSERT INTO user_blocks(user_id,blocked_id) VALUES('SA0000001','SA0000003')");
list = await call('GET', '/mapposts', { expect: 200 });
check(!list.some((p) => p.id === p3.id) && list.some((p) => p.id === okPost.id), 'blocked user\'s post hidden from blocker');
check(!(await call('GET', '/mapposts', { user: 'SA0000003', expect: 200 })).some((p) => p.user.id === 'SA0000001'), 'blocker hidden from the blocked too');
check((await call('GET', '/mapposts', { user: null, expect: 200 })).some((p) => p.id === p3.id), 'anonymous sees everything');

// ---- بلاغات المحتوى والإخفاء التلقائي (الحد 2)
await call('POST', '/safety/report', { body: { targetType: 'post', targetId: okPost.id }, user: 'SA0000002', expect: 400 });
await call('POST', '/safety/report', { body: { targetType: 'nope', targetId: okPost.id }, expect: 400 });
await call('POST', '/safety/report', { body: { targetType: 'post', targetId: 'aaaaaaaa-0000-4000-8000-000000000000' }, expect: 404 });
let rep = await call('POST', '/safety/report', { body: { targetType: 'post', targetId: okPost.id, reason: 'مضلل' }, expect: 200 });
check(rep.reports === 1 && rep.hidden === false, 'first report counted, not hidden', JSON.stringify(rep));
rep = await call('POST', '/safety/report', { body: { targetType: 'post', targetId: okPost.id, reason: 'مضلل جداً' }, expect: 200 });
check(rep.reports === 1, 'same reporter does not count twice');
rep = await call('POST', '/safety/report', { body: { targetType: 'post', targetId: okPost.id }, user: 'SA0000003', expect: 200 });
check(rep.reports === 2 && rep.hidden === true, 'second reporter reaches threshold → hidden', JSON.stringify(rep));
const st2 = await pool.query('SELECT status FROM map_posts WHERE id=$1', [okPost.id]);
check(st2.rows[0].status === 'blocked', 'post status blocked');
const notes = (await pool.query('SELECT user_id, kind FROM app_notifications ORDER BY created_at')).rows;
check(notes.some((n) => n.user_id === 'SA0000002' && n.kind === 'post_blocked'), 'owner notified');
check(notes.some((n) => n.user_id === 'SA0000004' && n.kind === 'content_autohidden'), 'admins notified');
check(notes.some((n) => n.user_id === 'SA0000004' && n.kind === 'report_new'), 'admins got the first report');
const l = await call('POST', '/market', { body: { kind: 'product', category: 'food', title: 'مزوّر', price: 500 }, user: 'SA0000002', expect: 200 });
await call('POST', '/safety/report', { body: { targetType: 'listing', targetId: l.id }, expect: 200 });
rep = await call('POST', '/safety/report', { body: { targetType: 'listing', targetId: l.id }, user: 'SA0000003', expect: 200 });
check(rep.hidden === true && (await pool.query('SELECT status FROM market_listings WHERE id=$1', [l.id])).rows[0].status === 'blocked', 'listing auto-hidden');
const reps = await call('GET', `/safety/reports/post/${okPost.id}`, { user: 'SA0000004', expect: 200 });
check(reps.length === 2, 'admin can list reports');
await call('GET', `/safety/reports/post/${okPost.id}`, { user: 'SA0000002', expect: 403 });
await call('POST', '/adminapi/settings', { body: { reportThreshold: 3 }, user: 'SA0000004', expect: 200 });
await pool.query('DELETE FROM user_blocks'); await pool.query('DELETE FROM map_posts'); await pool.query('DELETE FROM market_listings WHERE id=$1', [l.id]);
await app.close(); await pool.end();
console.log(fails ? `\n${fails} FAILED` : '\nALL SAFETY TESTS PASSED');
process.exit(fails ? 1 : 0);
