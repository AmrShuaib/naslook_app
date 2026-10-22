// «التغذية» GET /feed (server/row.js): البطاقات نفسها كما /row لكن الأحدث أولاً عبر الأنواع، التصفية بالنوع، مؤشر before بصفحات بلا تكرار
// ولا فجوة (حتى مع طابع زمني بالميكروثانية)، حدّ الصفحة 1..40، نصف القطر مع الموقع والترتيب يبقى زمنياً لا بالقرب، الحظر والضيف،
// حمولة اللحظة، التطابق الحرفي مع بطاقة /row، الجدول الغائب، وأن /row لم يتغير. (الاسم harness_feed.mjs مأخوذ لبث /mapposts/feed.)
import Fastify from 'fastify';
import pg from 'pg';
import crypto from 'node:crypto';
import { KINDS, FEED_LIMIT_MAX, LIMIT_DEFAULT } from '../row.js';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0';
let fails = 0;
const check = (c, l, extra = '') => { if (!c) fails++; console.log((c ? 'OK  ' : 'FAIL') + ' ' + l + (extra ? ' ' + extra : '')); };
const NOW = Date.now(), H = 3600000;
const hrs = (n) => new Date(NOW + n * H).toISOString();

// ---- التجهيز: الإضافات المالكة للجداول تُنشئها، والبذر مباشر بـ SQL
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("INSERT INTO users(id,nickname,avatar_url) VALUES('SA0000001','amr',NULL),('SA0000002','sara','https://naslife.app/seed/sara.png'),('SA0000003','khalid',NULL),('SA0000004','nora',NULL) ON CONFLICT (id) DO UPDATE SET nickname=EXCLUDED.nickname, avatar_url=EXCLUDED.avatar_url");
for (const sql of ['DROP TABLE IF EXISTS map_post_likes, map_post_views, map_post_events, map_posts, biz_offers, ticket_tiers, tickets, events, jobs, market_listings CASCADE', "DELETE FROM biz WHERE id LIKE 'rfeed-%'", 'DELETE FROM app_notifications']) { try { await pool.query(sql); } catch { /* first run */ } }
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
const short = (r) => r.items.map((i) => i.kind[0] + ':' + i.at.slice(11, 19)).join(' ');
const maxRun = (r) => { let best = 0, run = 0, last = null; for (const i of r.items) { run = i.kind === last ? run + 1 : 1; last = i.kind; best = Math.max(best, run); } return best; };

