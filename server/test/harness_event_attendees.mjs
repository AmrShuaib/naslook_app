// قائمة حضور الفعالية (server/commerce.js، نوفمبر 2026): GET /events/:id/attendees للمضيف وللإدارة فقط، صفحات بمؤشر معتم
// بلا تكرار (تذاكر الشراء الواحد تتشارك وقت الإنشاء)، ولا رموز تذاكر في القائمة إلا لمن بحث بالرمز، والفلاتر (دخلوا/لم يدخلوا/مستردة/الاسم).
import Fastify from 'fastify';
import pg from 'pg';
process.env.NASLIFE_HEALTH_BRIDGE = '0';
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
// معرّفات خاصة بهذه الحزمة حتى لا تتأثر بصفوف حزم أخرى على القاعدة نفسها
const HOST = 'SA0000781', A = 'SA0000782', B = 'SA0000783', C = 'SA0000784', STRANGER = 'SA0000785', ADMIN = 'SA0000786';
for (const [id, nick, admin] of [[HOST, 'ev_host', false], [A, 'رنا', false], [B, 'bandar', false], [C, 'colin', false], [STRANGER, 'stranger', false], [ADMIN, 'boss', true]]) {
  await pool.query("INSERT INTO users(id,nickname,is_admin) VALUES($1,$2,$3) ON CONFLICT (id) DO UPDATE SET nickname=EXCLUDED.nickname, is_admin=EXCLUDED.is_admin", [id, nick, admin]);
}
const cleanup = async () => {
  for (const sql of ['DELETE FROM tickets WHERE event_id IN (SELECT id FROM events WHERE host_id=$1)', 'DELETE FROM ticket_tiers WHERE event_id IN (SELECT id FROM events WHERE host_id=$1)', 'DELETE FROM events WHERE host_id=$1']) {
    try { await pool.query(sql, [HOST]); } catch { /* أول تشغيل */ }
  }
};
await cleanup();
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
app.register((await import('../commerce.js')).default, { pool, auth });
await app.ready(); await new Promise((r) => setTimeout(r, 300));
let fails = 0;
const check = (cond, label, extra = '') => { if (!cond) fails++; console.log((cond ? 'OK  ' : 'FAIL') + ' ' + label + (extra ? ' ' + extra : '')); };
const call = async (method, url, { body = {}, user = HOST, expect } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json' }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url.slice(0, 90)} -> ${r.statusCode}`, r.statusCode === expect ? '' : JSON.stringify(j).slice(0, 160));
  return j;
};
const startsAt = new Date(Date.now() + 2 * 86400000).toISOString();
const ev = await call('POST', '/events', { body: { title: 'أمسية القراءة', startsAt, placeName: 'مكتبة الحي', tiers: [{ name: 'عادي', price: 0, quantity: 50 }, { name: 'كبار الزوار', price: 0, quantity: 5 }] }, expect: 200 });
const other = await call('POST', '/events', { body: { title: 'فعالية أخرى', startsAt, tiers: [{ name: 'عادي', price: 0, quantity: 5 }] }, expect: 200 });
const [regular, vip] = ev.tiers;
// رنا تشتري ثلاث تذاكر في طلب واحد (وقت إنشاء واحد)، وبندر تذكرة كبار، وكولن تذكرة عادية
const ta = await call('POST', `/events/${ev.id}/tickets`, { user: A, body: { tierId: regular.id, qty: 3 }, expect: 200 });
const tb = await call('POST', `/events/${ev.id}/tickets`, { user: B, body: { tierId: vip.id, qty: 1 }, expect: 200 });
await call('POST', `/events/${ev.id}/tickets`, { user: C, body: { tierId: regular.id, qty: 1 }, expect: 200 });
const to = await call('POST', `/events/${other.id}/tickets`, { user: C, body: { tierId: other.tiers[0].id, qty: 1 }, expect: 200 });
const sameAt = (await pool.query('SELECT count(DISTINCT created_at)::int AS n FROM tickets WHERE id = ANY($1::uuid[])', [ta.map((t) => t.id)])).rows[0].n;
check(sameAt === 1, 'tickets bought together share one created_at (cursor needs the id tie-break)');

// الصلاحيات: المضيف والإدارة فقط
const url = `/events/${ev.id}/attendees`;
await call('GET', url, { user: null, expect: 401 });
check((await call('GET', url, { user: STRANGER, expect: 403 })).error === 'host-only', 'a non-host is refused with host-only');
check((await call('GET', url, { user: A, expect: 403 })).error === 'host-only', 'an attendee cannot list the other attendees');
const asAdmin = await call('GET', url, { user: ADMIN, expect: 200 });
check(asAdmin.total === 5, 'an admin can read the list', JSON.stringify(asAdmin.total));
await call('GET', '/events/not-a-uuid/attendees', { expect: 400 });
await call('GET', '/events/00000000-0000-4000-8000-000000000000/attendees', { expect: 404 });

