// رسائل الدوائر الخاصة (server/biz_inbox.js): بدء المحادثة ومتابعتها، المراجع (طلب/صنف) والصور، صلاحيات كل دور (المالك والمدير
// والموظف يقرؤون ويردون؛ hr ومدير النظام والغريب لا)، الرد باسم الدائرة مع تسجيل كاتبه داخلياً، الإسناد والإغلاق وإعادة الفتح والفلاتر،
// عدّادات غير المقروء والإشعارات بالاتجاهين (أول رسالة غير مقروءة فقط)، الحظر بالاتجاهين، الكلمات المحظورة، الإيقاف، حدّا المعدّل،
// الدائرة غير الموثّقة، والبلاغ على رسالة (نوع biz-msg) وقراءة الإدارة للسياق عبر البلاغ فقط.
import Fastify from 'fastify';
import pg from 'pg';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0'; process.env.NODE_ENV = 'test';
let fails = 0;
const check = (cond, label, extra = '') => { if (!cond) fails++; console.log((cond ? 'OK  ' : 'FAIL') + ' ' + label + (extra ? ' ' + extra : '')); };
const O = 'SI0000001', M = 'SI0000002', S = 'SI0000003', H = 'SI0000004', C = 'SI0000005', C2 = 'SI0000006', X = 'SI0000007', A = 'SI0000008',
  SUS = 'SI0000009', LIM = 'SI0000010', O2 = 'SI0000011', DAY = 'SI0000012';
const OURS = [O, M, S, H, C, C2, X, A, SUS, LIM, O2, DAY];
const ids = `('${OURS.join("','")}')`;

const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query(`INSERT INTO users(id,nickname) VALUES ${OURS.map((u, i) => `('${u}','${['owner', 'manager', 'staff', 'hr', 'cust', 'cust2', 'stranger', 'sysadmin', 'susp', 'limit', 'owner2', 'daily'][i]}')`).join(',')}
  ON CONFLICT (id) DO UPDATE SET nickname=EXCLUDED.nickname`);
await pool.query("CREATE TABLE IF NOT EXISTS user_blocks (user_id TEXT NOT NULL, blocked_id TEXT NOT NULL, created_at TIMESTAMPTZ DEFAULT now(), PRIMARY KEY (user_id, blocked_id))");
await pool.query("CREATE TABLE IF NOT EXISTS user_flags (user_id TEXT PRIMARY KEY, suspended BOOLEAN NOT NULL DEFAULT false, note TEXT NOT NULL DEFAULT '', updated_at TIMESTAMPTZ NOT NULL DEFAULT now())");
// بقايا تشغيل سابق (القاعدة مشتركة مع حزم أخرى: نحذف ما يخصّنا فقط)
for (const sql of [`DELETE FROM biz_threads WHERE biz_id LIKE 'bi-%' OR user_id IN ${ids}`, "DELETE FROM content_reports WHERE target_type='biz-msg'", "DELETE FROM content_report_actions WHERE target_type='biz-msg'",
  "DELETE FROM biz_orders WHERE biz_id LIKE 'bi-%'", "DELETE FROM biz_items WHERE biz_id LIKE 'bi-%'", "DELETE FROM biz_staff WHERE biz_id LIKE 'bi-%'", "DELETE FROM biz WHERE id LIKE 'bi-%'",
  `DELETE FROM user_blocks WHERE user_id IN ${ids} OR blocked_id IN ${ids}`, `DELETE FROM user_flags WHERE user_id IN ${ids}`]) { try { await pool.query(sql); } catch { /* أول تشغيل */ } }

const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
app.register((await import('../business.js')).default, { pool, auth });
app.register((await import('../safety.js')).default, { pool, auth });
app.register((await import('../biz_inbox.js')).default, { pool, auth });
await app.ready(); await new Promise((r) => setTimeout(r, 300));
const sent = [];
globalThis.naslifeNotify = async (to, payload) => { sent.push({ ids: [].concat(to).filter((x) => x !== payload.exclude), ...payload }); };
globalThis.naslifeNotifyAdmins = async (payload) => { sent.push({ ids: ['admins'], ...payload }); };
globalThis.naslifeIsAdmin = async (u) => u === A;
delete globalThis.naslifeIsSuspended; // بلا admin.js: الإيقاف من user_flags مباشرة
const take = (kind) => { const out = sent.filter((n) => !kind || n.kind === kind); sent.length = 0; return out; };