// ---- البذر: الأصل (21.54, 39.17) جدة؛ متوسط ≈ 8 كم؛ بعيد = الدمام. الأزمنة متباعدة حتى يكون الترتيب الزمني قاطعاً
const ORIGIN = { lat: 21.54, lng: 39.17 }, MID = { lat: 21.61, lng: 39.19 }, DMM = { lat: 26.43, lng: 50.10 };
const biz = async (id, nameAr, p, extra = {}) => pool.query("INSERT INTO biz(id,name,name_ar,category,lat,lng,address,active,logo_url) VALUES($1,$2,$3,'cafe',$4,$5,'الروضة',$6,$7)", [id, id, nameAr, p.lat, p.lng, extra.active !== false, extra.logo ?? null]);
await biz('rfeed-reef', 'مقهى ريف', ORIGIN, { logo: 'https://naslife.app/seed/reef.png' });
await biz('rfeed-mid', 'مطعم الشاطئ', MID);
await biz('rfeed-dmm', 'كافيه الدمام', DMM);
await biz('rfeed-mob', 'عربة قهوة', ORIGIN);
// دائرة متنقلة ثبّتت «هنا اليوم» قبل ساعة ونصف حتى بعد خمس ساعات (at = setAt)
await pool.query('UPDATE biz SET here=$2::jsonb WHERE id=$1', ['rfeed-mob', JSON.stringify({ lat: ORIGIN.lat, lng: ORIGIN.lng, until: hrs(5), setAt: hrs(-1.5) })]);
const C1 = 'rfeed-mob';
const offer = async (bizId, title, startsH, endsH, active = true) => { const id = uid(); await pool.query("INSERT INTO biz_offers(id,biz_id,kind,title,value,members_only,starts_at,ends_at,active) VALUES($1,$2,'deal',$3,'{\"type\":\"percent\",\"amount\":15}',false,$4,$5,$6)", [id, bizId, title, hrs(startsH), endsH == null ? null : hrs(endsH), active]); return id; };
const O1 = await offer('rfeed-reef', 'كورتادو بـ 10', -2, 1);
const O2 = await offer('rfeed-mid', 'عشاء لشخصين', -24, 72);
const O3 = await offer('rfeed-dmm', 'عرض الدمام', -2.5, 48);            // بعيد: يظهر بلا موقع فقط
const O4 = await offer('rfeed-reef', 'عرض موقوف', -2, 48, false);      // غير مفعّل
const O5 = await offer('rfeed-reef', 'عرض الغد', 24, 72);               // لم يبدأ
const post = async (user, p, { caption = '', kind = 'image', media = 'https://naslife.app/chat/media/x.jpg', created = -2, expires = 22, status = 'active', place = 'الكورنيش' } = {}) => { const id = uid(); await pool.query("INSERT INTO map_posts(id,user_id,kind,media_url,caption,lat,lng,place_name,status,expires_at,created_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)", [id, user, kind, media, caption, p.lat, p.lng, place, status, hrs(expires), hrs(created)]); return id; };
const P1 = await post(SARA, ORIGIN, { caption: 'قهوة الصباح عند الكورنيش', created: -0.5 });
await pool.query('INSERT INTO map_post_likes(post_id,user_id) VALUES($1,$2),($1,$3)', [P1, AMR, NORA]);
const P2 = await post(KHALID, ORIGIN, { caption: 'لحظة خالد', kind: 'text', media: null, created: -1 });   // محظور عند عمرو
const P3 = await post(SARA, DMM, { caption: 'من الدمام', created: -3 });                                  // بعيد
const P4 = await post(SARA, ORIGIN, { caption: 'منتهية', created: -48, expires: -1 });
const P5 = await post(SARA, ORIGIN, { caption: 'مخفية', status: 'hidden', created: -0.1 });
const event = async (host, title, p, { starts = 48, ends = null, cancelled = false, place = 'حديقة الأمير', tiers = [] } = {}) => { const id = uid(); await pool.query("INSERT INTO events(id,host_id,title,starts_at,ends_at,place_name,lat,lng,cancelled,hidden) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,false)", [id, host, title, hrs(starts), ends == null ? null : hrs(ends), place, p?.lat ?? null, p?.lng ?? null, cancelled]); for (const price of tiers) await pool.query("INSERT INTO ticket_tiers(id,event_id,name,price,quantity) VALUES($1,$2,'عادي',$3,50)", [uid(), id, price]); return id; };
const E1 = await event(SARA, 'لقاء المطورين', ORIGIN, { starts: 48, tiers: [8000, 5000] });   // موعد قادم: at في المستقبل فيتصدر
const E2 = await event(NORA, 'سوق الشاطئ', MID, { starts: -2.2 });                             // بدأت قبل ساعتين بلا نهاية
const E3 = await event(SARA, 'ملغاة', ORIGIN, { cancelled: true });
const job = async (bizId, title, { type = 'full', max = null, visible = false, status = 'open', pubH = -24 } = {}) => { const id = uid(); await pool.query("INSERT INTO jobs(id,biz_id,created_by,title,type,salary_min,salary_max,salary_visible,deadline,status,public,published_at,city,district) VALUES($1,$2,$3,$4,$5,NULL,$6,$7,$8,$9,true,$10,'جدة','')", [id, bizId, AMR, title, type, max, visible, hrs(240), status, hrs(pubH)]); return id; };
const J1 = await job('rfeed-reef', 'باريستا', { type: 'part', max: 4500, visible: true, pubH: -20 });
const J2 = await job('rfeed-reef', 'مسودة', { status: 'draft', pubH: -0.2 });
const J3 = await job('rfeed-dmm', 'كاشير الدمام', { pubH: -5 });                                  // بعيد
const listing = async (seller, title, p, { price = 265000, status = 'active', created = -2, bumped = null, micros = 0 } = {}) => { const id = uid(); await pool.query(`INSERT INTO market_listings(id,seller_id,kind,category,title,price,images,place_name,lat,lng,status,created_at,bumped_at) VALUES($1,$2,'product','sports',$3,$4,'["https://naslife.app/seed/bike.jpg"]','الروضة',$5,$6,$7,$8::timestamptz + ($10 || ' microseconds')::interval,$9)`, [id, seller, title, price, p?.lat ?? null, p?.lng ?? null, status, hrs(created), bumped == null ? null : hrs(bumped), String(micros)]); return id; };
const L1 = await listing(NORA, 'دراجة هوائية', ORIGIN, { created: -4 });
const L2 = await listing(NORA, 'مرفوعة للتو', MID, { created: -30, bumped: -0.25 });              // at = bumped_at
const L3 = await listing(NORA, 'مباعة', ORIGIN, { status: 'sold', created: -0.3 });
const L4 = await listing(NORA, 'دراجة الدمام', DMM, { created: -6 });                              // بعيد
const X = await listing(NORA, 'بالميكروثانية', ORIGIN, { created: -3.5, micros: 456 });              // طابع زمني أدق من الملي ثانية: اختبار المؤشر
const EXCLUDED = [O4, O5, P4, P5, E3, J2, L3];
// الأحدث أولاً (الضيف، بلا موقع): E1 +48س، L2 -15د، P1 -30د، P2 -1س، C1 -1.5س، O1 -2س، E2 -2.2س، O3 -2.5س، P3 -3س، X -3.5س، L1 -4س، J3 -5س، L4 -6س، J1 -20س، O2 -24س
const ALL_GUEST = [E1, L2, P1, P2, C1, O1, E2, O3, P3, X, L1, J3, L4, J1, O2];
const ALL_AMR = ALL_GUEST.filter((id) => id !== P2);
const FAR = [O3, P3, J3, L4], MIDS = [L2, E2, O2];
const NEAR_GUEST = ALL_GUEST.filter((id) => !FAR.includes(id));
const Q = `lat=${ORIGIN.lat}&lng=${ORIGIN.lng}`;

