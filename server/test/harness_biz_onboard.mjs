// تسجيل الدوائر الموثّقة (server/biz_onboard.js + امتدادات business.js وrow.js وmarket_plus.js): التحقق من كل رمز خطأ في التسجيل،
// المسار السعيد الثابت والمتنقل (تطبيع الجوال، الدور، الحضور ونطاق الخدمة، الظهور فوراً)، فحص التكرار خلال 3 كم، مستويات الاكتمال
// منشورة ← مكتملة ← موثّقة ← نشطة مع النسبة والخطوة التالية، التوثيق (أخطاء الإرسال، إخفاء بيانات الكيان، قائمة الإدارة وقرارها
// وإشعارات المالك وإعادة الإرسال بعد الرفض)، بوابة البيع (403 not-verified للمدفوع، المجاني مسموح، 200 بعد الاعتماد)،
// دبوس «هنا اليوم» وأثره على GET /biz والصف، تغطية نطاق الخدمة بـ lat/lng، خطّاف «أبحث عن» للدوائر المتنقلة، والفئات الجديدة.
import Fastify from 'fastify';
import pg from 'pg';
import { normalizePhone, CR_LOOKUP_URL, FREELANCE_LOOKUP_URL, WEIGHTS } from '../biz_onboard.js';
import { CATEGORIES, CATEGORY_AR } from '../business.js';
import { KINDS, ACT } from '../row.js';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0';
let fails = 0;
const check = (c, l, extra = '') => { if (!c) fails++; console.log((c ? 'OK  ' : 'FAIL') + ' ' + l + (extra ? ' ' + extra : '')); };

// ---- وحدات خالصة
check(normalizePhone('0512345678') === '+966512345678' && normalizePhone('512345678') === '+966512345678' && normalizePhone('+966 51 234 5678') === '+966512345678' && normalizePhone('00966512345678') === '+966512345678' && normalizePhone('٠٥١٢٣٤٥٦٧٨') === '+966512345678', 'phone normalised from every accepted form (incl. Arabic digits)');
check(normalizePhone('0112345678') === null && normalizePhone('05123') === null && normalizePhone('+971501234567') === null && normalizePhone('') === null, 'non-mobile, short and foreign numbers rejected');
check(['shop', 'services', 'salon', 'clinic', 'entertainment', 'other'].every((c) => CATEGORIES.has(c) && CATEGORY_AR[c]) && CATEGORIES.has('brand'), 'six new categories exported with Arabic labels');
check(KINDS.includes('circle') && ACT.circle === 'زيارة', 'row kinds gain circle with its action');
check(Object.values(WEIGHTS).reduce((a, b) => a + b, 0) === 100, 'completeness weights sum to 100');
check(/mc\.gov\.sa/.test(CR_LOOKUP_URL) && /freelance\.sa/.test(FREELANCE_LOOKUP_URL), 'official lookup pages are the defaults');

// ---- التجهيز: المستخدمون، تنظيف الدوائر المملوكة لهم، إشعارات مزيفة تُجمع في مصفوفة
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
const AMR = 'SA0000011', SARA = 'SA0000012', KHALID = 'SA0000013', NORA = 'SA0000014', ADMIN = 'SA0000019';
const USERS = [AMR, SARA, KHALID, NORA, ADMIN];
await pool.query("INSERT INTO users(id,nickname) VALUES($1,'amr'),($2,'sara'),($3,'khalid'),($4,'nora'),($5,'admin') ON CONFLICT (id) DO UPDATE SET nickname=EXCLUDED.nickname", USERS);
// جملة بلا معامل لا تُمرَّر لها معاملات (وإلا رفضها pg بصمت داخل try)
for (const sql of ['DELETE FROM biz_offers WHERE biz_id IN (SELECT id FROM biz WHERE owner_id = ANY($1::text[]))', 'DELETE FROM biz_staff WHERE user_id = ANY($1::text[])', 'DELETE FROM biz WHERE owner_id = ANY($1::text[])',
  'DELETE FROM market_wanted WHERE user_id = ANY($1::text[])', 'DELETE FROM wallet_tx WHERE user_id = ANY($1::text[])', 'DELETE FROM wallet_accounts WHERE user_id = ANY($1::text[])',
  'DELETE FROM admins WHERE user_id = ANY($1::text[])', 'UPDATE users SET is_admin=false WHERE id = ANY($1::text[])']) { try { await pool.query(sql, [USERS]); } catch { /* first run */ } }
