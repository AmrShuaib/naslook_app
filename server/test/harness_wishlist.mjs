// اختبارات قائمة الأمنيات (server/wishlist.js): إضافة عناصر مرجعية بأنواعها مع أخذ بياناتها من مصدرها، منع التكرار،
// الأمنيات الحرة، التعديل والحذف، وتحديث التوفر عند اختفاء المصدر.
import Fastify from 'fastify';
import pg from 'pg';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0';
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("INSERT INTO users(id,nickname) VALUES('SA0000001','amr'),('SA0000002','sara') ON CONFLICT DO NOTHING");
await pool.query('DROP TABLE IF EXISTS wishlist_items');
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
const dir = new URL('.', import.meta.url).pathname;
try { await pool.query('DELETE FROM app_notifications'); } catch { /* أول تشغيل */ }
app.register((await import('../commerce.js')).default, { pool, auth });
app.register((await import('../business.js')).default, { pool, auth });
app.register((await import('../map_posts.js')).default, { pool, auth });
app.register((await import('../notify.js')).default, { pool, auth, pollMs: 3600000, opsDir: dir + 'ops' });
app.register((await import('../wishlist.js')).default, { pool, auth, sweepMs: 0 });
await app.ready(); await new Promise((r) => setTimeout(r, 400));
let fails = 0;
const check = (cond, label, extra = '') => { if (!cond) fails++; console.log((cond ? 'OK  ' : 'FAIL') + ' ' + label + (extra ? ' ' + extra : '')); };
const call = async (method, url, { body = {}, user = 'SA0000001', expect } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json', host: 'naslife.app' }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url} -> ${r.statusCode}`, r.statusCode === expect ? '' : JSON.stringify(j).slice(0, 160));
  return j;
};
const st = await call('GET', '/wishlist/status', { user: null, expect: 200 });
check(st.sources.market && st.sources.item && st.sources.event && st.sources.post && st.sources.biz, 'all sources discovered', JSON.stringify(st.sources));

// مصادر: عرض في السوق، منتج دائرة، فعالية، منشور
const listing = await call('POST', '/market', { body: { kind: 'product', category: 'food', title: 'قهوة مختصة', description: 'حبوب', price: 4500, imageUrl: '/chat/media/c.jpg' }, user: 'SA0000002', expect: 200 });
const biz = await call('GET', '/biz/biz-ikea', { user: null, expect: 200 });
const item = biz.items[0];
const ev = await call('POST', '/events', { body: { title: 'أمسية شعرية', startsAt: new Date(Date.now() + 5 * 86400000).toISOString(), placeName: 'الكورنيش', tiers: [{ name: 'عادي', price: 2500, quantity: 50 }] }, user: 'SA0000002', expect: 200 });
const post = await call('POST', '/mapposts', { body: { kind: 'text', bg: '#BF3A1E', caption: 'خصم 30٪', title: 'عرض القهوة', price: 1500, tag: 'offer', lat: 21.5, lng: 39.2 }, user: 'SA0000002', expect: 200 });