const call = async (method, url, { body = {}, user = C, expect } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json' }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url} [${user}] -> ${r.statusCode}`, r.statusCode === expect ? '' : JSON.stringify(j).slice(0, 220));
  return j;
};
const P = (n) => `/chat/media/k9x1zz-abcdef0123456789abcdef0${n}.jpg`;

// ---- التجهيز: دائرة موثّقة بفريق كامل، وغير موثّقة، وبلا مالك، ومخفية، وست دوائر لمالك آخر لحدّ المحادثات اليومي
const mk = (id, owner, { verified = false, hidden = false, active = true } = {}) =>
  pool.query("INSERT INTO biz(id,name,name_ar,category,lat,lng,owner_id,verified,hidden,active,logo_url) VALUES($1,$2,$2,'shop',21.55,39.17,$3,$4,$5,$6,$7)", [id, 'دائرة ' + id, owner, verified, hidden, active, '/chat/media/logo-' + id + '.png']);
await mk('bi-shop', O, { verified: true });
await mk('bi-unver', O);
await mk('bi-noowner', null);
await mk('bi-hidden', O, { hidden: true });
for (let i = 1; i <= 6; i++) await mk('bi-c' + i, O2, { verified: true });
await pool.query("INSERT INTO biz_staff(biz_id,user_id,role) VALUES('bi-shop',$1,'manager'),('bi-shop',$2,'staff'),('bi-shop',$3,'hr')", [M, S, H]);
await pool.query("INSERT INTO biz_items(id,biz_id,kind,title,price) VALUES('bi-shop-oil','bi-shop','product','زيت',5000),('bi-c1-x','bi-c1','product','آخر',100)");
const order = (await pool.query("INSERT INTO biz_orders(id,biz_id,item_id,user_id,kind,total,code) VALUES(gen_random_uuid(),'bi-shop','bi-shop-oil',$1,'product',5000,'BI-' || substr(md5(random()::text),1,8)) RETURNING id, code", [C])).rows[0];
const order2 = (await pool.query("INSERT INTO biz_orders(id,biz_id,item_id,user_id,kind,total,code) VALUES(gen_random_uuid(),'bi-shop','bi-shop-oil',$1,'product',5000,'BI-' || substr(md5(random()::text),1,8)) RETURNING id", [C2])).rows[0];

// ---- الحالة والدخول
const st = await call('GET', '/bizinbox/status', { user: null, expect: 200 });
check(st.ok && st.perMin === 30 && st.threadsPerDay === 5 && st.maxPhotos === 4 && st.roles.join() === 'owner,manager,staff', 'status: limits and inbox roles', JSON.stringify(st));
await call('GET', '/biz/bi-shop/thread', { user: null, expect: 401 });
await call('POST', '/biz/bi-shop/thread', { user: null, body: { text: 'هلا' }, expect: 401 });
await call('GET', '/bizinbox/threads', { user: null, expect: 401 });

console.log('\n--- start a thread');
let g = await call('GET', '/biz/bi-shop/thread', { expect: 200 });
check(g.thread === null && g.canSend === true && g.reason === null && g.biz.verified === true && g.biz.name === 'دائرة bi-shop' && g.biz.logoUrl, 'before the first message: no thread, can send, circle name/logo/verified', JSON.stringify(g).slice(0, 200));
check(g.orders.length === 1 && g.orders[0].id === order.id && g.orders[0].code === order.code && g.orders[0].title === 'زيت', 'my orders at this circle come with the thread for the reference card');
for (const [u, label] of [[O, 'owner'], [S, 'staff'], [H, 'hr']]) {
  const own = await call('GET', '/biz/bi-shop/thread', { user: u, expect: 200 });
  check(own.canSend === false && own.reason === 'own-circle' && own.orders.length === 0, `the ${label} cannot message their own circle as a customer`);
}
check((await call('POST', '/biz/bi-shop/thread', { user: H, body: { text: 'تجربة' }, expect: 400 })).error === 'own-circle', 'POST from an hr member → own-circle');
check((await call('POST', '/biz/bi-noowner/thread', { body: { text: 'هل أنتم موجودون؟' }, expect: 409 })).error === 'no-owner', 'a circle without an owner cannot be messaged (nobody to answer)');
await call('GET', '/biz/bi-hidden/thread', { expect: 404 });
check((await call('POST', '/biz/bi-hidden/thread', { body: { text: 'هلا' }, expect: 409 })).error === 'unavailable', 'a circle hidden by moderation → unavailable');
await call('GET', '/biz/nope-nope/thread', { expect: 404 });

