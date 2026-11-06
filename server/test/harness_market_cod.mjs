// الدفع عند الاستلام في سوق المستخدمين (بند 10 من نواقص الإطلاق، 6 نوفمبر 2026) على Postgres المحلي:
// علم العرض وشرط التوصيل أو مكان الاستلام، الطلب بلا مال وبحجز المخزون، قبول البائع أو اعتذاره، المراحل، «استلمت المبلغ» ورمز المشتري
// وتأكيده، الإلغاء وإرجاع المخزون والكوبون، لا نزاع، حد ٣ طلبات مفتوحة (ومتوازية)، «لم يحضر» وإيقافه بعد ٣، مهلة القبول ٤٨ ساعة،
// الاكتمال التلقائي، قواعد الطلب المدفوع (18+، الحظر، الإيقاف، الكلمات الممنوعة)، عميل iOS، الفاتورة ولوحة البائع والإشعارات.
// وبعد المراجعة: «لم يحضر» لا يُسجَّل قبل أن يحين التسليم ويُعدّ ببائعين مختلفين خلال ٩٠ يوماً وتمسحه الإدارة، ونصه بلا المحفظة؛
// «من يراسلني» لا يُفتح بطلب لم يُقبل؛ والشارات لا تُصنع بطلبات بين حسابين ولا تُهدم بطلبات منافس ملغاة.
import Fastify from 'fastify';
import pg from 'pg';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NODE_ENV = 'test';
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
const SELLER = 'SA0000702', BUYER = 'SA0000703', BUYER2 = 'SA0000704', OTHER = 'SA0000705', RIDER = 'SA0000706', MINOR = 'SA0000707', PLATFORM = 'SA0000000';
// بائعان آخران لعدّ «لم يحضر» ببائعين مختلفين، ومشترٍ جديد لـ«من يراسلني»، ومدير، وبائع ومشترٍ يتبادلان طلبات بلا مال، ومنافس
const SELLER2 = 'SA0000708', SELLER3 = 'SA0000709', BUYER3 = 'SA0000710', ADMIN = 'SA0000711', FSELL = 'SA0000712', FBUY = 'SA0000713', COMP = 'SA0000714';
const OURS = [SELLER, BUYER, BUYER2, OTHER, RIDER, MINOR, PLATFORM, SELLER2, SELLER3, BUYER3, ADMIN, FSELL, FBUY, COMP];
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query(`INSERT INTO users(id,nickname,created_at) VALUES('${SELLER}','codseller',now()-interval '30 days'),('${BUYER}','codbuyer',now()-interval '30 days'),('${BUYER2}','codbuyer2',now()-interval '30 days'),
  ('${OTHER}','codother',now()-interval '30 days'),('${RIDER}','codrider',now()-interval '30 days'),('${MINOR}','codminor',now()-interval '30 days'),('${PLATFORM}','naslife',now()-interval '60 days'),
  ('${SELLER2}','codseller2',now()-interval '30 days'),('${SELLER3}','codseller3',now()-interval '30 days'),('${BUYER3}','codbuyer3',now()-interval '30 days'),('${ADMIN}','codadmin',now()-interval '30 days'),
  ('${FSELL}','codfarmer',now()-interval '30 days'),('${FBUY}','codsock',now()-interval '30 days'),('${COMP}','codrival',now()-interval '30 days')
  ON CONFLICT (id) DO UPDATE SET nickname=EXCLUDED.nickname, created_at=EXCLUDED.created_at`);
await pool.query('ALTER TABLE users ADD COLUMN IF NOT EXISTS is_admin BOOLEAN DEFAULT false');
await pool.query('UPDATE users SET is_admin = (id = $1) WHERE id = ANY($2)', [ADMIN, OURS]);
await pool.query("CREATE TABLE IF NOT EXISTS user_flags (user_id TEXT PRIMARY KEY, suspended BOOLEAN NOT NULL DEFAULT false, note TEXT, updated_at TIMESTAMPTZ DEFAULT now())");
await pool.query('DELETE FROM user_flags WHERE user_id = ANY($1)', [OURS]);
// جداول السوق تبدأ نظيفة (الحزم الأخرى تفعل الشيء نفسه)، والمحافظ لمستخدمينا فقط
for (const t of ['market_reviews', 'market_coupons', 'market_seller_stats', 'market_seller_flags', 'market_follows', 'market_questions', 'market_wanted', 'market_wanted_replies', 'market_spotlight', 'market_alerts', 'market_views', 'market_orders', 'market_listings']) await pool.query(`DROP TABLE IF EXISTS ${t}`);
for (const sql of ['DELETE FROM wallet_tx WHERE user_id = ANY($1)', 'DELETE FROM wallet_accounts WHERE user_id = ANY($1)']) { try { await pool.query(sql, [OURS]); } catch { /* أول تشغيل */ } }

const notes = []; globalThis.naslifeNotify = async (ids, p) => { notes.push({ ids: [].concat(ids), ...p }); }; globalThis.naslifeNotifyAdmins = async (p) => { notes.push({ ids: ['admins'], ...p }); };
globalThis.naslifeSettings = { marketCommissionPct: 10, marketBlockContacts: true, maxTopup: 10000000 };
// إقرار 18+ والحظر والكلمات الممنوعة كما تنشرها legal_pages.js وsafety.js
const adults = new Set([SELLER, BUYER, BUYER2, OTHER, SELLER2, SELLER3, BUYER3, FSELL, FBUY, COMP]);
globalThis.naslifeAdultOk = async (u) => adults.has(u);
const blocks = new Set(); globalThis.naslifeBlockedIds = async (u) => [...blocks].filter((p) => p.split(':').includes(u)).map((p) => p.split(':').find((x) => x !== u));
globalThis.naslifeCheckText = (...t) => (t.some((x) => /ممنوعة/.test(String(x ?? ''))) ? 'ممنوعة' : null);
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
app.register((await import('../commerce.js')).default, { pool, auth });
app.register((await import('../market_plus.js')).default, { pool, auth });
app.register((await import('../market_b.js')).default, { pool, auth });
await app.ready();

