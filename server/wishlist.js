// قائمة الأمنيات في Naslife: يحفظ المستخدم ما يتمناه من منتجات السوق وخدمات الدوائر التجارية والفعاليات ومنشورات الخريطة،
// أو أمنية حرة يكتبها بنفسه. عند الحفظ تُؤخذ بيانات العنصر (العنوان والسعر والصورة) من مصدرها في الخادم حتى لا تُزوَّر،
// وتُحدَّث عند كل قراءة إن كان المصدر ما يزال موجوداً.
// التسجيل في src/index.js قبل app.listen:
//   await app.register((await import("./wishlist.js")).default, { pool, auth });
import crypto from "node:crypto";

const KINDS = new Set(["market", "item", "event", "biz", "post", "custom"]);
const UUID_RE = /^[0-9a-f-]{36}$/i;
const str = (v, max) => { const s = String(v ?? "").trim(); return s ? s.slice(0, max) : ""; };

export default async function wishlist(app, opts) {
  const { pool, auth } = opts;
  if (!pool || !auth) throw new Error("wishlist: pool and auth are required");
  await pool.query(`
    CREATE TABLE IF NOT EXISTS wishlist_items (
      id UUID PRIMARY KEY,
      user_id TEXT NOT NULL,
      kind TEXT NOT NULL,
      ref_id TEXT,
      title TEXT NOT NULL,
      subtitle TEXT NOT NULL DEFAULT '',
      price BIGINT,
      image_url TEXT,
      note TEXT NOT NULL DEFAULT '',
      done BOOLEAN NOT NULL DEFAULT false,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE UNIQUE INDEX IF NOT EXISTS wishlist_items_ref ON wishlist_items(user_id, kind, ref_id) WHERE ref_id IS NOT NULL;
    CREATE INDEX IF NOT EXISTS wishlist_items_user ON wishlist_items(user_id, created_at DESC);
    ALTER TABLE wishlist_items ADD COLUMN IF NOT EXISTS last_available BOOLEAN NOT NULL DEFAULT true;
    ALTER TABLE wishlist_items ADD COLUMN IF NOT EXISTS reminded_at TIMESTAMPTZ;
    ALTER TABLE wishlist_items ADD COLUMN IF NOT EXISTS alerted_at TIMESTAMPTZ;
  `);
  const notify = async (ids, payload) => { try { await globalThis.naslifeNotify?.(ids, payload); } catch { /* ignore */ } };
  const SAR = (h) => (h % 100 === 0 ? String(h / 100) : (h / 100).toFixed(2)) + " ر.س";
  const unauthorized = (reply) => reply.code(401).send({ error: "auth" });
  const bad = (reply, code, error) => reply.code(code).send({ error });
  const tableExists = async (name) => (await pool.query("SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name=$1", [name])).rowCount > 0;
  const tables = { market: await tableExists("market_listings"), item: await tableExists("biz_items"), event: await tableExists("events"), biz: await tableExists("biz"), post: await tableExists("map_posts") };

  // بيانات العنصر من مصدره؛ null إن لم يعد موجوداً
  async function resolve(kind, refId) {
    try {
      switch (kind) {
        case "market": {
          if (!tables.market || !UUID_RE.test(refId)) return null;
          const r = await pool.query("SELECT title, price, image_url, status, kind FROM market_listings WHERE id=$1", [refId]);
          const l = r.rows[0]; if (!l) return null;
          return { title: l.title, subtitle: l.kind === "service" ? "خدمة في السوق" : "منتج في السوق", price: Number(l.price), imageUrl: l.image_url, available: l.status === "active" };
        }
        case "item": {
          if (!tables.item) return null;
          const r = await pool.query("SELECT i.title, i.price, i.image_url, i.active, i.biz_id, b.name_ar, b.name FROM biz_items i LEFT JOIN biz b ON b.id=i.biz_id WHERE i.id=$1", [refId]);
          const it = r.rows[0]; if (!it) return null;
          return { title: it.title, subtitle: it.name_ar || it.name || "دائرة تجارية", price: Number(it.price), imageUrl: it.image_url, available: it.active !== false, bizId: it.biz_id };
        }
        case "event": {
          if (!tables.event || !UUID_RE.test(refId)) return null;
          const r = await pool.query("SELECT e.title, e.place_name, e.starts_at, e.cancelled, (SELECT min(price) FROM ticket_tiers t WHERE t.event_id=e.id) AS min_price FROM events e WHERE e.id=$1", [refId]);
          const e = r.rows[0]; if (!e) return null;
          return { title: e.title, subtitle: ["فعالية", e.place_name].filter(Boolean).join(" · "), price: e.min_price == null ? null : Number(e.min_price), imageUrl: null, available: !e.cancelled && (!e.starts_at || new Date(e.starts_at) > new Date(Date.now() - 86400000)), startsAt: e.starts_at, placeName: e.place_name };
        }
        case "biz": {
          if (!tables.biz) return null;
          const r = await pool.query("SELECT name, name_ar, category, logo_url, active FROM biz WHERE id=$1", [refId]);
          const b = r.rows[0]; if (!b) return null;
          return { title: b.name_ar || b.name, subtitle: "دائرة تجارية", price: null, imageUrl: b.logo_url, available: b.active !== false };
        }
        case "post": {
          if (!tables.post || !UUID_RE.test(refId)) return null;
          const r = await pool.query("SELECT title, caption, price, media_url, kind, status, expires_at FROM map_posts WHERE id=$1", [refId]);
          const p = r.rows[0]; if (!p) return null;
          return { title: p.title || p.caption || "منشور على الخريطة", subtitle: "منشور على الخريطة", price: p.price == null ? null : Number(p.price), imageUrl: p.kind === "image" ? p.media_url : null, available: p.status === "active" && (!p.expires_at || new Date(p.expires_at) > new Date()) };
        }
        default: return null;
      }
    } catch { return null; }
  }

  const out = (w, live) => ({
    id: w.id, kind: w.kind, refId: w.ref_id, title: live?.title ?? w.title, subtitle: live?.subtitle ?? w.subtitle,
    price: live?.price ?? (w.price == null ? null : Number(w.price)), imageUrl: live?.imageUrl ?? w.image_url, note: w.note, done: w.done,
    available: w.kind === "custom" ? true : !!live?.available, bizId: live?.bizId ?? null, createdAt: w.created_at,
  });

  // ---- قائمتي: مع تحديث البيانات من مصدرها
  app.get("/wishlist", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const r = await pool.query("SELECT * FROM wishlist_items WHERE user_id=$1 ORDER BY done, created_at DESC LIMIT 300", [uid]);
    const list = [];
    for (const w of r.rows) list.push(out(w, w.kind === "custom" || !w.ref_id ? null : await resolve(w.kind, w.ref_id)));
    return list;
  });

  // ---- إضافة: عنصر مرجعي (يُحفظ مرة واحدة) أو أمنية حرة
  app.post("/wishlist", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const b = req.body ?? {};
    const kind = String(b.kind ?? "custom");
    if (!KINDS.has(kind)) return bad(reply, 400, "bad-kind");
    const note = str(b.note, 300);
    let refId = null, title = str(b.title, 120), subtitle = str(b.subtitle, 120), price = b.price == null || b.price === "" ? null : Math.round(Number(b.price)), imageUrl = str(b.imageUrl, 500) || null;
    if (price != null && (!Number.isFinite(price) || price < 0 || price > 1e11)) return bad(reply, 400, "bad-price");
    if (kind !== "custom") {
      refId = str(b.refId, 64); if (!refId) return bad(reply, 400, "bad-ref");
      const live = await resolve(kind, refId);
      if (!live) return bad(reply, 404, "not-found");
      title = live.title; subtitle = live.subtitle; price = live.price; imageUrl = live.imageUrl ?? null;
      const dup = await pool.query("SELECT * FROM wishlist_items WHERE user_id=$1 AND kind=$2 AND ref_id=$3", [uid, kind, refId]);
      if (dup.rows[0]) return { ...out(dup.rows[0], live), existed: true };
    }
    if (!title) return bad(reply, 400, "bad-title");
    const id = crypto.randomUUID();
    const r = await pool.query(
      "INSERT INTO wishlist_items(id,user_id,kind,ref_id,title,subtitle,price,image_url,note) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING *",
      [id, uid, kind, refId, title, subtitle, price, imageUrl, note]);
    return out(r.rows[0], kind === "custom" ? null : await resolve(kind, refId));
  });

  // ---- تعديل: تم/لم يتم، ملاحظة، وللأمنية الحرة العنوان والسعر
  app.patch("/wishlist/:id", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const id = String(req.params.id); if (!UUID_RE.test(id)) return bad(reply, 404, "not-found");
    const cur = (await pool.query("SELECT * FROM wishlist_items WHERE id=$1 AND user_id=$2", [id, uid])).rows[0];
    if (!cur) return bad(reply, 404, "not-found");
    const b = req.body ?? {};
    const sets = [], vals = []; const set = (col, v) => { vals.push(v); sets.push(`${col}=$${vals.length}`); };
    if (typeof b.done === "boolean") set("done", b.done);
    if (b.note !== undefined) set("note", str(b.note, 300));
    if (cur.kind === "custom") {
      if (b.title !== undefined) { const t = str(b.title, 120); if (!t) return bad(reply, 400, "bad-title"); set("title", t); }
      if (b.price !== undefined) { const p = b.price == null || b.price === "" ? null : Math.round(Number(b.price)); if (p != null && (!Number.isFinite(p) || p < 0)) return bad(reply, 400, "bad-price"); set("price", p); }
    }
    if (!sets.length) return out(cur, cur.kind === "custom" ? null : await resolve(cur.kind, cur.ref_id));
    set("updated_at", new Date());
    vals.push(id);
    const r = await pool.query(`UPDATE wishlist_items SET ${sets.join(",")} WHERE id=$${vals.length} RETURNING *`, vals);
    return out(r.rows[0], cur.kind === "custom" ? null : await resolve(cur.kind, cur.ref_id));
  });

  app.delete("/wishlist/:id", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const id = String(req.params.id); if (!UUID_RE.test(id)) return bad(reply, 404, "not-found");
    const r = await pool.query("DELETE FROM wishlist_items WHERE id=$1 AND user_id=$2", [id, uid]);
    if (!r.rowCount) return bad(reply, 404, "not-found");
    return { ok: true };
  });

  // ---- تنبيهات الأمنيات: انخفاض السعر، عودة التوفر، وتذكير بالفعالية قبل يوم. تُفحص العناصر غير المحقَّقة دورياً
  // وتُقارن ببياناتها المحفوظة؛ السعر المحفوظ يُحدَّث بعد كل مقارنة حتى لا يتكرر التنبيه نفسه.
  let sweeping = false;
  async function sweep() {
    if (sweeping) return { skipped: true };
    sweeping = true;
    const stats = { checked: 0, priceDrops: 0, available: 0, reminders: 0 };
    try {
      const rows = (await pool.query("SELECT * FROM wishlist_items WHERE done=false AND kind<>'custom' AND ref_id IS NOT NULL ORDER BY created_at DESC LIMIT 5000")).rows;
      for (const w of rows) {
        stats.checked++;
        const live = await resolve(w.kind, w.ref_id);
        if (!live) continue;
        const sets = [], vals = []; const set = (col, v) => { vals.push(v); sets.push(`${col}=$${vals.length}`); };
        const oldPrice = w.price == null ? null : Number(w.price);
        if (live.price != null && oldPrice != null && live.price < oldPrice) {
          stats.priceDrops++;
          await notify([w.user_id], { kind: "wish_price_drop", title: `انخفض سعر «${live.title}»`, body: `من ${SAR(oldPrice)} إلى ${SAR(live.price)} — من قائمة أمنياتك`, data: { wishId: w.id, kind: w.kind, refId: w.ref_id, oldPrice, price: live.price } });
          set("alerted_at", new Date());
        }
        if (live.price != null && live.price !== oldPrice) set("price", live.price);
        if (live.available && w.last_available === false) {
          stats.available++;
          await notify([w.user_id], { kind: "wish_available", title: `عاد «${live.title}» متاحاً`, body: "أحد عناصر قائمة أمنياتك متاح الآن", data: { wishId: w.id, kind: w.kind, refId: w.ref_id } });
          set("alerted_at", new Date());
        }
        if (!!live.available !== !!w.last_available) set("last_available", !!live.available);
        if (w.kind === "event" && live.startsAt && !w.reminded_at) {
          const ms = new Date(live.startsAt).getTime() - Date.now();
          if (ms > 0 && ms <= 26 * 3600e3 && live.available) {
            stats.reminders++;
            const d = new Date(live.startsAt);
            const when = `${d.getUTCHours() + 3 >= 24 ? d.getUTCHours() + 3 - 24 : d.getUTCHours() + 3}:${String(d.getUTCMinutes()).padStart(2, "0")}`;
            await notify([w.user_id], { kind: "wish_event_reminder", title: `غداً: ${live.title}`, body: `${live.placeName ? live.placeName + " · " : ""}الساعة ${when} — من قائمة أمنياتك`, data: { wishId: w.id, kind: "event", refId: w.ref_id, eventId: w.ref_id } });
            set("reminded_at", new Date());
          }
        }
        if (sets.length) { vals.push(w.id); await pool.query(`UPDATE wishlist_items SET ${sets.join(",")} WHERE id=$${vals.length}`, vals); }
      }
    } finally { sweeping = false; }
    return stats;
  }
  globalThis.naslifeWishlistSweep = sweep;
  const SWEEP_MS = opts.sweepMs ?? (Number(process.env.WISHLIST_SWEEP_MS) || 30 * 60 * 1000);
  let timer = null;
  if (SWEEP_MS > 0) { timer = setInterval(() => sweep().catch(() => {}), SWEEP_MS); timer.unref?.(); app.addHook("onClose", async () => { if (timer) clearInterval(timer); }); }

  app.get("/wishlist/status", async () => ({ ok: true, sources: tables, sweepEveryMs: SWEEP_MS }));
}
