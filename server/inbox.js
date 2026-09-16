// البريد الوارد لفريق Naslife: صندوق لكل عضو باسمه على نطاق الإرسال (sara@naslife.app) وصندوق مشترك (admin@)،
// استقبال عبر Webhook (Resend Receiving بتوقيع Svix، أو Webhook عام برمز سري لأي خدمة تحويل)، محادثات مترابطة
// بالمعرّفات والموضوع، قراءة/أرشفة/تمييز/إسناد، والرد والإنشاء من اللوحة بعنوان الصندوق نفسه عبر server/mail.js.
// الرؤية: صندوقك دائماً؛ الصندوق المشترك لمن يملك inbox.reply؛ صناديق من تحتك في التسلسل؛ والكل مع inbox.manage.
// التسجيل في src/index.js بعد mail.js وteam.js:
//   await app.register((await import("./inbox.js")).default, { pool, auth });
import crypto from "node:crypto";

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/i;
const UUID_RE = /^[0-9a-f-]{36}$/i;
const ID_RE = /^[A-Z]{2}\d{7}$/;
const str = (v, max) => String(v ?? "").trim().slice(0, max);
const lower = (v) => String(v ?? "").trim().toLowerCase();
/// "الاسم <a@b.c>" → {email, name}
export function parseAddress(v) {
  if (v && typeof v === "object") return { email: lower(v.email ?? v.address), name: str(v.name, 120) };
  const s = String(v ?? "").trim();
  const m = s.match(/^\s*"?([^"<]*)"?\s*<([^>]+)>\s*$/);
  if (m) return { email: lower(m[2]), name: str(m[1], 120) };
  return { email: lower(s), name: "" };
}
const addrList = (v) => (Array.isArray(v) ? v : v == null || v === "" ? [] : String(v).split(",")).map(parseAddress).filter((a) => EMAIL_RE.test(a.email));
/// موضوع مطبّع لربط الردود: بلا Re:/Fwd:/رد:/إعادة توجيه:
export const normSubject = (s) => String(s ?? "").replace(/^(\s*((re|fw|fwd|رد|إعادة توجيه|تحويل)\s*:\s*))+/i, "").trim().toLowerCase().slice(0, 200);
export const stripHtml = (h) => String(h ?? "").replace(/<style[\s\S]*?<\/style>|<script[\s\S]*?<\/script>/gi, " ").replace(/<br\s*\/?>|<\/p>|<\/div>|<\/li>/gi, "\n").replace(/<[^>]+>/g, " ").replace(/&nbsp;/g, " ").replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/[ \t]+/g, " ").replace(/ ?\n ?/g, "\n").replace(/\n{3,}/g, "\n\n").trim();
/// تحقق توقيع Svix (Resend): v1,<base64(HMAC-SHA256(secret, "id.timestamp.body"))>
export function verifySvix(secret, headers, rawBody, now = Date.now()) {
  const id = headers["svix-id"], ts = headers["svix-timestamp"], sig = headers["svix-signature"];
  if (!id || !ts || !sig) return false;
  if (Math.abs(now / 1000 - Number(ts)) > 300) return false;
  const key = Buffer.from(String(secret).replace(/^whsec_/, ""), "base64");
  const expected = crypto.createHmac("sha256", key).update(`${id}.${ts}.${rawBody}`).digest("base64");
  return String(sig).split(/\s+/).some((part) => { const [, v] = part.split(","); return v && v.length === expected.length && crypto.timingSafeEqual(Buffer.from(v), Buffer.from(expected)); });
}

