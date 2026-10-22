// «التغذية» GET /feed (server/row.js): البطاقات نفسها كما /row لكن الأحدث نشراً أولاً عبر الأنواع (feedAt، و«at» كما في /row)، التصفية بالنوع،
// المؤشر المركّب «feedAt~k~id» بصفحات بلا تكرار ولا فجوة (طابع بالميكروثانية، ثلاث فعاليات في ملي ثانية واحدة، لحظات بإدراج واحد، تعادل عبر الأنواع)،
// ISO وحده للعملاء الأقدم، حدّ الصفحة 1..40، نصف القطر والترتيب يبقى زمنياً لا بالقرب، فعالية بعيدة الموعد لا تدفن الجديد، الحظر والضيف
// (ولا يرى الضيف فعاليات الدوائر الخاصة ولا أحد يرى وظائف دائرة موقوفة أو مخفية، في /feed و/row)، حمولة اللحظة، التطابق مع بطاقة /row،
// الجدول الغائب، وأن /row لم يتغير. (الاسم harness_feed.mjs مأخوذ لبث /mapposts/feed.)
import Fastify from 'fastify';
import pg from 'pg';
import crypto from 'node:crypto';
import { KINDS, FEED_LIMIT_MAX, LIMIT_DEFAULT, parseCursor, feedCmp, cursorOf, byteCmp } from '../row.js';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0';
let fails = 0;
const check = (c, l, extra = '') => { if (!c) fails++; console.log((c ? 'OK  ' : 'FAIL') + ' ' + l + (extra ? ' ' + extra : '')); };
const NOW = Date.now(), H = 3600000;
const hrs = (n) => new Date(NOW + n * H).toISOString();

// ---- وحدات خالصة: المؤشر وترتيب التغذية
const T0 = '2026-10-22T10:00:00.123Z';
check(JSON.stringify(parseCursor(`${T0}~2~abc`)) === JSON.stringify({ at: T0, k: 2, id: 'abc' }), 'parseCursor reads feedAt~k~id');
check(parseCursor(`${T0}~1~a~b`)?.id === 'a~b', 'parseCursor keeps a ~ inside the id');
const bare = parseCursor(T0);
check(bare && bare.at === T0 && bare.k === KINDS.length && bare.id === '', 'a bare ISO (old clients) is strictly-before: kind index past every kind');
check(['garbage', 'x~1~y', `${T0}~6~a`, `${T0}~-1~a`, `${T0}~1~`, `${T0}~~a`, `${T0}~1`, '', null].every((s) => parseCursor(s) === null), 'unparsable cursors are null (ignored)');
const e = (ms, k, id) => ({ ms, k, id });
check([e(1, 0, 'b'), e(2, 4, 'a'), e(2, 0, 'z'), e(1, 0, 'B'), e(1, 0, '\u{1F600}'), e(1, 0, '\uFFFF')].sort(feedCmp).map((x) => `${x.ms}${x.k}${x.id}`).join(' ') === '20z 24a 10B 10b 10\uFFFF 10\u{1F600}',
  'feedCmp: newest ms, then kind order, then id by code point (B before b; U+FFFF before an emoji, unlike UTF-16 order)');
check(byteCmp('B', 'a') < 0 && byteCmp('\uFFFF', '\u{1F600}') < 0 && byteCmp('a', 'a') === 0, 'byteCmp is code point order');
check(cursorOf(e(Date.parse(T0), 3, 'id-1')) === `${T0}~3~id-1` && JSON.stringify(parseCursor(cursorOf(e(Date.parse(T0), 3, 'id-1')))) === JSON.stringify({ at: T0, k: 3, id: 'id-1' }), 'cursorOf round-trips through parseCursor');

