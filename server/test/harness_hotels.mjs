// حجز الفنادق (server/hotels.js) بخادم Nuitee Connect (LiteAPI) وهمي عبر globalThis.naslifeHotelFetch: الوحدات الخالصة (سياسة
// الإلغاء، تطبيع العرض)، الحالة قبل المفتاح وبعده، إعدادات اللوحة (قناع، صيغة، البيئة)، فحص الاتصال، الربط (إدارة ومالك وغريب)،
// العروض (التواريخ والضيوف وجسم طلب rates والتطبيع و204 بلا توفر وعطل المزوّد والمفتاح المرفوض)، الحجز (ضيف، بيانات ناقصة،
// prebook ثم book بجسم ACC_CREDIT_CARD، تأكيد، إشعار، 409 عند زوال العرض، 502 عند عطل، pending، البيئة الحية مرفوضة)،
// حجوزاتي، البحث عن فندق بالمدينة والإحداثيات، قائمة الروابط والفك.
import Fastify from 'fastify';
import pg from 'pg';
import { cancelInfo, normalizeOffer, PROVIDER } from '../hotels.js';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0';
let fails = 0;
const check = (c, l, extra = '') => { if (!c) fails++; console.log((c ? 'OK  ' : 'FAIL') + ' ' + l + (extra ? ' ' + extra : '')); };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const day = (n) => new Date(Date.now() + n * 86400000).toISOString().slice(0, 10);

// ---- وحدات خالصة
check(cancelInfo({ refundableTag: 'NRFN', cancelPolicyInfos: [] }).cancelText === 'غير قابل للاسترداد' && cancelInfo({ refundableTag: 'NRFN' }).refundable === false, 'non-refundable');
let ci = cancelInfo({ refundableTag: 'RFN', cancelPolicyInfos: [{ cancelTime: `${day(2)} 02:00:00`, amount: 100 }] });
check(ci.refundable === true && ci.cancelText.startsWith('إلغاء مجاني حتى') && ci.cancelBy === `${day(2)} 02:00:00`, 'free cancellation until the earliest deadline', ci.cancelText);
check(cancelInfo({}).cancelText === 'سياسة الإلغاء بحسب الفندق' && cancelInfo({}).refundable === null, 'unknown policy');
const RT = (over = {}) => ({ roomTypeId: 'x', offerId: 'OFF1', supplier: 'nuitee', offerRetailRate: { amount: 1100, currency: 'SAR' }, suggestedSellingPrice: { amount: 1265.5, currency: 'SAR' },
  rates: [{ rateId: 'R1', occupancyNumber: 1, name: 'Deluxe King Room - Sea view', maxOccupancy: 2, adultCount: 2, boardType: 'BB', boardName: 'Bed and Breakfast', remarks: '<p>Late check-out <b>if available</b></p>', retailRate: { total: [{ amount: 1100, currency: 'SAR' }] }, cancellationPolicies: { refundableTag: 'RFN', cancelPolicyInfos: [{ cancelTime: `${day(2)} 02:00:00`, amount: 1100 }] } }], ...over });
let n = normalizeOffer(RT(), 2, 'test');
check(n.id === 'OFF1' && n.roomName === 'Deluxe King Room - Sea view' && n.boardType === 'مع الإفطار' && n.description === 'Late check-out if available' && n.maxOccupancy === 2, 'offer normalized (board in Arabic, html stripped)', JSON.stringify([n.roomName, n.boardType, n.description]));
check(n.total === 126550 && n.cost === 110000 && n.currency === 'SAR' && n.totalText === '1,265.50 ر.س' && n.perNightText === '632.75 ر.س/ليلة', 'selling price shown in halalas, cost kept aside', n.totalText + ' ' + n.perNightText);
check(n.refundable === true && n.paymentType === 'prepay' && n.paymentText.includes('اختبار'), 'cancel + payment text (test env)');
n = normalizeOffer(RT({ suggestedSellingPrice: null, offerRetailRate: { amount: 300, currency: 'USD' } }), 3, 'live');
check(n.total === 300 && n.totalText === '300 USD' && n.cost === 300 && n.paymentText.includes('ناس لايف'), 'no SSP → retail; foreign currency raw; live payment text', n.totalText);
check(normalizeOffer({ offerId: 'Y', rates: [{ boardType: 'HB2', retailRate: { total: [{ amount: 10, currency: 'SAR' }] } }] }, 1).boardType === 'نصف إقامة' && normalizeOffer({ offerId: 'Z', rates: [] }, 1).roomName === 'غرفة', 'board code suffix ignored, defaults');

