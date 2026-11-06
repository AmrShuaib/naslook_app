// «الجمهور» لكل لحظة (map_posts.audience: friends | all، قرار المالك: الافتراضي «الأصدقاء» للحظة الشخصية) فوق القاعدة الواحدة
// momentVisibleSql في map_posts.js: يرى اللحظة صاحبها، أو صديقه (من أضافه صاحبها إلى جهات اتصاله)، أو أي أحد حين يكون جمهورها «الجميع»
// وملف صاحبها عاماً. هنا صاحبة ملف «عام» تنشر لحظة للأصدقاء ولحظة للجميع، وخمسة مشاهدين (صاحبتها، الصديقة، الغريب، من أضافها من طرفه
// فقط، والضيف) على كل مسار تتسرب منه لحظة: GET /mapposts و/mapposts/feed و/mapposts/:id و/mapposts/trending (والعدّ فيه) والإعجاب
// والمشاهدة، /row و/feed (row.js)، البث الحي /live/wait (live.js)، رابط المشاركة /m/:id (share.js)، التفاعلات (moment_extras.js)،
// المحفوظات (wishlist.js)، بطاقة #post في المحادثة (chat_cards.js)، البحث المحفوظ (saved_search.js)، وعدّ منشورات الملف (profile_ext.js)،
// وإحصاءات منشورات الدائرة /mapposts/stats/biz (الأرقام لصاحب الدائرة، والنص والصاحب لمن يرى اللحظة وحده).
// ثم الافتراضي عند الإنشاء بلا اختيار، والتعديل بـPATCH (صاحبها فقط) مع أحداثه الحية، والجمع مع الملف الخاص، والكفاءة بـEXPLAIN،
// والاحتياط المغلق بلا قاعدة profile_ext.js أو بقاعدة قديمة لا تفهم الجمهور، وأخيراً بلا عمود خصوصية في النواة.
import Fastify from 'fastify';
import pg from 'pg';
import { defaultAudience, AUDIENCES } from '../map_posts.js';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0';
let fails = 0;
const check = (c, l, extra = '') => { if (!c) fails++; console.log((c ? 'OK  ' : 'FAIL') + ' ' + l + (extra ? ' ' + extra : '')); };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---- القاعدة الخالصة للافتراضي
check(AUDIENCES.has('friends') && AUDIENCES.has('all') && AUDIENCES.size === 2, 'two audiences: friends, all');
check(defaultAudience({}) === 'friends' && defaultAudience({ tag: 'moment' }) === 'friends', 'default: a personal moment is for friends');
for (const tag of ['offer', 'ad', 'invest', 'event', 'job']) check(defaultAudience({ tag }) === 'all', `default: tag ${tag} is for everyone`);
check(defaultAudience({ tag: 'moment', price: 0 }) === 'all' && defaultAudience({ tag: 'moment', price: 1500 }) === 'all', 'default: a priced post (even free) is for everyone');
check(defaultAudience({ tag: 'moment', cta: { type: 'chat' } }) === 'all', 'default: a post with a call-to-action is for everyone');

const AUTHOR = 'SA0000021', FRIEND = 'SA0000022', STRANGER = 'SA0000023', ONEWAY = 'SA0000024', PRIV = 'SA0000025';
const VIEWERS = { author: AUTHOR, friend: FRIEND, stranger: STRANGER, oneway: ONEWAY, guest: null };
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query('DROP TABLE IF EXISTS profile_ext, user_follows, profile_views, profile_events CASCADE');
await pool.query('DROP TABLE IF EXISTS saved_searches CASCADE');
await pool.query('DROP TABLE IF EXISTS users, profiles, contacts, map_post_likes, map_post_views, map_post_events, map_posts, map_post_reactions, map_post_react_notified, wishlist_items CASCADE');
await pool.query(`CREATE TABLE users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now());
  CREATE TABLE profiles (user_id TEXT PRIMARY KEY, bio TEXT NOT NULL DEFAULT '', skills TEXT[] DEFAULT '{}', is_public BOOLEAN DEFAULT true);
  CREATE TABLE contacts (user_id TEXT NOT NULL, contact_id TEXT NOT NULL);`);
await pool.query(`INSERT INTO users(id, nickname) VALUES ('${AUTHOR}','huda'),('${FRIEND}','sara'),('${STRANGER}','khalid'),('${ONEWAY}','fahad'),('${PRIV}','mona')`);
// هدى ملفها عام؛ منى ملفها خاص. كلتاهما أضافت سارة؛ فهد أضاف هدى من طرفه فقط (لا يفتح لحظات «الأصدقاء»)
await pool.query(`INSERT INTO profiles(user_id, is_public) VALUES ('${AUTHOR}', true), ('${FRIEND}', true), ('${PRIV}', false)`);
await pool.query(`INSERT INTO contacts(user_id, contact_id) VALUES ('${AUTHOR}', '${FRIEND}'), ('${PRIV}', '${FRIEND}'), ('${ONEWAY}', '${AUTHOR}')`);

