// لحظات الملف الخاص (القاعدة الواحدة momentVisibleSql في map_posts.js فوق naslifeAuthorVisibleSql من profile_ext.js):
// صاحب ملف «غير عام» لا يرى لحظاته إلا هو وأصدقاؤه (من أضافهم هو إلى جهات اتصاله، تعريف «من يراسلني»). أربعة مشاهدين: الصديق،
// الغريب، من أضاف صاحب الملف من طرفه فقط (ليس صديقاً)، والضيف؛ على كل مسار تتسرب منه لحظة: GET /mapposts و/mapposts/feed
// و/mapposts/:id و/mapposts/trending والإعجاب، /row و/feed (row.js)، البث الحي /live/wait (live.js يصفّي لكل مستمع)،
// رابط المشاركة /m/:id (share.js)، التفاعلات (moment_extras.js)، والمحفوظات (wishlist.js) لمن لم يعد صديقاً. ثم العمود في users
// بدل جدول الملف، وأخيراً بلا عمود خصوصية = الجميع عامّ كما كان.
import Fastify from 'fastify';
import pg from 'pg';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0';
let fails = 0;
const check = (c, l, extra = '') => { if (!c) fails++; console.log((c ? 'OK  ' : 'FAIL') + ' ' + l + (extra ? ' ' + extra : '')); };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const AUTHOR = 'SA0000011', FRIEND = 'SA0000012', STRANGER = 'SA0000013', ONEWAY = 'SA0000014', PUB = 'SA0000015';
const VIEWERS = { author: AUTHOR, friend: FRIEND, stranger: STRANGER, oneway: ONEWAY, guest: null };
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query('DROP TABLE IF EXISTS profile_ext, user_follows, profile_views, profile_events CASCADE');
await pool.query('DROP TABLE IF EXISTS users, profiles, contacts, map_post_likes, map_post_views, map_post_events, map_posts, map_post_reactions, map_post_react_notified, wishlist_items CASCADE');
await pool.query(`CREATE TABLE users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now());
  CREATE TABLE profiles (user_id TEXT PRIMARY KEY, bio TEXT NOT NULL DEFAULT '', skills TEXT[] DEFAULT '{}', is_public BOOLEAN DEFAULT true);
  CREATE TABLE contacts (user_id TEXT NOT NULL, contact_id TEXT NOT NULL);`);
await pool.query(`INSERT INTO users(id, nickname) VALUES ('${AUTHOR}','huda'),('${FRIEND}','sara'),('${STRANGER}','khalid'),('${ONEWAY}','fahad'),('${PUB}','amr')`);
await pool.query(`INSERT INTO profiles(user_id, is_public) VALUES ('${AUTHOR}', false), ('${FRIEND}', true), ('${PUB}', true)`);
// صاحبة الملف الخاص أضافت سارة؛ فهد أضافها من طرفه فقط (طلب صداقة غير مقبول لا يفتح لحظاتها)
await pool.query(`INSERT INTO contacts(user_id, contact_id) VALUES ('${AUTHOR}', '${FRIEND}'), ('${ONEWAY}', '${AUTHOR}')`);

const auth = async (req) => req.headers['x-user'] || null;
const dir = new URL('.', import.meta.url).pathname;
const boot = async (full) => {
  const a = Fastify();
  a.register((await import('../map_posts.js')).default, { pool, auth });
  if (full) {
    a.register((await import('../moment_extras.js')).default, { pool, auth, sweepMs: 0 });
    a.register((await import('../wishlist.js')).default, { pool, auth, sweepMs: 0 });
    a.register((await import('../share.js')).default, { pool, auth, webappDir: dir + 'webapp' });
  }
  a.register((await import('../profile_ext.js')).default, { pool, auth });
  a.register((await import('../row.js')).default, { pool, auth });
  if (full) a.register((await import('../live.js')).default, { pool, auth });
  await a.ready();
  return a;
};
let app = await boot(true);
const call = async (method, url, { body = {}, user = AUTHOR, expect } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json', host: 'naslife.app', 'x-forwarded-proto': 'https' }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url} [${user ?? 'guest'}] -> ${r.statusCode}`, r.statusCode === expect ? '' : String(typeof j === 'string' ? j : JSON.stringify(j)).slice(0, 200));
  return { code: r.statusCode, j, body: r.body };
};
// يتحقق لكل مشاهد: يرى اللحظة الخاصة أم لا (المتوقع: صاحبها والصديق فقط) واللحظة العامة دائماً
const expectSeen = (label, seen) => {
  const want = { author: true, friend: true, stranger: false, oneway: false, guest: false };
  for (const [k, v] of Object.entries(want)) check(seen[k]?.priv === v && seen[k]?.pub === true, `${label}: ${k} ${v ? 'sees' : 'does not see'} the private moment, sees the public one`, JSON.stringify(seen[k]));
};

