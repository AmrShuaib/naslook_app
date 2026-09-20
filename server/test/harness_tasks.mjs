// مهام العمل (server/tasks.js) فوق فريق العمل: الإسناد عبر التسلسل، الرؤية حسب النطاق، تحديث الحالة والتعليقات
// والإشعارات، قيود المسند إليه، الملخص، التذكيرات، والحذف.
import Fastify from 'fastify';
import pg from 'pg';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0';
let fails = 0;
const check = (c, l, extra = '') => { if (!c) fails++; console.log((c ? 'OK  ' : 'FAIL') + ' ' + l + (extra ? ' ' + extra : '')); };
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("INSERT INTO users(id,nickname) VALUES('SA0000001','amr'),('SA0000002','sara'),('SA0000003','khalid'),('SA0000004','nora'),('SA0000005','fahad'),('SA0000006','lina') ON CONFLICT DO NOTHING");
for (const sql of ['DROP TABLE IF EXISTS work_task_comments, work_task_events, work_tasks', 'DROP TABLE IF EXISTS team_members', 'DROP TABLE IF EXISTS team_roles', 'DELETE FROM admins', "INSERT INTO admins(user_id,granted_by) VALUES('SA0000001','test')", 'DELETE FROM app_notifications']) { try { await pool.query(sql); } catch { /* first run */ } }
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
const dir = new URL('.', import.meta.url).pathname;
app.register((await import('../notify.js')).default, { pool, auth, pollMs: 3600000, opsDir: dir + 'ops' });
app.register((await import('../commerce.js')).default, { pool, auth });
app.register((await import('../business.js')).default, { pool, auth });
app.register((await import('../admin.js')).default, { pool, auth, webappDir: dir + 'webapp', opsDir: dir + 'ops' });
app.register((await import('../team.js')).default, { pool, auth });
app.register((await import('../tasks.js')).default, { pool, auth, sweepMs: 0 });
await app.ready(); await new Promise((r) => setTimeout(r, 300));
const call = async (method, url, { body = {}, user = 'SA0000001', expect } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json', host: 'naslife.app' }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url} [${user}] -> ${r.statusCode}`, r.statusCode === expect ? '' : JSON.stringify(j).slice(0, 160));
  return j;
};
const notes = async (kind, user) => (await pool.query("SELECT user_id, title FROM app_notifications WHERE kind=$1" + (user ? " AND user_id=$2" : "") + " ORDER BY created_at", user ? [kind, user] : [kind])).rows;
// الفريق: sara مديرة → nora مشرفة → khalid دعم؛ fahad محرر تحت sara؛ lina خارج الفريق
await call('POST', '/adminapi/team/members', { body: { userId: 'SA0000002', roleId: 'manager', department: 'العمليات' }, expect: 200 });
await call('POST', '/adminapi/team/members', { body: { userId: 'SA0000004', roleId: 'supervisor', managerId: 'SA0000002' }, expect: 200 });
await call('POST', '/adminapi/team/members', { body: { userId: 'SA0000003', roleId: 'support', managerId: 'SA0000004' }, expect: 200 });
await call('POST', '/adminapi/team/members', { body: { userId: 'SA0000005', roleId: 'editor', managerId: 'SA0000002' }, expect: 200 });

// ---- الوصول
await call('GET', '/adminapi/tasks', { user: 'SA0000006', expect: 403 });
await call('GET', '/adminapi/tasks', { user: null, expect: 401 });
let l = await call('GET', '/adminapi/tasks', { user: 'SA0000003', expect: 200 });
check(l.items.length === 0 && l.canAssign === false && l.assignees.length === 1 && l.assignees[0].id === 'SA0000003', 'support: empty, can only self-assign', JSON.stringify(l.assignees));
l = await call('GET', '/adminapi/tasks', { user: 'SA0000004', expect: 200 });
check(l.canAssign === true && l.assignees.map((a) => a.id).sort().join(',') === 'SA0000003,SA0000004', 'supervisor assigns within subtree', JSON.stringify(l.assignees.map((a) => a.id)));
l = await call('GET', '/adminapi/tasks', { user: 'SA0000002', expect: 200 });
check(l.canManage === true && l.assignees.length === 4, 'manager (tasks.manage) sees all members as assignees');

