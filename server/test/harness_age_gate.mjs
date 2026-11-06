// إقرار العمر وبيانات المنشأة (5 نوفمبر 2026): legal_pages.js (POST /me/adult-attest، حالة الإقرار في GET /legal/consent، صف age13
// مع كل موافقة، naslifeAdultOk)، وبوابة 18+ في مسارات المال: الشحن التجريبي وبالبطاقة، التحويل، طلب السوق المدفوع، طلب الدائرة المدفوع،
// التذكرة المدفوعة، حجز الفندق، وعرض السوق المسعّر والفعالية المسعّرة، وشراء سبوت لايت ودفع طلب المحادثة (رصيد دخل بلا فحص)؛
// المجاني مفتوح، وغياب المساعد أو خطؤه يفتح ولا يحجب.
// وبيانات المنشأة: تحقق admin.js من الصيغ، /settings/public و/legal/version، التذييل وقسم «من نحن» في الصفحات الثلاث، ورقم الكيان
// للدائرة الموثقة فقط في bizOut. وسياسة الخصوصية: قسم الذكاء الاصطناعي الدقيق وتاريخ التحديث دون رفع النسخة.
import Fastify from 'fastify';
import pg from 'pg';
import { LEGAL_VERSION, LEGAL_UPDATED_AR } from '../legal_content.js';
import { COMPANY_CR_RE as L_CR, COMPANY_VAT_RE as L_VAT, AGE_DOC, ADULT_DOC } from '../legal_pages.js';
import { COMPANY_CR_RE as A_CR, COMPANY_VAT_RE as A_VAT } from '../admin.js';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0'; process.env.NODE_ENV = 'test';
process.env.MOYASAR_PUBLISHABLE_KEY = 'pk_test_agegate000001'; process.env.MOYASAR_SECRET_KEY = 'sk_test_agegate000002';
process.env.LITEAPI_KEY = 'sand_agegate0123456789'; process.env.LITEAPI_ENV = 'test';
delete process.env.PAY_MIN; delete process.env.PAY_MAX; delete process.env.PAY_EMBED;
let fails = 0;
const check = (c, l, extra = '') => { if (!c) fails++; console.log((c ? 'OK  ' : 'FAIL') + ' ' + l + (extra ? ' ' + extra : '')); };
const ADULT = 'SA0000501', MINOR = 'SA0000502', SELLER = 'SA0000503', ADMIN = 'SA0000504';
const OURS = [ADULT, MINOR, SELLER, ADMIN];
const SETTINGS = ['testTopup', 'transfersEnabled', 'chatPaymentsEnabled', 'companyCr', 'companyVat', 'companyAddress', 'minTopup', 'maxCardTopup'];