// ---- المساعدات على globalThis
check(typeof globalThis.naslifeAuthorVisibleSql === 'function' && typeof globalThis.naslifeMomentVisibleSql === 'function', 'visibility helpers exposed (profile_ext + map_posts)');
check(globalThis.naslifePrivacyStatus?.privacy === true && globalThis.naslifePrivacyStatus?.friends === true, 'privacy column and contacts discovered', JSON.stringify(globalThis.naslifePrivacyStatus));
check((await globalThis.naslifeIsPublic(AUTHOR)) === false && (await globalThis.naslifeIsPublic(PUB)) === true && (await globalThis.naslifeIsPublic(STRANGER)) === true, 'naslifeIsPublic: private author false, public and profile-less users true');
check(JSON.stringify(await globalThis.naslifeFriendIds(AUTHOR)) === JSON.stringify([FRIEND]) && (await globalThis.naslifeFriendIds(FRIEND)).length === 0, 'naslifeFriendIds = whom the user added (one-way requests excluded)');

// ---- البث الحي: مصافحة لكل مستمع قبل النشر، والغريب ينتظر فلا توقظه اللحظة الخاصة
const hs = (await call('GET', '/live/wait', { user: null, expect: 200 })).j.seq;
const strangerWait = call('GET', `/live/wait?after=${hs}&timeout=1`, { user: STRANGER });
const friendWait = call('GET', `/live/wait?after=${hs}&timeout=5`, { user: FRIEND });
await sleep(50);

// ---- النشر: لحظة خاصة لهدى ولحظة عامة لعمرو في جدة، بمكانين مكتوبين للرائج
const t0 = Date.now();
const priv = (await call('POST', '/mapposts', { body: { kind: 'image', mediaUrl: '/chat/media/abcdef-0123456789abcdef01234567.jpg', caption: 'سرّ البيت', placeName: 'بيت هدى', lat: 22.901, lng: 39.901 }, user: AUTHOR, expect: 200 })).j;
const fr = await friendWait;
check(Date.now() - t0 < 2000 && fr.j.events.some((e) => e.kind === 'post' && e.data.id === priv.id), 'live: the friend waiting is woken with the private moment', `${Date.now() - t0}ms`);
check(!fr.body.includes('"only"'), 'live: the audience list is never serialised');
const sw = await strangerWait;
check(Date.now() - t0 >= 800 && sw.j.events.length === 0 && sw.j.seq > hs, 'live: the stranger is not woken by the private moment; its wait times out with the cursor moved on', `${Date.now() - t0}ms ${JSON.stringify(sw.j)}`);
const pub = (await call('POST', '/mapposts', { body: { kind: 'text', bg: '#0A6E78', caption: 'صباح الخير', placeName: 'الكورنيش', lat: 22.903, lng: 39.903 }, user: PUB, expect: 200 })).j;
const seen = {};
for (const [k, u] of Object.entries(VIEWERS)) {
  const r = (await call('GET', `/live/wait?after=${hs}&timeout=0`, { user: u, expect: 200 })).j;
  const ids = r.events.filter((e) => e.kind === 'post').map((e) => e.data.id);
  seen[k] = { priv: ids.includes(priv.id), pub: ids.includes(pub.id) };
}
expectSeen('live /live/wait', seen);

