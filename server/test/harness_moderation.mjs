// اختبارات الإشراف (App Store 1.2): أنواع البلاغ الجديدة مع الإخفاء التلقائي وإشعار الصاحب واختفائها من القراءة العامة،
// طابور الإشراف /adminapi/moderation وإجراءاته (تجاهل، إخفاء، إعادة، إيقاف الصاحب من المحتوى نفسه)، فلتر الكلمات والإيقاف
// على مسارات الإنشاء والتعديل، تصفية المحظورين في السوق والدوائر والفعاليات والبحث والروابط المباشرة، بلاغات النواة المثبّتة
// على جدول reports، ومراقبة content_reports في notify.js.
import Fastify from 'fastify';
import pg from 'pg';
import crypto from 'node:crypto';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0'; process.env.NODE_ENV = 'test';
let fails = 0;
const check = (cond, label, extra = '') => { if (!cond) fails++; console.log((cond ? 'OK  ' : 'FAIL') + ' ' + label + (extra ? ' ' + extra : '')); };
const ADMIN = 'SA0000211', AUTHOR = 'SA0000212', R1 = 'SA0000213', R2 = 'SA0000214', R3 = 'SA0000215', SUSP = 'SA0000216', PRIV = 'SA0000217';
const OURS = [ADMIN, AUTHOR, R1, R2, R3, SUSP, PRIV];

const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("ALTER TABLE users ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now()");
await pool.query(`INSERT INTO users(id,nickname,created_at) VALUES('${ADMIN}','modadmin',now()-interval '60 days'),('${AUTHOR}','monamod',now()-interval '60 days'),('${R1}','ramimod',now()-interval '60 days'),
  ('${R2}','hudamod',now()-interval '60 days'),('${R3}','ziadmod',now()-interval '60 days'),('${SUSP}','suspmod',now()-interval '60 days'),('${PRIV}','privymod',now()-interval '60 days')
  ON CONFLICT (id) DO UPDATE SET nickname=EXCLUDED.nickname, created_at=EXCLUDED.created_at`);
await pool.query("CREATE TABLE IF NOT EXISTS user_blocks (user_id TEXT NOT NULL, blocked_id TEXT NOT NULL, created_at TIMESTAMPTZ DEFAULT now(), PRIMARY KEY (user_id, blocked_id))");
await pool.query("CREATE TABLE IF NOT EXISTS reports (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), reporter_id TEXT, target_id TEXT, reason TEXT, created_at TIMESTAMPTZ DEFAULT now())");
// الملف الخاص يُكتشف في search.js عند التسجيل؛ وتعليقات الدوائر في النواة يُكتشف جدولها في vessel_mod.js
await pool.query("DROP TABLE IF EXISTS profiles; CREATE TABLE profiles (user_id TEXT PRIMARY KEY, bio TEXT NOT NULL DEFAULT '', is_public BOOLEAN NOT NULL DEFAULT true)");
await pool.query("DROP TABLE IF EXISTS comments; CREATE TABLE comments (id UUID PRIMARY KEY, post_id UUID NOT NULL, author_id TEXT NOT NULL, content TEXT NOT NULL DEFAULT '')");
// دوائر النواة (بنية harness_search نفسها) لبلاغ «vessel»
await pool.query("CREATE TABLE IF NOT EXISTS vessels (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), name TEXT, topic TEXT, kind TEXT DEFAULT 'general', is_public BOOLEAN DEFAULT true, owner_id TEXT, created_at TIMESTAMPTZ DEFAULT now())");
const ids = `('${OURS.join("','")}')`;
for (const sql of ['DELETE FROM content_reports', 'DELETE FROM content_report_actions', `DELETE FROM user_blocks WHERE user_id IN ${ids} OR blocked_id IN ${ids}`, `DELETE FROM user_flags WHERE user_id IN ${ids}`,
  `DELETE FROM app_notifications WHERE user_id IN ${ids}`, `DELETE FROM biz_reviews WHERE user_id IN ${ids}`, `DELETE FROM biz WHERE owner_id IN ${ids}`, `DELETE FROM market_listings WHERE seller_id IN ${ids}`,
  `DELETE FROM market_wanted WHERE user_id IN ${ids}`, `DELETE FROM events WHERE host_id IN ${ids}`, `DELETE FROM map_posts WHERE user_id IN ${ids}`, `DELETE FROM market_reviews WHERE buyer_id IN ${ids}`,
  'DELETE FROM vessel_comment_mod', `DELETE FROM admins WHERE user_id IN ${ids}`, `DELETE FROM vessels WHERE owner_id IN ${ids}`, "DELETE FROM content_prev_state WHERE target_type='vessel'"]) { try { await pool.query(sql); } catch { /* أول تشغيل */ } }