// التحقق من الجسم قبل إنشاء أي شيء
check((await call('POST', '/biz/bi-shop/thread', { body: { text: '' }, expect: 400 })).error === 'empty', 'empty message refused');
check((await call('POST', '/biz/bi-shop/thread', { body: { text: 'صور', photos: [P(1), P(2), P(3), P(4), P(5)] }, expect: 400 })).error === 'too-many-photos', 'five photos refused (max four)');
check((await call('POST', '/biz/bi-shop/thread', { body: { text: 'صورة', photos: ['https://evil.example/x.jpg'] }, expect: 400 })).error === 'bad-photo', 'outside photo URL refused (only /chat/media)');
const bw = await call('POST', '/biz/bi-shop/thread', { body: { text: 'يا شرموطه' }, expect: 400 });
check(bw.error === 'banned-words', 'banned words refused on the first message', JSON.stringify(bw));
check((await call('POST', '/biz/bi-shop/thread', { body: { text: 'طلبي', ref: { kind: 'order', id: order2.id } }, expect: 400 })).error === 'bad-ref', 'another customer\'s order cannot be referenced');
check((await call('POST', '/biz/bi-shop/thread', { body: { text: 'هذا', ref: { kind: 'item', id: 'bi-c1-x' } }, expect: 400 })).error === 'bad-ref', 'an item of another circle cannot be referenced');
check((await call('POST', '/biz/bi-shop/thread', { body: { text: 'هذا', ref: { kind: 'listing', id: 'x' } }, expect: 400 })).error === 'bad-ref', 'unknown reference kind refused');
check((await pool.query("SELECT count(*)::int AS n FROM biz_threads WHERE user_id=$1", [C])).rows[0].n === 0, 'no thread was created by the refused attempts');
take();

const s1 = await call('POST', '/biz/bi-shop/thread', { body: { text: 'السلام عليكم، وصل طلبي ناقص', photos: ['https://naslife.app' + P(1)], ref: { kind: 'order', id: order.id }, clientId: 'c-0001' }, expect: 200 });
const T = s1.thread.id;
check(/^[0-9a-f-]{36}$/.test(T) && s1.thread.status === 'open' && s1.thread.biz.id === 'bi-shop' && s1.thread.unread === 0, 'first message creates the thread', JSON.stringify(s1.thread));
check(s1.message.side === 'customer' && s1.message.mine === true && s1.message.photos[0] === P(1) && s1.message.ref?.kind === 'order' && s1.message.ref.code === order.code && s1.message.ref.status === 'confirmed', 'message stores the photo path on our origin and resolves the order card', JSON.stringify(s1.message));
let ns = take('biz_inbox_message');
check(ns.length === 1 && ['SI0000001', 'SI0000002', 'SI0000003'].every((u) => ns[0].ids.includes(u)) && !ns[0].ids.includes(H) && ns[0].data.threadId === T && ns[0].data.manage === true && ns[0].data.bizId === 'bi-shop',
  'team (owner, manager, staff — not hr) notified with the thread id', JSON.stringify(ns));
const s2 = await call('POST', '/biz/bi-shop/thread', { body: { text: 'هذا الصنف تحديداً', ref: { kind: 'item', id: 'bi-shop-oil' } }, expect: 200 });
check(s2.thread.id === T && s2.message.ref?.kind === 'item' && s2.message.ref.title === 'زيت' && s2.message.ref.price === 5000, 'second message continues the same thread with an item card');
check(take('biz_inbox_message').length === 0, 'second unread message does not notify the team again');
const dup = await call('POST', '/biz/bi-shop/thread', { body: { text: 'السلام عليكم، وصل طلبي ناقص', clientId: 'c-0001' }, expect: 200 });
check(dup.duplicate === true && dup.message.id === s1.message.id, 'same clientId returns the stored message (outbox retry)');
check((await pool.query("SELECT count(*)::int AS n FROM biz_thread_msgs WHERE thread_id=$1", [T])).rows[0].n === 2, 'the duplicate did not add a row');
check((await call('POST', `/bizinbox/threads/${T}/messages`, { body: { text: 'x', clientId: 'bad id!' }, expect: 400 })).error === 'bad-client-id', 'malformed clientId refused');

