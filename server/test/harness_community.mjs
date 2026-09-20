// اختبارات دائرة المطار ومساحة المجتمع (server/business_seed.js + server/biz_community.js + server/safety.js):
// إدراج المطار وخدماته التعريفية، النشر والقائمة (المثبّت أولاً، المواضيع، الصفحات)، تنقية الصور، الكلمات المحظورة،
// تصفية المحظورين، الردود والإشعارات، الإعجاب، التثبيت/الإخفاء للإدارة فقط، الحذف، البلاغات مع الإخفاء التلقائي، والحدّ الساعي.
import Fastify from 'fastify';
import pg from 'pg';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0';
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("INSERT INTO users(id,nickname) VALUES('SA0000001','amr'),('SA0000002','sara'),('SA0000003','khalid'),('SA0000004','nora') ON CONFLICT DO NOTHING");
await pool.query("CREATE TABLE IF NOT EXISTS user_blocks (user_id TEXT NOT NULL, blocked_id TEXT NOT NULL, created_at TIMESTAMPTZ DEFAULT now(), PRIMARY KEY (user_id, blocked_id))");
for (const sql of ['DELETE FROM user_blocks', 'DROP TABLE IF EXISTS biz_community_posts, biz_community_replies, biz_community_likes, biz_community_reply_likes, biz_community_reactions, content_reports', 'DELETE FROM app_notifications', "INSERT INTO admins(user_id,granted_by) VALUES('SA0000004','test') ON CONFLICT DO NOTHING", "DELETE FROM biz_staff WHERE biz_id='biz-kaia'"]) { try { await pool.query(sql); } catch { /* أول تشغيل */ } }
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
const dir = new URL('.', import.meta.url).pathname;
app.register((await import('../notify.js')).default, { pool, auth, pollMs: 3600000, opsDir: dir + 'ops' });
app.register((await import('../commerce.js')).default, { pool, auth });
app.register((await import('../business.js')).default, { pool, auth });
app.register((await import('../biz_community.js')).default, { pool, auth });
app.register((await import('../safety.js')).default, { pool, auth });
app.register((await import('../admin.js')).default, { pool, auth, webappDir: dir + 'webapp', opsDir: dir + 'ops' });
await app.ready(); await new Promise((r) => setTimeout(r, 800));
let fails = 0;
const check = (cond, label, extra = '') => { if (!cond) fails++; console.log((cond ? 'OK  ' : 'FAIL') + ' ' + label + (extra ? ' ' + extra : '')); };
const call = async (method, url, { body = {}, user = 'SA0000001', expect } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json', host: 'www.naslife.app' }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url} -> ${r.statusCode}`, r.statusCode === expect ? '' : JSON.stringify(j).slice(0, 160));
  return j;
};
// ---- المطار
check((await call('GET', '/biz/community/status', { user: null, expect: 200 })).topics.length === 5, 'community status lists 5 topics');
const list = await call('GET', '/biz?category=airport', { user: null, expect: 200 });
check(list.length === 1 && list[0].id === 'biz-kaia' && list[0].itemsCount === 25, 'airport listed by category', JSON.stringify({ n: list.length, items: list[0]?.itemsCount }));
const a = await call('GET', '/biz/biz-kaia', { user: null, expect: 200 });
check(a.nameAr === 'مطار الملك عبدالعزيز الدولي بجدة' && a.phone === '8001168888' && a.website?.includes('jed-airport') && a.lat > 21.6 && a.lng > 39.1, 'airport profile', JSON.stringify({ name: a.nameAr, phone: a.phone, site: a.website }));
check(a.items.every((i) => i.kind === 'info' && i.price === 0 && i.slots === undefined), 'all airport items are free info services');
const lost = a.items.find((i) => i.id === 'kaia-lost');
check(lost && lost.meta.phone && lost.meta.location, 'lost & found carries phone/location', JSON.stringify(lost?.meta));
check(a.items.some((i) => i.id === 'kaia-hajj') && a.items.some((i) => i.id === 'kaia-wifi') && a.items.some((i) => i.id === 'kaia-complaints'), 'hajj terminal, wifi and complaints present');
check((await call('POST', '/biz/biz-kaia/orders', { body: { itemId: 'kaia-wifi' }, expect: 400 })).error === 'not-orderable', 'info service is not orderable');

