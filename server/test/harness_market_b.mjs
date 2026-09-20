// المرحلة (ب) من السوق على Postgres المحلي: مندوب توصيل، بازارات، ترقية البائع إلى دائرة، بوابة دفع (معطّلة ثم مفعّلة بمزوّد وهمي)، بطاقة الشات الأغنى
import Fastify from 'fastify';
import pg from 'pg';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NODE_ENV = 'test';
delete process.env.MOYASAR_PUBLISHABLE_KEY; delete process.env.MOYASAR_SECRET_KEY;
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("INSERT INTO users(id,nickname,created_at) VALUES('SA0000001','amr',now()-interval '30 days'),('SA0000002','sara',now()-interval '30 days'),('SA0000003','khalid',now()-interval '30 days'),('SA0000004','rider',now()-interval '30 days'),('SA0000000','naslife',now()-interval '60 days') ON CONFLICT (id) DO UPDATE SET created_at=EXCLUDED.created_at, nickname=EXCLUDED.nickname");
await pool.query("UPDATE users SET is_admin=true WHERE id='SA0000001'");
for (const t of ['market_reviews','market_coupons','market_seller_stats','market_seller_flags','market_follows','market_questions','market_wanted','market_wanted_replies','market_spotlight','market_alerts','market_views','market_orders','market_listings','market_bazaars','market_seller_upgrades','payments','payment_settings','chat_requests']) await pool.query(`DROP TABLE IF EXISTS ${t}`);
await pool.query("DELETE FROM wallet_tx WHERE user_id IN ('SA0000001','SA0000002','SA0000003','SA0000004','SA0000000'); DELETE FROM wallet_accounts WHERE user_id IN ('SA0000001','SA0000002','SA0000003','SA0000004','SA0000000')").catch(() => {});
await pool.query("DELETE FROM biz_items WHERE biz_id IN (SELECT id FROM biz WHERE owner_id='SA0000002'); DELETE FROM biz WHERE owner_id='SA0000002'").catch(() => {});
const notes = []; globalThis.naslifeNotify = async (ids, p) => { notes.push({ ids: [].concat(ids), ...p }); }; globalThis.naslifeNotifyAdmins = async (p) => { notes.push({ ids: ['admins'], ...p }); };
globalThis.naslifeSettings = { marketCommissionPct: 10, spotlightPricePerDay: 1000, marketBlockContacts: true, maxTopup: 500000 };
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
app.register((await import('../commerce.js')).default, { pool, auth });
app.register((await import('../business.js')).default, { pool, auth });
app.register((await import('../market_plus.js')).default, { pool, auth });
app.register((await import('../chat_cards.js')).default, { pool, auth });
app.register((await import('../market_b.js')).default, { pool, auth });
await app.ready();
let fails = 0;
const call = async (method, url, { body, user = 'SA0000002', expect, raw = false } = {}) => {
  const r = await app.inject({ method, url, headers: { 'x-user': user, ...(method === 'GET' ? {} : { 'content-type': 'application/json' }) }, payload: method === 'GET' ? undefined : JSON.stringify(body ?? {}) });
  let j; try { j = raw ? r.body : r.json(); } catch { j = r.body; }
  const ok = expect == null || r.statusCode === expect; if (!ok) fails++;
  console.log((ok ? 'OK  ' : 'FAIL') + ' ' + method + ' ' + url.slice(0, 70) + ' -> ' + r.statusCode + (ok ? '' : ' expected ' + expect) + ' ' + (typeof j === 'string' ? j.replace(/\s+/g, ' ').slice(0, 80) : JSON.stringify(j).slice(0, 150)));
  return j;
};
const check = (ok, m) => { if (!ok) fails++; console.log((ok ? 'OK  ' : 'FAIL') + ' ' + m); };
const SELLER = 'SA0000002', BUYER = 'SA0000003', RIDER = 'SA0000004', ADMIN = 'SA0000001';
await call('POST', '/wallet/topup', { body: { amount: 200000 }, user: BUYER, expect: 200 });

