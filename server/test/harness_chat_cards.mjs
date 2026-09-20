// اختبارات رموز الاختصار في المحادثة (server/chat_cards.js): تحليل @شخص و@دائرة و#دائرة/صنف و#ev و#mk و#post و#space و#t و#o،
// وتسجيل الطلبات (مبلغ/تقسيم/موعد/إرسال) بمعرّف الرسالة، والدفع من المحفظة، والقبول/الرفض/الإلغاء، والصلاحيات، ودمجها في /chat/meta.
import Fastify from 'fastify';
import pg from 'pg';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0';
const dir = new URL('.', import.meta.url).pathname;
process.env.CHAT_MEDIA_DIR = dir + 'media_store';
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("INSERT INTO users(id,nickname,avatar_url) VALUES('SA0000001','amr','/files/amr.jpg'),('SA0000002','sara',NULL),('SA0000003','khalid',NULL) ON CONFLICT (id) DO UPDATE SET nickname=EXCLUDED.nickname");
await pool.query("CREATE TABLE IF NOT EXISTS user_blocks (user_id TEXT NOT NULL, blocked_id TEXT NOT NULL, created_at TIMESTAMPTZ DEFAULT now(), PRIMARY KEY (user_id, blocked_id))");
for (const sql of ['DELETE FROM user_blocks', 'DROP TABLE IF EXISTS chat_requests', 'DELETE FROM wallet_tx', 'DELETE FROM wallet_accounts', 'DELETE FROM app_notifications', 'DELETE FROM tickets', 'DELETE FROM ticket_tiers', 'DELETE FROM events', 'DELETE FROM market_listings', 'DELETE FROM map_posts', "DELETE FROM biz_orders", "DELETE FROM biz_community_posts WHERE biz_id='biz-brew92'"]) { try { await pool.query(sql); } catch { /* أول تشغيل */ } }
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
app.register((await import('../notify.js')).default, { pool, auth, pollMs: 3600000, opsDir: dir + 'ops' });
app.register((await import('../commerce.js')).default, { pool, auth });
app.register((await import('../chat_tools.js')).default, { pool, auth });
app.register((await import('../business.js')).default, { pool, auth });
app.register((await import('../biz_community.js')).default, { pool, auth });
app.register((await import('../map_posts.js')).default, { pool, auth });
app.register((await import('../chat_cards.js')).default, { pool, auth });
await app.ready(); await new Promise((r) => setTimeout(r, 800));
let fails = 0;
const check = (cond, label, extra = '') => { if (!cond) fails++; console.log((cond ? 'OK  ' : 'FAIL') + ' ' + label + (extra ? ' ' + extra : '')); };
const call = async (method, url, { body = {}, user = 'SA0000001', expect } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json', host: 'naslife.app' }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url} -> ${r.statusCode}`, r.statusCode === expect ? '' : JSON.stringify(j).slice(0, 200));
  return j;
};
const cards = async (refs, user = 'SA0000001') => (await call('GET', '/chat/cards?refs=' + encodeURIComponent(refs.join(',')), { user, expect: 200 })).refs;

// ---- الحالة
const st = await call('GET', '/chat/cards/status', { user: null, expect: 200 });
check(st.ok && st.wallet === true && st.requestKinds.includes('pay') && st.types.includes('item'), 'status: wallet hook present', JSON.stringify(st));
await call('GET', '/chat/cards?refs=@sara', { user: null, expect: 401 });

// ---- الإشارات
let c = await cards(['@sara', '@SARA', '@nobody', '@brew92', '@biz-brew92', '#brew92/v60', '#biz-brew92/brew92-v60', '#brew92/nope', '#space/brew92', 'hello', '#zz/1']);
check(c['@sara']?.type === 'user' && c['@sara'].id === 'SA0000002' && c['@sara'].link === '/u/sara', '@sara → user card', JSON.stringify(c['@sara']));
check(c['@SARA']?.type === 'user', 'nickname match is case-insensitive');
check(c['@nobody'] === null && c['hello'] === null && c['#zz/1'] === null && c['#brew92/nope'] === null, 'unknown refs resolve to null');
check(c['@brew92']?.type === 'biz' && c['@brew92'].id === 'biz-brew92' && c['@brew92'].link === '/c/biz-brew92' && c['@brew92'].image === 'asset:biz/brew92.png' && c['@brew92'].category === 'cafe', '@brew92 → circle card (biz- prefix implied)', JSON.stringify(c['@brew92']));
check(c['@biz-brew92']?.type === 'biz', '@biz-brew92 also works');
check(c['#brew92/v60']?.type === 'item' && c['#brew92/v60'].id === 'brew92-v60' && c['#brew92/v60'].bizId === 'biz-brew92' && c['#brew92/v60'].price > 0 && c['#brew92/v60'].subtitle.length > 0, '#brew92/v60 → product card with price', JSON.stringify(c['#brew92/v60']));
check(c['#biz-brew92/brew92-v60']?.type === 'item' && c['#biz-brew92/brew92-v60'].id === 'brew92-v60', 'full ids accepted too');
check(c['#space/brew92']?.type === 'space' && c['#space/brew92'].bizId === 'biz-brew92' && /مشاركة/.test(c['#space/brew92'].subtitle), '#space/brew92 → space card', JSON.stringify(c['#space/brew92']));

