// طلبات الدوائر (server/business.js، نوفمبر 2026): الدفع في المكان (بوابة التوثيق و18+، حجز الموعد، «تم الدفع»، «لم يحضر» وحدّ الثلاث)،
// المبلغ المحجوز للطلبات الجديدة المدفوعة من المحفظة (التحرير عند الاستلام وبعد المهلة، الإلغاء أثناء الحجز، والطلبات القديمة المقيّدة)،
// والنزاعات (الفتح والتجميد والرد والحسم بالاسترداد والتحرير والتقسيم، والصلاحيات).
import Fastify from 'fastify';
import pg from 'pg';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0'; process.env.NODE_ENV = 'test';
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("ALTER TABLE users ADD COLUMN IF NOT EXISTS is_admin BOOLEAN DEFAULT false");
await pool.query("INSERT INTO users(id,nickname,is_admin) VALUES('SB0000001','owner',false),('SB0000002','sara',false),('SB0000003','staff',false),('SB0000004','admin',true),('SB0000005','stranger',false),('SB0000006','poor',false) ON CONFLICT (id) DO UPDATE SET is_admin=EXCLUDED.is_admin");
for (const sql of ["DELETE FROM biz_disputes WHERE biz_id LIKE 'bo-%'", "DELETE FROM biz_orders WHERE biz_id LIKE 'bo-%'", "DELETE FROM biz_staff WHERE biz_id LIKE 'bo-%'", "DELETE FROM biz_items WHERE biz_id LIKE 'bo-%'", "DELETE FROM biz WHERE id LIKE 'bo-%'",
  "DELETE FROM wallet_tx WHERE user_id LIKE 'SB%'", "DELETE FROM wallet_accounts WHERE user_id LIKE 'SB%'"]) { try { await pool.query(sql); } catch { /* أول تشغيل */ } }
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
app.register((await import('../commerce.js')).default, { pool, auth });
app.register((await import('../business.js')).default, { pool, auth });
await app.ready(); await new Promise((r) => setTimeout(r, 500));
// الإشعارات وإقرار 18+ بدائل محلية: نلتقط ما يُرسل، ونتحكم بمن أقرّ
const sent = [];
globalThis.naslifeNotify = async (ids, payload) => { sent.push({ ids: [].concat(ids), ...payload }); };
globalThis.naslifeNotifyAdmins = async (payload) => { sent.push({ ids: ['admins'], ...payload }); };
const minors = new Set();
globalThis.naslifeAdultOk = async (uid) => !minors.has(uid);

let fails = 0;
const check = (cond, label, extra = '') => { if (!cond) fails++; console.log((cond ? 'OK  ' : 'FAIL') + ' ' + label + (extra ? ' ' + extra : '')); };
const call = async (method, url, { body = {}, user = 'SB0000001', expect } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json' }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url} -> ${r.statusCode}`, r.statusCode === expect ? '' : JSON.stringify(j).slice(0, 200));
  return j;
};
const bal = async (u) => Number((await pool.query('SELECT balance FROM wallet_accounts WHERE user_id=$1', [u])).rows[0]?.balance ?? 0);
const txs = async (u, ref) => (await pool.query('SELECT kind, amount FROM wallet_tx WHERE user_id=$1 AND ref=$2 ORDER BY created_at', [u, ref])).rows.map((t) => `${t.kind}:${t.amount}`);
const O = 'SB0000001', C = 'SB0000002', STAFF = 'SB0000003', ADMIN = 'SB0000004', X = 'SB0000005', POOR = 'SB0000006';