const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query(`INSERT INTO users(id,nickname) VALUES('${ADULT}','agead'),('${MINOR}','ageminor'),('${SELLER}','ageseller'),('${ADMIN}','ageadmin') ON CONFLICT (id) DO UPDATE SET nickname=EXCLUDED.nickname`);
// القاعدة مشتركة بين الحزم: نبدأ نظيفين لمستخدمينا وإعداداتنا
for (const [sql, args] of [
  ['DELETE FROM legal_consents WHERE user_id = ANY($1)', [OURS]], ['DELETE FROM platform_settings WHERE key = ANY($1)', [SETTINGS]], ['DELETE FROM admins WHERE user_id = ANY($1)', [OURS]],
  ['DELETE FROM wallet_tx WHERE user_id = ANY($1)', [OURS]], ['DELETE FROM wallet_accounts WHERE user_id = ANY($1)', [OURS]], ['DELETE FROM payments WHERE user_id = ANY($1)', [OURS]],
  ['DELETE FROM market_orders WHERE buyer_id = ANY($1)', [OURS]], ['DELETE FROM market_spotlight WHERE seller_id = ANY($1)', [OURS]], ['DELETE FROM market_listings WHERE seller_id = ANY($1)', [OURS]], ['DELETE FROM events WHERE host_id = ANY($1)', [OURS]],
  ["DELETE FROM chat_requests WHERE message_id LIKE 'age-%'", []],
  ["DELETE FROM biz_items WHERE id LIKE 'age-%'", []], ["DELETE FROM biz WHERE id LIKE 'age-%'", []], ['DELETE FROM hotel_settings', []], ["DELETE FROM biz_hotel_links WHERE biz_id LIKE 'age-%'", []],
]) { try { await pool.query(sql, args); } catch { /* أول تشغيل */ } }
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
const dir = new URL('.', import.meta.url).pathname;
app.register((await import('../notify.js')).default, { pool, auth, pollMs: 3600000, opsDir: dir + 'ops' });
app.register((await import('../commerce.js')).default, { pool, auth });
app.register((await import('../business.js')).default, { pool, auth });
app.register((await import('../admin.js')).default, { pool, auth, webappDir: dir + 'webapp', opsDir: dir + 'ops' });
app.register((await import('../market_plus.js')).default, { pool, auth });
app.register((await import('../market_b.js')).default, { pool, auth });
app.register((await import('../legal_pages.js')).default, { pool, auth });
app.register((await import('../hotels.js')).default, { pool, auth });
app.register((await import('../chat_cards.js')).default, { pool, auth });
await app.ready(); await new Promise((r) => setTimeout(r, 300));
await pool.query("INSERT INTO admins(user_id,granted_by) VALUES($1,'test') ON CONFLICT DO NOTHING", [ADMIN]);
const call = async (method, url, { body = {}, user = ADULT, expect, headers = {} } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json', host: 'naslife.app', ...headers }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url.slice(0, 80)} [${user ?? 'guest'}] -> ${r.statusCode}`, r.statusCode === expect ? '' : JSON.stringify(j).slice(0, 200));
  return { code: r.statusCode, json: j, body: r.body };
};
const adultReq = (r, label) => check(r.code === 403 && r.json?.error === 'adult-required', `${label} → 403 adult-required`, r.code === 403 ? '' : `${r.code} ${JSON.stringify(r.json).slice(0, 160)}`);
const html = async (path) => (await app.inject({ method: 'GET', url: path })).body;

// ---- الإعداد: الشحن التجريبي والتحويل مفعّلان من اللوحة (المسارات نفسها تُختبر)
let s = await call('POST', '/adminapi/settings', { body: { testTopup: true, transfersEnabled: true, chatPaymentsEnabled: true }, user: ADMIN, expect: 200 });
check(s.json.testTopup === true && s.json.transfersEnabled === true && s.json.chatPaymentsEnabled === true, 'admin enabled test top-up, transfers and chat payments for the run');

// ================================================================ الإقرار والحالة
check(LEGAL_VERSION === '2026-09-25', 'consent version unchanged (clarifying update, no re-consent)');
let c = await call('GET', '/legal/consent', { user: MINOR, expect: 200 });
check(c.json.needs === true && c.json.adult === false && c.json.adultAt === null, 'fresh account: consent needed, not attested', JSON.stringify(c.json));
await call('GET', '/legal/consent', { user: null, expect: 401 });
await call('POST', '/me/adult-attest', { user: null, body: { confirm: true }, expect: 401 });
let e = await call('POST', '/me/adult-attest', { user: ADULT, body: {}, expect: 400 }); check(e.json.error === 'confirm-required', 'attest needs confirm:true');
e = await call('POST', '/me/adult-attest', { user: ADULT, body: { confirm: 'yes' }, expect: 400 }); check(e.json.error === 'confirm-required', 'confirm must be the boolean true');
check(!(await globalThis.naslifeAdultOk(ADULT)), 'helper: not attested before the call');
let a = await call('POST', '/me/adult-attest', { user: ADULT, body: { confirm: true, source: 'web' }, expect: 200 });
check(a.json.ok && a.json.adult === true && typeof a.json.adultAt === 'string', 'attested', JSON.stringify(a.json));
const firstAt = a.json.adultAt;
a = await call('POST', '/me/adult-attest', { user: ADULT, body: { confirm: true }, expect: 200 });
check(a.json.adultAt === firstAt, 'repeat attest keeps the first date (idempotent)');
let rows = (await pool.query('SELECT doc, version, source FROM legal_consents WHERE user_id=$1', [ADULT])).rows;
check(rows.length === 1 && rows[0].doc === ADULT_DOC && rows[0].version === '1' && rows[0].source === 'web', 'stored once as a legal_consents row (adult18 v1, source kept)', JSON.stringify(rows));
c = await call('GET', '/legal/consent', { user: ADULT, expect: 200 });
check(c.json.adult === true && c.json.adultAt === firstAt && c.json.needs === true, 'consent state exposes the attestation; adult row does not count as terms consent', JSON.stringify(c.json));
check(await globalThis.naslifeAdultOk(ADULT) && !(await globalThis.naslifeAdultOk(MINOR)) && !(await globalThis.naslifeAdultOk('')), 'helper: attested / not attested / empty id');
await call('POST', '/me/adult-attest', { user: SELLER, body: { confirm: true }, expect: 200 });

