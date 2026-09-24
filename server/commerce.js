// إضافة Fastify للتجارة في Naslife: المحفظة، الفعاليات والتذاكر، سوق الخدمات والمنتجات.
// التسجيل في src/index.js قبل app.listen (pool وauth معرّفان هناك):
//   await app.register((await import("./commerce.js")).default, { pool, auth });
// المبالغ بالهللة (عدد صحيح). لا توجد بوابة دفع بعد: الشحن عبر المدير (/admin/wallet/credit)
// أو شحن تجريبي إذا WALLET_TEST_TOPUP=1.
import crypto from "node:crypto";

const SAR = (h) => Math.round(Number(h) || 0);
const UUID_RE = /^[0-9a-f-]{36}$/i;
const ID_RE = /^[A-Z]{2}\d{7}$/;
import { CATEGORY_SET, subOk, CONDITIONS, SORTS, ORDER_STAGES } from "./market_taxonomy.js";

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
  await pool.query(`
    ALTER TABLE market_listings ADD COLUMN IF NOT EXISTS images JSONB NOT NULL DEFAULT '[]', ADD COLUMN IF NOT EXISTS subcategory TEXT, ADD COLUMN IF NOT EXISTS condition TEXT,
      ADD COLUMN IF NOT EXISTS delivery BOOLEAN NOT NULL DEFAULT false, ADD COLUMN IF NOT EXISTS stock INT, ADD COLUMN IF NOT EXISTS sold INT NOT NULL DEFAULT 0, ADD COLUMN IF NOT EXISTS views INT NOT NULL DEFAULT 0,
      ADD COLUMN IF NOT EXISTS variants JSONB NOT NULL DEFAULT '[]', ADD COLUMN IF NOT EXISTS availability JSONB, ADD COLUMN IF NOT EXISTS publish_at TIMESTAMPTZ, ADD COLUMN IF NOT EXISTS bumped_at TIMESTAMPTZ,
      ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), ADD COLUMN IF NOT EXISTS spotlight_until TIMESTAMPTZ, ADD COLUMN IF NOT EXISTS rating_avg REAL, ADD COLUMN IF NOT EXISTS rating_count INT NOT NULL DEFAULT 0,
      ADD COLUMN IF NOT EXISTS city TEXT;
    UPDATE market_listings SET bumped_at = created_at WHERE bumped_at IS NULL;
    UPDATE market_listings SET images = jsonb_build_array(image_url) WHERE images = '[]'::jsonb AND image_url IS NOT NULL;
    CREATE INDEX IF NOT EXISTS market_listings_active ON market_listings(status, bumped_at DESC);
    ALTER TABLE market_orders ADD COLUMN IF NOT EXISTS code TEXT, ADD COLUMN IF NOT EXISTS variant TEXT, ADD COLUMN IF NOT EXISTS coupon TEXT, ADD COLUMN IF NOT EXISTS discount BIGINT NOT NULL DEFAULT 0,
      ADD COLUMN IF NOT EXISTS commission BIGINT NOT NULL DEFAULT 0, ADD COLUMN IF NOT EXISTS slot TIMESTAMPTZ, ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMPTZ, ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ,
      ADD COLUMN IF NOT EXISTS dispute_reason TEXT, ADD COLUMN IF NOT EXISTS dispute_status TEXT, ADD COLUMN IF NOT EXISTS dispute_note TEXT, ADD COLUMN IF NOT EXISTS accepted_at TIMESTAMPTZ,
      ADD COLUMN IF NOT EXISTS courier_id TEXT, ADD COLUMN IF NOT EXISTS courier_note TEXT NOT NULL DEFAULT '', ADD COLUMN IF NOT EXISTS courier_at TIMESTAMPTZ;
    UPDATE market_orders SET status='completed', completed_at=COALESCE(completed_at, updated_at) WHERE status='delivered' AND delivered_at IS NULL;
    CREATE TABLE IF NOT EXISTS market_reviews (order_id UUID PRIMARY KEY, listing_id UUID NOT NULL, seller_id TEXT NOT NULL, buyer_id TEXT NOT NULL, rating INT NOT NULL, text TEXT NOT NULL DEFAULT '',
      reply TEXT, reply_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE INDEX IF NOT EXISTS market_reviews_seller ON market_reviews(seller_id, created_at DESC);
    CREATE TABLE IF NOT EXISTS market_coupons (code TEXT NOT NULL, seller_id TEXT NOT NULL, percent INT, amount BIGINT, min_total BIGINT NOT NULL DEFAULT 0, max_uses INT, used INT NOT NULL DEFAULT 0,
      expires_at TIMESTAMPTZ, active BOOLEAN NOT NULL DEFAULT true, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (seller_id, code));
    CREATE TABLE IF NOT EXISTS market_seller_stats (seller_id TEXT PRIMARY KEY, rating_avg REAL, rating_count INT NOT NULL DEFAULT 0, completed INT NOT NULL DEFAULT 0, cancelled INT NOT NULL DEFAULT 0,
      response_hours REAL, badges JSONB NOT NULL DEFAULT '[]', updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE TABLE IF NOT EXISTS market_seller_flags (seller_id TEXT PRIMARY KEY, licensed BOOLEAN NOT NULL DEFAULT false, note TEXT, updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE TABLE IF NOT EXISTS market_follows (user_id TEXT NOT NULL, seller_id TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (user_id, seller_id));
    CREATE TABLE IF NOT EXISTS market_questions (id UUID PRIMARY KEY, listing_id UUID NOT NULL, user_id TEXT NOT NULL, text TEXT NOT NULL, answer TEXT, answered_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE INDEX IF NOT EXISTS market_questions_listing ON market_questions(listing_id, created_at DESC);
    CREATE TABLE IF NOT EXISTS market_wanted (id UUID PRIMARY KEY, user_id TEXT NOT NULL, title TEXT NOT NULL, description TEXT NOT NULL DEFAULT '', category TEXT NOT NULL, subcategory TEXT,
      budget_min BIGINT, budget_max BIGINT, place_name TEXT, city TEXT, lat DOUBLE PRECISION, lng DOUBLE PRECISION, status TEXT NOT NULL DEFAULT 'open', replies INT NOT NULL DEFAULT 0, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE TABLE IF NOT EXISTS market_wanted_replies (id UUID PRIMARY KEY, wanted_id UUID NOT NULL, seller_id TEXT NOT NULL, listing_id UUID, text TEXT NOT NULL DEFAULT '', price BIGINT, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE TABLE IF NOT EXISTS market_spotlight (id UUID PRIMARY KEY, listing_id UUID NOT NULL, seller_id TEXT NOT NULL, starts_at TIMESTAMPTZ NOT NULL DEFAULT now(), ends_at TIMESTAMPTZ NOT NULL, days INT NOT NULL,
      paid BIGINT NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'active', views INT NOT NULL DEFAULT 0, clicks INT NOT NULL DEFAULT 0, granted_by TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE TABLE IF NOT EXISTS market_alerts (id UUID PRIMARY KEY, user_id TEXT NOT NULL, category TEXT, subcategory TEXT, q TEXT, lat DOUBLE PRECISION, lng DOUBLE PRECISION, radius_km INT NOT NULL DEFAULT 25,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE TABLE IF NOT EXISTS market_views (listing_id UUID NOT NULL, user_id TEXT NOT NULL, day DATE NOT NULL, PRIMARY KEY (listing_id, user_id, day));
  `);
  // إخفاء الإشراف (safety.js): الأسئلة والتقييمات وردود الطلبات والفعاليات تُخفى بعمود مستقل لا يملكه صاحبها
  await pool.query(`
    ALTER TABLE market_reviews ADD COLUMN IF NOT EXISTS hidden BOOLEAN NOT NULL DEFAULT false;
    ALTER TABLE market_questions ADD COLUMN IF NOT EXISTS hidden BOOLEAN NOT NULL DEFAULT false;
    ALTER TABLE market_wanted_replies ADD COLUMN IF NOT EXISTS hidden BOOLEAN NOT NULL DEFAULT false;
    ALTER TABLE events ADD COLUMN IF NOT EXISTS hidden BOOLEAN NOT NULL DEFAULT false;
  `);
  try { await pool.query(String.raw`UPDATE market_listings SET image_url = regexp_replace(image_url, '^(https?://)www\.', '\1', 'i') WHERE image_url ~* '^https?://www\.'`); } catch { /* عمود غير موجود أو جدول قديم */ }

  const unauthorized = (reply) => reply.code(401).send({ error: "auth" });
  const bad = (reply, code, error, extra = {}) => reply.code(code).send({ error, ...extra });
  // تصفح الضيف (مراجِع المتجر يرى المحتوى قبل التسجيل): القراءة العامة بلا جلسة، والكتابة والقوائم الشخصية تبقى بجلسة
  const optionalAuth = async (req) => { try { return (await auth(req)) || null; } catch { return null; } };
  // عميل iOS الأصلي يرسل x-naslife-client: ios/<version>؛ لا تحويلات ولا شحن تجريبي فيه (قواعد آبل للمدفوعات)
  const iosNative = (req) => /^ios\//i.test(String(req.headers["x-naslife-client"] ?? ""));
  const blockedIds = async (uid) => { try { return uid ? (await globalThis.naslifeBlockedIds?.(uid)) ?? [] : []; } catch { return []; } };
  const bannedIn = (...texts) => { try { return globalThis.naslifeCheckText?.(...texts.filter((t) => typeof t === "string")) ?? null; } catch { return null; } };
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
    if (iosNative(req) && !(await isAdmin(uid))) return bad(reply, 403, "unavailable");
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
  // تحويل بين محفظتين (يستخدمه المسار أدناه وإضافة رموز المحادثة عبر globalThis.naslifeWalletTransfer)؛ الأخطاء تحمل code:
  // bad-recipient | bad-amount | suspended | not-found | insufficient-funds
  async function transfer({ from, to, amount, note = "", ref = null }) {
    amount = SAR(amount); note = String(note ?? "").slice(0, 120);
    const fail = (code) => Object.assign(new Error(code), { code });
    if (!ID_RE.test(to ?? "") || !ID_RE.test(from ?? "") || to === from) throw fail("bad-recipient");
    if (amount <= 0) throw fail("bad-amount");
    if (await isSuspended(from)) throw fail("suspended");
    const recipient = await userRow(to);
    if (!recipient || recipient.deleted_at || recipient.deleted === true) throw fail("not-found");
    await tx(async (c) => {
      await ledger(c, from, "transfer_out", -amount, { peerId: to, note, ref });
      await ledger(c, to, "transfer_in", amount, { peerId: from, note, ref });
    });
    await notify(to, { kind: "transfer_in", title: "وصلك تحويل", body: `${await nickOf(from)} حوّل لك ${sar(amount)}${note ? " · " + note : ""}`, data: { from, amount } });
    return { ok: true, amount };
  }
  globalThis.naslifeWalletTransfer = transfer;
  app.post("/wallet/transfer", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    // مفتاح المنصة transfersEnabled (قرار المالك التنظيمي) ولا تحويلات في عميل iOS
    if (globalThis.naslifeSettings?.transfersEnabled === false || iosNative(req)) return bad(reply, 403, "unavailable");
    const { to } = req.body ?? {};
    try {
      await transfer({ from: uid, to, amount: req.body?.amount, note: req.body?.note });
    } catch (e) {
      switch (e.code) {
        case "bad-recipient": return bad(reply, 400, "bad-recipient");
        case "bad-amount": return bad(reply, 400, "bad-amount");
        case "suspended": return bad(reply, 403, "suspended");
        case "not-found": return bad(reply, 404, "not-found");
        case "insufficient-funds": return bad(reply, 402, "insufficient-funds");
        default: throw e;
      }
    }
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
    if (await isSuspended(uid)) return bad(reply, 403, "suspended");
    const bannedE = bannedIn(title, String(b.description ?? ""), b.placeName ? String(b.placeName) : "", ...tiers.flatMap((t) => [String(t?.name ?? ""), String(t?.description ?? "")]));
    if (bannedE) return bad(reply, 400, "banned-words", { word: bannedE });
    // التذكرة المدفوعة لفعالية حضورية فقط (مكان أو إحداثيات)، فلا تُباع محتويات رقمية عبر المحفظة
    const hasPlace = !!String(b.placeName ?? "").trim() || (Number.isFinite(lat) && Number.isFinite(lng) && lat !== null && lng !== null);
    if (tiers.some((t) => SAR(t?.price) > 0) && !hasPlace) return bad(reply, 400, "place-required");
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
    const uid = await optionalAuth(req);
    const bb = bbox(req.query?.bbox); const mine = req.query?.mine === "1"; const vessel = UUID_RE.test(req.query?.vessel ?? "") ? req.query.vessel : null;
    if (mine && !uid) return unauthorized(reply);
    // الفعاليات المخفية بالإشراف ومضيفوها المحظورون لا تظهر في القوائم العامة
    const blocked = await blockedIds(uid);
    const r = mine
      ? await pool.query("SELECT * FROM events WHERE host_id=$1 ORDER BY starts_at DESC LIMIT 100", [uid])
      : vessel
        ? await pool.query("SELECT * FROM events WHERE vessel_id=$1 AND NOT cancelled AND NOT hidden AND NOT (host_id = ANY($2::text[])) ORDER BY starts_at LIMIT 100", [vessel, blocked])
        : bb
          ? await pool.query("SELECT * FROM events WHERE NOT cancelled AND NOT hidden AND NOT (host_id = ANY($5::text[])) AND starts_at > now() - interval '6 hours' AND lat BETWEEN $2 AND $4 AND lng BETWEEN $1 AND $3 ORDER BY starts_at LIMIT 100", [bb.minLng, bb.minLat, bb.maxLng, bb.maxLat, blocked])
          : await pool.query("SELECT * FROM events WHERE NOT cancelled AND NOT hidden AND NOT (host_id = ANY($1::text[])) AND starts_at > now() - interval '6 hours' ORDER BY starts_at LIMIT 100", [blocked]);
    return Promise.all(r.rows.map((e) => eventOut(e, uid)));
  });
  app.get("/events/:id", async (req, reply) => {
    const uid = await optionalAuth(req);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const r = await pool.query("SELECT * FROM events WHERE id=$1", [req.params.id]);
    if (!r.rowCount) return bad(reply, 404, "not-found");
    const e = r.rows[0];
    if (e.host_id !== uid && (e.hidden || (await blockedIds(uid)).includes(e.host_id)) && !(await isAdmin(uid))) return bad(reply, 404, "not-found");
    return eventOut(e, uid);
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
        if (!ev || ev.cancelled || ev.hidden) throw Object.assign(new Error(), { code: "not-found" });
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

  // ---- السوق (النسخة الثانية): صور متعددة، تصنيفات فرعية، خيارات ومخزون، مواعيد للخدمات، بحث بالقرب والفلاتر،
  // طلب بمراحل ورمز تسليم، كوبونات، عمولة للمنصة، نزاعات. الميزات التكميلية (سبوت لايت، تقييمات، بائعون…) في market_plus.js
  const PLATFORM = String(process.env.PLATFORM_ACCOUNT_ID ?? "SA0000000");
  const settingsOf = () => globalThis.naslifeSettings ?? {};
  const commissionPct = () => { const v = Number(settingsOf().marketCommissionPct); return Number.isFinite(v) && v >= 0 && v <= 30 ? v : 0; };
  const CONTACT_RE = /(\+?966|\b0)5\d{8}\b|https?:\/\/|www\.|wa\.me|t\.me|instagram\.com|snapchat\.com|tiktok\.com|@[a-z0-9_.]{4,}/i;
  const hasContact = (...texts) => settingsOf().marketBlockContacts !== false && texts.some((t) => CONTACT_RE.test(String(t ?? "")));
  const cache = { at: 0, map: new Map() };
  const sellerStats = async (id) => {
    if (Date.now() - cache.at > 60000) {
      try { const r = await pool.query("SELECT * FROM market_seller_stats"); cache.map = new Map(r.rows.map((x) => [x.seller_id, x])); } catch { /* الجدول يُنشأ لاحقاً */ }
      cache.at = Date.now();
    }
    return cache.map.get(id) ?? null;
  };
  globalThis.naslifeMarketStatsDirty = () => { cache.at = 0; };
  const imagesOf = (l) => { const a = Array.isArray(l.images) ? l.images.filter((u) => typeof u === "string" && u) : []; return a.length ? a : (l.image_url ? [l.image_url] : []); };
  const round1 = (v) => Math.round(v * 10) / 10;
  const listingOut = async (l, uid, { dist = null } = {}) => {
    const s = await sellerStats(l.seller_id); const imgs = imagesOf(l);
    const spot = l.spotlight_until && new Date(l.spotlight_until) > new Date();
    return {
      id: l.id, seller: await person(l.seller_id), sellerRating: s?.rating_avg == null ? null : Number(s.rating_avg), sellerRatingCount: s?.rating_count ?? 0, sellerBadges: Array.isArray(s?.badges) ? s.badges : [],
      kind: l.kind, category: l.category, subcategory: l.subcategory ?? null, condition: l.condition ?? null, delivery: l.delivery === true, title: l.title, description: l.description,
      price: Number(l.price), imageUrl: imgs[0] ?? null, images: imgs, placeName: l.place_name, city: l.city ?? null, lat: l.lat, lng: l.lng, status: l.status,
      stock: l.stock == null ? null : Number(l.stock), sold: Number(l.sold ?? 0), views: Number(l.views ?? 0), variants: Array.isArray(l.variants) ? l.variants : [], availability: l.availability ?? null,
      publishAt: l.publish_at ?? null, bumpedAt: l.bumped_at ?? l.created_at, spotlight: !!spot, spotlightUntil: spot ? l.spotlight_until : null,
      ratingAvg: l.rating_avg == null ? null : Number(l.rating_avg), ratingCount: Number(l.rating_count ?? 0), distanceKm: dist == null || !Number.isFinite(Number(dist)) ? null : round1(Number(dist)),
      createdAt: l.created_at, updatedAt: l.updated_at ?? l.created_at, mine: l.seller_id === uid,
    };
  };
  globalThis.naslifeMarketListingOut = listingOut;
  // الأصل العام للروابط المطلقة: PUBLIC_BASE_URL إن ضُبط، وإلا مضيف الطلب بلا "www." — الموقع يُقدَّم على naslife.app
  // وwww.naslife.app معاً، وسياسة CSP تقبل الوسائط من الأصل ذاته فقط، فرابط بمضيف يخالف صفحة المستخدم لا يُعرض.
  const publicOrigin = (req) => {
    const env = String(process.env.PUBLIC_BASE_URL ?? process.env.NASLIFE_PUBLIC_URL ?? "").trim().replace(/\/+$/, "");
    if (/^https?:\/\//i.test(env)) return env;
    const proto = String(req.headers["x-forwarded-proto"] ?? "https").split(",")[0].trim() || "https";
    const host = String(req.headers["x-forwarded-host"] ?? req.headers.host ?? "naslife.app").split(",")[0].trim().replace(/^www\./i, "");
    return `${proto}://${host}`;
  };
  const OWN_MEDIA = /^https?:\/\/[^/]+(\/(?:chat\/media|files|media|uploads|seed)\/.*)$/i;
  const absUrl = (req, url) => {
    const s = String(url ?? "").trim().slice(0, 500); if (!s) return null;
    const own = OWN_MEDIA.exec(s); if (own) return `${publicOrigin(req)}${own[1]}`;
    if (/^https?:\/\//i.test(s)) return s;
    if (!s.startsWith("/")) return null;
    return `${publicOrigin(req)}${s}`;
  };
  const parseImages = (req, b) => {
    const list = Array.isArray(b.images) ? b.images : (b.imageUrl ? [b.imageUrl] : []);
    return [...new Set(list.map((u) => absUrl(req, u)).filter(Boolean))].slice(0, 8);
  };
  const parseVariants = (v) => (Array.isArray(v) ? v : []).slice(0, 12)
    .map((x) => ({ name: String(x?.name ?? "").trim().slice(0, 40), price: Math.max(0, SAR(x?.price)), stock: x?.stock == null || x.stock === "" ? null : Math.max(0, Math.floor(Number(x.stock) || 0)) }))
    .filter((x) => x.name);
  const parseAvailability = (a) => {
    if (!a || typeof a !== "object") return null;
    const days = [...new Set((Array.isArray(a.days) ? a.days : []).map(Number).filter((d) => Number.isInteger(d) && d >= 0 && d <= 6))].sort();
    const t = (s) => (/^([01]\d|2[0-3]):[0-5]\d$/.test(String(s ?? "")) ? String(s) : null);
    const from = t(a.from), to = t(a.to); if (!days.length || !from || !to || from >= to) return null;
    return { days, from, to, slotMinutes: Math.min(240, Math.max(15, Math.floor(Number(a.slotMinutes) || 60))) };
  };
  // هل الموعد داخل أوقات الخدمة؟ (التوقيت المحلي للسعودية UTC+3)
  const slotOk = (av, d) => {
    const local = new Date(d.getTime() + 3 * 3600000); const day = local.getUTCDay();
    const hm = `${String(local.getUTCHours()).padStart(2, "0")}:${String(local.getUTCMinutes()).padStart(2, "0")}`;
    return av.days.includes(day) && hm >= av.from && hm < av.to && d.getTime() > Date.now();
  };
  const stockInt = (v) => (v == null || v === "" ? null : Math.max(0, Math.floor(Number(v) || 0)));
  const accountAgeHours = async (uid) => { const u = await userRow(uid); const t = u?.created_at ? new Date(u.created_at).getTime() : 0; return t ? (Date.now() - t) / 3600000 : 1e9; };

  app.post("/market", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (await isSuspended(uid)) return bad(reply, 403, "suspended");
    const b = req.body ?? {};
    const title = String(b.title ?? "").trim(); if (!title || title.length > 100) return bad(reply, 400, "bad-title");
    const description = String(b.description ?? "").slice(0, 2000);
    const kind = b.kind === "service" ? "service" : "product";
    const category = CATEGORY_SET.has(b.category) ? b.category : "other";
    const subcategory = subOk(category, b.subcategory) ? b.subcategory : null;
    const price = SAR(b.price); if (price < 0) return bad(reply, 400, "bad-price");
    const banned = globalThis.naslifeCheckText?.(title, description, b.placeName);
    if (banned) return reply.code(400).send({ error: "banned-words", word: banned });
    if (hasContact(title, description)) return bad(reply, 400, "contact-in-text");
    const guard = await globalThis.naslifeMarketGuard?.(uid, { title, price });
    if (guard) return bad(reply, 429, guard);
    const publishAt = b.publishAt ? new Date(b.publishAt) : null;
    const scheduled = publishAt && !Number.isNaN(publishAt.getTime()) && publishAt.getTime() > Date.now() + 60000;
    const needsReview = settingsOf().marketReviewNewAccounts === true && (await accountAgeHours(uid)) < 24 * 7 && !(await isAdmin(uid));
    const status = b.status === "draft" ? "draft" : scheduled ? "scheduled" : needsReview ? "pending" : "active";
    const imgs = parseImages(req, b); const id = crypto.randomUUID();
    await pool.query(`INSERT INTO market_listings(id,seller_id,kind,category,subcategory,condition,delivery,title,description,price,image_url,images,place_name,city,lat,lng,status,stock,variants,availability,publish_at,bumped_at)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,now())`,
      [id, uid, kind, category, subcategory, CONDITIONS.has(b.condition) ? b.condition : null, b.delivery === true, title, description, price, imgs[0] ?? null, JSON.stringify(imgs),
       b.placeName ? String(b.placeName).slice(0, 80) : null, b.city ? String(b.city).slice(0, 40) : null, b.lat == null ? null : Number(b.lat), b.lng == null ? null : Number(b.lng),
       status, stockInt(b.stock), JSON.stringify(parseVariants(b.variants)), b.availability ? JSON.stringify(parseAvailability(b.availability)) : null, scheduled ? publishAt : null]);
    const row = (await pool.query("SELECT * FROM market_listings WHERE id=$1", [id])).rows[0];
    if (status === "active") globalThis.naslifeMarketOnPublish?.(row).catch?.(() => {});
    if (status === "pending") globalThis.naslifeNotifyAdmins?.({ kind: "market_pending", title: "عرض بانتظار المراجعة", body: `${await nickOf(uid)}: ${title}`, data: { listingId: id } }).catch?.(() => {});
    return listingOut(row, uid);
  });

  // البحث: نص، تصنيف وفرعي، نوع، سعر من/إلى، توصيل، حالة، بائع، قرب (lat/lng/radius كم) وترتيب، وصفحات
  app.get("/market", async (req, reply) => {
    const uid = await optionalAuth(req);
    const qy = req.query ?? {};
    const q = String(qy.q ?? "").trim().slice(0, 60);
    const cat = CATEGORY_SET.has(qy.category) ? qy.category : null;
    const sub = cat && subOk(cat, qy.sub) ? qy.sub : null;
    const kind = ["product", "service"].includes(qy.kind) ? qy.kind : null;
    const min = qy.min != null && qy.min !== "" ? SAR(qy.min) : null, max = qy.max != null && qy.max !== "" ? SAR(qy.max) : null;
    const condition = CONDITIONS.has(qy.condition) ? qy.condition : null;
    const lat = Number(qy.lat), lng = Number(qy.lng); const hasPos = Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180;
    const radius = Math.min(1000, Math.max(0, Number(qy.radius) || 0)) || null;
    const sort = SORTS.has(qy.sort) ? qy.sort : (hasPos ? "near" : "new");
    const seller = ID_RE.test(String(qy.seller ?? "")) ? String(qy.seller) : null;
    const limit = Math.min(100, Math.max(1, Number(qy.limit) || 60)), offset = Math.max(0, Number(qy.offset) || 0);
    const bb = bbox(qy.bbox);
    const where = ["status='active'", "(publish_at IS NULL OR publish_at <= now())"]; const params = [];
    const p = (v) => { params.push(v); return `$${params.length}`; };
    if (q) { const t = p(`%${q}%`); where.push(`(title ILIKE ${t} OR description ILIKE ${t} OR place_name ILIKE ${t} OR city ILIKE ${t})`); }
    if (cat) where.push(`category=${p(cat)}`); if (sub) where.push(`subcategory=${p(sub)}`); if (kind) where.push(`kind=${p(kind)}`);
    if (min != null) where.push(`price >= ${p(min)}`); if (max != null) where.push(`price <= ${p(max)}`);
    if (qy.delivery === "1") where.push("delivery = true"); if (condition) where.push(`condition=${p(condition)}`); if (seller) where.push(`seller_id=${p(seller)}`);
    if (qy.spotlight === "1") where.push("spotlight_until > now()");
    const blocked = await blockedIds(uid);
    if (blocked.length) where.push(`NOT (seller_id = ANY(${p(blocked)}::text[]))`);
    if (bb) where.push(`(lat BETWEEN ${p(bb.minLat)} AND ${p(bb.maxLat)} AND lng BETWEEN ${p(bb.minLng)} AND ${p(bb.maxLng)})`);
    let dist = "NULL::float8";
    if (hasPos) {
      const la = p(lat), ln = p(lng);
      // least() يتجاهل NULL فيصبح acos(1)=0 للعروض بلا موقع؛ لذا نستثنيها صراحة
      dist = `(CASE WHEN lat IS NULL OR lng IS NULL THEN NULL ELSE 6371 * acos(least(1::float8, cos(radians(${la})) * cos(radians(lat)) * cos(radians(lng) - radians(${ln})) + sin(radians(${la})) * sin(radians(lat)))) END)`;
      if (radius) where.push(`lat IS NOT NULL AND ${dist} <= ${p(radius)}`);
    }
    const order = {
      near: hasPos ? `${dist} ASC NULLS LAST, bumped_at DESC` : "bumped_at DESC NULLS LAST", new: "bumped_at DESC NULLS LAST, created_at DESC", cheap: "price ASC, bumped_at DESC",
      expensive: "price DESC, bumped_at DESC", popular: "(sold * 3 + views) DESC, bumped_at DESC", rated: "rating_avg DESC NULLS LAST, rating_count DESC, bumped_at DESC",
    }[sort];
    const r = await pool.query(`SELECT *, ${dist} AS dist FROM market_listings WHERE ${where.join(" AND ")} ORDER BY ${order} LIMIT ${p(limit)} OFFSET ${p(offset)}`, params);
    return Promise.all(r.rows.map((l) => listingOut(l, uid, { dist: l.dist })));
  });
  // عروضي كلها: الظاهرة والمسودات والمجدولة وقيد المراجعة والمخفية وما أخفته الإدارة
  app.get("/market/mine", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const r = await pool.query("SELECT * FROM market_listings WHERE seller_id=$1 ORDER BY (status='active') DESC, bumped_at DESC NULLS LAST, created_at DESC", [uid]);
    return Promise.all(r.rows.map((l) => listingOut(l, uid)));
  });
  // تعديل عرضي: النصوص والسعر والصور والخيارات والمخزون والمواعيد، وحالته (ظاهر/مخفي/مسودة) ما لم تكن الإدارة قد أخفته
  app.patch("/market/:id", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const l = (await pool.query("SELECT * FROM market_listings WHERE id=$1", [req.params.id])).rows[0];
    if (!l) return bad(reply, 404, "not-found");
    if (l.seller_id !== uid) return bad(reply, 403, "forbidden");
    const b = req.body ?? {}; const sets = []; const vals = [];
    const set = (c, v) => { vals.push(v); sets.push(`${c}=$${vals.length}`); };
    const bannedP = globalThis.naslifeCheckText?.(b.title, b.description, b.placeName);
    if (bannedP) return reply.code(400).send({ error: "banned-words", word: bannedP });
    if (hasContact(b.title, b.description)) return bad(reply, 400, "contact-in-text");
    if (b.title !== undefined) { const t = String(b.title).trim(); if (!t || t.length > 100) return bad(reply, 400, "bad-title"); set("title", t); }
    if (b.description !== undefined) set("description", String(b.description).slice(0, 2000));
    if (b.price !== undefined) { const pr = SAR(b.price); if (pr < 0) return bad(reply, 400, "bad-price"); set("price", pr); }
    const category = b.category !== undefined ? (CATEGORY_SET.has(b.category) ? b.category : "other") : l.category;
    if (b.category !== undefined) set("category", category);
    if (b.subcategory !== undefined || b.category !== undefined) set("subcategory", subOk(category, b.subcategory ?? l.subcategory) ? (b.subcategory ?? l.subcategory) : null);
    if (b.kind !== undefined) set("kind", b.kind === "service" ? "service" : "product");
    if (b.condition !== undefined) set("condition", CONDITIONS.has(b.condition) ? b.condition : null);
    if (b.delivery !== undefined) set("delivery", b.delivery === true);
    if (b.images !== undefined || b.imageUrl !== undefined) { const imgs = parseImages(req, b); set("images", JSON.stringify(imgs)); set("image_url", imgs[0] ?? null); }
    if (b.placeName !== undefined) set("place_name", b.placeName ? String(b.placeName).slice(0, 80) : null);
    if (b.city !== undefined) set("city", b.city ? String(b.city).slice(0, 40) : null);
    if (b.lat !== undefined) set("lat", b.lat == null ? null : Number(b.lat)); if (b.lng !== undefined) set("lng", b.lng == null ? null : Number(b.lng));
    if (b.stock !== undefined) set("stock", stockInt(b.stock));
    if (b.variants !== undefined) set("variants", JSON.stringify(parseVariants(b.variants)));
    if (b.availability !== undefined) set("availability", b.availability ? JSON.stringify(parseAvailability(b.availability)) : null);
    if (b.publishAt !== undefined) { const d = b.publishAt ? new Date(b.publishAt) : null; set("publish_at", d && !Number.isNaN(d.getTime()) ? d : null); }
    let publishNow = false;
    if (b.status !== undefined) {
      if (!["active", "hidden", "draft"].includes(b.status)) return bad(reply, 400, "bad-status");
      if (l.status === "blocked") return bad(reply, 403, "blocked");
      if (l.status === "pending" && b.status === "active") return bad(reply, 409, "pending-review");
      set("status", b.status); publishNow = b.status === "active" && l.status !== "active";
      if (publishNow) set("bumped_at", new Date());
    }
    if (!sets.length) return bad(reply, 400, "empty");
    set("updated_at", new Date()); vals.push(l.id);
    await pool.query(`UPDATE market_listings SET ${sets.join(", ")} WHERE id=$${vals.length}`, vals);
    const row = (await pool.query("SELECT * FROM market_listings WHERE id=$1", [l.id])).rows[0];
    if (publishNow) globalThis.naslifeMarketOnPublish?.(row).catch?.(() => {});
    return listingOut(row, uid);
  });
  // رفع العرض إلى الأعلى مرة كل ٢٤ ساعة
  app.post("/market/:id/bump", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const l = (await pool.query("SELECT * FROM market_listings WHERE id=$1 AND seller_id=$2", [req.params.id, uid])).rows[0];
    if (!l) return bad(reply, 404, "not-found");
    if (l.status !== "active") return bad(reply, 409, "not-active");
    const last = l.bumped_at ? new Date(l.bumped_at).getTime() : 0;
    if (Date.now() - last < 24 * 3600000) return bad(reply, 429, "bump-too-soon", { nextAt: new Date(last + 24 * 3600000) });
    await pool.query("UPDATE market_listings SET bumped_at=now() WHERE id=$1", [l.id]);
    return { ok: true };
  });
  const orderOut = async (o, uid) => ({
    id: o.id, listingId: o.listing_id, title: o.title, imageUrl: o.image_url, kind: o.kind ?? null, qty: o.qty, total: Number(o.total), discount: Number(o.discount ?? 0), coupon: o.coupon ?? null,
    commission: o.seller_id === uid || (await isAdmin(uid)) ? Number(o.commission ?? 0) : null, status: o.status, note: o.note, variant: o.variant ?? null, slot: o.slot ?? null,
    code: o.buyer_id === uid ? o.code ?? null : null, buyer: await person(o.buyer_id), seller: await person(o.seller_id), mineAsSeller: o.seller_id === uid,
    courier: o.courier_id ? await person(o.courier_id) : null, courierNote: o.courier_note ?? "", mineAsCourier: !!o.courier_id && o.courier_id === uid,
    deliveredAt: o.delivered_at ?? null, completedAt: o.completed_at ?? null, disputeStatus: o.dispute_status ?? null, disputeReason: o.dispute_reason ?? null, disputeNote: o.dispute_note ?? null,
    reviewed: o.reviewed === true, createdAt: o.created_at, updatedAt: o.updated_at,
  });
  globalThis.naslifeMarketOrderOut = orderOut;
  const ORDER_SQL = "SELECT o.*, l.title, l.image_url, l.kind, (r.order_id IS NOT NULL) AS reviewed FROM market_orders o JOIN market_listings l ON l.id=o.listing_id LEFT JOIN market_reviews r ON r.order_id=o.id";
  app.get("/market/orders", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const r = await pool.query(`${ORDER_SQL} WHERE o.buyer_id=$1 OR o.seller_id=$1 OR o.courier_id=$1 ORDER BY o.created_at DESC LIMIT 200`, [uid]);
    return Promise.all(r.rows.map((o) => orderOut(o, uid)));
  });
  app.get("/market/orders/:id", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const o = (await pool.query(`${ORDER_SQL} WHERE o.id=$1`, [req.params.id])).rows[0];
    if (!o) return bad(reply, 404, "not-found");
    if (o.buyer_id !== uid && o.seller_id !== uid && o.courier_id !== uid && !(await isAdmin(uid))) return bad(reply, 403, "forbidden");
    return orderOut(o, uid);
  });
  app.get("/market/:id", async (req, reply) => {
    const uid = await optionalAuth(req);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const r = await pool.query("SELECT * FROM market_listings WHERE id=$1", [req.params.id]);
    if (!r.rowCount) return bad(reply, 404, "not-found");
    const l = r.rows[0];
    if (!["active"].includes(l.status) && l.seller_id !== uid && !(await isAdmin(uid))) return bad(reply, 404, "not-found");
    if (l.seller_id !== uid && (await blockedIds(uid)).includes(l.seller_id)) return bad(reply, 404, "not-found");
    return listingOut(l, uid);
  });
  app.delete("/market/:id", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    await pool.query("UPDATE market_listings SET status='hidden', updated_at=now() WHERE id=$1 AND seller_id=$2 AND status<>'blocked'", [req.params.id, uid]);
    return { ok: true };
  });
  // الطلب: خيار ومخزون وموعد وكوبون؛ المبلغ يُحجز من المشتري ولا يصل البائع إلا عند اكتمال الطلب (تأكيد الاستلام)
  app.post("/market/:id/order", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (await isSuspended(uid)) return bad(reply, 403, "suspended");
    const b = req.body ?? {};
    const qty = Math.max(1, Math.min(20, Number(b.qty) || 1)); const note = String(b.note ?? "").slice(0, 300);
    const variantName = String(b.variant ?? "").trim(); const couponCode = String(b.coupon ?? "").trim().toUpperCase().slice(0, 24);
    const slot = b.slot ? new Date(b.slot) : null;
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const l = (await pool.query("SELECT * FROM market_listings WHERE id=$1 AND status='active'", [req.params.id])).rows[0];
    if (!l) return bad(reply, 404, "not-found");
    if (l.seller_id === uid) return bad(reply, 400, "own-listing");
    // لا طلب بين طرفين بينهما حظر (بأي اتجاه)
    if ((await blockedIds(uid)).includes(l.seller_id)) return bad(reply, 404, "not-found");
    let unit = Number(l.price); let variant = null;
    const variants = Array.isArray(l.variants) ? l.variants : [];
    if (variants.length) {
      variant = variants.find((v) => v.name === variantName); if (!variant) return bad(reply, 400, "variant-required", { variants: variants.map((v) => v.name) });
      unit = Number(variant.price); if (variant.stock != null && Number(variant.stock) < qty) return bad(reply, 409, "out-of-stock");
    } else if (l.stock != null && Number(l.stock) < qty) return bad(reply, 409, "out-of-stock");
    if (l.kind === "service" && l.availability) {
      if (!slot || Number.isNaN(slot.getTime())) return bad(reply, 400, "slot-required");
      if (!slotOk(l.availability, slot)) return bad(reply, 400, "slot-unavailable");
      if ((await pool.query("SELECT 1 FROM market_orders WHERE listing_id=$1 AND slot=$2 AND status NOT IN ('cancelled','refunded')", [l.id, slot])).rowCount) return bad(reply, 409, "slot-taken");
    }
    const subtotal = unit * qty; let discount = 0; let coupon = null;
    if (couponCode) {
      const c = (await pool.query("SELECT * FROM market_coupons WHERE code=$1 AND seller_id=$2 AND active AND (expires_at IS NULL OR expires_at > now()) AND (max_uses IS NULL OR used < max_uses)", [couponCode, l.seller_id])).rows[0];
      if (!c) return bad(reply, 400, "bad-coupon");
      if (subtotal < Number(c.min_total ?? 0)) return bad(reply, 400, "coupon-min", { minTotal: Number(c.min_total) });
      discount = c.percent != null ? Math.floor(subtotal * Number(c.percent) / 100) : Math.min(subtotal, Number(c.amount ?? 0)); coupon = c.code;
    }
    const total = Math.max(0, subtotal - discount); const commission = Math.floor(total * commissionPct() / 100);
    const id = crypto.randomUUID(); const code = String(1000 + crypto.randomInt(9000));
    try {
      await tx(async (c) => {
        if (total > 0) await ledger(c, uid, "market", -total, { peerId: l.seller_id, ref: id, note: l.title, points: Math.floor(total / 1000) });
        await c.query("INSERT INTO market_orders(id,listing_id,buyer_id,seller_id,qty,total,note,code,variant,coupon,discount,commission,slot) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)",
          [id, l.id, uid, l.seller_id, qty, total, note, code, variant?.name ?? null, coupon, discount, commission, slot && !Number.isNaN(slot.getTime()) ? slot : null]);
        if (variant) await c.query(`UPDATE market_listings SET variants = (SELECT COALESCE(jsonb_agg(CASE WHEN v->>'name'=$2 AND (v->>'stock') IS NOT NULL THEN jsonb_set(v, '{stock}', to_jsonb(GREATEST(0, (v->>'stock')::int - $3))) ELSE v END), '[]'::jsonb) FROM jsonb_array_elements(variants) v), sold=sold+$3, updated_at=now() WHERE id=$1`, [l.id, variant.name, qty]);
        else await c.query("UPDATE market_listings SET stock = CASE WHEN stock IS NULL THEN NULL ELSE GREATEST(0, stock-$2) END, sold=sold+$2, updated_at=now() WHERE id=$1", [l.id, qty]);
        if (coupon) await c.query("UPDATE market_coupons SET used=used+1 WHERE code=$1 AND seller_id=$2", [coupon, l.seller_id]);
      });
    } catch (e) { if (e.code === "insufficient-funds") return bad(reply, 402, "insufficient-funds"); throw e; }
    await notify(l.seller_id, { kind: "market_order", title: "طلب جديد في السوق", body: `${await nickOf(uid)} طلب ${l.title}${variant ? " (" + variant.name + ")" : ""}${qty > 1 ? " × " + qty : ""} بقيمة ${sar(total)}${note ? " · " + note.slice(0, 80) : ""}`, data: { orderId: id, listingId: l.id } });
    return { ok: true, id, total, discount, commission, code };
  });
  const loadOrder = async (id) => (await pool.query(`${ORDER_SQL} WHERE o.id=$1`, [id])).rows[0] ?? null;
  const STAGE_LABEL = { preparing: "قيد التحضير", on_the_way: "في الطريق", delivered: "تم التسليم" };
  // تقدّم البائع بالطلب عبر المراحل (للأمام فقط)؛ «تم التسليم» ينتظر تأكيد المشتري أو رمزه، ويكتمل تلقائياً بعد ٧٢ ساعة
  const advance = async (req, reply, stage) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const o = await loadOrder(req.params.id); if (!o) return bad(reply, 404, "not-found");
    // المندوب المعيَّن يستطيع نقل الطلب إلى «في الطريق» و«تم التسليم» فقط
    const asCourier = !!o.courier_id && o.courier_id === uid && o.seller_id !== uid;
    if (o.seller_id !== uid && !asCourier) return bad(reply, 403, "seller-only");
    if (asCourier && !["on_the_way", "delivered"].includes(stage)) return bad(reply, 403, "courier-stage");
    const from = ORDER_STAGES.indexOf(o.status), to = ORDER_STAGES.indexOf(stage);
    if (from < 0 || to <= from || to >= ORDER_STAGES.indexOf("completed")) return bad(reply, 409, "bad-status");
    await pool.query(`UPDATE market_orders SET status=$2, updated_at=now(), accepted_at=COALESCE(accepted_at, now())${stage === "delivered" ? ", delivered_at=now()" : ""} WHERE id=$1`, [o.id, stage]);
    await notify(o.buyer_id, { kind: "market_status", title: `طلبك: ${STAGE_LABEL[stage]}`, body: stage === "delivered" ? `${o.title}: أكد البائع التسليم. أكّد الاستلام من صفحة الطلب أو أعطه رمزك ${o.code}` : `${o.title}: ${STAGE_LABEL[stage]}`, data: { orderId: o.id, status: stage } });
    return { ok: true, status: stage };
  };
  app.post("/market/orders/:id/stage", async (req, reply) => advance(req, reply, ["preparing", "on_the_way", "delivered"].includes(req.body?.stage) ? req.body.stage : "delivered"));
  app.post("/market/orders/:id/deliver", async (req, reply) => advance(req, reply, "delivered"));
  // اكتمال الطلب وتحرير المبلغ للبائع بعد خصم العمولة (تُقيَّد لحساب المنصة)
  const complete = async (o, { by = "buyer" } = {}) => {
    const net = Number(o.total) - Number(o.commission ?? 0);
    await tx(async (c) => {
      const r = await c.query("UPDATE market_orders SET status='completed', completed_at=now(), updated_at=now() WHERE id=$1 AND status IN ('paid','preparing','on_the_way','delivered') RETURNING id", [o.id]);
      if (!r.rowCount) throw Object.assign(new Error("bad-status"), { code: "bad-status" });
      if (net > 0) await ledger(c, o.seller_id, "market_sale", net, { peerId: o.buyer_id, ref: o.id, note: o.title });
      if (Number(o.commission) > 0) await ledger(c, PLATFORM, "commission", Number(o.commission), { peerId: o.seller_id, ref: o.id, note: o.title });
    });
    globalThis.naslifeMarketOnComplete?.(o).catch?.(() => {});
    await notify(o.seller_id, { kind: "market_status", title: "اكتمل الطلب ووصلك المبلغ", body: `${o.title}: ${sar(net)}${Number(o.commission) > 0 ? " بعد عمولة " + sar(o.commission) : ""}${by === "auto" ? " (اكتمال تلقائي)" : ""}`, data: { orderId: o.id, status: "completed" } });
    if (by !== "buyer") await notify(o.buyer_id, { kind: "market_status", title: "اكتمل طلبك", body: `${o.title}: يمكنك الآن تقييم البائع`, data: { orderId: o.id, status: "completed" } });
  };
  app.post("/market/orders/:id/confirm", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const o = await loadOrder(req.params.id); if (!o) return bad(reply, 404, "not-found");
    const isBuyer = o.buyer_id === uid, isSeller = o.seller_id === uid;
    if (!isBuyer && !isSeller) return bad(reply, 403, "forbidden");
    if (!["paid", "preparing", "on_the_way", "delivered"].includes(o.status)) return bad(reply, 409, "bad-status");
    if (isSeller && String(req.body?.code ?? "").trim() !== String(o.code)) return bad(reply, 400, "bad-code");
    try { await complete(o, { by: isBuyer ? "buyer" : "seller" }); } catch (e) { if (e.code === "bad-status") return bad(reply, 409, "bad-status"); throw e; }
    return { ok: true, status: "completed" };
  });
  const refund = async (o, { status = "cancelled", amount = null, note = null } = {}) => {
    const amt = amount == null ? Number(o.total) : amount;
    await tx(async (c) => {
      await c.query("UPDATE market_orders SET status=$2, dispute_status=CASE WHEN dispute_status IS NULL THEN NULL ELSE 'resolved' END, dispute_note=COALESCE($3, dispute_note), updated_at=now() WHERE id=$1", [o.id, status, note]);
      if (amt > 0) await ledger(c, o.buyer_id, "refund", amt, { peerId: o.seller_id, ref: o.id, note: o.title });
      // إرجاع المخزون والكوبون عند الإلغاء الكامل
      if (status === "cancelled") {
        if (o.variant) await c.query(`UPDATE market_listings SET variants = (SELECT COALESCE(jsonb_agg(CASE WHEN v->>'name'=$2 AND (v->>'stock') IS NOT NULL THEN jsonb_set(v, '{stock}', to_jsonb((v->>'stock')::int + $3)) ELSE v END), '[]'::jsonb) FROM jsonb_array_elements(variants) v), sold=GREATEST(0, sold-$3) WHERE id=$1`, [o.listing_id, o.variant, o.qty]);
        else await c.query("UPDATE market_listings SET stock = CASE WHEN stock IS NULL THEN NULL ELSE stock+$2 END, sold=GREATEST(0, sold-$2) WHERE id=$1", [o.listing_id, o.qty]);
        if (o.coupon) await c.query("UPDATE market_coupons SET used=GREATEST(0, used-1) WHERE code=$1 AND seller_id=$2", [o.coupon, o.seller_id]);
      }
    });
  };
  app.post("/market/orders/:id/cancel", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const o = await loadOrder(req.params.id); if (!o) return bad(reply, 404, "not-found");
    const byBuyer = o.buyer_id === uid;
    if (!byBuyer && o.seller_id !== uid) return bad(reply, 403, "forbidden");
    // المشتري يلغي قبل أن يبدأ البائع؛ البائع يلغي في أي مرحلة قبل الاكتمال
    if (byBuyer ? o.status !== "paid" : !["paid", "preparing", "on_the_way", "delivered"].includes(o.status)) return bad(reply, 409, "bad-status");
    await refund(o);
    await notify(byBuyer ? o.seller_id : o.buyer_id, { kind: "market_status", title: byBuyer ? "أُلغي طلب" : "أُلغي طلبك",
      body: byBuyer ? `${await nickOf(uid)} ألغى طلب ${o.title}` : `${o.title}: ألغى البائع الطلب${Number(o.total) > 0 ? " واستُرد " + sar(o.total) + " إلى محفظتك" : ""}`, data: { orderId: o.id, status: "cancelled" } });
    return { ok: true };
  });
  // نزاع من المشتري قبل الاكتمال: يتجمّد المبلغ حتى تحسمه الإدارة
  app.post("/market/orders/:id/dispute", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const o = await loadOrder(req.params.id); if (!o) return bad(reply, 404, "not-found");
    if (o.buyer_id !== uid) return bad(reply, 403, "buyer-only");
    if (!["paid", "preparing", "on_the_way", "delivered"].includes(o.status)) return bad(reply, 409, "bad-status");
    const reason = String(req.body?.reason ?? "").trim().slice(0, 600); if (reason.length < 5) return bad(reply, 400, "bad-reason");
    await pool.query("UPDATE market_orders SET status='disputed', dispute_status='open', dispute_reason=$2, updated_at=now() WHERE id=$1", [o.id, reason]);
    await notify(o.seller_id, { kind: "market_dispute", title: "نزاع على طلب", body: `${o.title}: ${reason.slice(0, 100)}`, data: { orderId: o.id } });
    globalThis.naslifeNotifyAdmins?.({ kind: "market_dispute", title: "نزاع جديد في السوق", body: `${o.title} (${sar(o.total)}): ${reason.slice(0, 100)}`, data: { orderId: o.id } }).catch?.(() => {});
    return { ok: true, status: "disputed" };
  });
  app.post("/adminapi/market/disputes/:id", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!(await isAdmin(uid))) return bad(reply, 403, "admin-only");
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const o = await loadOrder(req.params.id); if (!o) return bad(reply, 404, "not-found");
    if (o.status !== "disputed") return bad(reply, 409, "bad-status");
    const resolution = String(req.body?.resolution ?? ""); const note = String(req.body?.note ?? "").slice(0, 600) || null;
    const total = Number(o.total), commission = Number(o.commission ?? 0);
    if (resolution === "refund") await refund(o, { status: "refunded", note });
    else if (resolution === "release") {
      await tx(async (c) => {
        await c.query("UPDATE market_orders SET status='completed', completed_at=now(), dispute_status='resolved', dispute_note=$2, updated_at=now() WHERE id=$1", [o.id, note]);
        if (total - commission > 0) await ledger(c, o.seller_id, "market_sale", total - commission, { peerId: o.buyer_id, ref: o.id, note: o.title });
        if (commission > 0) await ledger(c, PLATFORM, "commission", commission, { peerId: o.seller_id, ref: o.id, note: o.title });
      });
    } else if (resolution === "split") {
      const half = Math.floor(total / 2);
      await tx(async (c) => {
        await c.query("UPDATE market_orders SET status='completed', completed_at=now(), dispute_status='resolved', dispute_note=$2, updated_at=now() WHERE id=$1", [o.id, note]);
        if (half > 0) await ledger(c, o.buyer_id, "refund", half, { peerId: o.seller_id, ref: o.id, note: o.title });
        if (total - half > 0) await ledger(c, o.seller_id, "market_sale", total - half, { peerId: o.buyer_id, ref: o.id, note: o.title });
      });
    } else return bad(reply, 400, "bad-resolution");
    const msg = { refund: "أُعيد المبلغ كاملاً للمشتري", release: "حُرِّر المبلغ للبائع", split: "قُسم المبلغ بين الطرفين" }[resolution];
    await notify([o.buyer_id, o.seller_id], { kind: "market_dispute", title: "حُسم النزاع", body: `${o.title}: ${msg}${note ? " · " + note : ""}`, data: { orderId: o.id } });
    return { ok: true, resolution };
  });
  // مسح دوري: نشر المجدول، واكتمال الطلبات المسلَّمة التي لم يؤكدها المشتري خلال ٧٢ ساعة
  const sweep = async () => {
    try {
      const due = (await pool.query("UPDATE market_listings SET status='active', bumped_at=now(), updated_at=now() WHERE status='scheduled' AND publish_at <= now() RETURNING *")).rows;
      for (const row of due) globalThis.naslifeMarketOnPublish?.(row).catch?.(() => {});
      const stale = (await pool.query(`${ORDER_SQL} WHERE o.status='delivered' AND o.delivered_at < now() - interval '72 hours' LIMIT 50`)).rows;
      for (const o of stale) { try { await complete(o, { by: "auto" }); } catch { /* تغيّرت حالته */ } }
    } catch (e) { app.log?.warn?.({ err: e?.message }, "market sweep failed"); }
  };
  if (process.env.NODE_ENV !== "test") setInterval(sweep, 5 * 60000).unref?.();
  globalThis.naslifeMarketSweep = sweep;
  globalThis.naslifeWallet = { ledger, tx, sar, person, nickOf, isAdmin, PLATFORM };
}