const auth = async (req) => req.headers['x-user'] || null;
const dir = new URL('.', import.meta.url).pathname;
const boot = async ({ profileExt = true } = {}) => {
  const a = Fastify();
  a.register((await import('../map_posts.js')).default, { pool, auth });
  a.register((await import('../moment_extras.js')).default, { pool, auth, sweepMs: 0 });
  a.register((await import('../wishlist.js')).default, { pool, auth, sweepMs: 0 });
  a.register((await import('../share.js')).default, { pool, auth, webappDir: dir + 'webapp' });
  a.register((await import('../chat_cards.js')).default, { pool, auth });
  a.register((await import('../saved_search.js')).default, { pool, auth, sweepMs: 0 });
  if (profileExt) a.register((await import('../profile_ext.js')).default, { pool, auth });
  a.register((await import('../row.js')).default, { pool, auth });
  a.register((await import('../live.js')).default, { pool, auth });
  await a.ready();
  return a;
};
let app = await boot();
const call = async (method, url, { body = {}, user = AUTHOR, expect } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json', host: 'naslife.app', 'x-forwarded-proto': 'https' }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url} [${user ?? 'guest'}] -> ${r.statusCode}`, r.statusCode === expect ? '' : String(typeof j === 'string' ? j : JSON.stringify(j)).slice(0, 200));
  return { code: r.statusCode, j, body: r.body };
};
const IMG = '/chat/media/abcdef-0123456789abcdef01234567.jpg';
const post = async (body, user = AUTHOR, expect = 200) => (await call('POST', '/mapposts', { body: { lat: 22.901, lng: 39.901, ...body }, user, expect })).j;

// ---- الافتراضي عند الإنشاء (بلا اختيار صريح) والاختيار الصريح والقيمة الخاطئة
{
  const made = [];
  const mk = async (label, body, want) => { const p = await post(body); made.push(p.id); check(p.audience === want, `create: ${label} → ${want}`, JSON.stringify({ audience: p.audience, tag: p.tag })); };
  await mk('plain moment', { kind: 'text', caption: 'لحظة' }, 'friends');
  await mk('tag moment', { kind: 'text', caption: 'لحظة', tag: 'moment' }, 'friends');
  await mk('offer', { kind: 'text', caption: 'عرض', tag: 'offer' }, 'all');
  await mk('event', { kind: 'text', caption: 'فعالية', tag: 'event' }, 'all');
  await mk('job', { kind: 'text', caption: 'وظيفة', tag: 'job' }, 'all');
  await mk('unknown tag (cleaned to moment)', { kind: 'text', caption: 'x', tag: 'zzz' }, 'friends');
  await mk('moment with a price', { kind: 'text', caption: 'كيك', price: 2500 }, 'all');
  await mk('moment with a call-to-action', { kind: 'text', caption: 'راسلني', cta: { type: 'chat' } }, 'all');
  await mk('moment with an invalid call-to-action (dropped)', { kind: 'text', caption: 'x', cta: { type: 'link', value: 'javascript:1' } }, 'friends');
  await mk('explicit all on a moment', { kind: 'text', caption: 'للجميع', audience: 'all' }, 'all');
  await mk('explicit friends on an offer', { kind: 'text', caption: 'عرض للأصدقاء', tag: 'offer', audience: 'friends' }, 'friends');
  await mk('empty audience = default', { kind: 'text', caption: 'x', audience: '' }, 'friends');
  await call('POST', '/mapposts', { body: { kind: 'text', caption: 'x', lat: 22.9, lng: 39.9, audience: 'public' }, expect: 400 });
  const mine = (await call('GET', '/mapposts/mine', { expect: 200 })).j;
  check(mine.length === made.length && mine.every((p) => p.audience === 'friends' || p.audience === 'all'), '/mapposts/mine carries each moment\'s audience');
  await pool.query('DELETE FROM map_posts WHERE id = ANY($1::uuid[])', [made]);
}
// الصفوف القديمة (قبل العمود) تبقى «الجميع»: افتراضي العمود
check((await pool.query("SELECT column_default FROM information_schema.columns WHERE table_name='map_posts' AND column_name='audience'")).rows[0]?.column_default?.includes("'all'"), 'column default is all (rows from before the feature were public)');

