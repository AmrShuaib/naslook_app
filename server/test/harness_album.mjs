// «لحظة الألبوم» (server/map_posts.js، docs/moments.md «الألبوم»): لحظة الصورة تحمل حتى 8 صور في media (الغلاف أولاً) وmedia_url
// يبقى الغلاف. يغطي: albumOf (ما قبل الميزة، غلاف عدّله إصدار سابق، غير الصورة، الحد)، الإنشاء بـ mediaUrls والتحقق (وسائطنا فقط،
// الحد، التكرار، الغلاف المخالف، الصورة وحدها)، الصفوف القديمة تُملأ بغلافها عند الإقلاع، التعديل (ترتيب وحذف فقط، غلاف جديد يبقي
// البقية، صورة من الألبوم تتقدّم، تعديل آخر لا يمس الألبوم)، وأن كل قارئ يعمل: القوائم والبث العمودي والرائج ولحظة واحدة ومنشوراتي،
// /row و/feed (row.js)، البث الحي، رابط المشاركة /m/:id (الغلاف)، «محفوظاتي» (الغلاف)، طابور الإشراف (كل الصور)، وكنس الحساب المحذوف
// (كل الصور). قوية أمام صفوف حزم أخرى على القاعدة نفسها: مستخدموها خاصّون بها وتحذف لحظاتهم فقط.
import Fastify from 'fastify';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import pg from 'pg';
import { albumOf, MAX_MEDIA } from '../map_posts.js';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0'; process.env.NODE_ENV = 'test';
let fails = 0;
const check = (cond, label, extra = '') => { if (!cond) fails++; console.log((cond ? 'OK  ' : 'FAIL') + ' ' + label + (extra ? ' ' + extra : '')); };
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'naslife-album-'));

// ---- وحدة: albumOf
const H = 'https://naslife.app/chat/media/';
check(JSON.stringify(albumOf({ kind: 'image', media_url: H + 'a.jpg', media: null })) === JSON.stringify([H + 'a.jpg']), 'albumOf: a moment from before albums = [cover]');
check(JSON.stringify(albumOf({ kind: 'image', media_url: H + 'b.jpg', media: [H + 'a.jpg', H + 'b.jpg', H + 'c.jpg'] })) === JSON.stringify([H + 'b.jpg', H + 'a.jpg', H + 'c.jpg']), 'albumOf: media_url is the cover even if an older release changed it after media');
check(JSON.stringify(albumOf({ kind: 'image', media_url: H + 'x.jpg', media: [H + 'a.jpg'] })) === JSON.stringify([H + 'x.jpg', H + 'a.jpg']), 'albumOf: a cover missing from media is put first');
check(JSON.stringify(albumOf({ kind: 'video', media_url: H + 'v.mp4', media: [H + 'v.mp4', H + 'a.jpg'] })) === JSON.stringify([H + 'v.mp4']) && albumOf({ kind: 'text', media_url: null, media: [] }).length === 0, 'albumOf: video = its clip only, text = none');
check(albumOf({ kind: 'image', media_url: H + '0.jpg', media: Array.from({ length: 12 }, (_, i) => H + i + '.jpg') }).length === MAX_MEDIA && MAX_MEDIA === 8, 'albumOf: capped at 8');

