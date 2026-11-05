// إزالة بيانات الموقع من الصور المرفوعة بلغة جافاسكربت وحدها (بلا ImageMagick ولا مكتبات أصلية)، وتمشيط الملفات القديمة.
// ليست إضافة Fastify (لا سطر في register.txt): تستوردها server/chat_tools.js، وتُتاح للإضافات عبر globalThis.naslifeStripImageMeta.
//   stripImageMeta(buf)  → {buf, changed, format, removed, orientation} ؛ أي شك = الأصل كما هو مع error (لا يُكتب ملف تالف أبداً)
//   hasLocationMeta(buf) → هل في الصورة إحداثيات GPS (Exif أو XMP)؟ للتمشيط فقط
//   sweepMediaMeta({dir, ...}) → تمشيط مرة واحدة بتقدّم محفوظ: يكتب نسخة نظيفة في ملف مؤقت ثم يعيد التسمية (inode جديد)
// JPEG: تُحذف APP1 (Exif/XMP) وAPP13 (IPTC) وCOM وكل APPn غير APP0/APP2-ICC/APP14 وما بعد EOI (صور MPF الملحقة بـ Exif خاص بها)؛
//   يبقى ICC وAdobe، والاتجاه (Orientation ≠ 1) يُعاد في APP1 صغير فيه هذا الوسم وحده.
// PNG: تُحذف eXIf وtEXt وiTXt وzTXt وtIME وما بعد IEND (والاتجاه في eXIf صغير). WebP: تُحذف EXIF وXMP وتُصفّر أعلامهما في VP8X.
// GIF لا يحمل موقعاً. التفاصيل في docs/chat.md «خصوصية الوسائط».
import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import zlib from "node:zlib";

const JPEG_SIG = Buffer.from([0xff, 0xd8, 0xff]);
const PNG_SIG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const EXIF_HDR = Buffer.from("Exif\0\0", "latin1");
const ICC_HDR = Buffer.from("ICC_PROFILE\0", "latin1");

export function formatOf(buf) {
  if (!Buffer.isBuffer(buf) || buf.length < 12) return null;
  if (buf.subarray(0, 3).equals(JPEG_SIG)) return "jpeg";
  if (buf.subarray(0, 8).equals(PNG_SIG)) return "png";
  if (buf.toString("latin1", 0, 4) === "RIFF" && buf.toString("latin1", 8, 12) === "WEBP") return "webp";
  if (buf.toString("latin1", 0, 4) === "GIF8") return "gif";
  return null;
}

// ---- TIFF/Exif: قراءة IFD0 فقط (الاتجاه ومؤشر GPS) بفحص الحدود في كل قراءة
/// يقرأ كتلة TIFF (تبدأ بـ II أو MM). يعيد {orientation, gps} حيث gps = وجود IFD لـ GPS فيه وسم إحداثيات (1..4).
export function readTiff(t) {
  if (!Buffer.isBuffer(t) || t.length < 8) throw new Error("tiff: short");
  const le = t[0] === 0x49 && t[1] === 0x49;
  if (!le && !(t[0] === 0x4d && t[1] === 0x4d)) throw new Error("tiff: bad byte order");
  const u16 = (o) => { if (o < 0 || o + 2 > t.length) throw new Error("tiff: out of range"); return le ? t.readUInt16LE(o) : t.readUInt16BE(o); };
  const u32 = (o) => { if (o < 0 || o + 4 > t.length) throw new Error("tiff: out of range"); return le ? t.readUInt32LE(o) : t.readUInt32BE(o); };
  if (u16(2) !== 42) throw new Error("tiff: bad magic");
  const entries = (ifd) => {
    const n = u16(ifd);
    if (n > 1000) throw new Error("tiff: too many entries");
    const out = [];
    for (let i = 0; i < n; i++) { const e = ifd + 2 + i * 12; out.push({ tag: u16(e), type: u16(e + 2), count: u32(e + 4), at: e + 8 }); }
    return out;
  };
  let orientation = 1, gps = false;
  for (const e of entries(u32(4))) {
    if (e.tag === 0x0112 && e.type === 3 && e.count >= 1) { const v = u16(e.at); if (v >= 1 && v <= 8) orientation = v; }
    if (e.tag === 0x8825) {
      try { gps = entries(u32(e.at)).some((g) => g.tag >= 1 && g.tag <= 4); } catch { gps = true; /* مؤشر GPS تالف: نعامله كموقع احتياطاً */ }
    }
  }
  return { orientation, gps };
}