try { await pool.query("DELETE FROM biz WHERE id LIKE 'reg-%'"); } catch { /* first run */ }
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
app.register((await import('../commerce.js')).default, { pool, auth });
app.register((await import('../business.js')).default, { pool, auth });
app.register((await import('../offers.js')).default, { pool, auth });
app.register((await import('../biz_onboard.js')).default, { pool, auth });
app.register((await import('../row.js')).default, { pool, auth });
app.register((await import('../market_plus.js')).default, { pool, auth });
await app.ready(); await new Promise((r) => setTimeout(r, 300));
await pool.query('UPDATE users SET is_admin=true WHERE id=$1', [ADMIN]);
const notes = [];
globalThis.naslifeNotify = async (ids, p) => { notes.push({ ids: [].concat(ids).filter(Boolean), ...p }); return []; };
globalThis.naslifeNotifyAdmins = async (p) => { notes.push({ ids: ['admins'], ...p }); return []; };
const audits = [];
globalThis.naslifeAudit = async (uid, action, target, details) => { audits.push({ uid, action, target, details }); };
const sent = (kind, to) => notes.filter((n) => n.kind === kind && n.ids.includes(to));
const call = async (method, url, { body = {}, user = AMR, expect } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json' }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url} [${user}] -> ${r.statusCode}`, r.statusCode === expect ? '' : String(typeof j === 'string' ? j : JSON.stringify(j)).slice(0, 200));
  return j;
};
// جدة: الأصل (الروضة)، نقطة على بعد ≈ 1 كم، نقطة على بعد ≈ 10 كم، والدمام بعيدة
const O = { lat: 21.5433, lng: 39.1728 }, NEAR = { lat: 21.552, lng: 39.1728 }, FAR = { lat: 21.633, lng: 39.1728 }, DMM = { lat: 26.43, lng: 50.10 };
const LOGO = '/media/logo-reg.png';
const base = { category: 'shop', nameAr: 'متجر ريف', name: 'Reef Store', logoUrl: LOGO, presence: 'fixed', lat: O.lat, lng: O.lng, phone: '0512345678', role: 'owner' };

// ---- خيارات التسجيل (عامة)
const opts = await call('GET', '/biz/register/options', { user: null, expect: 200 });
check(opts.categories.length === CATEGORIES.size && opts.categories.some((c) => c.key === 'salon' && c.label === 'صالون وتجميل') && opts.radiusKm.default === 15 && opts.lookup.cr === CR_LOOKUP_URL, 'options list categories, radius bounds and lookup links');

// ---- التحقق في التسجيل: كل رمز خطأ
await call('POST', '/biz/register', { body: base, user: null, expect: 401 });
let e = await call('POST', '/biz/register', { body: { ...base, category: 'bank' }, expect: 400 }); check(e.error === 'bad-category', 'bad-category');
e = await call('POST', '/biz/register', { body: { ...base, nameAr: 'م' }, expect: 400 }); check(e.error === 'bad-name', 'bad-name (too short)');
e = await call('POST', '/biz/register', { body: { ...base, logoUrl: '' }, expect: 400 }); check(e.error === 'logo-required', 'logo-required (missing)');
e = await call('POST', '/biz/register', { body: { ...base, logoUrl: 'logo.png' }, expect: 400 }); check(e.error === 'logo-required', 'logo-required (not an uploaded url)');
e = await call('POST', '/biz/register', { body: { ...base, presence: 'popup' }, expect: 400 }); check(e.error === 'bad-presence', 'bad-presence');
e = await call('POST', '/biz/register', { body: { ...base, lat: 95 }, expect: 400 }); check(e.error === 'bad-location', 'bad-location (out of range)');
e = await call('POST', '/biz/register', { body: { ...base, lat: null, lng: null }, expect: 400 }); check(e.error === 'bad-location', 'bad-location (missing)');
e = await call('POST', '/biz/register', { body: { ...base, presence: 'mobile', radiusKm: 1 }, expect: 400 }); check(e.error === 'bad-radius', 'bad-radius (below 2)');
e = await call('POST', '/biz/register', { body: { ...base, presence: 'mobile', radiusKm: 80 }, expect: 400 }); check(e.error === 'bad-radius', 'bad-radius (above 50)');
e = await call('POST', '/biz/register', { body: { ...base, phone: '0112345678' }, expect: 400 }); check(e.error === 'bad-phone', 'bad-phone (landline)');
e = await call('POST', '/biz/register', { body: { ...base, phone: '' }, expect: 400 }); check(e.error === 'bad-phone', 'bad-phone (missing)');
e = await call('POST', '/biz/register', { body: { ...base, role: 'ceo' }, expect: 400 }); check(e.error === 'bad-role', 'bad-role');
e = await call('POST', '/biz/register', { body: { ...base, presence: 'fixed', radiusKm: 1 }, expect: 200 }); check(e.biz && e.biz.presence === 'fixed' && e.biz.serviceArea === null, 'radius is ignored for a fixed circle');
await pool.query('DELETE FROM biz WHERE id=$1', [e.biz.id]);