// ---- التجهيز
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
const AMR = 'SA0000731', SARA = 'SA0000732', KHALID = 'SA0000733', ADMIN = 'SA0000734', GONE = 'SA0000735';
const OURS = [AMR, SARA, KHALID, ADMIN, GONE];
const inOurs = `('${OURS.join("','")}')`;
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query(`INSERT INTO users(id,nickname) VALUES('${AMR}','albamr'),('${SARA}','albsara'),('${KHALID}','albkhalid'),('${ADMIN}','albadmin'),('${GONE}','albgone') ON CONFLICT (id) DO UPDATE SET nickname=EXCLUDED.nickname`);
// جدول اللحظات كما كان قبل الألبوم (أول تشغيل على قاعدة فارغة)، ثم صفوف قديمة بلا media قبل إقلاع الإضافة
await pool.query(`CREATE TABLE IF NOT EXISTS map_posts (
  id UUID PRIMARY KEY, user_id TEXT NOT NULL, kind TEXT NOT NULL, media_url TEXT, caption TEXT NOT NULL DEFAULT '', bg TEXT,
  overlays JSONB NOT NULL DEFAULT '[]', tag TEXT NOT NULL DEFAULT 'moment', title TEXT NOT NULL DEFAULT '', price BIGINT, cta JSONB,
  lat DOUBLE PRECISION NOT NULL, lng DOUBLE PRECISION NOT NULL, place_name TEXT, duration_sec INT, status TEXT NOT NULL DEFAULT 'active',
  views INT NOT NULL DEFAULT 0, expires_at TIMESTAMPTZ NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  audio_url TEXT, audio_sec INT, audience TEXT NOT NULL DEFAULT 'all')`);
for (const sql of [`DELETE FROM map_posts WHERE user_id IN ${inOurs}`, `DELETE FROM wishlist_items WHERE user_id IN ${inOurs}`, `DELETE FROM content_reports WHERE reporter_id IN ${inOurs}`,
  `DELETE FROM account_deletions WHERE user_id IN ${inOurs}`, `DELETE FROM app_notifications WHERE user_id IN ${inOurs}`, `DELETE FROM user_flags WHERE user_id IN ${inOurs}`]) { try { await pool.query(sql); } catch { /* أول تشغيل */ } }
// الحزم الأخرى قد تترك العمود بلا قيمة لصفوفها؛ صفوفنا القديمة بلا media صراحةً (العمود قد يوجد من تشغيل سابق)
const legacyCols = (await pool.query("SELECT 1 FROM information_schema.columns WHERE table_name='map_posts' AND column_name='media'")).rowCount > 0;
const name = (tag, n) => `album${tag}${n}-${crypto.createHash('md5').update(tag + n).digest('hex').slice(0, 24)}.jpg`;
const L1 = crypto.randomUUID(), L2 = crypto.randomUUID();
const legacyCover = H + name('legacy', 1);
await pool.query(`INSERT INTO map_posts(id,user_id,kind,media_url,lat,lng,expires_at${legacyCols ? ',media' : ''}) VALUES($1,$2,'image',$3,21.54,39.17,now()+interval '1 day'${legacyCols ? ',NULL' : ''}),
  ($4,$2,'text',NULL,21.54,39.17,now()+interval '1 day'${legacyCols ? ',NULL' : ''})`, [L1, SARA, legacyCover, L2]);
await pool.query(`UPDATE map_posts SET caption='قديمة نصية' WHERE id=$1`, [L2]);

const auth = async (req) => req.headers['x-user'] || null;
globalThis.naslifeIsAdmin = async (uid) => uid === ADMIN;
globalThis.naslifeBlockedIds = async () => [];
const deleted = [];
globalThis.naslifeMediaDelete = async (u) => { deleted.push(u); return true; };
const dir = new URL('.', import.meta.url).pathname;
const app = Fastify();
app.register((await import('../notify.js')).default, { pool, auth, pollMs: 3600000, opsDir: dir + 'ops' });
app.register((await import('../map_posts.js')).default, { pool, auth });
app.register((await import('../row.js')).default, { pool, auth });
app.register((await import('../share.js')).default, { pool, auth, webappDir: path.join(tmp, 'webapp') });
app.register((await import('../wishlist.js')).default, { pool, auth, sweepMs: 0 });
app.register((await import('../safety.js')).default, { pool, auth });
app.register((await import('../account_delete.js')).default, { pool, auth, opsDir: path.join(tmp, 'ops') });
await app.ready(); await new Promise((r) => setTimeout(r, 400));
// البث الحي: نلتقط ما يُبث بدل live.js
const emitted = [];
globalThis.naslifeLive = { emit: (kind, data, o) => emitted.push({ kind, data, o }) };
const call = async (method, url, { body = {}, user = AMR, expect, host = 'naslife.app' } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json', host, 'x-forwarded-proto': 'https' }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url} -> ${r.statusCode}`, r.statusCode === expect ? '' : String(typeof j === 'string' ? j : JSON.stringify(j)).slice(0, 180));
  return j;
};
const rel = (n) => `/chat/media/${n}`, abs = (n) => H + n;
const same = (a, b) => Array.isArray(a) && a.length === b.length && a.every((x, i) => x === b[i]);

