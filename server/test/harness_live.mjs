// «القناة الحية» (server/live.js): الناقل الخالص (الترقيم، الحلقة، reset، التصفية بالأنواع، إيقاظ المنتظرين، الإلغاء)،
// المسارات (المصافحة بلا after، العودة الفورية بما بعد after، الانتظار ثم العودة فور الحدث، المهلة، timeout=0، kinds، after
// أقدم من الحلقة → reset، الحالة، الضيف)، وربط map_posts.js: نشر لحظة يبث post بحمولة المشاهد من منظور عام، الحذف يبث
// post_removed، والإخفاء الإداري post_removed ثم الإظهار post_restored.
import Fastify from 'fastify';
import pg from 'pg';
import { createBus, RING, WAIT_MAX, BATCH_MAX } from '../live.js';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0';
let fails = 0;
const check = (c, l, extra = '') => { if (!c) fails++; console.log((c ? 'OK  ' : 'FAIL') + ' ' + l + (extra ? ' ' + extra : '')); };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---- الناقل الخالص
{
  const bus = createBus({ ring: 5 });
  check(bus.emit('') === 0 && bus.seq === 0, 'empty kind is ignored');
  check(bus.emit('post', { id: 'a' }) === 1 && bus.emit('post_removed', { id: 'a' }) === 2, 'sequential numbering');
  const r = bus.since(0, null);
  check(!r.reset && r.events.length === 2 && r.events[0].kind === 'post' && r.events[1].seq === 2, 'since(0) returns both in order');
  check(bus.since(2, null).events.length === 0 && bus.since(1, new Set(['post'])).events.length === 0 && bus.since(0, new Set(['post'])).events.length === 1, 'since filters by cursor and kinds');
  for (let i = 0; i < 6; i++) bus.emit('post', { i });
  check(bus.buffered === 5 && bus.seq === 8, 'ring keeps the last 5', `${bus.buffered}/${bus.seq}`);
  check(bus.since(2, null).reset === true && bus.since(3, null).reset === false && bus.since(3, null).events.length === 5, 'cursor older than the ring → reset; the oldest kept cursor still catches up');
  check(bus.since(8, null).reset === false && bus.since(0, null).reset === true, 'reset only when the gap cannot be filled');
  const t0 = Date.now(); const p = bus.wait(2000); await sleep(30); bus.emit('post', { late: true }); const woke = await p;
  check(woke === true && Date.now() - t0 < 1000, 'wait wakes on emit', `${Date.now() - t0}ms`);
  const t1 = Date.now(); check((await bus.wait(100)) === false && Date.now() - t1 >= 90, 'wait resolves false on timeout');
  let abort; const q = bus.wait(5000, (a) => { abort = a; }); abort(); check((await q) === false && bus.waiting === 0, 'abort hook releases the waiter');
  check(bus.emitted === 9, 'emitted counter');
}
{
  const bus = createBus();
  for (let i = 0; i < RING + 20; i++) bus.emit('post', { i });
  check(bus.since(0, null).reset === true && bus.since(19, null).reset === true && bus.since(20, null).reset === false, 'ring of RING: a cursor before the ring → reset, the first kept one catches up', String(RING));
  const r = bus.since(RING + 20 - 150, null); check(r.events.length === BATCH_MAX && r.events[r.events.length - 1].seq === RING + 20, 'a long catch-up is capped at the newest BATCH_MAX');
}

// ---- التجهيز مع map_posts.js (ينشئ جداوله) وadmin.js (isAdmin) وnotify.js
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("INSERT INTO users(id,nickname,avatar_url) VALUES('SA0000001','amr',NULL),('SA0000002','sara','https://naslife.app/seed/sara.png') ON CONFLICT (id) DO UPDATE SET nickname=EXCLUDED.nickname, avatar_url=EXCLUDED.avatar_url");
for (const sql of ['DROP TABLE IF EXISTS map_post_likes, map_post_views, map_post_events, map_posts', 'DELETE FROM app_notifications', 'DELETE FROM user_flags']) { try { await pool.query(sql); } catch { /* ignore */ } }
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
const dir = new URL('.', import.meta.url).pathname;
app.register((await import('../notify.js')).default, { pool, auth, pollMs: 3600000, opsDir: dir + 'ops' });
app.register((await import('../admin.js')).default, { pool, auth, webappDir: dir + 'webapp', opsDir: dir + 'ops' });
app.register((await import('../map_posts.js')).default, { pool, auth });
app.register((await import('../live.js')).default, { pool, auth });
await app.ready(); await sleep(500);
// جدول admins ينشئه admin.js عند التسجيل، فالبذر بعد الجاهزية (قاعدة الاختبار قد تكون جديدة)
await pool.query("INSERT INTO admins(user_id,granted_by) VALUES('SA0000001','test') ON CONFLICT DO NOTHING");
const call = async (method, url, { body = {}, user = 'SA0000001', expect } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json', host: 'naslife.app', 'x-forwarded-proto': 'https' }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url} [${user}] -> ${r.statusCode}`, r.statusCode === expect ? '' : String(typeof j === 'string' ? j : JSON.stringify(j)).slice(0, 160));
  return j;
};

