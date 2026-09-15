// خدمة البريد الإلكتروني لناس لايف: إعدادات المزوّد تُحفظ في قاعدة البيانات وتُدار من لوحة الإدارة (بلا SSH)،
// وإرسال عبر SMTP (عميل مضمّن بلا حزم خارجية: TLS مباشر على 465 أو STARTTLS على 587، AUTH PLAIN/LOGIN) أو عبر
// واجهات HTTP لمزوّدي البريد (Resend، Brevo، SendGrid). كل إرسال يُسجَّل في mail_log.
// المسارات: GET/PUT /adminapi/mail (الإعدادات، الأسرار مقنّعة)، POST /adminapi/mail/test، GET /adminapi/mail/log،
// GET /mail/status (عام: هل البريد مفعّل). ويكشف globalThis.naslifeMail = { configured(), send({to, subject, text, html, tag}) }
// لبقية الإضافات (تحقق بريد الدخول مثلاً).
// التسجيل: await app.register((await import("./mail.js")).default, { pool, auth });
import crypto from "node:crypto";
import net from "node:net";
import tls from "node:tls";

const PROVIDERS = new Set(["off", "smtp", "resend", "brevo", "sendgrid"]);
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const MASK = "••••••••";
const DEFAULTS = { provider: "off", host: "", port: 587, secure: false, user: "", pass: "", apiKey: "", from: "", fromName: "ناس لايف", replyTo: "" };

const b64 = (s) => Buffer.from(String(s), "utf8").toString("base64");
/// عنوان بريد مع اسم عرض مرمّز (RFC 2047) للأحرف العربية.
const addr = (email, name) => (name ? `=?UTF-8?B?${b64(name)}?= <${email}>` : email);
const encHeader = (s) => (/^[\x20-\x7e]*$/.test(String(s)) ? String(s) : `=?UTF-8?B?${b64(s)}?=`);
/// تقسيم base64 إلى أسطر 76 حرفاً (حد الرسائل).
const b64Lines = (s) => b64(s).replace(/(.{76})/g, "$1\r\n");

/// يبني رسالة MIME كاملة (نص + HTML) بترميز base64 للأجزاء.
export function buildMime({ from, fromName, to, subject, text, html, replyTo, messageId }) {
  const boundary = "nl-" + crypto.randomBytes(9).toString("hex");
  const lines = [
    `From: ${addr(from, fromName)}`,
    `To: ${to}`,
    `Subject: ${encHeader(subject)}`,
    replyTo ? `Reply-To: ${replyTo}` : null,
    `Date: ${new Date().toUTCString()}`,
    `Message-ID: <${messageId}>`,
    "MIME-Version: 1.0",
    `Content-Type: multipart/alternative; boundary="${boundary}"`,
    "",
    `--${boundary}`,
    "Content-Type: text/plain; charset=UTF-8",
    "Content-Transfer-Encoding: base64",
    "",
    b64Lines(text || ""),
    `--${boundary}`,
    "Content-Type: text/html; charset=UTF-8",
    "Content-Transfer-Encoding: base64",
    "",
    b64Lines(html || `<pre>${String(text || "")}</pre>`),
    `--${boundary}--`,
    "",
  ].filter((l) => l !== null);
  return lines.join("\r\n");
}

