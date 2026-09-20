// اختبارات الإشعارات على Postgres المحلي: اكتشاف مفتاح VAPID وجدول الاشتراكات، التشفير والإرسال إلى خدمة دفع وهمية (تفكّ التشفير
// بمكتبة http_ece المرجعية)، حذف الاشتراكات المنتهية، مسارات /notify، وإشعارات الطلبات والحجوزات والتقييمات والملكية والمحفظة والسوق
// والفعاليات وإجراءات الإدارة ومراقبة البلاغات.
import Fastify from 'fastify';
import pg from 'pg';
import http from 'node:http';
import crypto from 'node:crypto';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const ece = require('http_ece'); const webpush = require('web-push');
const b64u = (b) => Buffer.from(b).toString('base64url');
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0';
const keys = webpush.generateVAPIDKeys();
process.env.VAPID_PUBLIC_KEY = keys.publicKey; process.env.VAPID_PRIVATE_KEY = keys.privateKey;

const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("INSERT INTO users(id,nickname) VALUES('SA0000001','amr'),('SA0000002','sara'),('SA0000003','khalid') ON CONFLICT DO NOTHING");
await pool.query("CREATE TABLE IF NOT EXISTS reports (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), reporter_id TEXT, target_id TEXT, reason TEXT, created_at TIMESTAMPTZ DEFAULT now())");
for (const sql of ['DROP TABLE IF EXISTS app_notifications, notify_state, push_subscriptions', 'DELETE FROM admins', "INSERT INTO admins(user_id,granted_by) VALUES('SA0000001','test')", 'DELETE FROM user_flags', 'DELETE FROM biz_claims', 'DELETE FROM biz_staff', 'DELETE FROM biz_reviews', 'DELETE FROM report_actions', 'DELETE FROM biz_orders', 'DELETE FROM market_orders', 'DELETE FROM market_listings', 'DELETE FROM tickets', 'DELETE FROM events', 'UPDATE users SET is_admin=false', 'UPDATE biz SET owner_id=NULL']) { try { await pool.query(sql); } catch (e) { console.log('   (prep skipped:', sql.slice(0, 30), e.message.slice(0, 40) + ')'); } }
await pool.query("CREATE TABLE push_subscriptions (id SERIAL PRIMARY KEY, user_id TEXT NOT NULL, endpoint TEXT NOT NULL UNIQUE, p256dh TEXT NOT NULL, auth TEXT NOT NULL, platform TEXT, created_at TIMESTAMPTZ DEFAULT now())");

// خدمة دفع وهمية: تفكّ التشفير بمفتاح المتصفح وتسجّل الحمولة؛ /gone يعيد 410
const subs = new Map(); const received = [];
const pushSrv = http.createServer((req, res) => {
  const chunks = []; req.on('data', (c) => chunks.push(c)); req.on('end', () => {
    const body = Buffer.concat(chunks); const rec = { path: req.url, auth: req.headers.authorization, enc: req.headers['content-encoding'], ttl: req.headers.ttl, payload: null };
    received.push(rec);
    if (req.url === '/gone') { res.writeHead(410); return res.end(); }
    const s = subs.get(req.url);
    try { rec.payload = JSON.parse(ece.decrypt(body, { version: 'aes128gcm', privateKey: s.ecdh, authSecret: b64u(s.auth) }).toString()); } catch (e) { rec.payload = { error: e.message }; }
    res.writeHead(201); res.end();
  });
});
await new Promise((r) => pushSrv.listen(0, '127.0.0.1', r)); const PP = pushSrv.address().port;
const addSub = async (user, path) => { const ecdh = crypto.createECDH('prime256v1'); ecdh.generateKeys(); const auth = crypto.randomBytes(16); subs.set(path, { ecdh, auth }); await pool.query('INSERT INTO push_subscriptions(user_id,endpoint,p256dh,auth,platform) VALUES($1,$2,$3,$4,$5)', [user, `http://127.0.0.1:${PP}${path}`, b64u(ecdh.getPublicKey()), b64u(auth), 'web']); };
await addSub('SA0000001', '/push/amr'); await addSub('SA0000001', '/gone'); await addSub('SA0000003', '/push/khalid');