// ---------- مندوب التوصيل ----------
const L1 = await call('POST', '/market', { body: { title: 'كيك عيد ميلاد', description: 'كيك فانيلا', kind: 'product', category: 'food', subcategory: 'sweets', price: 22000, delivery: true, city: 'جدة', placeName: 'الروضة', lat: 21.562, lng: 39.165, images: ['/seed/market/b.jpg'] }, user: SELLER, expect: 200 });
const O = await call('POST', `/market/${L1.id}/order`, { body: { qty: 1 }, user: BUYER, expect: 200 });
await call('POST', `/market/orders/${O.id}/courier`, { body: { nickname: 'rider' }, user: BUYER, expect: 403 });
await call('POST', `/market/orders/${O.id}/courier`, { body: { nickname: 'nobody' }, user: SELLER, expect: 404 });
await call('POST', `/market/orders/${O.id}/courier`, { body: { nickname: 'khalid' }, user: SELLER, expect: 400 }); // المشتري نفسه
const withC = await call('POST', `/market/orders/${O.id}/courier`, { body: { nickname: '@Rider', note: 'يتصل قبل الوصول' }, user: SELLER, expect: 200 });
check(withC.courier?.id === RIDER && withC.courierNote === 'يتصل قبل الوصول' && withC.mineAsCourier === false, 'seller assigned a courier by nickname');
check(notes.some((n) => n.kind === 'market_courier' && n.ids.includes(RIDER)) && notes.some((n) => n.ids.includes(BUYER) && /مندوب/.test(n.title)), 'courier and buyer notified');
const riderList = await call('GET', '/market/orders', { user: RIDER, expect: 200 }); check(riderList.length === 1 && riderList[0].mineAsCourier === true && riderList[0].code == null, 'courier sees the order in his list without the buyer code');
await call('GET', `/market/orders/${O.id}`, { user: RIDER, expect: 200 });
await call('POST', `/market/orders/${O.id}/stage`, { body: { stage: 'preparing' }, user: RIDER, expect: 403 }); // ليس من صلاحيته
await call('POST', `/market/orders/${O.id}/stage`, { body: { stage: 'preparing' }, user: SELLER, expect: 200 });
await call('POST', `/market/orders/${O.id}/stage`, { body: { stage: 'on_the_way' }, user: RIDER, expect: 200 });
await call('POST', `/market/orders/${O.id}/stage`, { body: { stage: 'delivered' }, user: RIDER, expect: 200 });
const afterD = await call('GET', `/market/orders/${O.id}`, { user: BUYER, expect: 200 }); check(afterD.status === 'delivered' && afterD.courier?.nickname === 'rider', 'courier moved the order to delivered');
await call('POST', `/market/orders/${O.id}/courier`, { body: { nickname: 'rider' }, user: SELLER, expect: 409 }); // بعد التسليم
await call('POST', `/market/orders/${O.id}/confirm`, { body: {}, user: BUYER, expect: 200 });
await call('DELETE', `/market/orders/${O.id}/courier`, { user: RIDER, expect: 403 });

