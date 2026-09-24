// المرحلة (ب) من السوق: بوابة دفع خارجية (هيكل يُفعَّل بمتغيرات البيئة)، مندوب توصيل على الطلب، بازارات موسمية،
// وترقية البائع إلى دائرة أعمال. يعتمد على commerce.js وmarket_plus.js وbusiness.js (تُسجَّل قبله):
//   await app.register((await import("./market_b.js")).default, { pool, auth });
//
// بوابة الدفع: تُفعَّل بمفاتيح ميسر من لوحة الإدارة (جدول payment_settings عبر /adminapi/payments/config) أو من البيئة
//   MOYASAR_PUBLISHABLE_KEY وMOYASAR_SECRET_KEY (اللوحة لها الأولوية). الشحن عبر البطاقة (مدى/فيزا/أبل باي):
//   POST /pay/topup {amount} → صف في payments + رابط صفحة الدفع /pay/checkout/:id?t=…
//   صفحة الدفع تُحمّل نموذج ميسر وتعود إلى /pay/return?id=<معرّف ميسر> حيث يُتحقق من الدفعة من خادم ميسر بالمفتاح السري
//   (لا يُصدَّق أي شيء يأتي من المتصفح) ثم تُقيَّد للمحفظة مرة واحدة. POST /pay/webhook يمر بالتحقق نفسه.
//   ملاحظة CSP: صفحة الدفع تسمح بسكربت cdn.moyasar.com عبر ترويسة خاصة بها؛ إن كان Caddy يفرض CSP عاماً أضف استثناءً لمسار /pay/*.
import crypto from "node:crypto";
import { CATEGORY_SET } from "./market_taxonomy.js";

const UUID_RE = /^[0-9a-f-]{36}$/i;
const ID_RE = /^[A-Z]{2}\d{7}$/;
const NICK_RE = /^[\p{L}\p{N}_.-]{2,40}$/u;
const MOYASAR_API = "https://api.moyasar.com/v1";
const MPF_SRC = "https://cdn.moyasar.com/mpf/1.14.0/moyasar.js";
const MPF_CSS = "https://cdn.moyasar.com/mpf/1.14.0/moyasar.css";
/// تصنيف السوق → فئة الدائرة عند الترقية
const BIZ_CATEGORY = { coffee: "cafe", food: "restaurant" };

export default async function marketB(app, opts) {
  try { await setup(app, opts); } catch (e) { (app.log?.error ? app.log.error.bind(app.log) : console.error)(`market_b disabled: ${e?.stack || e}`); }
}