// موافقة الشروط تحفظ معها إقرار 13+ (نص المربع والورقة يتضمنه)، و«needs» يعدّ الوثيقتين فقط
await call('POST', '/legal/consent', { user: MINOR, body: { version: LEGAL_VERSION, source: 'ios' }, expect: 200 });
rows = (await pool.query('SELECT doc FROM legal_consents WHERE user_id=$1 AND version=$2 ORDER BY doc', [MINOR, LEGAL_VERSION])).rows.map((r) => r.doc);
check(JSON.stringify(rows) === JSON.stringify([AGE_DOC, 'privacy', 'terms']), 'consent records terms, privacy and the 13+ declaration', JSON.stringify(rows));
c = await call('GET', '/legal/consent', { user: MINOR, expect: 200 });
check(c.json.needs === false && c.json.adult === false, 'after consent: not needed, still not 18+ attested');
check(await globalThis.naslifeLegalConsent(ADMIN, 'register') === true && (await pool.query('SELECT count(*)::int AS n FROM legal_consents WHERE user_id=$1 AND doc=$2', [ADMIN, AGE_DOC])).rows[0].n === 1, 'registration consent (auth_alias hook) records age13 too');

// ================================================================ بوابة المال
// الشحن التجريبي
adultReq(await call('POST', '/wallet/topup', { user: MINOR, body: { amount: 500000 } }), 'test top-up without attestation');
check(Number((await call('GET', '/wallet', { user: MINOR })).json.balance) === 0, 'nothing credited');
await call('POST', '/wallet/topup', { user: ADULT, body: { amount: 500000 }, expect: 200 });
check(Number((await call('GET', '/wallet', { user: ADULT })).json.balance) === 500000, 'attested user tops up');
// شحن البطاقة: لا نداء لميسر قبل الإقرار
let payCalls = 0;
globalThis.naslifePayFetch = async (url) => { payCalls++; return { ok: true, status: 201, json: async () => ({ id: 'inv_age_' + payCalls, url: 'https://checkout.moyasar.com/invoices/inv_age_' + payCalls }) }; };
adultReq(await call('POST', '/pay/topup', { user: MINOR, body: { amount: 15000 } }), 'card top-up without attestation');
check(payCalls === 0 && (await pool.query('SELECT count(*)::int AS n FROM payments WHERE user_id=$1', [MINOR])).rows[0].n === 0, 'no invoice created and no payment row');
let p = await call('POST', '/pay/topup', { user: ADULT, body: { amount: 15000 }, expect: 200 });
check(p.json.hosted === true && payCalls === 1, 'attested user gets a hosted invoice');
// التحويل
adultReq(await call('POST', '/wallet/transfer', { user: MINOR, body: { to: ADULT, amount: 100 } }), 'transfer without attestation');
await call('POST', '/wallet/transfer', { user: ADULT, body: { to: SELLER, amount: 100 }, expect: 200 });