// ---- البث الحي: مصافحة ثم لحظة للأصدقاء ولحظة للجميع من صاحبة ملف عام
const hs = (await call('GET', '/live/wait', { user: null, expect: 200 })).j.seq;
const strangerWait = call('GET', `/live/wait?after=${hs}&timeout=1`, { user: STRANGER });
const friendWait = call('GET', `/live/wait?after=${hs}&timeout=5`, { user: FRIEND });
await sleep(50);
const t0 = Date.now();
const fo = await post({ kind: 'image', mediaUrl: IMG, caption: 'عشاء البيت', placeName: 'بيت هدى' });
check(fo.audience === 'friends', 'friends-only moment created by default');
const fr = await friendWait;
check(Date.now() - t0 < 2000 && fr.j.events.some((e) => e.kind === 'post' && e.data.id === fo.id && e.data.audience === 'friends'), 'live: the waiting friend is woken with the friends-only moment', `${Date.now() - t0}ms`);
check(!fr.body.includes('"only"'), 'live: the audience list is never serialised');
const sw = await strangerWait;
check(Date.now() - t0 >= 800 && sw.j.events.length === 0 && sw.j.seq > hs, 'live: the stranger is not woken by it; the cursor moves on', `${Date.now() - t0}ms ${JSON.stringify(sw.j)}`);
const pub = await post({ kind: 'text', bg: '#0A6E78', caption: 'صباح الخير', placeName: 'الكورنيش', audience: 'all', lat: 22.903, lng: 39.903 });
// لحظة ثانية للأصدقاء في المكان نفسه («الكورنيش») حتى يُختبر عدّ الرائج
const fo2 = await post({ kind: 'text', bg: '#0A6E78', caption: 'سرّ الكورنيش', placeName: 'الكورنيش', lat: 22.903, lng: 39.903 });
const expectSeen = (label, seen) => {
  const want = { author: true, friend: true, stranger: false, oneway: false, guest: false };
  for (const [k, v] of Object.entries(want)) check(seen[k]?.fo === v && seen[k]?.pub === true, `${label}: ${k} ${v ? 'sees' : 'does not see'} the friends-only moment, sees the public one`, JSON.stringify(seen[k]));
};
{
  const seen = {};
  for (const [k, u] of Object.entries(VIEWERS)) {
    const ids = (await call('GET', `/live/wait?after=${hs}&timeout=0`, { user: u, expect: 200 })).j.events.filter((e) => e.kind === 'post').map((e) => e.data.id);
    seen[k] = { fo: ids.includes(fo.id) && ids.includes(fo2.id), pub: ids.includes(pub.id) };
  }
  expectSeen('live /live/wait', seen);
}