const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
const dir = new URL('.', import.meta.url).pathname;
app.register((await import('../notify.js')).default, { pool, auth, pollMs: 3600000, opsDir: dir + 'ops' });
app.register((await import('../commerce.js')).default, { pool, auth });
app.register((await import('../business.js')).default, { pool, auth });
app.register((await import('../biz_community.js')).default, { pool, auth });
app.register((await import('../search.js')).default, { pool, auth });
app.register((await import('../map_posts.js')).default, { pool, auth });
app.register((await import('../safety.js')).default, { pool, auth });
app.register((await import('../admin.js')).default, { pool, auth, webappDir: dir + 'webapp', opsDir: dir + 'ops' });
app.register((await import('../vessel_mod.js')).default, { pool, auth });
app.register((await import('../market_plus.js')).default, { pool, auth });
await app.ready(); await new Promise((r) => setTimeout(r, 300));
await pool.query("INSERT INTO admins(user_id,granted_by) VALUES($1,'test') ON CONFLICT DO NOTHING", [ADMIN]);
const call = async (method, url, { body = {}, user = AUTHOR, expect, headers = {} } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json', host: 'naslife.app', ...headers }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url.slice(0, 90)} -> ${r.statusCode}`, r.statusCode === expect ? '' : JSON.stringify(j).slice(0, 200));
  return j;
};
const noted = async (user, kind, pred = () => true) => (await pool.query("SELECT kind, data FROM app_notifications WHERE user_id=$1 AND kind=$2 ORDER BY created_at DESC", [user, kind])).rows.find((r) => pred(r.data ?? {})) ?? null;
const suspendedIn = async (id) => (await pool.query("SELECT suspended FROM user_flags WHERE user_id=$1", [id])).rows[0]?.suspended === true;
const tomorrow = new Date(Date.now() + 86400000).toISOString();
await call('POST', '/adminapi/settings', { body: { bannedWords: 'احتيال', reportThreshold: 3, bannedWordsDefault: true, marketReviewNewAccounts: false, testTopup: true }, user: ADMIN, expect: 200 });
await globalThis.naslifeNotifyPollReports?.(); // يثبّت نقطة البداية لمصدري البلاغات
const ns = await call('GET', '/notify/status', { user: null, expect: 200 });
check(ns.reports.table === 'reports' && ns.reports.sources.includes('content_reports'), 'notify pins core reports and also watches content_reports', JSON.stringify(ns.reports));

// ================= فلتر الكلمات على مسارات الإنشاء والتعديل =================
let e = await call('POST', '/biz', { body: { nameAr: 'متجر احتيال', lat: 21.5, lng: 39.2 }, expect: 400 });
check(e.error === 'banned-words', 'POST /biz name filtered');
e = await call('POST', '/biz', { body: { nameAr: 'مقهى منى', description: 'يا شرموطة', lat: 21.5, lng: 39.2 }, expect: 400 });
check(e.error === 'banned-words' && e.word === 'شرموطه', 'POST /biz description filtered by the default seed');
const B1 = await call('POST', '/biz', { body: { name: 'Mona Mod Cafe', nameAr: 'مقهى منى', description: 'قهوة مختصة', lat: 21.5, lng: 39.2 }, expect: 200 });
check(!!B1.id, 'biz created', B1.id);
await call('PATCH', `/biz/${B1.id}`, { body: { description: 'احتيال' }, expect: 400 });
await call('PATCH', `/biz/${B1.id}`, { body: { highlights: ['fuck'] }, expect: 400 });
await call('PATCH', `/biz/${B1.id}`, { body: { description: 'أجود القهوة' }, expect: 200 });
await call('POST', `/biz/${B1.id}/items`, { body: { title: 'احتيال', price: 1000 }, expect: 400 });
const item = await call('POST', `/biz/${B1.id}/items`, { body: { title: 'قهوة', price: 1000 }, expect: 200 });
await call('PATCH', `/biz/${B1.id}/items/${item.id}`, { body: { description: 'احتيال' }, expect: 400 });
const bp = await call('POST', `/biz/${B1.id}/posts`, { body: { title: 'افتتاح', body: 'افتتحنا فرعاً جديداً' }, expect: 200 });
await call('PATCH', `/biz/${B1.id}/posts/${bp.id}`, { body: { body: 'احتيال' }, expect: 400 });
const B2 = await call('POST', '/biz', { body: { name: 'Rami Mod Shop', nameAr: 'متجر رامي', lat: 21.51, lng: 39.21 }, user: R1, expect: 200 });
await call('POST', `/biz/${B2.id}/reviews`, { body: { rating: 4, text: 'ممتاز' }, expect: 200 });
await call('POST', `/biz/${B2.id}/reviews/${AUTHOR}/reply`, { body: { text: 'احتيال' }, user: R1, expect: 400 });
await call('POST', `/biz/${B2.id}/reviews/${AUTHOR}/reply`, { body: { text: 'شكراً لك' }, user: R1, expect: 200 });
// الفعاليات: النصوص وأسماء الفئات، والفعالية المدفوعة تحتاج مكاناً
await call('POST', '/events', { body: { title: 'احتيال كبير', startsAt: tomorrow }, expect: 400 });
e = await call('POST', '/events', { body: { title: 'أمسية', startsAt: tomorrow, tiers: [{ name: 'fuck', price: 0, quantity: 5 }] }, expect: 400 });
check(e.error === 'banned-words', 'event tier name filtered');
e = await call('POST', '/events', { body: { title: 'أمسية', startsAt: tomorrow, tiers: [{ name: 'عادي', price: 1000, quantity: 5 }] }, expect: 400 });
check(e.error === 'place-required', 'paid event without a place refused');
await call('POST', '/events', { body: { title: 'لقاء مجاني', startsAt: tomorrow }, expect: 200 });
await call('POST', '/events', { body: { title: 'لقاء بإحداثيات', startsAt: tomorrow, lat: 21.5, lng: 39.2, tiers: [{ name: 'عادي', price: 500, quantity: 5 }] }, expect: 200 });
const EV = await call('POST', '/events', { body: { title: 'أمسية منى', startsAt: tomorrow, placeName: 'الكورنيش', tiers: [{ name: 'عادي', price: 1000, quantity: 5 }] }, expect: 200 });
// السوق: إجابة السؤال ورد البائع على التقييم
const LR1 = await call('POST', '/market', { body: { kind: 'product', category: 'food', title: 'كعك رامي', price: 500 }, user: R1, expect: 200 });
const Q = await call('POST', `/market/${LR1.id}/questions`, { body: { text: 'هل يتوفر توصيل؟' }, expect: 200 });
await call('POST', `/market/questions/${Q.id}/answer`, { body: { text: 'احتيال' }, user: R1, expect: 400 });
await call('POST', `/market/questions/${Q.id}/answer`, { body: { text: 'نعم يتوفر' }, user: R1, expect: 200 });
const ORD = crypto.randomUUID();
await pool.query("INSERT INTO market_reviews(order_id,listing_id,seller_id,buyer_id,rating,text) VALUES($1,$2,$3,$4,5,'رائع جداً')", [ORD, LR1.id, R1, AUTHOR]);
await call('POST', `/market/reviews/${ORD}/reply`, { body: { text: 'احتيال' }, user: R1, expect: 400 });
await call('POST', `/market/reviews/${ORD}/reply`, { body: { text: 'شكراً' }, user: R1, expect: 200 });
const W = await call('POST', '/market/wanted', { body: { title: 'أبحث عن دراجة' }, expect: 200 });
const WR1 = await call('POST', '/market/wanted', { body: { title: 'أبحث عن كرسي' }, user: R1, expect: 200 });
const WR = await call('POST', `/market/wanted/${WR1.id}/replies`, { body: { text: 'عندي كرسي', price: 5000 }, expect: 200 });