// ---- المقاهي المختصة
const cafes = (await call('GET', '/biz?category=cafe', { user: null, expect: 200 })).filter((c) => c.lat < 23);
check(cafes.length === 10 && cafes.every((c) => c.category === 'cafe' && c.lat > 21.4 && c.lng > 39.0 && c.itemsCount >= 8), '10 cafés listed with coordinates and menus', JSON.stringify({ n: cafes.length, ids: cafes.map((c) => c.id) }));
const brew = await call('GET', '/biz/biz-brew92', { user: null, expect: 200 });
check(brew.logoUrl === 'asset:biz/brew92.png' && brew.address.includes('الروضة') && brew.items.length === 9 && brew.items.every((i) => i.kind === 'product' && i.discussions === 0), 'brew92: asset logo, district address, product menu, zero discussions', JSON.stringify({ logo: brew.logoUrl, n: brew.items.length }));
check(cafes.filter((c) => c.logoUrl).length === 6, 'six cafés carry a logo', String(cafes.filter((c) => c.logoUrl).length));
// اقتباس منتج في المشاركة والرد، قلوب الردود، الترتيب والأكثر نقاشاً
await call('POST', '/biz/biz-brew92/community', { body: { text: 'V60 هنا ممتاز', itemId: 'overdose-v60' }, expect: 400 });
const qp = await call('POST', '/biz/biz-brew92/community', { body: { text: 'V60 هنا ممتاز', itemId: 'brew92-v60' }, expect: 200 });
check(qp.item && qp.item.id === 'brew92-v60' && qp.item.title === 'V60 تقطير' && qp.item.price === 2200 && qp.item.unit === 'item', 'post carries the quoted product', JSON.stringify(qp.item));
const qp2 = await call('POST', '/biz/biz-brew92/community', { body: { text: 'الفلات وايت أفضل', itemId: 'brew92-flatwhite' }, user: 'SA0000002', expect: 200 });
const qr = await call('POST', `/biz/biz-brew92/community/${qp.id}/replies`, { body: { audio: '/chat/media/rv.m4a', audioMs: 3000, itemId: 'brew92-v60' }, user: 'SA0000003', expect: 200 });
check(qr.item?.id === 'brew92-v60' && qr.likes === 0 && qr.liked === false, 'voice reply quoting the product with heart counters', JSON.stringify(qr.item));
await call('POST', `/biz/biz-brew92/community/${qp.id}/replies`, { body: { text: 'x', itemId: 'nope' }, user: 'SA0000003', expect: 400 });
let rlk = await call('POST', `/biz/biz-brew92/community/${qp.id}/replies/${qr.id}/like`, { user: 'SA0000002', expect: 200 });
check(rlk.liked === true && rlk.likes === 1, 'heart on a reply');
rlk = await call('POST', `/biz/biz-brew92/community/${qp.id}/replies/${qr.id}/like`, { expect: 200 });
check(rlk.likes === 2, 'second heart');
const th = await call('GET', `/biz/biz-brew92/community/${qp.id}`, { expect: 200 });
check(th.replies[0].likes === 2 && th.replies[0].liked === true, 'thread shows reply hearts and my state');
await call('POST', `/biz/biz-brew92/community/${qp.id}/like`, { user: 'SA0000002', expect: 200 });
let bf = await call('GET', '/biz/biz-brew92/community?itemId=brew92-v60', { expect: 200 });
check(bf.posts.length === 1 && bf.posts[0].id === qp.id, 'feed filtered by product');
bf = await call('GET', '/biz/biz-brew92/community', { expect: 200 });
check(bf.topItems.length === 2 && bf.topItems[0].item.id === 'brew92-v60' && bf.topItems[0].count === 2 && bf.topItems[1].count === 1, 'most discussed products (post + reply)', JSON.stringify(bf.topItems.map((t) => [t.item.id, t.count])));
check(bf.posts[0].id === qp2.id, 'newest first by default');
bf = await call('GET', '/biz/biz-brew92/community?sort=top', { expect: 200 });
check(bf.posts[0].id === qp.id, 'sort=top puts the post with a like and a reply first');
const brew2 = await call('GET', '/biz/biz-brew92', { user: null, expect: 200 });
check(brew2.items.find((i) => i.id === 'brew92-v60').discussions === 2 && brew2.items.find((i) => i.id === 'brew92-flatwhite').discussions === 1, 'product cards get discussion counts', JSON.stringify(brew2.items.map((i) => [i.id, i.discussions]).filter((x) => x[1])));
// تفاعلات الضغط المطوّل
check((await call('GET', '/biz/community/status', { user: null, expect: 200 })).reactions.length === 8, 'status lists 8 reactions');
await call('POST', `/biz/biz-brew92/community/${qp.id}/react`, { body: { emoji: '🤖' }, expect: 400 });
let rx = await call('POST', `/biz/biz-brew92/community/${qp.id}/react`, { body: { emoji: '😂' }, expect: 200 });
check(rx.reactions.length === 1 && rx.reactions[0].emoji === '😂' && rx.reactions[0].count === 1 && rx.reactions[0].mine === true, 'react on a post', JSON.stringify(rx.reactions));
rx = await call('POST', `/biz/biz-brew92/community/${qp.id}/react`, { body: { emoji: '😂' }, user: 'SA0000002', expect: 200 });
rx = await call('POST', `/biz/biz-brew92/community/${qp.id}/react`, { body: { emoji: '🔥' }, user: 'SA0000003', expect: 200 });
check(rx.reactions.length === 2 && rx.reactions[0].emoji === '😂' && rx.reactions[0].count === 2 && rx.reactions[1].emoji === '🔥' && rx.reactions[1].mine === true, 'reactions aggregated and ordered by count', JSON.stringify(rx.reactions));
rx = await call('POST', `/biz/biz-brew92/community/${qp.id}/react`, { body: { emoji: '👏' }, expect: 200 });
check(rx.reactions.find((r) => r.emoji === '😂').count === 1 && rx.reactions.find((r) => r.emoji === '👏').mine === true, 'a new emoji replaces my previous reaction');
rx = await call('POST', `/biz/biz-brew92/community/${qp.id}/react`, { body: { emoji: '👏' }, expect: 200 });
check(!rx.reactions.some((r) => r.emoji === '👏'), 'same emoji again removes it');
rx = await call('POST', `/biz/biz-brew92/community/${qp.id}/react`, { body: { emoji: '' }, user: 'SA0000003', expect: 200 });
check(!rx.reactions.some((r) => r.emoji === '🔥') && rx.reactions.length === 1, 'empty emoji removes');
bf = await call('GET', '/biz/biz-brew92/community', { user: 'SA0000002', expect: 200 });
check(JSON.stringify(bf.posts.find((p) => p.id === qp.id).reactions) === JSON.stringify([{ emoji: '😂', count: 1, mine: true }]), 'feed carries reactions with my state');
rx = await call('POST', `/biz/biz-brew92/community/${qp.id}/replies/${qr.id}/react`, { body: { emoji: '☕' }, expect: 200 });
check(rx.reactions[0].emoji === '☕' && (await call('GET', `/biz/biz-brew92/community/${qp.id}`, { expect: 200 })).replies[0].reactions[0].mine === true, 'reply reactions in thread');
await call('DELETE', `/biz/biz-brew92/community/${qp.id}`, { expect: 200 });
check((await pool.query('SELECT count(*)::int AS n FROM biz_community_reply_likes')).rows[0].n === 0, 'deleting a post removes reply hearts');
check((await pool.query('SELECT count(*)::int AS n FROM biz_community_reactions')).rows[0].n === 0, 'deleting a post removes post and reply reactions');
await call('DELETE', `/biz/biz-brew92/community/${qp2.id}`, { user: 'SA0000002', expect: 200 });

