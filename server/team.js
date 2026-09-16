// فريق العمل في لوحة إدارة Naslife: أدوار بصلاحيات دقيقة، تسلسل إداري (مدير مباشر لكل عضو)، ونطاق رؤية لكل موظف.
// المديرون القدامى (جدول admins وملف admin_bootstrap) يُعاملون كمالكين بكل الصلاحيات.
// يعرّف للإضافات الأخرى:
//   globalThis.naslifeTeamInfo(uid)                 → {roleId, roleName, level, permissions, title, department, managerId, mailbox} أو null
//   globalThis.naslifeTeamCan(uid, perm)            → true/false
//   globalThis.naslifeTeamAccess(uid, method, url)  → هل يسمح مسار /adminapi هذا لهذا العضو؟
//   globalThis.naslifeTeamScope(uid)                → {all, ids:Set} (العضو نفسه + من تحته في التسلسل)
//   globalThis.naslifeTeamMembers()                 → قائمة الأعضاء النشطين
//   globalThis.naslifeTeamPeople(ids)               → Map(id → {id, nickname, avatarUrl}) من جدول المستخدمين
// التسجيل في src/index.js بعد admin.js:
//   await app.register((await import("./team.js")).default, { pool, auth });
import crypto from "node:crypto";

const ID_RE = /^[A-Z]{2}\d{7}$/;
const ROLE_ID_RE = /^[a-z][a-z0-9_-]{1,31}$/;
const MAILBOX_RE = /^[a-z0-9][a-z0-9._-]{0,63}$/;
const q = (ident) => `"${String(ident).replace(/"/g, '""')}"`;
const str = (v, max) => String(v ?? "").trim().slice(0, max);

/// كتالوج الصلاحيات (المفتاح، المجموعة، الوصف)
export const PERMISSIONS = [
  ["overview.view", "overview", "عرض النظرة العامة"],
  ["users.view", "users", "عرض المستخدمين"], ["users.manage", "users", "إيقاف المستخدمين والشحن"],
  ["reports.view", "reports", "عرض البلاغات"], ["reports.act", "reports", "معالجة البلاغات"],
  ["biz.view", "biz", "عرض الدوائر التجارية"], ["biz.manage", "biz", "توثيق الدوائر وطلبات الملكية"],
  ["finance.view", "finance", "عرض المالية"], ["finance.manage", "finance", "إجراءات مالية وتصدير"],
  ["content.view", "content", "عرض المحتوى"], ["content.manage", "content", "إخفاء المحتوى وإلغاء الفعاليات"],
  ["blog.view", "blog", "عرض المدونة"], ["blog.manage", "blog", "كتابة ونشر المدونة"],
  ["mail.view", "mail", "عرض إعدادات البريد"], ["mail.manage", "mail", "تغيير إعدادات البريد"],
  ["settings.view", "settings", "عرض الإعدادات"], ["settings.manage", "settings", "تغيير الإعدادات"],
  ["audit.view", "audit", "عرض سجل الإجراءات"],
  ["team.view", "team", "عرض الفريق والهيكل"], ["team.manage", "team", "إدارة الأعضاء والأدوار"],
  ["tasks.view", "tasks", "عرض مهامه ومهام فريقه"], ["tasks.assign", "tasks", "إسناد مهام لمن تحته"], ["tasks.manage", "tasks", "إدارة كل المهام"],
  ["inbox.view", "inbox", "قراءة صندوقه"], ["inbox.reply", "inbox", "الرد والإرسال من صندوقه"], ["inbox.manage", "inbox", "الاطلاع على كل الصناديق"],
];
const PERM_KEYS = new Set(PERMISSIONS.map((p) => p[0]));