// السوق: البيع المسعّر يحتاج الإقرار، والمجاني مفتوح
adultReq(await call('POST', '/market', { user: MINOR, body: { kind: 'product', category: 'other', title: 'دراجة للبيع', price: 5000 } }), 'priced listing without attestation');
adultReq(await call('POST', '/market', { user: MINOR, body: { kind: 'product', category: 'other', title: 'قميص بخيارات', price: 0, variants: [{ name: 'كبير', price: 3000 }] } }), 'free base price with a priced variant');
const freeL = await call('POST', '/market', { user: MINOR, body: { kind: 'product', category: 'other', title: 'كتب مجانية', price: 0 }, expect: 200 });
adultReq(await call('PATCH', `/market/${freeL.json.id}`, { user: MINOR, body: { price: 2000 } }), 'turning a free listing into a priced one');
await call('PATCH', `/market/${freeL.json.id}`, { user: MINOR, body: { title: 'كتب مجانية للجميع' }, expect: 200 });
const paidL = await call('POST', '/market', { user: SELLER, body: { kind: 'product', category: 'other', title: 'سماعة جديدة', price: 2500 }, expect: 200 });
const sellerFree = await call('POST', '/market', { user: SELLER, body: { kind: 'product', category: 'other', title: 'نشرة مجانية', price: 0 }, expect: 200 });
// الشراء: المدفوع يحتاج الإقرار (ولا خصم ولا طلب)، والمجاني مفتوح
adultReq(await call('POST', `/market/${paidL.json.id}/order`, { user: MINOR, body: { qty: 1 } }), 'paid market order without attestation');
check((await pool.query('SELECT count(*)::int AS n FROM market_orders WHERE buyer_id=$1', [MINOR])).rows[0].n === 0, 'no order row for the blocked buyer');
await call('POST', `/market/${sellerFree.json.id}/order`, { user: MINOR, body: { qty: 1 }, expect: 200 });
await call('POST', `/market/${paidL.json.id}/order`, { user: ADULT, body: { qty: 1 }, expect: 200 });

// الفعاليات: الفئة المسعّرة تحتاج إقرار المضيف، والتذكرة المسعّرة إقرار المشتري
const when = new Date(Date.now() + 3 * 86400000).toISOString();
adultReq(await call('POST', '/events', { user: MINOR, body: { title: 'أمسية', startsAt: when, placeName: 'الكورنيش', tiers: [{ name: 'عادي', price: 1000, quantity: 10 }] } }), 'event with a paid tier without attestation');
const freeEv = await call('POST', '/events', { user: MINOR, body: { title: 'لقاء مجاني', startsAt: when, placeName: 'الحديقة', tiers: [{ name: 'دخول', price: 0, quantity: 10 }] }, expect: 200 });
const ev = await call('POST', '/events', { user: SELLER, body: { title: 'حفلة', startsAt: when, placeName: 'المسرح', tiers: [{ name: 'عادي', price: 1500, quantity: 10 }, { name: 'مجانية', price: 0, quantity: 10 }] }, expect: 200 });
const paidTier = ev.json.tiers.find((t) => t.price > 0), freeTier = ev.json.tiers.find((t) => t.price === 0);
adultReq(await call('POST', `/events/${ev.json.id}/tickets`, { user: MINOR, body: { tierId: paidTier.id, qty: 1 } }), 'paid ticket without attestation');
await call('POST', `/events/${ev.json.id}/tickets`, { user: MINOR, body: { tierId: freeTier.id, qty: 1 }, expect: 200 });
await call('POST', `/events/${freeEv.json.id}/tickets`, { user: ADULT, body: { tierId: freeEv.json.tiers[0].id, qty: 1 }, expect: 200 });
await call('POST', `/events/${ev.json.id}/tickets`, { user: ADULT, body: { tierId: paidTier.id, qty: 1 }, expect: 200 });