console.log('\n--- customer list and unread');
let mine = await call('GET', '/bizinbox/threads', { expect: 200 });
check(mine.threads.length === 1 && mine.threads[0].id === T && mine.threads[0].lastText === 'هذا الصنف تحديداً' && mine.threads[0].lastSide === 'customer' && mine.threads[0].unread === 0 && mine.unread === 0, 'my circle threads list', JSON.stringify(mine).slice(0, 220));

console.log('\n--- team side and roles');
let inbox = await call('GET', '/biz/bi-shop/inbox', { user: O, expect: 200 });
check(inbox.counts.open === 1 && inbox.counts.unread === 1 && inbox.threads.length === 1 && inbox.threads[0].customer.id === C && inbox.threads[0].customer.nickname === 'cust' && inbox.threads[0].unread === 2 && inbox.threads[0].assignee === null,
  'owner sees the thread with two unread and the customer', JSON.stringify(inbox).slice(0, 300));
check(inbox.team.map((x) => x.id + ':' + x.role).join() === `${O}:owner,${M}:manager,${S}:staff` && inbox.canAssignOthers === true, 'inbox team = owner, manager, staff (no hr)');
check((await call('GET', '/biz/bi-shop/inbox', { user: S, expect: 200 })).canAssignOthers === false, 'staff reads the inbox but cannot assign others');
for (const [u, label] of [[H, 'hr'], [A, 'system admin'], [X, 'stranger'], [C, 'customer']]) {
  await call('GET', '/biz/bi-shop/inbox', { user: u, expect: 403 });
  await call('GET', `/bizinbox/threads/${T}`, { user: u === C ? X : u, expect: 404 });
  check(true, `${label}: no inbox access`);
}
check((await call('GET', '/biz/bi-shop/inbox/unread', { user: S, expect: 200 })).unread === 1, 'unread badge for the dashboard tab');
await call('GET', '/bizinbox/threads/not-a-uuid', { user: S, expect: 404 });
let tv = await call('GET', `/bizinbox/threads/${T}`, { user: S, expect: 200 });
check(tv.viewer === 'team' && tv.role === 'staff' && tv.messages.length === 2 && tv.thread.customer.id === C && tv.canSend === true && tv.team.length === 3 && tv.orders[0].id === order.id, 'staff reads the thread with the customer\'s orders', JSON.stringify(tv).slice(0, 200));

const r1 = await call('POST', `/bizinbox/threads/${T}/messages`, { user: S, body: { text: 'نعتذر، نرسل الناقص اليوم', ref: { kind: 'order', id: order.id } }, expect: 200 });
check(r1.message.side === 'team' && r1.message.mine === true && r1.message.sender?.id === S && r1.thread.unread === 0, 'team reply records the sender for the team');
check((await pool.query("SELECT sender_id FROM biz_thread_msgs WHERE id=$1", [r1.message.id])).rows[0].sender_id === S, 'the replying member is stored on the message');
ns = take('biz_inbox_reply');
check(ns.length === 1 && ns[0].ids.join() === C && ns[0].title.includes('دائرة bi-shop') && ns[0].data.threadId === T && ns[0].data.manage === undefined, 'customer notified of the reply under the circle name', JSON.stringify(ns));
check((await call('GET', '/biz/bi-shop/inbox/unread', { user: O, expect: 200 })).unread === 0, 'replying clears the team unread');
let cv = await call('GET', `/bizinbox/threads/${T}`, { expect: 200 });
const teamMsg = cv.messages.find((m) => m.side === 'team');
check(cv.viewer === 'customer' && cv.thread.unread === 1 && teamMsg && teamMsg.mine === false && !('sender' in teamMsg) && cv.thread.biz.name === 'دائرة bi-shop' && !('team' in cv), 'customer sees the reply as the circle (no team member identity)', JSON.stringify(teamMsg));
check((await call('GET', '/bizinbox/threads', { expect: 200 })).unread === 1, 'customer list counts the thread with an unread reply');
await call('POST', `/bizinbox/threads/${T}/messages`, { user: M, body: { text: 'وسنعوّضك بخصم' }, expect: 200 });
check(take('biz_inbox_reply').length === 0, 'a second unread reply does not notify the customer again');
await call('POST', `/bizinbox/threads/${T}/read`, { expect: 200 });
cv = await call('GET', `/bizinbox/threads/${T}`, { expect: 200 });
check(cv.thread.unread === 0 && (await call('GET', '/bizinbox/threads', { expect: 200 })).unread === 0, 'customer read clears the customer unread');
check(!!(await call('GET', `/bizinbox/threads/${T}`, { user: S, expect: 200 })).thread.seenAt, 'team sees when the customer read the thread');
await call('POST', `/bizinbox/threads/${T}/messages`, { user: M, body: { text: 'هل وصلك؟' }, expect: 200 });
check(take('biz_inbox_reply').length === 1, 'after the customer read, the next reply notifies again');
await call('POST', `/bizinbox/threads/${T}/read`, { expect: 200 });
await call('POST', `/bizinbox/threads/${T}/messages`, { user: H, body: { text: 'من hr' }, expect: 404 });
await call('POST', `/bizinbox/threads/${T}/messages`, { user: A, body: { text: 'من الإدارة' }, expect: 404 });
check((await call('POST', `/bizinbox/threads/${T}/messages`, { user: S, body: { text: 'fuck this' }, expect: 400 })).error === 'banned-words', 'banned words refused on team replies too');

