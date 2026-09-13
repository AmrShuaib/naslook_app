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
  // سجل أحداث المنشورات للإحصاءات: مشاهدة (كل فتح)، ضغطة زر الإجراء، مراسلة الناشر، إعجاب
  await pool.query(`
    CREATE TABLE IF NOT EXISTS map_post_events (
      id BIGSERIAL PRIMARY KEY, post_id UUID NOT NULL, user_id TEXT, kind TEXT NOT NULL, at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE INDEX IF NOT EXISTS map_post_events_post_at ON map_post_events(post_id, at DESC);
  `);
  const EVENT_KINDS = new Set(["view", "cta", "contact", "like"]);
  const logEvent = async (postId, uid, kind) => { try { await pool.query("INSERT INTO map_post_events(post_id,user_id,kind) VALUES($1,$2,$3)", [postId, uid, kind]); } catch { /* ignore */ } };
  // روابط حُفظت سابقاً بمضيف www. تُعاد إلى المضيف الأساسي (انظر publicOrigin)
  try { await pool.query(String.raw`UPDATE map_posts SET media_url = regexp_replace(media_url, '^(https?://)www\.', '\1', 'i') WHERE media_url ~* '^https?://www\.'`); } catch { /* ignore */ }

  const unauthorized = (reply) => reply.code(401).send({ error: "auth" });
  const bad = (reply, code, error, extra = {}) => reply.code(code).send({ error, ...extra });
  const optionalAuth = async (req) => { try { return (await auth(req)) || null; } catch { return null; } };
  const userRow = async (id) => { try { return (await pool.query("SELECT * FROM users WHERE id=$1", [id])).rows[0] ?? null; } catch { return null; } };
  const person = async (id) => { const u = await userRow(id); return u ? { id: u.id, nickname: u.nickname ?? "", avatarUrl: u.avatar_url ?? u.avatarUrl ?? null } : { id, nickname: "", avatarUrl: null }; };
  const isSuspended = async (uid) => { try { return (await pool.query("SELECT 1 FROM user_flags WHERE user_id=$1 AND suspended", [uid])).rowCount > 0; } catch { return false; } };
  const isAdmin = async (uid) => { try { return !!(await globalThis.naslifeIsAdmin?.(uid)); } catch { return false; } };
  const notify = async (ids, payload) => { try { await globalThis.naslifeNotify?.(ids, payload); } catch { /* ignore */ } };
  // الأصل العام للروابط المطلقة: PUBLIC_BASE_URL إن ضُبط، وإلا مضيف الطلب بلا "www." — الموقع يُقدَّم على naslife.app
  // وwww.naslife.app معاً، وسياسة CSP تقبل الوسائط من الأصل ذاته فقط، فرابط بمضيف يخالف صفحة المستخدم لا يُعرض.
  const publicOrigin = (req) => {
    const env = String(process.env.PUBLIC_BASE_URL ?? process.env.NASLIFE_PUBLIC_URL ?? "").trim().replace(/\/+$/, "");
    if (/^https?:\/\//i.test(env)) return env;
    const proto = String(req.headers["x-forwarded-proto"] ?? "https").split(",")[0].trim() || "https";
    const host = String(req.headers["x-forwarded-host"] ?? req.headers.host ?? "naslife.app").split(",")[0].trim().replace(/^www\./i, "");
    return `${proto}://${host}`;
  };
  const OWN_MEDIA = /^https?:\/\/[^/]+(\/(?:chat\/media|files|media|uploads)\/.*)$/i;
  const absUrl = (req, url) => {
    const s = str(url, 500); if (!s) return null;
    const own = OWN_MEDIA.exec(s); if (own) return `${publicOrigin(req)}${own[1]}`;
    if (/^https?:\/\//i.test(s)) return s;
    if (!s.startsWith("/")) return null;
    return `${publicOrigin(req)}${s}`;
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
    const banned = globalThis.naslifeCheckText?.(caption, str(b.title, 80), str(b.placeName, 80), ...overlays.filter((o) => o.type === "text").map((o) => o.text));
    if (banned) return reply.code(400).send({ error: "banned-words", word: banned });
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
    // من حظرهم المستخدم أو حظروه لا يظهر محتواهم له
    const blocked = uid ? await (globalThis.naslifeBlockedIds?.(uid) ?? []) : [];
    const rows = (await pool.query(`${SELECT} WHERE p.status='active' AND p.expires_at > now()
      AND ($2::float8 IS NULL OR (p.lat BETWEEN $3 AND $5 AND p.lng BETWEEN $2 AND $4)) AND ($6::text IS NULL OR p.tag=$6)
      AND NOT (p.user_id = ANY($8::text[]))
      ORDER BY p.created_at DESC LIMIT $7`, [uid, bb?.minLng ?? null, bb?.minLat ?? null, bb?.maxLng ?? null, bb?.maxLat ?? null, tag, limit, blocked])).rows;
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
    const bannedP = globalThis.naslifeCheckText?.(b.caption, b.title, b.placeName, ...(Array.isArray(b.overlays) ? b.overlays.map((o) => o?.text) : []));
    if (bannedP) return reply.code(400).send({ error: "banned-words", word: bannedP });
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
    const own = (await pool.query("SELECT 1 FROM map_posts WHERE id=$1 AND user_id=$2", [req.params.id, uid])).rowCount > 0;
    if (!own) await logEvent(req.params.id, uid, "view");
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
      if (p.user_id !== uid) await logEvent(req.params.id, uid, "like");
      if (p.user_id !== uid) await notify(p.user_id, { kind: "post_like", title: "إعجاب بمنشورك", body: `${(await person(uid)).nickname || uid} أعجب بمنشورك${p.title ? " «" + p.title + "»" : ""}`, data: { postId: req.params.id } });
    }
    const n = (await pool.query("SELECT count(*)::int AS n FROM map_post_likes WHERE post_id=$1", [req.params.id])).rows[0].n;
    return { ok: true, liked, likes: n };
  });
  // ---- تتبّع زر الإجراء والمراسلة (للإحصاءات)
  for (const kind of ["cta", "contact"]) {
    app.post(`/mapposts/:id/${kind}`, async (req, reply) => {
      const uid = await auth(req); if (!uid) return unauthorized(reply);
      if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
      const p = (await pool.query("SELECT user_id FROM map_posts WHERE id=$1", [req.params.id])).rows[0];
      if (!p) return bad(reply, 404, "not-found");
      if (p.user_id !== uid) await logEvent(req.params.id, uid, kind);
      return { ok: true };
    });
  }

  // ---- الإحصاءات: لكل منشور (المالك أو الإدارة)، ولكل منشوراتي، ولمنشورات دائرة تجارية (مالكها أو طاقمها أو الإدارة)
  const daysOf = (v) => Math.max(1, Math.min(90, Math.round(Number(v)) || 7));
  const emptyTotals = () => ({ views: 0, cta: 0, contacts: 0, likes: 0 });
  const fieldOf = (kind) => ({ view: "views", like: "likes", contact: "contacts", cta: "cta" })[kind] ?? null;
  async function series(postIds, days) {
    if (!postIds.length) return { totals: emptyTotals(), uniqueViews: 0, hourly: [], daily: [] };
    const t = (await pool.query(`SELECT kind, count(*)::int AS n FROM map_post_events WHERE post_id = ANY($1::uuid[]) AND at > now() - ($2 || ' days')::interval GROUP BY kind`, [postIds, String(days)])).rows;
    const totals = emptyTotals(); for (const r of t) { const f = fieldOf(r.kind); if (f) totals[f] = r.n; }
    const uniq = (await pool.query("SELECT count(*)::int AS n FROM map_post_views v JOIN map_posts p ON p.id=v.post_id WHERE v.post_id = ANY($1::uuid[]) AND v.user_id <> p.user_id", [postIds])).rows[0].n;
    const h = (await pool.query(`SELECT date_trunc('hour', at) AS h, kind, count(*)::int AS n FROM map_post_events WHERE post_id = ANY($1::uuid[]) AND at > now() - interval '24 hours' GROUP BY 1, 2`, [postIds])).rows;
    const hourly = []; const nowH = new Date(); nowH.setMinutes(0, 0, 0);
    for (let i = 23; i >= 0; i--) { const at = new Date(nowH.getTime() - i * 3600e3); hourly.push({ at: at.toISOString(), views: 0, cta: 0, contacts: 0, likes: 0 }); }
    for (const r of h) { const slot = hourly.find((x) => x.at === new Date(r.h).toISOString()); const f = fieldOf(r.kind); if (slot && f) slot[f] = r.n; }
    const d = (await pool.query(`SELECT (at AT TIME ZONE 'Asia/Riyadh')::date AS d, kind, count(*)::int AS n FROM map_post_events WHERE post_id = ANY($1::uuid[]) AND at > now() - ($2 || ' days')::interval GROUP BY 1, 2`, [postIds, String(days)])).rows;
    const daily = []; const today = new Date(Date.now() + 3 * 3600e3);
    for (let i = days - 1; i >= 0; i--) { const dd = new Date(today.getTime() - i * 86400e3); daily.push({ date: dd.toISOString().slice(0, 10), views: 0, cta: 0, contacts: 0, likes: 0 }); }
    for (const r of d) { const key = r.d instanceof Date ? new Date(r.d.getTime() - r.d.getTimezoneOffset() * 60000).toISOString().slice(0, 10) : String(r.d).slice(0, 10); const slot = daily.find((x) => x.date === key); const f = fieldOf(r.kind); if (slot && f) slot[f] = r.n; }
    return { totals, uniqueViews: uniq, hourly, daily };
  }
  const postBrief = (p) => ({ id: p.id, title: p.title || p.caption || (p.kind === "text" ? "منشور نصي" : "منشور"), kind: p.kind, tag: p.tag, status: p.status, createdAt: p.created_at, expiresAt: p.expires_at });
  async function perPost(postIds, days) {
    if (!postIds.length) return new Map();
    const rows = (await pool.query(`SELECT post_id, kind, count(*)::int AS n FROM map_post_events WHERE post_id = ANY($1::uuid[]) AND at > now() - ($2 || ' days')::interval GROUP BY 1, 2`, [postIds, String(days)])).rows;
    const m = new Map(); for (const id of postIds) m.set(id, emptyTotals());
    for (const r of rows) { const t = m.get(r.post_id); const f = fieldOf(r.kind); if (t && f) t[f] = r.n; }
    return m;
  }
  app.get("/mapposts/stats/mine", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const days = daysOf(req.query?.days);
    const posts = (await pool.query("SELECT * FROM map_posts WHERE user_id=$1 AND created_at > now() - interval '90 days' ORDER BY created_at DESC LIMIT 200", [uid])).rows;
    const ids = posts.map((p) => p.id);
    const agg = await series(ids, days); const per = await perPost(ids, days);
    return { days, posts: posts.length, ...agg, byPost: posts.map((p) => ({ ...postBrief(p), ...per.get(p.id) })) };
  });
  app.get("/mapposts/stats/biz/:slug", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const slug = str(req.params.slug, 64); const days = daysOf(req.query?.days);
    let allowed = await isAdmin(uid);
    if (!allowed) {
      try {
        const b = (await pool.query("SELECT owner_id FROM biz WHERE id=$1", [slug])).rows[0];
        allowed = !!b && (b.owner_id === uid || (await pool.query("SELECT 1 FROM biz_staff WHERE biz_id=$1 AND user_id=$2", [slug, uid])).rowCount > 0);
      } catch { allowed = false; }
    }
    if (!allowed) return bad(reply, 403, "forbidden");
    const posts = (await pool.query("SELECT * FROM map_posts WHERE cta->>'type'='biz' AND cta->>'value'=$1 AND created_at > now() - interval '90 days' ORDER BY created_at DESC LIMIT 200", [slug])).rows;
    const ids = posts.map((p) => p.id);
    const agg = await series(ids, days); const per = await perPost(ids, days);
    return { days, posts: posts.length, ...agg, byPost: posts.map((p) => ({ ...postBrief(p), author: p.user_id, ...per.get(p.id) })) };
  });
  app.get("/mapposts/:id/stats", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const p = (await pool.query("SELECT * FROM map_posts WHERE id=$1", [req.params.id])).rows[0];
    if (!p) return bad(reply, 404, "not-found");
    if (p.user_id !== uid && !(await isAdmin(uid))) return bad(reply, 403, "forbidden");
    const days = daysOf(req.query?.days);
    const agg = await series([p.id], days);
    const likes = (await pool.query("SELECT count(*)::int AS n FROM map_post_likes WHERE post_id=$1", [p.id])).rows[0].n;
    return { days, post: postBrief(p), ...agg, likesTotal: likes, viewsTotal: Number(p.views ?? 0) };
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
