// أدوات المحادثات في Naslife: رفع الوسائط وتقديمها، وبيانات إضافية للرسائل (رد مقتبس، إعادة توجيه، مدة الصوت).
// التسجيل في src/index.js قبل app.listen:
//   await app.register((await import("./chat_tools.js")).default, { pool, auth });
// الملفات تُحفظ في CHAT_MEDIA_DIR (الافتراضي /opt/naslife/media/chat) بأسماء عشوائية غير قابلة للتخمين،
// وتُقدَّم بلا مصادقة حتى تعمل في <img> و<audio> مباشرة؛ الحد الأقصى 30 ميغابايت.
import crypto from "node:crypto";
import fs from "node:fs/promises";
import { createReadStream } from "node:fs";
import path from "node:path";

const MEDIA_DIR = process.env.CHAT_MEDIA_DIR || "/opt/naslife/media/chat";
const MAX_BYTES = Number(process.env.CHAT_MEDIA_MAX_BYTES) || 30 * 1024 * 1024;
const TYPES = {
  "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp", "image/gif": "gif",
  "video/mp4": "mp4", "video/webm": "webm", "video/quicktime": "mov",
  "audio/webm": "weba", "audio/ogg": "ogg", "audio/mp4": "m4a", "audio/mpeg": "mp3", "audio/wav": "wav", "audio/aac": "aac",
  "application/pdf": "pdf",
};
const EXT_TYPE = Object.fromEntries(Object.entries(TYPES).map(([t, e]) => [e, t]));
const kindOf = (type) => type.startsWith("image/") ? "image" : type.startsWith("video/") ? "video" : type.startsWith("audio/") ? "audio" : "file";
const NAME_RE = /^[a-z0-9]{6,16}-[a-f0-9]{24}\.[a-z0-9]{2,5}$/;
const UUID_RE = /^[0-9a-f-]{36}$/i;

// أي خطأ أثناء التهيئة يُسجَّل ولا يُسقط الخادم: تبقى المحادثات النصية تعمل ولو تعطلت أدوات الوسائط
export default async function chatTools(app, opts) {
  try {
    await setup(app, opts);
  } catch (e) {
    (app.log?.error ? app.log.error.bind(app.log) : console.error)(`chat_tools disabled: ${e?.stack || e}`);
  }
}