// ---- المسار السعيد: دائرة ثابتة
const r1 = await call('POST', '/biz/register', { body: { ...base, phone: '+966 51 234 5678' }, expect: 200 });
const F = r1.biz;
check(F.id.startsWith('biz-reef-store-') && F.nameAr === 'متجر ريف' && F.name === 'Reef Store' && F.category === 'shop' && F.logoUrl === LOGO && F.ownerId === AMR && F.myRole === 'owner' && F.active === true, 'fixed circle registered with the creator as owner', JSON.stringify([F.id, F.myRole, F.active]));
check(F.phone === '+966512345678', 'phone stored normalised', F.phone);
check(F.presence === 'fixed' && F.serviceArea === null && F.here === null && F.verificationStatus === 'none' && F.canSell === false && F.tier === 'published' && F.verified === false && F.phoneVerified === false && F.entityKind === null, 'bizOut carries presence, verification status, canSell and tier', JSON.stringify([F.presence, F.verificationStatus, F.canSell, F.tier]));
const rowF = (await pool.query('SELECT owner_role, registered_at, verification, presence FROM biz WHERE id=$1', [F.id])).rows[0];
check(rowF.owner_role === 'owner' && rowF.registered_at && rowF.verification.status === 'none' && rowF.presence === 'fixed', 'owner_role, registered_at and verification stored', JSON.stringify(rowF));
check(r1.completeness && r1.completeness.tier === 'published' && r1.completeness.percent === 35 && r1.completeness.checks.logo === true && r1.completeness.checks.phone === true && r1.completeness.checks.location === true && r1.completeness.next?.key === 'hours' && r1.completeness.next.tab === 'profile', 'completeness after registration: 35% (logo, location, phone + the logo as one photo) and next = hours', JSON.stringify([r1.completeness.percent, r1.completeness.next?.key]));
let list = await call('GET', `/biz?bbox=${O.lng - 0.01},${O.lat - 0.01},${O.lng + 0.01},${O.lat + 0.01}`, { user: null, expect: 200 });
check(list.some((b) => b.id === F.id && b.tier === 'published'), 'new circle is visible on the map immediately');
list = await call('GET', '/biz?category=shop', { user: null, expect: 200 });
check(list.some((b) => b.id === F.id), 'new category accepted by GET /biz?category=');
const mgr = await call('POST', '/biz/register', { body: { ...base, nameAr: 'فرع ريف', name: 'Reef Branch', lat: DMM.lat, lng: DMM.lng, role: 'manager' }, expect: 200 });
check(mgr.biz.myRole === 'owner' && (await pool.query('SELECT owner_role FROM biz WHERE id=$1', [mgr.biz.id])).rows[0].owner_role === 'manager', 'registering as manager still makes the creator owner_id and stores owner_role=manager');

// ---- المسار السعيد: دائرة متنقلة
const r2 = await call('POST', '/biz/register', { body: { category: 'services', nameAr: 'صيانة نورة المتنقلة', logoUrl: LOGO, presence: 'mobile', lat: O.lat, lng: O.lng, radiusKm: 8, districts: ['الروضة', 'السلامة', '', 'الحمراء'], phone: '٠٥٥٥٥٥٥٥٥٥' }, user: NORA, expect: 200 });
const M = r2.biz;
check(M.presence === 'mobile' && M.serviceArea && M.serviceArea.radiusKm === 8 && M.serviceArea.lat === O.lat && M.serviceArea.districts.length === 3 && M.phone === '+966555555555' && M.name === 'صيانة نورة المتنقلة', 'mobile circle carries its service area and defaults the latin name to the Arabic one', JSON.stringify(M.serviceArea));
const r2b = await call('POST', '/biz/register', { body: { category: 'salon', nameAr: 'كوافيرة سارة', logoUrl: LOGO, presence: 'mobile', lat: DMM.lat, lng: DMM.lng, phone: '0501112222', role: 'owner' }, user: SARA, expect: 200 });
check(r2b.biz.serviceArea.radiusKm === 15 && r2b.biz.serviceArea.districts.length === 0, 'mobile radius defaults to 15 km');
const M2 = r2b.biz;
check(r2.completeness.checks.hours === true && r2.completeness.next?.key === 'description', 'mobile: service area counts as hours; next = description');

// ---- فحص التكرار: اسم مشابه خلال 3 كم، لا على بعد 10 كم
await pool.query("INSERT INTO biz(id,name,name_ar,category,lat,lng,active) VALUES('reg-far','Reef Store Far','متجر ريف البعيد','shop',$1,$2,true)", [FAR.lat, FAR.lng]);
let dup = await call('GET', `/biz/register/check?name=${encodeURIComponent('ريف')}&lat=${NEAR.lat}&lng=${NEAR.lng}`, { expect: 200 });
check(dup.duplicates.some((d) => d.id === F.id && d.distanceKm <= 1.5 && d.ownerId === AMR && d.logoUrl === LOGO && d.nameAr === 'متجر ريف') && !dup.duplicates.some((d) => d.id === 'reg-far'), 'duplicate check finds the near circle by Arabic name and not the one 10 km away', JSON.stringify(dup.duplicates.map((d) => [d.id, d.distanceKm])));
dup = await call('GET', `/biz/register/check?name=${encodeURIComponent('reef store')}&lat=${O.lat}&lng=${O.lng}`, { expect: 200 });
check(dup.duplicates.some((d) => d.id === F.id), 'duplicate check matches the latin name case-insensitively');
dup = await call('GET', `/biz/register/check?name=${encodeURIComponent('متجر ريف الجديد')}&lat=${O.lat}&lng=${O.lng}`, { expect: 200 });
check(dup.duplicates.some((d) => d.id === F.id), 'a longer query containing an existing name still matches');
dup = await call('GET', `/biz/register/check?name=${encodeURIComponent('مطعم الشاطئ')}&lat=${O.lat}&lng=${O.lng}`, { expect: 200 });
check(dup.duplicates.length === 0, 'unrelated name has no duplicates');
await call('GET', `/biz/register/check?name=x&lat=${O.lat}&lng=${O.lng}`, { expect: 400 });
await call('GET', `/biz/register/check?name=ريف&lat=${O.lat}&lng=${O.lng}`, { user: null, expect: 401 });

