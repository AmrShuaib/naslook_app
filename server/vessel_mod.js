// إشراف منشورات الدوائر (المجموعات التي ينشئها المستخدمون) في Naslife.
// النواة تسمح لصاحب المنشور فقط بحذفه (DELETE /posts/:id)؛ هذه الإضافة تمنح مالك الدائرة ومشرفيها (ومديري النظام)
// إزالة منشور: تحاول الحذف في النواة أولاً بجلسة الطالب، وإن رفضته تسجّله مخفياً في جدول vessel_post_mod
// فيختفي من التطبيق (البث والدائرة) عبر GET /posts/hidden. تعرّف للإضافات الأخرى:
//   globalThis.naslifeVesselPostHide(postId, {by, reason}) → true إن أُخفي الآن
//   globalThis.naslifeVesselPostInfo(postId) → {owner, title, status, vessel_id} أو null
// التسجيل في src/index.js قبل safety.js:
//   await app.register((await import("./vessel_mod.js")).default, { pool, auth });

const ID_RE = /^[A-Za-z0-9_-]{1,64}$/;
const MOD_ROLES = new Set(["owner", "moderator", "admin"]);
const q = (ident) => `"${String(ident).replace(/"/g, '""')}"`;
const str = (v, max) => String(v ?? "").trim().slice(0, max);