// ---- LiteAPI الوهمي
const fake = { calls: [], lastHeaders: null, lastRatesBody: null, lastPrebookBody: null, lastBookBody: null, noAvail: false, down: false, badKey: false, prebookFail: null, bookFail: null, bookStatus: 'CONFIRMED', sandbox: true,
  hotels: [{ id: 'lp1a2b3', name: 'Hilton Jeddah', latitude: 21.57, longitude: 39.11, city: 'Jeddah', country: 'SA', stars: 5, address: 'Corniche Rd', thumbnail: 'https://img/h.jpg' }, { id: 'lp9z8y7', name: 'The Ritz-Carlton Jeddah', latitude: 21.52, longitude: 39.17, city: 'Jeddah', country: 'SA', stars: 5 }] };
const resp = (status, body) => ({ ok: status < 300, status, json: async () => { if (body === undefined) throw new Error('no body'); return body; } });
globalThis.naslifeHotelFetch = async (url, init = {}) => {
  const u = new URL(url); fake.calls.push(`${init.method ?? 'GET'} ${u.host}${u.pathname}`); fake.lastHeaders = init.headers;
  if (fake.down) throw new Error('ECONNRESET');
  if (fake.badKey || init.headers?.['X-API-Key'] !== 'sand_abcdef0123456789') return resp(401, { error: { code: 4001, message: 'invalid api key' } });
  if (u.pathname === '/v3.0/data/hotels') {
    const q = u.searchParams; const name = (q.get('hotelName') ?? '').toLowerCase();
    let list = fake.hotels; if (q.get('latitude')) list = list.slice(0, 1);
    if (q.get('cityName') && q.get('cityName') !== 'Jeddah') list = [];
    const lim = Number(q.get('limit')) || 200;
    return resp(200, { data: list.filter((h) => !name || h.name.toLowerCase().includes(name)).slice(0, lim) });
  }
  if (u.pathname === '/v3.0/hotels/rates') {
    fake.lastRatesBody = JSON.parse(init.body);
    if (fake.noAvail) return resp(204, undefined);
    return resp(200, { data: [{ hotelId: fake.lastRatesBody.hotelIds[0], roomTypes: [RT({ offerId: 'OFF2', suggestedSellingPrice: { amount: 2200, currency: 'SAR' }, offerRetailRate: { amount: 2000, currency: 'SAR' } }), RT()] }], sandbox: fake.sandbox, hotels: [{ id: fake.lastRatesBody.hotelIds[0], name: 'Hilton Jeddah' }] });
  }
  if (u.pathname === '/v3.0/rates/prebook') {
    fake.lastPrebookBody = JSON.parse(init.body);
    if (fake.prebookFail) return resp(fake.prebookFail, { error: { code: 2001, message: 'no availability found' } });
    if (fake.lastPrebookBody.offerId === 'GHOST') return resp(400, { error: { code: 4000, message: 'bad request', description: 'offer not found' } });
    return resp(200, { data: { prebookId: 'PRE1', offerId: fake.lastPrebookBody.offerId, hotelId: 'lp1a2b3', checkin: day(3), checkout: day(5), currency: 'SAR', price: 1100, suggestedSellingPrice: { amount: 1265.5, currency: 'SAR' }, priceDifferencePercent: 0, roomTypes: [{ rates: RT().rates }] }, sandbox: fake.sandbox });
  }
  if (u.pathname === '/v3.0/rates/book') {
    fake.lastBookBody = JSON.parse(init.body);
    if (fake.bookFail) return resp(fake.bookFail, { error: { code: fake.bookFail === 500 ? 5000 : 2001, message: fake.bookFail === 500 ? 'internal error' : 'no availability found', description: 'sold out' } });
    return resp(200, { data: { bookingId: 'BK123', clientReference: fake.lastBookBody.clientReference, status: fake.bookStatus, hotelConfirmationCode: 'HCONF-7Q2Z', supplierBookingId: 'SUP1', checkin: day(3), checkout: day(5), hotel: { hotelId: 'lp1a2b3', name: 'Hilton Jeddah' }, price: 1100, currency: 'SAR', bookedRooms: [{ roomType: { name: 'Deluxe King Room - Sea view' }, adults: 2, rate: { cancellationPolicies: RT().rates[0].cancellationPolicies } }], cancellationPolicies: RT().rates[0].cancellationPolicies }, sandbox: fake.sandbox });
  }
  return resp(404, { error: { message: 'not found' } });
};

