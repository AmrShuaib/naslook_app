// الملف الشخصي v2 (server/profile_ext.js): الحالة، ملف بلا صف امتداد ومع صف، تسجيل الزيارات وإحصاءات سبعة أيام، فحص الحقول
// وتطبيع الروابط وقاعدة الغلاف، التعريف الصوتي/المرئي وظهوره حسب الصداقة، سياسة المراسلة، إخفاء المدينة، الملف الخاص،
// المتابعة وقوائمها وإشعار مرة واحدة، الأحداث، فحص الأسماء، اكتمال الملف، ومساعد الحذف.
// النواة وهمية: users/profiles/contacts/map_posts/market_reviews/market_orders بأعمدة دنيا كما يكتشفها الخادم.
import Fastify from 'fastify';
import pg from 'pg';
import { normaliseLink, linkUrl, handleShape, LINK_KINDS } from '../profile_ext.js';
let fails = 0;
const check = (c, l, extra = '') => { if (!c) fails++; console.log((c ? 'OK  ' : 'FAIL') + ' ' + l + (extra ? ' ' + extra : '')); };
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// ---- وحدات خالصة
check(same(normaliseLink({ kind: 'instagram', value: '@fahad' }), { kind: 'instagram', value: 'fahad' }), 'leading @ stripped');
check(same(normaliseLink({ kind: 'instagram', value: 'https://www.instagram.com/fahad/' }), { kind: 'instagram', value: 'fahad' }), 'instagram url reduced to the handle');
check(same(normaliseLink({ kind: 'tiktok', value: 'https://tiktok.com/@fahad?lang=ar' }), { kind: 'tiktok', value: 'fahad' }), 'tiktok url with @ and query reduced');
check(same(normaliseLink({ kind: 'snapchat', value: 'https://snapchat.com/add/fahad' }), { kind: 'snapchat', value: 'fahad' }), 'snapchat add/ prefix stripped');
check(same(normaliseLink({ kind: 'x', value: 'http://twitter.com/Fahad_1' }), { kind: 'x', value: 'Fahad_1' }), 'twitter.com accepted for x');
check(same(normaliseLink({ kind: 'website', value: ' fahad.sa ' }), { kind: 'website', value: 'fahad.sa' }), 'website trimmed and kept');
check(normaliseLink({ kind: 'facebook', value: 'x' }) === null && normaliseLink({ kind: 'x', value: 'has space' }) === null && normaliseLink({ kind: 'website', value: '' }) === null, 'unknown kind, spaces and empty rejected');
check(normaliseLink({ kind: 'x', value: 'a'.repeat(121) }) === null && normaliseLink({ kind: 'website', value: 'a'.repeat(121) }) === null, 'values longer than 120 rejected');
check(linkUrl('instagram', 'fahad') === 'https://instagram.com/fahad' && linkUrl('x', 'fahad') === 'https://x.com/fahad' && linkUrl('tiktok', 'fahad') === 'https://tiktok.com/@fahad' && linkUrl('snapchat', 'fahad') === 'https://snapchat.com/add/fahad', 'canonical social urls');
check(linkUrl('website', 'fahad.sa') === 'https://fahad.sa' && linkUrl('other', 'http://x.y') === 'http://x.y', 'website gets https:// only when missing');
check(same(handleShape('ab'), { nickname: 'ab', valid: false, reason: 'short' }) && handleShape('Fa-had').reason === 'chars' && handleShape('a'.repeat(21)).reason === 'chars' && same(handleShape(' Fahad.1 '), { nickname: 'fahad.1', valid: true, reason: null }), 'handle shape rules');
check(LINK_KINDS.length === 6, 'six link kinds');

// ---- التجهيز: نواة وهمية بأعمدة دنيا
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query('DROP TABLE IF EXISTS profile_ext, user_follows, profile_views, profile_events CASCADE');
await pool.query('DROP TABLE IF EXISTS users, profiles, contacts, map_posts, market_reviews, market_orders CASCADE');
await pool.query(`CREATE TABLE users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, login_email TEXT, login_verified BOOLEAN DEFAULT false, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now());
  CREATE TABLE profiles (user_id TEXT PRIMARY KEY, bio TEXT NOT NULL DEFAULT '', skills TEXT[] DEFAULT '{}', is_public BOOLEAN DEFAULT true);
  CREATE TABLE contacts (user_id TEXT NOT NULL, contact_id TEXT NOT NULL);
  CREATE TABLE map_posts (id UUID PRIMARY KEY, user_id TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'active', expires_at TIMESTAMPTZ NOT NULL, created_at TIMESTAMPTZ DEFAULT now());
  CREATE TABLE market_reviews (order_id UUID PRIMARY KEY, seller_id TEXT NOT NULL, buyer_id TEXT NOT NULL, rating INT NOT NULL);
  CREATE TABLE market_orders (id UUID PRIMARY KEY, buyer_id TEXT NOT NULL, seller_id TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'paid');`);
