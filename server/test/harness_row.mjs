// «الصف» (server/row.js): الحالة، المصادر الخمسة وشكل البطاقة، الترتيب بالقرب والدفعات (ينتهي قريباً، نُشر للتو، فعالية قريبة)،
// نصف القطر، بلا موقع، الحد، التوزيع (لا أكثر من ثلاث متتالية من نوع)، حد 12 لكل نوع، الحظر، الضيف، والجدول الغائب.
import Fastify from 'fastify';
import pg from 'pg';
import crypto from 'node:crypto';
import { KINDS, ACT, interleave, scoreOf, rankItems, endsText, agoText } from '../row.js';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0';
let fails = 0;
const check = (c, l, extra = '') => { if (!c) fails++; console.log((c ? 'OK  ' : 'FAIL') + ' ' + l + (extra ? ' ' + extra : '')); };
const NOW = Date.now(), H = 3600000;
const hrs = (n) => new Date(NOW + n * H).toISOString();

// ---- وحدات خالصة
const L = (id, extra = {}) => ({ kind: 'listing', id, at: hrs(-2), endsAt: null, distanceKm: 0, ...extra });
const il = interleave([L(1), L(2), L(3), L(4), L(5), L(6), { kind: 'moment', id: 'm', distanceKm: 0 }, { kind: 'event', id: 'e', distanceKm: 0 }]).map((x) => x.kind[0] + x.id).join(' ');
check(il === 'l1 l2 l3 mm l4 l5 l6 ee', 'interleave pulls a different kind forward after three in a row', il);
check(interleave([L(1), L(2), L(3), L(4), L(5)]).length === 5, 'interleave keeps a single-kind list intact');
check(scoreOf({ kind: 'offer', distanceKm: 0.4, at: hrs(-2), endsAt: hrs(1) }, NOW) === -1.6, 'ending within 3h subtracts 2', String(scoreOf({ kind: 'offer', distanceKm: 0.4, at: hrs(-2), endsAt: hrs(1) }, NOW)));
check(scoreOf({ kind: 'moment', distanceKm: null, at: new Date(NOW - 5 * 60000).toISOString(), endsAt: hrs(24) }, NOW) === -1.5, 'posted within 30 minutes subtracts 1.5 and no distance counts as zero');
check(scoreOf({ kind: 'event', distanceKm: 2, at: hrs(2), endsAt: null }, NOW) === 1 && scoreOf({ kind: 'job', distanceKm: 2, at: hrs(2), endsAt: null }, NOW) === 2, 'event starting within 6h subtracts 1 (events only)');
check(rankItems(Array.from({ length: 20 }, (_, i) => L(i)), 50, NOW).length === 12, 'rankItems caps a kind at 12');
check(rankItems([L(1), L(2), L(3)], 2, NOW).length === 2, 'rankItems honours the limit');
check(endsText(hrs(0.5), NOW) === 'ينتهي خلال ساعة' && endsText(null, NOW) === 'عرض مستمر' && agoText(new Date(NOW - 12 * 60000).toISOString(), NOW) === 'قبل 12 د', 'arabic time labels', endsText(hrs(0.5), NOW));

