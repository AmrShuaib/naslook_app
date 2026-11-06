// إضافة Fastify للتجارة في Naslife: المحفظة، الفعاليات والتذاكر، سوق الخدمات والمنتجات.
// التسجيل في src/index.js قبل app.listen (pool وauth معرّفان هناك):
//   await app.register((await import("./commerce.js")).default, { pool, auth });
// المبالغ بالهللة (عدد صحيح). الشحن الحقيقي عبر ميسر (server/market_b.js) أو من لوحة الإدارة (/adminapi/users/:id/credit في admin.js)،
// والشحن التجريبي (kind=test_topup) إذا WALLET_TEST_TOPUP=1 وما دامت بوابة الدفع ليست في الوضع الحي.
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
      ADD COLUMN IF NOT EXISTS courier_id TEXT, ADD COLUMN IF NOT EXISTS courier_note TEXT NOT NULL DEFAULT '', ADD COLUMN IF NOT EXISTS courier_at TIMESTAMPTZ,
      ADD COLUMN IF NOT EXISTS code_fails INT NOT NULL DEFAULT 0;
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
  // الدفع عند الاستلام (بند 10 من نواقص الإطلاق): البائع يسمح به على العرض، والطلب يحمل طريقة دفعه ولا يمر بالمحفظة.
  // cancel_reason يميّز اعتذار البائع وعدم حضور المشتري وانتهاء المهلة عن الإلغاء العادي (عدّاد «لم يحضر» يُحسب منه)
  await pool.query(`
    ALTER TABLE market_listings ADD COLUMN IF NOT EXISTS pay_on_receipt BOOLEAN NOT NULL DEFAULT false;
    ALTER TABLE market_orders ADD COLUMN IF NOT EXISTS payment TEXT NOT NULL DEFAULT 'wallet', ADD COLUMN IF NOT EXISTS cancel_reason TEXT, ADD COLUMN IF NOT EXISTS cash_received_at TIMESTAMPTZ;
    CREATE INDEX IF NOT EXISTS market_orders_buyer_cod ON market_orders(buyer_id, status) WHERE payment='cod';
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
  // إقرار 18+ قبل أول عملية مالية (legal_pages.js): 403 adult-required؛ غياب المساعد أو خطؤه لا يحجب المال
  const needsAdult = async (uid) => { try { const f = globalThis.naslifeAdultOk; return typeof f === "function" ? !(await f(uid)) : false; } catch { return false; } };
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
  // تعارض أقفال (40P01) أو تسلسل (40001) في Postgres يُعاد تنفيذه حتى ثلاث مرات بدل أن يصل للمستخدم خطأ 500
  const RETRY_SQL = new Set(["40P01", "40001"]);
  async function tx(fn) {
    for (let attempt = 1; ; attempt++) {
      const c = await pool.connect();
      try { await c.query("BEGIN"); const out = await fn(c); await c.query("COMMIT"); return out; }
      catch (e) {
        await c.query("ROLLBACK").catch(() => {});
        if (RETRY_SQL.has(e?.code) && attempt < 3) { await new Promise((r) => setTimeout(r, attempt === 1 ? 10 : 50)); continue; }
        throw e;
      }
      finally { c.release(); }
    }
  }
  const txRow = async (x) => ({ id: x.id, kind: x.kind, amount: Number(x.amount), peer: x.peer_id ? await person(x.peer_id) : null, ref: x.ref, note: x.note, createdAt: x.created_at });

  app.get("/wallet", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    await pool.query("INSERT INTO wallet_accounts(user_id) VALUES($1) ON CONFLICT DO NOTHING", [uid]);
    const a = (await pool.query("SELECT balance, points FROM wallet_accounts WHERE user_id=$1", [uid])).rows[0];
    const t = await pool.query("SELECT * FROM wallet_tx WHERE user_id=$1 ORDER BY created_at DESC LIMIT 10", [uid]);
    const tickets = (await pool.query("SELECT count(*)::int AS n FROM tickets t JOIN events e ON e.id=t.event_id WHERE t.user_id=$1 AND t.status='valid' AND e.starts_at > now() - interval '6 hours'", [uid])).rows[0].n;
    return { balance: Number(a.balance), points: a.points, currency: "SAR", upcomingTickets: tickets, recent: await Promise.all(t.rows.map(txRow)),
      testTopup: process.env.WALLET_TEST_TOPUP === "1", maxTopup: Number(globalThis.naslifeSettings?.maxTopup) || 10000000 };
  });
  app.get("/wallet/transactions", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const before = req.query?.before && !isNaN(Date.parse(req.query.before)) ? new Date(req.query.before).toISOString() : null;
    const t = await pool.query("SELECT * FROM wallet_tx WHERE user_id=$1 AND ($2::timestamptz IS NULL OR created_at < $2) ORDER BY created_at DESC LIMIT 50", [uid, before]);
    return Promise.all(t.rows.map(txRow));
  });
  // الشحن التجريبي: مال وهمي بنوع مستقل (test_topup) حتى لا يختلط بشحن البطاقة (topup)، ويُغلق للجميع عندما تكون مفاتيح ميسر حية
  app.post("/wallet/topup", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (globalThis.naslifePayMode?.() === "live") return bad(reply, 403, "topup-disabled-live");
    if (process.env.WALLET_TEST_TOPUP !== "1" && !(await isAdmin(uid))) return bad(reply, 403, "topup-disabled");
    if (iosNative(req) && !(await isAdmin(uid))) return bad(reply, 403, "unavailable");
    const amount = SAR(req.body?.amount);
    // حتى 100,000 ر.س للشحن التجريبي الواحد (أسعار الفنادق والسيارات تتجاوز السقف القديم 5,000)
    const maxTopup = Number(globalThis.naslifeSettings?.maxTopup) || 10000000;
    if (amount <= 0 || amount > maxTopup) return bad(reply, 400, "bad-amount", { max: maxTopup });
    if (await needsAdult(uid)) return bad(reply, 403, "adult-required");
    await tx((c) => ledger(c, uid, "test_topup", amount, { note: "شحن تجريبي" }));
    return { ok: true };
  });
  // أُزيل POST /admin/wallet/credit (بلا سقف ولا سجل تدقيق)؛ المسار المدقَّق هو /adminapi/users/:id/credit في admin.js
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
      // المحفظتان تُنشآن ثم تُقفلان معاً بترتيب ثابت، فلا يتعارض تحويلان متعاكسان (أ→ب وب→أ) في الوقت نفسه
      for (const u of [from, to].sort()) await c.query("INSERT INTO wallet_accounts(user_id) VALUES($1) ON CONFLICT DO NOTHING", [u]);
      await c.query("SELECT user_id FROM wallet_accounts WHERE user_id = ANY($1::text[]) ORDER BY user_id FOR UPDATE", [[from, to]]);
      await ledger(c, from, "transfer_out", -amount, { peerId: to, note, ref });
      await ledger(c, to, "transfer_in", amount, { peerId: from, note, ref });
    });
    await notify(to, { kind: "transfer_in", title: "وصلك تحويل", body: `${await nickOf(from)} حوّل لك ${sar(amount)}${note ? " · " + note : ""}`, data: { from, amount } });
    return { ok: true, amount };
  }
  globalThis.naslifeWalletTransfer = transfer;
  app.post("/wallet/transfer", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    // مفتاح المنصة transfersEnabled (قرار المالك التنظيمي): مغلق ما لم يكن true صراحة، ولا تحويلات في عميل iOS
    if (globalThis.naslifeSettings?.transfersEnabled !== true || iosNative(req)) return bad(reply, 403, "unavailable");
    if (await needsAdult(uid)) return bad(reply, 403, "adult-required");
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
    const lat = b.lat == null || b.lat === "" ? null : Number(b.lat), lng = b.lng == null || b.lng === "" ? null : Number(b.lng);
    // الإحداثيات اختيارية لكن معاً وضمن المدى: NaN كان يُحفظ في العمود فتختفي الفعالية من الخريطة والصف
    if ((lat == null) !== (lng == null) || (lat != null && (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180))) return bad(reply, 400, "bad-location");
    const tiers = Array.isArray(b.tiers) && b.tiers.length ? b.tiers : [{ name: "عادي", price: 0, quantity: 100 }];
    if (tiers.length > 6) return bad(reply, 400, "too-many-tiers");
    if (await isSuspended(uid)) return bad(reply, 403, "suspended");
    const bannedE = bannedIn(title, String(b.description ?? ""), b.placeName ? String(b.placeName) : "", ...tiers.flatMap((t) => [String(t?.name ?? ""), String(t?.description ?? "")]));
    if (bannedE) return bad(reply, 400, "banned-words", { word: bannedE });
    // التذكرة المدفوعة لفعالية حضورية فقط (مكان أو إحداثيات)، فلا تُباع محتويات رقمية عبر المحفظة
    const hasPlace = !!String(b.placeName ?? "").trim() || (Number.isFinite(lat) && Number.isFinite(lng) && lat !== null && lng !== null);
    if (tiers.some((t) => SAR(t?.price) > 0) && !hasPlace) return bad(reply, 400, "place-required");
    // بيع التذاكر بمقابل عملية مالية: إقرار 18+ أولاً؛ الفعالية المجانية مفتوحة
    if (tiers.some((t) => SAR(t?.price) > 0) && (await needsAdult(uid))) return bad(reply, 403, "adult-required");
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
  // الضيف (بلا جلسة) لا يرى فعاليات الدوائر الخاصة: عمود الخصوصية في جدول الدوائر بالنواة يُكتشف مرة واحدة
  let vesselPubCol;
  const guestEventsSql = async (uid, alias = "events") => {
    if (uid) return "";
    if (vesselPubCol === undefined) {
      try {
        const cols = (await pool.query("SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name='vessels'")).rows.map((r) => r.column_name);
        vesselPubCol = cols.includes("id") ? (["is_public", "public"].find((c) => cols.includes(c)) ?? null) : null;
      } catch { vesselPubCol = null; }
    }
    return vesselPubCol ? ` AND (${alias}.vessel_id IS NULL OR NOT EXISTS (SELECT 1 FROM vessels gv WHERE gv.id::text = ${alias}.vessel_id::text AND gv."${vesselPubCol}" = false))` : "";
  };
  // القاعدة نفسها لـ«الصف» و«التغذية» (row.js) حتى لا يرى الضيف هناك ما يخفيه عنه GET /events
  globalThis.naslifeGuestEventsSql = guestEventsSql;
  app.get("/events", async (req, reply) => {
    const uid = await optionalAuth(req);
    const bb = bbox(req.query?.bbox); const mine = req.query?.mine === "1"; const vessel = UUID_RE.test(req.query?.vessel ?? "") ? req.query.vessel : null;
    if (mine && !uid) return unauthorized(reply);
    // الفعاليات المخفية بالإشراف ومضيفوها المحظورون لا تظهر في القوائم العامة
    const blocked = await blockedIds(uid);
    const g = await guestEventsSql(uid);
    const r = mine
      ? await pool.query("SELECT * FROM events WHERE host_id=$1 ORDER BY starts_at DESC LIMIT 100", [uid])
      : vessel
        ? await pool.query(`SELECT * FROM events WHERE vessel_id=$1 AND NOT cancelled AND NOT hidden AND NOT (host_id = ANY($2::text[]))${g} ORDER BY starts_at LIMIT 100`, [vessel, blocked])
        : bb
          ? await pool.query(`SELECT * FROM events WHERE NOT cancelled AND NOT hidden AND NOT (host_id = ANY($5::text[])) AND starts_at > now() - interval '6 hours' AND lat BETWEEN $2 AND $4 AND lng BETWEEN $1 AND $3${g} ORDER BY starts_at LIMIT 100`, [bb.minLng, bb.minLat, bb.maxLng, bb.maxLat, blocked])
          : await pool.query(`SELECT * FROM events WHERE NOT cancelled AND NOT hidden AND NOT (host_id = ANY($1::text[])) AND starts_at > now() - interval '6 hours'${g} ORDER BY starts_at LIMIT 100`, [blocked]);
    return Promise.all(r.rows.map((e) => eventOut(e, uid)));
  });
  app.get("/events/:id", async (req, reply) => {
    const uid = await optionalAuth(req);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const r = await pool.query(`SELECT * FROM events WHERE id=$1${await guestEventsSql(uid)}`, [req.params.id]);
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
    // التذكرة المدفوعة تحتاج إقرار 18+ (المجانية مفتوحة)؛ السعر يُقرأ قبل المعاملة فقط لمن لم يقرّ بعد
    if (await needsAdult(uid)) {
      const tp = (await pool.query("SELECT price FROM ticket_tiers WHERE id=$1 AND event_id=$2", [tierId, req.params.id]).catch(() => ({ rows: [] }))).rows[0];
      if (tp && Number(tp.price) > 0) return bad(reply, 403, "adult-required");
    }
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
    // قبل أي تعديل: مجموع ما يُسترد للتذاكر الصالحة مقابل رصيد المضيف؛ من أنفق الإيراد يُرفض إلغاؤه بـ402 بدل خطأ 500 والفعالية تبقى كما هي
    const hostBalance = async () => Number((await pool.query("SELECT balance FROM wallet_accounts WHERE user_id=$1", [uid])).rows[0]?.balance ?? 0);
    const due = Number((await pool.query("SELECT COALESCE(SUM(paid),0)::bigint AS s FROM tickets WHERE event_id=$1 AND status='valid'", [ev.id])).rows[0].s);
    const have = await hostBalance();
    if (due > have) return bad(reply, 402, "insufficient-funds", { need: due - have, have });
    let holders;
    try {
      holders = await tx(async (c) => {
        await c.query("UPDATE events SET cancelled=true WHERE id=$1", [ev.id]);
        const ts = (await c.query("UPDATE tickets SET status='refunded' WHERE event_id=$1 AND status='valid' RETURNING user_id, paid", [ev.id])).rows;
        for (const t of ts) if (Number(t.paid) > 0) {
          await ledger(c, t.user_id, "refund", Number(t.paid), { peerId: uid, ref: ev.id, note: ev.title });
          await ledger(c, uid, "refund_out", -Number(t.paid), { peerId: t.user_id, ref: ev.id, note: ev.title });
        }
        return ts;
      });
    } catch (e) {
      // سباق: أُنفق الرصيد بين الفحص والمعاملة؛ المعاملة تراجعت كاملة
      if (e.code === "insufficient-funds") { const now = await hostBalance(); return bad(reply, 402, "insufficient-funds", { need: Math.max(0, due - now), have: now }); }
      throw e;
    }
    const refunded = new Map();
    for (const t of holders) refunded.set(t.user_id, (refunded.get(t.user_id) ?? 0) + Number(t.paid));
    for (const [u, paid] of refunded) await notify(u, { kind: "event_cancelled", title: "أُلغيت الفعالية", body: `${ev.title}${paid > 0 ? " · استُرد " + sar(paid) + " إلى محفظتك" : ""}`, data: { eventId: ev.id }, exclude: uid });
    return { ok: true };
  });

  // ---- السوق (النسخة الثانية): صور متعددة، تصنيفات فرعية، خيارات ومخزون، مواعيد للخدمات، بحث بالقرب والفلاتر،
  // طلب بمراحل ورمز تسليم، كوبونات، عمولة للمنصة، نزاعات. الميزات التكميلية (سبوت لايت، تقييمات، بائعون…) في market_plus.js
  const PLATFORM = String(process.env.PLATFORM_ACCOUNT_ID ?? "SA0000000");
  // رمز التسليم: بعد خمس محاولات خاطئة من البائع يُقفل الرمز نهائياً (حتى الصحيح)، ويبقى تأكيد المشتري متاحاً
  const CODE_MAX_FAILS = 5;
  // الدفع عند الاستلام: حد الطلبات المفتوحة لكل مشترٍ، وعدد مرات «لم يحضر» التي توقفه عنه، ومهلة قبول البائع
  const COD_MAX_OPEN = 3, COD_MAX_NO_SHOWS = 3, COD_ACCEPT_HOURS = 48;
  // «لم يحضر» لا يُسجَّل قبل أن يحين التسليم (ساعتان بعد القبول ما لم يكن «في الطريق» أو بموعد)، ويُعدّ ببائعين مختلفين خلال ٩٠ يوماً:
  // بائع واحد معادٍ أو متعجل لا يُغلق المسار على مشترٍ، ولا يبقى الأثر للأبد
  const COD_NO_SHOW_WAIT_HOURS = 2, COD_NO_SHOW_DAYS = 90;
  const noShowCount = async (c, buyerId) => (await c.query(`SELECT count(DISTINCT seller_id)::int AS n FROM market_orders
      WHERE buyer_id=$1 AND payment='cod' AND cancel_reason='no_show' AND updated_at > now() - make_interval(days => $2)`, [buyerId, COD_NO_SHOW_DAYS])).rows[0].n;
  const COD_OPEN = ["requested", "paid", "preparing", "on_the_way", "delivered"];
  // المراحل بعد القبول (أو بعد الدفع في طلب المحفظة) وقبل الاكتمال
  const ACTIVE = ["paid", "preparing", "on_the_way", "delivered"];
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
      createdAt: l.created_at, updatedAt: l.updated_at ?? l.created_at, mine: l.seller_id === uid, payOnReceipt: l.pay_on_receipt === true,
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
  // الدفع عند الاستلام لما يُسلَّم أو يُلتقى عليه حضورياً فقط: توصيل أو مكان استلام مكتوب
  const codPlaceOk = (delivery, placeName) => delivery === true || String(placeName ?? "").trim().length > 0;
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
    // البيع بمقابل (سعر أو خيار مسعّر) يحتاج إقرار 18+؛ العرض المجاني مفتوح
    if ((price > 0 || parseVariants(b.variants).some((v) => v.price > 0)) && (await needsAdult(uid))) return bad(reply, 403, "adult-required");
    const payOnReceipt = b.payOnReceipt === true;
    if (payOnReceipt && !codPlaceOk(b.delivery, b.placeName)) return bad(reply, 400, "cod-needs-place");
    const publishAt = b.publishAt ? new Date(b.publishAt) : null;
    const scheduled = publishAt && !Number.isNaN(publishAt.getTime()) && publishAt.getTime() > Date.now() + 60000;
    const needsReview = settingsOf().marketReviewNewAccounts === true && (await accountAgeHours(uid)) < 24 * 7 && !(await isAdmin(uid));
    const status = b.status === "draft" ? "draft" : scheduled ? "scheduled" : needsReview ? "pending" : "active";
    const imgs = parseImages(req, b); const id = crypto.randomUUID();
    await pool.query(`INSERT INTO market_listings(id,seller_id,kind,category,subcategory,condition,delivery,title,description,price,image_url,images,place_name,city,lat,lng,status,stock,variants,availability,publish_at,bumped_at,pay_on_receipt)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,now(),$22)`,
      [id, uid, kind, category, subcategory, CONDITIONS.has(b.condition) ? b.condition : null, b.delivery === true, title, description, price, imgs[0] ?? null, JSON.stringify(imgs),
       b.placeName ? String(b.placeName).slice(0, 80) : null, b.city ? String(b.city).slice(0, 40) : null, b.lat == null ? null : Number(b.lat), b.lng == null ? null : Number(b.lng),
       status, stockInt(b.stock), JSON.stringify(parseVariants(b.variants)), b.availability ? JSON.stringify(parseAvailability(b.availability)) : null, scheduled ? publishAt : null, payOnReceipt]);
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
    // تحويل عرض مجاني إلى مسعّر بيعٌ بمقابل: إقرار 18+ أولاً
    if (((b.price !== undefined && SAR(b.price) > 0) || (b.variants !== undefined && parseVariants(b.variants).some((v) => v.price > 0))) && (await needsAdult(uid))) return bad(reply, 403, "adult-required");
    if (b.title !== undefined) { const t = String(b.title).trim(); if (!t || t.length > 100) return bad(reply, 400, "bad-title"); set("title", t); }
    if (b.description !== undefined) set("description", String(b.description).slice(0, 2000));
    if (b.price !== undefined) { const pr = SAR(b.price); if (pr < 0) return bad(reply, 400, "bad-price"); set("price", pr); }
    const category = b.category !== undefined ? (CATEGORY_SET.has(b.category) ? b.category : "other") : l.category;
    if (b.category !== undefined) set("category", category);
    if (b.subcategory !== undefined || b.category !== undefined) set("subcategory", subOk(category, b.subcategory ?? l.subcategory) ? (b.subcategory ?? l.subcategory) : null);
    if (b.kind !== undefined) set("kind", b.kind === "service" ? "service" : "product");
    if (b.condition !== undefined) set("condition", CONDITIONS.has(b.condition) ? b.condition : null);
    if (b.delivery !== undefined) set("delivery", b.delivery === true);
    // الدفع عند الاستلام يبقى صالحاً بعد التعديل: يُفحص بالقيم الناتجة (المرسلة أو المحفوظة) متى لمس الطلب أحد الثلاثة
    if (b.payOnReceipt !== undefined || b.delivery !== undefined || b.placeName !== undefined) {
      const cod = b.payOnReceipt !== undefined ? b.payOnReceipt === true : l.pay_on_receipt === true;
      if (cod && !codPlaceOk(b.delivery !== undefined ? b.delivery === true : l.delivery === true, b.placeName !== undefined ? b.placeName : l.place_name)) return bad(reply, 400, "cod-needs-place");
      if (b.payOnReceipt !== undefined) set("pay_on_receipt", cod);
    }
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
    reviewed: o.reviewed === true, codeLocked: Number(o.code_fails ?? 0) >= CODE_MAX_FAILS, createdAt: o.created_at, updatedAt: o.updated_at,
    payment: o.payment === "cod" ? "cod" : "wallet", cancelReason: o.cancel_reason ?? null, acceptedAt: o.accepted_at ?? null, cashReceivedAt: o.cash_received_at ?? null,
  });
  globalThis.naslifeMarketOrderOut = orderOut;
  // «من يراسلني» (profile_ext.js): أطراف طلب السوق (المشتري والبائع والمندوب) يتراسلون أياً كانت سياستهم ما دام الطلب
  // قائماً، أو تغيّر خلال 14 يوماً (متابعة التسليم والتقييم والنزاع). طلب الدفع عند الاستلام الذي انتهى قبل أن يقبله البائع
  // (اعتذار أو إلغاء أو انتهاء مهلة) لا يفتح المراسلة: الطلب مجاني فلا يصير بطاقة مرور دائمة إلى بائع قيّد من يراسله
  (globalThis.naslifeMessageAllow ??= new Map()).set("market-orders", async (a, b) => !!a && !!b && a !== b && (await pool.query(
    `SELECT 1 FROM market_orders WHERE (status IN ('requested','paid','preparing','on_the_way','delivered','disputed') OR updated_at > now() - interval '14 days')
       AND NOT (payment='cod' AND accepted_at IS NULL AND status IN ('cancelled','refunded'))
       AND ((buyer_id=$1 AND (seller_id=$2 OR courier_id=$2)) OR (buyer_id=$2 AND (seller_id=$1 OR courier_id=$1)) OR (seller_id=$1 AND courier_id=$2) OR (seller_id=$2 AND courier_id=$1)) LIMIT 1`, [a, b])).rowCount > 0);
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
  // الطلب: خيار ومخزون وموعد وكوبون؛ المبلغ يُحجز من المشتري ولا يصل البائع إلا عند اكتمال الطلب (تأكيد الاستلام).
  // payment:"cod" (الدفع عند الاستلام، والعرض يسمح به): لا مال يتحرك، الطلب يبدأ «بانتظار قبول البائع» (requested) ويحجز المخزون
  // كالمدفوع، ولكل مشترٍ ٣ طلبات مفتوحة منه على الأكثر، ويُغلق عنه بعد ٣ مرات «لم يحضر»
  app.post("/market/:id/order", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (await isSuspended(uid)) return bad(reply, 403, "suspended");
    const b = req.body ?? {};
    const qty = Math.max(1, Math.min(20, Number(b.qty) || 1)); const note = String(b.note ?? "").slice(0, 300);
    const variantName = String(b.variant ?? "").trim(); const couponCode = String(b.coupon ?? "").trim().toUpperCase().slice(0, 24);
    const slot = b.slot ? new Date(b.slot) : null;
    const wantCod = b.payment === "cod";
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    // ملاحظة المشتري تصل البائع نصاً وإشعاراً: الكلمات الممنوعة نفسها التي تسري على العرض
    const bannedNote = bannedIn(note); if (bannedNote) return bad(reply, 400, "banned-words", { word: bannedNote });
    const blocked = await blockedIds(uid);
    // الشراء بمقابل يحتاج إقرار 18+ (يُفحص المبلغ داخل المعاملة؛ الطلب المجاني مفتوح)
    const adultMissing = await needsAdult(uid);
    const id = crypto.randomUUID(); const code = String(1000 + crypto.randomInt(9000));
    const fail = (err, extra = {}) => Object.assign(new Error(err), { code: err, ...extra });
    let l, variant = null, total = 0, discount = 0, commission = 0, payment = "wallet";
    try {
      // قراءة العرض بقفل داخل المعاملة نفسها: فحص المخزون والخيار والموعد والخصم في وحدة واحدة فلا بيع زائد عند طلبين متوازيين
      await tx(async (c) => {
        l = (await c.query("SELECT * FROM market_listings WHERE id=$1 AND status='active' FOR UPDATE", [req.params.id])).rows[0];
        if (!l) throw fail("not-found");
        if (l.seller_id === uid) throw fail("own-listing");
        // لا طلب بين طرفين بينهما حظر (بأي اتجاه)
        if (blocked.includes(l.seller_id)) throw fail("not-found");
        if (wantCod && l.pay_on_receipt !== true) throw fail("cod-unavailable");
        let unit = Number(l.price);
        const variants = Array.isArray(l.variants) ? l.variants : [];
        if (variants.length) {
          variant = variants.find((v) => v.name === variantName); if (!variant) throw fail("variant-required", { variants: variants.map((v) => v.name) });
          unit = Number(variant.price); if (variant.stock != null && Number(variant.stock) < qty) throw fail("out-of-stock");
        } else if (l.stock != null && Number(l.stock) < qty) throw fail("out-of-stock");
        if (l.kind === "service" && l.availability) {
          if (!slot || Number.isNaN(slot.getTime())) throw fail("slot-required");
          if (!slotOk(l.availability, slot)) throw fail("slot-unavailable");
          if ((await c.query("SELECT 1 FROM market_orders WHERE listing_id=$1 AND slot=$2 AND status NOT IN ('cancelled','refunded')", [l.id, slot])).rowCount) throw fail("slot-taken");
        }
        const subtotal = unit * qty; let coupon = null;
        if (couponCode) {
          const cp = (await c.query("SELECT * FROM market_coupons WHERE code=$1 AND seller_id=$2 AND active AND (expires_at IS NULL OR expires_at > now()) AND (max_uses IS NULL OR used < max_uses) FOR UPDATE", [couponCode, l.seller_id])).rows[0];
          if (!cp) throw fail("bad-coupon");
          if (subtotal < Number(cp.min_total ?? 0)) throw fail("coupon-min", { minTotal: Number(cp.min_total) });
          discount = cp.percent != null ? Math.floor(subtotal * Number(cp.percent) / 100) : Math.min(subtotal, Number(cp.amount ?? 0)); coupon = cp.code;
        }
        total = Math.max(0, subtotal - discount); commission = Math.floor(total * commissionPct() / 100);
        if (total > 0 && adultMissing) throw fail("adult-required");
        // الطلب المجاني لا طريقة دفع له: يسلك مسار الطلب العادي بلا قبول مسبق
        payment = wantCod && total > 0 ? "cod" : "wallet";
        if (payment === "cod") {
          // قفل لكل مشترٍ حتى نهاية المعاملة: طلبان متوازيان لا يتجاوزان الحد معاً
          await c.query("SELECT pg_advisory_xact_lock(hashtext($1))", [`market-cod:${uid}`]);
          const st = (await c.query("SELECT count(*)::int AS open FROM market_orders WHERE buyer_id=$1 AND payment='cod' AND status = ANY($2::text[])", [uid, COD_OPEN])).rows[0];
          const noShows = await noShowCount(c, uid);
          if (noShows >= COD_MAX_NO_SHOWS) throw fail("cod-blocked", { noShows, days: COD_NO_SHOW_DAYS });
          if (st.open >= COD_MAX_OPEN) throw fail("cod-limit", { max: COD_MAX_OPEN });
          // المال لا يمر بناس لايف فلا عمولة تُقتطع منه
          commission = 0;
        } else if (total > 0) await ledger(c, uid, "market", -total, { peerId: l.seller_id, ref: id, note: l.title, points: Math.floor(total / 1000) });
        await c.query("INSERT INTO market_orders(id,listing_id,buyer_id,seller_id,qty,total,note,code,variant,coupon,discount,commission,slot,payment,status) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)",
          [id, l.id, uid, l.seller_id, qty, total, note, code, variant?.name ?? null, coupon, discount, commission, slot && !Number.isNaN(slot.getTime()) ? slot : null, payment, payment === "cod" ? "requested" : "paid"]);
        if (variant) await c.query(`UPDATE market_listings SET variants = (SELECT COALESCE(jsonb_agg(CASE WHEN v->>'name'=$2 AND (v->>'stock') IS NOT NULL THEN jsonb_set(v, '{stock}', to_jsonb(GREATEST(0, (v->>'stock')::int - $3))) ELSE v END), '[]'::jsonb) FROM jsonb_array_elements(variants) v), sold=sold+$3, updated_at=now() WHERE id=$1`, [l.id, variant.name, qty]);
        else await c.query("UPDATE market_listings SET stock = CASE WHEN stock IS NULL THEN NULL ELSE GREATEST(0, stock-$2) END, sold=sold+$2, updated_at=now() WHERE id=$1", [l.id, qty]);
        if (coupon) await c.query("UPDATE market_coupons SET used=used+1 WHERE code=$1 AND seller_id=$2", [coupon, l.seller_id]);
      });
    } catch (e) {
      switch (e.code) {
        case "not-found": return bad(reply, 404, "not-found");
        case "own-listing": return bad(reply, 400, "own-listing");
        case "variant-required": return bad(reply, 400, "variant-required", { variants: e.variants });
        case "out-of-stock": case "slot-taken": return bad(reply, 409, e.code);
        case "slot-required": case "slot-unavailable": case "bad-coupon": return bad(reply, 400, e.code);
        case "coupon-min": return bad(reply, 400, "coupon-min", { minTotal: e.minTotal });
        case "insufficient-funds": return bad(reply, 402, "insufficient-funds");
        case "adult-required": return bad(reply, 403, "adult-required");
        case "cod-unavailable": return bad(reply, 400, "cod-unavailable");
        case "cod-blocked": return bad(reply, 403, "cod-blocked", { noShows: e.noShows, days: e.days });
        case "cod-limit": return bad(reply, 429, "cod-limit", { max: e.max });
        default: throw e;
      }
    }
    const what = `${l.title}${variant ? " (" + variant.name + ")" : ""}${qty > 1 ? " × " + qty : ""}`;
    if (payment === "cod") await notify(l.seller_id, { kind: "market_cod_order", title: "طلب جديد · الدفع عند الاستلام", body: `${await nickOf(uid)} طلب ${what} بقيمة ${sar(total)} يدفعها عند الاستلام. اقبل الطلب أو اعتذر${note ? " · " + note.slice(0, 80) : ""}`, data: { orderId: id, listingId: l.id, payment } });
    else await notify(l.seller_id, { kind: "market_order", title: "طلب جديد في السوق", body: `${await nickOf(uid)} طلب ${what} بقيمة ${sar(total)}${note ? " · " + note.slice(0, 80) : ""}`, data: { orderId: id, listingId: l.id } });
    return { ok: true, id, total, discount, commission, code, payment, status: payment === "cod" ? "requested" : "paid" };
  });
  const loadOrder = async (id) => (await pool.query(`${ORDER_SQL} WHERE o.id=$1`, [id])).rows[0] ?? null;
  const STAGE_LABEL = { preparing: "قيد التحضير", on_the_way: "في الطريق", delivered: "تم التسليم" };
  const isCod = (o) => o?.payment === "cod";
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
    // الانتقال مشروط بالحالة التي فُحصت: إلغاء متوازٍ سبق (استرداد) لا يُكتب فوقه «تم التسليم» فيدفع التأكيد أو الاكتمال التلقائي للبائع مرة ثانية
    const moved = await pool.query(`UPDATE market_orders SET status=$2, updated_at=now(), accepted_at=COALESCE(accepted_at, now())${stage === "delivered" ? ", delivered_at=now()" : ""} WHERE id=$1 AND status=$3 RETURNING id`, [o.id, stage, o.status]);
    if (!moved.rowCount) return bad(reply, 409, "bad-status");
    await notify(o.buyer_id, { kind: "market_status", title: `طلبك: ${STAGE_LABEL[stage]}`, body: stage !== "delivered" ? `${o.title}: ${STAGE_LABEL[stage]}`
      : isCod(o) ? `${o.title}: أكد البائع التسليم. ادفع له ${sar(o.total)} وأعطه رمزك ${o.code}، أو أكّد الاستلام من صفحة الطلب`
      : `${o.title}: أكد البائع التسليم. أكّد الاستلام من صفحة الطلب أو أعطه رمزك ${o.code}`, data: { orderId: o.id, status: stage } });
    return { ok: true, status: stage };
  };
  app.post("/market/orders/:id/stage", async (req, reply) => advance(req, reply, ["preparing", "on_the_way", "delivered"].includes(req.body?.stage) ? req.body.stage : "delivered"));
  app.post("/market/orders/:id/deliver", async (req, reply) => advance(req, reply, "delivered"));
  // اكتمال الطلب وتحرير المبلغ للبائع بعد خصم العمولة (تُقيَّد لحساب المنصة).
  // الدفع عند الاستلام: لا قيد في الدفتر (المال سُلّم يداً بيد)، و cash يسجّل «استلمت المبلغ» من البائع
  const complete = async (o, { by = "buyer", lockCode = false, cash = false } = {}) => {
    const cod = isCod(o);
    const net = cod ? 0 : Number(o.total) - Number(o.commission ?? 0);
    await tx(async (c) => {
      if (lockCode) {
        // رمز البائع يُفحص تحت قفل الصف نفسه الذي يزيد عدّاد الأخطاء، فلا تتجاوز دفعة متوازية حد المحاولات
        const cur = (await c.query("SELECT code_fails FROM market_orders WHERE id=$1 FOR UPDATE", [o.id])).rows[0];
        if (cur && Number(cur.code_fails) >= CODE_MAX_FAILS) throw Object.assign(new Error("code-locked"), { code: "code-locked" });
      }
      const r = await c.query("UPDATE market_orders SET status='completed', completed_at=now(), updated_at=now(), cash_received_at=CASE WHEN $2::boolean THEN now() ELSE cash_received_at END WHERE id=$1 AND status IN ('paid','preparing','on_the_way','delivered') RETURNING id", [o.id, cod && cash]);
      if (!r.rowCount) throw Object.assign(new Error("bad-status"), { code: "bad-status" });
      if (cod) return;
      if (net > 0) await ledger(c, o.seller_id, "market_sale", net, { peerId: o.buyer_id, ref: o.id, note: o.title });
      if (Number(o.commission) > 0) await ledger(c, PLATFORM, "commission", Number(o.commission), { peerId: o.seller_id, ref: o.id, note: o.title });
    });
    globalThis.naslifeMarketOnComplete?.(o).catch?.(() => {});
    if (cod) {
      // لا مبلغ يصل عبر ناس لايف: الاكتمال يُبلَّغ للطرف الذي لم يُكمله
      const data = { orderId: o.id, status: "completed", payment: "cod" };
      if (by !== "seller") await notify(o.seller_id, { kind: "market_cod_completed", title: "اكتمل الطلب", body: `${o.title}: ${by === "auto" ? "اكتمل تلقائياً بعد ٧٢ ساعة من التسليم" : "أكّد المشتري الاستلام"} · الدفع عند الاستلام ${sar(o.total)}`, data });
      if (by !== "buyer") await notify(o.buyer_id, { kind: "market_cod_completed", title: "اكتمل طلبك", body: `${o.title}: يمكنك الآن تقييم البائع`, data });
      return;
    }
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
    if (isSeller) {
      // قفل رمز التسليم: لا تخمين بلا حدود؛ المحاولة الخاطئة تُحسب ويُعاد ما تبقى، وبعد القفل يُرفض حتى الرمز الصحيح
      if (Number(o.code_fails ?? 0) >= CODE_MAX_FAILS) return bad(reply, 429, "code-locked");
      if (String(req.body?.code ?? "").trim() !== String(o.code)) {
        // الفحص والزيادة في جملة واحدة: دفعة متوازية من الرموز الخاطئة لا تتجاوز الحد لأن كل زيادة مشروطة بأن العدّاد ما زال دونه
        const r = await pool.query("UPDATE market_orders SET code_fails=code_fails+1 WHERE id=$1 AND code_fails < $2 AND status IN ('paid','preparing','on_the_way','delivered') RETURNING code_fails", [o.id, CODE_MAX_FAILS]);
        if (!r.rowCount) {
          const cur = (await pool.query("SELECT status FROM market_orders WHERE id=$1", [o.id])).rows[0];
          return ["paid", "preparing", "on_the_way", "delivered"].includes(cur?.status) ? bad(reply, 429, "code-locked") : bad(reply, 409, "bad-status");
        }
        return bad(reply, 400, "bad-code", { left: Math.max(0, CODE_MAX_FAILS - Number(r.rows[0].code_fails)) });
      }
    }
    // في الدفع عند الاستلام: رمز المشتري عند البائع يعني أن التسليم والدفع تمّا معاً
    try { await complete(o, { by: isBuyer ? "buyer" : "seller", lockCode: isSeller, cash: isSeller }); }
    catch (e) { if (e.code === "bad-status") return bad(reply, 409, "bad-status"); if (e.code === "code-locked") return bad(reply, 429, "code-locked"); throw e; }
    return { ok: true, status: "completed" };
  });
  // الدفع عند الاستلام: البائع يسجّل «استلمت المبلغ» عند التسليم فيكتمل الطلب (بلا أي قيد في المحفظة)
  app.post("/market/orders/:id/cash-received", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const o = await loadOrder(req.params.id); if (!o) return bad(reply, 404, "not-found");
    if (o.seller_id !== uid) return bad(reply, 403, "seller-only");
    if (!isCod(o)) return bad(reply, 409, "not-cod");
    if (!ACTIVE.includes(o.status)) return bad(reply, 409, "bad-status");
    try { await complete(o, { by: "seller", cash: true }); } catch (e) { if (e.code === "bad-status") return bad(reply, 409, "bad-status"); throw e; }
    return { ok: true, status: "completed" };
  });
  // الإلغاء: الحالة الجديدة مشروطة بأن الطلب ما زال في إحدى الحالات from (تتغيّر حسب من يلغي ولماذا).
  // الدفع عند الاستلام: لا مال محجوز فلا قيد استرداد، ويعود المخزون والكوبون كالمدفوع
  const refund = async (o, { status = "cancelled", amount = null, note = null, reason = null, from = ["requested", ...ACTIVE, "disputed"] } = {}) => {
    const amt = isCod(o) ? 0 : amount == null ? Number(o.total) : amount;
    await tx(async (c) => {
      // حارس الحالة قبل أي قيد في الدفتر: التحديث يقفل الصف ويفشل إن سبقه إلغاء أو اكتمال، فلا استرداد مرتين ولا بعد وصول المبلغ للبائع
      const r = await c.query("UPDATE market_orders SET status=$2, dispute_status=CASE WHEN dispute_status IS NULL THEN NULL ELSE 'resolved' END, dispute_note=COALESCE($3, dispute_note), cancel_reason=COALESCE($4, cancel_reason), updated_at=now() WHERE id=$1 AND status = ANY($5::text[]) RETURNING id", [o.id, status, note, reason, from]);
      if (!r.rowCount) throw Object.assign(new Error("bad-status"), { code: "bad-status" });
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
    // المشتري يلغي قبل أن يبدأ البائع (وفي الدفع عند الاستلام قبل القبول أيضاً)؛ البائع يلغي في أي مرحلة قبل الاكتمال
    const allowed = byBuyer ? (isCod(o) ? ["requested", "paid"] : ["paid"]) : ["requested", ...ACTIVE];
    if (!allowed.includes(o.status)) return bad(reply, 409, "bad-status");
    // حارس الكتابة كما كان: إلغاء البائع يسبق نزاعاً متزامناً فيُسترد للمشتري ويُحسم النزاع (refund يُغلقه)
    try { await refund(o, { reason: byBuyer ? "buyer" : "seller" }); } catch (e) { if (e.code === "bad-status") return bad(reply, 409, "bad-status"); throw e; }
    const back = !isCod(o) && Number(o.total) > 0 ? " واستُرد " + sar(o.total) + " إلى محفظتك" : "";
    await notify(byBuyer ? o.seller_id : o.buyer_id, { kind: "market_status", title: byBuyer ? "أُلغي طلب" : "أُلغي طلبك",
      body: byBuyer ? `${await nickOf(uid)} ألغى طلب ${o.title}` : `${o.title}: ألغى البائع الطلب${back}`, data: { orderId: o.id, status: "cancelled" } });
    return { ok: true };
  });
  // الدفع عند الاستلام: البائع يقبل الطلب أولاً («قبول الطلب») فيدخل المراحل، أو يعتذر عنه فيُلغى ويعود المخزون
  const codSellerOrder = async (req, reply) => {
    const uid = await auth(req); if (!uid) { unauthorized(reply); return null; }
    if (!UUID_RE.test(req.params.id)) { bad(reply, 400, "bad-id"); return null; }
    const o = await loadOrder(req.params.id); if (!o) { bad(reply, 404, "not-found"); return null; }
    if (o.seller_id !== uid) { bad(reply, 403, "seller-only"); return null; }
    if (!isCod(o)) { bad(reply, 409, "not-cod"); return null; }
    return o;
  };
  app.post("/market/orders/:id/accept", async (req, reply) => {
    const o = await codSellerOrder(req, reply); if (!o) return;
    if (await isSuspended(o.seller_id)) return bad(reply, 403, "suspended");
    const r = await pool.query("UPDATE market_orders SET status='paid', accepted_at=now(), updated_at=now() WHERE id=$1 AND status='requested' RETURNING id", [o.id]);
    if (!r.rowCount) return bad(reply, 409, "bad-status");
    await notify(o.buyer_id, { kind: "market_cod_accepted", title: "قبل البائع طلبك", body: `${o.title}: ادفع ${sar(o.total)} للبائع عند الاستلام وأعطه رمزك ${o.code}`, data: { orderId: o.id, status: "paid", payment: "cod" } });
    return { ok: true, status: "paid" };
  });
  app.post("/market/orders/:id/decline", async (req, reply) => {
    const o = await codSellerOrder(req, reply); if (!o) return;
    if (o.status !== "requested") return bad(reply, 409, "bad-status");
    const reason = String(req.body?.reason ?? "").trim().slice(0, 200);
    const w = bannedIn(reason); if (w) return bad(reply, 400, "banned-words", { word: w });
    try { await refund(o, { reason: "declined", from: ["requested"] }); } catch (e) { if (e.code === "bad-status") return bad(reply, 409, "bad-status"); throw e; }
    await notify(o.buyer_id, { kind: "market_status", title: "اعتذر البائع عن طلبك", body: `${o.title}${reason ? ": " + reason : ""} · لم يُخصم منك شيء`, data: { orderId: o.id, status: "cancelled" } });
    return { ok: true, status: "cancelled" };
  });
  // «لم يحضر المشتري»: يُلغى الطلب ويعود المخزون ويُحسب على المشتري؛ إن سجّله ٣ بائعين مختلفين خلال ٩٠ يوماً لا يُقبل منه طلب
  // بالدفع عند الاستلام. لا يُسجَّل قبل أن يحين التسليم: الخدمة بموعد عند حلوله، وغيرها «في الطريق» أو بعد ساعتين من القبول
  app.post("/market/orders/:id/no-show", async (req, reply) => {
    const o = await codSellerOrder(req, reply); if (!o) return;
    const from = ["paid", "preparing", "on_the_way"];
    if (!from.includes(o.status)) return bad(reply, 409, "bad-status");
    const dueAt = o.slot ? new Date(o.slot).getTime() : o.status === "on_the_way" ? 0 : new Date(o.accepted_at ?? o.created_at).getTime() + COD_NO_SHOW_WAIT_HOURS * 3600000;
    if (dueAt > Date.now()) return bad(reply, 409, "too-early", { slot: o.slot ?? null, at: new Date(dueAt).toISOString() });
    try { await refund(o, { reason: "no_show", from }); } catch (e) { if (e.code === "bad-status") return bad(reply, 409, "bad-status"); throw e; }
    const n = await noShowCount(pool, o.buyer_id);
    // نص محايد: لا دعوة إلى المحفظة (مستخدم iOS لا يشحنها)
    await notify(o.buyer_id, { kind: "market_status", title: "سُجّل عدم حضورك للاستلام", body: `${o.title}: سجّل البائع أنك لم تحضر (${n} من ${COD_MAX_NO_SHOWS}). ${n >= COD_MAX_NO_SHOWS ? "توقف الدفع عند الاستلام لحسابك" : `إن سجّل ذلك ${COD_MAX_NO_SHOWS} بائعين مختلفين خلال ${COD_NO_SHOW_DAYS} يوماً يتوقف الدفع عند الاستلام لحسابك`}. إن كان ذلك خطأً فأبلغ عن البائع`, data: { orderId: o.id, status: "cancelled" } });
    return { ok: true, status: "cancelled", noShows: n };
  });
  // نزاع من المشتري قبل الاكتمال: يتجمّد المبلغ حتى تحسمه الإدارة
  app.post("/market/orders/:id/dispute", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const o = await loadOrder(req.params.id); if (!o) return bad(reply, 404, "not-found");
    if (o.buyer_id !== uid) return bad(reply, 403, "buyer-only");
    // الدفع عند الاستلام: لا مبلغ محجوز تحسمه الإدارة؛ المشتري يبلّغ عن البائع من ورقة البلاغ بدلاً من ذلك
    if (isCod(o)) return bad(reply, 409, "cod-no-dispute");
    if (!["paid", "preparing", "on_the_way", "delivered"].includes(o.status)) return bad(reply, 409, "bad-status");
    const reason = String(req.body?.reason ?? "").trim().slice(0, 600); if (reason.length < 5) return bad(reply, 400, "bad-reason");
    // الانتقال مشروط بالحالة: إلغاء أو اكتمال سبق في اللحظة نفسها لا يُكتب فوقه «متنازَع عليه» فيحرّر الحسم المبلغ للبائع بعد استرداده
    const r = await pool.query("UPDATE market_orders SET status='disputed', dispute_status='open', dispute_reason=$2, updated_at=now() WHERE id=$1 AND status IN ('paid','preparing','on_the_way','delivered') RETURNING id", [o.id, reason]);
    if (!r.rowCount) return bad(reply, 409, "bad-status");
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
    if (!["refund", "release", "split"].includes(resolution)) return bad(reply, 400, "bad-resolution");
    // الحسم مرة واحدة: كل تحديث مشروط بأن الطلب ما زال متنازَعاً عليه، وإلا 409 بلا أي قيد (حسمان متوازيان)
    const resolveSql = "UPDATE market_orders SET status='completed', completed_at=now(), dispute_status='resolved', dispute_note=$2, updated_at=now() WHERE id=$1 AND status='disputed' RETURNING id";
    const badStatus = () => Object.assign(new Error("bad-status"), { code: "bad-status" });
    try {
      if (resolution === "refund") await refund(o, { status: "refunded", note });
      else if (resolution === "release") {
        await tx(async (c) => {
          if (!(await c.query(resolveSql, [o.id, note])).rowCount) throw badStatus();
          if (total - commission > 0) await ledger(c, o.seller_id, "market_sale", total - commission, { peerId: o.buyer_id, ref: o.id, note: o.title });
          if (commission > 0) await ledger(c, PLATFORM, "commission", commission, { peerId: o.seller_id, ref: o.id, note: o.title });
        });
      } else {
        const half = Math.floor(total / 2);
        await tx(async (c) => {
          if (!(await c.query(resolveSql, [o.id, note])).rowCount) throw badStatus();
          if (half > 0) await ledger(c, o.buyer_id, "refund", half, { peerId: o.seller_id, ref: o.id, note: o.title });
          if (total - half > 0) await ledger(c, o.seller_id, "market_sale", total - half, { peerId: o.buyer_id, ref: o.id, note: o.title });
        });
      }
    } catch (e) { if (e.code === "bad-status") return bad(reply, 409, "bad-status"); throw e; }
    const msg = { refund: "أُعيد المبلغ كاملاً للمشتري", release: "حُرِّر المبلغ للبائع", split: "قُسم المبلغ بين الطرفين" }[resolution];
    await notify([o.buyer_id, o.seller_id], { kind: "market_dispute", title: "حُسم النزاع", body: `${o.title}: ${msg}${note ? " · " + note : ""}`, data: { orderId: o.id } });
    return { ok: true, resolution };
  });
  // «لم يحضر» ظالم: المشتري يبلّغ عن البائع، والإدارة تراجع القائمة (نافذة العدّ نفسها، مع عدّاد كل مشترٍ) وتمسحه.
  // السبب يصير no_show_cleared فلا يُحسب على المشتري، ويُعدّ إلغاءً على البائع في شاراته (recompute يستثني no_show وحده)
  app.get("/adminapi/market/no-shows", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!(await isAdmin(uid))) return bad(reply, 403, "admin-only");
    const rows = (await pool.query(`${ORDER_SQL} WHERE o.payment='cod' AND o.cancel_reason='no_show' AND o.updated_at > now() - make_interval(days => $1) ORDER BY o.updated_at DESC LIMIT 100`, [COD_NO_SHOW_DAYS])).rows;
    const counts = new Map();
    for (const b of new Set(rows.map((r) => r.buyer_id))) counts.set(b, await noShowCount(pool, b));
    return { days: COD_NO_SHOW_DAYS, max: COD_MAX_NO_SHOWS, items: await Promise.all(rows.map(async (o) => ({ order: await orderOut(o, uid), buyerNoShows: counts.get(o.buyer_id) ?? 0 }))) };
  });
  app.post("/adminapi/market/orders/:id/clear-no-show", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!(await isAdmin(uid))) return bad(reply, 403, "admin-only");
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const o = await loadOrder(req.params.id); if (!o) return bad(reply, 404, "not-found");
    const note = String(req.body?.note ?? "").trim().slice(0, 300);
    const r = await pool.query("UPDATE market_orders SET cancel_reason='no_show_cleared', updated_at=now() WHERE id=$1 AND cancel_reason='no_show' RETURNING id", [o.id]);
    if (!r.rowCount) return bad(reply, 409, "not-no-show");
    await globalThis.naslifeMarketRecomputeSeller?.(o.seller_id)?.catch?.(() => {});
    await notify(o.buyer_id, { kind: "market_status", title: "أُزيل تسجيل عدم حضورك", body: `${o.title}: راجعت الإدارة الطلب وأزالت «لم يحضر» عن حسابك${note ? " · " + note : ""}`, data: { orderId: o.id } });
    await notify(o.seller_id, { kind: "market_status", title: "أُزيل «لم يحضر المشتري»", body: `${o.title}: راجعت الإدارة الطلب وأزالت تسجيل عدم الحضور${note ? " · " + note : ""}`, data: { orderId: o.id } });
    return { ok: true, noShows: await noShowCount(pool, o.buyer_id) };
  });
  // مسح دوري: نشر المجدول، واكتمال الطلبات المسلَّمة التي لم يؤكدها المشتري خلال ٧٢ ساعة
  const sweep = async () => {
    try {
      const due = (await pool.query("UPDATE market_listings SET status='active', bumped_at=now(), updated_at=now() WHERE status='scheduled' AND publish_at <= now() RETURNING *")).rows;
      for (const row of due) globalThis.naslifeMarketOnPublish?.(row).catch?.(() => {});
      const stale = (await pool.query(`${ORDER_SQL} WHERE o.status='delivered' AND o.delivered_at < now() - interval '72 hours' LIMIT 50`)).rows;
      for (const o of stale) { try { await complete(o, { by: "auto" }); } catch { /* تغيّرت حالته */ } }
      // طلب الدفع عند الاستلام لا يبقى معلقاً: بلا قبول خلال ٤٨ ساعة يُلغى ويعود المخزون ويتحرر مكانه من حد المشتري
      const unanswered = (await pool.query(`${ORDER_SQL} WHERE o.status='requested' AND o.payment='cod' AND o.created_at < now() - make_interval(hours => $1) LIMIT 50`, [COD_ACCEPT_HOURS])).rows;
      for (const o of unanswered) {
        try { await refund(o, { reason: "expired", from: ["requested"] }); } catch { continue; }
        await notify(o.buyer_id, { kind: "market_status", title: "أُلغي طلبك", body: `${o.title}: لم يقبله البائع خلال ${COD_ACCEPT_HOURS} ساعة، ولم يُخصم منك شيء`, data: { orderId: o.id, status: "cancelled" } });
        await notify(o.seller_id, { kind: "market_status", title: "أُلغي طلب لم تقبله", body: `${o.title}: مرت ${COD_ACCEPT_HOURS} ساعة بلا قبول فأُلغي وعاد المخزون`, data: { orderId: o.id, status: "cancelled" } });
      }
    } catch (e) { app.log?.warn?.({ err: e?.message }, "market sweep failed"); }
  };
  if (process.env.NODE_ENV !== "test") setInterval(sweep, 5 * 60000).unref?.();
  globalThis.naslifeMarketSweep = sweep;
  globalThis.naslifeWallet = { ledger, tx, sar, person, nickOf, isAdmin, PLATFORM };
}
