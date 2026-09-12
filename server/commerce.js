// إضافة Fastify للتجارة في Naslife: المحفظة، الفعاليات والتذاكر، سوق الخدمات والمنتجات.
// التسجيل في src/index.js قبل app.listen (pool وauth معرّفان هناك):
//   await app.register((await import("./commerce.js")).default, { pool, auth });
// المبالغ بالهللة (عدد صحيح). لا توجد بوابة دفع بعد: الشحن عبر المدير (/admin/wallet/credit)
// أو شحن تجريبي إذا WALLET_TEST_TOPUP=1.
import crypto from "node:crypto";

const SAR = (h) => Math.round(Number(h) || 0);
const UUID_RE = /^[0-9a-f-]{36}$/i;
const ID_RE = /^[A-Z]{2}\d{7}$/;
const CATEGORIES = new Set(["coffee", "food", "photo", "gifts", "handmade", "delivery", "services", "other"]);

export default async function commerce(app, opts) {
  const { pool, auth } = opts;
  if (!pool || !auth) throw new Error("commerce: pool and auth are required");

  await pool.query(`
    CREATE TABLE IF NOT EXISTS wallet_accounts (
      user_id TEXT PRIMARY KEY, balance BIGINT NOT NULL DEFAULT 0, points INT NOT NULL DEFAULT 0, updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE TABLE IF NOT EXISTS wallet_tx (
      id UUID PRIMARY KEY, user_id TEXT NOT NULL, kind TEXT NOT NULL, amount BIGINT NOT NULL, peer_id TEXT, ref TEXT, note TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE INDEX IF NOT EXISTS wallet_tx_user ON wallet_tx(user_id, created_at DESC);
    CREATE TABLE IF NOT EXISTS events (
      id UUID PRIMARY KEY, host_id TEXT NOT NULL, vessel_id UUID, title TEXT NOT NULL, description TEXT NOT NULL DEFAULT '',
      starts_at TIMESTAMPTZ NOT NULL, ends_at TIMESTAMPTZ, place_name TEXT, lat DOUBLE PRECISION, lng DOUBLE PRECISION,
      cancelled BOOLEAN NOT NULL DEFAULT false, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE TABLE IF NOT EXISTS ticket_tiers (
      id UUID PRIMARY KEY, event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE, name TEXT NOT NULL, description TEXT NOT NULL DEFAULT '',
      price BIGINT NOT NULL DEFAULT 0, quantity INT NOT NULL, sold INT NOT NULL DEFAULT 0, sort INT NOT NULL DEFAULT 0);
    CREATE TABLE IF NOT EXISTS tickets (
      id UUID PRIMARY KEY, event_id UUID NOT NULL, tier_id UUID NOT NULL, user_id TEXT NOT NULL, code TEXT NOT NULL UNIQUE,
      status TEXT NOT NULL DEFAULT 'valid', paid BIGINT NOT NULL DEFAULT 0, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), used_at TIMESTAMPTZ);
    CREATE INDEX IF NOT EXISTS tickets_user ON tickets(user_id, created_at DESC);
    CREATE TABLE IF NOT EXISTS market_listings (
      id UUID PRIMARY KEY, seller_id TEXT NOT NULL, kind TEXT NOT NULL, category TEXT NOT NULL, title TEXT NOT NULL, description TEXT NOT NULL DEFAULT '',
      price BIGINT NOT NULL, image_url TEXT, place_name TEXT, lat DOUBLE PRECISION, lng DOUBLE PRECISION, status TEXT NOT NULL DEFAULT 'active',
      created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE TABLE IF NOT EXISTS market_orders (
      id UUID PRIMARY KEY, listing_id UUID NOT NULL, buyer_id TEXT NOT NULL, seller_id TEXT NOT NULL, qty INT NOT NULL, total BIGINT NOT NULL,
      note TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'paid', created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
  `);

  const unauthorized = (reply) => reply.code(401).send({ error: "auth" });
  const bad = (reply, code, error, extra = {}) => reply.code(code).send({ error, ...extra });
  const userRow = async (id) => { try { return (await pool.query("SELECT * FROM users WHERE id=$1", [id])).rows[0] ?? null; } catch { return null; } };
  // مدير النظام: عمود في جدول المستخدمين أو جدول admins الذي تديره لوحة الإدارة (server/admin.js)
  const isAdmin = async (uid) => {
    const u = await userRow(uid);
    if (u?.is_admin === true || u?.role === "admin") return true;
    try { return (await pool.query("SELECT 1 FROM admins WHERE user_id=$1", [uid])).rowCount > 0; } catch { return false; }
  };
  const isSuspended = async (uid) => { try { return (await pool.query("SELECT 1 FROM user_flags WHERE user_id=$1 AND suspended", [uid])).rowCount > 0; } catch { return false; } };
  const person = async (id) => {
    const u = await userRow(id);
    return u ? { id: u.id, nickname: u.nickname ?? "", avatarUrl: u.avatar_url ?? u.avatarUrl ?? null } : { id, nickname: "", avatarUrl: null };
  };
  const bbox = (s) => {
    const p = String(s ?? "").split(",").map(Number);
    return p.length === 4 && p.every(Number.isFinite) ? { minLng: p[0], minLat: p[1], maxLng: p[2], maxLat: p[3] } : null;
  };
  // الإشعارات (server/notify.js إن كانت مسجّلة): لا تُفشل الطلب أبداً
  const notify = async (ids, payload) => { try { await globalThis.naslifeNotify?.(ids, payload); } catch { /* ignore */ } };
  const sar = (h) => { const v = Number(h) / 100; return (Number.isInteger(v) ? String(v) : v.toFixed(2)) + " ر.س"; };
  const nickOf = async (id) => (await person(id)).nickname || id;

  // ---- دفتر المحفظة: كل حركة داخل معاملة واحدة مع قفل الصفوف
  async function ledger(client, userId, kind, amount, { peerId = null, ref = null, note = null, points = 0 } = {}) {
    await client.query("INSERT INTO wallet_accounts(user_id) VALUES($1) ON CONFLICT DO NOTHING", [userId]);
    const acc = (await client.query("SELECT balance FROM wallet_accounts WHERE user_id=$1 FOR UPDATE", [userId])).rows[0];
    // BIGINT يصل من pg كنص؛ بدون التحويل لا يعمل فحص الرصيد أبداً
    if (Number(acc.balance) + amount < 0) throw Object.assign(new Error("insufficient"), { code: "insufficient-funds" });
    await client.query("UPDATE wallet_accounts SET balance=balance+$2, points=points+$3, updated_at=now() WHERE user_id=$1", [userId, amount, points]);
    await client.query("INSERT INTO wallet_tx(id,user_id,kind,amount,peer_id,ref,note) VALUES($1,$2,$3,$4,$5,$6,$7)",
      [crypto.randomUUID(), userId, kind, amount, peerId, ref, note]);
  }
  async function tx(fn) {
    const c = await pool.connect();
    try { await c.query("BEGIN"); const out = await fn(c); await c.query("COMMIT"); return out; }
    catch (e) { await c.query("ROLLBACK").catch(() => {}); throw e; }
    finally { c.release(); }
  }
  const txRow = async (x) => ({ id: x.id, kind: x.kind, amount: Number(x.amount), peer: x.peer_id ? await person(x.peer_id) : null, ref: x.ref, note: x.note, createdAt: x.created_at });

  app.get("/wallet", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    await pool.query("INSERT INTO wallet_accounts(user_id) VALUES($1) ON CONFLICT DO NOTHING", [uid]);
    const a = (await pool.query("SELECT balance, points FROM wallet_accounts WHERE user_id=$1", [uid])).rows[0];
    const t = await pool.query("SELECT * FROM wallet_tx WHERE user_id=$1 ORDER BY created_at DESC LIMIT 10", [uid]);
    const tickets = (await pool.query("SELECT count(*)::int AS n FROM tickets t JOIN events e ON e.id=t.event_id WHERE t.user_id=$1 AND t.status='valid' AND e.starts_at > now() - interval '6 hours'", [uid])).rows[0].n;
    return { balance: Number(a.balance), points: a.points, currency: "SAR", upcomingTickets: tickets, recent: await Promise.all(t.rows.map(txRow)),
      testTopup: process.env.WALLET_TEST_TOPUP === "1" };
  });
  app.get("/wallet/transactions", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const before = req.query?.before && !isNaN(Date.parse(req.query.before)) ? new Date(req.query.before).toISOString() : null;
    const t = await pool.query("SELECT * FROM wallet_tx WHERE user_id=$1 AND ($2::timestamptz IS NULL OR created_at < $2) ORDER BY created_at DESC LIMIT 50", [uid, before]);
    return Promise.all(t.rows.map(txRow));
  });
  app.post("/wallet/topup", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (process.env.WALLET_TEST_TOPUP !== "1" && !(await isAdmin(uid))) return bad(reply, 403, "topup-disabled");
    const amount = SAR(req.body?.amount);
    // حتى 100,000 ر.س للشحن التجريبي الواحد (أسعار الفنادق والسيارات تتجاوز السقف القديم 5,000)
    const maxTopup = Number(globalThis.naslifeSettings?.maxTopup) || 10000000;
    if (amount <= 0 || amount > maxTopup) return bad(reply, 400, "bad-amount", { max: maxTopup });
    await tx((c) => ledger(c, uid, "topup", amount, { note: "شحن" }));
    return { ok: true };
  });
  app.post("/admin/wallet/credit", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!(await isAdmin(uid))) return bad(reply, 403, "admin-only");
    const { userId, note } = req.body ?? {}; const amount = SAR(req.body?.amount);
    if (!ID_RE.test(userId ?? "") || amount === 0) return bad(reply, 400, "bad-request");
    await tx((c) => ledger(c, userId, amount > 0 ? "credit" : "debit", amount, { note: String(note ?? "").slice(0, 120), peerId: uid }));
    return { ok: true };
  });
  app.post("/wallet/transfer", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (await isSuspended(uid)) return bad(reply, 403, "suspended");
    const { to } = req.body ?? {}; const amount = SAR(req.body?.amount); const note = String(req.body?.note ?? "").slice(0, 120);
    if (!ID_RE.test(to ?? "") || to === uid) return bad(reply, 400, "bad-recipient");
    if (amount <= 0) return bad(reply, 400, "bad-amount");
    const recipient = await userRow(to);
    if (!recipient || recipient.deleted_at || recipient.deleted === true) return bad(reply, 404, "not-found");
    try {
      await tx(async (c) => {
        await ledger(c, uid, "transfer_out", -amount, { peerId: to, note });
        await ledger(c, to, "transfer_in", amount, { peerId: uid, note });
      });
    } catch (e) { if (e.code === "insufficient-funds") return bad(reply, 402, "insufficient-funds"); throw e; }
    await notify(to, { kind: "transfer_in", title: "وصلك تحويل", body: `${await nickOf(uid)} حوّل لك ${sar(amount)}${note ? " · " + note : ""}`, data: { from: uid, amount } });
    return { ok: true };
  });

  // ---- الفعاليات والتذاكر
  const tierOut = (t) => ({ id: t.id, name: t.name, description: t.description, price: Number(t.price), quantity: t.quantity, sold: t.sold, left: t.quantity - t.sold });
  async function eventOut(e, uid) {
    const tiers = (await pool.query("SELECT * FROM ticket_tiers WHERE event_id=$1 ORDER BY sort, price", [e.id])).rows.map(tierOut);
    const going = (await pool.query("SELECT count(DISTINCT user_id)::int AS n FROM tickets WHERE event_id=$1 AND status<>'refunded'", [e.id])).rows[0].n;
    const mine = uid ? (await pool.query("SELECT count(*)::int AS n FROM tickets WHERE event_id=$1 AND user_id=$2 AND status<>'refunded'", [e.id, uid])).rows[0].n : 0;
    return { id: e.id, host: await person(e.host_id), vesselId: e.vessel_id, title: e.title, description: e.description, startsAt: e.starts_at, endsAt: e.ends_at,
      placeName: e.place_name, lat: e.lat, lng: e.lng, cancelled: e.cancelled, tiers, going, myTickets: mine, isHost: e.host_id === uid };
  }
  app.post("/events", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const b = req.body ?? {};
    const title = String(b.title ?? "").trim(); if (!title || title.length > 120) return bad(reply, 400, "bad-title");
    const startsAt = new Date(b.startsAt); if (isNaN(startsAt)) return bad(reply, 400, "bad-date");
    const endsAt = b.endsAt ? new Date(b.endsAt) : null;
    const lat = b.lat == null ? null : Number(b.lat), lng = b.lng == null ? null : Number(b.lng);
    const tiers = Array.isArray(b.tiers) && b.tiers.length ? b.tiers : [{ name: "عادي", price: 0, quantity: 100 }];
    if (tiers.length > 6) return bad(reply, 400, "too-many-tiers");
    const id = crypto.randomUUID();
    await tx(async (c) => {
      await c.query("INSERT INTO events(id,host_id,vessel_id,title,description,starts_at,ends_at,place_name,lat,lng) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)",
        [id, uid, UUID_RE.test(b.vesselId ?? "") ? b.vesselId : null, title, String(b.description ?? "").slice(0, 2000), startsAt, endsAt, b.placeName ? String(b.placeName).slice(0, 80) : null, lat, lng]);
      for (const [i, t] of tiers.entries()) {
        await c.query("INSERT INTO ticket_tiers(id,event_id,name,description,price,quantity,sort) VALUES($1,$2,$3,$4,$5,$6,$7)",
          [crypto.randomUUID(), id, String(t.name ?? "تذكرة").slice(0, 40), String(t.description ?? "").slice(0, 200), SAR(t.price), Math.max(1, Math.min(10000, Number(t.quantity) || 1)), i]);
      }
    });
    return eventOut((await pool.query("SELECT * FROM events WHERE id=$1", [id])).rows[0], uid);
  });
  app.get("/events", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const bb = bbox(req.query?.bbox); const mine = req.query?.mine === "1"; const vessel = UUID_RE.test(req.query?.vessel ?? "") ? req.query.vessel : null;
    const r = mine
      ? await pool.query("SELECT * FROM events WHERE host_id=$1 ORDER BY starts_at DESC LIMIT 100", [uid])
      : vessel
        ? await pool.query("SELECT * FROM events WHERE vessel_id=$1 AND NOT cancelled ORDER BY starts_at LIMIT 100", [vessel])
        : bb
          ? await pool.query("SELECT * FROM events WHERE NOT cancelled AND starts_at > now() - interval '6 hours' AND lat BETWEEN $2 AND $4 AND lng BETWEEN $1 AND $3 ORDER BY starts_at LIMIT 100", [bb.minLng, bb.minLat, bb.maxLng, bb.maxLat])
          : await pool.query("SELECT * FROM events WHERE NOT cancelled AND starts_at > now() - interval '6 hours' ORDER BY starts_at LIMIT 100");
    return Promise.all(r.rows.map((e) => eventOut(e, uid)));
  });
  app.get("/events/:id", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const r = await pool.query("SELECT * FROM events WHERE id=$1", [req.params.id]);
    if (!r.rowCount) return bad(reply, 404, "not-found");
    return eventOut(r.rows[0], uid);
  });
  app.post("/events/:id/tickets", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (await isSuspended(uid)) return bad(reply, 403, "suspended");
    const { tierId } = req.body ?? {}; const qty = Math.max(1, Math.min(10, Number(req.body?.qty) || 1));
    if (!UUID_RE.test(req.params.id) || !UUID_RE.test(tierId ?? "")) return bad(reply, 400, "bad-id");
    let made = [], sale = null;
    try {
      sale = await tx(async (c) => {
        const ev = (await c.query("SELECT * FROM events WHERE id=$1", [req.params.id])).rows[0];
        if (!ev || ev.cancelled) throw Object.assign(new Error(), { code: "not-found" });
        const tier = (await c.query("SELECT * FROM ticket_tiers WHERE id=$1 AND event_id=$2 FOR UPDATE", [tierId, ev.id])).rows[0];
        if (!tier) throw Object.assign(new Error(), { code: "not-found" });
        if (tier.sold + qty > tier.quantity) throw Object.assign(new Error(), { code: "sold-out" });
        const total = Number(tier.price) * qty;
        if (total > 0) {
          await ledger(c, uid, "ticket", -total, { peerId: ev.host_id, ref: ev.id, note: ev.title, points: Math.floor(total / 1000) });
          await ledger(c, ev.host_id, "ticket_sale", total, { peerId: uid, ref: ev.id, note: ev.title });
        }
        await c.query("UPDATE ticket_tiers SET sold=sold+$2 WHERE id=$1", [tier.id, qty]);
        const out = [];
        for (let i = 0; i < qty; i++) {
          const id = crypto.randomUUID(); const code = "NAS-" + crypto.randomBytes(4).toString("hex").toUpperCase();
          await c.query("INSERT INTO tickets(id,event_id,tier_id,user_id,code,paid) VALUES($1,$2,$3,$4,$5,$6)", [id, ev.id, tier.id, uid, code, Number(tier.price)]);
          out.push(id);
        }
        return { out, ev, total };
      });
      made = sale.out;
    } catch (e) {
      if (e.code === "insufficient-funds") return bad(reply, 402, "insufficient-funds");
      if (e.code === "sold-out") return bad(reply, 409, "sold-out");
      if (e.code === "not-found") return bad(reply, 404, "not-found");
      throw e;
    }
    await notify(sale.ev.host_id, { kind: "ticket_sale", title: "تذاكر جديدة", body: `${await nickOf(uid)} اشترى ${qty > 1 ? qty + " تذاكر" : "تذكرة"} لفعالية ${sale.ev.title}${sale.total > 0 ? " بقيمة " + sar(sale.total) : ""}`, data: { eventId: sale.ev.id }, exclude: uid });
    const r = await pool.query("SELECT t.*, e.title, e.starts_at, e.place_name, tt.name AS tier_name FROM tickets t JOIN events e ON e.id=t.event_id JOIN ticket_tiers tt ON tt.id=t.tier_id WHERE t.id = ANY($1)", [made]);
    return r.rows.map(ticketOut);
  });
  const ticketOut = (t) => ({ id: t.id, code: t.code, status: t.status, paid: Number(t.paid), eventId: t.event_id, title: t.title, startsAt: t.starts_at, placeName: t.place_name, tier: t.tier_name, createdAt: t.created_at, usedAt: t.used_at });
  app.get("/tickets", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const r = await pool.query("SELECT t.*, e.title, e.starts_at, e.place_name, tt.name AS tier_name FROM tickets t JOIN events e ON e.id=t.event_id JOIN ticket_tiers tt ON tt.id=t.tier_id WHERE t.user_id=$1 ORDER BY e.starts_at DESC LIMIT 200", [uid]);
    return r.rows.map(ticketOut);
  });
  app.post("/events/:id/checkin", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const ev = (await pool.query("SELECT * FROM events WHERE id=$1", [req.params.id])).rows[0];
    if (!ev) return bad(reply, 404, "not-found");
    if (ev.host_id !== uid) return bad(reply, 403, "host-only");
    const code = String(req.body?.code ?? "").trim().toUpperCase();
    if (!code) return bad(reply, 400, "bad-code");
    const r = await pool.query("UPDATE tickets SET status='used', used_at=now() WHERE event_id=$1 AND code=$2 AND status='valid' RETURNING id, user_id", [ev.id, code]);
    if (!r.rowCount) return bad(reply, 404, "ticket-invalid");
    return { ok: true, holder: await person(r.rows[0].user_id) };
  });
  app.post("/events/:id/cancel", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const ev = (await pool.query("SELECT * FROM events WHERE id=$1", [req.params.id])).rows[0];
    if (!ev) return bad(reply, 404, "not-found");
    if (ev.host_id !== uid) return bad(reply, 403, "host-only");
    const holders = await tx(async (c) => {
      await c.query("UPDATE events SET cancelled=true WHERE id=$1", [ev.id]);
      const ts = (await c.query("UPDATE tickets SET status='refunded' WHERE event_id=$1 AND status='valid' RETURNING user_id, paid", [ev.id])).rows;
      for (const t of ts) if (Number(t.paid) > 0) {
        await ledger(c, t.user_id, "refund", Number(t.paid), { peerId: uid, ref: ev.id, note: ev.title });
        await ledger(c, uid, "refund_out", -Number(t.paid), { peerId: t.user_id, ref: ev.id, note: ev.title });
      }
      return ts;
    });
    const refunded = new Map();
    for (const t of holders) refunded.set(t.user_id, (refunded.get(t.user_id) ?? 0) + Number(t.paid));
    for (const [u, paid] of refunded) await notify(u, { kind: "event_cancelled", title: "أُلغيت الفعالية", body: `${ev.title}${paid > 0 ? " · استُرد " + sar(paid) + " إلى محفظتك" : ""}`, data: { eventId: ev.id }, exclude: uid });
    return { ok: true };
  });

  // ---- السوق
  const listingOut = async (l, uid) => ({ id: l.id, seller: await person(l.seller_id), kind: l.kind, category: l.category, title: l.title, description: l.description,
    price: Number(l.price), imageUrl: l.image_url, placeName: l.place_name, lat: l.lat, lng: l.lng, status: l.status, createdAt: l.created_at, mine: l.seller_id === uid });
  app.post("/market", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const b = req.body ?? {};
    const title = String(b.title ?? "").trim(); if (!title || title.length > 100) return bad(reply, 400, "bad-title");
    const kind = b.kind === "service" ? "service" : "product";
    const category = CATEGORIES.has(b.category) ? b.category : "other";
    const price = SAR(b.price); if (price < 0) return bad(reply, 400, "bad-price");
    const id = crypto.randomUUID();
    await pool.query("INSERT INTO market_listings(id,seller_id,kind,category,title,description,price,image_url,place_name,lat,lng) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)",
      [id, uid, kind, category, title, String(b.description ?? "").slice(0, 2000), price, absUrl(req, b.imageUrl), b.placeName ? String(b.placeName).slice(0, 80) : null,
       b.lat == null ? null : Number(b.lat), b.lng == null ? null : Number(b.lng)]);
    return listingOut((await pool.query("SELECT * FROM market_listings WHERE id=$1", [id])).rows[0], uid);
  });
  app.get("/market", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const bb = bbox(req.query?.bbox); const q = String(req.query?.q ?? "").trim().slice(0, 60); const cat = CATEGORIES.has(req.query?.category) ? req.query.category : null;
    const r = await pool.query(`SELECT * FROM market_listings WHERE status='active' AND ($1 = '' OR title ILIKE '%' || $1 || '%' OR description ILIKE '%' || $1 || '%')
      AND ($2::text IS NULL OR category=$2) AND ($3::float8 IS NULL OR (lat BETWEEN $4 AND $6 AND lng BETWEEN $3 AND $5)) ORDER BY created_at DESC LIMIT 200`,
      [q, cat, bb?.minLng ?? null, bb?.minLat ?? null, bb?.maxLng ?? null, bb?.maxLat ?? null]);
    return Promise.all(r.rows.map((l) => listingOut(l, uid)));
  });
  // عروضي كلها بما فيها المخفية (hidden) والتي أخفتها الإدارة (blocked) حتى يمكن إظهارها أو تعديلها
  app.get("/market/mine", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const r = await pool.query("SELECT * FROM market_listings WHERE seller_id=$1 ORDER BY (status='active') DESC, created_at DESC", [uid]);
    return Promise.all(r.rows.map((l) => listingOut(l, uid)));
  });
  // رابط مطلق لصورة مرفوعة على الخادم نفسه (يبقى صالحاً في تطبيقات الجوال لاحقاً)
  const absUrl = (req, url) => {
    const s = String(url ?? "").trim(); if (!s) return null;
    if (/^https?:\/\//.test(s)) return s.slice(0, 500);
    if (!s.startsWith("/")) return null;
    const proto = String(req.headers["x-forwarded-proto"] ?? "https").split(",")[0].trim() || "https";
    const host = String(req.headers["x-forwarded-host"] ?? req.headers.host ?? "naslife.app").split(",")[0].trim();
    return `${proto}://${host}${s}`.slice(0, 500);
  };
  // تعديل عرضي: النص والسعر والصورة، وإخفاؤه أو إظهاره (ما لم تكن الإدارة قد أخفته)
  app.patch("/market/:id", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const l = (await pool.query("SELECT * FROM market_listings WHERE id=$1", [req.params.id])).rows[0];
    if (!l) return bad(reply, 404, "not-found");
    if (l.seller_id !== uid) return bad(reply, 403, "forbidden");
    const b = req.body ?? {}; const sets = []; const vals = [];
    const set = (c, v) => { vals.push(v); sets.push(`${c}=$${vals.length}`); };
    if (b.title !== undefined) { const t = String(b.title).trim(); if (!t || t.length > 100) return bad(reply, 400, "bad-title"); set("title", t); }
    if (b.description !== undefined) set("description", String(b.description).slice(0, 2000));
    if (b.price !== undefined) { const p = SAR(b.price); if (p < 0) return bad(reply, 400, "bad-price"); set("price", p); }
    if (b.category !== undefined) set("category", CATEGORIES.has(b.category) ? b.category : "other");
    if (b.kind !== undefined) set("kind", b.kind === "service" ? "service" : "product");
    if (b.imageUrl !== undefined) set("image_url", absUrl(req, b.imageUrl));
    if (b.placeName !== undefined) set("place_name", b.placeName ? String(b.placeName).slice(0, 80) : null);
    if (b.status !== undefined) {
      if (!["active", "hidden"].includes(b.status)) return bad(reply, 400, "bad-status");
      if (l.status === "blocked") return bad(reply, 403, "blocked");
      set("status", b.status);
    }
    if (!sets.length) return bad(reply, 400, "empty");
    vals.push(l.id);
    await pool.query(`UPDATE market_listings SET ${sets.join(", ")} WHERE id=$${vals.length}`, vals);
    return listingOut((await pool.query("SELECT * FROM market_listings WHERE id=$1", [l.id])).rows[0], uid);
  });
  app.get("/market/orders", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const r = await pool.query("SELECT o.*, l.title, l.image_url FROM market_orders o JOIN market_listings l ON l.id=o.listing_id WHERE o.buyer_id=$1 OR o.seller_id=$1 ORDER BY o.created_at DESC LIMIT 200", [uid]);
    return Promise.all(r.rows.map(async (o) => ({ id: o.id, listingId: o.listing_id, title: o.title, imageUrl: o.image_url, qty: o.qty, total: Number(o.total), status: o.status, note: o.note,
      buyer: await person(o.buyer_id), seller: await person(o.seller_id), mineAsSeller: o.seller_id === uid, createdAt: o.created_at })));
  });
  app.get("/market/:id", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const r = await pool.query("SELECT * FROM market_listings WHERE id=$1", [req.params.id]);
    if (!r.rowCount) return bad(reply, 404, "not-found");
    return listingOut(r.rows[0], uid);
  });
  app.delete("/market/:id", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    await pool.query("UPDATE market_listings SET status='hidden' WHERE id=$1 AND seller_id=$2", [req.params.id, uid]);
    return { ok: true };
  });
  app.post("/market/:id/order", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (await isSuspended(uid)) return bad(reply, 403, "suspended");
    const qty = Math.max(1, Math.min(20, Number(req.body?.qty) || 1)); const note = String(req.body?.note ?? "").slice(0, 300);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const l = (await pool.query("SELECT * FROM market_listings WHERE id=$1 AND status='active'", [req.params.id])).rows[0];
    if (!l) return bad(reply, 404, "not-found");
    if (l.seller_id === uid) return bad(reply, 400, "own-listing");
    const total = Number(l.price) * qty; const id = crypto.randomUUID();
    try {
      await tx(async (c) => {
        // المبلغ يُحجز من المشتري ولا يصل البائع إلا عند التسليم
        if (total > 0) await ledger(c, uid, "market", -total, { peerId: l.seller_id, ref: id, note: l.title, points: Math.floor(total / 1000) });
        await c.query("INSERT INTO market_orders(id,listing_id,buyer_id,seller_id,qty,total,note) VALUES($1,$2,$3,$4,$5,$6,$7)", [id, l.id, uid, l.seller_id, qty, total, note]);
      });
    } catch (e) { if (e.code === "insufficient-funds") return bad(reply, 402, "insufficient-funds"); throw e; }
    await notify(l.seller_id, { kind: "market_order", title: "طلب جديد في السوق", body: `${await nickOf(uid)} طلب ${l.title}${qty > 1 ? " × " + qty : ""} بقيمة ${sar(total)}${note ? " · " + note.slice(0, 80) : ""}`, data: { orderId: id, listingId: l.id } });
    return { ok: true, id, total };
  });
  app.post("/market/orders/:id/deliver", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const o = (await pool.query("SELECT o.*, l.title FROM market_orders o JOIN market_listings l ON l.id=o.listing_id WHERE o.id=$1", [req.params.id])).rows[0];
    if (!o) return bad(reply, 404, "not-found");
    if (o.seller_id !== uid) return bad(reply, 403, "seller-only");
    if (o.status !== "paid") return bad(reply, 409, "bad-status");
    await tx(async (c) => {
      await c.query("UPDATE market_orders SET status='delivered', updated_at=now() WHERE id=$1", [o.id]);
      if (Number(o.total) > 0) await ledger(c, uid, "market_sale", Number(o.total), { peerId: o.buyer_id, ref: o.id, note: o.title });
    });
    await notify(o.buyer_id, { kind: "market_status", title: "تم تسليم طلبك", body: `${o.title}: أكد البائع التسليم`, data: { orderId: o.id, status: "delivered" } });
    return { ok: true };
  });
  app.post("/market/orders/:id/cancel", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const o = (await pool.query("SELECT o.*, l.title FROM market_orders o JOIN market_listings l ON l.id=o.listing_id WHERE o.id=$1", [req.params.id])).rows[0];
    if (!o) return bad(reply, 404, "not-found");
    if (o.buyer_id !== uid && o.seller_id !== uid) return bad(reply, 403, "forbidden");
    if (o.status !== "paid") return bad(reply, 409, "bad-status");
    await tx(async (c) => {
      await c.query("UPDATE market_orders SET status='cancelled', updated_at=now() WHERE id=$1", [o.id]);
      if (Number(o.total) > 0) await ledger(c, o.buyer_id, "refund", Number(o.total), { peerId: o.seller_id, ref: o.id, note: o.title });
    });
    const byBuyer = o.buyer_id === uid;
    await notify(byBuyer ? o.seller_id : o.buyer_id, { kind: "market_status", title: byBuyer ? "أُلغي طلب" : "أُلغي طلبك",
      body: byBuyer ? `${await nickOf(uid)} ألغى طلب ${o.title}` : `${o.title}: ألغى البائع الطلب${Number(o.total) > 0 ? " واستُرد " + sar(o.total) + " إلى محفظتك" : ""}`, data: { orderId: o.id, status: "cancelled" } });
    return { ok: true };
  });
}