console.log('\n--- assignment, filters, close and reopen');
await call('POST', `/bizinbox/threads/${T}/assign`, { user: S, body: { userId: M }, expect: 403 });
let as = await call('POST', `/bizinbox/threads/${T}/assign`, { user: S, body: { userId: S }, expect: 200 });
check(as.thread.assignee?.id === S && take('biz_inbox_assigned').length === 0, 'staff takes the thread (no self notification)');
check((await call('GET', '/biz/bi-shop/inbox?filter=mine', { user: S, expect: 200 })).threads.length === 1, 'mine filter for the staff');
as = await call('POST', `/bizinbox/threads/${T}/assign`, { user: O, body: { userId: M }, expect: 200 });
ns = take('biz_inbox_assigned');
check(as.thread.assignee?.id === M && ns.length === 1 && ns[0].ids.join() === M && ns[0].data.threadId === T && ns[0].data.manage === true, 'owner assigns to the manager, who is notified', JSON.stringify(ns));
check((await call('GET', '/biz/bi-shop/inbox?filter=mine', { user: S, expect: 200 })).threads.length === 0 && (await call('GET', '/biz/bi-shop/inbox?filter=mine', { user: M, expect: 200 })).counts.mine === 1, 'mine follows the assignee');
await call('POST', `/bizinbox/threads/${T}/assign`, { user: S, body: { userId: null }, expect: 403 });
check((await call('POST', `/bizinbox/threads/${T}/assign`, { user: M, body: { userId: H }, expect: 400 })).error === 'not-in-team', 'hr is not an inbox member to assign');
check((await call('POST', `/bizinbox/threads/${T}/assign`, { user: M, body: { userId: X }, expect: 400 })).error === 'not-in-team', 'a stranger cannot be assigned');
await call('POST', `/bizinbox/threads/${T}/assign`, { user: C, body: { userId: S }, expect: 403 });
// المسندة: رسالة العميل تنبّه المسؤول وحده
await call('POST', `/bizinbox/threads/${T}/messages`, { body: { text: 'شكراً' }, expect: 200 });
ns = take('biz_inbox_message');
check(ns.length === 1 && ns[0].ids.join() === M, 'an assigned thread notifies only the assignee', JSON.stringify(ns.map((n) => n.ids)));
await call('POST', `/bizinbox/threads/${T}/close`, { user: C, expect: 403 });
let cl = await call('POST', `/bizinbox/threads/${T}/close`, { user: S, expect: 200 });
check(cl.thread.status === 'closed' && cl.thread.closedAt, 'any inbox member closes the thread');
inbox = await call('GET', '/biz/bi-shop/inbox', { user: O, expect: 200 });
check(inbox.threads.length === 0 && inbox.counts.closed === 1 && inbox.counts.open === 0, 'open filter (default) hides the closed thread');
check((await call('GET', '/biz/bi-shop/inbox?filter=closed', { user: O, expect: 200 })).threads[0]?.id === T && (await call('GET', '/biz/bi-shop/inbox?filter=all', { user: O, expect: 200 })).threads.length === 1, 'closed and all filters');
check((await call('GET', '/biz/bi-shop/thread', { expect: 200 })).thread.status === 'closed', 'the customer sees the thread closed');
await call('POST', `/bizinbox/threads/${T}/read`, { user: M, expect: 200 });
take();
await call('POST', '/biz/bi-shop/thread', { body: { text: 'عندي سؤال آخر' }, expect: 200 });
check((await call('GET', `/bizinbox/threads/${T}`, { user: O, expect: 200 })).thread.status === 'open' && take('biz_inbox_message').length === 1, 'a new customer message reopens the closed thread and notifies');
await call('POST', `/bizinbox/threads/${T}/close`, { user: M, expect: 200 });
check((await call('POST', `/bizinbox/threads/${T}/reopen`, { user: M, expect: 200 })).thread.status === 'open', 'reopen by the team');

