// «أتابعهم» (7 نوفمبر 2026، تقرير النواقص القسم 2 البند 1): GET /feed?scope=following في row.js (لحظات من أتابعهم ومن أضفتهم وفعالياتهم
// وإعلاناتهم، وعروض الدوائر التي انضممت إليها ووظائفها و«هنا اليوم»، بقاعدة الرؤية الواحدة والجمهور والحظر في الاتجاهين، بالمؤشر نفسه
// وبلا نطاق مسافة، وصفحة فارغة للضيف وعدّاد الأشخاص والدوائر لنص الفراغ)، وGET /me/following/ids، وإشعار المتابِعين بلحظة جديدة
// (profile_ext.js عبر خطّاف map_posts.js: من يرى اللحظة فقط، لحظة «الأصدقاء» لأصدقاء الناشر، الملف الخاص، الحظر، «إشعارات من أتابعهم»،
// وحد مرة كل 6 ساعات لكل ناشر ومتابِع لا تستهلكه لحظة لا يراها)، وقائمتا «متابِعون» و«يتابع» (صفحات بمؤشر يصمد للتعادل، isFollowing،
// الملف الخاص لصاحبه ومن أضافهم، طرفا الحظر، ومن حظرهم المشاهد لا يظهرون).
import Fastify from 'fastify';
import pg from 'pg';
import crypto from 'node:crypto';
import { KINDS, scoped } from '../row.js';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0';
let fails = 0;
const check = (c, l, extra = '') => { if (!c) fails++; console.log((c ? 'OK  ' : 'FAIL') + ' ' + l + (extra ? ' ' + extra : '')); };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const NOW = Date.now(), H = 3600000;
const hrs = (n) => new Date(NOW + n * H).toISOString();
const uid = () => crypto.randomUUID();

// ---- وحدة خالصة: شرط النطاق
check(JSON.stringify(scoped({}, 'p.user_id', 'people', [1, 2])) === JSON.stringify(['', [1, 2]]), 'scoped: without the following scope there is no condition and no extra parameter');
check(scoped({ following: { people: [], circles: ['x'] } }, 'p.user_id', 'people', [1]) === null, 'scoped: an empty set means the kind contributes nothing (null, no query)');
{ const s = scoped({ following: { people: ['SA0000001'], circles: [] } }, 'p.user_id', 'people', [1, 2, 3]); check(s && s[0] === ' AND p.user_id = ANY($4::text[])' && s[1].length === 4 && s[1][3][0] === 'SA0000001', 'scoped: appends the set as the next parameter', JSON.stringify(s)); }

const ME = 'SA0000101', FOL = 'SA0000102', FRI = 'SA0000103', PRIV = 'SA0000104', PRIV2 = 'SA0000105', BLK = 'SA0000106', STR = 'SA0000107', CIRC = 'SA0000108', ORPHAN = 'SA0000109';
const AUTH = 'SA0000110', PAUTH = 'SA0000111', OPT = 'SA0000112', BLKF = 'SA0000113', BLKF2 = 'SA0000114', FRN = 'SA0000115';
const NAMES = { [ME]: 'amr', [FOL]: 'huda', [FRI]: 'sara', [PRIV]: 'mona', [PRIV2]: 'noor', [BLK]: 'khalid', [STR]: 'fahad', [CIRC]: 'reem', [ORPHAN]: 'zaid', [AUTH]: 'layla', [PAUTH]: 'dana', [OPT]: 'omar', [BLKF]: 'saad', [BLKF2]: 'hind', [FRN]: 'yara' };