export default async function inbox(app, opts = {}) {
  const pool = opts.pool ?? globalThis.naslifePool ?? null;
  const auth = opts.auth ?? globalThis.naslifeAuth ?? null;
  if (!pool || !auth) throw new Error("inbox: pool and auth are required");
  const fetchFn = () => opts.fetchFn ?? globalThis.fetch;
  await pool.query(`
    CREATE TABLE IF NOT EXISTS inbox_settings (id INT PRIMARY KEY DEFAULT 1, data JSONB NOT NULL DEFAULT '{}', updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE TABLE IF NOT EXISTS inbox_threads (
      id UUID PRIMARY KEY, mailbox TEXT NOT NULL, subject TEXT NOT NULL DEFAULT '', norm_subject TEXT NOT NULL DEFAULT '', snippet TEXT NOT NULL DEFAULT '',
      counterpart TEXT NOT NULL DEFAULT '', counterpart_name TEXT NOT NULL DEFAULT '', participants JSONB NOT NULL DEFAULT '[]',
      last_at TIMESTAMPTZ NOT NULL DEFAULT now(), last_direction TEXT NOT NULL DEFAULT 'in', unread INT NOT NULL DEFAULT 0, message_count INT NOT NULL DEFAULT 0,
      archived BOOLEAN NOT NULL DEFAULT false, starred BOOLEAN NOT NULL DEFAULT false, assigned_to TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE INDEX IF NOT EXISTS inbox_threads_box ON inbox_threads(mailbox, archived, last_at DESC);
    CREATE TABLE IF NOT EXISTS inbox_messages (
      id UUID PRIMARY KEY, thread_id UUID NOT NULL, mailbox TEXT NOT NULL, direction TEXT NOT NULL, message_id TEXT, in_reply_to TEXT, provider_id TEXT,
      from_addr TEXT NOT NULL DEFAULT '', from_name TEXT NOT NULL DEFAULT '', to_addrs JSONB NOT NULL DEFAULT '[]', cc_addrs JSONB NOT NULL DEFAULT '[]',
      subject TEXT NOT NULL DEFAULT '', text TEXT NOT NULL DEFAULT '', html TEXT, attachments JSONB NOT NULL DEFAULT '[]', read BOOLEAN NOT NULL DEFAULT false,
      sent_by TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE INDEX IF NOT EXISTS inbox_messages_thread ON inbox_messages(thread_id, created_at);
    CREATE INDEX IF NOT EXISTS inbox_messages_mid ON inbox_messages(message_id);
    CREATE UNIQUE INDEX IF NOT EXISTS inbox_messages_provider ON inbox_messages(provider_id) WHERE provider_id IS NOT NULL;
  `);
  let settings = { provider: "generic", webhookSecret: "", token: "", lastReceivedAt: null, received: 0, rejected: 0 };
  async function load() { try { const r = await pool.query("SELECT data FROM inbox_settings WHERE id=1"); settings = { ...settings, ...(r.rows[0]?.data ?? {}) }; } catch { /* ignore */ } }
  await load();
  if (!settings.token) { settings.token = crypto.randomBytes(18).toString("base64url"); await pool.query("INSERT INTO inbox_settings(id,data) VALUES(1,$1) ON CONFLICT (id) DO UPDATE SET data=EXCLUDED.data, updated_at=now()", [JSON.stringify(settings)]); }
  const saveSettings = async (next) => { settings = next; await pool.query("INSERT INTO inbox_settings(id,data,updated_at) VALUES(1,$1,now()) ON CONFLICT (id) DO UPDATE SET data=EXCLUDED.data, updated_at=now()", [JSON.stringify(next)]); };

  const teamInfo = async (uid) => { try { return (await globalThis.naslifeTeamInfo?.(uid)) ?? null; } catch { return null; } };
  const teamScope = async (uid) => { try { return (await globalThis.naslifeTeamScope?.(uid)) ?? { all: false, ids: new Set([uid]) }; } catch { return { all: false, ids: new Set([uid]) }; } };
  const teamMembers = async () => { try { return (await globalThis.naslifeTeamMembers?.()) ?? []; } catch { return []; } };
  const people = async (ids) => { try { return (await globalThis.naslifeTeamPeople?.(ids)) ?? new Map(); } catch { return new Map(); } };
  const notify = async (ids, payload) => { try { await globalThis.naslifeNotify?.([...new Set(ids.filter(Boolean))], payload); } catch { /* ignore */ } };
  const has = (info, perm) => !!info && (info.permissions.includes("*") || info.permissions.includes(perm));
  const bad = (reply, code, error, extra = {}) => reply.code(code).send({ error, ...extra });
  const mailCfg = () => { try { return globalThis.naslifeMail?.settings?.() ?? null; } catch { return null; } };
  const domainName = () => mailCfg()?.domain?.name || (mailCfg()?.from?.split("@")[1]) || "naslife.app";
  const sharedLocal = () => mailCfg()?.domain?.local || (mailCfg()?.from?.split("@")[0]) || "admin";

  /// الصناديق المرئية لعضو: {alias, address, label, kind: own|shared|team, ownerId}
  async function mailboxes(uid) {
    const info = await teamInfo(uid); if (!info) return [];
    const dom = domainName(); const members = await teamMembers(); const pmap = await people(members.map((m) => m.user_id));
    const s = await teamScope(uid); const manage = has(info, "inbox.manage");
    const out = [];
    const push = (alias, kind, ownerId, label) => { if (alias && !out.some((x) => x.alias === alias)) out.push({ alias, address: `${alias}@${dom}`, kind, ownerId, label }); };
    if (info.mailbox) push(info.mailbox, "own", uid, "صندوقي");
    if (has(info, "inbox.reply") || manage) push(sharedLocal(), "shared", null, "الصندوق المشترك");
    for (const m of members) if (m.mailbox && m.user_id !== uid && (manage || s.all || s.ids.has(m.user_id))) push(m.mailbox, "team", m.user_id, pmap.get(m.user_id)?.nickname || m.user_id);
    if (out.length) {
      const counts = (await pool.query("SELECT mailbox, sum(unread)::int AS unread FROM inbox_threads WHERE NOT archived AND mailbox = ANY($1) GROUP BY mailbox", [out.map((x) => x.alias)])).rows;
      for (const x of out) x.unread = counts.find((c) => c.mailbox === x.alias)?.unread ?? 0;
    }
    return out;
  }
  const canSee = async (uid, alias) => (await mailboxes(uid)).some((x) => x.alias === alias);
  /// صندوق لعنوان وارد: عضو بالاسم نفسه، وإلا المشترك
  async function routeMailbox(toList) {
    const dom = domainName(); const members = await teamMembers();
    for (const a of toList) { const [local, d] = a.email.split("@"); if (d !== dom) continue; if (local === sharedLocal()) return sharedLocal(); const m = members.find((x) => x.mailbox === local); if (m) return m.mailbox; }
    return sharedLocal();
  }
  async function ownersOf(alias) {
    const members = await teamMembers();
    if (alias === sharedLocal()) {
      let legacy = []; try { legacy = (await pool.query("SELECT user_id FROM admins")).rows.map((r) => r.user_id); } catch { legacy = []; }
      return [...new Set([...members.filter((m) => m.permissions.includes("*") || m.permissions.includes("inbox.reply")).map((m) => m.user_id), ...legacy])];
    }
    return members.filter((m) => m.mailbox === alias).map((m) => m.user_id);
  }
  const threadOut = (t, amap) => ({ id: t.id, mailbox: t.mailbox, subject: t.subject, snippet: t.snippet, counterpart: t.counterpart, counterpartName: t.counterpart_name, participants: t.participants, lastAt: t.last_at, lastDirection: t.last_direction, unread: t.unread, messages: t.message_count, archived: t.archived, starred: t.starred, assignedTo: t.assigned_to, assignedName: t.assigned_to ? (amap?.get(t.assigned_to)?.nickname ?? "") : "" });
  const messageOut = (m) => ({ id: m.id, direction: m.direction, from: { email: m.from_addr, name: m.from_name }, to: m.to_addrs, cc: m.cc_addrs, subject: m.subject, text: m.text, html: m.html ?? null, attachments: m.attachments, read: m.read, sentBy: m.sent_by, messageId: m.message_id, createdAt: m.created_at });

  /// إدخال رسالة واردة: ربط بمحادثة قائمة (In-Reply-To/References ثم الموضوع والطرف خلال 30 يوماً) أو إنشاء جديدة
  async function ingest(msg) {
    const from = parseAddress(msg.from); if (!EMAIL_RE.test(from.email)) throw new Error("bad-from");
    const to = addrList(msg.to); const cc = addrList(msg.cc);
    const mailbox = await routeMailbox([...to, ...cc]);
    const messageId = str(msg.messageId, 300) || null; const inReplyTo = str(msg.inReplyTo, 300) || null;
    const refs = String(msg.references ?? "").split(/\s+/).map((x) => x.trim()).filter(Boolean).slice(-10);
    const subject = str(msg.subject, 300); const norm = normSubject(subject);
    const text = str(msg.text, 200000) || stripHtml(msg.html).slice(0, 200000);
    const html = msg.html ? String(msg.html).slice(0, 500000) : null;
    const attachments = Array.isArray(msg.attachments) ? msg.attachments.slice(0, 20).map((a) => ({ name: str(a?.name ?? a?.filename, 200), size: Number(a?.size) || 0, type: str(a?.type ?? a?.contentType ?? a?.content_type, 100), url: str(a?.url ?? a?.download_url, 1000) || null })) : [];
    const providerId = str(msg.providerId, 120) || null;
    if (providerId && (await pool.query("SELECT 1 FROM inbox_messages WHERE provider_id=$1", [providerId])).rowCount) return { duplicate: true };
    if (messageId && (await pool.query("SELECT 1 FROM inbox_messages WHERE message_id=$1 AND mailbox=$2", [messageId, mailbox])).rowCount) return { duplicate: true };
    let thread = null;
    const keys = [inReplyTo, ...refs].filter(Boolean);
    if (keys.length) thread = (await pool.query("SELECT t.* FROM inbox_messages m JOIN inbox_threads t ON t.id=m.thread_id WHERE m.message_id = ANY($1) AND t.mailbox=$2 ORDER BY m.created_at DESC LIMIT 1", [keys, mailbox])).rows[0] ?? null;
    if (!thread && norm) thread = (await pool.query("SELECT * FROM inbox_threads WHERE mailbox=$1 AND norm_subject=$2 AND counterpart=$3 AND last_at > now() - interval '30 days' ORDER BY last_at DESC LIMIT 1", [mailbox, norm, from.email])).rows[0] ?? null;
    const now = new Date().toISOString();
    const snippet = text.replace(/\s+/g, " ").slice(0, 160);
    if (!thread) {
      const id = crypto.randomUUID();
      const participants = [...new Set([from.email, ...to.map((a) => a.email), ...cc.map((a) => a.email)])];
      await pool.query("INSERT INTO inbox_threads(id,mailbox,subject,norm_subject,snippet,counterpart,counterpart_name,participants,last_at,last_direction,unread,message_count) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,'in',1,1)", [id, mailbox, subject || "(بلا موضوع)", norm, snippet, from.email, from.name, JSON.stringify(participants), now]);
      thread = { id, mailbox };
    } else {
      await pool.query("UPDATE inbox_threads SET snippet=$2, last_at=$3, last_direction='in', unread=unread+1, message_count=message_count+1, archived=false, counterpart_name=CASE WHEN $4<>'' THEN $4 ELSE counterpart_name END WHERE id=$1", [thread.id, snippet, now, from.name]);
    }
    const mid = crypto.randomUUID();
    await pool.query("INSERT INTO inbox_messages(id,thread_id,mailbox,direction,message_id,in_reply_to,provider_id,from_addr,from_name,to_addrs,cc_addrs,subject,text,html,attachments,read,created_at) VALUES($1,$2,$3,'in',$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,false,$15)",
      [mid, thread.id, mailbox, messageId, inReplyTo, providerId, from.email, from.name, JSON.stringify(to), JSON.stringify(cc), subject, text, html, JSON.stringify(attachments), now]);
    await saveSettings({ ...settings, lastReceivedAt: now, received: (settings.received ?? 0) + 1 });
    const t = (await pool.query("SELECT assigned_to FROM inbox_threads WHERE id=$1", [thread.id])).rows[0];
    const targets = t?.assigned_to ? [t.assigned_to] : await ownersOf(mailbox);
    await notify(targets, { kind: "inbox_message", title: `بريد جديد إلى ${mailbox}@${domainName()}`, body: `${from.name || from.email}: ${subject || snippet}`.slice(0, 140), data: { threadId: thread.id, mailbox, section: "inbox" } });
    return { threadId: thread.id, messageId: mid, mailbox };
  }
  globalThis.naslifeInboxIngest = ingest;

  // ---- Webhooks (بلا مصادقة مستخدم؛ التحقق بالتوقيع أو الرمز)
  app.addContentTypeParser("application/json", { parseAs: "string" }, (req, body, done) => { try { done(null, body ? JSON.parse(body) : {}); } catch (e) { e.statusCode = 400; done(e); } });
  app.addHook("preParsing", async (req, reply, payload) => { if (req.url.startsWith("/inbox/webhook/")) { const chunks = []; for await (const c of payload) chunks.push(c); req.rawBody = Buffer.concat(chunks).toString("utf8"); const { Readable } = await import("node:stream"); return Readable.from([req.rawBody]); } return payload; });
  /// جلب محتوى رسالة Resend المستلمة بعد إشعار الـ webhook
  async function fetchResendEmail(emailId, apiKey) {
    for (const path of [`/emails/receiving/${encodeURIComponent(emailId)}`, `/emails/${encodeURIComponent(emailId)}`]) {
      try {
        const r = await fetchFn()(`https://api.resend.com${path}`, { headers: { authorization: `Bearer ${apiKey}` } });
        if (r.ok) return JSON.parse(await r.text());
      } catch { /* التالي */ }
    }
    return null;
  }
  app.post("/inbox/webhook/resend", async (req, reply) => {
    if (settings.webhookSecret && !verifySvix(settings.webhookSecret, req.headers, req.rawBody ?? "")) { await saveSettings({ ...settings, rejected: (settings.rejected ?? 0) + 1 }); return bad(reply, 401, "bad-signature"); }
    if (!settings.webhookSecret && !(settings.token && req.query?.token === settings.token)) return bad(reply, 401, "no-secret");
    const ev = req.body ?? {}; const type = String(ev.type ?? "");
    if (type !== "email.received") return { ok: true, ignored: type };
    const d = ev.data ?? {};
    const apiKey = opts.apiKey ?? globalThis.naslifeMailApiKey?.() ?? null;
    const full = d.email_id && apiKey ? await fetchResendEmail(d.email_id, apiKey) : null;
    const src = full ?? d;
    const r = await ingest({ providerId: d.email_id ?? null, from: src.from ?? d.from, to: src.to ?? d.to, cc: src.cc ?? d.cc, subject: src.subject ?? d.subject, text: src.text ?? "", html: src.html ?? null, messageId: src.message_id ?? src.headers?.["message-id"] ?? d.message_id, inReplyTo: src.headers?.["in-reply-to"] ?? src.in_reply_to, references: src.headers?.references ?? "", attachments: src.attachments ?? [] });
    return { ok: true, ...r, fetched: !!full };
  });
  app.post("/inbox/webhook/generic", async (req, reply) => {
    const token = req.headers["x-inbox-token"] ?? req.query?.token;
    if (!settings.token || token !== settings.token) return bad(reply, 401, "bad-token");
    const b = req.body ?? {};
    if (!b.from || !(b.to || b.recipient)) return bad(reply, 400, "bad-message");
    try { return { ok: true, ...(await ingest({ ...b, to: b.to ?? b.recipient, messageId: b.messageId ?? b["message-id"], inReplyTo: b.inReplyTo ?? b["in-reply-to"] })) }; }
    catch (e) { return bad(reply, 400, String(e.message)); }
  });

  // ---- واجهة اللوحة
  async function guard(req, reply, perm = "inbox.view") {
    const uid = await auth(req); if (!uid) { bad(reply, 401, "auth"); return null; }
    const info = await teamInfo(uid);
    if (!has(info, perm)) { bad(reply, 403, "forbidden", { need: perm }); return null; }
    req.teamInfo = info; return uid;
  }
  app.get("/adminapi/inbox/mailboxes", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    const boxes = await mailboxes(uid);
    const cfg = mailCfg();
    return { mailboxes: boxes, domain: domainName(), domainVerified: !!cfg?.domain?.verified, canReply: has(req.teamInfo, "inbox.reply") || has(req.teamInfo, "inbox.manage"), canManage: has(req.teamInfo, "inbox.manage"), myMailbox: req.teamInfo.mailbox || "", receiving: { provider: settings.provider, configured: !!(settings.webhookSecret || settings.token), lastReceivedAt: settings.lastReceivedAt, received: settings.received ?? 0 } };
  });
  app.get("/adminapi/inbox", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    const boxes = await mailboxes(uid);
    const mailbox = str(req.query?.mailbox, 64) || boxes[0]?.alias || "";
    if (!mailbox || !boxes.some((b) => b.alias === mailbox)) return { threads: [], mailbox, folder: "inbox" };
    const folder = str(req.query?.folder, 10) || "inbox"; const term = str(req.query?.q, 80);
    const where = ["mailbox=$1"]; const params = [mailbox];
    if (folder === "inbox") where.push("NOT archived"); else if (folder === "archived") where.push("archived"); else if (folder === "starred") where.push("starred"); else if (folder === "unread") where.push("unread > 0 AND NOT archived");
    if (term) { params.push(`%${term}%`); where.push(`(subject ILIKE $${params.length} OR counterpart ILIKE $${params.length} OR counterpart_name ILIKE $${params.length} OR snippet ILIKE $${params.length})`); }
    const rows = (await pool.query(`SELECT * FROM inbox_threads WHERE ${where.join(" AND ")} ORDER BY last_at DESC LIMIT 200`, params)).rows;
    const amap = await people(rows.map((r) => r.assigned_to));
    return { threads: rows.map((t) => threadOut(t, amap)), mailbox, folder };
  });
  app.get("/adminapi/inbox/threads/:id", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    const id = str(req.params.id, 36); if (!UUID_RE.test(id)) return bad(reply, 404, "not-found");
    const t = (await pool.query("SELECT * FROM inbox_threads WHERE id=$1", [id])).rows[0]; if (!t) return bad(reply, 404, "not-found");
    if (!(await canSee(uid, t.mailbox))) return bad(reply, 403, "forbidden");
    const msgs = (await pool.query("SELECT * FROM inbox_messages WHERE thread_id=$1 ORDER BY created_at", [id])).rows;
    if (t.unread > 0 && req.query?.markRead !== "0") { await pool.query("UPDATE inbox_threads SET unread=0 WHERE id=$1", [id]); await pool.query("UPDATE inbox_messages SET read=true WHERE thread_id=$1", [id]); t.unread = 0; }
    const amap = await people([t.assigned_to, ...msgs.map((m) => m.sent_by)]);
    return { ...threadOut(t, amap), address: `${t.mailbox}@${domainName()}`, messageList: msgs.map((m) => ({ ...messageOut(m), sentByName: m.sent_by ? (amap.get(m.sent_by)?.nickname ?? "") : "" })) };
  });
  app.patch("/adminapi/inbox/threads/:id", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    const id = str(req.params.id, 36); if (!UUID_RE.test(id)) return bad(reply, 404, "not-found");
    const t = (await pool.query("SELECT * FROM inbox_threads WHERE id=$1", [id])).rows[0]; if (!t) return bad(reply, 404, "not-found");
    if (!(await canSee(uid, t.mailbox))) return bad(reply, 403, "forbidden");
    const b = req.body ?? {}; const sets = []; const params = [id];
    const set = (col, val) => { params.push(val); sets.push(`${col}=$${params.length}`); };
    if (b.archived !== undefined) set("archived", b.archived === true);
    if (b.starred !== undefined) set("starred", b.starred === true);
    if (b.read !== undefined) { set("unread", b.read === true ? 0 : Math.max(1, t.unread)); if (b.read === true) await pool.query("UPDATE inbox_messages SET read=true WHERE thread_id=$1", [id]); }
    if (b.assignedTo !== undefined) {
      const a = b.assignedTo ? str(b.assignedTo, 12).toUpperCase() : null;
      if (a && (!ID_RE.test(a) || !(await teamInfo(a)))) return bad(reply, 400, "bad-assignee");
      set("assigned_to", a);
      if (a && a !== uid) await notify([a], { kind: "inbox_assigned", title: "أُسندت إليك محادثة بريد", body: t.subject, data: { threadId: id, mailbox: t.mailbox, section: "inbox" } });
    }
    if (!sets.length) return bad(reply, 400, "nothing-to-update");
    await pool.query(`UPDATE inbox_threads SET ${sets.join(", ")} WHERE id=$1`, params);
    const n = (await pool.query("SELECT * FROM inbox_threads WHERE id=$1", [id])).rows[0];
    return threadOut(n, await people([n.assigned_to]));
  });
  /// إرسال من صندوق: رد على محادثة أو رسالة جديدة
  async function sendFrom({ uid, mailbox, to, cc, subject, text, html, thread }) {
    const mail = globalThis.naslifeMail; if (!mail?.configured?.()) throw Object.assign(new Error("mail-not-configured"), { code: 400 });
    const info = await teamInfo(uid); const pmap = await people([uid]);
    const fromAddr = `${mailbox}@${domainName()}`; const fromName = mailbox === sharedLocal() ? (mailCfg()?.fromName || "ناس لايف") : `${pmap.get(uid)?.nickname || info?.title || "فريق"} · ناس لايف`;
    const messageId = `${crypto.randomUUID()}@${domainName()}`;
    const headers = { "Message-ID": `<${messageId}>` };
    let inReplyTo = null;
    if (thread) { const last = (await pool.query("SELECT message_id FROM inbox_messages WHERE thread_id=$1 AND direction='in' AND message_id IS NOT NULL ORDER BY created_at DESC LIMIT 1", [thread.id])).rows[0]; if (last?.message_id) { inReplyTo = last.message_id; headers["In-Reply-To"] = last.message_id.startsWith("<") ? last.message_id : `<${last.message_id}>`; headers.References = headers["In-Reply-To"]; } }
    const bodyHtml = html || `<div dir="auto" style="font-family:Segoe UI,Tahoma,sans-serif;white-space:pre-wrap;line-height:1.7">${String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;")}</div>`;
    const res = await mail.send({ to, subject, text, html: bodyHtml, tag: "inbox", from: fromAddr, fromName, replyTo: fromAddr, headers });
    const now = new Date().toISOString();
    let t = thread;
    if (!t) {
      const id = crypto.randomUUID(); const norm = normSubject(subject);
      await pool.query("INSERT INTO inbox_threads(id,mailbox,subject,norm_subject,snippet,counterpart,counterpart_name,participants,last_at,last_direction,unread,message_count) VALUES($1,$2,$3,$4,$5,$6,'',$7,$8,'out',0,0)", [id, mailbox, subject || "(بلا موضوع)", norm, text.replace(/\s+/g, " ").slice(0, 160), to, JSON.stringify([to, fromAddr, ...cc]), now]);
      t = { id, mailbox };
    }
    const mid = crypto.randomUUID();
    await pool.query("INSERT INTO inbox_messages(id,thread_id,mailbox,direction,message_id,in_reply_to,provider_id,from_addr,from_name,to_addrs,cc_addrs,subject,text,html,attachments,read,sent_by,created_at) VALUES($1,$2,$3,'out',$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,'[]',true,$14,$15)",
      [mid, t.id, mailbox, messageId, inReplyTo, res?.id ?? null, fromAddr, fromName, JSON.stringify([{ email: to, name: "" }]), JSON.stringify(cc.map((e) => ({ email: e, name: "" }))), subject, text, bodyHtml, uid, now]);
    await pool.query("UPDATE inbox_threads SET snippet=$2, last_at=$3, last_direction='out', message_count=message_count+1 WHERE id=$1", [t.id, text.replace(/\s+/g, " ").slice(0, 160), now]);
    return { threadId: t.id, messageId: mid };
  }
  app.post("/adminapi/inbox/threads/:id/reply", async (req, reply) => {
    const uid = await guard(req, reply, "inbox.reply"); if (!uid) return;
    const id = str(req.params.id, 36); if (!UUID_RE.test(id)) return bad(reply, 404, "not-found");
    const t = (await pool.query("SELECT * FROM inbox_threads WHERE id=$1", [id])).rows[0]; if (!t) return bad(reply, 404, "not-found");
    if (!(await canSee(uid, t.mailbox))) return bad(reply, 403, "forbidden");
    const text = str(req.body?.text, 50000); if (!text) return bad(reply, 400, "bad-text");
    const to = lower(req.body?.to) || t.counterpart; if (!EMAIL_RE.test(to)) return bad(reply, 400, "bad-recipient");
    const cc = addrList(req.body?.cc).map((a) => a.email);
    const subject = str(req.body?.subject, 300) || (/^(re|رد)\s*:/i.test(t.subject) ? t.subject : `Re: ${t.subject}`);
    try { return { ok: true, ...(await sendFrom({ uid, mailbox: t.mailbox, to, cc, subject, text, html: null, thread: t })) }; }
    catch (e) { return bad(reply, e.code ?? 502, e.code ? e.message : "send-failed", { detail: String(e.message).slice(0, 300) }); }
  });
  app.post("/adminapi/inbox/compose", async (req, reply) => {
    const uid = await guard(req, reply, "inbox.reply"); if (!uid) return;
    const boxes = await mailboxes(uid);
    const mailbox = str(req.body?.mailbox, 64) || boxes.find((b) => b.kind === "own")?.alias || boxes[0]?.alias;
    if (!mailbox || !boxes.some((b) => b.alias === mailbox)) return bad(reply, 403, "forbidden");
    const to = lower(req.body?.to); if (!EMAIL_RE.test(to)) return bad(reply, 400, "bad-recipient");
    const subject = str(req.body?.subject, 300); if (!subject) return bad(reply, 400, "bad-subject");
    const text = str(req.body?.text, 50000); if (!text) return bad(reply, 400, "bad-text");
    const cc = addrList(req.body?.cc).map((a) => a.email);
    try { return { ok: true, ...(await sendFrom({ uid, mailbox, to, cc, subject, text, html: null, thread: null })) }; }
    catch (e) { return bad(reply, e.code ?? 502, e.code ? e.message : "send-failed", { detail: String(e.message).slice(0, 300) }); }
  });
  // ---- إعدادات الاستقبال (inbox.manage)
  const publicOrigin = (req) => { const host = String(req.headers["x-forwarded-host"] ?? req.headers.host ?? "naslife.app").split(",")[0].trim(); const proto = String(req.headers["x-forwarded-proto"] ?? "https").split(",")[0].trim(); return `${proto}://${host}`; };
  const settingsOut = (req) => ({ provider: settings.provider, hasSecret: !!settings.webhookSecret, token: settings.token, resendUrl: `${publicOrigin(req)}/inbox/webhook/resend`, genericUrl: `${publicOrigin(req)}/inbox/webhook/generic?token=${settings.token}`, lastReceivedAt: settings.lastReceivedAt, received: settings.received ?? 0, rejected: settings.rejected ?? 0, domain: domainName(), shared: `${sharedLocal()}@${domainName()}` });
  app.get("/adminapi/inbox/settings", async (req, reply) => { if (!(await guard(req, reply, "inbox.manage"))) return; await load(); return settingsOut(req); });
  app.put("/adminapi/inbox/settings", async (req, reply) => {
    if (!(await guard(req, reply, "inbox.manage"))) return;
    const b = req.body ?? {}; const next = { ...settings };
    if (b.provider !== undefined) { if (!["resend", "generic"].includes(String(b.provider))) return bad(reply, 400, "bad-provider"); next.provider = String(b.provider); }
    if (b.webhookSecret !== undefined) next.webhookSecret = str(b.webhookSecret, 200);
    if (b.rotateToken === true) next.token = crypto.randomBytes(18).toString("base64url");
    await saveSettings(next);
    return settingsOut(req);
  });
}
