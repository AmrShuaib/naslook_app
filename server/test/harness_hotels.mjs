// حجز الفنادق (server/hotels.js) بخادم Amadeus وهمي عبر globalThis.naslifeHotelFetch: الوحدات الخالصة (Luhn، تطبيع العرض)،
// الحالة قبل المفاتيح وبعدها، إعدادات اللوحة (قناع، المفتاحان معاً، البيئة)، فحص الاتصال، الربط (إدارة ومالك وغريب)،
// العروض (التواريخ والضيوف والتطبيع والحالة بلا توفر وعطل المزوّد)، الحجز (ضيف، بيانات ناقصة، بطاقة خاطئة، نجاح بتأكيد، لا بطاقة
// في المخزون، إشعار، 409 عند زوال العرض)، حجوزاتي، الرمز يُخزَّن ويُجدَّد عند تغيّر المفاتيح، البحث عن فندق، قائمة الروابط والفك.
import Fastify from 'fastify';
import pg from 'pg';
import { luhn, normalizeOffer, TEST_CARD } from '../hotels.js';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0';
let fails = 0;
const check = (c, l, extra = '') => { if (!c) fails++; console.log((c ? 'OK  ' : 'FAIL') + ' ' + l + (extra ? ' ' + extra : '')); };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const day = (n) => new Date(Date.now() + n * 86400000).toISOString().slice(0, 10);

// ---- وحدات خالصة
check(luhn('4151289722471370') && luhn('4111 1111 1111 1111') && !luhn('4111111111111112') && !luhn('123'), 'luhn accepts valid cards and rejects typos');
const RAW_OFFER = { id: 'OFF1', checkInDate: day(3), checkOutDate: day(5), boardType: 'BREAKFAST', room: { type: 'A1K', typeEstimated: { category: 'DELUXE_ROOM', beds: 1, bedType: 'KING' }, description: { text: 'Deluxe king room, sea view', lang: 'EN' } }, guests: { adults: 2 },
  price: { currency: 'SAR', base: '1100.00', total: '1265.50' }, policies: { paymentType: 'guarantee', cancellations: [{ deadline: `${day(2)}T12:00:00+03:00`, type: 'FULL_STAY' }], refundable: { cancellationRefund: 'REFUNDABLE_UP_TO_DEADLINE' } } };
let n = normalizeOffer(RAW_OFFER, 2);
check(n.id === 'OFF1' && n.roomName === 'غرفة ديلوكس' && n.bedType === 'سرير كينغ' && n.beds === 1 && n.boardType === 'مع الإفطار', 'offer normalized to Arabic room/bed/board', JSON.stringify([n.roomName, n.bedType, n.boardType]));
check(n.total === 126550 && n.currency === 'SAR' && n.totalText === '1,265.50 ر.س' && n.perNightText === '632.75 ر.س/ليلة', 'SAR totals in halalas with texts', n.totalText + ' ' + n.perNightText);
check(n.refundable === true && n.cancelText.startsWith('إلغاء مجاني حتى') && n.paymentType === 'guarantee' && n.paymentText.includes('ضمان'), 'free-cancellation deadline and guarantee payment', n.cancelText);
n = normalizeOffer({ id: 'X', price: { currency: 'USD', total: '300' }, room: {}, policies: { paymentType: 'prepay', refundable: { cancellationRefund: 'NON_REFUNDABLE' } } }, 3);
check(n.total === 300 && n.totalText === '300 USD' && n.refundable === false && n.cancelText === 'غير قابل للاسترداد' && n.paymentType === 'prepay' && n.roomName === 'غرفة', 'foreign currency kept raw, non-refundable, prepay', n.totalText);
check(normalizeOffer({ id: 'Y', price: { currency: 'SAR', total: '10' }, policies: {} }, 1).cancelText === 'سياسة الإلغاء بحسب الفندق', 'unknown policy text');