const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
const dir = new URL('.', import.meta.url).pathname;
app.get('/push/key', async () => ({ key: keys.publicKey }));
app.register((await import('../notify.js')).default, { pool, auth, pollMs: 3600000, opsDir: dir + 'ops' });
app.register((await import('../commerce.js')).default, { pool, auth });
app.register((await import('../business.js')).default, { pool, auth });
app.register((await import('../admin.js')).default, { pool, auth, webappDir: dir + 'webapp', opsDir: dir + 'ops' });
await app.ready(); await new Promise((r) => setTimeout(r, 900));
await pool.query("UPDATE biz SET owner_id='SA0000001' WHERE id='biz-ikea'");
await pool.query("INSERT INTO biz_staff(biz_id,user_id,role) VALUES('biz-ikea','SA0000003','staff')");
for (const [u, bal] of [['SA0000002', 20000000], ['SA0000003', 5000000]]) await pool.query('INSERT INTO wallet_accounts(user_id,balance) VALUES($1,$2) ON CONFLICT (user_id) DO UPDATE SET balance=$2', [u, bal]);

let fails = 0;
const check = (cond, label, extra = '') => { if (!cond) fails++; console.log((cond ? 'OK  ' : 'FAIL') + ' ' + label + (extra ? ' ' + extra : '')); };
const call = async (method, url, { body = {}, user = 'SA0000001', expect } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json' }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url} -> ${r.statusCode}`, r.statusCode === expect ? '' : 'expected ' + expect + ' ' + JSON.stringify(j).slice(0, 160));
  return j;
};
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const items = async (user) => (await call('GET', '/notify', { user })).items;
const latest = async (user, kind) => { const l = await items(user); const n = l[0]; check(n?.kind === kind, `${user} latest is ${kind}`, n ? `"${n.title}" / "${n.body}" data=${JSON.stringify(n.data)}` : '(none)'); return n; };

// ---- الحالة والاكتشاف
const st = await call('GET', '/notify/status', { user: null, expect: 200 });
check(st.push.ready && st.push.ok, 'push discovered', JSON.stringify(st.push));
check(st.push.source === 'env' && st.push.subscriptions?.table === 'push_subscriptions' && st.push.subscriptions.keys === 'columns', 'push source/table', st.push.source + '/' + JSON.stringify(st.push.subscriptions));
check(st.reports.table === 'reports' && st.reports.polling, 'reports polling', JSON.stringify(st.reports));
await call('GET', '/notify', { user: null, expect: 401 });

// ---- طلب جديد: يصل المالك والموظف (أمر + خالد) ولا يصل العميل؛ الدفع يصل متصفح أمر ويُحذف الاشتراك المنتهي
const order = await call('POST', '/biz/biz-ikea/orders', { body: { itemId: 'ikea-lack', qty: 2 }, user: 'SA0000002', expect: 200 });
await wait(400);
let n = await latest('SA0000001', 'biz_order');
check(n?.data?.bizId === 'biz-ikea' && n?.data?.orderId === order.id && /طلب جديد/.test(n?.title ?? '') && /sara/.test(n?.body ?? '') && /× 2/.test(n?.body ?? ''), 'order notification content');
check((await items('SA0000003')).some((x) => x.kind === 'biz_order'), 'staff notified too');
check((await items('SA0000002')).length === 0, 'customer not notified of own order');
check(received.some((r) => r.path === '/push/amr' && r.payload?.title === n.title && r.payload?.url === '/#/n/' + n.id && r.enc === 'aes128gcm'), 'push delivered and decrypted', JSON.stringify(received.map((r) => [r.path, r.payload?.title]).slice(0, 4)));
const a = received.find((r) => r.path === '/push/amr');
const m = a?.auth?.match(/^vapid t=([^,]+), k=(.+)$/);
check(!!m && m[2] === keys.publicKey && JSON.parse(Buffer.from(m[1].split('.')[1], 'base64url')).aud === `http://127.0.0.1:${PP}`, 'vapid header audience/key');
check(received.some((r) => r.path === '/gone'), 'gone endpoint attempted');
check((await pool.query("SELECT count(*)::int AS n FROM push_subscriptions WHERE endpoint LIKE '%/gone'")).rows[0].n === 0, 'gone subscription pruned');
const st2 = await call('GET', '/notify/status', { user: null }); check(st2.push.sent >= 1 && st2.push.pruned === 1, 'status counters', `sent=${st2.push.sent} pruned=${st2.push.pruned} failed=${st2.push.failed} ${st2.push.lastError ?? ''}`);
check((await call('GET', '/notify/unread', { expect: 200 })).unread >= 1, 'unread count');

