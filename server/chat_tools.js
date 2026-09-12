// أدوات المحادثات في Naslife: رفع الوسائط وتقديمها، وبيانات إضافية للرسائل (رد مقتبس، إعادة توجيه، مدة الصوت).
// التسجيل في src/index.js قبل app.listen:
//   await app.register((await import("./chat_tools.js")).default, { pool, auth });
// الملفات تُحفظ في CHAT_MEDIA_DIR (الافتراضي /opt/naslife/media/chat) بأسماء عشوائية غير قابلة للتخمين،
// وتُقدَّم بلا مصادقة حتى تعمل في <img> و<audio> مباشرة؛ الحد الأقصى 30 ميغابايت.
import crypto from "node:crypto";
import fs from "node:fs/promises";
import { createReadStream, constants as fsConstants } from "node:fs";
import path from "node:path";

import os from "node:os";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
const execFileP = promisify(execFile);

// مجلد الوسائط: الأول القابل للكتابة. الخدمة قد تعمل بتقييد systemd (ProtectSystem/ProtectHome)، فنجرّب
// المجلدات التي يستخدمها الخادم الأساسي (من متغيرات بيئته) ثم مسارات معتادة ثم مجلد الحالة/المؤقت.
function mediaCandidates() {
  const out = [process.env.CHAT_MEDIA_DIR];
  for (const [k, v] of Object.entries(process.env)) {
    if (/MEDIA|UPLOAD|STORAGE|DATA_DIR|FILES_DIR|STATE_DIRECTORY|RUNTIME_DIRECTORY/i.test(k) && typeof v === "string" && v.startsWith("/")) out.push(path.join(v.split(":")[0], "chat"));
  }
  out.push("/opt/naslife/media/chat", "/opt/naslife/data/chat-media", "/opt/naslife/uploads/chat", "/var/lib/naslife/chat-media",
    path.join(process.cwd(), "media", "chat"), path.join(process.cwd(), "data", "chat-media"), path.join(os.homedir() || "/tmp", ".naslife-chat-media"),
    path.join(os.tmpdir(), "naslife-chat-media"));
  return [...new Set(out.filter(Boolean))];
}
const MAX_BYTES = Number(process.env.CHAT_MEDIA_MAX_BYTES) || 30 * 1024 * 1024;
const TYPES = {
  "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp", "image/gif": "gif",
  "video/mp4": "mp4", "video/webm": "webm", "video/quicktime": "mov", "video/3gpp": "3gp", "video/x-m4v": "m4v",
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
  let MEDIA_DIR = null;
  const mediaErrors = [];
  for (const dir of mediaCandidates()) {
    try {
      await fs.mkdir(dir, { recursive: true });
      await fs.access(dir, fsConstants.W_OK);
      MEDIA_DIR = dir; break;
    } catch (e) { mediaErrors.push(`${dir}: ${e?.code || e?.message || e}`); }
  }
  const logger = app.log?.info ? app.log.info.bind(app.log) : console.log;
  // ffmpeg (إن وُجد) يحوّل التسجيلات الصوتية إلى AAC/m4a والفيديو إلى MP4 حتى تُشغَّل على iPhone وAndroid معاً
  let ffmpeg = false;
  try { await execFileP("ffmpeg", ["-version"], { timeout: 5000 }); ffmpeg = true; } catch {}
  logger(`chat_tools: ffmpeg ${ffmpeg ? "available" : "not found (audio kept as recorded)"}`);
  // ffprobe: ترميزا الفيديو والصوت في الملف
  async function probeStreams(file) {
    const { stdout } = await execFileP("ffprobe", ["-v", "error", "-show_entries", "stream=codec_type,codec_name", "-of", "json", file], { timeout: 20000 });
    const streams = JSON.parse(stdout || "{}").streams ?? [];
    return { video: streams.find((x) => x.codec_type === "video"), audio: streams.find((x) => x.codec_type === "audio") };
  }
  // الفيديو يُوحَّد إلى MP4 (H.264/AAC وmoov في المقدمة): iPhone يرسل .mov وAndroid يرسل .webm ولا يشغّل أيٌّ منهما ملفات الآخر.
  // H.264/AAC يُعاد تغليفه فقط (سريع، مع إسقاط مسارات البيانات الوصفية)، وغيره (HEVC/VP8/VP9…) يُعاد ترميزه بحد أقصى 720 بكسل.
  async function normalizeVideo(inFile, ext) {
    const { video, audio } = await probeStreams(inFile);
    if (!video) throw new Error("no video stream");
    const copyOk = video.codec_name === "h264" && (!audio || audio.codec_name === "aac");
    if (copyOk && ext === "mp4") return inFile;
    const out = path.join(path.dirname(inFile), `${Date.now().toString(36)}-${crypto.randomBytes(12).toString("hex")}.mp4`);
    const args = ["-y", "-hide_banner", "-loglevel", "error", "-i", inFile, "-map", "0:v:0", "-map", "0:a:0?", "-sn", "-dn"];
    if (copyOk) args.push("-c", "copy");
    else args.push("-c:v", "libx264", "-preset", "veryfast", "-crf", "26", "-pix_fmt", "yuv420p", "-vf", "scale=min(720\\,iw):-2,scale=trunc(iw/2)*2:trunc(ih/2)*2", "-c:a", "aac", "-b:a", "96k");
    args.push("-movflags", "+faststart", out);
    try { await execFileP("ffmpeg", args, { timeout: 150000 }); }
    catch (e) { await fs.unlink(out).catch(() => {}); throw e; }
    await fs.unlink(inFile).catch(() => {});
    return out;
  }
  async function transcodeAudio(inFile) {
    const out = inFile.replace(/\.[a-z0-9]+$/, ".m4a");
    await execFileP("ffmpeg", ["-y", "-hide_banner", "-loglevel", "error", "-i", inFile, "-vn", "-ac", "1", "-c:a", "aac", "-b:a", "64k", "-movflags", "+faststart", out], { timeout: 120000 });
    await fs.unlink(inFile).catch(() => {});
    return out;
  }
  logger(MEDIA_DIR ? `chat_tools: media dir ${MEDIA_DIR}` : `chat_tools: NO writable media dir (${mediaErrors.join("; ")})`);

  const unauthorized = (reply) => reply.code(401).send({ error: "auth" });
  const bad = (reply, code, error) => reply.code(code).send({ error });

  // حالة الإضافة (بلا مصادقة وبلا مسارات): يفيد التحقق من النشر
  app.get("/chat/status", async () => ({ ok: true, media: !!MEDIA_DIR, durable: !!MEDIA_DIR && !MEDIA_DIR.startsWith(os.tmpdir()), transcode: ffmpeg, maxBytes: MAX_BYTES }));

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
    if (!MEDIA_DIR) return bad(reply, 503, "media-storage-unavailable");
    if (!ext) return bad(reply, 415, "unsupported-type");
    if (!Buffer.isBuffer(req.body) || req.body.length === 0) return bad(reply, 400, "empty");
    let name = `${Date.now().toString(36)}-${crypto.randomBytes(12).toString("hex")}.${ext}`;
    let file = path.join(MEDIA_DIR, name);
    await fs.writeFile(file, req.body);
    let size = req.body.length;
    if (ffmpeg && ct.startsWith("audio/") && ext !== "m4a" && ext !== "mp3") {
      try {
        file = await transcodeAudio(file);
        name = path.basename(file); ct = "audio/mp4"; size = (await fs.stat(file)).size;
      } catch (e) { logger(`chat_tools: transcode failed, keeping original: ${e?.message || e}`); }
    } else if (ffmpeg && ct.startsWith("video/")) {
      try {
        file = await normalizeVideo(file, ext);
        name = path.basename(file); ct = "video/mp4"; size = (await fs.stat(file)).size;
      } catch (e) { logger(`chat_tools: video normalize failed, keeping original: ${e?.message || e}`); }
    }
    return { url: `/chat/media/${name}`, type: ct, kind: kindOf(ct), size };
  });

  // ---- التقديم مع دعم Range للصوت والفيديو
  app.get("/chat/media/:name", { config: { rateLimit: false } }, async (req, reply) => {
    const name = String(req.params.name);
    if (!MEDIA_DIR || !NAME_RE.test(name)) return bad(reply, 404, "not-found");
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
    if (!MEDIA_DIR || !NAME_RE.test(name)) return bad(reply, 404, "not-found");
    try { const st = await fs.stat(path.join(MEDIA_DIR, name)); return { size: st.size, type: EXT_TYPE[name.split(".").pop()] || null }; }
    catch { return bad(reply, 404, "not-found"); }
  });
  void UUID_RE;
}