// ---- التجهيز: الإضافات المالكة للجداول تُنشئها، والبذر مباشر بـ SQL
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("INSERT INTO users(id,nickname,avatar_url) VALUES('SA0000001','amr',NULL),('SA0000002','sara','https://naslife.app/seed/sara.png'),('SA0000003','khalid',NULL),('SA0000004','nora',NULL) ON CONFLICT (id) DO UPDATE SET nickname=EXCLUDED.nickname, avatar_url=EXCLUDED.avatar_url");
// جدول الدوائر من النواة بعمود الخصوصية كما في harness_guest؛ يُنشأ قبل أول طلب ضيف لأن commerce.js يكتشف العمود مرة واحدة
await pool.query("CREATE TABLE IF NOT EXISTS vessels (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), name TEXT, topic TEXT, kind TEXT DEFAULT 'general', is_public BOOLEAN DEFAULT true, owner_id TEXT, created_at TIMESTAMPTZ DEFAULT now())");
for (const sql of ['DROP TABLE IF EXISTS map_post_likes, map_post_views, map_post_events, map_posts, biz_offers, ticket_tiers, tickets, events, jobs, market_listings CASCADE', "DELETE FROM biz WHERE id LIKE 'rfeed-%'", "DELETE FROM vessels WHERE owner_id='rfeed-owner'", 'DELETE FROM app_notifications']) { try { await pool.query(sql); } catch { /* first run */ } }
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
const byId = (r, id) => r.items.find((i) => i.id === id);
const same = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);
const short = (r) => r.items.map((i) => i.kind[0] + ':' + i.feedAt.slice(11, 19)).join(' ');
const maxRun = (r) => { let best = 0, run = 0, last = null; for (const i of r.items) { run = i.kind === last ? run + 1 : 1; last = i.kind; best = Math.max(best, run); } return best; };
const cur = (i) => `${i.feedAt}~${KINDS.indexOf(i.kind)}~${i.id}`;
// يمشي الصفحات بالمؤشر حتى النهاية ويعيد المعرّفات بترتيبها وعدد الصفحات
const walk = async (q, limit, user = null) => { const out = []; let c = null, pages = 0; do { const pg = await call('GET', `/feed?${q}&limit=${limit}${c ? '&before=' + encodeURIComponent(c) : ''}`, { user }); out.push(...ids(pg)); c = pg.next; pages++; } while (c && pages < 200); return { ids: out, pages }; };