// ---- بلا موقع: الأحدث أولاً عبر الأنواع، كل شيء بما فيه البعيد، بلا مسافة، وبلا next لأن الصفحة لم تمتلئ
let r = await call('GET', '/feed', { user: null, expect: 200 });
check(r.located === false && same(ids(r), ALL_GUEST), 'guest without location: every active item newest-first across kinds (future event on top)', short(r));
check(r.next === null && r.items.every((i) => i.distanceKm === null), 'no location: next is null below the page size and no distances');
check(EXCLUDED.every((id) => !ids(r).includes(id)), 'inactive, upcoming, expired, hidden, cancelled, draft and sold rows excluded');
check(r.items.every((i) => KINDS.includes(i.kind) && i.id && i.refId && typeof i.title === 'string' && i.title && typeof i.subtitle === 'string' && typeof i.at === 'string' && i.payload && typeof i.payload === 'object' && typeof i.act === 'string'), 'every item has the /row contract shape');
check(ids(r).indexOf(E1) === 0 && byId(r, E1).at === hrs(48), 'upcoming event sorts by its start time (at), which is the time column');
check(byId(r, L2).at === hrs(-0.25) && byId(r, L2).title === 'مرفوعة للتو', 'listing at = bumped_at when bumped');
check(byId(r, C1).kind === 'circle' && byId(r, C1).at === hrs(-1.5) && byId(r, C1).payload.here === true, 'circle card sorts by its setAt and carries the here payload');
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

// ---- التطابق الحرفي مع /row: البطاقة نفسها من البنّاء نفسه
const row = await call('GET', `/row?${Q}&limit=50`, { expect: 200 });
const feed = await call('GET', `/feed?${Q}&limit=40`, { expect: 200 });
check(same([...ids(row)].sort(), [...ids(feed)].sort()), 'located /row and /feed return the same set of items', `${row.items.length} vs ${feed.items.length}`);
check(feed.items.every((i) => JSON.stringify(byId(row, i.id)) === JSON.stringify(i)), 'every feed item is byte-identical to its /row card');

// ---- التصفية بالنوع
const kindIds = async (kind) => ids(await call('GET', `/feed?kind=${kind}`, { user: null, expect: 200 }));
check(same(await kindIds('moment'), [P1, P2, P3]), 'kind=moment');
check(same(await kindIds('offer'), [O1, O3, O2]), 'kind=offer');
check(same(await kindIds('event'), [E1, E2]), 'kind=event');
check(same(await kindIds('job'), [J3, J1]), 'kind=job');
check(same(await kindIds('listing'), [L2, X, L1, L4]), 'kind=listing');
check(same(await kindIds('circle'), [C1]), 'kind=circle');
check(same(await kindIds('all'), ALL_GUEST) && same(await kindIds('bogus'), ALL_GUEST), 'kind=all and an unknown kind merge every kind');

