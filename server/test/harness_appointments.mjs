// مواعيد الصالونات والخدمات (server/business.js، نوفمبر 2026): أيام العمل يختارها المالك في meta.days بترقيم getUTCDay لتاريخ السعودية
// (0=الأحد … 6=السبت)، تُنقّى وتُرفض القائمة الفارغة، ومواعيد الجمعة والسبت تُولَّد وتُحجز، وما خارج الأيام يُرفض، وفئة الخدمات تضيف
// صنف موعد (clinic) بجانب المنتج ويُحجز.
import Fastify from 'fastify';
import pg from 'pg';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0';
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("INSERT INTO users(id,nickname) VALUES('SA0000001','amr'),('SA0000002','sara') ON CONFLICT DO NOTHING");
for (const sql of ["DELETE FROM biz_orders WHERE biz_id LIKE 'appt-%'", "DELETE FROM biz_items WHERE biz_id LIKE 'appt-%'", "DELETE FROM biz WHERE id LIKE 'appt-%'"]) { try { await pool.query(sql); } catch { /* أول تشغيل */ } }
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
app.register((await import('../commerce.js')).default, { pool, auth });
app.register((await import('../business.js')).default, { pool, auth });
await app.ready(); await new Promise((r) => setTimeout(r, 500));
let fails = 0;
const check = (cond, label, extra = '') => { if (!cond) fails++; console.log((cond ? 'OK  ' : 'FAIL') + ' ' + label + (extra ? ' ' + extra : '')); };
const call = async (method, url, { body = {}, user = 'SA0000001', expect } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json' }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url} -> ${r.statusCode}`, r.statusCode === expect ? '' : JSON.stringify(j).slice(0, 160));
  return j;
};
// يوم الأسبوع بتاريخ السعودية (UTC+3) كما يقرؤه الخادم
const dow = (iso) => new Date(new Date(iso).getTime() + 3 * 3600e3).getUTCDay();
/// اليوم i من الآن (بتاريخ السعودية) الساعة hh:00 بصيغة ISO؛ نافذة المواعيد سبعة أيام (0..6)
const dayAt = (i, hh) => { const loc = new Date(Date.now() + 3 * 3600e3); return new Date(Date.UTC(loc.getUTCFullYear(), loc.getUTCMonth(), loc.getUTCDate() + i, hh, 0) - 3 * 3600e3).toISOString(); };
// يوم مستقبلي داخل النافذة ليس جمعة ولا سبتاً (لاختبار الرفض خارج أيام العمل)
const offDay = [2, 3, 4, 5, 6].find((i) => ![5, 6].includes(dow(dayAt(i, 10))));