const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
// قاعدة مشتركة محتملة: الجداول التي تبذرها الحزمة تُحذف وتُنشأ من جديد، والدوائر بمعرّفات flw-* وحدها
for (const sql of ['DROP TABLE IF EXISTS profile_ext, user_follows, profile_views, profile_events, follow_notify_log CASCADE',
  'DROP TABLE IF EXISTS users, profiles, contacts, map_post_likes, map_post_views, map_post_events, map_posts, biz_offers, ticket_tiers, tickets, events, jobs, market_listings CASCADE',
  "DELETE FROM biz WHERE id LIKE 'flw-%'", "DELETE FROM biz_follows WHERE biz_id LIKE 'flw-%'", 'DELETE FROM app_notifications']) { try { await pool.query(sql); } catch { /* أول تشغيل */ } }
await pool.query(`CREATE TABLE users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now());
  CREATE TABLE profiles (user_id TEXT PRIMARY KEY, bio TEXT NOT NULL DEFAULT '', skills TEXT[] DEFAULT '{}', is_public BOOLEAN DEFAULT true);
  CREATE TABLE contacts (user_id TEXT NOT NULL, contact_id TEXT NOT NULL);`);
for (const [id, nick] of Object.entries(NAMES)) await pool.query('INSERT INTO users(id, nickname) VALUES($1,$2)', [id, nick]);
// منى ونور ودانة ملفاتهن خاصة؛ البقية عامة
await pool.query(`INSERT INTO profiles(user_id, is_public) SELECT id, id NOT IN ('${PRIV}','${PRIV2}','${PAUTH}') FROM users`);
// أضفتُ سارة (فهي في «أتابعهم» بلا متابعة) وأضافتني (أرى لحظات «الأصدقاء» عندها)؛ منى أضافتني (أرى لحظات ملفها الخاص)؛ نور لم تضفني.
// ليلى أضافت يارا (صديقتها)، ودانة (ملف خاص) أضافتني
await pool.query(`INSERT INTO contacts(user_id, contact_id) VALUES ('${ME}','${FRI}'), ('${FRI}','${ME}'), ('${PRIV}','${ME}'), ('${AUTH}','${FRN}'), ('${PAUTH}','${ME}')`);
// الحظر في الاتجاهين كما يعيده safety.js: أنا حظرت خالداً، وليلى حظرت سعداً، وهند حظرت ليلى
const BLOCKS = [[ME, BLK], [AUTH, BLKF], [BLKF2, AUTH]];
globalThis.naslifeBlockedIds = async (u) => BLOCKS.flatMap(([a, b]) => (a === u ? [b] : b === u ? [a] : []));
globalThis.naslifeIsBlocked = async (a, b) => (await globalThis.naslifeBlockedIds(a)).includes(b);
globalThis.naslifeHasBlocked = async (a, b) => BLOCKS.some(([x, y]) => x === a && y === b);

const auth = async (req) => req.headers['x-user'] || null;
const dir = new URL('.', import.meta.url).pathname;
const app = Fastify();
app.register((await import('../notify.js')).default, { pool, auth, pollMs: 0, opsDir: dir + 'ops' });
app.register((await import('../commerce.js')).default, { pool, auth });
app.register((await import('../business.js')).default, { pool, auth });
app.register((await import('../offers.js')).default, { pool, auth });
app.register((await import('../map_posts.js')).default, { pool, auth });
app.register((await import('../jobs.js')).default, { pool, auth, sweepMs: 0 });
app.register((await import('../profile_ext.js')).default, { pool, auth });
app.register((await import('../row.js')).default, { pool, auth });
await app.ready(); await sleep(300);
const call = async (method, url, { body = {}, user = ME, expect } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json', host: 'naslife.app', 'x-forwarded-proto': 'https' }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url} [${user ?? 'guest'}] -> ${r.statusCode}`, r.statusCode === expect ? '' : String(typeof j === 'string' ? j : JSON.stringify(j)).slice(0, 200));
  return { code: r.statusCode, j };
};
const ids = (r) => r.items.map((i) => i.id);
const same = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);
const follow = (a, b, at = null) => pool.query('INSERT INTO user_follows(follower_id, user_id, created_at) VALUES($1,$2,COALESCE($3::timestamptz, now())) ON CONFLICT DO NOTHING', [a, b, at]);

