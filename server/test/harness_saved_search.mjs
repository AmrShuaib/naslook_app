// اختبارات البحث المحفوظ (server/saved_search.js): الحفظ والتكرار والحد، المطابقة بالتطبيع العربي والنطاق والنوع،
// استبعاد محتوى المستخدم نفسه، الإشعار مرة لكل فحص، والتعطيل والحذف والفحص اليدوي.
import Fastify from 'fastify';
import pg from 'pg';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0';
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("INSERT INTO users(id,nickname) VALUES('SA0000001','amr'),('SA0000002','sara') ON CONFLICT DO NOTHING");
for (const sql of ['DROP TABLE IF EXISTS saved_searches', 'DELETE FROM app_notifications', 'DELETE FROM map_posts', 'DELETE FROM market_listings', "DELETE FROM events WHERE title LIKE '%SS-%'"]) { try { await pool.query(sql); } catch { /* أول تشغيل */ } }
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
const dir = new URL('.', import.meta.url).pathname;
app.register((await import('../notify.js')).default, { pool, auth, pollMs: 3600000, opsDir: dir + 'ops' });
app.register((await import('../commerce.js')).default, { pool, auth });
app.register((await import('../business.js')).default, { pool, auth });
app.register((await import('../map_posts.js')).default, { pool, auth });
app.register((await import('../saved_search.js')).default, { pool, auth, sweepMs: 0 });
await app.ready(); await new Promise((r) => setTimeout(r, 400));
let fails = 0;
const check = (cond, label, extra = '') => { if (!cond) fails++; console.log((cond ? 'OK  ' : 'FAIL') + ' ' + label + (extra ? ' ' + extra : '')); };
const call = async (method, url, { body = {}, user = 'SA0000001', expect } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json', host: 'naslife.app' }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url} -> ${r.statusCode}`, r.statusCode === expect ? '' : JSON.stringify(j).slice(0, 160));
  return j;
};
const notes = async () => (await pool.query("SELECT kind, title, body, data FROM app_notifications WHERE user_id='SA0000001' ORDER BY created_at")).rows;
const sweep = () => globalThis.naslifeSavedSearchSweep();
const st = await call('GET', '/searches/saved/status', { user: null, expect: 200 });
check(st.sources.posts && st.sources.market && st.sources.events && st.sources.biz, 'sources discovered', JSON.stringify(st.sources));

await call('POST', '/searches/saved', { body: { q: 'شقة' }, user: null, expect: 401 });
await call('POST', '/searches/saved', { body: { q: 'ش' }, expect: 400 });
await call('POST', '/searches/saved', { body: { q: 'شقة', radiusKm: 10 }, expect: 400 });
const s1 = await call('POST', '/searches/saved', { body: { q: 'شقة للإيجار', radiusKm: 10, lat: 21.5, lng: 39.2 }, expect: 200 });
check(s1.q === 'شقة للإيجار' && s1.radiusKm === 10 && s1.active === true && s1.existed === false, 'saved with radius', JSON.stringify(s1));
const dup = await call('POST', '/searches/saved', { body: { q: 'شقه للايجار', radiusKm: 15, lat: 21.5, lng: 39.2 }, expect: 200 });
check(dup.id === s1.id && dup.existed === true && dup.radiusKm === 15, 'same query (normalized) updates instead of duplicating');
const s2 = await call('POST', '/searches/saved', { body: { q: 'قهوة', types: ['events', 'bogus'] }, expect: 200 });
check(s2.types.join() === 'events' && s2.radiusKm === null, 'types filtered, no radius', JSON.stringify(s2.types));
check((await call('GET', '/searches/saved', { expect: 200 })).length === 2, 'list mine');
check(!(await call('GET', '/searches/saved', { user: 'SA0000002', expect: 200 })).length, 'other user sees none');