// ---- قوائم map_posts
const sweep = async (label, urlOf, idsOf) => {
  const s = {};
  for (const [k, u] of Object.entries(VIEWERS)) { const r = await call('GET', urlOf(k), { user: u, expect: 200 }); const ids = idsOf(r.j); s[k] = { priv: ids.includes(priv.id), pub: ids.includes(pub.id) }; }
  expectSeen(label, s);
};
await sweep('GET /mapposts', () => '/mapposts?bbox=39.8,22.8,40.0,23.0', (j) => j.map((p) => p.id));
await sweep('GET /mapposts/feed', () => '/mapposts/feed?lat=22.9&lng=39.9', (j) => j.items.map((p) => p.id));
await sweep('GET /mapposts/trending', () => '/mapposts/trending?lat=22.9&lng=39.9', (j) => j.places.map((p) => p.sampleId));
await sweep('GET /row', () => '/row?lat=22.9&lng=39.9', (j) => j.items.filter((i) => i.kind === 'moment').map((i) => i.id));
await sweep('GET /feed?kind=moment', () => '/feed?kind=moment&lat=22.9&lng=39.9', (j) => j.items.map((i) => i.id));
await sweep('GET /feed (all kinds)', () => '/feed', (j) => j.items.filter((i) => i.kind === 'moment').map((i) => i.id));
for (const [k, u] of Object.entries(VIEWERS)) {
  const want = k === 'author' || k === 'friend' ? 200 : 404;
  await call('GET', `/mapposts/${priv.id}`, { user: u, expect: want });
  await call('GET', `/mapposts/${pub.id}`, { user: u, expect: 200 });
}
// «أصدقائي فقط» في البث العمودي لا يتجاوز القاعدة: الغريب يمرّر معرّفها ولا يأخذ شيئاً
check((await call('GET', `/mapposts/feed?authors=${AUTHOR}`, { user: STRANGER })).j.items.length === 0, 'feed authors filter cannot reach a private author');
// الإعجاب: الغريب 404، الصديق يعجب
await call('POST', `/mapposts/${priv.id}/like`, { user: STRANGER, expect: 404 });
check((await call('POST', `/mapposts/${priv.id}/like`, { user: FRIEND, expect: 200 })).j.liked === true, 'friend can like the private moment');

// ---- رابط المشاركة: لحظة الملف الخاص بلا صورة ولا نص ولا مكان (من يقرأ الوسوم ضيف)
const getHtml = async (url) => (await app.inject({ method: 'GET', url, headers: { host: 'naslife.app', 'x-forwarded-proto': 'https' } })).body;
const meta = (html, prop) => (html.match(new RegExp(`<meta (?:property|name)="${prop}" content="([^"]*)"`)) || [])[1];
let h = await getHtml(`/m/${priv.id}`);
check(meta(h, 'og:title') === 'لحظة على ناس لايف' && meta(h, 'og:image') === undefined && !h.includes('سرّ البيت') && !h.includes('بيت هدى') && !h.includes('huda') && !h.includes('22.901'), 'share /m/: private moment → generic tags, no image, caption, author or place');
check(h.includes(`url=/#/m/${priv.id}`), 'share /m/: still redirects into the app (friends open it signed in)');
h = await getHtml(`/m/${pub.id}`);
check(meta(h, 'og:title') === 'صباح الخير' && meta(h, 'og:description') === 'amr · الكورنيش', 'share /m/: public moment keeps its preview');

// ---- التفاعلات
for (const [k, u] of Object.entries(VIEWERS)) await call('GET', `/moments/${priv.id}/reactions`, { user: u, expect: k === 'author' || k === 'friend' ? 200 : 404 });
await call('POST', `/moments/${priv.id}/react`, { body: { emoji: '🔥' }, user: STRANGER, expect: 404 });
await call('POST', `/moments/${priv.id}/react`, { body: { emoji: '🔥' }, user: FRIEND, expect: 200 });
await call('GET', `/moments/${pub.id}/reactions`, { user: null, expect: 200 });

// ---- المحفوظات: الغريب لا يحفظها، والصديق يحفظها ثم تُزال صداقته فتصير بطاقة عامة وتُغلق التفاعلات أمامه
await call('POST', '/wishlist', { body: { kind: 'post', refId: priv.id }, user: STRANGER, expect: 404 });
const w = (await call('POST', '/wishlist', { body: { kind: 'post', refId: priv.id }, user: FRIEND, expect: 200 })).j;
check(w.title === 'سرّ البيت' && w.available === true, 'friend saves the private moment', JSON.stringify(w));
await pool.query('DELETE FROM contacts WHERE user_id=$1 AND contact_id=$2', [AUTHOR, FRIEND]);
const list = (await call('GET', '/wishlist', { user: FRIEND, expect: 200 })).j;
const item = list.find((x) => x.refId === priv.id);
check(item && item.title === 'لحظة لم تعد متاحة' && item.imageUrl === null && item.available === false, 'ex-friend: the saved moment becomes the generic card (no title, no image)', JSON.stringify(item));
await call('GET', `/moments/${priv.id}/reactions`, { user: FRIEND, expect: 404 });
await call('GET', `/mapposts/${priv.id}`, { user: FRIEND, expect: 404 });
check(!(await call('GET', '/mapposts', { user: FRIEND })).j.some((p) => p.id === priv.id), 'ex-friend no longer sees it on the map');
await pool.query('INSERT INTO contacts(user_id, contact_id) VALUES ($1, $2)', [AUTHOR, FRIEND]);