// ---- البذر: كل شيء في جدة؛ أزمنة النشر متباعدة حتى يكون الترتيب قاطعاً
const JED = { lat: 21.54, lng: 39.17 }, DMM = { lat: 26.43, lng: 50.10 };
for (const f of [FOL, PRIV, PRIV2, BLK]) await follow(ME, f);
const biz = async (id, nameAr) => pool.query("INSERT INTO biz(id,name,name_ar,category,lat,lng,address,active) VALUES($1,$2,$3,'cafe',$4,$5,'الروضة',true)", [id, id, nameAr, JED.lat, JED.lng]);
await biz('flw-joined', 'مقهى انضممت إليه'); await biz('flw-other', 'مقهى آخر');
await pool.query("INSERT INTO biz_follows(biz_id, user_id) VALUES('flw-joined',$1),('flw-joined',$2)", [ME, CIRC]);
await pool.query('UPDATE biz SET here=$2::jsonb WHERE id=$1', ['flw-joined', JSON.stringify({ lat: JED.lat, lng: JED.lng, until: hrs(5), setAt: hrs(-2.5) })]);
await pool.query('UPDATE biz SET here=$2::jsonb WHERE id=$1', ['flw-other', JSON.stringify({ lat: JED.lat, lng: JED.lng, until: hrs(5), setAt: hrs(-2.6) })]);
const post = async (user, { audience = 'all', created = -1, caption = 'لحظة', status = 'active' } = {}) => { const id = uid(); await pool.query("INSERT INTO map_posts(id,user_id,kind,caption,lat,lng,status,expires_at,created_at,audience) VALUES($1,$2,'text',$3,$4,$5,$6,$7,$8,$9)", [id, user, caption, JED.lat, JED.lng, status, hrs(20), hrs(created), audience]); return id; };
const M_FOL = await post(FOL, { created: -0.5, caption: 'هدى للجميع' });
const M_FOL_F = await post(FOL, { created: -0.6, audience: 'friends', caption: 'هدى للأصدقاء' });   // هدى لم تضفني: لا أراها
const M_FRI = await post(FRI, { created: -0.7, caption: 'سارة للجميع' });
const M_FRI_F = await post(FRI, { created: -0.8, audience: 'friends', caption: 'سارة للأصدقاء' }); // سارة أضافتني: أراها
const M_PRIV = await post(PRIV, { created: -0.9, caption: 'منى ملف خاص' });                      // منى أضافتني
const M_PRIV2 = await post(PRIV2, { created: -1.0, caption: 'نور ملف خاص' });                    // نور لم تضفني
const M_BLK = await post(BLK, { created: -1.1, caption: 'خالد المحظور' });
const M_STR = await post(STR, { created: -1.2, caption: 'غريب لا أتابعه' });
const M_ME = await post(ME, { created: -1.3, caption: 'لحظتي' });
const M_OLD = await post(FOL, { created: -30, status: 'hidden' });
const offer = async (bizId, title, startsH) => { const id = uid(); await pool.query("INSERT INTO biz_offers(id,biz_id,kind,title,value,members_only,starts_at,ends_at,active,created_at) VALUES($1,$2,'deal',$3,'{\"type\":\"percent\",\"amount\":15}',false,$4,$5,true,$4)", [id, bizId, title, hrs(startsH), hrs(48)]); return id; };
const O_J = await offer('flw-joined', 'عرض دائرتي', -1.5), O_X = await offer('flw-other', 'عرض دائرة أخرى', -1.4);
const job = async (bizId, title, pubH) => { const id = uid(); await pool.query("INSERT INTO jobs(id,biz_id,created_by,title,type,salary_visible,deadline,status,public,published_at,city,district) VALUES($1,$2,$3,$4,'full',false,$5,'open',true,$6,'جدة','')", [id, bizId, ME, title, hrs(240), hrs(pubH)]); return id; };
const J_J = await job('flw-joined', 'باريستا دائرتي', -1.7), J_X = await job('flw-other', 'باريستا دائرة أخرى', -1.6);
const event = async (host, title, createdH) => { const id = uid(); await pool.query('INSERT INTO events(id,host_id,title,starts_at,place_name,lat,lng,cancelled,hidden,created_at) VALUES($1,$2,$3,$4,$5,$6,$7,false,false,$8)', [id, host, title, hrs(48), 'الكورنيش', JED.lat, JED.lng, hrs(createdH)]); return id; };
const E_FOL = await event(FOL, 'فعالية هدى', -1.9), E_STR = await event(STR, 'فعالية غريب', -1.8), E_BLK = await event(BLK, 'فعالية خالد', -1.85);
const listing = async (seller, title, createdH) => { const id = uid(); await pool.query(`INSERT INTO market_listings(id,seller_id,kind,category,title,price,images,place_name,lat,lng,status,created_at) VALUES($1,$2,'product','sports',$3,10000,'[]','الروضة',$4,$5,'active',$6)`, [id, seller, title, JED.lat, JED.lng, hrs(createdH)]); return id; };
const L_FOL = await listing(FOL, 'دراجة هدى', -2.1), L_STR = await listing(STR, 'دراجة غريب', -2.0);
const C_J = 'flw-joined';
// المتوقع لي بالأحدث نشراً أولاً
const MINE = [M_FOL, M_FRI, M_FRI_F, M_PRIV, O_J, J_J, E_FOL, L_FOL, C_J];
const NEVER = [M_FOL_F, M_PRIV2, M_BLK, M_STR, M_ME, M_OLD, O_X, J_X, E_STR, E_BLK, L_STR, 'flw-other'];