/// كتلة TIFF صغيرة فيها وسم الاتجاه وحده (II، IFD0 بمدخل واحد، بلا IFD تالٍ): 26 بايتاً.
export function orientationTiff(orientation) {
  const t = Buffer.alloc(26);
  t.write("II", 0, "latin1"); t.writeUInt16LE(42, 2); t.writeUInt32LE(8, 4);
  t.writeUInt16LE(1, 8);
  t.writeUInt16LE(0x0112, 10); t.writeUInt16LE(3, 12); t.writeUInt32LE(1, 14); t.writeUInt16LE(orientation, 18); t.writeUInt16LE(0, 20);
  t.writeUInt32LE(0, 22);
  return t;
}

const XMP_GPS_RE = /GPS(Latitude|Longitude|Altitude|Coordinates)|exif:GPS/;
const textHasGps = (s) => XMP_GPS_RE.test(s);

// ---- JPEG
/// يقسم JPEG إلى مقاطع حتى SOS، ثم يجد EOI الأول في بيانات المسح (FF مضاعفة بـ 00 داخلها، وRSTn وحدها بلا طول).
function jpegSegments(buf) {
  if (!buf.subarray(0, 2).equals(Buffer.from([0xff, 0xd8]))) throw new Error("jpeg: no SOI");
  const segs = [];
  let p = 2;
  for (;;) {
    if (p >= buf.length) throw new Error("jpeg: truncated before SOS");
    if (buf[p] !== 0xff) throw new Error("jpeg: marker expected");
    while (p < buf.length && buf[p] === 0xff) p++; // بايتات حشو
    if (p >= buf.length) throw new Error("jpeg: truncated");
    const m = buf[p]; const start = p - 1; p++;
    if (m === 0xd8 || m === 0x01 || (m >= 0xd0 && m <= 0xd7)) { segs.push({ m, start, end: p }); continue; }
    if (m === 0xd9) throw new Error("jpeg: EOI before SOS");
    if (p + 2 > buf.length) throw new Error("jpeg: truncated length");
    const len = buf.readUInt16BE(p);
    if (len < 2 || p + len > buf.length) throw new Error("jpeg: bad segment length");
    segs.push({ m, start, end: p + len, data: buf.subarray(p + 2, p + len) });
    p += len;
    if (m === 0xda) break;
  }
  // بيانات المسح وما بعدها (مسوحات متعددة في JPEG التدريجي بمقاطع DHT/SOS بينها) حتى أول FFD9
  let q = p, eoi = -1;
  while (q + 1 < buf.length) {
    q = buf.indexOf(0xff, q); // قفز إلى FF التالية بدل المرور على كل بايت (ملف 30 م.ب)
    if (q < 0 || q + 1 >= buf.length) break;
    if (buf[q] === 0xff) {
      const n = buf[q + 1];
      if (n === 0xd9) { eoi = q + 2; break; }
      if (n === 0x00 || n === 0xff || (n >= 0xd0 && n <= 0xd7)) { q += n === 0xff ? 1 : 2; continue; }
      // مقطع بين المسوحات (DHT، SOS، DQT، DRI…) أو APPn بعد المسح: له طول
      if (q + 4 > buf.length) break;
      const len = buf.readUInt16BE(q + 2);
      if (len < 2) throw new Error("jpeg: bad inner segment");
      segs.push({ m: n, start: q, end: q + 2 + len, data: buf.subarray(q + 4, q + 2 + len), inner: true });
      q += 2 + len;
      continue;
    }
    q++;
  }
  if (eoi < 0) throw new Error("jpeg: no EOI");
  return { segs, scanStart: p, eoi };
}

function exifOfJpeg(segs) {
  for (const s of segs) if (s.m === 0xe1 && s.data?.subarray(0, 6).equals(EXIF_HDR)) return s.data.subarray(6);
  return null;
}

function jpegHasGps(buf) {
  const { segs } = jpegSegments(buf);
  for (const s of segs) {
    if (s.m !== 0xe1 || !s.data) continue;
    if (s.data.subarray(0, 6).equals(EXIF_HDR)) { try { if (readTiff(s.data.subarray(6)).gps) return true; } catch { return true; } }
    else if (textHasGps(s.data.toString("latin1"))) return true;
  }
  return false;
}

