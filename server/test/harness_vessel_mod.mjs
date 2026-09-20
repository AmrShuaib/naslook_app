// اختبارات إشراف منشورات الدوائر (server/vessel_mod.js) مع بلاغات vessel-post في safety.js:
// نواة وهمية تعطي دور العضو في الدائرة وتحذف المنشور لصاحبه فقط.
import Fastify from 'fastify';
import pg from 'pg';
process.env.NASLIFE_HEALTH_BRIDGE = '0';
let fails = 0;
const check = (cond, label, extra = '') => { if (!cond) fails++; console.log((cond ? 'OK  ' : 'FAIL') + ' ' + label + (extra ? ' ' + extra : '')); };
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("INSERT INTO users(id,nickname) VALUES('SA0000001','amr'),('SA0000002','sara'),('SA0000003','khalid'),('SA0000004','nora'),('SA0000005','fahad') ON CONFLICT DO NOTHING");
for (const sql of ['DROP TABLE IF EXISTS vessel_post_mod, content_reports, posts', 'DELETE FROM app_notifications', "INSERT INTO admins(user_id,granted_by) VALUES('SA0000004','test') ON CONFLICT DO NOTHING"]) { try { await pool.query(sql); } catch { /* أول تشغيل */ } }
// جدول منشورات النواة (كما تكتشفه الإضافة)
await pool.query("CREATE TABLE posts (id UUID PRIMARY KEY, vessel_id TEXT NOT NULL, author_id TEXT NOT NULL, content TEXT NOT NULL DEFAULT '', created_at TIMESTAMPTZ DEFAULT now())");
const V1 = 'aaaaaaaa-1111-4000-8000-000000000001', V2 = 'aaaaaaaa-2222-4000-8000-000000000002';
const P = { sara: 'bbbbbbbb-0000-4000-8000-000000000001', khalid: 'bbbbbbbb-0000-4000-8000-000000000002', sara2: 'bbbbbbbb-0000-4000-8000-000000000003', other: 'bbbbbbbb-0000-4000-8000-000000000004' };
await pool.query("INSERT INTO posts(id,vessel_id,author_id,content) VALUES($1,$5,'SA0000002','منشور سارة'),($2,$5,'SA0000003','منشور خالد'),($3,$5,'SA0000002','منشور سارة الثاني'),($4,$6,'SA0000005','منشور فهد في دائرة أخرى')", [P.sara, P.khalid, P.sara2, P.other, V1, V2]);
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
const dir = new URL('.', import.meta.url).pathname;
// النواة الوهمية: amr مالك V1، sara مشرفة، khalid عضو، fahad مالك V2؛ الحذف لصاحب المنشور فقط
const roles = { SA0000001: { [V1]: 'owner' }, SA0000002: { [V1]: 'moderator' }, SA0000003: { [V1]: 'member' }, SA0000005: { [V2]: 'owner' } };
const coreCalls = [];
app.get('/vessels/:id', async (req, reply) => {
  const uid = req.headers['x-user']; const id = req.params.id;
  coreCalls.push(`GET vessel ${id} by ${uid}`);
  if (![V1, V2].includes(id)) return reply.code(404).send({ error: 'not-found' });
  const role = roles[uid]?.[id] ?? null;
  return { id, name: id === V1 ? 'دائرة الحي' : 'دائرة أخرى', ownerId: id === V1 ? 'SA0000001' : 'SA0000005', role, joined: !!role, postsPage: [] };
});
app.delete('/posts/:id', async (req, reply) => {
  const uid = req.headers['x-user'];
  coreCalls.push(`DELETE post ${req.params.id} by ${uid}`);
  if (!uid) return reply.code(401).send({ error: 'auth' });
  const r = (await pool.query('SELECT author_id FROM posts WHERE id::text=$1', [req.params.id])).rows[0];
  if (!r) return reply.code(404).send({ error: 'not-found' });
  if (r.author_id !== uid) return reply.code(403).send({ error: 'forbidden' });
  await pool.query('DELETE FROM posts WHERE id::text=$1', [req.params.id]);
  return { ok: true };
});
app.register((await import('../notify.js')).default, { pool, auth, pollMs: 3600000, opsDir: dir + 'ops' });
app.register((await import('../commerce.js')).default, { pool, auth });
app.register((await import('../business.js')).default, { pool, auth });
app.register((await import('../safety.js')).default, { pool, auth });
app.register((await import('../admin.js')).default, { pool, auth, webappDir: dir + 'webapp', opsDir: dir + 'ops' });
app.register((await import('../vessel_mod.js')).default, { pool, auth });
await app.ready(); await new Promise((r) => setTimeout(r, 300));
const call = async (method, url, { body = {}, user = 'SA0000001', expect } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json', host: 'naslife.app' }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url} -> ${r.statusCode}`, r.statusCode === expect ? '' : JSON.stringify(j).slice(0, 160));
  return j;
};
const st = await call('GET', '/vessel-mod/status', { user: null, expect: 200 });
check(st.postsTable === 'posts', 'posts table discovered', JSON.stringify(st));
check((await call('GET', '/posts/hidden', { expect: 200 })).ids.length === 0, 'nothing hidden at start');
await call('GET', '/posts/hidden', { user: null, expect: 401 });