// ---- الصفوف القديمة: تُملأ بغلافها عند الإقلاع
const lrow = (await pool.query('SELECT id, media FROM map_posts WHERE id = ANY($1::uuid[])', [[L1, L2]])).rows;
check(same(lrow.find((r) => r.id === L1).media, [legacyCover]) && same(lrow.find((r) => r.id === L2).media, []), 'boot backfill: legacy image media = [media_url], legacy text media = []', JSON.stringify(lrow));
let lg = await call('GET', `/mapposts/${L1}`, { user: null, expect: 200 });
check(lg.mediaUrl === legacyCover && same(lg.media, [legacyCover]), 'legacy moment reads with media = [mediaUrl]');
// صف كتبه إصدار سابق بعد الإقلاع (تراجع النشر): بلا media، ثم غلاف عدّله بلا لمس media
const L3 = crypto.randomUUID();
await pool.query("INSERT INTO map_posts(id,user_id,kind,media_url,lat,lng,expires_at,media) VALUES($1,$2,'image',$3,21.54,39.17,now()+interval '1 day',NULL)", [L3, SARA, abs(name('legacy', 3))]);
lg = await call('GET', `/mapposts/${L3}`, { user: null, expect: 200 });
check(same(lg.media, [abs(name('legacy', 3))]), 'a row without media (older writer) still reads as [cover]');

