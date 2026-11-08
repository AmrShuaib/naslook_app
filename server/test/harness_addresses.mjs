// دفتر العناوين وتوصيل السوق (بند 13 من نواقص الإطلاق، 7 نوفمبر 2026) على Postgres المحلي:
// الدفتر: الإنشاء والتحقق (الحي، النقطة، الجوال، الكلمات الممنوعة)، الافتراضي، الحد ١٠ (ومتوازياً)، الخصوصية (غيري لا يقرأ ولا يعدّل ولا يحذف)،
// ومسح عناوين الحساب المحذوف. التوصيل: رسم التوصيل وأقصى مسافة على العرض، الرسم في الإجمالي للمحفظة وللدفع عند الاستلام (والكوبون
// على البضاعة، والعمولة على الإجمالي ومنه الرسم فلا يُنقل السعر إلى الرسم)، فحص المسافة، نسخة العنوان على الطلب، من يراها (المشتري، البائع بعد القبول، المندوب ما دام مكلّفاً،
// الإدارة في النزاع)، الاسترداد بالرسم، الفاتورة، والكنس بعد ٣٠ يوماً ولحساب محذوف. الحزمة متينة أمام صفوف حزم أخرى في القاعدة نفسها.
import Fastify from 'fastify';
import pg from 'pg';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NODE_ENV = 'test';
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
const SELLER = 'SA0000851', BUYER = 'SA0000852', OTHER = 'SA0000853', RIDER = 'SA0000854', MINOR = 'SA0000855', ADMIN = 'SA0000856', FILLER = 'SA0000857', GONE = 'SA0000858', PLATFORM = 'SA0000000';
const OURS = [SELLER, BUYER, OTHER, RIDER, MINOR, ADMIN, FILLER, GONE];
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query('ALTER TABLE users ADD COLUMN IF NOT EXISTS is_admin BOOLEAN DEFAULT false');
await pool.query(`INSERT INTO users(id,nickname,created_at) VALUES('${SELLER}','adrseller',now()-interval '30 days'),('${BUYER}','adrbuyer',now()-interval '30 days'),('${OTHER}','adrother',now()-interval '30 days'),
  ('${RIDER}','adrrider',now()-interval '30 days'),('${MINOR}','adrminor',now()-interval '30 days'),('${ADMIN}','adradmin',now()-interval '30 days'),('${FILLER}','adrfiller',now()-interval '30 days'),
  ('${GONE}','adrgone',now()-interval '30 days'),('${PLATFORM}','naslife',now()-interval '60 days')
  ON CONFLICT (id) DO UPDATE SET nickname=EXCLUDED.nickname, created_at=EXCLUDED.created_at`);
await pool.query('UPDATE users SET is_admin = (id = $1) WHERE id = ANY($2)', [ADMIN, OURS]);
await pool.query("CREATE TABLE IF NOT EXISTS user_flags (user_id TEXT PRIMARY KEY, suspended BOOLEAN NOT NULL DEFAULT false, note TEXT, updated_at TIMESTAMPTZ DEFAULT now())");
await pool.query('DELETE FROM user_flags WHERE user_id = ANY($1)', [OURS]);
// صفوفنا فقط تُنظَّف (حزم أخرى قد تعمل على القاعدة نفسها)؛ الأعمدة الجديدة تضيفها الإضافات عند الإقلاع
for (const sql of ['DELETE FROM user_addresses WHERE user_id = ANY($1)', 'DELETE FROM market_orders WHERE buyer_id = ANY($1) OR seller_id = ANY($1)', 'DELETE FROM market_listings WHERE seller_id = ANY($1)',
  'DELETE FROM market_coupons WHERE seller_id = ANY($1)', 'DELETE FROM wallet_tx WHERE user_id = ANY($1)', 'DELETE FROM wallet_accounts WHERE user_id = ANY($1)', 'DELETE FROM account_deletions WHERE user_id = ANY($1)']) {
  try { await pool.query(sql, [OURS]); } catch { /* أول تشغيل: الجدول لم يُنشأ بعد */ }
}
await pool.query(`CREATE TABLE IF NOT EXISTS account_deletions (user_id TEXT PRIMARY KEY, status TEXT NOT NULL DEFAULT 'done', by_id TEXT NOT NULL, requested_at TIMESTAMPTZ NOT NULL DEFAULT now())`);