await call('POST', '/wishlist', { body: { kind: 'market', refId: listing.id }, user: null, expect: 401 });
let w1 = await call('POST', '/wishlist', { body: { kind: 'market', refId: listing.id, title: 'مزوّر', price: 1 }, expect: 200 });
check(w1.title === 'قهوة مختصة' && w1.price === 4500 && w1.imageUrl === 'https://naslife.app/chat/media/c.jpg' && w1.available === true && w1.subtitle === 'منتج في السوق', 'market wish takes data from the source, not the client', JSON.stringify(w1));
const dup = await call('POST', '/wishlist', { body: { kind: 'market', refId: listing.id }, expect: 200 });
check(dup.id === w1.id && dup.existed === true, 'duplicate reference returns the existing wish');
const w2 = await call('POST', '/wishlist', { body: { kind: 'item', refId: item.id }, expect: 200 });
check(w2.title === item.title && w2.price === item.price && w2.bizId === 'biz-ikea' && w2.subtitle.length > 0, 'biz item wish resolved with business name', JSON.stringify(w2).slice(0, 200));
const w3 = await call('POST', '/wishlist', { body: { kind: 'event', refId: ev.id }, expect: 200 });
check(w3.title === 'أمسية شعرية' && w3.price === 2500 && w3.subtitle.includes('الكورنيش') && w3.available, 'event wish resolved with min ticket price', JSON.stringify(w3).slice(0, 200));
const w4 = await call('POST', '/wishlist', { body: { kind: 'post', refId: post.id }, expect: 200 });
check(w4.title === 'عرض القهوة' && w4.price === 1500 && w4.available, 'post wish resolved', JSON.stringify(w4).slice(0, 160));
const w5 = await call('POST', '/wishlist', { body: { kind: 'biz', refId: 'biz-ikea' }, expect: 200 });
check(w5.title.length > 0 && w5.subtitle === 'دائرة تجارية', 'business wish resolved', w5.title);
await call('POST', '/wishlist', { body: { kind: 'market', refId: 'aaaaaaaa-0000-4000-8000-000000000000' }, expect: 404 });
await call('POST', '/wishlist', { body: { kind: 'nope', refId: 'x' }, expect: 400 });
await call('POST', '/wishlist', { body: { kind: 'custom' }, expect: 400 });
const c1 = await call('POST', '/wishlist', { body: { kind: 'custom', title: 'دراجة كهربائية', note: 'قبل الصيف', price: 250000 }, expect: 200 });
check(c1.kind === 'custom' && c1.title === 'دراجة كهربائية' && c1.note === 'قبل الصيف' && c1.price === 250000 && c1.available === true && c1.refId === null, 'custom wish saved', JSON.stringify(c1).slice(0, 160));
const c2 = await call('POST', '/wishlist', { body: { kind: 'custom', title: 'دراجة كهربائية' }, expect: 200 });
check(c2.id !== c1.id, 'custom wishes may repeat');

let list = await call('GET', '/wishlist', { expect: 200 });
check(list.length === 7 && list[0].kind === 'custom', 'list newest first', list.map((x) => x.kind).join(','));
check(!(await call('GET', '/wishlist', { user: 'SA0000002', expect: 200 })).length, 'another user sees an empty list');

// تعديل: تم، ملاحظة، عنوان الأمنية الحرة فقط
let u = await call('PATCH', `/wishlist/${w1.id}`, { body: { done: true, note: 'أشتريه الأسبوع القادم', title: 'لا يتغير' }, expect: 200 });
check(u.done === true && u.note === 'أشتريه الأسبوع القادم' && u.title === 'قهوة مختصة', 'patch done/note; referenced title untouched', JSON.stringify(u).slice(0, 160));
u = await call('PATCH', `/wishlist/${c1.id}`, { body: { title: 'دراجة', price: 200000 }, expect: 200 });
check(u.title === 'دراجة' && u.price === 200000, 'custom wish title/price editable');
await call('PATCH', `/wishlist/${c1.id}`, { body: { title: '' }, expect: 400 });
await call('PATCH', `/wishlist/${w1.id}`, { body: { done: false }, user: 'SA0000002', expect: 404 });
list = await call('GET', '/wishlist', { expect: 200 });
check(list[list.length - 1].id === w1.id, 'done items sink to the end');

// المصدر اختفى أو أُخفي → غير متاح
await call('PATCH', `/market/${listing.id}`, { body: { status: 'hidden' }, user: 'SA0000002', expect: 200 });
list = await call('GET', '/wishlist', { expect: 200 });
check(list.find((x) => x.id === w1.id).available === false, 'hidden listing → available=false');
await call('DELETE', `/mapposts/${post.id}`, { user: 'SA0000002', expect: 200 });
list = await call('GET', '/wishlist', { expect: 200 });
const gone = list.find((x) => x.id === w4.id);
check(gone && gone.available === false && gone.title === 'عرض القهوة', 'deleted post keeps the saved title but is unavailable');