// ---- المؤشر: صفحات متتالية بلا تكرار ولا فجوة، والحدّ بين الصفحات يقع على الطابع بالميكروثانية
const pg1 = await call('GET', '/feed?limit=5', { user: null, expect: 200 });
check(same(ids(pg1), ALL_GUEST.slice(0, 5)) && pg1.next === byId(pg1, C1).at, 'page 1: five newest and next = at of the last card', pg1.next);
const pg2 = await call('GET', `/feed?limit=5&before=${encodeURIComponent(pg1.next)}`, { user: null, expect: 200 });
check(same(ids(pg2), ALL_GUEST.slice(5, 10)) && pg2.next === byId(pg2, X).at, 'page 2 continues after the cursor and ends on the microsecond-stamped listing', short(pg2));
check(/\.\d{3}Z$/.test(pg2.next), 'cursor is an ISO string with millisecond precision', pg2.next);
const pg3 = await call('GET', `/feed?limit=5&before=${encodeURIComponent(pg2.next)}`, { user: null, expect: 200 });
check(same(ids(pg3), ALL_GUEST.slice(10, 15)) && ids(pg3)[0] === L1, 'page 3 starts right after it: no repeat of the microsecond row and no gap', short(pg3));
check(pg3.next === byId(pg3, O2).at, 'a full last page still returns next (the client learns the end from the empty page)');
const pg4 = await call('GET', `/feed?limit=5&before=${encodeURIComponent(pg3.next)}`, { user: null, expect: 200 });
check(pg4.items.length === 0 && pg4.next === null, 'page after the last is empty with next null');
check(same([...ids(pg1), ...ids(pg2), ...ids(pg3)], ALL_GUEST), 'pages concatenate to the full list');
r = await call('GET', '/feed?before=garbage', { user: null, expect: 200 });
check(same(ids(r), ALL_GUEST), 'an unparsable before is ignored');
r = await call('GET', `/feed?before=${encodeURIComponent(hrs(-2.3))}`, { user: null, expect: 200 });
check(same(ids(r), ALL_GUEST.slice(7)), 'before=-2.3h keeps strictly older items only', short(r));
r = await call('GET', `/feed?kind=moment&limit=1`, { user: null, expect: 200 });
check(same(ids(r), [P1]) && r.next === byId(r, P1).at, 'cursor with a kind filter: first moment');
r = await call('GET', `/feed?kind=moment&limit=1&before=${encodeURIComponent(r.next)}`, { user: null, expect: 200 });
check(same(ids(r), [P2]), 'cursor with a kind filter: second moment');
r = await call('GET', `/feed?${Q}&limit=3`, { user: null, expect: 200 });
check(same(ids(r), NEAR_GUEST.slice(0, 3)) && r.next === r.items[2].at, 'cursor and radius together: first page');
r = await call('GET', `/feed?${Q}&limit=3&before=${encodeURIComponent(r.next)}`, { user: null, expect: 200 });
check(same(ids(r), NEAR_GUEST.slice(3, 6)), 'cursor and radius together: second page keeps the radius', short(r));

// ---- حدّ الصفحة 1..40 وبلا حد 12 لكل نوع: 45 إعلاناً أقدم من كل شيء
const extra = []; for (let i = 0; i < 45; i++) extra.push(await listing(NORA, `إعلان ${i + 1}`, ORIGIN, { created: -40 - i / 60, price: 1000 * (i + 1) }));
r = await call('GET', '/feed?limit=500', { user: null, expect: 200 });
check(r.items.length === FEED_LIMIT_MAX && r.next === r.items[FEED_LIMIT_MAX - 1].at, 'limit above 40 is clamped to 40 with a cursor', String(r.items.length));
r = await call('GET', '/feed?limit=abc', { user: null, expect: 200 });
check(r.items.length === LIMIT_DEFAULT, 'bad limit falls back to the default 30', String(r.items.length));
r = await call('GET', '/feed?limit=0', { user: null, expect: 200 });
check(r.items.length === 1 && r.items[0].id === E1, 'limit=0 clamps to 1');
r = await call('GET', '/feed?kind=listing&limit=40', { user: null, expect: 200 });
check(r.items.length === 40 && r.items.filter((i) => i.kind === 'listing').length === 40, 'no per-kind cap of 12 in the feed (unlike /row)', String(r.items.length));
const all = []; let cursor = null, pages = 0;
do { const pg = await call('GET', `/feed?limit=40${cursor ? '&before=' + encodeURIComponent(cursor) : ''}`, { user: null, expect: 200 }); all.push(...ids(pg)); cursor = pg.next; pages++; } while (cursor && pages < 10);
check(all.length === ALL_GUEST.length + 45 && new Set(all).size === all.length && pages === 2 && extra.every((id) => all.includes(id)), 'walking every page with limit=40 yields all 60 items once (40 + 20; the short page carries next=null)', `${all.length} in ${pages} pages`);
check(same(all.slice(0, ALL_GUEST.length), ALL_GUEST), 'the newer base items still lead the walk');

// ---- /row لم يتغير: الأقرب أولاً مع الدفعات، حد 12 لكل نوع، والتوزيع ما دام نوع آخر باقياً (harness_row.mjs يغطي التفاصيل)
r = await call('GET', `/row?${Q}`, { expect: 200 });
check(r.items[0].id === O1 && r.items.filter((i) => i.kind === 'listing').length === 12 && maxRun({ items: r.items.slice(0, 12) }) <= 3 && !('next' in r), '/row still ranks the ending-soon offer first, caps listings at 12, interleaves while other kinds remain, and has no cursor', r.items.map((i) => i.kind[0]).join(''));

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
