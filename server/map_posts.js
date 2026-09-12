// إضافة Fastify لمنشورات الخريطة في Naslife: منشور بصورة أو فيديو قصير أو تسجيل صوتي أو نص، مع طبقات (نصوص وملصقات) تُرسم
// فوق الوسائط عند العرض، وحقول احترافية للمسوّقين والمستثمرين (نوع المنشور، عنوان، سعر، زر إجراء)، ومدة ظهور (يوم/3 أيام/أسبوع)،
// وإعجابات ومشاهدات. الوسائط تُرفع عبر /chat/upload ثم يُمرَّر رابطها هنا.
// المسارات تحت /mapposts (النواة تستخدم /posts لمنشورات الدوائر) والملف map_posts.js (النواة تملك posts.js).
// التسجيل في src/index.js:
//   await app.register((await import("./map_posts.js")).default, { pool, auth });
import crypto from "node:crypto";

const UUID_RE = /^[0-9a-f-]{36}$/i;
const SLUG_RE = /^[a-z0-9-]{3,60}$/;
const HEX_RE = /^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/;
const KINDS = new Set(["text", "image", "video", "audio"]);
const TAGS = new Set(["moment", "offer", "ad", "invest", "event", "job"]);
const CTA_TYPES = new Set(["link", "whatsapp", "call", "biz", "market", "chat"]);
const TTL_HOURS = new Set([24, 72, 168]);
const MAX_OVERLAYS = 30;
const str = (v, max = 200) => String(v ?? "").trim().slice(0, max);
const num = (v) => (v == null || v === "" ? null : Number(v));
const clamp = (v, lo, hi, d) => { const n = Number(v); return Number.isFinite(n) ? Math.min(hi, Math.max(lo, n)) : d; };

/// يتحقق من طبقات المنشور ويعيد نسخة نظيفة: نص أو ملصق بموضع نسبي ومقياس ودوران ولون.
export function cleanOverlays(input) {
  if (!Array.isArray(input)) return [];
  const out = [];
  for (const o of input.slice(0, MAX_OVERLAYS)) {
    if (!o || typeof o !== "object") continue;
    const type = o.type === "sticker" ? "sticker" : o.type === "text" ? "text" : null;
    if (!type) continue;
    const text = str(o.text, type === "sticker" ? 16 : 140);
    if (!text) continue;
    out.push({
      type, text,
      x: clamp(o.x, 0, 1, 0.5), y: clamp(o.y, 0, 1, 0.5), scale: clamp(o.scale, 0.3, 5, 1), rot: clamp(o.rot, -3.2, 3.2, 0),
      color: HEX_RE.test(String(o.color ?? "")) ? String(o.color) : "#FFFFFF",
      bg: HEX_RE.test(String(o.bg ?? "")) ? String(o.bg) : null,
      align: ["start", "center", "end"].includes(o.align) ? o.align : "center",
      font: ["bold", "hand", "serif", "plain"].includes(o.font) ? o.font : "bold",
    });
  }
  return out;
}

/// ينظّف زر الإجراء: رابط، واتساب، اتصال، دائرة تجارية، عرض في السوق، مراسلة.
export function cleanCta(c) {
  if (!c || typeof c !== "object" || !CTA_TYPES.has(c.type)) return null;
  const label = str(c.label, 40);
  let value = str(c.value, 300);
  if (c.type === "link") { if (!/^https?:\/\/[^\s]+$/i.test(value)) return null; }
  else if (c.type === "whatsapp" || c.type === "call") { value = value.replace(/[^\d+]/g, ""); if (value.replace(/\D/g, "").length < 7) return null; }
  else if (c.type === "biz") { if (!SLUG_RE.test(value)) return null; }
  else if (c.type === "market") { if (!UUID_RE.test(value)) return null; }
  else if (c.type === "chat") value = "";
  return { type: c.type, value, label: label || ({ link: "افتح الرابط", whatsapp: "واتساب", call: "اتصال", biz: "زيارة الدائرة", market: "اطلب الآن", chat: "راسلني" })[c.type] };
}