// ---- الاكتمال: منشورة ← مكتملة
await call('GET', `/biz/${F.id}/completeness`, { user: KHALID, expect: 403 });
await call('GET', `/biz/${F.id}/completeness`, { user: null, expect: 401 });
await call('GET', `/biz/biz-nope-xx/completeness`, { expect: 404 });
await call('PATCH', `/biz/${F.id}`, { body: { hours: 'يومياً 10:00 ص – 11:00 م' }, expect: 200 });
let c = await call('GET', `/biz/${F.id}/completeness`, { expect: 200 });
check(c.percent === 45 && c.next?.key === 'description' && c.checks.hours === true, 'hours adds 10%; next = description', JSON.stringify([c.percent, c.next?.key]));
await call('PATCH', `/biz/${F.id}`, { body: { description: 'قصير' }, expect: 200 });
c = await call('GET', `/biz/${F.id}/completeness`, { expect: 200 });
check(c.percent === 45 && c.checks.description === false, 'a description under 20 chars does not count');
await call('PATCH', `/biz/${F.id}`, { body: { description: 'متجر هدايا وعطور في الروضة، توصيل داخل جدة خلال ساعتين' }, expect: 200 });
c = await call('GET', `/biz/${F.id}/completeness`, { expect: 200 });
check(c.percent === 55 && c.next?.key === 'photos' && c.next.tab === 'profile', 'description adds 10%; next = photos (cover first)', JSON.stringify([c.percent, c.next]));
await call('PATCH', `/biz/${F.id}`, { body: { coverUrl: '/media/cover-reg.png' }, expect: 200 });
c = await call('GET', `/biz/${F.id}/completeness`, { expect: 200 });
check(c.checks.photos.have === 2 && c.percent === 60 && c.next?.key === 'photos' && c.next.tab === 'catalog', 'logo + cover = 2 photos (10 of 15 points); next photos step points to the catalog', JSON.stringify([c.checks.photos, c.percent, c.next?.tab]));
const items = [];
for (const [t, img] of [['عطر العود', '/media/i1.png'], ['شمعة', null], ['هدية', LOGO]]) items.push(await call('POST', `/biz/${F.id}/items`, { body: { title: t, price: 5000, stock: 10, imageUrl: img }, expect: 200 }));
c = await call('GET', `/biz/${F.id}/completeness`, { expect: 200 });
check(c.checks.catalog.have === 3 && c.checks.photos.have === 3 && c.percent === 80 && c.tier === 'complete' && c.next?.key === 'entity' && c.next.tab === 'verify' && c.canSell === false, 'three items (one image is the logo again, not double counted) → complete, 80%, next = entity', JSON.stringify([c.checks.photos, c.checks.catalog, c.percent, c.tier, c.next?.key]));
check(items[0].kind === 'product', 'shop items default to product');
const staffC = await call('GET', `/biz/${F.id}/completeness`, { user: ADMIN, expect: 200 });
check(staffC.tier === 'complete', 'admin can read completeness');

// ---- بوابة البيع قبل التوثيق
for (let i = 0; i < 2; i++) await call('POST', '/wallet/topup', { body: { amount: 500000 }, user: KHALID, expect: 200 });
const free = await call('POST', `/biz/${F.id}/items`, { body: { title: 'كتيّب مجاني', price: 0, stock: 100 }, expect: 200 });
let o = await call('POST', `/biz/${F.id}/orders`, { body: { itemId: items[0].id, qty: 1 }, user: KHALID, expect: 403 });
check(o.error === 'not-verified', 'paid order on an unverified circle → 403 not-verified');
check((await call('GET', '/wallet', { user: KHALID })).balance === 1000000, 'nothing debited by the refused order');
o = await call('POST', `/biz/${F.id}/orders`, { body: { itemId: free.id, qty: 1 }, user: KHALID, expect: 200 });
check(o.total === 0, 'free item still orderable before verification');

// ---- التوثيق: أخطاء الإرسال
await call('POST', `/biz/${F.id}/verification`, { body: { entityKind: 'cr', entityNumber: '1010123456', docUrl: '/media/cr.pdf' }, user: KHALID, expect: 403 });
e = await call('POST', `/biz/${F.id}/verification`, { body: { entityKind: 'passport', entityNumber: '1010123456', docUrl: '/media/cr.pdf' }, expect: 400 }); check(e.error === 'bad-entity', 'bad-entity');
e = await call('POST', `/biz/${F.id}/verification`, { body: { entityKind: 'cr', entityNumber: '12345', docUrl: '/media/cr.pdf' }, expect: 400 }); check(e.error === 'bad-number', 'bad-number (cr must be 10 digits)');
e = await call('POST', `/biz/${F.id}/verification`, { body: { entityKind: 'freelance', entityNumber: 'FL-12', docUrl: '/media/fl.pdf' }, expect: 400 }); check(e.error === 'bad-number', 'bad-number (freelance 8..20)');
e = await call('POST', `/biz/${F.id}/verification`, { body: { entityKind: 'cr', entityNumber: '1010123456' }, expect: 400 }); check(e.error === 'doc-required', 'doc-required');
e = await call('POST', `/biz/${F.id}/verification`, { body: { entityKind: 'cr', entityNumber: '1010123456', docUrl: 'cr.pdf' }, expect: 400 }); check(e.error === 'doc-required', 'doc-required (not an uploaded url)');
// الإرسال الصحيح
const sub = await call('POST', `/biz/${F.id}/verification`, { body: { entityKind: 'cr', entityNumber: '١٠١٠-١٢٣٤٥٦', docUrl: '/media/cr.pdf' }, expect: 200 });
check(sub.status === 'pending' && sub.verification.status === 'pending' && sub.verification.entityKind === 'cr' && sub.verification.entityNumber === '1010123456' && sub.verification.docUrl === '/media/cr.pdf' && sub.verification.submittedAt, 'submission stored as pending with the normalised number', JSON.stringify(sub));
check(sent('biz_verification', 'admins').length === 1 && sent('biz_verification', 'admins')[0].data.bizId === F.id, 'admins notified (kind biz_verification)');
// بيانات الكيان مخفية عن غير الطاقم
const pub = await call('GET', `/biz/${F.id}`, { user: KHALID, expect: 200 });
check(pub.verificationStatus === 'pending' && pub.entityKind === null && !('entityNumber' in pub) && !('docUrl' in pub) && !JSON.stringify(pub).includes('1010123456') && !JSON.stringify(pub).includes('/media/cr.pdf'), 'public view shows only the status, never entity number or document');
const own = await call('GET', `/biz/${F.id}`, { expect: 200 });
check(own.entityKind === 'cr' && !JSON.stringify(own).includes('1010123456'), 'owner view shows the entity kind (number only via /verification)');
const ov = await call('GET', `/biz/${F.id}/verification`, { expect: 200 });
check(ov.status === 'pending' && ov.entityNumber === '1010123456' && ov.docUrl === '/media/cr.pdf' && ov.lookupUrl === CR_LOOKUP_URL, 'owner reads the submitted number, document and lookup link');
await call('GET', `/biz/${F.id}/verification`, { user: KHALID, expect: 403 });
c = await call('GET', `/biz/${F.id}/completeness`, { expect: 200 });
check(c.verification.status === 'pending' && c.next?.key === 'entity' && c.next.title === 'التوثيق قيد المراجعة', 'completeness reports pending verification');