// ================= الحساب الموقوف لا ينشر =================
await pool.query("INSERT INTO user_flags(user_id,suspended,note) VALUES($1,true,'test') ON CONFLICT (user_id) DO UPDATE SET suspended=true", [SUSP]);
check(await globalThis.naslifeIsSuspended?.(SUSP) === true && await globalThis.naslifeIsSuspended?.(R1) === false, 'admin.js exports naslifeIsSuspended');
for (const [m, u, b] of [['POST', '/biz', { nameAr: 'دائرة موقوف', lat: 21.5, lng: 39.2 }], ['POST', '/events', { title: 'فعالية موقوف', startsAt: tomorrow }], ['POST', `/biz/${B2.id}/reviews`, { rating: 1, text: 'سيئ' }],
  ['POST', `/market/${LR1.id}/questions`, { text: 'سؤال من موقوف' }], ['POST', '/market/wanted', { title: 'أبحث عن شيء' }], ['POST', `/market/wanted/${WR1.id}/replies`, { text: 'عندي' }], ['POST', `/market/orders/${ORD}/review`, { rating: 5 }]]) {
  e = await call(m, u, { body: b, user: SUSP, expect: 403 });
  check(e.error === 'suspended', `suspended user refused on ${u.replace(/[0-9a-f-]{36}/g, ':id')}`);
}