// ---- التجهيز: الإضافات المالكة للجداول تُنشئها، والبذر مباشر بـ SQL
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("INSERT INTO users(id,nickname,avatar_url) VALUES('SA0000001','amr',NULL),('SA0000002','sara','https://naslife.app/seed/sara.png'),('SA0000003','khalid',NULL),('SA0000004','nora',NULL) ON CONFLICT (id) DO UPDATE SET nickname=EXCLUDED.nickname, avatar_url=EXCLUDED.avatar_url");
for (const sql of ['DROP TABLE IF EXISTS map_post_likes, map_post_views, map_post_events, map_posts, biz_offers, ticket_tiers, tickets, events, jobs, market_listings CASCADE', "DELETE FROM biz WHERE id LIKE 'row-%'", 'DELETE FROM app_notifications']) { try { await pool.query(sql); } catch { /* first run */ } }
const auth = async (req) => req.headers['x-user'] || null;
// عمرو حظر خالداً: لحظات خالد لا تظهر له وتظهر للضيف
globalThis.naslifeBlockedIds = async (uid) => (uid === 'SA0000001' ? ['SA0000003'] : []);
const app = Fastify();
const dir = new URL('.', import.meta.url).pathname;
app.register((await import('../notify.js')).default, { pool, auth, pollMs: 3600000, opsDir: dir + 'ops' });
app.register((await import('../commerce.js')).default, { pool, auth });
app.register((await import('../business.js')).default, { pool, auth });
app.register((await import('../offers.js')).default, { pool, auth });
app.register((await import('../map_posts.js')).default, { pool, auth });
app.register((await import('../jobs.js')).default, { pool, auth, sweepMs: 0 });
app.register((await import('../row.js')).default, { pool, auth });
await app.ready(); await new Promise((r) => setTimeout(r, 300));
const call = async (method, url, { body = {}, user = 'SA0000001', expect } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json' }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url} [${user}] -> ${r.statusCode}`, r.statusCode === expect ? '' : String(typeof j === 'string' ? j : JSON.stringify(j)).slice(0, 160));
  return j;
};
const AMR = 'SA0000001', SARA = 'SA0000002', KHALID = 'SA0000003', NORA = 'SA0000004';
const uid = () => crypto.randomUUID();
const ids = (r) => r.items.map((i) => i.id);
const at = (r, id) => r.items.findIndex((i) => i.id === id);
const byId = (r, id) => r.items.find((i) => i.id === id);
const maxRun = (r) => { let best = 0, run = 0, last = null; for (const i of r.items) { run = i.kind === last ? run + 1 : 1; last = i.kind; best = Math.max(best, run); } return best; };