/// الأدوار المدمجة (لا تُحذف؛ صلاحياتها ثابتة)
export const BUILTIN_ROLES = [
  { id: "owner", name: "المالك", description: "كل الصلاحيات بلا استثناء", level: 100, permissions: ["*"] },
  { id: "admin", name: "مدير النظام", description: "كل الصلاحيات التشغيلية", level: 90, permissions: ["*"] },
  { id: "manager", name: "مدير قسم", description: "يدير أعضاء فريقه ومهامهم وبريدهم ويعالج البلاغات والدوائر", level: 70,
    permissions: ["overview.view", "users.view", "reports.view", "reports.act", "biz.view", "biz.manage", "finance.view", "content.view", "content.manage", "blog.view", "audit.view", "team.view", "team.manage", "tasks.view", "tasks.assign", "tasks.manage", "inbox.view", "inbox.reply", "inbox.manage"] },
  { id: "supervisor", name: "مشرف", description: "يتابع فريقه ويسند المهام ويعالج البلاغات", level: 60,
    permissions: ["overview.view", "users.view", "reports.view", "reports.act", "biz.view", "content.view", "team.view", "tasks.view", "tasks.assign", "inbox.view", "inbox.reply"] },
  { id: "finance", name: "محاسب", description: "المالية والمحافظ والتصدير", level: 50,
    permissions: ["overview.view", "finance.view", "finance.manage", "biz.view", "team.view", "tasks.view", "inbox.view", "inbox.reply"] },
  { id: "support", name: "دعم العملاء", description: "المستخدمون والبلاغات والبريد", level: 40,
    permissions: ["overview.view", "users.view", "reports.view", "reports.act", "team.view", "tasks.view", "inbox.view", "inbox.reply"] },
  { id: "moderator", name: "مشرف محتوى", description: "البلاغات والمحتوى", level: 40,
    permissions: ["overview.view", "reports.view", "reports.act", "content.view", "content.manage", "team.view", "tasks.view", "inbox.view", "inbox.reply"] },
  { id: "editor", name: "محرر", description: "المدونة والمحتوى", level: 40,
    permissions: ["blog.view", "blog.manage", "content.view", "team.view", "tasks.view", "inbox.view", "inbox.reply"] },
  { id: "viewer", name: "مطّلع", description: "قراءة فقط: النظرة العامة والفريق ومهامه", level: 10,
    permissions: ["overview.view", "team.view", "tasks.view", "inbox.view"] },
];

/// خريطة مسارات /adminapi إلى الصلاحية المطلوبة (طريقة الطلب → الصلاحية؛ "*" لبقية الطرق؛ الصلاحية "*" للمالكين فقط)
const RULES = [
  [/^\/adminapi\/status$/, { "*": null }], [/^\/adminapi\/setup$/, { "*": null }],
  [/^\/adminapi\/overview/, { get: "overview.view" }],
  [/^\/adminapi\/users\/[^/]+\/admin$/, { post: "*" }],
  [/^\/adminapi\/users/, { get: "users.view", "*": "users.manage" }],
  [/^\/adminapi\/reports/, { get: "reports.view", "*": "reports.act" }],
  [/^\/adminapi\/(biz|claims)/, { get: "biz.view", "*": "biz.manage" }],
  [/^\/adminapi\/finance/, { get: "finance.view", "*": "finance.manage" }],
  [/^\/adminapi\/(content|market|events)/, { get: "content.view", "*": "content.manage" }],
  [/^\/adminapi\/blog\/[^/]+\/preview$/, { post: "blog.view" }],
  [/^\/adminapi\/blog/, { get: "blog.view", "*": "blog.manage" }],
  [/^\/adminapi\/mail/, { get: "mail.view", "*": "mail.manage" }],
  [/^\/adminapi\/settings/, { get: "settings.view", "*": "settings.manage" }],
  [/^\/adminapi\/audit/, { get: "audit.view" }],
  [/^\/adminapi\/admins/, { get: "team.view", "*": "*" }],
  [/^\/adminapi\/team/, { get: "team.view", "*": "team.manage" }],
  [/^\/adminapi\/tasks/, { "*": "tasks.view" }],
  [/^\/adminapi\/inbox/, { "*": "inbox.view" }],
];
export function permissionFor(method, url) {
  const path = String(url ?? "").split("?")[0];
  const m = String(method ?? "GET").toLowerCase();
  for (const [re, map] of RULES) if (re.test(path)) return m in map ? map[m] : ("*" in map ? map["*"] : undefined);
  return undefined; // مسار غير معروف: للمديرين فقط
}
export const hasPerm = (perms, perm) => perm === null || (Array.isArray(perms) && (perms.includes("*") || (perm !== "*" && perm !== undefined && perms.includes(perm))));

