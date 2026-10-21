// سلامة المال (أكتوبر 2026) في commerce.js وbusiness.js على Postgres المحلي عبر fastify.inject:
// إعادة محاولة المعاملة عند تعارض الأقفال، تحويلات متعاكسة متوازية بلا 500، إلغاء فعالية بعد إنفاق إيرادها (402 بلا تغيير)،
// استرداد مرة واحدة فقط (إلغاءان متوازيان، إلغاء بعد الاكتمال، حسم نزاع مرتين، إلغاء مع نزاع أو تسليم في اللحظة نفسها)،
// لا بيع زائد للمخزون أو الموعد عند طلبين متوازيين، قفل رمز التسليم بعد خمس محاولات (متتابعة أو دفعة متوازية)،
// دائرة بلا مالك ترفض الطلب المدفوع وتقبل المجاني، والشحن التجريبي بنوعه وإغلاقه في الوضع الحي.
import Fastify from 'fastify';
import pg from 'pg';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NODE_ENV = 'test'; process.env.NASLIFE_HEALTH_BRIDGE = '0';
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
const A = 'SA0000501', B = 'SA0000502', HOST = 'SA0000503', SELLER = 'SA0000504', BUYER = 'SA0000505', BUYER2 = 'SA0000506', ADMIN = 'SA0000507';
const IDS = [A, B, HOST, SELLER, BUYER, BUYER2, ADMIN];
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("INSERT INTO users(id,nickname) VALUES($1,'ms-a'),($2,'ms-b'),($3,'ms-host'),($4,'ms-seller'),($5,'ms-buyer'),($6,'ms-buyer2'),($7,'ms-admin') ON CONFLICT (id) DO UPDATE SET nickname=EXCLUDED.nickname", IDS);
await pool.query("UPDATE users SET is_admin=true WHERE id=$1", [ADMIN]);
for (const sql of ['DELETE FROM wallet_tx WHERE user_id = ANY($1)', 'DELETE FROM wallet_accounts WHERE user_id = ANY($1)', 'DELETE FROM tickets WHERE user_id = ANY($1)',
  'DELETE FROM ticket_tiers WHERE event_id IN (SELECT id FROM events WHERE host_id = ANY($1))', 'DELETE FROM events WHERE host_id = ANY($1)',
  'DELETE FROM market_orders WHERE seller_id = ANY($1)', 'DELETE FROM market_listings WHERE seller_id = ANY($1)',
  'DELETE FROM biz_orders WHERE user_id = ANY($1)', 'DELETE FROM biz_orders WHERE biz_id LIKE $1', 'DELETE FROM biz_items WHERE biz_id LIKE $1', 'DELETE FROM biz WHERE id LIKE $1']) {
  // كل جملة بمعاملها الوحيد: معامل غير مستخدم يفشل في Postgres بصمت هنا فيبقى biz-ms-cafe ويسقط التشغيل الثاني
  try { await pool.query(sql, sql.includes('LIKE') ? ['biz-ms-%'] : [IDS]); } catch { /* أول تشغيل: الجداول تُنشأ عند التسجيل */ }
}
const notes = []; globalThis.naslifeNotify = async (ids, p) => { notes.push({ ids: [].concat(ids), ...p }); }; globalThis.naslifeNotifyAdmins = async () => {};
globalThis.naslifeSettings = { maxTopup: 2000000, marketCommissionPct: 0 };
delete globalThis.naslifePayMode;
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
app.register((await import('../commerce.js')).default, { pool, auth });
app.register((await import('../business.js')).default, { pool, auth });
await app.ready();
let fails = 0;
const check = (ok, m, extra = '') => { if (!ok) fails++; console.log((ok ? 'OK  ' : 'FAIL') + ' ' + m + (extra ? ' ' + extra : '')); };
const inject = (method, url, { body, user } = {}) => app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json' }, payload: method === 'GET' ? undefined : JSON.stringify(body ?? {}) });
const call = async (method, url, { body, user = BUYER, expect } = {}) => {
  const r = await inject(method, url, { body, user });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url.slice(0, 60)} [${user}] -> ${r.statusCode}`, r.statusCode === expect ? '' : JSON.stringify(j).slice(0, 160));
  return j;
};
const bal = async (u) => (await call('GET', '/wallet', { user: u, expect: 200 })).balance;
const txCount = async (ref, kind) => (await pool.query('SELECT count(*)::int AS n FROM wallet_tx WHERE ref=$1 AND kind=$2', [ref, kind])).rows[0].n;
const statuses = (rs) => rs.map((r) => r.statusCode).sort().join(',');
const topup = (u, amount) => call('POST', '/wallet/topup', { body: { amount }, user: u, expect: 200 });

// ---------- 7. الشحن التجريبي: نوعه test_topup، سقفه في /wallet، ويُغلق في الوضع الحي، ومسار الإدارة القديم أُزيل
await topup(A, 100000);
const wA = await call('GET', '/wallet', { user: A, expect: 200 });
check(wA.recent[0]?.kind === 'test_topup' && wA.recent[0].note === 'شحن تجريبي' && wA.balance === 100000, 'test top-up is recorded as test_topup with its note', JSON.stringify(wA.recent[0]));
check(wA.maxTopup === 2000000 && wA.testTopup === true, '/wallet exposes maxTopup from platform settings', String(wA.maxTopup));
globalThis.naslifePayMode = () => 'live';
check((await call('POST', '/wallet/topup', { body: { amount: 1000 }, user: ADMIN, expect: 403 })).error === 'topup-disabled-live', 'live gateway keys close the test top-up for everyone (even admins)');
globalThis.naslifePayMode = () => 'test';
await topup(B, 100000);
delete globalThis.naslifePayMode;
await call('POST', '/admin/wallet/credit', { body: { userId: A, amount: 1000 }, user: ADMIN, expect: 404 });

// ---------- 1. tx() يعيد المحاولة عند 40P01/40001، والتحويلات المتعاكسة المتوازية لا تتعارض
const W = globalThis.naslifeWallet;
let tries = 0;
const out = await W.tx(async () => { tries++; if (tries < 3) throw Object.assign(new Error('deadlock'), { code: '40P01' }); return 'done'; });
check(out === 'done' && tries === 3, 'tx retries a deadlock twice then succeeds', String(tries));
tries = 0;
await W.tx(async () => { tries++; throw Object.assign(new Error('serialize'), { code: '40001' }); }).then(() => check(false, 'tx must give up after 3 attempts'), (e) => check(e.code === '40001' && tries === 3, 'tx gives up after the third serialization failure', String(tries)));
tries = 0;
await W.tx(async () => { tries++; throw Object.assign(new Error('x'), { code: 'insufficient-funds' }); }).catch((e) => check(e.code === 'insufficient-funds' && tries === 1, 'tx does not retry application errors'));
const sumBefore = (await bal(A)) + (await bal(B));
const rs = await Promise.all(Array.from({ length: 20 }, (_, i) => inject('POST', '/wallet/transfer', { body: { to: i % 2 ? A : B, amount: 100 + i, note: 'ping' }, user: i % 2 ? B : A })));
check(rs.every((r) => r.statusCode === 200), '20 parallel opposite transfers all return 200 (no deadlock, no 500)', statuses(rs));
const sumAfter = (await bal(A)) + (await bal(B));
check(sumAfter === sumBefore, 'sum of the two balances is unchanged after the parallel transfers', `${sumBefore} -> ${sumAfter}`);
check((await pool.query("SELECT count(*)::int AS n FROM wallet_tx WHERE kind='transfer_out' AND user_id = ANY($1)", [[A, B]])).rows[0].n === 20, 'exactly 20 transfer_out rows');

// ---------- 2. إلغاء الفعالية: المضيف الذي أنفق الإيراد يُرفض بـ402 ولا يتغير شيء، وبعد الشحن يُلغى ويُسترد
const ev = await call('POST', '/events', { body: { title: 'أمسية شعرية', startsAt: new Date(Date.now() + 3 * 86400000).toISOString(), placeName: 'الكورنيش', tiers: [{ name: 'عادي', price: 5000, quantity: 10 }] }, user: HOST, expect: 200 });
await topup(BUYER, 500000);
const tk = await call('POST', `/events/${ev.id}/tickets`, { body: { tierId: ev.tiers[0].id, qty: 2 }, user: BUYER, expect: 200 });
check(tk.length === 2 && (await bal(HOST)) === 10000, 'host received 100 SAR for two tickets');
await call('POST', '/wallet/transfer', { body: { to: A, amount: 8000 }, user: HOST, expect: 200 }); // المضيف أنفق الإيراد
const buyerBefore = await bal(BUYER);
const rc = await call('POST', `/events/${ev.id}/cancel`, { user: HOST, expect: 402 });
check(rc.error === 'insufficient-funds' && rc.need === 8000 && rc.have === 2000, 'cancel with spent revenue returns 402 with need/have', JSON.stringify(rc));
const evAfter = await call('GET', `/events/${ev.id}`, { user: HOST, expect: 200 });
const tkAfter = (await call('GET', '/tickets', { user: BUYER, expect: 200 })).filter((t) => t.eventId === ev.id);
check(evAfter.cancelled === false && tkAfter.every((t) => t.status === 'valid') && (await bal(BUYER)) === buyerBefore && (await bal(HOST)) === 2000, 'event not cancelled, tickets still valid, no money moved');
check((await txCount(ev.id, 'refund')) === 0, 'no refund rows written by the refused cancel');
await topup(HOST, 8000);
await call('POST', `/events/${ev.id}/cancel`, { user: HOST, expect: 200 });
check((await call('GET', `/events/${ev.id}`, { user: HOST, expect: 200 })).cancelled === true && (await bal(BUYER)) === buyerBefore + 10000 && (await bal(HOST)) === 0, 'after top-up the cancel refunds the buyer and empties the host');
check((await txCount(ev.id, 'refund')) === 2 && (await txCount(ev.id, 'refund_out')) === 2, 'one refund row per ticket');

// ---------- 3. الاسترداد مرة واحدة: إلغاءان متوازيان، إلغاء بعد الاكتمال، تأكيد وإلغاء متوازيان، حسم نزاع مرتين
const L = await call('POST', '/market', { body: { title: 'كيك', price: 1000, category: 'food', kind: 'product', stock: 50 }, user: SELLER, expect: 200 });
const O1 = await call('POST', `/market/${L.id}/order`, { body: { qty: 1 }, user: BUYER, expect: 200 });
const c2 = await Promise.all([inject('POST', `/market/orders/${O1.id}/cancel`, { user: BUYER }), inject('POST', `/market/orders/${O1.id}/cancel`, { user: BUYER })]);
check(statuses(c2) === '200,409' && c2.find((r) => r.statusCode === 409).json().error === 'bad-status', 'two parallel cancels: exactly one 200 and one 409 bad-status', statuses(c2));
check((await txCount(O1.id, 'refund')) === 1, 'exactly one refund row for the doubly cancelled order');
const O2 = await call('POST', `/market/${L.id}/order`, { body: { qty: 1 }, user: BUYER, expect: 200 });
await call('POST', `/market/orders/${O2.id}/confirm`, { user: BUYER, expect: 200 });
const sellerAfterSale = await bal(SELLER);
check((await call('POST', `/market/orders/${O2.id}/cancel`, { user: SELLER, expect: 409 })).error === 'bad-status', 'cancel after completion is refused');
check((await txCount(O2.id, 'refund')) === 0 && (await bal(SELLER)) === sellerAfterSale, 'no refund row and the seller keeps the sale');
const O3 = await call('POST', `/market/${L.id}/order`, { body: { qty: 1 }, user: BUYER, expect: 200 });
const race = await Promise.all([inject('POST', `/market/orders/${O3.id}/confirm`, { user: BUYER }), inject('POST', `/market/orders/${O3.id}/cancel`, { user: SELLER })]);
check(statuses(race) === '200,409', 'parallel buyer confirm and seller cancel: only one wins', statuses(race));
check(((await txCount(O3.id, 'refund')) + (await txCount(O3.id, 'market_sale'))) === 1, 'the order either refunded or paid out, never both');
const O4 = await call('POST', `/market/${L.id}/order`, { body: { qty: 1 }, user: BUYER, expect: 200 });
await call('POST', `/market/orders/${O4.id}/dispute`, { body: { reason: 'لم يصل الطلب أبداً' }, user: BUYER, expect: 200 });
const d2 = await Promise.all([inject('POST', `/adminapi/market/disputes/${O4.id}`, { body: { resolution: 'refund' }, user: ADMIN }), inject('POST', `/adminapi/market/disputes/${O4.id}`, { body: { resolution: 'refund' }, user: ADMIN })]);
check(statuses(d2) === '200,409', 'two parallel dispute refunds: one 200 and one 409', statuses(d2));
check((await call('POST', `/adminapi/market/disputes/${O4.id}`, { body: { resolution: 'refund' }, user: ADMIN, expect: 409 })).error === 'bad-status', 'a later dispute refund is 409 bad-status');
check((await txCount(O4.id, 'refund')) === 1, 'exactly one refund row for the disputed order');
const O5 = await call('POST', `/market/${L.id}/order`, { body: { qty: 1 }, user: BUYER, expect: 200 });
await call('POST', `/market/orders/${O5.id}/dispute`, { body: { reason: 'وصل ناقصاً جداً' }, user: BUYER, expect: 200 });
const d3 = await Promise.all([inject('POST', `/adminapi/market/disputes/${O5.id}`, { body: { resolution: 'release' }, user: ADMIN }), inject('POST', `/adminapi/market/disputes/${O5.id}`, { body: { resolution: 'split' }, user: ADMIN })]);
check(statuses(d3) === '200,409' && ((await txCount(O5.id, 'market_sale')) + (await txCount(O5.id, 'refund'))) <= 2 && (await pool.query("SELECT count(*)::int AS n FROM wallet_tx WHERE ref=$1 AND kind='market_sale'", [O5.id])).rows[0].n === 1, 'parallel release/split: one resolution applied, one seller payout', statuses(d3));
// الأبواب الجانبية للاسترداد: نزاع أو مرحلة تُكتب فوق إلغاء سبق كانت تعيد الطلب إلى حالة يُدفع منها للبائع بعد استرداد المشتري
const orderRow = async (id) => (await pool.query('SELECT status, code_fails FROM market_orders WHERE id=$1', [id])).rows[0];
// سباق مضمون: نمسك قفل صف الطلب حتى يجتاز الطلبان فحصهما المسبق (قراءة بلا قفل) ثم نحرّره فتتصادم الكتابتان فعلاً
const raced = async (orderId, reqs) => {
  const c = await pool.connect(); await c.query('BEGIN'); await c.query('SELECT 1 FROM market_orders WHERE id=$1 FOR UPDATE', [orderId]);
  const p = Promise.all(reqs.map((f) => f())); await new Promise((r) => setTimeout(r, 200)); await c.query('COMMIT'); c.release(); return p;
};
const sellerBefore8 = await bal(SELLER);
const O8 = await call('POST', `/market/${L.id}/order`, { body: { qty: 1 }, user: BUYER, expect: 200 });
const cd = await raced(O8.id, [() => inject('POST', `/market/orders/${O8.id}/cancel`, { user: SELLER }), () => inject('POST', `/market/orders/${O8.id}/dispute`, { body: { reason: 'لم يصل الطلب أبداً' }, user: BUYER })]);
check(cd[0].statusCode === 200 && [200, 409].includes(cd[1].statusCode) && (await orderRow(O8.id)).status === 'cancelled', 'parallel seller cancel and buyer dispute: the order never ends disputed once refunded', statuses(cd) + ' ' + (await orderRow(O8.id)).status);
check((await call('POST', `/adminapi/market/disputes/${O8.id}`, { body: { resolution: 'release' }, user: ADMIN, expect: 409 })).error === 'bad-status', 'admin release on the cancelled order is 409');
check((await txCount(O8.id, 'refund')) === 1 && (await txCount(O8.id, 'market_sale')) === 0 && (await bal(SELLER)) === sellerBefore8, 'exactly one refund row, no payout, seller balance unchanged');
check((await call('POST', `/market/orders/${O8.id}/dispute`, { body: { reason: 'لم يصل الطلب أبداً' }, user: BUYER, expect: 409 })).error === 'bad-status', 'dispute after cancel is 409 bad-status');
const O9 = await call('POST', `/market/${L.id}/order`, { body: { qty: 1 }, user: BUYER, expect: 200 });
const cs = await raced(O9.id, [() => inject('POST', `/market/orders/${O9.id}/cancel`, { user: SELLER }), () => inject('POST', `/market/orders/${O9.id}/stage`, { body: { stage: 'delivered' }, user: SELLER })]);
check(cs[0].statusCode === 200 && [200, 409].includes(cs[1].statusCode) && (await orderRow(O9.id)).status === 'cancelled', 'parallel seller cancel and seller deliver: the order never ends delivered once refunded', statuses(cs) + ' ' + (await orderRow(O9.id)).status);
check((await call('POST', `/market/orders/${O9.id}/confirm`, { user: BUYER, expect: 409 })).error === 'bad-status', 'buyer confirm after the refund is 409');
await pool.query("UPDATE market_orders SET delivered_at=now() - interval '80 hours' WHERE id=$1", [O9.id]); await globalThis.naslifeMarketSweep();
check((await txCount(O9.id, 'refund')) === 1 && (await txCount(O9.id, 'market_sale')) === 0 && (await orderRow(O9.id)).status === 'cancelled', 'neither buyer confirm nor the 72h sweep pays the seller after the refund');
check((await call('POST', `/market/orders/${O9.id}/stage`, { body: { stage: 'preparing' }, user: SELLER, expect: 409 })).error === 'bad-status', 'stage after cancel is 409 bad-status');
const O10 = await call('POST', `/market/${L.id}/order`, { body: { qty: 1 }, user: BUYER, expect: 200 });
const st2 = await raced(O10.id, [() => inject('POST', `/market/orders/${O10.id}/stage`, { body: { stage: 'delivered' }, user: SELLER }), () => inject('POST', `/market/orders/${O10.id}/stage`, { body: { stage: 'preparing' }, user: SELLER })]);
// إن تصادمت الكتابتان: 200 و409؛ وإن تتابعتا بترتيب ما: لا رجوع للخلف أبداً («تم التسليم» الناجح لا يُكتب فوقه «قيد التحضير»)
check(st2.some((r) => r.statusCode === 200) && st2.every((r) => [200, 409].includes(r.statusCode)) && (await orderRow(O10.id)).status === (st2[0].statusCode === 200 ? 'delivered' : 'preparing'), 'two parallel stage moves from the same state: one applies and the order never moves backward', statuses(st2) + ' ' + (await orderRow(O10.id)).status);

// ---------- 4. لا بيع زائد: مخزون واحد وطلبان متوازيان، وموعد واحد وطلبان متوازيان
await topup(BUYER2, 100000);
const L1 = await call('POST', '/market', { body: { title: 'ساعة', price: 500, category: 'electronics', kind: 'product', stock: 1 }, user: SELLER, expect: 200 });
const os = await Promise.all([inject('POST', `/market/${L1.id}/order`, { body: { qty: 1 }, user: BUYER }), inject('POST', `/market/${L1.id}/order`, { body: { qty: 1 }, user: BUYER2 })]);
check(statuses(os) === '200,409' && os.find((r) => r.statusCode === 409).json().error === 'out-of-stock', 'stock 1 with two parallel orders: one 200, one 409 out-of-stock', statuses(os));
const l1 = await call('GET', `/market/${L1.id}`, { user: BUYER, expect: 200 });
check(l1.sold === 1 && l1.stock === 0, 'listing sold == 1 and stock == 0', JSON.stringify({ sold: l1.sold, stock: l1.stock }));
check((await pool.query("SELECT count(*)::int AS n FROM wallet_tx WHERE kind='market' AND note='ساعة'")).rows[0].n === 1, 'only one buyer was debited');
const slot = new Date(); slot.setUTCDate(slot.getUTCDate() + 1); slot.setUTCHours(9, 0, 0, 0); // 12:00 بتوقيت السعودية غداً
const L2 = await call('POST', '/market', { body: { title: 'درس', price: 700, category: 'services', kind: 'service', availability: { days: [0, 1, 2, 3, 4, 5, 6], from: '00:00', to: '23:59', slotMinutes: 60 } }, user: SELLER, expect: 200 });
const ss = await Promise.all([inject('POST', `/market/${L2.id}/order`, { body: { qty: 1, slot: slot.toISOString() }, user: BUYER }), inject('POST', `/market/${L2.id}/order`, { body: { qty: 1, slot: slot.toISOString() }, user: BUYER2 })]);
check(statuses(ss) === '200,409' && ss.find((r) => r.statusCode === 409).json().error === 'slot-taken', 'one slot with two parallel orders: one 200, one 409 slot-taken', statuses(ss));
// رموز الخطأ القديمة لم تتغير
check((await call('POST', `/market/${L1.id}/order`, { body: { qty: 1 }, user: SELLER, expect: 400 })).error === 'own-listing', 'own-listing still 400');
check((await call('POST', `/market/${L2.id}/order`, { body: { qty: 1 }, user: BUYER, expect: 400 })).error === 'slot-required', 'slot-required still 400');
check((await call('POST', `/market/${L.id}/order`, { body: { qty: 1, coupon: 'NOPE' }, user: BUYER, expect: 400 })).error === 'bad-coupon', 'bad-coupon still 400');
await call('POST', `/market/00000000-0000-4000-8000-000000000000/order`, { body: { qty: 1 }, user: BUYER, expect: 404 });

// ---------- 5. قفل رمز التسليم بعد خمس محاولات خاطئة؛ المشتري يؤكد رغم القفل
const O6 = await call('POST', `/market/${L.id}/order`, { body: { qty: 1 }, user: BUYER, expect: 200 });
const lefts = [];
for (let i = 0; i < 5; i++) { const r = await call('POST', `/market/orders/${O6.id}/confirm`, { body: { code: '0000' }, user: SELLER, expect: 400 }); lefts.push(r.left); }
check(lefts.join(',') === '4,3,2,1,0', 'each wrong code reports how many attempts are left', lefts.join(','));
check((await call('POST', `/market/orders/${O6.id}/confirm`, { body: { code: O6.code }, user: SELLER, expect: 429 })).error === 'code-locked', 'sixth attempt with the right code is 429 code-locked');
check((await call('GET', `/market/orders/${O6.id}`, { user: SELLER, expect: 200 })).codeLocked === true, 'seller view shows codeLocked');
await call('POST', `/market/orders/${O6.id}/confirm`, { user: BUYER, expect: 200 });
check((await call('GET', `/market/orders/${O6.id}`, { user: BUYER, expect: 200 })).status === 'completed', 'buyer can still confirm a code-locked order');
const O7 = await call('POST', `/market/${L.id}/order`, { body: { qty: 1 }, user: BUYER, expect: 200 });
await call('POST', `/market/orders/${O7.id}/confirm`, { body: { code: '0000' }, user: SELLER, expect: 400 });
check((await call('GET', `/market/orders/${O7.id}`, { user: SELLER, expect: 200 })).codeLocked === false, 'one wrong attempt does not lock');
await call('POST', `/market/orders/${O7.id}/confirm`, { body: { code: O7.code }, user: SELLER, expect: 200 });
// دفعة متوازية: الفحص والزيادة جملة واحدة فلا يتجاوز العدّاد الحد، ولا يمر الرمز الصحيح بعد تسجيل خمس محاولات
const O11 = await call('POST', `/market/${L.id}/order`, { body: { qty: 1 }, user: BUYER, expect: 200 });
const burst = await Promise.all(Array.from({ length: 12 }, () => inject('POST', `/market/orders/${O11.id}/confirm`, { body: { code: '0000' }, user: SELLER })));
const n400 = burst.filter((r) => r.statusCode === 400).length, n429 = burst.filter((r) => r.statusCode === 429).length;
check(n400 === 5 && n429 === 7 && (await orderRow(O11.id)).code_fails === 5, '12 parallel wrong codes: exactly 5 x 400 and 7 x 429, code_fails == 5', `${n400}x400 ${n429}x429 fails=${(await orderRow(O11.id)).code_fails}`);
const burst2 = await Promise.all([...Array.from({ length: 8 }, () => inject('POST', `/market/orders/${O11.id}/confirm`, { body: { code: '0000' }, user: SELLER })), inject('POST', `/market/orders/${O11.id}/confirm`, { body: { code: O11.code }, user: SELLER })]);
check(burst2.every((r) => r.statusCode === 429) && (await orderRow(O11.id)).status === 'paid', 'locked order: a parallel burst including the right code is all 429 and the order stays paid', statuses(burst2));
const O12 = await call('POST', `/market/${L.id}/order`, { body: { qty: 1 }, user: BUYER, expect: 200 });
const mixed = await Promise.all([...Array.from({ length: 29 }, () => inject('POST', `/market/orders/${O12.id}/confirm`, { body: { code: '0000' }, user: SELLER })), inject('POST', `/market/orders/${O12.id}/confirm`, { body: { code: O12.code }, user: SELLER })]);
const right = mixed[29], row12 = await orderRow(O12.id), wrong400 = mixed.slice(0, 29).filter((r) => r.statusCode === 400).length;
check(row12.code_fails <= 5 && wrong400 === row12.code_fails && mixed.slice(0, 29).every((r) => [400, 429, 409].includes(r.statusCode)), '29 wrong + 1 right in one burst: the counter never passes 5 and every wrong code is counted or refused', `fails=${row12.code_fails} 400s=${wrong400}`);
check((right.statusCode === 200) === (row12.status === 'completed' && row12.code_fails < 5) && (right.statusCode === 200 || (right.statusCode === 429 && row12.code_fails === 5 && row12.status === 'paid')), 'the right code completes only while fewer than 5 failures are recorded, otherwise 429', `right=${right.statusCode} status=${row12.status} fails=${row12.code_fails}`);
check((await txCount(O12.id, 'market_sale')) === (row12.status === 'completed' ? 1 : 0), 'the seller is paid at most once and only on completion');

// ---------- 6. دائرة بلا مالك: الصنف المدفوع 409 no-owner بلا خصم، والمجاني يُطلب
const biz = await call('POST', '/biz', { body: { name: 'MS Cafe', nameAr: 'مقهى سلامة', category: 'cafe', lat: 21.54, lng: 39.17, address: 'الروضة' }, user: HOST, expect: 200 });
await pool.query("UPDATE biz SET id='biz-ms-cafe' WHERE id=$1", [biz.id]);
const paid = await call('POST', '/biz/biz-ms-cafe/items', { body: { title: 'كورتادو', price: 1400, stock: 10 }, user: HOST, expect: 200 });
const free = await call('POST', '/biz/biz-ms-cafe/items', { body: { title: 'ماء', price: 0, stock: 10 }, user: HOST, expect: 200 });
await pool.query("UPDATE biz SET owner_id=NULL WHERE id='biz-ms-cafe'");
const before6 = await bal(BUYER);
check((await call('POST', '/biz/biz-ms-cafe/orders', { body: { itemId: paid.id, qty: 1 }, user: BUYER, expect: 409 })).error === 'no-owner', 'priced item on an ownerless circle is 409 no-owner');
check((await bal(BUYER)) === before6 && (await pool.query("SELECT count(*)::int AS n FROM biz_orders WHERE biz_id='biz-ms-cafe'")).rows[0].n === 0, 'nothing debited and no order row');
check((await call('POST', '/biz/biz-ms-cafe/orders', { body: { itemId: free.id, qty: 1 }, user: BUYER, expect: 200 })).total === 0, 'free item on an ownerless circle is still orderable');

console.log(fails ? `\n${fails} FAILED` : '\nALL OK');
await app.close(); await pool.end();