/// عميل SMTP صغير: يفتح الاتصال، يقرأ الردود متعددة الأسطر، ويرسل الأوامر بالتسلسل.
export async function smtpSend({ host, port = 587, secure = false, user, pass, from, to, mime, timeoutMs = 20000, log = () => {} }) {
  let socket = secure ? tls.connect({ host, port, servername: host }) : net.connect({ host, port });
  let buffer = "";
  const waiters = [];
  let pending = [];
  /// يقرأ الردود سطراً سطراً: تنتهي الاستجابة عند سطر يبدأ برمز ثلاثي الأرقام تليه مسافة (وليس شرطة).
  const feed = (chunk) => {
    buffer += chunk.toString("utf8");
    for (;;) {
      const nl = buffer.indexOf("\n");
      if (nl < 0) break;
      const line = buffer.slice(0, nl).replace(/\r$/, "");
      buffer = buffer.slice(nl + 1);
      pending.push(line);
      const m = line.match(/^(\d{3})(?: |$)/);
      if (!m) continue;
      const text = pending.join("\n"); pending = [];
      const w = waiters.shift();
      if (w) w.resolve({ code: Number(m[1]), text });
    }
  };
  const attach = (s) => { s.on("data", feed); s.on("error", (e) => { const w = waiters.shift(); if (w) w.reject(e); }); s.on("close", () => { const w = waiters.shift(); if (w) w.reject(new Error("smtp: connection closed")); }); };
  attach(socket);
  const read = () => new Promise((resolve, reject) => { const t = setTimeout(() => reject(new Error("smtp: timeout")), timeoutMs); waiters.push({ resolve: (v) => { clearTimeout(t); resolve(v); }, reject: (e) => { clearTimeout(t); reject(e); } }); });
  const send = async (cmd, expect = [250]) => {
    log(`> ${cmd.startsWith("AUTH") ? "AUTH ***" : cmd.slice(0, 80)}`);
    socket.write(cmd + "\r\n");
    const r = await read();
    log(`< ${r.text.slice(0, 120)}`);
    if (!expect.includes(r.code)) throw new Error(`smtp: ${cmd.split(" ")[0]} failed: ${r.text.split("\n").pop()}`);
    return r;
  };
  try {
    await new Promise((resolve, reject) => { socket.once("error", reject); socket.once(secure ? "secureConnect" : "connect", resolve); });
    const greet = await read();
    if (greet.code !== 220) throw new Error(`smtp: bad greeting ${greet.text}`);
    let ehlo = await send(`EHLO naslife.app`);
    if (!secure && /STARTTLS/i.test(ehlo.text)) {
      await send("STARTTLS", [220]);
      socket.removeAllListeners("data");
      socket = await new Promise((resolve, reject) => { const t = tls.connect({ socket, servername: host }, () => resolve(t)); t.once("error", reject); });
      attach(socket);
      ehlo = await send(`EHLO naslife.app`);
    }
    if (user) {
      if (/AUTH[^\n]*PLAIN/i.test(ehlo.text)) await send(`AUTH PLAIN ${b64(`\u0000${user}\u0000${pass}`)}`, [235]);
      else { await send("AUTH LOGIN", [334]); await send(b64(user), [334]); await send(b64(pass), [235]); }
    }
    await send(`MAIL FROM:<${from}>`);
    await send(`RCPT TO:<${to}>`, [250, 251]);
    await send("DATA", [354]);
    const body = mime.replace(/\r?\n/g, "\r\n").replace(/^\./gm, "..");
    socket.write(body + (body.endsWith("\r\n") ? "" : "\r\n") + ".\r\n");
    const r = await read();
    if (r.code !== 250) throw new Error(`smtp: message rejected: ${r.text}`);
    try { socket.write("QUIT\r\n"); } catch { /* ignore */ }
    return { id: (r.text.match(/id=([^\s]+)/i) || [])[1] ?? null };
  } finally {
    try { socket.destroy(); } catch { /* ignore */ }
  }
}

/// إرسال عبر واجهات HTTP للمزوّدين.
export async function httpSend(provider, { apiKey, from, fromName, replyTo, to, subject, text, html }, fetchFn = globalThis.fetch) {
  let url, headers, body;
  if (provider === "resend") {
    url = "https://api.resend.com/emails"; headers = { authorization: `Bearer ${apiKey}`, "content-type": "application/json" };
    body = { from: fromName ? `${fromName} <${from}>` : from, to: [to], subject, text, html, ...(replyTo ? { reply_to: replyTo } : {}) };
  } else if (provider === "brevo") {
    url = "https://api.brevo.com/v3/smtp/email"; headers = { "api-key": apiKey, "content-type": "application/json" };
    body = { sender: { email: from, name: fromName || undefined }, to: [{ email: to }], subject, textContent: text, htmlContent: html, ...(replyTo ? { replyTo: { email: replyTo } } : {}) };
  } else if (provider === "sendgrid") {
    url = "https://api.sendgrid.com/v3/mail/send"; headers = { authorization: `Bearer ${apiKey}`, "content-type": "application/json" };
    body = { personalizations: [{ to: [{ email: to }] }], from: { email: from, name: fromName || undefined }, subject, content: [{ type: "text/plain", value: text || " " }, { type: "text/html", value: html || `<pre>${text || ""}</pre>` }], ...(replyTo ? { reply_to: { email: replyTo } } : {}) };
  } else throw new Error("mail: unknown provider");
  const r = await fetchFn(url, { method: "POST", headers, body: JSON.stringify(body) });
  const t = await r.text();
  if (!r.ok) throw new Error(`mail: ${provider} ${r.status}: ${t.slice(0, 200)}`);
  let id = null; try { const j = JSON.parse(t); id = j.id ?? j.messageId ?? null; } catch { /* sendgrid returns empty */ }
  return { id: id ?? r.headers?.get?.("x-message-id") ?? null };
}