const FAHAD = 'SA0000001', SARA = 'SA0000002', KHALID = 'SA0000003', NOURA = 'SA0000004';
await pool.query(`INSERT INTO users(id, nickname, avatar_url, login_email, login_verified, created_at) VALUES
  ('${FAHAD}', 'Fahad', 'https://naslife.app/chat/media/av1.jpg', 'f@x.sa', true, '2025-03-01T00:00:00Z'),
  ('${SARA}', 'sara', NULL, NULL, false, '2025-04-01T00:00:00Z'),
  ('${KHALID}', 'khalid', NULL, NULL, false, now()),
  ('${NOURA}', 'noura', NULL, NULL, false, now())`);
await pool.query(`INSERT INTO profiles(user_id, bio, skills, is_public) VALUES ('${FAHAD}', 'مصوّر في جدة', '{تصوير,مونتاج}', true), ('${NOURA}', 'خاص', '{}', false)`);
await pool.query(`INSERT INTO contacts(user_id, contact_id) VALUES ('${FAHAD}', '${SARA}'), ('${NOURA}', '${SARA}')`);
const uuid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
await pool.query(`INSERT INTO map_posts(id, user_id, status, expires_at) VALUES ($1, '${FAHAD}', 'active', now() + interval '1 day'), ($2, '${FAHAD}', 'active', now() + interval '2 days'), ($3, '${FAHAD}', 'active', now() - interval '1 day'), ($4, '${FAHAD}', 'hidden', now() + interval '1 day')`, [uuid(1), uuid(2), uuid(3), uuid(4)]);
await pool.query(`INSERT INTO market_reviews(order_id, seller_id, buyer_id, rating) VALUES ($1, '${FAHAD}', '${SARA}', 5), ($2, '${FAHAD}', '${KHALID}', 4)`, [uuid(11), uuid(12)]);
await pool.query(`INSERT INTO market_orders(id, buyer_id, seller_id, status) VALUES ($1, '${SARA}', '${FAHAD}', 'completed'), ($2, '${SARA}', '${FAHAD}', 'delivered'), ($3, '${KHALID}', '${FAHAD}', 'done'), ($4, '${KHALID}', '${FAHAD}', 'paid')`, [uuid(21), uuid(22), uuid(23), uuid(24)]);

const notes = [];
globalThis.naslifeNotify = async (ids, p) => { notes.push({ ids, ...p }); };
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
app.register((await import('../profile_ext.js')).default, { pool, auth });
await app.ready();
const call = async (method, url, { body = {}, user = FAHAD, expect } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json', host: 'naslife.app', 'x-forwarded-proto': 'https' }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url} [${user ?? 'guest'}] -> ${r.statusCode}`, r.statusCode === expect ? '' : String(typeof j === 'string' ? j : JSON.stringify(j)).slice(0, 200));
  return j;
};

// ---- الحالة والاكتشاف
const st = await call('GET', '/profile/v2/status', { user: null, expect: 200 });
check(st.ok === true && st.users === true && st.profiles === 'profiles' && st.contacts === true && st.posts === true && st.reviews === true && st.orders === true, 'status reports detected core tables', JSON.stringify(st));