// ---- البذر: الأصل (21.54, 39.17) جدة؛ قريب = على الأصل، متوسط ≈ 8 كم، بعيد = الدمام
const ORIGIN = { lat: 21.54, lng: 39.17 }, MID = { lat: 21.61, lng: 39.19 }, DMM = { lat: 26.43, lng: 50.10 };
const biz = async (id, nameAr, p, extra = {}) => pool.query("INSERT INTO biz(id,name,name_ar,category,lat,lng,address,active,logo_url) VALUES($1,$2,$3,'cafe',$4,$5,'الروضة',$6,$7)", [id, id, nameAr, p.lat, p.lng, extra.active !== false, extra.logo ?? null]);
await biz('row-reef', 'مقهى ريف', ORIGIN, { logo: 'https://naslife.app/seed/reef.png' });
await biz('row-mid', 'مطعم الشاطئ', MID);
await biz('row-dmm', 'كافيه الدمام', DMM);
await biz('row-off', 'دائرة موقوفة', ORIGIN, { active: false });
const offer = async (bizId, title, startsH, endsH, active = true) => { const id = uid(); await pool.query("INSERT INTO biz_offers(id,biz_id,kind,title,value,members_only,starts_at,ends_at,active) VALUES($1,$2,'deal',$3,'{\"type\":\"percent\",\"amount\":15}',false,$4,$5,$6)", [id, bizId, title, hrs(startsH), endsH == null ? null : hrs(endsH), active]); return id; };
const O1 = await offer('row-reef', 'كورتادو بـ 10', -2, 1);            // ينتهي خلال ساعة: الدفعة -2
const O2 = await offer('row-mid', 'عشاء لشخصين', -24, 72);
const O3 = await offer('row-dmm', 'عرض الدمام', -2, 48);               // خارج نصف القطر
const O4 = await offer('row-reef', 'عرض موقوف', -2, 48, false);        // غير مفعّل
const O5 = await offer('row-reef', 'عرض الغد', 24, 72);                 // لم يبدأ
const O6 = await offer('row-off', 'عرض دائرة موقوفة', -2, 48);         // الدائرة غير نشطة
const post = async (user, p, { caption = '', kind = 'image', media = 'https://naslife.app/chat/media/x.jpg', created = -2, expires = 22, status = 'active', place = 'الكورنيش' } = {}) => { const id = uid(); await pool.query("INSERT INTO map_posts(id,user_id,kind,media_url,caption,lat,lng,place_name,status,expires_at,created_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)", [id, user, kind, media, caption, p.lat, p.lng, place, status, hrs(expires), hrs(created)]); return id; };
const P1 = await post(SARA, ORIGIN, { caption: 'قهوة الصباح عند الكورنيش والجو رايق' });
await pool.query('INSERT INTO map_post_likes(post_id,user_id) VALUES($1,$2),($1,$3)', [P1, AMR, NORA]);
const P2 = await post(KHALID, ORIGIN, { caption: 'لحظة خالد', kind: 'text', media: null });   // محظور عند عمرو
const P3 = await post(SARA, ORIGIN, { caption: 'منتهية', created: -48, expires: -1 });         // منتهية
const P4 = await post(SARA, ORIGIN, { caption: 'مخفية', status: 'hidden' });                  // مخفية
const event = async (host, title, p, { starts = 48, ends = null, cancelled = false, hidden = false, place = 'حديقة الأمير', tiers = [] } = {}) => { const id = uid(); await pool.query("INSERT INTO events(id,host_id,title,starts_at,ends_at,place_name,lat,lng,cancelled,hidden) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)", [id, host, title, hrs(starts), ends == null ? null : hrs(ends), place, p?.lat ?? null, p?.lng ?? null, cancelled, hidden]); for (const price of tiers) await pool.query("INSERT INTO ticket_tiers(id,event_id,name,price,quantity) VALUES($1,$2,'عادي',$3,50)", [uid(), id, price]); return id; };
const E1 = await event(SARA, 'لقاء المطورين', ORIGIN, { starts: 48, tiers: [8000, 5000] });   // من 50 ر.س
const E2 = await event(SARA, 'سوق الشاطئ', MID, { starts: 72 });
const E3 = await event(NORA, 'يوغا الصباح', ORIGIN, { starts: 3, tiers: [0] });             // تبدأ خلال 6 ساعات: الدفعة -1، مجاناً
const E4 = await event(SARA, 'ملغاة', ORIGIN, { cancelled: true });
const E5 = await event(SARA, 'مخفية', ORIGIN, { hidden: true });
const E6 = await event(SARA, 'بلا موقع', null);
const E7 = await event(SARA, 'انتهت', ORIGIN, { starts: -30, ends: -2 });
const E8 = await event(SARA, 'جارية الآن', ORIGIN, { starts: -2 });                          // بدأت قبل ساعتين بلا نهاية
const job = async (bizId, title, { type = 'full', min = null, max = null, visible = false, status = 'open', pub = true, district = '' } = {}) => { const id = uid(); await pool.query("INSERT INTO jobs(id,biz_id,created_by,title,type,salary_min,salary_max,salary_visible,deadline,status,public,published_at,city,district) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,'جدة',$13)", [id, bizId, AMR, title, type, min, max, visible, hrs(240), status, pub, hrs(-24), district]); return id; };
const J1 = await job('row-reef', 'باريستا', { type: 'part', max: 4500, visible: true });
const J2 = await job('row-reef', 'مسودة', { status: 'draft' });
const J3 = await job('row-reef', 'غير عامة', { pub: false });
const J4 = await job('row-mid', 'كاشير', { type: 'full', min: 4000, max: 6000, visible: false, district: 'الشاطئ' });
const listing = async (seller, title, p, { price = 265000, images = ['https://naslife.app/seed/bike.jpg'], status = 'active', created = -2, publishAt = null, place = 'الروضة' } = {}) => { const id = uid(); await pool.query("INSERT INTO market_listings(id,seller_id,kind,category,title,price,images,place_name,lat,lng,status,created_at,publish_at) VALUES($1,$2,'product','sports',$3,$4,$5,$6,$7,$8,$9,$10,$11)", [id, seller, title, price, JSON.stringify(images), place, p?.lat ?? null, p?.lng ?? null, status, hrs(created), publishAt == null ? null : hrs(publishAt)]); return id; };
const L1 = await listing(NORA, 'دراجة هوائية', ORIGIN);
const L2 = await listing(NORA, 'مباعة', ORIGIN, { status: 'sold' });
const L3 = await listing(NORA, 'بلا موقع', null);
const L4 = await listing(NORA, 'مجدولة', ORIGIN, { publishAt: 24 });
const EXCLUDED = [O3, O4, O5, O6, P3, P4, E4, E5, E6, E7, J2, J3, L2, L3, L4];
const NEAR = [O1, P1, E1, E3, E8, J1, L1], MIDS = [O2, E2, J4];
const Q = `/row?lat=${ORIGIN.lat}&lng=${ORIGIN.lng}`;

