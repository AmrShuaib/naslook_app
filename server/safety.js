// الأمان والإشراف في Naslife: كتم المحادثات، بلاغات المحتوى (منشورات الخريطة وعروض السوق) مع إخفاء تلقائي عند بلوغ حدّ
// البلاغات، فلتر الكلمات المحظورة (تُضبط من لوحة الإدارة)، وقائمة المحظورين من جدول الحظر في النواة لتصفية المحتوى.
// يعرّف للإضافات الأخرى: globalThis.naslifeCheckText(...نصوص) → الكلمة المحظورة أو null،
// وglobalThis.naslifeBlockedIds(uid) → معرّفات من حظرهم المستخدم أو حظروه.
// التسجيل في src/index.js قبل admin.js:
//   await app.register((await import("./safety.js")).default, { pool, auth });
import crypto from "node:crypto";
import { normQ } from "./business.js";

const UUID_RE = /^[0-9a-f-]{36}$/i;
const ID_RE = /^[A-Z]{2}\d{7}$/i;
const TARGETS = new Set(["post", "listing"]);
const q = (ident) => `"${String(ident).replace(/"/g, '""')}"`;
const str = (v, max) => String(v ?? "").trim().slice(0, max);

/// الكلمات المحظورة من نص الإعدادات (سطر أو فاصلة لكل كلمة) مطبّعةً.
export function parseWords(raw) {
  return [...new Set(String(raw ?? "").split(/[\n,،;]+/).map((w) => normQ(w)).filter((w) => w.length >= 2))];
}
/// أول كلمة محظورة تظهر داخل النصوص (بعد التطبيع العربي) أو null.
export function findBanned(words, ...texts) {
  if (!words.length) return null;
  const t = normQ(texts.filter(Boolean).join(" "));
  if (!t) return null;
  for (const w of words) if (t.includes(w)) return w;
  return null;
}