// ---- الإدارة: القائمة والقرار
await call('GET', '/adminapi/biz/verifications', { user: KHALID, expect: 403 });
await call('GET', '/adminapi/biz/verifications?status=weird', { user: ADMIN, expect: 400 });
let pend = await call('GET', '/adminapi/biz/verifications', { user: ADMIN, expect: 200 });
let row = pend.find((x) => x.bizId === F.id);
check(row && row.status === 'pending' && row.entityKind === 'cr' && row.entityNumber === '1010123456' && row.docUrl === '/media/cr.pdf' && row.owner?.id === AMR && row.lookupUrl === CR_LOOKUP_URL && row.presence === 'fixed' && row.nameAr === 'متجر ريف', 'admin list carries entity data, owner and the MoC lookup link', JSON.stringify(row));
globalThis.naslifeSettings = { crLookupUrl: 'https://example.sa/cr' };
pend = await call('GET', '/adminapi/biz/verifications?status=pending', { user: ADMIN, expect: 200 });
check(pend.find((x) => x.bizId === F.id)?.lookupUrl === 'https://example.sa/cr', 'platform setting overrides the lookup link');
delete globalThis.naslifeSettings;
await call('POST', `/adminapi/biz/${F.id}/verification/approve`, { user: KHALID, expect: 403 });
await call('POST', `/adminapi/biz/${F.id}/verification/maybe`, { user: ADMIN, expect: 400 });
await call('POST', `/adminapi/biz/biz-nope-xx/verification/approve`, { user: ADMIN, expect: 404 });
e = await call('POST', `/adminapi/biz/${F.id}/verification/reject`, { body: { reason: 'لا' }, user: ADMIN, expect: 400 }); check(e.error === 'bad-reason', 'reject needs a reason of 3+ chars');
const rej = await call('POST', `/adminapi/biz/${F.id}/verification/reject`, { body: { reason: 'الوثيقة غير واضحة' }, user: ADMIN, expect: 200 });
check(rej.ok && rej.status === 'rejected', 'rejected with reason');
const nrej = sent('biz_verification_rejected', AMR);
check(nrej.length === 1 && nrej[0].data.bizId === F.id && nrej[0].data.reason === 'الوثيقة غير واضحة', 'owner notified of rejection with the reason');
check(audits.some((a) => a.action === 'biz.verification.reject' && a.target === F.id && a.uid === ADMIN), 'rejection audited');
c = await call('GET', `/biz/${F.id}/completeness`, { expect: 200 });
check(c.verification.status === 'rejected' && c.verification.reason === 'الوثيقة غير واضحة' && c.verification.reviewedAt && c.canSell === false && c.tier === 'complete' && c.next?.key === 'entity' && c.next.hint === 'الوثيقة غير واضحة', 'completeness shows the rejection reason as the hint', JSON.stringify(c.verification));
check((await call('GET', `/biz/${F.id}`, { user: KHALID })).verificationStatus === 'rejected' && !JSON.stringify(await call('GET', `/biz/${F.id}`, { user: KHALID })).includes('غير واضحة'), 'public view never shows the rejection reason');
e = await call('POST', `/adminapi/biz/${F.id}/verification/reject`, { body: { reason: 'مرة أخرى' }, user: ADMIN, expect: 409 }); check(e.error === 'not-pending', 'cannot reject what is not pending');
let adm = await call('GET', '/adminapi/biz/verifications?status=rejected', { user: ADMIN, expect: 200 });
check(adm.some((x) => x.bizId === F.id && x.reason === 'الوثيقة غير واضحة'), 'rejected filter lists it with the reason');
// إعادة الإرسال بعد الرفض ثم الاعتماد
const re = await call('POST', `/biz/${F.id}/verification`, { body: { entityKind: 'freelance', entityNumber: 'FL20250012', docUrl: '/media/fl.pdf' }, expect: 200 });
check(re.status === 'pending' && re.verification.entityKind === 'freelance' && re.verification.reason === null, 're-submission after rejection replaces the request and clears the reason');
adm = await call('GET', '/adminapi/biz/verifications', { user: ADMIN, expect: 200 });
check(adm.find((x) => x.bizId === F.id)?.lookupUrl === FREELANCE_LOOKUP_URL, 'freelance submission links to freelance.sa');
const apr = await call('POST', `/adminapi/biz/${F.id}/verification/approve`, { user: ADMIN, expect: 200 });
check(apr.ok && apr.status === 'approved', 'approved');
const napr = sent('biz_verified', AMR);
check(napr.length === 1 && napr[0].data.bizId === F.id, 'owner notified (kind biz_verified)');
check(audits.some((a) => a.action === 'biz.verification.approve' && a.target === F.id), 'approval audited');
const dbF = (await pool.query('SELECT verified, verified_at, verification FROM biz WHERE id=$1', [F.id])).rows[0];
check(dbF.verified === true && dbF.verified_at && dbF.verification.status === 'approved' && dbF.verification.reviewedBy === ADMIN, 'biz.verified mirrors the approval with verified_at', JSON.stringify(dbF));
c = await call('GET', `/biz/${F.id}/completeness`, { expect: 200 });
check(c.tier === 'verified' && c.percent === 100 && c.canSell === true && c.next?.key === 'offer30d' && c.next.tab === 'offers', 'verified tier at 100%; next = launch an offer', JSON.stringify([c.tier, c.percent, c.next?.key]));
e = await call('POST', `/biz/${F.id}/verification`, { body: { entityKind: 'cr', entityNumber: '1010123456', docUrl: '/media/cr.pdf' }, expect: 409 }); check(e.error === 'already-approved', 'no re-submission once approved');
adm = await call('GET', '/adminapi/biz/verifications?status=all', { user: ADMIN, expect: 200 });
check(adm.some((x) => x.bizId === F.id && x.status === 'approved') && !adm.some((x) => x.bizId === M.id), 'all filter lists approved and skips never-submitted circles');

