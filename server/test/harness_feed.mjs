// البث العمودي «الآن حولك» (server/map_posts.js): ترتيب بالقرب والحداثة، نصف قطر، ترقيم، تصفية بالمكان، نسب اللحظة إلى أقرب
// دائرة تجارية أو اسم المكان، الأماكن الرائجة، واستبعاد المحظورين والمنتهية، وسقوط الترتيب إلى الحداثة بلا موقع.
import Fastify from 'fastify';
import pg from 'pg';
process.env.NASLIFE_HEALTH_BRIDGE = '0';
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("INSERT INTO users(id,nickname) VALUES('SA0000001','amr'),('SA0000002','sara'),('SA0000003','khalid') ON CONFLICT (id) DO NOTHING");
await pool.query(`CREATE TABLE IF NOT EXISTS biz (id TEXT PRIMARY KEY, name TEXT NOT NULL, name_ar TEXT NOT NULL DEFAULT '', category TEXT NOT NULL, sector TEXT NOT NULL DEFAULT '', description TEXT NOT NULL DEFAULT '', lat DOUBLE PRECISION NOT NULL, lng DOUBLE PRECISION NOT NULL, address TEXT NOT NULL DEFAULT '', hours TEXT NOT NULL DEFAULT '', phone TEXT, website TEXT, color TEXT, highlights JSONB NOT NULL DEFAULT '[]', verified BOOLEAN NOT NULL DEFAULT false, official BOOLEAN NOT NULL DEFAULT false, active BOOLEAN NOT NULL DEFAULT true, sort INT NOT NULL DEFAULT 0, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), owner_id TEXT, logo_url TEXT)`);
await pool.query("DELETE FROM biz WHERE id LIKE 'feed-%'");
await pool.query("INSERT INTO biz(id,name,name_ar,category,lat,lng,logo_url) VALUES('feed-cafe','Feed Cafe','مقهى البث','cafe',21.5440,39.1730,'asset:biz/x.png')");
await pool.query("DROP TABLE IF EXISTS map_posts; DROP TABLE IF EXISTS map_post_likes; DROP TABLE IF EXISTS map_post_views; DROP TABLE IF EXISTS map_post_events");
let blocked = [];
globalThis.naslifeBlockedIds = async () => blocked;
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
app.register((await import('../map_posts.js')).default, { pool, auth });
await app.ready();
let fails = 0;
const check = (c, l, extra = '') => { if (!c) fails++; console.log((c ? 'OK  ' : 'FAIL') + ' ' + l + (extra ? ' ' + extra : '')); };
const call = async (method, url, { body, user } = {}) => { const r = await app.inject({ method, url, headers: { 'content-type': 'application/json', ...(user ? { 'x-user': user } : {}) }, payload: body ? JSON.stringify(body) : undefined }); let j; try { j = r.json(); } catch { j = r.body; } return { code: r.statusCode, json: j }; };
// منشورات حول نقطة الأصل (21.5433, 39.1728)
const seed = async (id, user, lat, lng, minutesAgo, { placeName = null, expired = false, caption = '' } = {}) => pool.query(
  `INSERT INTO map_posts(id,user_id,kind,caption,lat,lng,place_name,expires_at,created_at) VALUES($1,$2,'text',$3,$4,$5,$6, now() + ($7 || ' hours')::interval, now() - ($8 || ' minutes')::interval)`,
  [id, user, caption || id, lat, lng, placeName, expired ? '-1' : '24', String(minutesAgo)]);
const A = '11111111-1111-4111-8111-111111111111', B = '22222222-2222-4222-8222-222222222222', C = '33333333-3333-4333-8333-333333333333', D = '44444444-4444-4444-8444-444444444444', E = '55555555-5555-4555-8555-555555555555', F = '66666666-6666-4666-8666-666666666666', G = '77777777-7777-4777-8777-777777777777';
await seed(A, 'SA0000001', 21.5441, 39.1729, 50, { caption: 'A قريب من المقهى' });           // ~90 م، قبل 50 دقيقة، قرب المقهى
await seed(B, 'SA0000002', 21.5880, 39.1728, 30, { placeName: 'كورنيش جدة' });               // ~5 كم، قبل 30 دقيقة، اسم مكان
await seed(C, 'SA0000002', 21.5478, 39.1728, 20 * 60);                                         // ~0.5 كم، قبل 20 ساعة، بلا مكان
await seed(D, 'SA0000001', 21.4225, 39.8262, 5);                                                // مكة ~70 كم، قبل 5 دقائق
await seed(E, 'SA0000001', 21.5434, 39.1729, 10, { expired: true });                           // منتهٍ
await seed(F, 'SA0000003', 21.5438, 39.1731, 120, { caption: 'F قرب المقهى أيضاً' });         // ~40 م من المقهى، قبل ساعتين
await seed(G, 'SA0000003', 21.5433, 39.1690, 3);                                                // قريب وحديث، ناشره سيُحظر لاحقاً