// ---- البذر: الأصل (21.54, 39.17) جدة؛ متوسط ≈ 8 كم؛ بعيد = الدمام. أزمنة النشر متباعدة حتى يكون الترتيب الزمني قاطعاً
const ORIGIN = { lat: 21.54, lng: 39.17 }, MID = { lat: 21.61, lng: 39.19 }, DMM = { lat: 26.43, lng: 50.10 };
const biz = async (id, nameAr, p, extra = {}) => { await pool.query("INSERT INTO biz(id,name,name_ar,category,lat,lng,address,active,logo_url) VALUES($1,$2,$3,'cafe',$4,$5,'الروضة',$6,$7)", [id, id, nameAr, p.lat, p.lng, extra.active !== false, extra.logo ?? null]); if (extra.hidden) await pool.query('UPDATE biz SET hidden=true WHERE id=$1', [id]); };
await biz('rfeed-reef', 'مقهى ريف', ORIGIN, { logo: 'https://naslife.app/seed/reef.png' });
await biz('rfeed-mid', 'مطعم الشاطئ', MID);
await biz('rfeed-dmm', 'كافيه الدمام', DMM);
await biz('rfeed-mob', 'عربة قهوة', ORIGIN);
await biz('rfeed-hid', 'دائرة مخفية', ORIGIN, { hidden: true });
await biz('rfeed-off', 'دائرة موقوفة', ORIGIN, { active: false });
// دائرة متنقلة ثبّتت «هنا اليوم» قبل ساعة ونصف حتى بعد خمس ساعات (at = feedAt = setAt)
await pool.query('UPDATE biz SET here=$2::jsonb WHERE id=$1', ['rfeed-mob', JSON.stringify({ lat: ORIGIN.lat, lng: ORIGIN.lng, until: hrs(5), setAt: hrs(-1.5) })]);
const C1 = 'rfeed-mob';
// العرض: «at» بدايته، وزمن نشره الأحدث من إنشائه وبدايته (الافتراضي أُنشئ حين بدأ)
const offer = async (bizId, title, startsH, endsH, { active = true, created = startsH } = {}) => { const id = uid(); await pool.query("INSERT INTO biz_offers(id,biz_id,kind,title,value,members_only,starts_at,ends_at,active,created_at) VALUES($1,$2,'deal',$3,'{\"type\":\"percent\",\"amount\":15}',false,$4,$5,$6,$7)", [id, bizId, title, hrs(startsH), endsH == null ? null : hrs(endsH), active, hrs(created)]); return id; };
const O1 = await offer('rfeed-reef', 'كورتادو بـ 10', -2, 1);
const O2 = await offer('rfeed-mid', 'عشاء لشخصين', -24, 72);
const O3 = await offer('rfeed-dmm', 'عرض الدمام', -2.5, 48);                      // بعيد: يظهر بلا موقع فقط
const O4 = await offer('rfeed-reef', 'عرض موقوف', -2, 48, { active: false });     // غير مفعّل
const O5 = await offer('rfeed-reef', 'عرض الغد', 24, 72);                          // لم يبدأ
const O6 = await offer('rfeed-mid', 'عرض مجدول', -0.75, 48, { created: -30 });    // أُنشئ قبل يوم وبدأ قبل 45 د: نُشر حين بدأ
const post = async (user, p, { caption = '', kind = 'image', media = 'https://naslife.app/chat/media/x.jpg', created = -2, micros = 0, expires = 22, status = 'active', place = 'الكورنيش', id = uid() } = {}) => { await pool.query("INSERT INTO map_posts(id,user_id,kind,media_url,caption,lat,lng,place_name,status,expires_at,created_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11::timestamptz + ($12 || ' microseconds')::interval)", [id, user, kind, media, caption, p.lat, p.lng, place, status, hrs(expires), hrs(created), String(micros)]); return id; };
const P1 = await post(SARA, ORIGIN, { caption: 'قهوة الصباح عند الكورنيش', created: -0.5 });
await pool.query('INSERT INTO map_post_likes(post_id,user_id) VALUES($1,$2),($1,$3)', [P1, AMR, NORA]);
const P2 = await post(KHALID, ORIGIN, { caption: 'لحظة خالد', kind: 'text', media: null, created: -1 });   // محظور عند عمرو
const P3 = await post(SARA, DMM, { caption: 'من الدمام', created: -3 });                                  // بعيد
const P4 = await post(SARA, ORIGIN, { caption: 'منتهية', created: -48, expires: -1 });
const P5 = await post(SARA, ORIGIN, { caption: 'مخفية', status: 'hidden', created: -0.1 });
// الفعالية: «at» موعدها، وزمن نشرها created_at
const event = async (host, title, p, { starts = 48, ends = null, cancelled = false, place = 'حديقة الأمير', tiers = [], created = -1, micros = 0, vessel = null, id = uid() } = {}) => { await pool.query("INSERT INTO events(id,host_id,title,starts_at,ends_at,place_name,lat,lng,cancelled,hidden,created_at,vessel_id) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,false,$10::timestamptz + ($11 || ' microseconds')::interval,$12)", [id, host, title, hrs(starts), ends == null ? null : hrs(ends), place, p?.lat ?? null, p?.lng ?? null, cancelled, hrs(created), String(micros), vessel]); for (const price of tiers) await pool.query("INSERT INTO ticket_tiers(id,event_id,name,price,quantity) VALUES($1,$2,'عادي',$3,50)", [uid(), id, price]); return id; };
const E1 = await event(SARA, 'لقاء المطورين', ORIGIN, { starts: 48, created: -1.2, tiers: [8000, 5000] });   // موعد بعد يومين، نُشرت قبل 72 د
const E2 = await event(NORA, 'سوق الشاطئ', MID, { starts: -2.2, created: -26 });                               // بدأت قبل ساعتين بلا نهاية، نُشرت أمس
const E3 = await event(SARA, 'ملغاة', ORIGIN, { cancelled: true, created: -0.2 });
const E9 = await event(SARA, 'مهرجان الشتاء', ORIGIN, { starts: 720, created: -50 });                          // بعد شهر: لا تتصدر التغذية
const job = async (bizId, title, { type = 'full', max = null, visible = false, status = 'open', pubH = -24 } = {}) => { const id = uid(); await pool.query("INSERT INTO jobs(id,biz_id,created_by,title,type,salary_min,salary_max,salary_visible,deadline,status,public,published_at,city,district) VALUES($1,$2,$3,$4,$5,NULL,$6,$7,$8,$9,true,$10,'جدة','')", [id, bizId, AMR, title, type, max, visible, hrs(240), status, hrs(pubH)]); return id; };
const J1 = await job('rfeed-reef', 'باريستا', { type: 'part', max: 4500, visible: true, pubH: -20 });
const J2 = await job('rfeed-reef', 'مسودة', { status: 'draft', pubH: -0.2 });
const J3 = await job('rfeed-dmm', 'كاشير الدمام', { pubH: -5 });                                  // بعيد
const J4 = await job('rfeed-hid', 'وظيفة دائرة مخفية', { pubH: -0.1 });                           // الدائرة مخفية بالإشراف
const J5 = await job('rfeed-off', 'وظيفة دائرة موقوفة', { pubH: -0.1 });                          // الدائرة موقوفة
const listing = async (seller, title, p, { price = 265000, status = 'active', created = -2, bumped = null, micros = 0, id = uid() } = {}) => { await pool.query(`INSERT INTO market_listings(id,seller_id,kind,category,title,price,images,place_name,lat,lng,status,created_at,bumped_at) VALUES($1,$2,'product','sports',$3,$4,'["https://naslife.app/seed/bike.jpg"]','الروضة',$5,$6,$7,$8::timestamptz + ($10 || ' microseconds')::interval,$9)`, [id, seller, title, price, p?.lat ?? null, p?.lng ?? null, status, hrs(created), bumped == null ? null : hrs(bumped), String(micros)]); return id; };
const L1 = await listing(NORA, 'دراجة هوائية', ORIGIN, { created: -4 });
const L2 = await listing(NORA, 'مرفوعة للتو', MID, { created: -30, bumped: -0.25 });              // feedAt = at = bumped_at
const L3 = await listing(NORA, 'مباعة', ORIGIN, { status: 'sold', created: -0.3 });
const L4 = await listing(NORA, 'دراجة الدمام', DMM, { created: -6 });                              // بعيد
const X = await listing(NORA, 'بالميكروثانية', ORIGIN, { created: -3.5, micros: 456 });              // طابع زمني أدق من الملي ثانية: اختبار المؤشر
const EXCLUDED = [O4, O5, P4, P5, E3, J2, J4, J5, L3];
// زمن النشر بالساعات، الأحدث أولاً (الضيف، بلا موقع): الترتيب المتوقع للتغذية كلها
const FEED_H = new Map([[L2, -0.25], [P1, -0.5], [O6, -0.75], [P2, -1], [E1, -1.2], [C1, -1.5], [O1, -2], [O3, -2.5], [P3, -3], [X, -3.5], [L1, -4], [J3, -5], [L4, -6], [J1, -20], [O2, -24], [E2, -26], [E9, -50]]);
const ALL_GUEST = [...FEED_H.keys()];
check(ALL_GUEST.every((id, i) => i === 0 || FEED_H.get(ALL_GUEST[i - 1]) > FEED_H.get(id)), 'seed: expected order is strictly newest-first');
const ALL_AMR = ALL_GUEST.filter((id) => id !== P2);
const FAR = [O3, P3, J3, L4], MIDS = [L2, O6, E2, O2];
const NEAR_GUEST = ALL_GUEST.filter((id) => !FAR.includes(id));
const Q = `lat=${ORIGIN.lat}&lng=${ORIGIN.lng}`;