export default async function team(app, opts = {}) {
  const pool = opts.pool ?? globalThis.naslifePool ?? null;
  const auth = opts.auth ?? globalThis.naslifeAuth ?? null;
  if (!pool || !auth) throw new Error("team: pool and auth are required");
  await pool.query(`
    CREATE TABLE IF NOT EXISTS team_roles (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT NOT NULL DEFAULT '', level INT NOT NULL DEFAULT 10,
      permissions JSONB NOT NULL DEFAULT '[]', builtin BOOLEAN NOT NULL DEFAULT false,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE TABLE IF NOT EXISTS team_members (
      user_id TEXT PRIMARY KEY, role_id TEXT NOT NULL REFERENCES team_roles(id), title TEXT NOT NULL DEFAULT '', department TEXT NOT NULL DEFAULT '',
      manager_id TEXT, active BOOLEAN NOT NULL DEFAULT true, mailbox TEXT NOT NULL DEFAULT '', added_by TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE INDEX IF NOT EXISTS team_members_manager ON team_members(manager_id);
  `);
  for (const r of BUILTIN_ROLES) {
    await pool.query("INSERT INTO team_roles(id,name,description,level,permissions,builtin) VALUES($1,$2,$3,$4,$5,true) ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, level=EXCLUDED.level, permissions=EXCLUDED.permissions, builtin=true, updated_at=now()", [r.id, r.name, r.description, r.level, JSON.stringify(r.permissions)]);
  }
  // أعمدة جدول المستخدمين (الاسم والصورة) تُكتشف
  let UC = { nick: null, avatar: null, ok: false };
  try {
    const cols = new Set((await pool.query("SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name='users'")).rows.map((r) => r.column_name));
    const pick = (...n) => n.find((x) => cols.has(x)) ?? null;
    UC = { ok: cols.has("id"), nick: pick("nickname", "name", "handle", "username"), avatar: pick("avatar_url", "avatarurl", "avatar") };
  } catch { /* بلا جدول مستخدمين */ }
  async function people(ids) {
    const out = new Map();
    const list = [...new Set(ids.filter(Boolean))];
    if (!list.length || !UC.ok) return out;
    try {
      const r = await pool.query(`SELECT id${UC.nick ? `, ${q(UC.nick)} AS nick` : ""}${UC.avatar ? `, ${q(UC.avatar)} AS avatar` : ""} FROM users WHERE id = ANY($1)`, [list]);
      for (const u of r.rows) out.set(u.id, { id: u.id, nickname: u.nick ?? "", avatarUrl: u.avatar ?? null });
    } catch { /* ignore */ }
    return out;
  }
  const personOf = (map, id) => map.get(id) ?? { id, nickname: "", avatarUrl: null };
  const legacyAdmin = async (uid) => { try { return !!(await globalThis.naslifeIsAdmin?.(uid)); } catch { return false; } };
  const legacyAdminIds = async () => { try { return (await pool.query("SELECT user_id FROM admins")).rows.map((r) => r.user_id); } catch { return []; } };
  const notify = async (ids, payload) => { try { await globalThis.naslifeNotify?.(ids, payload); } catch { /* ignore */ } };
  const audit = async (adminId, action, target, details = {}) => { try { await pool.query("INSERT INTO admin_audit(id,admin_id,action,target,details) VALUES($1,$2,$3,$4,$5)", [crypto.randomUUID(), adminId, action, target, JSON.stringify(details)]); } catch { /* ignore */ } };

  const roleOut = (r) => ({ id: r.id, name: r.name, description: r.description, level: r.level, permissions: r.permissions, builtin: r.builtin, members: r.members ?? undefined });
  const roles = async () => (await pool.query("SELECT r.*, (SELECT count(*)::int FROM team_members m WHERE m.role_id=r.id AND m.active) AS members FROM team_roles r ORDER BY level DESC, name")).rows;
  const roleById = async (id) => (await pool.query("SELECT * FROM team_roles WHERE id=$1", [id])).rows[0] ?? null;
  const memberRow = async (uid) => (await pool.query("SELECT m.*, r.name AS role_name, r.level, r.permissions FROM team_members m JOIN team_roles r ON r.id=m.role_id WHERE m.user_id=$1", [uid])).rows[0] ?? null;
  const activeMembers = async () => (await pool.query("SELECT m.*, r.name AS role_name, r.level, r.permissions FROM team_members m JOIN team_roles r ON r.id=m.role_id WHERE m.active ORDER BY r.level DESC, m.created_at")).rows;

  /// معلومات وصول عضو: عضو نشط في الفريق، أو مدير قديم (مالك افتراضي)
  async function info(uid) {
    if (!uid) return null;
    const m = await memberRow(uid);
    if (m && m.active) return { userId: uid, roleId: m.role_id, roleName: m.role_name, level: m.level, permissions: m.permissions, title: m.title, department: m.department, managerId: m.manager_id, mailbox: m.mailbox, legacy: false };
    if (await legacyAdmin(uid)) return { userId: uid, roleId: "owner", roleName: BUILTIN_ROLES[0].name, level: 100, permissions: ["*"], title: m?.title ?? "", department: m?.department ?? "", managerId: null, mailbox: m?.mailbox ?? "", legacy: true };
    return null;
  }
  const can = async (uid, perm) => hasPerm((await info(uid))?.permissions, perm);
  const access = async (uid, method, url) => { const perm = permissionFor(method, url); if (perm === undefined) return false; return can(uid, perm); };
  /// نطاق الرؤية: المالك/المدير يرى الجميع؛ غيرهم يرى نفسه ومن تحته في التسلسل
  async function scope(uid) {
    const i = await info(uid);
    if (!i) return { all: false, ids: new Set() };
    if (i.permissions.includes("*")) return { all: true, ids: new Set() };
    // التسلسل يشمل الموقوفين أيضاً حتى يبقى المدير قادراً على إدارتهم
    const members = (await pool.query("SELECT user_id, manager_id FROM team_members")).rows;
    const byManager = new Map();
    for (const m of members) { if (!byManager.has(m.manager_id)) byManager.set(m.manager_id, []); byManager.get(m.manager_id).push(m.user_id); }
    const ids = new Set([uid]); const stack = [uid];
    while (stack.length) { const cur = stack.pop(); for (const c of byManager.get(cur) ?? []) if (!ids.has(c)) { ids.add(c); stack.push(c); } }
    return { all: false, ids };
  }
  const inScope = async (uid, targetId) => { const s = await scope(uid); return s.all || s.ids.has(targetId); };
  globalThis.naslifeTeamInfo = info;
  globalThis.naslifeTeamCan = can;
  globalThis.naslifeTeamAccess = access;
  globalThis.naslifeTeamScope = scope;
  globalThis.naslifeTeamMembers = activeMembers;
  globalThis.naslifeTeamPeople = people;

  const bad = (reply, code, error, extra = {}) => reply.code(code).send({ error, ...extra });
  async function guard(req, reply, perm) {
    const uid = await auth(req); if (!uid) { bad(reply, 401, "auth"); return null; }
    const i = await info(uid);
    if (!i || !hasPerm(i.permissions, perm)) { bad(reply, 403, "forbidden", { need: perm }); return null; }
    req.teamInfo = i;
    return uid;
  }
  const memberOut = (m, pmap, mgrNames) => ({
    user: personOf(pmap, m.user_id), roleId: m.role_id, roleName: m.role_name, level: m.level, permissions: m.permissions,
    title: m.title, department: m.department, managerId: m.manager_id, managerName: m.manager_id ? (mgrNames.get(m.manager_id)?.nickname ?? "") : "",
    active: m.active, mailbox: m.mailbox, legacy: !!m.legacy, since: m.created_at,
  });
  /// كل الأعضاء (جدول الفريق + المديرون القدامى غير المدرجين كمالكين)
  async function allMembers() {
    const rows = (await pool.query("SELECT m.*, r.name AS role_name, r.level, r.permissions FROM team_members m JOIN team_roles r ON r.id=m.role_id ORDER BY r.level DESC, m.created_at")).rows;
    const have = new Set(rows.map((r) => r.user_id));
    for (const id of await legacyAdminIds()) if (!have.has(id)) rows.unshift({ user_id: id, role_id: "owner", role_name: BUILTIN_ROLES[0].name, level: 100, permissions: ["*"], title: "", department: "", manager_id: null, active: true, mailbox: "", created_at: null, legacy: true });
    return rows;
  }

  app.get("/adminapi/team/permissions", async (req, reply) => {
    if (!(await guard(req, reply, "team.view"))) return;
    return PERMISSIONS.map(([key, group, label]) => ({ key, group, label }));
  });
  app.get("/adminapi/team/me", async (req, reply) => {
    const uid = await guard(req, reply, null); if (!uid) return;
    const s = await scope(uid);
    return { ...req.teamInfo, scopeAll: s.all, scopeIds: [...s.ids] };
  });
  app.get("/adminapi/team", async (req, reply) => {
    const uid = await guard(req, reply, "team.view"); if (!uid) return;
    const rows = await allMembers();
    const pmap = await people([...rows.map((r) => r.user_id), ...rows.map((r) => r.manager_id)]);
    const departments = [...new Set(rows.map((r) => r.department).filter(Boolean))].sort();
    const s = await scope(uid);
    return { members: rows.map((m) => memberOut(m, pmap, pmap)), roles: (await roles()).map(roleOut), departments, me: { ...req.teamInfo, scopeAll: s.all, scopeIds: [...s.ids] } };
  });
  app.get("/adminapi/team/tree", async (req, reply) => {
    if (!(await guard(req, reply, "team.view"))) return;
    const rows = (await allMembers()).filter((m) => m.active);
    const pmap = await people(rows.map((r) => r.user_id));
    const ids = new Set(rows.map((r) => r.user_id));
    const byManager = new Map();
    for (const m of rows) { const key = m.manager_id && ids.has(m.manager_id) && m.manager_id !== m.user_id ? m.manager_id : null; if (!byManager.has(key)) byManager.set(key, []); byManager.get(key).push(m); }
    const node = (m, depth, seen) => ({ ...memberOut(m, pmap, pmap), depth, reports: depth > 20 ? [] : (byManager.get(m.user_id) ?? []).filter((c) => !seen.has(c.user_id)).map((c) => node(c, depth + 1, new Set([...seen, c.user_id]))) });
    return { roots: (byManager.get(null) ?? []).map((m) => node(m, 0, new Set([m.user_id]))) };
  });
  app.get("/adminapi/team/search", async (req, reply) => {
    if (!(await guard(req, reply, "team.manage"))) return;
    const term = str(req.query?.q, 40);
    if (!UC.ok || term.length < 2) return [];
    const existing = new Set((await pool.query("SELECT user_id FROM team_members")).rows.map((r) => r.user_id));
    const r = await pool.query(`SELECT id${UC.nick ? `, ${q(UC.nick)} AS nick` : ""}${UC.avatar ? `, ${q(UC.avatar)} AS avatar` : ""} FROM users WHERE id ILIKE $1${UC.nick ? ` OR ${q(UC.nick)} ILIKE $1` : ""} ORDER BY id LIMIT 12`, [`%${term}%`]);
    return r.rows.map((u) => ({ id: u.id, nickname: u.nick ?? "", avatarUrl: u.avatar ?? null, member: existing.has(u.id) }));
  });

  /// التحقق من حقول عضو (الدور، المدير، الصندوق) وفق صلاحيات الفاعل
  async function validateMember(actor, target, body, current) {
    const out = {};
    if (body.roleId !== undefined) {
      const r = await roleById(str(body.roleId, 32));
      if (!r) return { error: "bad-role" };
      if (r.level >= actor.level && actor.level < 100) return { error: "role-above-you" };
      out.role_id = r.id; out.level = r.level;
    }
    if (body.title !== undefined) out.title = str(body.title, 60);
    if (body.department !== undefined) out.department = str(body.department, 60);
    if (body.mailbox !== undefined) { const mb = str(body.mailbox, 64).toLowerCase(); if (mb && !MAILBOX_RE.test(mb)) return { error: "bad-mailbox" }; out.mailbox = mb; }
    if (body.managerId !== undefined) {
      const mgr = body.managerId ? str(body.managerId, 12).toUpperCase() : null;
      if (mgr) {
        if (!ID_RE.test(mgr) || mgr === target) return { error: "bad-manager" };
        const mi = await info(mgr); if (!mi) return { error: "bad-manager" };
        // منع الحلقات: لا يكون المدير أحد مرؤوسي العضو
        let cur = mgr, hops = 0;
        while (cur && hops++ < 50) { if (cur === target) return { error: "manager-cycle" }; cur = (await memberRow(cur))?.manager_id ?? null; }
      }
      out.manager_id = mgr;
    }
    if (body.active !== undefined) { if (body.active === false && target === actor.userId) return { error: "self" }; out.active = body.active !== false; }
    if (current && current.level >= actor.level && actor.level < 100 && target !== actor.userId) return { error: "member-above-you" };
    return { fields: out };
  }
  app.post("/adminapi/team/members", async (req, reply) => {
    const uid = await guard(req, reply, "team.manage"); if (!uid) return;
    const actor = req.teamInfo;
    const target = str(req.body?.userId, 12).toUpperCase();
    if (!ID_RE.test(target)) return bad(reply, 400, "bad-user");
    if (UC.ok) { try { if (!(await pool.query("SELECT 1 FROM users WHERE id=$1", [target])).rowCount) return bad(reply, 404, "user-not-found"); } catch { /* ignore */ } }
    const existing = await memberRow(target);
    if (existing) return bad(reply, 409, "already-member");
    const body = { roleId: req.body?.roleId ?? "viewer", title: req.body?.title ?? "", department: req.body?.department ?? "", managerId: req.body?.managerId ?? (actor.legacy ? null : actor.userId), mailbox: req.body?.mailbox ?? "" };
    const v = await validateMember(actor, target, body, null);
    if (v.error) return bad(reply, 400, v.error);
    const f = v.fields;
    await pool.query("INSERT INTO team_members(user_id,role_id,title,department,manager_id,mailbox,added_by) VALUES($1,$2,$3,$4,$5,$6,$7)", [target, f.role_id, f.title, f.department, f.manager_id, f.mailbox, uid]);
    await audit(uid, "team.add", target, { roleId: f.role_id, managerId: f.manager_id, title: f.title });
    const r = await roleById(f.role_id);
    await notify([target], { kind: "team_added", title: "أُضفت إلى فريق عمل ناس لايف", body: `دورك: ${r.name}${f.title ? ` · ${f.title}` : ""}. افتح لوحة الإدارة من ماي سبيس.`, data: { section: "team" } });
    const m = await memberRow(target); const pmap = await people([target, m.manager_id]);
    return memberOut(m, pmap, pmap);
  });
  app.patch("/adminapi/team/members/:id", async (req, reply) => {
    const uid = await guard(req, reply, "team.manage"); if (!uid) return;
    const actor = req.teamInfo;
    const target = str(req.params.id, 12).toUpperCase();
    let current = await memberRow(target);
    if (!current && (await legacyAdmin(target))) {
      // مدير قديم: نُنشئ له صفاً كمالك حتى يمكن ضبط عنوانه وقسمه وصندوقه
      await pool.query("INSERT INTO team_members(user_id,role_id,added_by) VALUES($1,'owner',$2) ON CONFLICT DO NOTHING", [target, uid]);
      current = await memberRow(target);
    }
    if (!current) return bad(reply, 404, "not-found");
    if (!(await inScope(uid, target)) && target !== uid) return bad(reply, 403, "out-of-scope");
    const body = req.body && typeof req.body === "object" ? req.body : {};
    if (target === uid && (body.roleId !== undefined || body.active === false) && actor.level < 100) return bad(reply, 400, "self");
    const v = await validateMember(actor, target, body, current);
    if (v.error) return bad(reply, 400, v.error);
    const f = v.fields; delete f.level;
    if (current.role_id === "owner" && f.role_id && f.role_id !== "owner") {
      const owners = (await pool.query("SELECT count(*)::int AS n FROM team_members WHERE role_id='owner' AND active")).rows[0].n + (await legacyAdminIds()).filter((x) => x !== target).length;
      if (owners < 1) return bad(reply, 400, "last-owner");
    }
    const keys = Object.keys(f);
    if (keys.length) {
      const sets = keys.map((k, i) => `${q(k)}=$${i + 2}`);
      await pool.query(`UPDATE team_members SET ${sets.join(", ")}, updated_at=now() WHERE user_id=$1`, [target, ...keys.map((k) => f[k])]);
    }
    await audit(uid, "team.update", target, f);
    if (f.role_id && f.role_id !== current.role_id) { const r = await roleById(f.role_id); await notify([target], { kind: "team_role", title: "تغيّر دورك في فريق ناس لايف", body: `دورك الآن: ${r?.name ?? f.role_id}`, data: { section: "team" } }); }
    const m = await memberRow(target); const pmap = await people([target, m.manager_id]);
    return memberOut(m, pmap, pmap);
  });
  app.delete("/adminapi/team/members/:id", async (req, reply) => {
    const uid = await guard(req, reply, "team.manage"); if (!uid) return;
    const target = str(req.params.id, 12).toUpperCase();
    if (target === uid) return bad(reply, 400, "self");
    const current = await memberRow(target);
    if (!current) return bad(reply, 404, "not-found");
    if (current.level >= req.teamInfo.level && req.teamInfo.level < 100) return bad(reply, 403, "member-above-you");
    if (!(await inScope(uid, target))) return bad(reply, 403, "out-of-scope");
    await pool.query("UPDATE team_members SET manager_id=$2 WHERE manager_id=$1", [target, current.manager_id]);
    await pool.query("DELETE FROM team_members WHERE user_id=$1", [target]);
    await audit(uid, "team.remove", target, {});
    return { ok: true };
  });

  // ---- الأدوار
  app.get("/adminapi/team/roles", async (req, reply) => { if (!(await guard(req, reply, "team.view"))) return; return (await roles()).map(roleOut); });
  const cleanPerms = (list) => Array.isArray(list) ? [...new Set(list.map((p) => String(p)).filter((p) => PERM_KEYS.has(p)))] : null;
  app.post("/adminapi/team/roles", async (req, reply) => {
    const uid = await guard(req, reply, "team.manage"); if (!uid) return;
    const b = req.body ?? {};
    const name = str(b.name, 40); if (!name) return bad(reply, 400, "bad-name");
    let id = str(b.id, 32).toLowerCase() || name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || `role-${Date.now().toString(36)}`;
    if (!ROLE_ID_RE.test(id)) id = `role-${Date.now().toString(36)}`;
    if (await roleById(id)) return bad(reply, 409, "role-exists");
    const level = Math.max(1, Math.min(99, Math.round(Number(b.level)) || 30));
    if (level >= req.teamInfo.level && req.teamInfo.level < 100) return bad(reply, 400, "role-above-you");
    const perms = cleanPerms(b.permissions); if (!perms) return bad(reply, 400, "bad-permissions");
    if (!req.teamInfo.permissions.includes("*") && perms.some((p) => !req.teamInfo.permissions.includes(p))) return bad(reply, 400, "permissions-above-you");
    await pool.query("INSERT INTO team_roles(id,name,description,level,permissions) VALUES($1,$2,$3,$4,$5)", [id, name, str(b.description, 200), level, JSON.stringify(perms)]);
    await audit(uid, "team.role.create", id, { name, level, permissions: perms });
    return roleOut({ ...(await roleById(id)), members: 0 });
  });
  app.patch("/adminapi/team/roles/:id", async (req, reply) => {
    const uid = await guard(req, reply, "team.manage"); if (!uid) return;
    const r = await roleById(str(req.params.id, 32)); if (!r) return bad(reply, 404, "not-found");
    const b = req.body ?? {}; const sets = []; const params = [r.id]; const details = {};
    const set = (col, val) => { params.push(val); sets.push(`${q(col)}=$${params.length}`); details[col] = val; };
    if (b.name !== undefined) { const n = str(b.name, 40); if (!n) return bad(reply, 400, "bad-name"); set("name", n); }
    if (b.description !== undefined) set("description", str(b.description, 200));
    if (!r.builtin) {
      if (r.level >= req.teamInfo.level && req.teamInfo.level < 100) return bad(reply, 400, "role-above-you");
      if (b.level !== undefined) { const level = Math.max(1, Math.min(99, Math.round(Number(b.level)) || r.level)); if (level >= req.teamInfo.level && req.teamInfo.level < 100) return bad(reply, 400, "role-above-you"); set("level", level); }
      if (b.permissions !== undefined) { const perms = cleanPerms(b.permissions); if (!perms) return bad(reply, 400, "bad-permissions"); if (!req.teamInfo.permissions.includes("*") && perms.some((p) => !req.teamInfo.permissions.includes(p))) return bad(reply, 400, "permissions-above-you"); set("permissions", JSON.stringify(perms)); }
    } else if (b.level !== undefined || b.permissions !== undefined) return bad(reply, 400, "builtin-role");
    if (sets.length) await pool.query(`UPDATE team_roles SET ${sets.join(", ")}, updated_at=now() WHERE id=$1`, params);
    await audit(uid, "team.role.update", r.id, details);
    return roleOut(await roleById(r.id));
  });
  app.delete("/adminapi/team/roles/:id", async (req, reply) => {
    const uid = await guard(req, reply, "team.manage"); if (!uid) return;
    const r = await roleById(str(req.params.id, 32)); if (!r) return bad(reply, 404, "not-found");
    if (r.builtin) return bad(reply, 400, "builtin-role");
    if ((await pool.query("SELECT 1 FROM team_members WHERE role_id=$1 LIMIT 1", [r.id])).rowCount) return bad(reply, 409, "role-in-use");
    await pool.query("DELETE FROM team_roles WHERE id=$1", [r.id]);
    await audit(uid, "team.role.delete", r.id, {});
    return { ok: true };
  });
}