console.log('\n--- unverified circle');
const u1 = await call('POST', '/biz/bi-unver/thread', { body: { text: 'هل عندكم توصيل؟' }, expect: 200 });
check(u1.thread.biz.verified === false && (await call('GET', '/bizinbox/threads', { expect: 200 })).threads.find((t) => t.bizId === 'bi-unver')?.biz.verified === false, 'unverified circles can be messaged and carry verified:false for the warning');

console.log('\n--- blocks');
// العميل الثاني محظور من المالك: القناة مغلقة للدائرة كلها
await pool.query("INSERT INTO user_blocks(user_id,blocked_id) VALUES($1,$2)", [O, C2]);
check((await call('POST', '/biz/bi-shop/thread', { user: C2, body: { text: 'هلا' }, expect: 403 })).error === 'blocked', 'a customer blocked by the owner cannot message the circle');
g = await call('GET', '/biz/bi-shop/thread', { user: C2, expect: 200 });
check(g.canSend === false && g.reason === 'blocked' && g.thread === null, 'GET shows the blocked reason');
await pool.query("DELETE FROM user_blocks WHERE user_id=$1 AND blocked_id=$2", [O, C2]);
const t2 = (await call('POST', '/biz/bi-shop/thread', { user: C2, body: { text: 'بعد فك الحظر' }, expect: 200 })).thread.id;
// حظر بين الموظف والعميل الثاني: يخفي المحادثة عن الموظف وحده
await pool.query("INSERT INTO user_blocks(user_id,blocked_id) VALUES($1,$2)", [C2, S]);
const sList = await call('GET', '/biz/bi-shop/inbox?filter=all', { user: S, expect: 200 });
check(!sList.threads.some((t) => t.id === t2) && (await call('GET', '/biz/bi-shop/inbox?filter=all', { user: M, expect: 200 })).threads.some((t) => t.id === t2), 'a member blocked with the customer does not see the thread; others do');
await call('GET', `/bizinbox/threads/${t2}`, { user: S, expect: 404 });
await call('POST', `/bizinbox/threads/${t2}/messages`, { user: S, body: { text: 'هلا' }, expect: 404 });
check((await call('POST', `/bizinbox/threads/${t2}/assign`, { user: O, body: { userId: S }, expect: 403 })).error === 'blocked', 'cannot assign the thread to a member blocked with the customer');
await call('POST', `/bizinbox/threads/${t2}/read`, { user: M, expect: 200 });
take();
await call('POST', `/bizinbox/threads/${t2}/messages`, { user: C2, body: { text: 'أحتاج رداً' }, expect: 200 });
ns = take('biz_inbox_message');
check(ns.length === 1 && !ns[0].ids.includes(S) && ns[0].ids.includes(O) && ns[0].ids.includes(M), 'the blocked member is not notified', JSON.stringify(ns.map((n) => n.ids)));
await pool.query("DELETE FROM user_blocks WHERE user_id=$1 AND blocked_id=$2", [C2, S]);
// العميل يحظر المالك بعد المحادثة: تختفي من قائمته، ولا يرد الفريق
await pool.query("INSERT INTO user_blocks(user_id,blocked_id) VALUES($1,$2)", [C2, O]);
check(!(await call('GET', '/bizinbox/threads', { user: C2, expect: 200 })).threads.some((t) => t.id === t2), 'blocking the owner hides the thread from the customer list');
await call('GET', `/bizinbox/threads/${t2}`, { user: C2, expect: 404 });
check((await call('POST', `/bizinbox/threads/${t2}/messages`, { user: M, body: { text: 'هلا' }, expect: 403 })).error === 'blocked', 'the team cannot reply while the customer and the owner are blocked');
check((await call('GET', `/bizinbox/threads/${t2}`, { user: M, expect: 200 })).canSend === false, 'the team view shows canSend:false');
await pool.query("DELETE FROM user_blocks WHERE user_id=$1 AND blocked_id=$2", [C2, O]);