let r = await call('GET', '/mapposts/feed?lat=21.5433&lng=39.1728&radiusKm=30');
let ids = r.json.items.map((x) => x.id);
check(r.code === 200 && r.json.located === true && ids.join() === [G, A, F, B, C].join(), 'feed ordered by recency + distance within 30 km (D too far, E expired)', ids.map((i) => i[0]).join(','));
const a = r.json.items.find((x) => x.id === A);
check(a && a.distanceKm === 0.1 && a.place && a.place.key === 'biz:feed-cafe' && a.place.name === 'مقهى البث' && a.place.bizId === 'feed-cafe' && a.place.category === 'cafe', 'post near a business is attributed to it with distance', JSON.stringify(a?.place));
const b = r.json.items.find((x) => x.id === B);
check(b && b.place && b.place.key === 'name:كورنيش جدة' && b.place.name === 'كورنيش جدة' && b.place.bizId === null && Math.abs(b.distanceKm - 5) < 0.3, 'post with a written place name keeps it', JSON.stringify({ p: b?.place, d: b?.distanceKm }));
const c = r.json.items.find((x) => x.id === C);
check(c && c.place && c.place.key.startsWith('cell:') && c.place.name === null, 'post without a place gets a cell key and no name');
r = await call('GET', '/mapposts/feed?lat=21.5433&lng=39.1728&radiusKm=30&limit=2');
check(r.json.items.length === 2 && r.json.nextCursor === 2 && r.json.items[0].id === G && r.json.items[1].id === A, 'pagination: first page of 2 with cursor');
r = await call('GET', '/mapposts/feed?lat=21.5433&lng=39.1728&radiusKm=30&limit=2&cursor=2');
check(r.json.items.length === 2 && r.json.nextCursor === 4 && r.json.items[0].id === F && r.json.items[1].id === B, 'pagination: second page');
r = await call('GET', '/mapposts/feed?lat=21.5433&lng=39.1728&radiusKm=30&limit=2&cursor=4');
check(r.json.items.length === 1 && r.json.nextCursor === null && r.json.items[0].id === C, 'pagination: last page has no cursor');
r = await call('GET', '/mapposts/feed?lat=21.5433&lng=39.1728&radiusKm=200');
check(r.json.items.some((x) => x.id === D), 'wider radius includes the far post');
r = await call('GET', '/mapposts/feed?lat=21.5433&lng=39.1728&place=biz:feed-cafe');
check(r.json.items.map((x) => x.id).join() === [A, F].join(), 'place filter returns only that business\'s moments');
r = await call('GET', '/mapposts/feed?lat=21.5433&lng=39.1728&place=' + encodeURIComponent('name:كورنيش جدة'));
check(r.json.items.length === 1 && r.json.items[0].id === B, 'place filter by written name');
r = await call('GET', '/mapposts/feed');
ids = r.json.items.map((x) => x.id);
check(r.json.located === false && ids[0] === G && ids[1] === D && ids.length === 6 && r.json.items.every((x) => x.distanceKm === null), 'without a location: newest first, no distances, all active posts', ids.map((i) => i[0]).join(','));
blocked = ['SA0000003'];
r = await call('GET', '/mapposts/feed?lat=21.5433&lng=39.1728', { user: 'SA0000001' });
check(!r.json.items.some((x) => x.user.id === 'SA0000003') && r.json.items.some((x) => x.id === A), 'blocked users are hidden for the viewer');
blocked = [];
r = await call('GET', '/mapposts/feed?lat=21.5433&lng=39.1728&authors=SA0000002,sa0000003');
check(r.json.items.map((x) => x.id).join() === [G, F, B, C].join(), 'authors filter (friends only) keeps only those users, case-insensitive ids', r.json.items.map((x) => x.id[0]).join(','));
r = await call('GET', '/mapposts/feed?lat=21.5433&lng=39.1728&authors=');
check(r.json.items.length === 0, 'empty authors list means no results');
r = await call('GET', '/mapposts/feed?lat=21.5433&lng=39.1728&radiusKm=1');
check(r.json.items.map((x) => x.id).join() === [G, A, F, C].join(), 'radius 1 km drops the 5 km post');
await pool.query("UPDATE map_posts SET tag='offer' WHERE id=$1", [B]);
r = await call('GET', '/mapposts/feed?lat=21.5433&lng=39.1728&tag=offer');
check(r.json.items.length === 1 && r.json.items[0].id === B, 'tag filter');
// الأماكن الرائجة
r = await call('GET', '/mapposts/trending?lat=21.5433&lng=39.1728&hours=24');
if (r.code !== 200) console.log('TRENDING ERROR', JSON.stringify(r.json).slice(0, 300));
check(r.code === 200 && r.json.hours === 24 && r.json.places.length === 2, 'trending lists only named places', JSON.stringify(r.json.places.map((p) => [p.key, p.posts])));
const cafe = r.json.places[0];
check(cafe.key === 'biz:feed-cafe' && cafe.name === 'مقهى البث' && cafe.posts === 2 && cafe.authors === 2 && cafe.bizId === 'feed-cafe' && cafe.logoUrl === 'asset:biz/x.png' && Math.abs(cafe.lat - 21.544) < 0.001 && cafe.sampleId === A, 'busiest place first with biz details and latest sample', JSON.stringify(cafe));
check(r.json.places[1].key === 'name:كورنيش جدة' && r.json.places[1].posts === 1 && Math.abs(r.json.places[1].distanceKm - 5) < 0.3, 'named place second with distance');
r = await call('GET', '/mapposts/trending?lat=21.5433&lng=39.1728&hours=1');
check(r.json.places.length === 2 && r.json.places.every((p) => p.posts === 1), 'trending within the last hour counts only fresh moments', JSON.stringify(r.json.places.map((p) => [p.key, p.posts])));
r = await call('GET', '/mapposts/trending?lat=21.5433&lng=39.1728&radiusKm=2');
check(r.json.places.length === 1 && r.json.places[0].key === 'biz:feed-cafe', 'trending radius excludes far places');
r = await call('GET', '/mapposts/trending');
check(r.json.places.length === 2 && r.json.places.every((p) => p.distanceKm === null), 'trending without a location works (no distances)');
console.log(fails ? `\n${fails} FAILED` : '\nALL FEED TESTS PASSED');
await app.close(); await pool.end(); process.exit(fails ? 1 : 0);