// ---- ملف بلا صف امتداد (زائر ضيف) ومع الإحصاءات من النواة
let p = await call('GET', `/profiles/${FAHAD}/v2`, { user: null, expect: 200 });
check(p.id === FAHAD && p.nickname === 'Fahad' && p.displayName === '' && p.avatarUrl === 'https://naslife.app/chat/media/av1.jpg' && p.coverUrl === null && p.bio === 'مصوّر في جدة' && p.accountType === 'personal' && p.jobTitle === '' && p.city === '' && same(p.links, []) && p.intro === null, 'profile without ext row uses defaults', JSON.stringify(p));
check(same(p.stats, { posts: 2, followers: 0, following: 0, circles: 0, ratingAvg: 4.5, ratingCount: 2, completedOrders: 3, friends: 0 }), 'stats from core tables (friends hidden by default)', JSON.stringify(p.stats));
check(p.trust.emailVerified === true && p.trust.phoneVerified === false && p.trust.memberSince === '2025-03-01T00:00:00.000Z' && p.trust.respondsFast === null && p.memberSince === p.trust.memberSince, 'trust block', JSON.stringify(p.trust));
check(same(p.flags, { isMe: false, isFollowing: false, isFriend: false, isPrivate: false, blocked: false, canMessage: true, online: null, showFriends: false }), 'guest flags', JSON.stringify(p.flags));
p = await call('GET', '/profiles/fahad/v2', { user: SARA, expect: 200 });
check(p.id === FAHAD && p.flags.isFriend === true && p.flags.isMe === false, 'resolved by nickname case-insensitively, friend flag set');
p = await call('GET', '/profiles/@FAHAD/v2', { user: null, expect: 200 });
check(p.id === FAHAD, 'leading @ in handle ignored');
await call('GET', '/profiles/nobody/v2', { user: null, expect: 404 });
await call('GET', '/profiles/SA9999999/v2', { user: null, expect: 404 });
p = await call('GET', `/profiles/${KHALID}/v2`, { user: null, expect: 200 });
check(p.bio === '' && same(p.stats, { posts: 0, followers: 0, following: 0, circles: 0, ratingAvg: null, ratingCount: 0, completedOrders: 0, friends: 0 }) && p.trust.emailVerified === false, 'user without profiles row gets empty defaults', JSON.stringify(p.stats));

// ---- تسجيل الزيارات: مرة لكل زائر ويوم، لا للمالك ولا للضيف
await call('GET', `/profiles/${FAHAD}/v2`, { user: SARA, expect: 200 });
await call('GET', `/profiles/${FAHAD}/v2`, { user: SARA, expect: 200 });
await call('GET', `/profiles/${FAHAD}/v2`, { user: KHALID, expect: 200 });
await call('GET', `/profiles/${FAHAD}/v2`, { user: FAHAD, expect: 200 });
await call('GET', `/profiles/${FAHAD}/v2`, { user: null, expect: 200 });
check((await pool.query('SELECT count(*)::int AS n FROM profile_views WHERE user_id=$1', [FAHAD])).rows[0].n === 2, 'two unique viewers recorded today');
await pool.query("INSERT INTO profile_views(user_id, viewer_id, day) VALUES ($1, $2, current_date - 3), ($1, $3, current_date - 3), ($1, $2, current_date - 8), ($1, $2, current_date - 20)", [FAHAD, SARA, KHALID]);
let s7 = await call('GET', '/me/profile/stats', { expect: 200 });
check(s7.visits7 === 4 && s7.visits7Prev === 1 && s7.messages7 === 0 && s7.follows7 === 0 && s7.shares7 === 0, 'visits this week and previous week', JSON.stringify(s7));
check(Array.isArray(s7.series) && s7.series.length === 7 && s7.series.every((d) => /^\d{4}-\d{2}-\d{2}$/.test(d.day) && Number.isInteger(d.visits)) && s7.series[6].visits === 2 && s7.series[3].visits === 2 && s7.series.reduce((a, d) => a + d.visits, 0) === 4, 'series has 7 days oldest to newest', JSON.stringify(s7.series));
check(s7.series.slice(1).every((d, i) => d.day > s7.series[i].day), 'series days ascend');
await call('GET', '/me/profile/stats', { user: null, expect: 401 });

