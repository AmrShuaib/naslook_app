// توزيع التذاكر على الأصحاب (15 نوفمبر 2026، قرار المالك مع قسم «استكشف»): من اشترى عدة تذاكر يرسل كل واحدة لمستخدم
// في ناس لايف (تصله طلباً يقبله أو يرفضه) أو برابط لشخص واحد عبر أي تطبيق. التحويل مجاني دائماً (لا سعر ولا إعادة بيع).
// القواعد: تحويل معلّق واحد للتذكرة؛ التذكرة تبقى للمرسل حتى القبول وله استرجاعها؛ عند القبول يتغير رمز الدخول فلا يدخل
// بها اثنان؛ ومن دفع ثمنها (tickets.payer_id) يبقى كما هو فيعود إليه الاسترداد إن أُلغيت الفعالية (commerce.js).
// جدول واحد ticket_transfers، ولا يُلمس مسار الشراء. التفاصيل في docs/ticket-sharing.md.
// التسجيل في register.txt:
//   await app.register((await import("./ticket_share.js")).default, { pool, auth });
import crypto from "node:crypto";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const TOKEN_RE = /^[A-Za-z0-9_-]{16,64}$/;
/// سقف يومي لما يرسله المستخدم (لمستخدمين وروابط معاً) حتى لا تصير التذاكر وسيلة إزعاج
export const MAX_SENDS_PER_DAY = 40;
const APP_URL = (process.env.APP_URL || "https://naslife.app").replace(/\/+$/, "");