// ---- بوابة البيع بعد الاعتماد، ثم المستوى «نشطة» بعرض ومنشور
o = await call('POST', `/biz/${F.id}/orders`, { body: { itemId: items[0].id, qty: 1 }, user: KHALID, expect: 200 });
check(o.total === 5000, 'paid order allowed after approval');
const pubF = await call('GET', `/biz/${F.id}`, { user: KHALID, expect: 200 });
check(pubF.canSell === true && pubF.verified === true && pubF.tier === 'verified', 'public view shows canSell after approval');
await call('POST', `/biz/${F.id}/manage/offers`, { body: { kind: 'deal', title: 'خصم الافتتاح', value: { type: 'percent', amount: 10 }, endsAt: new Date(Date.now() + 48 * 3600000).toISOString() }, expect: 200 });
c = await call('GET', `/biz/${F.id}/completeness`, { expect: 200 });
check(c.tier === 'verified' && c.checks.offer30d === true && c.next?.key === 'post30d' && c.next.tab === 'posts', 'offer alone keeps verified; next = post', JSON.stringify([c.tier, c.next?.key]));
await call('POST', `/biz/${F.id}/posts`, { body: { title: 'افتتحنا', body: 'تشكيلة جديدة' }, expect: 200 });
c = await call('GET', `/biz/${F.id}/completeness`, { expect: 200 });
check(c.tier === 'active' && c.checks.post30d === true && c.next === null, 'offer + post within 30 days → active, nothing left to do', JSON.stringify([c.tier, c.next]));
check((await call('GET', '/biz?category=shop', { user: null })).find((b) => b.id === F.id)?.tier === 'active', 'list carries the active tier');
// المفتاح القديم للمدير يبقى متسقاً مع حالة التوثيق
await call('POST', `/biz/${F.id}/verify`, { body: { verified: false }, user: ADMIN, expect: 200 });
let dbV = (await pool.query('SELECT verified, verified_at, verification FROM biz WHERE id=$1', [F.id])).rows[0];
check(dbV.verified === false && dbV.verified_at === null && dbV.verification.status === 'none', 'legacy toggle off clears the approval', JSON.stringify(dbV));
check((await call('POST', `/biz/${F.id}/orders`, { body: { itemId: items[0].id, qty: 1 }, user: KHALID, expect: 403 })).error === 'not-verified', 'selling closes again when the approval is withdrawn');
await call('POST', `/biz/${F.id}/verify`, { body: { verified: true }, user: ADMIN, expect: 200 });
dbV = (await pool.query('SELECT verified, verification FROM biz WHERE id=$1', [F.id])).rows[0];
check(dbV.verified === true && dbV.verification.status === 'approved' && dbV.verification.reviewedBy === ADMIN, 'legacy toggle on writes verification.status=approved');
await call('POST', `/biz/${F.id}/orders`, { body: { itemId: items[0].id, qty: 1 }, user: KHALID, expect: 200 });