// ---- الملف يعود عاماً: الجميع يرون اللحظة فوراً (القاعدة تُقرأ مع كل طلب)
await pool.query('UPDATE profiles SET is_public=true WHERE user_id=$1', [AUTHOR]);
check((await call('GET', '/mapposts', { user: null })).j.some((p) => p.id === priv.id), 'profile made public → guests see the moment');
await call('GET', `/mapposts/${priv.id}`, { user: STRANGER, expect: 200 });
await pool.query('UPDATE profiles SET is_public=false WHERE user_id=$1', [AUTHOR]);

// ---- الكفاءة: استعلام واحد بلا استعلام لكل صف (الأجزاء استعلامات فرعية غير مرتبطة)
const frag = globalThis.naslifeMomentVisibleSql('p', '$1::text');
check(!/\bp\.(?!user_id)/.test(frag.replace(/\bp\.user_id\b/g, '')) && (frag.match(/p\.user_id/g) || []).length === 3, 'fragment references the row only through p.user_id (uncorrelated subqueries)', frag);
const plan = (await pool.query(`EXPLAIN SELECT p.id FROM map_posts p WHERE ${frag}`, [STRANGER])).rows.map((r) => r['QUERY PLAN']).join('\n');
check((plan.match(/hashed SubPlan/g) || []).length === 2, 'planner hashes the private-id and friend sets once per query', plan.replace(/\n/g, ' | ').slice(0, 300));

await app.close();

// ---- العمود في users بدل جدول الملف (users.is_public كما يكتشفه profile_ext)
await pool.query('ALTER TABLE profiles DROP COLUMN is_public');
await pool.query('ALTER TABLE users ADD COLUMN is_public BOOLEAN DEFAULT true');
await pool.query('UPDATE users SET is_public=false WHERE id=$1', [AUTHOR]);
app = await boot(false);
check(globalThis.naslifePrivacyStatus?.privacy === true, 'users.is_public discovered');
let ids = (await call('GET', '/mapposts', { user: STRANGER, expect: 200 })).j.map((p) => p.id);
check(!ids.includes(priv.id) && ids.includes(pub.id), 'users.is_public=false hides the moment from a stranger');
ids = (await call('GET', '/mapposts', { user: FRIEND, expect: 200 })).j.map((p) => p.id);
check(ids.includes(priv.id), 'users.is_public=false: the friend still sees it');
ids = (await call('GET', '/feed?kind=moment', { user: null, expect: 200 })).j.items.map((i) => i.id);
check(!ids.includes(priv.id) && ids.includes(pub.id), 'users.is_public=false: /feed hides it from guests');
await app.close();

// ---- بلا عمود خصوصية في النواة: الجميع عامّ كما كان
await pool.query('ALTER TABLE users DROP COLUMN is_public');
app = await boot(true);
check(globalThis.naslifePrivacyStatus?.privacy === false && (await globalThis.naslifeIsPublic(AUTHOR)) === true, 'no privacy column → everyone public');
ids = (await call('GET', '/mapposts', { user: null, expect: 200 })).j.map((p) => p.id);
check(ids.includes(priv.id) && ids.includes(pub.id), 'no privacy column → guests see every moment (current behaviour)');
await call('GET', `/mapposts/${priv.id}`, { user: STRANGER, expect: 200 });
// الجزء «الصحيح دائماً» يبقى يذكر معامل المشاهد: الإعجاب والتفاعل والحفظ يمررونه وحده (Postgres يرفض معاملاً غير مستعمل)
await call('POST', `/mapposts/${priv.id}/like`, { user: STRANGER, expect: 200 });
await call('GET', `/moments/${priv.id}/reactions`, { user: null, expect: 200 });
await call('POST', `/moments/${priv.id}/react`, { body: { emoji: '👏' }, user: STRANGER, expect: 200 });
await call('POST', '/wishlist', { body: { kind: 'post', refId: priv.id }, user: STRANGER, expect: 200 });
check(meta(await getHtml(`/m/${priv.id}`), 'og:title') === 'سرّ البيت', 'no privacy column → share preview as before');
await app.close();

await pool.end();
console.log(fails ? `${fails} FAILED` : 'ALL PRIVATE MOMENTS TESTS PASSED');
process.exit(fails ? 1 : 0);