// ما يبقى من APPn: JFIF/JFXX (APP0)، ملف ICC (APP2 بترويسة ICC_PROFILE)، وAdobe (APP14: تحويل الألوان لصور CMYK)
const keepApp = (s) => s.m === 0xe0 || s.m === 0xee || (s.m === 0xe2 && s.data?.subarray(0, 12).equals(ICC_HDR));

function stripJpeg(buf) {
  const { segs, scanStart, eoi } = jpegSegments(buf);
  let orientation = 1;
  const exif = exifOfJpeg(segs);
  if (exif) { try { orientation = readTiff(exif).orientation; } catch { orientation = 1; } }
  const removed = [];
  const parts = [buf.subarray(0, 2)];
  let insertedExif = orientation === 1;
  const exifSeg = () => {
    const tiff = orientationTiff(orientation);
    const h = Buffer.alloc(4); h[0] = 0xff; h[1] = 0xe1; h.writeUInt16BE(2 + EXIF_HDR.length + tiff.length, 2);
    return Buffer.concat([h, EXIF_HDR, tiff]);
  };
  const head = segs.filter((s) => !s.inner);
  for (let i = 0; i < head.length; i++) {
    const s = head[i];
    if (s.m === 0xd8) continue;
    const isApp = s.m >= 0xe0 && s.m <= 0xef;
    if (s.m === 0xfe || (isApp && !keepApp(s))) { removed.push(s.m === 0xfe ? "COM" : `APP${s.m - 0xe0}`); continue; }
    // الاتجاه يُكتب بعد APP0 إن وُجد (JFIF يجب أن يلي SOI) وإلا في أول المقاطع
    if (!insertedExif && s.m !== 0xe0) { parts.push(exifSeg()); insertedExif = true; }
    parts.push(buf.subarray(s.start, s.end));
  }
  if (!insertedExif) parts.push(exifSeg());
  // المقاطع داخل منطقة المسح تُنسخ كما هي إلا APPn/COM فيها (نادرة)
  let q = scanStart;
  for (const s of segs.filter((x) => x.inner)) {
    const isApp = s.m >= 0xe0 && s.m <= 0xef;
    if (s.m === 0xfe || (isApp && !keepApp(s))) { parts.push(buf.subarray(q, s.start)); q = s.end; removed.push(s.m === 0xfe ? "COM" : `APP${s.m - 0xe0}`); }
  }
  parts.push(buf.subarray(q, eoi));
  if (eoi < buf.length) removed.push("trailer");
  if (!removed.length) return { buf, changed: false, removed, orientation };
  const out = Buffer.concat(parts);
  // تحقق بنيوي من الناتج: SOI وSOF وSOS وEOI في مكانها
  const v = jpegSegments(out);
  if (!v.segs.some((s) => s.m >= 0xc0 && s.m <= 0xcf && s.m !== 0xc4 && s.m !== 0xc8 && s.m !== 0xcc) || v.eoi !== out.length) throw new Error("jpeg: output failed validation");
  return { buf: out, changed: true, removed, orientation };
}