const notes = []; globalThis.naslifeNotify = async (ids, p) => { notes.push({ ids: [].concat(ids), ...p }); }; globalThis.naslifeNotifyAdmins = async (p) => { notes.push({ ids: ['admins'], ...p }); };
globalThis.naslifeSettings = { marketCommissionPct: 10, marketBlockContacts: true, maxTopup: 10000000 };
const adults = new Set([SELLER, BUYER, OTHER, RIDER, ADMIN, FILLER, GONE]);
globalThis.naslifeAdultOk = async (u) => adults.has(u);
globalThis.naslifeBlockedIds = async () => [];
globalThis.naslifeCheckText = (...t) => (t.some((x) => /ممنوعة/.test(String(x ?? ''))) ? 'ممنوعة' : null);
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
app.register((await import('../commerce.js')).default, { pool, auth });
app.register((await import('../market_plus.js')).default, { pool, auth });
app.register((await import('../market_b.js')).default, { pool, auth });
app.register((await import('../addresses.js')).default, { pool, auth });
await app.ready();
const { MAX_ADDRESSES, normalizePhone, addressInput } = await import('../addresses.js');

let fails = 0;
const call = async (method, url, { body, user = BUYER, expect, raw = false } = {}) => {
  const headers = user ? { 'x-user': user } : {};
  const r = await app.inject({ method, url, headers: { ...headers, ...(method === 'GET' ? {} : { 'content-type': 'application/json' }) }, payload: method === 'GET' ? undefined : JSON.stringify(body ?? {}) });
  let j; try { j = raw ? r.body : r.json(); } catch { j = r.body; }
  const ok = expect == null || r.statusCode === expect; if (!ok) fails++;
  console.log((ok ? 'OK  ' : 'FAIL') + ' ' + method + ' ' + url.slice(0, 64) + ' -> ' + r.statusCode + (ok ? '' : ' expected ' + expect) + ' ' + (typeof j === 'string' ? j.replace(/\s+/g, ' ').slice(0, 80) : JSON.stringify(j).slice(0, 150)));
  return j;
};
const check = (ok, m) => { if (!ok) fails++; console.log((ok ? 'OK  ' : 'FAIL') + ' ' + m); };
const row = async (id) => (await pool.query('SELECT * FROM market_orders WHERE id=$1', [id])).rows[0];
const balance = async (u) => Number((await pool.query('SELECT balance FROM wallet_accounts WHERE user_id=$1', [u])).rows[0]?.balance ?? 0);
const sweep = () => globalThis.naslifeMarketSweep();