// ---- دائرة موثّقة بمالك وموظف، وأصناف: منتج يقبل الدفع في المكان، منتج لا يقبله، موعد يقبله، ودائرة غير موثّقة
const mk = async (name, id) => { const b = await call('POST', '/biz', { body: { name, nameAr: name, category: 'salon', sector: 'تجميل', lat: 21.55, lng: 39.17, address: 'الروضة' }, expect: 200 }); await pool.query('UPDATE biz SET id=$2 WHERE id=$1', [b.id, id]); return id; };
const B = await mk('Venue Salon', 'bo-salon');
await pool.query(`UPDATE biz SET verification='{"status":"approved"}' WHERE id=$1`, [B]);
const U = await mk('Unverified', 'bo-unver');
await call('POST', `/biz/${B}/team`, { body: { userId: STAFF, role: 'staff' }, expect: 200 });
const oil = await call('POST', `/biz/${B}/items`, { body: { kind: 'product', title: 'زيت', price: 5000, stock: 10, payAtVenue: true }, expect: 200 });
const comb = await call('POST', `/biz/${B}/items`, { body: { kind: 'product', title: 'مشط', price: 2000, stock: 10 }, expect: 200 });
const cut = await call('POST', `/biz/${B}/items`, { body: { kind: 'clinic', title: 'قص', price: 6000, stock: 1, payAtVenue: true, meta: { times: ['10:00', '18:00'], minutes: 30 } }, expect: 200 });
const free = await call('POST', `/biz/${B}/items`, { body: { kind: 'product', title: 'استشارة', price: 0 }, expect: 200 });
const uItem = await call('POST', `/biz/${U}/items`, { body: { kind: 'product', title: 'منتج', price: 3000, payAtVenue: true }, expect: 200 });
check(oil.payAtVenue === true && comb.payAtVenue === false && cut.payAtVenue === true, 'payAtVenue is per item and off by default');
const toggled = await call('PATCH', `/biz/${B}/items/${comb.id}`, { body: { payAtVenue: true }, expect: 200 });
const back = await call('PATCH', `/biz/${B}/items/${comb.id}`, { body: { title: 'مشط خشب' }, expect: 200 });
check(toggled.payAtVenue === true && back.payAtVenue === true, 'PATCH toggles the flag and a partial PATCH keeps it');
await call('PATCH', `/biz/${B}/items/${comb.id}`, { body: { payAtVenue: false }, expect: 200 });
check((await call('GET', `/biz/${B}`, { user: null, expect: 200 })).items.find((i) => i.id === oil.id).payAtVenue === true, 'public item carries payAtVenue');