// ================= تصفية المحظورين (huda حظرت منى) =================
await pool.query('INSERT INTO user_blocks(user_id,blocked_id) VALUES($1,$2)', [R2, AUTHOR]);
const MP = await call('POST', '/mapposts', { body: { kind: 'text', bg: '#000000', caption: 'منشور منى', lat: 21.5, lng: 39.2 }, expect: 200 });
await call('GET', `/mapposts/${MP.id}`, { user: R2, expect: 404 });
await call('GET', `/mapposts/${MP.id}`, { user: R1, expect: 200 });
check(!(await call('GET', `/market/${LR1.id}/questions`, { user: R2, expect: 200 })).some((x) => x.id === Q.id) && (await call('GET', `/market/${LR1.id}/questions`, { user: R1, expect: 200 })).some((x) => x.id === Q.id), 'questions exclude blocked authors');
check(!(await call('GET', `/market/${LR1.id}/reviews`, { user: R2, expect: 200 })).some((x) => x.orderId === ORD) && (await call('GET', `/market/${LR1.id}/reviews`, { user: null, expect: 200 })).some((x) => x.orderId === ORD), 'reviews exclude blocked authors');
check(!(await call('GET', '/market/wanted', { user: R2, expect: 200 })).some((x) => x.id === W.id) && (await call('GET', '/market/wanted', { user: R1, expect: 200 })).some((x) => x.id === W.id), 'wanted list excludes blocked authors');
await call('GET', `/market/wanted/${W.id}`, { user: R2, expect: 404 });
check(!(await call('GET', `/market/wanted/${WR1.id}`, { user: R2, expect: 200 })).replyList.some((x) => x.id === WR.id) && (await call('GET', `/market/wanted/${WR1.id}`, { user: R1, expect: 200 })).replyList.some((x) => x.id === WR.id), 'wanted replies exclude blocked authors');
const LA = await call('POST', '/market', { body: { kind: 'product', category: 'other', title: 'ساعة منى', price: 1500 }, expect: 200 });
check(!(await call('GET', '/market?limit=100', { user: R2, expect: 200 })).some((x) => x.seller.id === AUTHOR) && (await call('GET', `/market?seller=${AUTHOR}`, { user: R1, expect: 200 })).some((x) => x.id === LA.id), 'market list excludes blocked sellers');
await call('GET', `/market/${LA.id}`, { user: R2, expect: 404 });
await call('GET', `/market/sellers/${AUTHOR}`, { user: R2, expect: 404 });
check(!(await call('GET', `/biz/${B2.id}`, { user: R2, expect: 200 })).reviews.some((x) => x.user.id === AUTHOR) && (await call('GET', `/biz/${B2.id}`, { user: null, expect: 200 })).reviews.some((x) => x.user.id === AUTHOR), 'biz reviews exclude blocked authors');
check(!(await call('GET', '/events', { user: R2, expect: 200 })).some((x) => x.id === EV.id), 'events exclude blocked hosts');
await call('GET', `/events/${EV.id}`, { user: R2, expect: 404 });
let ppl = await call('GET', '/search?q=monamod&type=people', { user: R2, expect: 200 });
check(!ppl.people.some((x) => x.id === AUTHOR), 'people search excludes blocked users');
ppl = await call('GET', '/search?q=monamod&type=people', { user: R1, expect: 200 });
check(ppl.people.some((x) => x.id === AUTHOR), 'people search finds unblocked users');
await pool.query("INSERT INTO profiles(user_id,is_public) VALUES($1,false)", [PRIV]);
check(!(await call('GET', '/search?q=privymod&type=people', { user: R1, expect: 200 })).people.some((x) => x.id === PRIV), 'people search hides private profiles');
check((await call('GET', '/search?q=privymod&type=people', { user: PRIV, expect: 200 })).people.some((x) => x.id === PRIV), 'private profile still finds itself');
check(!(await call('GET', '/search?q=privymod&type=people', { user: null, expect: 200 })).people.some((x) => x.id === PRIV), 'guest search hides private profiles');
await pool.query('DELETE FROM user_blocks WHERE user_id=$1', [R2]);

