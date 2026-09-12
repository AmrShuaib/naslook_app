// إضافة Fastify للدوائر التجارية في Naslife: براندات عالمية وسينما وفنادق وتأجير سيارات.
// التسجيل في src/index.js (بعد commerce.js لأن الدفع يمر بجداول المحفظة نفسها):
//   await app.register((await import("./business.js")).default, { pool, auth });
// المبالغ بالهللة. الشراء والحجز يخصمان من محفظة ناس لايف ويُستردان عند الإلغاء ضمن المهلة.
import crypto from "node:crypto";
import { SEED } from "./business_seed.js";

const SLUG_RE = /^[a-z0-9-]{3,60}$/;
const UUID_RE = /^[0-9a-f-]{36}$/i;
const CATEGORIES = new Set(["brand", "cinema", "hotel", "car_rental"]);
const KINDS = new Set(["product", "showtime", "room", "car"]);
const DAY = 86400000;
const SHOWTIME_DAYS = 3;            // عدد الأيام القادمة التي تُعرض لها مواعيد السينما
const RIYADH_OFFSET_MIN = 180;      // توقيت السعودية UTC+3 (بلا توقيت صيفي)

export default async function business(app, opts) {
  const { pool, auth } = opts;
  if (!pool || !auth) throw new Error("business: pool and auth are required");

  await pool.query(`
    CREATE TABLE IF NOT EXISTS wallet_accounts (
      user_id TEXT PRIMARY KEY, balance BIGINT NOT NULL DEFAULT 0, points INT NOT NULL DEFAULT 0, updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE TABLE IF NOT EXISTS wallet_tx (
      id UUID PRIMARY KEY, user_id TEXT NOT NULL, kind TEXT NOT NULL, amount BIGINT NOT NULL, peer_id TEXT, ref TEXT, note TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE TABLE IF NOT EXISTS biz (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, name_ar TEXT NOT NULL DEFAULT '', category TEXT NOT NULL, sector TEXT NOT NULL DEFAULT '',
      description TEXT NOT NULL DEFAULT '', lat DOUBLE PRECISION NOT NULL, lng DOUBLE PRECISION NOT NULL, address TEXT NOT NULL DEFAULT '',
      hours TEXT NOT NULL DEFAULT '', phone TEXT, website TEXT, color TEXT, highlights JSONB NOT NULL DEFAULT '[]', verified BOOLEAN NOT NULL DEFAULT false,
      official BOOLEAN NOT NULL DEFAULT false, active BOOLEAN NOT NULL DEFAULT true, sort INT NOT NULL DEFAULT 0, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE TABLE IF NOT EXISTS biz_items (
      id TEXT PRIMARY KEY, biz_id TEXT NOT NULL REFERENCES biz(id) ON DELETE CASCADE, kind TEXT NOT NULL, title TEXT NOT NULL, description TEXT NOT NULL DEFAULT '',
      price BIGINT NOT NULL, unit TEXT NOT NULL DEFAULT 'item', stock INT, meta JSONB NOT NULL DEFAULT '{}', image_url TEXT, active BOOLEAN NOT NULL DEFAULT true, sort INT NOT NULL DEFAULT 0);
    CREATE INDEX IF NOT EXISTS biz_items_biz ON biz_items(biz_id, sort);
    CREATE TABLE IF NOT EXISTS biz_orders (
      id UUID PRIMARY KEY, biz_id TEXT NOT NULL, item_id TEXT NOT NULL, user_id TEXT NOT NULL, kind TEXT NOT NULL, qty INT NOT NULL DEFAULT 1,
      start_at TIMESTAMPTZ, end_at TIMESTAMPTZ, units INT NOT NULL DEFAULT 1, total BIGINT NOT NULL, status TEXT NOT NULL DEFAULT 'confirmed',
      code TEXT NOT NULL UNIQUE, note TEXT NOT NULL DEFAULT '', meta JSONB NOT NULL DEFAULT '{}', created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE INDEX IF NOT EXISTS biz_orders_user ON biz_orders(user_id, created_at DESC);
    CREATE INDEX IF NOT EXISTS biz_orders_item ON biz_orders(item_id, status);
    CREATE TABLE IF NOT EXISTS biz_follows (biz_id TEXT NOT NULL, user_id TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (biz_id, user_id));
    CREATE TABLE IF NOT EXISTS biz_reviews (
      biz_id TEXT NOT NULL, user_id TEXT NOT NULL, rating INT NOT NULL, text TEXT NOT NULL DEFAULT '', created_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (biz_id, user_id));
  `);

  // ---- بذر البيانات الأولية: استعلامان مجمّعان فقط (لا 100+ رحلة إلى قاعدة البيانات) ولا يوقفان الإقلاع،
  // حتى يمرّ فحص الصحة في النشر التلقائي سريعاً وتبقى الطلبات السابقة محفوظة (upsert).
  async function seedAll() {
    const bv = [], bp = [];
    SEED.forEach((b, i) => {
      const o = bp.length;
      bv.push(`($${o + 1},$${o + 2},$${o + 3},$${o + 4},$${o + 5},$${o + 6},$${o + 7},$${o + 8},$${o + 9},$${o + 10},$${o + 11},$${o + 12},$${o + 13},$${o + 14},$${o + 15})`);
      bp.push(b.id, b.name, b.nameAr ?? "", b.category, b.sector ?? "", b.description ?? "", b.lat, b.lng, b.address ?? "", b.hours ?? "", b.phone ?? null, b.website ?? null, b.color ?? null, JSON.stringify(b.highlights ?? []), i);
    });
    await pool.query(`INSERT INTO biz(id,name,name_ar,category,sector,description,lat,lng,address,hours,phone,website,color,highlights,sort) VALUES ${bv.join(",")}
      ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, name_ar=EXCLUDED.name_ar, category=EXCLUDED.category, sector=EXCLUDED.sector, description=EXCLUDED.description,
        lat=EXCLUDED.lat, lng=EXCLUDED.lng, address=EXCLUDED.address, hours=EXCLUDED.hours, phone=EXCLUDED.phone, website=EXCLUDED.website, color=EXCLUDED.color,
        highlights=EXCLUDED.highlights, sort=EXCLUDED.sort, active=true`, bp);
    const iv = [], ip = [];
    for (const b of SEED) {
      (b.items ?? []).forEach((it, j) => {
        const o = ip.length;
        iv.push(`($${o + 1},$${o + 2},$${o + 3},$${o + 4},$${o + 5},$${o + 6},$${o + 7},$${o + 8},$${o + 9},$${o + 10},$${o + 11})`);
        ip.push(it.id, b.id, it.kind, it.title, it.description ?? "", it.price, it.unit ?? "item", it.stock ?? null, JSON.stringify(it.meta ?? {}), it.imageUrl ?? null, j);
      });
    }
    if (iv.length) await pool.query(`INSERT INTO biz_items(id,biz_id,kind,title,description,price,unit,stock,meta,image_url,sort) VALUES ${iv.join(",")}
      ON CONFLICT (id) DO UPDATE SET biz_id=EXCLUDED.biz_id, kind=EXCLUDED.kind, title=EXCLUDED.title, description=EXCLUDED.description, price=EXCLUDED.price,
        unit=EXCLUDED.unit, stock=EXCLUDED.stock, meta=EXCLUDED.meta, image_url=EXCLUDED.image_url, sort=EXCLUDED.sort, active=true`, ip);
  }
  let seedState = "pending";
  const seeding = seedAll().then(() => { seedState = "ok"; }).catch((e) => { seedState = "error: " + (e?.message || e); try { app.log.error({ err: e }, "business: seed failed"); } catch { console.error("business: seed failed", e); } });
  // تشخيص عام خفيف: زمن تشغيل العملية ومنفذ الاستماع الفعلي (يساعد فحص صحة النشر التلقائي)
  app.get("/biz/status", async () => {
    let addr = null; try { addr = app.server?.address?.() ?? null; } catch { addr = null; }
    return { ok: true, uptimeSec: Math.round(process.uptime()), seed: seedState, listen: addr, envPort: process.env.PORT ?? null, node: process.version };
  });

  const unauthorized = (reply) => reply.code(401).send({ error: "auth" });
  const bad = (reply, code, error, extra = {}) => reply.code(code).send({ error, ...extra });
  const optionalAuth = async (req) => { try { return (await auth(req)) || null; } catch { return null; } };
  const userRow = async (id) => { try { return (await pool.query("SELECT * FROM users WHERE id=$1", [id])).rows[0] ?? null; } catch { return null; } };
  const person = async (id) => {
    const u = await userRow(id);
    return u ? { id: u.id, nickname: u.nickname ?? "", avatarUrl: u.avatar_url ?? u.avatarUrl ?? null } : { id, nickname: "", avatarUrl: null };
  };
  const bbox = (s) => {
    const p = String(s ?? "").split(",").map(Number);
    return p.length === 4 && p.every(Number.isFinite) ? { minLng: p[0], minLat: p[1], maxLng: p[2], maxLat: p[3] } : null;
  };

  // ---- دفتر المحفظة (نفس جداول commerce.js وقواعده: قفل الصف، رصيد لا يقل عن صفر)
  async function ledger(client, userId, kind, amount, { peerId = null, ref = null, note = null, points = 0 } = {}) {
    await client.query("INSERT INTO wallet_accounts(user_id) VALUES($1) ON CONFLICT DO NOTHING", [userId]);
    const acc = (await client.query("SELECT balance FROM wallet_accounts WHERE user_id=$1 FOR UPDATE", [userId])).rows[0];
    if (Number(acc.balance) + amount < 0) throw Object.assign(new Error("insufficient"), { code: "insufficient-funds" });
    await client.query("UPDATE wallet_accounts SET balance=balance+$2, points=points+$3, updated_at=now() WHERE user_id=$1", [userId, amount, points]);
    await client.query("INSERT INTO wallet_tx(id,user_id,kind,amount,peer_id,ref,note) VALUES($1,$2,$3,$4,$5,$6,$7)", [crypto.randomUUID(), userId, kind, amount, peerId, ref, note]);
  }
  async function tx(fn) {
    const c = await pool.connect();
    try { await c.query("BEGIN"); const out = await fn(c); await c.query("COMMIT"); return out; }
    catch (e) { await c.query("ROLLBACK").catch(() => {}); throw e; }
    finally { c.release(); }
  }
  const fail = (code, extra = {}) => Object.assign(new Error(code), { code, ...extra });

  // ---- مواعيد السينما: تُولَّد من أوقات العرض اليومية للأيام القادمة (بتوقيت السعودية)
  function showtimeSlots(item, now = new Date()) {
    const times = Array.isArray(item.meta?.times) ? item.meta.times : [];
    const local = new Date(now.getTime() + RIYADH_OFFSET_MIN * 60000);
    const y = local.getUTCFullYear(), m = local.getUTCMonth(), d = local.getUTCDate();
    const out = [];
    for (let day = 0; day < SHOWTIME_DAYS; day++) {
      for (const t of times) {
        const [hh, mm] = String(t).split(":").map(Number);
        if (!Number.isFinite(hh) || !Number.isFinite(mm)) continue;
        const at = new Date(Date.UTC(y, m, d + day, hh, mm) - RIYADH_OFFSET_MIN * 60000);
        if (at.getTime() > now.getTime() + 15 * 60000) out.push(at);
      }
    }
    return out;
  }
  const isSlot = (item, at) => showtimeSlots(item).some((s) => s.getTime() === at.getTime());

  // ---- الحجوزات المتداخلة زمنياً (غرف وسيارات) ومقاعد كل موعد
  async function bookedUnits(client, itemId, startAt, endAt) {
    const r = await client.query(
      "SELECT COALESCE(SUM(qty),0)::int AS n FROM biz_orders WHERE item_id=$1 AND status IN ('confirmed','used') AND start_at < $3 AND end_at > $2",
      [itemId, startAt, endAt]);
    return r.rows[0].n;
  }
  async function seatsTaken(client, itemId, at) {
    const r = await client.query("SELECT COALESCE(SUM(qty),0)::int AS n FROM biz_orders WHERE item_id=$1 AND status IN ('confirmed','used') AND start_at=$2", [itemId, at]);
    return r.rows[0].n;
  }

  // ---- المخرجات
  const bizOut = (b, extra = {}) => ({
    id: b.id, name: b.name, nameAr: b.name_ar, category: b.category, sector: b.sector, description: b.description, lat: b.lat, lng: b.lng, address: b.address,
    hours: b.hours, phone: b.phone, website: b.website, color: b.color, highlights: b.highlights ?? [], verified: b.verified, official: b.official,
    followers: Number(b.followers ?? 0), rating: b.rating == null ? null : Number(b.rating), ratingCount: Number(b.rating_count ?? 0), minPrice: b.min_price == null ? null : Number(b.min_price),
    itemsCount: Number(b.items_count ?? 0), following: b.following === true, ...extra,
  });
  async function itemOut(it, now = new Date()) {
    const base = { id: it.id, bizId: it.biz_id, kind: it.kind, title: it.title, description: it.description, price: Number(it.price), unit: it.unit, stock: it.stock, meta: it.meta ?? {}, imageUrl: it.image_url, active: it.active };
    if (it.kind === "showtime") {
      const slots = showtimeSlots(it, now);
      const taken = slots.length ? (await pool.query("SELECT start_at, COALESCE(SUM(qty),0)::int AS n FROM biz_orders WHERE item_id=$1 AND status IN ('confirmed','used') AND start_at = ANY($2) GROUP BY start_at", [it.id, slots])).rows : [];
      const map = new Map(taken.map((r) => [new Date(r.start_at).getTime(), r.n]));
      base.slots = slots.map((s) => ({ startsAt: s.toISOString(), seatsLeft: Math.max(0, (it.stock ?? 0) - (map.get(s.getTime()) ?? 0)) }));
    }
    return base;
  }
  const orderOut = (o) => ({
    id: o.id, bizId: o.biz_id, bizName: o.biz_name ?? null, bizNameAr: o.biz_name_ar ?? null, category: o.category ?? null, itemId: o.item_id, title: o.item_title ?? null, kind: o.kind, qty: o.qty,
    startAt: o.start_at, endAt: o.end_at, units: o.units, total: Number(o.total), status: o.status, code: o.code, note: o.note, meta: o.meta ?? {}, createdAt: o.created_at,
    cancellable: cancellable(o),
  });
  // الإلغاء: المنتجات خلال 24 ساعة من الشراء، التذاكر قبل ساعتين من العرض، الغرف والسيارات قبل 24 ساعة من البداية
  function cancellable(o, now = Date.now()) {
    if (o.status !== "confirmed") return false;
    const start = o.start_at ? new Date(o.start_at).getTime() : null;
    if (o.kind === "product") return now - new Date(o.created_at).getTime() < DAY;
    if (o.kind === "showtime") return start != null && start - now > 2 * 3600000;
    return start != null && start - now > DAY;
  }

  const LIST_SQL = `
    SELECT b.*, (SELECT count(*) FROM biz_follows f WHERE f.biz_id=b.id) AS followers,
      (SELECT round(avg(rating)::numeric, 1) FROM biz_reviews r WHERE r.biz_id=b.id) AS rating,
      (SELECT count(*) FROM biz_reviews r WHERE r.biz_id=b.id) AS rating_count,
      (SELECT min(price) FROM biz_items i WHERE i.biz_id=b.id AND i.active) AS min_price,
      (SELECT count(*) FROM biz_items i WHERE i.biz_id=b.id AND i.active) AS items_count,
      ($1::text IS NOT NULL AND EXISTS (SELECT 1 FROM biz_follows f WHERE f.biz_id=b.id AND f.user_id=$1)) AS following
    FROM biz b WHERE b.active`;

  // ---- القائمة (عامة) مع تصفية بالفئة والحدود الجغرافية والبحث
  app.get("/biz", async (req) => {
    await seeding;
    const uid = await optionalAuth(req);
    const cat = CATEGORIES.has(req.query?.category) ? req.query.category : null;
    const bb = bbox(req.query?.bbox);
    const q = String(req.query?.q ?? "").trim().slice(0, 60);
    const mine = req.query?.following === "1" && uid;
    const r = await pool.query(`${LIST_SQL}
      AND ($2::text IS NULL OR b.category=$2)
      AND ($3::float8 IS NULL OR (b.lat BETWEEN $4 AND $6 AND b.lng BETWEEN $3 AND $5))
      AND ($7 = '' OR b.name ILIKE '%' || $7 || '%' OR b.name_ar ILIKE '%' || $7 || '%' OR b.sector ILIKE '%' || $7 || '%')
      AND ($8::bool = false OR EXISTS (SELECT 1 FROM biz_follows f WHERE f.biz_id=b.id AND f.user_id=$1))
      ORDER BY b.category, b.sort, b.name LIMIT 200`,
      [uid, cat, bb?.minLng ?? null, bb?.minLat ?? null, bb?.maxLng ?? null, bb?.maxLat ?? null, q, !!mine]);
    return r.rows.map((b) => bizOut(b));
  });

  // ---- التفاصيل (عامة): الكتالوج والمراجعات، وطلبات المستخدم إن كان مسجّلاً
  app.get("/biz/:id", async (req, reply) => {
    await seeding;
    const uid = await optionalAuth(req);
    if (!SLUG_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const r = await pool.query(`${LIST_SQL} AND b.id=$2`, [uid, req.params.id]);
    if (!r.rowCount) return bad(reply, 404, "not-found");
    const b = r.rows[0];
    const items = await Promise.all((await pool.query("SELECT * FROM biz_items WHERE biz_id=$1 AND active ORDER BY sort", [b.id])).rows.map((it) => itemOut(it)));
    const reviews = await Promise.all((await pool.query("SELECT * FROM biz_reviews WHERE biz_id=$1 ORDER BY created_at DESC LIMIT 20", [b.id])).rows.map(async (x) => ({
      user: await person(x.user_id), rating: x.rating, text: x.text, createdAt: x.created_at, mine: x.user_id === uid })));
    const myOrders = uid ? (await pool.query("SELECT o.*, i.title AS item_title FROM biz_orders o JOIN biz_items i ON i.id=o.item_id WHERE o.biz_id=$1 AND o.user_id=$2 ORDER BY o.created_at DESC LIMIT 50", [b.id, uid])).rows.map(orderOut) : [];
    return bizOut(b, { items, reviews, myOrders });
  });

  app.post("/biz/:id/follow", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!SLUG_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const b = (await pool.query("SELECT id FROM biz WHERE id=$1 AND active", [req.params.id])).rows[0];
    if (!b) return bad(reply, 404, "not-found");
    await pool.query("INSERT INTO biz_follows(biz_id,user_id) VALUES($1,$2) ON CONFLICT DO NOTHING", [b.id, uid]);
    return { ok: true };
  });
  app.delete("/biz/:id/follow", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!SLUG_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    await pool.query("DELETE FROM biz_follows WHERE biz_id=$1 AND user_id=$2", [req.params.id, uid]);
    return { ok: true };
  });

  app.post("/biz/:id/reviews", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!SLUG_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const rating = Math.round(Number(req.body?.rating)); const text = String(req.body?.text ?? "").trim().slice(0, 500);
    if (!(rating >= 1 && rating <= 5)) return bad(reply, 400, "bad-rating");
    const b = (await pool.query("SELECT id FROM biz WHERE id=$1 AND active", [req.params.id])).rows[0];
    if (!b) return bad(reply, 404, "not-found");
    await pool.query("INSERT INTO biz_reviews(biz_id,user_id,rating,text) VALUES($1,$2,$3,$4) ON CONFLICT (biz_id,user_id) DO UPDATE SET rating=EXCLUDED.rating, text=EXCLUDED.text, created_at=now()", [b.id, uid, rating, text]);
    return { ok: true };
  });

  // ---- الشراء والحجز: منتج (كمية)، تذكرة سينما (موعد + عدد)، غرفة (من/إلى + عدد غرف)، سيارة (من/إلى)
  app.post("/biz/:id/orders", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!SLUG_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const body = req.body ?? {};
    if (!SLUG_RE.test(body.itemId ?? "")) return bad(reply, 400, "bad-item");
    const qty = Math.max(1, Math.min(20, Math.round(Number(body.qty) || 1)));
    const note = String(body.note ?? "").slice(0, 300);
    const startAt = body.startAt ? new Date(body.startAt) : null, endAt = body.endAt ? new Date(body.endAt) : null;
    if ((startAt && isNaN(startAt)) || (endAt && isNaN(endAt))) return bad(reply, 400, "bad-date");
    const id = crypto.randomUUID();
    let out;
    try {
      out = await tx(async (c) => {
        const b = (await c.query("SELECT * FROM biz WHERE id=$1 AND active", [req.params.id])).rows[0];
        if (!b) throw fail("not-found");
        const it = (await c.query("SELECT * FROM biz_items WHERE id=$1 AND biz_id=$2 AND active FOR UPDATE", [body.itemId, b.id])).rows[0];
        if (!it || !KINDS.has(it.kind)) throw fail("not-found");
        const price = Number(it.price);
        let units = 1, total = 0, s = null, e = null, meta = {};
        if (it.kind === "product") {
          if (it.stock != null && it.stock < qty) throw fail("sold-out", { left: it.stock });
          total = price * qty;
          if (it.stock != null) await c.query("UPDATE biz_items SET stock=stock-$2 WHERE id=$1", [it.id, qty]);
        } else if (it.kind === "showtime") {
          if (!startAt || !isSlot(it, startAt)) throw fail("bad-slot");
          if (qty > 10) throw fail("too-many");
          const taken = await seatsTaken(c, it.id, startAt);
          if (taken + qty > (it.stock ?? 0)) throw fail("sold-out", { left: Math.max(0, (it.stock ?? 0) - taken) });
          total = price * qty; s = startAt; e = new Date(startAt.getTime() + ((it.meta?.minutes ?? 120) * 60000));
          meta = { movie: it.title, hall: it.meta?.hall ?? null };
        } else {
          // غرفة أو سيارة: مدة بالأيام الكاملة بين البداية والنهاية
          if (!startAt || !endAt) throw fail("bad-date");
          const days = Math.round((endAt.getTime() - startAt.getTime()) / DAY);
          if (days < 1 || days > 60) throw fail("bad-range");
          if (startAt.getTime() < Date.now() - DAY) throw fail("in-past");
          const rooms = it.kind === "room" ? Math.min(qty, 5) : 1;
          const booked = await bookedUnits(c, it.id, startAt, endAt);
          if (booked + rooms > (it.stock ?? 0)) throw fail("unavailable", { left: Math.max(0, (it.stock ?? 0) - booked) });
          units = days; total = price * days * rooms; s = startAt; e = endAt;
          meta = it.kind === "room" ? { rooms, guests: Math.max(1, Math.min(20, Math.round(Number(body.guests) || 1))) } : { pickup: b.address };
          if (it.kind === "room") { /* الكمية = عدد الغرف */ }
        }
        const finalQty = it.kind === "room" ? Math.min(qty, 5) : it.kind === "car" ? 1 : qty;
        const code = "NAS-" + crypto.randomBytes(4).toString("hex").toUpperCase();
        if (total > 0) await ledger(c, uid, "biz", -total, { ref: id, note: `${b.name_ar || b.name} · ${it.title}`, points: Math.floor(total / 1000) });
        await c.query("INSERT INTO biz_orders(id,biz_id,item_id,user_id,kind,qty,start_at,end_at,units,total,code,note,meta) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)",
          [id, b.id, it.id, uid, it.kind, finalQty, s, e, units, total, code, note, JSON.stringify(meta)]);
        return { id, code, total };
      });
    } catch (err) {
      if (err.code === "insufficient-funds") return bad(reply, 402, "insufficient-funds");
      if (err.code === "not-found") return bad(reply, 404, "not-found");
      if (["sold-out", "unavailable"].includes(err.code)) return bad(reply, 409, err.code, { left: err.left ?? 0 });
      if (["bad-slot", "bad-date", "bad-range", "in-past", "too-many"].includes(err.code)) return bad(reply, 400, err.code);
      throw err;
    }
    const r = await pool.query("SELECT o.*, i.title AS item_title, b.name AS biz_name, b.name_ar AS biz_name_ar, b.category FROM biz_orders o JOIN biz_items i ON i.id=o.item_id JOIN biz b ON b.id=o.biz_id WHERE o.id=$1", [out.id]);
    return orderOut(r.rows[0]);
  });

  app.get("/biz/orders/mine", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const r = await pool.query("SELECT o.*, i.title AS item_title, b.name AS biz_name, b.name_ar AS biz_name_ar, b.category FROM biz_orders o JOIN biz_items i ON i.id=o.item_id JOIN biz b ON b.id=o.biz_id WHERE o.user_id=$1 ORDER BY o.created_at DESC LIMIT 200", [uid]);
    return r.rows.map(orderOut);
  });

  app.post("/biz/orders/:id/cancel", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    try {
      await tx(async (c) => {
        const o = (await c.query("SELECT o.*, i.title AS item_title, i.kind AS item_kind, i.stock, b.name_ar, b.name FROM biz_orders o JOIN biz_items i ON i.id=o.item_id JOIN biz b ON b.id=o.biz_id WHERE o.id=$1 FOR UPDATE OF o", [req.params.id])).rows[0];
        if (!o || o.user_id !== uid) throw fail("not-found");
        if (!cancellable(o)) throw fail("not-cancellable");
        await c.query("UPDATE biz_orders SET status='cancelled', updated_at=now() WHERE id=$1", [o.id]);
        if (o.kind === "product" && o.stock != null) await c.query("UPDATE biz_items SET stock=stock+$2 WHERE id=$1", [o.item_id, o.qty]);
        if (Number(o.total) > 0) await ledger(c, uid, "biz_refund", Number(o.total), { ref: o.id, note: `${o.name_ar || o.name} · ${o.item_title}` });
      });
    } catch (err) {
      if (err.code === "not-found") return bad(reply, 404, "not-found");
      if (err.code === "not-cancellable") return bad(reply, 409, "not-cancellable");
      throw err;
    }
    return { ok: true };
  });

  // ---- تأكيد الاستخدام (للتحقق من رمز الحجز عند الاستلام؛ متاح للمدير فقط الآن)
  app.post("/biz/:id/checkin", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const u = await userRow(uid);
    if (!(u?.is_admin === true || u?.role === "admin")) return bad(reply, 403, "admin-only");
    const code = String(req.body?.code ?? "").trim().toUpperCase();
    const r = await pool.query("UPDATE biz_orders SET status='used', updated_at=now() WHERE biz_id=$1 AND code=$2 AND status='confirmed' RETURNING user_id", [req.params.id, code]);
    if (!r.rowCount) return bad(reply, 404, "code-invalid");
    return { ok: true, holder: await person(r.rows[0].user_id) };
  });
}
