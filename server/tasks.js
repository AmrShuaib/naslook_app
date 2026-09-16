// مهام العمل في لوحة إدارة Naslife: إسناد عبر التسلسل الإداري (server/team.js)، حالات وأولويات ومواعيد، تعليقات وسجل،
// إشعارات للمسند إليه والمنشئ، وتذكير قبل الموعد وعند التأخر.
// قواعد الرؤية: من يملك tasks.manage يرى الكل؛ غيره يرى مهامه وما أنشأه وما أُسند لمن تحته.
// قواعد الإسناد: لنفسك دائماً؛ لغيرك تحتاج tasks.assign وأن يكون ضمن نطاقك (أو tasks.manage لأي عضو).
// التسجيل في src/index.js بعد team.js:
//   await app.register((await import("./tasks.js")).default, { pool, auth });
import crypto from "node:crypto";

const STATUSES = ["todo", "doing", "review", "done", "blocked"];
const PRIORITIES = ["low", "normal", "high", "urgent"];
const UUID_RE = /^[0-9a-f-]{36}$/i;
const ID_RE = /^[A-Z]{2}\d{7}$/;
const str = (v, max) => String(v ?? "").trim().slice(0, max);
const STATUS_AR = { todo: "جديدة", doing: "قيد التنفيذ", review: "للمراجعة", done: "منجزة", blocked: "معلّقة" };
const PRIORITY_AR = { low: "منخفضة", normal: "عادية", high: "مرتفعة", urgent: "عاجلة" };