let fails = 0;
const call = async (method, url, { body, user = BUYER, expect, raw = false, headers = {} } = {}) => {
  const r = await app.inject({ method, url, headers: { 'x-user': user, ...headers, ...(method === 'GET' ? {} : { 'content-type': 'application/json' }) }, payload: method === 'GET' ? undefined : JSON.stringify(body ?? {}) });
  let j; try { j = raw ? r.body : r.json(); } catch { j = r.body; }
  const ok = expect == null || r.statusCode === expect; if (!ok) fails++;
  console.log((ok ? 'OK  ' : 'FAIL') + ' ' + method + ' ' + url.slice(0, 64) + ' -> ' + r.statusCode + (ok ? '' : ' expected ' + expect) + ' ' + (typeof j === 'string' ? j.replace(/\s+/g, ' ').slice(0, 80) : JSON.stringify(j).slice(0, 140)));
  return j;
};
const check = (ok, m) => { if (!ok) fails++; console.log((ok ? 'OK  ' : 'FAIL') + ' ' + m); };
const row = async (id) => (await pool.query('SELECT * FROM market_orders WHERE id=$1', [id])).rows[0];
const stockOf = async (id) => (await pool.query('SELECT stock, sold, variants FROM market_listings WHERE id=$1', [id])).rows[0];
const txCount = async (u) => (await pool.query('SELECT count(*)::int AS n FROM wallet_tx WHERE user_id=$1', [u])).rows[0].n;
const balance = async (u) => Number((await pool.query('SELECT balance FROM wallet_accounts WHERE user_id=$1', [u])).rows[0]?.balance ?? 0);
const lastNote = (kind, to) => [...notes].reverse().find((n) => n.kind === kind && n.ids.includes(to));
const cod = (listingId, body = {}, opts = {}) => call('POST', `/market/${listingId}/order`, { body: { qty: 1, payment: 'cod', ...body }, ...opts });

// ---------- علم العرض ----------
check((await call('POST', '/market', { body: { title: 'كيك بلا مكان', kind: 'product', category: 'food', price: 5000, payOnReceipt: true }, user: SELLER, expect: 400 })).error === 'cod-needs-place', 'pay on receipt needs delivery or a pickup place');
const L1 = await call('POST', '/market', { body: { title: 'كيك عيد ميلاد', kind: 'product', category: 'food', price: 5000, stock: 40, placeName: 'الروضة', payOnReceipt: true }, user: SELLER, expect: 200 });
check(L1.payOnReceipt === true && L1.stock === 40, 'listing allows pay on receipt with a pickup place');
const LD = await call('POST', '/market', { body: { title: 'عسل سدر', kind: 'product', category: 'food', price: 9000, delivery: true, payOnReceipt: true }, user: SELLER, expect: 200 });
check(LD.payOnReceipt === true, 'delivery alone is enough for pay on receipt');
const L2 = await call('POST', '/market', { body: { title: 'قهوة مختصة', kind: 'product', category: 'coffee', price: 4000, placeName: 'جدة' }, user: SELLER, expect: 200 });
check(L2.payOnReceipt === false, 'pay on receipt is off by default');
check((await call('GET', `/market/${L1.id}`, { user: BUYER, expect: 200 })).payOnReceipt === true, 'listing page carries payOnReceipt');
check((await call('PATCH', `/market/${L1.id}`, { body: { placeName: '' }, user: SELLER, expect: 400 })).error === 'cod-needs-place', 'clearing the place of a pay-on-receipt listing is refused');
check((await call('PATCH', `/market/${L2.id}`, { body: { payOnReceipt: true, placeName: '' }, user: SELLER, expect: 400 })).error === 'cod-needs-place', 'turning it on without a place is refused');
check((await call('PATCH', `/market/${L2.id}`, { body: { payOnReceipt: true }, user: SELLER, expect: 200 })).payOnReceipt === true, 'turning it on with the saved place works');
check((await call('PATCH', `/market/${L2.id}`, { body: { payOnReceipt: false }, user: SELLER, expect: 200 })).payOnReceipt === false, 'and off again');
check((await call('PATCH', `/market/${L2.id}`, { body: { title: 'قهوة مختصة إثيوبية' }, user: SELLER, expect: 200 })).payOnReceipt === false, 'an unrelated edit keeps the flag');

