// لحظات الملف الخاص (القاعدة الواحدة momentVisibleSql في map_posts.js فوق naslifeAuthorVisibleSql من profile_ext.js):
// صاحب ملف «غير عام» لا يرى لحظاته إلا هو وأصدقاؤه (من أضافهم هو إلى جهات اتصاله، تعريف «من يراسلني»). أربعة مشاهدين: الصديق،
// الغريب، من أضاف صاحب الملف من طرفه فقط (ليس صديقاً)، والضيف؛ على كل مسار تتسرب منه لحظة: GET /mapposts و/mapposts/feed
// و/mapposts/:id و/mapposts/trending والإعجاب، /row و/feed (row.js)، البث الحي /live/wait (live.js يصفّي لكل مستمع)،
// رابط المشاركة /m/:id (share.js)، التفاعلات (moment_extras.js)، والمحفوظات (wishlist.js) لمن لم يعد صديقاً. ثم الملف نفسه بالتعريف
// نفسه، والشكلان (القوائم وقراءة الصف الواحد) بـEXPLAIN على 30 ألف ملف، واحتياط map_posts.js المغلق بلا قاعدة profile_ext.js، ثم العمود
// في users بدل جدول الملف، وأخيراً بلا عمود خصوصية = الجميع عامّ كما كان، والقاعدة تُنشر قبل جداول profile_ext.js.
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
await pool.query('DROP TABLE IF EXISTS saved_searches CASCADE');
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
// profileExt: false = بلا قاعدة profile_ext.js (لم تُسجَّل أو تعثّرت قبل نشرها) فيعمل احتياط map_posts.js
const boot = async (full, { profileExt = true } = {}) => {
  const a = Fastify();
  a.register((await import('../map_posts.js')).default, { pool, auth });
  if (full) {
    a.register((await import('../moment_extras.js')).default, { pool, auth, sweepMs: 0 });
    a.register((await import('../wishlist.js')).default, { pool, auth, sweepMs: 0 });
    a.register((await import('../share.js')).default, { pool, auth, webappDir: dir + 'webapp' });
    a.register((await import('../chat_cards.js')).default, { pool, auth });
    a.register((await import('../saved_search.js')).default, { pool, auth, sweepMs: 0 });
  }
  if (profileExt) a.register((await import('../profile_ext.js')).default, { pool, auth });
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
// بطاقة #post/<id> في المحادثة (chat_cards.js): الغريب لا يأخذ عنوانها ولا صاحبها، والصديق يأخذها
{
  const ref = encodeURIComponent(`#post/${priv.id}`);
  const cs = (await call('GET', `/chat/cards?refs=${ref}`, { user: STRANGER, expect: 200 })).j;
  check(cs.refs[`#post/${priv.id}`] === null, 'chat card #post: a stranger gets no card for the private moment', JSON.stringify(cs));
  const cf = (await call('GET', `/chat/cards?refs=${ref}`, { user: FRIEND, expect: 200 })).j;
  check(cf.refs[`#post/${priv.id}`]?.id === priv.id, 'chat card #post: the friend gets the card', JSON.stringify(cf).slice(0, 200));
  const cp = (await call('GET', `/chat/cards?refs=${encodeURIComponent(`#post/${pub.id}`)}`, { user: STRANGER, expect: 200 })).j;
  check(cp.refs[`#post/${pub.id}`]?.id === pub.id, 'chat card #post: a public moment still resolves for anyone');
}
// تنبيه البحث المحفوظ (saved_search.js): لا يطابق لحظة صاحب الملف الخاص لغريب، ويطابقها للصديق
{
  const runFor = async (user) => {
    const s = (await call('POST', '/searches/saved', { body: { q: 'بيت' }, user, expect: 200 })).j;
    return (await call('POST', `/searches/saved/${s.id}/run`, { user, expect: 200 })).j.items.map((i) => i.id);
  };
  check(!(await runFor(STRANGER)).includes(priv.id), 'saved search: a stranger is not matched with the private moment');
  check((await runFor(FRIEND)).includes(priv.id), 'saved search: the friend is matched with it');
}

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

// ---- الملف نفسه بالتعريف نفسه: من أضافها من طرفه فقط يرى الملف المختصر (لا نبذة ولا عدّ للحظات لا يفتحها)، والصديقة ترى عدداً
// يساوي ما تفتحه في «لحظاته»
{
  const prof = async (u) => (await call('GET', `/profiles/${AUTHOR}/v2`, { user: u, expect: 200 })).j;
  const ow = await prof(ONEWAY);
  check(ow.flags.isPrivate === true && ow.flags.isFriend === false && ow.bio === undefined && JSON.stringify(ow.stats) === '{}', 'profile: a one-way contact gets the limited private profile, like moments', JSON.stringify(ow));
  for (const u of [STRANGER, null]) check(JSON.stringify((await prof(u)).stats) === '{}', `profile: ${u ?? 'guest'} gets no stats`);
  const fp = await prof(FRIEND);
  const fFeed = (await call('GET', `/mapposts/feed?authors=${AUTHOR}`, { user: FRIEND, expect: 200 })).j.items.length;
  check(fp.flags.isFriend === true && fFeed >= 1 && fp.stats.posts === fFeed, 'profile: the friend sees the full profile and a posts count equal to the moments she can open', `${fp.stats?.posts} vs ${fFeed}`);
}

// ---- الكفاءة بشكلين للجزء نفسه. القوائم: استعلامات فرعية غير مرتبطة بالصف (تذكر p.user_id وحده) يجزّئها Postgres مرة لكل استعلام،
// وكلفتها المقدّرة تبقى صغيرة مع آلاف اللحظات (الشكل المرتبط يُقدَّر بفحص لكل صف فتكبر كلفته مع عدد اللحظات حتى تتجاوز عتبة JIT). صف واحد ({ single: true }، في
// /mapposts/:id والإعجاب والتفاعلات و«محفوظاتي» وبطاقة المحادثة ورابط المشاركة وعدّ منشورات الملف): فحوص مفاتيح مرتبطة بالصف فلا يُمسح
// جدول الملفات كله في كل قراءة
const frag = globalThis.naslifeMomentVisibleSql('p', '$1::text');
check(!/\bp\.(?!user_id)/.test(frag.replace(/\bp\.user_id\b/g, '')) && (frag.match(/p\.user_id/g) || []).length === 3, 'list fragment references the row only through p.user_id (uncorrelated subqueries)', frag);
const plan = (await pool.query(`EXPLAIN SELECT p.id FROM map_posts p WHERE ${frag}`, [STRANGER])).rows.map((r) => r['QUERY PLAN']).join('\n');
check((plan.match(/hashed SubPlan/g) || []).length === 2, 'list: the planner hashes the private-id and friend sets once per query', plan.replace(/\n/g, ' | ').slice(0, 300));
const one = globalThis.naslifeMomentVisibleSql('p', '$1::text', { single: true });
check(one.includes('EXISTS (SELECT 1 FROM "profiles" vis_p WHERE vis_p."user_id" = p.user_id') && one.includes('EXISTS (SELECT 1 FROM "contacts" vis_c WHERE vis_c."user_id" = p.user_id AND vis_c."contact_id" = $1::text)') && !one.includes('NOT IN'),
  'single-row fragment probes the keys of the row\'s author (profile key, contact pair)', one);
// 30 ألف مستخدم إضافي بملفاتهم (خُمسهم خاص) و5000 لحظة لهم
await pool.query(`INSERT INTO users(id, nickname) SELECT 'SF'||lpad(g::text, 7, '0'), 'filler'||g FROM generate_series(1, 30000) g`);
await pool.query(`INSERT INTO profiles(user_id, is_public) SELECT 'SF'||lpad(g::text, 7, '0'), g % 5 <> 0 FROM generate_series(1, 30000) g`);
await pool.query(`INSERT INTO map_posts(id, user_id, kind, caption, lat, lng, expires_at) SELECT gen_random_uuid(), 'SF'||lpad(((g * 7) % 30000 + 1)::text, 7, '0'), 'text', 'حشو', 21.5, 39.1, now() + interval '1 day' FROM generate_series(1, 5000) g`);
await pool.query('ANALYZE users; ANALYZE profiles; ANALYZE contacts; ANALYZE map_posts');
{
  // الشكلان يتفقان على 5000 لحظة مختلطة: الغريب يرى لحظات أصحاب الملفات العامة وحدها
  const n = async (sql) => Number((await pool.query(sql, [STRANGER])).rows[0].n);
  const want = await n(`SELECT count(*)::int AS n FROM map_posts p JOIN profiles pr ON pr.user_id = p.user_id WHERE p.user_id LIKE 'SF%' AND pr.is_public AND $1::text IS NOT NULL`);
  const [ln, on] = [await n(`SELECT count(*)::int AS n FROM map_posts p WHERE p.user_id LIKE 'SF%' AND ${frag}`), await n(`SELECT count(*)::int AS n FROM map_posts p WHERE p.user_id LIKE 'SF%' AND ${one}`)];
  check(want === 4000 && ln === want && on === want, 'both forms agree on 5000 mixed moments (a stranger sees the public authors\' only)', `${want} ${ln} ${on}`);
  // القائمة بلا حد يقصّه الفهرس (كالرائج والبث بالمسافة): الكلفة المقدّرة تحت عتبة JIT فلا يُترجم الاستعلام عند كل طلب
  const jit = Number((await pool.query('SHOW jit_above_cost')).rows[0].jit_above_cost);
  const cost = async (f) => (await pool.query(`EXPLAIN (FORMAT JSON) SELECT count(*) FROM map_posts p WHERE ${f}`, [STRANGER])).rows[0]['QUERY PLAN'][0].Plan['Total Cost'];
  const [cl, co] = [await cost(frag), await cost(one)];
  check(cl < jit && cl * 5 < co, 'list form keeps the estimated cost of a 5000-moment scan small and under the JIT threshold; the correlated form is costed per row', `list ${cl} / single ${co} / jit_above_cost ${jit}`);
}
const nodes = (n) => [n, ...(n.Plans ?? []).flatMap(nodes)];
const point = async (f, viewer, id) => {
  const pl = (await pool.query(`EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT p.id FROM map_posts p WHERE p.id = $2 AND ${f}`, [viewer, id])).rows[0]['QUERY PLAN'][0].Plan;
  const scans = nodes(pl).filter((x) => x['Node Type'] === 'Seq Scan' && ['users', 'profiles'].includes(x['Relation Name'])).length;
  return { rows: pl['Actual Rows'], blocks: pl['Shared Hit Blocks'] + pl['Shared Read Blocks'], userTableScans: scans };
};
for (const [label, viewer, id, rows] of [['stranger / private', STRANGER, priv.id, 0], ['friend / private', FRIEND, priv.id, 1], ['guest / public', null, pub.id, 1]]) {
  const r = await point(one, viewer, id);
  check(r.rows === rows && r.blocks < 40 && r.userTableScans === 0, `point lookup (${label}) with 30k extra profiles: right answer, key probes only`, JSON.stringify(r));
}
{
  // الفرق الذي جاء من أجله الشكل الثاني: الشكل الأول لصف واحد يبني مجموعة الملفات الخاصة كلها
  const [o, l] = [await point(one, STRANGER, priv.id), await point(frag, STRANGER, priv.id)];
  check(l.rows === 0 && l.userTableScans > 0 && o.blocks * 3 < l.blocks, 'the list form on a single row scans the profiles table; the single form does not', `single ${o.blocks} vs list ${l.blocks} blocks`);
}
// المسارات نفسها ما زالت صحيحة مع الحشو (الإعجاب ورابط المشاركة وبطاقة المحادثة والتفاعلات تمر بالشكل الثاني)
await call('GET', `/mapposts/${priv.id}`, { user: STRANGER, expect: 404 });
await call('GET', `/mapposts/${priv.id}`, { user: FRIEND, expect: 200 });
await call('GET', `/moments/${priv.id}/reactions`, { user: STRANGER, expect: 404 });
check(meta(await getHtml(`/m/${priv.id}`), 'og:title') === 'لحظة على ناس لايف', 'share /m/ still generic for the private moment');
await pool.query("DELETE FROM map_posts WHERE user_id LIKE 'SF%'; DELETE FROM profiles WHERE user_id LIKE 'SF%'; DELETE FROM users WHERE id LIKE 'SF%'; ANALYZE users; ANALYZE profiles; ANALYZE map_posts");

await app.close();

// ---- احتياط map_posts.js المغلق: عمود الخصوصية موجود وقاعدة profile_ext.js غائبة (لم تُسجَّل، أو تعثّرت قبل نشرها) → لحظة الملف الخاص
// لصاحبها وحده لا «الجميع عامّ»: الغريب والضيف ومن أضافها من طرفه لا يرونها، والصديقة أيضاً حتى تعود القاعدة (إغلاق عند الشك)،
// والعامة كما هي، وتنبيه في السجل. الإضافات الأخرى تمر بجزء map_posts.js فترث الاحتياط نفسه
const dropRule = () => { for (const k of ['naslifeAuthorVisibleSql', 'naslifeIsPublic', 'naslifeFriendIds', 'naslifePrivacyStatus']) delete globalThis[k]; };
const bootWarned = async (full, opts) => {
  const warns = [], warn0 = console.warn;
  console.warn = (...a) => { warns.push(a.join(' ')); };
  try { return { a: await boot(full, opts), warns }; } finally { console.warn = warn0; }
};
const closedSweep = async (label) => {
  const s = {};
  for (const [k, u] of Object.entries(VIEWERS)) {
    const m = (await call('GET', '/mapposts?bbox=39.8,22.8,40.0,23.0', { user: u, expect: 200 })).j.map((p) => p.id);
    s[k] = { priv: m.includes(priv.id), pub: m.includes(pub.id) };
    await call('GET', `/mapposts/${priv.id}`, { user: u, expect: k === 'author' ? 200 : 404 });
  }
  for (const [k, v] of Object.entries(s)) check(v.priv === (k === 'author') && v.pub === true, `${label}: ${k} ${k === 'author' ? 'sees' : 'does not see'} the private moment, sees the public one`, JSON.stringify(v));
};
{
  dropRule();
  const r = await bootWarned(true, { profileExt: false });
  app = r.a;
  check(typeof globalThis.naslifeAuthorVisibleSql !== 'function' && r.warns.some((w) => w.includes('naslifeAuthorVisibleSql')), 'no profile_ext rule: map_posts serves on its closed fallback and warns at ready', JSON.stringify(r.warns));
  const lf = globalThis.naslifeMomentVisibleSql('p', '$1::text'), sf = globalThis.naslifeMomentVisibleSql('p', '$1::text', { single: true });
  check(lf.includes('NOT IN (SELECT vis_f."user_id" FROM "profiles" vis_f') && sf.includes('EXISTS (SELECT 1 FROM "profiles" vis_f WHERE vis_f."user_id" = p.user_id'), 'fallback has the same two forms (list set, single-row probe)', `${lf} || ${sf}`);
  await closedSweep('fallback GET /mapposts + /mapposts/:id');
  for (const [k, u] of Object.entries(VIEWERS)) {
    const ids = (await call('GET', '/feed?kind=moment&lat=22.9&lng=39.9', { user: u, expect: 200 })).j.items.map((i) => i.id);
    check(ids.includes(priv.id) === (k === 'author') && ids.includes(pub.id), `fallback /feed (row.js): ${k}`, JSON.stringify(ids));
  }
  await call('POST', `/mapposts/${priv.id}/like`, { user: FRIEND, expect: 404 });
  await call('GET', `/moments/${priv.id}/reactions`, { user: STRANGER, expect: 404 });
  await call('POST', '/wishlist', { body: { kind: 'post', refId: priv.id }, user: STRANGER, expect: 404 });
  check((await call('GET', `/chat/cards?refs=${encodeURIComponent(`#post/${priv.id}`)}`, { user: STRANGER, expect: 200 })).j.refs[`#post/${priv.id}`] === null, 'fallback chat card #post: none for a stranger');
  check(meta(await getHtml(`/m/${priv.id}`), 'og:title') === 'لحظة على ناس لايف' && meta(await getHtml(`/m/${pub.id}`), 'og:title') === 'صباح الخير', 'fallback share /m/: private generic, public keeps its preview');
  // البث الحي: لحظة خاصة جديدة لا تصل إلا صاحبها
  const h0 = (await call('GET', '/live/wait', { user: null, expect: 200 })).j.seq;
  const p2 = (await call('POST', '/mapposts', { body: { kind: 'text', bg: '#0A6E78', caption: 'سرّ آخر', lat: 22.902, lng: 39.902 }, user: AUTHOR, expect: 200 })).j;
  for (const [k, u] of Object.entries(VIEWERS)) {
    const evs = (await call('GET', `/live/wait?after=${h0}&timeout=0`, { user: u, expect: 200 })).j.events.filter((e) => e.kind === 'post').map((e) => e.data.id);
    check(evs.includes(p2.id) === (k === 'author'), `fallback live: ${k} ${k === 'author' ? 'gets' : 'does not get'} the new private moment`, JSON.stringify(evs));
  }
  await pool.query('DELETE FROM map_posts WHERE id=$1', [p2.id]);
  await app.close();
}

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
// الاحتياط يكتشف العمود في users أيضاً
dropRule();
({ a: app } = await bootWarned(false, { profileExt: false }));
await closedSweep('fallback on users.is_public');
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

// بلا عمود خصوصية وبلا profile_ext.js أيضاً: الجميع عامّ كما كان (الاحتياط لا يغلق ما لا خصوصية له) ولا تنبيه
{
  dropRule();
  const r = await bootWarned(true, { profileExt: false });
  app = r.a;
  check(r.warns.length === 0, 'no privacy column, no profile_ext: no warning', JSON.stringify(r.warns));
  ids = (await call('GET', '/mapposts', { user: null, expect: 200 })).j.map((p) => p.id);
  check(ids.includes(priv.id) && ids.includes(pub.id), 'no privacy column, no profile_ext → guests see every moment');
  await call('GET', `/mapposts/${priv.id}`, { user: STRANGER, expect: 200 });
  await call('POST', `/moments/${priv.id}/react`, { body: { emoji: '😍' }, user: STRANGER, expect: 200 });
  await app.close();
}

// ---- القاعدة تُنشر قبل جداول profile_ext.js ومساراتها: تعثّر بعدها (هنا إنشاء جداول الإضافة) يُفشل الإقلاع ويتراجع النشر التلقائي،
// لكن ما يبقى في العملية لا يرجع إلى الاحتياط: القاعدة كاملة بالأصدقاء منشورة
await pool.query('ALTER TABLE profiles ADD COLUMN is_public BOOLEAN DEFAULT true');
await pool.query('UPDATE profiles SET is_public=false WHERE user_id=$1', [AUTHOR]);
{
  dropRule();
  const flaky = { query: (sql, params) => (/CREATE TABLE IF NOT EXISTS profile_ext/.test(String(sql)) ? Promise.reject(new Error('db hiccup')) : pool.query(sql, params)) };
  const a = Fastify();
  a.register((await import('../profile_ext.js')).default, { pool: flaky, auth });
  let err = null; try { await a.ready(); } catch (e) { err = e; }
  check(err?.message === 'db hiccup', 'the injected failure happened after discovery (boot fails)', String(err?.message));
  const f = globalThis.naslifeAuthorVisibleSql;
  check(typeof f === 'function' && globalThis.naslifePrivacyStatus?.privacy === true, 'the rule was published before the failing step');
  if (typeof f === 'function') {
    const sees = async (viewer) => (await pool.query(`SELECT ${f('$1::text', '$2::text', { single: true })} AS v, ${f('$1::text', '$2::text')} AS l`, [AUTHOR, viewer])).rows[0];
    const [fr, st] = [await sees(FRIEND), await sees(STRANGER)];
    check(fr.v === true && fr.l === true && st.v === false && st.l === false, 'the published rule is the full one (the friend sees, the stranger does not), in both forms', JSON.stringify({ fr, st }));
  }
  await a.close().catch(() => {});
}
// لا نترك ملفاً خاصاً في القاعدة المشتركة لحزم أخرى تُقلع map_posts.js وحدها (فيعمل احتياطها)
await pool.query('ALTER TABLE profiles DROP COLUMN is_public');

await pool.end();
console.log(fails ? `${fails} FAILED` : 'ALL PRIVATE MOMENTS TESTS PASSED');
process.exit(fails ? 1 : 0);