// ---- تعديل الحقول
await call('PUT', '/me/profile/v2', { body: { displayName: 'x' }, user: null, expect: 401 });
let m = await call('PUT', '/me/profile/v2', { body: { displayName: '  فهد العتيبي ', jobTitle: 'مصوّر', city: 'جدة', district: 'الشاطئ', links: [{ kind: 'instagram', value: '@fahad' }, { kind: 'x', value: 'https://www.x.com/fahad_1/' }, { kind: 'website', value: 'fahad.sa' }], coverUrl: '/chat/media/cover-1.jpg', msgPolicy: 'friends', showOnline: false, showCity: false, showFriends: true, introVisibility: 'friends' }, expect: 200 });
check(m.displayName === 'فهد العتيبي' && m.jobTitle === 'مصوّر' && m.city === 'جدة' && m.district === 'الشاطئ' && m.coverUrl === 'https://naslife.app/chat/media/cover-1.jpg', 'fields trimmed and cover made absolute', JSON.stringify([m.displayName, m.coverUrl]));
check(same(m.links, [{ kind: 'instagram', value: 'fahad', url: 'https://instagram.com/fahad' }, { kind: 'x', value: 'fahad_1', url: 'https://x.com/fahad_1' }, { kind: 'website', value: 'fahad.sa', url: 'https://fahad.sa' }]), 'links normalised with canonical urls', JSON.stringify(m.links));
check(same(m.settings, { msgPolicy: 'friends', showOnline: false, showCity: false, showFriends: true, introVisibility: 'friends' }), 'settings echoed', JSON.stringify(m.settings));
check(m.flags.isMe === true && m.flags.canMessage === true && m.flags.online === null && m.stats.friends === 1, 'owner sees own friends count and can always message');
m = await call('PUT', '/me/profile/v2', { body: { jobTitle: 'مخرج' }, expect: 200 });
check(m.jobTitle === 'مخرج' && m.displayName === 'فهد العتيبي' && m.links.length === 3 && m.settings.msgPolicy === 'friends', 'partial put keeps the other fields');
m = await call('PUT', '/me/profile/v2', { body: {}, expect: 200 });
check(m.jobTitle === 'مخرج', 'empty body changes nothing');
const badField = async (body, field, label) => { const r = await call('PUT', '/me/profile/v2', { body, expect: 400 }); check(r.error === 'bad-field' && r.field === field, label, JSON.stringify(r)); };
await badField({ displayName: 'a'.repeat(41) }, 'displayName', 'display name over 40 rejected');
await badField({ city: 12 }, 'city', 'non-string city rejected');
await badField({ links: [{ kind: 'facebook', value: 'x' }] }, 'links', 'unknown link kind rejected');
await badField({ links: [{ kind: 'x', value: 'a'.repeat(121) }] }, 'links', 'link value over 120 rejected');
await badField({ links: [{ kind: 'x', value: 'a' }, { kind: 'x', value: 'b' }, { kind: 'x', value: 'c' }, { kind: 'x', value: 'd' }] }, 'links', 'more than three links rejected');
await badField({ links: 'x' }, 'links', 'links must be an array');
await badField({ msgPolicy: 'everyone' }, 'msgPolicy', 'bad msg policy rejected');
await badField({ introVisibility: 'none' }, 'introVisibility', 'bad intro visibility rejected');
await badField({ showOnline: 'yes' }, 'showOnline', 'non-boolean toggle rejected');
await badField({ coverUrl: 'https://evil.example/x.jpg' }, 'coverUrl', 'foreign cover url rejected');
await badField({ coverUrl: '/files/x.jpg' }, 'coverUrl', 'non-media path rejected');
const rawBad = await app.inject({ method: 'PUT', url: '/me/profile/v2', headers: { 'x-user': FAHAD, 'content-type': 'application/json' }, payload: '[1]' });
check(rawBad.statusCode === 400, 'array body rejected');
m = await call('GET', '/me/profile/v2', { expect: 200 });
check(m.jobTitle === 'مخرج' && m.coverUrl === 'https://naslife.app/chat/media/cover-1.jpg', 'bad payloads did not change the row');
m = await call('PUT', '/me/profile/v2', { body: { coverUrl: 'https://naslife.app/chat/media/cover-2.jpg' }, expect: 200 });
check(m.coverUrl === 'https://naslife.app/chat/media/cover-2.jpg', 'absolute media cover accepted');
m = await call('PUT', '/me/profile/v2', { body: { coverUrl: null }, expect: 200 });
check(m.coverUrl === null, 'null clears the cover');
await call('PUT', '/me/profile/v2', { body: { coverUrl: '/chat/media/cover-1.jpg' }, expect: 200 });

// ---- المدينة تُخفى عن الآخرين عند show_city=false والأصدقاء يُعدّون عند show_friends=true
p = await call('GET', `/profiles/${FAHAD}/v2`, { user: SARA, expect: 200 });
check(p.city === '' && p.district === '' && p.displayName === 'فهد العتيبي' && p.coverUrl === 'https://naslife.app/chat/media/cover-1.jpg', 'city hidden for visitors when show_city is off', JSON.stringify([p.city, p.district]));
check(p.stats.friends === 1 && p.flags.showFriends === true, 'friends count visible when show_friends is on');
await call('PUT', '/me/profile/v2', { body: { showCity: true }, expect: 200 });
p = await call('GET', `/profiles/${FAHAD}/v2`, { user: SARA, expect: 200 });
check(p.city === 'جدة' && p.district === 'الشاطئ', 'city visible again');