// ---------- قواعد الطلب ----------
check((await cod(L2.id, {}, { expect: 400 })).error === 'cod-unavailable', 'a listing without the flag refuses pay on receipt');
check((await cod(L1.id, {}, { user: MINOR, expect: 403 })).error === 'adult-required', '18+ declaration needed for a pay-on-receipt order');
blocks.add(`${BUYER2}:${SELLER}`);
await cod(L1.id, {}, { user: BUYER2, expect: 404 });
blocks.clear();
await pool.query("INSERT INTO user_flags(user_id,suspended) VALUES($1,true) ON CONFLICT (user_id) DO UPDATE SET suspended=true", [OTHER]);
check((await cod(L1.id, {}, { user: OTHER, expect: 403 })).error === 'suspended', 'a suspended buyer cannot order');
await pool.query('UPDATE user_flags SET suspended=false WHERE user_id=$1', [OTHER]);
check((await cod(L1.id, { note: 'كلمة ممنوعة هنا' }, { expect: 400 })).error === 'banned-words', 'banned words in the note are refused');
check((await call('POST', `/market/${L1.id}/order`, { body: { qty: 1 }, expect: 402 })).error === 'insufficient-funds', 'wallet order without balance: insufficient funds');
await call('POST', `/market/${L1.id}/order`, { body: { qty: 1, payment: 'cod' }, user: SELLER, expect: 400 }); // own-listing
const n0 = notes.length;
const O1 = await cod(L1.id, { qty: 2, note: 'بعد المغرب' }, { expect: 200 });
check(O1.payment === 'cod' && O1.status === 'requested' && O1.total === 10000 && O1.commission === 0 && /^\d{4}$/.test(O1.code), 'pay-on-receipt order: requested, full total, no commission, a code');
check(await balance(BUYER) === 0 && await txCount(BUYER) === 0 && await txCount(SELLER) === 0, 'no money moved for a pay-on-receipt order');
check((await stockOf(L1.id)).stock === 38 && (await stockOf(L1.id)).sold === 2, 'stock reserved like a paid order');
const nOrder = notes.slice(n0).find((n) => n.kind === 'market_cod_order');
check(nOrder && nOrder.ids.includes(SELLER) && nOrder.data.orderId === O1.id && nOrder.data.payment === 'cod' && /عند الاستلام/.test(nOrder.title), 'seller notified with market_cod_order');
const g1 = await call('GET', `/market/orders/${O1.id}`, { expect: 200 });
check(g1.payment === 'cod' && g1.status === 'requested' && g1.code === O1.code && g1.commission === null, 'buyer sees payment method, status and code');
const s1 = await call('GET', `/market/orders/${O1.id}`, { user: SELLER, expect: 200 });
check(s1.payment === 'cod' && s1.code == null && s1.commission === 0, 'seller sees the order without the code');
const allow = (a, b) => globalThis.naslifeMessageAllow.get('market-orders')(a, b);
await pool.query("UPDATE market_orders SET updated_at=now() - interval '30 days' WHERE id=$1", [O1.id]);
check(await allow(BUYER, SELLER), 'message allow: a requested order unlocks messaging');
await pool.query('UPDATE market_orders SET updated_at=now() WHERE id=$1', [O1.id]);

// ---------- قبل القبول ----------
await call('POST', `/market/orders/${O1.id}/confirm`, { expect: 409 });
await call('POST', `/market/orders/${O1.id}/stage`, { body: { stage: 'preparing' }, user: SELLER, expect: 409 });
await call('POST', `/market/orders/${O1.id}/courier`, { body: { nickname: 'codrider' }, user: SELLER, expect: 409 });
await call('POST', `/market/orders/${O1.id}/cash-received`, { user: SELLER, expect: 409 });
await call('POST', `/market/orders/${O1.id}/no-show`, { user: SELLER, expect: 409 });
check((await call('POST', `/market/orders/${O1.id}/dispute`, { body: { reason: 'لم يصل الطلب' }, expect: 409 })).error === 'cod-no-dispute', 'no dispute on a pay-on-receipt order');
await call('POST', `/market/orders/${O1.id}/accept`, { user: BUYER, expect: 403 });
check((await call('POST', `/market/${L1.id}/order`, { body: { qty: 1 }, user: OTHER, expect: 402 })) && true, 'wallet orders unaffected by the flag');
const acc = await call('POST', `/market/orders/${O1.id}/accept`, { user: SELLER, expect: 200 });
check(acc.status === 'paid' && (await row(O1.id)).accepted_at != null, 'seller accepted: order confirmed');
check(lastNote('market_cod_accepted', BUYER)?.data?.orderId === O1.id, 'buyer notified with market_cod_accepted');
await call('POST', `/market/orders/${O1.id}/accept`, { user: SELLER, expect: 409 });
await call('POST', `/market/orders/${O1.id}/decline`, { user: SELLER, expect: 409 });

// ---------- المراحل و«استلمت المبلغ» ----------
await call('POST', `/market/orders/${O1.id}/stage`, { body: { stage: 'preparing' }, user: SELLER, expect: 200 });
const withC = await call('POST', `/market/orders/${O1.id}/courier`, { body: { nickname: 'codrider' }, user: SELLER, expect: 200 });
check(withC.courier?.id === RIDER, 'a courier can carry a pay-on-receipt order after acceptance');
await call('POST', `/market/orders/${O1.id}/stage`, { body: { stage: 'on_the_way' }, user: RIDER, expect: 200 });
await call('POST', `/market/orders/${O1.id}/stage`, { body: { stage: 'delivered' }, user: RIDER, expect: 200 });
check(/ادفع/.test(lastNote('market_status', BUYER)?.body ?? ''), 'delivered notice tells the buyer to pay the seller');
await call('POST', `/market/orders/${O1.id}/cash-received`, { user: BUYER, expect: 403 });
await call('POST', `/market/orders/${O1.id}/cash-received`, { user: RIDER, expect: 403 });
const n1 = notes.length;
check((await call('POST', `/market/orders/${O1.id}/cash-received`, { user: SELLER, expect: 200 })).status === 'completed', 'seller marked «استلمت المبلغ»: completed');
const r1 = await row(O1.id);
check(r1.status === 'completed' && r1.cash_received_at != null && r1.completed_at != null, 'cash received time recorded');
check(await txCount(SELLER) === 0 && await txCount(PLATFORM) === 0 && await txCount(BUYER) === 0, 'completion moved no money and took no commission');
check(notes.slice(n1).some((n) => n.kind === 'market_cod_completed' && n.ids.includes(BUYER)) && !notes.slice(n1).some((n) => n.ids.includes(SELLER) && n.kind === 'market_status'), 'buyer notified with market_cod_completed');
await call('POST', `/market/orders/${O1.id}/cash-received`, { user: SELLER, expect: 409 });
await call('POST', `/market/orders/${O1.id}/review`, { body: { rating: 5, text: 'ممتاز' }, expect: 200 });
check((await call('POST', `/market/orders/${O1.id}/dispute`, { body: { reason: 'متأخر جداً' }, expect: 409 })).error === 'cod-no-dispute', 'no dispute after completion either');
const inv = await call('GET', `/market/orders/${O1.id}/invoice`, { raw: true, expect: 200 });
check(/يُدفع للبائع عند الاستلام/.test(inv) && !/الإجمالي المدفوع/.test(inv) && /لم يمر المبلغ بمحفظة/.test(inv), 'invoice states pay on receipt');