// ---- بلا موقع: الأحدث نشراً أولاً عبر الأنواع، كل شيء بما فيه البعيد، بلا مسافة، وبلا next لأن الصفحة لم تمتلئ
let r = await call('GET', '/feed', { user: null, expect: 200 });
check(r.located === false && same(ids(r), ALL_GUEST), 'guest without location: every active item newest-published first across kinds', short(r));
check(r.next === null && r.items.every((i) => i.distanceKm === null), 'no location: next is null below the page size and no distances');
check(EXCLUDED.every((id) => !ids(r).includes(id)), 'inactive, upcoming, expired, hidden, cancelled, draft, sold rows and jobs of hidden/inactive circles excluded');
check(r.items.every((i) => KINDS.includes(i.kind) && i.id && i.refId && typeof i.title === 'string' && i.title && typeof i.subtitle === 'string' && typeof i.at === 'string' && i.payload && typeof i.payload === 'object' && typeof i.act === 'string'), 'every item has the /row contract shape');
check(r.items.every((i) => i.feedAt === hrs(FEED_H.get(i.id))), 'every item carries feedAt = its publish time (ms ISO; the microsecond row floors to its millisecond)', r.items.filter((i) => i.feedAt !== hrs(FEED_H.get(i.id))).map((i) => i.kind + ' ' + i.feedAt).join(', '));
check(byId(r, E1).at === hrs(48) && byId(r, E1).feedAt === hrs(-1.2), 'event card keeps at = its start time; feedAt is when it was published');
check(ids(r).indexOf(P1) < ids(r).indexOf(E1) && ids(r).at(-1) === E9 && r.items[0].kind !== 'event', 'far-future events do not bury fresh moments: the event a month away sorts by its publish time (last)', short(r));
check(byId(r, O6).at === hrs(-0.75) && byId(r, O6).feedAt === hrs(-0.75) && byId(r, O1).at === hrs(-2), 'a scheduled offer counts as published when it starts (later of created and starts)');
check(byId(r, L2).at === hrs(-0.25) && byId(r, L2).feedAt === hrs(-0.25) && byId(r, L2).title === 'مرفوعة للتو', 'listing at = feedAt = bumped_at when bumped');
check(byId(r, C1).kind === 'circle' && byId(r, C1).at === hrs(-1.5) && byId(r, C1).feedAt === hrs(-1.5) && byId(r, C1).payload.here === true, 'circle card sorts by its setAt and carries the here payload');
const p1 = byId(r, P1);
check(p1.kind === 'moment' && p1.payload.id === P1 && p1.payload.user?.nickname === 'sara' && p1.payload.kind === 'image' && p1.payload.mediaUrl === 'https://naslife.app/chat/media/x.jpg' && p1.payload.likes === 2 && p1.payload.liked === false && p1.payload.mine === false && 'expiresAt' in p1.payload, 'moment carries the post payload with its id (guest: nothing personal)', JSON.stringify(p1.payload).slice(0, 200));