// ---- سياسة المراسلة
p = await call('GET', `/profiles/${FAHAD}/v2`, { user: SARA, expect: 200 }); check(p.flags.canMessage === true, 'friends policy: friend can message');
p = await call('GET', `/profiles/${FAHAD}/v2`, { user: KHALID, expect: 200 }); check(p.flags.canMessage === false, 'friends policy: stranger cannot message');
p = await call('GET', `/profiles/${FAHAD}/v2`, { user: null, expect: 200 }); check(p.flags.canMessage === false, 'friends policy: guest cannot message');
await call('PUT', '/me/profile/v2', { body: { msgPolicy: 'none' }, expect: 200 });
p = await call('GET', `/profiles/${FAHAD}/v2`, { user: SARA, expect: 200 }); check(p.flags.canMessage === false, 'none policy: even a friend cannot message');
m = await call('GET', '/me/profile/v2', { expect: 200 }); check(m.flags.canMessage === true, 'none policy: owner still true');
await call('PUT', '/me/profile/v2', { body: { msgPolicy: 'all' }, expect: 200 });
p = await call('GET', `/profiles/${FAHAD}/v2`, { user: KHALID, expect: 200 }); check(p.flags.canMessage === true, 'all policy: stranger can message');

// ---- التعريف الصوتي/المرئي
await call('PUT', '/me/profile/intro', { body: { kind: 'voice', url: '/chat/media/v.weba', sec: 42 }, user: null, expect: 401 });
const badIntro = async (body, label) => { const r = await call('PUT', '/me/profile/intro', { body, expect: 400 }); check(r.error === 'bad-intro', label, JSON.stringify(r)); };
await badIntro({ kind: 'voice', url: '/chat/media/v.weba', sec: 61 }, 'voice over 60s rejected');
await badIntro({ kind: 'video', url: '/chat/media/v.mp4', sec: 31 }, 'video over 30s rejected');
await badIntro({ kind: 'voice', url: '/chat/media/v.weba', sec: 0 }, 'zero seconds rejected');
await badIntro({ kind: 'voice', url: '/chat/media/v.weba', sec: 4.5 }, 'fractional seconds rejected');
await badIntro({ kind: 'text', url: '/chat/media/v.weba', sec: 5 }, 'bad kind rejected');
await badIntro({ kind: 'voice', url: 'https://evil.example/v.weba', sec: 5 }, 'foreign url rejected');
await badIntro({ kind: 'voice', sec: 5 }, 'missing url rejected');
let it = await call('PUT', '/me/profile/intro', { body: { kind: 'voice', url: '/chat/media/v1.weba', sec: 60 }, expect: 200 });
check(it.ok === true && it.intro.kind === 'voice' && it.intro.url === 'https://naslife.app/chat/media/v1.weba' && it.intro.sec === 60 && !Number.isNaN(Date.parse(it.intro.at)), 'voice intro of 60s stored', JSON.stringify(it));
const dropped = []; globalThis.naslifeMediaDelete = async (u) => { dropped.push(u); return true; };
it = await call('PUT', '/me/profile/intro', { body: { kind: 'video', url: 'https://naslife.app/chat/media/v2.mp4', sec: 30 }, expect: 200 });
check(it.intro.kind === 'video' && it.intro.sec === 30 && same(dropped, ['https://naslife.app/chat/media/v1.weba']), 'video intro of 30s replaces the voice one and drops the old file', JSON.stringify(dropped));
// الظهور: friends فقط → مخفي عن الغريب والضيف، ظاهر للصديق والمالك
p = await call('GET', `/profiles/${FAHAD}/v2`, { user: KHALID, expect: 200 }); check(p.intro === null, 'intro hidden from a stranger when visibility=friends');
p = await call('GET', `/profiles/${FAHAD}/v2`, { user: null, expect: 200 }); check(p.intro === null, 'intro hidden from guests when visibility=friends');
p = await call('GET', `/profiles/${FAHAD}/v2`, { user: SARA, expect: 200 }); check(p.intro?.kind === 'video' && p.intro.url === 'https://naslife.app/chat/media/v2.mp4' && p.intro.sec === 30, 'intro visible to a friend', JSON.stringify(p.intro));
m = await call('GET', '/me/profile/v2', { expect: 200 }); check(m.intro?.kind === 'video', 'intro visible to the owner');
await call('PUT', '/me/profile/v2', { body: { introVisibility: 'all' }, expect: 200 });
p = await call('GET', `/profiles/${FAHAD}/v2`, { user: null, expect: 200 }); check(p.intro?.kind === 'video', 'intro visible to everyone when visibility=all');
await call('DELETE', '/me/profile/intro', { user: null, expect: 401 });
const d = await call('DELETE', '/me/profile/intro', { expect: 200 });
check(d.ok === true && dropped.length === 2 && dropped[1] === 'https://naslife.app/chat/media/v2.mp4', 'delete clears the intro and drops the file');
p = await call('GET', `/profiles/${FAHAD}/v2`, { user: SARA, expect: 200 }); check(p.intro === null, 'intro gone after delete');
await call('DELETE', '/me/profile/intro', { expect: 200 });
check(dropped.length === 2, 'second delete is a no-op');