// ---- دبوس «هنا اليوم»: للمتنقلة فقط، يحرّك موقعها في GET /biz ويظهر في الصف ثم يزول
e = await call('POST', `/biz/${F.id}/here`, { body: { lat: FAR.lat, lng: FAR.lng, hours: 3 }, expect: 409 }); check(e.error === 'not-mobile', 'fixed circle cannot pin here');
await call('POST', `/biz/${M.id}/here`, { body: { lat: FAR.lat, lng: FAR.lng, hours: 3 }, user: KHALID, expect: 403 });
e = await call('POST', `/biz/${M.id}/here`, { body: { lat: 200, lng: FAR.lng }, user: NORA, expect: 400 }); check(e.error === 'bad-location', 'here: bad-location');
e = await call('POST', `/biz/${M.id}/here`, { body: { lat: FAR.lat, lng: FAR.lng, hours: 20 }, user: NORA, expect: 400 }); check(e.error === 'bad-hours', 'here: bad-hours');
const here = await call('POST', `/biz/${M.id}/here`, { body: { lat: FAR.lat, lng: FAR.lng, hours: 3 }, user: NORA, expect: 200 });
check(here.here && here.here.lat === FAR.lat && here.here.lng === FAR.lng && new Date(here.here.until).getTime() > Date.now() + 2.9 * 3600000, 'here pin set for 3 hours', JSON.stringify(here));
const farBox = `${FAR.lng - 0.01},${FAR.lat - 0.01},${FAR.lng + 0.01},${FAR.lat + 0.01}`;
list = await call('GET', `/biz?bbox=${farBox}`, { user: null, expect: 200 });
let m = list.find((b) => b.id === M.id);
check(m && m.lat === FAR.lat && m.lng === FAR.lng && m.here && m.here.until === here.here.until && m.serviceArea.lat === O.lat, 'bbox around the pin lists the mobile circle at the pin position (service area still at the centre)', JSON.stringify([m?.lat, m?.here]));
list = await call('GET', `/biz?bbox=${O.lng - 0.002},${O.lat - 0.002},${O.lng + 0.002},${O.lat + 0.002}`, { user: null, expect: 200 });
check(!list.some((b) => b.id === M.id) && list.some((b) => b.id === F.id), 'while pinned, the centre bbox no longer lists it (without lat/lng)');
const det = await call('GET', `/biz/${M.id}`, { user: null, expect: 200 });
check(det.lat === FAR.lat && det.here?.lat === FAR.lat, 'detail also reports the effective position');
let rowr = await call('GET', `/row?lat=${FAR.lat}&lng=${FAR.lng}&radiusKm=3`, { user: null, expect: 200 });
let ci = rowr.items.find((i) => i.kind === 'circle' && i.id === M.id);
check(ci && ci.refId === M.id && ci.title === 'صيانة نورة المتنقلة' && /^هنا اليوم حتى \d{2}:\d{2} · خدمات وورش$/.test(ci.subtitle) && ci.imageUrl === LOGO && ci.act === 'زيارة' && ci.cta === 'زيارة' && ci.payload.here === true && ci.payload.until === here.here.until && ci.distanceKm === 0 && ci.lat === FAR.lat && typeof ci.at === 'string' && ci.endsAt === here.here.until, 'row shows the circle kind at the pin with its Arabic subtitle', JSON.stringify(ci));
rowr = await call('GET', `/row?lat=${O.lat}&lng=${O.lng}&radiusKm=3`, { user: null, expect: 200 });
check(!rowr.items.some((i) => i.kind === 'circle' && i.id === M.id), 'row near the centre (10 km from the pin, radius 3) does not show it');
check((await call('GET', '/row/status', { user: null })).sources.circle === true, 'row status knows the circle source');
// الانتهاء: دبوس قديم لا يُحتسب
await pool.query("UPDATE biz SET here = here || jsonb_build_object('until', (now() - interval '1 minute')::text) WHERE id=$1", [M.id]);
list = await call('GET', `/biz?bbox=${farBox}`, { user: null, expect: 200 });
check(!list.some((b) => b.id === M.id), 'expired pin: not listed in the pin bbox any more');
rowr = await call('GET', `/row?lat=${FAR.lat}&lng=${FAR.lng}&radiusKm=3`, { user: null, expect: 200 });
check(!rowr.items.some((i) => i.kind === 'circle'), 'expired pin: gone from the row');
check((await call('GET', `/biz/${M.id}`, { user: null })).here === null, 'expired pin reads as null');
await call('POST', `/biz/${M.id}/here`, { body: { lat: FAR.lat, lng: FAR.lng }, user: NORA, expect: 200 });
check((await call('GET', `/biz/${M.id}`, { user: null })).here !== null, 'hours defaults when omitted');
await call('DELETE', `/biz/${M.id}/here`, { user: KHALID, expect: 403 });
check((await call('DELETE', `/biz/${M.id}/here`, { user: NORA, expect: 200 })).ok === true, 'owner clears the pin');
check((await pool.query('SELECT here FROM biz WHERE id=$1', [M.id])).rows[0].here === null && (await call('GET', `/biz/${M.id}`, { user: null })).lat === O.lat, 'cleared pin: position back to the centre');