// ---- إلغاء العميل → الفريق؛ إلغاء المالك → العميل؛ تأكيد الاستلام → العميل
await call('POST', `/biz/orders/${order.id}/cancel`, { user: 'SA0000002', expect: 200 });
n = await latest('SA0000001', 'order_cancelled'); check(/إلغاء طلب/.test(n?.title ?? '') && /استُرد/.test(n?.body ?? ''), 'cancel by customer text');
const o2 = await call('POST', '/biz/biz-ikea/orders', { body: { itemId: 'ikea-lack', qty: 1 }, user: 'SA0000002', expect: 200 });
await call('POST', `/biz/biz-ikea/orders/${o2.id}/cancel`, { expect: 200 });
n = await latest('SA0000002', 'order_status'); check(n?.data?.status === 'cancelled' && /استُرد/.test(n?.body ?? ''), 'cancel by owner → customer');
const o3 = await call('POST', '/biz/biz-ikea/orders', { body: { itemId: 'ikea-lack', qty: 1 }, user: 'SA0000002', expect: 200 });
await call('POST', '/biz/biz-ikea/checkin', { body: { code: o3.code }, user: 'SA0000003', expect: 200 });
n = await latest('SA0000002', 'order_status'); check(n?.data?.status === 'used' && /استلام/.test(n?.title ?? ''), 'checkin → customer');

// ---- التقييم والرد
await call('POST', '/biz/biz-ikea/reviews', { body: { rating: 5, text: 'ممتاز' }, user: 'SA0000002', expect: 200 });
n = await latest('SA0000001', 'biz_review'); check(/★5/.test(n?.title ?? '') && /ممتاز/.test(n?.body ?? ''), 'review → owner');
check(!(await items('SA0000003')).some((x) => x.kind === 'biz_review'), 'staff (not manager) not notified of review');
await call('POST', '/biz/biz-ikea/reviews/SA0000002/reply', { body: { text: 'شكراً لك' }, expect: 200 });
n = await latest('SA0000002', 'review_reply'); check(/شكراً/.test(n?.body ?? ''), 'reply → reviewer');

// ---- طلبات الملكية: للمديرين ثم للطالب
await call('POST', '/biz/biz-vox/claim', { body: { note: 'مدير الفرع' }, user: 'SA0000003', expect: 200 });
n = await latest('SA0000001', 'biz_claim'); check(n?.data?.bizId === 'biz-vox' && n?.data?.userId === 'SA0000003', 'claim → admins');
await call('POST', '/adminapi/claims/biz-vox/SA0000003/approve', { expect: 200 });
n = await latest('SA0000003', 'claim_decided'); check(n?.data?.approved === true && /قُبل/.test(n?.title ?? ''), 'claim approved → claimant');
await call('POST', '/biz/biz-vox/transfer', { body: { userId: 'SA0000002' }, user: 'SA0000003', expect: 200 });
n = await latest('SA0000002', 'biz_owner'); check(n?.data?.bizId === 'biz-vox', 'ownership transfer → new owner');