// ---- /feed?scope=following
let r = (await call('GET', '/feed?scope=following', { expect: 200 })).j;
check(same(ids(r), MINE), 'following: moments of people I follow and friends I added, their events and listings, and my circles\' offers, jobs and here-today, newest first', r.items.map((i) => i.kind[0] + ':' + (i.title || '').slice(0, 14)).join(' | '));
check(NEVER.every((id) => !ids(r).includes(id)), 'not: friends-only of someone who did not add me, a private profile that did not add me, a blocked author, a stranger, my own moment, a hidden moment, other circles');
check(r.scope === 'following' && r.following?.people === 4 && r.following?.circles === 1, 'scope echoed with counts: 4 people (followed + contact, blocked dropped), 1 circle', JSON.stringify(r.following));
check(r.items.every((i) => KINDS.includes(i.kind) && typeof i.feedAt === 'string'), 'cards keep the /feed contract (kind, feedAt)');
check(r.items.find((i) => i.id === M_FRI_F)?.payload?.audience === 'friends', 'a friends-only moment I can see carries its audience in the payload');
// المؤشر: صفحات بحجم 1 و2 و4 تعطي القائمة نفسها بلا تكرار ولا فجوة، والمؤشر بصيغة feedAt~k~id
for (const limit of [1, 2, 4]) {
  const out = []; let c = null, pages = 0, okFmt = true;
  do { const pg1 = (await call('GET', `/feed?scope=following&limit=${limit}${c ? '&before=' + encodeURIComponent(c) : ''}`)).j; out.push(...ids(pg1)); c = pg1.next; if (c && !/^\d{4}-\d{2}-\d{2}T[\d:.]+Z~\d~.+$/.test(c)) okFmt = false; pages++; } while (c && pages < 50);
  check(same(out, MINE) && okFmt, `cursor walk with limit ${limit}: same order, no repeats or gaps (${pages} pages)`);
}
r = (await call('GET', '/feed?scope=following&kind=moment', { expect: 200 })).j;
check(same(ids(r), [M_FOL, M_FRI, M_FRI_F, M_PRIV]), 'kind=moment narrows the scope to moments');
r = (await call('GET', '/feed?scope=following&kind=offer', { expect: 200 })).j;
check(same(ids(r), [O_J]), 'kind=offer: only offers of the circles I joined');
// بلا نطاق مسافة: من الدمام تظهر لحظات جدة كلها بمسافتها
r = (await call('GET', `/feed?scope=following&lat=${DMM.lat}&lng=${DMM.lng}&radiusKm=5`, { expect: 200 })).j;
check(same(ids(r), MINE) && r.items.every((i) => typeof i.distanceKm === 'number' && i.distanceKm > 900), 'no radius in the following scope: items 1000 km away still show, with their distance');
// العام لم يتغير: الغريب يظهر فيه
r = (await call('GET', '/feed', { expect: 200 })).j;
check(ids(r).includes(M_STR) && ids(r).includes(O_X) && !ids(r).includes(M_BLK) && r.scope === undefined, 'the default scope is unchanged (strangers and other circles, still no blocked author)');
// الضيف وصاحب حساب بلا متابعات ودوائر فقط
r = (await call('GET', '/feed?scope=following', { user: null, expect: 200 })).j;
check(r.items.length === 0 && r.next === null && r.following.people === 0, 'guest: an empty following page');
r = (await call('GET', '/feed?scope=following', { user: ORPHAN, expect: 200 })).j;
check(r.items.length === 0 && r.following.people === 0 && r.following.circles === 0, 'nobody followed and no circles: empty with zero counts (the app invites following and joining)');
r = (await call('GET', '/feed?scope=following', { user: CIRC, expect: 200 })).j;
check(same(ids(r), [O_J, J_J, C_J]) && r.following.people === 0, 'circles only: offers, jobs and here-today of the joined circle, no people query');
// الحظر يسري حين يحظرني من أتابعه أيضاً (الاتجاه الآخر): هند حظرت ليلى؛ ليلى تتابع هند فلا ترى لحظاتها
await follow(AUTH, BLKF2);
const M_HIND = await post(BLKF2, { created: -0.3, caption: 'هند' });
r = (await call('GET', '/feed?scope=following', { user: AUTH, expect: 200 })).j;
check(!ids(r).includes(M_HIND) && r.following.people === 1, 'blocked the other way (she blocked me): her moments stay out (only my friend remains in the set)', JSON.stringify(r.following));
await pool.query('DELETE FROM user_follows WHERE follower_id=$1 AND user_id=$2', [AUTH, BLKF2]);
await pool.query('DELETE FROM map_posts WHERE id=$1', [M_HIND]);
// المعرّفات للتطبيق
r = (await call('GET', '/me/following/ids', { expect: 200 })).j;
check(Array.isArray(r.ids) && same([...r.ids].sort(), [FOL, FRI, PRIV, PRIV2].sort()), 'GET /me/following/ids: followed + contacts I added, without blocked', JSON.stringify(r.ids));
check((await call('GET', '/me/following/ids', { user: null })).code === 401, 'GET /me/following/ids needs an account');