// مشاركة في المساحة تقتبس منتجاً
const sp = await call('POST', '/biz/biz-brew92/community', { body: { text: 'الـV60 هنا رائع', itemId: 'brew92-v60' }, user: 'SA0000002', expect: 200 });
c = await cards([`#space/brew92/${sp.id}`, '#brew92/v60']);
check(c[`#space/brew92/${sp.id}`]?.type === 'spacepost' && c[`#space/brew92/${sp.id}`].title === 'الـV60 هنا رائع' && c[`#space/brew92/${sp.id}`].user?.nickname === 'sara', '#space/biz/post → post card with author', JSON.stringify(c[`#space/brew92/${sp.id}`]));
check(c['#brew92/v60'].discussions === 1, 'item card counts discussions', String(c['#brew92/v60'].discussions));

// فعالية وتذكرة
await call('POST', '/wallet/topup', { body: { amount: 50000 }, user: 'SA0000001', expect: 200 });
await call('POST', '/wallet/topup', { body: { amount: 20000 }, user: 'SA0000002', expect: 200 });
const ev = await call('POST', '/events', { body: { title: 'ليلة جاز', startsAt: new Date(Date.now() + 86400000).toISOString(), placeName: 'حي الروضة', tiers: [{ name: 'عادي', price: 5000, quantity: 20 }] }, user: 'SA0000003', expect: 200 });
c = await cards([`#ev/${ev.id}`, '#ev/not-a-uuid']);
check(c[`#ev/${ev.id}`]?.type === 'event' && c[`#ev/${ev.id}`].title === 'ليلة جاز' && c[`#ev/${ev.id}`].price === 5000 && c[`#ev/${ev.id}`].left === 20 && c[`#ev/${ev.id}`].host?.nickname === 'khalid', '#ev/id → event card', JSON.stringify(c[`#ev/${ev.id}`]));
check(c['#ev/not-a-uuid'] === null, 'bad event id → null');
const tk = await call('POST', `/events/${ev.id}/tickets`, { body: { tierId: ev.tiers[0].id, qty: 1 }, user: 'SA0000001', expect: 200 });
const code = (tk.tickets ?? tk)[0]?.code ?? tk.code;
check(typeof code === 'string' && code.startsWith('NAS-'), 'bought a ticket', JSON.stringify(tk).slice(0, 120));
c = await cards([`#t/${code}`, `#t/${code.toLowerCase()}`, '#t/NAS-NOPE0000'], 'SA0000002');
check(c[`#t/${code}`]?.type === 'ticket' && c[`#t/${code}`].title === 'ليلة جاز' && c[`#t/${code}`].owner?.nickname === 'amr' && c[`#t/${code}`].status === 'valid', '#t/code → ticket card visible to the peer holding the code', JSON.stringify(c[`#t/${code}`]));
check(c[`#t/${code.toLowerCase()}`]?.type === 'ticket', 'ticket code case-insensitive');
check(c['#t/NAS-NOPE0000'] === null, 'unknown ticket → null');

// عرض في السوق ومنشور على الخريطة
const mk = await call('POST', '/market', { body: { title: 'آيفون 13', price: 180000, category: 'electronics', kind: 'product', placeName: 'جدة' }, user: 'SA0000002', expect: 200 });
const post = await call('POST', '/mapposts', { body: { kind: 'text', caption: 'الجوازات مزدحمة الآن', lat: 21.68, lng: 39.15, placeName: 'صالة 1' }, user: 'SA0000002', expect: 200 });
c = await cards([`#mk/${mk.id}`, `#post/${post.id}`]);
check(c[`#mk/${mk.id}`]?.type === 'listing' && c[`#mk/${mk.id}`].title === 'آيفون 13' && c[`#mk/${mk.id}`].price === 180000 && c[`#mk/${mk.id}`].seller?.nickname === 'sara', '#mk/id → listing card', JSON.stringify(c[`#mk/${mk.id}`]));
check(c[`#post/${post.id}`]?.type === 'post' && c[`#post/${post.id}`].title === 'الجوازات مزدحمة الآن' && /sara/.test(c[`#post/${post.id}`].subtitle), '#post/id → map post card', JSON.stringify(c[`#post/${post.id}`]));