// ---- المحفظة والسوق
await call('POST', '/wallet/transfer', { body: { to: 'SA0000003', amount: 2550, note: 'هدية' }, user: 'SA0000002', expect: 200 });
n = await latest('SA0000003', 'transfer_in'); check(/25\.50 ر\.س/.test(n?.body ?? '') && /هدية/.test(n?.body ?? '') && n?.data?.from === 'SA0000002', 'transfer → recipient');
await wait(300); check(received.some((r) => r.path === '/push/khalid' && r.payload?.title === 'وصلك تحويل'), 'push to khalid');
const lst = await call('POST', '/market', { body: { kind: 'product', category: 'coffee', title: 'قهوة مختصة', description: 'حبوب', price: 4500, placeName: 'جدة' }, user: 'SA0000002', expect: 200 });
const mo = await call('POST', `/market/${lst.id}/order`, { body: { qty: 2, note: 'بدون سكر' }, user: 'SA0000003', expect: 200 });
n = await latest('SA0000002', 'market_order'); check(/khalid/.test(n?.body ?? '') && /× 2/.test(n?.body ?? '') && /90 ر\.س/.test(n?.body ?? '') && n?.data?.orderId === mo.id, 'market order → seller');
await call('POST', `/market/orders/${mo.id}/deliver`, { user: 'SA0000002', expect: 200 });
n = await latest('SA0000003', 'market_status'); check(n?.data?.status === 'delivered', 'deliver → buyer');
const mo2 = await call('POST', `/market/${lst.id}/order`, { body: { qty: 1 }, user: 'SA0000003', expect: 200 });
await call('POST', `/market/orders/${mo2.id}/cancel`, { user: 'SA0000002', expect: 200 });
n = await latest('SA0000003', 'market_status'); check(/استُرد/.test(n?.body ?? ''), 'seller cancel → buyer refund text');

// ---- الفعاليات: شراء تذاكر → المضيف؛ إلغاء المضيف → الحاملون؛ إلغاء الإدارة → الحاملون والمضيف
const ev = await call('POST', '/events', { body: { title: 'لقاء المطورين', startsAt: new Date(Date.now() + 86400000).toISOString(), tiers: [{ name: 'عادي', price: 2000, quantity: 10 }] }, user: 'SA0000002', expect: 200 });
await call('POST', `/events/${ev.id}/tickets`, { body: { tierId: ev.tiers[0].id, qty: 2 }, user: 'SA0000003', expect: 200 });
n = await latest('SA0000002', 'ticket_sale'); check(/2 تذاكر/.test(n?.body ?? '') && /40 ر\.س/.test(n?.body ?? '') && n?.data?.eventId === ev.id, 'tickets → host');
await call('POST', `/events/${ev.id}/cancel`, { user: 'SA0000002', expect: 200 });
n = await latest('SA0000003', 'event_cancelled'); check(/40 ر\.س/.test(n?.body ?? ''), 'host cancel → holder refund');
const ev2 = await call('POST', '/events', { body: { title: 'أمسية', startsAt: new Date(Date.now() + 86400000).toISOString(), tiers: [{ name: 'عادي', price: 1000, quantity: 10 }] }, user: 'SA0000002', expect: 200 });
await call('POST', `/events/${ev2.id}/tickets`, { body: { tierId: ev2.tiers[0].id, qty: 1 }, user: 'SA0000003', expect: 200 });
await call('POST', `/adminapi/events/${ev2.id}/cancel`, { expect: 200 });
n = await latest('SA0000003', 'event_cancelled'); check(/الإدارة/.test(n?.body ?? ''), 'admin cancel → holder');
n = await latest('SA0000002', 'event_cancelled'); check(/فعاليتك/.test(n?.title ?? ''), 'admin cancel → host');

