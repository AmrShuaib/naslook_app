// فريق العمل (server/team.js): الأدوار المدمجة، الصلاحيات على مسارات /adminapi، التسلسل الإداري والنطاق، قواعد المستويات،
// الأدوار المخصصة، وظهور الدور والصلاحيات في /adminapi/status.
import Fastify from 'fastify';
import pg from 'pg';
import { permissionFor, hasPerm } from '../team.js';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0';
let fails = 0;
const check = (c, l, extra = '') => { if (!c) fails++; console.log((c ? 'OK  ' : 'FAIL') + ' ' + l + (extra ? ' ' + extra : '')); };
check(permissionFor('GET', '/adminapi/users?q=x') === 'users.view' && permissionFor('POST', '/adminapi/users/SA1/suspend') === 'users.manage' && permissionFor('POST', '/adminapi/users/SA1/admin') === '*', 'route → permission map');
check(permissionFor('GET', '/adminapi/status') === null && permissionFor('GET', '/adminapi/unknown') === undefined && permissionFor('POST', '/adminapi/blog/x/preview') === 'blog.view' && permissionFor('DELETE', '/adminapi/blog/x') === 'blog.manage', 'special routes');
check(hasPerm(['*'], 'anything') && hasPerm(['users.view'], 'users.view') && !hasPerm(['users.view'], 'users.manage') && !hasPerm(['users.view'], '*') && hasPerm([], null) && !hasPerm(['x'], undefined), 'hasPerm semantics');

const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("INSERT INTO users(id,nickname) VALUES('SA0000001','amr'),('SA0000002','sara'),('SA0000003','khalid'),('SA0000004','nora'),('SA0000005','fahad'),('SA0000006','lina') ON CONFLICT DO NOTHING");
for (const sql of ['DROP TABLE IF EXISTS team_members', 'DROP TABLE IF EXISTS team_roles', 'DELETE FROM admins', "INSERT INTO admins(user_id,granted_by) VALUES('SA0000001','test')", 'DELETE FROM app_notifications']) { try { await pool.query(sql); } catch { /* first run */ } }
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
const dir = new URL('.', import.meta.url).pathname;
app.register((await import('../notify.js')).default, { pool, auth, pollMs: 3600000, opsDir: dir + 'ops' });
app.register((await import('../commerce.js')).default, { pool, auth });
app.register((await import('../business.js')).default, { pool, auth });
app.register((await import('../admin.js')).default, { pool, auth, webappDir: dir + 'webapp', opsDir: dir + 'ops' });
app.register((await import('../team.js')).default, { pool, auth });
await app.ready(); await new Promise((r) => setTimeout(r, 300));
const call = async (method, url, { body = {}, user = 'SA0000001', expect } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json', host: 'naslife.app' }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url} [${user}] -> ${r.statusCode}`, r.statusCode === expect ? '' : JSON.stringify(j).slice(0, 160));
  return j;
};
// ---- المالك القديم
let st = await call('GET', '/adminapi/status', { expect: 200 });
check(st.isAdmin === true && st.role === 'owner' && st.permissions[0] === '*' && st.level === 100, 'legacy admin → owner with all permissions', JSON.stringify({ r: st.role, p: st.permissions }));
st = await call('GET', '/adminapi/status', { user: 'SA0000002', expect: 200 });
check(st.isAdmin === false && st.role === null && st.permissions.length === 0, 'non-member: not admin');
let t = await call('GET', '/adminapi/team', { expect: 200 });
{ const amr = t.members.find((x) => x.user.id === 'SA0000001'); check(t.members.every((x) => x.legacy && x.roleId === 'owner') && amr && amr.user.nickname === 'amr', 'team lists legacy admins as owners', JSON.stringify(t.members.map((x) => x.user.id))); }
check(t.roles.length === 9 && t.roles[0].id === 'owner' && t.roles.every((r) => r.builtin) && t.me.scopeAll === true, 'builtin roles seeded, owner scope all');
const perms = await call('GET', '/adminapi/team/permissions', { expect: 200 });
check(perms.length >= 25 && perms.some((p) => p.key === 'tasks.assign'), 'permissions catalogue');
await call('GET', '/adminapi/team', { user: 'SA0000002', expect: 403 });
await call('GET', '/adminapi/team', { user: null, expect: 401 });