// ---------- تأكيد المشتري ورمزه ----------
const O2 = await cod(L1.id, {}, { expect: 200 });
await call('POST', `/market/orders/${O2.id}/accept`, { user: SELLER, expect: 200 });
const n2 = notes.length;
await call('POST', `/market/orders/${O2.id}/confirm`, { expect: 200 });
check((await row(O2.id)).status === 'completed' && (await row(O2.id)).cash_received_at == null, 'buyer confirmed receipt: completed');
check(notes.slice(n2).some((n) => n.kind === 'market_cod_completed' && n.ids.includes(SELLER) && /أكّد المشتري/.test(n.body)), 'seller notified the buyer confirmed');
const O3 = await cod(L1.id, {}, { expect: 200 });
await call('POST', `/market/orders/${O3.id}/accept`, { user: SELLER, expect: 200 });
const code3 = (await row(O3.id)).code;
check((await call('POST', `/market/orders/${O3.id}/confirm`, { body: { code: code3 === '0000' ? '1111' : '0000' }, user: SELLER, expect: 400 })).error === 'bad-code', 'seller with a wrong buyer code');
await call('POST', `/market/orders/${O3.id}/confirm`, { body: { code: code3 }, user: SELLER, expect: 200 });
check((await row(O3.id)).status === 'completed' && (await row(O3.id)).cash_received_at != null, 'seller entered the buyer code: completed with cash received');
check(await txCount(SELLER) === 0 && await txCount(PLATFORM) === 0, 'still no money in the ledger');

// ---------- الإلغاء والمخزون والكوبون ----------
const before4 = (await stockOf(L1.id)).stock;
const O4 = await cod(L1.id, { qty: 3 }, { expect: 200 });
check((await stockOf(L1.id)).stock === before4 - 3, 'stock reserved');
await call('POST', `/market/orders/${O4.id}/cancel`, { expect: 200 });
check((await stockOf(L1.id)).stock === before4 && (await row(O4.id)).cancel_reason === 'buyer' && await txCount(BUYER) === 0, 'buyer cancelled before acceptance: stock back, no wallet entry');
const O5 = await cod(L1.id, {}, { expect: 200 });
check((await call('POST', `/market/orders/${O5.id}/decline`, { body: { reason: 'كلمة ممنوعة' }, user: SELLER, expect: 400 })).error === 'banned-words', 'decline reason checked for banned words');
await call('POST', `/market/orders/${O5.id}/decline`, { user: BUYER, expect: 403 });
await call('POST', `/market/orders/${O5.id}/decline`, { body: { reason: 'نفدت المكونات اليوم' }, user: SELLER, expect: 200 });
check((await row(O5.id)).status === 'cancelled' && (await row(O5.id)).cancel_reason === 'declined' && (await stockOf(L1.id)).stock === before4, 'seller declined: cancelled, stock back');
check(/اعتذر البائع/.test(lastNote('market_status', BUYER)?.title ?? '') && /نفدت المكونات/.test(lastNote('market_status', BUYER)?.body ?? ''), 'buyer told the seller declined, with the reason');
const O6 = await cod(L1.id, {}, { expect: 200 });
await call('POST', `/market/orders/${O6.id}/accept`, { user: SELLER, expect: 200 });
await call('POST', `/market/orders/${O6.id}/cancel`, { expect: 200 }); // بعد القبول وقبل التحضير
const O7 = await cod(L1.id, {}, { expect: 200 });
await call('POST', `/market/orders/${O7.id}/accept`, { user: SELLER, expect: 200 });
await call('POST', `/market/orders/${O7.id}/stage`, { body: { stage: 'preparing' }, user: SELLER, expect: 200 });
await call('POST', `/market/orders/${O7.id}/cancel`, { expect: 409 }); // بدأ التحضير
const nC = notes.length;
await call('POST', `/market/orders/${O7.id}/cancel`, { user: SELLER, expect: 200 });
check((await stockOf(L1.id)).stock === before4 && (await row(O7.id)).cancel_reason === 'seller', 'seller cancelled mid-way: stock back');
check(notes.slice(nC).some((n) => n.ids.includes(BUYER) && !/استُرد/.test(n.body)), 'cancellation notice promises no refund for pay on receipt');
// الخيارات والكوبون
const LV = await call('POST', '/market', { body: { title: 'عباية', kind: 'product', category: 'other', price: 30000, placeName: 'البلد', payOnReceipt: true, variants: [{ name: 'S', price: 30000, stock: 2 }, { name: 'M', price: 32000 }] }, user: SELLER, expect: 200 });
await call('POST', '/market/coupons', { body: { code: 'COD10', percent: 10 }, user: SELLER, expect: 200 });
const OV = await cod(LV.id, { variant: 'S', qty: 2, coupon: 'cod10' }, { expect: 200 });
check(OV.total === 54000 && OV.discount === 6000, 'coupon applies to a pay-on-receipt order');
const vs = (await stockOf(LV.id)).variants.find((v) => v.name === 'S');
check(vs.stock === 0 && (await pool.query("SELECT used FROM market_coupons WHERE code='COD10'")).rows[0].used === 1, 'variant stock and coupon use reserved');
check((await cod(LV.id, { variant: 'S' }, { user: BUYER2, expect: 409 })).error === 'out-of-stock', 'sold-out variant refused');
await call('POST', `/market/orders/${OV.id}/decline`, { user: SELLER, expect: 200 });
check((await stockOf(LV.id)).variants.find((v) => v.name === 'S').stock === 2 && (await pool.query("SELECT used FROM market_coupons WHERE code='COD10'")).rows[0].used === 0, 'decline returns variant stock and the coupon');

