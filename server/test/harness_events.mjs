// مكان الفعالية (server/commerce.js، نوفمبر 2026): POST /events يحفظ إحداثيات يختارها المنشئ (موقع جهازه أو نقطة على الخريطة)
// ويرفض الناقصة أو خارج المدى أو غير الرقمية (400 bad-location) بدل حفظ NaN، ويبقى المكان اختيارياً للمجانية وشرطاً للمدفوعة.
import Fastify from 'fastify';
import pg from 'pg';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0';
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
const HOST = 'SA0000071';
await pool.query("INSERT INTO users(id,nickname) VALUES($1,'evhost') ON CONFLICT DO NOTHING", [HOST]);
for (const sql of ['DELETE FROM ticket_tiers WHERE event_id IN (SELECT id FROM events WHERE host_id=$1)', 'DELETE FROM events WHERE host_id=$1']) { try { await pool.query(sql, [HOST]); } catch { /* أول تشغيل */ } }
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
app.register((await import('../commerce.js')).default, { pool, auth });
await app.ready(); await new Promise((r) => setTimeout(r, 300));
let fails = 0;
const check = (cond, label, extra = '') => { if (!cond) fails++; console.log((cond ? 'OK  ' : 'FAIL') + ' ' + label + (extra ? ' ' + extra : '')); };
const call = async (method, url, { body = {}, user = HOST, expect } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json' }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url} -> ${r.statusCode}`, r.statusCode === expect ? '' : JSON.stringify(j).slice(0, 160));
  return j;
};
const startsAt = new Date(Date.now() + 2 * 86400000).toISOString();
const base = { title: 'أمسية على الكورنيش', startsAt, tiers: [{ name: 'عادي', price: 0, quantity: 30 }] };

// نقطة حددها المنشئ على الخريطة: تُحفظ كما أُرسلت وتعود في التفاصيل والقائمة
const ev = await call('POST', '/events', { body: { ...base, placeName: 'ممشى الكورنيش', lat: 21.6012, lng: 39.1068 }, expect: 200 });
check(ev.lat === 21.6012 && ev.lng === 39.1068 && ev.placeName === 'ممشى الكورنيش', 'chosen point and place name stored', JSON.stringify([ev.lat, ev.lng]));
const one = await call('GET', `/events/${ev.id}`, { user: null, expect: 200 });
check(one.lat === 21.6012 && one.lng === 39.1068, 'event detail returns the chosen point');
const list = await call('GET', '/events', { user: null, expect: 200 });
check(Array.isArray(list) && list.some((e) => e.id === ev.id && e.lat === 21.6012), 'events list carries the chosen point');
// الأرقام النصية مقبولة (نماذج قديمة)
const str = await call('POST', '/events', { body: { ...base, lat: '26.4207', lng: '50.0888' }, expect: 200 });
check(str.lat === 26.4207 && str.lng === 50.0888, 'numeric strings accepted');
// المرفوض: نصف إحداثية، خارج المدى، غير رقمي
for (const [label, extra] of [['lat without lng', { lat: 21.5 }], ['lng without lat', { lng: 39.1 }], ['lat out of range', { lat: 91, lng: 39.1 }], ['lng out of range', { lat: 21.5, lng: -181 }], ['not a number', { lat: 'abc', lng: 39.1 }], ['NaN string pair', { lat: 'NaN', lng: 'NaN' }]]) {
  const r = await call('POST', '/events', { body: { ...base, ...extra }, expect: 400 });
  check(r.error === 'bad-location', `rejects ${label} with bad-location`);
}
check((await pool.query("SELECT count(*)::int AS n FROM events WHERE host_id=$1 AND (lat = 'NaN'::float8 OR lng = 'NaN'::float8)", [HOST])).rows[0].n === 0, 'no NaN coordinates stored');
// بلا إحداثيات: المجانية مقبولة، والمدفوعة تحتاج مكاناً (اسماً أو نقطة)
const free = await call('POST', '/events', { body: { ...base, lat: null, lng: '' }, expect: 200 });
check(free.lat === null && free.lng === null, 'free event without a point keeps null coordinates');
const paid = { ...base, tiers: [{ name: 'عادي', price: 5000, quantity: 10 }] }; // بالهللة كما يرسلها التطبيق
check((await call('POST', '/events', { body: paid, expect: 400 })).error === 'place-required', 'paid event without name or point → place-required');
const paidPoint = await call('POST', '/events', { body: { ...paid, lat: 21.55, lng: 39.17 }, expect: 200 });
check(paidPoint.lat === 21.55 && paidPoint.tiers[0].price === 5000, 'paid event with a map point only is accepted');
await call('POST', '/events', { body: { ...base, lat: 21.5, lng: 39.1 }, user: null, expect: 401 });

for (const sql of ['DELETE FROM ticket_tiers WHERE event_id IN (SELECT id FROM events WHERE host_id=$1)', 'DELETE FROM events WHERE host_id=$1']) await pool.query(sql, [HOST]);
await app.close(); await pool.end();
console.log(fails ? `\n${fails} FAILED` : '\nALL EVENTS TESTS PASSED');
process.exit(fails ? 1 : 0);