// الدوائر: الطلب المدفوع يحتاج الإقرار، والصنف المجاني مفتوح؛ ورقم الكيان للعامة بعد الاعتماد فقط
await pool.query(`INSERT INTO biz(id,name,name_ar,category,lat,lng,owner_id,verified,verification,entity_kind,entity_number) VALUES
  ('age-shop','Age Shop','متجر العمر','shop',21.5,39.2,$1,true,'{"status":"approved"}','cr','4030111222'),
  ('age-pend','Age Pending','متجر قيد التوثيق','shop',21.5,39.2,$1,false,'{"status":"pending"}','freelance','FL20259999'),
  ('age-free','Age Freelance','مستقل موثق','services',21.5,39.2,$1,true,'{"status":"approved"}','freelance','FL20250077')`, [SELLER]);
await pool.query(`INSERT INTO biz_items(id,biz_id,kind,title,price) VALUES('age-paid','age-shop','product','حقيبة',2500),('age-gift','age-shop','product','هدية',0)`);
adultReq(await call('POST', '/biz/age-shop/orders', { user: MINOR, body: { itemId: 'age-paid', qty: 1 } }), 'paid circle order without attestation');
await call('POST', '/biz/age-shop/orders', { user: MINOR, body: { itemId: 'age-gift', qty: 1 }, expect: 200 });
await call('POST', '/biz/age-shop/orders', { user: ADULT, body: { itemId: 'age-paid', qty: 1 }, expect: 200 });
let pub = (await call('GET', '/biz/age-shop', { user: MINOR, expect: 200 })).json;
check(pub.entity?.kind === 'cr' && pub.entity.number === '4030111222' && !('docUrl' in pub), 'approved circle shows its commercial registration publicly', JSON.stringify(pub.entity));
pub = (await call('GET', '/biz/age-free', { user: null, expect: 200 })).json;
check(pub.entity?.kind === 'freelance' && pub.entity.number === 'FL20250077', 'approved freelancer shows the freelance document number (guest too)');
pub = (await call('GET', '/biz/age-pend', { user: MINOR, expect: 200 })).json;
check(pub.entity === null && !JSON.stringify(pub).includes('FL20259999'), 'pending circle never exposes its number');
const lst = (await call('GET', '/biz?q=' + encodeURIComponent('متجر العمر'), { user: null, expect: 200 })).json;
check(Array.isArray(lst) && lst.some((b) => b.id === 'age-shop' && b.entity?.number === '4030111222'), 'list output carries the approved entity too');

// الفندق: لا نداء للمزوّد قبل الإقرار
await pool.query("INSERT INTO biz(id,name,name_ar,category,lat,lng,owner_id) VALUES('age-hotel','Age Hotel','فندق العمر','hotel',21.5,39.2,$1)", [SELLER]);
await pool.query("INSERT INTO biz_hotel_links(biz_id,hotel_id,hotel_name) VALUES('age-hotel','lpAGE1','Age Hotel')");
let hotelCalls = 0;
globalThis.naslifeHotelFetch = async () => { hotelCalls++; return { ok: false, status: 400, json: async () => ({ error: { code: 4000, message: 'offer not found' } }) }; };
const guest = { firstName: 'Sara', lastName: 'Ali', phone: '+966501234567', email: 'sara@example.com' };
adultReq(await call('POST', '/biz/age-hotel/hotel/book', { user: MINOR, body: { offerId: 'OFF1', guest } }), 'hotel booking without attestation');
check(hotelCalls === 0, 'the provider is never called for an unattested booking');
e = await call('POST', '/biz/age-hotel/hotel/book', { user: ADULT, body: { offerId: 'OFF1', guest }, expect: 409 });
check(hotelCalls === 1 && e.json.error === 'offer-unavailable', 'attested user passes the gate (provider reached)');