// القائمة: الاسم الظاهر والصورة والفئة والحالة فقط، بلا رموز ولا بيانات أخرى
const all = await call('GET', url, { expect: 200 });
check(all.total === 5 && all.checkedIn === 0 && all.people === 3, 'counts: 5 tickets, 0 in, 3 people', JSON.stringify([all.total, all.checkedIn, all.people]));
check(all.items.length === 5 && all.next === null, 'first page holds all five and no next cursor');
const allowed = new Set(['ticketId', 'holder', 'tier', 'status', 'checkedIn', 'checkedInAt', 'boughtAt', 'paid']);
check(all.items.every((i) => Object.keys(i).every((k) => allowed.has(k))), 'items carry only the listed fields', JSON.stringify(Object.keys(all.items[0])));
check(all.items.every((i) => !('code' in i)) && !JSON.stringify(all).includes('NAS-'), 'no ticket codes leak in the list');
check(all.items.every((i) => Object.keys(i.holder).sort().join() === 'avatarUrl,id,nickname'), 'holder is id, nickname and avatar only');
check(all.items.filter((i) => i.holder.nickname === 'رنا').length === 3 && all.items.find((i) => i.holder.id === B)?.tier === 'كبار الزوار', 'names and tiers are right');

// الصفحات: حد 2 ثم المؤشر، بلا تكرار ولا فقد
const seen = []; let cursor = null; let pages = 0;
do {
  const p = await call('GET', `${url}?limit=2${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ''}`, { expect: 200 });
  seen.push(...p.items.map((i) => i.ticketId)); cursor = p.next; pages++;
} while (cursor && pages < 10);
check(pages === 3 && seen.length === 5 && new Set(seen).size === 5, 'paging with limit=2 walks 3 pages with no duplicate or gap', JSON.stringify([pages, seen.length, new Set(seen).size]));
check((await call('GET', `${url}?cursor=garbage`, { expect: 400 })).error === 'bad-cursor', 'a forged cursor is refused');
check((await call('GET', `${url}?limit=1000`, { expect: 200 })).items.length === 5, 'limit is clamped, not an error');

// الدخول: المضيف يمسح تذكرة بندر ثم تذكرة لرنا
await call('POST', `/events/${ev.id}/checkin`, { body: { code: tb[0].code }, expect: 200 });
await call('POST', `/events/${ev.id}/checkin`, { body: { code: ta[1].code.toLowerCase() }, expect: 200 });
const inn = await call('GET', `${url}?status=in`, { expect: 200 });
check(inn.items.length === 2 && inn.items.every((i) => i.checkedIn && i.status === 'used' && i.checkedInAt), 'status=in lists the two checked-in tickets with their time');
const out = await call('GET', `${url}?status=out`, { expect: 200 });
check(out.items.length === 3 && out.items.every((i) => !i.checkedIn && i.checkedInAt === null), 'status=out lists the three still outside');
check(out.checkedIn === 2 && out.total === 5, 'counts follow the check-ins');

// البحث بالرمز بعد المسح: التذكرة نفسها برمزها، وأحرف صغيرة مقبولة، ورمز فعالية أخرى لا يظهر هنا
const byCode = await call('GET', `${url}?code=${encodeURIComponent(ta[0].code.toLowerCase())}`, { expect: 200 });
check(byCode.items.length === 1 && byCode.items[0].ticketId === ta[0].id && byCode.items[0].code === ta[0].code && byCode.items[0].status === 'valid', 'code lookup returns that ticket and its code');
const used = await call('GET', `${url}?code=${encodeURIComponent(tb[0].code)}`, { expect: 200 });
check(used.items[0]?.checkedIn === true && used.items[0]?.holder.id === B, 'code lookup of a used ticket says it is in');
check((await call('GET', `${url}?code=${encodeURIComponent(to[0].code)}`, { expect: 200 })).items.length === 0, "another event's ticket is not found here");
check((await call('GET', `${url}?code=NAS-00000000`, { expect: 200 })).items.length === 0, 'unknown code finds nothing');

// البحث بالاسم (والرموز الخاصة في LIKE لا تُعامل كأنماط)
check((await call('GET', `${url}?q=${encodeURIComponent('رن')}`, { expect: 200 })).items.length === 3, 'name search finds رنا');
check((await call('GET', `${url}?q=${encodeURIComponent('%')}`, { expect: 200 })).items.length === 0, 'a % in the name search is literal');

// الإلغاء يسترد كل التذاكر الصالحة: تخرج من القائمة الافتراضية، وتبقى عند طلب المستردة
await call('POST', `/events/${ev.id}/cancel`, { body: {}, expect: 200 });
const after = await call('GET', url, { expect: 200 });
check(after.items.length === 2 && after.total === 2 && after.items.every((i) => i.status === 'used'), 'refunded tickets leave the default list (the two used remain)', JSON.stringify([after.items.length, after.total]));
const ref = await call('GET', `${url}?status=refunded`, { expect: 200 });
check(ref.items.length === 3 && ref.items.every((i) => i.status === 'refunded'), 'status=refunded lists the refunded three');

await cleanup();
try { await pool.query('DELETE FROM tickets WHERE event_id=$1', [other.id]); } catch { /* */ }
await app.close(); await pool.end();
console.log(fails ? `\n${fails} FAILED` : '\nALL EVENT ATTENDEES TESTS PASSED');
process.exit(fails ? 1 : 0);