// مطابقات
let sw = await sweep();
check(sw.searches === 2 && sw.notified === 0, 'nothing new yet', JSON.stringify(sw));
await call('POST', '/mapposts', { body: { kind: 'text', bg: '#000', caption: 'شقه للايجار قرب الكورنيش', lat: 21.51, lng: 39.19 }, user: 'SA0000002', expect: 200 });
await call('POST', '/mapposts', { body: { kind: 'text', bg: '#000', caption: 'شقة للإيجار في الرياض', lat: 24.7, lng: 46.7 }, user: 'SA0000002', expect: 200 });
await call('POST', '/mapposts', { body: { kind: 'text', bg: '#000', caption: 'شقة للإيجار مني أنا', lat: 21.5, lng: 39.2 }, user: 'SA0000001', expect: 200 });
await call('POST', '/market', { body: { kind: 'product', category: 'food', title: 'قهوة مختصة', price: 4500 }, user: 'SA0000002', expect: 200 });
sw = await sweep();
check(sw.notified === 1 && sw.found === 1, 'post nearby matches (normalized), far and own excluded; listing ignored for events-only search', JSON.stringify(sw));
let ns = await notes();
check(ns.length === 1 && ns[0].kind === 'saved_search_match' && ns[0].title.includes('يطابق بحثك') && ns[0].body.includes('الكورنيش') && ns[0].data.count === 1, 'notification content', JSON.stringify(ns[0]).slice(0, 200));
sw = await sweep();
check(sw.notified === 0, 'no repeat for the same post');
const ev = await call('POST', '/events', { body: { title: 'SS-أمسية قهوة', startsAt: new Date(Date.now() + 3 * 86400e3).toISOString(), placeName: 'جدة', tiers: [{ name: 'عادي', price: 0, quantity: 10 }] }, user: 'SA0000002', expect: 200 });
sw = await sweep();
ns = await notes();
check(sw.notified === 1 && ns[ns.length - 1].title.includes('قهوة') && ns[ns.length - 1].data.first.type === 'event', 'event matches the events-only search', JSON.stringify(sw));
const listing2 = await call('POST', '/market', { body: { kind: 'service', category: 'other', title: 'تأجير شقق', description: 'شقة للإيجار مفروشة', price: 150000, lat: 21.52, lng: 39.18 }, user: 'SA0000002', expect: 200 });
sw = await sweep();
check(sw.found === 1 && (await notes()).length === 3, 'listing description matches the radius search');
const got = await call('GET', '/searches/saved', { expect: 200 });
check(got.find((x) => x.id === s1.id).matches === 2 && got.find((x) => x.id === s1.id).lastMatchAt, 'match counters updated');
// تعطيل ثم إعادة تفعيل
await call('PATCH', `/searches/saved/${s1.id}`, { body: { active: false }, expect: 200 });
await call('POST', '/mapposts', { body: { kind: 'text', bg: '#000', caption: 'شقة للإيجار جديدة', lat: 21.5, lng: 39.2 }, user: 'SA0000002', expect: 200 });
sw = await sweep();
check(sw.searches === 1 && (await notes()).length === 3, 'inactive search skipped');
await call('PATCH', `/searches/saved/${s1.id}`, { body: { active: true }, expect: 200 });
sw = await sweep();
check((await notes()).length === 3, 're-activation resets the checkpoint (older post not re-reported)');
const run = await call('POST', `/searches/saved/${s1.id}/run`, { expect: 200 });
check(run.count === 3 && run.items.every((i) => ['post', 'listing'].includes(i.type)), 'manual run lists matches of the last 7 days', JSON.stringify(run.count));
await call('PATCH', `/searches/saved/${s1.id}`, { body: { active: false }, user: 'SA0000002', expect: 404 });
await call('DELETE', `/searches/saved/${s2.id}`, { user: 'SA0000002', expect: 404 });
await call('DELETE', `/searches/saved/${s2.id}`, { expect: 200 });
check((await call('GET', '/searches/saved', { expect: 200 })).length === 1, 'delete');
for (let i = 0; i < 19; i++) await call('POST', '/searches/saved', { body: { q: 'كلمة رقم ' + i }, expect: 200 });
await call('POST', '/searches/saved', { body: { q: 'الحادية والعشرون' }, expect: 400 });
await pool.query("DELETE FROM saved_searches"); await pool.query('DELETE FROM map_posts'); await pool.query('DELETE FROM market_listings WHERE id=$1', [listing2.id]); await pool.query("DELETE FROM market_listings WHERE title='قهوة مختصة'"); await pool.query('DELETE FROM events WHERE id=$1', [ev.id]);
await app.close(); await pool.end();
console.log(fails ? `\n${fails} FAILED` : '\nALL SAVED SEARCH TESTS PASSED');
process.exit(fails ? 1 : 0);