await call('DELETE', `/wishlist/${w2.id}`, { user: 'SA0000002', expect: 404 });
await call('DELETE', `/wishlist/${w2.id}`, { expect: 200 });
await call('DELETE', `/wishlist/${w2.id}`, { expect: 404 });
check((await call('GET', '/wishlist', { expect: 200 })).length === 6, 'delete removes');
// ---- التنبيهات
await pool.query('DELETE FROM wishlist_items'); await pool.query('DELETE FROM app_notifications');
await call('PATCH', `/market/${listing.id}`, { body: { status: 'active', price: 4500 }, user: 'SA0000002', expect: 200 });
const wa = await call('POST', '/wishlist', { body: { kind: 'market', refId: listing.id }, expect: 200 });
const ev2 = await call('POST', '/events', { body: { title: 'ورشة تصوير', startsAt: new Date(Date.now() + 20 * 3600e3).toISOString(), placeName: 'حي الشاطئ', tiers: [{ name: 'عادي', price: 0, quantity: 30 }] }, user: 'SA0000002', expect: 200 });
const wb = await call('POST', '/wishlist', { body: { kind: 'event', refId: ev2.id }, expect: 200 });
const notes = async () => (await pool.query("SELECT kind, title, body, data FROM app_notifications WHERE user_id='SA0000001' ORDER BY created_at")).rows;
let sw = await globalThis.naslifeWishlistSweep();
check(sw.checked === 2 && sw.priceDrops === 0 && sw.reminders === 1, 'first sweep: no price change, event reminder (20h ahead)', JSON.stringify(sw));
let ns = await notes();
check(ns.length === 1 && ns[0].kind === 'wish_event_reminder' && ns[0].title.includes('ورشة تصوير') && ns[0].body.includes('حي الشاطئ'), 'event reminder notification', JSON.stringify(ns[0]));
await call('PATCH', `/market/${listing.id}`, { body: { price: 3900 }, user: 'SA0000002', expect: 200 });
sw = await globalThis.naslifeWishlistSweep();
check(sw.priceDrops === 1 && sw.reminders === 0, 'price drop detected once, reminder not repeated', JSON.stringify(sw));
ns = await notes();
check(ns.length === 2 && ns[1].kind === 'wish_price_drop' && ns[1].body.includes('45') && ns[1].body.includes('39'), 'price drop notification with old and new price', JSON.stringify(ns[1]));
check((await call('GET', '/wishlist', { expect: 200 })).find((x) => x.id === wa.id).price === 3900, 'stored price updated');
sw = await globalThis.naslifeWishlistSweep();
check(sw.priceDrops === 0 && (await notes()).length === 2, 'no duplicate alert on the next sweep');
await call('PATCH', `/market/${listing.id}`, { body: { price: 4200 }, user: 'SA0000002', expect: 200 });
sw = await globalThis.naslifeWishlistSweep();
check(sw.priceDrops === 0 && (await notes()).length === 2, 'price rise is silent');
await call('PATCH', `/market/${listing.id}`, { body: { status: 'hidden' }, user: 'SA0000002', expect: 200 });
await globalThis.naslifeWishlistSweep();
await call('PATCH', `/market/${listing.id}`, { body: { status: 'active' }, user: 'SA0000002', expect: 200 });
sw = await globalThis.naslifeWishlistSweep();
ns = await notes();
check(sw.available === 1 && ns[ns.length - 1].kind === 'wish_available', 'back-in-stock alert after hide → unhide', JSON.stringify(sw));
await call('PATCH', `/wishlist/${wa.id}`, { body: { done: true }, expect: 200 });
await call('PATCH', `/market/${listing.id}`, { body: { price: 1000 }, user: 'SA0000002', expect: 200 });
sw = await globalThis.naslifeWishlistSweep();
check(sw.priceDrops === 0, 'done wishes are not watched');
void wb;
await pool.query('DELETE FROM wishlist_items'); await pool.query('DELETE FROM market_listings WHERE id=$1', [listing.id]); await pool.query('DELETE FROM events WHERE id = ANY($1)', [[ev.id, ev2.id]]);
await app.close(); await pool.end();
console.log(fails ? `\n${fails} FAILED` : '\nALL WISHLIST TESTS PASSED');
process.exit(fails ? 1 : 0);