// ---- الحظر والشخصي
r = await call('GET', '/feed', { expect: 200 });
check(same(ids(r), ALL_AMR), 'blocker does not see the blocked author\'s moment', short(r));
check(byId(r, P1).payload.liked === true && byId(r, P1).payload.mine === false, 'viewer\'s like shows in the payload');

// ---- الموقع: نصف القطر يقصر، الترتيب يبقى زمنياً لا بالقرب
r = await call('GET', `/feed?${Q}`, { user: null, expect: 200 });
check(r.located === true && same(ids(r), NEAR_GUEST), 'located: far items dropped, order still newest-first', short(r));
check(r.items.every((i) => typeof i.distanceKm === 'number') && byId(r, P1).distanceKm < 0.5 && byId(r, L2).distanceKm > 6, 'distanceKm filled for every item');
check(ids(r).indexOf(L2) < ids(r).indexOf(P1), 'the 8 km listing bumped 15 minutes ago ranks above the moment at the origin from 30 minutes ago (time, not distance)');
r = await call('GET', `/feed?${Q}&radiusKm=5`, { user: null, expect: 200 });
check(same(ids(r), NEAR_GUEST.filter((id) => !MIDS.includes(id))), 'radiusKm=5 drops the 8 km items too', short(r));
r = await call('GET', '/feed?lat=999&lng=39', { user: null, expect: 200 });
check(r.located === false && ids(r).length === ALL_GUEST.length, 'out-of-range coordinates count as no location');

// ---- التطابق مع /row: البطاقة نفسها من البنّاء نفسه، والتغذية تزيد feedAt فقط
const row = await call('GET', `/row?${Q}&limit=50`, { expect: 200 });
const feed = await call('GET', `/feed?${Q}&limit=40`, { expect: 200 });
const strip = ({ feedAt, ...card }) => card;
check(same([...ids(row)].sort(), [...ids(feed)].sort()), 'located /row and /feed return the same set of items', `${row.items.length} vs ${feed.items.length}`);
check(feed.items.every((i) => JSON.stringify(byId(row, i.id)) === JSON.stringify(strip(i))), 'every feed item minus feedAt is byte-identical to its /row card');
check(row.items.every((i) => !('feedAt' in i)), '/row cards carry no feedAt (contract unchanged)');
check(!ids(row).includes(J4) && !ids(row).includes(J5), '/row hides jobs of hidden and inactive circles too');

// ---- التصفية بالنوع
const kindIds = async (kind) => ids(await call('GET', `/feed?kind=${kind}`, { user: null, expect: 200 }));
check(same(await kindIds('moment'), [P1, P2, P3]), 'kind=moment');
check(same(await kindIds('offer'), [O6, O1, O3, O2]), 'kind=offer');
check(same(await kindIds('event'), [E1, E2, E9]), 'kind=event: newest-published first, not furthest-first');
check(same(await kindIds('job'), [J3, J1]), 'kind=job: hidden and inactive circles\' jobs excluded');
check(same(await kindIds('listing'), [L2, X, L1, L4]), 'kind=listing');
check(same(await kindIds('circle'), [C1]), 'kind=circle');
check(same(await kindIds('all'), ALL_GUEST) && same(await kindIds('bogus'), ALL_GUEST), 'kind=all and an unknown kind merge every kind');