// ---- تغطية نطاق الخدمة: مع lat/lng تُدرج المتنقلة التي يغطي نطاقها النقطة ولو خارج الحدود
const inside = { lat: O.lat + 0.045, lng: O.lng }; // ≈ 5 كم من المركز: داخل 8 كم
list = await call('GET', `/biz?bbox=${farBox}&lat=${inside.lat}&lng=${inside.lng}`, { user: null, expect: 200 });
m = list.find((b) => b.id === M.id);
check(m && m.distanceKm >= 4.5 && m.distanceKm <= 5.5 && !list.some((b) => b.id === F.id), 'mobile circle covering the point is listed outside the bbox with distanceKm to its centre', JSON.stringify([m?.distanceKm, list.map((b) => b.id)]));
list = await call('GET', `/biz?bbox=${farBox}&lat=${FAR.lat}&lng=${FAR.lng}`, { user: null, expect: 200 });
check(!list.some((b) => b.id === M.id), 'a point 10 km away (radius 8) is not covered');
list = await call('GET', `/biz?bbox=${farBox}&lat=${DMM.lat}&lng=${DMM.lng}`, { user: null, expect: 200 });
check(list.some((b) => b.id === M2.id) && !list.some((b) => b.id === M.id), 'the Dammam mobile circle covers Dammam with its default 15 km');

// ---- خطّاف «أبحث عن»: صاحب الدائرة المتنقلة داخل النطاق يُخبَر، وخارجه لا
notes.length = 0;
await call('POST', '/market/wanted', { body: { title: 'أبحث عن صيانة مكيف', category: 'services', lat: inside.lat, lng: inside.lng }, user: KHALID, expect: 200 });
check(sent('market_wanted', NORA).length === 1 && sent('market_wanted', SARA).length === 0, 'wanted inside the service area notifies the mobile owner only', JSON.stringify(notes.map((n) => [n.kind, n.ids])));
notes.length = 0;
await call('POST', '/market/wanted', { body: { title: 'أبحث عن كوافيرة', category: 'services', lat: DMM.lat, lng: DMM.lng }, user: KHALID, expect: 200 });
check(sent('market_wanted', SARA).length === 1 && sent('market_wanted', NORA).length === 0, 'wanted in Dammam notifies the Dammam mobile owner, not the Jeddah one');
notes.length = 0;
await call('POST', '/market/wanted', { body: { title: 'أبحث عن شيء بلا موقع', category: 'services' }, user: NORA, expect: 200 });
check(sent('market_wanted', NORA).length === 0 && sent('market_wanted', SARA).length === 0, 'no location → no mobile owners notified, and never the requester');
const near = await globalThis.naslifeBizOwnersNear(inside.lat, inside.lng);
check(near.includes(NORA) && !near.includes(SARA), 'naslifeBizOwnersNear returns owners whose radius covers the point');
await pool.query('UPDATE biz SET hidden=true WHERE id=$1', [M.id]);
check(!(await globalThis.naslifeBizOwnersNear(inside.lat, inside.lng)).includes(NORA), 'hidden circles are skipped');
await pool.query('UPDATE biz SET hidden=false WHERE id=$1', [M.id]);

// ---- الفئات الجديدة في المسار القديم وأنواع أصنافها
const old = await call('POST', '/biz', { body: { name: 'Nora Salon', nameAr: 'صالون نورة', category: 'salon', lat: O.lat, lng: O.lng }, user: NORA, expect: 200 });
check(old.category === 'salon' && old.presence === 'fixed' && old.verificationStatus === 'none', 'POST /biz accepts the new category and defaults presence');
const slot = await call('POST', `/biz/${old.id}/items`, { body: { title: 'قص وتصفيف', price: 8000, meta: { times: ['10:00', '14:00'] } }, user: NORA, expect: 200 });
check(slot.kind === 'clinic' && Array.isArray(slot.slots), 'salon items default to appointments (clinic kind)');
const ent = await call('POST', '/biz', { body: { name: 'Fun Park', nameAr: 'ملاهي', category: 'entertainment', lat: O.lat, lng: O.lng }, user: NORA, expect: 200 });
check((await call('POST', `/biz/${ent.id}/items`, { body: { title: 'تذكرة', price: 3000, meta: { times: ['18:00'] } }, user: NORA, expect: 200 })).kind === 'showtime', 'entertainment items default to showtime');
check((await call('POST', `/biz/${ent.id}/items`, { body: { title: 'x', price: 1, kind: 'product' }, user: NORA, expect: 200 })).kind === 'product', 'explicit kind still wins');
check(globalThis.naslifeBizCategories === CATEGORIES && globalThis.naslifeBizCategories.has('other'), 'categories shared on globalThis for other plugins');
// حد 20 دائرة للمستخدم عبر التسجيل
const cnt = (await pool.query('SELECT count(*)::int AS n FROM biz WHERE owner_id=$1', [SARA])).rows[0].n;
for (let i = cnt; i < 20; i++) await pool.query("INSERT INTO biz(id,name,name_ar,category,lat,lng,owner_id) VALUES($1,$1,$1,'shop',$2,$3,$4)", [`reg-fill-${i}`, DMM.lat, DMM.lng, SARA]);
e = await call('POST', '/biz/register', { body: { ...base, nameAr: 'الحادية والعشرون' }, user: SARA, expect: 409 }); check(e.error === 'too-many', 'register honours the 20-circle limit');
await pool.query("DELETE FROM biz WHERE id LIKE 'reg-fill-%'");
// دوائري تحمل الحقول الجديدة
const mine = await call('GET', '/biz/mine', { user: NORA, expect: 200 });
check(mine.circles.some((b) => b.id === M.id && b.presence === 'mobile' && b.serviceArea?.radiusKm === 8 && b.tier === 'published'), '/biz/mine carries presence, service area and tier');

await app.close(); await pool.end();
console.log(fails ? `\n${fails} FAILED` : '\nALL BIZ ONBOARD TESTS PASSED');
process.exit(fails ? 1 : 0);