// ---------- حد الطلبات المفتوحة ----------
const open = [];
for (let i = 0; i < 3; i++) open.push(await cod(LD.id, {}, { user: BUYER2, expect: 200 }));
await call('POST', `/market/orders/${open[0].id}/accept`, { user: SELLER, expect: 200 });
check((await cod(L1.id, {}, { user: BUYER2, expect: 429 })).error === 'cod-limit', 'a fourth open pay-on-receipt order is refused');
await call('POST', '/wallet/topup', { body: { amount: 100000 }, user: BUYER2, expect: 200 });
const W = await call('POST', `/market/${L1.id}/order`, { body: { qty: 1 }, user: BUYER2, expect: 200 });
check(W.payment === 'wallet' && W.status === 'paid' && await balance(BUYER2) === 95000, 'the wallet path stays open at the limit');
await call('POST', `/market/orders/${open[1].id}/cancel`, { user: BUYER2, expect: 200 });
await cod(L1.id, {}, { user: BUYER2, expect: 200 });
// ثلاثة متوازية من مشترٍ لديه طلبان مفتوحان: يمر واحد فقط
await pool.query("UPDATE market_orders SET status='cancelled', cancel_reason='buyer' WHERE buyer_id=$1 AND payment='cod' AND status IN ('requested','paid')", [BUYER2]);
await cod(L1.id, {}, { user: BUYER2, expect: 200 }); await cod(LD.id, {}, { user: BUYER2, expect: 200 });
const par = await Promise.all([0, 1, 2].map(() => app.inject({ method: 'POST', url: `/market/${L1.id}/order`, headers: { 'x-user': BUYER2, 'content-type': 'application/json' }, payload: JSON.stringify({ qty: 1, payment: 'cod' }) })));
const codes = par.map((r) => r.statusCode).sort();
check(codes.join(',') === '200,429,429', `parallel orders respect the limit (${codes.join(',')})`);
const openNow = (await pool.query("SELECT count(*)::int AS n FROM market_orders WHERE buyer_id=$1 AND payment='cod' AND status IN ('requested','paid','preparing','on_the_way','delivered')", [BUYER2])).rows[0].n;
check(openNow === 3, 'exactly three open pay-on-receipt orders');
const stats = await call('GET', '/market/seller/stats', { user: SELLER, expect: 200 });
check(stats.pending >= 3, 'seller dashboard counts orders awaiting acceptance as pending');