export default async function ticketSharePlugin(app, { pool, auth }) {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS ticket_transfers (
      id UUID PRIMARY KEY, ticket_id UUID NOT NULL, from_id TEXT NOT NULL, to_id TEXT, token TEXT UNIQUE,
      status TEXT NOT NULL DEFAULT 'pending', created_at TIMESTAMPTZ NOT NULL DEFAULT now(), closed_at TIMESTAMPTZ);
    -- تحويل معلّق واحد لكل تذكرة: الفهرس الفريد يحسم السباق بين طلبين متزامنين
    CREATE UNIQUE INDEX IF NOT EXISTS ticket_transfers_one_pending ON ticket_transfers(ticket_id) WHERE status='pending';
    CREATE INDEX IF NOT EXISTS ticket_transfers_to ON ticket_transfers(to_id) WHERE status='pending';
    CREATE INDEX IF NOT EXISTS ticket_transfers_from ON ticket_transfers(from_id, created_at DESC);
    ALTER TABLE tickets ADD COLUMN IF NOT EXISTS payer_id TEXT;
  `);

  const bad = (reply, code, error, extra = {}) => reply.code(code).send({ error, ...extra });
  const unauthorized = (reply) => bad(reply, 401, "unauthorized");
  const notify = async (ids, payload) => { try { await globalThis.naslifeNotify?.(ids, payload); } catch { /* الإشعار لا يُفشل التحويل */ } };
  const blockedIds = async (uid) => { try { return (await globalThis.naslifeBlockedIds?.(uid)) ?? []; } catch { return []; } };
  const person = async (id) => {
    try {
      const u = (await pool.query("SELECT * FROM users WHERE id=$1", [id])).rows[0];
      return u ? { id: u.id, nickname: u.nickname ?? "", avatarUrl: u.avatar_url ?? u.avatarUrl ?? null } : null;
    } catch { return null; }
  };
  const tx = async (fn) => {
    const c = await pool.connect();
    try { await c.query("BEGIN"); const r = await fn(c); await c.query("COMMIT"); return r; }
    catch (e) { try { await c.query("ROLLBACK"); } catch { /* ignore */ } throw e; }
    finally { c.release(); }
  };
  const fail = (code) => Object.assign(new Error(code), { code });
  const TICKET_SQL = "SELECT t.*, e.title, e.starts_at, e.place_name, e.cancelled, e.hidden, tt.name AS tier_name FROM tickets t JOIN events e ON e.id=t.event_id LEFT JOIN ticket_tiers tt ON tt.id=t.tier_id";
  // الشكل نفسه الذي يعيده GET /tickets في commerce.js
  const ticketOut = (t) => ({ id: t.id, code: t.code, status: t.status, paid: Number(t.paid), eventId: t.event_id, title: t.title, startsAt: t.starts_at, placeName: t.place_name, tier: t.tier_name ?? "", createdAt: t.created_at, usedAt: t.used_at });
  const brief = (t) => ({ id: t.id, eventId: t.event_id, title: t.title, startsAt: t.starts_at, placeName: t.place_name, tier: t.tier_name ?? "" });
  const linkUrl = (token) => `${APP_URL}/t/${token}`;
  const outItem = async (tr) => ({ ticketId: tr.ticket_id, transferId: tr.id, mode: tr.token ? "link" : "user", to: tr.to_id ? await person(tr.to_id) : null, url: tr.token ? linkUrl(tr.token) : null, createdAt: tr.created_at });
  const newCode = () => "NAS-" + crypto.randomBytes(4).toString("hex").toUpperCase();

  /// التذكرة لصاحبها، صالحة، وفعاليتها قائمة: وإلا لا تُحوَّل
  const ownTicket = async (c, id, uid) => {
    const t = (await c.query(`${TICKET_SQL} WHERE t.id=$1 FOR UPDATE OF t`, [id])).rows[0];
    if (!t || t.user_id !== uid) throw fail("not-found");
    if (t.status !== "valid" || t.cancelled || t.hidden) throw fail("not-transferable");
    return t;
  };
  const underCap = async (c, uid) => {
    const n = (await c.query("SELECT count(*)::int AS n FROM ticket_transfers WHERE from_id=$1 AND created_at > now() - interval '1 day'", [uid])).rows[0].n;
    if (n >= MAX_SENDS_PER_DAY) throw fail("too-many");
  };
  const sendErr = (reply, e) => {
    const map = { "not-found": 404, "not-transferable": 409, "already-pending": 409, "too-many": 429 };
    if (map[e.code]) return bad(reply, map[e.code], e.code);
    // سباق على الفهرس الفريد: طلب آخر سبق بتحويل معلّق
    if (e.code === "23505") return bad(reply, 409, "already-pending");
    throw e;
  };

  // ---- ما أرسلته وما وصلني (المعلّق فقط، ولتذاكر ما زالت صالحة)
  app.get("/tickets/shares", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const out = (await pool.query(`SELECT tr.* FROM ticket_transfers tr JOIN tickets t ON t.id=tr.ticket_id
      WHERE tr.from_id=$1 AND tr.status='pending' AND t.status='valid' AND t.user_id=$1 ORDER BY tr.created_at`, [uid])).rows;
    const blocked = await blockedIds(uid);
    const inc = (await pool.query(`SELECT tr.id AS transfer_id, tr.from_id, tr.created_at AS sent_at, t.id, t.event_id, e.title, e.starts_at, e.place_name, tt.name AS tier_name
      FROM ticket_transfers tr JOIN tickets t ON t.id=tr.ticket_id JOIN events e ON e.id=t.event_id LEFT JOIN ticket_tiers tt ON tt.id=t.tier_id
      WHERE tr.to_id=$1 AND tr.status='pending' AND t.status='valid' AND t.user_id=tr.from_id AND NOT e.cancelled AND NOT e.hidden
        AND NOT (tr.from_id = ANY($2::text[])) ORDER BY tr.created_at DESC LIMIT 100`, [uid, blocked])).rows;
    return {
      outgoing: await Promise.all(out.map(outItem)),
      incoming: await Promise.all(inc.map(async (r) => ({ transferId: r.transfer_id, from: (await person(r.from_id)) ?? { id: r.from_id, nickname: "", avatarUrl: null }, ticket: brief(r), createdAt: r.sent_at }))),
    };
  });

  // ---- إرسال لمستخدم في ناس لايف
  app.post("/tickets/:id/send", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 404, "not-found");
    const to = String(req.body?.userId ?? "").trim();
    if (!to || to.length > 40) return bad(reply, 400, "bad-user");
    if (to === uid) return bad(reply, 400, "self");
    const target = await person(to);
    if (!target) return bad(reply, 400, "bad-user");
    // الحظر في أي اتجاه يمنع الإرسال، وبالرد نفسه حتى لا يُعرف من حظر من
    if ((await blockedIds(uid)).includes(to) || (await blockedIds(to)).includes(uid)) return bad(reply, 403, "blocked");
    let tr, t;
    try {
      ({ tr, t } = await tx(async (c) => {
        const t = await ownTicket(c, req.params.id, uid);
        if ((await c.query("SELECT 1 FROM ticket_transfers WHERE ticket_id=$1 AND status='pending'", [t.id])).rowCount) throw fail("already-pending");
        await underCap(c, uid);
        const tr = (await c.query("INSERT INTO ticket_transfers(id,ticket_id,from_id,to_id) VALUES($1,$2,$3,$4) RETURNING *", [crypto.randomUUID(), t.id, uid, to])).rows[0];
        return { tr, t };
      }));
    } catch (e) { return sendErr(reply, e); }
    const me = await person(uid);
    await notify(to, { kind: "ticket_gift", title: "وصلتك تذكرة", body: `${me?.nickname || "صديق"} أرسل لك تذكرة: ${t.title}`, data: { transferId: tr.id, eventId: t.event_id }, exclude: uid });
    return outItem(tr);
  });

  // ---- رابط لشخص واحد عبر أي تطبيق آخر (يعيد الرابط القائم إن وُجد)
  app.post("/tickets/:id/link", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 404, "not-found");
    try {
      const tr = await tx(async (c) => {
        const t = await ownTicket(c, req.params.id, uid);
        const cur = (await c.query("SELECT * FROM ticket_transfers WHERE ticket_id=$1 AND status='pending'", [t.id])).rows[0];
        if (cur) { if (cur.token) return cur; throw fail("already-pending"); }
        await underCap(c, uid);
        return (await c.query("INSERT INTO ticket_transfers(id,ticket_id,from_id,token) VALUES($1,$2,$3,$4) RETURNING *", [crypto.randomUUID(), t.id, uid, crypto.randomBytes(18).toString("base64url")])).rows[0];
      });
      return outItem(tr);
    } catch (e) { return sendErr(reply, e); }
  });

  // ---- استرجاع: يلغي التحويل المعلّق (لمستخدم أو رابط) فتبقى التذكرة برمزها عند صاحبها
  app.delete("/tickets/:id/send", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 404, "not-found");
    const r = await pool.query("UPDATE ticket_transfers SET status='cancelled', closed_at=now() WHERE ticket_id=$1 AND from_id=$2 AND status='pending' RETURNING id", [req.params.id, uid]);
    if (!r.rowCount) return bad(reply, 404, "not-found");
    return { ok: true };
  });

  /// القبول (بالطلب أو بالرابط) في معاملة واحدة: التحويل ما زال معلّقاً والتذكرة ما زالت صالحة عند مرسلها، فتنتقل برمز جديد
  const accept = async (where, args, uid) => tx(async (c) => {
    const tr = (await c.query(`SELECT * FROM ticket_transfers WHERE ${where} FOR UPDATE`, args)).rows[0];
    if (!tr) throw fail("not-found");
    if (tr.from_id === uid) throw fail("self");
    if (tr.status !== "pending") throw fail("gone");
    const t = (await c.query(`${TICKET_SQL} WHERE t.id=$1 FOR UPDATE OF t`, [tr.ticket_id])).rows[0];
    if (!t || t.user_id !== tr.from_id || t.status !== "valid" || t.cancelled || t.hidden) {
      await c.query("UPDATE ticket_transfers SET status='cancelled', closed_at=now() WHERE id=$1", [tr.id]);
      return { gone: true };
    }
    const code = newCode();
    await c.query("UPDATE tickets SET user_id=$2, code=$3, payer_id=COALESCE(payer_id,$4) WHERE id=$1", [t.id, uid, code, tr.from_id]);
    await c.query("UPDATE ticket_transfers SET status='accepted', to_id=$2, closed_at=now() WHERE id=$1", [tr.id, uid]);
    return { tr, ticket: { ...t, user_id: uid, code } };
  });
  const acceptReply = async (reply, run, uid) => {
    let r;
    try { r = await run(); } catch (e) {
      if (e.code === "not-found") return bad(reply, 404, "not-found");
      if (e.code === "gone") return bad(reply, 409, "gone");
      if (e.code === "self") return bad(reply, 400, "self");
      throw e;
    }
    if (r.gone) return bad(reply, 409, "gone");
    const me = await person(uid);
    await notify(r.tr.from_id, { kind: "ticket_accepted", title: "استُلمت التذكرة", body: `${me?.nickname || "صديقك"} استلم تذكرة ${r.ticket.title}`, data: { eventId: r.ticket.event_id }, exclude: uid });
    return ticketOut(r.ticket);
  };

  app.post("/tickets/transfers/:id/accept", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 404, "not-found");
    return acceptReply(reply, () => accept("id=$1 AND to_id=$2", [req.params.id, uid], uid), uid);
  });
  app.post("/tickets/transfers/:id/decline", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 404, "not-found");
    const r = await pool.query("UPDATE ticket_transfers SET status='declined', closed_at=now() WHERE id=$1 AND to_id=$2 AND status='pending' RETURNING from_id, ticket_id", [req.params.id, uid]);
    if (!r.rowCount) return bad(reply, 404, "not-found");
    const t = (await pool.query(`${TICKET_SQL} WHERE t.id=$1`, [r.rows[0].ticket_id])).rows[0];
    const me = await person(uid);
    if (t) await notify(r.rows[0].from_id, { kind: "ticket_declined", title: "لم تُقبل التذكرة", body: `${me?.nickname || "صديقك"} لم يقبل تذكرة ${t.title}، وهي باقية عندك`, data: { eventId: t.event_id }, exclude: uid });
    return { ok: true };
  });

  // ---- الرابط: معاينة بلا حساب (اسم الفعالية والمرسل فقط، بلا رمز الدخول) ثم استلام بحساب
  app.get("/tickets/claim/:token", async (req, reply) => {
    const token = String(req.params.token ?? "");
    if (!TOKEN_RE.test(token)) return bad(reply, 404, "not-found");
    const tr = (await pool.query("SELECT * FROM ticket_transfers WHERE token=$1", [token])).rows[0];
    if (!tr) return bad(reply, 404, "not-found");
    const t = (await pool.query(`${TICKET_SQL} WHERE t.id=$1`, [tr.ticket_id])).rows[0];
    if (!t) return bad(reply, 404, "not-found");
    const from = await person(tr.from_id);
    const live = tr.status === "pending" && t.status === "valid" && t.user_id === tr.from_id && !t.cancelled && !t.hidden;
    reply.header("cache-control", "no-store");
    return { title: t.title, startsAt: t.starts_at, placeName: t.place_name, tier: t.tier_name ?? "", from: { nickname: from?.nickname ?? "", avatarUrl: from?.avatarUrl ?? null }, status: live ? "pending" : "gone" };
  });
  app.post("/tickets/claim", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const token = String(req.body?.token ?? "");
    if (!TOKEN_RE.test(token)) return bad(reply, 404, "not-found");
    return acceptReply(reply, () => accept("token=$1", [token], uid), uid);
  });

  // صفحة الرابط العام: تحوّل إلى التطبيق (#/t/<token>) كما تفعل روابط اللحظات والعروض؛ غير مفهرسة ولا تُخزَّن
  app.get("/t/:token", async (req, reply) => {
    const token = String(req.params.token ?? "");
    reply.header("cache-control", "no-store").header("x-robots-tag", "noindex");
    return reply.redirect(TOKEN_RE.test(token) ? `/#/t/${token}` : "/", 302);
  });
}