// ---- إنشاء وإسناد
let e = await call('POST', '/adminapi/tasks', { body: { title: 'x' }, user: 'SA0000003', expect: 400 });
check(e.error === 'bad-title', 'short title rejected');
e = await call('POST', '/adminapi/tasks', { body: { title: 'مهمة', priority: 'asap' }, user: 'SA0000003', expect: 400 });
check(e.error === 'bad-priority', 'bad priority');
e = await call('POST', '/adminapi/tasks', { body: { title: 'مهمة', dueAt: 'yesterday-ish' }, user: 'SA0000003', expect: 400 });
check(e.error === 'bad-due', 'bad due date');
e = await call('POST', '/adminapi/tasks', { body: { title: 'مهمة لفهد', assigneeId: 'SA0000005' }, user: 'SA0000003', expect: 403 });
check(e.error === 'cannot-assign', 'support cannot assign to others');
e = await call('POST', '/adminapi/tasks', { body: { title: 'مهمة لفهد', assigneeId: 'SA0000005' }, user: 'SA0000004', expect: 403 });
check(e.error === 'cannot-assign', 'supervisor cannot assign outside her subtree');
e = await call('POST', '/adminapi/tasks', { body: { title: 'مهمة للينا', assigneeId: 'SA0000006' }, user: 'SA0000002', expect: 403 });
check(e.error === 'cannot-assign', 'cannot assign to a non-member');
const own = await call('POST', '/adminapi/tasks', { body: { title: 'مراجعة بلاغات اليوم', assigneeId: 'SA0000003', checklist: [{ text: 'بلاغ 1' }, { text: '' }, { text: 'بلاغ 2', done: true }], tags: ['بلاغات', 'يومي', 'بلاغات'] }, user: 'SA0000003', expect: 200 });
check(own.mine === true && own.assignee.id === 'SA0000003' && own.creator.nickname === 'khalid' && own.checklist.length === 2 && own.tags.join(',') === 'بلاغات,يومي' && own.status === 'todo', 'self task created (checklist/tags cleaned)', JSON.stringify(own).slice(0, 200));
const due = new Date(Date.now() + 3 * 3600e3).toISOString();
const t1 = await call('POST', '/adminapi/tasks', { body: { title: 'الرد على شكاوى المتجر', description: 'كل الشكاوى المفتوحة', assigneeId: 'SA0000003', priority: 'high', dueAt: due, department: 'العمليات' }, user: 'SA0000004', expect: 200 });
check(t1.assignee.id === 'SA0000003' && t1.creator.id === 'SA0000004' && t1.priority === 'high' && t1.dueAt && t1.canEdit === true && t1.mine === false, 'supervisor assigned to khalid');
check((await notes('task_assigned', 'SA0000003')).length === 1, 'assignee notified once (self task does not notify)');
const t2 = await call('POST', '/adminapi/tasks', { body: { title: 'مقال الأسبوع', assigneeId: 'SA0000005', priority: 'urgent', dueAt: new Date(Date.now() - 3600e3).toISOString() }, user: 'SA0000002', expect: 200 });
check(t2.overdue === true, 'past due → overdue flag');
const t3 = await call('POST', '/adminapi/tasks', { body: { title: 'مهمة بلا مسند', priority: 'low' }, user: 'SA0000002', expect: 200 });
check(t3.assignee === null && t3.department === 'العمليات', 'unassigned task inherits creator department');

// ---- الرؤية
l = await call('GET', '/adminapi/tasks', { user: 'SA0000003', expect: 200 });
check(l.items.length === 2 && l.items.every((t) => t.assignee.id === 'SA0000003') && l.items[0].priority === 'high', 'khalid sees his two tasks, high first', JSON.stringify(l.items.map((t) => t.title)));
l = await call('GET', '/adminapi/tasks?view=team', { user: 'SA0000004', expect: 200 });
check(l.items.length === 2 && !l.items.some((t) => t.id === t2.id), 'nora team view = subtree only (not fahad)', JSON.stringify(l.items.map((t) => t.title)));
l = await call('GET', '/adminapi/tasks?view=team', { user: 'SA0000005', expect: 200 });
check(l.items.length === 1 && l.items[0].id === t2.id && l.items[0].canEdit === false && l.items[0].canUpdateStatus === true, 'fahad sees only his task, cannot edit fields');
l = await call('GET', '/adminapi/tasks?view=all', { user: 'SA0000002', expect: 200 });
check(l.items.length === 4 && l.counts.todo === 4 && l.counts.overdue === 1, 'manager sees everything with counts', JSON.stringify(l.counts));
l = await call('GET', '/adminapi/tasks?view=all&status=open&priority=urgent', { expect: 200 });
check(l.items.length === 1 && l.items[0].id === t2.id, 'filters');
l = await call('GET', '/adminapi/tasks?view=all&q=شكاوى', { expect: 200 });
check(l.items.length === 1 && l.items[0].id === t1.id, 'search');
l = await call('GET', '/adminapi/tasks?view=mine', { user: 'SA0000002', expect: 200 });
check(l.items.length === 1 && l.items[0].id === t3.id, 'mine includes my unassigned tasks');
await call('GET', `/adminapi/tasks/${t2.id}`, { user: 'SA0000003', expect: 403 });
await call('GET', `/adminapi/tasks/${t2.id}`, { user: 'SA0000004', expect: 403 });

