// رموز الاختصار في محادثات Naslife: يكتب المستخدم رمزاً قصيراً (@sara، @brew92، #brew92/v60، #ev/…، /pay 45 قهوة، /meet 7م @brew92)
// فيظهر عند الطرفين بطاقة ذكية بزر واحد. البطاقة تحمل المعرّف فقط، وهذه الإضافة تجلب الاسم والسعر والحالة من مصدرها عند العرض
// حتى لا يمكن تزوير سعر أو مبلغ. الطلبات (مبلغ، تقسيم، موعد، إرسال) تُسجَّل هنا بمعرّف الرسالة وتُدار حالتها (معلّق، مدفوع، مقبول…).
// التسجيل في src/index.js بعد chat_tools.js وcommerce.js:
//   await app.register((await import("./chat_cards.js")).default, { pool, auth });
// التحويل المالي يمر عبر globalThis.naslifeWalletTransfer التي تعرّفها commerce.js، وبيانات الطلبات تُدمج في GET /chat/meta
// عبر globalThis.naslifeChatRequests.
import { isOpenNow } from "./business.js";

const UUID_RE = /^[0-9a-f-]{36}$/i;
const ID_RE = /^[A-Z]{2}\d{7}$/;
const SLUG_RE = /^[a-z0-9][a-z0-9-]{1,63}$/;
const CODE_RE = /^[A-Z0-9][A-Z0-9-]{4,40}$/;
const NICK_RE = /^[\p{L}\p{N}_.-]{2,40}$/u;
const MAX_REFS = 40;
const DAY = 24 * 3600 * 1000;
export const REQUEST_KINDS = ["pay", "send", "split", "meet"];
export const CARD_TYPES = ["user", "biz", "item", "event", "listing", "post", "space", "spacepost", "ticket", "order"];
/// أقصى مبلغ لطلب أو تحويل عبر المحادثة (بالهللات): 20,000 ر.س
const MAX_AMOUNT = 20000 * 100;
const EXPIRY = { pay: DAY, split: DAY, meet: 3 * DAY, send: 0 };

export default async function chatCards(app, opts) {
  try {
    await setup(app, opts);
  } catch (e) {
    (app.log?.error ? app.log.error.bind(app.log) : console.error)(`chat_cards disabled: ${e?.stack || e}`);
  }
}