// ---- التجهيز
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("INSERT INTO users(id,nickname) VALUES('SA0000001','amr'),('SA0000002','sara'),('SA0000003','khalid') ON CONFLICT DO NOTHING");
for (const sql of ['DROP TABLE IF EXISTS hotel_settings, biz_hotel_links, hotel_bookings', 'DELETE FROM app_notifications', "DELETE FROM biz WHERE id LIKE 'hot-%'"]) { try { await pool.query(sql); } catch { /* first run */ } }
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
const dir = new URL('.', import.meta.url).pathname;
app.register((await import('../notify.js')).default, { pool, auth, pollMs: 3600000, opsDir: dir + 'ops' });
app.register((await import('../admin.js')).default, { pool, auth, webappDir: dir + 'webapp', opsDir: dir + 'ops' });
app.register((await import('../commerce.js')).default, { pool, auth });
app.register((await import('../business.js')).default, { pool, auth });
app.register((await import('../hotels.js')).default, { pool, auth });
await app.ready(); await sleep(500);
await pool.query("INSERT INTO admins(user_id,granted_by) VALUES('SA0000001','test') ON CONFLICT DO NOTHING");
await pool.query("INSERT INTO biz(id,name,name_ar,category,lat,lng,address,active,owner_id) VALUES('hot-hilton','Hilton Jeddah','هيلتون جدة','hotel',21.57,39.11,'الكورنيش',true,'SA0000002') ON CONFLICT (id) DO UPDATE SET owner_id='SA0000002'");
const AMR = 'SA0000001', SARA = 'SA0000002', KHALID = 'SA0000003';
const call = async (method, url, { body = {}, user = AMR, expect } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json', host: 'naslife.app', 'x-forwarded-proto': 'https' }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url} [${user}] -> ${r.statusCode}`, r.statusCode === expect ? '' : String(typeof j === 'string' ? j : JSON.stringify(j)).slice(0, 160));
  return j;
};
const stay = () => `checkIn=${day(3)}&checkOut=${day(5)}&adults=2&rooms=1`;
const KEY = 'sand_abcdef0123456789';

// ---- قبل المفتاح
let st = await call('GET', '/hotel/status', { user: null, expect: 200 });
check(st.ok && st.provider === PROVIDER && st.configured === false && st.env === null && st.linked === 0 && st.cardRequired === false && st.testCard === null, 'status unconfigured for a guest (no card ever)');
await call('GET', `/biz/hot-hilton/hotel/offers?${stay()}`, { user: null, expect: 503 });
let cfg = await call('GET', '/adminapi/hotels/config', { expect: 200 }); check(cfg.configured === false && cfg.secretSet === false && cfg.env === 'test' && cfg.provider === PROVIDER, 'admin config empty');
await call('GET', '/adminapi/hotels/config', { user: SARA, expect: 403 });
let t = await call('POST', '/adminapi/hotels/test', { expect: 200 }); check(t.ok === false && t.error === 'hotel-disabled', 'test without a key');