// ================= الدفتر =================
check(normalizePhone('0551234567') === '+966551234567' && normalizePhone('+966 55 123 4567') === '+966551234567' && normalizePhone('٠٥٥١٢٣٤٥٦٧') === '+966551234567' && normalizePhone('0121234567') === null, 'phone normaliser: Saudi mobiles only');
check(addressInput({ label: 'البيت', district: 'الروضة', lat: 21 }).error === 'bad-point', 'a point needs both coordinates');
await call('GET', '/me/addresses', { user: null, expect: 401 });
await call('POST', '/me/addresses', { user: null, body: { label: 'البيت', district: 'الروضة' }, expect: 401 });
check((await call('GET', '/me/addresses', { expect: 200 })).items.length === 0, 'empty book');
check((await call('POST', '/me/addresses', { body: { label: '', district: 'الروضة' }, expect: 400 })).error === 'bad-label', 'label is required');
check((await call('POST', '/me/addresses', { body: { label: 'البيت', district: 'ر' }, expect: 400 })).error === 'bad-district', 'district is required');
check((await call('POST', '/me/addresses', { body: { label: 'البيت', district: 'الروضة', phone: '12345' }, expect: 400 })).error === 'bad-phone', 'phone must be a Saudi mobile');
check((await call('POST', '/me/addresses', { body: { label: 'البيت', district: 'الروضة', lat: 200, lng: 39 }, expect: 400 })).error === 'bad-point', 'point out of range');
check((await call('POST', '/me/addresses', { body: { label: 'البيت', district: 'حي ممنوعة' }, expect: 400 })).error === 'banned-words', 'banned words in the address');
check((await call('POST', '/me/addresses', { body: { label: 'البيت', district: 'الروضة', details: 'x'.repeat(201) }, expect: 400 })).error === 'bad-details', 'details are capped at 200');
// محارف التحكم: NUL يرفضه Postgres في TEXT (كان 500)؛ تُحذف، والتسمية التي لا يبقى منها شيء 400
check((await call('POST', '/me/addresses', { body: { label: '\u0000', district: 'الروضة' }, expect: 400 })).error === 'bad-label', 'a label of only NUL is refused, not a 500');
const ctl = await call('POST', '/me/addresses', { user: OTHER, body: { label: 'الب\u0000يت', district: 'الرو\u0007ضة', details: 'سطر\nثانٍ\u0000', city: 'جدة\u001f' }, expect: 200 });
check(ctl.label === 'البيت' && ctl.district === 'الروضة' && ctl.details === 'سطر ثانٍ' && ctl.city === 'جدة', 'control characters are stripped from every field (newline becomes a space)');
check((await call('PATCH', `/me/addresses/${ctl.id}`, { user: OTHER, body: { details: '\u0000\u0000' }, expect: 200 })).details === '', 'edit strips NUL too');
await call('DELETE', `/me/addresses/${ctl.id}`, { user: OTHER, expect: 200 });
// قرب البائع في جدة (الروضة) وبعيد في الدمام وبلا نقطة
const HOME = await call('POST', '/me/addresses', { body: { label: 'البيت', district: 'الروضة', details: 'شارع الأمير سلطان، عمارة ٣، الدور الثاني', city: 'جدة', lat: 21.55, lng: 39.16, phone: '0551234567' }, expect: 200 });
check(HOME.isDefault === true && HOME.phone === '+966551234567' && HOME.lat === 21.55 && HOME.city === 'جدة', 'first address is the default, phone normalised');
const FAR = await call('POST', '/me/addresses', { body: { label: 'العمل', district: 'الشاطئ', city: 'الدمام', lat: 26.43, lng: 50.1 }, expect: 200 });
check(FAR.isDefault === false && FAR.phone === null, 'second address is not the default');
const NOPT = await call('POST', '/me/addresses', { body: { label: 'بيت أهلي', district: 'الصفا', isDefault: true }, expect: 200 });
let book = await call('GET', '/me/addresses', { expect: 200 });
check(book.max === MAX_ADDRESSES && book.items.length === 3 && book.items[0].id === NOPT.id && book.items.filter((a) => a.isDefault).length === 1, 'isDefault moves the default; one default; default listed first');
const ed = await call('PATCH', `/me/addresses/${FAR.id}`, { body: { details: 'برج ٢', phone: '' }, expect: 200 });
check(ed.details === 'برج ٢' && ed.district === 'الشاطئ' && ed.lat === 26.43, 'partial edit keeps the other fields');
check((await call('PATCH', `/me/addresses/${FAR.id}`, { body: { lat: 1 }, expect: 400 })).error === 'bad-point', 'edit needs a full point');
check((await call('POST', `/me/addresses/${HOME.id}/default`, { expect: 200 })).isDefault === true, 'make default');
book = await call('GET', '/me/addresses', { expect: 200 });
check(book.items[0].id === HOME.id && book.items.filter((a) => a.isDefault).length === 1, 'default switched');
// الخصوصية: غيري لا يرى دفتري ولا يلمس عنواني
check((await call('GET', '/me/addresses', { user: OTHER, expect: 200 })).items.length === 0, 'another user sees an empty book');
await call('PATCH', `/me/addresses/${HOME.id}`, { user: OTHER, body: { district: 'السلامة' }, expect: 404 });
await call('DELETE', `/me/addresses/${HOME.id}`, { user: OTHER, expect: 404 });
await call('POST', `/me/addresses/${HOME.id}/default`, { user: OTHER, expect: 404 });
await call('PATCH', '/me/addresses/not-a-uuid', { expect: 404 });
check((await call('GET', '/me/addresses', { expect: 200 })).items.find((a) => a.id === HOME.id).district === 'الروضة', 'my address untouched by others');
check(await globalThis.naslifeAddressFor(OTHER, HOME.id) === null && (await globalThis.naslifeAddressFor(BUYER, HOME.id)).district === 'الروضة', 'naslifeAddressFor returns only my own address');
// الحد ١٠، ومتوازياً
for (let i = 0; i < 7; i++) await call('POST', '/me/addresses', { user: FILLER, body: { label: `عنوان ${i}`, district: 'النسيم' }, expect: 200 });
const burst = await Promise.all([0, 1, 2, 3, 4].map((i) => app.inject({ method: 'POST', url: '/me/addresses', headers: { 'x-user': FILLER, 'content-type': 'application/json' }, payload: JSON.stringify({ label: `متوازٍ ${i}`, district: 'النسيم' }) })));
const okN = burst.filter((r) => r.statusCode === 200).length, limN = burst.filter((r) => r.statusCode === 409 && r.json().error === 'address-limit' && r.json().max === 10).length;
check(okN === 3 && limN === 2, `parallel adds stop at the limit (${okN} added, ${limN} refused)`);
check((await call('GET', '/me/addresses', { user: FILLER, expect: 200 })).items.length === 10, 'ten addresses at most');
check((await call('POST', '/me/addresses', { user: FILLER, body: { label: 'زيادة', district: 'النسيم' }, expect: 409 })).error === 'address-limit', 'the eleventh is refused');
// حذف الافتراضي يرقّي غيره
const fl = (await call('GET', '/me/addresses', { user: FILLER })).items; const flDef = fl.find((a) => a.isDefault);
await call('DELETE', `/me/addresses/${flDef.id}`, { user: FILLER, expect: 200 });
const fl2 = (await call('GET', '/me/addresses', { user: FILLER })).items;
check(fl2.length === 9 && fl2.filter((a) => a.isDefault).length === 1 && !fl2.some((a) => a.id === flDef.id), 'deleting the default promotes another');