async function setup(app, opts) {
  const { pool } = opts; const auth = opts.auth ?? globalThis.naslifeAuth;
  if (!pool || !auth) throw new Error("market_b: pool and auth are required");
  await pool.query(`
    ALTER TABLE market_orders ADD COLUMN IF NOT EXISTS courier_id TEXT;
    ALTER TABLE market_orders ADD COLUMN IF NOT EXISTS courier_note TEXT NOT NULL DEFAULT '';
    ALTER TABLE market_orders ADD COLUMN IF NOT EXISTS courier_at TIMESTAMPTZ;
    CREATE INDEX IF NOT EXISTS market_orders_courier ON market_orders(courier_id) WHERE courier_id IS NOT NULL;
    ALTER TABLE market_listings ADD COLUMN IF NOT EXISTS bazaar_id UUID;
    CREATE INDEX IF NOT EXISTS market_listings_bazaar ON market_listings(bazaar_id) WHERE bazaar_id IS NOT NULL;
    CREATE TABLE IF NOT EXISTS market_bazaars (
      id UUID PRIMARY KEY, title TEXT NOT NULL, description TEXT NOT NULL DEFAULT '', banner_url TEXT, city TEXT NOT NULL DEFAULT '', category TEXT,
      starts_at TIMESTAMPTZ NOT NULL, ends_at TIMESTAMPTZ NOT NULL, created_by TEXT NOT NULL, active BOOLEAN NOT NULL DEFAULT true, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE TABLE IF NOT EXISTS market_seller_upgrades (seller_id TEXT PRIMARY KEY, biz_id TEXT NOT NULL, items INT NOT NULL DEFAULT 0, at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE TABLE IF NOT EXISTS payments (
      id UUID PRIMARY KEY, user_id TEXT NOT NULL, amount BIGINT NOT NULL, currency TEXT NOT NULL DEFAULT 'SAR', provider TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'created',
      provider_ref TEXT UNIQUE, description TEXT NOT NULL DEFAULT '', nonce TEXT NOT NULL, meta JSONB NOT NULL DEFAULT '{}', created_at TIMESTAMPTZ NOT NULL DEFAULT now(), paid_at TIMESTAMPTZ);
    CREATE INDEX IF NOT EXISTS payments_user ON payments(user_id, created_at DESC);
    CREATE TABLE IF NOT EXISTS payment_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_by TEXT, updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
  `);

  const W = () => globalThis.naslifeWallet;
  const settings = () => globalThis.naslifeSettings ?? {};
  const unauthorized = (reply) => reply.code(401).send({ error: "auth" });
  const bad = (reply, code, error, extra = {}) => reply.code(code).send({ error, ...extra });
  const str = (v, max) => String(v ?? "").trim().slice(0, max);
  const notify = async (ids, payload) => { try { await globalThis.naslifeNotify?.(ids, payload); } catch { /* ignore */ } };
  const isAdmin = (id) => W().isAdmin(id);
  const person = (id) => W().person(id);
  const sar = (h) => W().sar(h);
  const listingOut = (l, uid, o) => globalThis.naslifeMarketListingOut(l, uid, o);
  const orderOut = (o, uid) => globalThis.naslifeMarketOrderOut(o, uid);
  const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const origin = (req) => { const proto = String(req.headers["x-forwarded-proto"] ?? req.protocol ?? "https").split(",")[0].trim(); const host = String(req.headers["x-forwarded-host"] ?? req.headers.host ?? "naslife.app").split(",")[0].trim(); return `${proto}://${host}`; };
  const userByNick = async (nick) => { try { return (await pool.query("SELECT id, nickname FROM users WHERE lower(nickname)=lower($1) ORDER BY id LIMIT 1", [nick])).rows[0] ?? null; } catch { return null; } };
  const blocked = async (a, b) => { try { return (await pool.query("SELECT 1 FROM user_blocks WHERE (user_id=$1 AND blocked_id=$2) OR (user_id=$2 AND blocked_id=$1)", [a, b])).rowCount > 0; } catch { return false; } };
  // تصفح الضيف للبازارات (مراجِع المتجر)؛ الانضمام والإدارة بجلسة
  const optionalAuth = async (req) => { try { return (await auth(req)) || null; } catch { return null; } };
  const blockedIds = async (uid) => { try { return uid ? (await globalThis.naslifeBlockedIds?.(uid)) ?? [] : []; } catch { return []; } };
  const ORDER_SQL = "SELECT o.*, l.title, l.image_url, l.kind, (r.order_id IS NOT NULL) AS reviewed FROM market_orders o JOIN market_listings l ON l.id=o.listing_id LEFT JOIN market_reviews r ON r.order_id=o.id";
  const loadOrder = async (id) => (UUID_RE.test(id) ? (await pool.query(`${ORDER_SQL} WHERE o.id=$1`, [id])).rows[0] ?? null : null);

  // =============================== مندوب التوصيل ===============================
  // البائع يعيّن مستخدماً في ناس لايف مندوباً لطلب مفتوح؛ المندوب يرى الطلب في قائمته ويستطيع نقله إلى «في الطريق» و«تم التسليم».
  app.post("/market/orders/:id/courier", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const o = await loadOrder(req.params.id); if (!o) return bad(reply, 404, "not-found");
    if (o.seller_id !== uid) return bad(reply, 403, "seller-only");
    if (!["paid", "preparing", "on_the_way"].includes(o.status)) return bad(reply, 409, "bad-status");
    const b = req.body ?? {};
    let courier = null;
    if (ID_RE.test(String(b.userId ?? ""))) courier = (await pool.query("SELECT id, nickname FROM users WHERE id=$1", [b.userId])).rows[0] ?? null;
    else { const nick = String(b.nickname ?? "").trim().replace(/^@/, ""); if (NICK_RE.test(nick)) courier = await userByNick(nick); }
    if (!courier) return bad(reply, 404, "courier-not-found");
    if (courier.id === o.buyer_id || courier.id === o.seller_id) return bad(reply, 400, "bad-courier");
    if (await blocked(courier.id, o.buyer_id)) return bad(reply, 403, "blocked");
    const note = str(b.note, 200);
    await pool.query("UPDATE market_orders SET courier_id=$2, courier_note=$3, courier_at=now(), updated_at=now() WHERE id=$1", [o.id, courier.id, note]);
    await notify(courier.id, { kind: "market_courier", title: "كُلّفت بتوصيل طلب", body: `${o.title}: من ${await W().nickOf(o.seller_id)}${note ? " · " + note : ""}`, data: { orderId: o.id } });
    await notify(o.buyer_id, { kind: "market_status", title: "تعيين مندوب توصيل", body: `${o.title}: سيوصله ${courier.nickname}`, data: { orderId: o.id } });
    return orderOut(await loadOrder(o.id), uid);
  });
  app.delete("/market/orders/:id/courier", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const o = await loadOrder(req.params.id); if (!o) return bad(reply, 404, "not-found");
    if (o.seller_id !== uid) return bad(reply, 403, "seller-only");
    if (o.courier_id) await notify(o.courier_id, { kind: "market_courier", title: "أُلغي تكليفك بالتوصيل", body: o.title, data: { orderId: o.id } });
    await pool.query("UPDATE market_orders SET courier_id=NULL, courier_note='', courier_at=NULL, updated_at=now() WHERE id=$1", [o.id]);
    return orderOut(await loadOrder(o.id), uid);
  });

  // =============================== البازارات ===============================
  const bazaarOut = (b, uid) => ({
    id: b.id, title: b.title, description: b.description, bannerUrl: b.banner_url ?? null, city: b.city, category: b.category ?? null, startsAt: b.starts_at, endsAt: b.ends_at, active: b.active,
    listings: Number(b.n ?? 0), mine: Number(b.mine ?? 0), state: !b.active || b.ends_at <= new Date() ? "ended" : b.starts_at > new Date() ? "upcoming" : "live", createdBy: b.created_by === uid,
  });
  const BAZAAR_SQL = (uid) => `SELECT b.*, (SELECT count(*)::int FROM market_listings l WHERE l.bazaar_id=b.id AND l.status='active') AS n, (SELECT count(*)::int FROM market_listings l WHERE l.bazaar_id=b.id AND l.seller_id=${uid}) AS mine FROM market_bazaars b`;
  const activeBazaars = async (uid) => (await pool.query(`${BAZAAR_SQL("$1")} WHERE b.active AND b.ends_at > now() ORDER BY (b.starts_at <= now()) DESC, b.starts_at ASC LIMIT 6`, [uid])).rows.map((b) => bazaarOut(b, uid));
  globalThis.naslifeMarketBazaars = activeBazaars;
  app.get("/market/bazaars", async (req) => {
    const uid = await optionalAuth(req);
    return activeBazaars(uid);
  });
  app.get("/market/bazaars/:id", async (req, reply) => {
    const uid = await optionalAuth(req);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const b = (await pool.query(`${BAZAAR_SQL("$2")} WHERE b.id=$1`, [req.params.id, uid])).rows[0]; if (!b) return bad(reply, 404, "not-found");
    const lat = Number(req.query?.lat), lng = Number(req.query?.lng); const hasPos = Number.isFinite(lat) && Number.isFinite(lng);
    const dist = hasPos ? "(CASE WHEN lat IS NULL OR lng IS NULL THEN NULL ELSE 6371 * acos(least(1::float8, cos(radians($2)) * cos(radians(lat)) * cos(radians(lng) - radians($3)) + sin(radians($2)) * sin(radians(lat)))) END)" : "NULL::float8";
    const r = await pool.query(`SELECT *, ${dist} AS dist FROM market_listings WHERE bazaar_id=$1 AND status='active' ORDER BY (spotlight_until > now()) DESC NULLS LAST, bumped_at DESC LIMIT 200`, hasPos ? [b.id, lat, lng] : [b.id]);
    const hide = new Set(await blockedIds(uid));
    return { ...bazaarOut(b, uid), items: await Promise.all(r.rows.filter((l) => !hide.has(l.seller_id)).map((l) => listingOut(l, uid, { dist: l.dist }))) };
  });
  app.post("/market/bazaars/:id/join", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id) || !UUID_RE.test(String(req.body?.listingId ?? ""))) return bad(reply, 400, "bad-id");
    const b = (await pool.query("SELECT * FROM market_bazaars WHERE id=$1", [req.params.id])).rows[0]; if (!b) return bad(reply, 404, "not-found");
    if (!b.active || b.ends_at <= new Date()) return bad(reply, 409, "bazaar-ended");
    const l = (await pool.query("SELECT * FROM market_listings WHERE id=$1", [req.body.listingId])).rows[0]; if (!l) return bad(reply, 404, "not-found");
    if (l.seller_id !== uid) return bad(reply, 403, "owner-only");
    if (b.category && l.category !== b.category) return bad(reply, 400, "bazaar-category", { category: b.category });
    await pool.query("UPDATE market_listings SET bazaar_id=$2, updated_at=now() WHERE id=$1", [l.id, b.id]);
    return { ok: true, bazaarId: b.id };
  });
  app.delete("/market/bazaars/:id/join/:listingId", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id) || !UUID_RE.test(req.params.listingId)) return bad(reply, 400, "bad-id");
    const r = await pool.query("UPDATE market_listings SET bazaar_id=NULL, updated_at=now() WHERE id=$1 AND bazaar_id=$2 AND seller_id=$3 RETURNING id", [req.params.listingId, req.params.id, uid]);
    if (!r.rowCount) return bad(reply, 404, "not-found");
    return { ok: true };
  });
  const bazaarFields = (b, { partial = false } = {}) => {
    const out = {}; const has = (k) => b[k] !== undefined;
    if (!partial || has("title")) out.title = str(b.title, 80);
    if (!partial || has("description")) out.description = str(b.description, 1000);
    if (!partial || has("city")) out.city = str(b.city, 60);
    if (!partial || has("category")) out.category = CATEGORY_SET.has(b.category) ? b.category : null;
    if (!partial || has("bannerUrl")) out.banner_url = /^(https?:)?\//.test(String(b.bannerUrl ?? "")) ? str(b.bannerUrl, 500) : null;
    if (!partial || has("startsAt")) { const d = new Date(b.startsAt ?? Date.now()); out.starts_at = Number.isNaN(d.getTime()) ? new Date() : d; }
    if (!partial || has("endsAt")) { const d = new Date(b.endsAt ?? 0); out.ends_at = Number.isNaN(d.getTime()) ? null : d; }
    if (partial && has("active")) out.active = b.active === true;
    return out;
  };
  app.get("/adminapi/market/bazaars", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply); if (!(await isAdmin(uid))) return bad(reply, 403, "admin-only");
    return (await pool.query(`${BAZAAR_SQL("$1")} ORDER BY b.ends_at DESC LIMIT 100`, [uid])).rows.map((b) => bazaarOut(b, uid));
  });
  app.post("/adminapi/market/bazaars", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply); if (!(await isAdmin(uid))) return bad(reply, 403, "admin-only");
    const f = bazaarFields(req.body ?? {});
    if (!f.title) return bad(reply, 400, "bad-title");
    if (!f.ends_at || f.ends_at <= f.starts_at) return bad(reply, 400, "bad-dates");
    const id = crypto.randomUUID();
    await pool.query("INSERT INTO market_bazaars(id, title, description, banner_url, city, category, starts_at, ends_at, created_by) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)", [id, f.title, f.description, f.banner_url, f.city, f.category, f.starts_at, f.ends_at, uid]);
    globalThis.naslifeAudit?.(uid, "market.bazaar.create", id, { title: f.title })?.catch?.(() => {});
    // إشعار البائعين النشطين في التصنيف (أو الكل) بفتح باب المشاركة
    try {
      const sellers = (await pool.query(`SELECT DISTINCT seller_id FROM market_listings WHERE status='active'${f.category ? " AND category=$1" : ""} LIMIT 500`, f.category ? [f.category] : [])).rows.map((r) => r.seller_id);
      if (sellers.length) await notify(sellers, { kind: "market_bazaar", title: `بازار جديد: ${f.title}`, body: "أضف عروضك إلى البازار من صفحة العرض أو نموذج التعديل", data: { bazaarId: id } });
    } catch { /* ignore */ }
    const b = (await pool.query(`${BAZAAR_SQL("$2")} WHERE b.id=$1`, [id, uid])).rows[0];
    return bazaarOut(b, uid);
  });
  app.patch("/adminapi/market/bazaars/:id", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply); if (!(await isAdmin(uid))) return bad(reply, 403, "admin-only");
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const f = bazaarFields(req.body ?? {}, { partial: true });
    const keys = Object.keys(f).filter((k) => f[k] !== undefined && !(k === "ends_at" && f[k] === null));
    if (keys.length) await pool.query(`UPDATE market_bazaars SET ${keys.map((k, i) => `${k}=$${i + 2}`).join(", ")} WHERE id=$1`, [req.params.id, ...keys.map((k) => f[k])]);
    const b = (await pool.query(`${BAZAAR_SQL("$2")} WHERE b.id=$1`, [req.params.id, uid])).rows[0]; if (!b) return bad(reply, 404, "not-found");
    return bazaarOut(b, uid);
  });

  // =============================== ترقية البائع إلى دائرة أعمال ===============================
  const upgradePreview = async (uid) => {
    const done = (await pool.query("SELECT biz_id, items, at FROM market_seller_upgrades WHERE seller_id=$1", [uid])).rows[0] ?? null;
    const ls = (await pool.query("SELECT id, title, description, price, image_url, kind, category, lat, lng, city, place_name FROM market_listings WHERE seller_id=$1 AND status='active' ORDER BY sold DESC, created_at ASC LIMIT 60", [uid])).rows;
    const completed = (await pool.query("SELECT count(*)::int AS n FROM market_orders WHERE seller_id=$1 AND status='completed'", [uid])).rows[0].n;
    const cats = {}; for (const l of ls) cats[l.category] = (cats[l.category] ?? 0) + 1;
    const top = Object.entries(cats).sort((a, b) => b[1] - a[1])[0]?.[0] ?? null;
    const withPos = ls.filter((l) => l.lat != null && l.lng != null);
    const lat = withPos.length ? withPos.reduce((s, l) => s + Number(l.lat), 0) / withPos.length : null, lng = withPos.length ? withPos.reduce((s, l) => s + Number(l.lng), 0) / withPos.length : null;
    const p = await person(uid);
    return {
      upgraded: done ? { bizId: done.biz_id, items: done.items, at: done.at } : null, eligible: !done && ls.length >= 1, listings: ls.length, completed,
      suggestedName: p?.nickname ?? "", suggestedCategory: BIZ_CATEGORY[top] ?? "brand", marketCategory: top, city: ls.find((l) => l.city)?.city ?? "", address: ls.find((l) => l.place_name)?.place_name ?? "", lat, lng, rows: ls,
    };
  };
  app.get("/market/seller/upgrade", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const { rows: _rows, ...out } = await upgradePreview(uid);
    return out;
  });
  app.post("/market/seller/upgrade", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const pv = await upgradePreview(uid);
    if (pv.upgraded) return bad(reply, 409, "already-upgraded", { bizId: pv.upgraded.bizId });
    if (!pv.eligible) return bad(reply, 409, "no-listings");
    const b = req.body ?? {};
    const lat = Number.isFinite(Number(b.lat)) ? Number(b.lat) : pv.lat, lng = Number.isFinite(Number(b.lng)) ? Number(b.lng) : pv.lng;
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) return bad(reply, 400, "bad-location");
    const nameAr = str(b.nameAr ?? b.name, 60) || pv.suggestedName;
    const payload = {
      name: str(b.name, 60) || nameAr, nameAr, category: str(b.category, 30) || pv.suggestedCategory, sector: str(b.sector, 60) || "سوق ناس لايف", description: str(b.description, 2000),
      lat, lng, address: str(b.address, 200) || [pv.city, pv.address].filter(Boolean).join(" · "), hours: str(b.hours, 120), highlights: ["بائع من سوق ناس لايف"],
    };
    // إنشاء الدائرة عبر مسار business.js نفسه (بترويسات الطلب الأصلية حتى تمر المصادقة كما هي)
    const headers = { ...req.headers, "content-type": "application/json" }; delete headers["content-length"]; delete headers.host;
    const res = await app.inject({ method: "POST", url: "/biz", headers, payload });
    if (res.statusCode !== 200) { let j = {}; try { j = res.json(); } catch { /* ignore */ } return bad(reply, res.statusCode === 404 ? 503 : res.statusCode, j.error ?? "biz-failed"); }
    const biz = res.json(); const bizId = biz.id;
    // نسخ العروض النشطة إلى كتالوج الدائرة (المنتجات والخدمات كأصناف من نوع product)
    let items = 0;
    if (b.copyListings !== false) {
      for (const [i, l] of pv.rows.entries()) {
        try {
          await pool.query("INSERT INTO biz_items(id, biz_id, kind, title, description, price, unit, stock, meta, image_url, active, sort) VALUES($1,$2,'product',$3,$4,$5,$6,NULL,$7,$8,true,$9)",
            [`itm-${crypto.randomBytes(4).toString("hex")}`, bizId, l.title, str(l.description, 2000), Number(l.price), l.kind === "service" ? "service" : "item", JSON.stringify({ listingId: l.id, marketCategory: l.category }), l.image_url ?? null, i]);
          items++;
        } catch (e) { app.log?.warn?.({ err: e?.message }, "market_b: item copy failed"); }
      }
    }
    await pool.query("INSERT INTO market_seller_upgrades(seller_id, biz_id, items) VALUES($1,$2,$3) ON CONFLICT (seller_id) DO UPDATE SET biz_id=EXCLUDED.biz_id, items=EXCLUDED.items, at=now()", [uid, bizId, items]);
    await notify(uid, { kind: "biz", title: "أصبح لديك دائرة أعمال", body: `${payload.nameAr}: أُنشئت بكتالوج من ${items} صنفاً. أكمل ملفها من لوحة المالك`, data: { bizId } });
    globalThis.naslifeNotifyAdmins?.({ kind: "biz", title: "ترقية بائع إلى دائرة", body: `${await W().nickOf(uid)} → ${payload.nameAr}`, data: { bizId } })?.catch?.(() => {});
    return { ok: true, bizId, items, biz };
  });

  // =============================== بوابة الدفع (هيكل) ===============================
  const fetchImpl = (...a) => (globalThis.naslifePayFetch ?? globalThis.fetch)(...a);
  // مفاتيح اللوحة تُحمَّل مرة عند الإقلاع وتُحدَّث عند الحفظ (جدول منفصل عن platform_settings كي لا يظهر السر في إعدادات الإدارة العامة)
  const panel = { publishableKey: "", secretKey: "", webhookSecret: "", updatedAt: null, updatedBy: null };
  const loadPanel = async () => {
    const rows = (await pool.query("SELECT key, value, updated_by, updated_at FROM payment_settings")).rows;
    panel.publishableKey = ""; panel.secretKey = ""; panel.webhookSecret = ""; panel.updatedAt = null; panel.updatedBy = null;
    for (const r of rows) { if (r.key in panel && typeof panel[r.key] === "string") panel[r.key] = r.value; if (!panel.updatedAt || r.updated_at > panel.updatedAt) { panel.updatedAt = r.updated_at; panel.updatedBy = r.updated_by; } }
  };
  await loadPanel();
  const KEY_RE = { publishableKey: /^pk_(test|live)_[A-Za-z0-9]{8,120}$/, secretKey: /^sk_(test|live)_[A-Za-z0-9]{8,120}$/ };
  const keyMode = (k) => (/^[ps]k_test_/.test(k) ? "test" : /^[ps]k_live_/.test(k) ? "live" : null);
  const PAY = () => {
    const env = { publishableKey: process.env.MOYASAR_PUBLISHABLE_KEY ?? "", secretKey: process.env.MOYASAR_SECRET_KEY ?? "", webhookSecret: process.env.MOYASAR_WEBHOOK_SECRET ?? "" };
    const source = panel.publishableKey && panel.secretKey ? "panel" : env.publishableKey && env.secretKey ? "env" : null;
    const k = source === "panel" ? panel : source === "env" ? env : { publishableKey: "", secretKey: "", webhookSecret: "" };
    const enabled = !!source;
    const max = Number(settings().maxTopup) || Number(process.env.PAY_MAX) || 500000;
    return { enabled, source, mode: enabled ? keyMode(k.secretKey) ?? keyMode(k.publishableKey) : null, provider: "moyasar", publishableKey: k.publishableKey, secretKey: k.secretKey, min: Number(process.env.PAY_MIN) || 1000, max, methods: (process.env.PAY_METHODS ?? "creditcard,stcpay").split(",").map((s) => s.trim()).filter(Boolean), webhookSecret: k.webhookSecret, envPresent: !!(env.publishableKey && env.secretKey) };
  };
  const hint = (k) => (k ? `${k.slice(0, k.indexOf("_", 3) + 1)}…${k.slice(-4)}` : "");
  const adminConfigOut = (req) => {
    const c = PAY();
    return { enabled: c.enabled, provider: c.provider, mode: c.mode, source: c.source, envPresent: c.envPresent, publishableKey: c.publishableKey || null, secretKeySet: !!c.secretKey, secretKeyHint: hint(c.secretKey), webhookSecretSet: !!c.webhookSecret,
      panelKeysSet: !!(panel.publishableKey && panel.secretKey), updatedAt: panel.updatedAt, updatedBy: panel.updatedBy, methods: c.methods, min: c.min, max: c.max, currency: "SAR", returnUrl: `${origin(req)}/pay/return`, webhookUrl: `${origin(req)}/pay/webhook` };
  };
  app.get("/adminapi/payments/config", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply); if (!(await isAdmin(uid))) return bad(reply, 403, "admin-only");
    return adminConfigOut(req);
  });
  // حفظ المفاتيح من اللوحة: حقل غير مرسل يبقى كما هو، وحقل فارغ يُمسح. الفارغان معاً يعيدان الاعتماد على البيئة
  app.put("/adminapi/payments/config", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply); if (!(await isAdmin(uid))) return bad(reply, 403, "admin-only");
    const b = req.body ?? {}; const next = { ...panel };
    for (const f of ["publishableKey", "secretKey", "webhookSecret"]) {
      if (b[f] === undefined) continue;
      const v = str(b[f], 200).replace(/\s+/g, "");
      if (v && /[*•●]/.test(v)) return bad(reply, 400, "masked-key", { field: f }); // منسوخ من اللوحة وهو مقنّع
      if (v && KEY_RE[f] && !KEY_RE[f].test(v)) return bad(reply, 400, "bad-key", { field: f });
      next[f] = v;
    }
    if (!!next.publishableKey !== !!next.secretKey) return bad(reply, 400, "both-keys-required");
    if (next.publishableKey && keyMode(next.publishableKey) !== keyMode(next.secretKey)) return bad(reply, 400, "mode-mismatch");
    for (const f of ["publishableKey", "secretKey", "webhookSecret"]) {
      if (next[f]) await pool.query("INSERT INTO payment_settings(key, value, updated_by, updated_at) VALUES($1,$2,$3,now()) ON CONFLICT (key) DO UPDATE SET value=EXCLUDED.value, updated_by=EXCLUDED.updated_by, updated_at=now()", [f, next[f], uid]);
      else await pool.query("DELETE FROM payment_settings WHERE key=$1", [f]);
    }
    await loadPanel();
    globalThis.naslifeAudit?.(uid, "payments.config", "moyasar", { mode: PAY().mode, source: PAY().source, publishableKey: next.publishableKey || null })?.catch?.(() => {});
    return adminConfigOut(req);
  });
  // فحص الاتصال: طلب صغير إلى ميسر بالمفتاح السري الحالي (200 = المفتاح صحيح، 401 = خاطئ)
  app.post("/adminapi/payments/test", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply); if (!(await isAdmin(uid))) return bad(reply, 403, "admin-only");
    const c = PAY(); if (!c.enabled) return { ok: false, error: "payments-disabled", mode: null };
    try {
      const r = await fetchImpl(`${MOYASAR_API}/payments?per=1`, { headers: { authorization: basicAuth(c.secretKey) }, signal: AbortSignal.timeout(8000) });
      if (!r.ok) {
        let j = null; try { j = await r.json(); } catch { /* ignore */ }
        const type = String(j?.type ?? ""), message = String(j?.message ?? "").slice(0, 200);
        if (r.status === 401 || r.status === 403) return { ok: false, error: "bad-secret", status: r.status, mode: c.mode, source: c.source, message };
        // ميسر يردّ 405 (account_inactive_error) عندما يكون الحساب الحي غير مفعّل بعد مع أن المفتاح صحيح
        if (r.status === 405 || type === "account_inactive_error") return { ok: false, error: "account-inactive", status: r.status, mode: c.mode, source: c.source, message };
        return { ok: false, error: `provider-${r.status}`, status: r.status, mode: c.mode, source: c.source, type, message };
      }
      let count = null; try { const j = await r.json(); count = Array.isArray(j?.payments) ? j.payments.length : null; } catch { /* ignore */ }
      return { ok: true, status: r.status, mode: c.mode, source: c.source, recentPayments: count };
    } catch (e) { return { ok: false, error: "provider-unreachable", message: String(e?.message ?? e).slice(0, 120), mode: c.mode, source: c.source }; }
  });
  const payOut = (p) => ({ id: p.id, amount: Number(p.amount), currency: p.currency, provider: p.provider, status: p.status, providerRef: p.provider_ref ?? null, description: p.description, createdAt: p.created_at, paidAt: p.paid_at ?? null });
  app.get("/pay/config", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const c = PAY();
    return { enabled: c.enabled, provider: c.provider, methods: c.methods, min: c.min, max: c.max, currency: "SAR", publishableKey: c.enabled ? c.publishableKey : null };
  });
  // الشحن: افتراضياً صفحة دفع مستضافة لدى ميسر (فاتورة) لأنها لا تتأثر بسياسة CSP العامة على نطاقنا وتدعم أبل باي من نطاق ميسر؛
  // PAY_EMBED=1 يعيد النموذج المضمّن في /pay/checkout/:id (يحتاج استثناء CSP لمسار /pay/* في Caddy).
  const basicAuth = (sk) => "Basic " + Buffer.from(`${sk}:`).toString("base64");
  app.post("/pay/topup", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    // نسخة iOS الأولى بلا شحن بالبطاقة (قرار تنظيمي معلّق وسياسة أبل للمحافظ)؛ الويب كما هو
    if (/^ios\//i.test(String(req.headers["x-naslife-client"] ?? ""))) return bad(reply, 403, "unavailable");
    const c = PAY(); if (!c.enabled) return bad(reply, 503, "payments-disabled");
    const amount = Math.round(Number(req.body?.amount) || 0);
    if (amount < c.min || amount > c.max) return bad(reply, 400, "bad-amount", { min: c.min, max: c.max });
    const id = crypto.randomUUID(), nonce = crypto.randomBytes(12).toString("hex");
    const description = `شحن محفظة ناس لايف ${sar(amount)}`;
    if (process.env.PAY_EMBED === "1") {
      await pool.query("INSERT INTO payments(id, user_id, amount, provider, description, nonce) VALUES($1,$2,$3,$4,$5,$6)", [id, uid, amount, c.provider, description, nonce]);
      return { id, amount, currency: "SAR", checkoutUrl: `${origin(req)}/pay/checkout/${id}?t=${nonce}`, expiresInMinutes: 30, hosted: false };
    }
    let inv;
    const base = { amount, currency: "SAR", description, callback_url: `${origin(req)}/pay/return`, expired_at: new Date(Date.now() + 30 * 60e3).toISOString(), metadata: { naslife_payment: id, naslife_user: uid } };
    // روابط النجاح والرجوع والشعار اختيارية لدى ميسر؛ إن رُفضت يُعاد الطلب بالحقول الأساسية فقط
    const extras = { success_url: `${origin(req)}/pay/return?p=${id}`, back_url: `${origin(req)}/pay/return?p=${id}&back=1`, logo_url: process.env.PAY_LOGO_URL || `${origin(req)}/icons/Icon-512.png` };
    const createInvoice = (body) => fetchImpl(`${MOYASAR_API}/invoices`, { method: "POST", headers: { authorization: basicAuth(c.secretKey), "content-type": "application/json" }, signal: AbortSignal.timeout(10000), body: JSON.stringify(body) });
    try {
      let r = await createInvoice({ ...base, ...extras });
      if (r.status === 400 || r.status === 422) { app.log?.warn?.({ status: r.status }, "market_b: invoice extras rejected, retrying without them"); r = await createInvoice(base); }
      if (!r.ok) {
        let t = ""; try { t = (await r.text()).slice(0, 300); } catch { /* ignore */ }
        app.log?.warn?.({ status: r.status, body: t }, "market_b: invoice create failed");
        if (r.status === 405 || t.includes("account_inactive_error")) return bad(reply, 503, "payments-inactive");
        return bad(reply, 502, "provider-error", { status: r.status });
      }
      inv = await r.json();
    } catch (e) { app.log?.warn?.({ err: e?.message }, "market_b: invoice create unreachable"); return bad(reply, 502, "provider-unreachable"); }
    if (!inv?.id || !inv?.url) return bad(reply, 502, "provider-error");
    // صفحة ميسر تدعم العربية عبر lang=ar
    const pageUrl = /[?&]lang=/.test(String(inv.url)) ? String(inv.url).replace(/([?&])lang=[a-z-]+/i, "$1lang=ar") : `${inv.url}${String(inv.url).includes("?") ? "&" : "?"}lang=ar`;
    await pool.query("INSERT INTO payments(id, user_id, amount, provider, description, nonce, meta) VALUES($1,$2,$3,$4,$5,$6,$7)", [id, uid, amount, c.provider, description, nonce, JSON.stringify({ hosted: true, invoiceId: String(inv.id), invoiceUrl: pageUrl })]);
    return { id, amount, currency: "SAR", checkoutUrl: pageUrl, expiresInMinutes: 30, hosted: true };
  });
  // دفعات بدأت ولم تكتمل خلال ٤٥ دقيقة تُعلَّم منتهية عند العرض (الفاتورة لدى ميسر تنتهي بعد ٣٠ دقيقة)
  const expireStale = () => pool.query("UPDATE payments SET status='expired' WHERE status='created' AND created_at < now() - interval '45 minutes'").catch(() => {});
  app.get("/pay/mine", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    await expireStale();
    return (await pool.query("SELECT * FROM payments WHERE user_id=$1 ORDER BY created_at DESC LIMIT 50", [uid])).rows.map(payOut);
  });
  app.get("/adminapi/payments", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply); if (!(await isAdmin(uid))) return bad(reply, 403, "admin-only");
    await expireStale();
    const rows = (await pool.query("SELECT * FROM payments ORDER BY created_at DESC LIMIT 200")).rows;
    return { enabled: PAY().enabled, provider: PAY().provider, mode: PAY().mode, source: PAY().source, items: await Promise.all(rows.map(async (p) => ({ ...payOut(p), user: await person(p.user_id) }))) };
  });
  // صفحة الدفع: نموذج ميسر (HTML بسيط بالعربية) يعود إلى /pay/return
  const htmlPage = (title, body) => `<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(title)}</title>
<style>body{font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;background:#f6f4ef;color:#1f1b16;margin:0;padding:24px;display:flex;justify-content:center}main{background:#fff;border-radius:20px;padding:24px;max-width:460px;width:100%;box-shadow:0 8px 30px rgba(0,0,0,.06)}h1{font-size:20px;margin:0 0 6px}p{color:#6b6257;margin:0 0 16px;font-size:14px}.amt{font-size:30px;font-weight:800;margin:8px 0 18px}a.btn{display:inline-block;background:#1f6f5f;color:#fff;text-decoration:none;padding:12px 18px;border-radius:14px;font-weight:700}</style></head><body><main>${body}</main></body></html>`;
  app.get("/pay/checkout/:id", async (req, reply) => {
    const c = PAY();
    const p = UUID_RE.test(req.params.id) ? (await pool.query("SELECT * FROM payments WHERE id=$1", [req.params.id])).rows[0] : null;
    if (!p || p.nonce !== String(req.query?.t ?? "")) return reply.code(404).type("text/html; charset=utf-8").send(htmlPage("غير موجود", "<h1>رابط الدفع غير صالح</h1><p>افتح المحفظة في ناس لايف وابدأ الشحن من جديد.</p>"));
    if (p.status === "paid") return reply.type("text/html; charset=utf-8").send(htmlPage("تم الشحن", `<h1>تم شحن المحفظة</h1><div class="amt">${esc(sar(p.amount))}</div><a class="btn" href="/">العودة إلى ناس لايف</a>`));
    if (!c.enabled) return reply.code(503).type("text/html; charset=utf-8").send(htmlPage("غير متاح", "<h1>الدفع بالبطاقة غير مفعّل حالياً</h1><p>سيتوفر قريباً؛ يمكنك الشحن عبر الإدارة في الوقت الحالي.</p>"));
    // أبل باي يحتاج إعدادات إضافية وتسجيل النطاق في لوحة ميسر؛ لا يُضاف إلا إذا كان ضمن PAY_METHODS
    const applePay = c.methods.includes("applepay") ? { country: process.env.PAY_APPLEPAY_COUNTRY || "SA", label: process.env.PAY_APPLEPAY_LABEL || "ناس لايف", validate_merchant_url: "https://api.moyasar.com/v1/applepay/initiate" } : undefined;
    const cfg = { element: ".mysr-form", amount: Number(p.amount), currency: "SAR", description: p.description, publishable_api_key: c.publishableKey, callback_url: `${origin(req)}/pay/return`, methods: c.methods, metadata: { naslife_payment: p.id, naslife_user: p.user_id }, language: "ar", ...(applePay ? { apple_pay: applePay } : {}) };
    const body = `<h1>شحن محفظة ناس لايف</h1><p>ادفع بمدى أو البطاقة${c.methods.includes("applepay") ? " أو أبل باي" : ""}. يُضاف المبلغ لمحفظتك فور نجاح العملية.</p><div class="amt">${esc(sar(p.amount))}</div><div class="mysr-form"></div><p id="pay-err" style="color:#b3261e;display:none"></p>
<p style="margin-top:18px"><a class="btn" href="/" style="background:#eee;color:#1f1b16">العودة إلى ناس لايف</a></p>
<link rel="stylesheet" href="${MPF_CSS}"><script src="${MPF_SRC}" onerror="document.getElementById('pay-err').style.display='block';document.getElementById('pay-err').textContent='تعذر تحميل نموذج الدفع؛ تحقق من الاتصال ثم أعد فتح الرابط.'"></script>
<script>try{Moyasar.init(${JSON.stringify(cfg)});}catch(e){var el=document.getElementById('pay-err');el.style.display='block';el.textContent='تعذر تهيئة نموذج الدفع: '+(e&&e.message?e.message:e);}</script>`;
    return reply.type("text/html; charset=utf-8").header("cache-control", "no-store")
      .header("content-security-policy", `default-src 'self'; script-src 'self' 'unsafe-inline' https://*.moyasar.com; style-src 'self' 'unsafe-inline' https://*.moyasar.com; img-src 'self' data: https://*.moyasar.com; font-src 'self' data: https://*.moyasar.com; connect-src 'self' https://*.moyasar.com; frame-src https://*.moyasar.com`)
      .send(htmlPage("شحن المحفظة", body));
  });
  // التحقق من الدفعة عند ميسر ثم قيدها للمحفظة مرة واحدة (idempotent على provider_ref)
  const settle = async (providerId) => {
    const c = PAY(); if (!c.enabled) return { ok: false, error: "payments-disabled" };
    if (!/^[A-Za-z0-9_-]{6,80}$/.test(String(providerId ?? ""))) return { ok: false, error: "bad-id" };
    let j;
    try {
      const r = await fetchImpl(`${MOYASAR_API}/payments/${providerId}`, { headers: { authorization: basicAuth(c.secretKey) }, signal: AbortSignal.timeout(10000) });
      if (!r.ok) return { ok: false, error: `provider-${r.status}` };
      j = await r.json();
    } catch (e) { return { ok: false, error: "provider-unreachable" }; }
    const pid = j?.metadata?.naslife_payment;
    let p = UUID_RE.test(String(pid ?? "")) ? (await pool.query("SELECT * FROM payments WHERE id=$1", [pid])).rows[0] : null;
    // دفعات الفاتورة المستضافة قد لا تحمل بياناتنا الوصفية؛ نجدها بمعرّف الفاتورة المحفوظ عند الإنشاء
    if (!p && j?.invoice_id) p = (await pool.query("SELECT * FROM payments WHERE provider='moyasar' AND meta->>'invoiceId'=$1 ORDER BY created_at DESC LIMIT 1", [String(j.invoice_id)])).rows[0];
    if (!p) return { ok: false, error: pid || j?.invoice_id ? "not-found" : "no-metadata" };
    if (j.status !== "paid") { await pool.query("UPDATE payments SET status=$2, provider_ref=COALESCE(provider_ref,$3), meta=meta || $4 WHERE id=$1 AND status<>'paid'", [p.id, j.status === "failed" ? "failed" : "pending", String(j.id), JSON.stringify({ providerStatus: j.status, message: j.source?.message ?? null })]); return { ok: false, error: "not-paid", status: j.status, payment: p }; }
    if (Number(j.amount) !== Number(p.amount) || String(j.currency ?? "SAR").toUpperCase() !== "SAR") return { ok: false, error: "amount-mismatch" };
    let credited = false;
    await W().tx(async (client) => {
      const r = await client.query("UPDATE payments SET status='paid', provider_ref=$2, paid_at=now(), meta=meta || $3 WHERE id=$1 AND status<>'paid' RETURNING id", [p.id, String(j.id), JSON.stringify({ source: j.source?.type ?? null, company: j.source?.company ?? null })]);
      if (!r.rowCount) return;
      await W().ledger(client, p.user_id, "topup", Number(p.amount), { note: `شحن بالبطاقة (${j.source?.company ?? j.source?.type ?? "بطاقة"})`, ref: p.id });
      credited = true;
    });
    if (credited) await notify(p.user_id, { kind: "wallet", title: "تم شحن محفظتك", body: sar(p.amount), data: { paymentId: p.id } });
    return { ok: true, credited, payment: { ...p, status: "paid" } };
  };
  // العودة من صفحة ميسر: إمّا بمعرّف الدفعة (callback) أو بمعرّفنا p (success_url/back_url) فنسأل ميسر عن دفعات الفاتورة
  const settleByOurs = async (ourId, back) => {
    if (!UUID_RE.test(String(ourId ?? ""))) return { ok: false, error: "bad-id" };
    const p = (await pool.query("SELECT * FROM payments WHERE id=$1", [ourId])).rows[0]; if (!p) return { ok: false, error: "not-found" };
    if (p.status === "paid") return { ok: true, credited: false, payment: p };
    const c = PAY(); const invId = p.meta?.invoiceId; if (!c.enabled || !invId) return { ok: false, error: back ? "cancelled" : "not-paid", status: p.status, payment: p };
    try {
      const r = await fetchImpl(`${MOYASAR_API}/invoices/${encodeURIComponent(invId)}`, { headers: { authorization: basicAuth(c.secretKey) }, signal: AbortSignal.timeout(10000) });
      if (!r.ok) return { ok: false, error: `provider-${r.status}` };
      const inv = await r.json();
      const paid = (inv?.payments ?? []).find((x) => x?.status === "paid") ?? (inv?.payments ?? []).at(-1);
      if (!paid?.id) return { ok: false, error: back ? "cancelled" : "not-paid", status: inv?.status ?? p.status, payment: p };
      return settle(paid.id);
    } catch { return { ok: false, error: "provider-unreachable" }; }
  };
  app.get("/pay/return", async (req, reply) => {
    const r = req.query?.id ? await settle(req.query.id) : await settleByOurs(req.query?.p, req.query?.back === "1");
    if (r.ok) return reply.type("text/html; charset=utf-8").send(htmlPage("تم الشحن", `<h1>تم شحن المحفظة</h1><div class="amt">${esc(sar(r.payment.amount))}</div><p>يمكنك إغلاق هذه الصفحة والعودة إلى التطبيق.</p><a class="btn" href="/">العودة إلى ناس لايف</a>`));
    const msg = r.error === "cancelled" ? "أُلغيت العملية قبل الدفع. لم يُخصم شيء، ويمكنك المحاولة من المحفظة متى شئت." : r.error === "not-paid" ? `لم تكتمل العملية (${esc(String(req.query?.message ?? r.status ?? ""))}). لم يُخصم شيء.` : r.error === "payments-disabled" ? "الدفع بالبطاقة غير مفعّل." : "تعذر التحقق من العملية؛ إن خُصم المبلغ فسيُضاف تلقائياً خلال دقائق.";
    return reply.code(r.error === "cancelled" ? 200 : r.error === "not-paid" ? 402 : 400).type("text/html; charset=utf-8").send(htmlPage("لم تكتمل", `<h1>${r.error === "cancelled" ? "أُلغيت عملية الدفع" : "لم تكتمل عملية الدفع"}</h1><p>${msg}</p><a class="btn" href="/">العودة إلى ناس لايف</a>`));
  });
  app.post("/pay/webhook", async (req, reply) => {
    const c = PAY(); if (!c.enabled) return bad(reply, 503, "payments-disabled");
    // ميسر يضع السر في جسم الطلب (secret_token)؛ نقبل أيضاً ترويسة x-webhook-secret أو Authorization: Bearer للاختبار اليدوي
    const given = String(req.body?.secret_token ?? req.headers["x-webhook-secret"] ?? req.headers.authorization ?? "").replace(/^Bearer /, "");
    if (c.webhookSecret && (given.length !== c.webhookSecret.length || !crypto.timingSafeEqual(Buffer.from(given), Buffer.from(c.webhookSecret)))) return bad(reply, 401, "bad-signature");
    const id = req.body?.data?.id ?? req.body?.id;
    const r = await settle(id);
    return { ok: r.ok, credited: r.credited === true, error: r.ok ? undefined : r.error };
  });
  globalThis.naslifePaySettle = settle;
}