export default async function safety(app, opts) {
  const { pool, auth } = opts;
  if (!pool || !auth) throw new Error("safety: pool and auth are required");
  await pool.query(`
    CREATE TABLE IF NOT EXISTS chat_mutes (
      user_id TEXT NOT NULL, peer_id TEXT NOT NULL, until TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      PRIMARY KEY (user_id, peer_id));
    CREATE TABLE IF NOT EXISTS content_reports (
      id UUID PRIMARY KEY, reporter_id TEXT NOT NULL, target_type TEXT NOT NULL, target_id TEXT NOT NULL,
      reason TEXT NOT NULL DEFAULT '', created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      UNIQUE (reporter_id, target_type, target_id));
    CREATE INDEX IF NOT EXISTS content_reports_target ON content_reports(target_type, target_id);
  `);
  const cols = (await pool.query("SELECT table_name, column_name FROM information_schema.columns WHERE table_schema='public'")).rows;
  const tables = new Map();
  for (const c of cols) { if (!tables.has(c.table_name)) tables.set(c.table_name, new Set()); tables.get(c.table_name).add(c.column_name); }
  const pick = (m, ...names) => names.find((n) => m?.has(n)) ?? null;
  // جدول الحظر في النواة (أسماء أعمدته تُكتشف)
  const blocksTable = [...tables.keys()].find((t) => /block/.test(t) && !/report/.test(t)) ?? null;
  const BC = blocksTable ? { user: pick(tables.get(blocksTable), "user_id", "blocker_id", "by_id", "owner_id"), blocked: pick(tables.get(blocksTable), "blocked_id", "blocked_user_id", "target_id", "to_id") } : null;
  const blocksOk = !!(BC?.user && BC?.blocked);
  async function blockedIds(uid) {
    if (!blocksOk || !uid) return [];
    try {
      const r = await pool.query(`SELECT ${q(BC.user)} AS a, ${q(BC.blocked)} AS b FROM ${q(blocksTable)} WHERE ${q(BC.user)}=$1 OR ${q(BC.blocked)}=$1`, [uid]);
      const s = new Set();
      for (const row of r.rows) { if (row.a && row.a !== uid) s.add(row.a); if (row.b && row.b !== uid) s.add(row.b); }
      return [...s];
    } catch { return []; }
  }
  const words = () => parseWords(globalThis.naslifeSettings?.bannedWords);
  const checkText = (...texts) => findBanned(words(), ...texts);
  const threshold = () => Math.max(1, Math.min(50, Math.round(Number(globalThis.naslifeSettings?.reportThreshold)) || 3));
  globalThis.naslifeCheckText = checkText;
  globalThis.naslifeBlockedIds = blockedIds;
  const notify = async (ids, payload) => { try { await globalThis.naslifeNotify?.(ids, payload); } catch { /* ignore */ } };
  const notifyAdmins = async (payload) => { try { await globalThis.naslifeNotifyAdmins?.(payload); } catch { /* ignore */ } };
  const unauthorized = (reply) => reply.code(401).send({ error: "auth" });
  const bad = (reply, code, error, extra = {}) => reply.code(code).send({ error, ...extra });

  app.get("/safety/status", async () => ({ ok: true, blocks: blocksOk, blocksTable, words: words().length, threshold: threshold() }));

  // ---- كتم المحادثات (الإشعارات في التطبيق؛ رسائل النواة تصل لكن بلا شارة)
  const muteOut = (r) => ({ peerId: r.peer_id, until: r.until, createdAt: r.created_at });
  app.get("/safety/mutes", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    await pool.query("DELETE FROM chat_mutes WHERE user_id=$1 AND until IS NOT NULL AND until < now()", [uid]);
    return (await pool.query("SELECT * FROM chat_mutes WHERE user_id=$1 ORDER BY created_at DESC", [uid])).rows.map(muteOut);
  });
  app.post("/safety/mutes", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const peer = str(req.body?.peerId, 12).toUpperCase();
    if (!ID_RE.test(peer) || peer === uid) return bad(reply, 400, "bad-peer");
    const hours = req.body?.hours == null ? null : Math.max(1, Math.min(24 * 365, Number(req.body.hours) || 0));
    const r = await pool.query(
      "INSERT INTO chat_mutes(user_id,peer_id,until) VALUES($1,$2, CASE WHEN $3::float8 IS NULL THEN NULL ELSE now() + ($3::float8 || ' hours')::interval END) ON CONFLICT (user_id,peer_id) DO UPDATE SET until=EXCLUDED.until, created_at=now() RETURNING *",
      [uid, peer, hours]);
    return muteOut(r.rows[0]);
  });
  app.delete("/safety/mutes/:peerId", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    await pool.query("DELETE FROM chat_mutes WHERE user_id=$1 AND peer_id=$2", [uid, str(req.params.peerId, 12).toUpperCase()]);
    return { ok: true };
  });

  // ---- الكلمات المحظورة: القائمة للتحقق المسبق في التطبيق، وفحص نص
  app.get("/safety/words", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    return { words: words(), threshold: threshold() };
  });
  app.post("/safety/check", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const word = checkText(str(req.body?.text, 5000));
    return { ok: !word, word };
  });

  // ---- بلاغات المحتوى مع الإخفاء التلقائي
  async function targetInfo(type, id) {
    if (type === "post") {
      if (!UUID_RE.test(id) || !tables.has("map_posts")) return null;
      const r = await pool.query("SELECT user_id AS owner, COALESCE(NULLIF(title,''), NULLIF(caption,''), 'منشور') AS title, status FROM map_posts WHERE id=$1", [id]);
      return r.rows[0] ?? null;
    }
    if (type === "listing") {
      if (!UUID_RE.test(id) || !tables.has("market_listings")) return null;
      const r = await pool.query("SELECT seller_id AS owner, title, status FROM market_listings WHERE id=$1", [id]);
      return r.rows[0] ?? null;
    }
    return null;
  }
  async function autoHide(type, id, info, n) {
    if (type === "post") {
      const r = await pool.query("UPDATE map_posts SET status='blocked', updated_at=now() WHERE id=$1 AND status<>'blocked' RETURNING id", [id]);
      if (!r.rowCount) return false;
      await notify([info.owner], { kind: "post_blocked", title: "أُخفي منشورك بعد عدة بلاغات", body: `«${info.title}» قيد مراجعة الإدارة`, data: { postId: id, reason: "reports", reports: n } });
    } else {
      const r = await pool.query("UPDATE market_listings SET status='blocked' WHERE id=$1 AND status<>'blocked' RETURNING id", [id]);
      if (!r.rowCount) return false;
      await notify([info.owner], { kind: "listing_hidden", title: "أُخفي عرضك بعد عدة بلاغات", body: `«${info.title}» قيد مراجعة الإدارة`, data: { listingId: id, reason: "reports", reports: n } });
    }
    await notifyAdmins({ kind: "content_autohidden", title: `أُخفي ${type === "post" ? "منشور" : "عرض"} تلقائياً بعد ${n} بلاغات`, body: `«${info.title}» — راجعه في قسم المحتوى`, data: { targetType: type, targetId: id, reports: n } });
    return true;
  }
  app.post("/safety/report", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const type = String(req.body?.targetType ?? ""); const id = str(req.body?.targetId, 64); const reason = str(req.body?.reason, 300);
    if (!TARGETS.has(type)) return bad(reply, 400, "bad-target");
    const info = await targetInfo(type, id);
    if (!info) return bad(reply, 404, "not-found");
    if (info.owner === uid) return bad(reply, 400, "own-content");
    await pool.query("INSERT INTO content_reports(id,reporter_id,target_type,target_id,reason) VALUES($1,$2,$3,$4,$5) ON CONFLICT (reporter_id,target_type,target_id) DO UPDATE SET reason=EXCLUDED.reason", [crypto.randomUUID(), uid, type, id, reason]);
    const n = (await pool.query("SELECT count(DISTINCT reporter_id)::int AS n FROM content_reports WHERE target_type=$1 AND target_id=$2", [type, id])).rows[0].n;
    let hidden = false;
    if (n >= threshold() && info.status !== "blocked") hidden = await autoHide(type, id, info, n);
    else if (n === 1) await notifyAdmins({ kind: "report_new", title: `بلاغ على ${type === "post" ? "منشور" : "عرض"}`, body: `«${info.title}»${reason ? ` — ${reason}` : ""}`, data: { targetType: type, targetId: id, reports: n }, push: false });
    return { ok: true, reports: n, hidden, threshold: threshold() };
  });
  // بلاغات عنصر (للإدارة)
  app.get("/safety/reports/:type/:id", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    let admin = false; try { admin = !!(await globalThis.naslifeIsAdmin?.(uid)); } catch { admin = false; }
    if (!admin) return bad(reply, 403, "forbidden");
    const r = await pool.query("SELECT reporter_id, reason, created_at FROM content_reports WHERE target_type=$1 AND target_id=$2 ORDER BY created_at DESC LIMIT 100", [String(req.params.type), str(req.params.id, 64)]);
    return r.rows.map((x) => ({ reporterId: x.reporter_id, reason: x.reason, createdAt: x.created_at }));
  });
}