// ---- المؤشر: صفحات متتالية بلا تكرار ولا فجوة، والحدّ بين الصفحات يقع على الطابع بالميكروثانية
const pg1 = await call('GET', '/feed?limit=5', { user: null, expect: 200 });
check(same(ids(pg1), ALL_GUEST.slice(0, 5)) && pg1.next === cur(byId(pg1, E1)), 'page 1: five newest and next = feedAt~kind~id of the last card', pg1.next);
check(/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z~\d~[0-9a-f-]{36}$/.test(pg1.next), 'cursor is opaque feedAt(ms ISO)~kindIndex~id', pg1.next);
const pg2 = await call('GET', `/feed?limit=5&before=${encodeURIComponent(pg1.next)}`, { user: null, expect: 200 });
check(same(ids(pg2), ALL_GUEST.slice(5, 10)) && pg2.next === cur(byId(pg2, X)), 'page 2 continues after the cursor and ends on the microsecond-stamped listing', short(pg2));
const pg3 = await call('GET', `/feed?limit=5&before=${encodeURIComponent(pg2.next)}`, { user: null, expect: 200 });
check(same(ids(pg3), ALL_GUEST.slice(10, 15)) && ids(pg3)[0] === L1 && pg3.next === cur(byId(pg3, O2)), 'page 3 starts right after it: no repeat of the microsecond row and no gap', short(pg3));
const pg4 = await call('GET', `/feed?limit=5&before=${encodeURIComponent(pg3.next)}`, { user: null, expect: 200 });
check(same(ids(pg4), ALL_GUEST.slice(15)) && pg4.next === null, 'the short last page carries next=null', short(pg4));
check(same([...ids(pg1), ...ids(pg2), ...ids(pg3), ...ids(pg4)], ALL_GUEST), 'pages concatenate to the full list');
r = await call('GET', '/feed?kind=moment&limit=3', { user: null, expect: 200 });
const fullLast = await call('GET', `/feed?kind=moment&limit=3&before=${encodeURIComponent(r.next)}`, { user: null, expect: 200 });
check(same(ids(r), [P1, P2, P3]) && r.next !== null && fullLast.items.length === 0 && fullLast.next === null, 'a full last page still returns next; the page after it is empty with next null');
for (const bad of ['garbage', 'x~1~y', `${hrs(-2.3)}~9~${O3}`]) {
  r = await call('GET', `/feed?before=${encodeURIComponent(bad)}`, { user: null, expect: 200 });
  check(same(ids(r), ALL_GUEST), `an unparsable before is ignored (${bad.slice(0, 12)})`);
}
// ISO وحده (عملاء أقدم): أقدم نشراً من ذلك الزمن تماماً، والبطاقة التي زمنها يساويه لا تُعاد
r = await call('GET', `/feed?before=${encodeURIComponent(hrs(-2.3))}`, { user: null, expect: 200 });
check(same(ids(r), ALL_GUEST.filter((id) => FEED_H.get(id) < -2.3)), 'a bare ISO before=-2.3h keeps strictly older items only', short(r));
r = await call('GET', `/feed?before=${encodeURIComponent(hrs(-2))}`, { user: null, expect: 200 });
check(same(ids(r), ALL_GUEST.filter((id) => FEED_H.get(id) < -2)) && !ids(r).includes(O1), 'a bare ISO equal to a card\'s feedAt excludes that card (strict)');
r = await call('GET', `/feed?kind=moment&limit=1`, { user: null, expect: 200 });
check(same(ids(r), [P1]) && r.next === cur(byId(r, P1)), 'cursor with a kind filter: first moment');
r = await call('GET', `/feed?kind=moment&limit=1&before=${encodeURIComponent(r.next)}`, { user: null, expect: 200 });
check(same(ids(r), [P2]), 'cursor with a kind filter: second moment');
r = await call('GET', `/feed?${Q}&limit=3`, { user: null, expect: 200 });
check(same(ids(r), NEAR_GUEST.slice(0, 3)) && r.next === cur(r.items[2]), 'cursor and radius together: first page');
r = await call('GET', `/feed?${Q}&limit=3&before=${encodeURIComponent(r.next)}`, { user: null, expect: 200 });
check(same(ids(r), NEAR_GUEST.slice(3, 6)), 'cursor and radius together: second page keeps the radius', short(r));

