// اختبارات الدائرة الطبية (server/business.js + business_seed.js): تصنيف مستشفى، عيادات بمواعيد مجانية ضمن أيام العمل،
// خدمات تعريفية لا تُطلب، حجز موعد عيادة لشخص واحد بلا خصم، والإلغاء والبحث.
import Fastify from 'fastify';
import pg from 'pg';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0';
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("INSERT INTO users(id,nickname) VALUES('SA0000001','amr'),('SA0000002','sara') ON CONFLICT DO NOTHING");
try { await pool.query("DELETE FROM biz_orders WHERE biz_id='biz-kfgh'"); } catch { /* أول تشغيل */ }
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
app.register((await import('../commerce.js')).default, { pool, auth });
app.register((await import('../business.js')).default, { pool, auth });
app.register((await import('../search.js')).default, { pool, auth });
await app.ready(); await new Promise((r) => setTimeout(r, 800));
let fails = 0;
const check = (cond, label, extra = '') => { if (!cond) fails++; console.log((cond ? 'OK  ' : 'FAIL') + ' ' + label + (extra ? ' ' + extra : '')); };
const call = async (method, url, { body = {}, user = 'SA0000001', expect } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json', host: 'naslife.app' }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url} -> ${r.statusCode}`, r.statusCode === expect ? '' : JSON.stringify(j).slice(0, 160));
  return j;
};
const list = await call('GET', '/biz?category=hospital', { user: null, expect: 200 });
const kfgh = list.find((b) => b.id === 'biz-kfgh');
check(list.length === 6 && list.every((b) => b.category === 'hospital') && kfgh?.itemsCount === 38, 'hospital listed by category (Jeddah + 5 Dammam)', JSON.stringify({ n: list.length, items: kfgh?.itemsCount }));
const h = await call('GET', '/biz/biz-kfgh', { user: null, expect: 200 });
check(h.nameAr === 'مستشفى الملك فهد العام بجدة' && h.phone === '937' && h.highlights.includes('طوارئ 24 ساعة') && h.lat > 21 && h.lng > 39, 'hospital profile', h.nameAr);
const clinics = h.items.filter((i) => i.kind === 'clinic'), infos = h.items.filter((i) => i.kind === 'info');
check(clinics.length === 21 && infos.length === 17, '21 clinics + 17 info services', `${clinics.length}/${infos.length}`);
const fam = clinics.find((i) => i.id === 'kfgh-family');
check(fam.price === 0 && fam.unit === 'visit' && fam.stock === 6 && fam.meta.floor && Array.isArray(fam.slots) && fam.slots.length > 0, 'clinic: free, visit unit, capacity, slots', JSON.stringify({ price: fam.price, unit: fam.unit, stock: fam.stock, slots: fam.slots.length }));
const dow = (iso) => new Date(new Date(iso).getTime() + 3 * 3600e3).getUTCDay();
check(fam.slots.every((s) => [0, 1, 2, 3, 4].includes(dow(s.startsAt))), 'clinic slots only on Sunday–Thursday');
const days = new Set(fam.slots.map((s) => new Date(new Date(s.startsAt).getTime() + 3 * 3600e3).toISOString().slice(0, 10)));
check(days.size >= 4 && days.size <= 6, 'clinic slots span about a week of work days', String(days.size));
check(fam.slots.every((s) => s.seatsLeft === 6), 'seats left = capacity before bookings');
const er = infos.find((i) => i.id === 'kfgh-er');
check(er.price === 0 && er.slots === undefined && er.meta.hours === '24 ساعة' && er.meta.phone === '997', 'info service carries hours/location/phone', JSON.stringify(er.meta));
// حجز موعد عيادة: مجاني، لشخص واحد، بلا خصم من المحفظة
const before = await call('GET', '/wallet', { expect: 200 });
const slot = fam.slots[0].startsAt;
await call('POST', '/biz/biz-kfgh/orders', { body: { itemId: 'kfgh-family', qty: 3, startAt: slot }, user: null, expect: 401 });
const o = await call('POST', '/biz/biz-kfgh/orders', { body: { itemId: 'kfgh-family', qty: 3, startAt: slot }, expect: 200 });
check(o.total === 0 && o.qty === 1 && o.kind === 'clinic' && o.code.startsWith('NAS-') && o.meta.clinic === 'عيادة طب الأسرة' && o.meta.floor, 'clinic appointment: free, one person, clinic meta', JSON.stringify({ total: o.total, qty: o.qty, kind: o.kind, meta: o.meta }));
const after = await call('GET', '/wallet', { expect: 200 });
check(after.balance === before.balance, 'wallet untouched for a free appointment');
const h2 = await call('GET', '/biz/biz-kfgh', { expect: 200 });
check(h2.items.find((i) => i.id === 'kfgh-family').slots[0].seatsLeft === 5, 'capacity decremented for that slot');
check(h2.myOrders.some((x) => x.id === o.id && x.cancellable === true), 'appointment appears in my orders and is cancellable (>2h ahead)');
await call('POST', '/biz/biz-kfgh/orders', { body: { itemId: 'kfgh-family', startAt: new Date(new Date(slot).getTime() + 7 * 60000).toISOString() }, expect: 400 });
await call('POST', '/biz/biz-kfgh/orders', { body: { itemId: 'kfgh-er' }, expect: 400 });
check((await call('POST', '/biz/biz-kfgh/orders', { body: { itemId: 'kfgh-er' }, expect: 400 })).error === 'not-orderable', 'info service is not orderable');
await call('POST', `/biz/orders/${o.id}/cancel`, { expect: 200 });
check((await call('GET', '/biz/biz-kfgh', { expect: 200 })).items.find((i) => i.id === 'kfgh-family').slots[0].seatsLeft === 6, 'cancel frees the slot');
// البحث يجد المستشفى وعياداته
const sr = await call('GET', '/search?q=عيادة الأسنان', { expect: 200 });
check(sr.items.some((i) => i.bizId === 'biz-kfgh' && i.kind === 'clinic'), 'search finds the dental clinic as an item', JSON.stringify(sr.items.slice(0, 2)));
const sr2 = await call('GET', '/search?q=مستشفى الملك فهد', { expect: 200 });
check(sr2.biz.some((b) => b.id === 'biz-kfgh'), 'search finds the hospital');
await pool.query("DELETE FROM biz_orders WHERE biz_id='biz-kfgh'");
await app.close(); await pool.end();
console.log(fails ? `\n${fails} FAILED` : '\nALL HOSPITAL TESTS PASSED');
process.exit(fails ? 1 : 0);