// ---- صالون موثّق: خدمة بموعد يومي الجمعة والسبت
const salon = await call('POST', '/biz', { body: { name: 'Lamsa Salon', nameAr: 'صالون لمسة', category: 'salon', sector: 'تجميل', lat: 21.55, lng: 39.17, address: 'الروضة' }, expect: 200 });
await pool.query("UPDATE biz SET id='appt-salon', verified=true, verification='{\"status\":\"approved\"}' WHERE id=$1", [salon.id]);
const S = 'appt-salon';
await call('POST', `/biz/${S}/items`, { body: { kind: 'clinic', title: 'قص', price: 6000, stock: 1, meta: { times: ['10:00'], days: [] } }, expect: 400 });
check((await call('POST', `/biz/${S}/items`, { body: { kind: 'clinic', title: 'قص', price: 6000, stock: 1, meta: { times: ['10:00'], days: [] } } })).error === 'bad-days', 'explicit empty work days rejected (bad-days)');
check((await call('POST', `/biz/${S}/items`, { body: { kind: 'clinic', title: 'قص', price: 6000, stock: 1, meta: { times: ['10:00'], days: [9, -1, 'x'] } } })).error === 'bad-days', 'only invalid day numbers → bad-days');
check((await call('POST', `/biz/${S}/items`, { body: { kind: 'clinic', title: 'قص', price: 6000, stock: 1, meta: { days: [5] } } })).error === 'bad-times', 'appointment still needs a daily time');
const cut = await call('POST', `/biz/${S}/items`, { body: { kind: 'clinic', title: 'قص وتصفيف', price: 6000, stock: 1, meta: { times: ['10:00', '18:00'], days: [6, '5', 5, 7, 2.5], minutes: 30 } }, expect: 200 });
check(cut.kind === 'clinic' && cut.unit === 'visit' && JSON.stringify(cut.meta.days) === '[5,6]', 'days sanitized to unique sorted ints 0..6', JSON.stringify(cut.meta.days));
// النافذة سبعة أيام فيها جمعة وسبت دائماً، ويبقى منهما موعد مستقبلي على الأقل
check(cut.slots.length >= 2 && cut.slots.every((s) => [5, 6].includes(dow(s.startsAt))), 'slots only on Friday and Saturday (Riyadh date)', JSON.stringify(cut.slots.map((s) => dow(s.startsAt))));
const fri = cut.slots[0].startsAt;
const det = await call('GET', `/biz/${S}`, { user: null, expect: 200 });
const pubCut = det.items.find((i) => i.id === cut.id);
check(pubCut.slots.some((s) => s.startsAt === fri) && pubCut.slots.every((s) => s.seatsLeft === 1), 'guest sees the weekend slots with one seat each', fri);
// العميل يحجز موعد نهاية الأسبوع؛ يوم خارج أيام العمل يُرفض
const sun = dayAt(offDay, 10);
await call('POST', '/wallet/topup', { body: { amount: 20000 }, user: 'SA0000002', expect: 200 });
check((await call('POST', `/biz/${S}/orders`, { body: { itemId: cut.id, startAt: sun }, user: 'SA0000002', expect: 400 })).error === 'bad-slot', 'a time on a day outside the work days is not bookable', `dow=${dow(sun)}`);
const o = await call('POST', `/biz/${S}/orders`, { body: { itemId: cut.id, startAt: fri, qty: 3 }, user: 'SA0000002', expect: 200 });
check(o.kind === 'clinic' && o.qty === 1 && o.total === 6000 && new Date(o.startAt).toISOString() === fri && [5, 6].includes(dow(o.startAt)) && new Date(o.endAt).getTime() - new Date(o.startAt).getTime() === 30 * 60000, 'weekend appointment booked for one person with its duration', JSON.stringify({ qty: o.qty, total: o.total, startAt: o.startAt }));
check((await call('POST', `/biz/${S}/orders`, { body: { itemId: cut.id, startAt: fri }, user: 'SA0000002', expect: 409 })).error === 'sold-out', 'one client per slot: the same slot is now full');
check((await call('GET', `/biz/${S}`, { user: null, expect: 200 })).items.find((i) => i.id === cut.id).slots.find((s) => s.startsAt === fri).seatsLeft === 0, 'slot shows zero seats after booking');
// تعديل الأيام: القائمة الفارغة مرفوضة، والأسبوع كله يفتح الأحد
check((await call('PATCH', `/biz/${S}/items/${cut.id}`, { body: { meta: { times: ['10:00', '18:00'], days: [] } }, expect: 400 })).error === 'bad-days', 'PATCH with empty days rejected');
const all = await call('PATCH', `/biz/${S}/items/${cut.id}`, { body: { meta: { times: ['10:00', '18:00'], days: [0, 1, 2, 3, 4, 5, 6], minutes: 30 } }, expect: 200 });
check(new Set(all.slots.map((s) => dow(s.startsAt))).size === 7 || all.slots.length >= 12, 'all seven days produce slots across the week', String(new Set(all.slots.map((s) => dow(s.startsAt))).size));
await call('POST', `/biz/${S}/orders`, { body: { itemId: cut.id, startAt: sun }, user: 'SA0000002', expect: 200 });
// صنف موعد بلا أيام محفوظة (بيانات قديمة) = كل الأيام
await pool.query("UPDATE biz_items SET meta = meta - 'days' WHERE id=$1", [cut.id]);
const legacy = (await call('GET', `/biz/${S}`, { user: null, expect: 200 })).items.find((i) => i.id === cut.id);
check(new Set(legacy.slots.map((s) => dow(s.startsAt))).size === 7 || legacy.slots.length >= 12, 'appointment without meta.days keeps every day');
// الصالون يبيع منتجاً أيضاً
const oil = await call('POST', `/biz/${S}/items`, { body: { kind: 'product', title: 'زيت شعر', price: 3500, stock: 5 }, expect: 200 });
check(oil.kind === 'product' && oil.slots === undefined, 'salon can also list a product');
const dflt = await call('POST', `/biz/${S}/items`, { body: { title: 'تسريحة', price: 0, meta: { times: ['12:00'] } }, expect: 200 });
check(dflt.kind === 'clinic', 'salon default item kind stays an appointment');