// ---- الإعدادات
let e = await call('PUT', '/adminapi/hotels/config', { body: { apiKey: 'sand_ab***masked' }, expect: 400 }); check(e.error === 'masked-key' && e.field === 'apiKey', 'masked copy rejected');
e = await call('PUT', '/adminapi/hotels/config', { body: { apiKey: 'short' }, expect: 400 }); check(e.error === 'bad-key', 'too-short key rejected');
e = await call('PUT', '/adminapi/hotels/config', { body: { apiKey: KEY, env: 'prod' }, expect: 400 }); check(e.error === 'bad-env', 'bad env rejected');
cfg = await call('PUT', '/adminapi/hotels/config', { body: { apiKey: ` ${KEY} `, env: 'test' }, expect: 200 });
check(cfg.configured && cfg.source === 'panel' && cfg.env === 'test' && cfg.secretSet && cfg.secretHint === 'sand…6789' && cfg.panelSet && cfg.updatedBy === AMR, 'key saved (trimmed), masked hint returned', JSON.stringify([cfg.secretHint, cfg.env]));
st = await call('GET', '/hotel/status', { user: null, expect: 200 }); check(st.configured && st.env === 'test' && st.cardRequired === false, 'status configured, card not required');
t = await call('POST', '/adminapi/hotels/test', { expect: 200 }); check(t.ok && t.env === 'test' && t.source === 'panel' && t.hotels === 1 && fake.lastHeaders['X-API-Key'] === KEY, 'connection test hits /data/hotels with the key header', JSON.stringify(t));
fake.badKey = true; t = await call('POST', '/adminapi/hotels/test', { expect: 200 }); check(t.ok === false && t.error === 'bad-credentials', 'rejected key → bad-credentials'); fake.badKey = false;
fake.down = true; t = await call('POST', '/adminapi/hotels/test', { expect: 200 }); check(t.ok === false && t.error === 'provider-unreachable', 'network down → provider-unreachable'); fake.down = false;

// ---- الربط
check((await call('GET', '/biz/hot-hilton/hotel', { user: null, expect: 200 })).linked === false, 'unlinked circle');
await call('PUT', '/biz/hot-hilton/hotel/link', { body: { hotelId: 'lp1a2b3' }, user: KHALID, expect: 403 });
await call('PUT', '/biz/hot-hilton/hotel/link', { body: { hotelId: 'bad id!' }, user: SARA, expect: 400 });
await call('PUT', '/biz/nope/hotel/link', { body: { hotelId: 'lp1a2b3' }, expect: 404 });
let link = await call('PUT', '/biz/hot-hilton/hotel/link', { body: { hotelId: 'lp1a2b3', hotelName: 'Hilton Jeddah', cityCode: 'jed' }, user: SARA, expect: 200 });
check(link.linked && link.hotelId === 'lp1a2b3' && link.cityCode === 'JED' && link.env === 'test' && link.configured && link.provider === PROVIDER, 'owner links the circle (LiteAPI id kept as is)');
link = await call('GET', '/biz/hot-hilton/hotel', { user: null, expect: 200 }); check(link.linked && link.hotelName === 'Hilton Jeddah', 'guest sees the link');
st = await call('GET', '/hotel/status', { user: null }); check(st.linked === 1, 'status counts links');