// ---- الحالة
const st = await call('GET', '/row/status', { user: null, expect: 200 });
check(st.ok === true && KINDS.every((k) => st.sources[k] === true), 'status detects the five source tables', JSON.stringify(st));

// ---- الترتيب بالموقع
let r = await call('GET', Q, { expect: 200 });
check(r.located === true && r.items.length === NEAR.length + MIDS.length, 'located call returns the near and mid items only', `${r.items.length}`);
check(EXCLUDED.every((id) => !ids(r).includes(id)), 'inactive, upcoming, expired, hidden, cancelled, draft, private, sold, scheduled and no-location rows excluded');
check(!ids(r).includes(O3), 'items beyond the radius excluded');
check(NEAR.every((id) => at(r, id) >= 0) && Math.max(...NEAR.map((id) => at(r, id))) < Math.min(...MIDS.map((id) => at(r, id))), 'near items rank before the 8 km ones', r.items.map((i) => i.kind + ':' + (i.distanceKm ?? '-')).join(' '));
check(r.items[0].id === O1 && at(r, O1) < at(r, L1), 'offer ending within the hour ranks first, before the equally near listing');
check(at(r, E3) === 1, 'free event starting within 6 hours ranks second', String(at(r, E3)));
check(r.items.every((i) => typeof i.distanceKm === 'number') && NEAR.every((id) => byId(r, id).distanceKm < 0.5) && MIDS.every((id) => byId(r, id).distanceKm > 6 && byId(r, id).distanceKm < 10), 'distanceKm computed for every item');
check(!ids(r).includes(P2), 'moments by a blocked author are hidden from the blocker');

