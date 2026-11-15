// توزيع التذاكر (ticket_share.js) على Postgres المحلي: الإرسال لمستخدم (القبول برمز جديد، الرفض، الاسترجاع)، الرابط لشخص واحد
// (المعاينة بلا حساب، الاستلام، إعادة استعمال الرابط)، القواعد (تحويل معلّق واحد، تذكرة مستعملة أو لغيري، الحظر، النفس)،
// الدخول بالرمز الجديد لا القديم، قائمة الحضور باسم الحامل، واسترداد الإلغاء لمن دفع لا لمن يحمل.
import Fastify from 'fastify';
import pg from 'pg';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NODE_ENV = 'test';
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: process.env.NASLIFE_TEST_DB || 'naslife_test' });
const HOST = 'SA0000871', BUYER = 'SA0000872', NORA = 'SA0000873', KHALID = 'SA0000874', FOE = 'SA0000875';
const OURS = [HOST, BUYER, NORA, KHALID, FOE];
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query(`INSERT INTO users(id,nickname,created_at) VALUES('${HOST}','tshost',now()-interval '30 days'),('${BUYER}','tsbuyer',now()-interval '30 days'),('${NORA}','tsnora',now()-interval '30 days'),
  ('${KHALID}','tskhalid',now()-interval '30 days'),('${FOE}','tsfoe',now()-interval '30 days') ON CONFLICT (id) DO UPDATE SET nickname=EXCLUDED.nickname`);
await pool.query("CREATE TABLE IF NOT EXISTS user_flags (user_id TEXT PRIMARY KEY, suspended BOOLEAN NOT NULL DEFAULT false, note TEXT, updated_at TIMESTAMPTZ DEFAULT now())");
for (const sql of ['DELETE FROM ticket_transfers WHERE from_id = ANY($1) OR to_id = ANY($1)', 'DELETE FROM tickets WHERE user_id = ANY($1) OR payer_id = ANY($1)', 'DELETE FROM events WHERE host_id = ANY($1)',
  'DELETE FROM wallet_tx WHERE user_id = ANY($1)', 'DELETE FROM wallet_accounts WHERE user_id = ANY($1)', 'DELETE FROM user_flags WHERE user_id = ANY($1)']) {
  try { await pool.query(sql, [OURS]); } catch { /* أول تشغيل: الجدول لم يُنشأ بعد */ }
}
const notes = []; globalThis.naslifeNotify = async (ids, p) => { notes.push({ ids: [].concat(ids), ...p }); };
globalThis.naslifeSettings = { maxTopup: 10000000 };
globalThis.naslifeAdultOk = async () => true;
globalThis.naslifeBlockedIds = async (u) => (u === FOE ? [BUYER] : []);
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
app.register((await import('../commerce.js')).default, { pool, auth });
app.register((await import('../ticket_share.js')).default, { pool, auth });
await app.ready();

let fails = 0;
const call = async (method, url, { body, user = BUYER, expect } = {}) => {
  const headers = user ? { 'x-user': user } : {};
  const r = await app.inject({ method, url, headers: { ...headers, ...(method === 'GET' || method === 'DELETE' ? {} : { 'content-type': 'application/json' }) }, payload: method === 'GET' || method === 'DELETE' ? undefined : JSON.stringify(body ?? {}) });
  let j; try { j = r.json(); } catch { j = r.body; }
  const ok = expect == null || r.statusCode === expect; if (!ok) fails++;
  console.log((ok ? 'OK  ' : 'FAIL') + ' ' + method + ' ' + url.slice(0, 70) + ' -> ' + r.statusCode + (ok ? '' : ' expected ' + expect + ' ' + JSON.stringify(j).slice(0, 160)));
  return Object.assign(j ?? {}, { _status: r.statusCode, _headers: r.headers });
};
const check = (ok, m) => { if (!ok) fails++; console.log((ok ? 'OK  ' : 'FAIL') + ' ' + m); };
const balance = async (u) => Number((await pool.query('SELECT balance FROM wallet_accounts WHERE user_id=$1', [u])).rows[0]?.balance ?? 0);
const mine = async (u) => (await call('GET', '/tickets', { user: u, expect: 200 }));