// ---- النشر والقائمة
await call('POST', '/biz/biz-kaia/community', { body: { text: 'hi' }, user: null, expect: 401 });
await call('POST', '/biz/nope-biz/community', { body: { text: 'hi' }, expect: 404 });
await call('POST', '/biz/biz-kaia/community', { body: { text: '   ' }, expect: 400 });
await call('POST', '/biz/biz-kaia/community', { body: { text: '', images: ['https://evil.example.com/x.jpg'] }, expect: 400 });
const p1 = await call('POST', '/biz/biz-kaia/community', { body: { topic: 'tip', text: 'الصالة الشمالية: استخدموا بوابات الجوازات الذكية توفّر وقتاً' }, expect: 200 });
check(p1.id && p1.topic === 'tip' && p1.user.id === 'SA0000001' && p1.user.nickname === 'amr' && p1.likes === 0 && p1.replies === 0 && p1.mine === true && p1.staff === false && p1.pinned === false, 'post created with author info', JSON.stringify(p1).slice(0, 200));
const p2 = await call('POST', '/biz/biz-kaia/community', { body: { images: ['https://www.naslife.app/chat/media/a.jpg', '/uploads/b.jpg', 'https://evil.example.com/c.jpg', 'https://naslife.app/files/d.png'] }, user: 'SA0000002', expect: 200 });
check(p2.topic === 'photo' && p2.images.length === 3 && p2.images.every((u) => u.startsWith('https://naslife.app/')) && !p2.images.some((u) => u.includes('evil')) && p2.audio === null, 'images: own media only, www stripped, photo topic by default', JSON.stringify(p2.images));
// حتى 10 صور: الحادية عشرة تُهمل
const many = await call('POST', '/biz/biz-kaia/community', { body: { text: 'جولة مصوّرة', images: Array.from({ length: 12 }, (_, i) => `/chat/media/g${i}.jpg`) }, user: 'SA0000002', expect: 200 });
check(many.images.length === 10 && many.images[9].endsWith('/g9.jpg'), 'images capped at 10', String(many.images.length));
await call('DELETE', `/biz/biz-kaia/community/${many.id}`, { user: 'SA0000002', expect: 200 });
// تسجيل صوتي بلا نص
await call('POST', '/biz/biz-kaia/community', { body: { audio: 'https://evil.example.com/v.m4a', audioMs: 4000 }, user: 'SA0000002', expect: 400 });
const voice = await call('POST', '/biz/biz-kaia/community', { body: { audio: '/chat/media/v1.m4a', audioMs: 4321.7 }, user: 'SA0000002', expect: 200 });
check(voice.audio === 'https://naslife.app/chat/media/v1.m4a' && voice.audioMs === 4322 && voice.topic === 'general' && voice.text === '', 'voice-only post stored with duration', JSON.stringify({ a: voice.audio, ms: voice.audioMs, t: voice.topic }));
await call('DELETE', `/biz/biz-kaia/community/${voice.id}`, { user: 'SA0000002', expect: 200 });
const p3 = await call('POST', '/biz/biz-kaia/community', { body: { topic: 'question', text: 'هل يوجد مصلى في صالة الحج؟' }, user: 'SA0000003', expect: 200 });
check(p3.topic === 'question', 'question posted');
const bogusTopic = await call('POST', '/biz/biz-kaia/community', { body: { topic: 'zzz', text: 'موضوع غير معروف' }, user: 'SA0000003', expect: 200 });
check(bogusTopic.topic === 'general', 'unknown topic falls back to general');
let feed = await call('GET', '/biz/biz-kaia/community', { user: null, expect: 200 });
check(feed.posts.length === 4 && feed.total === 4 && feed.members === 3 && feed.canModerate === false && feed.hasMore === false, 'feed lists 4 posts, 3 members', JSON.stringify({ n: feed.posts.length, total: feed.total, members: feed.members }));
check(feed.posts[0].id === bogusTopic.id && feed.posts.every((p) => p.mine === false && p.liked === false), 'newest first; anonymous sees mine=false');
feed = await call('GET', '/biz/biz-kaia/community?topic=photo', { expect: 200 });
check(feed.posts.length === 1 && feed.posts[0].id === p2.id, 'topic filter');
feed = await call('GET', '/biz/biz-kaia/community?limit=2', { expect: 200 });
check(feed.posts.length === 2 && feed.hasMore === true, 'limit + hasMore');
const page2 = await call('GET', `/biz/biz-kaia/community?limit=2&before=${encodeURIComponent(feed.posts[1].createdAt)}`, { expect: 200 });
check(page2.posts.length === 2 && page2.posts[0].id === p2.id && page2.posts[1].id === p1.id && page2.hasMore === true, 'before paging returns the older two', JSON.stringify(page2.posts.map((p) => p.id === p1.id ? 'p1' : p.id === p2.id ? 'p2' : '?')));
await call('GET', '/biz/biz-kaia/community?before=garbage', { expect: 400 });