// ================= أنواع البلاغ الجديدة: الإخفاء التلقائي عند 3 مبلّغين، الاختفاء من القراءة العامة، وإشعار الصاحب =================
const report3 = async (type, id) => { let r; for (const u of [R1, R2, R3]) r = await call('POST', '/safety/report', { body: { targetType: type, targetId: id, reason: 'مسيء' }, user: u, expect: 200 }); return r; };
const hiddenNote = (type) => noted(AUTHOR, 'content_hidden', (d) => d.targetType === type && d.reason === 'reports');
await call('POST', '/safety/report', { body: { targetType: 'event', targetId: EV.id }, user: AUTHOR, expect: 400 }); // محتواه
await call('POST', '/safety/report', { body: { targetType: 'biz-review', targetId: `${B2.id}:SA0000999` }, user: R1, expect: 404 });
await call('POST', '/safety/report', { body: { targetType: 'biz', targetId: 'NOT A SLUG' }, user: R1, expect: 404 });
// رد في مساحة الدائرة
const CP = await call('POST', `/biz/${B2.id}/community`, { body: { text: 'مرحبا بالجميع' }, user: R1, expect: 200 });
const CR = await call('POST', `/biz/${B2.id}/community/${CP.id}/replies`, { body: { text: 'أهلاً بك' }, expect: 200 });
let rep = await report3('community-reply', CR.id);
check(rep.hidden === true && rep.reports === 3, 'community-reply auto-hidden at threshold', JSON.stringify(rep));
check(!(await call('GET', `/biz/${B2.id}/community/${CP.id}`, { user: R2, expect: 200 })).replies.some((x) => x.id === CR.id), 'hidden community reply gone from the thread');
check(!!(await hiddenNote('community-reply')), 'owner notified (community-reply)');
// سؤال على عرض
rep = await report3('listing-question', Q.id);
check(rep.hidden === true, 'listing-question auto-hidden');
check(!(await call('GET', `/market/${LR1.id}/questions`, { user: R1, expect: 200 })).some((x) => x.id === Q.id), 'hidden question gone for others');
check((await call('GET', `/market/${LR1.id}/questions`, { expect: 200 })).some((x) => x.id === Q.id), 'author still sees own hidden question');
check(!!(await hiddenNote('listing-question')), 'owner notified (listing-question)');
// تقييم في السوق
rep = await report3('listing-review', ORD);
check(rep.hidden === true && !(await call('GET', `/market/${LR1.id}/reviews`, { user: null, expect: 200 })).some((x) => x.orderId === ORD), 'listing-review auto-hidden and gone from reviews');
check((await pool.query('SELECT rating_count FROM market_listings WHERE id=$1', [LR1.id])).rows[0].rating_count === 0, 'hidden review leaves the listing rating');
check(!!(await hiddenNote('listing-review')), 'owner notified (listing-review)');
// طلب «أبحث عن»
rep = await report3('wanted', W.id);
check(rep.hidden === true, 'wanted auto-hidden');
await call('GET', `/market/wanted/${W.id}`, { user: R1, expect: 404 });
await call('GET', `/market/wanted/${W.id}`, { expect: 200 });
await call('PATCH', `/market/wanted/${W.id}`, { body: { status: 'open' }, expect: 200 });
check((await pool.query('SELECT status FROM market_wanted WHERE id=$1', [W.id])).rows[0].status === 'blocked', 'owner cannot reopen a moderated request');
check(!!(await hiddenNote('wanted')), 'owner notified (wanted)');
// رد على طلب
rep = await report3('wanted-reply', WR.id);
check(rep.hidden === true && !(await call('GET', `/market/wanted/${WR1.id}`, { user: R1, expect: 200 })).replyList.some((x) => x.id === WR.id), 'wanted-reply auto-hidden and gone');
check(!!(await hiddenNote('wanted-reply')), 'owner notified (wanted-reply)');
// تقييم دائرة
rep = await report3('biz-review', `${B2.id}:${AUTHOR}`);
let bz = await call('GET', `/biz/${B2.id}`, { user: null, expect: 200 });
check(rep.hidden === true && !bz.reviews.some((x) => x.user.id === AUTHOR), 'biz-review auto-hidden and gone from the biz page');
check(!!(await hiddenNote('biz-review')), 'owner notified (biz-review)');
// خبر دائرة
rep = await report3('biz-post', bp.id);
check(rep.hidden === true && !(await call('GET', `/biz/${B1.id}`, { user: null, expect: 200 })).posts.some((x) => x.id === bp.id), 'biz-post auto-hidden and gone from the biz page');
check(!!(await hiddenNote('biz-post')), 'owner notified (biz-post)');
// فعالية
rep = await report3('event', EV.id);
check(rep.hidden === true && !(await call('GET', '/events', { user: null, expect: 200 })).some((x) => x.id === EV.id), 'event auto-hidden and gone from the list');
await call('GET', `/events/${EV.id}`, { user: null, expect: 404 });
await call('GET', `/events/${EV.id}`, { expect: 200 });
await call('POST', `/events/${EV.id}/tickets`, { body: { tierId: EV.tiers[0].id, qty: 1 }, user: R1, expect: 404 });
check(!!(await hiddenNote('event')), 'owner notified (event)');
// تعليق في دائرة (النواة)
const C1 = crypto.randomUUID();
await pool.query("INSERT INTO comments(id,post_id,author_id,content) VALUES($1,$2,$3,'تعليق مزعج')", [C1, crypto.randomUUID(), AUTHOR]);
rep = await report3('vessel-comment', C1);
check(rep.hidden === true && (await call('GET', '/posts/hidden?kind=comment', { user: R1, expect: 200 })).ids.includes(C1), 'vessel-comment auto-hidden and listed in /posts/hidden?kind=comment');
check(!(await call('GET', '/posts/hidden', { user: R1, expect: 200 })).ids.includes(C1), 'comment ids stay out of the posts list');
check(!!(await hiddenNote('vessel-comment')), 'owner notified (vessel-comment)');
// الدائرة نفسها
rep = await report3('biz', B1.id);
check(rep.hidden === false && rep.reports === 3, 'biz is NOT auto-hidden by reports (queue only)', JSON.stringify(rep));
await call('GET', `/biz/${B1.id}`, { user: null, expect: 200 });
check(!!(await noted(ADMIN, 'content_reported_many', (d) => d.targetType === 'biz' && d.targetId === B1.id)), 'admins alerted when a circle reaches the threshold');
let bh = await call('POST', `/adminapi/moderation/biz/${B1.id}`, { body: { action: 'hide', note: 'مخالف' }, user: ADMIN, expect: 200 });
check(bh.changed === true, 'admin hides the circle from the queue');
await call('GET', `/biz/${B1.id}`, { user: null, expect: 404 });
check(!(await call('GET', '/biz?q=' + encodeURIComponent('مقهى منى'), { user: null, expect: 200 })).some((x) => x.id === B1.id), 'hidden biz gone from the list');
e = await call('PATCH', `/biz/${B1.id}`, { body: { active: true }, expect: 403 });
check(e.error === 'moderated', 'owner cannot re-activate a moderated biz');
check(!!(await noted(AUTHOR, 'content_hidden', (d) => d.targetType === 'biz' && d.reason === 'moderation')), 'owner notified (biz, by moderation)');
await globalThis.naslifeNotifyPollReports?.();
check(!!(await noted(ADMIN, 'content_reports_new', (d) => d.source === 'content_reports' && d.count >= 3)), 'admins get a push for new content reports');