// فعالية بتذكرة مدفوعة (50 ريالاً)، والمشتري يأخذ أربع
await call('POST', '/wallet/topup', { body: { amount: 100000 }, expect: 200 });
const ev = await call('POST', '/events', { user: HOST, body: { title: 'أمسية الاختبار', startsAt: new Date(Date.now() + 86400000).toISOString(), placeName: 'المسرح', tiers: [{ name: 'عادي', price: 5000, quantity: 20 }] }, expect: 200 });
const bought = await call('POST', `/events/${ev.id}/tickets`, { body: { tierId: ev.tiers[0].id, qty: 4 }, expect: 200 });
const [T1, T2, T3, T4] = [bought[0], bought[1], bought[2], bought[3]];
check(bought.length === 4 && (await balance(BUYER)) === 80000, 'bought four tickets for 200 SAR');

// ---- القواعد قبل الإرسال
await call('GET', '/tickets/shares', { user: null, expect: 401 });
await call('POST', `/tickets/${T2.id}/send`, { user: null, body: { userId: NORA }, expect: 401 });
check((await call('POST', `/tickets/${T2.id}/send`, { body: { userId: BUYER }, expect: 400 })).error === 'self', 'cannot send to myself');
check((await call('POST', `/tickets/${T2.id}/send`, { body: { userId: 'SA9999999' }, expect: 400 })).error === 'bad-user', 'unknown user is refused');
check((await call('POST', `/tickets/${T2.id}/send`, { body: {}, expect: 400 })).error === 'bad-user', 'missing user is refused');
check((await call('POST', `/tickets/${T2.id}/send`, { body: { userId: FOE }, expect: 403 })).error === 'blocked', 'a block in either direction stops the send');
check((await call('POST', `/tickets/${T2.id}/send`, { user: NORA, body: { userId: KHALID }, expect: 404 })).error === 'not-found', "someone else's ticket is not found");
await call('POST', '/tickets/not-a-uuid/send', { body: { userId: NORA }, expect: 404 });

// ---- إرسال لمستخدم: معلّق، التذكرة ما زالت عندي، وتظهر عنده واردة
notes.length = 0;
const s2 = await call('POST', `/tickets/${T2.id}/send`, { body: { userId: NORA }, expect: 200 });
check(s2.mode === 'user' && s2.to?.id === NORA && s2.to.nickname === 'tsnora' && s2.url === null && s2.ticketId === T2.id, 'outgoing item names the recipient');
check(notes.some((n) => n.kind === 'ticket_gift' && n.ids.includes(NORA) && n.data.transferId === s2.transferId && n.data.eventId === ev.id), 'recipient is notified');
check((await call('POST', `/tickets/${T2.id}/send`, { body: { userId: KHALID }, expect: 409 })).error === 'already-pending', 'one pending transfer per ticket');
check((await call('POST', `/tickets/${T2.id}/link`, { expect: 409 })).error === 'already-pending', 'no link while pending to a user');
check((await mine(BUYER)).length === 4 && (await mine(NORA)).length === 0, 'the ticket stays with the sender until accepted');
let sh = await call('GET', '/tickets/shares', { expect: 200 });
check(sh.outgoing.length === 1 && sh.incoming.length === 0, 'sender sees one outgoing');
sh = await call('GET', '/tickets/shares', { user: NORA, expect: 200 });
check(sh.incoming.length === 1 && sh.incoming[0].from.id === BUYER && sh.incoming[0].ticket.title === 'أمسية الاختبار' && sh.incoming[0].ticket.tier === 'عادي' && !('code' in sh.incoming[0].ticket), 'recipient sees it incoming, without the entry code');
await call('POST', `/tickets/transfers/${s2.transferId}/accept`, { user: KHALID, expect: 404 });