// ---- إشعار المتابِعين: ليلى (ملف عام) يتابعها: أنا، فهد، عمر (أطفأ الإشعارات)، سعد (حظرته ليلى)، هند (حظرت ليلى)، يارا (صديقتها)
for (const f of [ME, STR, OPT, BLKF, BLKF2, FRN]) await follow(f, AUTH);
let put = await call('PUT', '/me/profile/v2', { user: OPT, body: { followNotify: false }, expect: 200 });
check(put.j.settings?.followNotify === false, 'PUT followNotify=false is saved and returned in settings');
check((await call('PUT', '/me/profile/v2', { user: OPT, body: { followNotify: 'no' } })).code === 400, 'followNotify must be a boolean (400 bad-field)');
check((await call('GET', '/me/profile/v2', { user: ME, expect: 200 })).j.settings?.followNotify === true, 'followNotify defaults to on');
const notes = async () => (await pool.query("SELECT user_id, title, body, data FROM app_notifications WHERE kind='follow_moment' ORDER BY created_at, user_id")).rows;
// ينتظر حتى يستقر عدد الإشعارات (الخطّاف لا ينتظره النشر)
const settle = async (want) => { let n = []; for (let i = 0; i < 40; i++) { n = await notes(); if (n.length >= want) break; await sleep(50); } await sleep(250); return notes(); };
const newSince = (before, all) => all.slice(before.length);
let before = await notes();
const P1 = (await call('POST', '/mapposts', { user: AUTH, body: { kind: 'text', caption: 'غروب الكورنيش اليوم', audience: 'all', lat: JED.lat, lng: JED.lng }, expect: 200 })).j;
let got = newSince(before, await settle(before.length + 3));
check(same(got.map((n) => n.user_id).sort(), [ME, STR, FRN].sort()), 'a public moment notifies followers who see it: not the opted-out, not the one she blocked, not the one who blocked her', got.map((n) => NAMES[n.user_id]).join(','));
const n1 = got.find((n) => n.user_id === ME);
check(n1 && n1.title === 'لحظة جديدة من layla' && n1.body === 'غروب الكورنيش اليوم' && n1.data.postId === P1.id && n1.data.userId === AUTH && n1.data.nickname === 'layla', 'notification: kind follow_moment, title with the author, the caption as body, postId/userId/nickname', JSON.stringify(n1));
before = await notes();
await call('POST', '/mapposts', { user: AUTH, body: { kind: 'text', caption: 'لحظة ثانية بعد دقيقة', audience: 'all', lat: JED.lat, lng: JED.lng }, expect: 200 });
got = newSince(before, await settle(before.length + 1));
check(got.length === 0, 'a second moment within 6 hours does not notify again (cap per author and follower)', got.map((n) => NAMES[n.user_id]).join(','));
// بعد ست ساعات (يُرجع السجل 7 ساعات): لحظة «الأصدقاء» تصل يارا وحدها ولا تستهلك حد من لا يراها
await pool.query("UPDATE follow_notify_log SET last_at = now() - interval '7 hours' WHERE author_id=$1", [AUTH]);
before = await notes();
const P3 = (await call('POST', '/mapposts', { user: AUTH, body: { kind: 'text', caption: 'للأصدقاء فقط', audience: 'friends', lat: JED.lat, lng: JED.lng }, expect: 200 })).j;
got = newSince(before, await settle(before.length + 1));
check(P3.audience === 'friends' && same(got.map((n) => n.user_id), [FRN]), 'a friends-only moment notifies only followers she added (her friend), not other followers', got.map((n) => NAMES[n.user_id]).join(','));
await call('PUT', '/me/profile/v2', { user: OPT, body: { followNotify: true }, expect: 200 });
before = await notes();
await call('POST', '/mapposts', { user: AUTH, body: { kind: 'image', mediaUrl: '/chat/media/abcdef-0123456789abcdef01234567.jpg', audience: 'all', lat: JED.lat, lng: JED.lng }, expect: 200 });
got = newSince(before, await settle(before.length + 3));
check(same(got.map((n) => n.user_id).sort(), [ME, STR, OPT].sort()), 'next public moment: those who could not see the friends-only one keep their turn, her friend stays capped, the re-enabled follower is notified', got.map((n) => NAMES[n.user_id]).join(','));
check(got.every((n) => n.body === 'صورة'), 'a moment without caption: the media word is the body');
// ملف خاص: دانة أضافتني ولم تضف فهداً
for (const f of [ME, STR]) await follow(f, PAUTH);
before = await notes();
await call('POST', '/mapposts', { user: PAUTH, body: { kind: 'text', caption: 'من ملف خاص', audience: 'all', lat: JED.lat, lng: JED.lng }, expect: 200 });
got = newSince(before, await settle(before.length + 1));
check(same(got.map((n) => n.user_id), [ME]), 'a private profile notifies only followers it added', got.map((n) => NAMES[n.user_id]).join(','));
check((await pool.query('SELECT count(*)::int AS n FROM app_notifications WHERE kind=$1 AND user_id = ANY($2::text[])', ['follow_moment', [AUTH, PAUTH]])).rows[0].n === 0, 'the author is never notified of their own moment');
// الدالة مباشرة: لحظة مخفية أو معرّف غير صالح لا تُرسل شيئاً
check((await globalThis.naslifeNotifyFollowers({ id: M_OLD, user_id: FOL })).length === 0 && (await globalThis.naslifeNotifyFollowers({ id: 'x', user_id: FOL })).length === 0, 'a hidden moment or a bad id notifies nobody');
// حساب له 250 متابِعاً: الإرسال بدفعات متتالية من 100 (نداء واحد بالكل كان يطلق مئات استعلامات الاشتراكات واتصالات الدفع معاً)
{
  const BURST = 'SA0000116', FANS = Array.from({ length: 250 }, (_, i) => `SA000${2000 + i}`);
  await pool.query("INSERT INTO users(id, nickname) VALUES($1,'burst')", [BURST]);
  await pool.query('INSERT INTO profiles(user_id, is_public) VALUES($1, true)', [BURST]);
  await pool.query('INSERT INTO user_follows(follower_id, user_id) SELECT unnest($1::text[]), $2', [FANS, BURST]);
  const realNotify = globalThis.naslifeNotify, sizes = [];
  let inflight = 0, maxInflight = 0;
  globalThis.naslifeNotify = async (list, p) => { inflight++; maxInflight = Math.max(maxInflight, inflight); sizes.push(list.length); try { return await realNotify(list, p); } finally { inflight--; } };
  const PB = await post(BURST, { created: -0.1, caption: 'لحظة لجمهور كبير' });
  const sent = await globalThis.naslifeNotifyFollowers({ id: PB, user_id: BURST, caption: 'لحظة لجمهور كبير', kind: 'text' });
  globalThis.naslifeNotify = realNotify;
  check(sent.length === 250 && same(sizes, [100, 100, 50]) && maxInflight === 1, 'a large audience is notified in sequential chunks of 100, never one call with everyone', `sent=${sent.length} chunks=${JSON.stringify(sizes)} inflight=${maxInflight}`);
  check((await pool.query("SELECT count(DISTINCT user_id)::int AS n FROM app_notifications WHERE kind='follow_moment' AND data->>'postId'=$1", [PB])).rows[0].n === 250, 'every follower in every chunk gets the notification');
  await pool.query('DELETE FROM user_follows WHERE user_id=$1', [BURST]);
}