// ---- إجراءات الإدارة
await call('POST', '/adminapi/users/SA0000003/credit', { body: { amount: 12345, note: 'تعويض' }, expect: 200 });
n = await latest('SA0000003', 'wallet_credit'); check(/123\.45 ر\.س/.test(n?.body ?? '') && /تعويض/.test(n?.body ?? ''), 'credit → user');
await call('POST', '/adminapi/users/SA0000003/suspend', { body: { suspended: true, note: 'مخالفة' }, expect: 200 });
n = await latest('SA0000003', 'account_suspended'); check(n?.body === 'مخالفة', 'suspend → user');
await call('POST', '/adminapi/users/SA0000003/suspend', { body: { suspended: false }, expect: 200 });
n = await latest('SA0000003', 'account_restored'); check(!!n, 'unsuspend → user');
const rep = (await pool.query("INSERT INTO reports(reporter_id,target_id,reason) VALUES('SA0000002','SA0000003','إزعاج') RETURNING id")).rows[0];
await call('POST', `/adminapi/reports/${rep.id}/action`, { body: { action: 'warn', note: 'يرجى الالتزام', targetId: 'SA0000003' }, expect: 200 });
n = await latest('SA0000003', 'account_warning'); check(n?.body === 'يرجى الالتزام' && n?.data?.reportId === String(rep.id), 'warn → target');
await call('POST', '/adminapi/users/SA0000002/admin', { body: { grant: true }, expect: 200 });
n = await latest('SA0000002', 'admin_granted'); check(!!n, 'grant → user');
await call('POST', '/adminapi/users/SA0000002/admin', { body: { grant: false }, expect: 200 });
await call('POST', `/adminapi/market/${lst.id}/hide`, { expect: 200 });
n = await latest('SA0000002', 'listing_hidden'); check(n?.data?.listingId === lst.id, 'hide → seller');

// ---- مراقبة البلاغات: تهيئة ثم بلاغ جديد → المديرون فقط
await globalThis.naslifeNotifyPollReports();
const before = (await items('SA0000001')).length;
await pool.query("INSERT INTO reports(reporter_id,target_id,reason) VALUES('SA0000003','SA0000002','سب')");
await globalThis.naslifeNotifyPollReports();
n = await latest('SA0000001', 'report_new'); check(n?.data?.count === 1 && (await items('SA0000001')).length === before + 1, 'new report → admin');
await globalThis.naslifeNotifyPollReports(); check((await items('SA0000001')).length === before + 1, 'no duplicate on next poll');
check(!(await items('SA0000002')).some((x) => x.kind === 'report_new'), 'non-admin not notified of reports');

// ---- القراءة والجلب والحذف والاختبار
const mine = await call('GET', '/notify?limit=3', { user: 'SA0000003', expect: 200 }); check(mine.items.length === 3 && mine.unread > 3, 'limit + unread', `unread=${mine.unread}`);
const r1 = await call('POST', '/notify/read', { body: { ids: [mine.items[0].id] }, user: 'SA0000003', expect: 200 }); check(r1.unread === mine.unread - 1, 'read one');
await call('GET', `/notify/${mine.items[0].id}`, { user: 'SA0000003', expect: 200 }).then((x) => check(x.readAt != null && x.url === '/#/n/' + x.id, 'get item read'));
await call('GET', `/notify/${mine.items[0].id}`, { user: 'SA0000002', expect: 404 });
await call('POST', '/notify/read', { body: {}, user: 'SA0000003', expect: 400 });
const r2 = await call('POST', '/notify/read', { body: { all: true }, user: 'SA0000003', expect: 200 }); check(r2.unread === 0, 'read all');
await call('DELETE', `/notify/${mine.items[1].id}`, { user: 'SA0000003', expect: 200 });
check(!(await items('SA0000003')).some((x) => x.id === mine.items[1].id), 'deleted');
const t = await call('POST', '/notify/test', { expect: 200 }); check(t.pushed === 1 && t.subscriptions === 1, 'test push', JSON.stringify(t));
const t2 = await call('POST', '/notify/test', { user: 'SA0000002', expect: 200 }); check(t2.pushed === 0 && t2.push === true && t2.subscriptions === 0, 'test without subscription', JSON.stringify(t2));

console.log(fails ? `\n${fails} FAILURES` : '\nALL NOTIFY TESTS PASSED');
await app.close(); pushSrv.close(); await pool.end();
process.exit(fails ? 1 : 0);