export default async function tasks(app, opts = {}) {
  const pool = opts.pool ?? globalThis.naslifePool ?? null;
  const auth = opts.auth ?? globalThis.naslifeAuth ?? null;
  if (!pool || !auth) throw new Error("tasks: pool and auth are required");
  await pool.query(`
    CREATE TABLE IF NOT EXISTS work_tasks (
      id UUID PRIMARY KEY, title TEXT NOT NULL, description TEXT NOT NULL DEFAULT '',
      status TEXT NOT NULL DEFAULT 'todo', priority TEXT NOT NULL DEFAULT 'normal',
      assignee_id TEXT, creator_id TEXT NOT NULL, department TEXT NOT NULL DEFAULT '',
      due_at TIMESTAMPTZ, tags JSONB NOT NULL DEFAULT '[]', related JSONB, checklist JSONB NOT NULL DEFAULT '[]',
      reminded_due BOOLEAN NOT NULL DEFAULT false, reminded_overdue BOOLEAN NOT NULL DEFAULT false,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), completed_at TIMESTAMPTZ);
    CREATE INDEX IF NOT EXISTS work_tasks_assignee ON work_tasks(assignee_id, status);
    CREATE INDEX IF NOT EXISTS work_tasks_creator ON work_tasks(creator_id);
    CREATE TABLE IF NOT EXISTS work_task_comments (id UUID PRIMARY KEY, task_id UUID NOT NULL, user_id TEXT NOT NULL, text TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE INDEX IF NOT EXISTS work_task_comments_task ON work_task_comments(task_id, created_at);
    CREATE TABLE IF NOT EXISTS work_task_events (id UUID PRIMARY KEY, task_id UUID NOT NULL, user_id TEXT NOT NULL, kind TEXT NOT NULL, data JSONB NOT NULL DEFAULT '{}', created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE INDEX IF NOT EXISTS work_task_events_task ON work_task_events(task_id, created_at);
  `);
  const teamInfo = async (uid) => { try { return (await globalThis.naslifeTeamInfo?.(uid)) ?? null; } catch { return null; } };
  const teamScope = async (uid) => { try { return (await globalThis.naslifeTeamScope?.(uid)) ?? { all: false, ids: new Set([uid]) }; } catch { return { all: false, ids: new Set([uid]) }; } };
  const teamMembers = async () => { try { return (await globalThis.naslifeTeamMembers?.()) ?? []; } catch { return []; } };
  const people = async (ids) => { try { return (await globalThis.naslifeTeamPeople?.(ids)) ?? new Map(); } catch { return new Map(); } };
  const personOf = (map, id) => (id ? (map.get(id) ?? { id, nickname: "", avatarUrl: null }) : null);
  const notify = async (ids, payload) => { try { await globalThis.naslifeNotify?.([...new Set(ids.filter(Boolean))], payload); } catch { /* ignore */ } };
  const bad = (reply, code, error, extra = {}) => reply.code(code).send({ error, ...extra });
  const has = (info, perm) => !!info && (info.permissions.includes("*") || info.permissions.includes(perm));

  async function guard(req, reply) {
    const uid = await auth(req); if (!uid) { bad(reply, 401, "auth"); return null; }
    const info = await teamInfo(uid);
    if (!has(info, "tasks.view")) { bad(reply, 403, "forbidden", { need: "tasks.view" }); return null; }
    req.teamInfo = info; return uid;
  }
  const event = async (taskId, uid, kind, data = {}) => { await pool.query("INSERT INTO work_task_events(id,task_id,user_id,kind,data) VALUES($1,$2,$3,$4,$5)", [crypto.randomUUID(), taskId, uid, kind, JSON.stringify(data)]); };
  const taskRow = async (id) => (UUID_RE.test(id) ? (await pool.query("SELECT t.*, (SELECT count(*)::int FROM work_task_comments c WHERE c.task_id=t.id) AS comments FROM work_tasks t WHERE id=$1", [id])).rows[0] ?? null : null);
  /// هل يرى هذا العضو المهمة؟ ولماذا (manage | own | created | scope)
  async function visibility(uid, info, t) {
    if (has(info, "tasks.manage")) return "manage";
    if (t.assignee_id === uid) return "own";
    if (t.creator_id === uid) return "created";
    const s = await teamScope(uid);
    if (s.all || (t.assignee_id && s.ids.has(t.assignee_id)) || s.ids.has(t.creator_id)) return "scope";
    return null;
  }
  /// هل يجوز إسناد مهمة لهذا الشخص؟
  async function canAssign(uid, info, targetId) {
    if (!targetId) return true;
    if (targetId === uid) return true;
    if (!has(info, "tasks.assign") && !has(info, "tasks.manage")) return false;
    const members = await teamMembers();
    const isMember = members.some((m) => m.user_id === targetId) || !!(await teamInfo(targetId));
    if (!isMember) return false;
    if (has(info, "tasks.manage")) return true;
    const s = await teamScope(uid);
    return s.all || s.ids.has(targetId);
  }
  const out = (t, pmap, uid, vis) => ({
    id: t.id, title: t.title, description: t.description, status: t.status, priority: t.priority,
    assignee: personOf(pmap, t.assignee_id), creator: personOf(pmap, t.creator_id), department: t.department,
    dueAt: t.due_at, tags: t.tags ?? [], related: t.related ?? null, checklist: t.checklist ?? [], comments: t.comments ?? 0,
    createdAt: t.created_at, updatedAt: t.updated_at, completedAt: t.completed_at,
    overdue: !!t.due_at && t.status !== "done" && new Date(t.due_at) < new Date(),
    canEdit: vis === "manage" || vis === "created" || vis === "scope", canUpdateStatus: vis !== null, mine: t.assignee_id === uid,
  });
  const parseDue = (v) => { if (v === undefined || v === null || v === "") return null; const d = new Date(v); return Number.isNaN(d.getTime()) ? undefined : d.toISOString(); };
  const cleanChecklist = (v) => Array.isArray(v) ? v.slice(0, 50).map((x) => ({ text: str(x?.text, 200), done: x?.done === true })).filter((x) => x.text) : null;
  const cleanTags = (v) => Array.isArray(v) ? [...new Set(v.map((x) => str(x, 30)).filter(Boolean))].slice(0, 10) : null;

  // ---- القائمة
  app.get("/adminapi/tasks", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    const info = req.teamInfo;
    const view = str(req.query?.view, 10) || "mine"; // mine | team | all
    const status = str(req.query?.status, 10); const priority = str(req.query?.priority, 10);
    const assignee = str(req.query?.assignee, 12).toUpperCase(); const term = str(req.query?.q, 60);
    const limit = Math.max(1, Math.min(200, Number(req.query?.limit) || 100));
    const where = []; const params = [];
    const manage = has(info, "tasks.manage");
    const s = await teamScope(uid);
    if (view === "mine") { params.push(uid); where.push(`(t.assignee_id=$${params.length} OR (t.assignee_id IS NULL AND t.creator_id=$${params.length}))`); }
    else if (!manage && !s.all) { params.push(uid); params.push([...s.ids]); where.push(`(t.assignee_id=$${params.length - 1} OR t.creator_id=$${params.length - 1} OR t.assignee_id = ANY($${params.length}) OR t.creator_id = ANY($${params.length}))`); }
    if (status && STATUSES.includes(status)) { params.push(status); where.push(`t.status=$${params.length}`); }
    else if (status === "open") where.push("t.status<>'done'");
    if (priority && PRIORITIES.includes(priority)) { params.push(priority); where.push(`t.priority=$${params.length}`); }
    if (ID_RE.test(assignee)) { params.push(assignee); where.push(`t.assignee_id=$${params.length}`); }
    if (term) { params.push(`%${term}%`); where.push(`(t.title ILIKE $${params.length} OR t.description ILIKE $${params.length})`); }
    params.push(limit);
    const sql = `SELECT t.*, (SELECT count(*)::int FROM work_task_comments c WHERE c.task_id=t.id) AS comments FROM work_tasks t ${where.length ? "WHERE " + where.join(" AND ") : ""}
      ORDER BY (t.status='done') ASC, CASE t.priority WHEN 'urgent' THEN 0 WHEN 'high' THEN 1 WHEN 'normal' THEN 2 ELSE 3 END, t.due_at ASC NULLS LAST, t.created_at DESC LIMIT $${params.length}`;
    const rows = (await pool.query(sql, params)).rows;
    const pmap = await people(rows.flatMap((t) => [t.assignee_id, t.creator_id]));
    const items = [];
    for (const t of rows) { const vis = await visibility(uid, info, t); if (vis) items.push(out(t, pmap, uid, vis)); }
    const counts = { todo: 0, doing: 0, review: 0, done: 0, blocked: 0, overdue: 0 };
    for (const it of items) { counts[it.status] = (counts[it.status] ?? 0) + 1; if (it.overdue) counts.overdue++; }
    // من يمكن الإسناد إليهم: نطاقي (أو الجميع مع tasks.manage)
    const members = await teamMembers();
    const assignable = members.filter((m) => manage || s.all || s.ids.has(m.user_id) || m.user_id === uid);
    const amap = await people(assignable.map((m) => m.user_id));
    return { items, counts, view, assignees: assignable.map((m) => ({ ...personOf(amap, m.user_id), roleName: m.role_name, title: m.title })), canAssign: has(info, "tasks.assign") || manage, canManage: manage };
  });
  // ---- ملخص لكل عضو في نطاقي (للمدير)
  app.get("/adminapi/tasks/summary", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    const info = req.teamInfo; const s = await teamScope(uid); const manage = has(info, "tasks.manage");
    const members = (await teamMembers()).filter((m) => manage || s.all || s.ids.has(m.user_id));
    const ids = members.map((m) => m.user_id);
    const r = ids.length ? (await pool.query(`SELECT assignee_id, count(*) FILTER (WHERE status<>'done')::int AS open, count(*) FILTER (WHERE status<>'done' AND due_at IS NOT NULL AND due_at < now())::int AS overdue,
      count(*) FILTER (WHERE status='done' AND completed_at > now() - interval '30 days')::int AS done30, count(*) FILTER (WHERE status='review')::int AS review FROM work_tasks WHERE assignee_id = ANY($1) GROUP BY assignee_id`, [ids])).rows : [];
    const by = new Map(r.map((x) => [x.assignee_id, x]));
    const pmap = await people(ids);
    return { members: members.map((m) => { const x = by.get(m.user_id) ?? {}; return { ...personOf(pmap, m.user_id), roleName: m.role_name, title: m.title, department: m.department, open: x.open ?? 0, overdue: x.overdue ?? 0, review: x.review ?? 0, done30: x.done30 ?? 0 }; }) };
  });
  // ---- إنشاء
  app.post("/adminapi/tasks", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    const info = req.teamInfo; const b = req.body ?? {};
    const title = str(b.title, 160); if (title.length < 2) return bad(reply, 400, "bad-title");
    const status = b.status === undefined ? "todo" : str(b.status, 10); if (!STATUSES.includes(status)) return bad(reply, 400, "bad-status");
    const priority = b.priority === undefined ? "normal" : str(b.priority, 10); if (!PRIORITIES.includes(priority)) return bad(reply, 400, "bad-priority");
    const assignee = b.assigneeId ? str(b.assigneeId, 12).toUpperCase() : null;
    if (assignee && !ID_RE.test(assignee)) return bad(reply, 400, "bad-assignee");
    if (!(await canAssign(uid, info, assignee))) return bad(reply, 403, "cannot-assign");
    const due = parseDue(b.dueAt); if (due === undefined) return bad(reply, 400, "bad-due");
    const id = crypto.randomUUID();
    const related = b.related && typeof b.related === "object" ? { type: str(b.related.type, 30), id: str(b.related.id, 80), label: str(b.related.label, 120) } : null;
    await pool.query("INSERT INTO work_tasks(id,title,description,status,priority,assignee_id,creator_id,department,due_at,tags,related,checklist,completed_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)",
      [id, title, str(b.description, 5000), status, priority, assignee, uid, str(b.department, 60) || info.department || "", due, JSON.stringify(cleanTags(b.tags) ?? []), related ? JSON.stringify(related) : null, JSON.stringify(cleanChecklist(b.checklist) ?? []), status === "done" ? new Date().toISOString() : null]);
    await event(id, uid, "created", { assignee, priority, due });
    if (assignee && assignee !== uid) await notify([assignee], { kind: "task_assigned", title: "مهمة جديدة أُسندت إليك", body: `${title}${due ? ` · الموعد ${new Date(due).toLocaleDateString("ar-SA")}` : ""} · الأولوية ${PRIORITY_AR[priority]}`, data: { taskId: id, section: "tasks" } });
    const t = await taskRow(id); const pmap = await people([t.assignee_id, t.creator_id]);
    return out(t, pmap, uid, "created");
  });
  // ---- تفاصيل
  app.get("/adminapi/tasks/:id", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    const t = await taskRow(str(req.params.id, 36)); if (!t) return bad(reply, 404, "not-found");
    const vis = await visibility(uid, req.teamInfo, t); if (!vis) return bad(reply, 403, "forbidden");
    const comments = (await pool.query("SELECT * FROM work_task_comments WHERE task_id=$1 ORDER BY created_at", [t.id])).rows;
    const events = (await pool.query("SELECT * FROM work_task_events WHERE task_id=$1 ORDER BY created_at DESC LIMIT 100", [t.id])).rows;
    const pmap = await people([t.assignee_id, t.creator_id, ...comments.map((c) => c.user_id), ...events.map((e) => e.user_id)]);
    return { ...out(t, pmap, uid, vis), commentList: comments.map((c) => ({ id: c.id, user: personOf(pmap, c.user_id), text: c.text, createdAt: c.created_at })), events: events.map((e) => ({ id: e.id, user: personOf(pmap, e.user_id), kind: e.kind, data: e.data, createdAt: e.created_at })) };
  });
  // ---- تعديل
  app.patch("/adminapi/tasks/:id", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    const info = req.teamInfo;
    const t = await taskRow(str(req.params.id, 36)); if (!t) return bad(reply, 404, "not-found");
    const vis = await visibility(uid, info, t); if (!vis) return bad(reply, 403, "forbidden");
    const b = req.body ?? {}; const sets = []; const params = [t.id]; const changes = {};
    const set = (col, val) => { params.push(val); sets.push(`"${col}"=$${params.length}`); changes[col] = val; };
    const ownerOnly = vis === "own"; // المسند إليه فقط: الحالة والقائمة والتعليقات
    if (b.status !== undefined) { const s = str(b.status, 10); if (!STATUSES.includes(s)) return bad(reply, 400, "bad-status"); if (s !== t.status) { set("status", s); set("completed_at", s === "done" ? new Date().toISOString() : null); } }
    if (b.checklist !== undefined) { const c = cleanChecklist(b.checklist); if (!c) return bad(reply, 400, "bad-checklist"); set("checklist", JSON.stringify(c)); }
    if (!ownerOnly) {
      if (b.title !== undefined) { const title = str(b.title, 160); if (title.length < 2) return bad(reply, 400, "bad-title"); set("title", title); }
      if (b.description !== undefined) set("description", str(b.description, 5000));
      if (b.priority !== undefined) { const p = str(b.priority, 10); if (!PRIORITIES.includes(p)) return bad(reply, 400, "bad-priority"); set("priority", p); }
      if (b.department !== undefined) set("department", str(b.department, 60));
      if (b.dueAt !== undefined) { const d = parseDue(b.dueAt); if (d === undefined) return bad(reply, 400, "bad-due"); set("due_at", d); set("reminded_due", false); set("reminded_overdue", false); }
      if (b.tags !== undefined) { const tg = cleanTags(b.tags); if (!tg) return bad(reply, 400, "bad-tags"); set("tags", JSON.stringify(tg)); }
      if (b.assigneeId !== undefined) {
        const a = b.assigneeId ? str(b.assigneeId, 12).toUpperCase() : null;
        if (a && !ID_RE.test(a)) return bad(reply, 400, "bad-assignee");
        if (a !== t.assignee_id) { if (!(await canAssign(uid, info, a))) return bad(reply, 403, "cannot-assign"); set("assignee_id", a); }
      }
    } else if (["title", "description", "priority", "dueAt", "assigneeId", "tags", "department"].some((k) => b[k] !== undefined)) return bad(reply, 403, "assignee-limited");
    if (!sets.length) return bad(reply, 400, "nothing-to-update");
    await pool.query(`UPDATE work_tasks SET ${sets.join(", ")}, updated_at=now() WHERE id=$1`, params);
    if (changes.status) await event(t.id, uid, "status", { from: t.status, to: changes.status });
    if ("assignee_id" in changes) await event(t.id, uid, "assigned", { from: t.assignee_id, to: changes.assignee_id });
    const edited = Object.keys(changes).filter((k) => !["status", "completed_at", "assignee_id", "reminded_due", "reminded_overdue"].includes(k));
    if (edited.length) await event(t.id, uid, "edited", { fields: edited });
    // إشعارات: تغيّر الحالة يصل للمنشئ (إن لم يكن هو)، الإسناد الجديد يصل للمسند إليه
    if (changes.status && t.creator_id !== uid) await notify([t.creator_id], { kind: "task_status", title: `المهمة «${t.title}» أصبحت ${STATUS_AR[changes.status]}`, body: "", data: { taskId: t.id, section: "tasks" } });
    if (changes.status && t.assignee_id && t.assignee_id !== uid) await notify([t.assignee_id], { kind: "task_status", title: `حالة مهمتك «${t.title}» أصبحت ${STATUS_AR[changes.status]}`, body: "", data: { taskId: t.id, section: "tasks" } });
    if ("assignee_id" in changes && changes.assignee_id && changes.assignee_id !== uid) await notify([changes.assignee_id], { kind: "task_assigned", title: "مهمة أُسندت إليك", body: t.title, data: { taskId: t.id, section: "tasks" } });
    const n = await taskRow(t.id); const pmap = await people([n.assignee_id, n.creator_id]);
    return out(n, pmap, uid, await visibility(uid, info, n));
  });
  // ---- تعليق
  app.post("/adminapi/tasks/:id/comments", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    const t = await taskRow(str(req.params.id, 36)); if (!t) return bad(reply, 404, "not-found");
    if (!(await visibility(uid, req.teamInfo, t))) return bad(reply, 403, "forbidden");
    const text = str(req.body?.text, 4000); if (!text) return bad(reply, 400, "bad-text");
    const id = crypto.randomUUID();
    await pool.query("INSERT INTO work_task_comments(id,task_id,user_id,text) VALUES($1,$2,$3,$4)", [id, t.id, uid, text]);
    await pool.query("UPDATE work_tasks SET updated_at=now() WHERE id=$1", [t.id]);
    await event(t.id, uid, "comment", { id });
    await notify([t.assignee_id, t.creator_id].filter((x) => x && x !== uid), { kind: "task_comment", title: `تعليق جديد على «${t.title}»`, body: text.slice(0, 120), data: { taskId: t.id, section: "tasks" } });
    const pmap = await people([uid]);
    return { id, user: personOf(pmap, uid), text, createdAt: new Date().toISOString() };
  });
  // ---- حذف: المنشئ أو من يملك tasks.manage
  app.delete("/adminapi/tasks/:id", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    const t = await taskRow(str(req.params.id, 36)); if (!t) return bad(reply, 404, "not-found");
    if (t.creator_id !== uid && !has(req.teamInfo, "tasks.manage")) return bad(reply, 403, "forbidden");
    await pool.query("DELETE FROM work_task_comments WHERE task_id=$1", [t.id]);
    await pool.query("DELETE FROM work_task_events WHERE task_id=$1", [t.id]);
    await pool.query("DELETE FROM work_tasks WHERE id=$1", [t.id]);
    return { ok: true };
  });

  // ---- تذكيرات: قبل الموعد بيوم، وعند التأخر (مرة واحدة لكل حالة)
  async function sweep() {
    const soon = (await pool.query("SELECT id, title, assignee_id, creator_id, due_at FROM work_tasks WHERE status<>'done' AND due_at IS NOT NULL AND NOT reminded_due AND due_at <= now() + interval '24 hours' AND due_at > now()")).rows;
    for (const t of soon) {
      await pool.query("UPDATE work_tasks SET reminded_due=true WHERE id=$1", [t.id]);
      await notify([t.assignee_id ?? t.creator_id], { kind: "task_due", title: `موعد المهمة «${t.title}» خلال 24 ساعة`, body: "", data: { taskId: t.id, section: "tasks" } });
    }
    const late = (await pool.query("SELECT id, title, assignee_id, creator_id FROM work_tasks WHERE status<>'done' AND due_at IS NOT NULL AND NOT reminded_overdue AND due_at < now()")).rows;
    for (const t of late) {
      await pool.query("UPDATE work_tasks SET reminded_overdue=true WHERE id=$1", [t.id]);
      await notify([t.assignee_id, t.creator_id], { kind: "task_overdue", title: `تأخرت المهمة «${t.title}» عن موعدها`, body: "", data: { taskId: t.id, section: "tasks" } });
    }
    return { soon: soon.length, late: late.length };
  }
  globalThis.naslifeTasksSweep = sweep;
  const sweepMs = opts.sweepMs ?? 15 * 60000;
  if (sweepMs > 0) { const timer = setInterval(() => sweep().catch(() => {}), sweepMs); timer.unref?.(); app.addHook("onClose", async () => clearInterval(timer)); }
}