// ---------- البازارات ----------
await call('POST', '/adminapi/market/bazaars', { body: { title: 'بازار', endsAt: new Date(Date.now() + 5 * 86400000).toISOString() }, user: SELLER, expect: 403 });
await call('POST', '/adminapi/market/bazaars', { body: { title: 'بازار', endsAt: new Date(Date.now() - 86400000).toISOString() }, user: ADMIN, expect: 400 });
const BZ = await call('POST', '/adminapi/market/bazaars', { body: { title: 'بازار الحلويات', description: 'أسبوع الحلا', city: 'جدة', category: 'food', endsAt: new Date(Date.now() + 5 * 86400000).toISOString() }, user: ADMIN, expect: 200 });
check(BZ.state === 'live' && BZ.category === 'food' && BZ.listings === 0, 'bazaar created and live');
check(notes.some((n) => n.kind === 'market_bazaar' && n.ids.includes(SELLER)), 'sellers in the category notified about the bazaar');
const UP = await call('POST', '/adminapi/market/bazaars', { body: { title: 'بازار العيد', startsAt: new Date(Date.now() + 2 * 86400000).toISOString(), endsAt: new Date(Date.now() + 9 * 86400000).toISOString() }, user: ADMIN, expect: 200 });
check(UP.state === 'upcoming', 'upcoming bazaar');
const L2 = await call('POST', '/market', { body: { title: 'عباية', kind: 'product', category: 'other', price: 30000 }, user: SELLER, expect: 200 });
await call('POST', `/market/bazaars/${BZ.id}/join`, { body: { listingId: L2.id }, user: SELLER, expect: 400 }); // تصنيف مختلف
await call('POST', `/market/bazaars/${BZ.id}/join`, { body: { listingId: L1.id }, user: BUYER, expect: 403 }); // ليس المالك
await call('POST', `/market/bazaars/${BZ.id}/join`, { body: { listingId: L1.id }, user: SELLER, expect: 200 });
await call('POST', `/market/bazaars/${UP.id}/join`, { body: { listingId: L2.id }, user: SELLER, expect: 200 }); // بازار بلا تصنيف يقبل الكل
const list = await call('GET', '/market/bazaars', { user: BUYER, expect: 200 }); check(list.length === 2 && list[0].id === BZ.id && list[0].listings === 1 && list[0].state === 'live', 'active bazaars listed live first with counts');
const det = await call('GET', `/market/bazaars/${BZ.id}?lat=21.56&lng=39.16`, { user: BUYER, expect: 200 }); check(det.items?.length === 1 && det.items[0].id === L1.id && det.items[0].distanceKm != null, 'bazaar detail lists joined listings with distance');
const home = await call('GET', '/market/home?lat=21.56&lng=39.16', { user: BUYER, expect: 200 }); check(Array.isArray(home.bazaars) && home.bazaars.length === 2, 'market home carries the bazaars');
await call('DELETE', `/market/bazaars/${BZ.id}/join/${L1.id}`, { user: BUYER, expect: 404 });
await call('DELETE', `/market/bazaars/${BZ.id}/join/${L1.id}`, { user: SELLER, expect: 200 });
const ended = await call('PATCH', `/adminapi/market/bazaars/${BZ.id}`, { body: { active: false }, user: ADMIN, expect: 200 }); check(ended.state === 'ended', 'admin closed the bazaar');
await call('POST', `/market/bazaars/${BZ.id}/join`, { body: { listingId: L1.id }, user: SELLER, expect: 409 });
const all = await call('GET', '/adminapi/market/bazaars', { user: ADMIN, expect: 200 }); check(all.length === 2, 'admin sees all bazaars');

// ---------- بطاقة الشات الأغنى ----------
const cards = await call('GET', `/chat/cards?refs=${encodeURIComponent('#mk/' + L1.id)}`, { user: BUYER, expect: 200 });
const card = cards?.refs?.[`#mk/${L1.id}`];
check(card && String(card.image ?? '').endsWith('/seed/market/b.jpg') && /جدة/.test(card.subtitle) && /توصيل/.test(card.subtitle) && card.kind === 'product', 'chat listing card carries image, city, delivery and kind');

// ---------- ترقية البائع إلى دائرة ----------
const pv = await call('GET', '/market/seller/upgrade', { user: SELLER, expect: 200 }); check(pv.eligible === true && pv.listings === 2 && pv.suggestedCategory === 'restaurant' && pv.lat != null, 'upgrade preview: eligible, category from top listings, position from listings');
await call('POST', '/market/seller/upgrade', { body: {}, user: BUYER, expect: 409 }); // بلا عروض
const up = await call('POST', '/market/seller/upgrade', { body: { nameAr: 'مطبخ سارة', description: 'حلويات منزلية' }, user: SELLER, expect: 200 });
check(up.ok && up.bizId?.startsWith('biz-') && up.items === 2 && up.biz?.nameAr === 'مطبخ سارة' && up.biz?.category === 'restaurant', 'circle created with the listings copied as catalog items');
const bz = await call('GET', `/biz/${up.bizId}`, { user: BUYER, expect: 200 }); check(bz.items?.length === 2 && bz.items.some((i) => i.title === 'كيك عيد ميلاد' && i.price === 22000), 'circle catalog shows the copied items');
await call('POST', '/market/seller/upgrade', { body: {}, user: SELLER, expect: 409 });
const pv2 = await call('GET', '/market/seller/upgrade', { user: SELLER, expect: 200 }); check(pv2.upgraded?.bizId === up.bizId && pv2.eligible === false, 'preview reports the existing circle');