// رصيد دخل المحفظة بلا فحص (تحويل وارد، وكذلك دخل مبيعات الدائرة والاسترداد والرصيد التجريبي القديم) لا يُنفق قبل الإقرار
await call('POST', '/wallet/transfer', { user: ADULT, body: { to: MINOR, amount: 10000 }, expect: 200 });
const minorBal = async () => Number((await call('GET', '/wallet', { user: MINOR })).json.balance);
check(await minorBal() === 10000, 'unattested user received an incoming transfer (no gate on receiving)');
// سبوت لايت على عرض مجاني: لم يمر البائع ببوابة البيع، والخصم من محفظته
adultReq(await call('POST', `/market/${freeL.json.id}/spotlight`, { user: MINOR, body: { days: 1 } }), 'spotlight purchase without attestation');
check(await minorBal() === 10000 && (await pool.query('SELECT count(*)::int AS n FROM market_spotlight WHERE seller_id=$1', [MINOR])).rows[0].n === 0, 'no debit and no spotlight row for the blocked seller');
const spot = await call('POST', `/market/${sellerFree.json.id}/spotlight`, { user: SELLER, body: { days: 1 }, expect: 200 });
check(spot.json.paid > 0, 'attested seller buys spotlight on a free listing', JSON.stringify(spot.json));
// دفع طلب مبلغ في المحادثة: يستدعي transfer() مباشرة لا مسار /wallet/transfer
await call('POST', '/chat/requests', { user: SELLER, body: { messageId: 'age-req-minor', peerId: MINOR, kind: 'pay', amount: 3000, note: 'قهوة' }, expect: 200 });
adultReq(await call('POST', '/chat/requests/age-req-minor/pay', { user: MINOR }), 'chat request payment without attestation');
const reqRow = (await pool.query("SELECT status FROM chat_requests WHERE message_id='age-req-minor'")).rows[0];
check(await minorBal() === 10000 && reqRow?.status === 'pending', 'no transfer and the request stays pending', JSON.stringify(reqRow));
await call('POST', '/chat/requests', { user: SELLER, body: { messageId: 'age-req-adult', peerId: ADULT, kind: 'pay', amount: 3000 }, expect: 200 });
const paid = await call('POST', '/chat/requests/age-req-adult/pay', { user: ADULT, expect: 200 });
check(paid.json.request?.status === 'paid', 'attested user pays the chat request');

// iOS: الشحن يبقى مرفوضاً بـ unavailable قبل أي فحص عمر (الإخفاء القائم لا يتغير)
{ const r = await app.inject({ method: 'POST', url: '/pay/topup', headers: { 'x-user': MINOR, 'content-type': 'application/json', 'x-naslife-client': 'ios/1.0' }, payload: JSON.stringify({ amount: 15000 }) }); check(r.statusCode === 403 && r.json().error === 'unavailable', 'iOS card top-up still unavailable (money hidden on iOS)'); }

// يفتح ولا يحجب: غياب المساعد أو خطؤه
const keep = globalThis.naslifeAdultOk;
delete globalThis.naslifeAdultOk;
await call('POST', '/wallet/topup', { user: MINOR, body: { amount: 5000 }, expect: 200 });
globalThis.naslifeAdultOk = async () => { throw new Error('db down'); };
await call('POST', `/market/${paidL.json.id}/order`, { user: MINOR, body: { qty: 1 }, expect: 200 });
await call('POST', '/chat/requests/age-req-minor/pay', { user: MINOR, expect: 200 });
globalThis.naslifeAdultOk = keep;
adultReq(await call('POST', '/wallet/topup', { user: MINOR, body: { amount: 1000 } }), 'gate back once the helper returns');
// الإقرار يفتح فوراً لمن أقرّ للتو (السالب لا يُحفظ في الذاكرة)
await call('POST', '/me/adult-attest', { user: MINOR, body: { confirm: true }, expect: 200 });
await call('POST', '/wallet/topup', { user: MINOR, body: { amount: 1000 }, expect: 200 });