// ---- خدمات وورش (غير موثّقة): المنتج افتراضي، والموعد باختيار المالك ويُحجز مجاناً
const svc = await call('POST', '/biz', { body: { name: 'Cool Fix', nameAr: 'كول فكس', category: 'services', sector: 'صيانة', lat: 21.56, lng: 39.18, address: 'السلامة' }, expect: 200 });
await pool.query("UPDATE biz SET id='appt-svc' WHERE id=$1", [svc.id]);
const V = 'appt-svc';
const filter = await call('POST', `/biz/${V}/items`, { body: { title: 'فلتر مكيف', price: 2500 }, expect: 200 });
check(filter.kind === 'product', 'services default item kind is a product');
// يوم إجازة الورشة: بعد ثلاثة أيام من اليوم (داخل النافذة ومستقبلي دائماً)
const restDow = dow(dayAt(3, 9));
const visit = await call('POST', `/biz/${V}/items`, { body: { kind: 'clinic', title: 'زيارة فحص مكيف', price: 0, stock: 2, meta: { times: ['09:00', '16:00'], days: [0, 1, 2, 3, 4, 5, 6].filter((d) => d !== restDow), minutes: 60 } }, expect: 200 });
check(visit.kind === 'clinic' && visit.unit === 'visit' && visit.slots.length >= 10 && visit.slots.every((s) => dow(s.startsAt) !== restDow), 'services adds an appointment; no slots on its day off', JSON.stringify(visit.meta.days));
const vo = await call('POST', `/biz/${V}/orders`, { body: { itemId: visit.id, startAt: visit.slots[0].startsAt }, user: 'SA0000002', expect: 200 });
check(vo.kind === 'clinic' && vo.total === 0 && vo.qty === 1, 'free services appointment booked without verification', JSON.stringify({ total: vo.total }));
check((await call('POST', `/biz/${V}/orders`, { body: { itemId: visit.id, startAt: dayAt(3, 16) }, user: 'SA0000002', expect: 400 })).error === 'bad-slot', 'the day off is rejected');
const paid = await call('POST', `/biz/${V}/items`, { body: { kind: 'clinic', title: 'تركيب', price: 15000, stock: 1, meta: { times: ['11:00'] } }, expect: 200 });
check((await call('POST', `/biz/${V}/orders`, { body: { itemId: paid.id, startAt: paid.slots[0].startsAt }, user: 'SA0000002', expect: 403 })).error === 'not-verified', 'paid appointment still needs a verified circle');

await pool.query("DELETE FROM biz_orders WHERE biz_id LIKE 'appt-%'");
await app.close(); await pool.end();
console.log(fails ? `\n${fails} FAILED` : '\nALL APPOINTMENTS TESTS PASSED');
process.exit(fails ? 1 : 0);