// ---- القوائم
const sweep = async (label, urlOf, idsOf) => {
  const s = {};
  for (const [k, u] of Object.entries(VIEWERS)) { const r = await call('GET', urlOf(k), { user: u, expect: 200 }); const ids = idsOf(r.j); s[k] = { fo: ids.includes(fo.id), pub: ids.includes(pub.id) }; }
  expectSeen(label, s);
};
await sweep('GET /mapposts', () => '/mapposts?bbox=39.8,22.8,40.0,23.0', (j) => j.map((p) => p.id));
await sweep('GET /mapposts/feed', () => '/mapposts/feed?lat=22.9&lng=39.9', (j) => j.items.map((p) => p.id));
await sweep('GET /row', () => '/row?lat=22.9&lng=39.9', (j) => j.items.filter((i) => i.kind === 'moment').map((i) => i.id));
await sweep('GET /feed?kind=moment', () => '/feed?kind=moment&lat=22.9&lng=39.9', (j) => j.items.map((i) => i.id));
await sweep('GET /feed (all kinds)', () => '/feed', (j) => j.items.filter((i) => i.kind === 'moment').map((i) => i.id));
// حمولة اللحظة في الصف والتغذية تحمل جمهورها (العارض يفتح منها ويضع «للأصدقاء»)
{
  const feed = (await call('GET', '/feed?kind=moment&lat=22.9&lng=39.9', { user: FRIEND, expect: 200 })).j.items;
  const row = (await call('GET', '/row?lat=22.9&lng=39.9', { user: FRIEND, expect: 200 })).j.items;
  const aud = (list, id) => list.find((i) => i.id === id)?.payload?.audience;
  check(aud(feed, fo.id) === 'friends' && aud(feed, pub.id) === 'all' && aud(row, fo.id) === 'friends' && aud(row, pub.id) === 'all', '/feed and /row moment payloads carry the audience', JSON.stringify([aud(feed, fo.id), aud(feed, pub.id), aud(row, fo.id), aud(row, pub.id)]));
}
// الرائج يعدّ ما يراه المشاهد وحده: «الكورنيش» فيه لحظة عامة ولحظة للأصدقاء، و«بيت هدى» لا يظهر للغريب أصلاً
for (const [k, u] of Object.entries(VIEWERS)) {
  const places = (await call('GET', '/mapposts/trending?lat=22.9&lng=39.9', { user: u, expect: 200 })).j.places;
  const corn = places.find((p) => p.name === 'الكورنيش'), home = places.find((p) => p.name === 'بيت هدى');
  const insider = k === 'author' || k === 'friend';
  check(corn?.posts === (insider ? 2 : 1) && !!home === insider && (insider || corn?.sampleId === pub.id), `trending counts only what ${k} can see`, JSON.stringify(places.map((p) => [p.name, p.posts, p.sampleId === pub.id ? 'pub' : p.sampleId === fo2.id ? 'fo2' : p.sampleId])));
}
for (const [k, u] of Object.entries(VIEWERS)) {
  const r = await call('GET', `/mapposts/${fo.id}`, { user: u, expect: k === 'author' || k === 'friend' ? 200 : 404 });
  if (r.code === 200) check(r.j.audience === 'friends', `GET /mapposts/:id carries audience for ${k}`);
  await call('GET', `/mapposts/${pub.id}`, { user: u, expect: 200 });
}
// «أصدقائي فقط» في البث لا يتجاوز القاعدة
check((await call('GET', `/mapposts/feed?authors=${AUTHOR}`, { user: STRANGER })).j.items.every((p) => p.audience === 'all'), 'feed authors filter gives a stranger the public moments only');
// الإعجاب والمشاهدة وتتبّع الإجراء: من لا يراها لا يعجب ولا يُعدّ
await call('POST', `/mapposts/${fo.id}/like`, { user: STRANGER, expect: 404 });
await call('POST', `/mapposts/${fo.id}/like`, { user: ONEWAY, expect: 404 });
check((await call('POST', `/mapposts/${fo.id}/like`, { user: FRIEND, expect: 200 })).j.liked === true, 'the friend likes the friends-only moment');
await call('POST', `/mapposts/${fo.id}/view`, { user: STRANGER, expect: 404 });
check((await call('POST', `/mapposts/${fo.id}/view`, { user: FRIEND, expect: 200 })).j.views === 1, 'the friend\'s view counts');
await call('POST', `/mapposts/${fo.id}/cta`, { user: STRANGER, expect: 200 });
await call('POST', `/mapposts/${fo.id}/contact`, { user: FRIEND, expect: 200 });
{
  const ev = (await pool.query('SELECT user_id, kind FROM map_post_events WHERE post_id=$1 ORDER BY id', [fo.id])).rows;
  check(!ev.some((e) => e.user_id === STRANGER) && ev.some((e) => e.user_id === FRIEND && e.kind === 'contact'), 'stats log events only from viewers who can see the moment', JSON.stringify(ev));
}
// بطاقة #post في المحادثة
{
  const ref = encodeURIComponent(`#post/${fo.id}`);
  check((await call('GET', `/chat/cards?refs=${ref}`, { user: STRANGER, expect: 200 })).j.refs[`#post/${fo.id}`] === null, 'chat card #post: none for a stranger');
  check((await call('GET', `/chat/cards?refs=${ref}`, { user: FRIEND, expect: 200 })).j.refs[`#post/${fo.id}`]?.id === fo.id, 'chat card #post: the friend gets it');
}
// البحث المحفوظ
{
  const runFor = async (user) => {
    const s = (await call('POST', '/searches/saved', { body: { q: 'عشاء' }, user, expect: 200 })).j;
    return (await call('POST', `/searches/saved/${s.id}/run`, { user, expect: 200 })).j.items.map((i) => i.id);
  };
  check(!(await runFor(STRANGER)).includes(fo.id), 'saved search: a stranger is not matched with the friends-only moment');
  check((await runFor(FRIEND)).includes(fo.id), 'saved search: the friend is matched with it');
}
// رابط المشاركة: من يقرأ الوسوم ضيف، فلحظة «الأصدقاء» بوسوم عامة بلا صورة ولا نص ولا مكان
const getHtml = async (url) => (await app.inject({ method: 'GET', url, headers: { host: 'naslife.app', 'x-forwarded-proto': 'https' } })).body;
const meta = (html, prop) => (html.match(new RegExp(`<meta (?:property|name)="${prop}" content="([^"]*)"`)) || [])[1];
{
  const h = await getHtml(`/m/${fo.id}`);
  check(meta(h, 'og:title') === 'لحظة على ناس لايف' && meta(h, 'og:image') === undefined && !h.includes('عشاء البيت') && !h.includes('بيت هدى') && !h.includes('huda'), 'share /m/: friends-only moment → generic tags');
  check(meta(await getHtml(`/m/${pub.id}`), 'og:title') === 'صباح الخير', 'share /m/: the public moment keeps its preview');
}
// التفاعلات
for (const [k, u] of Object.entries(VIEWERS)) await call('GET', `/moments/${fo.id}/reactions`, { user: u, expect: k === 'author' || k === 'friend' ? 200 : 404 });
await call('POST', `/moments/${fo.id}/react`, { body: { emoji: '🔥' }, user: STRANGER, expect: 404 });
await call('POST', `/moments/${fo.id}/react`, { body: { emoji: '🔥' }, user: FRIEND, expect: 200 });
// المحفوظات
await call('POST', '/wishlist', { body: { kind: 'post', refId: fo.id }, user: STRANGER, expect: 404 });
check((await call('POST', '/wishlist', { body: { kind: 'post', refId: fo.id }, user: FRIEND, expect: 200 })).j.title === 'عشاء البيت', 'the friend saves the friends-only moment');
// عدّ منشورات الملف يطابق ما يفتحه كل مشاهد
{
  const count = async (u) => (await call('GET', `/profiles/${AUTHOR}/v2`, { user: u, expect: 200 })).j.stats?.posts;
  const [a, f, s, g] = [await count(AUTHOR), await count(FRIEND), await count(STRANGER), await count(null)];
  check(a === 3 && f === 3 && s === 1 && g === 1, 'profile posts count follows the audience (author/friend 3, stranger/guest 1)', JSON.stringify({ a, f, s, g }));
}
// إحصاءات منشورات الدائرة: أي أحد يضع زر دائرة على لحظته، فصاحب الدائرة الغريب يأخذ أرقام لحظة «الأصدقاء» بلا نصها ولا صاحبها
{
  // جدول الدوائر لا تنشئه هذه الحزمة: إن غاب أُنشئ بأقل أعمدته ثم يُحذف حتى لا يرثه business.js ناقصاً في قاعدة مشتركة
  const hadBiz = (await pool.query("SELECT to_regclass('public.biz') AS t")).rows[0].t !== null;
  if (!hadBiz) await pool.query('CREATE TABLE biz (id TEXT PRIMARY KEY, name TEXT NOT NULL, category TEXT NOT NULL, lat DOUBLE PRECISION NOT NULL, lng DOUBLE PRECISION NOT NULL, owner_id TEXT)');
  const SLUG = 'biz-aud-stats', cta = { type: 'biz', value: SLUG };
  const setOwner = (u) => pool.query("INSERT INTO biz(id, name, category, lat, lng, owner_id) VALUES ($1, 'مقهى', 'cafe', 22.9, 39.9, $2) ON CONFLICT (id) DO UPDATE SET owner_id = EXCLUDED.owner_id", [SLUG, u]);
  await setOwner(STRANGER);
  const sf = await post({ kind: 'text', caption: 'سر عائلي خاص بالأصدقاء', cta, audience: 'friends' });
  const sp = await post({ kind: 'text', caption: 'تعالوا للمقهى', cta, audience: 'all' });
  await call('POST', `/mapposts/${sf.id}/view`, { user: FRIEND, expect: 200 });
  await call('GET', `/mapposts/${sf.id}`, { user: STRANGER, expect: 404 });
  const statsFor = async (user) => {
    const r = await call('GET', `/mapposts/stats/biz/${SLUG}`, { user, expect: 200 });
    return { body: r.body, n: r.j.posts, f: r.j.byPost?.find((x) => x.id === sf.id), p: r.j.byPost?.find((x) => x.id === sp.id) };
  };
  let st = await statsFor(STRANGER);
  check(st.n === 2 && st.f?.title === 'منشور خاص' && st.f?.author === null && st.f?.views === 1 && !st.body.includes('سر عائلي'), 'circle stats: a stranger owner keeps the friends-only moment\'s numbers but not its caption or author', JSON.stringify(st.f));
  check(st.p?.title === 'تعالوا للمقهى' && st.p?.author === AUTHOR, 'circle stats: the public moment keeps its caption and author', JSON.stringify(st.p));
  await setOwner(FRIEND);
  st = await statsFor(FRIEND);
  check(st.f?.title === 'سر عائلي خاص بالأصدقاء' && st.f?.author === AUTHOR, 'circle stats: an owner who is the author\'s friend sees the friends-only moment', JSON.stringify(st.f));
  // الإدارة ترى كل شيء ولو لم تكن من أصدقائها
  const isAdmin0 = globalThis.naslifeIsAdmin;
  globalThis.naslifeIsAdmin = async (u) => u === ONEWAY;
  st = await statsFor(ONEWAY);
  check(st.f?.title === 'سر عائلي خاص بالأصدقاء' && st.f?.author === AUTHOR, 'circle stats: an admin sees every row', JSON.stringify(st.f));
  if (isAdmin0 === undefined) delete globalThis.naslifeIsAdmin; else globalThis.naslifeIsAdmin = isAdmin0;
  await call('GET', `/mapposts/stats/biz/${SLUG}`, { user: STRANGER, expect: 403 });
  await pool.query('DELETE FROM map_posts WHERE id = ANY($1::uuid[])', [[sf.id, sp.id]]);
  if (hadBiz) await pool.query('DELETE FROM biz WHERE id=$1', [SLUG]); else await pool.query('DROP TABLE biz');
}