// ================= العرض: رسم التوصيل وأقصى مسافة =================
check((await call('POST', '/market', { user: SELLER, body: { title: 'رسم سالب', kind: 'product', category: 'food', price: 5000, delivery: true, deliveryFee: -1 }, expect: 400 })).error === 'bad-delivery-fee', 'negative fee refused');
check((await call('POST', '/market', { user: SELLER, body: { title: 'رسم ضخم', kind: 'product', category: 'food', price: 5000, delivery: true, deliveryFee: 100001 }, expect: 400 })).error === 'bad-delivery-fee', 'fee above 1000 SAR refused');
check((await call('POST', '/market', { user: SELLER, body: { title: 'مسافة غريبة', kind: 'product', category: 'food', price: 5000, delivery: true, deliveryMaxKm: 900 }, expect: 400 })).error === 'bad-delivery-km', 'max distance above 500 km refused');
check((await call('POST', '/market', { user: MINOR, body: { title: 'هدية مجانية', kind: 'product', category: 'gifts', price: 0, delivery: true, deliveryFee: 1500 }, expect: 403 })).error === 'adult-required', 'a delivery fee is selling for money: 18+');
const L = await call('POST', '/market', { user: SELLER, body: { title: 'كيكة الفانيلا', kind: 'product', category: 'food', price: 5000, stock: 30, delivery: true, deliveryFee: 1500, deliveryMaxKm: 20, placeName: 'الروضة', city: 'جدة', lat: 21.56, lng: 39.17, payOnReceipt: true }, expect: 200 });
check(L.deliveryFee === 1500 && L.deliveryMaxKm === 20 && L.delivery === true, 'listing carries fee and max distance');
const LP = await call('POST', '/market', { user: SELLER, body: { title: 'قهوة استلام فقط', kind: 'product', category: 'coffee', price: 3000, placeName: 'الروضة', lat: 21.56, lng: 39.17 }, expect: 200 });
check(LP.delivery === false && LP.deliveryFee === 0 && LP.deliveryMaxKm === null, 'defaults: no delivery, free, no limit');
const LF = await call('POST', '/market', { user: SELLER, body: { title: 'توصيل مجاني بلا موقع', kind: 'product', category: 'gifts', price: 2000, delivery: true }, expect: 200 });
check((await call('PATCH', `/market/${LF.id}`, { user: SELLER, body: { deliveryFee: 'abc' }, expect: 400 })).error === 'bad-delivery-fee', 'edit validates the fee');
// رقم أو نص رقمي فقط (Number(true)=1 كان يُحفظ رسماً بهللة واحدة)
check((await call('PATCH', `/market/${LF.id}`, { user: SELLER, body: { deliveryFee: true }, expect: 400 })).error === 'bad-delivery-fee', 'a boolean fee is refused');
check((await call('PATCH', `/market/${LF.id}`, { user: SELLER, body: { deliveryFee: [500] }, expect: 400 })).error === 'bad-delivery-fee', 'an array fee is refused');
check((await call('PATCH', `/market/${LF.id}`, { user: SELLER, body: { deliveryMaxKm: true }, expect: 400 })).error === 'bad-delivery-km', 'a boolean max distance is refused');
check((await call('POST', '/market', { user: SELLER, body: { title: 'رسم منطقي', kind: 'product', category: 'food', price: 5000, delivery: true, deliveryFee: false }, expect: 400 })).error === 'bad-delivery-fee', 'a boolean fee is refused on create');
check((await call('PATCH', `/market/${LF.id}`, { user: SELLER, body: { deliveryFee: '300', deliveryMaxKm: '12.5' }, expect: 200 })).deliveryMaxKm === 12.5, 'numeric strings still work');
check((await call('GET', `/market/${LF.id}`, { user: OTHER })).deliveryFee === 300, 'and the string fee is stored as a number');
check((await call('PATCH', `/market/${LF.id}`, { user: SELLER, body: { deliveryFee: 500, deliveryMaxKm: 0 }, expect: 200 })).deliveryFee === 500, 'edit sets the fee; 0 km = no limit');
check((await call('PATCH', `/market/${LF.id}`, { user: SELLER, body: { deliveryFee: 0 }, expect: 200 })).deliveryFee === 0, 'and back to free');
check((await call('GET', `/market/${L.id}`, { user: OTHER, expect: 200 })).deliveryFee === 1500, 'public listing shows the fee');

