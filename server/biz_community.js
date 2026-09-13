// مساحة مجتمع الدائرة في Naslife: مساحة تواصل عامة داخل كل دائرة تجارية (مطار، مستشفى، متجر…) ينشر فيها المستخدمون
// رسائل وصوراً مصنّفة بمواضيع (عام، صور، سؤال، نصيحة، تنبيه)، مع ردود وإعجابات، وتثبيت أو إخفاء من إدارة الدائرة.
// يطبّق فلتر الكلمات المحظورة وتصفية المحظورين والإشعارات عبر الإضافات الأخرى (safety.js, notify.js).
// التسجيل في src/index.js بعد business.js:
//   await app.register((await import("./biz_community.js")).default, { pool, auth });
import crypto from "node:crypto";

const TOPICS = new Set(["general", "photo", "question", "tip", "alert"]);
const UUID_RE = /^[0-9a-f-]{36}$/i;
const SLUG_RE = /^[a-z0-9][a-z0-9-]{1,63}$/;
const OWN_MEDIA = /^https?:\/\/[^/]+(\/(?:chat\/media|files|media|uploads)\/.*)$/i;
const str = (v, max) => String(v ?? "").trim().slice(0, max);

export default async function bizCommunity(app, opts) {
  const { pool, auth } = opts;
  if (!pool || !auth) throw new Error("biz_community: pool and auth are required");
  await pool.query(`
    CREATE TABLE IF NOT EXISTS biz_community_posts (
      id UUID PRIMARY KEY, biz_id TEXT NOT NULL, user_id TEXT NOT NULL, topic TEXT NOT NULL DEFAULT 'general',
      text TEXT NOT NULL DEFAULT '', images JSONB NOT NULL DEFAULT '[]', pinned BOOLEAN NOT NULL DEFAULT false,
      hidden BOOLEAN NOT NULL DEFAULT false, hidden_by TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE INDEX IF NOT EXISTS biz_community_posts_biz ON biz_community_posts(biz_id, pinned DESC, created_at DESC);
    CREATE TABLE IF NOT EXISTS biz_community_replies (
      id UUID PRIMARY KEY, post_id UUID NOT NULL, user_id TEXT NOT NULL, text TEXT NOT NULL, hidden BOOLEAN NOT NULL DEFAULT false,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE INDEX IF NOT EXISTS biz_community_replies_post ON biz_community_replies(post_id, created_at);
    CREATE TABLE IF NOT EXISTS biz_community_likes (post_id UUID NOT NULL, user_id TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (post_id, user_id));
  `);
  const unauthorized = (reply) => reply.code(401).send({ error: "auth" });
  const bad = (reply, code, error, extra = {}) => reply.code(code).send({ error, ...extra });
  const optionalAuth = async (req) => { try { return (await auth(req)) || null; } catch { return null; } };
  const isSuspended = async (uid) => { try { return (await pool.query("SELECT 1 FROM user_flags WHERE user_id=$1 AND suspended", [uid])).rowCount > 0; } catch { return false; } };
  const isAdmin = async (uid) => { try { return !!(await globalThis.naslifeIsAdmin?.(uid)); } catch { return false; } };
  const notify = async (ids, payload) => { try { await globalThis.naslifeNotify?.(ids, payload); } catch { /* ignore */ } };
  const blockedIds = async (uid) => { try { return uid ? await (globalThis.naslifeBlockedIds?.(uid) ?? []) : []; } catch { return []; } };
  const checkText = (...t) => { try { return globalThis.naslifeCheckText?.(...t) ?? null; } catch { return null; } };
  const publicOrigin = (req) => {
    const env = String(process.env.PUBLIC_BASE_URL ?? process.env.NASLIFE_PUBLIC_URL ?? "").trim().replace(/\/+$/, "");
    if (/^https?:\/\//i.test(env)) return env;
    const proto = String(req.headers["x-forwarded-proto"] ?? "https").split(",")[0].trim() || "https";
    const host = String(req.headers["x-forwarded-host"] ?? req.headers.host ?? "naslife.app").split(",")[0].trim().replace(/^www\./i, "");
    return `${proto}://${host}`;
  };
  // صور المنشور: مسارات وسائط خادمنا فقط (المرفوعة عبر /chat/upload)
  const cleanImages = (req, v) => {
    if (!Array.isArray(v)) return [];
    const out = [];
    for (const raw of v.slice(0, 4)) {
      const s = str(raw, 500); if (!s) continue;
      const own = OWN_MEDIA.exec(s);
      if (own) out.push(`${publicOrigin(req)}${own[1]}`);
      else if (/^\/(?:chat\/media|files|media|uploads)\//.test(s)) out.push(`${publicOrigin(req)}${s}`);
    }
    return out;
  };
  async function people(ids) {
    const uniq = [...new Set(ids.filter(Boolean))];
    const m = new Map();
    if (!uniq.length) return m;
    try {
      for (const u of (await pool.query("SELECT id, nickname, avatar_url FROM users WHERE id = ANY($1)", [uniq])).rows) m.set(u.id, { id: u.id, nickname: u.nickname ?? "", avatarUrl: u.avatar_url ?? null });
    } catch { /* ignore */ }
    for (const id of uniq) if (!m.has(id)) m.set(id, { id, nickname: "", avatarUrl: null });
    return m;
  }
  async function loadBiz(id) {
    if (!SLUG_RE.test(id ?? "")) return null;
    return (await pool.query("SELECT id, name, name_ar, owner_id, active FROM biz WHERE id=$1", [id])).rows[0] ?? null;
  }
  async function roleFor(uid, b) {
    if (!uid || !b) return null;
    if (b.owner_id === uid) return "owner";
    try { const s = (await pool.query("SELECT role FROM biz_staff WHERE biz_id=$1 AND user_id=$2", [b.id, uid])).rows[0]; if (s) return s.role; } catch { /* ignore */ }
    return (await isAdmin(uid)) ? "admin" : null;
  }
  const canModerate = (r) => r === "owner" || r === "manager" || r === "staff" || r === "admin";
  async function staffIds(b) {
    const ids = new Set(); if (b.owner_id) ids.add(b.owner_id);
    try { for (const r of (await pool.query("SELECT user_id FROM biz_staff WHERE biz_id=$1 AND role IN ('manager','staff')", [b.id])).rows) ids.add(r.user_id); } catch { /* ignore */ }
    return [...ids];
  }
  const out = (p, uid, pm, likes, liked, replies, role) => ({
    id: p.id, bizId: p.biz_id, user: pm.get(p.user_id), topic: p.topic, text: p.text, images: p.images ?? [], pinned: p.pinned, hidden: p.hidden,
    likes: likes.get(p.id) ?? 0, liked: liked.has(p.id), replies: replies.get(p.id) ?? 0, mine: p.user_id === uid,
    staff: role != null && p.user_id === uid && canModerate(role), createdAt: p.created_at,
  });
  async function decorate(rows, uid, role) {
    const ids = rows.map((p) => p.id);
    const pm = await people(rows.map((p) => p.user_id));
    const likes = new Map(), replies = new Map(), liked = new Set();
    if (ids.length) {
      for (const r of (await pool.query("SELECT post_id, count(*)::int AS n FROM biz_community_likes WHERE post_id = ANY($1::uuid[]) GROUP BY post_id", [ids])).rows) likes.set(r.post_id, r.n);
      for (const r of (await pool.query("SELECT post_id, count(*)::int AS n FROM biz_community_replies WHERE post_id = ANY($1::uuid[]) AND hidden=false GROUP BY post_id", [ids])).rows) replies.set(r.post_id, r.n);
      if (uid) for (const r of (await pool.query("SELECT post_id FROM biz_community_likes WHERE post_id = ANY($1::uuid[]) AND user_id=$2", [ids, uid])).rows) liked.add(r.post_id);
    }
    // من هم من طاقم الدائرة يُعلَّمون حتى تظهر شارة «إدارة الدائرة»
    return rows.map((p) => out(p, uid, pm, likes, liked, replies, role));
  }
  async function markStaff(list, b) {
    const ids = new Set(await staffIds(b));
    for (const p of list) p.staff = ids.has(p.user.id);
    return list;
  }
  const replyOut = (r, pm, uid) => ({ id: r.id, postId: r.post_id, user: pm.get(r.user_id), text: r.text, mine: r.user_id === uid, createdAt: r.created_at });

  // ---- القائمة: المثبّتة أولاً ثم الأحدث، بتصفية موضوع، وصفحات بـ before
  app.get("/biz/:id/community", async (req, reply) => {
    const uid = await optionalAuth(req);
    const b = await loadBiz(req.params.id); if (!b) return bad(reply, 404, "not-found");
    const role = await roleFor(uid, b);
    const topic = TOPICS.has(req.query?.topic) ? req.query.topic : null;
    const before = req.query?.before ? new Date(req.query.before) : null;
    if (before && isNaN(before)) return bad(reply, 400, "bad-before");
    const limit = Math.max(1, Math.min(50, Number(req.query?.limit) || 30));
    const blocked = await blockedIds(uid);
    const mod = canModerate(role);
    const rows = (await pool.query(`SELECT * FROM biz_community_posts WHERE biz_id=$1 AND ($2::boolean OR hidden=false OR user_id=$3)
      AND ($4::text IS NULL OR topic=$4) AND ($5::timestamptz IS NULL OR created_at < $5) AND NOT (user_id = ANY($6::text[]))
      ORDER BY (CASE WHEN $5::timestamptz IS NULL THEN pinned ELSE false END) DESC, created_at DESC LIMIT $7`,
      [b.id, mod, uid ?? "", topic, before, blocked, limit])).rows;
    const total = (await pool.query("SELECT count(*)::int AS n, count(DISTINCT user_id)::int AS members FROM biz_community_posts WHERE biz_id=$1 AND hidden=false", [b.id])).rows[0];
    const list = await markStaff(await decorate(rows, uid, role), b);
    return { posts: list, total: total.n, members: total.members, canModerate: mod, hasMore: rows.length === limit };
  });
  // ---- نشر
  app.post("/biz/:id/community", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (await isSuspended(uid)) return bad(reply, 403, "suspended");
    const b = await loadBiz(req.params.id); if (!b || b.active === false) return bad(reply, 404, "not-found");
    const body = req.body ?? {};
    const text = str(body.text, 1000);
    const images = cleanImages(req, body.images);
    if (!text && !images.length) return bad(reply, 400, "empty");
    const topic = TOPICS.has(body.topic) ? body.topic : (images.length && !text ? "photo" : "general");
    const banned = checkText(text); if (banned) return bad(reply, 400, "banned-words", { word: banned });
    const recent = (await pool.query("SELECT count(*)::int AS n FROM biz_community_posts WHERE biz_id=$1 AND user_id=$2 AND created_at > now() - interval '1 hour'", [b.id, uid])).rows[0].n;
    if (recent >= 20) return bad(reply, 429, "too-many");
    const id = crypto.randomUUID();
    const r = await pool.query("INSERT INTO biz_community_posts(id,biz_id,user_id,topic,text,images) VALUES($1,$2,$3,$4,$5,$6) RETURNING *", [id, b.id, uid, topic, text, JSON.stringify(images)]);
    const role = await roleFor(uid, b);
    if (topic === "question" || topic === "alert") {
      const staff = (await staffIds(b)).filter((x) => x !== uid);
      if (staff.length) await notify(staff, { kind: "community_post", title: `${topic === "question" ? "سؤال" : "تنبيه"} جديد في مساحة ${b.name_ar || b.name}`, body: text.slice(0, 120) || "صورة", data: { bizId: b.id, postId: id } });
    }
    const [p] = await markStaff(await decorate(r.rows, uid, role), b);
    return p;
  });
  // ---- منشور واحد مع ردوده
  app.get("/biz/:id/community/:pid", async (req, reply) => {
    const uid = await optionalAuth(req);
    const b = await loadBiz(req.params.id); if (!b) return bad(reply, 404, "not-found");
    if (!UUID_RE.test(req.params.pid)) return bad(reply, 404, "not-found");
    const role = await roleFor(uid, b);
    const p = (await pool.query("SELECT * FROM biz_community_posts WHERE id=$1 AND biz_id=$2", [req.params.pid, b.id])).rows[0];
    if (!p || (p.hidden && !canModerate(role) && p.user_id !== uid)) return bad(reply, 404, "not-found");
    const blocked = await blockedIds(uid);
    const rs = (await pool.query("SELECT * FROM biz_community_replies WHERE post_id=$1 AND hidden=false AND NOT (user_id = ANY($2::text[])) ORDER BY created_at ASC LIMIT 300", [p.id, blocked])).rows;
    const pm = await people(rs.map((r) => r.user_id));
    const [post] = await markStaff(await decorate([p], uid, role), b);
    return { post, replies: rs.map((r) => replyOut(r, pm, uid)), canModerate: canModerate(role) };
  });
  // ---- حذف / تثبيت / إخفاء
  app.delete("/biz/:id/community/:pid", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const b = await loadBiz(req.params.id); if (!b) return bad(reply, 404, "not-found");
    if (!UUID_RE.test(req.params.pid)) return bad(reply, 404, "not-found");
    const p = (await pool.query("SELECT user_id FROM biz_community_posts WHERE id=$1 AND biz_id=$2", [req.params.pid, b.id])).rows[0];
    if (!p) return bad(reply, 404, "not-found");
    if (p.user_id !== uid && !canModerate(await roleFor(uid, b))) return bad(reply, 403, "forbidden");
    await pool.query("DELETE FROM biz_community_replies WHERE post_id=$1", [req.params.pid]);
    await pool.query("DELETE FROM biz_community_likes WHERE post_id=$1", [req.params.pid]);
    await pool.query("DELETE FROM biz_community_posts WHERE id=$1", [req.params.pid]);
    return { ok: true };
  });
  for (const action of ["pin", "hide"]) {
    app.post(`/biz/:id/community/:pid/${action}`, async (req, reply) => {
      const uid = await auth(req); if (!uid) return unauthorized(reply);
      const b = await loadBiz(req.params.id); if (!b) return bad(reply, 404, "not-found");
      if (!UUID_RE.test(req.params.pid)) return bad(reply, 404, "not-found");
      const role = await roleFor(uid, b);
      if (!canModerate(role)) return bad(reply, 403, "forbidden");
      const on = req.body?.[action === "pin" ? "pinned" : "hidden"] !== false;
      const col = action === "pin" ? "pinned" : "hidden";
      const r = await pool.query(`UPDATE biz_community_posts SET ${col}=$3, hidden_by=CASE WHEN $4 THEN $5 ELSE hidden_by END, updated_at=now() WHERE id=$1 AND biz_id=$2 RETURNING *`, [req.params.pid, b.id, on, action === "hide", on ? uid : null]);
      if (!r.rowCount) return bad(reply, 404, "not-found");
      if (action === "hide" && on && r.rows[0].user_id !== uid) await notify([r.rows[0].user_id], { kind: "community_hidden", title: `أُخفي منشورك في مساحة ${b.name_ar || b.name}`, body: "أخفته إدارة الدائرة", data: { bizId: b.id, postId: req.params.pid } });
      const [p] = await markStaff(await decorate(r.rows, uid, role), b);
      return p;
    });
  }
  // ---- إعجاب
  app.post("/biz/:id/community/:pid/like", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.pid)) return bad(reply, 404, "not-found");
    const p = (await pool.query("SELECT id FROM biz_community_posts WHERE id=$1 AND biz_id=$2 AND hidden=false", [req.params.pid, String(req.params.id)])).rows[0];
    if (!p) return bad(reply, 404, "not-found");
    const del = await pool.query("DELETE FROM biz_community_likes WHERE post_id=$1 AND user_id=$2 RETURNING 1", [p.id, uid]);
    let liked = false;
    if (!del.rowCount) { await pool.query("INSERT INTO biz_community_likes(post_id,user_id) VALUES($1,$2) ON CONFLICT DO NOTHING", [p.id, uid]); liked = true; }
    const n = (await pool.query("SELECT count(*)::int AS n FROM biz_community_likes WHERE post_id=$1", [p.id])).rows[0].n;
    return { ok: true, liked, likes: n };
  });
  // ---- الردود
  app.post("/biz/:id/community/:pid/replies", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (await isSuspended(uid)) return bad(reply, 403, "suspended");
    const b = await loadBiz(req.params.id); if (!b) return bad(reply, 404, "not-found");
    if (!UUID_RE.test(req.params.pid)) return bad(reply, 404, "not-found");
    const p = (await pool.query("SELECT id, user_id, text FROM biz_community_posts WHERE id=$1 AND biz_id=$2 AND hidden=false", [req.params.pid, b.id])).rows[0];
    if (!p) return bad(reply, 404, "not-found");
    const text = str(req.body?.text, 500); if (!text) return bad(reply, 400, "empty");
    const banned = checkText(text); if (banned) return bad(reply, 400, "banned-words", { word: banned });
    const id = crypto.randomUUID();
    const r = await pool.query("INSERT INTO biz_community_replies(id,post_id,user_id,text) VALUES($1,$2,$3,$4) RETURNING *", [id, p.id, uid, text]);
    if (p.user_id !== uid) {
      const pm = await people([uid]);
      await notify([p.user_id], { kind: "community_reply", title: `رد على منشورك في مساحة ${b.name_ar || b.name}`, body: `${pm.get(uid)?.nickname || uid}: ${text.slice(0, 100)}`, data: { bizId: b.id, postId: p.id } });
    }
    const pm = await people([uid]);
    return replyOut(r.rows[0], pm, uid);
  });
  app.delete("/biz/:id/community/:pid/replies/:rid", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const b = await loadBiz(req.params.id); if (!b) return bad(reply, 404, "not-found");
    if (!UUID_RE.test(req.params.pid) || !UUID_RE.test(req.params.rid)) return bad(reply, 404, "not-found");
    const r = (await pool.query("SELECT user_id FROM biz_community_replies WHERE id=$1 AND post_id=$2", [req.params.rid, req.params.pid])).rows[0];
    if (!r) return bad(reply, 404, "not-found");
    if (r.user_id !== uid && !canModerate(await roleFor(uid, b))) return bad(reply, 403, "forbidden");
    await pool.query("DELETE FROM biz_community_replies WHERE id=$1", [req.params.rid]);
    return { ok: true };
  });
  // للإخفاء التلقائي من safety.js عند تعدد البلاغات
  globalThis.naslifeCommunityHide = async (postId) => {
    const r = await pool.query("UPDATE biz_community_posts SET hidden=true, hidden_by='auto', updated_at=now() WHERE id=$1 AND hidden=false RETURNING user_id, biz_id", [postId]);
    return r.rows[0] ?? null;
  };
  app.get("/biz/community/status", async () => ({ ok: true, topics: [...TOPICS] }));
}