// ---- العروض
e = await call('GET', `/biz/hot-hilton/hotel/offers?checkIn=${day(5)}&checkOut=${day(3)}`, { user: null, expect: 400 }); check(e.error === 'bad-dates', 'checkout before checkin');
e = await call('GET', `/biz/hot-hilton/hotel/offers?checkIn=${day(-1)}&checkOut=${day(2)}`, { user: null, expect: 400 }); check(e.error === 'bad-dates', 'past checkin');
e = await call('GET', `/biz/hot-hilton/hotel/offers?checkIn=${day(1)}&checkOut=${day(40)}`, { user: null, expect: 400 }); check(e.error === 'bad-dates', 'more than 30 nights');
e = await call('GET', `/biz/hot-hilton/hotel/offers?checkIn=${day(3)}&checkOut=${day(5)}&adults=12`, { user: null, expect: 400 }); check(e.error === 'bad-guests', 'too many adults');
e = await call('GET', `/biz/hot-hilton/hotel/offers?checkIn=${day(3)}&checkOut=${day(5)}&adults=2&rooms=0`, { user: null, expect: 400 }); check(e.error === 'bad-guests', 'zero rooms');
await call('GET', `/biz/nope/hotel/offers?${stay()}`, { user: null, expect: 404 });
let off = await call('GET', `/biz/hot-hilton/hotel/offers?${stay()}`, { user: null, expect: 200 });
const rb = fake.lastRatesBody;
check(rb.hotelIds[0] === 'lp1a2b3' && rb.occupancies[0].adults === 2 && rb.occupancies[0].rooms === 1 && rb.currency === 'SAR' && rb.guestNationality === 'SA' && rb.checkin === day(3) && rb.checkout === day(5), 'rates request body', JSON.stringify(rb));
check(off.hotel.hotelId === 'lp1a2b3' && off.nights === 2 && off.adults === 2 && off.rooms === 1 && off.currency === 'SAR' && off.env === 'test' && off.provider === PROVIDER && off.available === true, 'offers header (env from the sandbox flag)');
check(off.offers.length === 2 && off.offers[0].id === 'OFF1' && off.offers[0].total === 126550 && off.offers[1].id === 'OFF2' && off.offers[1].total === 220000 && off.offers[0].cancelText.startsWith('إلغاء مجاني'), 'offers normalized and sorted by price', JSON.stringify(off.offers.map((o) => [o.id, o.total])));
check(!('cost' in off.offers[0]) || off.offers[0].cost === 110000, 'cost present server-side only as a number');
fake.sandbox = false; off = await call('GET', `/biz/hot-hilton/hotel/offers?${stay()}`, { user: null, expect: 200 }); check(off.env === 'live', 'a production reply flips env to live even with env=test saved'); fake.sandbox = true;
fake.noAvail = true; off = await call('GET', `/biz/hot-hilton/hotel/offers?${stay()}`, { user: null, expect: 200 }); check(off.available === false && off.offers.length === 0, '204 → empty list, not an error'); fake.noAvail = false;
fake.down = true; e = await call('GET', `/biz/hot-hilton/hotel/offers?${stay()}`, { user: null, expect: 502 }); check(e.error === 'provider-error', 'provider down → 502'); fake.down = false;
fake.badKey = true; e = await call('GET', `/biz/hot-hilton/hotel/offers?${stay()}`, { user: null, expect: 502 }); check(e.error === 'provider-error' && e.message === 'bad-credentials', 'rejected key on search → 502 bad-credentials'); fake.badKey = false;