// ================= الطلب بالتوصيل =================
await call('POST', '/wallet/topup', { body: { amount: 100000 }, expect: 200 });
check((await call('POST', `/market/${LP.id}/order`, { body: { qty: 1, fulfilment: 'delivery', addressId: HOME.id }, expect: 400 })).error === 'delivery-unavailable', 'a pickup-only listing refuses delivery');
check((await call('POST', `/market/${L.id}/order`, { body: { qty: 1, fulfilment: 'delivery' }, expect: 400 })).error === 'address-required', 'delivery needs an address');
const otherAddr = await call('POST', '/me/addresses', { user: OTHER, body: { label: 'البيت', district: 'السلامة', lat: 21.58, lng: 39.15 }, expect: 200 });
check((await call('POST', `/market/${L.id}/order`, { body: { qty: 1, fulfilment: 'delivery', addressId: otherAddr.id }, expect: 400 })).error === 'address-not-found', "someone else's address cannot be used");
check((await call('POST', `/market/${L.id}/order`, { body: { qty: 1, fulfilment: 'delivery', addressId: 'zzzz' }, expect: 400 })).error === 'address-not-found', 'a malformed id is not found');
const far = await call('POST', `/market/${L.id}/order`, { body: { qty: 1, fulfilment: 'delivery', addressId: FAR.id }, expect: 400 });
check(far.error === 'too-far' && far.maxKm === 20 && far.km > 900, `distance check: Dammam is too far (${far.km} km)`);
check(await balance(BUYER) === 100000, 'nothing charged for refused orders');
// كوبون ١٠٪ على البضاعة فقط
await call('POST', '/market/coupons', { user: SELLER, body: { code: 'ADR10', percent: 10 }, expect: 200 });
const n0 = notes.length;
const W1 = await call('POST', `/market/${L.id}/order`, { body: { qty: 2, fulfilment: 'delivery', addressId: HOME.id, coupon: 'ADR10' }, expect: 200 });
// البضاعة ١٠٠٠٠ − خصم ١٠٠٠ = ٩٠٠٠ + رسم ١٥٠٠ = ١٠٥٠٠؛ العمولة ١٠٪ من الإجمالي ومنه الرسم = ١٠٥٠
check(W1.total === 10500 && W1.discount === 1000 && W1.commission === 1050 && W1.deliveryFee === 1500 && W1.fulfilment === 'delivery' && W1.deliveryKm > 0 && W1.deliveryKm < 3, `wallet total = goods − coupon + fee, commission on the whole total (${W1.total}/${W1.commission}/${W1.deliveryKm} km)`);
check(await balance(BUYER) === 100000 - 10500, 'wallet charged the fee too');
const nW = notes.slice(n0).find((n) => n.kind === 'market_order');
check(nW && /توصيل/.test(nW.body) && !/الروضة|سلطان|0551234567|\+966/.test(nW.body), 'seller notification mentions delivery but not the address');
const r1 = await row(W1.id);
check(r1.fulfilment === 'delivery' && Number(r1.delivery_fee) === 1500 && r1.delivery_address?.district === 'الروضة' && r1.delivery_address?.phone === '+966551234567' && r1.delivery_address?.id === undefined, 'snapshot stored on the order (no address id)');
// النسخة لا تتبع الدفتر
await call('PATCH', `/me/addresses/${HOME.id}`, { body: { details: 'تفاصيل جديدة' }, expect: 200 });
const bW = await call('GET', `/market/orders/${W1.id}`, { expect: 200 });
check(bW.address?.details === 'شارع الأمير سلطان، عمارة ٣، الدور الثاني' && bW.deliveryFee === 1500 && bW.fulfilment === 'delivery', 'buyer sees the snapshot as ordered, not the edited book');
const sW = await call('GET', `/market/orders/${W1.id}`, { user: SELLER, expect: 200 });
check(sW.address?.district === 'الروضة' && sW.address?.phone === '+966551234567' && sW.address?.lat === 21.55, 'seller sees the address on a paid wallet order');
await call('GET', `/market/orders/${W1.id}`, { user: OTHER, expect: 403 });
check(!JSON.stringify(await call('GET', `/market/${L.id}`, { user: OTHER })).includes('سلطان'), 'the listing never carries order addresses');
check(!JSON.stringify(await call('GET', '/market', { user: OTHER })).includes('سلطان'), 'nor the market search');
// الاستلام على عرض يوصّل: بلا رسم ولا عنوان
const P1 = await call('POST', `/market/${L.id}/order`, { body: { qty: 1 }, expect: 200 });
check(P1.total === 5000 && P1.deliveryFee === 0 && P1.fulfilment === 'pickup', 'pickup on a delivery listing: no fee');
check((await call('GET', `/market/orders/${P1.id}`, { user: SELLER })).address === null, 'pickup order has no address');
// نقطة غير معروفة: لا فحص مسافة
const N1 = await call('POST', `/market/${L.id}/order`, { body: { qty: 1, fulfilment: 'delivery', addressId: NOPT.id }, expect: 200 });
check(N1.deliveryKm === null && N1.total === 6500, 'address without a point: accepted, no distance');
// العرض بلا موقع: لا فحص مسافة ولو حُدّد العنوان بعيداً
await call('PATCH', `/market/${LF.id}`, { user: SELLER, body: { deliveryFee: 700, deliveryMaxKm: 5 }, expect: 200 });
const F1 = await call('POST', `/market/${LF.id}/order`, { body: { qty: 1, fulfilment: 'delivery', addressId: FAR.id }, expect: 200 });
check(F1.deliveryKm === null && F1.total === 2700, 'listing without a location: no distance check, fee applies');
// المندوب: يرى العنوان ما دام مكلّفاً والطلب لم يُسلَّم
await call('POST', `/market/orders/${W1.id}/stage`, { user: SELLER, body: { stage: 'preparing' }, expect: 200 });
await call('POST', `/market/orders/${W1.id}/courier`, { user: SELLER, body: { nickname: 'adrrider' }, expect: 200 });
const cW = await call('GET', `/market/orders/${W1.id}`, { user: RIDER, expect: 200 });
check(cW.mineAsCourier === true && cW.address?.district === 'الروضة' && cW.code == null, 'assigned courier sees the address (and not the code)');
check((await call('GET', '/market/orders', { user: RIDER, expect: 200 })).find((o) => o.id === W1.id)?.address?.district === 'الروضة', 'courier list carries it too');
check(!notes.filter((n) => n.kind === 'market_courier' && n.ids.includes(RIDER)).some((n) => /الروضة|سلطان/.test(n.body)), 'courier notification has no address');
await call('DELETE', `/market/orders/${W1.id}/courier`, { user: SELLER, expect: 200 });
await call('GET', `/market/orders/${W1.id}`, { user: RIDER, expect: 403 });
await call('POST', `/market/orders/${W1.id}/courier`, { user: SELLER, body: { nickname: 'adrrider' }, expect: 200 });
await call('POST', `/market/orders/${W1.id}/stage`, { user: RIDER, body: { stage: 'on_the_way' }, expect: 200 });
check((await call('GET', `/market/orders/${W1.id}`, { user: RIDER })).address?.district === 'الروضة', 'courier still sees it on the way');
await call('POST', `/market/orders/${W1.id}/stage`, { user: RIDER, body: { stage: 'delivered' }, expect: 200 });
check((await call('GET', `/market/orders/${W1.id}`, { user: RIDER, expect: 200 })).address === null, 'after delivery the courier no longer sees the address');
// الاكتمال: البائع يستلم الإجمالي ناقص العمولة (الرسم كاملاً)، ولا يرى العنوان بعدها
const sBefore = await balance(SELLER);
await call('POST', `/market/orders/${W1.id}/confirm`, { expect: 200 });
check(await balance(SELLER) - sBefore === 10500 - 1050, 'seller receives the total − commission (the fee pays commission like the goods)');
check((await call('GET', `/market/orders/${W1.id}`, { user: SELLER })).address === null, 'seller no longer sees the address after completion');
check((await call('GET', `/market/orders/${W1.id}`)).address?.district === 'الروضة', 'buyer still sees it');
// الإلغاء يرد الرسم مع البضاعة
const bBefore = await balance(BUYER);
await call('POST', `/market/orders/${N1.id}/cancel`, { expect: 200 });
check(await balance(BUYER) - bBefore === 6500, 'cancel refunds the fee too');
// السعر لا يُنقل إلى الرسم: عرض بصفر ورسم ٢٠٠ ر.س (توصيل فقط) يدفع العمولة على الرسم، وكان يدفع صفراً
const LZ = await call('POST', '/market', { user: SELLER, body: { title: 'سعر في الرسم', kind: 'product', category: 'gifts', price: 0, delivery: true, deliveryFee: 20000 }, expect: 200 });
const Z1 = await call('POST', `/market/${LZ.id}/order`, { body: { qty: 1, fulfilment: 'delivery', addressId: HOME.id }, expect: 200 });
check(Z1.total === 20000 && Z1.commission === 2000, `a zero price with a 200 SAR fee pays commission on the fee (${Z1.total}/${Z1.commission})`);
const zBefore = await balance(SELLER);
await call('POST', `/market/orders/${Z1.id}/confirm`, { expect: 200 });
check(await balance(SELLER) - zBefore === 18000, 'seller receives the fee less commission');
// الإدارة: العنوان في النزاع فقط
const D1 = await call('POST', `/market/${L.id}/order`, { body: { qty: 1, fulfilment: 'delivery', addressId: HOME.id }, expect: 200 });
check((await call('GET', `/market/orders/${D1.id}`, { user: ADMIN, expect: 200 })).address === null, 'admin does not see the address of an ordinary order');
await call('POST', `/market/orders/${D1.id}/dispute`, { body: { reason: 'لم يصل الطلب أبداً' }, expect: 200 });
check((await call('GET', `/market/orders/${D1.id}`, { user: ADMIN, expect: 200 })).address?.district === 'الروضة', 'admin sees it to settle a dispute');
check((await call('GET', `/market/orders/${D1.id}`, { user: SELLER, expect: 200 })).address?.district === 'الروضة', 'seller keeps it during the dispute');
// الفاتورة: سطر التوصيل، وسطر البند بقيمة البضاعة
const inv = await call('GET', `/market/orders/${W1.id}/invoice`, { raw: true, expect: 200 });
check(/التوصيل<\/td><td><\/td><td>15 ر\.س/.test(inv) && /<td>2<\/td><td>100 ر\.س<\/td>/.test(inv) && /105 ر\.س/.test(inv), 'invoice: item 100, delivery 15, total 105');