// ---- التعديل: صاحبها وحده، وقيمة صحيحة فقط، والتطبيقات المفتوحة تتبع التغيير
await call('PATCH', `/mapposts/${fo.id}`, { body: { audience: 'all' }, user: FRIEND, expect: 403 });
await call('PATCH', `/mapposts/${fo.id}`, { body: { audience: 'everyone' }, expect: 400 });
let h1 = (await call('GET', '/live/wait', { user: null, expect: 200 })).j.seq;
check((await call('PATCH', `/mapposts/${fo.id}`, { body: { audience: 'all' }, expect: 200 })).j.audience === 'all', 'PATCH widens to everyone');
for (const [k, u] of Object.entries(VIEWERS)) {
  await call('GET', `/mapposts/${fo.id}`, { user: u, expect: 200 });
  const evs = (await call('GET', `/live/wait?after=${h1}&timeout=0`, { user: u, expect: 200 })).j.events;
  check(evs.some((e) => e.kind === 'post_restored' && e.data.id === fo.id) && !evs.some((e) => e.kind === 'post_removed'), `live: widening tells ${k} to refetch (post_restored)`, JSON.stringify(evs.map((e) => e.kind)));
}
check((await call('GET', '/mapposts', { user: null })).j.some((p) => p.id === fo.id), 'widened: guests see it on the map');
h1 = (await call('GET', '/live/wait', { user: null, expect: 200 })).j.seq;
check((await call('PATCH', `/mapposts/${fo.id}`, { body: { audience: 'friends' }, expect: 200 })).j.audience === 'friends', 'PATCH narrows back to friends');
for (const [k, u] of Object.entries(VIEWERS)) {
  const insider = k === 'author' || k === 'friend';
  await call('GET', `/mapposts/${fo.id}`, { user: u, expect: insider ? 200 : 404 });
  const evs = (await call('GET', `/live/wait?after=${h1}&timeout=0`, { user: u, expect: 200 })).j.events;
  const removed = evs.some((e) => e.kind === 'post_removed' && e.data.id === fo.id), restored = evs.some((e) => e.kind === 'post_restored' && e.data.id === fo.id);
  check(removed && restored === insider, `live: narrowing removes it from ${k}'s open lists${insider ? ' then refetches it' : ''}`, JSON.stringify(evs.map((e) => e.kind)));
}
check(!(await call('GET', '/mapposts', { user: STRANGER })).j.some((p) => p.id === fo.id), 'narrowed: the stranger no longer sees it on the map');
// تعديل حقول أخرى لا يمس الجمهور ولا يبث تغيّراً
h1 = (await call('GET', '/live/wait', { user: null, expect: 200 })).j.seq;
check((await call('PATCH', `/mapposts/${fo.id}`, { body: { caption: 'عشاء البيت 2' }, expect: 200 })).j.audience === 'friends', 'PATCH without audience keeps it');
check((await call('GET', `/live/wait?after=${h1}&timeout=0`, { user: AUTHOR, expect: 200 })).j.events.length === 0, 'no live event for an unrelated edit');

