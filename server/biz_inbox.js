// رسائل الدوائر الخاصة (نوفمبر 2026، البند 24 من النواقص): محادثة خاصة بين مستخدم ودائرة تجارية، منفصلة عن محادثات النواة
// (النواة تملك POST /messages و/ws بين مستخدمَين فقط). محادثة واحدة لكل (دائرة، مستخدم) تُفتح بأول رسالة وتُعاد فتحها برسالة جديدة.
// الرسالة: نص، حتى 4 صور من /chat/upload، ومرجع اختياري إلى طلب للعميل في الدائرة أو صنف من كتالوجها.
// جهة الدائرة: صندوق مشترك للمالك والمدير والموظف (ليس دور hr ولا مدير النظام)؛ الرد يظهر للعميل باسم الدائرة وشعارها
// ويُسجَّل داخلياً من كتبه من الفريق، مع الإسناد والإغلاق وعدّادات غير المقروء. الإدارة لا تقرأ المحادثات إلا عبر بلاغ على رسالة
// (نوع biz-msg في safety.js، وسياقها في GET /adminapi/bizinbox/reported/:msgId).
// التسجيل في register.txt بعد business.js وsafety.js:
//   await app.register((await import("./biz_inbox.js")).default, { pool, auth });
import crypto from "node:crypto";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SLUG_RE = /^[a-z0-9-]{3,60}$/;
const ITEM_RE = /^[A-Za-z0-9_-]{1,80}$/;
const ID_RE = /^[A-Z]{2}\d{7}$/;
const CLIENT_RE = /^[A-Za-z0-9_-]{4,64}$/;
// ملف رفعه المستخدم عبر /chat/upload: يُحفظ المسار وحده فيُحمَّل من أصلنا دائماً (كصور النزاع في business.js)
const MEDIA_RE = /^(?:https?:\/\/[^/]+)?(\/chat\/media\/[A-Za-z0-9._-]{1,120})$/;
export const MAX_TEXT = 2000;
export const MAX_PHOTOS = 4;
export const PER_MIN = 30;          // رسائل في الدقيقة لكل مستخدم (من أي جهة)
export const THREADS_PER_DAY = 5;   // محادثات جديدة في اليوم لكل مستخدم
const PAGE = 50;
// من يرى صندوق الدائرة ويرد: المالك والمدير والموظف (دور hr للتوظيف فقط، ومدير النظام لا يقرأ إلا عبر بلاغ)
export const INBOX_ROLES = new Set(["owner", "manager", "staff"]);
const ASSIGN_ANY = new Set(["owner", "manager"]);
export const FILTERS = ["open", "closed", "mine", "all"];

const str = (v, max) => String(v ?? "").trim().slice(0, max);
export const mediaPath = (v) => String(v ?? "").trim().match(MEDIA_RE)?.[1] ?? null;
const clip = (t, n = 100) => (t.length > n ? t.slice(0, n) + "…" : t);
/// معاينة آخر رسالة في القوائم: النص، أو «صورة»، أو اسم المرجع
export const previewOf = (text, photos, ref) => (text ? clip(text.replace(/\s+/g, " "), 120) : photos > 0 ? (photos > 1 ? `${photos} صور` : "صورة") : ref === "order" ? "طلب" : ref === "item" ? "صنف" : "");