// ================= 1) الدفع في المكان
console.log('\n--- pay at venue');
check((await call('POST', `/biz/${U}/orders`, { body: { itemId: uItem.id, payment: 'at_venue' }, user: POOR, expect: 403 })).error === 'not-verified', 'pay at venue still needs a verified circle');
minors.add(POOR);
check((await call('POST', `/biz/${B}/orders`, { body: { itemId: oil.id, payment: 'at_venue' }, user: POOR, expect: 403 })).error === 'adult-required', 'pay at venue still needs the 18+ declaration');
minors.delete(POOR);
check((await call('POST', `/biz/${B}/orders`, { body: { itemId: comb.id, payment: 'at_venue' }, user: POOR, expect: 409 })).error === 'venue-not-allowed', 'item without the flag refuses pay at venue');
check((await call('POST', `/biz/${B}/orders`, { body: { itemId: oil.id }, user: POOR, expect: 402 })).error === 'insufficient-funds', 'wallet payment without balance is 402');
const v1 = await call('POST', `/biz/${B}/orders`, { body: { itemId: oil.id, qty: 2, payment: 'at_venue' }, user: POOR, expect: 200 });
check(v1.payment === 'at_venue' && v1.paid === false && v1.funds === null && v1.total === 10000 && /^NAS-/.test(v1.code) && v1.status === 'confirmed', 'pay-at-venue order needs no balance, unpaid, has a code', JSON.stringify({ p: v1.payment, paid: v1.paid, f: v1.funds }));
check(await bal(POOR) === 0 && (await txs(POOR, v1.id)).length === 0, 'no wallet movement for pay at venue');
check((await pool.query('SELECT stock FROM biz_items WHERE id=$1', [oil.id])).rows[0].stock === 8, 'pay-at-venue reserves product stock');
check(sent.some((n) => n.kind === 'biz_order' && n.ids.includes(O) && /يُدفع في المكان/.test(n.body)), 'owner notified the order is paid at the venue');
// موعد بالدفع في المكان يحجز الموعد مثل المدفوع
const slot = cut.slots[0].startsAt;
const v2 = await call('POST', `/biz/${B}/orders`, { body: { itemId: cut.id, startAt: slot, payment: 'at_venue' }, user: POOR, expect: 200 });
check(v2.payment === 'at_venue' && v2.startAt && v2.paid === false, 'appointment booked to pay at the venue');
check((await call('POST', `/biz/${B}/orders`, { body: { itemId: cut.id, startAt: slot }, user: C, expect: 409 })).error === 'sold-out', 'the slot is reserved by the pay-at-venue booking');
check((await call('GET', `/biz/${B}`, { user: null, expect: 200 })).items.find((i) => i.id === cut.id).slots.find((s) => s.startsAt === slot).seatsLeft === 0, 'slot shows zero seats');
// الاستلام يُظهر «لم يُدفع بعد» ثم «تم الدفع»
const chk = await call('POST', `/biz/${B}/checkin`, { body: { code: v1.code }, user: STAFF, expect: 200 });
check(chk.status === 'used' && chk.payment === 'at_venue' && chk.paid === false && chk.usedAt, 'check-in by staff: used but still unpaid');
const paid = await call('POST', `/biz/${B}/orders/${v1.id}/paid`, { user: STAFF, expect: 200 });
check(paid.paid === true && paid.paidAt && paid.status === 'used', 'staff confirms «تم الدفع»');
check((await call('POST', `/biz/${B}/orders/${v1.id}/paid`, { user: STAFF, expect: 409 })).error === 'already-paid', 'paid twice is 409');
await call('POST', `/biz/${B}/orders/${v1.id}/paid`, { user: X, expect: 403 });
// «تم الدفع» على حجز مؤكد يجعله مستخدماً، والاستلام مع paid:true يسجّل الدفع مباشرة
const v3 = await call('POST', `/biz/${B}/orders`, { body: { itemId: oil.id, payment: 'at_venue' }, user: POOR, expect: 200 });
const p3 = await call('POST', `/biz/${B}/orders/${v3.id}/paid`, { expect: 200 });
check(p3.status === 'used' && p3.paid === true, 'marking a confirmed order paid also checks it in');
const v4 = await call('POST', `/biz/${B}/orders`, { body: { itemId: oil.id, payment: 'at_venue' }, user: POOR, expect: 200 });
const c4 = await call('POST', `/biz/${B}/checkin`, { body: { orderId: v4.id, paid: true }, expect: 200 });
check(c4.status === 'used' && c4.paid === true, 'check-in with paid:true records the payment in one step');
// «لم يحضر»: قبل الموعد مرفوض، وعلى طلب المحفظة مرفوض، والمنتج يعيد مخزونه
check((await call('POST', `/biz/${B}/orders/${v2.id}/no-show`, { user: STAFF, expect: 409 })).error === 'too-early', 'no-show before the appointment time is refused');
const ns = [];
for (let i = 0; i < 3; i++) {
  const v = await call('POST', `/biz/${B}/orders`, { body: { itemId: oil.id, payment: 'at_venue' }, user: POOR, expect: 200 });
  const before = (await pool.query('SELECT stock FROM biz_items WHERE id=$1', [oil.id])).rows[0].stock;
  const r = await call('POST', `/biz/${B}/orders/${v.id}/no-show`, { user: STAFF, expect: 200 });
  const after = (await pool.query('SELECT stock FROM biz_items WHERE id=$1', [oil.id])).rows[0].stock;
  ns.push(r.noShows);
  check(r.status === 'no_show' && after === before + 1, `no-show #${i + 1} recorded and stock returned`, JSON.stringify({ s: r.status, before, after }));
}
check(JSON.stringify(ns) === '[1,2,3]', 'per-customer no-show count at this circle', JSON.stringify(ns));
check(sent.some((n) => n.kind === 'order_status' && n.ids.includes(POOR) && /عدم حضورك/.test(n.title)), 'customer notified of the no-show');
check((await call('POST', `/biz/${B}/orders`, { body: { itemId: oil.id, payment: 'at_venue' }, user: POOR, expect: 403 })).error === 'venue-blocked', 'after 3 no-shows pay at venue is refused at this circle');
const teamView = await call('GET', `/biz/orders/${v2.id}`, { user: STAFF, expect: 200 });
check(teamView.viewer === 'team' && teamView.noShows === 3 && teamView.customer?.id === POOR, 'team order view shows the customer and no-show count');
// العميل يلغي حجز الدفع في المكان: لا استرداد ولا قيد
const vc = await call('POST', `/biz/${B}/orders`, { body: { itemId: cut.id, startAt: cut.slots[1].startsAt, payment: 'at_venue' }, user: C, expect: 200 });
const cbal = await bal(C);
const cr = await call('POST', `/biz/orders/${vc.id}/cancel`, { user: C, expect: 200 });
check(cr.refunded === 0 && await bal(C) === cbal && (await txs(C, vc.id)).length === 0, 'cancelling a pay-at-venue booking moves no money');
check((await call('POST', `/biz/orders/${v1.id}/dispute`, { body: { reason: 'المنتج تالف تماماً' }, user: POOR, expect: 409 })).error === 'not-disputable', 'pay-at-venue order cannot be disputed (no money in Naslife)');