export default async function vesselMod(app, opts) {
  const pool = opts?.pool ?? globalThis.naslifePool ?? null;
  const auth = opts?.auth ?? globalThis.naslifeAuth ?? null;
  if (!pool || !auth) throw new Error("vessel_mod: pool and auth are required");
  await pool.query(`
    CREATE TABLE IF NOT EXISTS vessel_post_mod (
      post_id TEXT PRIMARY KEY, vessel_id TEXT NOT NULL DEFAULT '', hidden_by TEXT NOT NULL DEFAULT '',
      reason TEXT NOT NULL DEFAULT '', created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE INDEX IF NOT EXISTS vessel_post_mod_vessel ON vessel_post_mod(vessel_id);
  `);

  // اكتشاف جدول منشورات الدوائر في النواة (إن كان في القاعدة نفسها) لقراءة المؤلف والنص
  let PT = null;
  try {
    const cols = (await pool.query("SELECT table_name, column_name FROM information_schema.columns WHERE table_schema='public'")).rows;
    const tables = new Map();
    for (const c of cols) { if (!tables.has(c.table_name)) tables.set(c.table_name, new Set()); tables.get(c.table_name).add(c.column_name); }
    const pick = (m, ...names) => names.find((n) => m?.has(n)) ?? null;
    for (const name of ["posts", "vessel_posts"]) {
      const m = tables.get(name);
      if (!m) continue;
      const vessel = pick(m, "vessel_id", "vesselId");
      const author = pick(m, "author_id", "user_id", "authorId", "owner_id");
      if (!vessel || !author) continue;
      PT = { name, vessel, author, content: pick(m, "content", "text", "body", "caption"), deleted: pick(m, "deleted_at", "deleted") };
      break;
    }
  } catch { PT = null; }

  const notify = async (ids, payload) => { try { await globalThis.naslifeNotify?.(ids.filter(Boolean), payload); } catch { /* ignore */ } };
  const isAdmin = async (uid) => { try { return !!(await globalThis.naslifeIsAdmin?.(uid)); } catch { return false; } };
  const unauthorized = (reply) => reply.code(401).send({ error: "auth" });
  const bad = (reply, code, error, extra = {}) => reply.code(code).send({ error, ...extra });
  const fwdHeaders = (req) => {
    const h = {};
    for (const k of ["x-token", "authorization", "x-user", "cookie"]) if (req.headers[k]) h[k] = req.headers[k];
    return h;
  };
  const parse = (r) => { try { return r.json(); } catch { return null; } };

  /// معلومات المنشور من جدول النواة (إن وُجد) + حالة الإخفاء
  async function postInfo(id) {
    if (!ID_RE.test(id)) return null;
    const hidden = (await pool.query("SELECT vessel_id, hidden_by, reason FROM vessel_post_mod WHERE post_id=$1", [id])).rows[0] ?? null;
    let row = null;
    if (PT) {
      try {
        const sel = `SELECT ${q(PT.author)} AS owner, ${q(PT.vessel)} AS vessel_id${PT.content ? `, left(${q(PT.content)}::text, 80) AS title` : ""} FROM ${q(PT.name)} WHERE id::text=$1`;
        row = (await pool.query(sel, [id])).rows[0] ?? null;
      } catch { row = null; }
      if (!row && !hidden) return null;
    }
    return {
      owner: row?.owner ?? null,
      vessel_id: row?.vessel_id ?? hidden?.vessel_id ?? null,
      title: str(row?.title, 80) || "منشور في دائرة",
      status: hidden ? "blocked" : "active",
      hiddenBy: hidden?.hidden_by ?? null,
    };
  }
  async function hidePost(id, { vesselId = "", by = "", reason = "" } = {}) {
    if (!ID_RE.test(id)) return false;
    const r = await pool.query(
      "INSERT INTO vessel_post_mod(post_id,vessel_id,hidden_by,reason) VALUES($1,$2,$3,$4) ON CONFLICT (post_id) DO NOTHING RETURNING post_id",
      [id, str(vesselId, 64), str(by, 32), str(reason, 300)]);
    return r.rowCount > 0;
  }
  globalThis.naslifeVesselPostInfo = postInfo;
  globalThis.naslifeVesselPostHide = hidePost;

  /// الدائرة من النواة بجلسة الطالب (تعطي role وownerId)
  async function coreVessel(req, vesselId) {
    if (!ID_RE.test(vesselId)) return null;
    try {
      const r = await app.inject({ method: "GET", url: `/vessels/${encodeURIComponent(vesselId)}`, headers: fwdHeaders(req) });
      if (r.statusCode !== 200) return null;
      const v = parse(r);
      return v && typeof v === "object" ? v : null;
    } catch { return null; }
  }
  const canModerate = (uid, v) => !!v && (v.ownerId === uid || MOD_ROLES.has(String(v.role ?? "").toLowerCase()));

  app.get("/vessel-mod/status", async () => ({ ok: true, postsTable: PT?.name ?? null }));

  /// المنشورات المخفية (لتصفيتها في التطبيق). ?vessel= اختياري
  app.get("/posts/hidden", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const vessel = str(req.query?.vessel, 64);
    const r = vessel
      ? await pool.query("SELECT post_id FROM vessel_post_mod WHERE vessel_id=$1 ORDER BY created_at DESC LIMIT 5000", [vessel])
      : await pool.query("SELECT post_id FROM vessel_post_mod ORDER BY created_at DESC LIMIT 5000");
    return { ids: r.rows.map((x) => x.post_id) };
  });

  /// إزالة منشور من دائرة: مالكها/مشرفوها/مديرو النظام
  app.post("/posts/:id/remove", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const id = str(req.params.id, 64);
    if (!ID_RE.test(id)) return bad(reply, 400, "bad-post");
    const info = await postInfo(id);
    let vesselId = str(req.body?.vesselId, 64) || info?.vessel_id || "";
    if (!vesselId) return bad(reply, 400, "bad-vessel");
    if (info?.vessel_id && info.vessel_id !== vesselId) return bad(reply, 400, "bad-vessel");
    const reason = str(req.body?.reason, 300);
    const v = await coreVessel(req, vesselId);
    const admin = !canModerate(uid, v) && (await isAdmin(uid));
    if (!v && !admin) return bad(reply, 404, "not-found");
    if (!canModerate(uid, v) && !admin) return bad(reply, 403, "forbidden");
    // 1) الحذف الفعلي في النواة إن سمحت (صاحب المنشور، أو صلاحيات أوسع مستقبلاً)
    let core = null;
    try { core = await app.inject({ method: "DELETE", url: `/posts/${encodeURIComponent(id)}`, headers: fwdHeaders(req) }); } catch { core = null; }
    if (core && core.statusCode >= 200 && core.statusCode < 300) {
      await pool.query("DELETE FROM vessel_post_mod WHERE post_id=$1", [id]);
      return { ok: true, deleted: true, hidden: false };
    }
    if (core && core.statusCode === 404 && PT && !info) return bad(reply, 404, "not-found");
    // 2) وإلا يُخفى من التطبيق
    const inserted = await hidePost(id, { vesselId, by: uid, reason });
    if (inserted && info?.owner && info.owner !== uid) {
      await notify([info.owner], { kind: "vessel_post_hidden", title: "أزال مشرف الدائرة منشورك", body: `«${info.title}»${reason ? ` — ${reason}` : ""}`, data: { vesselId, postId: id, reason: reason || "moderation" } });
    }
    return { ok: true, deleted: false, hidden: true, already: !inserted };
  });

  /// إعادة إظهار منشور مخفي
  app.post("/posts/:id/unhide", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const id = str(req.params.id, 64);
    if (!ID_RE.test(id)) return bad(reply, 400, "bad-post");
    const row = (await pool.query("SELECT vessel_id FROM vessel_post_mod WHERE post_id=$1", [id])).rows[0];
    if (!row) return bad(reply, 404, "not-found");
    const vesselId = row.vessel_id || str(req.body?.vesselId, 64);
    const v = vesselId ? await coreVessel(req, vesselId) : null;
    if (!canModerate(uid, v) && !(await isAdmin(uid))) return bad(reply, 403, "forbidden");
    await pool.query("DELETE FROM vessel_post_mod WHERE post_id=$1", [id]);
    return { ok: true };
  });
}