// ---- إضافة أعضاء: مدير قسم sara، مشرفة nora تحت sara، دعم khalid تحت nora، محرر fahad تحت sara
let e = await call('POST', '/adminapi/team/members', { body: { userId: 'bad' }, expect: 400 });
e = await call('POST', '/adminapi/team/members', { body: { userId: 'SA9999999', roleId: 'support' }, expect: 404 });
check(e.error === 'user-not-found', 'unknown user rejected');
let m = await call('POST', '/adminapi/team/members', { body: { userId: 'sa0000002', roleId: 'manager', title: 'مديرة العمليات', department: 'العمليات', mailbox: 'sara' }, expect: 200 });
check(m.user.id === 'SA0000002' && m.roleId === 'manager' && m.level === 70 && m.managerId === null && m.title === 'مديرة العمليات' && m.mailbox === 'sara', 'manager added (legacy owner has no manager row → no manager)', JSON.stringify(m).slice(0, 200));
await call('POST', '/adminapi/team/members', { body: { userId: 'SA0000002', roleId: 'support' }, expect: 409 });
m = await call('POST', '/adminapi/team/members', { body: { userId: 'SA0000004', roleId: 'supervisor', managerId: 'SA0000002', department: 'العمليات' }, expect: 200 });
check(m.managerId === 'SA0000002' && m.managerName === 'sara', 'supervisor under sara');
m = await call('POST', '/adminapi/team/members', { body: { userId: 'SA0000003', roleId: 'support', managerId: 'SA0000004' }, expect: 200 });
m = await call('POST', '/adminapi/team/members', { body: { userId: 'SA0000005', roleId: 'editor', managerId: 'SA0000002', department: 'المحتوى' }, expect: 200 });
const notes = (await pool.query("SELECT user_id, kind FROM app_notifications WHERE kind='team_added' ORDER BY created_at")).rows;
check(notes.length === 4 && notes[0].user_id === 'SA0000002', 'new members notified');

// ---- الصلاحيات على المسارات
st = await call('GET', '/adminapi/status', { user: 'SA0000003', expect: 200 });
check(st.isAdmin === true && st.role === 'support' && st.permissions.includes('reports.act') && !st.permissions.includes('finance.view'), 'support status', JSON.stringify({ r: st.role, n: st.permissions.length }));
await call('GET', '/adminapi/users', { user: 'SA0000003', expect: 200 });
await call('GET', '/adminapi/reports', { user: 'SA0000003', expect: 200 });
e = await call('GET', '/adminapi/finance', { user: 'SA0000003', expect: 403 });
check(e.error === 'admin-only', 'support cannot see finance');
await call('POST', '/adminapi/users/SA0000006/suspend', { body: { suspended: true }, user: 'SA0000003', expect: 403 });
await call('GET', '/adminapi/settings', { user: 'SA0000003', expect: 403 });
await call('GET', '/adminapi/finance', { user: 'SA0000002', expect: 200 });
await call('GET', '/adminapi/audit', { user: 'SA0000002', expect: 200 });
e = await call('POST', '/adminapi/users/SA0000006/admin', { body: { admin: true }, user: 'SA0000002', expect: 403 });
check(e.error === 'admin-only', 'manager cannot grant legacy admin');
await call('GET', '/adminapi/content', { user: 'SA0000005', expect: 200 });
await call('GET', '/adminapi/users', { user: 'SA0000005', expect: 403 });

// ---- النطاق والتسلسل
let me = await call('GET', '/adminapi/team/me', { user: 'SA0000002', expect: 200 });
check(me.scopeAll === false && [...me.scopeIds].sort().join(',') === 'SA0000002,SA0000003,SA0000004,SA0000005', 'sara scope = subtree', JSON.stringify(me.scopeIds));
me = await call('GET', '/adminapi/team/me', { user: 'SA0000004', expect: 200 });
check(me.scopeIds.sort().join(',') === 'SA0000003,SA0000004', 'nora scope = self + khalid');
const tree = await call('GET', '/adminapi/team/tree', { expect: 200 });
const sara = tree.roots.find((r) => r.user.id === 'SA0000002');
check(tree.roots.some((r) => r.user.id === 'SA0000001') && sara && sara.reports.length === 2 && sara.reports.find((r) => r.user.id === 'SA0000004').reports[0].user.id === 'SA0000003', 'org tree nested', JSON.stringify(tree.roots.map((r) => [r.user.id, r.reports.length])));
// المستويات: مشرفة لا تضيف مديراً، ولا تُعدّل من فوقها، ولا تخرج عن نطاقها
e = await call('POST', '/adminapi/team/members', { body: { userId: 'SA0000006', roleId: 'manager' }, user: 'SA0000004', expect: 403 });
check(e.error === 'forbidden' && e.need === 'team.manage', 'supervisor lacks team.manage');
e = await call('POST', '/adminapi/team/members', { body: { userId: 'SA0000006', roleId: 'manager' }, user: 'SA0000002', expect: 400 });
check(e.error === 'role-above-you', 'manager cannot create another manager (level rule)');
e = await call('PATCH', '/adminapi/team/members/SA0000005', { body: { managerId: 'SA0000003' }, user: 'SA0000002', expect: 200 });
check(e.managerId === 'SA0000003', 'manager reassigns editor under khalid');
e = await call('PATCH', '/adminapi/team/members/SA0000004', { body: { managerId: 'SA0000003' }, expect: 400 });
check(e.error === 'manager-cycle', 'cycle prevented (nora under her own report)');
e = await call('PATCH', '/adminapi/team/members/SA0000002', { body: { roleId: 'viewer' }, user: 'SA0000002', expect: 400 });
check(e.error === 'self', 'cannot change own role');
e = await call('PATCH', '/adminapi/team/members/SA0000002', { body: { title: 'x' }, user: 'SA0000004', expect: 403 });
check(e.error === 'forbidden', 'supervisor cannot edit members');
// manager يضيف عضواً بلا managerId → يصبح تحته تلقائياً
m = await call('POST', '/adminapi/team/members', { body: { userId: 'SA0000006', roleId: 'support' }, user: 'SA0000002', expect: 200 });
check(m.managerId === 'SA0000002', 'default manager = the actor');
e = await call('PATCH', '/adminapi/team/members/SA0000006', { body: { active: false, title: 'موقوف' }, user: 'SA0000002', expect: 200 });
check(e.active === false, 'deactivated');
st = await call('GET', '/adminapi/status', { user: 'SA0000006', expect: 200 });
check(st.isAdmin === false, 'inactive member loses access');
await call('GET', '/adminapi/users', { user: 'SA0000006', expect: 403 });
e = await call('DELETE', '/adminapi/team/members/SA0000002', { user: 'SA0000002', expect: 400 });
check(e.error === 'self', 'cannot remove self');
await call('DELETE', '/adminapi/team/members/SA0000006', { user: 'SA0000002', expect: 200 });
t = await call('GET', '/adminapi/team', { user: 'SA0000002', expect: 200 });
check(t.members.filter((x) => !x.legacy).length === 4 && t.members.some((x) => x.legacy && x.user.id === 'SA0000001') && t.departments.join('|') === 'العمليات|المحتوى', 'team list + departments', JSON.stringify([t.members.length, t.departments]));
// المالك يضبط بياناته (صف يُنشأ له كمالك)
e = await call('PATCH', '/adminapi/team/members/SA0000001', { body: { title: 'المؤسس', mailbox: 'amr' }, expect: 200 });
check(e.roleId === 'owner' && e.title === 'المؤسس' && e.mailbox === 'amr' && e.legacy === false, 'owner row created on edit');
st = await call('GET', '/adminapi/status', { expect: 200 });
check(st.role === 'owner' && st.title === 'المؤسس' && st.permissions[0] === '*', 'owner status keeps all permissions');
e = await call('PATCH', '/adminapi/team/members/SA0000003', { body: { mailbox: 'Bad Mail!' }, expect: 400 });
check(e.error === 'bad-mailbox', 'mailbox validated');