export default async function bizInbox(app, opts) {
  const { pool, auth } = opts;
  if (!pool || !auth) throw new Error("biz_inbox: pool and auth are required");
  const perMin = opts.perMin ?? PER_MIN;
  const perDay = opts.threadsPerDay ?? THREADS_PER_DAY;
  await pool.query(`
    CREATE TABLE IF NOT EXISTS biz_threads (
      id UUID PRIMARY KEY, biz_id TEXT NOT NULL, user_id TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'open', assignee_id TEXT,
      last_at TIMESTAMPTZ NOT NULL DEFAULT now(), last_text TEXT NOT NULL DEFAULT '', last_side TEXT NOT NULL DEFAULT 'customer',
      user_unread INT NOT NULL DEFAULT 0, team_unread INT NOT NULL DEFAULT 0, user_read_at TIMESTAMPTZ, team_read_at TIMESTAMPTZ,
      closed_at TIMESTAMPTZ, closed_by TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), UNIQUE (biz_id, user_id));
    CREATE INDEX IF NOT EXISTS biz_threads_biz ON biz_threads(biz_id, last_at DESC);
    CREATE INDEX IF NOT EXISTS biz_threads_user ON biz_threads(user_id, last_at DESC);
    CREATE TABLE IF NOT EXISTS biz_thread_msgs (
      id UUID PRIMARY KEY, thread_id UUID NOT NULL REFERENCES biz_threads(id) ON DELETE CASCADE, side TEXT NOT NULL, sender_id TEXT NOT NULL,
      text TEXT NOT NULL DEFAULT '', photos JSONB NOT NULL DEFAULT '[]', ref_kind TEXT, ref_id TEXT, client_id TEXT,
      hidden BOOLEAN NOT NULL DEFAULT false, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE INDEX IF NOT EXISTS biz_thread_msgs_thread ON biz_thread_msgs(thread_id, created_at);
    CREATE INDEX IF NOT EXISTS biz_thread_msgs_sender ON biz_thread_msgs(sender_id, created_at);
    CREATE UNIQUE INDEX IF NOT EXISTS biz_thread_msgs_client ON biz_thread_msgs(thread_id, sender_id, client_id) WHERE client_id IS NOT NULL;
  `);

  const unauthorized = (reply) => reply.code(401).send({ error: "auth" });
  const bad = (reply, code, error, extra = {}) => reply.code(code).send({ error, ...extra });
  const notify = async (ids, payload) => { try { await globalThis.naslifeNotify?.(ids, payload); } catch { /* الإشعار لا يُفشل الرسالة */ } };
  const banned = (...texts) => { try { return globalThis.naslifeCheckText?.(...texts.filter(Boolean)) ?? null; } catch { return null; } };
  const isBlocked = async (a, b) => { if (!a || !b || a === b) return false; try { return !!(await globalThis.naslifeIsBlocked?.(a, b)); } catch { return false; } };
  const blockedIds = async (uid) => { try { return (await globalThis.naslifeBlockedIds?.(uid)) ?? []; } catch { return []; } };
  const isSuspended = async (uid) => {
    if (typeof globalThis.naslifeIsSuspended === "function") { try { return !!(await globalThis.naslifeIsSuspended(uid)); } catch { return false; } }
    try { return (await pool.query("SELECT 1 FROM user_flags WHERE user_id=$1 AND suspended", [uid])).rowCount > 0; } catch { return false; }
  };
  const people = async (ids) => {
    const m = new Map(); const uniq = [...new Set(ids.filter(Boolean))];
    if (!uniq.length) return m;
    try { for (const u of (await pool.query("SELECT * FROM users WHERE id = ANY($1::text[])", [uniq])).rows) m.set(u.id, { id: u.id, nickname: u.nickname ?? u.name ?? "", avatarUrl: u.avatar_url ?? null }); } catch { /* ignore */ }
    return m;
  };
  const personIn = (pm, id) => (id ? pm.get(id) ?? { id, nickname: "", avatarUrl: null } : null);
  const bizName = (b) => b?.name_ar || b?.name || b?.id || "";
  const loadBiz = async (id) => {
    if (!SLUG_RE.test(String(id ?? ""))) return null;
    try { return (await pool.query("SELECT * FROM biz WHERE id=$1", [id])).rows[0] ?? null; } catch { return null; }
  };
  const bizRef = (b) => ({ id: b.id, name: bizName(b), logoUrl: b.logo_url ?? null, category: b.category ?? null, verified: b.verified === true, ownerId: b.owner_id ?? null });
  /// دور المستخدم في صندوق الدائرة: owner|manager|staff أو null (hr ومدير النظام خارج الصندوق)
  async function teamRole(uid, b) {
    if (!uid || !b) return null;
    if (b.owner_id === uid) return "owner";
    try {
      const r = (await pool.query("SELECT role FROM biz_staff WHERE biz_id=$1 AND user_id=$2", [b.id, uid])).rows[0];
      return r && INBOX_ROLES.has(r.role) ? r.role : null;
    } catch { return null; }
  }
  // أي عضو في فريق الدائرة (ومنه hr) لا يراسل دائرته كعميل
  const onStaff = async (uid, b) => { try { return (await pool.query("SELECT 1 FROM biz_staff WHERE biz_id=$1 AND user_id=$2", [b.id, uid])).rowCount > 0; } catch { return false; } };
  /// فريق الصندوق: المالك ثم المديرون والموظفون (بلا hr)
  async function inboxTeam(b) {
    let rows = [];
    try { rows = (await pool.query("SELECT user_id, role FROM biz_staff WHERE biz_id=$1 AND role IN ('manager','staff') ORDER BY created_at", [b.id])).rows; } catch { rows = []; }
    const out = b.owner_id ? [{ id: b.owner_id, role: "owner" }] : [];
    for (const r of rows) if (r.user_id !== b.owner_id) out.push({ id: r.user_id, role: r.role });
    return out;
  }
  const loadThread = async (tid) => {
    if (!UUID_RE.test(String(tid ?? ""))) return null;
    return (await pool.query("SELECT * FROM biz_threads WHERE id=$1", [tid])).rows[0] ?? null;
  };
  /// جهة المستخدم في المحادثة وحالتها: { side: customer|team, role, b } أو null (ليس طرفاً، أو بينه وبين الطرف الآخر حظر)
  async function viewerOf(uid, t, b) {
    if (!t || !b) return null;
    if (t.user_id === uid) {
      // حظر بين العميل ومالك الدائرة يغلق القناة كلها: لا تظهر المحادثة له
      if (await isBlocked(uid, b.owner_id)) return null;
      return { side: "customer", role: null };
    }
    const role = await teamRole(uid, b);
    if (!role) return null;
    if (await isBlocked(uid, t.user_id)) return null;
    return { side: "team", role };
  }
  // سبب منع الإرسال (null = مسموح). للمحادثة الجديدة يُشترط أن تكون الدائرة نشطة ولها مالك
  async function sendBlockReason(uid, side, b, { fresh = false, customerId = null } = {}) {
    if (b.hidden === true) return "unavailable";
    if (side === "customer") {
      if (!b.owner_id) return "no-owner";
      if (fresh && b.active === false) return "unavailable";
      if (b.owner_id === uid || (await onStaff(uid, b))) return "own-circle";
      if (await isBlocked(uid, b.owner_id)) return "blocked";
    } else {
      if (await isBlocked(uid, customerId) || await isBlocked(b.owner_id, customerId)) return "blocked";
    }
    if (await isSuspended(uid)) return "suspended";
    return null;
  }
  const REASON_CODE = { unavailable: 409, "no-owner": 409, "own-circle": 400, blocked: 403, suspended: 403 };

  // ---- المراجع: طلب للعميل في الدائرة نفسها، أو صنف من كتالوجها
  async function parseRef(raw, b, customerId) {
    if (raw == null || raw === "") return { ok: true, ref: null };
    const kind = String(raw?.kind ?? "");
    // معرّف الطلب بحروف صغيرة كما يعيده pg حتى تُحل بطاقته عند القراءة
    const id = kind === "order" ? str(raw?.id, 80).toLowerCase() : str(raw?.id, 80);
    if (kind === "order") {
      if (!UUID_RE.test(id)) return { ok: false };
      try { const r = await pool.query("SELECT 1 FROM biz_orders WHERE id=$1 AND biz_id=$2 AND user_id=$3", [id, b.id, customerId]); return r.rowCount ? { ok: true, ref: { kind, id } } : { ok: false }; } catch { return { ok: false }; }
    }
    if (kind === "item") {
      if (!ITEM_RE.test(id)) return { ok: false };
      try { const r = await pool.query("SELECT 1 FROM biz_items WHERE id=$1 AND biz_id=$2", [id, b.id]); return r.rowCount ? { ok: true, ref: { kind, id } } : { ok: false }; } catch { return { ok: false }; }
    }
    return { ok: false };
  }
  /// بطاقات المراجع محلولة لحظة القراءة (حالة الطلب الحالية لا وقت الإرسال)
  async function refsFor(rows) {
    const orders = [...new Set(rows.filter((m) => m.ref_kind === "order" && UUID_RE.test(m.ref_id ?? "")).map((m) => m.ref_id))];
    const items = [...new Set(rows.filter((m) => m.ref_kind === "item").map((m) => m.ref_id))];
    const out = new Map();
    if (orders.length) {
      try {
        for (const o of (await pool.query("SELECT o.id, o.code, o.status, o.total, o.start_at, o.kind, o.qty, i.title FROM biz_orders o LEFT JOIN biz_items i ON i.id=o.item_id WHERE o.id = ANY($1::uuid[])", [orders])).rows)
          out.set("order:" + o.id, { kind: "order", id: o.id, title: o.title ?? "", code: o.code, status: o.status, total: Number(o.total), startAt: o.start_at, itemKind: o.kind, qty: o.qty });
      } catch { /* ignore */ }
    }
    if (items.length) {
      try {
        for (const i of (await pool.query("SELECT id, title, price, image_url, kind, unit FROM biz_items WHERE id = ANY($1::text[])", [items])).rows)
          out.set("item:" + i.id, { kind: "item", id: i.id, title: i.title, price: Number(i.price), imageUrl: i.image_url ?? null, itemKind: i.kind, unit: i.unit });
      } catch { /* ignore */ }
    }
    return out;
  }
  /// الرسالة لجهة القارئ: العميل لا يرى من كتب من الفريق (الرد باسم الدائرة)، والفريق يراه
  function msgOut(m, viewer, uid, refs, pm) {
    const hidden = m.hidden === true;
    const out = {
      id: m.id, threadId: m.thread_id, side: m.side, mine: viewer === "customer" ? m.side === "customer" : m.sender_id === uid,
      text: hidden ? "" : m.text, photos: hidden ? [] : (Array.isArray(m.photos) ? m.photos : []), hidden,
      ref: hidden || !m.ref_kind ? null : (refs.get(`${m.ref_kind}:${m.ref_id}`) ?? { kind: m.ref_kind, id: m.ref_id, missing: true }),
      clientId: m.sender_id === uid ? m.client_id ?? null : null, createdAt: m.created_at,
    };
    if (viewer === "team" && m.side === "team") out.sender = personIn(pm, m.sender_id);
    return out;
  }
  function threadOut(t, viewer, b, pm) {
    const base = {
      id: t.id, bizId: t.biz_id, status: t.status, lastAt: t.last_at, lastText: t.last_text, lastSide: t.last_side, createdAt: t.created_at, closedAt: t.closed_at ?? null,
    };
    if (viewer === "customer") return { ...base, biz: b ? bizRef(b) : { id: t.biz_id, name: "", logoUrl: null, verified: false }, unread: t.user_unread, seenAt: t.team_read_at ?? null };
    return { ...base, customer: personIn(pm, t.user_id), assignee: personIn(pm, t.assignee_id), unread: t.team_unread, seenAt: t.user_read_at ?? null };
  }
  async function customerOrders(b, customerId) {
    try {
      return (await pool.query(`SELECT o.id, o.code, o.status, o.total, o.start_at, o.kind, o.qty, o.created_at, i.title FROM biz_orders o LEFT JOIN biz_items i ON i.id=o.item_id
        WHERE o.biz_id=$1 AND o.user_id=$2 ORDER BY o.created_at DESC LIMIT 10`, [b.id, customerId])).rows
        .map((o) => ({ kind: "order", id: o.id, title: o.title ?? "", code: o.code, status: o.status, total: Number(o.total), startAt: o.start_at, itemKind: o.kind, qty: o.qty }));
    } catch { return []; }
  }
  async function messagesOf(t, viewer, uid, { before = null } = {}) {
    const rows = (await pool.query(`SELECT * FROM biz_thread_msgs WHERE thread_id=$1 AND ($2::timestamptz IS NULL OR created_at < $2) ORDER BY created_at DESC, id DESC LIMIT ${PAGE + 1}`, [t.id, before])).rows;
    const hasMore = rows.length > PAGE;
    const page = rows.slice(0, PAGE).reverse();
    const refs = await refsFor(page);
    const pm = viewer === "team" ? await people(page.filter((m) => m.side === "team").map((m) => m.sender_id)) : new Map();
    return { messages: page.map((m) => msgOut(m, viewer, uid, refs, pm)), hasMore };
  }

  // ---- حدود المعدّل من القاعدة نفسها (تصمد بعد إعادة التشغيل وعبر العمليات)
  const sentLastMinute = async (uid) => (await pool.query("SELECT count(*)::int AS n FROM biz_thread_msgs WHERE sender_id=$1 AND created_at > now() - interval '1 minute'", [uid])).rows[0].n;
  const threadsToday = async (uid) => (await pool.query("SELECT count(*)::int AS n FROM biz_threads WHERE user_id=$1 AND created_at > now() - interval '1 day'", [uid])).rows[0].n;

  /// يتحقق من جسم الرسالة: { text, photos, clientId } أو رمز خطأ
  function parseBody(body) {
    const text = str(body?.text, MAX_TEXT);
    const rawPhotos = Array.isArray(body?.photos) ? body.photos : [];
    if (rawPhotos.length > MAX_PHOTOS) return { error: "too-many-photos" };
    const photos = rawPhotos.map(mediaPath);
    if (photos.some((p) => !p)) return { error: "bad-photo" };
    if (!text && !photos.length) return { error: "empty" };
    const clientId = body?.clientId == null || body.clientId === "" ? null : String(body.clientId);
    if (clientId != null && !CLIENT_RE.test(clientId)) return { error: "bad-client-id" };
    return { text, photos, clientId };
  }

  /// يضيف رسالة إلى المحادثة ويحدّث عدّاداتها وحالتها، ثم يرسل الإشعار عند أول رسالة غير مقروءة للطرف الآخر
  async function append(t, b, { side, uid, text, photos, ref, clientId }) {
    if (clientId) {
      const dup = (await pool.query("SELECT * FROM biz_thread_msgs WHERE thread_id=$1 AND sender_id=$2 AND client_id=$3", [t.id, uid, clientId])).rows[0];
      if (dup) return { m: dup, t, duplicate: true };
    }
    const id = crypto.randomUUID();
    let m;
    try {
      m = (await pool.query("INSERT INTO biz_thread_msgs(id,thread_id,side,sender_id,text,photos,ref_kind,ref_id,client_id) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING *",
        [id, t.id, side, uid, text, JSON.stringify(photos), ref?.kind ?? null, ref?.id ?? null, clientId])).rows[0];
    } catch (e) {
      // إرسالان متزامنان بالمعرّف نفسه: الثاني يعيد الأول
      if (e?.code === "23505" && clientId) return { m: (await pool.query("SELECT * FROM biz_thread_msgs WHERE thread_id=$1 AND sender_id=$2 AND client_id=$3", [t.id, uid, clientId])).rows[0], t, duplicate: true };
      throw e;
    }
    const preview = previewOf(text, photos.length, ref?.kind);
    // رسالة جديدة تعيد فتح المحادثة المغلقة؛ وكاتبها قرأ ما قبلها
    const sql = side === "customer"
      ? "UPDATE biz_threads SET status='open', closed_at=NULL, closed_by=NULL, last_at=$2, last_text=$3, last_side='customer', team_unread=team_unread+1, user_unread=0, user_read_at=$2 WHERE id=$1 RETURNING *"
      : "UPDATE biz_threads SET status='open', closed_at=NULL, closed_by=NULL, last_at=$2, last_text=$3, last_side='team', user_unread=user_unread+1, team_unread=0, team_read_at=$2 WHERE id=$1 RETURNING *";
    const nt = (await pool.query(sql, [t.id, m.created_at, preview])).rows[0];
    const name = bizName(b);
    if (side === "customer" && nt.team_unread === 1) {
      // المحادثة المسندة تُنبّه المسؤول وحده (إن بقي في الفريق)، وإلا الفريق كله؛ من بينه وبين العميل حظر لا يُنبَّه
      const team = await inboxTeam(b);
      let to = nt.assignee_id && team.some((x) => x.id === nt.assignee_id) ? [nt.assignee_id] : team.map((x) => x.id);
      const blocked = new Set(await blockedIds(uid));
      to = to.filter((x) => !blocked.has(x));
      const nick = (await people([uid])).get(uid)?.nickname || uid;
      await notify(to, { kind: "biz_inbox_message", title: `رسالة جديدة · ${name}`, body: `${nick}: ${preview}`, data: { bizId: b.id, threadId: t.id, manage: true }, exclude: uid });
    } else if (side === "team" && nt.user_unread === 1) {
      await notify([nt.user_id], { kind: "biz_inbox_reply", title: `رد من ${name}`, body: preview, data: { bizId: b.id, threadId: t.id } });
    }
    return { m, t: nt, duplicate: false };
  }
  // يرد بخطأ إن لم يُقبل الإرسال؛ يعيد true عند الرفض
  async function rejectSend(reply, uid, parsed, { fresh = false } = {}) {
    if (parsed.error) { bad(reply, 400, parsed.error, parsed.error === "too-many-photos" ? { max: MAX_PHOTOS } : {}); return true; }
    const w = banned(parsed.text);
    if (w) { bad(reply, 400, "banned-words", { word: w }); return true; }
    if (await sentLastMinute(uid) >= perMin) { bad(reply, 429, "rate-limit", { perMin }); return true; }
    if (fresh && await threadsToday(uid) >= perDay) { bad(reply, 429, "too-many-threads", { perDay }); return true; }
    return false;
  }

  app.get("/bizinbox/status", async () => ({ ok: true, perMin, threadsPerDay: perDay, maxPhotos: MAX_PHOTOS, maxText: MAX_TEXT, roles: [...INBOX_ROLES], filters: FILTERS }));

  // ================= جهة العميل
  // محادثتي مع دائرة (قبل أول رسالة: thread=null) مع حالة الإرسال وطلباتي فيها لبطاقة المرجع
  app.get("/biz/:id/thread", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const b = await loadBiz(req.params.id);
    const t0 = b ? (await pool.query("SELECT * FROM biz_threads WHERE biz_id=$1 AND user_id=$2", [b.id, uid])).rows[0] ?? null : null;
    // الدائرة المخفية بالإشراف لا تُفتح لمن لم يراسلها قبل الإخفاء
    if (!b || (b.hidden === true && !t0)) return bad(reply, 404, "not-found");
    // حظر بيني وبين مالكها: لا تُعرض المحادثة السابقة (الحظر يخفي بالاتجاهين) ويبقى السبب ظاهراً
    const t = t0 && (await viewerOf(uid, t0, b)) ? t0 : null;
    const reason = await sendBlockReason(uid, "customer", b, { fresh: !t0 });
    const msgs = t ? await messagesOf(t, "customer", uid) : { messages: [], hasMore: false };
    return { biz: bizRef(b), thread: t ? threadOut(t, "customer", b) : null, ...msgs, canSend: !reason, reason, orders: reason === "own-circle" ? [] : await customerOrders(b, uid) };
  });
  // بدء محادثة مع دائرة أو متابعتها: أول رسالة تنشئ المحادثة (5 في اليوم على الأكثر)
  app.post("/biz/:id/thread", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const b = await loadBiz(req.params.id);
    if (!b) return bad(reply, 404, "not-found");
    let t = (await pool.query("SELECT * FROM biz_threads WHERE biz_id=$1 AND user_id=$2", [b.id, uid])).rows[0] ?? null;
    const reason = await sendBlockReason(uid, "customer", b, { fresh: !t });
    if (reason) return bad(reply, REASON_CODE[reason] ?? 403, reason);
    const parsed = parseBody(req.body);
    if (await rejectSend(reply, uid, parsed, { fresh: !t })) return;
    const r = await parseRef(req.body?.ref, b, uid);
    if (!r.ok) return bad(reply, 400, "bad-ref");
    if (!t) {
      t = (await pool.query("INSERT INTO biz_threads(id,biz_id,user_id) VALUES($1,$2,$3) ON CONFLICT (biz_id,user_id) DO UPDATE SET biz_id=EXCLUDED.biz_id RETURNING *", [crypto.randomUUID(), b.id, uid])).rows[0];
    }
    const out = await append(t, b, { side: "customer", uid, ...parsed, ref: r.ref });
    const refs = await refsFor([out.m]);
    return { thread: threadOut(out.t, "customer", b), message: msgOut(out.m, "customer", uid, refs, new Map()), duplicate: out.duplicate };
  });
  // «رسائل الدوائر» في قائمة محادثاتي: الأحدث أولاً، بلا محادثات بيني وبين مالكها حظر
  app.get("/bizinbox/threads", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const blocked = await blockedIds(uid);
    const rows = (await pool.query(`SELECT t.*, b.name, b.name_ar, b.logo_url, b.category, b.verified, b.owner_id, b.hidden FROM biz_threads t JOIN biz b ON b.id=t.biz_id
      WHERE t.user_id=$1 AND COALESCE(b.owner_id, '') <> ALL($2::text[]) ORDER BY t.last_at DESC LIMIT 100`, [uid, blocked])).rows;
    const threads = rows.map((r) => threadOut(r, "customer", { id: r.biz_id, name: r.name, name_ar: r.name_ar, logo_url: r.logo_url, category: r.category, verified: r.verified, owner_id: r.owner_id }));
    return { threads, unread: threads.reduce((n, t) => n + (t.unread > 0 ? 1 : 0), 0) };
  });

  // ================= المحادثة بمعرّفها (للعميل أو لفريق الدائرة)
  async function open(req, reply) {
    const uid = await auth(req); if (!uid) { unauthorized(reply); return null; }
    const t = await loadThread(req.params.tid);
    const b = t ? await loadBiz(t.biz_id) : null;
    const v = await viewerOf(uid, t, b);
    if (!v) { bad(reply, 404, "not-found"); return null; }
    return { uid, t, b, ...v };
  }
  app.get("/bizinbox/threads/:tid", async (req, reply) => {
    const g = await open(req, reply); if (!g) return;
    const before = req.query?.before && !Number.isNaN(Date.parse(req.query.before)) ? new Date(req.query.before).toISOString() : null;
    const pm = g.side === "team" ? await people([g.t.user_id, g.t.assignee_id]) : new Map();
    const reason = await sendBlockReason(g.uid, g.side, g.b, { customerId: g.t.user_id });
    const msgs = await messagesOf(g.t, g.side, g.uid, { before });
    const out = { viewer: g.side, role: g.role, biz: bizRef(g.b), thread: threadOut(g.t, g.side, g.b, pm), ...msgs, canSend: !reason, reason, orders: await customerOrders(g.b, g.t.user_id) };
    if (g.side === "team") {
      const team = await inboxTeam(g.b);
      const tm = await people(team.map((x) => x.id));
      out.team = team.map((x) => ({ ...personIn(tm, x.id), role: x.role }));
      out.canAssignOthers = ASSIGN_ANY.has(g.role);
    }
    return out;
  });
  app.post("/bizinbox/threads/:tid/messages", async (req, reply) => {
    const g = await open(req, reply); if (!g) return;
    const reason = await sendBlockReason(g.uid, g.side, g.b, { customerId: g.t.user_id });
    if (reason) return bad(reply, REASON_CODE[reason] ?? 403, reason);
    const parsed = parseBody(req.body);
    if (await rejectSend(reply, g.uid, parsed)) return;
    const r = await parseRef(req.body?.ref, g.b, g.t.user_id);
    if (!r.ok) return bad(reply, 400, "bad-ref");
    const out = await append(g.t, g.b, { side: g.side, uid: g.uid, ...parsed, ref: r.ref });
    const refs = await refsFor([out.m]);
    const pm = g.side === "team" ? await people([g.uid, out.t.user_id, out.t.assignee_id]) : new Map();
    return { thread: threadOut(out.t, g.side, g.b, pm), message: msgOut(out.m, g.side, g.uid, refs, pm), duplicate: out.duplicate };
  });
  app.post("/bizinbox/threads/:tid/read", async (req, reply) => {
    const g = await open(req, reply); if (!g) return;
    const sql = g.side === "customer" ? "UPDATE biz_threads SET user_unread=0, user_read_at=now() WHERE id=$1" : "UPDATE biz_threads SET team_unread=0, team_read_at=now() WHERE id=$1";
    await pool.query(sql, [g.t.id]);
    return { ok: true };
  });

  // ================= جهة الدائرة
  async function teamGuard(req, reply) {
    const uid = await auth(req); if (!uid) { unauthorized(reply); return null; }
    const b = await loadBiz(req.params.id);
    if (!b) { bad(reply, 404, "not-found"); return null; }
    const role = await teamRole(uid, b);
    if (!role) { bad(reply, 403, "forbidden"); return null; }
    return { uid, b, role };
  }
  const FILTER_SQL = { open: "AND t.status='open'", closed: "AND t.status='closed'", mine: "", all: "" };
  app.get("/biz/:id/inbox", async (req, reply) => {
    const g = await teamGuard(req, reply); if (!g) return;
    const filter = FILTERS.includes(req.query?.filter) ? req.query.filter : "open";
    const blocked = await blockedIds(g.uid);
    const rows = (await pool.query(`SELECT t.* FROM biz_threads t WHERE t.biz_id=$1 ${FILTER_SQL[filter]} AND ($2::text IS NULL OR t.assignee_id=$2) AND t.user_id <> ALL($3::text[]) ORDER BY t.last_at DESC LIMIT 200`,
      [g.b.id, filter === "mine" ? g.uid : null, blocked])).rows;
    const c = (await pool.query(`SELECT count(*) FILTER (WHERE status='open')::int AS open, count(*) FILTER (WHERE status='closed')::int AS closed,
      count(*) FILTER (WHERE assignee_id=$2)::int AS mine, count(*) FILTER (WHERE team_unread > 0)::int AS unread
      FROM biz_threads WHERE biz_id=$1 AND user_id <> ALL($3::text[])`, [g.b.id, g.uid, blocked])).rows[0];
    const pm = await people(rows.flatMap((t) => [t.user_id, t.assignee_id]));
    const team = await inboxTeam(g.b);
    const tm = await people(team.map((x) => x.id));
    return { filter, role: g.role, canAssignOthers: ASSIGN_ANY.has(g.role), counts: c, threads: rows.map((t) => threadOut(t, "team", g.b, pm)), team: team.map((x) => ({ ...personIn(tm, x.id), role: x.role })) };
  });
  // شارة تبويب «الرسائل» في لوحة الدائرة: محادثات فيها رسائل لم يقرأها الفريق
  app.get("/biz/:id/inbox/unread", async (req, reply) => {
    const g = await teamGuard(req, reply); if (!g) return;
    const blocked = await blockedIds(g.uid);
    const r = (await pool.query("SELECT count(*) FILTER (WHERE team_unread > 0)::int AS unread, count(*) FILTER (WHERE status='open')::int AS open, count(*) FILTER (WHERE assignee_id=$2 AND team_unread > 0)::int AS mine FROM biz_threads WHERE biz_id=$1 AND user_id <> ALL($3::text[])", [g.b.id, g.uid, blocked])).rows[0];
    return r;
  });
  async function teamThread(req, reply) {
    const g = await open(req, reply); if (!g) return null;
    if (g.side !== "team") { bad(reply, 403, "forbidden"); return null; }
    return g;
  }
  // الإسناد: المالك والمدير لأي عضو في الصندوق (أو إلغاؤه)؛ الموظف يأخذ المحادثة لنفسه أو يتركها إن كانت له
  app.post("/bizinbox/threads/:tid/assign", async (req, reply) => {
    const g = await teamThread(req, reply); if (!g) return;
    const to = req.body?.userId == null || req.body.userId === "" ? null : str(req.body.userId, 12).toUpperCase();
    if (to != null && !ID_RE.test(to)) return bad(reply, 400, "bad-user");
    const team = await inboxTeam(g.b);
    if (to != null && !team.some((x) => x.id === to)) return bad(reply, 400, "not-in-team");
    if (!ASSIGN_ANY.has(g.role)) {
      const ok = to === g.uid || (to == null && g.t.assignee_id === g.uid);
      if (!ok) return bad(reply, 403, "forbidden");
    }
    if (to != null && await isBlocked(to, g.t.user_id)) return bad(reply, 403, "blocked");
    const t = (await pool.query("UPDATE biz_threads SET assignee_id=$2 WHERE id=$1 RETURNING *", [g.t.id, to])).rows[0];
    if (to && to !== g.uid && to !== g.t.assignee_id) {
      const nick = (await people([g.t.user_id])).get(g.t.user_id)?.nickname || g.t.user_id;
      await notify([to], { kind: "biz_inbox_assigned", title: `أُسندت إليك محادثة · ${bizName(g.b)}`, body: `مع ${nick}${t.last_text ? `: ${t.last_text}` : ""}`, data: { bizId: g.b.id, threadId: t.id, manage: true } });
    }
    const pm = await people([t.user_id, t.assignee_id]);
    return { thread: threadOut(t, "team", g.b, pm) };
  });
  // الإغلاق وإعادة الفتح لأي عضو في الصندوق؛ رسالة جديدة من أي طرف تعيد الفتح أيضاً
  for (const [path, status] of [["close", "closed"], ["reopen", "open"]]) {
    app.post(`/bizinbox/threads/:tid/${path}`, async (req, reply) => {
      const g = await teamThread(req, reply); if (!g) return;
      const t = (await (status === "closed"
        ? pool.query("UPDATE biz_threads SET status='closed', closed_at=now(), closed_by=$2 WHERE id=$1 RETURNING *", [g.t.id, g.uid])
        : pool.query("UPDATE biz_threads SET status='open', closed_at=NULL, closed_by=NULL WHERE id=$1 RETURNING *", [g.t.id]))).rows[0];
      const pm = await people([t.user_id, t.assignee_id]);
      return { thread: threadOut(t, "team", g.b, pm) };
    });
  }

  // ================= البلاغ والإدارة
  /// لـ safety.js: جهة المستخدم في محادثة الرسالة (customer|team) حتى لا يُبلغ عنها إلا طرفاها، والمرسل لا يُبلغ عن جهته
  globalThis.naslifeBizInboxSideOf = async (uid, msgId) => {
    if (!uid || !UUID_RE.test(String(msgId ?? ""))) return null;
    const m = (await pool.query("SELECT t.* FROM biz_thread_msgs m JOIN biz_threads t ON t.id=m.thread_id WHERE m.id=$1", [msgId])).rows[0];
    if (!m) return null;
    if (m.user_id === uid) return "customer";
    return (await teamRole(uid, await loadBiz(m.biz_id))) ? "team" : null;
  };
  // الإدارة تقرأ المحادثة عبر بلاغ فقط: الرسالة المُبلَّغ عنها وعشر قبلها وعشر بعدها، ولا قائمة عامة للمحادثات
  app.get("/adminapi/bizinbox/reported/:msgId", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    let ok = false;
    try { ok = !!(await globalThis.naslifeIsAdmin?.(uid)); } catch { ok = false; }
    if (!ok) { try { ok = !!(await globalThis.naslifeTeamCan?.(uid, "reports.view")); } catch { ok = false; } }
    if (!ok) return bad(reply, 403, "forbidden");
    const id = String(req.params.msgId ?? "");
    if (!UUID_RE.test(id)) return bad(reply, 404, "not-found");
    let reports = 0;
    try { reports = (await pool.query("SELECT count(DISTINCT reporter_id)::int AS n FROM content_reports WHERE target_type='biz-msg' AND target_id=$1", [id])).rows[0].n; } catch { reports = 0; }
    if (!reports) return bad(reply, 404, "not-reported");
    const m = (await pool.query("SELECT * FROM biz_thread_msgs WHERE id=$1", [id])).rows[0];
    if (!m) return bad(reply, 404, "not-found");
    const t = await loadThread(m.thread_id);
    const b = await loadBiz(t.biz_id);
    const ctx = (await pool.query(`(SELECT * FROM biz_thread_msgs WHERE thread_id=$1 AND (created_at, id) < ($2, $3) ORDER BY created_at DESC, id DESC LIMIT 10)
      UNION ALL (SELECT * FROM biz_thread_msgs WHERE id=$3)
      UNION ALL (SELECT * FROM biz_thread_msgs WHERE thread_id=$1 AND (created_at, id) > ($2, $3) ORDER BY created_at, id LIMIT 10)`, [t.id, m.created_at, id])).rows
      .sort((a, z) => new Date(a.created_at) - new Date(z.created_at) || String(a.id).localeCompare(String(z.id)));
    const refs = await refsFor(ctx);
    const pm = await people([t.user_id, ...ctx.map((x) => x.sender_id)]);
    // الإدارة ترى النص حتى للرسائل المخفية (للمراجعة) ومن كتبها من الفريق
    const out = ctx.map((x) => ({ ...msgOut({ ...x, hidden: false }, "team", null, refs, pm), hidden: x.hidden === true, reported: x.id === id, sender: personIn(pm, x.sender_id) }));
    try { await pool.query("INSERT INTO admin_audit(id,admin_id,action,target,details) VALUES($1,$2,$3,$4,$5)", [crypto.randomUUID(), uid, "bizinbox.read-reported", `biz-msg:${id}`, JSON.stringify({ threadId: t.id, bizId: t.biz_id })]); } catch { /* ignore */ }
    return { reports, biz: b ? bizRef(b) : { id: t.biz_id }, thread: { id: t.id, status: t.status, customer: personIn(pm, t.user_id), createdAt: t.created_at }, messages: out };
  });
}