// ================= طابور الإشراف =================
await call('GET', '/adminapi/moderation', { user: null, expect: 401 });
await call('GET', '/adminapi/moderation', { user: R1, expect: 403 });
let mq = await call('GET', '/adminapi/moderation', { user: ADMIN, expect: 200 });
const evItem = mq.items.find((i) => i.targetType === 'event' && i.targetId === EV.id);
check(evItem && evItem.reports === 3 && evItem.owner?.id === AUTHOR && evItem.owner.nickname === 'monamod' && evItem.hidden === true && evItem.title === 'أمسية منى' && evItem.reasons.includes('مسيء') && evItem.typeName === 'فعالية', 'queue groups reports with owner, preview and state', JSON.stringify(evItem));
check(mq.open >= 9 && mq.items.length === mq.open && mq.types.length === 15 && mq.types.some((t) => t.id === 'vessel' && t.name === 'دائرة'), 'open count and the 15 target types (with vessel)', `${mq.open}/${mq.items.length}`);
let a = await call('POST', `/adminapi/moderation/event/${EV.id}`, { body: { action: 'restore', note: 'لا مخالفة' }, user: ADMIN, expect: 200 });
check(a.changed === true && a.status === 'visible', 'restore brings the event back', JSON.stringify(a));
await call('GET', `/events/${EV.id}`, { user: null, expect: 200 });
check(!!(await noted(AUTHOR, 'content_restored', (d) => d.targetType === 'event')), 'owner told about the restore');
// الإعادة ترجع الحالة السابقة: عرض كان مسودة يبقى مسودة ولا يُنشر
const LD = await call('POST', '/market', { body: { kind: 'product', category: 'food', title: 'مسودة كعك', price: 700 }, user: R1, expect: 200 });
await pool.query("UPDATE market_listings SET status='draft' WHERE id=$1", [LD.id]);
await call('POST', `/adminapi/moderation/listing/${LD.id}`, { body: { action: 'hide' }, user: ADMIN, expect: 200 });
check((await pool.query('SELECT status FROM market_listings WHERE id=$1', [LD.id])).rows[0].status === 'blocked', 'hidden draft listing is blocked');
await call('POST', `/adminapi/moderation/listing/${LD.id}`, { body: { action: 'restore' }, user: ADMIN, expect: 200 });
check((await pool.query('SELECT status FROM market_listings WHERE id=$1', [LD.id])).rows[0].status === 'draft', 'restore returns the listing to draft, not active');
mq = await call('GET', '/adminapi/moderation', { user: ADMIN, expect: 200 });
check(!mq.items.some((i) => i.targetId === EV.id), 'acted item leaves the open queue');
mq = await call('GET', '/adminapi/moderation?status=all', { user: ADMIN, expect: 200 });
check(mq.items.find((i) => i.targetId === EV.id)?.action?.action === 'restore' && mq.items.find((i) => i.targetId === EV.id).action.by.id === ADMIN, 'status=all keeps it with the last action');
// بعد إعادة الإظهار يبدأ العد من جديد: بلاغ واحد (ولو من مبلّغ سابق) لا يعيد الإخفاء
let again = await call('POST', '/safety/report', { body: { targetType: 'event', targetId: EV.id, reason: 'مجدداً' }, user: R1, expect: 200 });
check(again.hidden === false && again.reports === 1, 'one report after a restore does not re-hide', JSON.stringify(again));
await call('GET', `/events/${EV.id}`, { user: null, expect: 200 });
await call('POST', '/safety/report', { body: { targetType: 'post', targetId: MP.id, reason: 'مضلل' }, user: R1, expect: 200 });
a = await call('POST', `/adminapi/moderation/post/${MP.id}`, { body: { action: 'hide', note: 'مخالف للقواعد' }, user: ADMIN, expect: 200 });
check(a.changed === true && (await pool.query('SELECT status FROM map_posts WHERE id=$1', [MP.id])).rows[0].status === 'blocked', 'hide blocks the map post');
check(!!(await noted(AUTHOR, 'post_blocked', (d) => d.reason === 'moderation' && d.postId === MP.id)), 'owner told about the admin hide');
// إيقاف الصاحب: من المحتوى نفسه، ويُتجاهل أي targetId في الجسم
await call('POST', '/safety/report', { body: { targetType: 'listing', targetId: LA.id }, user: R1, expect: 200 });
a = await call('POST', `/adminapi/moderation/listing/${LA.id}`, { body: { action: 'suspend-owner', targetId: R2, ownerId: R2, note: 'تكرار المخالفة' }, user: ADMIN, expect: 200 });
check(a.owner === AUTHOR && await suspendedIn(AUTHOR) && !(await suspendedIn(R2)), 'suspend-owner suspends the content owner, never the body target');
check((await pool.query('SELECT status FROM market_listings WHERE id=$1', [LA.id])).rows[0].status === 'blocked', 'suspend-owner also hides the content');
check((await pool.query("SELECT 1 FROM admin_audit WHERE admin_id=$1 AND action='moderation.suspend-owner' AND target=$2", [ADMIN, `listing:${LA.id}`])).rowCount === 1, 'moderation actions audited');
check((await pool.query("SELECT count(*)::int AS n FROM content_report_actions WHERE admin_id=$1", [ADMIN])).rows[0].n === 6, 'actions recorded in content_report_actions');
a = await call('POST', `/adminapi/moderation/vessel-comment/${C1}`, { body: { action: 'dismiss' }, user: ADMIN, expect: 200 });
check(a.changed === false && !(await call('GET', '/adminapi/moderation', { user: ADMIN, expect: 200 })).items.some((i) => i.targetId === C1), 'dismiss closes the item without changing it');
a = await call('POST', `/adminapi/moderation/biz/${B1.id}`, { body: { action: 'restore' }, user: ADMIN, expect: 200 });
check(a.changed === true, 'admin restores the biz');
await call('GET', `/biz/${B1.id}`, { user: null, expect: 200 });
// تفعيل الدائرة من صفحة الدوائر في الإدارة يرفع إخفاء الإشراف أيضاً
await pool.query('UPDATE biz SET hidden=true, active=false WHERE id=$1', [B1.id]);
await call('POST', `/adminapi/biz/${B1.id}`, { body: { active: true }, user: ADMIN, expect: 200 });
check((await pool.query('SELECT hidden, active FROM biz WHERE id=$1', [B1.id])).rows[0].hidden === false, 'admin biz activation clears the moderation hide');
await call('POST', '/adminapi/moderation/nope/x', { body: { action: 'hide' }, user: ADMIN, expect: 400 });
await call('POST', `/adminapi/moderation/event/${EV.id}`, { body: { action: 'zap' }, user: ADMIN, expect: 400 });
await call('POST', `/adminapi/moderation/event/${crypto.randomUUID()}`, { body: { action: 'hide' }, user: ADMIN, expect: 404 });
await call('POST', `/adminapi/moderation/event/${EV.id}`, { body: { action: 'hide' }, user: R1, expect: 403 });
// عضو فريق بصلاحية reports.view يرى الطابور ولا ينفّذ بلا reports.act (server/team.js؛ هنا بديل ثابت)
const savedTeamCan = globalThis.naslifeTeamCan;
globalThis.naslifeTeamCan = async (u, perm) => u === R3 && perm === 'reports.view';
await call('GET', '/adminapi/moderation', { user: R3, expect: 200 });
await call('POST', `/adminapi/moderation/event/${EV.id}`, { body: { action: 'hide' }, user: R3, expect: 403 });
globalThis.naslifeTeamCan = savedTeamCan;
e = await call('POST', `/adminapi/moderation/biz-post/${bp.id}`, { body: { action: 'suspend-owner' }, user: ADMIN, expect: 200 });
await pool.query('INSERT INTO admins(user_id,granted_by) VALUES($1,$2) ON CONFLICT DO NOTHING', [R1, 'test']);
e = await call('POST', `/adminapi/moderation/community/${CP.id}`, { body: { action: 'suspend-owner' }, user: ADMIN, expect: 403 });
check(e.error === 'owner-is-admin', 'an admin cannot be suspended from the queue');
await pool.query('DELETE FROM admins WHERE user_id=$1', [R1]);