// ---- الحجز
const guest = { title: 'mr', firstName: 'Amr', lastName: 'Shuaib', phone: '+966 50 123 4567', email: 'Amr@Example.com' };
await call('POST', '/biz/hot-hilton/hotel/book', { body: { offerId: 'OFF1', guest }, user: null, expect: 401 });
e = await call('POST', '/biz/hot-hilton/hotel/book', { body: { offerId: 'OFF1', guest: { ...guest, email: 'nope' } }, expect: 400 }); check(e.error === 'bad-guest', 'bad email');
e = await call('POST', '/biz/hot-hilton/hotel/book', { body: { offerId: '', guest }, expect: 400 }); check(e.error === 'bad-offer', 'missing offer');
await call('POST', '/biz/nope/hotel/book', { body: { offerId: 'OFF1', guest }, expect: 404 });
await pool.query('DELETE FROM app_notifications');
const bk = await call('POST', '/biz/hot-hilton/hotel/book', { body: { offerId: 'OFF1', guest, card: { number: '4111111111111111' } }, expect: 200 });
check(fake.lastPrebookBody.offerId === 'OFF1' && fake.lastPrebookBody.usePaymentSdk === false, 'prebook called with the offer');
const sent = fake.lastBookBody;
check(sent.prebookId === 'PRE1' && sent.payment.method === 'ACC_CREDIT_CARD' && sent.holder.firstName === 'Amr' && sent.holder.phone === '+966501234567' && sent.holder.email === 'amr@example.com' && sent.guests[0].occupancyNumber === 1 && sent.clientReference === `naslife-${bk.id}` && !JSON.stringify(sent).includes('4111'), 'book body: sandbox payment, cleaned holder, idempotent reference, no card forwarded', JSON.stringify(sent).slice(0, 200));
check(bk.status === 'confirmed' && bk.confirmation === 'HCONF-7Q2Z' && bk.orderId === 'BK123' && bk.hotelName === 'Hilton Jeddah' && bk.bizName === 'هيلتون جدة' && bk.nights === 2 && bk.roomName === 'Deluxe King Room - Sea view' && bk.total === 126550 && bk.totalText === '1,265.50 ر.س' && bk.guestName === 'Amr Shuaib' && bk.upcoming === true && bk.env === 'test' && bk.provider === PROVIDER, 'booking confirmed and stored', JSON.stringify(bk).slice(0, 220));
check(bk.checkIn === day(3) && bk.checkOut === day(5) && bk.cancelText.startsWith('إلغاء مجاني'), 'dates and policy from the provider', `${bk.checkIn} ${bk.checkOut} ${bk.cancelText}`);
const stored = (await pool.query('SELECT raw::text AS raw, cost, provider FROM hotel_bookings WHERE id=$1', [bk.id])).rows[0];
check(!stored.raw.includes('4111') && Number(stored.cost) === 110000 && stored.provider === PROVIDER, 'stored raw has no card, cost kept', stored.raw.slice(0, 120));
const notes = (await pool.query("SELECT kind, title, body FROM app_notifications WHERE user_id=$1", [AMR])).rows;
check(notes.some((x) => x.kind === 'hotel_booked' && x.title.includes('Hilton') && x.body.includes('HCONF-7Q2Z')), 'notification sent', JSON.stringify(notes[0]));
let mine = await call('GET', '/hotel/bookings/mine', { expect: 200 }); check(mine.length === 1 && mine[0].id === bk.id, 'mine lists the booking');
check((await call('GET', '/hotel/bookings/mine', { user: SARA })).length === 0, 'others see nothing');
await call('GET', `/hotel/bookings/${bk.id}`, { user: SARA, expect: 403 });
check((await call('GET', `/hotel/bookings/${bk.id}`, { expect: 200 })).confirmation === 'HCONF-7Q2Z', 'single booking by owner');
await call('GET', '/hotel/bookings/mine', { user: null, expect: 401 });
e = await call('POST', '/biz/hot-hilton/hotel/book', { body: { offerId: 'GHOST', guest }, expect: 409 }); check(e.error === 'offer-unavailable', 'unknown offer at prebook → 409');
fake.prebookFail = 204; e = await call('POST', '/biz/hot-hilton/hotel/book', { body: { offerId: 'OFF1', guest }, expect: 409 }); check(e.error === 'offer-unavailable', 'no availability at prebook → 409'); fake.prebookFail = null;
fake.bookFail = 400; e = await call('POST', '/biz/hot-hilton/hotel/book', { body: { offerId: 'OFF1', guest }, expect: 409 }); check(e.error === 'offer-unavailable' && /sold out/.test(e.message), 'sold out at booking → 409 with the provider message'); fake.bookFail = null;
fake.bookFail = 500; e = await call('POST', '/biz/hot-hilton/hotel/book', { body: { offerId: 'OFF1', guest }, expect: 502 }); check(e.error === 'provider-error', 'provider 500 → 502'); fake.bookFail = null;
fake.bookStatus = 'PENDING'; const pend = await call('POST', '/biz/hot-hilton/hotel/book', { body: { offerId: 'OFF1', guest }, expect: 200 }); check(pend.status === 'pending', 'non-confirmed provider status → pending'); fake.bookStatus = 'CONFIRMED';
mine = await call('GET', '/hotel/bookings/mine'); check(mine.length === 2 && mine[0].id === pend.id, 'mine newest first');
cfg = await call('GET', '/adminapi/hotels/config'); check(cfg.bookings === 2 && cfg.linked === 1, 'admin config counts');
// البيئة الحية: البحث يعمل، الحجز مرفوض حتى يُعتمد التحصيل
await call('PUT', '/adminapi/hotels/config', { body: { env: 'live' }, expect: 200 });
check((await call('GET', `/biz/hot-hilton/hotel/offers?${stay()}`, { user: null, expect: 200 })).offers.length === 2, 'live env still searches');
e = await call('POST', '/biz/hot-hilton/hotel/book', { body: { offerId: 'OFF1', guest }, expect: 503 }); check(e.error === 'live-payment-pending', 'live booking refused until per-booking payment exists');
await call('PUT', '/adminapi/hotels/config', { body: { env: 'test' }, expect: 200 });