console.log('\n--- suspended accounts');
await pool.query("INSERT INTO user_flags(user_id,suspended) VALUES($1,true)", [SUS]);
check((await call('POST', '/biz/bi-shop/thread', { user: SUS, body: { text: 'هلا' }, expect: 403 })).error === 'suspended', 'a suspended account cannot message');
check((await call('GET', '/biz/bi-shop/thread', { user: SUS, expect: 200 })).reason === 'suspended', 'GET shows the suspended reason');
await pool.query("INSERT INTO user_flags(user_id,suspended) VALUES($1,true)", [S]);
check((await call('POST', `/bizinbox/threads/${T}/messages`, { user: S, body: { text: 'رد' }, expect: 403 })).error === 'suspended', 'a suspended team member cannot reply');
await pool.query("DELETE FROM user_flags WHERE user_id=$1", [S]);

console.log('\n--- rate limits');
let lim = null;
for (let i = 1; i <= 30; i++) lim = await call('POST', '/biz/bi-shop/thread', { user: LIM, body: { text: 'رسالة ' + i } });
check(lim?.message?.text === 'رسالة 30', '30 messages within a minute are accepted');
const rl = await call('POST', '/biz/bi-shop/thread', { user: LIM, body: { text: 'رسالة 31' }, expect: 429 });
check(rl.error === 'rate-limit' && rl.perMin === 30, 'the 31st message in a minute → 429 rate-limit');
await pool.query("UPDATE biz_thread_msgs SET created_at = created_at - interval '2 minutes' WHERE sender_id=$1", [LIM]);
await call('POST', '/biz/bi-shop/thread', { user: LIM, body: { text: 'بعد دقيقة' }, expect: 200 });
const lt = (await call('GET', '/bizinbox/threads', { user: LIM, expect: 200 })).threads[0].id;
const page = await call('GET', `/bizinbox/threads/${lt}`, { user: LIM, expect: 200 });
check(page.messages.length === 31 && page.hasMore === false && page.messages[0].text === 'رسالة 1' && page.messages.at(-1).text === 'بعد دقيقة', 'thread messages are oldest first');
const older = await call('GET', `/bizinbox/threads/${lt}?before=${encodeURIComponent(page.messages[10].createdAt)}`, { user: LIM, expect: 200 });
check(older.messages.length === 10 && older.messages.at(-1).text === 'رسالة 10', 'before= pages back to older messages');
for (let i = 1; i <= 5; i++) await call('POST', `/biz/bi-c${i}/thread`, { user: DAY, body: { text: 'سؤال' }, expect: 200 });
const td = await call('POST', '/biz/bi-c6/thread', { user: DAY, body: { text: 'سؤال' }, expect: 429 });
check(td.error === 'too-many-threads' && td.perDay === 5, 'the sixth new thread in a day → 429 too-many-threads');
await call('POST', '/biz/bi-c1/thread', { user: DAY, body: { text: 'متابعة' }, expect: 200 });
check(true, 'continuing an existing thread is not counted as a new one');