// ---- القوائم: متابِعو ليلى بأزمنة متعادلة لثلاثة منهم حتى يُختبر فضّ التعادل في المؤشر
await pool.query('DELETE FROM user_follows WHERE user_id=$1', [AUTH]);
const T = '2026-11-01T10:00:00.123456Z';
for (const f of [ME, STR, OPT]) await follow(f, AUTH, T);
await follow(FRN, AUTH, '2026-11-02T10:00:00Z'); await follow(BLK, AUTH, '2026-11-03T10:00:00Z'); await follow(BLKF2, AUTH, '2026-10-30T10:00:00Z');
await follow(ME, STR);   // أتابع فهداً: isFollowing في القائمة
r = (await call('GET', `/profiles/${AUTH}/followers`, { expect: 200 })).j;
const FULL = [FRN, OPT, STR, ME, BLKF2]; // الأحدث متابعةً أولاً، ثم المعرّف تنازلياً عند التعادل؛ خالد (حظرته) لا يظهر لي
check(same(ids(r), FULL) && r.next === null && r.total === 6, 'followers list newest first, ties by id, without people I blocked; total counts all', `${ids(r).map((x) => NAMES[x]).join(',')} total=${r.total}`);
const meRow = r.items.find((i) => i.id === ME), strRow = r.items.find((i) => i.id === STR), frnRow = r.items.find((i) => i.id === FRN);
check(meRow?.isMe === true && strRow?.isFollowing === true && frnRow?.isFollowing === false && strRow?.nickname === 'fahad' && 'avatarUrl' in strRow && 'displayName' in strRow, 'each person: nickname, avatar, displayName, isFollowing (I follow them), isMe');
for (const limit of [1, 2, 3]) {
  const out = []; let c = null, pages = 0;
  do { const pg1 = (await call('GET', `/profiles/${AUTH}/followers?limit=${limit}${c ? '&before=' + encodeURIComponent(c) : ''}`)).j; out.push(...ids(pg1)); c = pg1.next; pages++; } while (c && pages < 20);
  check(same(out, FULL), `followers paging with limit ${limit}: no repeats or gaps across tied timestamps (${pages} pages)`);
}
check(same(ids((await call('GET', `/profiles/${AUTH}/followers?before=garbage`)).j), FULL), 'an unparsable cursor is ignored (first page)');
r = (await call('GET', `/profiles/${AUTH}/followers`, { user: null, expect: 200 })).j;
check(ids(r).length === 6, 'a public profile\'s lists are open to guests (nobody hidden for a guest)');
check((await call('GET', `/profiles/${AUTH}/followers`, { user: BLKF })).code === 403 && (await call('GET', `/profiles/${AUTH}/following`, { user: BLKF2 })).code === 403, 'block pair (either way): 403 private, like a private profile');
r = (await call('GET', `/profiles/${ME}/following`, { expect: 200 })).j;
check(same([...ids(r)].sort(), [FOL, PRIV, PRIV2, STR, PAUTH, AUTH].sort()) && r.items.every((i) => i.isFollowing === true), 'my following list (blocked one hidden), every row isFollowing for me', ids(r).map((x) => NAMES[x]).join(','));
// الملف الخاص: دانة أضافتني فقط
await follow(OPT, PAUTH);
check((await call('GET', `/profiles/${PAUTH}/followers`, { user: ME })).code === 200, 'private profile lists: open to a contact the owner added');
check((await call('GET', `/profiles/${PAUTH}/followers`, { user: PAUTH })).code === 200, 'private profile lists: open to the owner');
check((await call('GET', `/profiles/${PAUTH}/followers`, { user: STR })).j?.error === 'private' && (await call('GET', `/profiles/${PAUTH}/following`, { user: null })).code === 403, 'private profile lists: 403 private for a follower she did not add and for guests');
check((await call('GET', '/profiles/SA0999999/followers')).code === 404, 'unknown user: 404');
// العملاء الأقدم (limit=50 وitems فقط) يعملون كما كانوا
r = (await call('GET', `/profiles/${AUTH}/following?limit=50`, { expect: 200 })).j;
check(Array.isArray(r.items) && r.next === null, 'old clients: limit=50 still returns items');
// دالة الحذف المساعدة تمسح سجل الحد أيضاً (حذف الحساب الفعلي في account_delete.js يمسحه بنفسه، وتختبره harness_account_delete.mjs)
await globalThis.naslifeProfileV2Delete(FRN);
check((await pool.query('SELECT count(*)::int AS n FROM follow_notify_log WHERE follower_id=$1 OR author_id=$1', [FRN])).rows[0].n === 0, 'naslifeProfileV2Delete clears the notify log (the real deletion path is covered in harness_account_delete)');

await pool.query("DELETE FROM biz WHERE id LIKE 'flw-%'");
await app.close(); await pool.end();
console.log(fails ? `\n${fails} FAILED` : '\nALL FOLLOW FEED TESTS PASSED');
process.exit(fails ? 1 : 0);