// ---- المسند إليه يحدّث الحالة والقائمة فقط
e = await call('PATCH', `/adminapi/tasks/${t1.id}`, { body: { title: 'عنوان آخر' }, user: 'SA0000003', expect: 403 });
check(e.error === 'assignee-limited', 'assignee cannot edit title');
let u = await call('PATCH', `/adminapi/tasks/${t1.id}`, { body: { status: 'doing', checklist: [{ text: 'قرأت الشكاوى', done: true }] }, user: 'SA0000003', expect: 200 });
check(u.status === 'doing' && u.checklist[0].done === true, 'assignee moved to doing');
check((await notes('task_status', 'SA0000004')).length === 1, 'creator notified of status change');
u = await call('PATCH', `/adminapi/tasks/${t1.id}`, { body: { status: 'review' }, user: 'SA0000003', expect: 200 });
u = await call('PATCH', `/adminapi/tasks/${t1.id}`, { body: { status: 'done', priority: 'low' }, user: 'SA0000004', expect: 200 });
check(u.status === 'done' && u.completedAt && u.priority === 'low' && u.overdue === false, 'supervisor closes and edits');
check((await notes('task_status', 'SA0000003')).length === 1, 'assignee notified when someone else changes status');
e = await call('PATCH', `/adminapi/tasks/${t1.id}`, { body: {}, user: 'SA0000004', expect: 400 });
check(e.error === 'nothing-to-update', 'empty patch');
e = await call('PATCH', `/adminapi/tasks/${t2.id}`, { body: { assigneeId: 'SA0000003' }, user: 'SA0000004', expect: 403 });
check(e.error === 'forbidden', 'nora cannot touch a task outside her scope');
u = await call('PATCH', `/adminapi/tasks/${t3.id}`, { body: { assigneeId: 'SA0000004', dueAt: new Date(Date.now() + 10 * 3600e3).toISOString() }, user: 'SA0000002', expect: 200 });
check(u.assignee.id === 'SA0000004' && (await notes('task_assigned', 'SA0000004')).length === 1, 'reassignment notifies new assignee');

// ---- التعليقات والتفاصيل
const c = await call('POST', `/adminapi/tasks/${t1.id}/comments`, { body: { text: 'أنجزت 8 من 10' }, user: 'SA0000003', expect: 200 });
check(c.id && c.user.nickname === 'khalid', 'comment added');
check((await notes('task_comment', 'SA0000004')).length === 1 && (await notes('task_comment', 'SA0000003')).length === 0, 'comment notifies the other party only');
await call('POST', `/adminapi/tasks/${t1.id}/comments`, { body: { text: '' }, user: 'SA0000003', expect: 400 });
await call('POST', `/adminapi/tasks/${t1.id}/comments`, { body: { text: 'x' }, user: 'SA0000005', expect: 403 });
const d = await call('GET', `/adminapi/tasks/${t1.id}`, { user: 'SA0000002', expect: 200 });
check(d.commentList.length === 1 && d.comments === 1 && d.events.length >= 5 && d.events[0].kind === 'comment' && d.events.some((x) => x.kind === 'status' && x.data.to === 'doing'), 'detail has comments + timeline', JSON.stringify(d.events.map((x) => x.kind)));

// ---- الملخص
const sm = await call('GET', '/adminapi/tasks/summary', { user: 'SA0000002', expect: 200 });
const f = sm.members.find((m) => m.id === 'SA0000005'); const k = sm.members.find((m) => m.id === 'SA0000003');
check(sm.members.length === 4 && f.open === 1 && f.overdue === 1 && k.open === 1 && k.done30 === 1, 'summary per member', JSON.stringify(sm.members.map((m) => [m.id, m.open, m.overdue, m.done30])));
check((await call('GET', '/adminapi/tasks/summary', { user: 'SA0000004', expect: 200 })).members.length === 2, 'supervisor summary = subtree');

// ---- التذكيرات
const sw = await globalThis.naslifeTasksSweep();
check(sw.soon === 1 && sw.late === 1, 'sweep: one due soon (t3 in 10h), one overdue (t2)', JSON.stringify(sw));
check((await notes('task_due', 'SA0000004')).length === 1 && (await notes('task_overdue', 'SA0000005')).length === 1 && (await notes('task_overdue', 'SA0000002')).length === 1, 'reminders delivered to assignee (+creator when overdue)');
const sw2 = await globalThis.naslifeTasksSweep();
check(sw2.soon === 0 && sw2.late === 0, 'reminders not repeated');

// ---- الحذف
await call('DELETE', `/adminapi/tasks/${t1.id}`, { user: 'SA0000003', expect: 403 });
await call('DELETE', `/adminapi/tasks/${t1.id}`, { user: 'SA0000004', expect: 200 });
await call('GET', `/adminapi/tasks/${t1.id}`, { user: 'SA0000004', expect: 404 });
await call('DELETE', `/adminapi/tasks/${t2.id}`, { expect: 200 });
await app.close(); await pool.end();
console.log(fails ? `\n${fails} FAILED` : '\nALL TASKS TESTS PASSED');
process.exit(fails ? 1 : 0);
