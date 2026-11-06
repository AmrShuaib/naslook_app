// «لحظات هنا» في صفحة الدائرة (نوفمبر 2026): التطبيق يطلب GET /mapposts/feed?place=biz:<id> بلا موقع المشاهد، فيعود كل ما نسبه
// map_posts.js إلى الدائرة (أقرب دائرة نشطة ضمن 250 م) أياً كان مكان المشاهد، للزائر أيضاً، بلا لحظات دائرة مجاورة أو بعيدة.
// (مع موقع بعيد ونطاق 200 كم كان البث القديم FeedPage يقصّها، ولهذا لا يُرسل التطبيق موقعاً.)
import Fastify from 'fastify';
import pg from 'pg';
process.env.NASLIFE_HEALTH_BRIDGE = '0';
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("INSERT INTO users(id,nickname) VALUES('SA0000001','amr'),('SA0000002','sara') ON CONFLICT (id) DO NOTHING");
await pool.query(`CREATE TABLE IF NOT EXISTS biz (id TEXT PRIMARY KEY, name TEXT NOT NULL, name_ar TEXT NOT NULL DEFAULT '', category TEXT NOT NULL, sector TEXT NOT NULL DEFAULT '', description TEXT NOT NULL DEFAULT '', lat DOUBLE PRECISION NOT NULL, lng DOUBLE PRECISION NOT NULL, address TEXT NOT NULL DEFAULT '', hours TEXT NOT NULL DEFAULT '', phone TEXT, website TEXT, color TEXT, highlights JSONB NOT NULL DEFAULT '[]', verified BOOLEAN NOT NULL DEFAULT false, official BOOLEAN NOT NULL DEFAULT false, active BOOLEAN NOT NULL DEFAULT true, sort INT NOT NULL DEFAULT 0, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), owner_id TEXT, logo_url TEXT)`);
await pool.query("DELETE FROM biz WHERE id LIKE 'pm-%'");
// دوائر حزم أخرى في القاعدة المشتركة (biz_onboard وrow) قد تقع في الدمام قرب هذه النقاط فتسحب نسبة اللحظات إليها: تُطفأ في هذا الصندوق
try { await pool.query("UPDATE biz SET active=false WHERE id NOT LIKE 'pm-%' AND lat BETWEEN 26.42 AND 26.45 AND lng BETWEEN 50.09 AND 50.11"); }
catch { await pool.query("DELETE FROM biz WHERE id NOT LIKE 'pm-%' AND lat BETWEEN 26.42 AND 26.45 AND lng BETWEEN 50.09 AND 50.11").catch(() => {}); }
// دائرتان في الدمام بينهما ~600 م
await pool.query("INSERT INTO biz(id,name,name_ar,category,lat,lng) VALUES('pm-cafe','PM Cafe','مقهى الواجهة','cafe',26.4300,50.1000),('pm-salon','PM Salon','صالون الواجهة','salon',26.4354,50.1000)");
await pool.query("DROP TABLE IF EXISTS map_posts; DROP TABLE IF EXISTS map_post_likes; DROP TABLE IF EXISTS map_post_views; DROP TABLE IF EXISTS map_post_events");
globalThis.naslifeBlockedIds = async () => [];
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
app.register((await import('../map_posts.js')).default, { pool, auth });
await app.ready();
let fails = 0;
const check = (c, l, extra = '') => { if (!c) fails++; console.log((c ? 'OK  ' : 'FAIL') + ' ' + l + (extra ? ' ' + extra : '')); };
const call = async (url, user) => { const r = await app.inject({ method: 'GET', url, headers: user ? { 'x-user': user } : {} }); return { code: r.statusCode, json: r.json() }; };
const seed = (id, lat, lng, minutesAgo) => pool.query(
  `INSERT INTO map_posts(id,user_id,kind,caption,lat,lng,expires_at,created_at) VALUES($1,'SA0000002','text',$5,$2,$3, now() + interval '24 hours', now() - ($4 || ' minutes')::interval)`, [id, lat, lng, String(minutesAgo), 'لحظة ' + id.slice(-3)]);
const A = '11111111-1111-4111-8111-aaaaaaaaaaa1', B = '11111111-1111-4111-8111-aaaaaaaaaaa2', C = '11111111-1111-4111-8111-aaaaaaaaaaa3', D = '11111111-1111-4111-8111-aaaaaaaaaaa4';
await seed(A, 26.4302, 50.1001, 30);   // ~25 م من المقهى
await seed(B, 26.4310, 50.1003, 5);    // ~115 م من المقهى (أقرب إليه من الصالون)
await seed(C, 26.4352, 50.1000, 10);   // ~20 م من الصالون
await seed(D, 21.5433, 39.1728, 1);    // جدة: لا دائرة قريبة