// ---- التعادل في الملي ثانية نفسها: ثلاث فعاليات معرّفاتها بعكس ترتيب ميكروثوانيها، ولحظة وإعلان في الملي ثانية نفسها،
// وثلاث لحظات بإدراج واحد (now() واحد). لا شيء يسقط ولا يتكرر مهما كان حجم الصفحة
const TIE = hrs(-0.1);
const TA = '00000000-0000-4000-8000-00000000000a', TB = '00000000-0000-4000-8000-00000000000b', TC = '00000000-0000-4000-8000-00000000000c';
await event(SARA, 'تعادل أ', ORIGIN, { created: -0.1, micros: 100, id: TA });
await event(SARA, 'تعادل ب', ORIGIN, { created: -0.1, micros: 900, id: TB });
await event(SARA, 'تعادل ج', ORIGIN, { created: -0.1, micros: 500, id: TC });
const TM = await post(SARA, ORIGIN, { caption: 'لحظة التعادل', created: -0.1, micros: 300 });
const TL = await listing(NORA, 'إعلان التعادل', ORIGIN, { created: -0.1, micros: 0 });
const S = [uid(), uid(), uid()];
await pool.query("INSERT INTO map_posts(id,user_id,kind,media_url,caption,lat,lng,place_name,status,expires_at) VALUES($1,'SA0000002','text',NULL,'دفعة 1',21.54,39.17,'الكورنيش','active',now()+interval '1 day'),($2,'SA0000002','text',NULL,'دفعة 2',21.54,39.17,'الكورنيش','active',now()+interval '1 day'),($3,'SA0000002','text',NULL,'دفعة 3',21.54,39.17,'الكورنيش','active',now()+interval '1 day')", S);
const SORTED_S = [...S].sort(byteCmp);
const TIED = [...SORTED_S, TM, TA, TB, TC, TL, ...ALL_GUEST];
r = await call('GET', '/feed?limit=40', { user: null, expect: 200 });
check(same(ids(r), TIED), 'one page: same-statement moments by id, then the tied millisecond as moment, events by id (not by microsecond), listing', short(r));
check([TM, TA, TB, TC, TL].every((id) => byId(r, id).feedAt === TIE) && new Set(S.map((id) => byId(r, id).feedAt)).size === 1, 'tied rows share one feedAt');
let p = await call('GET', '/feed?kind=event&limit=2', { user: null, expect: 200 });
check(same(ids(p), [TA, TB]) && p.next === `${TIE}~2~${TB}`, 'three events in one millisecond, limit=2: page 1 takes the first two by id although SQL meets the 900µs one first', `${ids(p)} ${p.next}`);
p = await call('GET', `/feed?kind=event&limit=2&before=${encodeURIComponent(p.next)}`, { user: null, expect: 200 });
check(same(ids(p), [TC, E1]), 'page 2 starts with the third tied event: nothing lost at the millisecond boundary', `${ids(p)}`);
for (const limit of [1, 2]) { const w = await walk('kind=event', limit); check(same(w.ids, [TA, TB, TC, E1, E2, E9]), `walking kind=event with limit=${limit} yields every event once in order`, `${w.ids.length} in ${w.pages}`); }
for (const limit of [1, 2]) { const w = await walk('kind=moment', limit); check(same(w.ids, [...SORTED_S, TM, P1, P2, P3]), `moments inserted in one statement: walking kind=moment with limit=${limit} loses none`, `${w.ids.length} in ${w.pages}`); }
for (const limit of [1, 2, 3, 7]) { const w = await walk('kind=all', limit); check(same(w.ids, TIED), `walking kind=all with limit=${limit} across the tied millisecond equals the single page`, `${w.ids.length} in ${w.pages}`); }
await pool.query('DELETE FROM events WHERE id = ANY($1::uuid[])', [[TA, TB, TC]]);
await pool.query('DELETE FROM map_posts WHERE id = ANY($1::uuid[])', [[TM, ...S]]);
await pool.query('DELETE FROM market_listings WHERE id=$1', [TL]);

// ---- الضيف وفعاليات الدوائر الخاصة: القاعدة نفسها في GET /events و/feed و/row؛ المسجّل يراها كما في GET /events
const vessel = async (pub) => (await pool.query("INSERT INTO vessels(name,is_public,owner_id) VALUES($1,$2,'rfeed-owner') RETURNING id", [pub ? 'دائرة عامة' : 'دائرة خاصة', pub])).rows[0].id;
const EV_PRIV = await event(SARA, 'لقاء الدائرة الخاصة', ORIGIN, { starts: 24, created: -0.05, vessel: await vessel(false) });
const EV_PUB = await event(SARA, 'لقاء الدائرة العامة', ORIGIN, { starts: 24, created: -0.06, vessel: await vessel(true) });
const evGuest = await call('GET', '/events', { user: null, expect: 200 });
check(Array.isArray(evGuest) && !evGuest.some((x) => x.id === EV_PRIV) && evGuest.some((x) => x.id === EV_PUB), 'reference: GET /events hides the private-circle event from a guest');
r = await call('GET', '/feed?kind=event', { user: null, expect: 200 });
check(!ids(r).includes(EV_PRIV) && same(ids(r), [EV_PUB, E1, E2, E9]), 'guest /feed?kind=event: no private-circle event, the public-circle one stays', short(r));
r = await call('GET', '/feed', { user: null, expect: 200 });
check(!ids(r).includes(EV_PRIV) && ids(r)[0] === EV_PUB, 'guest /feed (all): no private-circle event');
r = await call('GET', `/row?${Q}`, { user: null, expect: 200 });
check(!ids(r).includes(EV_PRIV) && ids(r).includes(EV_PUB), 'guest /row: no private-circle event either');
r = await call('GET', '/feed?kind=event', { expect: 200 });
check(same(ids(r), [EV_PRIV, EV_PUB, E1, E2, E9]), 'a signed-in viewer sees it, as in GET /events');
await pool.query('DELETE FROM events WHERE id = ANY($1::uuid[])', [[EV_PRIV, EV_PUB]]);
await pool.query("DELETE FROM vessels WHERE owner_id='rfeed-owner'");