// ---- الجمع مع الملف الخاص: منى ملفها خاص، فلحظتها «للجميع» لأصدقائها وحدهم كذلك
{
  const pa = await post({ kind: 'text', caption: 'منى للجميع', audience: 'all' }, PRIV);
  const pf = await post({ kind: 'text', caption: 'منى للأصدقاء' }, PRIV);
  for (const [k, u] of Object.entries({ ...VIEWERS, author: PRIV })) {
    const ids = (await call('GET', '/mapposts?bbox=39.8,22.8,40.0,23.0', { user: u, expect: 200 })).j.map((p) => p.id);
    const insider = k === 'author' || k === 'friend';
    check(ids.includes(pa.id) === insider && ids.includes(pf.id) === insider, `private profile × audience: ${k} ${insider ? 'sees both' : 'sees neither'}`);
  }
  // توسيعها لا يبث «أعد الجلب» للجميع: لا جديد لغير أصدقائها
  const h2 = (await call('GET', '/live/wait', { user: null, expect: 200 })).j.seq;
  await call('PATCH', `/mapposts/${pf.id}`, { body: { audience: 'all' }, user: PRIV, expect: 200 });
  check((await call('GET', `/live/wait?after=${h2}&timeout=0`, { user: STRANGER, expect: 200 })).j.events.length === 0, 'widening on a private profile tells strangers nothing');
  await pool.query('DELETE FROM map_posts WHERE id = ANY($1::uuid[])', [[pa.id, pf.id]]);
}