// ================= بلاغات النواة (جدول reports مثبّت): المستهدف من صف البلاغ =================
const rr = (await pool.query("INSERT INTO reports(reporter_id,target_id,reason) VALUES($1,$2,'إزعاج') RETURNING id", [R1, R3])).rows[0];
const reps = await call('GET', '/adminapi/reports', { user: ADMIN, expect: 200 });
check(reps.table === 'reports' && reps.items.some((x) => x.id === String(rr.id)), 'admin reports pinned to the core reports table', reps.table);
await call('POST', `/adminapi/reports/${rr.id}/action`, { body: { action: 'suspend', targetId: R2 }, user: ADMIN, expect: 200 });
check(await suspendedIn(R3) && !(await suspendedIn(R2)), 'report action suspends the reported user from the row, not the body');
await call('POST', `/adminapi/reports/${crypto.randomUUID()}/action`, { body: { action: 'warn' }, user: ADMIN, expect: 404 });
await globalThis.naslifeNotifyPollReports?.();
check(!!(await noted(ADMIN, 'report_new', (d) => d.source === 'reports')), 'admins get a push for new core reports');
const ov = await call('GET', '/adminapi/overview', { user: ADMIN, expect: 200 });
check(ov.server.reportsTable === 'reports' && typeof ov.reports.contentOpen === 'number', 'overview: core reports table and open content reports', JSON.stringify(ov.reports));

// ================= الدائرة نفسها (vessel في النواة): بلاغ، لا إخفاء تلقائي، طابور، إخفاء = خاصة، إعادة = حالتها السابقة =================
await pool.query(`DELETE FROM user_flags WHERE user_id IN ${ids}`);
const VS = (await pool.query("INSERT INTO vessels(name,topic,is_public,owner_id) VALUES('دائرة منى المزعجة','نقاش عام',true,$1) RETURNING id", [AUTHOR])).rows[0].id;
const VP = (await pool.query("INSERT INTO vessels(name,topic,is_public,owner_id) VALUES('دائرة منى الخاصة','خاصة',false,$1) RETURNING id", [AUTHOR])).rows[0].id;
e = await call('POST', '/safety/report', { body: { targetType: 'vessel', targetId: VS }, user: AUTHOR, expect: 400 });
check(e.error === 'own-content', 'owner cannot report own circle');
await call('POST', '/safety/report', { body: { targetType: 'vessel', targetId: crypto.randomUUID() }, user: R1, expect: 404 });
await call('POST', '/safety/report', { body: { targetType: 'vessel', targetId: 'not a/core id' }, user: R1, expect: 404 });
rep = await report3('vessel', VS);
check(rep.hidden === false && rep.reports === 3, 'vessel is NOT auto-hidden by reports (queue only)', JSON.stringify(rep));
check((await pool.query('SELECT is_public FROM vessels WHERE id=$1', [VS])).rows[0].is_public === true, 'reported circle stays public');
check(!!(await noted(ADMIN, 'content_reported_many', (d) => d.targetType === 'vessel' && d.targetId === VS)), 'admins alerted when a vessel reaches the threshold');
mq = await call('GET', '/adminapi/moderation?type=vessel', { user: ADMIN, expect: 200 });
const vItem = mq.items.find((i) => i.targetId === VS);
check(vItem && vItem.targetType === 'vessel' && vItem.typeName === 'دائرة' && vItem.title === 'دائرة منى المزعجة' && vItem.text === 'نقاش عام' && vItem.owner?.id === AUTHOR && vItem.hidden === false && vItem.vesselId === VS,
  'vessel listed in the queue with name, topic and owner', JSON.stringify(vItem));