// ---- Amadeus الوهمي
const fake = { calls: [], tokenCalls: 0, creds: null, offers: [RAW_OFFER], noAvail: false, down: false, bookStatus: 'CONFIRMED', bookFail: null, priceFail: null, lastBookBody: null, hotels: [{ hotelId: 'HLJEDHIL', name: 'Hilton Jeddah', geoCode: { latitude: 21.57, longitude: 39.11 }, distance: { value: 2.3 } }, { hotelId: 'RTJEDRIT', name: 'Ritz Carlton Jeddah', geoCode: { latitude: 21.52, longitude: 39.17 }, distance: { value: 4 } }] };
const resp = (status, body) => ({ ok: status < 300, status, json: async () => body });
globalThis.naslifeHotelFetch = async (url, init = {}) => {
  const u = new URL(url); fake.calls.push(`${init.method ?? 'GET'} ${u.pathname}`);
  if (fake.down) throw new Error('ECONNRESET');
  if (u.pathname === '/v1/security/oauth2/token') {
    fake.tokenCalls++; const p = new URLSearchParams(init.body); fake.creds = [p.get('client_id'), p.get('client_secret')];
    if (p.get('client_secret') === 'WRONGSECRET1') return resp(401, { error: 'invalid_client', error_description: 'Invalid parameters', title: 'Invalid parameters' });
    return resp(200, { access_token: 'tok-' + fake.tokenCalls, expires_in: 1799 });
  }
  if (init.headers?.authorization !== `Bearer tok-${fake.tokenCalls}`) return resp(401, { errors: [{ code: 38190, title: 'Invalid access token' }] });
  if (u.pathname === '/v1/reference-data/locations/hotels/by-city') return resp(200, { data: fake.hotels, meta: { city: u.searchParams.get('cityCode') } });
  if (u.pathname === '/v1/reference-data/locations/hotels/by-geocode') return resp(200, { data: fake.hotels.slice(0, 1) });
  if (u.pathname === '/v3/shopping/hotel-offers') {
    if (fake.noAvail) return resp(400, { errors: [{ code: 3664, title: 'NO ROOMS AVAILABLE AT REQUESTED PROPERTY', status: 400 }] });
    return resp(200, { data: [{ type: 'hotel-offers', hotel: { hotelId: u.searchParams.get('hotelIds'), name: 'Hilton Jeddah', cityCode: 'JED' }, available: true, offers: fake.offers.map((o) => ({ ...o, checkInDate: u.searchParams.get('checkInDate'), checkOutDate: u.searchParams.get('checkOutDate'), guests: { adults: Number(u.searchParams.get('adults')) } })) }] });
  }
  if (u.pathname.startsWith('/v3/shopping/hotel-offers/')) {
    if (fake.priceFail) return resp(fake.priceFail, { errors: [{ code: 3664, title: 'NO ROOMS AVAILABLE AT REQUESTED PROPERTY' }] });
    const id = decodeURIComponent(u.pathname.split('/').pop()); const o = fake.offers.find((x) => x.id === id); if (!o) return resp(404, { errors: [{ code: 1257, title: 'INVALID PROPERTY CODE' }] });
    return resp(200, { data: { type: 'hotel-offers', hotel: { hotelId: 'HLJEDHIL', name: 'Hilton Jeddah' }, offers: [o] } });
  }
  if (u.pathname === '/v2/booking/hotel-orders') {
    fake.lastBookBody = JSON.parse(init.body);
    if (fake.bookFail) return resp(fake.bookFail, { errors: [{ code: 11226, title: 'PROPERTY NOT AVAILABLE', detail: 'sold out' }] });
    return resp(201, { data: { type: 'hotel-order', id: 'ORD123', hotelBookings: [{ type: 'hotel-booking', id: 'HB1', bookingStatus: fake.bookStatus, hotelProviderInformation: [{ hotelProviderCode: 'HL', confirmationNumber: 'CONF-7Q2Z' }], hotel: { hotelId: 'HLJEDHIL', name: 'Hilton Jeddah' } }], associatedRecords: [{ reference: 'PNRABC', originSystemCode: 'GDS' }] } });
  }
  return resp(404, { errors: [{ title: 'not found' }] });
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
const stay = (extra = '') => `checkIn=${day(3)}&checkOut=${day(5)}&adults=2&rooms=1${extra}`;

// ---- قبل المفاتيح
let st = await call('GET', '/hotel/status', { user: null, expect: 200 });
check(st.ok && st.configured === false && st.env === null && st.linked === 0 && st.testCard === null, 'status unconfigured for a guest');
await call('GET', `/biz/hot-hilton/hotel/offers?${stay()}`, { user: null, expect: 503 });
let cfg = await call('GET', '/adminapi/hotels/config', { expect: 200 }); check(cfg.configured === false && cfg.secretSet === false && cfg.env === 'test', 'admin config empty');
await call('GET', '/adminapi/hotels/config', { user: SARA, expect: 403 });
let t = await call('POST', '/adminapi/hotels/test', { expect: 200 }); check(t.ok === false && t.error === 'hotel-disabled', 'test without keys');

// ---- الإعدادات
let e = await call('PUT', '/adminapi/hotels/config', { body: { clientId: 'AbCdEfGh12345678', clientSecret: 'sec***masked' }, expect: 400 }); check(e.error === 'masked-key' && e.field === 'clientSecret', 'masked copy rejected');
e = await call('PUT', '/adminapi/hotels/config', { body: { clientId: 'AbCdEfGh12345678' }, expect: 400 }); check(e.error === 'both-keys-required', 'id without secret rejected');
e = await call('PUT', '/adminapi/hotels/config', { body: { clientId: 'AbCdEfGh12345678', clientSecret: 'ZyXwVuTs87654321', env: 'prod' }, expect: 400 }); check(e.error === 'bad-env', 'bad env rejected');
cfg = await call('PUT', '/adminapi/hotels/config', { body: { clientId: 'AbCdEfGh12345678', clientSecret: 'ZyXwVuTs87654321', env: 'test' }, expect: 200 });
check(cfg.configured && cfg.source === 'panel' && cfg.env === 'test' && cfg.clientIdHint === 'AbC…5678' && cfg.secretSet && cfg.secretHint === 'ZyX…4321' && cfg.updatedBy === AMR, 'keys saved, masked hints returned', JSON.stringify([cfg.clientIdHint, cfg.secretHint]));
st = await call('GET', '/hotel/status', { user: null, expect: 200 }); check(st.configured && st.env === 'test' && st.testCard?.number === TEST_CARD.number, 'status configured with the test card');
t = await call('POST', '/adminapi/hotels/test', { expect: 200 }); check(t.ok && t.env === 'test' && t.source === 'panel' && t.expiresIn > 1700 && fake.creds[0] === 'AbCdEfGh12345678', 'connection test fetches a token with the panel keys', JSON.stringify(t));
await call('PUT', '/adminapi/hotels/config', { body: { clientSecret: 'WRONGSECRET1' }, expect: 200 });
t = await call('POST', '/adminapi/hotels/test', { expect: 200 }); check(t.ok === false && t.error === 'bad-credentials', 'wrong secret → bad-credentials');
fake.down = true; t = await call('POST', '/adminapi/hotels/test', { expect: 200 }); check(t.ok === false && t.error === 'provider-unreachable', 'network down → provider-unreachable'); fake.down = false;
await call('PUT', '/adminapi/hotels/config', { body: { clientSecret: 'ZyXwVuTs87654321' }, expect: 200 });

// ---- الربط
check((await call('GET', '/biz/hot-hilton/hotel', { user: null, expect: 200 })).linked === false, 'unlinked circle');
await call('PUT', '/biz/hot-hilton/hotel/link', { body: { hotelId: 'HLJEDHIL' }, user: KHALID, expect: 403 });
await call('PUT', '/biz/hot-hilton/hotel/link', { body: { hotelId: 'bad id!' }, user: SARA, expect: 400 });
await call('PUT', '/biz/nope/hotel/link', { body: { hotelId: 'HLJEDHIL' }, expect: 404 });
let link = await call('PUT', '/biz/hot-hilton/hotel/link', { body: { hotelId: 'hljedhil', hotelName: 'Hilton Jeddah', cityCode: 'jed' }, user: SARA, expect: 200 });
check(link.linked && link.hotelId === 'HLJEDHIL' && link.cityCode === 'JED' && link.env === 'test' && link.configured, 'owner links the circle (ids upper-cased)');
link = await call('GET', '/biz/hot-hilton/hotel', { user: null, expect: 200 }); check(link.linked && link.hotelName === 'Hilton Jeddah', 'guest sees the link');
st = await call('GET', '/hotel/status', { user: null }); check(st.linked === 1, 'status counts links');

// ---- العروض
e = await call('GET', `/biz/hot-hilton/hotel/offers?checkIn=${day(5)}&checkOut=${day(3)}`, { user: null, expect: 400 }); check(e.error === 'bad-dates', 'checkout before checkin');
e = await call('GET', `/biz/hot-hilton/hotel/offers?checkIn=${day(-1)}&checkOut=${day(2)}`, { user: null, expect: 400 }); check(e.error === 'bad-dates', 'past checkin');
e = await call('GET', `/biz/hot-hilton/hotel/offers?checkIn=${day(1)}&checkOut=${day(40)}`, { user: null, expect: 400 }); check(e.error === 'bad-dates', 'more than 30 nights');
e = await call('GET', `/biz/hot-hilton/hotel/offers?checkIn=${day(3)}&checkOut=${day(5)}&adults=12`, { user: null, expect: 400 }); check(e.error === 'bad-guests', 'too many adults');
e = await call('GET', `/biz/hot-hilton/hotel/offers?checkIn=${day(3)}&checkOut=${day(5)}&adults=2&rooms=0`, { user: null, expect: 400 }); check(e.error === 'bad-guests', 'zero rooms');
await call('GET', `/biz/nope/hotel/offers?${stay()}`, { user: null, expect: 404 });
const before = fake.tokenCalls;
let off = await call('GET', `/biz/hot-hilton/hotel/offers?${stay()}`, { user: null, expect: 200 });
check(off.hotel.hotelId === 'HLJEDHIL' && off.nights === 2 && off.adults === 2 && off.rooms === 1 && off.currency === 'SAR' && off.env === 'test' && off.available === true, 'offers header', JSON.stringify({ n: off.nights, a: off.adults }));
check(off.offers.length === 1 && off.offers[0].id === 'OFF1' && off.offers[0].total === 126550 && off.offers[0].roomName === 'غرفة ديلوكس' && off.offers[0].cancelText.startsWith('إلغاء مجاني'), 'offers normalized', JSON.stringify(off.offers[0]).slice(0, 160));
// أول بحث بعد حفظ المفاتيح يجلب رمزاً واحداً، والبحث التالي يعيد استخدامه
check(fake.tokenCalls === before + 1, 'first search after saving keys fetches one token', `${fake.tokenCalls} vs ${before}`);
await call('GET', `/biz/hot-hilton/hotel/offers?${stay()}`, { user: null, expect: 200 });
check(fake.tokenCalls === before + 1, 'cached token reused for the next search', `${fake.tokenCalls} vs ${before + 1}`);
fake.noAvail = true; off = await call('GET', `/biz/hot-hilton/hotel/offers?${stay()}`, { user: null, expect: 200 }); check(off.available === false && off.offers.length === 0, 'no availability → empty list, not an error'); fake.noAvail = false;
fake.down = true; e = await call('GET', `/biz/hot-hilton/hotel/offers?${stay()}`, { user: null, expect: 502 }); check(e.error === 'provider-error', 'provider down → 502'); fake.down = false;

// ---- الحجز
const guest = { title: 'mr', firstName: 'Amr', lastName: 'Shuaib', phone: '+966 50 123 4567', email: 'Amr@Example.com' };
const card = { vendorCode: 'VI', number: '4151 2897 2247 1370', expiry: '2028-08', holderName: 'AMR SHUAIB' };
await call('POST', '/biz/hot-hilton/hotel/book', { body: { offerId: 'OFF1', guest, card }, user: null, expect: 401 });
e = await call('POST', '/biz/hot-hilton/hotel/book', { body: { offerId: 'OFF1', guest: { ...guest, email: 'nope' }, card }, expect: 400 }); check(e.error === 'bad-guest', 'bad email');
e = await call('POST', '/biz/hot-hilton/hotel/book', { body: { offerId: 'OFF1', guest, card: { ...card, number: '4111111111111112' } }, expect: 400 }); check(e.error === 'bad-card', 'luhn failure');
e = await call('POST', '/biz/hot-hilton/hotel/book', { body: { offerId: 'OFF1', guest, card: { ...card, expiry: '2020-01' } }, expect: 400 }); check(e.error === 'bad-card', 'expired card');
e = await call('POST', '/biz/hot-hilton/hotel/book', { body: { offerId: '', guest, card }, expect: 400 }); check(e.error === 'bad-offer', 'missing offer');
await call('POST', '/biz/nope/hotel/book', { body: { offerId: 'OFF1', guest, card }, expect: 404 });
await pool.query('DELETE FROM app_notifications');
const bk = await call('POST', '/biz/hot-hilton/hotel/book', { body: { offerId: 'OFF1', guest, card }, expect: 200 });
check(bk.status === 'confirmed' && bk.confirmation === 'CONF-7Q2Z' && bk.orderId === 'ORD123' && bk.hotelName === 'Hilton Jeddah' && bk.bizName === 'هيلتون جدة' && bk.nights === 2 && bk.roomName === 'غرفة ديلوكس' && bk.total === 126550 && bk.totalText === '1,265.50 ر.س' && bk.guestName === 'Amr Shuaib' && bk.guestEmail === 'amr@example.com' && bk.upcoming === true && bk.env === 'test', 'booking confirmed and stored', JSON.stringify(bk).slice(0, 220));
check(bk.checkIn === day(3) && bk.checkOut === day(5), 'dates from the priced offer', `${bk.checkIn} ${bk.checkOut}`);
const sent = fake.lastBookBody?.data;
check(sent?.type === 'hotel-order' && sent.guests[0].title === 'MR' && sent.guests[0].phone === '+966501234567' && sent.roomAssociations[0].hotelOfferId === 'OFF1' && sent.payment.paymentCard.paymentCardInfo.cardNumber === '4151289722471370' && sent.payment.paymentCard.paymentCardInfo.expiryDate === '2028-08', 'Amadeus order body (v2) with cleaned phone and card');
const stored = (await pool.query('SELECT raw::text AS raw, guest_phone FROM hotel_bookings WHERE id=$1', [bk.id])).rows[0];
check(!stored.raw.includes('4151289722471370') && !stored.raw.includes('2028-08') && stored.guest_phone === '+966501234567', 'card never stored (raw holds only the provider reply)');
const notes = (await pool.query("SELECT kind, title, body FROM app_notifications WHERE user_id=$1", [AMR])).rows;
check(notes.some((x) => x.kind === 'hotel_booked' && x.title.includes('Hilton') && x.body.includes('CONF-7Q2Z')), 'notification sent', JSON.stringify(notes[0]));
let mine = await call('GET', '/hotel/bookings/mine', { expect: 200 }); check(mine.length === 1 && mine[0].id === bk.id, 'mine lists the booking');
check((await call('GET', '/hotel/bookings/mine', { user: SARA })).length === 0, 'others see nothing');
await call('GET', `/hotel/bookings/${bk.id}`, { user: SARA, expect: 403 });
check((await call('GET', `/hotel/bookings/${bk.id}`, { expect: 200 })).confirmation === 'CONF-7Q2Z', 'single booking by owner');
await call('GET', '/hotel/bookings/mine', { user: null, expect: 401 });
fake.priceFail = 400; e = await call('POST', '/biz/hot-hilton/hotel/book', { body: { offerId: 'OFF1', guest, card }, expect: 409 }); check(e.error === 'offer-unavailable', 'offer gone at pricing → 409'); fake.priceFail = null;
fake.bookFail = 400; e = await call('POST', '/biz/hot-hilton/hotel/book', { body: { offerId: 'OFF1', guest, card }, expect: 409 }); check(e.error === 'offer-unavailable' && /sold out/.test(e.message), 'sold out at booking → 409 with the provider message'); fake.bookFail = null;
fake.bookFail = 500; e = await call('POST', '/biz/hot-hilton/hotel/book', { body: { offerId: 'OFF1', guest, card }, expect: 502 }); check(e.error === 'provider-error', 'provider 500 → 502'); fake.bookFail = null;
e = await call('POST', '/biz/hot-hilton/hotel/book', { body: { offerId: 'GHOST', guest, card }, expect: 409 }); check(e.error === 'offer-unavailable', 'unknown offer → 409');
fake.bookStatus = 'PENDING'; const pend = await call('POST', '/biz/hot-hilton/hotel/book', { body: { offerId: 'OFF1', guest, card }, expect: 200 }); check(pend.status === 'pending', 'non-confirmed provider status → pending'); fake.bookStatus = 'CONFIRMED';
mine = await call('GET', '/hotel/bookings/mine'); check(mine.length === 2 && mine[0].id === pend.id, 'mine newest first');
cfg = await call('GET', '/adminapi/hotels/config'); check(cfg.bookings === 2 && cfg.linked === 1, 'admin config counts');

// ---- الرمز يُجدَّد عند تغيّر المفاتيح
const tk = fake.tokenCalls;
await call('PUT', '/adminapi/hotels/config', { body: { clientId: 'NewClientId00001', clientSecret: 'NewSecret0000001' }, expect: 200 });
await call('GET', `/biz/hot-hilton/hotel/offers?${stay()}`, { user: null, expect: 200 });
check(fake.tokenCalls === tk + 1 && fake.creds[0] === 'NewClientId00001', 'new keys → new token on the next call');

// ---- البحث والروابط
let s = await call('GET', '/adminapi/hotels/search?cityCode=jed', { expect: 200 }); check(s.hotels.length === 2 && s.hotels[0].hotelId === 'HLJEDHIL' && s.hotels[0].lat === 21.57 && s.hotels[0].distanceKm === 2.3, 'search by city');
s = await call('GET', '/adminapi/hotels/search?cityCode=JED&q=ritz', { expect: 200 }); check(s.hotels.length === 1 && s.hotels[0].name === 'Ritz Carlton Jeddah', 'name filter');
s = await call('GET', '/adminapi/hotels/search?lat=21.57&lng=39.11', { expect: 200 }); check(s.hotels.length === 1, 'search by geocode');
e = await call('GET', '/adminapi/hotels/search', { expect: 400 }); check(e.error === 'bad-query', 'search without city or point');
await call('GET', '/adminapi/hotels/search?cityCode=JED', { user: SARA, expect: 403 });
const links = await call('GET', '/adminapi/hotels/links', { expect: 200 }); check(links.length === 1 && links[0].bizId === 'hot-hilton' && links[0].bizName === 'هيلتون جدة' && links[0].hotelId === 'HLJEDHIL', 'links list');
await call('DELETE', '/biz/hot-hilton/hotel/link', { user: KHALID, expect: 403 });
await call('DELETE', '/biz/hot-hilton/hotel/link', { expect: 200 });
check((await call('GET', '/biz/hot-hilton/hotel', { user: null })).linked === false, 'unlinked by admin');
await call('GET', `/biz/hot-hilton/hotel/offers?${stay()}`, { user: null, expect: 404 });
// مسح المفاتيح يعيد الحالة إلى غير مفعّل
cfg = await call('PUT', '/adminapi/hotels/config', { body: { clientId: '', clientSecret: '' }, expect: 200 }); check(cfg.configured === false && cfg.panelSet === false, 'clearing both keys disables');

await app.close(); await pool.end();
console.log(fails ? `${fails} FAILED` : 'ALL OK');
process.exit(fails ? 1 : 0);