console.log('\n--- reports and admin reading');
const custMsg = s1.message.id, staffMsg = r1.message.id;
check((await call('POST', '/safety/report', { user: X, body: { targetType: 'biz-msg', targetId: custMsg, reason: 'سبام' }, expect: 404 })).error === 'not-found', 'a stranger cannot report a private message');
check((await call('POST', '/safety/report', { user: C, body: { targetType: 'biz-msg', targetId: custMsg, reason: 'x' }, expect: 400 })).error === 'own-content', 'own message cannot be reported');
check((await call('POST', '/safety/report', { user: M, body: { targetType: 'biz-msg', targetId: staffMsg, reason: 'x' }, expect: 400 })).error === 'own-content', 'a teammate\'s reply cannot be reported by the team');
check((await call('POST', '/safety/report', { user: H, body: { targetType: 'biz-msg', targetId: custMsg, reason: 'x' }, expect: 404 })).error === 'not-found', 'hr (outside the inbox) cannot report');
await call('GET', `/adminapi/bizinbox/reported/${custMsg}`, { user: A, expect: 404 });
check(true, 'no admin reading before a report');
take();
const rep = await call('POST', '/safety/report', { user: S, body: { targetType: 'biz-msg', targetId: custMsg, reason: 'إزعاج أو سبام' }, expect: 200 });
check(rep.ok && rep.reports === 1 && rep.hidden === false, 'the team reports the customer message (below the auto-hide threshold)');
check(take('report_new').length === 1, 'admins are told about the new report');
await call('POST', '/safety/report', { user: C, body: { targetType: 'biz-msg', targetId: staffMsg, reason: 'تحرش أو تنمر' }, expect: 200 });
await call('GET', `/adminapi/bizinbox/reported/${custMsg}`, { user: X, expect: 403 });
await call('GET', `/adminapi/bizinbox/reported/${custMsg}`, { user: O, expect: 403 });
const ar = await call('GET', `/adminapi/bizinbox/reported/${custMsg}`, { user: A, expect: 200 });
check(ar.reports === 1 && ar.messages.some((m) => m.id === custMsg && m.reported === true) && ar.messages.length <= 21 && ar.thread.customer.id === C && ar.biz.id === 'bi-shop', 'admin reads the reported message with its context', JSON.stringify(ar).slice(0, 200));
check(ar.messages.find((m) => m.side === 'team')?.sender?.id != null, 'admin sees which member wrote each team reply');
const q = await call('GET', '/adminapi/moderation?type=biz-msg', { user: A, expect: 200 });
const qi = q.items.find((i) => i.targetId === custMsg);
check(qi && qi.typeName === 'رسالة خاصة مع دائرة' && qi.text.includes('وصل طلبي ناقص') && qi.bizId === 'bi-shop' && qi.owner?.id === C, 'the reported message appears in the moderation queue', JSON.stringify(qi));
await call('GET', `/adminapi/bizinbox/reported/${s2.message.id}`, { user: A, expect: 404 });
check(true, 'an unreported message of the same thread is not readable alone');
await call('GET', '/biz/bi-shop/inbox', { user: A, expect: 403 });
check(true, 'still no general admin reading of the inbox');
const hid = await call('POST', `/adminapi/moderation/biz-msg/${staffMsg}`, { user: A, body: { action: 'hide', note: 'مخالفة' }, expect: 200 });
check(hid.changed === true && hid.status === 'hidden', 'admin hides the reported team reply');
ns = take('content_hidden');
check(ns.length === 1 && ns[0].ids.join() === S && ns[0].data.threadId === T && ns[0].data.targetType === 'biz-msg', 'the writer is told, with the thread id', JSON.stringify(ns));
cv = await call('GET', `/bizinbox/threads/${T}`, { expect: 200 });
const hm = cv.messages.find((m) => m.id === staffMsg);
check(hm.hidden === true && hm.text === '' && hm.photos.length === 0 && hm.ref === null, 'a hidden message keeps its place without content');
check((await call('POST', `/adminapi/moderation/biz-msg/${staffMsg}`, { user: A, body: { action: 'restore' }, expect: 200 })).status === 'visible', 'restore brings it back');

const upRef = await call('POST', '/biz/bi-shop/thread', { body: { text: 'الطلب نفسه', ref: { kind: 'order', id: order.id.toUpperCase() } }, expect: 200 });
check(upRef.message.ref?.code === order.code && !upRef.message.ref.missing, 'an upper-case order id still resolves the order card');

console.log('\n--- clean up');
await pool.query(`DELETE FROM biz_threads WHERE biz_id LIKE 'bi-%' OR user_id IN ${ids}`);
await pool.query("DELETE FROM content_reports WHERE target_type='biz-msg'");
await pool.query("DELETE FROM biz_orders WHERE biz_id LIKE 'bi-%'"); await pool.query("DELETE FROM biz_items WHERE biz_id LIKE 'bi-%'");
await pool.query("DELETE FROM biz_staff WHERE biz_id LIKE 'bi-%'"); await pool.query("DELETE FROM biz WHERE id LIKE 'bi-%'");
await pool.query(`DELETE FROM user_flags WHERE user_id IN ${ids}`);
console.log(fails ? `\n${fails} FAILED` : '\nALL OK');
await app.close(); await pool.end();
process.exit(fails ? 1 : 0);