// ---- الصلاحيات
await call('POST', `/posts/${P.sara}/remove`, { body: { vesselId: V1 }, user: null, expect: 401 });
let e = await call('POST', `/posts/${P.sara}/remove`, { body: { vesselId: V1 }, user: 'SA0000003', expect: 403 });
check(e.error === 'forbidden', 'plain member cannot remove');
e = await call('POST', `/posts/${P.sara}/remove`, { body: { vesselId: V1 }, user: 'SA0000005', expect: 403 });
check(e.error === 'forbidden', 'owner of another circle cannot remove');
e = await call('POST', `/posts/${P.sara}/remove`, { body: { vesselId: V2 }, expect: 400 });
check(e.error === 'bad-vessel', 'vessel mismatch rejected');
await call('POST', '/posts/bad id!/remove', { body: { vesselId: V1 }, expect: 400 });
e = await call('POST', `/posts/cccccccc-0000-4000-8000-000000000009/remove`, { body: { vesselId: V1 }, expect: 404 });
check(e.error === 'not-found', 'unknown post → 404');

// ---- مالك الدائرة يزيل منشور عضو: النواة ترفض الحذف → إخفاء + إشعار المؤلف
let r = await call('POST', `/posts/${P.sara}/remove`, { body: { vesselId: V1, reason: 'خارج الموضوع' }, expect: 200 });
check(r.ok && r.hidden === true && r.deleted === false, 'owner hides member post', JSON.stringify(r));
check(coreCalls.some((c) => c === `DELETE post ${P.sara} by SA0000001`), 'core delete attempted with requester session');
check((await pool.query('SELECT count(*)::int AS n FROM posts WHERE id::text=$1', [P.sara])).rows[0].n === 1, 'post still exists in core');
let hidden = await call('GET', '/posts/hidden', { user: 'SA0000003', expect: 200 });
check(hidden.ids.length === 1 && hidden.ids[0] === P.sara, 'hidden list has the post', JSON.stringify(hidden));
hidden = await call('GET', `/posts/hidden?vessel=${V2}`, { expect: 200 });
check(hidden.ids.length === 0, 'hidden list filtered by vessel');
let notes = (await pool.query("SELECT user_id, kind, body FROM app_notifications WHERE kind='vessel_post_hidden'")).rows;
check(notes.length === 1 && notes[0].user_id === 'SA0000002' && notes[0].body.includes('خارج الموضوع'), 'author notified with reason', JSON.stringify(notes));
r = await call('POST', `/posts/${P.sara}/remove`, { body: { vesselId: V1 }, expect: 200 });
check(r.hidden === true && r.already === true, 'hiding twice is idempotent');
check((await pool.query("SELECT count(*)::int AS n FROM app_notifications WHERE kind='vessel_post_hidden'")).rows[0].n === 1, 'no duplicate notification');
// vesselId يُستنتج من جدول النواة إن غاب
r = await call('POST', `/posts/${P.khalid}/remove`, { body: {}, user: 'SA0000002', expect: 200 });
check(r.hidden === true, 'moderator hides without vesselId (inferred)', JSON.stringify(r));
check((await call('GET', '/posts/hidden', { expect: 200 })).ids.length === 2, 'two hidden');

// ---- إعادة الإظهار
await call('POST', `/posts/${P.khalid}/unhide`, { body: {}, user: 'SA0000003', expect: 403 });
await call('POST', `/posts/${P.khalid}/unhide`, { body: {}, user: 'SA0000002', expect: 200 });
check((await call('GET', '/posts/hidden', { expect: 200 })).ids.length === 1, 'unhide removes the row');
await call('POST', `/posts/${P.khalid}/unhide`, { body: {}, expect: 404 });

// ---- صاحب المنشور وهو مشرف: الحذف الفعلي في النواة
r = await call('POST', `/posts/${P.sara2}/remove`, { body: { vesselId: V1 }, user: 'SA0000002', expect: 200 });
check(r.deleted === true && r.hidden === false, 'author-moderator removal deletes in core', JSON.stringify(r));
check((await pool.query('SELECT count(*)::int AS n FROM posts WHERE id::text=$1', [P.sara2])).rows[0].n === 0, 'post gone from core');