// ---- القبول: تنتقل برمز جديد، والرمز القديم لا يُدخل، والمرسل يُشعر
notes.length = 0;
const acc = await call('POST', `/tickets/transfers/${s2.transferId}/accept`, { user: NORA, expect: 200 });
check(acc.id === T2.id && acc.code !== T2.code && /^NAS-[0-9A-F]{8}$/.test(acc.code) && acc.status === 'valid' && acc.title === 'أمسية الاختبار', 'accepted ticket has a new code');
check(notes.some((n) => n.kind === 'ticket_accepted' && n.ids.includes(BUYER)), 'sender is told it was accepted');
check((await mine(BUYER)).length === 3 && (await mine(NORA)).length === 1, 'the ticket moved to the recipient');
check((await call('POST', `/tickets/transfers/${s2.transferId}/accept`, { user: NORA, expect: 409 })).error === 'gone', 'accepting twice is gone');
check((await call('POST', `/events/${ev.id}/checkin`, { user: HOST, body: { code: T2.code }, expect: 404 })).error === 'ticket-invalid', 'the old code no longer admits anyone');
const ci = await call('POST', `/events/${ev.id}/checkin`, { user: HOST, body: { code: acc.code }, expect: 200 });
check(ci.holder?.id === NORA, 'the new code admits the new holder');
const att = await call('GET', `/events/${ev.id}/attendees`, { user: HOST, expect: 200 });
check(att.items.some((i) => i.ticketId === T2.id && i.holder.id === NORA && i.checkedIn), 'attendee list shows the holder, not the buyer');
check((await call('POST', `/tickets/${T2.id}/send`, { user: NORA, body: { userId: KHALID }, expect: 409 })).error === 'not-transferable', 'a used ticket cannot be sent on');

// ---- الرفض والاسترجاع
notes.length = 0;
const s3 = await call('POST', `/tickets/${T3.id}/send`, { body: { userId: KHALID }, expect: 200 });
await call('POST', `/tickets/transfers/${s3.transferId}/decline`, { user: NORA, expect: 404 });
await call('POST', `/tickets/transfers/${s3.transferId}/decline`, { user: KHALID, expect: 200 });
check(notes.some((n) => n.kind === 'ticket_declined' && n.ids.includes(BUYER)), 'sender is told it was declined');
check((await call('POST', `/tickets/transfers/${s3.transferId}/accept`, { user: KHALID, expect: 409 })).error === 'gone', 'a declined transfer cannot be accepted');
const s3b = await call('POST', `/tickets/${T3.id}/send`, { body: { userId: KHALID }, expect: 200 });
await call('DELETE', `/tickets/${T3.id}/send`, { user: NORA, expect: 404 });
await call('DELETE', `/tickets/${T3.id}/send`, { expect: 200 });
await call('DELETE', `/tickets/${T3.id}/send`, { expect: 404 });
check((await call('POST', `/tickets/transfers/${s3b.transferId}/accept`, { user: KHALID, expect: 409 })).error === 'gone', 'a recalled transfer cannot be accepted');
check((await call('GET', '/tickets/shares', { user: KHALID, expect: 200 })).incoming.length === 0, 'recalled transfer leaves the inbox');
check((await mine(BUYER)).some((t) => t.id === T3.id && t.code === T3.code), 'recalled ticket keeps its code');