// ---- الكلمات المحظورة
await call('POST', '/adminapi/settings', { body: { bannedWords: 'احتيال, نصب', reportThreshold: 2 }, user: 'SA0000004', expect: 200 });
let e = await call('POST', '/biz/biz-kaia/community', { body: { text: 'هذا إحتيال' }, expect: 400 });
check(e.error === 'banned-words' && e.word === 'احتيال', 'banned word rejected in post', JSON.stringify(e));
e = await call('POST', `/biz/biz-kaia/community/${p1.id}/replies`, { body: { text: 'نَصب!' }, user: 'SA0000002', expect: 400 });
check(e.error === 'banned-words', 'banned word rejected in reply');

// ---- الردود + الإشعار
await call('POST', `/biz/biz-kaia/community/${p1.id}/replies`, { body: { text: '' }, user: 'SA0000002', expect: 400 });
await call('POST', `/biz/biz-kaia/community/aaaaaaaa-0000-4000-8000-000000000000/replies`, { body: { text: 'x' }, expect: 404 });
const r1 = await call('POST', `/biz/biz-kaia/community/${p1.id}/replies`, { body: { text: 'شكراً، جربتها وفعلاً أسرع' }, user: 'SA0000002', expect: 200 });
check(r1.id && r1.postId === p1.id && r1.user.nickname === 'sara' && r1.mine === true, 'reply created', JSON.stringify(r1).slice(0, 160));
const r2 = await call('POST', `/biz/biz-kaia/community/${p1.id}/replies`, { body: { text: 'العفو' }, expect: 200 });
// رد صوتي وبصور
await call('POST', `/biz/biz-kaia/community/${p1.id}/replies`, { body: { audio: 'https://evil.example.com/x.m4a' }, user: 'SA0000003', expect: 400 });
const vr = await call('POST', `/biz/biz-kaia/community/${p1.id}/replies`, { body: { audio: 'https://www.naslife.app/chat/media/r1.m4a', audioMs: 2500, images: ['/chat/media/ri.jpg'] }, user: 'SA0000003', expect: 200 });
check(vr.audio === 'https://naslife.app/chat/media/r1.m4a' && vr.audioMs === 2500 && vr.images.length === 1 && vr.text === '', 'voice reply with an image', JSON.stringify({ a: vr.audio, ms: vr.audioMs, im: vr.images }));
check((await pool.query("SELECT body FROM app_notifications WHERE kind='community_reply' ORDER BY created_at DESC LIMIT 1")).rows[0].body.includes('تسجيل صوتي'), 'voice reply notification says voice');
await call('DELETE', `/biz/biz-kaia/community/${p1.id}/replies/${vr.id}`, { user: 'SA0000003', expect: 200 });
let notes = (await pool.query("SELECT user_id, kind, data FROM app_notifications ORDER BY created_at")).rows;
check(notes.some((n) => n.user_id === 'SA0000001' && n.kind === 'community_reply' && n.data.postId === p1.id && n.data.bizId === 'biz-kaia'), 'post author notified of reply');
check(!notes.some((n) => n.user_id === 'SA0000001' && n.kind === 'community_reply' && n.data.postId === p1.id && JSON.stringify(n).includes('العفو')), 'no notification for own reply');
let thread = await call('GET', `/biz/biz-kaia/community/${p1.id}`, { user: 'SA0000002', expect: 200 });
check(thread.post.replies === 2 && thread.replies.length === 2 && thread.replies[0].id === r1.id && thread.replies[0].mine === true && thread.replies[1].mine === false && thread.canModerate === false, 'thread with replies in order', JSON.stringify({ n: thread.replies.length }));
await call('DELETE', `/biz/biz-kaia/community/${p1.id}/replies/${r1.id}`, { user: 'SA0000003', expect: 403 });
await call('DELETE', `/biz/biz-kaia/community/${p1.id}/replies/${r1.id}`, { user: 'SA0000002', expect: 200 });
check((await call('GET', `/biz/biz-kaia/community/${p1.id}`, { expect: 200 })).replies.length === 1, 'reply author can delete own reply');