export default async function posts(app, opts) {
  const { pool, auth } = opts;
  if (!pool || !auth) throw new Error("posts: pool and auth are required");

  await pool.query(`
    CREATE TABLE IF NOT EXISTS map_posts (
      id UUID PRIMARY KEY, user_id TEXT NOT NULL, kind TEXT NOT NULL, media_url TEXT, caption TEXT NOT NULL DEFAULT '', bg TEXT,
      overlays JSONB NOT NULL DEFAULT '[]', tag TEXT NOT NULL DEFAULT 'moment', title TEXT NOT NULL DEFAULT '', price BIGINT, cta JSONB,
      lat DOUBLE PRECISION NOT NULL, lng DOUBLE PRECISION NOT NULL, place_name TEXT, duration_sec INT, status TEXT NOT NULL DEFAULT 'active',
      views INT NOT NULL DEFAULT 0, expires_at TIMESTAMPTZ NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE INDEX IF NOT EXISTS map_posts_user ON map_posts(user_id, created_at DESC);
    CREATE INDEX IF NOT EXISTS map_posts_active ON map_posts(expires_at) WHERE status='active';
    CREATE TABLE IF NOT EXISTS map_post_likes (post_id UUID NOT NULL, user_id TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (post_id, user_id));
    CREATE TABLE IF NOT EXISTS map_post_views (post_id UUID NOT NULL, user_id TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (post_id, user_id));
  `);

  const unauthorized = (reply) => reply.code(401).send({ error: "auth" });
  const bad = (reply, code, error, extra = {}) => reply.code(code).send({ error, ...extra });
  const optionalAuth = async (req) => { try { return (await auth(req)) || null; } catch { return null; } };
  const userRow = async (id) => { try { return (await pool.query("SELECT * FROM users WHERE id=$1", [id])).rows[0] ?? null; } catch { return null; } };
  const person = async (id) => { const u = await userRow(id); return u ? { id: u.id, nickname: u.nickname ?? "", avatarUrl: u.avatar_url ?? u.avatarUrl ?? null } : { id, nickname: "", avatarUrl: null }; };
  const isSuspended = async (uid) => { try { return (await pool.query("SELECT 1 FROM user_flags WHERE user_id=$1 AND suspended", [uid])).rowCount > 0; } catch { return false; } };
  const isAdmin = async (uid) => { try { return !!(await globalThis.naslifeIsAdmin?.(uid)); } catch { return false; } };
  const notify = async (ids, payload) => { try { await globalThis.naslifeNotify?.(ids, payload); } catch { /* ignore */ } };
  const absUrl = (req, url) => {
    const s = str(url, 500); if (!s) return null;
    if (/^https?:\/\//i.test(s)) return s;
    if (!s.startsWith("/")) return null;
    const proto = String(req.headers["x-forwarded-proto"] ?? "https").split(",")[0].trim() || "https";
    const host = String(req.headers["x-forwarded-host"] ?? req.headers.host ?? "naslife.app").split(",")[0].trim();
    return `${proto}://${host}${s}`;
  };
  const bbox = (s) => { const p = String(s ?? "").split(",").map(Number); return p.length === 4 && p.every(Number.isFinite) ? { minLng: p[0], minLat: p[1], maxLng: p[2], maxLat: p[3] } : null; };

  const SELECT = `SELECT p.*, (SELECT count(*) FROM map_post_likes l WHERE l.post_id=p.id)::int AS likes,
    ($1::text IS NOT NULL AND EXISTS (SELECT 1 FROM map_post_likes l WHERE l.post_id=p.id AND l.user_id=$1)) AS liked FROM map_posts p`;
  const out = async (p, uid) => ({
    id: p.id, user: await person(p.user_id), kind: p.kind, mediaUrl: p.media_url, caption: p.caption, bg: p.bg, overlays: p.overlays ?? [], tag: p.tag, title: p.title,
    price: p.price == null ? null : Number(p.price), cta: p.cta ?? null, lat: p.lat, lng: p.lng, placeName: p.place_name, durationSec: p.duration_sec, status: p.status,
    views: Number(p.views ?? 0), likes: Number(p.likes ?? 0), liked: p.liked === true, mine: p.user_id === uid, expiresAt: p.expires_at, createdAt: p.created_at,
    expired: new Date(p.expires_at).getTime() < Date.now(),
  });
  const many = async (rows, uid) => { const cache = new Map(); const res = []; for (const r of rows) { if (!cache.has(r.user_id)) cache.set(r.user_id, await person(r.user_id)); res.push({ ...(await out(r, uid)), user: cache.get(r.user_id) }); } return res; };

  // ---- إنشاء
  app.post("/mapposts", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (await isSuspended(uid)) return bad(reply, 403, "suspended");
    const b = req.body ?? {};
    const kind = KINDS.has(b.kind) ? b.kind : null; if (!kind) return bad(reply, 400, "bad-kind");
    const mediaUrl = kind === "text" ? null : absUrl(req, b.mediaUrl);
    if (kind !== "text" && !mediaUrl) return bad(reply, 400, "bad-media");
    const lat = num(b.lat), lng = num(b.lng);
    if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) return bad(reply, 400, "bad-location");
    const caption = str(b.caption, 500);
    const overlays = cleanOverlays(b.overlays);
    if (kind === "text" && !caption && !overlays.some((o) => o.type === "text")) return bad(reply, 400, "empty");
    const ttl = TTL_HOURS.has(Number(b.ttlHours)) ? Number(b.ttlHours) : 24;
    const price = b.price == null || b.price === "" ? null : Math.max(0, Math.round(Number(b.price) || 0));
    const id = crypto.randomUUID();
    await pool.query(`INSERT INTO map_posts(id,user_id,kind,media_url,caption,bg,overlays,tag,title,price,cta,lat,lng,place_name,duration_sec,expires_at)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15, now() + ($16 || ' hours')::interval)`,
      [id, uid, kind, mediaUrl, caption, HEX_RE.test(String(b.bg ?? "")) ? String(b.bg) : null, JSON.stringify(overlays), TAGS.has(b.tag) ? b.tag : "moment", str(b.title, 80), price,
       JSON.stringify(cleanCta(b.cta)), lat, lng, str(b.placeName, 80) || null, b.durationSec == null ? null : Math.round(clamp(b.durationSec, 0, 600, 0)), String(ttl)]);
    return out((await pool.query(`${SELECT} WHERE p.id=$2`, [uid, id])).rows[0], uid);
  });

  // ---- القوائم: على الخريطة (حدود)، الأحدث للرئيسية، منشوراتي
  app.get("/mapposts", async (req) => {
    const uid = await optionalAuth(req);
    const bb = bbox(req.query?.bbox);
    const limit = Math.max(1, Math.min(300, Number(req.query?.limit) || 200));
    const tag = TAGS.has(req.query?.tag) ? req.query.tag : null;
    const rows = (await pool.query(`${SELECT} WHERE p.status='active' AND p.expires_at > now()
      AND ($2::float8 IS NULL OR (p.lat BETWEEN $3 AND $5 AND p.lng BETWEEN $2 AND $4)) AND ($6::text IS NULL OR p.tag=$6)
      ORDER BY p.created_at DESC LIMIT $7`, [uid, bb?.minLng ?? null, bb?.minLat ?? null, bb?.maxLng ?? null, bb?.maxLat ?? null, tag, limit])).rows;
    return many(rows, uid);
  });
  app.get("/mapposts/mine", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const rows = (await pool.query(`${SELECT} WHERE p.user_id=$1 AND p.created_at > now() - interval '30 days' ORDER BY p.created_at DESC LIMIT 200`, [uid])).rows;
    return many(rows, uid);
  });
  app.get("/mapposts/:id", async (req, reply) => {
    const uid = await optionalAuth(req);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const p = (await pool.query(`${SELECT} WHERE p.id=$2`, [uid, req.params.id])).rows[0];
    if (!p) return bad(reply, 404, "not-found");
    if (p.status !== "active" && p.user_id !== uid && !(await isAdmin(uid))) return bad(reply, 404, "not-found");
    return out(p, uid);
  });

  // ---- تعديل (صاحب المنشور): النص والطبقات والحقول الاحترافية والإظهار/الإخفاء وتمديد المدة
  app.patch("/mapposts/:id", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const p = (await pool.query("SELECT * FROM map_posts WHERE id=$1", [req.params.id])).rows[0];
    if (!p) return bad(reply, 404, "not-found");
    if (p.user_id !== uid) return bad(reply, 403, "forbidden");
    const b = req.body ?? {}; const sets = []; const vals = [];
    const set = (c, v) => { vals.push(v); sets.push(`${c}=$${vals.length}`); };
    if (b.caption !== undefined) set("caption", str(b.caption, 500));
    if (b.overlays !== undefined) set("overlays", JSON.stringify(cleanOverlays(b.overlays)));
    if (b.bg !== undefined) set("bg", HEX_RE.test(String(b.bg ?? "")) ? String(b.bg) : null);
    if (b.tag !== undefined) set("tag", TAGS.has(b.tag) ? b.tag : "moment");
    if (b.title !== undefined) set("title", str(b.title, 80));
    if (b.price !== undefined) set("price", b.price == null || b.price === "" ? null : Math.max(0, Math.round(Number(b.price) || 0)));
    if (b.cta !== undefined) set("cta", JSON.stringify(cleanCta(b.cta)));
    if (b.placeName !== undefined) set("place_name", str(b.placeName, 80) || null);
    if (b.mediaUrl !== undefined && p.kind !== "text") { const u = absUrl(req, b.mediaUrl); if (!u) return bad(reply, 400, "bad-media"); set("media_url", u); }
    if (b.status !== undefined) { if (!["active", "hidden"].includes(b.status)) return bad(reply, 400, "bad-status"); if (p.status === "blocked") return bad(reply, 403, "blocked"); set("status", b.status); }
    if (b.ttlHours !== undefined) { if (!TTL_HOURS.has(Number(b.ttlHours))) return bad(reply, 400, "bad-ttl"); vals.push(String(Number(b.ttlHours))); sets.push(`expires_at=now() + ($${vals.length} || ' hours')::interval`); }
    if (!sets.length) return bad(reply, 400, "empty");
    sets.push("updated_at=now()");
    vals.push(p.id);
    await pool.query(`UPDATE map_posts SET ${sets.join(", ")} WHERE id=$${vals.length}`, vals);
    return out((await pool.query(`${SELECT} WHERE p.id=$2`, [uid, p.id])).rows[0], uid);
  });
  app.delete("/mapposts/:id", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const p = (await pool.query("SELECT user_id FROM map_posts WHERE id=$1", [req.params.id])).rows[0];
    if (!p) return bad(reply, 404, "not-found");
    if (p.user_id !== uid && !(await isAdmin(uid))) return bad(reply, 403, "forbidden");
    await pool.query("DELETE FROM map_post_likes WHERE post_id=$1", [req.params.id]);
    await pool.query("DELETE FROM map_post_views WHERE post_id=$1", [req.params.id]);
    await pool.query("DELETE FROM map_posts WHERE id=$1", [req.params.id]);
    return { ok: true };
  });

  // ---- مشاهدة (مرة لكل مستخدم) وإعجاب (تبديل) وحجب إداري
  app.post("/mapposts/:id/view", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const r = await pool.query("INSERT INTO map_post_views(post_id,user_id) VALUES($1,$2) ON CONFLICT DO NOTHING RETURNING 1", [req.params.id, uid]);
    if (r.rowCount) await pool.query("UPDATE map_posts SET views=views+1 WHERE id=$1 AND user_id<>$2", [req.params.id, uid]);
    const v = (await pool.query("SELECT views FROM map_posts WHERE id=$1", [req.params.id])).rows[0];
    return { ok: true, views: Number(v?.views ?? 0) };
  });
  app.post("/mapposts/:id/like", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const p = (await pool.query("SELECT user_id, caption, title FROM map_posts WHERE id=$1 AND status='active'", [req.params.id])).rows[0];
    if (!p) return bad(reply, 404, "not-found");
    const del = await pool.query("DELETE FROM map_post_likes WHERE post_id=$1 AND user_id=$2 RETURNING 1", [req.params.id, uid]);
    let liked = false;
    if (!del.rowCount) {
      await pool.query("INSERT INTO map_post_likes(post_id,user_id) VALUES($1,$2) ON CONFLICT DO NOTHING", [req.params.id, uid]);
      liked = true;
      if (p.user_id !== uid) await notify(p.user_id, { kind: "post_like", title: "إعجاب بمنشورك", body: `${(await person(uid)).nickname || uid} أعجب بمنشورك${p.title ? " «" + p.title + "»" : ""}`, data: { postId: req.params.id } });
    }
    const n = (await pool.query("SELECT count(*)::int AS n FROM map_post_likes WHERE post_id=$1", [req.params.id])).rows[0].n;
    return { ok: true, liked, likes: n };
  });
  app.post("/mapposts/:id/block", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!(await isAdmin(uid))) return bad(reply, 403, "admin-only");
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const hidden = req.body?.hidden !== false;
    const r = await pool.query("UPDATE map_posts SET status=$2, updated_at=now() WHERE id=$1 RETURNING user_id, title", [req.params.id, hidden ? "blocked" : "active"]);
    if (!r.rowCount) return bad(reply, 404, "not-found");
    if (hidden) await notify(r.rows[0].user_id, { kind: "post_blocked", title: "أُخفي منشورك", body: "أخفت الإدارة منشورك من الخريطة لمخالفته قواعد المجتمع", data: { postId: req.params.id }, exclude: uid });
    return { ok: true, status: hidden ? "blocked" : "active" };
  });

  // تنظيف دوري: حذف ما انتهت مدته منذ أكثر من 30 يوماً
  const sweep = () => pool.query("DELETE FROM map_posts WHERE expires_at < now() - interval '30 days'").catch(() => {});
  const timer = setInterval(sweep, 6 * 3600 * 1000); timer.unref?.();
  app.addHook("onClose", async () => clearInterval(timer));
}