// ================================================================ بيانات المنشأة
check(String(L_CR) === String(A_CR) && String(L_VAT) === String(A_VAT), 'admin.js and legal_pages.js share the CR/VAT patterns');
let pubS = (await call('GET', '/settings/public', { user: null, expect: 200 })).json;
check(pubS.companyCr === '' && pubS.companyVat === '' && pubS.companyAddress === '', 'public settings: identity empty by default', JSON.stringify(pubS));
let page = await html('/privacy');
check(page.includes('من نحن') && page.includes('Areeb Alraqmiah Company') && !page.includes('السجل التجاري رقم') && !page.includes('الرقم الضريبي'), 'privacy: about us shows the company name only while unset');
e = await call('POST', '/adminapi/settings', { user: ADMIN, body: { companyCr: '12345' }, expect: 400 }); check(e.json.error === 'bad-cr', 'CR must be 10 digits');
e = await call('POST', '/adminapi/settings', { user: ADMIN, body: { companyVat: '300000000000001' }, expect: 400 }); check(e.json.error === 'bad-vat', 'VAT must start and end with 3');
e = await call('POST', '/adminapi/settings', { user: ADMIN, body: { companyVat: '30000000000003' }, expect: 400 }); check(e.json.error === 'bad-vat', 'VAT must be 15 digits');
e = await call('POST', '/adminapi/settings', { user: ADMIN, body: { companyAddress: 'x'.repeat(201) }, expect: 400 }); check(e.json.error === 'bad-address', 'address longer than 200 rejected');
e = await call('POST', '/adminapi/settings', { user: ADMIN, body: { companyAddress: 'جدة\u0007' }, expect: 400 }); check(e.json.error === 'bad-address', 'control characters rejected');
await call('POST', '/adminapi/settings', { user: SELLER, body: { companyCr: '4030000001' }, expect: 403 });
s = await call('POST', '/adminapi/settings', { user: ADMIN, body: { companyCr: '٤٠٣٠-٠٠٠٠٠١', companyVat: '310000000000003', companyAddress: '  RRRD2929، 8228 شارع الأمير سلطان،\n حي الروضة، جدة 23435 <b>  ' }, expect: 200 });
check(s.json.companyCr === '4030000001' && s.json.companyVat === '310000000000003' && s.json.companyAddress === 'RRRD2929، 8228 شارع الأمير سلطان، حي الروضة، جدة 23435 <b>', 'saved normalised (Arabic digits, dashes, whitespace)', JSON.stringify([s.json.companyCr, s.json.companyAddress]));
pubS = (await call('GET', '/settings/public', { user: null, expect: 200 })).json;
check(pubS.companyCr === '4030000001' && pubS.companyVat === '310000000000003' && pubS.companyAddress.startsWith('RRRD2929'), 'public settings expose the identity');
const ver = (await call('GET', '/legal/version', { user: null, expect: 200 })).json;
check(ver.company?.cr === '4030000001' && ver.company.vat === '310000000000003' && ver.company.nameEn === 'Areeb Alraqmiah Company' && ver.company.address.includes('الروضة'), '/legal/version carries the company identity');
for (const path of ['/privacy', '/terms', '/support']) {
  page = await html(path);
  const footer = page.slice(page.indexOf('<footer>'));
  check(footer.includes('4030000001') && footer.includes('310000000000003') && footer.includes('الروضة'), `${path}: footer shows CR, VAT and national address`);
  check(page.includes('<h2 id="about">من نحن</h2>') && page.includes('السجل التجاري رقم <span dir="ltr">4030000001</span>') && page.includes('Commercial registration No. 4030000001') && page.includes('VAT No. 310000000000003'), `${path}: about us (Arabic and English) lists the identity`);
  check(!page.includes('<b>  ') && page.includes('&lt;b&gt;') && !/23435 <b>/.test(page), `${path}: address is escaped`);
}
// قيمة كُتبت في القاعدة مباشرة بصيغة خاطئة لا تظهر
await pool.query("UPDATE platform_settings SET value='\"12\"' WHERE key='companyCr'");
await call('POST', '/adminapi/settings', { user: ADMIN, body: { announcement: '' }, expect: 200 }); // يعيد تحميل الإعدادات
page = await html('/privacy');
check(!page.includes('السجل التجاري رقم') && page.includes('310000000000003'), 'malformed stored CR is hidden, valid VAT still shown');
check((await call('GET', '/settings/public', { user: null })).json.companyCr === '', 'public settings hide the malformed CR');
// المسح يخفيها
s = await call('POST', '/adminapi/settings', { user: ADMIN, body: { companyCr: '', companyVat: '', companyAddress: '' }, expect: 200 });
page = await html('/terms');
check(!page.includes('310000000000003') && !page.includes('الروضة') && page.includes('من نحن'), 'cleared identity disappears from the pages');