// ---- الإعجاب
let lk = await call('POST', `/biz/biz-kaia/community/${p1.id}/like`, { user: 'SA0000002', expect: 200 });
check(lk.liked === true && lk.likes === 1, 'like');
lk = await call('POST', `/biz/biz-kaia/community/${p1.id}/like`, { user: 'SA0000003', expect: 200 });
check(lk.likes === 2, 'second like');
lk = await call('POST', `/biz/biz-kaia/community/${p1.id}/like`, { user: 'SA0000002', expect: 200 });
check(lk.liked === false && lk.likes === 1, 'unlike toggles');
feed = await call('GET', '/biz/biz-kaia/community', { user: 'SA0000003', expect: 200 });
check(feed.posts.find((p) => p.id === p1.id).liked === true && feed.posts.find((p) => p.id === p1.id).likes === 1, 'feed shows liked state');

// ---- إشعار الطاقم بالأسئلة، والتثبيت/الإخفاء للإدارة فقط
await call('POST', `/biz/biz-kaia/community/${p1.id}/pin`, { body: { pinned: true }, user: 'SA0000002', expect: 403 });
await call('POST', `/biz/biz-kaia/community/${p1.id}/hide`, { body: { hidden: true }, user: 'SA0000002', expect: 403 });
await pool.query("UPDATE biz SET owner_id='SA0000004' WHERE id='biz-kaia'");
await pool.query("INSERT INTO biz_staff(biz_id,user_id,role) VALUES('biz-kaia','SA0000003','staff') ON CONFLICT DO NOTHING");
const q2 = await call('POST', '/biz/biz-kaia/community', { body: { topic: 'alert', text: 'ازدحام شديد عند بوابة الجوازات الآن' }, user: 'SA0000002', expect: 200 });
notes = (await pool.query("SELECT user_id, kind, data FROM app_notifications WHERE kind='community_post'")).rows;
check(notes.some((n) => n.user_id === 'SA0000004' && n.data.postId === q2.id) && notes.some((n) => n.user_id === 'SA0000003' && n.data.postId === q2.id) && !notes.some((n) => n.user_id === 'SA0000002'), 'owner and staff notified of alert, not the author', JSON.stringify(notes.map((n) => n.user_id)));
feed = await call('GET', '/biz/biz-kaia/community', { user: 'SA0000004', expect: 200 });
check(feed.canModerate === true, 'owner can moderate');
const staffPost = await call('POST', '/biz/biz-kaia/community', { body: { topic: 'general', text: 'أهلاً بكم في مساحة المطار، نرد على استفساراتكم هنا' }, user: 'SA0000003', expect: 200 });
check(staffPost.staff === true, 'staff post carries staff badge');
let pinned = await call('POST', `/biz/biz-kaia/community/${staffPost.id}/pin`, { body: { pinned: true }, user: 'SA0000003', expect: 200 });
check(pinned.pinned === true, 'staff pinned the welcome post');
feed = await call('GET', '/biz/biz-kaia/community', { user: null, expect: 200 });
check(feed.posts[0].id === staffPost.id && feed.posts[0].pinned === true && feed.posts[0].staff === true && feed.posts[1].id === q2.id, 'pinned post first, then newest', JSON.stringify(feed.posts.slice(0, 2).map((p) => [p.pinned, p.staff])));
feed = await call('GET', `/biz/biz-kaia/community?limit=3&before=${encodeURIComponent(feed.posts[2].createdAt)}`, { user: null, expect: 200 });
check(!feed.posts.some((p) => p.id === staffPost.id), 'pinned not repeated on later pages');
await call('POST', `/biz/biz-kaia/community/${staffPost.id}/pin`, { body: { pinned: false }, user: 'SA0000004', expect: 200 });
const hid = await call('POST', `/biz/biz-kaia/community/${bogusTopic.id}/hide`, { body: { hidden: true }, user: 'SA0000004', expect: 200 });
check(hid.hidden === true, 'owner hides a post');
feed = await call('GET', '/biz/biz-kaia/community', { user: 'SA0000002', expect: 200 });
check(!feed.posts.some((p) => p.id === bogusTopic.id), 'hidden post gone for others');
feed = await call('GET', '/biz/biz-kaia/community', { user: 'SA0000003', expect: 200 });
check(feed.posts.some((p) => p.id === bogusTopic.id && p.hidden === true) && feed.posts.filter((p) => p.hidden).length === 1, 'author and moderators still see hidden post');
check(feed.total === 5, 'total excludes hidden', String(feed.total));
await call('GET', `/biz/biz-kaia/community/${bogusTopic.id}`, { user: 'SA0000002', expect: 404 });
await call('GET', `/biz/biz-kaia/community/${bogusTopic.id}`, { user: 'SA0000003', expect: 200 });
await call('POST', `/biz/biz-kaia/community/${bogusTopic.id}/like`, { user: 'SA0000002', expect: 404 });
notes = (await pool.query("SELECT user_id, kind, data FROM app_notifications WHERE kind='community_hidden'")).rows;
check(notes.some((n) => n.user_id === 'SA0000003' && n.data.postId === bogusTopic.id), 'author notified of hide');
await call('POST', `/biz/biz-kaia/community/${bogusTopic.id}/hide`, { body: { hidden: false }, user: 'SA0000004', expect: 200 });
check((await call('GET', '/biz/biz-kaia/community', { user: 'SA0000002', expect: 200 })).posts.some((p) => p.id === bogusTopic.id), 'unhide restores');