async function setup(app, opts) {
  const { pool, auth } = opts;
  if (!pool || !auth) throw new Error("chat_cards: pool and auth are required");
  await pool.query(`
    CREATE TABLE IF NOT EXISTS chat_requests (
      message_id TEXT PRIMARY KEY, kind TEXT NOT NULL, from_id TEXT NOT NULL, to_id TEXT NOT NULL,
      amount BIGINT NOT NULL DEFAULT 0, n INT NOT NULL DEFAULT 1, note TEXT NOT NULL DEFAULT '', when_text TEXT NOT NULL DEFAULT '', place TEXT NOT NULL DEFAULT '',
      status TEXT NOT NULL DEFAULT 'pending', created_at TIMESTAMPTZ NOT NULL DEFAULT now(), resolved_at TIMESTAMPTZ, expires_at TIMESTAMPTZ);
    CREATE INDEX IF NOT EXISTS chat_requests_to ON chat_requests(to_id, status);
  `);

  const unauthorized = (reply) => reply.code(401).send({ error: "auth" });
  const bad = (reply, code, error, extra = {}) => reply.code(code).send({ error, ...extra });
  const str = (v, max) => String(v ?? "").trim().slice(0, max);
  const cols = async (table) => { try { return new Set((await pool.query("SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name=$1", [table])).rows.map((r) => r.column_name)); } catch { return new Set(); } };
  const userCols = await cols("users");
  const avatarCol = ["avatar_url", "avatarurl", "avatar", "photo_url", "image_url", "picture"].find((c) => userCols.has(c)) ?? null;
  const personOf = (u) => u ? { id: u.id, nickname: u.nickname ?? "", avatarUrl: avatarCol ? u[avatarCol] ?? null : null } : null;
  const userRow = async (id) => { try { return (await pool.query("SELECT * FROM users WHERE id=$1", [id])).rows[0] ?? null; } catch { return null; } };
  const userByNick = async (nick) => { try { return (await pool.query("SELECT * FROM users WHERE lower(nickname)=lower($1) ORDER BY id LIMIT 1", [nick])).rows[0] ?? null; } catch { return null; } };
  const nickOf = async (id) => (await userRow(id))?.nickname || id;
  const notify = async (ids, payload) => { try { await globalThis.naslifeNotify?.(ids, payload); } catch { /* ignore */ } };
  const sar = (h) => { const v = Number(h) / 100; return (Number.isInteger(v) ? String(v) : v.toFixed(2)) + " ر.س"; };
  const blocked = async (a, b) => { try { return (await pool.query("SELECT 1 FROM user_blocks WHERE (user_id=$1 AND blocked_id=$2) OR (user_id=$2 AND blocked_id=$1)", [a, b])).rowCount > 0; } catch { return false; } };
  // المال داخل المحادثة (طلب مبلغ، تقسيم، إرسال): مفتاح المنصة chatPaymentsEnabled، ومطفأ دائماً في عميل iOS الأصلي
  const iosNative = (req) => /^ios\//i.test(String(req.headers["x-naslife-client"] ?? ""));
  const moneyOff = (req) => globalThis.naslifeSettings?.chatPaymentsEnabled === false || iosNative(req);

  // ---- الدوائر والأصناف: المعرّف كما هو أو مع البادئة biz- (يكتب المستخدم @brew92 بدل @biz-brew92)
  const bizRow = async (slug) => {
    if (!SLUG_RE.test(slug)) return null;
    try {
      const r = await pool.query("SELECT * FROM biz WHERE id = ANY($1) AND active ORDER BY (id=$2) DESC LIMIT 1", [[slug, `biz-${slug}`], slug]);
      return r.rows[0] ?? null;
    } catch { return null; }
  };
  const bizShort = (id) => id.startsWith("biz-") ? id.slice(4) : id;
  const itemRow = async (b, slug) => {
    if (!SLUG_RE.test(slug)) return null;
    const ids = [slug, `${bizShort(b.id)}-${slug}`, `${b.id}-${slug}`];
    try { return (await pool.query("SELECT * FROM biz_items WHERE biz_id=$1 AND id = ANY($2) AND active ORDER BY array_position($2, id) LIMIT 1", [b.id, ids])).rows[0] ?? null; } catch { return null; }
  };
  const bizCard = (b) => ({ type: "biz", id: b.id, title: b.name_ar || b.name, subtitle: b.address || "", image: b.logo_url ?? null, category: b.category, openNow: isOpenNow(b.hours), verified: b.verified === true, link: `/c/${b.id}` });
  const itemCard = async (b, i) => {
    let discussions = 0;
    try {
      const d = await pool.query("SELECT (SELECT count(*) FROM biz_community_posts WHERE item_id=$1 AND hidden=false)::int + (SELECT count(*) FROM biz_community_replies WHERE item_id=$1 AND hidden=false)::int AS n", [i.id]);
      discussions = d.rows[0]?.n ?? 0;
    } catch { /* الأعمدة غير موجودة بعد */ }
    return { type: "item", id: i.id, bizId: b.id, title: i.title, subtitle: b.name_ar || b.name, image: i.image_url ?? b.logo_url ?? null, price: Number(i.price), unit: i.unit, kind: i.kind, category: b.category, discussions, link: `/c/${b.id}` };
  };

  // ---- تحليل رمز واحد إلى بطاقة (null إن لم يُفهم أو لم يوجد)
  async function resolve(ref) {
    const s = String(ref ?? "").trim();
    if (s.length < 2 || s.length > 120) return null;
    if (s[0] === "@") {
      const x = s.slice(1);
      if (SLUG_RE.test(x) && (x.startsWith("biz-") || !(await userByNick(x)))) { const b = await bizRow(x); if (b) return bizCard(b); }
      if (NICK_RE.test(x)) { const u = await userByNick(x); if (u) return { type: "user", id: u.id, title: u.nickname ?? "", subtitle: "", image: personOf(u).avatarUrl, link: `/u/${encodeURIComponent(u.nickname ?? "")}` }; }
      const b = await bizRow(x);
      return b ? bizCard(b) : null;
    }
    if (s[0] !== "#") return null;
    const parts = s.slice(1).split("/").filter(Boolean);
    if (!parts.length || parts.length > 3) return null;
    const [a, b, c] = parts;
    switch (a) {
      case "ev": {
        if (!UUID_RE.test(b ?? "")) return null;
        const e = (await pool.query("SELECT * FROM events WHERE id=$1", [b])).rows[0]; if (!e) return null;
        const t = (await pool.query("SELECT min(price)::bigint AS min, sum(quantity-sold)::int AS left FROM ticket_tiers WHERE event_id=$1", [e.id])).rows[0];
        const going = (await pool.query("SELECT count(DISTINCT user_id)::int AS n FROM tickets WHERE event_id=$1 AND status<>'refunded'", [e.id])).rows[0].n;
        return { type: "event", id: e.id, title: e.title, subtitle: e.place_name ?? "", startsAt: e.starts_at, price: t?.min == null ? null : Number(t.min), left: t?.left ?? 0, going, cancelled: e.cancelled === true, host: personOf(await userRow(e.host_id)) };
      }
      case "mk": {
        if (!UUID_RE.test(b ?? "")) return null;
        const l = (await pool.query("SELECT * FROM market_listings WHERE id=$1", [b])).rows[0]; if (!l) return null;
        let images = []; try { images = Array.isArray(l.images) ? l.images : JSON.parse(l.images ?? "[]"); } catch { images = []; }
        const bits = [l.city || l.place_name, l.kind === "service" ? "خدمة" : l.condition === "used" ? "مستعمل" : null, l.delivery ? "توصيل" : null, l.rating_avg != null && Number(l.rating_count) > 0 ? `★ ${Number(l.rating_avg).toFixed(1)}` : null, Number(l.sold) > 0 ? `${l.sold} مبيعة` : null].filter(Boolean);
        return { type: "listing", id: l.id, title: l.title, subtitle: bits.join(" · "), image: images[0] ?? l.image_url ?? null, price: Number(l.price), status: l.status, kind: l.kind ?? null, category: l.category ?? null, verified: l.spotlight_until != null && new Date(l.spotlight_until) > new Date(), left: l.stock == null ? null : Number(l.stock), seller: personOf(await userRow(l.seller_id)) };
      }
      case "post": {
        if (!UUID_RE.test(b ?? "")) return null;
        const p = (await pool.query("SELECT * FROM map_posts WHERE id=$1 AND status='active'", [b])).rows[0]; if (!p) return null;
        const u = personOf(await userRow(p.user_id));
        return { type: "post", id: p.id, title: p.title || p.caption || (p.kind === "image" ? "صورة" : p.kind === "video" ? "فيديو" : p.kind === "audio" ? "تسجيل صوتي" : "منشور"), subtitle: [u?.nickname, p.place_name].filter(Boolean).join(" · "), image: p.kind === "image" ? p.media_url : null, kind: p.kind, price: p.price == null ? null : Number(p.price), user: u };
      }
      case "space": {
        const biz = await bizRow(b ?? ""); if (!biz) return null;
        if (c) {
          if (!UUID_RE.test(c)) return null;
          const p = (await pool.query("SELECT * FROM biz_community_posts WHERE id=$1 AND biz_id=$2 AND hidden=false", [c, biz.id])).rows[0]; if (!p) return null;
          const u = personOf(await userRow(p.user_id));
          const replies = (await pool.query("SELECT count(*)::int AS n FROM biz_community_replies WHERE post_id=$1 AND hidden=false", [p.id])).rows[0].n;
          return { type: "spacepost", id: p.id, bizId: biz.id, title: p.text || (p.audio ? "🎤 مشاركة صوتية" : "📷 صور"), subtitle: [u?.nickname, biz.name_ar || biz.name].filter(Boolean).join(" · "), image: Array.isArray(p.images) && p.images[0] ? p.images[0] : null, replies, user: u };
        }
        let posts = 0, members = 0;
        try { const t = (await pool.query("SELECT count(*)::int AS n, count(DISTINCT user_id)::int AS m FROM biz_community_posts WHERE biz_id=$1 AND hidden=false", [biz.id])).rows[0]; posts = t.n; members = t.m; } catch { /* لا مجتمع بعد */ }
        return { type: "space", id: biz.id, bizId: biz.id, title: `مساحة ${biz.name_ar || biz.name}`, subtitle: `${posts} مشاركة · ${members} مشارك`, image: biz.logo_url ?? null, posts, members, link: `/c/${biz.id}` };
      }
      case "t": {
        const code = String(b ?? "").toUpperCase(); if (!CODE_RE.test(code)) return null;
        const t = (await pool.query("SELECT t.*, e.title, e.starts_at, e.place_name, tt.name AS tier_name FROM tickets t JOIN events e ON e.id=t.event_id JOIN ticket_tiers tt ON tt.id=t.tier_id WHERE t.code=$1", [code])).rows[0]; if (!t) return null;
        return { type: "ticket", id: t.id, code: t.code, eventId: t.event_id, title: t.title, subtitle: [t.tier_name, t.place_name].filter(Boolean).join(" · "), startsAt: t.starts_at, status: t.status, paid: Number(t.paid), owner: personOf(await userRow(t.user_id)) };
      }
      case "o": {
        const code = String(b ?? "").toUpperCase(); if (!CODE_RE.test(code)) return null;
        const o = (await pool.query("SELECT o.*, i.title AS item_title, b.name, b.name_ar, b.category FROM biz_orders o JOIN biz_items i ON i.id=o.item_id JOIN biz b ON b.id=o.biz_id WHERE o.code=$1", [code])).rows[0]; if (!o) return null;
        return { type: "order", id: o.id, code: o.code, bizId: o.biz_id, itemId: o.item_id, title: o.item_title, subtitle: o.name_ar || o.name, category: o.category, kind: o.kind, qty: o.qty, startAt: o.start_at, total: Number(o.total), status: o.status, owner: personOf(await userRow(o.user_id)), link: `/c/${o.biz_id}` };
      }
      default: {
        // #دائرة/صنف
        if (c) return null;
        const biz = await bizRow(a); if (!biz) return null;
        if (!b) return bizCard(biz);
        const i = await itemRow(biz, b);
        return i ? itemCard(biz, i) : null;
      }
    }
  }

  app.get("/chat/cards/status", async () => ({ ok: true, types: CARD_TYPES, requestKinds: REQUEST_KINDS, wallet: typeof globalThis.naslifeWalletTransfer === "function", maxAmount: MAX_AMOUNT }));

  // GET /chat/cards?refs=@sara,%23brew92/v60 → { refs: { "@sara": {...}, "#brew92/v60": null } }
  app.get("/chat/cards", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const refs = [...new Set(String(req.query?.refs ?? "").split(",").map((s) => s.trim()).filter(Boolean))].slice(0, MAX_REFS);
    const out = {};
    await Promise.all(refs.map(async (r) => { try { out[r] = await resolve(r); } catch (e) { req.log?.warn?.(`chat_cards resolve ${r}: ${e?.message}`); out[r] = null; } }));
    return { refs: out };
  });

  // ---- الطلبات: مبلغ، تقسيم، موعد، إرسال (مسجّلة بمعرّف الرسالة)
  const share = (r) => r.kind === "split" ? Math.ceil(Number(r.amount) / Math.max(1, r.n)) : Number(r.amount);
  const requestOut = (r) => {
    const expired = r.status === "pending" && r.expires_at && new Date(r.expires_at) < new Date();
    return { messageId: r.message_id, kind: r.kind, from: r.from_id, to: r.to_id, amount: Number(r.amount), n: r.n, share: share(r), note: r.note, when: r.when_text, place: r.place,
      status: expired ? "expired" : r.status, createdAt: r.created_at, resolvedAt: r.resolved_at, expiresAt: r.expires_at };
  };
  async function requestsFor(ids, uid) {
    const m = {};
    if (!ids.length) return m;
    const rows = (await pool.query("SELECT * FROM chat_requests WHERE message_id = ANY($1) AND (from_id=$2 OR to_id=$2)", [ids, uid])).rows;
    for (const r of rows) m[r.message_id] = requestOut(r);
    return m;
  }
  globalThis.naslifeChatRequests = requestsFor;

  app.get("/chat/requests", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const ids = String(req.query?.ids ?? "").split(",").map((s) => s.trim()).filter((s) => s && s.length <= 64).slice(0, 200);
    return requestsFor(ids, uid);
  });

  app.post("/chat/requests", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const b = req.body ?? {};
    const messageId = str(b.messageId, 64); if (!messageId) return bad(reply, 400, "bad-id");
    const peerId = str(b.peerId, 16); if (!ID_RE.test(peerId) || peerId === uid) return bad(reply, 400, "bad-peer");
    const kind = str(b.kind, 10); if (!REQUEST_KINDS.includes(kind)) return bad(reply, 400, "bad-kind", { allowed: REQUEST_KINDS });
    if (kind !== "meet" && moneyOff(req)) return bad(reply, 403, "unavailable");
    if (await blocked(uid, peerId)) return bad(reply, 403, "blocked");
    const amount = Math.round(Number(b.amount) || 0);
    const n = Math.round(Number(b.n) || 1);
    const note = str(b.note, 120), when = str(b.when, 40), place = str(b.place, 80);
    if (kind !== "meet" && (amount <= 0 || amount > MAX_AMOUNT)) return bad(reply, 400, "bad-amount", { max: MAX_AMOUNT });
    if (kind === "split" && (n < 2 || n > 20)) return bad(reply, 400, "bad-count");
    if (kind === "meet" && !when) return bad(reply, 400, "bad-when");
    let status = "pending";
    if (kind === "send") {
      // التحويل نفّذه التطبيق عبر /wallet/transfer قبل إرسال الرسالة؛ نتحقق من وجوده في السجل خلال الدقائق الماضية
      let ok = false;
      try { ok = (await pool.query("SELECT 1 FROM wallet_tx WHERE user_id=$1 AND peer_id=$2 AND kind='transfer_out' AND amount=$3 AND created_at > now() - interval '10 minutes'", [uid, peerId, -amount])).rowCount > 0; } catch { ok = false; }
      status = ok ? "paid" : "unverified";
    }
    const expires = EXPIRY[kind] ? new Date(Date.now() + EXPIRY[kind]) : null;
    const r = await pool.query(`INSERT INTO chat_requests(message_id,kind,from_id,to_id,amount,n,note,when_text,place,status,expires_at,resolved_at)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) ON CONFLICT (message_id) DO UPDATE SET note=EXCLUDED.note WHERE chat_requests.from_id=EXCLUDED.from_id RETURNING *`,
      [messageId, kind, uid, peerId, amount, n, note, when, place, status, expires, status === "pending" ? null : new Date()]);
    if (!r.rows[0]) return bad(reply, 409, "exists");
    return { ok: true, request: requestOut(r.rows[0]) };
  });

  const load = async (id, uid, reply) => {
    const r = (await pool.query("SELECT * FROM chat_requests WHERE message_id=$1", [id])).rows[0];
    if (!r || (r.from_id !== uid && r.to_id !== uid)) { bad(reply, 404, "not-found"); return null; }
    return r;
  };
  const finish = async (id, status) => (await pool.query("UPDATE chat_requests SET status=$2, resolved_at=now() WHERE message_id=$1 RETURNING *", [id, status])).rows[0];

  // المستلم يدفع المبلغ (أو نصيبه من التقسيم) إلى صاحب الطلب من محفظته
  app.post("/chat/requests/:id/pay", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const r = await load(str(req.params.id, 64), uid, reply); if (!r) return;
    if (r.to_id !== uid) return bad(reply, 403, "not-recipient");
    if (!["pay", "split"].includes(r.kind)) return bad(reply, 400, "not-payable");
    if (moneyOff(req)) return bad(reply, 403, "unavailable");
    if (await blocked(uid, r.from_id)) return bad(reply, 403, "blocked");
    const cur = requestOut(r);
    if (cur.status !== "pending") return bad(reply, 409, "not-pending", { status: cur.status });
    const transfer = globalThis.naslifeWalletTransfer;
    if (typeof transfer !== "function") return bad(reply, 503, "wallet-unavailable");
    const amount = share(r);
    try {
      await transfer({ from: uid, to: r.from_id, amount, note: r.note || (r.kind === "split" ? "نصيبي من الفاتورة" : "طلب عبر المحادثة"), ref: r.message_id });
    } catch (e) {
      if (e?.code === "insufficient-funds") return bad(reply, 402, "insufficient-funds");
      if (e?.code === "not-found" || e?.code === "bad-recipient") return bad(reply, 404, "recipient-missing");
      if (e?.code === "suspended") return bad(reply, 403, "suspended");
      throw e;
    }
    const done = await finish(r.message_id, "paid");
    return { ok: true, request: requestOut(done) };
  });

  app.post("/chat/requests/:id/accept", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const r = await load(str(req.params.id, 64), uid, reply); if (!r) return;
    if (r.to_id !== uid) return bad(reply, 403, "not-recipient");
    if (r.kind !== "meet") return bad(reply, 400, "not-acceptable");
    if (requestOut(r).status !== "pending") return bad(reply, 409, "not-pending", { status: requestOut(r).status });
    const done = await finish(r.message_id, "accepted");
    await notify(r.from_id, { kind: "meet_accepted", title: "وافق على الموعد", body: `${await nickOf(uid)} وافق على اللقاء ${r.when_text}${r.place ? " في " + r.place : ""}`, data: { peerId: uid, messageId: r.message_id } });
    return { ok: true, request: requestOut(done) };
  });

  app.post("/chat/requests/:id/decline", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const r = await load(str(req.params.id, 64), uid, reply); if (!r) return;
    if (r.to_id !== uid) return bad(reply, 403, "not-recipient");
    if (requestOut(r).status !== "pending") return bad(reply, 409, "not-pending", { status: requestOut(r).status });
    const done = await finish(r.message_id, "declined");
    return { ok: true, request: requestOut(done) };
  });

  app.post("/chat/requests/:id/cancel", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const r = await load(str(req.params.id, 64), uid, reply); if (!r) return;
    if (r.from_id !== uid) return bad(reply, 403, "not-owner");
    if (requestOut(r).status !== "pending") return bad(reply, 409, "not-pending", { status: requestOut(r).status });
    const done = await finish(r.message_id, "cancelled");
    return { ok: true, request: requestOut(done) };
  });

  // كل الطلبات المعلّقة الموجّهة إليّ (للتنبيه في التطبيق)
  app.get("/chat/requests/pending", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const r = await pool.query("SELECT * FROM chat_requests WHERE to_id=$1 AND status='pending' AND (expires_at IS NULL OR expires_at > now()) ORDER BY created_at DESC LIMIT 50", [uid]);
    return r.rows.map(requestOut);
  });
}
