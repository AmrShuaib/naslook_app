// اختبار محلي حقيقي لإضافتي commerce.js وbusiness.js على Postgres 16 المحلي عبر fastify.inject.
import Fastify from 'fastify';
import pg from 'pg';
process.env.WALLET_TEST_TOPUP = '1';
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false)");
await pool.query("INSERT INTO users(id,nickname) VALUES('SA0000001','amr'),('SA0000002','sara') ON CONFLICT DO NOTHING");
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
app.register((await import('../commerce.js')).default, { pool, auth });
app.register((await import('../business.js')).default, { pool, auth });
await app.ready();
let fails = 0;
const call = async (method, url, { body, user = 'SA0000001', expect } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json' }, payload: body ? JSON.stringify(body) : undefined });
  let j; try { j = r.json(); } catch { j = r.body; }
  const ok = expect == null || r.statusCode === expect;
  if (!ok) fails++;
  console.log((ok ? 'OK  ' : 'FAIL') + ' ' + method + ' ' + url + ' -> ' + r.statusCode + (ok ? '' : ' expected ' + expect) + ' ' + JSON.stringify(j).slice(0, 160));
  return j;
};
const list = await call('GET', '/biz', { user: null, expect: 200 });
console.log('   businesses:', list.length, 'categories:', [...new Set(list.map(b => b.category))].join(','), 'sample:', list[0].name, list[0].minPrice, list[0].itemsCount);
await call('GET', '/biz?category=hotel', { user: null, expect: 200 }).then(l => console.log('   hotels:', l.map(b => b.nameAr).join(' | ')));
await call('GET', '/biz?bbox=39.10,21.60,39.12,21.63', { user: null, expect: 200 }).then(l => console.log('   in corniche bbox:', l.map(b => b.name).join(', ')));
await call('GET', '/biz?q=سينما', { user: null, expect: 200 }).then(l => console.log('   q=سينما:', l.length));
const ikea = await call('GET', '/biz/biz-ikea', { user: null, expect: 200 });
console.log('   ikea items:', ikea.items.map(i => i.title + ' ' + i.price).join(' | '));
await call('GET', '/biz/nope', { user: null, expect: 404 });
// المحفظة: شحن تجريبي 3000 ر.س
await call('POST', '/wallet/topup', { body: { amount: 500000 }, expect: 200 });
await call('POST', '/wallet/topup', { body: { amount: 500000 }, expect: 200 });
await call('POST', '/wallet/topup', { body: { amount: 500000 }, expect: 200 });
await call('POST', '/wallet/topup', { body: { amount: 500000 }, expect: 200 });
// منتج
await call('POST', '/biz/biz-ikea/orders', { body: { itemId: 'ikea-billy', qty: 2 }, user: null, expect: 401 });
const o1 = await call('POST', '/biz/biz-ikea/orders', { body: { itemId: 'ikea-billy', qty: 2 }, expect: 200 });
console.log('   product order total', o1.total, 'code', o1.code, 'cancellable', o1.cancellable);
const oq = await call('POST', '/biz/biz-ikea/orders', { body: { itemId: 'ikea-lack', qty: 99 }, expect: 200 });
console.log('   qty clamped to', oq.qty, '(expect 20) total', oq.total, '(expect 158000)');
// سينما: موعد صالح من القائمة
const vox = await call('GET', '/biz/biz-vox', { expect: 200 });
const slot = vox.items[0].slots[0];
console.log('   vox slots:', vox.items[0].slots.length, 'first', slot.startsAt, 'seats', slot.seatsLeft);
const o2 = await call('POST', '/biz/biz-vox/orders', { body: { itemId: vox.items[0].id, qty: 3, startAt: slot.startsAt }, expect: 200 });
console.log('   ticket total', o2.total, 'startAt', o2.startAt, 'meta', JSON.stringify(o2.meta));
await call('POST', '/biz/biz-vox/orders', { body: { itemId: vox.items[0].id, qty: 1, startAt: '2020-01-01T10:00:00Z' }, expect: 400 });
const vox2 = await call('GET', '/biz/biz-vox', { expect: 200 });
console.log('   seats after:', vox2.items[0].slots[0].seatsLeft, '(was', slot.seatsLeft + ')');
// فندق: ليلتان، غرفتان
const d = (n) => new Date(Date.now() + n * 86400000).toISOString().slice(0, 10) + 'T00:00:00.000Z';
const o3 = await call('POST', '/biz/biz-hilton/orders', { body: { itemId: 'hil-suite', qty: 2, startAt: d(3), endAt: d(5), guests: 3 }, expect: 200 });
console.log('   hotel total', o3.total, 'units', o3.units, 'qty', o3.qty, '(expect 2*2*120000=480000)');
// سعة الجناح 8: حجز 7 غرف أخرى متداخلة يجب أن يفشل، و5 ينجح ثم 2 يفشل
const o7 = await call('POST', '/biz/biz-hilton/orders', { body: { itemId: 'hil-suite', qty: 7, startAt: d(4), endAt: d(6) }, expect: 200 });
console.log('   rooms clamped to', o7.qty, '(expect 5) total', o7.total, '(expect 1200000)');
for (let i = 0; i < 4; i++) await call('POST', '/wallet/topup', { body: { amount: 500000 }, expect: 200 });
await call('POST', '/biz/biz-hilton/orders', { body: { itemId: 'hil-suite', qty: 5, startAt: d(4), endAt: d(6) }, user: 'SA0000002', expect: 409 });
await call('POST', '/wallet/topup', { body: { amount: 500000 }, user: 'SA0000002', expect: 200 });
await call('POST', '/wallet/topup', { body: { amount: 500000 }, user: 'SA0000002', expect: 200 });
await call('POST', '/wallet/topup', { body: { amount: 500000 }, user: 'SA0000002', expect: 200 });
await call('POST', '/wallet/topup', { body: { amount: 500000 }, user: 'SA0000002', expect: 200 });
await call('POST', '/biz/biz-hilton/orders', { body: { itemId: 'hil-suite', qty: 5, startAt: d(4), endAt: d(6) }, user: 'SA0000002', expect: 409 });
await call('POST', '/biz/biz-hilton/orders', { body: { itemId: 'hil-suite', qty: 1, startAt: d(5), endAt: d(7) }, user: 'SA0000002', expect: 200 });
await call('POST', '/biz/biz-hilton/orders', { body: { itemId: 'hil-suite', qty: 1, startAt: d(5), endAt: d(4) }, expect: 400 });
// سيارة: 3 أيام
const o4 = await call('POST', '/biz/biz-budget/orders', { body: { itemId: 'bg-lc', qty: 1, startAt: d(2), endAt: d(5) }, expect: 200 });
console.log('   car total', o4.total, '(expect 3*45000=135000)');
await call('POST', '/biz/biz-budget/orders', { body: { itemId: 'bg-lc', qty: 1, startAt: d(3), endAt: d(4) }, expect: 200 });
await call('POST', '/biz/biz-budget/orders', { body: { itemId: 'bg-lc', qty: 1, startAt: d(3), endAt: d(4) }, expect: 409 });
// المتابعة والمراجعات
await call('POST', '/biz/biz-ikea/follow', { body: {}, expect: 200 });
await call('POST', '/biz/biz-ikea/reviews', { body: { rating: 5, text: 'ممتاز' }, expect: 200 });
await call('POST', '/biz/biz-ikea/reviews', { body: { rating: 3, text: 'جيد' }, user: 'SA0000002', expect: 200 });
await call('POST', '/biz/biz-ikea/reviews', { body: { rating: 9 }, expect: 400 });
const ikea2 = await call('GET', '/biz/biz-ikea', { expect: 200 });
console.log('   ikea followers', ikea2.followers, 'rating', ikea2.rating, 'count', ikea2.ratingCount, 'following', ikea2.following, 'myOrders', ikea2.myOrders.length, 'reviews', ikea2.reviews.length, 'stock billy', ikea2.items[0].stock);
await call('GET', '/biz?following=1', { expect: 200 }).then(l => console.log('   following list:', l.map(b => b.id).join(',')));
await call('DELETE', '/biz/biz-ikea/follow', { body: {}, expect: 200 });
// طلباتي والإلغاء
const mine = await call('GET', '/biz/orders/mine', { expect: 200 });
console.log('   mine:', mine.map(o => o.kind + ':' + o.status + ':' + o.total + ':' + o.cancellable).join(' | '));
const w1 = await call('GET', '/wallet', { expect: 200 });
await call('POST', '/biz/orders/' + o1.id + '/cancel', { body: {}, expect: 200 });
await call('POST', '/biz/orders/' + o1.id + '/cancel', { body: {}, expect: 409 });
await call('POST', '/biz/orders/' + o3.id + '/cancel', { body: {}, user: 'SA0000002', expect: 404 });
const w2 = await call('GET', '/wallet', { expect: 200 });
console.log('   balance before cancel', w1.balance, 'after', w2.balance, '(diff should be', o1.total + ')', 'last tx', w2.recent[0].kind, w2.recent[0].amount, w2.recent[0].note);
const ikea3 = await call('GET', '/biz/biz-ikea', { expect: 200 });
console.log('   stock billy restored:', ikea3.items[0].stock);
await call('POST', '/biz/biz-ikea/checkin', { body: { code: o2.code }, expect: 403 });
console.log(fails ? `\n${fails} FAILED` : '\nALL OK');
await app.close(); await pool.end();