// ---------- بوابة الدفع: معطّلة ----------
const cfg0 = await call('GET', '/pay/config', { user: BUYER, expect: 200 }); check(cfg0.enabled === false && cfg0.publishableKey == null, 'payments disabled without keys');
await call('POST', '/pay/topup', { body: { amount: 5000 }, user: BUYER, expect: 503 });
// ---------- مفاتيح من لوحة الإدارة ----------
await call('GET', '/adminapi/payments/config', { user: BUYER, expect: 403 });
const pc0 = await call('GET', '/adminapi/payments/config', { user: ADMIN, expect: 200 }); check(pc0.enabled === false && pc0.source == null && pc0.panelKeysSet === false && pc0.envPresent === false, 'admin config: disabled, no keys anywhere');
await call('PUT', '/adminapi/payments/config', { body: { publishableKey: 'oops', secretKey: 'sk_test_abcdefgh34' }, user: ADMIN, expect: 400 });
check((await call('PUT', '/adminapi/payments/config', { body: { publishableKey: 'pk_test_abcdefgh12', secretKey: 'sk_t**************************' }, user: ADMIN, expect: 400 })).error === 'masked-key', 'masked secret copied from the dashboard is rejected with masked-key');
check((await call('PUT', '/adminapi/payments/config', { body: { publishableKey: ' pk_test_abcdefgh12\n', secretKey: 'sk_test_ abcdefgh34' }, user: ADMIN, expect: 200 })).enabled === true, 'whitespace inside pasted keys is stripped');
await call('PUT', '/adminapi/payments/config', { body: { publishableKey: '', secretKey: '' }, user: ADMIN, expect: 200 });
await call('PUT', '/adminapi/payments/config', { body: { publishableKey: 'pk_test_abcdefgh12' }, user: ADMIN, expect: 400 });
await call('PUT', '/adminapi/payments/config', { body: { publishableKey: 'pk_test_abcdefgh12', secretKey: 'sk_live_abcdefgh34' }, user: ADMIN, expect: 400 });
const pc1 = await call('PUT', '/adminapi/payments/config', { body: { publishableKey: 'pk_test_abcdefgh12', secretKey: 'sk_test_abcdefgh34', webhookSecret: 'panelwh' }, user: ADMIN, expect: 200 });
check(pc1.enabled === true && pc1.mode === 'test' && pc1.source === 'panel' && pc1.secretKeySet === true && pc1.secretKeyHint === 'sk_test_…gh34' && pc1.webhookSecretSet === true && pc1.publishableKey === 'pk_test_abcdefgh12' && !JSON.stringify(pc1).includes('abcdefgh34'), 'panel keys saved: test mode, secret masked, never echoed');
const cfgP = await call('GET', '/pay/config', { user: BUYER, expect: 200 }); check(cfgP.enabled === true && cfgP.publishableKey === 'pk_test_abcdefgh12', 'wallet sees payments enabled from panel keys');
let lastAuth = null; globalThis.naslifePayFetch = async (url, init) => { lastAuth = init?.headers?.authorization; return { ok: true, status: 200, json: async () => ({ payments: [] }) }; };
const t1 = await call('POST', '/adminapi/payments/test', { user: ADMIN, expect: 200 }); check(t1.ok === true && t1.mode === 'test' && t1.source === 'panel' && lastAuth === 'Basic ' + Buffer.from('sk_test_abcdefgh34:').toString('base64'), 'connection test uses the panel secret');
globalThis.naslifePayFetch = async () => ({ ok: false, status: 401, json: async () => ({}) });
const t2 = await call('POST', '/adminapi/payments/test', { user: ADMIN, expect: 200 }); check(t2.ok === false && t2.error === 'bad-secret', 'connection test reports a wrong secret');
globalThis.naslifePayFetch = async () => { throw new Error('ECONNREFUSED'); };
const t3 = await call('POST', '/adminapi/payments/test', { user: ADMIN, expect: 200 }); check(t3.ok === false && t3.error === 'provider-unreachable', 'connection test reports unreachable provider');
globalThis.naslifePayFetch = async () => ({ ok: false, status: 405, json: async () => ({ type: 'account_inactive_error', message: 'Your account is not active' }), text: async () => '{"type":"account_inactive_error"}' });
const t4 = await call('POST', '/adminapi/payments/test', { user: ADMIN, expect: 200 }); check(t4.ok === false && t4.error === 'account-inactive' && t4.message === 'Your account is not active', 'connection test reports an inactive Moyasar account (405)');
check((await call('POST', '/pay/topup', { body: { amount: 5000 }, user: BUYER, expect: 503 })).error === 'payments-inactive', 'top-up with an inactive account returns payments-inactive');
const wh0 = await app.inject({ method: 'POST', url: '/pay/webhook', headers: { 'content-type': 'application/json', 'x-webhook-secret': 'wrong' }, payload: JSON.stringify({ data: { id: 'pay_000009' } }) }); check(wh0.statusCode === 401, 'webhook rejects a wrong panel secret');
const pc2 = await call('PUT', '/adminapi/payments/config', { body: { secretKey: '' , publishableKey: '' }, user: ADMIN, expect: 200 }); check(pc2.enabled === false && pc2.panelKeysSet === false && pc2.webhookSecretSet === false, 'clearing both keys disables payments again');
check((await call('POST', '/adminapi/payments/test', { user: ADMIN, expect: 200 })).error === 'payments-disabled', 'connection test without keys says disabled');