// ---- حدّ الصفحة 1..40 وبلا حد 12 لكل نوع: 45 إعلاناً أقدم نشراً من كل شيء
const extra = []; for (let i = 0; i < 45; i++) extra.push(await listing(NORA, `إعلان ${i + 1}`, ORIGIN, { created: -60 - i / 60, price: 1000 * (i + 1) }));
r = await call('GET', '/feed?limit=500', { user: null, expect: 200 });
check(r.items.length === FEED_LIMIT_MAX && r.next === cur(r.items[FEED_LIMIT_MAX - 1]), 'limit above 40 is clamped to 40 with a cursor', String(r.items.length));
r = await call('GET', '/feed?limit=abc', { user: null, expect: 200 });
check(r.items.length === LIMIT_DEFAULT, 'bad limit falls back to the default 30', String(r.items.length));
r = await call('GET', '/feed?limit=0', { user: null, expect: 200 });
check(r.items.length === 1 && r.items[0].id === L2, 'limit=0 clamps to 1');
r = await call('GET', '/feed?kind=listing&limit=40', { user: null, expect: 200 });
check(r.items.length === 40 && r.items.filter((i) => i.kind === 'listing').length === 40, 'no per-kind cap of 12 in the feed (unlike /row)', String(r.items.length));
const all = await walk('kind=all', 40);
check(all.ids.length === ALL_GUEST.length + 45 && new Set(all.ids).size === all.ids.length && all.pages === 2 && extra.every((id) => all.ids.includes(id)), `walking every page with limit=40 yields all ${ALL_GUEST.length + 45} items once (40 + ${ALL_GUEST.length + 5}; the short page carries next=null)`, `${all.ids.length} in ${all.pages} pages`);
check(same(all.ids.slice(0, ALL_GUEST.length), ALL_GUEST), 'the newer base items still lead the walk');

// ---- /row لم يتغير: الأقرب أولاً مع الدفعات، حد 12 لكل نوع، والتوزيع ما دام نوع آخر باقياً (harness_row.mjs يغطي التفاصيل)
r = await call('GET', `/row?${Q}`, { expect: 200 });
check(r.items[0].id === O1 && r.items.filter((i) => i.kind === 'listing').length === 12 && maxRun({ items: r.items.slice(0, 12) }) <= 3 && !('next' in r) && r.items.every((i) => !('feedAt' in i)), '/row still ranks the ending-soon offer first, caps listings at 12, interleaves while other kinds remain, and has no cursor or feedAt', r.items.map((i) => i.kind[0]).join(''));

// ---- جدول غائب: النوع يسقط وحده والتغذية تبقى
await pool.query('DROP TABLE jobs');
r = await call('GET', '/feed', { user: null, expect: 200 });
check(r.items.length === 30 && r.items.every((i) => i.kind !== 'job') && ids(r).includes(E1) && ids(r).includes(P1), 'feed still answers without the jobs table', String(r.items.length));
r = await call('GET', '/feed?kind=job', { user: null, expect: 200 });
check(r.items.length === 0 && r.next === null, 'kind=job without its table is an empty page');

// تنظيف: دوائر الحزمة (ومنها دبوس «هنا اليوم») حتى لا تزيد عدّ الدائرة في حزم تالية على القاعدة نفسها (harness_row.mjs يعدّ بطاقاته)
await pool.query("DELETE FROM biz WHERE id LIKE 'rfeed-%'");
await app.close(); await pool.end();
console.log(fails ? `\n${fails} FAILED` : '\nALL ROW FEED TESTS PASSED');
process.exit(fails ? 1 : 0);