/// قالب رسالة ناس لايف: ترويسة بلون العلامة ونص عربي من اليمين.
export function template({ title, lines = [], code = null, footer = "هذه رسالة آلية من ناس لايف." }) {
  const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
  const html = `<!doctype html><html lang="ar" dir="rtl"><body style="margin:0;background:#F2F2F7;font-family:Tahoma,Arial,sans-serif;color:#111">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:24px 12px">
<table role="presentation" width="520" style="max-width:520px;background:#fff;border-radius:16px;overflow:hidden">
<tr><td style="background:#0A6E78;color:#fff;padding:16px 22px;font-size:20px;font-weight:bold">ناس لايف</td></tr>
<tr><td style="padding:22px;font-size:16px;line-height:1.8;text-align:right">
<div style="font-size:19px;font-weight:bold;margin-bottom:8px">${esc(title)}</div>
${lines.map((l) => `<p style="margin:0 0 10px">${esc(l)}</p>`).join("")}
${code ? `<div style="margin:18px 0;text-align:center"><span style="display:inline-block;letter-spacing:8px;font-size:30px;font-weight:bold;background:#E0F3F4;color:#0A6E78;padding:10px 18px;border-radius:12px;direction:ltr">${esc(code)}</span></div>` : ""}
</td></tr>
<tr><td style="padding:12px 22px 20px;color:#6B7280;font-size:12px;text-align:right">${esc(footer)}</td></tr>
</table></td></tr></table></body></html>`;
  const text = [title, "", ...lines, code ? `\n${code}\n` : "", footer].join("\n");
  return { html, text };
}