// ---- الكفاءة: القائمة غير مرتبطة بالصف إلا بعمودين منه (user_id وaudience)، ومجموعتان مجزّأتان مرة لكل استعلام، وكلفة تحت JIT
const frag = globalThis.naslifeMomentVisibleSql('p', '$1::text');
const one = globalThis.naslifeMomentVisibleSql('p', '$1::text', { single: true });
check(frag.includes("p.audience = 'all'") && one.includes("p.audience = 'all'"), 'both forms carry the audience condition', `${frag} || ${one}`);
check(frag.indexOf("p.audience = 'all'") < frag.indexOf('NOT IN'), 'the cheap row condition comes before the private-id set');
{
  const plan = (await pool.query(`EXPLAIN SELECT p.id FROM map_posts p WHERE ${frag}`, [STRANGER])).rows.map((r) => r['QUERY PLAN']).join('\n');
  check((plan.match(/hashed SubPlan/g) || []).length === 2, 'list: the planner hashes the private-id and friend sets once per query', plan.replace(/\n/g, ' | ').slice(0, 300));
  await pool.query(`INSERT INTO users(id, nickname) SELECT 'SG'||lpad(g::text, 7, '0'), 'filler'||g FROM generate_series(1, 20000) g`);
  await pool.query(`INSERT INTO profiles(user_id, is_public) SELECT 'SG'||lpad(g::text, 7, '0'), g % 5 <> 0 FROM generate_series(1, 20000) g`);
  // 5000 لحظة: نصفها للأصدقاء، وخُمس أصحابها ملفهم خاص
  await pool.query(`INSERT INTO map_posts(id, user_id, kind, caption, lat, lng, expires_at, audience) SELECT gen_random_uuid(), 'SG'||lpad(((g * 7) % 20000 + 1)::text, 7, '0'), 'text', 'حشو', 21.5, 39.1, now() + interval '1 day', CASE WHEN g % 2 = 0 THEN 'friends' ELSE 'all' END FROM generate_series(1, 5000) g`);
  await pool.query('ANALYZE users; ANALYZE profiles; ANALYZE contacts; ANALYZE map_posts');
  const n = async (sql) => Number((await pool.query(sql, [STRANGER])).rows[0].n);
  const want = await n(`SELECT count(*)::int AS n FROM map_posts p JOIN profiles pr ON pr.user_id = p.user_id WHERE p.user_id LIKE 'SG%' AND pr.is_public AND p.audience = 'all' AND $1::text IS NOT NULL`);
  const [ln, on] = [await n(`SELECT count(*)::int AS n FROM map_posts p WHERE p.user_id LIKE 'SG%' AND ${frag}`), await n(`SELECT count(*)::int AS n FROM map_posts p WHERE p.user_id LIKE 'SG%' AND ${one}`)];
  check(want > 1000 && ln === want && on === want, 'both forms agree on 5000 mixed moments (a stranger sees public authors\' everyone-moments only)', `${want} ${ln} ${on}`);
  const jit = Number((await pool.query('SHOW jit_above_cost')).rows[0].jit_above_cost);
  const cost = Number((await pool.query(`EXPLAIN (FORMAT JSON) SELECT count(*) FROM map_posts p WHERE ${frag}`, [STRANGER])).rows[0]['QUERY PLAN'][0].Plan['Total Cost']);
  check(cost < jit, 'list form stays under the JIT threshold over 5000 moments', `${cost} / ${jit}`);
  const pl = (await pool.query(`EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT p.id FROM map_posts p WHERE p.id = $2 AND ${one}`, [STRANGER, fo.id])).rows[0]['QUERY PLAN'][0].Plan;
  const nodes = (x) => [x, ...(x.Plans ?? []).flatMap(nodes)];
  check(pl['Actual Rows'] === 0 && !nodes(pl).some((x) => x['Node Type'] === 'Seq Scan' && ['users', 'profiles'].includes(x['Relation Name'])), 'point lookup with 20k profiles: right answer, key probes only');
  await pool.query("DELETE FROM map_posts WHERE user_id LIKE 'SG%'; DELETE FROM profiles WHERE user_id LIKE 'SG%'; DELETE FROM users WHERE id LIKE 'SG%'; ANALYZE users; ANALYZE profiles; ANALYZE map_posts");
}
await app.close();

