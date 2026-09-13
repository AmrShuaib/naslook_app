// البحث المحفوظ مع تنبيه في Naslife: يحفظ المستخدم كلمة بحث (مع نطاق مسافة اختياري ونوع محتوى اختياري)، ويفحص الخادم
// دورياً ما نُشر منذ آخر فحص في منشورات الخريطة وعروض السوق والفعاليات والأنشطة وكتالوجها، ويرسل إشعاراً واحداً
// لكل بحث في كل فحص بعدد المطابقات وأول عناوينها. التطبيع العربي نفسه المستخدم في البحث.
// التسجيل في src/index.js بعد business.js:
//   await app.register((await import("./saved_search.js")).default, { pool, auth });
import crypto from "node:crypto";
import { NORM, likeOf, normQ, DIST } from "./business.js";

const UUID_RE = /^[0-9a-f-]{36}$/i;
const TYPES = ["posts", "market", "events", "biz", "items"];
const str = (v, max) => String(v ?? "").trim().slice(0, max);
const num = (v) => (v == null || v === "" ? null : Number(v));

export default async function savedSearch(app, opts) {
  const { pool, auth } = opts;
  if (!pool || !auth) throw new Error("saved_search: pool and auth are required");
  await pool.query(`
    CREATE TABLE IF NOT EXISTS saved_searches (
      id UUID PRIMARY KEY, user_id TEXT NOT NULL, q TEXT NOT NULL, norm_q TEXT NOT NULL, types TEXT[],
      lat DOUBLE PRECISION, lng DOUBLE PRECISION, radius_km INT, active BOOLEAN NOT NULL DEFAULT true,
      last_checked_at TIMESTAMPTZ NOT NULL DEFAULT now(), last_match_at TIMESTAMPTZ, matches INT NOT NULL DEFAULT 0,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE UNIQUE INDEX IF NOT EXISTS saved_searches_uq ON saved_searches(user_id, norm_q);
  `);
  const cols = (await pool.query("SELECT table_name, column_name FROM information_schema.columns WHERE table_schema='public'")).rows;
  const tables = new Map();
  for (const c of cols) { if (!tables.has(c.table_name)) tables.set(c.table_name, new Set()); tables.get(c.table_name).add(c.column_name); }
  const has = (t, ...cs) => tables.has(t) && cs.every((c) => tables.get(t).has(c));
  const sources = {
    posts: has("map_posts", "created_at", "status", "expires_at", "lat", "lng"),
    market: has("market_listings", "created_at", "status"),
    events: has("events", "created_at", "starts_at", "cancelled"),
    biz: has("biz", "created_at", "name"),
    items: has("biz_items", "created_at", "title") && has("biz", "lat", "lng"),
  };
  const notify = async (ids, payload) => { try { await globalThis.naslifeNotify?.(ids, payload); } catch { /* ignore */ } };
  const unauthorized = (reply) => reply.code(401).send({ error: "auth" });
  const bad = (reply, code, error, extra = {}) => reply.code(code).send({ error, ...extra });
  const out = (r) => ({ id: r.id, q: r.q, types: r.types ?? null, lat: r.lat, lng: r.lng, radiusKm: r.radius_km, active: r.active, matches: Number(r.matches ?? 0), lastMatchAt: r.last_match_at, lastCheckedAt: r.last_checked_at, createdAt: r.created_at });

  // ---- المطابقة: ما نُشر بعد since ويطابق الكلمة، ضمن النطاق إن حُدد، وليس من المستخدم نفسه
  const within = (latCol, lngCol) => `($4::float8 IS NULL OR $6::float8 IS NULL OR (${latCol} IS NOT NULL AND ${DIST("$4", "$5", latCol, lngCol)} <= $6::float8))`;
  async function matchesFor(s, since) {
    const like = likeOf(s.q);
    const params = [since, s.user_id, like, s.lat, s.lng, s.radius_km];
    const want = (t) => !s.types || !s.types.length || s.types.includes(t);
    const found = [];
    const run = async (type, sql) => {
      try { for (const r of (await pool.query(sql, params)).rows) found.push({ type, id: r.id, title: r.title, createdAt: r.created_at }); }
      catch (e) { app.log?.warn?.({ err: e?.message }, `saved_search: ${type} query failed`); }
    };
    if (sources.posts && want("posts")) await run("post", `SELECT id, COALESCE(NULLIF(title,''), NULLIF(caption,''), 'منشور') AS title, created_at FROM map_posts
      WHERE status='active' AND expires_at > now() AND created_at > $1::timestamptz AND user_id <> $2
      AND (${NORM("title")} LIKE $3 OR ${NORM("caption")} LIKE $3 OR ${NORM("COALESCE(place_name,'')")} LIKE $3) AND ${within("lat", "lng")} ORDER BY created_at DESC LIMIT 20`);
    if (sources.market && want("market")) await run("listing", `SELECT id, title, created_at FROM market_listings
      WHERE status='active' AND created_at > $1::timestamptz AND seller_id <> $2
      AND (${NORM("title")} LIKE $3 OR ${NORM("description")} LIKE $3 OR ${NORM("COALESCE(place_name,'')")} LIKE $3) AND ${within("lat", "lng")} ORDER BY created_at DESC LIMIT 20`);
    if (sources.events && want("events")) await run("event", `SELECT id, title, created_at FROM events
      WHERE cancelled=false AND starts_at > now() AND created_at > $1::timestamptz AND host_id <> $2
      AND (${NORM("title")} LIKE $3 OR ${NORM("COALESCE(description,'')")} LIKE $3 OR ${NORM("COALESCE(place_name,'')")} LIKE $3) AND ${within("lat", "lng")} ORDER BY created_at DESC LIMIT 20`);
    if (sources.biz && want("biz")) await run("biz", `SELECT id, COALESCE(NULLIF(name_ar,''), name) AS title, created_at FROM biz
      WHERE active <> false AND created_at > $1::timestamptz AND COALESCE(owner_id,'') <> $2
      AND (${NORM("name")} LIKE $3 OR ${NORM("COALESCE(name_ar,'')")} LIKE $3 OR ${NORM("COALESCE(description,'')")} LIKE $3 OR ${NORM("category")} LIKE $3) AND ${within("lat", "lng")} ORDER BY created_at DESC LIMIT 20`);
    if (sources.items && want("items")) await run("item", `SELECT i.id, i.title, i.created_at FROM biz_items i JOIN biz b ON b.id=i.biz_id
      WHERE i.active <> false AND i.created_at > $1::timestamptz AND COALESCE(b.owner_id,'') <> $2
      AND (${NORM("i.title")} LIKE $3 OR ${NORM("COALESCE(i.description,'')")} LIKE $3) AND ${within("b.lat", "b.lng")} ORDER BY i.created_at DESC LIMIT 20`);
    found.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
    return found;
  }
  async function check(s, { notifyUser = true } = {}) {
    const found = await matchesFor(s, s.last_checked_at);
    const now = new Date();
    if (found.length) {
      await pool.query("UPDATE saved_searches SET last_checked_at=$2, last_match_at=$2, matches=matches+$3 WHERE id=$1", [s.id, now, found.length]);
      if (notifyUser) {
        const titles = found.slice(0, 3).map((f) => `«${f.title}»`).join(" · ");
        await notify([s.user_id], { kind: "saved_search_match", title: found.length === 1 ? `جديد يطابق بحثك «${s.q}»` : `${found.length} جديد يطابق بحثك «${s.q}»`, body: titles, data: { searchId: s.id, q: s.q, count: found.length, first: found[0] } });
      }
    } else {
      await pool.query("UPDATE saved_searches SET last_checked_at=$2 WHERE id=$1", [s.id, now]);
    }
    return found;
  }
  let sweeping = false;
  async function sweep() {
    if (sweeping) return { skipped: true };
    sweeping = true;
    const stats = { searches: 0, notified: 0, found: 0 };
    try {
      const rows = (await pool.query("SELECT * FROM saved_searches WHERE active=true ORDER BY last_checked_at ASC LIMIT 2000")).rows;
      for (const s of rows) {
        stats.searches++;
        try { const f = await check(s); if (f.length) { stats.notified++; stats.found += f.length; } } catch { /* بحث واحد لا يوقف الباقي */ }
      }
    } finally { sweeping = false; }
    return stats;
  }
  globalThis.naslifeSavedSearchSweep = sweep;
  const SWEEP_MS = opts.sweepMs ?? (Number(process.env.SAVED_SEARCH_SWEEP_MS) || 10 * 60 * 1000);
  let timer = null;
  if (SWEEP_MS > 0) { timer = setInterval(() => sweep().catch(() => {}), SWEEP_MS); timer.unref?.(); app.addHook("onClose", async () => { if (timer) clearInterval(timer); }); }

  // ---- المسارات
  app.get("/searches/saved/status", async () => ({ ok: true, sources, sweepEveryMs: SWEEP_MS }));
  app.get("/searches/saved", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    return (await pool.query("SELECT * FROM saved_searches WHERE user_id=$1 ORDER BY created_at DESC", [uid])).rows.map(out);
  });
  app.post("/searches/saved", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const b = req.body ?? {};
    const q = str(b.q, 80); const nq = normQ(q);
    if (nq.length < 2) return bad(reply, 400, "bad-query");
    const types = Array.isArray(b.types) ? [...new Set(b.types.map(String).filter((t) => TYPES.includes(t)))] : null;
    let lat = num(b.lat), lng = num(b.lng), radius = b.radiusKm == null ? null : Math.max(1, Math.min(500, Math.round(Number(b.radiusKm)) || 0));
    if (radius && (!Number.isFinite(lat) || !Number.isFinite(lng))) return bad(reply, 400, "location-required");
    if (!radius) { lat = null; lng = null; radius = null; }
    const n = (await pool.query("SELECT count(*)::int AS n FROM saved_searches WHERE user_id=$1", [uid])).rows[0].n;
    const exists = (await pool.query("SELECT id FROM saved_searches WHERE user_id=$1 AND norm_q=$2", [uid, nq])).rows[0];
    if (!exists && n >= 20) return bad(reply, 400, "too-many");
    const r = await pool.query(`INSERT INTO saved_searches(id,user_id,q,norm_q,types,lat,lng,radius_km) VALUES($1,$2,$3,$4,$5,$6,$7,$8)
      ON CONFLICT (user_id,norm_q) DO UPDATE SET q=EXCLUDED.q, types=EXCLUDED.types, lat=EXCLUDED.lat, lng=EXCLUDED.lng, radius_km=EXCLUDED.radius_km, active=true RETURNING *`,
      [crypto.randomUUID(), uid, q, nq, types && types.length ? types : null, lat, lng, radius]);
    return { ...out(r.rows[0]), existed: !!exists };
  });
  app.patch("/searches/saved/:id", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const id = String(req.params.id); if (!UUID_RE.test(id)) return bad(reply, 404, "not-found");
    const b = req.body ?? {}; const sets = [], vals = []; const set = (c, v) => { vals.push(v); sets.push(`${c}=$${vals.length}`); };
    if (typeof b.active === "boolean") { set("active", b.active); if (b.active) set("last_checked_at", new Date()); }
    if (b.radiusKm !== undefined) {
      const radius = b.radiusKm == null ? null : Math.max(1, Math.min(500, Math.round(Number(b.radiusKm)) || 0));
      set("radius_km", radius);
      if (b.lat !== undefined) set("lat", num(b.lat)); if (b.lng !== undefined) set("lng", num(b.lng));
    }
    if (!sets.length) return bad(reply, 400, "nothing");
    vals.push(id, uid);
    const r = await pool.query(`UPDATE saved_searches SET ${sets.join(",")} WHERE id=$${vals.length - 1} AND user_id=$${vals.length} RETURNING *`, vals);
    if (!r.rowCount) return bad(reply, 404, "not-found");
    return out(r.rows[0]);
  });
  app.delete("/searches/saved/:id", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const id = String(req.params.id); if (!UUID_RE.test(id)) return bad(reply, 404, "not-found");
    const r = await pool.query("DELETE FROM saved_searches WHERE id=$1 AND user_id=$2", [id, uid]);
    if (!r.rowCount) return bad(reply, 404, "not-found");
    return { ok: true };
  });
  // فحص يدوي: ما يطابق البحث في آخر 7 أيام (بلا إشعار ولا تحديث لآخر فحص)
  app.post("/searches/saved/:id/run", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const id = String(req.params.id); if (!UUID_RE.test(id)) return bad(reply, 404, "not-found");
    const s = (await pool.query("SELECT * FROM saved_searches WHERE id=$1 AND user_id=$2", [id, uid])).rows[0];
    if (!s) return bad(reply, 404, "not-found");
    const found = await matchesFor(s, new Date(Date.now() - 7 * 86400e3));
    return { count: found.length, items: found.slice(0, 20) };
  });
}