a = await call('POST', `/adminapi/moderation/vessel/${VS}`, { body: { action: 'hide', note: 'اسم مسيء' }, user: ADMIN, expect: 200 });
check(a.changed === true && a.status === 'hidden' && a.owner === AUTHOR, 'admin hides the circle', JSON.stringify(a));
check((await pool.query('SELECT is_public FROM vessels WHERE id=$1', [VS])).rows[0].is_public === false, 'hide makes the circle private');
check(!!(await noted(AUTHOR, 'content_hidden', (d) => d.targetType === 'vessel' && d.reason === 'moderation' && d.vesselId === VS)), 'owner notified (vessel, by moderation)');
a = await call('POST', `/adminapi/moderation/vessel/${VS}`, { body: { action: 'hide' }, user: ADMIN, expect: 200 });
check(a.changed === false, 'hiding twice keeps the saved previous state');
a = await call('POST', `/adminapi/moderation/vessel/${VS}`, { body: { action: 'restore' }, user: ADMIN, expect: 200 });
check(a.changed === true && a.status === 'visible' && (await pool.query('SELECT is_public FROM vessels WHERE id=$1', [VS])).rows[0].is_public === true, 'restore makes it public again', JSON.stringify(a));
check(!!(await noted(AUTHOR, 'content_restored', (d) => d.targetType === 'vessel')), 'owner told about the vessel restore');
// دائرة كانت خاصة أصلاً: الإعادة تبقيها خاصة (الحالة السابقة لا «عامة» دائماً)
await call('POST', '/safety/report', { body: { targetType: 'vessel', targetId: VP }, user: R1, expect: 200 });
a = await call('POST', `/adminapi/moderation/vessel/${VP}`, { body: { action: 'hide' }, user: ADMIN, expect: 200 });
check(a.changed === true && a.status === 'hidden', 'a private circle can be marked hidden');
a = await call('POST', `/adminapi/moderation/vessel/${VP}`, { body: { action: 'restore' }, user: ADMIN, expect: 200 });
check(a.changed === true && (await pool.query('SELECT is_public FROM vessels WHERE id=$1', [VP])).rows[0].is_public === false, 'restore returns a private circle to private, not public');
a = await call('POST', `/adminapi/moderation/vessel/${VS}`, { body: { action: 'suspend-owner', note: 'دائرة مسيئة' }, user: ADMIN, expect: 200 });
check(a.owner === AUTHOR && await suspendedIn(AUTHOR), 'suspend-owner works from a circle report');

// ================= كل نوع بلاغ يرسله التطبيق معروف في الخادم (قراءة lib/**/*.dart) =================
{
  const fs = await import('node:fs');
  const path = await import('node:path');
  const { TARGET_TYPES } = await import('../safety.js');
  const libDir = path.join(dir, '..', '..', 'lib');
  const files = []; const walk = (d) => { for (const f of fs.readdirSync(d, { withFileTypes: true })) { const p = path.join(d, f.name); if (f.isDirectory()) walk(p); else if (p.endsWith('.dart')) files.push(p); } };
  walk(libDir);
  const used = new Set();
  for (const f of files) {
    const src = fs.readFileSync(f, 'utf8');
    for (const m of src.matchAll(/(?:showReportSheet|ReportMenuButton)\(/g)) {
      // وسائط النداء حتى القوس المقابل
      let depth = 0, i = m.index + m[0].length - 1, end = i;
      for (; i < src.length; i++) { if (src[i] === '(') depth++; else if (src[i] === ')' && --depth === 0) { end = i; break; } }
      for (const t of src.slice(m.index, end).matchAll(/\btype:\s*'([^']+)'/g)) used.add(t[1]);
    }
  }
  const unknown = [...used].filter((t) => !TARGET_TYPES.includes(t));
  check(used.size >= 15 && used.has('vessel') && unknown.length === 0, 'every report type used in lib/ is in TARGET_TYPES', `used=${[...used].join(',')} unknown=${unknown.join(',')}`);
}

await pool.query(`DELETE FROM user_flags WHERE user_id IN ${ids}`);
await pool.query(`DELETE FROM vessels WHERE owner_id IN ${ids}`);
await pool.query('DROP TABLE IF EXISTS comments');
await pool.query("DELETE FROM platform_settings WHERE key = ANY($1)", [['bannedWords', 'reportThreshold', 'bannedWordsDefault', 'marketReviewNewAccounts', 'testTopup']]);
await app.close(); await pool.end();
console.log(fails ? `\n${fails} FAILED` : '\nALL MODERATION TESTS PASSED');
process.exit(fails ? 1 : 0);