check(typeof globalThis.naslifeLive?.emit === 'function' && globalThis.naslifeLive.seq === 0, 'globalThis.naslifeLive exposed with seq 0');
let st = await call('GET', '/live/status', { user: null, expect: 200 });
check(st.ok === true && st.seq === 0 && st.waiting === 0 && st.waitMax === WAIT_MAX, 'status for a guest');
let h = await call('GET', '/live/wait', { user: null, expect: 200 });
check(h.seq === 0 && Array.isArray(h.events) && h.events.length === 0 && h.reset === false, 'handshake without after returns the cursor immediately');
h = await call('GET', '/live/wait?after=abc', { expect: 200 }); check(h.seq === 0 && h.events.length === 0, 'bad after behaves like a handshake');
let t0 = Date.now(); h = await call('GET', '/live/wait?after=0&timeout=1', { user: null, expect: 200 });
check(Date.now() - t0 >= 900 && h.events.length === 0 && h.seq === 0, 'nothing pending: waits the timeout then returns empty', `${Date.now() - t0}ms`);
t0 = Date.now(); h = await call('GET', '/live/wait?after=0&timeout=0', { expect: 200 }); check(Date.now() - t0 < 300 && h.events.length === 0, 'timeout=0 never waits');

// ---- نشر لحظة أثناء انتظار معلّق: يعود الطلب فوراً بالحدث وحمولته
t0 = Date.now();
const pending = call('GET', '/live/wait?after=0&timeout=5', { user: null, expect: 200 });
await sleep(80);
const made = await call('POST', '/mapposts', { body: { kind: 'image', mediaUrl: '/chat/media/a.jpg', caption: 'كورنيش الليلة', lat: 21.54, lng: 39.17, placeName: 'الكورنيش' }, user: 'SA0000002', expect: 200 });
const got = await pending;
check(Date.now() - t0 < 2500, 'pending wait resolves as soon as a post is published', `${Date.now() - t0}ms`);
check(got.seq === 1 && got.events.length === 1 && got.events[0].kind === 'post' && got.events[0].seq === 1, 'event post #1');
const ev = got.events[0].data;
check(ev.id === made.id && ev.caption === 'كورنيش الليلة' && ev.user?.nickname === 'sara' && ev.user?.avatarUrl === 'https://naslife.app/seed/sara.png' && ev.mediaUrl === 'https://naslife.app/chat/media/a.jpg' && ev.placeName === 'الكورنيش' && ev.lat === 21.54, 'payload is the viewer shape with the author', JSON.stringify(ev).slice(0, 200));
check(ev.mine === false && ev.liked === false && made.mine === true, 'broadcast payload is from a public viewpoint (not mine/liked), the author still gets mine:true');
check(typeof got.events[0].at === 'string' && !Number.isNaN(Date.parse(got.events[0].at)), 'event carries an ISO timestamp');
h = await call('GET', '/live/wait?after=0&timeout=0', { expect: 200 }); check(h.events.length === 1 && h.seq === 1, 'late client with after=0 gets the buffered event at once');
h = await call('GET', '/live/wait?after=1&timeout=0', { expect: 200 }); check(h.events.length === 0 && h.seq === 1, 'after=1 has nothing pending');

// ---- الحذف والإخفاء الإداري
const p2 = await call('POST', '/mapposts', { body: { kind: 'text', caption: 'نص', lat: 21.5, lng: 39.1 }, user: 'SA0000002', expect: 200 });
await call('DELETE', `/mapposts/${made.id}`, { user: 'SA0000002', expect: 200 });
h = await call('GET', '/live/wait?after=1&timeout=0', { expect: 200 });
check(h.seq === 3 && h.events.map((e) => e.kind).join(',') === 'post,post_removed' && h.events[1].data.id === made.id, 'delete emits post_removed after the second post', h.events.map((e) => e.kind).join(','));
await call('POST', `/mapposts/${p2.id}/block`, { body: { hidden: true }, user: 'SA0000001', expect: 200 });
await call('POST', `/mapposts/${p2.id}/block`, { body: { hidden: false }, user: 'SA0000001', expect: 200 });
h = await call('GET', '/live/wait?after=3&timeout=0', { expect: 200 });
check(h.events.map((e) => e.kind + ':' + e.data.id).join(',') === `post_removed:${p2.id},post_restored:${p2.id}`, 'admin hide → post_removed, unhide → post_restored');
h = await call('GET', '/live/wait?after=1&kinds=post_removed&timeout=0', { expect: 200 });
check(h.events.length === 2 && h.events.every((e) => e.kind === 'post_removed'), 'kinds filter');
h = await call('GET', '/live/wait?after=0&kinds=nope&timeout=1', { expect: 200 }); check(h.events.length === 0 && h.seq === 5, 'unmatched kinds wait then return empty with the current cursor');

// ---- اثنان ينتظران حدثاً واحداً، وبعد after قديم جداً reset
t0 = Date.now();
const w1 = call('GET', '/live/wait?after=5&timeout=5', { expect: 200 }), w2 = call('GET', '/live/wait?after=5&timeout=5', { user: null, expect: 200 });
await sleep(60); st = await call('GET', '/live/status'); check(st.waiting === 2, 'status counts the two waiters');
globalThis.naslifeLive.emit('post', { id: 'x' });
const [a, b] = await Promise.all([w1, w2]);
check(Date.now() - t0 < 2000 && a.events.length === 1 && b.events.length === 1 && a.seq === 6 && b.seq === 6, 'both waiters wake on one emit');
for (let i = 0; i < RING + 5; i++) globalThis.naslifeLive.emit('post', { i });
h = await call('GET', '/live/wait?after=6&timeout=0', { expect: 200 });
check(h.reset === true && h.events.length === 0 && h.seq === RING + 11, 'cursor older than the ring → reset:true and no events');
h = await call('GET', `/live/wait?after=${RING + 11 - 3}&timeout=0`, { expect: 200 }); check(h.reset === false && h.events.length === 3, 'recent cursor catches up normally');
st = await call('GET', '/live/status'); check(st.buffered === RING && st.emitted === RING + 11 && st.waiting === 0, 'status after the flood');

await app.close(); await pool.end();
console.log(fails ? `${fails} FAILED` : 'ALL OK');
process.exit(fails ? 1 : 0);