// ---- تصفية المحظورين
await pool.query("INSERT INTO user_blocks(user_id, blocked_id) VALUES('SA0000001','SA0000003')");
feed = await call('GET', '/biz/biz-kaia/community', { expect: 200 });
check(!feed.posts.some((p) => p.user.id === 'SA0000003') && feed.posts.length === 3, 'blocked users hidden from my feed', String(feed.posts.length));
await call('POST', `/biz/biz-kaia/community/${p1.id}/replies`, { body: { text: 'رد من محظور' }, user: 'SA0000003', expect: 200 });
thread = await call('GET', `/biz/biz-kaia/community/${p1.id}`, { expect: 200 });
check(!thread.replies.some((r) => r.user.id === 'SA0000003') && thread.replies.length === 1, 'blocked user replies hidden from me');
await pool.query('DELETE FROM user_blocks');

// ---- البلاغات مع الإخفاء التلقائي (العتبة 2)
await call('POST', '/safety/report', { body: { targetType: 'community', targetId: p3.id }, user: 'SA0000003', expect: 400 });
await call('POST', '/safety/report', { body: { targetType: 'community', targetId: 'aaaaaaaa-0000-4000-8000-000000000000' }, expect: 404 });
let rep = await call('POST', '/safety/report', { body: { targetType: 'community', targetId: p3.id, reason: 'مخالف' }, expect: 200 });
check(rep.reports === 1 && rep.hidden === false, 'first report counted', JSON.stringify(rep));
rep = await call('POST', '/safety/report', { body: { targetType: 'community', targetId: p3.id }, user: 'SA0000002', expect: 200 });
check(rep.reports === 2 && rep.hidden === true, 'threshold reached → auto hidden', JSON.stringify(rep));
const row = (await pool.query('SELECT hidden, hidden_by FROM biz_community_posts WHERE id=$1', [p3.id])).rows[0];
check(row.hidden === true && row.hidden_by === 'auto', 'hidden_by=auto');
notes = (await pool.query("SELECT user_id, kind, data FROM app_notifications WHERE kind IN ('community_hidden','content_autohidden')")).rows;
check(notes.some((n) => n.user_id === 'SA0000003' && n.kind === 'community_hidden' && n.data.reason === 'reports') && notes.some((n) => n.user_id === 'SA0000004' && n.kind === 'content_autohidden' && n.data.targetType === 'community'), 'author + admins notified of auto hide');
await call('GET', `/biz/biz-kaia/community/${p3.id}`, { user: 'SA0000002', expect: 404 });