// ================================================================ سياسة الخصوصية: الذكاء الاصطناعي والعمر
page = await html('/privacy');
check(page.includes(`آخر تحديث: ${LEGAL_UPDATED_AR}`) && LEGAL_UPDATED_AR === '6 نوفمبر 2026', 'privacy shows the new last-updated date');
check(page.includes('<h2 id="ai">الذكاء الاصطناعي</h2>') && page.includes('محادثاتك الخاصة لا تُرسل إلى أي ذكاء اصطناعي'), 'privacy: private chats are never sent to AI');
check(page.includes('صندوق الدعم') && page.includes('يراجعها الموظف') && page.includes('صياغة عرض وظيفي') && page.includes('اكتب لي العرض') && page.includes('لا تُرسل أي بيانات عن المرشحين'), 'privacy: the two Anthropic uses described exactly');
check(page.includes('your private chats are never sent to any AI') && page.includes('Write the job offer for me'), 'privacy (English) matches');
check(page.includes('ونطلب منك الإقرار بذلك عند التسجيل') && page.includes('مرة واحدة قبل أول عملية مالية'), 'privacy: ages section describes both declarations');
page = await html('/terms');
check(page.includes('وتقرّ بذلك عند التسجيل') && page.includes('declared once before the first financial action'), 'terms: age declarations (Arabic and English)');

// ---- تنظيف ما يؤثر في الحزم الأخرى (القاعدة مشتركة: حزمة البحث تعدّ الفنادق، وحزم السوق تعدّ العروض)
await pool.query('DELETE FROM platform_settings WHERE key = ANY($1)', [SETTINGS]);
await pool.query('DELETE FROM admins WHERE user_id = ANY($1)', [OURS]);
for (const [sql, args] of [
  ["DELETE FROM biz_orders WHERE biz_id LIKE 'age-%'", []], ["DELETE FROM biz_hotel_links WHERE biz_id LIKE 'age-%'", []], ["DELETE FROM biz_items WHERE id LIKE 'age-%'", []], ["DELETE FROM biz WHERE id LIKE 'age-%'", []],
  ['DELETE FROM market_orders WHERE buyer_id = ANY($1) OR seller_id = ANY($1)', [OURS]], ['DELETE FROM market_spotlight WHERE seller_id = ANY($1)', [OURS]], ['DELETE FROM market_listings WHERE seller_id = ANY($1)', [OURS]],
  ["DELETE FROM chat_requests WHERE message_id LIKE 'age-%'", []],
  ['DELETE FROM tickets WHERE user_id = ANY($1)', [OURS]], ['DELETE FROM events WHERE host_id = ANY($1)', [OURS]], ['DELETE FROM payments WHERE user_id = ANY($1)', [OURS]],
]) { try { await pool.query(sql, args); } catch { /* جدول غائب */ } }
delete globalThis.naslifePayFetch; delete globalThis.naslifeHotelFetch;
await app.close(); await pool.end();
console.log(fails ? `${fails} FAILED` : 'ALL OK');
process.exit(fails ? 1 : 0);