// ---------- «لم يحضر المشتري» ----------
await pool.query("UPDATE market_orders SET status='cancelled', cancel_reason='buyer' WHERE buyer_id=$1 AND payment='cod' AND status='requested'", [BUYER2]);
const ns = [];
for (let i = 0; i < 3; i++) { const o = await cod(L1.id, {}, { user: BUYER2, expect: 200 }); ns.push(o); }
await call('POST', `/market/orders/${ns[0].id}/no-show`, { user: SELLER, expect: 409 }); // قبل القبول
await call('POST', `/market/orders/${ns[0].id}/accept`, { user: SELLER, expect: 200 });
await call('POST', `/market/orders/${ns[0].id}/no-show`, { user: BUYER2, expect: 403 });
// لا «لم يحضر» لحظة القبول ولا أثناء التحضير: التسليم لم يحن بعد (ساعتان من القبول، أو «في الطريق»)
const early = await call('POST', `/market/orders/${ns[0].id}/no-show`, { user: SELLER, expect: 409 });
check(early.error === 'too-early' && new Date(early.at).getTime() > Date.now() + 3600000, 'no-show right after acceptance is refused until the handover is due');
await call('POST', `/market/orders/${ns[0].id}/stage`, { body: { stage: 'preparing' }, user: SELLER, expect: 200 });
check((await call('POST', `/market/orders/${ns[0].id}/no-show`, { user: SELLER, expect: 409 })).error === 'too-early', 'still too early while preparing');
await pool.query("UPDATE market_orders SET accepted_at=now() - interval '2 hours 1 minute' WHERE id=$1", [ns[0].id]);
const sBefore = (await stockOf(L1.id)).stock;
const ns1 = await call('POST', `/market/orders/${ns[0].id}/no-show`, { user: SELLER, expect: 200 });
check(ns1.noShows === 1 && (await row(ns[0].id)).cancel_reason === 'no_show' && (await stockOf(L1.id)).stock === sBefore + 1, 'no-show two hours after acceptance: cancelled, counted, stock back');
const nsNote = lastNote('market_status', BUYER2)?.body ?? '';
check(/1 من 3/.test(nsNote) && /3 بائعين مختلفين خلال 90 يوماً/.test(nsNote) && /أبلغ عن البائع/.test(nsNote) && !/المحفظة/.test(nsNote), 'buyer told the count, the rule and how to report, with no wallet hint');
await call('POST', `/market/orders/${ns[0].id}/no-show`, { user: SELLER, expect: 409 });
// «في الطريق» يكفي بلا انتظار، لكن البائع نفسه لا يُحسب مرتين
await call('POST', `/market/orders/${ns[1].id}/accept`, { user: SELLER, expect: 200 });
await call('POST', `/market/orders/${ns[1].id}/stage`, { body: { stage: 'on_the_way' }, user: SELLER, expect: 200 });
check((await call('POST', `/market/orders/${ns[1].id}/no-show`, { user: SELLER, expect: 200 })).noShows === 1, 'on the way: no-show allowed at once, and the same seller counts once');
await call('POST', `/market/orders/${ns[2].id}/accept`, { user: SELLER, expect: 200 });
await pool.query("UPDATE market_orders SET accepted_at=now() - interval '3 hours' WHERE id=$1", [ns[2].id]);
check((await call('POST', `/market/orders/${ns[2].id}/no-show`, { user: SELLER, expect: 200 })).noShows === 1, 'a third no-show from the same seller is still one');
const stillOk = await cod(L1.id, {}, { user: BUYER2, expect: 200 });
check(stillOk.status === 'requested', 'one seller alone cannot shut pay on receipt for a buyer');
await call('POST', `/market/orders/${stillOk.id}/cancel`, { user: BUYER2, expect: 200 });
// بائعان آخران يكملان الثلاثة
const L2S = await call('POST', '/market', { body: { title: 'ورد طبيعي', kind: 'product', category: 'gifts', price: 6000, placeName: 'التحلية', payOnReceipt: true }, user: SELLER2, expect: 200 });
const L3S = await call('POST', '/market', { body: { title: 'بخور', kind: 'product', category: 'gifts', price: 7000, placeName: 'الشاطئ', payOnReceipt: true }, user: SELLER3, expect: 200 });
const noShowBy = async (listing, seller, buyer = BUYER2) => {
  const o = await cod(listing.id, {}, { user: buyer, expect: 200 });
  await call('POST', `/market/orders/${o.id}/accept`, { user: seller, expect: 200 });
  await call('POST', `/market/orders/${o.id}/stage`, { body: { stage: 'on_the_way' }, user: seller, expect: 200 });
  return { id: o.id, ...(await call('POST', `/market/orders/${o.id}/no-show`, { user: seller, expect: 200 })) };
};
const nsB = await noShowBy(L2S, SELLER2);
check(nsB.noShows === 2, 'a second seller makes two');
const nsC = await noShowBy(L3S, SELLER3);
const lastNs = lastNote('market_status', BUYER2)?.body ?? '';
check(nsC.noShows === 3 && /توقف الدفع عند الاستلام لحسابك\./.test(lastNs) && !/المحفظة/.test(lastNs), 'third seller: buyer told pay on receipt is off, in neutral words');
const blockedErr = await cod(L1.id, {}, { user: BUYER2, expect: 403 });
check(blockedErr.error === 'cod-blocked' && blockedErr.noShows === 3 && blockedErr.days === 90, 'after no-shows from three sellers pay on receipt is refused');
// الإدارة: قائمة «لم يحضر» في نافذة العدّ ومسح الظالم منها
await call('GET', '/adminapi/market/no-shows', { user: SELLER, expect: 403 });
const nsList = await call('GET', '/adminapi/market/no-shows', { user: ADMIN, expect: 200 });
const itC = nsList.items.find((x) => x.order.id === nsC.id);
check(nsList.days === 90 && nsList.max === 3 && itC && itC.buyerNoShows === 3 && itC.order.cancelReason === 'no_show' && itC.order.code == null, 'admin lists recent no-shows with the buyer count (no buyer code)');
await call('POST', `/adminapi/market/orders/${nsC.id}/clear-no-show`, { user: SELLER3, expect: 403 });
const cleared = await call('POST', `/adminapi/market/orders/${nsC.id}/clear-no-show`, { body: { note: 'ثبت أن المشتري حضر' }, user: ADMIN, expect: 200 });
check(cleared.noShows === 2 && (await row(nsC.id)).cancel_reason === 'no_show_cleared', 'admin cleared a no-show: the buyer is back to two');
check(lastNote('market_status', BUYER2)?.title === 'أُزيل تسجيل عدم حضورك' && /ثبت أن المشتري حضر/.test(lastNote('market_status', BUYER2)?.body ?? '') && lastNote('market_status', SELLER3)?.data?.orderId === nsC.id, 'both sides told the no-show was removed');
await call('POST', `/adminapi/market/orders/${nsC.id}/clear-no-show`, { user: ADMIN, expect: 409 });
check(!(await call('GET', '/adminapi/market/no-shows', { user: ADMIN, expect: 200 })).items.some((x) => x.order.id === nsC.id), 'a cleared no-show leaves the admin list');
const back = await cod(L1.id, {}, { user: BUYER2, expect: 200 });
check(back.status === 'requested', 'pay on receipt open again after the admin cleared one');
await call('POST', `/market/orders/${back.id}/cancel`, { user: BUYER2, expect: 200 });
// نافذة ٩٠ يوماً: «لم يحضر» أقدم منها لا يُحسب
await pool.query("UPDATE market_orders SET updated_at=now() - interval '91 days' WHERE id=$1", [nsB.id]);
check((await noShowBy(L3S, SELLER3)).noShows === 2, 'a no-show older than 90 days no longer counts');
await cod(L1.id, {}, { user: BUYER2, expect: 200 }).then((o) => call('POST', `/market/orders/${o.id}/cancel`, { user: BUYER2, expect: 200 }));
await pool.query("UPDATE market_orders SET updated_at=now() WHERE id=$1", [nsB.id]);
check((await cod(L1.id, {}, { user: BUYER2, expect: 403 })).error === 'cod-blocked', 'three sellers inside the window block again');
await call('POST', `/market/${L1.id}/order`, { body: { qty: 1 }, user: BUYER2, expect: 200 }); // المحفظة تبقى
await globalThis.naslifeMarketRecomputeSeller(SELLER);
const sellerCancelled = (await pool.query('SELECT cancelled FROM market_seller_stats WHERE seller_id=$1', [SELLER])).rows[0].cancelled;
const expectCancelled = (await pool.query("SELECT count(*)::int AS n FROM market_orders WHERE seller_id=$1 AND status IN ('cancelled','refunded') AND cancel_reason IS DISTINCT FROM 'no_show' AND NOT (payment='cod' AND accepted_at IS NULL)", [SELLER])).rows[0].n;
check(sellerCancelled === expectCancelled, `buyer no-shows and never-accepted requests are not held against the seller (${sellerCancelled})`);
// خدمة بموعد: لا «لم يحضر» قبل الموعد
const LS = await call('POST', '/market', { body: { title: 'جلسة تصوير', kind: 'service', category: 'photo', price: 20000, placeName: 'الكورنيش', payOnReceipt: true, availability: { days: [0, 1, 2, 3, 4, 5, 6], from: '08:00', to: '22:00', slotMinutes: 60 } }, user: SELLER, expect: 200 });
const d = new Date(Date.now() + 2 * 86400000); const slot = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(), 10 - 3, 0));
const OS = await cod(LS.id, { slot: slot.toISOString() }, { user: OTHER, expect: 200 });
await cod(LS.id, { slot: slot.toISOString() }, { user: BUYER, expect: 409 }); // الموعد محجوز ولو قبل القبول
await call('POST', `/market/orders/${OS.id}/accept`, { user: SELLER, expect: 200 });
check((await call('POST', `/market/orders/${OS.id}/no-show`, { user: SELLER, expect: 409 })).error === 'too-early', 'no-show before the booked slot is refused');
await pool.query("UPDATE market_orders SET slot=now() - interval '1 hour' WHERE id=$1", [OS.id]);
await call('POST', `/market/orders/${OS.id}/no-show`, { user: SELLER, expect: 200 });