// ---- الحذف
await call('DELETE', `/biz/biz-kaia/community/${p1.id}`, { user: 'SA0000002', expect: 403 });
await call('DELETE', `/biz/biz-kaia/community/${p1.id}`, { expect: 200 });
await call('GET', `/biz/biz-kaia/community/${p1.id}`, { expect: 404 });
check((await pool.query('SELECT count(*)::int AS n FROM biz_community_replies WHERE post_id=$1', [p1.id])).rows[0].n === 0 && (await pool.query('SELECT count(*)::int AS n FROM biz_community_likes WHERE post_id=$1', [p1.id])).rows[0].n === 0, 'delete cascades replies + likes');
await call('DELETE', `/biz/biz-kaia/community/${p2.id}`, { user: 'SA0000004', expect: 200 });
check(!(await call('GET', '/biz/biz-kaia/community', { expect: 200 })).posts.some((p) => p.id === p2.id), 'owner deleted another user post');

// ---- الحدّ الساعي 20
for (let i = 0; i < 19; i++) await call('POST', '/biz/biz-kaia/community', { body: { text: `رسالة ${i}` }, user: 'SA0000002' });
const lim = await call('POST', '/biz/biz-kaia/community', { body: { text: 'زيادة' }, user: 'SA0000002', expect: 429 });
check(lim.error === 'too-many', 'rate limited at 20/hour');
// ---- الموقوف
await pool.query("CREATE TABLE IF NOT EXISTS user_flags (user_id TEXT PRIMARY KEY, suspended BOOLEAN DEFAULT false)");
await pool.query("INSERT INTO user_flags(user_id, suspended) VALUES('SA0000001', true) ON CONFLICT (user_id) DO UPDATE SET suspended=true");
await call('POST', '/biz/biz-kaia/community', { body: { text: 'موقوف' }, expect: 403 });
await pool.query("UPDATE user_flags SET suspended=false WHERE user_id='SA0000001'");

await pool.query("UPDATE biz SET owner_id=NULL WHERE id='biz-kaia'"); await pool.query("DELETE FROM biz_staff WHERE biz_id='biz-kaia'");
await pool.query('DROP TABLE IF EXISTS biz_community_posts, biz_community_replies, biz_community_likes');
await app.close(); await pool.end();
console.log(fails ? `\n${fails} FAILED` : '\nALL COMMUNITY TESTS PASSED');
process.exit(fails ? 1 : 0);