// ---- الملف الخاص: كائن مختصر بـ200 للغريب، كامل للصديق والمالك
p = await call('GET', `/profiles/${NOURA}/v2`, { user: KHALID, expect: 200 });
check(same(Object.keys(p).sort(), ['avatarUrl', 'coverUrl', 'displayName', 'flags', 'id', 'nickname', 'stats']) && p.flags.isPrivate === true && p.flags.isMe === false && same(p.stats, {}) && p.bio === undefined, 'private profile limited for a stranger', JSON.stringify(p));
p = await call('GET', `/profiles/${NOURA}/v2`, { user: null, expect: 200 }); check(p.flags.isPrivate === true && p.bio === undefined, 'private profile limited for guests');
p = await call('GET', `/profiles/${NOURA}/v2`, { user: SARA, expect: 200 }); check(p.flags.isPrivate === true && p.flags.isFriend === true && p.bio === 'خاص' && typeof p.stats.posts === 'number', 'private profile full for a friend');
p = await call('GET', '/me/profile/v2', { user: NOURA, expect: 200 }); check(p.flags.isPrivate === true && p.flags.isMe === true && p.bio === 'خاص' && p.settings && p.completion, 'private profile full for the owner');

// ---- المتابعة
await call('POST', `/profiles/${FAHAD}/follow`, { user: null, expect: 401 });
let f = await call('POST', `/profiles/${FAHAD}/follow`, { expect: 400 }); check(f.error === 'self', 'following yourself rejected');
f = await call('DELETE', `/profiles/${FAHAD}/follow`, { expect: 400 }); check(f.error === 'self', 'unfollowing yourself rejected');
await call('POST', '/profiles/SA9999999/follow', { user: SARA, expect: 404 });
f = await call('POST', `/profiles/${FAHAD}/follow`, { user: SARA, expect: 200 });
check(same(f, { ok: true, following: true, followers: 1 }), 'sara follows fahad', JSON.stringify(f));
check(notes.length === 1 && same(notes[0].ids, [FAHAD]) && notes[0].kind === 'profile_follow' && notes[0].title === 'sara يتابعك' && notes[0].data.userId === SARA, 'follow notification sent to fahad', JSON.stringify(notes));
f = await call('POST', `/profiles/${FAHAD}/follow`, { user: SARA, expect: 200 });
check(same(f, { ok: true, following: true, followers: 1 }) && notes.length === 1, 'follow is idempotent and does not notify again');
f = await call('POST', '/profiles/fahad/follow', { user: KHALID, expect: 200 });
check(f.followers === 2 && notes.length === 2 && notes[1].title === 'khalid يتابعك', 'second follower by nickname, notified');
p = await call('GET', `/profiles/${FAHAD}/v2`, { user: SARA, expect: 200 });
check(p.flags.isFollowing === true && p.stats.followers === 2 && p.stats.following === 0, 'follow flag and counts on the profile');
p = await call('GET', `/profiles/${SARA}/v2`, { user: FAHAD, expect: 200 });
check(p.flags.isFollowing === false && p.stats.followers === 0 && p.stats.following === 1, 'following count for sara');
let list = await call('GET', `/profiles/${FAHAD}/followers`, { user: null, expect: 200 });
check(same(list.items.map((x) => x.id), [KHALID, SARA]) && list.items[1].nickname === 'sara' && list.items[1].avatarUrl === null, 'followers list newest first with nicknames', JSON.stringify(list));
list = await call('GET', `/profiles/${SARA}/following`, { user: null, expect: 200 });
check(same(list.items, [{ id: FAHAD, nickname: 'Fahad', avatarUrl: 'https://naslife.app/chat/media/av1.jpg' }]), 'following list', JSON.stringify(list));
list = await call('GET', `/profiles/${FAHAD}/followers?limit=1`, { user: null, expect: 200 });
check(list.items.length === 1 && list.items[0].id === KHALID, 'limit respected');
await call('GET', '/profiles/nobody/followers', { user: null, expect: 404 });
f = await call('DELETE', `/profiles/${FAHAD}/follow`, { user: SARA, expect: 200 });
check(same(f, { ok: true, following: false, followers: 1 }), 'unfollow', JSON.stringify(f));
f = await call('DELETE', `/profiles/${FAHAD}/follow`, { user: SARA, expect: 200 });
check(same(f, { ok: true, following: false, followers: 1 }), 'unfollow is idempotent');
f = await call('POST', `/profiles/${FAHAD}/follow`, { user: SARA, expect: 200 });
check(f.followers === 2 && notes.length === 2, 'refollow does not notify again (once per follower)');