// ---- PNG
let CRC_TABLE = null;
function crc32(b) {
  if (typeof zlib.crc32 === "function") return zlib.crc32(b) >>> 0;
  if (!CRC_TABLE) { CRC_TABLE = new Uint32Array(256); for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; CRC_TABLE[n] = c >>> 0; } }
  let c = 0xffffffff;
  for (let i = 0; i < b.length; i++) c = CRC_TABLE[(c ^ b[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
function pngChunks(buf) {
  if (!buf.subarray(0, 8).equals(PNG_SIG)) throw new Error("png: bad signature");
  const out = [];
  let p = 8;
  for (;;) {
    if (p + 12 > buf.length) throw new Error("png: truncated");
    const len = buf.readUInt32BE(p);
    const type = buf.toString("latin1", p + 4, p + 8);
    if (!/^[A-Za-z]{4}$/.test(type) || p + 12 + len > buf.length) throw new Error("png: bad chunk");
    out.push({ type, start: p, end: p + 12 + len, data: buf.subarray(p + 8, p + 8 + len) });
    p += 12 + len;
    if (type === "IEND") break;
  }
  if (out[0]?.type !== "IHDR") throw new Error("png: IHDR not first");
  return { chunks: out, end: p };
}
const PNG_DROP = new Set(["eXIf", "tEXt", "iTXt", "zTXt", "tIME"]);
/// نص قطعة PNG النصية (مع فك ضغط zTXt وiTXt المضغوط) لفحص GPS في XMP أو «Raw profile type exif».
function pngText(c) {
  const d = c.data;
  const z = d.indexOf(0);
  if (z < 0) return "";
  const keyword = d.toString("latin1", 0, z);
  let text;
  try {
    if (c.type === "tEXt") text = d.subarray(z + 1).toString("latin1");
    else if (c.type === "zTXt") text = zlib.inflateSync(d.subarray(z + 2)).toString("latin1");
    else {
      const compressed = d[z + 1] === 1;
      let q = z + 3; const l = d.indexOf(0, q); const t = d.indexOf(0, l + 1);
      if (l < 0 || t < 0) return keyword;
      q = t + 1;
      text = compressed ? zlib.inflateSync(d.subarray(q)).toString("utf8") : d.subarray(q).toString("utf8");
    }
  } catch { return keyword; }
  return `${keyword}\n${text}`;
}
function rawProfileGps(text) {
  // «Raw profile type exif/APP1» من ImageMagick: سطر اسم ثم الطول ثم سداسي عشري لكتلة Exif
  const m = /^Raw profile type (exif|APP1)\n/i.exec(text);
  if (!m) return false;
  const hex = text.slice(m[0].length).replace(/^[\s\S]*?\n\s*\d+\s*\n/, "").replace(/[^0-9a-f]/gi, "");
  try {
    let b = Buffer.from(hex, "hex");
    if (b.subarray(0, 6).equals(EXIF_HDR)) b = b.subarray(6);
    return readTiff(b).gps;
  } catch { return /exif|app1/i.test(m[1]); }
}
function pngHasGps(buf) {
  for (const c of pngChunks(buf).chunks) {
    if (c.type === "eXIf") { try { if (readTiff(c.data).gps) return true; } catch { return true; } }
    else if (c.type === "tEXt" || c.type === "zTXt" || c.type === "iTXt") { const t = pngText(c); if (textHasGps(t) || rawProfileGps(t)) return true; }
  }
  return false;
}
function pngChunk(type, data) {
  const h = Buffer.alloc(8); h.writeUInt32BE(data.length, 0); h.write(type, 4, "latin1");
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(Buffer.concat([h.subarray(4), data])), 0);
  return Buffer.concat([h, data, crc]);
}
function stripPng(buf) {
  const { chunks, end } = pngChunks(buf);
  let orientation = 1;
  const ex = chunks.find((c) => c.type === "eXIf");
  if (ex) { try { orientation = readTiff(ex.data).orientation; } catch { orientation = 1; } }
  const removed = [];
  const parts = [PNG_SIG];
  for (const c of chunks) {
    if (PNG_DROP.has(c.type)) {
      removed.push(c.type);
      // eXIf يسبق IDAT دائماً، فنضع مكانه نسخة بالاتجاه وحده
      if (c === ex && orientation !== 1) parts.push(pngChunk("eXIf", orientationTiff(orientation)));
      continue;
    }
    parts.push(buf.subarray(c.start, c.end));
  }
  if (end < buf.length) removed.push("trailer");
  if (!removed.length) return { buf, changed: false, removed, orientation };
  const out = Buffer.concat(parts);
  const v = pngChunks(out);
  if (v.end !== out.length || !v.chunks.some((c) => c.type === "IDAT")) throw new Error("png: output failed validation");
  return { buf: out, changed: true, removed, orientation };
}

// ---- WebP (RIFF)
function webpChunks(buf) {
  const size = buf.readUInt32LE(4);
  const end = 8 + size;
  if (end > buf.length || size < 4) throw new Error("webp: bad RIFF size");
  const out = [];
  let p = 12;
  while (p < end) {
    if (p + 8 > end) throw new Error("webp: truncated chunk");
    const fourcc = buf.toString("latin1", p, p + 4), len = buf.readUInt32LE(p + 4);
    const next = p + 8 + len + (len & 1);
    if (p + 8 + len > end) throw new Error("webp: chunk past end");
    out.push({ fourcc, start: p, end: Math.min(next, end), data: buf.subarray(p + 8, p + 8 + len) });
    p = next;
  }
  if (!out.some((c) => c.fourcc === "VP8 " || c.fourcc === "VP8L" || c.fourcc === "ANIM")) throw new Error("webp: no image data");
  return { chunks: out, end };
}
const webpExifTiff = (d) => (d.subarray(0, 6).equals(EXIF_HDR) ? d.subarray(6) : d);
function webpHasGps(buf) {
  for (const c of webpChunks(buf).chunks) {
    if (c.fourcc === "EXIF") { try { if (readTiff(webpExifTiff(c.data)).gps) return true; } catch { return true; } }
    else if (c.fourcc === "XMP " && textHasGps(c.data.toString("latin1"))) return true;
  }
  return false;
}
function stripWebp(buf) {
  const { chunks, end } = webpChunks(buf);
  let orientation = 1;
  const ex = chunks.find((c) => c.fourcc === "EXIF");
  if (ex) { try { orientation = readTiff(webpExifTiff(ex.data)).orientation; } catch { orientation = 1; } }
  const removed = [];
  const parts = [];
  const keepExif = orientation !== 1;
  for (const c of chunks) {
    if (c.fourcc === "EXIF" || c.fourcc === "XMP ") {
      removed.push(c.fourcc.trim());
      if (c === ex && keepExif) {
        const t = orientationTiff(orientation), h = Buffer.alloc(8);
        h.write("EXIF", 0, "latin1"); h.writeUInt32LE(t.length, 4);
        parts.push(Buffer.concat([h, t])); // 26 بايتاً: زوجي فلا حشو
      }
      continue;
    }
    if (c.fourcc === "VP8X") {
      const copy = Buffer.from(buf.subarray(c.start, c.end));
      // أعلام VP8X: 0x08 = Exif، 0x04 = XMP
      copy[8] = (copy[8] & ~0x04 & ~0x08) | (keepExif ? 0x08 : 0);
      parts.push(copy);
      continue;
    }
    parts.push(buf.subarray(c.start, c.end));
  }
  if (end < buf.length) removed.push("trailer");
  if (!removed.length) return { buf, changed: false, removed, orientation };
  const body = Buffer.concat(parts);
  const head = Buffer.alloc(12); head.write("RIFF", 0, "latin1"); head.writeUInt32LE(4 + body.length, 4); head.write("WEBP", 8, "latin1");
  const out = Buffer.concat([head, body]);
  const v = webpChunks(out);
  if (v.end !== out.length) throw new Error("webp: output failed validation");
  return { buf: out, changed: true, removed, orientation };
}

/// يزيل بيانات الموقع والوصف من صورة. لا يرمي أبداً: الفشل يعيد الأصل مع error ليُسجَّل.
export function stripImageMeta(buf) {
  const format = formatOf(buf);
  try {
    if (format === "jpeg") return { format, ...stripJpeg(buf) };
    if (format === "png") return { format, ...stripPng(buf) };
    if (format === "webp") return { format, ...stripWebp(buf) };
  } catch (e) {
    return { buf, changed: false, format, removed: [], orientation: 1, error: String(e?.message ?? e) };
  }
  return { buf, changed: false, format, removed: [], orientation: 1 };
}

/// هل تحمل الصورة إحداثيات GPS؟ (Exif أو XMP أو نص PNG). الملف غير المقروء = false (لا نلمسه).
export function hasLocationMeta(buf) {
  try {
    const f = formatOf(buf);
    if (f === "jpeg") return jpegHasGps(buf);
    if (f === "png") return pngHasGps(buf);
    if (f === "webp") return webpHasGps(buf);
  } catch { return false; }
  return false;
}

// ---- تمشيط الملفات القديمة: مرة واحدة، بتقدّم محفوظ في ملف حالة، دفعات صغيرة بينها توقف، وكتابة ذرية.
export const SWEEP_VERSION = 1;
const IMAGE_EXT = new Set(["jpg", "jpeg", "png", "webp"]);
/// {dir, nameRe, stateFile, batch, pauseMs, before, log, signal}. before: لا يُمشَّط إلا ما اسمه أقدم من هذا (ما بعده نُظّف عند الرفع).
/// يعيد ملخصاً {scanned, located, stripped, failed, skipped, done}. يكمل من آخر اسم عند إعادة التشغيل ولا يكرر بعد done.
export async function sweepMediaMeta({ dir, nameRe = null, stateFile = null, batch = 25, pauseMs = 2000, before = null, log = () => {}, signal = null } = {}) {
  const stPath = stateFile ?? path.join(dir, ".meta-sweep.json");
  let state = { version: SWEEP_VERSION, cursor: "", done: false, scanned: 0, located: 0, stripped: 0, failed: 0 };
  try { const s = JSON.parse(await fs.readFile(stPath, "utf8")); if (s?.version === SWEEP_VERSION) state = { ...state, ...s }; } catch { /* أول تشغيل */ }
  const summary = () => ({ scanned: state.scanned, located: state.located, stripped: state.stripped, failed: state.failed, done: state.done });
  if (state.done) return { ...summary(), skipped: true };
  const save = async () => {
    const tmp = `${stPath}.${crypto.randomBytes(4).toString("hex")}.tmp`;
    await fs.writeFile(tmp, JSON.stringify({ ...state, at: new Date().toISOString() }));
    await fs.rename(tmp, stPath);
  };
  let names = (await fs.readdir(dir)).filter((n) => (!nameRe || nameRe.test(n)) && IMAGE_EXT.has(n.split(".").pop().toLowerCase()) && n > state.cursor && (!before || n < before));
  names.sort();
  const sleep = (ms) => new Promise((r) => { const t = setTimeout(r, ms); t.unref?.(); });
  let inBatch = 0;
  for (const name of names) {
    if (signal?.aborted) break;
    const file = path.join(dir, name);
    try {
      const st = await fs.stat(file);
      if (!st.isFile()) { state.cursor = name; continue; }
      const buf = await fs.readFile(file);
      state.scanned++;
      if (hasLocationMeta(buf)) {
        state.located++;
        const r = stripImageMeta(buf);
        if (!r.changed || r.error || hasLocationMeta(r.buf)) { state.failed++; log(`media sweep: kept ${name} as is (${r.error ?? "not stripped"})`); }
        else {
          // ملف مؤقت ثم إعادة تسمية: inode جديد، فالروابط الصلبة في لقطات النسخ الاحتياطي لا تُعدَّل في مكانها
          const tmp = path.join(dir, `.${name}.${crypto.randomBytes(4).toString("hex")}.sweep`);
          try {
            await fs.writeFile(tmp, r.buf, { mode: st.mode & 0o777 });
            // حُذف الملف أو تغيّر أثناء القراءة (حذف حساب مثلاً): لا نعيده
            const now = await fs.stat(file).catch(() => null);
            if (!now || now.ino !== st.ino || now.size !== st.size || now.mtimeMs !== st.mtimeMs) { await fs.unlink(tmp).catch(() => {}); }
            else { await fs.rename(tmp, file); state.stripped++; }
          } catch (e) { await fs.unlink(tmp).catch(() => {}); state.failed++; log(`media sweep: write failed for ${name}: ${e?.message ?? e}`); }
        }
      }
    } catch (e) { if (e?.code !== "ENOENT") { state.failed++; log(`media sweep: ${name}: ${e?.message ?? e}`); } }
    state.cursor = name;
    if (++inBatch >= batch) { inBatch = 0; await save().catch(() => {}); if (pauseMs > 0) await sleep(pauseMs); }
  }
  if (!signal?.aborted) state.done = true;
  await save().catch((e) => log(`media sweep: cannot save progress: ${e?.message ?? e}`));
  return summary();
}

// ---- الفيديو: هل في الحاوية موقع؟ (©xyz من أندرويد، ISO6709 من الآيفون، مفتاح location، أو GPS في XMP).
// يُستخدم لقرار «يبقى كما رُفع» فقط: الإيجابية الكاذبة تكلّف إعادة تغليف سريعة لا أكثر.
const VIDEO_LOCATION_MARKERS = [Buffer.from([0xa9, 0x78, 0x79, 0x7a]), Buffer.from("ISO6709", "latin1"), Buffer.from("location", "latin1"), Buffer.from("GPSLatitude", "latin1")];
export function videoHasLocation(buf) {
  if (!Buffer.isBuffer(buf)) return false;
  return VIDEO_LOCATION_MARKERS.some((m) => buf.indexOf(m) >= 0);
}