// ================= الدفع عند الاستلام بالتوصيل =================
const C1 = await call('POST', `/market/${L.id}/order`, { body: { qty: 1, payment: 'cod', fulfilment: 'delivery', addressId: HOME.id }, expect: 200 });
check(C1.payment === 'cod' && C1.total === 6500 && C1.commission === 0 && C1.status === 'requested', 'pay on receipt: total includes the fee, no commission');
check((await call('GET', `/market/orders/${C1.id}`, { user: SELLER })).address === null, 'seller does not see the address before accepting');
check((await call('GET', '/market/orders', { user: SELLER })).find((o) => o.id === C1.id)?.address === null, 'nor in the list');
check((await call('GET', `/market/orders/${C1.id}`)).address?.district === 'الروضة', 'buyer sees it');
const nCod = [...notes].reverse().find((n) => n.kind === 'market_cod_order' && n.data?.orderId === C1.id);
check(nCod && /65 ر\.س/.test(nCod.body) && !/الروضة|سلطان/.test(nCod.body), 'cod notification shows the total with fee, no address');
await call('POST', `/market/orders/${C1.id}/accept`, { user: SELLER, expect: 200 });
const sC = await call('GET', `/market/orders/${C1.id}`, { user: SELLER });
check(sC.address?.district === 'الروضة' && sC.deliveryFee === 1500 && sC.total === 6500, 'after acceptance the seller sees the address');
const nAcc = [...notes].reverse().find((n) => n.kind === 'market_cod_accepted' && n.data?.orderId === C1.id);
check(nAcc && /65 ر\.س/.test(nAcc.body), 'buyer is told to pay the total with the fee');
// اعتذار قبل القبول: لا يرى البائع العنوان أبداً
const C2 = await call('POST', `/market/${L.id}/order`, { body: { qty: 1, payment: 'cod', fulfilment: 'delivery', addressId: HOME.id }, expect: 200 });
await call('POST', `/market/orders/${C2.id}/decline`, { user: SELLER, expect: 200 });
check((await call('GET', `/market/orders/${C2.id}`, { user: SELLER })).address === null, 'declined pay-on-receipt order: seller never saw the address');
await call('POST', `/market/orders/${C1.id}/cash-received`, { user: SELLER, expect: 200 });