// ---- الأحداث والإحصاءات
const e = await call('POST', `/profiles/${FAHAD}/event`, { body: { kind: 'message' }, user: SARA, expect: 200 }); check(e.ok === true, 'message event recorded');
await call('POST', `/profiles/${FAHAD}/event`, { body: { kind: 'share' }, user: null, expect: 200 });
await call('POST', `/profiles/${FAHAD}/event`, { body: { kind: 'link' }, user: KHALID, expect: 200 });
await call('POST', `/profiles/${FAHAD}/event`, { body: { kind: 'message' }, user: FAHAD, expect: 200 });
const be = await call('POST', `/profiles/${FAHAD}/event`, { body: { kind: 'view' }, user: SARA, expect: 400 }); check(be.error === 'bad-kind', 'unknown event kind rejected');
await call('POST', '/profiles/nobody/event', { body: { kind: 'share' }, user: SARA, expect: 404 });
check((await pool.query("SELECT count(*)::int AS n FROM profile_events WHERE user_id=$1 AND kind='message'", [FAHAD])).rows[0].n === 1, 'owner event ignored');
s7 = await call('GET', '/me/profile/stats', { expect: 200 });
check(s7.messages7 === 1 && s7.follows7 === 3 && s7.shares7 === 1 && s7.links7 === 1 && s7.series.length === 7, 'seven-day counters', JSON.stringify(s7));
check(same(Object.keys(s7).sort(), ['follows7', 'links7', 'messages7', 'series', 'shares7', 'visits7', 'visits7Prev']), 'stats keys');

// ---- فحص الأسماء
const h = async (n) => call('GET', `/handles/check?nickname=${encodeURIComponent(n)}`, { user: null, expect: 200 });
check(same(await h('new_user.1'), { valid: true, available: true, reason: null }), 'valid and available');
check(same(await h('ab'), { valid: false, available: false, reason: 'short' }), 'too short');
check(same(await h('bad name'), { valid: false, available: false, reason: 'chars' }), 'bad characters');
check(same(await h('a'.repeat(21)), { valid: false, available: false, reason: 'chars' }), 'too long');
check(same(await h('admin'), { valid: true, available: false, reason: 'taken' }) && same(await h('NasLife'), { valid: true, available: false, reason: 'taken' }), 'reserved names taken');
check(same(await h('FAHAD'), { valid: true, available: false, reason: 'taken' }) && same(await h('Sara'), { valid: true, available: false, reason: 'taken' }), 'existing names taken case-insensitively');
check(same(await h(''), { valid: false, available: false, reason: 'short' }), 'missing nickname');
globalThis.naslifeNickReserved = async (n) => n === 'gone_user';
check(same(await h('gone_user'), { valid: true, available: false, reason: 'taken' }), 'deleted names reserved by account_delete are taken');
delete globalThis.naslifeNickReserved;