// ---- الإنشاء بألبوم
const A = [1, 2, 3].map((n) => name('a', n));
const p = await call('POST', '/mapposts', { body: { audience: 'all', kind: 'image', mediaUrl: rel(A[0]), mediaUrls: A.map(rel), caption: 'ثلاث صور من الكورنيش', lat: 21.5433, lng: 39.1728, placeName: 'الكورنيش' }, expect: 200 });
check(p.mediaUrl === abs(A[0]) && same(p.media, A.map(abs)), 'album created: cover first, absolute urls, mediaUrl = cover', JSON.stringify(p.media));
const db = (await pool.query('SELECT media_url, media FROM map_posts WHERE id=$1', [p.id])).rows[0];
check(db.media_url === abs(A[0]) && same(db.media, A.map(abs)), 'stored: media_url = cover, media = the album');
const live = emitted.find((e) => e.kind === 'post' && e.data.id === p.id);
check(live && same(live.data.media, A.map(abs)) && live.data.mediaUrl === abs(A[0]), 'live broadcast carries the album');
const p2 = await call('POST', '/mapposts', { body: { audience: 'all', kind: 'image', mediaUrls: [rel(name('b', 1)), `https://www.naslife.app/chat/media/${name('b', 2)}`], lat: 21.54, lng: 39.17 }, expect: 200 });
check(p2.mediaUrl === abs(name('b', 1)) && same(p2.media, [abs(name('b', 1)), abs(name('b', 2))]), 'mediaUrls without mediaUrl: the first is the cover; www host normalised');
const p3 = await call('POST', '/mapposts', { body: { audience: 'all', kind: 'image', mediaUrls: [rel(name('c', 1)), rel(name('c', 2)), rel(name('c', 1))], lat: 21.54, lng: 39.17 }, expect: 200 });
check(same(p3.media, [abs(name('c', 1)), abs(name('c', 2))]), 'duplicates are dropped, order kept');
const single = await call('POST', '/mapposts', { body: { audience: 'all', kind: 'image', mediaUrl: rel(name('s', 1)), mediaUrls: [], lat: 21.54, lng: 39.17 }, expect: 200 });
check(same(single.media, [abs(name('s', 1))]), 'single photo (empty mediaUrls) = [mediaUrl] as before');
const old = await call('POST', '/mapposts', { body: { audience: 'all', kind: 'image', mediaUrl: '/chat/media/a.jpg', lat: 21.54, lng: 39.17 }, expect: 200 });
check(old.mediaUrl === 'https://naslife.app/chat/media/a.jpg' && same(old.media, ['https://naslife.app/chat/media/a.jpg']), 'an older client sending mediaUrl only works as before');
const vid = await call('POST', '/mapposts', { body: { audience: 'all', kind: 'video', mediaUrl: rel(name('v', 1).replace('.jpg', '.mp4')), lat: 21.54, lng: 39.17 }, expect: 200 });
check(same(vid.media, [vid.mediaUrl]), 'video moment media = [its clip]');
// التحقق
const bad = async (body, err, label) => { const r = await call('POST', '/mapposts', { body: { audience: 'all', kind: 'image', lat: 21.54, lng: 39.17, ...body }, expect: 400 }); check(r.error === err, label, JSON.stringify(r)); };
await bad({ mediaUrls: [rel(A[0]), 'https://evil.example/x.jpg'] }, 'bad-media', 'an external url in mediaUrls → 400 bad-media');
await bad({ mediaUrls: ['/files/x.jpg'] }, 'bad-media', 'a non /chat/media path → 400 bad-media');
await bad({ mediaUrls: ['/chat/media/../../etc/passwd'] }, 'bad-media', 'a path that is not an upload name → 400 bad-media');
await bad({ mediaUrls: rel(A[0]) }, 'bad-media', 'mediaUrls not an array → 400 bad-media');
await bad({ mediaUrls: Array.from({ length: 9 }, (_, i) => rel(name('n', i))) }, 'too-many-media', '9 photos → 400 too-many-media');
await bad({ mediaUrl: rel(A[1]), mediaUrls: A.map(rel) }, 'cover-mismatch', 'mediaUrl that is not the first of mediaUrls → 400 cover-mismatch');
const r9 = await call('POST', '/mapposts', { body: { audience: 'all', kind: 'video', mediaUrl: rel('x.mp4'), mediaUrls: [rel(A[0]), rel(A[1])], lat: 21.54, lng: 39.17 }, expect: 400 });
check(r9.error === 'album-images-only', 'mediaUrls on a video → 400 album-images-only');
const eight = await call('POST', '/mapposts', { body: { audience: 'all', kind: 'image', mediaUrls: Array.from({ length: 8 }, (_, i) => rel(name('e', i))), lat: 21.54, lng: 39.17 }, expect: 200 });
check(eight.media?.length === 8, '8 photos accepted');