// ================= الكنس: ٣٠ يوماً بعد الانتهاء =================
await pool.query("UPDATE market_orders SET completed_at=now() - interval '31 days', updated_at=now() - interval '31 days' WHERE id=$1", [W1.id]);
await pool.query("UPDATE market_orders SET completed_at=now() - interval '10 days', updated_at=now() - interval '10 days' WHERE id=$1", [C1.id]);
await pool.query("UPDATE market_orders SET updated_at=now() - interval '40 days' WHERE id=$1", [C2.id]);
const upBefore = (await row(W1.id)).updated_at.getTime();
await sweep();
const w1 = await row(W1.id), c1 = await row(C1.id), c2 = await row(C2.id), d1 = await row(D1.id);
check(w1.delivery_address === null && w1.address_purged_at != null && w1.updated_at.getTime() === upBefore && Number(w1.delivery_fee) === 1500 && w1.delivery_km != null, 'completed 31 days ago: address purged, fee and distance kept, updated_at untouched');
check(c1.delivery_address?.district === 'الروضة', 'completed 10 days ago: kept');
check(c2.delivery_address === null, 'cancelled 40 days ago: purged');
check(d1.delivery_address?.district === 'الروضة', 'an open dispute keeps its address');
const bP = await call('GET', `/market/orders/${W1.id}`);
check(bP.address === null && bP.addressPurged === true && bP.deliveryFee === 1500, 'buyer sees «address removed»');
// حساب محذوف: نسخ طلباته المنتهية تُمحى فوراً، وعناوين دفتره تُحذف
await call('POST', '/wallet/topup', { user: GONE, body: { amount: 20000 }, expect: 200 });
const ga = await call('POST', '/me/addresses', { user: GONE, body: { label: 'البيت', district: 'المروة', lat: 21.6, lng: 39.2 }, expect: 200 });
const G1 = await call('POST', `/market/${L.id}/order`, { user: GONE, body: { qty: 1, fulfilment: 'delivery', addressId: ga.id }, expect: 200 });
const G2 = await call('POST', `/market/${L.id}/order`, { user: GONE, body: { qty: 1, fulfilment: 'delivery', addressId: ga.id }, expect: 200 });
await call('POST', `/market/orders/${G1.id}/confirm`, { user: GONE, expect: 200 });
await pool.query("INSERT INTO account_deletions(user_id, status, by_id) VALUES($1,'done',$1) ON CONFLICT (user_id) DO NOTHING", [GONE]);
await sweep();
check((await row(G1.id)).delivery_address === null && (await row(G2.id)).delivery_address?.district === 'المروة', 'deleted buyer: finished order purged at once, an open one kept for delivery');
const removed = await globalThis.naslifeAddressesSweep();
check(removed >= 1 && (await pool.query('SELECT count(*)::int AS n FROM user_addresses WHERE user_id=$1', [GONE])).rows[0].n === 0, 'address book of a deleted account is wiped');
check((await pool.query('SELECT count(*)::int AS n FROM user_addresses WHERE user_id=$1', [BUYER])).rows[0].n === 3, 'other books untouched');

// الطلبات القديمة (بلا fulfilment) تبقى استلاماً كما كانت
check((await call('GET', `/market/orders/${P1.id}`)).fulfilment === 'pickup', 'orders without fulfilment are pickup');
// حذف العنوان من الدفتر لا يمس الطلب القائم
await call('DELETE', `/me/addresses/${HOME.id}`, { expect: 200 });
check((await call('GET', `/market/orders/${D1.id}`)).address?.district === 'الروضة', 'deleting the address from the book keeps the order snapshot');
check(!(await call('GET', '/me/addresses')).items.some((a) => a.id === HOME.id), 'and it is gone from the book');

console.log(fails ? `\n${fails} FAILED` : '\nALL ADDRESS TESTS OK');
await app.close(); await pool.end();
process.exit(fails ? 1 : 0);