// ---- الاكتمال
m = await call('GET', '/me/profile/v2', { expect: 200 });
let done = Object.fromEntries(m.completion.steps.map((s) => [s.id, s.done]));
check(same(m.completion.steps.map((s) => s.id), ['avatar', 'cover', 'bio', 'links', 'intro', 'email', 'skills']) && m.completion.steps.every((s) => typeof s.label === 'string' && s.label), 'seven completion steps with labels', JSON.stringify(m.completion));
check(same(done, { avatar: true, cover: true, bio: true, links: true, intro: false, email: true, skills: true }) && m.completion.pct === 85, 'six of seven done = 85%', JSON.stringify([done, m.completion.pct]));
await call('PUT', '/me/profile/intro', { body: { kind: 'voice', url: '/chat/media/v3.weba', sec: 12 }, expect: 200 });
m = await call('GET', '/me/profile/v2', { expect: 200 }); check(m.completion.pct === 100, 'all done = 100%');
m = await call('GET', '/me/profile/v2', { user: KHALID, expect: 200 });
done = Object.fromEntries(m.completion.steps.map((s) => [s.id, s.done]));
check(Object.values(done).every((v) => v === false) && m.completion.pct === 0, 'fresh user = 0%', JSON.stringify(done));
await call('PUT', '/me/profile/v2', { body: { links: [{ kind: 'x', value: 'khalid' }] }, user: KHALID, expect: 200 });
m = await call('GET', '/me/profile/v2', { user: KHALID, expect: 200 }); check(m.completion.pct === 15, 'one of seven = 15%', String(m.completion.pct));

// ---- المساعدات العامة والحذف
const ext = await globalThis.naslifeProfileExt(FAHAD);
check(ext && ext.user_id === FAHAD && ext.display_name === 'فهد العتيبي' && ext.intro_kind === 'voice', 'naslifeProfileExt returns the row');
check((await globalThis.naslifeProfileExt('SA9999999')) === null, 'naslifeProfileExt null for unknown user');
check((await globalThis.naslifeProfileV2Delete(FAHAD)) === true, 'naslifeProfileV2Delete returns true');
const left = await Promise.all([
  pool.query('SELECT count(*)::int AS n FROM profile_ext WHERE user_id=$1', [FAHAD]),
  pool.query('SELECT count(*)::int AS n FROM user_follows WHERE user_id=$1 OR follower_id=$1', [FAHAD]),
  pool.query('SELECT count(*)::int AS n FROM profile_views WHERE user_id=$1 OR viewer_id=$1', [FAHAD]),
  pool.query('SELECT count(*)::int AS n FROM profile_events WHERE user_id=$1 OR actor_id=$1', [FAHAD]),
]);
check(left.every((r) => r.rows[0].n === 0), 'all four tables wiped for the user', JSON.stringify(left.map((r) => r.rows[0].n)));
check((await pool.query('SELECT count(*)::int AS n FROM profile_ext WHERE user_id=$1', [KHALID])).rows[0].n === 1, 'other users untouched');
check((await globalThis.naslifeProfileV2Delete(FAHAD)) === true && (await globalThis.naslifeProfileV2Delete('')) === false, 'delete helper idempotent and rejects empty id');
p = await call('GET', `/profiles/${FAHAD}/v2`, { user: SARA, expect: 200 });
check(p.displayName === '' && p.intro === null && p.stats.followers === 0 && p.flags.isFollowing === false, 'profile back to defaults after wipe');

// ---- بلا جداول نواة: الإضافة تعمل وتعيد أصفاراً
await pool.query('DROP TABLE IF EXISTS profiles, contacts, map_posts, market_reviews, market_orders CASCADE');
const app2 = Fastify();
app2.register((await import('../profile_ext.js')).default, { pool, auth });
await app2.ready();
const r2 = await app2.inject({ method: 'GET', url: `/profiles/${SARA}/v2`, headers: { 'x-user': KHALID } });
const p2 = r2.json();
check(r2.statusCode === 200 && same(p2.stats, { posts: 0, followers: 0, following: 0, circles: 0, ratingAvg: null, ratingCount: 0, completedOrders: 0, friends: 0 }) && p2.bio === '' && p2.flags.isPrivate === false, 'works without core profile tables', JSON.stringify(p2.stats));
await app2.close();

await app.close(); await pool.end();
console.log(fails ? `\n${fails} FAILED` : '\nALL PROFILE V2 TESTS PASSED');
process.exit(fails ? 1 : 0);