// ---- الرابط: واحد للتذكرة، معاينة بلا حساب، استلام لشخص واحد
const l4 = await call('POST', `/tickets/${T4.id}/link`, { expect: 200 });
check(l4.mode === 'link' && l4.to === null && /^https:\/\/naslife\.app\/t\/[A-Za-z0-9_-]{16,64}$/.test(l4.url), 'link item carries the public url');
const token = l4.url.split('/t/')[1];
check((await call('POST', `/tickets/${T4.id}/link`, { expect: 200 })).url === l4.url, 'asking again returns the same link');
check((await call('POST', `/tickets/${T4.id}/send`, { body: { userId: KHALID }, expect: 409 })).error === 'already-pending', 'no user send while a link is out');
const pv = await call('GET', `/tickets/claim/${token}`, { user: null, expect: 200 });
check(pv.title === 'أمسية الاختبار' && pv.tier === 'عادي' && pv.from.nickname === 'tsbuyer' && pv.status === 'pending' && !('code' in pv), 'preview needs no account and shows no code');
await call('GET', '/tickets/claim/' + 'x'.repeat(24), { user: null, expect: 404 });
await call('GET', '/tickets/claim/bad', { user: null, expect: 404 });
const red = await app.inject({ method: 'GET', url: `/t/${token}` });
check(red.statusCode === 302 && red.headers.location === `/#/t/${token}` && red.headers['x-robots-tag'] === 'noindex', 'public link redirects into the app');
check((await app.inject({ method: 'GET', url: '/t/!!' })).headers.location === '/', 'a malformed link goes home');
await call('POST', '/tickets/claim', { user: null, body: { token }, expect: 401 });
check((await call('POST', '/tickets/claim', { body: { token }, expect: 400 })).error === 'self', 'the sender cannot claim their own link');
const cl = await call('POST', '/tickets/claim', { user: KHALID, body: { token }, expect: 200 });
check(cl.id === T4.id && cl.code !== T4.code, 'claimed by link with a new code');
check((await call('POST', '/tickets/claim', { user: NORA, body: { token }, expect: 409 })).error === 'gone', 'the link works for one person only');
check((await call('GET', `/tickets/claim/${token}`, { user: null, expect: 200 })).status === 'gone', 'preview says gone afterwards');
check((await mine(KHALID)).length === 1 && (await mine(BUYER)).length === 2, 'two tickets left with the buyer');

// ---- تحويل معلّق على تذكرة استُعملت: القبول يجده منتهياً
const s1 = await call('POST', `/tickets/${T1.id}/send`, { body: { userId: NORA }, expect: 200 });
await call('POST', `/events/${ev.id}/checkin`, { user: HOST, body: { code: T1.code }, expect: 200 });
check((await call('POST', `/tickets/transfers/${s1.transferId}/accept`, { user: NORA, expect: 409 })).error === 'gone', 'a ticket used while pending cannot be accepted');
check((await call('GET', '/tickets/shares', { expect: 200 })).outgoing.length === 0, 'and it leaves the outgoing list');

// ---- الإلغاء: الاسترداد لمن دفع (المشتري) لا لمن يحمل، والحامل يُشعر بلا مبلغ
// بقي صالحاً: T3 عند المشتري، T4 عند خالد (دفعها المشتري). T1 وT2 مستعملتان فلا تُستردان.
const before = { buyer: await balance(BUYER), khalid: await balance(KHALID), host: await balance(HOST) };
notes.length = 0;
await call('POST', `/events/${ev.id}/cancel`, { user: HOST, expect: 200 });
check((await balance(BUYER)) === before.buyer + 10000 && (await balance(KHALID)) === before.khalid && (await balance(HOST)) === before.host - 10000, 'refund for a transferred ticket goes to the payer');
check(notes.some((n) => n.kind === 'event_cancelled' && n.ids.includes(KHALID) && !/استُرد/.test(n.body)) && notes.some((n) => n.kind === 'event_cancelled' && n.ids.includes(BUYER) && /استُرد/.test(n.body)), 'holder is told without an amount, payer with it');
check((await call('POST', `/tickets/${T3.id}/send`, { body: { userId: NORA }, expect: 409 })).error === 'not-transferable', 'refunded tickets cannot be sent');

console.log(fails ? `\n${fails} FAILED` : '\nALL TICKET SHARE TESTS OK');
await app.close(); await pool.end();
process.exit(fails ? 1 : 0);
