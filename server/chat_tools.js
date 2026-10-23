// أدوات المحادثات في Naslife: رفع الوسائط وتقديمها، وموجة الصوت (48 قيمة مع الرفع وGET /chat/peaks)، وبيانات إضافية للرسائل (رد مقتبس، إعادة توجيه، مدة الصوت).
// الفيديو المرفوع «خفيف» (videoArgs: 720p وسقف 2 ميغابت/ث و30 إطاراً)، وGET /chat/vpreview/:name معاينة صامتة 360p لست ثوانٍ (docs/moments.md).
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

// ---- «الفيديو الخفيف» (قرار المالك لعارض اللحظات): حدود الفيديو بعد الرفع. ما يتجاوز 720p (الضلع الأقصر فوق 720 أو الأطول
// فوق 1280، أياً كان الاتجاه) أو معدّله فوق 3 ميغابت/ث أو ليس H.264/AAC يُعاد ترميزه بسقف 2 ميغابت/ث، وغيره يبقى بلا ترميز.
export const LIGHT_VIDEO = Object.freeze({ maxShort: 720, maxLong: 1280, maxBitrate: 3_000_000, crf: 26, maxrate: "2M", bufsize: "4M", maxFps: 30, audio: "96k" });
// معاينة الشبكة («اللحظات» وعارضها): أول 6 ثوانٍ بلا صوت بدقة 360p تُعاد كحلقة
export const VIDEO_PREVIEW = Object.freeze({ seconds: 6, maxShort: 360, maxLong: 640, crf: 30, maxFps: 30 });
const fpsOf = (s) => {
  const [a, b] = String(s ?? "").split("/").map(Number);
  const v = b ? a / b : a;
  return Number.isFinite(v) && v > 0 && v < 1000 ? v : null;
};
// يحجّم داخل صندوق بحسب الاتجاه (أفقي 1280×720، عمودي 720×1280) بلا تكبير، ثم أبعاد زوجية يطلبها H.264.
// الاتجاه من الإطار بعد التدوير التلقائي (iw/ih داخل المرشّح) لا من أبعاد الملف، فلقطة الآيفون العمودية لا تصغر خطأً.
const boxScale = (short, long) => [
  `scale=w='if(gte(iw,ih),min(${long},iw),min(${short},iw))':h='if(gte(iw,ih),min(${short},ih),min(${long},ih))':force_original_aspect_ratio=decrease`,
  "scale=trunc(iw/2)*2:trunc(ih/2)*2",
];

/// قرار «الفيديو الخفيف» من نتيجة ffprobe ({video, audio, format}) وامتداد الملف المرفوع، بلا تشغيل ffmpeg (يُختبر وحده).
/// يعيد {keep, copy, reasons, args}: keep = MP4 خفيف يبقى كما هو؛ copy بلا keep = إعادة تغليف (-c copy)؛
/// وإلا ترميز بخيارات args (بلا -i ولا ملف الخرج). reasons أسباب الترميز: codec, audio, pix_fmt, size, bitrate.
export function videoArgs(probe, ext = "mp4") {
  const L = LIGHT_VIDEO;
  const v = probe?.video ?? null, a = probe?.audio ?? null;
  const w = Number(v?.width) || 0, h = Number(v?.height) || 0;
  const bitrate = Number(probe?.format?.bit_rate) || Number(v?.bit_rate) || 0;
  const fps = fpsOf(v?.avg_frame_rate) ?? fpsOf(v?.r_frame_rate);
  const reasons = [];
  if (v?.codec_name !== "h264") reasons.push("codec");
  if (a && a.codec_name !== "aac") reasons.push("audio");
  // H.264 بعشر بتات أو 4:2:2 لا يُشغَّل على كثير من الجوالات
  if (v?.pix_fmt && !["yuv420p", "yuvj420p"].includes(v.pix_fmt)) reasons.push("pix_fmt");
  if (Math.min(w, h) > L.maxShort || Math.max(w, h) > L.maxLong) reasons.push("size");
  if (bitrate > L.maxBitrate) reasons.push("bitrate");
  if (!reasons.length) return ext === "mp4" ? { keep: true, copy: true, reasons, args: [] } : { keep: false, copy: true, reasons, args: ["-c", "copy"] };
  const capFps = fps != null && fps > L.maxFps + 0.01;
  const outFps = capFps ? L.maxFps : fps ?? L.maxFps;
  // إطار مرجعي كل ثانية: التقديم بالسحب والتشغيل من منتصف الملف يبدآن فوراً
  const gop = String(Math.max(1, Math.round(outFps)));
  const vf = [...(capFps ? [`fps=${L.maxFps}`] : []), ...boxScale(L.maxShort, L.maxLong)].join(",");
  return {
    keep: false, copy: false, reasons,
    args: ["-c:v", "libx264", "-preset", "veryfast", "-crf", String(L.crf), "-maxrate", L.maxrate, "-bufsize", L.bufsize, "-pix_fmt", "yuv420p", "-vf", vf,
      "-g", gop, "-keyint_min", gop, "-sc_threshold", "0", "-c:a", "aac", "-b:a", L.audio],
  };
}