async function setup(app, opts) {
  const { pool, auth } = opts;
  if (!pool || !auth) throw new Error("chat_tools: pool and auth are required");
  await pool.query(`
    CREATE TABLE IF NOT EXISTS chat_message_meta (
      message_id TEXT PRIMARY KEY, user_id TEXT NOT NULL, reply_to TEXT, quote JSONB, forwarded_from TEXT, extra JSONB,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now());
  `);
  await fs.mkdir(MEDIA_DIR, { recursive: true });

  const unauthorized = (reply) => reply.code(401).send({ error: "auth" });
  const bad = (reply, code, error) => reply.code(code).send({ error });

  // محلل محتوى ثنائي داخل نطاق هذه الإضافة فقط؛ نتخطى أي نوع سجّله الخادم الأساسي مسبقاً (وإلا رمى Fastify خطأ FST_ERR_CTP_ALREADY_PRESENT)
  for (const type of [...Object.keys(TYPES), "application/octet-stream"]) {
    try {
      if (typeof app.hasContentTypeParser === "function" && app.hasContentTypeParser(type)) continue;
      app.addContentTypeParser(type, { parseAs: "buffer", bodyLimit: MAX_BYTES }, (req, body, done) => done(null, body));
    } catch (e) {
      (app.log?.warn ? app.log.warn.bind(app.log) : console.warn)(`chat_tools: parser for ${type} skipped: ${e?.message || e}`);
    }
  }

  // ---- الرفع: الجسم هو الملف نفسه، ونوعه من content-type (أو من امتداد x-file-name عند octet-stream)
  app.post("/chat/upload", { bodyLimit: MAX_BYTES, config: { rateLimit: false } }, async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    let ct = String(req.headers["content-type"] || "").split(";")[0].trim().toLowerCase();
    let ext = TYPES[ct];
    if (!ext && ct === "application/octet-stream") {
      const fromName = String(req.headers["x-file-name"] || "").toLowerCase().match(/\.([a-z0-9]{2,5})$/)?.[1];
      if (fromName && EXT_TYPE[fromName]) { ext = fromName; ct = EXT_TYPE[fromName]; }
    }
    if (!ext) return bad(reply, 415, "unsupported-type");
    if (!Buffer.isBuffer(req.body) || req.body.length === 0) return bad(reply, 400, "empty");
    const name = `${Date.now().toString(36)}-${crypto.randomBytes(12).toString("hex")}.${ext}`;
    await fs.writeFile(path.join(MEDIA_DIR, name), req.body);
    return { url: `/chat/media/${name}`, type: ct, kind: kindOf(ct), size: req.body.length };
  });

  // ---- التقديم مع دعم Range للصوت والفيديو
  app.get("/chat/media/:name", { config: { rateLimit: false } }, async (req, reply) => {
    const name = String(req.params.name);
    if (!NAME_RE.test(name)) return bad(reply, 404, "not-found");
    const file = path.join(MEDIA_DIR, name);
    let st;
    try { st = await fs.stat(file); } catch { return bad(reply, 404, "not-found"); }
    const type = EXT_TYPE[name.split(".").pop()] || "application/octet-stream";
    reply.header("content-type", type).header("accept-ranges", "bytes").header("cache-control", "public, max-age=31536000, immutable");
    const range = /^bytes=(\d*)-(\d*)$/.exec(String(req.headers.range || ""));
    if (range && (range[1] || range[2])) {
      const start = range[1] ? Number(range[1]) : Math.max(0, st.size - Number(range[2]));
      const end = range[1] && range[2] ? Math.min(Number(range[2]), st.size - 1) : st.size - 1;
      if (start >= st.size || start > end) return reply.code(416).header("content-range", `bytes */${st.size}`).send();
      reply.code(206).header("content-range", `bytes ${start}-${end}/${st.size}`).header("content-length", end - start + 1);
      return reply.send(createReadStream(file, { start, end }));
    }
    reply.header("content-length", st.size);
    return reply.send(createReadStream(file));
  });

  // ---- بيانات إضافية للرسائل: رد مقتبس، إعادة توجيه، مدة الصوت… تُحفظ بمعرّف الرسالة بعد إرسالها
  const metaOut = (r) => ({ replyTo: r.reply_to, quote: r.quote, forwardedFrom: r.forwarded_from, extra: r.extra });
  app.post("/chat/meta", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const b = req.body ?? {};
    const id = String(b.messageId ?? "");
    if (!id || id.length > 64) return bad(reply, 400, "bad-id");
    const replyTo = b.replyTo ? String(b.replyTo).slice(0, 64) : null;
    let quote = null;
    if (b.quote && typeof b.quote === "object") {
      quote = { id: String(b.quote.id ?? "").slice(0, 64), senderId: String(b.quote.senderId ?? "").slice(0, 16), senderName: String(b.quote.senderName ?? "").slice(0, 40),
        type: String(b.quote.type ?? "text").slice(0, 16), content: String(b.quote.content ?? "").slice(0, 300) };
    }
    const forwardedFrom = b.forwardedFrom ? String(b.forwardedFrom).slice(0, 40) : null;
    const extra = b.extra && typeof b.extra === "object" ? JSON.parse(JSON.stringify(b.extra).slice(0, 2000)) : null;
    await pool.query(
      `INSERT INTO chat_message_meta(message_id,user_id,reply_to,quote,forwarded_from,extra) VALUES($1,$2,$3,$4,$5,$6)
       ON CONFLICT (message_id) DO UPDATE SET reply_to=COALESCE(EXCLUDED.reply_to, chat_message_meta.reply_to),
         quote=COALESCE(EXCLUDED.quote, chat_message_meta.quote), forwarded_from=COALESCE(EXCLUDED.forwarded_from, chat_message_meta.forwarded_from),
         extra=COALESCE(EXCLUDED.extra, chat_message_meta.extra) WHERE chat_message_meta.user_id=$2`,
      [id, uid, replyTo, quote, forwardedFrom, extra]);
    return { ok: true };
  });
  app.get("/chat/meta", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const ids = String(req.query?.ids ?? "").split(",").map((s) => s.trim()).filter((s) => s && s.length <= 64).slice(0, 200);
    if (!ids.length) return {};
    const r = await pool.query("SELECT * FROM chat_message_meta WHERE message_id = ANY($1)", [ids]);
    return Object.fromEntries(r.rows.map((x) => [x.message_id, metaOut(x)]));
  });

  // ---- فحص: معلومات الوسائط لملف (يفيد التطبيق لمعرفة النوع قبل العرض)
  app.get("/chat/media-info/:name", async (req, reply) => {
    const name = String(req.params.name);
    if (!NAME_RE.test(name)) return bad(reply, 404, "not-found");
    try { const st = await fs.stat(path.join(MEDIA_DIR, name)); return { size: st.size, type: EXT_TYPE[name.split(".").pop()] || null }; }
    catch { return bad(reply, 404, "not-found"); }
  });
  void UUID_RE;
}