// ---------- مهلة القبول والاكتمال التلقائي ----------
const OE = await cod(L1.id, {}, { user: OTHER, expect: 200 });
const sE = (await stockOf(L1.id)).stock;
await pool.query("UPDATE market_orders SET created_at=now() - interval '49 hours' WHERE id=$1", [OE.id]);
const nE = notes.length;
await globalThis.naslifeMarketSweep();
check((await row(OE.id)).status === 'cancelled' && (await row(OE.id)).cancel_reason === 'expired' && (await stockOf(L1.id)).stock === sE + 1, 'unanswered order cancelled after 48 hours, stock back');
check(notes.slice(nE).some((n) => n.ids.includes(OTHER)) && notes.slice(nE).some((n) => n.ids.includes(SELLER)), 'both sides told about the expiry');
const OA = await cod(L1.id, {}, { user: OTHER, expect: 200 });
await call('POST', `/market/orders/${OA.id}/accept`, { user: SELLER, expect: 200 });
await call('POST', `/market/orders/${OA.id}/stage`, { body: { stage: 'delivered' }, user: SELLER, expect: 200 });
await pool.query("UPDATE market_orders SET delivered_at=now() - interval '73 hours' WHERE id=$1", [OA.id]);
await globalThis.naslifeMarketSweep();
check((await row(OA.id)).status === 'completed' && await txCount(SELLER) === 0 && await txCount(PLATFORM) === 0, 'delivered pay-on-receipt order auto-completes after 72 hours with no ledger entry');

// ---------- iOS والطلب المجاني والمحفظة ----------
const OI = await cod(LD.id, {}, { user: OTHER, headers: { 'x-naslife-client': 'ios/1.0.0' }, expect: 200 });
check(OI.payment === 'cod' && OI.status === 'requested', 'iOS client can order with pay on receipt');
const LF = await call('POST', '/market', { body: { title: 'كتب مستعملة', kind: 'product', category: 'other', price: 0, placeName: 'الحمراء', payOnReceipt: true }, user: SELLER, expect: 200 });
const OF = await cod(LF.id, {}, { user: MINOR, expect: 200 });
check(OF.payment === 'wallet' && OF.status === 'paid' && OF.total === 0, 'a free item with payment=cod is an ordinary free order (no acceptance, no 18+)');
// طلب المحفظة لم يتغيّر: الخصم عند الطلب، والتحرير للبائع بعد العمولة عند الاكتمال
await call('POST', `/market/orders/${W.id}/confirm`, { user: BUYER2, expect: 200 });
check(await balance(SELLER) === 4500 && await balance(PLATFORM) === 500, 'wallet order still releases net to the seller and commission to the platform');
const mine = await call('GET', '/market/orders', { user: OTHER, expect: 200 });
check(mine.some((o) => o.payment === 'cod') && mine.every((o) => ['cod', 'wallet'].includes(o.payment)), 'order list carries the payment method');