export default async function mail(app, opts = {}) {
  const pool = opts.pool ?? globalThis.naslifePool ?? null;
  const auth = opts.auth ?? globalThis.naslifeAuth ?? null;
  if (!pool) throw new Error("mail: pool is required");
  await pool.query(`CREATE TABLE IF NOT EXISTS mail_settings (id INT PRIMARY KEY DEFAULT 1, data JSONB NOT NULL DEFAULT '{}', updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE TABLE IF NOT EXISTS mail_log (id UUID PRIMARY KEY, recipient TEXT NOT NULL, subject TEXT NOT NULL, tag TEXT, status TEXT NOT NULL, error TEXT, provider TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE INDEX IF NOT EXISTS mail_log_time ON mail_log(created_at DESC)`);
  let settings = { ...DEFAULTS };
  async function load() {
    try { const r = await pool.query("SELECT data FROM mail_settings WHERE id=1"); settings = { ...DEFAULTS, ...(r.rows[0]?.data ?? {}) }; } catch { /* ignore */ }
    return settings;
  }
  await load();
  const configured = () => settings.provider !== "off" && EMAIL_RE.test(settings.from) && (settings.provider === "smtp" ? !!settings.host : !!settings.apiKey);
  const masked = () => ({ ...settings, pass: settings.pass ? MASK : "", apiKey: settings.apiKey ? MASK : "", hasPass: !!settings.pass, hasApiKey: !!settings.apiKey, configured: configured() });

  async function send({ to, subject, text, html, tag = null }) {
    const rcpt = String(to ?? "").trim().toLowerCase();
    if (!EMAIL_RE.test(rcpt)) throw new Error("mail: bad recipient");
    if (!configured()) throw new Error("mail: not configured");
    const id = crypto.randomUUID();
    const p = settings.provider;
    try {
      let res;
      if (p === "smtp") {
        const mime = buildMime({ from: settings.from, fromName: settings.fromName, to: rcpt, subject, text, html, replyTo: settings.replyTo, messageId: `${id}@naslife.app` });
        res = await smtpSend({ host: settings.host, port: Number(settings.port) || (settings.secure ? 465 : 587), secure: settings.secure === true, user: settings.user, pass: settings.pass, from: settings.from, to: rcpt, mime });
      } else {
        res = await httpSend(p, { apiKey: settings.apiKey, from: settings.from, fromName: settings.fromName, replyTo: settings.replyTo, to: rcpt, subject, text, html });
      }
      await pool.query("INSERT INTO mail_log(id, recipient, subject, tag, status, provider) VALUES($1,$2,$3,$4,'sent',$5)", [id, rcpt, subject, tag, p]).catch(() => {});
      return { ok: true, id: res?.id ?? id };
    } catch (e) {
      const msg = String(e?.message ?? e).slice(0, 300);
      await pool.query("INSERT INTO mail_log(id, recipient, subject, tag, status, error, provider) VALUES($1,$2,$3,$4,'failed',$5,$6)", [id, rcpt, subject, tag, msg, p]).catch(() => {});
      throw new Error(msg);
    }
  }
  globalThis.naslifeMail = { configured, send, template, settings: () => ({ provider: settings.provider, from: settings.from, fromName: settings.fromName }) };

  const bad = (reply, code, error, extra = {}) => reply.code(code).send({ error, ...extra });
  async function guard(req, reply) {
    if (!auth) { bad(reply, 503, "auth-unavailable"); return null; }
    const uid = await auth(req); if (!uid) { bad(reply, 401, "auth"); return null; }
    const isAdmin = globalThis.naslifeIsAdmin; if (!isAdmin || !(await isAdmin(uid))) { bad(reply, 403, "admin-only"); return null; }
    return uid;
  }
  const audit = async (adminId, action, details = {}) => { try { await pool.query("INSERT INTO admin_audit(id,admin_id,action,target,details) VALUES($1,$2,$3,'mail',$4)", [crypto.randomUUID(), adminId, action, JSON.stringify(details)]); } catch { /* ignore */ } };

  app.get("/mail/status", async () => ({ ok: true, configured: configured(), provider: settings.provider }));
  app.get("/adminapi/mail", async (req, reply) => { if (!(await guard(req, reply))) return; await load(); return masked(); });
  app.put("/adminapi/mail", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    const b = req.body && typeof req.body === "object" ? req.body : {};
    const next = { ...settings };
    if (b.provider !== undefined) { if (!PROVIDERS.has(String(b.provider))) return bad(reply, 400, "bad-provider"); next.provider = String(b.provider); }
    for (const k of ["host", "user", "from", "fromName", "replyTo"]) if (b[k] !== undefined) next[k] = String(b[k] ?? "").trim().slice(0, 200);
    if (b.port !== undefined) { const n = Number(b.port); if (!Number.isInteger(n) || n < 1 || n > 65535) return bad(reply, 400, "bad-port"); next.port = n; }
    if (b.secure !== undefined) next.secure = b.secure === true;
    for (const k of ["pass", "apiKey"]) if (b[k] !== undefined && b[k] !== MASK) next[k] = String(b[k] ?? "");
    if (next.from && !EMAIL_RE.test(next.from)) return bad(reply, 400, "bad-from");
    if (next.replyTo && !EMAIL_RE.test(next.replyTo)) return bad(reply, 400, "bad-reply-to");
    await pool.query("INSERT INTO mail_settings(id, data, updated_at) VALUES(1,$1,now()) ON CONFLICT (id) DO UPDATE SET data=EXCLUDED.data, updated_at=now()", [JSON.stringify(next)]);
    settings = next;
    await audit(uid, "mail.settings", { provider: next.provider, from: next.from, host: next.host });
    return masked();
  });
  app.post("/adminapi/mail/test", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    const to = String(req.body?.to ?? "").trim().toLowerCase();
    if (!EMAIL_RE.test(to)) return bad(reply, 400, "bad-recipient");
    if (!configured()) return bad(reply, 400, "not-configured");
    const t = template({ title: "رسالة تجريبية من ناس لايف", lines: ["إن وصلتك هذه الرسالة فخدمة البريد تعمل بشكل صحيح.", `المزوّد: ${settings.provider} · المرسل: ${settings.from}`] });
    try {
      const r = await send({ to, subject: "تجربة البريد · ناس لايف", ...t, tag: "test" });
      await audit(uid, "mail.test", { to, ok: true });
      return { ok: true, id: r.id };
    } catch (e) {
      await audit(uid, "mail.test", { to, ok: false, error: String(e.message) });
      return bad(reply, 502, "send-failed", { detail: String(e.message).slice(0, 300) });
    }
  });
  app.get("/adminapi/mail/log", async (req, reply) => {
    if (!(await guard(req, reply))) return;
    const limit = Math.min(200, Math.max(1, Number(req.query?.limit) || 50));
    const rows = (await pool.query("SELECT id, recipient, subject, tag, status, error, provider, created_at FROM mail_log ORDER BY created_at DESC LIMIT $1", [limit])).rows;
    const counts = (await pool.query("SELECT count(*) FILTER (WHERE status='sent')::int AS sent, count(*) FILTER (WHERE status='failed')::int AS failed FROM mail_log WHERE created_at > now() - interval '30 days'")).rows[0];
    return { log: rows.map((r) => ({ id: r.id, to: r.recipient, subject: r.subject, tag: r.tag, status: r.status, error: r.error, provider: r.provider, at: r.created_at })), sent30d: counts.sent, failed30d: counts.failed };
  });
}