/// خيارات ترميز معاينة الشبكة (بلا -i ولا ملف الخرج): أول 6 ثوانٍ، بلا صوت، 360p، crf 30، و+faststart حتى تبدأ فوراً.
export function previewArgs(probe) {
  const P = VIDEO_PREVIEW;
  const fps = fpsOf(probe?.video?.avg_frame_rate) ?? fpsOf(probe?.video?.r_frame_rate);
  const capFps = fps != null && fps > P.maxFps + 0.01;
  const vf = [...(capFps ? [`fps=${P.maxFps}`] : []), ...boxScale(P.maxShort, P.maxLong)].join(",");
  return ["-t", String(P.seconds), "-an", "-sn", "-dn", "-c:v", "libx264", "-preset", "veryfast", "-crf", String(P.crf), "-pix_fmt", "yuv420p", "-vf", vf, "-movflags", "+faststart"];
}

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
    CREATE TABLE IF NOT EXISTS chat_reactions (message_id TEXT NOT NULL, user_id TEXT NOT NULL, emoji TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (message_id, user_id));
  `);
  // تفاعلات الرسائل (قلب بالنقر المزدوج، أو إيموجي من الضغط المطوّل): مجموعة ثابتة، واحد لكل مستخدم لكل رسالة
  const REACTIONS = ["❤️", "😂", "😮", "😢", "🔥", "👏", "☕", "👍"];
  async function reactionsFor(ids, uid) {
    const m = {};
    if (!ids.length) return m;
    const rows = (await pool.query("SELECT message_id, emoji, count(*)::int AS n, bool_or(user_id=$2) AS mine FROM chat_reactions WHERE message_id = ANY($1) GROUP BY message_id, emoji ORDER BY n DESC, emoji", [ids, uid])).rows;
    for (const r of rows) (m[r.message_id] ??= []).push({ emoji: r.emoji, count: r.n, mine: r.mine === true });
    return m;
  }
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
  // ffprobe: ترميزا الفيديو والصوت وأبعاد الإطار ومعدّل الإطارات والمعدّل الكلي (لقرار «الفيديو الخفيف»)
  async function probeStreams(file) {
    const { stdout } = await execFileP("ffprobe", ["-v", "error", "-show_entries",
      "stream=codec_type,codec_name,width,height,pix_fmt,avg_frame_rate,r_frame_rate,bit_rate:format=bit_rate,duration", "-of", "json", file], { timeout: 20000 });
    const j = JSON.parse(stdout || "{}");
    const streams = j.streams ?? [];
    return { video: streams.find((x) => x.codec_type === "video"), audio: streams.find((x) => x.codec_type === "audio"), format: j.format ?? {} };
  }
  // الفيديو يُوحَّد إلى MP4 (H.264/AAC وmoov في المقدمة): iPhone يرسل .mov وAndroid يرسل .webm ولا يشغّل أيٌّ منهما ملفات الآخر.
  // الخفيف أصلاً يُعاد تغليفه فقط (سريع، مع إسقاط مسارات البيانات الوصفية)، وغيره يُرمَّز بقواعد videoArgs (720p، سقف 2 ميغابت/ث، 30 إطاراً).
  async function normalizeVideo(inFile, ext) {
    const probe = await probeStreams(inFile);
    if (!probe.video) throw new Error("no video stream");
    const plan = videoArgs(probe, ext);
    if (plan.keep) return inFile;
    const out = path.join(path.dirname(inFile), `${Date.now().toString(36)}-${crypto.randomBytes(12).toString("hex")}.mp4`);
    const args = ["-y", "-hide_banner", "-loglevel", "error", "-i", inFile, "-map", "0:v:0", "-map", "0:a:0?", "-sn", "-dn", ...plan.args, "-movflags", "+faststart", out];
    try { await execFileP("ffmpeg", args, { timeout: 180000 }); }
    catch (e) { await fs.unlink(out).catch(() => {}); throw e; }
    if (!plan.copy) logger(`chat_tools: light video ${path.basename(out)} (${plan.reasons.join(",")})`);
    await fs.unlink(inFile).catch(() => {});
    return out;
  }
  async function transcodeAudio(inFile) {
    const out = inFile.replace(/\.[a-z0-9]+$/, ".m4a");
    await execFileP("ffmpeg", ["-y", "-hide_banner", "-loglevel", "error", "-i", inFile, "-vn", "-ac", "1", "-c:a", "aac", "-b:a", "64k", "-movflags", "+faststart", out], { timeout: 120000 });
    await fs.unlink(inFile).catch(() => {});
    return out;
  }
  // ---- موجة الصوت: 48 قيمة RMS في 0..1 لكل رسالة صوتية حتى يرسم التطبيق شكل الموجة بدل شريط مسطّح.
  // تُحسب بعد التحويل بفكّ الترميز إلى PCM أحادي 8 كيلوهرتز (كافٍ للشكل ورخيص)، وتُطبَّع على أعلى شريحة، وتُخزَّن بجانب الملف
  // <name>.peaks.json (الاسم بنقطتين فلا يطابق NAME_RE ولا يُقدَّم من /chat/media). أي فشل = «بلا موجة» ولا يُفشل الرفع أبداً.
  const PEAKS_N = 48;
  const peaksPath = (name) => path.join(MEDIA_DIR, `${name}.peaks.json`);
  const peaksInflight = new Map();
  async function computePeaks(file) {
    // -t 1800: نصف ساعة من الصوت على الأكثر (28.8 ميغابايت PCM) حتى لا يبتلع ملف طويل الذاكرة
    const { stdout } = await execFileP("ffmpeg", ["-hide_banner", "-loglevel", "error", "-i", file, "-t", "1800", "-vn", "-ac", "1", "-ar", "8000", "-f", "s16le", "-"], { encoding: "buffer", maxBuffer: 32 * 1024 * 1024, timeout: 60000 });
    const n = stdout.length >> 1;
    if (!n) throw new Error("no audio samples");
    const rms = [];
    let max = 0;
    for (let i = 0; i < PEAKS_N; i++) {
      const a = Math.floor((i * n) / PEAKS_N), b = Math.max(a + 1, Math.floor(((i + 1) * n) / PEAKS_N));
      let sum = 0, count = 0;
      for (let j = a; j < b && j < n; j++) { const v = stdout.readInt16LE(j * 2) / 32768; sum += v * v; count++; }
      const r = count ? Math.sqrt(sum / count) : 0;
      rms.push(r); if (r > max) max = r;
    }
    return rms.map((r) => (max > 0 ? Math.round((r / max) * 1000) / 1000 : 0));
  }
  async function audioPeaks(name) {
    if (!MEDIA_DIR || !ffmpeg) return null;
    const cache = peaksPath(name);
    try {
      const j = JSON.parse(await fs.readFile(cache, "utf8"));
      if (Array.isArray(j?.peaks) && j.peaks.length === PEAKS_N) return j.peaks;
    } catch { /* تُحسب الآن */ }
    if (peaksInflight.has(name)) return peaksInflight.get(name);
    const job = (async () => {
      try {
        const peaks = await computePeaks(path.join(MEDIA_DIR, name));
        await fs.writeFile(cache, JSON.stringify({ peaks, n: PEAKS_N, at: new Date().toISOString() })).catch(() => {});
        return peaks;
      } catch (e) {
        logger(`chat_tools: peaks failed for ${name}: ${e?.message || e}`);
        return null;
      } finally { peaksInflight.delete(name); }
    })();
    peaksInflight.set(name, job);
    return job;
  }
  logger(MEDIA_DIR ? `chat_tools: media dir ${MEDIA_DIR}` : `chat_tools: NO writable media dir (${mediaErrors.join("; ")})`);

  // ---- المصغّرات: نسخة JPEG بحد 480 بكسل للصور، وإطار من الثانية الأولى للفيديو. تُولَّد عند الرفع وعند أول طلب
  // (فتشمل الملفات القديمة)، وتُخزَّن في MEDIA_DIR/thumbs. إن تعذّر التوليد يُقدَّم الملف الأصلي.
  const THUMB_MAX = Number(process.env.CHAT_THUMB_MAX) || 480;
  const THUMB_DIR = MEDIA_DIR ? path.join(MEDIA_DIR, "thumbs") : null;
  if (THUMB_DIR) await fs.mkdir(THUMB_DIR, { recursive: true }).catch(() => {});
  const inflight = new Map();
  const thumbPath = (name) => path.join(THUMB_DIR, name.replace(/\.[a-z0-9]+$/, "") + ".jpg");
  async function makeThumb(name) {
    if (!THUMB_DIR || !ffmpeg) return null;
    const out = thumbPath(name);
    try { await fs.access(out); return out; } catch { /* يُولَّد الآن */ }
    if (inflight.has(name)) return inflight.get(name);
    const type = EXT_TYPE[name.split(".").pop()] || "";
    if (!type.startsWith("image/") && !type.startsWith("video/")) return null;
    const job = (async () => {
      const src = path.join(MEDIA_DIR, name);
      const tmp = out + ".part.jpg";
      const args = ["-y", "-hide_banner", "-loglevel", "error"];
      if (type.startsWith("video/")) args.push("-ss", "0.5");
      args.push("-i", src);
      if (type.startsWith("video/")) args.push("-frames:v", "1");
      args.push("-vf", `scale='min(${THUMB_MAX},iw)':'min(${THUMB_MAX},ih)':force_original_aspect_ratio=decrease`, "-c:v", "mjpeg", "-q:v", "5", "-f", "image2", tmp);
      try {
        await execFileP("ffmpeg", args, { timeout: 30000 });
        await fs.rename(tmp, out);
        return out;
      } catch (e) {
        await fs.unlink(tmp).catch(() => {});
        logger(`chat_tools: thumb failed for ${name}: ${e?.message || e}`);
        return null;
      } finally { inflight.delete(name); }
    })();
    inflight.set(name, job);
    return job;
  }
  const sendFile = (reply, file, type, size) => {
    reply.header("content-type", type).header("content-length", size).header("cache-control", "public, max-age=31536000, immutable");
    return reply.send(createReadStream(file));
  };
  app.get("/chat/thumb/:name", { config: { rateLimit: false } }, async (req, reply) => {
    const name = String(req.params.name);
    if (!MEDIA_DIR || !NAME_RE.test(name)) return bad(reply, 404, "not-found");
    const src = path.join(MEDIA_DIR, name);
    let st;
    try { st = await fs.stat(src); } catch { return bad(reply, 404, "not-found"); }
    const type = EXT_TYPE[name.split(".").pop()] || "application/octet-stream";
    if (!type.startsWith("image/") && !type.startsWith("video/")) return bad(reply, 404, "not-found");
    const t = await makeThumb(name);
    if (t) {
      try { const ts = await fs.stat(t); return sendFile(reply, t, "image/jpeg", ts.size); } catch { /* نعود للأصل */ }
    }
    if (type.startsWith("video/")) return bad(reply, 404, "not-found");
    return sendFile(reply, src, type, st.size);
  });

  // ---- تقديم ملف بدعم Range (الصوت والفيديو ومعاينات الفيديو): 206 للجزء المطلوب و416 لنطاق خارج الملف
  async function serveRange(req, reply, file, type) {
    let st;
    try { st = await fs.stat(file); } catch { return bad(reply, 404, "not-found"); }
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
  }

  // ---- معاينة الفيديو للشبكة وعارض اللحظات: MP4 صامت 360p لأول 6 ثوانٍ يُعاد كحلقة بدل تنزيل الفيديو كاملاً.
  // تُولَّد عند أول طلب (فتشمل الفيديوهات القديمة) وتُخزَّن في MEDIA_DIR/vpreviews باسم الملف؛ ترميزان على الأكثر في الوقت نفسه
  // حتى لا تُغرق شبكةٌ من الفيديوهات الجديدة المعالج. أي فشل (أو غياب ffmpeg) = 404 فيعود التطبيق إلى المصغّر.
  const PREVIEW_DIR = MEDIA_DIR ? path.join(MEDIA_DIR, "vpreviews") : null;
  if (PREVIEW_DIR) await fs.mkdir(PREVIEW_DIR, { recursive: true }).catch(() => {});
  const previewPath = (name) => path.join(PREVIEW_DIR, name.replace(/\.[a-z0-9]+$/, "") + ".mp4");
  const previewInflight = new Map();
  const PREVIEW_SLOTS = Math.max(1, Number(process.env.CHAT_VPREVIEW_SLOTS) || 2);
  let previewRunning = 0;
  const previewQueue = [];
  const withPreviewSlot = async (fn) => {
    if (previewRunning >= PREVIEW_SLOTS) await new Promise((r) => previewQueue.push(r));
    previewRunning++;
    try { return await fn(); } finally { previewRunning--; previewQueue.shift()?.(); }
  };
  async function makePreview(name) {
    if (!PREVIEW_DIR || !ffmpeg) return null;
    const out = previewPath(name);
    try { await fs.access(out); return out; } catch { /* تُولَّد الآن */ }
    if (previewInflight.has(name)) return previewInflight.get(name);
    const job = (async () => {
      const tmp = out.replace(/\.mp4$/, `.part-${crypto.randomBytes(4).toString("hex")}.mp4`);
      try {
        return await withPreviewSlot(async () => {
          const src = path.join(MEDIA_DIR, name);
          const probe = await probeStreams(src);
          if (!probe.video) throw new Error("no video stream");
          await execFileP("ffmpeg", ["-y", "-hide_banner", "-loglevel", "error", "-i", src, "-map", "0:v:0", ...previewArgs(probe), tmp], { timeout: 60000 });
          await fs.rename(tmp, out);
          return out;
        });
      } catch (e) {
        await fs.unlink(tmp).catch(() => {});
        logger(`chat_tools: vpreview failed for ${name}: ${e?.message || e}`);
        return null;
      } finally { previewInflight.delete(name); }
    })();
    previewInflight.set(name, job);
    return job;
  }
  app.get("/chat/vpreview/:name", { config: { rateLimit: false } }, async (req, reply) => {
    const name = String(req.params.name);
    if (!MEDIA_DIR || !ffmpeg || !NAME_RE.test(name)) return bad(reply, 404, "not-found");
    const type = EXT_TYPE[name.split(".").pop()] || "";
    if (!type.startsWith("video/")) return bad(reply, 404, "not-found");
    try { await fs.access(path.join(MEDIA_DIR, name)); } catch { return bad(reply, 404, "not-found"); }
    const file = await makePreview(name);
    if (!file) return bad(reply, 404, "not-found");
    return serveRange(req, reply, file, "video/mp4");
  });

  const unauthorized = (reply) => reply.code(401).send({ error: "auth" });
  const bad = (reply, code, error) => reply.code(code).send({ error });

  // حالة الإضافة (بلا مصادقة وبلا مسارات): يفيد التحقق من النشر
  // حذف ملف وسائط وصورته المصغّرة (عند حذف حساب أو مسح محتوى مخفي). يقبل /chat/media/<name> أو رابطاً كاملاً.
  globalThis.naslifeMediaDelete = async (url) => {
    const name = String(url ?? "").split("?")[0].split("/").pop();
    if (!MEDIA_DIR || !NAME_RE.test(name)) return false;
    await fs.unlink(path.join(MEDIA_DIR, name)).catch(() => {});
    if (THUMB_DIR) await fs.unlink(thumbPath(name)).catch(() => {});
    if (PREVIEW_DIR) await fs.unlink(previewPath(name)).catch(() => {});
    await fs.unlink(peaksPath(name)).catch(() => {});
    return true;
  };
  app.get("/chat/status", async () => ({ ok: true, media: !!MEDIA_DIR, durable: !!MEDIA_DIR && !MEDIA_DIR.startsWith(os.tmpdir()), transcode: ffmpeg, thumbs: !!MEDIA_DIR && ffmpeg, peaks: !!MEDIA_DIR && ffmpeg, vpreview: !!MEDIA_DIR && ffmpeg, maxBytes: MAX_BYTES }));

  // ---- موجة الصوت لملف موجود (الرسائل الأقدم من هذه الميزة): تُحسب عند أول طلب وتُخزَّن بجانب الملف. يقبل الاسم أو الرابط كاملاً.
  // بلا مصادقة كالملف نفسه (الأسماء عشوائية غير قابلة للتخمين)؛ 404 لاسم غير صالح أو ملف غير صوتي أو مفقود، و{peaks:null} إن تعذّر الحساب.
  app.get("/chat/peaks", async (req, reply) => {
    const name = String(req.query?.name ?? "").split("?")[0].split("/").pop();
    if (!MEDIA_DIR || !NAME_RE.test(name)) return bad(reply, 404, "not-found");
    const type = EXT_TYPE[name.split(".").pop()] || "";
    if (!type.startsWith("audio/")) return bad(reply, 404, "not-found");
    try { await fs.access(path.join(MEDIA_DIR, name)); } catch { return bad(reply, 404, "not-found"); }
    const peaks = await audioPeaks(name);
    if (peaks) reply.header("cache-control", "public, max-age=31536000, immutable");
    return { name, peaks, n: PEAKS_N };
  });

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
    if (ct.startsWith("image/") || ct.startsWith("video/")) makeThumb(name).catch(() => {});
    // الصوت يعود مع موجته (48 قيمة) حتى يحفظها التطبيق في extra.peaks مع الرسالة؛ null إن تعذّر الحساب
    const peaks = ct.startsWith("audio/") ? await audioPeaks(name).catch(() => null) : undefined;
    return { url: `/chat/media/${name}`, type: ct, kind: kindOf(ct), size, thumbUrl: ct.startsWith("image/") || ct.startsWith("video/") ? `/chat/thumb/${name}` : null, ...(peaks !== undefined ? { peaks } : {}) };
  });

  // ---- التقديم مع دعم Range للصوت والفيديو
  app.get("/chat/media/:name", { config: { rateLimit: false } }, async (req, reply) => {
    const name = String(req.params.name);
    if (!MEDIA_DIR || !NAME_RE.test(name)) return bad(reply, 404, "not-found");
    return serveRange(req, reply, path.join(MEDIA_DIR, name), EXT_TYPE[name.split(".").pop()] || "application/octet-stream");
  });

  // ---- بيانات إضافية للرسائل: رد مقتبس، إعادة توجيه، مدة الصوت… تُحفظ بمعرّف الرسالة بعد إرسالها
  const metaOut = (r) => ({ replyTo: r.reply_to, quote: r.quote, forwardedFrom: r.forwarded_from, extra: r.extra });
  // الحظر بين طرفي المحادثة: الطرف الآخر من peerId في الطلب، أو كاتب الرسالة المقتبسة، أو صف الرسالة في النواة إن كان جدولها في القاعدة نفسها
  let MSG = null;
  try {
    const mc = new Set((await pool.query("SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name='messages'")).rows.map((r) => r.column_name));
    const from = ["sender_id", "from_id", "user_id", "author_id"].find((c) => mc.has(c)), to = ["recipient_id", "to_id", "receiver_id", "peer_id"].find((c) => mc.has(c));
    if (mc.has("id") && from) MSG = { from, to: to ?? null };
  } catch { MSG = null; }
  const peersOf = async (uid, messageId, ...hints) => {
    const out = new Set(hints.map((h) => String(h ?? "").toUpperCase()).filter((h) => /^[A-Z]{2}\d{7}$/.test(h)));
    if (MSG && messageId) {
      try {
        const m = (await pool.query(`SELECT "${MSG.from}" AS a${MSG.to ? `, "${MSG.to}" AS b` : ""} FROM messages WHERE id::text=$1`, [messageId])).rows[0];
        for (const v of [m?.a, m?.b]) if (v) out.add(String(v));
      } catch { /* ignore */ }
    }
    out.delete(uid);
    return [...out];
  };
  const blockedWith = async (uid, messageId, ...hints) => {
    const peers = await peersOf(uid, messageId, ...hints);
    if (!peers.length) return false;
    let list = [];
    try { list = (await globalThis.naslifeBlockedIds?.(uid)) ?? []; } catch { list = []; }
    if (!list.length) { try { list = (await pool.query("SELECT user_id, blocked_id FROM user_blocks WHERE user_id=$1 OR blocked_id=$1", [uid])).rows.flatMap((r) => [r.user_id, r.blocked_id]); } catch { list = []; } }
    return peers.some((p) => list.includes(p));
  };
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
    if (await blockedWith(uid, id, b.peerId, quote?.senderId)) return bad(reply, 403, "blocked");
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
    const out = Object.fromEntries(r.rows.map((x) => [x.message_id, metaOut(x)]));
    // التفاعلات تُضاف لكل رسالة لها تفاعل حتى بلا صف بيانات إضافية
    const rx = await reactionsFor(ids, uid);
    for (const [id, list] of Object.entries(rx)) (out[id] ??= { replyTo: null, quote: null, forwardedFrom: null, extra: null }).reactions = list;
    // طلبات رموز الاختصار (مبلغ/تقسيم/موعد/إرسال) من server/chat_cards.js إن كانت مسجّلة
    try {
      const rq = await globalThis.naslifeChatRequests?.(ids, uid);
      for (const [id, r] of Object.entries(rq ?? {})) (out[id] ??= { replyTo: null, quote: null, forwardedFrom: null, extra: null }).request = r;
    } catch { /* بلا طلبات */ }
    return out;
  });
  app.post("/chat/react", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const id = String(req.body?.messageId ?? "");
    if (!id || id.length > 64) return bad(reply, 400, "bad-id");
    const raw = String(req.body?.emoji ?? "").trim();
    if (raw && !REACTIONS.includes(raw)) return bad(reply, 400, "bad-emoji", { allowed: REACTIONS });
    if (raw && await blockedWith(uid, id, req.body?.peerId)) return bad(reply, 403, "blocked");
    if (!raw) await pool.query("DELETE FROM chat_reactions WHERE message_id=$1 AND user_id=$2", [id, uid]);
    else {
      const cur = (await pool.query("SELECT emoji FROM chat_reactions WHERE message_id=$1 AND user_id=$2", [id, uid])).rows[0];
      if (cur && cur.emoji === raw) await pool.query("DELETE FROM chat_reactions WHERE message_id=$1 AND user_id=$2", [id, uid]);
      else await pool.query("INSERT INTO chat_reactions(message_id,user_id,emoji) VALUES($1,$2,$3) ON CONFLICT (message_id,user_id) DO UPDATE SET emoji=EXCLUDED.emoji, created_at=now()", [id, uid, raw]);
    }
    return { ok: true, messageId: id, reactions: (await reactionsFor([id], uid))[id] ?? [] };
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