// طلب من دائرة
const ord = await call('POST', '/biz/biz-brew92/orders', { body: { itemId: 'brew92-v60', qty: 1 }, user: 'SA0000001', expect: 200 });
c = await cards([`#o/${ord.code}`], 'SA0000002');
check(c[`#o/${ord.code}`]?.type === 'order' && c[`#o/${ord.code}`].bizId === 'biz-brew92' && c[`#o/${ord.code}`].owner?.nickname === 'amr' && c[`#o/${ord.code}`].status === 'confirmed', '#o/code → order card', JSON.stringify(c[`#o/${ord.code}`]));

// الحد الأقصى للإشارات وتكرارها
const many = Array.from({ length: 60 }, (_, i) => `@u${i}`);
c = await cards(many);
check(Object.keys(c).length === 40, 'refs capped at 40', String(Object.keys(c).length));

// ---- الطلبات: مبلغ
const bal = async (u) => (await call('GET', '/wallet', { user: u })).balance;
const a0 = await bal('SA0000001'), s0 = await bal('SA0000002');
await call('POST', '/chat/requests', { body: { messageId: 'm-pay-1', peerId: 'SA0000002', kind: 'pay', amount: 0 }, expect: 400 });
await call('POST', '/chat/requests', { body: { messageId: 'm-pay-1', peerId: 'SA0000001', kind: 'pay', amount: 100 }, expect: 400 });
await call('POST', '/chat/requests', { body: { messageId: 'm-pay-1', peerId: 'SA0000002', kind: 'nope', amount: 100 }, expect: 400 });
await call('POST', '/chat/requests', { body: { messageId: 'm-pay-1', peerId: 'SA0000002', kind: 'pay', amount: 99999999 }, expect: 400 });
let r = await call('POST', '/chat/requests', { body: { messageId: 'm-pay-1', peerId: 'SA0000002', kind: 'pay', amount: 4500, note: 'قهوة أمس' }, expect: 200 });
check(r.request.status === 'pending' && r.request.amount === 4500 && r.request.share === 4500 && r.request.note === 'قهوة أمس' && r.request.expiresAt, 'pay request registered pending with expiry', JSON.stringify(r.request));
// تظهر في /chat/meta للطرفين فقط
let meta = await call('GET', '/chat/meta?ids=m-pay-1', { user: 'SA0000002', expect: 200 });
check(meta['m-pay-1']?.request?.kind === 'pay' && meta['m-pay-1'].request.from === 'SA0000001', 'request merged into /chat/meta for the recipient', JSON.stringify(meta));
meta = await call('GET', '/chat/meta?ids=m-pay-1', { user: 'SA0000003', expect: 200 });
check(!meta['m-pay-1']?.request, 'third party does not see the request');
// الدفع: صاحب الطلب لا يدفع لنفسه، وطرف ثالث ممنوع
await call('POST', '/chat/requests/m-pay-1/pay', { user: 'SA0000001', expect: 403 });
await call('POST', '/chat/requests/m-pay-1/pay', { user: 'SA0000003', expect: 404 });
r = await call('POST', '/chat/requests/m-pay-1/pay', { user: 'SA0000002', expect: 200 });
check(r.request.status === 'paid' && r.request.resolvedAt, 'recipient paid', JSON.stringify(r.request));
check(await bal('SA0000001') === a0 + 4500 && await bal('SA0000002') === s0 - 4500, 'wallets moved 45 SAR', JSON.stringify([await bal('SA0000001') - a0, await bal('SA0000002') - s0]));
await call('POST', '/chat/requests/m-pay-1/pay', { user: 'SA0000002', expect: 409 });
const tx = await call('GET', '/wallet/transactions', { user: 'SA0000001' });
check(tx[0]?.kind === 'transfer_in' && tx[0].ref === 'm-pay-1' && tx[0].note === 'قهوة أمس', 'ledger row references the message', JSON.stringify(tx[0]));
// رصيد غير كافٍ
await call('POST', '/chat/requests', { body: { messageId: 'm-pay-2', peerId: 'SA0000002', kind: 'pay', amount: 999900 }, expect: 200 });
await call('POST', '/chat/requests/m-pay-2/pay', { user: 'SA0000002', expect: 402 });
// إلغاء من صاحب الطلب
await call('POST', '/chat/requests/m-pay-2/cancel', { user: 'SA0000002', expect: 403 });
r = await call('POST', '/chat/requests/m-pay-2/cancel', { user: 'SA0000001', expect: 200 });
check(r.request.status === 'cancelled', 'owner cancelled pending request');
await call('POST', '/chat/requests/m-pay-2/pay', { user: 'SA0000002', expect: 409 });
// رفض
await call('POST', '/chat/requests', { body: { messageId: 'm-pay-3', peerId: 'SA0000002', kind: 'pay', amount: 1000 }, expect: 200 });
r = await call('POST', '/chat/requests/m-pay-3/decline', { user: 'SA0000002', expect: 200 });
check(r.request.status === 'declined', 'recipient declined');
// انتهاء الصلاحية
await call('POST', '/chat/requests', { body: { messageId: 'm-pay-4', peerId: 'SA0000002', kind: 'pay', amount: 1000 }, expect: 200 });
await pool.query("UPDATE chat_requests SET expires_at=now() - interval '1 minute' WHERE message_id='m-pay-4'");
r = await call('GET', '/chat/requests?ids=m-pay-4', { user: 'SA0000002', expect: 200 });
check(r['m-pay-4']?.status === 'expired', 'pending request past expiry reads as expired');
await call('POST', '/chat/requests/m-pay-4/pay', { user: 'SA0000002', expect: 409 });
// لا يمكن لطرف آخر إعادة تسجيل الرسالة نفسها
await call('POST', '/chat/requests', { body: { messageId: 'm-pay-3', peerId: 'SA0000001', kind: 'pay', amount: 1000 }, user: 'SA0000002', expect: 409 });