// ---------- مفعّلة بمزوّد وهمي ----------
process.env.MOYASAR_PUBLISHABLE_KEY = 'pk_test_x'; process.env.MOYASAR_SECRET_KEY = 'sk_test_y'; process.env.MOYASAR_WEBHOOK_SECRET = 'whsec';
const provider = {}; // معرّف ميسر → الدفعة
const invoices = []; // طلبات إنشاء الفواتير المستضافة
let rejectExtrasOnce = false; const invoicePayments = {}; // معرّف الفاتورة → دفعاتها كما يعيدها GET /invoices/:id
globalThis.naslifePayFetch = async (url, init) => {
  if (url.endsWith('/invoices') && init?.method === 'POST') {
    const b = JSON.parse(init.body);
    if (b.success_url && rejectExtrasOnce) { rejectExtrasOnce = false; return { ok: false, status: 400, text: async () => 'unpermitted', json: async () => ({}) }; }
    invoices.push({ auth: init.headers?.authorization, ...b }); const n = invoices.length; return { ok: true, status: 201, json: async () => ({ id: `inv_00000${n}`, status: 'initiated', url: `https://invoice.moyasar.com/inv_00000${n}`, amount: b.amount, metadata: b.metadata }) };
  }
  if (/\/invoices\/inv_/.test(url)) { const id = url.split('/').pop(); return { ok: true, status: 200, json: async () => ({ id, status: invoicePayments[id]?.some((x) => x.status === 'paid') ? 'paid' : 'initiated', payments: invoicePayments[id] ?? [] }) }; }
  const id = url.split('/').pop(); const p = provider[id]; return { ok: !!p, status: p ? 200 : 404, json: async () => p };
};
process.env.PAY_EMBED = '1'; // القسم التالي يختبر النموذج المضمّن
const cfg1 = await call('GET', '/pay/config', { user: BUYER, expect: 200 }); check(cfg1.enabled === true && cfg1.publishableKey === 'pk_test_x' && cfg1.min === 1000 && cfg1.max === 500000, 'payments enabled with publishable key and limits');
await call('POST', '/pay/topup', { body: { amount: 500 }, user: BUYER, expect: 400 });
const tp = await call('POST', '/pay/topup', { body: { amount: 15000 }, user: BUYER, expect: 200 }); check(/\/pay\/checkout\/[0-9a-f-]{36}\?t=[0-9a-f]{24}$/.test(tp.checkoutUrl) && tp.amount === 15000, 'topup intent returns a checkout url with a nonce');
const page = await call('GET', tp.checkoutUrl.replace(/^https?:\/\/[^/]+/, ''), { user: BUYER, expect: 200, raw: true }); check(page.includes('Moyasar.init') && page.includes('"amount":15000') && page.includes('naslife_payment'), 'checkout page embeds the Moyasar form with amount and metadata');
check(!page.includes('applepay') && page.includes('"methods":["creditcard","stcpay"]') && page.includes('try{Moyasar.init') && page.includes('العودة إلى ناس لايف') && !page.includes('form-action'), 'checkout page: no Apple Pay without its config, init guarded, back link, CSP without form-action');
await call('GET', `/pay/checkout/${tp.id}?t=wrong`, { user: BUYER, expect: 404, raw: true });
const before = (await call('GET', '/wallet', { user: BUYER, expect: 200 })).balance;
provider.pay_000001 = { id: 'pay_000001', status: 'paid', amount: 15000, currency: 'SAR', metadata: { naslife_payment: tp.id }, source: { type: 'creditcard', company: 'mada' } };
provider.pay_000002 = { id: 'pay_000002', status: 'failed', amount: 15000, currency: 'SAR', metadata: { naslife_payment: tp.id }, source: { message: 'DECLINED' } };
provider.pay_000003 = { id: 'pay_000003', status: 'paid', amount: 999, currency: 'SAR', metadata: { naslife_payment: tp.id } };
await call('GET', '/pay/return?id=pay_000003', { user: BUYER, expect: 400, raw: true }); // مبلغ مختلف
await call('GET', '/pay/return?id=pay_000002&message=DECLINED', { user: BUYER, expect: 402, raw: true });
check((await call('GET', '/wallet', { user: BUYER, expect: 200 })).balance === before, 'failed or mismatched payments credit nothing');
await call('GET', '/pay/return?id=pay_000001', { user: BUYER, expect: 200, raw: true });
check((await call('GET', '/wallet', { user: BUYER, expect: 200 })).balance === before + 15000, 'paid payment credited the wallet');
await call('POST', '/pay/webhook', { body: { type: 'payment_paid', data: { id: 'pay_000001' } }, user: BUYER, expect: 401 }); // بلا سر
const whBody = await app.inject({ method: 'POST', url: '/pay/webhook', headers: { 'content-type': 'application/json' }, payload: JSON.stringify({ type: 'payment_paid', secret_token: 'whsec', live: false, data: { id: 'pay_000001' } }) });
check(whBody.statusCode === 200 && whBody.json().ok === true && whBody.json().credited === false, 'webhook accepts the secret_token field as Moyasar sends it, and a paid payment is not credited twice');
const whBad = await app.inject({ method: 'POST', url: '/pay/webhook', headers: { 'content-type': 'application/json' }, payload: JSON.stringify({ type: 'payment_paid', secret_token: 'whsec-wrong', data: { id: 'pay_000001' } }) });
check(whBad.statusCode === 401, 'webhook rejects a wrong secret_token in the body');
const wh = await app.inject({ method: 'POST', url: '/pay/webhook', headers: { 'content-type': 'application/json', 'x-webhook-secret': 'whsec' }, payload: JSON.stringify({ type: 'payment_paid', data: { id: 'pay_000001' } }) });
check(wh.statusCode === 200 && wh.json().ok === true && wh.json().credited === false, 'webhook replay is idempotent (no double credit)');
check((await call('GET', '/wallet', { user: BUYER, expect: 200 })).balance === before + 15000, 'balance unchanged after replay');
const mine = await call('GET', '/pay/mine', { user: BUYER, expect: 200 }); check(mine.length === 1 && mine[0].status === 'paid' && mine[0].providerRef === 'pay_000001', 'my payments list');