// ---------- «من يراسلني»: الطلب الذي لم يُقبل قط لا يُبقي المراسلة مفتوحة ----------
// BUYER3 مع SELLER2 بلا أي طلب آخر بينهما
check(!(await allow(BUYER3, SELLER2)), 'message allow: no order, no unlock');
const M1 = await cod(L2S.id, {}, { user: BUYER3, expect: 200 });
check(await allow(BUYER3, SELLER2), 'message allow: a live request unlocks messaging');
await call('POST', `/market/orders/${M1.id}/decline`, { user: SELLER2, expect: 200 });
check(!(await allow(BUYER3, SELLER2)) && !(await allow(SELLER2, BUYER3)), 'message allow: a declined request no longer unlocks it');
const M2 = await cod(L2S.id, {}, { user: BUYER3, expect: 200 });
await call('POST', `/market/orders/${M2.id}/cancel`, { user: BUYER3, expect: 200 });
check(!(await allow(BUYER3, SELLER2)), 'message allow: a request the buyer cancelled does not unlock it');
const M3 = await cod(L2S.id, {}, { user: BUYER3, expect: 200 });
await pool.query("UPDATE market_orders SET created_at=now() - interval '49 hours' WHERE id=$1", [M3.id]);
await globalThis.naslifeMarketSweep();
check((await row(M3.id)).cancel_reason === 'expired' && !(await allow(BUYER3, SELLER2)), 'message allow: an expired request does not unlock it');
const M4 = await cod(L2S.id, {}, { user: BUYER3, expect: 200 });
await call('POST', `/market/orders/${M4.id}/accept`, { user: SELLER2, expect: 200 });
await call('POST', `/market/orders/${M4.id}/cancel`, { user: SELLER2, expect: 200 });
check(await allow(BUYER3, SELLER2), 'message allow: an accepted order cancelled later keeps the 14-day window');

// ---------- الشارات: طلبات بلا مال بين حسابين لا تصنع ثقة، وطلبات المنافس الملغاة لا تُحسب على البائع ----------
const LF2 = await call('POST', '/market', { body: { title: 'تمر خلاص', kind: 'product', category: 'food', price: 3000, placeName: 'الصفا', payOnReceipt: true }, user: FSELL, expect: 200 });
for (let i = 0; i < 10; i++) {
  const o = await cod(LF2.id, {}, { user: FBUY, expect: 200 });
  await call('POST', `/market/orders/${o.id}/accept`, { user: FSELL, expect: 200 });
  await call('POST', `/market/orders/${o.id}/cash-received`, { user: FSELL, expect: 200 });
  if (i < 5) await call('POST', `/market/orders/${o.id}/review`, { body: { rating: 5, text: 'ممتاز' }, user: FBUY, expect: 200 });
}
await globalThis.naslifeMarketRecomputeSeller(FSELL);
const farm = (await pool.query('SELECT * FROM market_seller_stats WHERE seller_id=$1', [FSELL])).rows[0];
check(farm.completed === 10 && farm.rating_count === 5 && ![...farm.badges].some((b) => ['trusted', 'top', 'fast'].includes(b)), `ten self-dealt pay-on-receipt orders from one account earn no trusted/top/fast badge (${JSON.stringify(farm.badges)})`);
check(await txCount(FSELL) === 0 && await txCount(FBUY) === 0, 'and moved no money');
// مشترون مختلفون حقيقيون يُحسبون: ثلاثة مشترين بقبول سريع = «سريع الرد»
for (const b of [BUYER, BUYER3]) {
  const o = await cod(LF2.id, {}, { user: b, expect: 200 });
  await call('POST', `/market/orders/${o.id}/accept`, { user: FSELL, expect: 200 });
  await call('POST', `/market/orders/${o.id}/confirm`, { user: b, expect: 200 });
}
await globalThis.naslifeMarketRecomputeSeller(FSELL);
check([...(await pool.query('SELECT badges FROM market_seller_stats WHERE seller_id=$1', [FSELL])).rows[0].badges].includes('fast'), 'pay-on-receipt orders from three distinct buyers still count toward a badge');
// منافس يطلب ويلغي مجاناً، والبائع يعتذر، ومهلة تنتهي: لا شيء منها إلغاء على البائع
const cancelledOf = async () => { await globalThis.naslifeMarketRecomputeSeller(FSELL); return (await pool.query('SELECT cancelled FROM market_seller_stats WHERE seller_id=$1', [FSELL])).rows[0].cancelled; };
const c0 = await cancelledOf();
for (let i = 0; i < 2; i++) { const o = await cod(LF2.id, {}, { user: COMP, expect: 200 }); await call('POST', `/market/orders/${o.id}/cancel`, { user: COMP, expect: 200 }); }
const cd = await cod(LF2.id, {}, { user: COMP, expect: 200 }); await call('POST', `/market/orders/${cd.id}/decline`, { user: FSELL, expect: 200 });
const ce = await cod(LF2.id, {}, { user: COMP, expect: 200 });
await pool.query("UPDATE market_orders SET created_at=now() - interval '49 hours' WHERE id=$1", [ce.id]); await globalThis.naslifeMarketSweep();
check(await cancelledOf() === c0, `never-accepted requests (buyer cancel, decline, expiry) do not count as seller cancellations (${c0})`);
const ca = await cod(LF2.id, {}, { user: COMP, expect: 200 });
await call('POST', `/market/orders/${ca.id}/accept`, { user: FSELL, expect: 200 });
await call('POST', `/market/orders/${ca.id}/cancel`, { user: FSELL, expect: 200 });
check(await cancelledOf() === c0 + 1, 'a seller cancelling an accepted order still counts');

console.log(fails ? `\n${fails} FAILED` : '\nALL MARKET COD OK');
await app.close(); await pool.end();
process.exit(fails ? 1 : 0);