// ---- كل قارئ
const list = await call('GET', '/mapposts?bbox=39.0,21.0,39.5,22.0', { user: null, expect: 200 });
check(same(list.find((x) => x.id === p.id)?.media ?? [], A.map(abs)), 'GET /mapposts carries media');
const one = await call('GET', `/mapposts/${p.id}`, { user: KHALID, expect: 200 });
check(same(one.media, A.map(abs)) && one.mediaUrl === abs(A[0]), 'GET /mapposts/:id carries media');
const mine = await call('GET', '/mapposts/mine', { expect: 200 });
check(same(mine.find((x) => x.id === p.id)?.media ?? [], A.map(abs)), 'GET /mapposts/mine carries media');
const feed = await call('GET', '/mapposts/feed?lat=21.5433&lng=39.1728&radiusKm=5&limit=60', { user: null, expect: 200 });
check(same(feed.items.find((x) => x.id === p.id)?.media ?? [], A.map(abs)), 'GET /mapposts/feed carries media');
const tr = await call('GET', '/mapposts/trending?lat=21.5433&lng=39.1728&hours=2', { user: null, expect: 200 });
const kor = tr.places.find((x) => x.key === 'name:الكورنيش');
check(kor && kor.sampleUrl === abs(A[0]), 'trending sample = the cover', JSON.stringify(kor ?? null));
const row = await call('GET', '/row?lat=21.5433&lng=39.1728', { user: null, expect: 200 });
const ri = row.items.find((x) => x.kind === 'moment' && x.id === p.id);
check(ri && ri.imageUrl === abs(A[0]) && same(ri.payload.media, A.map(abs)), '/row: card image = cover, payload.media = album', JSON.stringify(ri ? { img: ri.imageUrl, media: ri.payload.media } : null));
const rl = row.items.find((x) => x.kind === 'moment' && x.id === L1);
check(!rl || same(rl.payload.media, [legacyCover]), '/row: legacy moment payload.media = [cover]');
const fd = await call('GET', '/feed?lat=21.5433&lng=39.1728&limit=40', { user: null, expect: 200 });
const fi = fd.items.find((x) => x.kind === 'moment' && x.id === p.id);
check(fi && fi.imageUrl === abs(A[0]) && same(fi.payload.media, A.map(abs)), '/feed: same card with the album in its payload');
// رابط المشاركة: الغلاف
const html = (await app.inject({ method: 'GET', url: `/m/${p.id}`, headers: { host: 'naslife.app', 'x-forwarded-proto': 'https' } })).body;
const og = (html.match(/<meta property="og:image" content="([^"]*)"/) || [])[1];
check(og === `https://naslife.app/chat/thumb/${A[0]}`, 'share /m/:id: og:image = thumb of the cover', og);
// «محفوظاتي»: الغلاف
await call('POST', '/wishlist', { body: { kind: 'post', refId: p.id }, user: KHALID, expect: 200 });
const wl = await call('GET', '/wishlist', { user: KHALID, expect: 200 });
check(wl.find((w) => w.refId === p.id || w.ref_id === p.id)?.imageUrl === abs(A[0]), 'wishlist card image = the cover', JSON.stringify(wl.map((w) => w.imageUrl)));

// ---- التعديل
let e = await call('PATCH', `/mapposts/${p.id}`, { body: { mediaUrls: [rel(A[2]), rel(A[0]), rel(A[1])] }, expect: 200 });
check(e.mediaUrl === abs(A[2]) && same(e.media, [abs(A[2]), abs(A[0]), abs(A[1])]), 'PATCH reorders: the new first is the cover');
e = await call('PATCH', `/mapposts/${p.id}`, { body: { mediaUrls: [`https://www.naslife.app/chat/media/${A[0]}`, rel(A[2])] }, expect: 200 });
check(e.mediaUrl === abs(A[0]) && same(e.media, [abs(A[0]), abs(A[2])]), 'PATCH removes a photo (matched by path, any host)');
let er = await call('PATCH', `/mapposts/${p.id}`, { body: { mediaUrls: [rel(A[0]), rel(name('z', 1))] }, expect: 400 });
check(er.error === 'media-not-in-album', 'PATCH cannot add a photo that is not in the album → 400 media-not-in-album');
er = await call('PATCH', `/mapposts/${p.id}`, { body: { mediaUrls: [] }, expect: 400 });
check(er.error === 'empty', 'PATCH mediaUrls [] is not an edit (nothing to change) → 400 empty');
er = await call('PATCH', `/mapposts/${p.id}`, { body: { mediaUrls: 'x' }, expect: 400 });
check(er.error === 'bad-media', 'PATCH mediaUrls not an array → 400 bad-media');
er = await call('PATCH', `/mapposts/${p.id}`, { body: { mediaUrl: rel(A[2]), mediaUrls: [rel(A[0]), rel(A[2])] }, expect: 400 });
check(er.error === 'cover-mismatch', 'PATCH mediaUrl ≠ first of mediaUrls → 400 cover-mismatch');
await call('PATCH', `/mapposts/${p.id}`, { body: { mediaUrls: [rel(A[0])] }, user: SARA, expect: 403 });
e = await call('PATCH', `/mapposts/${p.id}`, { body: { caption: 'تعديل النص فقط' }, expect: 200 });
check(e.caption === 'تعديل النص فقط' && same(e.media, [abs(A[0]), abs(A[2])]), 'another edit keeps the album');
e = await call('PATCH', `/mapposts/${p.id}`, { body: { mediaUrl: rel(A[2]) }, expect: 200 });
check(e.mediaUrl === abs(A[2]) && same(e.media, [abs(A[2]), abs(A[0])]), 'PATCH mediaUrl = a photo of the album: moves it to the front, nothing removed');
const fresh = name('f', 1);
e = await call('PATCH', `/mapposts/${p.id}`, { body: { mediaUrl: rel(fresh) }, expect: 200 });
check(e.mediaUrl === abs(fresh) && same(e.media, [abs(fresh), abs(A[0])]), 'PATCH mediaUrl = a new photo (older client): replaces the cover, the rest stays');
const txt = await call('POST', '/mapposts', { body: { audience: 'all', kind: 'text', caption: 'نص', lat: 21.54, lng: 39.17 }, expect: 200 });
check(same(txt.media, []), 'text moment media = []');
er = await call('PATCH', `/mapposts/${txt.id}`, { body: { mediaUrls: [rel(A[0])] }, expect: 400 });
check(er.error === 'album-images-only', 'PATCH mediaUrls on a text moment → 400 album-images-only');
e = await call('PATCH', `/mapposts/${vid.id}`, { body: { mediaUrl: rel(name('v', 2).replace('.jpg', '.mp4')) }, expect: 200 });
check(same(e.media, [e.mediaUrl]) && e.mediaUrl.endsWith(name('v', 2).replace('.jpg', '.mp4')), 'video: PATCH mediaUrl replaces its only media');

