// العروض والتحديثات والعضوية في الدوائر التجارية.
// الانضمام (biz_follows) ضغطة واحدة يفتح العروض والخصومات والتحديثات. أربعة أنواع: deal (سعر مخفض على منتج، للجميع افتراضياً)،
// coupon (كوبون للأعضاء بحدود)، checkin (خصم لحظي لمن هو في المكان: يحتاج موقعاً قريباً وقت الطلب)، loyalty (كل N طلب مستلم منتج مجاني).
// لا حفظ: المحفظة نافذة على المتاح لك من دوائرك. الاستخدام تلقائي على الطلب داخل التطبيق فقط (business.js يستدعي naslifeOffersApply).
// الكوبون يُرسل لصاحب حساب مرة واحدة وينتقل كاملاً. إشعارات لكل دائرة: all | near | none (near تُنفَّذ في مرحلة القرب).
// التسجيل في src/index.js بعد business.js:
//   await app.register((await import("./offers.js")).default, { pool, auth });
import crypto from "node:crypto";

const UUID_RE = /^[0-9a-f-]{36}$/i;
const SLUG_RE = /^[a-z0-9][a-z0-9-]{1,63}$/;
const ID_RE = /^[A-Z]{2}\d{7}$/;
const KINDS = ["deal", "coupon", "checkin", "loyalty"];
const VALUE_TYPES = { deal: ["price", "percent"], coupon: ["percent", "amount", "free_item"], checkin: ["percent", "amount", "free_item"], loyalty: ["free_item"] };
const NOTIFY = ["all", "near", "none"];
const DAY = 86400000;
const str = (v, max) => String(v ?? "").trim().slice(0, max);
const num = (v) => { const n = Number(v); return Number.isFinite(n) ? n : null; };
const distanceM = (lat1, lng1, lat2, lng2) => { const R = 6371000, r = Math.PI / 180; const dLat = (lat2 - lat1) * r, dLng = (lng2 - lng1) * r; const a = Math.sin(dLat / 2) ** 2 + Math.cos(lat1 * r) * Math.cos(lat2 * r) * Math.sin(dLng / 2) ** 2; return 2 * R * Math.asin(Math.sqrt(a)); };
const sar = (h) => { const v = Number(h) / 100; return (Number.isInteger(v) ? String(v) : v.toFixed(2)) + " ر.س"; };

/// قوالب المالك: ثلاث ضغطات بدل نموذج طويل
export const TEMPLATES = [
  { id: "happy_hour", name: "ساعة هادئة", kind: "deal", value: { type: "percent", amount: 15 }, hours: 3, membersOnly: false, hint: "خصم على كل القائمة لفترة هادئة من اليوم" },
  { id: "first_order", name: "أول طلب", kind: "coupon", value: { type: "percent", amount: 20 }, days: 30, conditions: { firstOrder: true, perUser: 1 }, hint: "لمن يطلب منك أول مرة" },
  { id: "here_now", name: "لمن هنا الآن", kind: "checkin", value: { type: "percent", amount: 15 }, hours: 3, conditions: { perUser: 1, radiusM: 300 }, hint: "يُفتح فقط لمن يطلب وهو في المكان" },
  { id: "product_week", name: "منتج الأسبوع", kind: "deal", value: { type: "price", amount: null }, days: 7, membersOnly: false, needsItem: true, hint: "سعر خاص على منتج واحد" },
  { id: "limited_coupon", name: "كوبون بعدد محدود", kind: "coupon", value: { type: "amount", amount: 1000 }, days: 14, conditions: { total: 50, perUser: 1, minTotal: 3000 }, hint: "أول 50 عضواً" },
  { id: "loyalty", name: "مكافأة الرواد", kind: "loyalty", value: { type: "free_item" }, conditions: { every: 10 }, needsItem: true, transferable: false, hint: "كل 10 طلبات مستلمة، منتج مجاني" },
];