// ---- احتياط map_posts.js المغلق: بلا قاعدة profile_ext.js لحظة «الأصدقاء» لصاحبتها وحدها (حتى الصديقة)، والعامة كما هي، وتنبيه
const dropRule = () => { for (const k of ['naslifeAuthorVisibleSql', 'naslifeIsPublic', 'naslifeFriendIds', 'naslifePrivacyStatus']) delete globalThis[k]; };
const bootWarned = async (opts) => {
  const warns = [], warn0 = console.warn;
  console.warn = (...a) => { warns.push(a.join(' ')); };
  try { return { a: await boot(opts), warns }; } finally { console.warn = warn0; }
};
const closedSweep = async (label) => {
  for (const [k, u] of Object.entries(VIEWERS)) {
    const ids = (await call('GET', '/mapposts?bbox=39.8,22.8,40.0,23.0', { user: u, expect: 200 })).j.map((p) => p.id);
    const fids = (await call('GET', '/feed?kind=moment&lat=22.9&lng=39.9', { user: u, expect: 200 })).j.items.map((i) => i.id);
    check(ids.includes(fo.id) === (k === 'author') && ids.includes(pub.id) && fids.includes(fo.id) === (k === 'author') && fids.includes(pub.id), `${label}: ${k} ${k === 'author' ? 'sees' : 'does not see'} the friends-only moment, sees the public one`);
    await call('GET', `/mapposts/${fo.id}`, { user: u, expect: k === 'author' ? 200 : 404 });
  }
};
{
  dropRule();
  const r = await bootWarned({ profileExt: false });
  app = r.a;
  check(r.warns.some((w) => w.includes('friends-only moments')), 'no profile_ext rule: warns at ready', JSON.stringify(r.warns));
  await closedSweep('fallback (no rule)');
  const h0 = (await call('GET', '/live/wait', { user: null, expect: 200 })).j.seq;
  const p3 = await post({ kind: 'text', caption: 'سرّ ثالث' });
  for (const [k, u] of Object.entries(VIEWERS)) {
    const evs = (await call('GET', `/live/wait?after=${h0}&timeout=0`, { user: u, expect: 200 })).j.events.filter((e) => e.kind === 'post').map((e) => e.data.id);
    check(evs.includes(p3.id) === (k === 'author'), `fallback live: ${k} ${k === 'author' ? 'gets' : 'does not get'} the new friends-only moment`);
  }
  await pool.query('DELETE FROM map_posts WHERE id=$1', [p3.id]);
  await app.close();
}
// قاعدة قديمة بلا علامة الجمهور (profile_ext.js أقدم من map_posts.js): لا تُمرَّر إليها فتعمل الاحتياط المغلق بدل فتح لحظات «الأصدقاء»
{
  dropRule();
  app = await boot();
  const full = globalThis.naslifeAuthorVisibleSql;
  globalThis.naslifeAuthorVisibleSql = (a, v, o = {}) => full(a, v, { single: o.single });
  await closedSweep('old rule without audience support');
  globalThis.naslifeAuthorVisibleSql = full;
  await app.close();
}

// ---- بلا عمود خصوصية في النواة: كل ملف عام، ويبقى الجمهور وحده يفرّق (والأصدقاء معروفون من جهات الاتصال)
await pool.query('ALTER TABLE profiles DROP COLUMN is_public');
{
  dropRule();
  app = await boot();
  check(globalThis.naslifePrivacyStatus?.privacy === false && globalThis.naslifePrivacyStatus?.friends === true, 'no privacy column, contacts known');
  const s = {};
  for (const [k, u] of Object.entries(VIEWERS)) { const ids = (await call('GET', '/mapposts?bbox=39.8,22.8,40.0,23.0', { user: u, expect: 200 })).j.map((p) => p.id); s[k] = { fo: ids.includes(fo.id), pub: ids.includes(pub.id) }; }
  expectSeen('no privacy column', s);
  await call('POST', `/mapposts/${fo.id}/like`, { user: STRANGER, expect: 404 });
  await call('GET', `/moments/${fo.id}/reactions`, { user: FRIEND, expect: 200 });
  const h0 = (await call('GET', '/live/wait', { user: null, expect: 200 })).j.seq;
  const p4 = await post({ kind: 'text', caption: 'للأصدقاء بلا عمود' });
  for (const [k, u] of Object.entries(VIEWERS)) {
    const evs = (await call('GET', `/live/wait?after=${h0}&timeout=0`, { user: u, expect: 200 })).j.events.filter((e) => e.kind === 'post').map((e) => e.data.id);
    check(evs.includes(p4.id) === (k === 'author' || k === 'friend'), `no privacy column live: ${k}`);
  }
  await app.close();
}
// بلا عمود خصوصية وبلا profile_ext.js: لحظات «الجميع» للجميع كما كانت، و«الأصدقاء» لصاحبها
{
  dropRule();
  const r = await bootWarned({ profileExt: false });
  app = r.a;
  check(r.warns.length === 1 && !r.warns[0].includes('private profiles'), 'no privacy column, no rule: one warning about friends-only moments', JSON.stringify(r.warns));
  await closedSweep('no privacy column, no rule');
  await app.close();
}
// الجدول يبقى بلا عمود خصوصية كما تتركه harness_private_moments.mjs: حزم أخرى تُقلع map_posts.js وحدها على القاعدة المشتركة

await pool.end();
console.log(fails ? `${fails} FAILED` : 'ALL AUDIENCE TESTS PASSED');
process.exit(fails ? 1 : 0);