// ---- شكل البطاقة لكل نوع
check(r.items.every((i) => KINDS.includes(i.kind) && i.id && i.refId && typeof i.title === 'string' && i.title && typeof i.subtitle === 'string' && i.subtitle.length <= 60 && i.act === ACT[i.kind] && Number.isFinite(i.lat) && Number.isFinite(i.lng) && typeof i.at === 'string' && i.payload && typeof i.payload === 'object'), 'every item has the contract shape');
const o1 = byId(r, O1);
check(o1.refId === 'row-reef' && o1.who === 'مقهى ريف' && o1.title === 'كورتادو بـ 10' && o1.subtitle === 'مقهى ريف · ينتهي خلال ساعة' && o1.logoUrl === 'https://naslife.app/seed/reef.png' && o1.imageUrl === o1.logoUrl && o1.endsAt === hrs(1) && o1.act === 'استخدم', 'offer card: bizId, business name, ends-soon subtitle, logo', JSON.stringify(o1));
const o2 = byId(r, O2);
check(o2.subtitle === 'مطعم الشاطئ · ينتهي بعد 3 أيام' && o2.at === hrs(-24), 'offer card: ends-in-days subtitle and at = startsAt', o2.subtitle);
const p1 = byId(r, P1);
check(p1.refId === P1 && p1.title === 'قهوة الصباح عند الكورنيش والجو رايق' && p1.subtitle === 'قبل 2 س · إعجابان' && p1.who === 'sara' && p1.logoUrl === 'https://naslife.app/seed/sara.png' && p1.imageUrl === 'https://naslife.app/chat/media/x.jpg' && p1.at === hrs(-2) && p1.endsAt === hrs(22) && p1.act === 'شاهد', 'moment card: caption title, ago + likes subtitle, author, media', JSON.stringify(p1));
const pl = p1.payload;
check(pl.id === P1 && pl.user?.nickname === 'sara' && pl.user?.avatarUrl === 'https://naslife.app/seed/sara.png' && pl.kind === 'image' && pl.mediaUrl === p1.imageUrl && pl.caption === p1.title && Array.isArray(pl.overlays) && pl.likes === 2 && pl.liked === true && pl.mine === false && pl.expired === false && pl.placeName === 'الكورنيش' && pl.status === 'active' && typeof pl.expiresAt === 'string' && typeof pl.createdAt === 'string' && 'audioUrl' in pl && 'cta' in pl && 'views' in pl, 'moment payload matches the GET /mapposts shape', JSON.stringify(pl));
const e1 = byId(r, E1);
check(e1.refId === E1 && e1.title === 'لقاء المطورين' && e1.subtitle.startsWith('حديقة الأمير · ') && e1.subtitle.endsWith(' · من 50 ر.س') && e1.who === 'sara' && e1.imageUrl === null && e1.at === hrs(48) && e1.endsAt === null && e1.act === 'تذكرة', 'event card: place, time, min tier price, host', JSON.stringify(e1));
const e3 = byId(r, E3);
check(e3.subtitle.endsWith(' · مجاناً') && /اليوم|غداً/.test(e3.subtitle), 'event card: free tier shows مجاناً and today/tomorrow', e3.subtitle);
check(byId(r, E8) && byId(r, E8).subtitle.includes('حديقة الأمير'), 'event that started two hours ago without an end is still listed');
const j1 = byId(r, J1);
check(j1.refId === 'row-reef' && j1.title === 'باريستا' && j1.subtitle === 'دوام جزئي · 4,500 ر.س' && j1.who === 'مقهى ريف' && j1.logoUrl === 'https://naslife.app/seed/reef.png' && j1.imageUrl === null && j1.at === hrs(-24) && j1.endsAt === hrs(240) && j1.act === 'قدّم', 'job card: bizId, type and visible salary, deadline', JSON.stringify(j1));
check(byId(r, J4).subtitle === 'دوام كامل · الشاطئ', 'job card: hidden salary falls back to the district', byId(r, J4).subtitle);
const l1 = byId(r, L1);
check(l1.refId === L1 && l1.title === 'دراجة هوائية' && l1.subtitle === '2,650 ر.س · الروضة' && l1.who === 'nora' && l1.imageUrl === 'https://naslife.app/seed/bike.jpg' && l1.at === hrs(-2) && l1.endsAt === null && l1.act === 'اطلب', 'listing card: price and place subtitle, first image, seller', JSON.stringify(l1));