// ================= 2) المبلغ المحجوز
console.log('\n--- held funds');
await call('POST', '/wallet/topup', { body: { amount: 500000 }, user: C, expect: 200 });
let ob = await bal(O), cb = await bal(C);
const w1 = await call('POST', `/biz/${B}/orders`, { body: { itemId: comb.id }, user: C, expect: 200 });
check(w1.payment === 'wallet' && w1.funds === 'held' && w1.paid === true, 'new wallet order is held', JSON.stringify({ f: w1.funds }));
check(await bal(C) === cb - 2000 && await bal(O) === ob, 'buyer debited, owner not credited at purchase');
const rel = new Date(w1.releaseAt).getTime() - Date.now();
check(rel > 2.9 * 86400e3 && rel < 3.1 * 86400e3, 'product release is 3 days after purchase', String(rel / 86400e3));
const ci = await call('POST', `/biz/${B}/checkin`, { body: { code: w1.code }, expect: 200 });
check(ci.funds === 'released' && ci.releasedAt && await bal(O) === ob + 2000, 'check-in releases the held amount to the owner');
check(JSON.stringify(await txs(O, w1.id)) === '["biz_sale:2000"]', 'one biz_sale entry for the owner', JSON.stringify(await txs(O, w1.id)));
// التحرير التلقائي بعد المهلة، مرة واحدة فقط
ob = await bal(O);
const w2 = await call('POST', `/biz/${B}/orders`, { body: { itemId: comb.id }, user: C, expect: 200 });
check((await globalThis.naslifeBizReleaseDue()) === 0 && await bal(O) === ob, 'nothing released before the hold period');
await pool.query("UPDATE biz_orders SET release_at=now() - interval '1 minute' WHERE id=$1", [w2.id]);
const n1 = await globalThis.naslifeBizReleaseDue(), n2 = await globalThis.naslifeBizReleaseDue();
check(n1 >= 1 && n2 === 0 && await bal(O) === ob + 2000, 'auto-release sweep credits once', JSON.stringify({ n1, n2 }));
const w2s = await call('GET', `/biz/orders/${w2.id}`, { user: C, expect: 200 });
check(w2s.funds === 'released' && w2s.status === 'confirmed' && w2s.viewer === 'customer' && w2s.customer === undefined, 'released while still confirmed; customer view has no customer block');
// مهلة الموعد من نهايته، وقابلة للضبط من الإعدادات
globalThis.naslifeSettings = { ...(globalThis.naslifeSettings ?? {}), bizHoldDays: 5 };
const cut2 = (await call('GET', `/biz/${B}`, { user: null })).items.find((i) => i.id === cut.id);
const freeSlot = cut2.slots.find((s) => s.seatsLeft > 0).startsAt;
const w3 = await call('POST', `/biz/${B}/orders`, { body: { itemId: cut.id, startAt: freeSlot }, user: C, expect: 200 });
check(new Date(w3.releaseAt).getTime() === new Date(w3.endAt).getTime() + 5 * 86400e3, 'appointment release = slot end + bizHoldDays (5)', `${w3.endAt} -> ${w3.releaseAt}`);
globalThis.naslifeSettings = { ...globalThis.naslifeSettings, bizHoldDays: undefined };
// الإلغاء أثناء الحجز يعيد المال للمشتري بلا خصم من صاحب الدائرة (من العميل ومن صاحب الدائرة)
ob = await bal(O); cb = await bal(C);
const cc = await call('POST', `/biz/orders/${w3.id}/cancel`, { user: C, expect: 200 });
check(cc.refunded === 6000 && await bal(C) === cb + 6000 && await bal(O) === ob, 'customer cancel while held: refund without owner debit');
check(JSON.stringify(await txs(O, w3.id)) === '[]' && (await call('GET', `/biz/orders/${w3.id}`, { user: C })).funds === 'refunded', 'no owner ledger entry; funds refunded');
const w4 = await call('POST', `/biz/${B}/orders`, { body: { itemId: comb.id, qty: 2 }, user: C, expect: 200 });
ob = await bal(O); cb = await bal(C);
const oc = await call('POST', `/biz/${B}/orders/${w4.id}/cancel`, { expect: 200 });
check(oc.refunded === 4000 && await bal(C) === cb + 4000 && await bal(O) === ob, 'owner cancel while held: refund without owner debit');
check(sent.some((n) => n.kind === 'order_status' && n.ids.includes(C) && /استُرد/.test(n.body)), 'customer told about the refund');
// طلب قديم (قُيّد لصاحب الدائرة عند الشراء): الإلغاء يخصم من صاحب الدائرة كما كان، والمسح لا يلمسه
const L = await call('POST', `/biz/${B}/orders`, { body: { itemId: comb.id }, user: C, expect: 200 });
await pool.query("UPDATE biz_orders SET funds=NULL, release_at=NULL WHERE id=$1", [L.id]);
await pool.query("UPDATE wallet_accounts SET balance=balance+2000 WHERE user_id=$1", [O]);
const Ls = await call('GET', `/biz/orders/${L.id}`, { user: C, expect: 200 });
check(Ls.funds === 'credited', 'legacy wallet order shows funds credited');
ob = await bal(O); cb = await bal(C);
await call('POST', `/biz/${B}/orders/${L.id}/cancel`, { expect: 200 });
check(await bal(C) === cb + 2000 && await bal(O) === ob - 2000, 'legacy cancel refunds the buyer and debits the owner');
check(JSON.stringify(await txs(O, L.id)) === '["biz_refund_out:-2000"]', 'legacy owner entry biz_refund_out', JSON.stringify(await txs(O, L.id)));
const L2 = await call('POST', `/biz/${B}/orders`, { body: { itemId: comb.id }, user: C, expect: 200 });
await pool.query("UPDATE biz_orders SET funds=NULL, release_at=now() - interval '1 day' WHERE id=$1", [L2.id]);
ob = await bal(O);
await globalThis.naslifeBizReleaseDue();
check(await bal(O) === ob, 'the sweep never credits a legacy order again');
// الإحصاءات: المحجوز والمحرَّر والدفع في المكان
const w5 = await call('POST', `/biz/${B}/orders`, { body: { itemId: comb.id }, user: C, expect: 200 });
const st = await call('GET', `/biz/${B}/stats`, { user: STAFF, expect: 200 });
check(st.money && st.money.held >= 2000 && st.money.released >= 4000 && st.money.venuePaid === 20000 && st.money.venueDue === 6000 && st.money.venueDue >= 0 && st.money.noShows === 3 && st.money.holdDays === 3,
  'stats show held vs released and pay-at-venue amounts', JSON.stringify(st.money));