// ---- تقسيم فاتورة
await call('POST', '/chat/requests', { body: { messageId: 'm-split-1', peerId: 'SA0000002', kind: 'split', amount: 18000, n: 1 }, expect: 400 });
r = await call('POST', '/chat/requests', { body: { messageId: 'm-split-1', peerId: 'SA0000002', kind: 'split', amount: 18000, n: 4 }, expect: 200 });
check(r.request.share === 4500 && r.request.n === 4, 'split share = ceil(180/4) = 45', JSON.stringify(r.request));
const s1 = await bal('SA0000002');
r = await call('POST', '/chat/requests/m-split-1/pay', { user: 'SA0000002', expect: 200 });
check(r.request.status === 'paid' && await bal('SA0000002') === s1 - 4500, 'split: recipient pays only their share');

// ---- موعد
await call('POST', '/chat/requests', { body: { messageId: 'm-meet-1', peerId: 'SA0000002', kind: 'meet', when: '' }, expect: 400 });
r = await call('POST', '/chat/requests', { body: { messageId: 'm-meet-1', peerId: 'SA0000002', kind: 'meet', when: '7م', place: '@brew92' }, expect: 200 });
check(r.request.status === 'pending' && r.request.when === '7م' && r.request.place === '@brew92' && r.request.amount === 0, 'meet proposal registered', JSON.stringify(r.request));
await call('POST', '/chat/requests/m-meet-1/pay', { user: 'SA0000002', expect: 400 });
await call('POST', '/chat/requests/m-meet-1/accept', { user: 'SA0000001', expect: 403 });
r = await call('POST', '/chat/requests/m-meet-1/accept', { user: 'SA0000002', expect: 200 });
check(r.request.status === 'accepted', 'meet accepted by the peer');
const n = await call('GET', '/notify', { user: 'SA0000001' });
check((n.items ?? n).some?.((x) => x.kind === 'meet_accepted'), 'proposer notified of acceptance', JSON.stringify((n.items ?? n).slice?.(0, 2)));
await call('POST', '/chat/requests/m-meet-1/accept', { user: 'SA0000002', expect: 409 });

// ---- إرسال مبلغ: يتحقق من تحويل حديث في السجل
await call('POST', '/chat/requests', { body: { messageId: 'm-send-0', peerId: 'SA0000002', kind: 'send', amount: 7700 }, expect: 200 }).then((x) => check(x.request.status === 'unverified', 'send without a matching transfer → unverified', x.request.status));
await call('POST', '/wallet/transfer', { body: { to: 'SA0000002', amount: 2500, note: 'هدية' }, user: 'SA0000001', expect: 200 });
r = await call('POST', '/chat/requests', { body: { messageId: 'm-send-1', peerId: 'SA0000002', kind: 'send', amount: 2500, note: 'هدية' }, expect: 200 });
check(r.request.status === 'paid' && r.request.resolvedAt, 'send matched the ledger → paid', JSON.stringify(r.request));

// ---- المحظورون
await pool.query("INSERT INTO user_blocks(user_id,blocked_id) VALUES('SA0000003','SA0000001')");
await call('POST', '/chat/requests', { body: { messageId: 'm-pay-9', peerId: 'SA0000003', kind: 'pay', amount: 1000 }, expect: 403 });

// ---- المعلّقة لي
const pend = await call('GET', '/chat/requests/pending', { user: 'SA0000002', expect: 200 });
check(Array.isArray(pend) && pend.every((x) => x.status === 'pending' && x.to === 'SA0000002'), 'pending list for recipient', String(pend.length));

console.log(fails ? `\n${fails} FAILED` : '\nALL PASSED');
await app.close(); await pool.end();
process.exit(fails ? 1 : 0);