// ---- البحث والروابط
let s = await call('GET', '/adminapi/hotels/search?cityCode=jed', { expect: 200 }); check(s.hotels.length === 2 && s.hotels[0].hotelId === 'lp1a2b3' && s.hotels[0].lat === 21.57 && s.hotels[0].stars === 5 && s.hotels[0].photo === 'https://img/h.jpg', 'search by city code mapped to Jeddah');
s = await call('GET', '/adminapi/hotels/search?cityCode=Jeddah&q=ritz', { expect: 200 }); check(s.hotels.length === 1 && s.hotels[0].name === 'The Ritz-Carlton Jeddah', 'city name + name filter');
s = await call('GET', '/adminapi/hotels/search?cityCode=Dammam', { expect: 200 }); check(s.hotels.length === 0, 'other city → empty');
s = await call('GET', '/adminapi/hotels/search?lat=21.57&lng=39.11', { expect: 200 }); check(s.hotels.length === 1, 'search by coordinates');
e = await call('GET', '/adminapi/hotels/search', { expect: 400 }); check(e.error === 'bad-query', 'search without city or point');
await call('GET', '/adminapi/hotels/search?cityCode=JED', { user: SARA, expect: 403 });
const links = await call('GET', '/adminapi/hotels/links', { expect: 200 }); check(links.length === 1 && links[0].bizId === 'hot-hilton' && links[0].bizName === 'هيلتون جدة' && links[0].hotelId === 'lp1a2b3', 'links list');
await call('DELETE', '/biz/hot-hilton/hotel/link', { user: KHALID, expect: 403 });
await call('DELETE', '/biz/hot-hilton/hotel/link', { expect: 200 });
check((await call('GET', '/biz/hot-hilton/hotel', { user: null })).linked === false, 'unlinked by admin');
await call('GET', `/biz/hot-hilton/hotel/offers?${stay()}`, { user: null, expect: 404 });
cfg = await call('PUT', '/adminapi/hotels/config', { body: { apiKey: '' }, expect: 200 }); check(cfg.configured === false && cfg.panelSet === false, 'clearing the key disables');

await app.close(); await pool.end();
console.log(fails ? `${fails} FAILED` : 'ALL OK');
process.exit(fails ? 1 : 0);