// ================= 3) النزاعات
console.log('\n--- disputes');
check((await call('POST', `/biz/orders/${w5.id}/dispute`, { body: { reason: 'قصير' }, user: C, expect: 400 })).error === 'bad-reason', 'reason needs at least 5 characters');
await call('POST', `/biz/orders/${w5.id}/dispute`, { body: { reason: 'لم أستلم الطلب' }, user: X, expect: 404 });
sent.length = 0;
const d1 = await call('POST', `/biz/orders/${w5.id}/dispute`, { body: { reason: 'المنتج وصل مكسوراً', photos: ['/media/a.jpg', 'javascript:alert(1)', 'https://x.test/b.jpg', '/m/c', '/m/d', '/m/e'] }, user: C, expect: 200 });
check(d1.dispute?.status === 'open' && d1.dispute.photos.length === 4 && !d1.dispute.photos.includes('javascript:alert(1)') && d1.disputable === false && d1.cancellable === false, 'customer opens a dispute with up to 4 photo links', JSON.stringify(d1.dispute?.photos));
check(sent.some((n) => n.kind === 'biz_dispute' && n.ids.includes(O) && n.data.side === 'team' && n.data.orderId === w5.id) && sent.some((n) => n.kind === 'biz_dispute' && n.ids.includes('admins') && n.data.side === 'admin'), 'owner and admins notified with the order id');
check((await call('POST', `/biz/orders/${w5.id}/dispute`, { body: { reason: 'مرة ثانية للمشكلة' }, user: C, expect: 409 })).error === 'already-disputed', 'one dispute per order');
check((await call('POST', `/biz/orders/${w5.id}/cancel`, { user: C, expect: 409 })).error === 'not-cancellable', 'customer cannot cancel during an open dispute');
// التجميد: لا تحرير بالمسح ولا بالاستلام
ob = await bal(O);
await pool.query("UPDATE biz_orders SET release_at=now() - interval '1 minute' WHERE id=$1", [w5.id]);
await globalThis.naslifeBizReleaseDue();
const ck5 = await call('POST', `/biz/${B}/checkin`, { body: { orderId: w5.id }, expect: 200 });
check(await bal(O) === ob && ck5.funds === 'held' && ck5.status === 'used', 'dispute freezes the release (sweep and check-in)');
// الرد من الطرفين، والغريب لا يرد
const r1 = await call('POST', `/biz/orders/${w5.id}/dispute/reply`, { body: { text: 'نعتذر، نرسل بديلاً' }, user: STAFF, expect: 200 });
const r2 = await call('POST', `/biz/orders/${w5.id}/dispute/reply`, { body: { text: 'شكراً لكم' }, user: C, expect: 200 });
await call('POST', `/biz/orders/${w5.id}/dispute/reply`, { body: { text: 'تطفل' }, user: X, expect: 404 });
check(r1.dispute.messages.length === 1 && r1.dispute.messages[0].by === 'team' && r2.dispute.messages[1].by === 'customer' && r2.customer === undefined, 'team and customer replies kept in order');
check(sent.some((n) => n.kind === 'biz_dispute' && n.ids.includes(C) && n.data.side === 'customer'), 'customer notified of the team reply');
// قائمة الإدارة والصلاحيات
await call('GET', '/adminapi/biz/disputes', { user: O, expect: 403 });
const list = await call('GET', '/adminapi/biz/disputes', { user: ADMIN, expect: 200 });
const row = list.find((x) => x.id === w5.id);
check(row && row.dispute.reason === 'المنتج وصل مكسوراً' && row.customer?.id === C && row.owner?.id === O && row.funds === 'held', 'admin list shows the open dispute with both parties');
await call('POST', `/adminapi/biz/disputes/${w5.id}`, { body: { resolution: 'refund' }, user: O, expect: 403 });
await call('POST', `/adminapi/biz/disputes/${w5.id}`, { body: { resolution: 'keep' }, user: ADMIN, expect: 400 });
// الحسم: تقسيم على مبلغ محجوز
ob = await bal(O); cb = await bal(C);
const rs = await call('POST', `/adminapi/biz/disputes/${w5.id}`, { body: { resolution: 'split', note: 'بالتراضي' }, user: ADMIN, expect: 200 });
check(rs.order.funds === 'split' && rs.order.dispute.status === 'resolved' && rs.order.dispute.resolution === 'split' && await bal(C) === cb + 1000 && await bal(O) === ob + 1000, 'split: half to the customer, half to the owner from held');
check((await call('POST', `/adminapi/biz/disputes/${w5.id}`, { body: { resolution: 'refund' }, user: ADMIN, expect: 409 })).error === 'bad-status', 'resolving twice is 409 with no ledger move');
check(sent.some((n) => n.kind === 'biz_dispute' && n.title === 'حُسم النزاع' && n.ids.includes(C)) && sent.some((n) => n.kind === 'biz_dispute' && n.title === 'حُسم النزاع' && n.ids.includes(O)), 'both sides notified of the resolution');
// الحسم بالاسترداد على طلب محجوز لم يُستخدم: يُلغى ويعود مخزونه بلا خصم من صاحب الدائرة
const w6 = await call('POST', `/biz/${B}/orders`, { body: { itemId: comb.id, qty: 3 }, user: C, expect: 200 });
await call('POST', `/biz/orders/${w6.id}/dispute`, { body: { reason: 'تأخر التجهيز كثيراً' }, user: C, expect: 200 });
const stock6 = (await pool.query('SELECT stock FROM biz_items WHERE id=$1', [comb.id])).rows[0].stock;
ob = await bal(O); cb = await bal(C);
const rf = await call('POST', `/adminapi/biz/disputes/${w6.id}`, { body: { resolution: 'refund' }, user: ADMIN, expect: 200 });
const stock6b = (await pool.query('SELECT stock FROM biz_items WHERE id=$1', [comb.id])).rows[0].stock;
check(rf.order.status === 'cancelled' && rf.order.funds === 'refunded' && await bal(C) === cb + 6000 && await bal(O) === ob && stock6b === stock6 + 3, 'refund while held: buyer refunded, owner untouched, stock back');
// الحسم بالتحرير
const w7 = await call('POST', `/biz/${B}/orders`, { body: { itemId: comb.id }, user: C, expect: 200 });
await call('POST', `/biz/orders/${w7.id}/dispute`, { body: { reason: 'لون مختلف عن الصورة' }, user: C, expect: 200 });
ob = await bal(O);
const rl = await call('POST', `/adminapi/biz/disputes/${w7.id}`, { body: { resolution: 'release' }, user: ADMIN, expect: 200 });
check(rl.order.funds === 'released' && await bal(O) === ob + 2000, 'release credits the owner');
// المهلة: سبعة أيام بعد الاستخدام، والاسترداد بعد التحرير يخصم من صاحب الدائرة
const w8 = await call('POST', `/biz/${B}/orders`, { body: { itemId: comb.id }, user: C, expect: 200 });
await call('POST', `/biz/${B}/checkin`, { body: { orderId: w8.id }, expect: 200 });
await pool.query("UPDATE biz_orders SET used_at=now() - interval '8 days', released_at=now() - interval '8 days' WHERE id=$1", [w8.id]);
check((await call('POST', `/biz/orders/${w8.id}/dispute`, { body: { reason: 'اكتشفت عيباً متأخراً' }, user: C, expect: 409 })).error === 'not-disputable', 'no dispute 8 days after use');
await pool.query("UPDATE biz_orders SET used_at=now() - interval '2 days', released_at=now() - interval '2 days' WHERE id=$1", [w8.id]);
check((await call('GET', `/biz/orders/${w8.id}`, { user: C })).disputable === true, 'disputable within 7 days after use');
await call('POST', `/biz/orders/${w8.id}/dispute`, { body: { reason: 'اكتشفت عيباً في المنتج' }, user: C, expect: 200 });
ob = await bal(O); cb = await bal(C);
const rr = await call('POST', `/adminapi/biz/disputes/${w8.id}`, { body: { resolution: 'refund' }, user: ADMIN, expect: 200 });
check(rr.order.status === 'used' && rr.order.funds === 'refunded' && await bal(C) === cb + 2000 && await bal(O) === ob - 2000, 'refund after release debits the owner (biz_refund_out)');
// طلب قديم مستخدم خلال 7 أيام: نزاع وتقسيم يخصم نصف المبلغ من صاحب الدائرة
const L3 = await call('POST', `/biz/${B}/orders`, { body: { itemId: comb.id }, user: C, expect: 200 });
await pool.query("UPDATE biz_orders SET funds=NULL, release_at=NULL, status='used', used_at=NULL, updated_at=now() - interval '1 day' WHERE id=$1", [L3.id]);
await call('POST', `/biz/orders/${L3.id}/dispute`, { body: { reason: 'الخدمة لم تكتمل' }, user: C, expect: 200 });
ob = await bal(O); cb = await bal(C);
await call('POST', `/adminapi/biz/disputes/${L3.id}`, { body: { resolution: 'split' }, user: ADMIN, expect: 200 });
check(await bal(C) === cb + 1000 && await bal(O) === ob - 1000, 'legacy split: half back to the buyer from the owner');
// إلغاء الدائرة أثناء نزاع مفتوح يحسمه لصالح العميل
const w9 = await call('POST', `/biz/${B}/orders`, { body: { itemId: comb.id }, user: C, expect: 200 });
await call('POST', `/biz/orders/${w9.id}/dispute`, { body: { reason: 'لم يجهز الطلب' }, user: C, expect: 200 });
ob = await bal(O); cb = await bal(C);
await call('POST', `/biz/${B}/orders/${w9.id}/cancel`, { expect: 200 });
const w9s = await call('GET', `/biz/orders/${w9.id}`, { user: C, expect: 200 });
check(w9s.status === 'cancelled' && w9s.dispute.status === 'resolved' && w9s.dispute.resolution === 'refund' && await bal(C) === cb + 2000 && await bal(O) === ob, 'owner cancel during a dispute refunds and closes it');
// الطلب المجاني والطلب لشخص آخر
const fr = await call('POST', `/biz/${B}/orders`, { body: { itemId: free.id }, user: C, expect: 200 });
check(fr.payment === 'free' && fr.disputable === false && fr.funds === null, 'free order: no funds, not disputable');
await call('GET', `/biz/orders/${fr.id}`, { user: X, expect: 404 });
check((await call('GET', `/biz/orders/${fr.id}`, { user: ADMIN, expect: 200 })).viewer === 'admin', 'admin can open any order');
check((await call('GET', `/biz/${B}/orders?status=disputed`, { user: STAFF, expect: 200 })).length === 0, 'disputed filter empty once all are resolved');

await pool.query("DELETE FROM biz_disputes WHERE biz_id LIKE 'bo-%'");
await app.close(); await pool.end();
console.log(fails ? `\n${fails} FAILED` : '\nALL BIZ ORDERS TESTS PASSED');
process.exit(fails ? 1 : 0);