// ---- مدير النظام يزيل في دائرة ليس عضواً فيها
r = await call('POST', `/posts/${P.other}/remove`, { body: { vesselId: V2 }, user: 'SA0000004', expect: 200 });
check(r.hidden === true, 'site admin can hide anywhere', JSON.stringify(r));
await call('POST', `/posts/${P.other}/unhide`, { body: {}, user: 'SA0000004', expect: 200 });

// ---- البلاغات: vessel-post مع الإخفاء التلقائي (الحد 2)
await call('POST', '/adminapi/settings', { body: { reportThreshold: 2 }, user: 'SA0000004', expect: 200 });
e = await call('POST', '/safety/report', { body: { targetType: 'vessel-post', targetId: P.other }, user: 'SA0000005', expect: 400 });
check(e.error === 'own-content', 'author cannot report own circle post');
await call('POST', '/safety/report', { body: { targetType: 'vessel-post', targetId: 'cccccccc-0000-4000-8000-000000000009' }, expect: 404 });
let rep = await call('POST', '/safety/report', { body: { targetType: 'vessel-post', targetId: P.other, reason: 'مسيء' }, user: 'SA0000002', expect: 200 });
check(rep.reports === 1 && rep.hidden === false, 'first report counted', JSON.stringify(rep));
rep = await call('POST', '/safety/report', { body: { targetType: 'vessel-post', targetId: P.other, reason: 'مسيء' }, user: 'SA0000003', expect: 200 });
check(rep.reports === 2 && rep.hidden === true, 'threshold → auto-hidden', JSON.stringify(rep));
hidden = await call('GET', `/posts/hidden?vessel=${V2}`, { expect: 200 });
check(hidden.ids.includes(P.other), 'auto-hidden post in hidden list');
notes = (await pool.query("SELECT user_id, kind, title FROM app_notifications WHERE user_id='SA0000005' AND kind='vessel_post_hidden'")).rows;
check(notes.filter((n) => n.title.includes('بلاغات')).length === 1, 'author notified about reports', JSON.stringify(notes));
check((await pool.query("SELECT count(*)::int AS n FROM app_notifications WHERE user_id='SA0000004' AND kind='content_autohidden' AND title LIKE '%منشور دائرة%'")).rows[0].n === 1, 'admins notified with type name');
const reps = await call('GET', `/safety/reports/vessel-post/${P.other}`, { user: 'SA0000004', expect: 200 });
check(reps.length === 2, 'admin lists reports');
await call('POST', '/adminapi/settings', { body: { reportThreshold: 3 }, user: 'SA0000004', expect: 200 });

// ---- بدون جدول النواة: يعمل بالـ vesselId من الطلب فقط
await pool.query('DROP TABLE posts');
const app2 = Fastify();
app2.get('/vessels/:id', async (req) => ({ id: req.params.id, ownerId: 'SA0000001', role: req.headers['x-user'] === 'SA0000001' ? 'owner' : 'member' }));
app2.delete('/posts/:id', async (req, reply) => reply.code(403).send({ error: 'forbidden' }));
app2.register((await import('../vessel_mod.js')).default, { pool, auth });
await app2.ready();
const call2 = async (method, url, { body = {}, user = 'SA0000001', expect } = {}) => {
  const r0 = await app2.inject({ method, url, headers: { 'x-user': user, 'content-type': 'application/json' }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r0.json(); } catch { j = r0.body; }
  if (expect != null) check(r0.statusCode === expect, `${method} ${url} -> ${r0.statusCode}`, r0.statusCode === expect ? '' : JSON.stringify(j).slice(0, 160));
  return j;
};
check((await call2('GET', '/vessel-mod/status', { expect: 200 })).postsTable === null, 'no core table → still works');
e = await call2('POST', '/posts/p1/remove', { body: {}, expect: 400 });
check(e.error === 'bad-vessel', 'vesselId required without core table');
r = await call2('POST', '/posts/p1/remove', { body: { vesselId: 'v1' }, expect: 200 });
check(r.hidden === true, 'hidden without core table', JSON.stringify(r));
await call2('POST', '/posts/p1/remove', { body: { vesselId: 'v1' }, user: 'SA0000003', expect: 403 });
await app2.close();
await pool.query('DROP TABLE IF EXISTS vessel_post_mod'); await pool.query("DELETE FROM content_reports WHERE target_type='vessel-post'");
await app.close(); await pool.end();
console.log(fails ? `\n${fails} FAILED` : '\nALL VESSEL MOD TESTS PASSED');
process.exit(fails ? 1 : 0);