export default async function offers(app, opts = {}) {
  const pool = opts.pool ?? globalThis.naslifePool ?? null;
  const auth = opts.auth ?? globalThis.naslifeAuth ?? null;
  if (!pool || !auth) throw new Error("offers: pool and auth are required");
  await pool.query(`
    CREATE TABLE IF NOT EXISTS biz_offers (
      id UUID PRIMARY KEY, biz_id TEXT NOT NULL, kind TEXT NOT NULL, title TEXT NOT NULL, description TEXT NOT NULL DEFAULT '',
      value JSONB NOT NULL DEFAULT '{}', item_id TEXT, conditions JSONB NOT NULL DEFAULT '{}',
      members_only BOOLEAN NOT NULL DEFAULT true, transferable BOOLEAN NOT NULL DEFAULT true,
      starts_at TIMESTAMPTZ NOT NULL DEFAULT now(), ends_at TIMESTAMPTZ, active BOOLEAN NOT NULL DEFAULT true, template TEXT,
      created_by TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE INDEX IF NOT EXISTS biz_offers_biz ON biz_offers(biz_id, active, ends_at);
    CREATE TABLE IF NOT EXISTS biz_offer_uses (
      id UUID PRIMARY KEY, offer_id UUID NOT NULL, biz_id TEXT NOT NULL, user_id TEXT NOT NULL, order_id UUID, kind TEXT NOT NULL DEFAULT 'use',
      amount BIGINT NOT NULL DEFAULT 0, grant_id UUID, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE INDEX IF NOT EXISTS biz_offer_uses_offer ON biz_offer_uses(offer_id, user_id);
    CREATE INDEX IF NOT EXISTS biz_offer_uses_user ON biz_offer_uses(user_id, created_at DESC);
    CREATE INDEX IF NOT EXISTS biz_offer_uses_order ON biz_offer_uses(order_id);
    CREATE TABLE IF NOT EXISTS biz_offer_grants (
      id UUID PRIMARY KEY, offer_id UUID NOT NULL, biz_id TEXT NOT NULL, user_id TEXT NOT NULL, from_user TEXT, reason TEXT NOT NULL DEFAULT 'transfer',
      milestone INT, expires_at TIMESTAMPTZ, used_at TIMESTAMPTZ, order_id UUID, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE INDEX IF NOT EXISTS biz_offer_grants_user ON biz_offer_grants(user_id, used_at);
    CREATE UNIQUE INDEX IF NOT EXISTS biz_offer_grants_milestone ON biz_offer_grants(offer_id, user_id, milestone) WHERE milestone IS NOT NULL;
    CREATE TABLE IF NOT EXISTS biz_member_prefs (biz_id TEXT NOT NULL, user_id TEXT NOT NULL, notify TEXT NOT NULL DEFAULT 'near', last_notified_at TIMESTAMPTZ, updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (biz_id, user_id));
    CREATE TABLE IF NOT EXISTS biz_offer_views (offer_id UUID NOT NULL, user_id TEXT NOT NULL, day DATE NOT NULL, PRIMARY KEY (offer_id, user_id, day));
  `);

  const bad = (reply, code, error, extra = {}) => reply.code(code).send({ error, ...extra });
  const optionalAuth = async (req) => { try { return (await auth(req)) || null; } catch { return null; } };
  const notify = async (ids, payload) => { try { await globalThis.naslifeNotify?.([...new Set([].concat(ids).filter(Boolean))], payload); } catch { /* ignore */ } };
  const person = async (id) => { try { const u = (await pool.query("SELECT id, nickname, avatar_url FROM users WHERE id=$1", [id])).rows[0]; return u ? { id: u.id, nickname: u.nickname ?? "", avatarUrl: u.avatar_url ?? null } : null; } catch { return null; } };
  const bizName = (b) => b?.name_ar || b?.name || b?.id || "";
  const loadBiz = async (id) => (SLUG_RE.test(id ?? "") ? (await pool.query("SELECT * FROM biz WHERE id=$1", [id])).rows[0] ?? null : null);
  const isMember = async (bizId, uid) => !!uid && (await pool.query("SELECT 1 FROM biz_follows WHERE biz_id=$1 AND user_id=$2", [bizId, uid])).rowCount > 0;
  const members = async (bizId) => (await pool.query("SELECT f.user_id, COALESCE(p.notify,'near') AS notify, p.last_notified_at FROM biz_follows f LEFT JOIN biz_member_prefs p ON p.biz_id=f.biz_id AND p.user_id=f.user_id WHERE f.biz_id=$1", [bizId])).rows;
  /// صلاحية الإدارة على الدائرة عبر business.js (المالك، المدير، مدير النظام)
  async function manageGuard(req, reply) {
    const uid = await auth(req); if (!uid) { bad(reply, 401, "auth"); return null; }
    const b = await loadBiz(req.params.id); if (!b) { bad(reply, 404, "not-found"); return null; }
    const role = await globalThis.naslifeBizRole?.(uid, b);
    if (!["owner", "manager", "admin"].includes(role ?? "")) { bad(reply, 403, "forbidden"); return null; }
    return { uid, b, role };
  }

  const state = (o, now = Date.now()) => !o.active ? "off" : new Date(o.starts_at).getTime() > now ? "upcoming" : o.ends_at && new Date(o.ends_at).getTime() <= now ? "ended" : "active";
  const live = (o, now = Date.now()) => state(o, now) === "active";
  const perUser = (o) => (o.kind === "deal" ? Math.max(0, Number(o.conditions?.perUser) || 0) : Math.max(1, Math.min(10, Number(o.conditions?.perUser) || 1)));
  /// قيمة الخصم على طلب بمجموع total وسعر وحدة price (بالهللات)
  function discountFor(o, { total, price, qty = 1 }) {
    const v = o.value ?? {}; const t = Number(total) || 0; if (t <= 0) return 0;
    switch (v.type) {
      case "percent": return Math.min(t, Math.round((t * Math.max(0, Math.min(100, Number(v.amount) || 0))) / 100));
      case "amount": return Math.min(t, Math.max(0, Math.round(Number(v.amount) || 0)));
      case "price": { const p = Number(price) || 0; const np = Math.max(0, Math.round(Number(v.amount) || 0)); return p > np && p > 0 ? Math.min(t, Math.round(t * (1 - np / p))) : 0; }
      case "free_item": return Math.min(t, Math.max(0, Math.round(Number(price) || 0)));
      default: return 0;
    }
  }
  const scoped = (o, itemId) => (!o.item_id || o.item_id === itemId) && (!Array.isArray(o.conditions?.items) || !o.conditions.items.length || o.conditions.items.includes(itemId));
  const useCount = async (c, offerId, uid, { today = false } = {}) => (await c.query(`SELECT count(*)::int AS n FROM biz_offer_uses WHERE offer_id=$1 AND user_id=$2 AND kind IN ('use','transfer')${today ? " AND created_at > now() - interval '24 hours'" : ""}`, [offerId, uid])).rows[0].n;
  const totalUses = async (c, offerId) => (await c.query("SELECT count(*)::int AS n FROM biz_offer_uses WHERE offer_id=$1 AND kind='use'", [offerId])).rows[0].n;
  const openGrant = async (c, offerId, uid) => (await c.query("SELECT * FROM biz_offer_grants WHERE offer_id=$1 AND user_id=$2 AND used_at IS NULL AND (expires_at IS NULL OR expires_at > now()) ORDER BY created_at LIMIT 1", [offerId, uid])).rows[0] ?? null;
  const hadOrder = async (c, bizId, uid) => (await c.query("SELECT 1 FROM biz_orders WHERE biz_id=$1 AND user_id=$2 AND status IN ('confirmed','used') LIMIT 1", [bizId, uid])).rowCount > 0;

  /// هل يملك هذا المستخدم استحقاقاً للعرض؟ (العضوية والحدود والهدايا) ثم شروط وقت الطلب إن أُعطي total.
  /// يعيد {ok, reason, via, grant, note}: note تُخبر في القوائم بشرط سيُفحص عند الطلب (مثل أول طلب) دون أن يمنع الاستحقاق.
  async function eligibility(c, o, { biz, uid, member, item, qty, total, lat, lng, first }) {
    if (!live(o)) return { ok: false, reason: state(o) === "upcoming" ? "upcoming" : "ended" };
    if (item && !scoped(o, item.id)) return { ok: false, reason: "item" };
    const cap = Number(o.conditions?.total) || 0;
    if (cap && (await totalUses(c, o.id)) >= cap) return { ok: false, reason: "sold-out" };
    const ordering = total != null;
    let via = "public", grant = null;
    if (o.kind === "deal") {
      if (o.members_only && !member) return { ok: false, reason: "members" };
      const pu = perUser(o); if (pu && uid && (await useCount(c, o.id, uid)) >= pu) return { ok: false, reason: "used" };
    } else {
      if (!uid) return { ok: false, reason: "members" };
      grant = await openGrant(c, o.id, uid);
      if (grant) via = "grant";
      else if (o.kind === "loyalty") return { ok: false, reason: "loyalty", progress: await loyaltyProgress(c, o, uid) };
      else if (o.members_only && !member) return { ok: false, reason: "members" };
      else if (o.kind !== "checkin" && (await useCount(c, o.id, uid)) >= perUser(o)) return { ok: false, reason: "used" };
      else via = "member";
    }
    const firstFails = o.conditions?.firstOrder === true && uid ? (first ?? (await hadOrder(c, biz.id, uid))) : false;
    if (!ordering) return { ok: true, via, grant, note: firstFails ? "first-order" : null };
    // شروط وقت الطلب
    if (o.kind === "checkin" && via !== "grant" && (await useCount(c, o.id, uid, { today: true })) >= perUser(o)) return { ok: false, reason: "used-today" };
    if (firstFails) return { ok: false, reason: "first-order" };
    if (Number(o.conditions?.minTotal) > 0 && total < Number(o.conditions.minTotal)) return { ok: false, reason: "min-total" };
    if (o.kind === "checkin") {
      const r = Math.max(50, Math.min(2000, Number(o.conditions?.radiusM) || 300));
      if (!Number.isFinite(lat) || !Number.isFinite(lng) || distanceM(lat, lng, Number(biz.lat), Number(biz.lng)) > r) return { ok: false, reason: "near" };
    }
    return { ok: true, via, grant };
  }
  async function loyaltyProgress(c, o, uid) {
    const every = Math.max(2, Math.min(50, Number(o.conditions?.every) || 10));
    const n = (await c.query("SELECT count(*)::int AS n FROM biz_orders WHERE biz_id=$1 AND user_id=$2 AND status='used'", [o.biz_id, uid])).rows[0].n;
    return { every, count: n % every, total: n };
  }

  /// يُستدعى من مسار الطلب داخل معاملة business.js: يختار أفضل عرض (أو المطلوب) ويسجّل استخدامه ويعيد الخصم
  async function apply(c, { biz, uid, item, qty, total, offerId, lat, lng, orderId }) {
    if (!biz || !uid || !item || !(Number(total) > 0)) return null;
    const rows = (await c.query("SELECT * FROM biz_offers WHERE biz_id=$1 AND active AND starts_at <= now() AND (ends_at IS NULL OR ends_at > now())", [biz.id])).rows;
    const member = await isMember(biz.id, uid);
    const first = await hadOrder(c, biz.id, uid);
    const la = num(lat), ln = num(lng);
    let best = null;
    for (const o of rows) {
      if (offerId && o.id !== offerId) continue;
      const e = await eligibility(c, o, { biz, uid, member, item, qty, total, lat: la, lng: ln, first });
      if (!e.ok) { if (offerId) throw Object.assign(new Error("offer-unavailable"), { code: "offer-unavailable", reason: e.reason }); continue; }
      const d = discountFor(o, { total, price: Number(item.price), qty });
      if (d <= 0) continue;
      if (!best || d > best.discount || (d === best.discount && o.ends_at && (!best.o.ends_at || new Date(o.ends_at) < new Date(best.o.ends_at)))) best = { o, discount: d, e };
    }
    if (offerId && !best) throw Object.assign(new Error("offer-unavailable"), { code: "offer-unavailable", reason: "not-found" });
    if (!best) return null;
    const useId = crypto.randomUUID();
    await c.query("INSERT INTO biz_offer_uses(id,offer_id,biz_id,user_id,order_id,kind,amount,grant_id) VALUES($1,$2,$3,$4,$5,'use',$6,$7)", [useId, best.o.id, biz.id, uid, orderId ?? null, best.discount, best.e.grant?.id ?? null]);
    if (best.e.grant) await c.query("UPDATE biz_offer_grants SET used_at=now(), order_id=$2 WHERE id=$1", [best.e.grant.id, orderId ?? null]);
    return { id: best.o.id, kind: best.o.kind, title: best.o.title, discount: best.discount, via: best.e.via };
  }
  /// إلغاء طلب يعيد الاستحقاق
  async function release(c, orderId) {
    const rows = (await c.query("DELETE FROM biz_offer_uses WHERE order_id=$1 RETURNING grant_id", [orderId])).rows;
    for (const r of rows) if (r.grant_id) await c.query("UPDATE biz_offer_grants SET used_at=NULL, order_id=NULL WHERE id=$1", [r.grant_id]);
    return rows.length;
  }
  /// بعد استلام طلب: مكافأة الرواد كل N طلب مستلم
  async function onRedeem(biz, uid) {
    const rows = (await pool.query("SELECT * FROM biz_offers WHERE biz_id=$1 AND kind='loyalty' AND active AND starts_at <= now() AND (ends_at IS NULL OR ends_at > now())", [biz.id])).rows;
    if (!rows.length) return [];
    if (!(await isMember(biz.id, uid))) return [];
    const out = [];
    for (const o of rows) {
      const p = await loyaltyProgress(pool, o, uid);
      if (p.total === 0 || p.count !== 0) continue;
      const milestone = p.total / p.every;
      const gid = crypto.randomUUID();
      const r = await pool.query("INSERT INTO biz_offer_grants(id,offer_id,biz_id,user_id,reason,milestone,expires_at) VALUES($1,$2,$3,$4,'loyalty',$5,now() + interval '30 days') ON CONFLICT DO NOTHING RETURNING id", [gid, o.id, biz.id, uid, milestone]);
      if (!r.rowCount) continue;
      out.push(o.id);
      await notify([uid], { kind: "offer_loyalty", title: `مكافأة من ${bizName(biz)}`, body: `${o.title} · صالحة 30 يوماً`, data: { bizId: biz.id, offerId: o.id, section: "offers" } });
    }
    return out;
  }
  /// إشعار الأعضاء (all فقط الآن؛ near في مرحلة القرب) بسقف إشعار واحد لكل دائرة يومياً
  async function notifyMembers(biz, payload, { level = "all" } = {}) {
    const rows = await members(biz.id);
    const ids = rows.filter((m) => m.notify === level && (!m.last_notified_at || Date.now() - new Date(m.last_notified_at).getTime() > DAY)).map((m) => m.user_id);
    if (!ids.length) return 0;
    await notify(ids, payload);
    await pool.query("INSERT INTO biz_member_prefs(biz_id,user_id,notify,last_notified_at) SELECT $1, unnest($2::text[]), 'all', now() ON CONFLICT (biz_id,user_id) DO UPDATE SET last_notified_at=now()", [biz.id, ids]);
    return ids.length;
  }
  /// يُعلّم عناصر القائمة بعرض السعر الفعّال (deal) وعدد العروض
  async function annotateItems(bizId, items, uid) {
    const rows = (await pool.query("SELECT * FROM biz_offers WHERE biz_id=$1 AND kind='deal' AND active AND starts_at <= now() AND (ends_at IS NULL OR ends_at > now())", [bizId])).rows;
    if (!rows.length) return;
    const member = uid ? await isMember(bizId, uid) : false;
    for (const it of items) {
      const o = rows.find((x) => scoped(x, it.id) && (!x.members_only || member));
      if (!o) continue;
      const d = discountFor(o, { total: it.price, price: it.price, qty: 1 });
      if (d > 0) it.deal = { id: o.id, title: o.title, price: it.price - d, endsAt: o.ends_at, membersOnly: o.members_only };
    }
  }
  async function counts(bizIds) {
    if (!bizIds.length) return new Map();
    const rows = (await pool.query("SELECT biz_id, count(*)::int AS n, min(ends_at) AS soonest FROM biz_offers WHERE biz_id = ANY($1) AND active AND starts_at <= now() AND (ends_at IS NULL OR ends_at > now()) GROUP BY biz_id", [bizIds])).rows;
    return new Map(rows.map((r) => [r.biz_id, { offers: r.n, offerEndsAt: r.soonest }]));
  }
  globalThis.naslifeOffersApply = apply;
  globalThis.naslifeOffersRelease = release;
  globalThis.naslifeOffersOnRedeem = onRedeem;
  globalThis.naslifeOffersAnnotate = annotateItems;
  globalThis.naslifeOffersCounts = counts;
  globalThis.naslifeOffersOnPost = async (biz, post) => notifyMembers(biz, { kind: "biz_update", title: `${bizName(biz)}: ${post.title}`, body: String(post.body ?? "").slice(0, 120), data: { bizId: biz.id, postId: post.id } });

  const itemTitle = async (id) => (id ? (await pool.query("SELECT title, price FROM biz_items WHERE id=$1", [id])).rows[0] ?? null : null);
  async function offerOut(o, viewer = null) {
    const it = await itemTitle(o.item_id);
    const st = state(o);
    const base = { id: o.id, bizId: o.biz_id, kind: o.kind, title: o.title, description: o.description, value: o.value ?? {}, itemId: o.item_id, itemTitle: it?.title ?? null, itemPrice: it ? Number(it.price) : null,
      conditions: o.conditions ?? {}, membersOnly: o.members_only, transferable: o.transferable, startsAt: o.starts_at, endsAt: o.ends_at, active: o.active, state: st, template: o.template, createdAt: o.created_at };
    if (viewer) {
      const { uid, biz, member } = viewer;
      const e = uid ? await eligibility(pool, o, { biz, uid, member, item: null, qty: 1, total: null }) : { ok: false, reason: o.kind === "deal" && !o.members_only ? null : "members" };
      const uses = uid ? await useCount(pool, o.id, uid) : 0;
      const cap = Number(o.conditions?.total) || 0;
      base.eligible = !!e.ok; base.lockedReason = e.ok ? null : e.reason; base.note = e.note ?? null; base.usedByMe = uses > 0; base.via = e.via ?? null;
      base.grant = e.grant ? { id: e.grant.id, from: e.grant.from_user ? await person(e.grant.from_user) : null, reason: e.grant.reason, expiresAt: e.grant.expires_at } : null;
      base.loyalty = o.kind === "loyalty" && uid ? await loyaltyProgress(pool, o, uid) : null;
      base.left = cap ? Math.max(0, cap - (await totalUses(pool, o.id))) : null;
      base.canSend = !!uid && o.transferable && ["coupon", "checkin"].includes(o.kind) && e.ok && e.via === "member";
    }
    return base;
  }

  // ---- عروض الدائرة (عام؛ الأهلية للمسجّل)
  app.get("/biz/:id/offers", async (req, reply) => {
    const uid = await optionalAuth(req);
    const b = await loadBiz(req.params.id); if (!b || b.active === false) return bad(reply, 404, "not-found");
    const member = await isMember(b.id, uid);
    const rows = (await pool.query("SELECT * FROM biz_offers WHERE biz_id=$1 AND active AND (ends_at IS NULL OR ends_at > now() - interval '30 days') ORDER BY ends_at NULLS LAST, created_at DESC", [b.id])).rows;
    const viewer = { uid, biz: b, member };
    const active = [], upcoming = [], past = [];
    for (const o of rows) { const st = state(o); const out = await offerOut(o, viewer); (st === "active" ? active : st === "upcoming" ? upcoming : past).push(out); }
    if (uid && active.length) { const today = new Date().toISOString().slice(0, 10); for (const o of active) pool.query("INSERT INTO biz_offer_views(offer_id,user_id,day) VALUES($1,$2,$3) ON CONFLICT DO NOTHING", [o.id, uid, today]).catch(() => {}); }
    const pref = uid ? (await pool.query("SELECT notify FROM biz_member_prefs WHERE biz_id=$1 AND user_id=$2", [b.id, uid])).rows[0] : null;
    return { bizId: b.id, member, notify: member ? (pref?.notify ?? "near") : null, active, upcoming, past };
  });
  // ---- مستوى إشعارات الدائرة للعضو
  app.get("/biz/:id/notify", async (req, reply) => {
    const uid = await auth(req); if (!uid) return bad(reply, 401, "auth");
    const b = await loadBiz(req.params.id); if (!b) return bad(reply, 404, "not-found");
    const member = await isMember(b.id, uid);
    const pref = (await pool.query("SELECT notify FROM biz_member_prefs WHERE biz_id=$1 AND user_id=$2", [b.id, uid])).rows[0];
    return { member, notify: pref?.notify ?? "near" };
  });
  app.put("/biz/:id/notify", async (req, reply) => {
    const uid = await auth(req); if (!uid) return bad(reply, 401, "auth");
    const b = await loadBiz(req.params.id); if (!b) return bad(reply, 404, "not-found");
    if (!(await isMember(b.id, uid))) return bad(reply, 409, "not-member");
    const level = str(req.body?.notify, 8); if (!NOTIFY.includes(level)) return bad(reply, 400, "bad-level");
    await pool.query("INSERT INTO biz_member_prefs(biz_id,user_id,notify) VALUES($1,$2,$3) ON CONFLICT (biz_id,user_id) DO UPDATE SET notify=EXCLUDED.notify, updated_at=now()", [b.id, uid, level]);
    return { member: true, notify: level };
  });
  // ---- عروضي: نافذة على المتاح لي من دوائري (وما أُهدي لي)، وما استخدمته، وما فاتني
  app.get("/offers/mine", async (req, reply) => {
    const uid = await auth(req); if (!uid) return bad(reply, 401, "auth");
    const rows = (await pool.query(`SELECT o.*, b.name AS biz_name, b.name_ar AS biz_name_ar, b.logo_url, b.category, b.lat AS biz_lat, b.lng AS biz_lng FROM biz_offers o JOIN biz b ON b.id=o.biz_id
      WHERE o.active AND b.active AND (o.ends_at IS NULL OR o.ends_at > now() - interval '30 days') AND o.starts_at <= now()
        AND (EXISTS (SELECT 1 FROM biz_follows f WHERE f.biz_id=o.biz_id AND f.user_id=$1) OR EXISTS (SELECT 1 FROM biz_offer_grants g WHERE g.offer_id=o.id AND g.user_id=$1))
      ORDER BY o.ends_at NULLS LAST, o.created_at DESC LIMIT 300`, [uid])).rows;
    const active = [], expired = [];
    for (const o of rows) {
      const biz = { id: o.biz_id, lat: o.biz_lat, lng: o.biz_lng };
      const member = await isMember(o.biz_id, uid);
      const out = await offerOut(o, { uid, biz, member });
      out.biz = { id: o.biz_id, name: o.biz_name_ar || o.biz_name, logoUrl: o.logo_url, category: o.category };
      if (state(o) === "active") { if (out.eligible || out.lockedReason === "loyalty") active.push(out); }
      else if (state(o) === "ended" && !out.usedByMe) expired.push(out);
    }
    const used = (await pool.query(`SELECT u.*, o.title, o.kind, b.name AS biz_name, b.name_ar AS biz_name_ar, b.logo_url, ord.code, ord.total AS order_total, i.title AS item_title
      FROM biz_offer_uses u JOIN biz_offers o ON o.id=u.offer_id JOIN biz b ON b.id=u.biz_id LEFT JOIN biz_orders ord ON ord.id=u.order_id LEFT JOIN biz_items i ON i.id=ord.item_id
      WHERE u.user_id=$1 AND u.kind='use' AND u.created_at > now() - interval '180 days' ORDER BY u.created_at DESC LIMIT 200`, [uid])).rows;
    const sums = (await pool.query("SELECT COALESCE(SUM(amount) FILTER (WHERE created_at >= date_trunc('month', now())),0)::bigint AS month, COALESCE(SUM(amount),0)::bigint AS total, count(*) FILTER (WHERE kind='use')::int AS n FROM biz_offer_uses WHERE user_id=$1 AND kind='use'", [uid])).rows[0];
    return {
      active, expired,
      used: used.map((u) => ({ id: u.id, offerId: u.offer_id, title: u.title, kind: u.kind, amount: Number(u.amount), usedAt: u.created_at, orderId: u.order_id, orderCode: u.code ?? null, orderTotal: u.order_total == null ? null : Number(u.order_total), itemTitle: u.item_title ?? null, biz: { id: u.biz_id, name: u.biz_name_ar || u.biz_name, logoUrl: u.logo_url } })),
      savings: { month: Number(sums.month), total: Number(sums.total), uses: sums.n },
      counts: { active: active.length, used: used.length, expired: expired.length },
    };
  });
  // ---- إرسال كوبون لصاحب حساب: ينتقل كاملاً ومرة واحدة
  app.post("/biz/:id/offers/:offerId/send", async (req, reply) => {
    const uid = await auth(req); if (!uid) return bad(reply, 401, "auth");
    const b = await loadBiz(req.params.id); if (!b) return bad(reply, 404, "not-found");
    if (!UUID_RE.test(req.params.offerId)) return bad(reply, 404, "not-found");
    const o = (await pool.query("SELECT * FROM biz_offers WHERE id=$1 AND biz_id=$2", [req.params.offerId, b.id])).rows[0]; if (!o) return bad(reply, 404, "not-found");
    const to = str(req.body?.toUserId, 12).toUpperCase();
    if (!ID_RE.test(to)) return bad(reply, 400, "bad-user");
    if (to === uid) return bad(reply, 400, "self");
    if (!(await person(to))) return bad(reply, 404, "user-not-found");
    // لا هدايا بين طرفين بينهما حظر، ولا من حساب موقوف
    let bl = []; try { bl = (await globalThis.naslifeBlockedIds?.(uid)) ?? []; } catch { bl = []; }
    if (bl.includes(to)) return bad(reply, 403, "blocked");
    let susp = false; try { susp = !!(await globalThis.naslifeIsSuspended?.(uid)); } catch { susp = false; }
    if (susp) return bad(reply, 403, "suspended");
    if (!o.transferable || !["coupon", "checkin"].includes(o.kind)) return bad(reply, 409, "not-transferable");
    if (!live(o)) return bad(reply, 409, "ended");
    const member = await isMember(b.id, uid);
    const mine = await eligibility(pool, o, { biz: b, uid, member, item: null, qty: 1, total: null });
    if (!mine.ok || mine.via !== "member") return bad(reply, 409, mine.via === "grant" ? "not-transferable" : (mine.reason === "members" ? "members" : "used"));
    const theirs = await eligibility(pool, o, { biz: b, uid: to, member: await isMember(b.id, to), item: null, qty: 1, total: null });
    if (theirs.ok || theirs.reason === "used" || theirs.reason === "used-today") return bad(reply, 409, "already-has");
    const gid = crypto.randomUUID();
    await pool.query("BEGIN");
    try {
      await pool.query("INSERT INTO biz_offer_uses(id,offer_id,biz_id,user_id,kind,amount,grant_id) VALUES($1,$2,$3,$4,'transfer',0,$5)", [crypto.randomUUID(), o.id, b.id, uid, gid]);
      await pool.query("INSERT INTO biz_offer_grants(id,offer_id,biz_id,user_id,from_user,reason,expires_at) VALUES($1,$2,$3,$4,$5,'transfer',$6)", [gid, o.id, b.id, to, uid, o.ends_at]);
      await pool.query("COMMIT");
    } catch (e) { await pool.query("ROLLBACK").catch(() => {}); throw e; }
    const me = await person(uid);
    await notify([to], { kind: "offer_received", title: `${me?.nickname || uid} أرسل لك كوبوناً`, body: `${o.title} من ${bizName(b)}`, data: { bizId: b.id, offerId: o.id, section: "offers" } });
    return { ok: true, grantId: gid, to: await person(to) };
  });

  // ---- إدارة العروض (المالك والمدير)
  const cleanValue = (kind, v) => {
    const type = str(v?.type, 12); if (!VALUE_TYPES[kind]?.includes(type)) throw Object.assign(new Error("bad-value"), { code: 400 });
    if (type === "free_item") return { type };
    const amount = Math.round(Number(v?.amount));
    if (!Number.isFinite(amount) || amount < 0) throw Object.assign(new Error("bad-value"), { code: 400 });
    if (type === "percent" && (amount < 1 || amount > 100)) throw Object.assign(new Error("bad-value"), { code: 400 });
    if (type === "amount" && (amount < 100 || amount > 10000000)) throw Object.assign(new Error("bad-value"), { code: 400 });
    return { type, amount };
  };
  const cleanConditions = async (bizId, c) => {
    const o = {}; if (!c || typeof c !== "object") return o;
    if (Number(c.minTotal) > 0) o.minTotal = Math.round(Number(c.minTotal));
    if (c.firstOrder === true) o.firstOrder = true;
    if (Number(c.perUser) > 0) o.perUser = Math.max(1, Math.min(10, Math.round(Number(c.perUser))));
    if (Number(c.total) > 0) o.total = Math.max(1, Math.min(100000, Math.round(Number(c.total))));
    if (Number(c.every) > 0) o.every = Math.max(2, Math.min(50, Math.round(Number(c.every))));
    if (Number(c.radiusM) > 0) o.radiusM = Math.max(50, Math.min(2000, Math.round(Number(c.radiusM))));
    if (Array.isArray(c.items) && c.items.length) {
      const ids = c.items.map((x) => str(x, 64)).filter((x) => SLUG_RE.test(x)).slice(0, 50);
      const ok = (await pool.query("SELECT id FROM biz_items WHERE biz_id=$1 AND id = ANY($2)", [bizId, ids])).rows.map((r) => r.id);
      if (ok.length) o.items = ok;
    }
    return o;
  };
  async function readOffer(req, reply, b, cur) {
    const body = req.body ?? {};
    try {
      const kind = body.kind !== undefined ? str(body.kind, 10) : cur?.kind; if (!KINDS.includes(kind)) return bad(reply, 400, "bad-kind"), null;
      const title = body.title !== undefined ? str(body.title, 80) : cur?.title; if (!title || title.length < 2) return bad(reply, 400, "bad-title"), null;
      const banned = globalThis.naslifeCheckText?.(title, str(body.description, 500)); if (banned) return bad(reply, 400, "banned-words", { word: banned }), null;
      const value = body.value !== undefined ? cleanValue(kind, body.value) : cur ? cleanValue(kind, cur.value) : null; if (!value) return bad(reply, 400, "bad-value"), null;
      let itemId = body.itemId !== undefined ? (body.itemId ? str(body.itemId, 64) : null) : (cur?.item_id ?? null);
      if (itemId) { if (!SLUG_RE.test(itemId) || !(await pool.query("SELECT 1 FROM biz_items WHERE id=$1 AND biz_id=$2", [itemId, b.id])).rowCount) return bad(reply, 400, "bad-item"), null; }
      if ((value.type === "free_item" || value.type === "price") && !itemId) return bad(reply, 400, "item-required"), null;
      if (value.type === "price" && itemId) { const it = (await pool.query("SELECT price FROM biz_items WHERE id=$1", [itemId])).rows[0]; if (it && value.amount >= Number(it.price)) return bad(reply, 400, "price-not-lower"), null; }
      const conditions = body.conditions !== undefined ? await cleanConditions(b.id, body.conditions) : (cur?.conditions ?? {});
      if (kind === "loyalty" && !conditions.every) conditions.every = 10;
      const membersOnly = body.membersOnly !== undefined ? body.membersOnly === true : cur ? cur.members_only : kind !== "deal";
      const transferable = body.transferable !== undefined ? body.transferable === true : cur ? cur.transferable : kind !== "loyalty";
      const startsAt = body.startsAt !== undefined ? (body.startsAt ? new Date(body.startsAt) : new Date()) : new Date(cur?.starts_at ?? Date.now());
      const endsAt = body.endsAt !== undefined ? (body.endsAt ? new Date(body.endsAt) : null) : (cur?.ends_at ? new Date(cur.ends_at) : null);
      if (Number.isNaN(startsAt.getTime()) || (endsAt && Number.isNaN(endsAt.getTime()))) return bad(reply, 400, "bad-date"), null;
      if (kind !== "loyalty" && !endsAt) return bad(reply, 400, "end-required"), null;
      if (endsAt && (endsAt <= startsAt || endsAt.getTime() - startsAt.getTime() > 90 * DAY)) return bad(reply, 400, "bad-range"), null;
      if (endsAt && endsAt.getTime() < Date.now() && !cur) return bad(reply, 400, "in-past"), null;
      return { kind, title, description: body.description !== undefined ? str(body.description, 500) : (cur?.description ?? ""), value, itemId, conditions, membersOnly, transferable, startsAt, endsAt, template: body.template !== undefined ? str(body.template, 30) || null : (cur?.template ?? null) };
    } catch (e) { if (e.code === 400) { bad(reply, 400, e.message); return null; } throw e; }
  }
  async function statsFor(o) {
    const s = (await pool.query(`SELECT (SELECT count(*)::int FROM biz_offer_views v WHERE v.offer_id=$1) AS views,
      (SELECT count(*)::int FROM biz_offer_uses u WHERE u.offer_id=$1 AND u.kind='use') AS uses,
      (SELECT COALESCE(SUM(amount),0)::bigint FROM biz_offer_uses u WHERE u.offer_id=$1 AND u.kind='use') AS discount,
      (SELECT COALESCE(SUM(ord.total),0)::bigint FROM biz_offer_uses u JOIN biz_orders ord ON ord.id=u.order_id WHERE u.offer_id=$1 AND u.kind='use' AND ord.status IN ('confirmed','used')) AS revenue,
      (SELECT count(*)::int FROM biz_offer_uses u WHERE u.offer_id=$1 AND u.kind='transfer') AS sent,
      (SELECT count(*)::int FROM biz_offer_grants g WHERE g.offer_id=$1 AND g.reason='loyalty') AS rewards`, [o.id])).rows[0];
    return { views: s.views, uses: s.uses, discount: Number(s.discount), revenue: Number(s.revenue), sent: s.sent, rewards: s.rewards };
  }
  app.get("/biz/:id/manage/offers", async (req, reply) => {
    const g = await manageGuard(req, reply); if (!g) return;
    const rows = (await pool.query("SELECT * FROM biz_offers WHERE biz_id=$1 ORDER BY (CASE WHEN active AND (ends_at IS NULL OR ends_at > now()) THEN 0 ELSE 1 END), ends_at NULLS LAST, created_at DESC LIMIT 200", [g.b.id])).rows;
    const out = [];
    for (const o of rows) out.push({ ...(await offerOut(o)), stats: await statsFor(o) });
    const memberCount = (await pool.query("SELECT count(*)::int AS n FROM biz_follows WHERE biz_id=$1", [g.b.id])).rows[0].n;
    return { offers: out, templates: TEMPLATES, members: memberCount };
  });
  app.post("/biz/:id/manage/offers", async (req, reply) => {
    const g = await manageGuard(req, reply); if (!g) return;
    const f = await readOffer(req, reply, g.b, null); if (!f) return;
    const id = crypto.randomUUID();
    await pool.query("INSERT INTO biz_offers(id,biz_id,kind,title,description,value,item_id,conditions,members_only,transferable,starts_at,ends_at,template,created_by) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)",
      [id, g.b.id, f.kind, f.title, f.description, JSON.stringify(f.value), f.itemId, JSON.stringify(f.conditions), f.membersOnly, f.transferable, f.startsAt.toISOString(), f.endsAt ? f.endsAt.toISOString() : null, f.template, g.uid]);
    const o = (await pool.query("SELECT * FROM biz_offers WHERE id=$1", [id])).rows[0];
    let notified = 0;
    if (state(o) === "active" && f.kind !== "loyalty") notified = await notifyMembers(g.b, { kind: "biz_offer", title: `عرض من ${bizName(g.b)}`, body: f.title, data: { bizId: g.b.id, offerId: id, section: "offers" } });
    return { ...(await offerOut(o)), stats: await statsFor(o), notified };
  });
  app.patch("/biz/:id/manage/offers/:offerId", async (req, reply) => {
    const g = await manageGuard(req, reply); if (!g) return;
    if (!UUID_RE.test(req.params.offerId)) return bad(reply, 404, "not-found");
    const cur = (await pool.query("SELECT * FROM biz_offers WHERE id=$1 AND biz_id=$2", [req.params.offerId, g.b.id])).rows[0]; if (!cur) return bad(reply, 404, "not-found");
    const b = req.body ?? {};
    if (b.endNow === true) { await pool.query("UPDATE biz_offers SET ends_at=now(), updated_at=now() WHERE id=$1", [cur.id]); const o = (await pool.query("SELECT * FROM biz_offers WHERE id=$1", [cur.id])).rows[0]; return { ...(await offerOut(o)), stats: await statsFor(o) }; }
    if (b.active !== undefined && Object.keys(b).length === 1) { await pool.query("UPDATE biz_offers SET active=$2, updated_at=now() WHERE id=$1", [cur.id, b.active === true]); const o = (await pool.query("SELECT * FROM biz_offers WHERE id=$1", [cur.id])).rows[0]; return { ...(await offerOut(o)), stats: await statsFor(o) }; }
    const f = await readOffer(req, reply, g.b, cur); if (!f) return;
    await pool.query("UPDATE biz_offers SET kind=$2, title=$3, description=$4, value=$5, item_id=$6, conditions=$7, members_only=$8, transferable=$9, starts_at=$10, ends_at=$11, template=$12, active=$13, updated_at=now() WHERE id=$1",
      [cur.id, f.kind, f.title, f.description, JSON.stringify(f.value), f.itemId, JSON.stringify(f.conditions), f.membersOnly, f.transferable, f.startsAt.toISOString(), f.endsAt ? f.endsAt.toISOString() : null, f.template, b.active !== undefined ? b.active === true : cur.active]);
    const o = (await pool.query("SELECT * FROM biz_offers WHERE id=$1", [cur.id])).rows[0];
    return { ...(await offerOut(o)), stats: await statsFor(o) };
  });
  app.delete("/biz/:id/manage/offers/:offerId", async (req, reply) => {
    const g = await manageGuard(req, reply); if (!g) return;
    if (!UUID_RE.test(req.params.offerId)) return bad(reply, 404, "not-found");
    const used = (await pool.query("SELECT count(*)::int AS n FROM biz_offer_uses WHERE offer_id=$1", [req.params.offerId])).rows[0].n;
    if (used) { const r = await pool.query("UPDATE biz_offers SET active=false, ends_at=LEAST(COALESCE(ends_at, now()), now()), updated_at=now() WHERE id=$1 AND biz_id=$2 RETURNING id", [req.params.offerId, g.b.id]); return r.rowCount ? { ok: true, archived: true } : bad(reply, 404, "not-found"); }
    const r = await pool.query("DELETE FROM biz_offers WHERE id=$1 AND biz_id=$2 RETURNING id", [req.params.offerId, g.b.id]);
    if (!r.rowCount) return bad(reply, 404, "not-found");
    await pool.query("DELETE FROM biz_offer_views WHERE offer_id=$1", [req.params.offerId]);
    return { ok: true, archived: false };
  });
  /// كرّر العرض: نسخة جديدة بنفس الإعدادات لفترة جديدة
  app.post("/biz/:id/manage/offers/:offerId/duplicate", async (req, reply) => {
    const g = await manageGuard(req, reply); if (!g) return;
    if (!UUID_RE.test(req.params.offerId)) return bad(reply, 404, "not-found");
    const cur = (await pool.query("SELECT * FROM biz_offers WHERE id=$1 AND biz_id=$2", [req.params.offerId, g.b.id])).rows[0]; if (!cur) return bad(reply, 404, "not-found");
    const startsAt = req.body?.startsAt ? new Date(req.body.startsAt) : new Date();
    const span = cur.ends_at ? new Date(cur.ends_at).getTime() - new Date(cur.starts_at).getTime() : null;
    const endsAt = req.body?.endsAt ? new Date(req.body.endsAt) : span ? new Date(startsAt.getTime() + span) : null;
    if (Number.isNaN(startsAt.getTime()) || (endsAt && Number.isNaN(endsAt.getTime()))) return bad(reply, 400, "bad-date");
    if (endsAt && (endsAt <= startsAt || endsAt.getTime() - startsAt.getTime() > 90 * DAY)) return bad(reply, 400, "bad-range");
    const id = crypto.randomUUID();
    await pool.query("INSERT INTO biz_offers(id,biz_id,kind,title,description,value,item_id,conditions,members_only,transferable,starts_at,ends_at,template,created_by) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)",
      [id, g.b.id, cur.kind, cur.title, cur.description, JSON.stringify(cur.value ?? {}), cur.item_id, JSON.stringify(cur.conditions ?? {}), cur.members_only, cur.transferable, startsAt.toISOString(), endsAt ? endsAt.toISOString() : null, cur.template, g.uid]);
    const o = (await pool.query("SELECT * FROM biz_offers WHERE id=$1", [id])).rows[0];
    let notified = 0;
    if (state(o) === "active" && o.kind !== "loyalty") notified = await notifyMembers(g.b, { kind: "biz_offer", title: `عرض من ${bizName(g.b)}`, body: o.title, data: { bizId: g.b.id, offerId: id, section: "offers" } });
    return { ...(await offerOut(o)), stats: await statsFor(o), notified };
  });
}