// ---- الأدوار المخصصة
e = await call('POST', '/adminapi/team/roles', { body: { name: 'مراجع مالي', level: 45, permissions: ['finance.view', 'nope', 'audit.view'] }, expect: 200 });
check(e.id === 'role-' + e.id.slice(5) && e.permissions.join(',') === 'finance.view,audit.view' && e.builtin === false, 'custom role created (unknown perms dropped)', JSON.stringify(e));
const rid = e.id;
e = await call('POST', '/adminapi/team/roles', { body: { id: 'qa', name: 'جودة', level: 80, permissions: ['reports.view'] }, user: 'SA0000002', expect: 400 });
check(e.error === 'role-above-you', 'manager cannot create role above own level');
e = await call('POST', '/adminapi/team/roles', { body: { id: 'qa', name: 'جودة', level: 30, permissions: ['settings.manage'] }, user: 'SA0000002', expect: 400 });
check(e.error === 'permissions-above-you', 'cannot grant permissions you lack');
e = await call('POST', '/adminapi/team/roles', { body: { id: 'qa', name: 'جودة', level: 30, permissions: ['reports.view', 'tasks.view'] }, user: 'SA0000002', expect: 200 });
check(e.id === 'qa' && e.level === 30, 'manager creates lower role');
await call('PATCH', '/adminapi/team/members/SA0000003', { body: { roleId: rid }, expect: 200 });
st = await call('GET', '/adminapi/status', { user: 'SA0000003', expect: 200 });
check(st.role === rid && st.permissions.join(',') === 'finance.view,audit.view', 'member moved to custom role');
await call('GET', '/adminapi/finance', { user: 'SA0000003', expect: 200 });
await call('GET', '/adminapi/reports', { user: 'SA0000003', expect: 403 });
e = await call('DELETE', `/adminapi/team/roles/${rid}`, { expect: 409 });
check(e.error === 'role-in-use', 'role in use cannot be deleted');
e = await call('PATCH', '/adminapi/team/roles/owner', { body: { permissions: [] }, expect: 400 });
check(e.error === 'builtin-role', 'builtin permissions immutable');
e = await call('PATCH', `/adminapi/team/roles/${rid}`, { body: { permissions: ['finance.view'], level: 20 }, expect: 200 });
check(e.permissions.join(',') === 'finance.view' && e.level === 20, 'custom role updated');
await call('DELETE', '/adminapi/team/roles/qa', { expect: 200 });
await call('DELETE', '/adminapi/team/roles/owner', { expect: 400 });
const audit = (await pool.query("SELECT action FROM admin_audit WHERE action LIKE 'team.%' ORDER BY created_at")).rows.map((r) => r.action);
check(audit.includes('team.add') && audit.includes('team.update') && audit.includes('team.remove') && audit.includes('team.role.create'), 'team actions audited');
await app.close(); await pool.end();
console.log(fails ? `\n${fails} FAILED` : '\nALL TEAM TESTS PASSED');
process.exit(fails ? 1 : 0);