// ---- طابور الإشراف: كل صور الألبوم
for (const u of [SARA, KHALID]) await call('POST', '/safety/report', { body: { targetType: 'post', targetId: eight.id, reason: 'مسيء' }, user: u, expect: 200 });
await call('POST', '/safety/report', { body: { targetType: 'post', targetId: single.id, reason: 'مسيء' }, user: SARA, expect: 200 });
const mq = await call('GET', '/adminapi/moderation?type=post', { user: ADMIN, expect: 200 });
const mAlbum = mq.items.find((x) => x.targetId === eight.id), mSingle = mq.items.find((x) => x.targetId === single.id);
check(mAlbum && mAlbum.mediaUrl === eight.media[0] && same(mAlbum.mediaUrls, eight.media), 'moderation: an album shows all its photos (mediaUrls), cover in mediaUrl', JSON.stringify(mAlbum?.mediaUrls?.length));
check(mSingle && mSingle.mediaUrl === single.mediaUrl && mSingle.mediaUrls === undefined, 'moderation: a single photo keeps mediaUrl only');

// ---- كنس الحساب المحذوف: صور الألبوم كلها مع الغلاف والصوت
const G = [1, 2, 3].map((n) => name('g', n));
const gp = await call('POST', '/mapposts', { body: { audience: 'all', kind: 'image', mediaUrls: G.map(rel), audioUrl: rel(name('g', 9).replace('.jpg', '.weba')), audioSec: 5, lat: 21.54, lng: 39.17 }, user: GONE, expect: 200 });
await pool.query("UPDATE map_posts SET status='hidden' WHERE id=$1", [gp.id]);
await pool.query("INSERT INTO account_deletions(user_id, status, by_id, purge_after) VALUES($1,'done',$1, now() - interval '1 minute')", [GONE]);
await globalThis.naslifeAccountSweep();
const gone = (await pool.query('SELECT 1 FROM map_posts WHERE id=$1', [gp.id])).rowCount === 0;
check(gone && G.every((n) => deleted.includes(abs(n))) && deleted.some((u) => u.endsWith('.weba')), 'account purge deletes every album photo, the cover and the voice', JSON.stringify(deleted));

// ---- الحذف لا يتأثر
await call('DELETE', `/mapposts/${p.id}`, { expect: 200 });
await call('GET', `/mapposts/${p.id}`, { user: KHALID, expect: 404 });

await app.close();
await pool.end();
console.log(fails ? `\n${fails} FAILURES` : '\nALL ALBUM TESTS PASSED');
process.exit(fails ? 1 : 0);