// ---------- الصفحة المستضافة (الافتراضي بلا PAY_EMBED) ----------
delete process.env.PAY_EMBED;
const before2 = (await call('GET', '/wallet', { user: BUYER, expect: 200 })).balance;
const hp = await call('POST', '/pay/topup', { body: { amount: 2500 }, user: BUYER, expect: 200 });
check(hp.hosted === true && hp.checkoutUrl === 'https://invoice.moyasar.com/inv_000001?lang=ar' && invoices[0].amount === 2500 && invoices[0].currency === 'SAR' && invoices[0].callback_url.endsWith('/pay/return') && invoices[0].metadata.naslife_payment === hp.id && invoices[0].auth === 'Basic ' + Buffer.from('sk_test_y:').toString('base64'), 'hosted top-up creates a Moyasar invoice with our metadata and returns its page url');
check(invoices[0].success_url.endsWith(`/pay/return?p=${hp.id}`) && invoices[0].back_url.endsWith(`/pay/return?p=${hp.id}&back=1`) && /\/icons\/Icon-512\.png$/.test(invoices[0].logo_url), 'invoice carries success/back urls and our logo');
// الرجوع قبل الدفع → صفحة إلغاء بلا قيد
const backPage = await call('GET', `/pay/return?p=${hp.id}&back=1`, { user: BUYER, expect: 200, raw: true }); check(backPage.includes('أُلغيت عملية الدفع'), 'back_url before paying shows the cancelled page');
// success_url بلا معرّف دفعة → نسأل ميسر عن دفعات الفاتورة
invoicePayments.inv_000001 = [{ id: 'pay_000010', status: 'paid' }];
provider.pay_000010 = { id: 'pay_000010', status: 'paid', amount: 2500, currency: 'SAR', invoice_id: 'inv_000001', metadata: null, source: { type: 'creditcard', company: 'visa' } }; // بلا بياناتنا الوصفية
const okPage = await call('GET', `/pay/return?p=${hp.id}`, { user: BUYER, expect: 200, raw: true }); check(okPage.includes('تم شحن المحفظة'), 'success_url return settles through the invoice payments');
check((await call('GET', '/wallet', { user: BUYER, expect: 200 })).balance === before2 + 2500, 'invoice payment without metadata is matched by invoice id and credited');
await call('GET', '/pay/return?id=pay_000010', { user: BUYER, expect: 200, raw: true });
await call('GET', '/pay/return?id=pay_000010', { user: BUYER, expect: 200, raw: true });
check((await call('GET', '/wallet', { user: BUYER, expect: 200 })).balance === before2 + 2500, 'replay of the invoice payment credits nothing more');
rejectExtrasOnce = true;
const hp2 = await call('POST', '/pay/topup', { body: { amount: 3000 }, user: BUYER, expect: 200 }); check(hp2.hosted === true && invoices.at(-1).amount === 3000 && invoices.at(-1).success_url === undefined, 'when the provider rejects the optional fields the invoice is retried without them');
globalThis.naslifePayFetch = async () => { throw new Error('ECONNRESET'); };
await call('POST', '/pay/topup', { body: { amount: 2500 }, user: BUYER, expect: 502 });
globalThis.naslifePayFetch = async (url, init) => { if (url.endsWith('/invoices')) return { ok: false, status: 401, text: async () => 'unauthorized', json: async () => ({}) }; const id = url.split('/').pop(); const p = provider[id]; return { ok: !!p, status: p ? 200 : 404, json: async () => p }; };
check((await call('POST', '/pay/topup', { body: { amount: 2500 }, user: BUYER, expect: 502 })).error === 'provider-error', 'invoice creation failure is reported, nothing stored');
check((await call('GET', '/pay/mine', { user: BUYER, expect: 200 })).length === 3, 'failed invoice attempts leave no payment rows');
const adm = await call('GET', '/adminapi/payments', { user: ADMIN, expect: 200 }); check(adm.enabled === true && adm.source === 'env' && adm.items.length === 3 && adm.items[0].user?.nickname === 'khalid', 'admin payments list (env keys)');
const pc3 = await call('PUT', '/adminapi/payments/config', { body: { publishableKey: 'pk_live_abcdefgh12', secretKey: 'sk_live_abcdefgh34' }, user: ADMIN, expect: 200 }); check(pc3.source === 'panel' && pc3.mode === 'live' && pc3.envPresent === true, 'panel keys take precedence over env keys');
const pc4 = await call('PUT', '/adminapi/payments/config', { body: { publishableKey: '', secretKey: '' }, user: ADMIN, expect: 200 }); check(pc4.source === 'env' && pc4.mode === 'test' && pc4.enabled === true, 'clearing panel keys falls back to env keys');
check(notes.some((n) => n.kind === 'wallet' && n.ids.includes(BUYER)), 'buyer notified about the topup');

console.log(fails ? `\n${fails} FAILED` : '\nALL OK');
await app.close(); await pool.end(); process.exit(fails ? 1 : 0);