// الزائر في جدة يفتح دائرة الدمام: بلا موقع، كل لحظاتها، والأحدث أولاً
let r = await call('/mapposts/feed?place=biz:pm-cafe&limit=30&radiusKm=200');
check(r.code === 200 && r.json.located === false, 'guest request without a location succeeds', JSON.stringify(r.json).slice(0, 120));
check(r.json.items.map((x) => x.id).join() === [B, A].join(), 'only the moments attributed to the circle, newest first', JSON.stringify(r.json.items.map((x) => x.id)));
check(r.json.items.every((x) => x.place?.bizId === 'pm-cafe' && x.place?.name === 'مقهى الواجهة' && x.distanceKm === null), 'each moment carries the circle as its place and no distance');
r = await call('/mapposts/feed?place=biz:pm-salon&limit=30&radiusKm=200', 'SA0000001');
check(r.json.items.map((x) => x.id).join() === C, 'the neighbouring circle gets only its own nearest moment');
// الموقع البعيد مع نطاق 200 كم (ما كان يرسله البث القديم) يقصّها كلها: لذلك لا يرسل المدخل موقعاً
r = await call('/mapposts/feed?place=biz:pm-cafe&lat=21.5433&lng=39.1728&radiusKm=200');
check(r.json.items.length === 0, 'a far viewer location with a radius would hide them (why the app sends none)');
r = await call('/mapposts/feed?place=biz:pm-none');
check(r.code === 200 && r.json.items.length === 0, 'unknown circle → empty list');
// الأداء: مع place=biz:<id> يُحصر الاستعلام في صندوق حول الدائرة قبل حساب أقرب دائرة لكل لحظة (لا مسح لكل لحظات المنصة)
const seen = [];
const q0 = pool.query.bind(pool);
pool.query = (sql, params) => { if (typeof sql === 'string' && sql.includes('place_key')) seen.push(params); return q0(sql, params); };
r = await call('/mapposts/feed?place=biz:pm-cafe&limit=30&radiusKm=200');
const box = seen.at(-1)?.slice(10, 14) ?? [];
check(box.length === 4 && box.every((v) => typeof v === 'number') && box[0] < 26.43 && box[1] > 26.43 && box[2] < 50.1 && box[3] > 50.1 && box[1] - box[0] < 0.01,
  'the circle feed is bounded by a box around the circle', JSON.stringify(box));
seen.length = 0;
await call('/mapposts/feed?lat=26.43&lng=50.1&radiusKm=30');
check(seen.at(-1)?.[10] === null, 'the ordinary feed has no box');
pool.query = q0;
// الصندوق لا يقصّ لحظة في حد 250 م شرقاً (درجة الطول أقصر من درجة العرض في الدمام)
const E = '11111111-1111-4111-8111-aaaaaaaaaaa5';
await seed(E, 26.4300, 50.10245, 2);   // ~244 م شرق المقهى
r = await call('/mapposts/feed?place=biz:pm-cafe&limit=30&radiusKm=200');
check(r.json.items.map((x) => x.id).join() === [E, B, A].join(), 'a moment 244 m east is still attributed to the circle', JSON.stringify(r.json.items.map((x) => x.id)));

await pool.query("DELETE FROM biz WHERE id LIKE 'pm-%'");
// دوائر حزم أخرى في القاعدة المشتركة (biz_onboard وrow) قد تقع في الدمام قرب هذه النقاط فتسحب نسبة اللحظات إليها: تُطفأ في هذا الصندوق
try { await pool.query("UPDATE biz SET active=false WHERE id NOT LIKE 'pm-%' AND lat BETWEEN 26.42 AND 26.45 AND lng BETWEEN 50.09 AND 50.11"); }
catch { await pool.query("DELETE FROM biz WHERE id NOT LIKE 'pm-%' AND lat BETWEEN 26.42 AND 26.45 AND lng BETWEEN 50.09 AND 50.11").catch(() => {}); }
await app.close(); await pool.end();
console.log(fails ? `\n${fails} FAILED` : '\nALL PLACE MOMENTS TESTS PASSED');
process.exit(fails ? 1 : 0);