// ---- الضيف ونصف القطر وبلا موقع والحد
const g = await call('GET', Q, { user: null, expect: 200 });
check(g.items.length === NEAR.length + MIDS.length + 1 && ids(g).includes(P2) && g.items.every((i) => i.payload.mine !== true && i.payload.liked !== true), 'guest gets 200 with the blocked author visible and nothing personal');
r = await call('GET', `${Q}&radiusKm=5`, { expect: 200 });
check(r.items.length === NEAR.length && MIDS.every((id) => !ids(r).includes(id)), 'radiusKm=5 drops the 8 km items', String(r.items.length));
r = await call('GET', '/row', { expect: 200 });
// بلا موقع لا نصف قطر، فعرض الدمام يدخل القائمة أيضاً
check(r.located === false && r.items.length === NEAR.length + MIDS.length + 1 && ids(r).includes(O3) && r.items.every((i) => i.distanceKm === null), 'no location: located=false, every item including the far one, no distance', `${r.located} ${r.items.length}`);
check(r.items[0].id === O1 && at(r, E3) === 1, 'no location: boosts still order the ending-soon offer and the soon event first');
r = await call('GET', '/row?lat=999&lng=39', { expect: 200 });
check(r.located === false, 'out-of-range coordinates count as no location');
r = await call('GET', `${Q}&limit=2`, { expect: 200 });
check(r.items.length === 2 && r.items[0].id === O1, 'limit=2 honoured');
r = await call('GET', `${Q}&limit=500`, { expect: 200 });
check(r.items.length === NEAR.length + MIDS.length, 'limit above 50 is clamped and returns everything available');
r = await call('GET', `${Q}&limit=abc&radiusKm=zzz`, { expect: 200 });
check(r.items.length === NEAR.length + MIDS.length, 'bad limit and radius fall back to the defaults');

// ---- التوزيع: ست إعلانات إضافية على الأصل لا تتوالى أكثر من ثلاث
const extra = []; for (let i = 0; i < 6; i++) extra.push(await listing(NORA, `إعلان ${i + 1}`, ORIGIN, { created: -3, price: 1000 * (i + 1) }));
r = await call('GET', Q, { expect: 200 });
check(r.items.length === NEAR.length + MIDS.length + 6 && r.items.filter((i) => i.kind === 'listing').length === 7, 'six more listings all returned', String(r.items.length));
check(maxRun(r) <= 3, 'no more than three consecutive items of one kind', r.items.map((i) => i.kind[0]).join(''));
check(r.items[0].id === O1 && extra.every((id) => at(r, id) >= 0), 'interleave keeps the ending-soon offer first and loses nothing');
r = await call('GET', '/row', { expect: 200 });
check(maxRun(r) <= 3, 'interleave also applies without a location', r.items.map((i) => i.kind[0]).join(''));

// ---- حد 12 لكل نوع
for (let i = 0; i < 10; i++) await listing(NORA, `إعلان إضافي ${i + 1}`, ORIGIN, { created: -4 });
r = await call('GET', `${Q}&limit=50`, { expect: 200 });
check(r.items.filter((i) => i.kind === 'listing').length === 12 && r.items.length === 12 + NEAR.length + MIDS.length - 1, 'a kind is capped at 12 in the final list', `${r.items.filter((i) => i.kind === 'listing').length} of ${r.items.length}`);
check(maxRun(r) <= 3, 'cap and interleave together', r.items.map((i) => i.kind[0]).join(''));
r = await call('GET', Q, { expect: 200 });
check(r.items.length === 21 && maxRun(r) <= 3, 'default limit 30 returns the 21 available', String(r.items.length));

// ---- جدول غائب: النوع يسقط وحده والصف يبقى
await pool.query('DROP TABLE jobs');
const st2 = await call('GET', '/row/status', { user: null, expect: 200 });
check(st2.sources.job === false && st2.sources.offer === true, 'status reports the missing table', JSON.stringify(st2.sources));
r = await call('GET', Q, { expect: 200 });
check(r.items.length === 19 && r.items.every((i) => i.kind !== 'job') && ids(r).includes(O1) && ids(r).includes(P1), 'row still answers without the jobs table', String(r.items.length));

await app.close(); await pool.end();
console.log(fails ? `\n${fails} FAILED` : '\nALL ROW TESTS PASSED');
process.exit(fails ? 1 : 0);
