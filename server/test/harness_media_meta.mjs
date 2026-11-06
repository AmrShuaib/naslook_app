// خصوصية الوسائط (server/media_meta.js + server/chat_tools.js، docs/chat.md «خصوصية الوسائط»):
//  1) المنظّف وحده على ملفات مصنوعة: JPEG فيه GPS واتجاه 6 وICC وXMP وتعليق وصورة MPF ملحقة، PNG فيه eXIf/tEXt/iTXt/zTXt/tIME،
//     WebP فيه EXIF وXMP بأعلام VP8X. يُفحص: لا GPS، الاتجاه وICC باقيان، البنية سليمة، والملف يُفك (ffmpeg إن وُجد).
//  2) الملف التالف أو غير المدعوم يعود كما هو مع error (لا يُكتب ملف تالف أبداً).
//  3) الرفع عبر /chat/upload: الصورة المخزّنة نظيفة، والفيديو والصوت بلا وسوم الموقع والعنوان مع بقاء التدوير (إن وُجد ffmpeg).
//  4) التمشيط: يمشّط القديم فقط، يكتب inode جديداً (الرابط الصلب في لقطة النسخ الاحتياطي يبقى كما هو)، يحفظ تقدّمه ولا يتكرر،
//     ويتوقف بـ NASLIFE_MEDIA_SWEEP=0، ويظهر في /chat/status.
import Fastify from 'fastify';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import zlib from 'node:zlib';
import { execFileSync } from 'node:child_process';
import pg from 'pg';
import { stripImageMeta, hasLocationMeta, readTiff, formatOf, sweepMediaMeta, videoHasLocation } from '../media_meta.js';

let fails = 0;
const check = (cond, label, extra = '') => { if (!cond) fails++; console.log((cond ? 'OK  ' : 'FAIL') + ' ' + label + (extra ? ' ' + extra : '')); };
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'naslife-meta-'));
let ffmpeg = true;
try { execFileSync('ffmpeg', ['-version'], { stdio: 'ignore' }); execFileSync('ffprobe', ['-version'], { stdio: 'ignore' }); } catch { ffmpeg = false; }
/// يُفك الملف كاملاً بـ ffmpeg (إن وُجد): نجاح بلا أخطاء = صورة صالحة
const decodes = (buf, ext) => {
  if (!ffmpeg) return true;
  const f = path.join(tmp, `decode-${Math.random().toString(36).slice(2)}.${ext}`);
  fs.writeFileSync(f, buf);
  try { execFileSync('ffmpeg', ['-v', 'error', '-xerror', '-i', f, '-f', 'null', '-'], { stdio: 'pipe' }); return true; } catch (e) { console.log('   decode error:', String(e.stderr || e.message).slice(0, 200)); return false; } finally { fs.rmSync(f, { force: true }); }
};

// ---- بناء Exif: IFD0 (اتجاه + مؤشر GPS) وIFD لـ GPS بخط عرض وطول جدة. bigEndian لتجربة الترتيبين.
const LAT = [21, 29, 8], LON = [39, 11, 33];
function tiff({ orientation = 1, gps = true, be = false } = {}) {
  const b = Buffer.alloc(200);
  const w16 = (v, o) => (be ? b.writeUInt16BE(v, o) : b.writeUInt16LE(v, o));
  const w32 = (v, o) => (be ? b.writeUInt32BE(v, o) : b.writeUInt32LE(v, o));
  b.write(be ? 'MM' : 'II', 0, 'latin1'); w16(42, 2); w32(8, 4);
  const entries = [[0x0112, 3, 1, orientation], ...(gps ? [[0x8825, 4, 1, 38]] : [])];
  w16(entries.length, 8);
  entries.forEach(([tag, type, count, val], i) => { const e = 10 + i * 12; w16(tag, e); w16(type, e + 2); w32(count, e + 4); if (type === 3) w16(val, e + 8); else w32(val, e + 8); });
  w32(0, 10 + entries.length * 12);
  if (!gps) return b.subarray(0, 14 + entries.length * 12);
  // GPS IFD عند 38: أربعة مداخل (المرجع نص قصير داخل المدخل، والقيم كسور عند 92 و116)
  const g = 38;
  w16(4, g);
  const ent = (i, tag, type, count, val) => { const e = g + 2 + i * 12; w16(tag, e); w16(type, e + 2); w32(count, e + 4); if (type === 2) b.write(val, e + 8, 'latin1'); else w32(val, e + 8); };
  ent(0, 1, 2, 2, 'N\0'); ent(1, 2, 5, 3, 92); ent(2, 3, 2, 2, 'E\0'); ent(3, 4, 5, 3, 116);
  w32(0, g + 2 + 48);
  LAT.forEach((v, i) => { w32(v, 92 + i * 8); w32(1, 96 + i * 8); });
  LON.forEach((v, i) => { w32(v, 116 + i * 8); w32(1, 120 + i * 8); });
  return b.subarray(0, 140);
}
const seg = (marker, payload) => { const h = Buffer.alloc(4); h[0] = 0xff; h[1] = marker; h.writeUInt16BE(payload.length + 2, 2); return Buffer.concat([h, payload]); };
const EXIF = Buffer.from('Exif\0\0', 'latin1');
const ICC_PAYLOAD = Buffer.concat([Buffer.from('ICC_PROFILE\0', 'latin1'), Buffer.from([1, 1]), Buffer.from('naslife-test-icc-profile-bytes', 'latin1')]);
const XMP = Buffer.from('http://ns.adobe.com/xap/1.0/\0<x:xmpmeta><rdf:Description exif:GPSLatitude="21,29.13N" exif:GPSLongitude="39,11.55E"/></x:xmpmeta>', 'latin1');
// JPEG أساسي 16×8 من ImageMagick (‎-strip): SOI ثم APP0 JFIF ثم الجداول
const BASE_JPEG = Buffer.from('/9j/4AAQSkZJRgABAQAAAAAAAAD/2wBDAAoHBwgHBgoICAgLCgoLDhgQDg0NDh0VFhEYIx8lJCIfIiEmKzcvJik0KSEiMEExNDk7Pj4+JS5ESUM8SDc9Pjv/2wBDAQoLCw4NDhwQEBw7KCIoOzs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozv/wAARCAAIABADASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAb/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAABQb/xAAYEQACAwAAAAAAAAAAAAAAAAAABkSCwv/aAAwDAQACEQMRAD8AlQE6Oocimj//2Q==', 'base64');
/// يبني JPEG مثل كاميرا جوال: Exif أولاً (بلا JFIF) ثم ICC وXMP وAPP13 وتعليق، والجداول من الأساس، وصورة MPF ملحقة بعد EOI بـ Exif خاص بها
function cameraJpeg({ orientation = 6, be = false, withJfif = false, trailer = true } = {}) {
  const body = BASE_JPEG.subarray(2 + 2 + BASE_JPEG.readUInt16BE(4)); // بعد SOI وAPP0
  const parts = [Buffer.from([0xff, 0xd8])];
  if (withJfif) parts.push(BASE_JPEG.subarray(2, 2 + 2 + BASE_JPEG.readUInt16BE(4)));
  parts.push(seg(0xe1, Buffer.concat([EXIF, tiff({ orientation, be })])), seg(0xe2, ICC_PAYLOAD), seg(0xe2, Buffer.from('MPF\0MM\0*\0\0\0\x08', 'latin1')), seg(0xe1, XMP),
    seg(0xed, Buffer.from('Photoshop 3.0\x008BIM\x04\x04\0\0\0\0\0\x10City: Jeddah home', 'latin1')), seg(0xfe, Buffer.from('shot at home 21.48,39.19', 'latin1')), body);
  if (trailer) parts.push(Buffer.from([0xff, 0xd8]), seg(0xe1, Buffer.concat([EXIF, tiff({ orientation: 1 })])), body);
  return Buffer.concat(parts);
}
const jpegSegs = (buf) => { const out = []; let p = 2; while (p + 4 <= buf.length && buf[p] === 0xff) { const m = buf[p + 1]; if (m === 0xda) { out.push({ m }); break; } const len = buf.readUInt16BE(p + 2); out.push({ m, data: buf.subarray(p + 4, p + 2 + len) }); p += 2 + len; } return out; };
const latBytes = (be) => { const b = Buffer.alloc(8); if (be) { b.writeUInt32BE(21, 0); b.writeUInt32BE(1, 4); } else { b.writeUInt32LE(21, 0); b.writeUInt32LE(1, 4); } return Buffer.concat([b, b.subarray(0, 0)]); };

// ===================== 1) JPEG
for (const be of [false, true]) {
  const src = cameraJpeg({ orientation: 6, be });
  check(hasLocationMeta(src) && formatOf(src) === 'jpeg', `jpeg fixture (${be ? 'MM' : 'II'}): carries GPS`);
  const r = stripImageMeta(src);
  const segs = jpegSegs(r.buf);
  const exif = segs.filter((s) => s.m === 0xe1);
  check(r.changed && !r.error && !hasLocationMeta(r.buf), `jpeg (${be ? 'MM' : 'II'}): GPS gone`, JSON.stringify(r.removed));
  check(exif.length === 1 && exif[0].data.subarray(0, 6).equals(EXIF) && readTiff(exif[0].data.subarray(6)).orientation === 6 && !readTiff(exif[0].data.subarray(6)).gps && exif[0].data.length === 32, `jpeg (${be ? 'MM' : 'II'}): orientation 6 kept in a 32-byte Exif with that tag only`);
  check(segs[0].m === 0xe1, 'jpeg: the orientation Exif comes right after SOI when there is no JFIF');
  check(segs.some((s) => s.m === 0xe2 && s.data.equals(ICC_PAYLOAD)) && !segs.some((s) => s.m === 0xe2 && s.data.subarray(0, 4).toString('latin1') === 'MPF\0'), 'jpeg: ICC profile kept byte for byte, MPF index dropped');
  check(!segs.some((s) => s.m === 0xed || s.m === 0xfe) && r.buf.indexOf('GPSLatitude') < 0 && r.buf.indexOf('Jeddah home') < 0 && r.buf.indexOf('shot at home') < 0, 'jpeg: XMP, APP13 (IPTC) and the comment are gone');
  check(r.buf.indexOf(latBytes(be)) < 0, 'jpeg: the GPS rational bytes are gone');
  check(r.buf[r.buf.length - 2] === 0xff && r.buf[r.buf.length - 1] === 0xd9 && r.buf.subarray(2).indexOf(Buffer.from([0xff, 0xd8])) < 0, 'jpeg: ends at the first EOI (the appended MPF image with its own Exif is dropped)');
  check(decodes(r.buf, 'jpg'), 'jpeg: output decodes');
}
{
  const src = cameraJpeg({ orientation: 1, withJfif: true, trailer: false });
  const r = stripImageMeta(src);
  const segs = jpegSegs(r.buf);
  check(r.changed && segs[0].m === 0xe0 && !segs.some((s) => s.m === 0xe1) && !hasLocationMeta(r.buf) && decodes(r.buf, 'jpg'), 'jpeg orientation 1 with JFIF: no Exif written at all, JFIF stays first');
  const r6 = stripImageMeta(cameraJpeg({ orientation: 6, withJfif: true, trailer: false }));
  const s6 = jpegSegs(r6.buf);
  check(s6[0].m === 0xe0 && s6[1].m === 0xe1 && readTiff(s6[1].data.subarray(6)).orientation === 6, 'jpeg with JFIF: the orientation Exif goes right after APP0');
  const clean = stripImageMeta(BASE_JPEG);
  check(!clean.changed && clean.buf === BASE_JPEG, 'jpeg already clean: returned untouched (same buffer)');
  // Exif بعد بيانات المسح (بين المسوحات): يُقطع لأن ترويسته معروفة؛ ومقطع بلا ترويسة معروفة هناك لا يُلمس
  const tail = BASE_JPEG.subarray(0, BASE_JPEG.length - 2), eoi = Buffer.from([0xff, 0xd9]);
  const inner = Buffer.concat([tail, seg(0xe1, Buffer.concat([EXIF, tiff({ orientation: 1 })])), eoi]);
  const ri = stripImageMeta(inner);
  check(hasLocationMeta(inner) && ri.changed && !hasLocationMeta(ri.buf) && ri.buf.equals(BASE_JPEG) && decodes(ri.buf, 'jpg'), 'jpeg: an Exif segment after the scan data is cut out (output equals the clean base)', JSON.stringify(ri.removed));
  const unknown = Buffer.concat([tail, seg(0xe5, Buffer.from('not metadata', 'latin1')), eoi]);
  const ru = stripImageMeta(unknown);
  check(!ru.changed && ru.buf === unknown, 'jpeg: an unrecognised marker inside the scan area is never cut (could be stray bytes)', JSON.stringify(ru.removed));
}
// ===================== 2) PNG
function pngChunk(type, data) { const h = Buffer.alloc(8); h.writeUInt32BE(data.length, 0); h.write(type, 4, 'latin1'); const c = Buffer.alloc(4); c.writeUInt32BE(zlib.crc32(Buffer.concat([h.subarray(4), data])) >>> 0); return Buffer.concat([h, data, c]); }
function makePng({ orientation = 6 } = {}) {
  const w = 4, hgt = 3;
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(hgt, 4); ihdr[8] = 8; ihdr[9] = 2;
  const raw = Buffer.alloc((w * 3 + 1) * hgt); for (let y = 0; y < hgt; y++) for (let x = 0; x < w; x++) raw[y * (w * 3 + 1) + 1 + x * 3] = 200;
  const xmp = Buffer.concat([Buffer.from('XML:com.adobe.xmp\0\0\0\0\0', 'latin1'), Buffer.from('<x:xmpmeta exif:GPSLatitude="21,29N"/>', 'utf8')]);
  const ztxt = Buffer.concat([Buffer.from('Raw profile type exif\0\0', 'latin1'), zlib.deflateSync(Buffer.from(`\nexif\n     140\n${Buffer.concat([EXIF, tiff({ orientation })]).toString('hex')}\n`, 'latin1'))]);
  return Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), pngChunk('IHDR', ihdr), pngChunk('sRGB', Buffer.from([0])), pngChunk('eXIf', tiff({ orientation, be: true })),
    pngChunk('tEXt', Buffer.from('Comment\0taken at home', 'latin1')), pngChunk('iTXt', xmp), pngChunk('zTXt', ztxt), pngChunk('tIME', Buffer.from([7, 234, 11, 5, 10, 0, 0])),
    pngChunk('pHYs', Buffer.from([0, 0, 11, 19, 0, 0, 11, 19, 1])), pngChunk('IDAT', zlib.deflateSync(raw)), pngChunk('IEND', Buffer.alloc(0)), Buffer.from('trailing GPS 21.48')]);
}
const pngTypes = (buf) => { const out = []; let p = 8; while (p + 12 <= buf.length) { const len = buf.readUInt32BE(p); const t = buf.toString('latin1', p + 4, p + 8); out.push({ t, data: buf.subarray(p + 8, p + 8 + len), crcOk: (zlib.crc32(buf.subarray(p + 4, p + 8 + len)) >>> 0) === buf.readUInt32BE(p + 8 + len) }); p += 12 + len; if (t === 'IEND') break; } return { out, end: p }; };
{
  const src = makePng({ orientation: 6 });
  check(hasLocationMeta(src), 'png fixture: carries GPS (eXIf)');
  { // كل قطعة نصية وحدها تكفي لاكتشاف الموقع
    const noExif = Buffer.concat(pngTypes(src).out.filter((c) => c.t !== 'eXIf' && c.t !== 'iTXt').map((c) => pngChunk(c.t, c.data)));
    check(hasLocationMeta(Buffer.concat([src.subarray(0, 8), noExif])), 'png: GPS inside a compressed «Raw profile type exif» zTXt is detected');
  }
  const r = stripImageMeta(src);
  const { out: chunks, end } = pngTypes(r.buf);
  const types = chunks.map((c) => c.t);
  check(r.changed && !r.error && !hasLocationMeta(r.buf) && !['tEXt', 'iTXt', 'zTXt', 'tIME'].some((t) => types.includes(t)), 'png: GPS gone, textual and time chunks dropped', JSON.stringify(types));
  const ex = chunks.find((c) => c.t === 'eXIf');
  check(ex && readTiff(ex.data).orientation === 6 && !readTiff(ex.data).gps && ex.crcOk && types.indexOf('eXIf') < types.indexOf('IDAT'), 'png: orientation kept in a minimal eXIf before IDAT with a valid CRC');
  check(['IHDR', 'sRGB', 'pHYs', 'IDAT', 'IEND'].every((t) => types.includes(t)) && types[0] === 'IHDR' && end === r.buf.length && chunks.every((c) => c.crcOk), 'png: other chunks kept, IHDR first, nothing after IEND, every CRC valid');
  check(decodes(r.buf, 'png'), 'png: output decodes');
  const r1 = stripImageMeta(makePng({ orientation: 1 }));
  check(r1.changed && !pngTypes(r1.buf).out.some((c) => c.t === 'eXIf'), 'png orientation 1: eXIf dropped entirely');
}
// ===================== 3) WebP
const BASE_WEBP = Buffer.from('UklGRjoAAABXRUJQVlA4IC4AAADQAQCdASoQAAgAAgA0JaACdLoB+AADsAD+8Nvpf+QXLC65Gv/NgfyA8uv+LmAA', 'base64');
function riffChunk(fourcc, data) { const h = Buffer.alloc(8); h.write(fourcc, 0, 'latin1'); h.writeUInt32LE(data.length, 4); return Buffer.concat([h, data, data.length & 1 ? Buffer.alloc(1) : Buffer.alloc(0)]); }
function makeWebp({ orientation = 1, exifPrefix = false } = {}) {
  const vp8 = BASE_WEBP.subarray(12);
  const vp8x = Buffer.alloc(10); vp8x[0] = 0x08 | 0x04; vp8x.writeUIntLE(16 - 1, 4, 3); vp8x.writeUIntLE(8 - 1, 7, 3);
  const exif = exifPrefix ? Buffer.concat([EXIF, tiff({ orientation })]) : tiff({ orientation });
  const body = Buffer.concat([riffChunk('VP8X', vp8x), vp8, riffChunk('EXIF', exif), riffChunk('XMP ', Buffer.from('<x:xmpmeta exif:GPSLatitude="21,29N"/>', 'latin1'))]);
  const head = Buffer.alloc(12); head.write('RIFF', 0, 'latin1'); head.writeUInt32LE(4 + body.length, 4); head.write('WEBP', 8, 'latin1');
  return Buffer.concat([head, body]);
}
const webpChunks = (buf) => { const out = []; let p = 12; const end = 8 + buf.readUInt32LE(4); while (p + 8 <= end) { const f = buf.toString('latin1', p, p + 4), len = buf.readUInt32LE(p + 4); out.push({ f, data: buf.subarray(p + 8, p + 8 + len) }); p += 8 + len + (len & 1); } return { out, end, size: buf.length }; };
{
  const src = makeWebp({ orientation: 1 });
  check(hasLocationMeta(src) && formatOf(src) === 'webp', 'webp fixture: carries GPS (EXIF chunk)');
  const r = stripImageMeta(src);
  const { out, end, size } = webpChunks(r.buf);
  check(r.changed && !r.error && !hasLocationMeta(r.buf) && !out.some((c) => c.f === 'EXIF' || c.f === 'XMP '), 'webp: EXIF and XMP chunks dropped', JSON.stringify(out.map((c) => c.f)));
  check((out[0].data[0] & 0x0c) === 0 && end === size, 'webp: VP8X Exif/XMP flags cleared and the RIFF size matches the file');
  check(decodes(r.buf, 'webp'), 'webp: output decodes');
  const r6 = stripImageMeta(makeWebp({ orientation: 6, exifPrefix: true }));
  const c6 = webpChunks(r6.buf).out;
  const e6 = c6.find((c) => c.f === 'EXIF');
  check(e6 && readTiff(e6.data).orientation === 6 && !readTiff(e6.data).gps && (c6[0].data[0] & 0x08) === 0x08 && (c6[0].data[0] & 0x04) === 0 && !hasLocationMeta(r6.buf), 'webp orientation 6 (Exif-prefixed): minimal EXIF kept with its flag, XMP flag cleared');
  check(!stripImageMeta(BASE_WEBP).changed, 'webp without metadata: untouched');
}
// ===================== 4) مدخلات تالفة وغير مدعومة
{
  const src = cameraJpeg();
  const cut = src.subarray(0, 300);
  const r = stripImageMeta(cut);
  check(!r.changed && r.buf === cut && typeof r.error === 'string', 'truncated jpeg: original returned with an error, nothing rewritten', r.error);
  const badPng = Buffer.from(makePng()); badPng.writeUInt32BE(0x7fffffff, 8 + 8 + 13 + 4 + 12 + 1 + 0); // طول مستحيل لقطعة بعد IHDR
  const rp = stripImageMeta(badPng);
  check(!rp.changed && rp.error, 'corrupt png chunk length: original returned with an error', rp.error);
  const gif = Buffer.from('GIF89a\x01\x00\x01\x00\x00\x00\x00;', 'latin1');
  check(!stripImageMeta(gif).changed && formatOf(gif) === 'gif' && !hasLocationMeta(gif), 'gif: nothing to do');
  check(!stripImageMeta(Buffer.from('not an image at all')).changed && !hasLocationMeta(Buffer.from('xx')), 'unknown bytes: untouched');
  check(videoHasLocation(Buffer.from('....\xa9xyz+21.4858+039.1925/', 'latin1')) && videoHasLocation(Buffer.from('com.apple.quicktime.location.ISO6709', 'latin1')) && !videoHasLocation(Buffer.from('ftypisommoov')), 'videoHasLocation: Android ©xyz and Apple ISO6709 detected, plain moov not');
}

// ===================== 5) الرفع عبر /chat/upload
process.env.CHAT_MEDIA_DIR = path.join(tmp, 'media');
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
const auth = async (req) => req.headers['x-user'] || null;
const logs = [];
const makeApp = async (opts = {}) => {
  const app = Fastify({ bodyLimit: 40 * 1024 * 1024, logger: { level: 'info', stream: { write: (s) => { try { logs.push(JSON.parse(s).msg ?? s); } catch { logs.push(s); } } } } });
  await app.register((await import('../chat_tools.js')).default, { pool, auth, ...opts });
  await app.ready();
  return app;
};
const upload = async (app, buf, type) => { const r = await app.inject({ method: 'POST', url: '/chat/upload', headers: { 'content-type': type, 'x-user': 'SA0000001' }, payload: buf }); return { code: r.statusCode, json: r.json() }; };
const storedOf = (url) => fs.readFileSync(path.join(process.env.CHAT_MEDIA_DIR, url.split('/').pop()));
// ملفات «قديمة» قبل الإقلاع (اسم بختم زمني أقدم) للتمشيط في القسم 6
fs.mkdirSync(process.env.CHAT_MEDIA_DIR, { recursive: true });
const oldName = (i, ext) => `${(Date.now() - 86400000 * (10 - i)).toString(36)}-${'ab'.repeat(12)}.${ext}`.replace('abab', 'ab' + String(i).padStart(2, '0'));
const old = { jpg: oldName(1, 'jpg'), png: oldName(2, 'png'), webp: oldName(3, 'webp'), clean: oldName(4, 'jpg'), broken: oldName(5, 'jpg') };
fs.writeFileSync(path.join(process.env.CHAT_MEDIA_DIR, old.jpg), cameraJpeg({ orientation: 6 }));
fs.writeFileSync(path.join(process.env.CHAT_MEDIA_DIR, old.png), makePng());
fs.writeFileSync(path.join(process.env.CHAT_MEDIA_DIR, old.webp), makeWebp());
fs.writeFileSync(path.join(process.env.CHAT_MEDIA_DIR, old.clean), BASE_JPEG);
fs.writeFileSync(path.join(process.env.CHAT_MEDIA_DIR, old.broken), cameraJpeg().subarray(0, 300));
// لقطة نسخ احتياطي بروابط صلبة (rsync --link-dest): يجب ألا تتغير
const snap = path.join(tmp, 'snapshot'); fs.mkdirSync(snap);
fs.linkSync(path.join(process.env.CHAT_MEDIA_DIR, old.jpg), path.join(snap, old.jpg));
const inodeBefore = fs.statSync(path.join(process.env.CHAT_MEDIA_DIR, old.jpg)).ino;

let app = await makeApp({ metaSweep: { enabled: false } });
{
  let r = await upload(app, cameraJpeg({ orientation: 6 }), 'image/jpeg');
  const st = r.code === 200 ? storedOf(r.json.url) : Buffer.alloc(0);
  check(r.code === 200 && r.json.kind === 'image' && !hasLocationMeta(st) && r.json.size === st.length, 'upload jpeg: stored without GPS, size reported for the clean file', JSON.stringify(r.json));
  check(readTiff(jpegSegs(st).find((s) => s.m === 0xe1).data.subarray(6)).orientation === 6 && jpegSegs(st).some((s) => s.m === 0xe2 && s.data.equals(ICC_PAYLOAD)), 'upload jpeg: orientation and ICC survive');
  r = await upload(app, makePng(), 'image/png');
  check(r.code === 200 && !hasLocationMeta(storedOf(r.json.url)) && storedOf(r.json.url).indexOf('taken at home') < 0, 'upload png: stored without eXIf GPS or text chunks');
  r = await upload(app, makeWebp(), 'image/webp');
  check(r.code === 200 && !hasLocationMeta(storedOf(r.json.url)), 'upload webp: stored without EXIF/XMP');
  // صورة مسمّاة خطأً: النوع من البايتات لا من الترويسة
  r = await upload(app, makePng(), 'image/jpeg');
  check(r.code === 200 && !hasLocationMeta(storedOf(r.json.url)), 'upload: a PNG labelled image/jpeg is still cleaned (format from magic bytes)');
  const cut = cameraJpeg().subarray(0, 300);
  logs.length = 0;
  r = await upload(app, cut, 'image/jpeg');
  check(r.code === 200 && storedOf(r.json.url).equals(cut) && logs.some((l) => l.includes('image metadata kept')), 'upload of an unparseable jpeg: stored as sent (never a corrupt rewrite) and logged');
  r = await app.inject({ method: 'GET', url: '/chat/status' });
  check(r.json().metaStrip === true && r.json().metaSweep?.enabled === false, '/chat/status reports the image cleaner and the sweep switch', JSON.stringify(r.json().metaSweep));
  check(typeof globalThis.naslifeStripImageMeta === 'function', 'cleaner shared on globalThis for other plugins');
}

if (ffmpeg) {
  const gen = (name, args) => { const f = path.join(tmp, name); execFileSync('ffmpeg', ['-y', '-hide_banner', '-loglevel', 'error', ...args, f]); return f; };
  const tags = (file) => JSON.parse(execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'format_tags:stream_tags:stream_side_data=rotation', '-of', 'json', file]).toString());
  const tagText = (j) => JSON.stringify(j);
  const lavfi = (size, sec) => ['-f', 'lavfi', '-i', `testsrc=size=${size}:rate=15:duration=${sec}`, '-f', 'lavfi', '-i', `sine=duration=${sec}`];
  const locTags = ['-metadata', 'location=+21.4858+039.1925/', '-metadata', 'com.apple.quicktime.location.ISO6709=+21.4858+039.1925+000.000/', '-metadata', 'title=بيتي في الروضة'];
  // MP4 خفيف (يبقى كما رُفع لولا الموقع) بتدوير 90
  const base = gen('light.mp4', [...lavfi('320x240', 1), '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-shortest', ...locTags, '-movflags', '+faststart+use_metadata_tags']);
  const light = gen('light_rot.mp4', ['-display_rotation', '90', '-i', base, '-c', 'copy', '-movflags', '+faststart+use_metadata_tags']);
  check(tagText(tags(light)).includes('21.4858') && tags(light).streams[0].side_data_list?.[0]?.rotation === 90, 'fixture: light mp4 with location tags and rotation 90');
  let r = await upload(app, fs.readFileSync(light), 'video/mp4');
  let f = path.join(process.env.CHAT_MEDIA_DIR, r.json.url.split('/').pop());
  let t = tags(f);
  check(r.code === 200 && !tagText(t).includes('21.4858') && !tagText(t).includes('الروضة') && !videoHasLocation(fs.readFileSync(f)), 'upload light mp4 with location: remuxed without location or title tags', tagText(t).slice(0, 200));
  check(t.streams.find((s) => s.side_data_list)?.side_data_list?.[0]?.rotation === 90, 'upload light mp4: rotation side data kept (-map_metadata -1 keeps the display matrix)');
  // MP4 خفيف بلا موقع: يبقى كما رُفع (لا تكلفة إضافية)
  const plain = gen('plain.mp4', [...lavfi('320x240', 1), '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-shortest', '-movflags', '+faststart']);
  logs.length = 0;
  r = await upload(app, fs.readFileSync(plain), 'video/mp4');
  check(r.code === 200 && fs.readFileSync(path.join(process.env.CHAT_MEDIA_DIR, r.json.url.split('/').pop())).equals(fs.readFileSync(plain)), 'upload light mp4 without location: kept byte for byte (no extra remux)');
  // MOV (إعادة تغليف) وفيديو يحتاج ترميزاً
  const mov = gen('loc.mov', [...lavfi('320x240', 1), '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-shortest', ...locTags, '-movflags', '+use_metadata_tags']);
  r = await upload(app, fs.readFileSync(mov), 'video/quicktime');
  f = path.join(process.env.CHAT_MEDIA_DIR, r.json.url.split('/').pop());
  check(r.code === 200 && r.json.url.endsWith('.mp4') && !tagText(tags(f)).includes('21.4858'), 'upload mov with location: remuxed to mp4 without location');
  const big = gen('big.mp4', [...lavfi('1280x960', 1), '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-shortest', ...locTags, '-movflags', '+use_metadata_tags']);
  r = await upload(app, fs.readFileSync(big), 'video/mp4');
  f = path.join(process.env.CHAT_MEDIA_DIR, r.json.url.split('/').pop());
  check(r.code === 200 && !tagText(tags(f)).includes('21.4858') && !tagText(tags(f)).includes('الروضة'), 'upload video that needs encoding: encoded without location or title');
  // الصوت: m4a بوسم عنوان (اسم شارع) وwebm يُرمَّز
  const m4a = gen('memo.m4a', ['-f', 'lavfi', '-i', 'sine=duration=1', '-c:a', 'aac', '-metadata', 'title=شارع التحلية', '-metadata', 'location=+21.4858+039.1925/', '-movflags', '+use_metadata_tags']);
  check(tagText(tags(m4a)).includes('التحلية'), 'fixture: m4a voice memo titled with a street name');
  r = await upload(app, fs.readFileSync(m4a), 'audio/mp4');
  f = path.join(process.env.CHAT_MEDIA_DIR, r.json.url.split('/').pop());
  check(r.code === 200 && r.json.kind === 'audio' && r.json.url.endsWith('.m4a') && !tagText(tags(f)).includes('التحلية') && !tagText(tags(f)).includes('21.4858') && Array.isArray(r.json.peaks), 'upload m4a: copied without title/location tags, waveform still computed');
  const weba = gen('note.webm', ['-f', 'lavfi', '-i', 'sine=duration=1', '-c:a', 'libopus', '-metadata', 'title=شارع التحلية']);
  r = await upload(app, fs.readFileSync(weba), 'audio/webm');
  f = path.join(process.env.CHAT_MEDIA_DIR, r.json.url.split('/').pop());
  check(r.code === 200 && r.json.type === 'audio/mp4' && !tagText(tags(f)).includes('التحلية'), 'upload webm voice note: transcoded to m4a without tags');
} else console.log('SKIP video/audio checks: ffmpeg not installed');
await app.close();

// ===================== 6) التمشيط
{
  // دالة التمشيط وحدها: دفعات من ملفين بلا توقف
  const dir = process.env.CHAT_MEDIA_DIR;
  const NAME_RE = /^[a-z0-9]{6,16}-[a-f0-9]{24}\.[a-z0-9]{2,5}$/;
  const before = Date.now().toString(36);
  // ملف «جديد» بعد الإقلاع لا يُمشَّط (نُظّف عند الرفع)
  const fresh = `${(Date.now() + 60000).toString(36)}-${'cd'.repeat(12)}.jpg`;
  fs.writeFileSync(path.join(dir, fresh), cameraJpeg());
  const msgs = [];
  const r = await sweepMediaMeta({ dir, nameRe: NAME_RE, batch: 2, pauseMs: 0, before, log: (m) => msgs.push(m) });
  check(r.done && r.located === 3 && r.stripped === 3 && r.failed === 0, 'sweep: the three old files with GPS stripped; the unparseable one is not touched', JSON.stringify(r));
  for (const k of ['jpg', 'png', 'webp']) check(!hasLocationMeta(fs.readFileSync(path.join(dir, old[k]))), `sweep: old ${k} no longer carries GPS`);
  check(fs.readFileSync(path.join(dir, old.clean)).equals(BASE_JPEG), 'sweep: a clean old file is not rewritten');
  check(fs.readFileSync(path.join(dir, old.broken)).equals(cameraJpeg().subarray(0, 300)), 'sweep: the unparseable file is untouched (never a corrupt write)');
  check(hasLocationMeta(fs.readFileSync(path.join(dir, fresh))), 'sweep: files named after the boot cutoff are skipped (cleaned at upload)');
  const newIno = fs.statSync(path.join(dir, old.jpg)).ino;
  check(newIno !== inodeBefore && hasLocationMeta(fs.readFileSync(path.join(snap, old.jpg))) && fs.statSync(path.join(snap, old.jpg)).ino === inodeBefore, 'sweep: temp file + rename gives a new inode; the backup snapshot hard link keeps its old inode untouched');
  check(readTiff(jpegSegs(fs.readFileSync(path.join(dir, old.jpg))).find((s) => s.m === 0xe1).data.subarray(6)).orientation === 6, 'sweep: orientation kept on the rewritten jpeg');
  check(!fs.readdirSync(dir).some((n) => n.endsWith('.sweep') || n.endsWith('.tmp')), 'sweep: no temp files left behind');
  const state = JSON.parse(fs.readFileSync(path.join(dir, '.meta-sweep.json'), 'utf8'));
  check(state.done === true && state.version === 1 && state.stripped === 3, 'sweep: progress saved in .meta-sweep.json');
  const again = await sweepMediaMeta({ dir, nameRe: NAME_RE, batch: 2, pauseMs: 0, before: (Date.now() + 120000).toString(36) });
  check(again.skipped === true && fs.statSync(path.join(dir, old.jpg)).ino === newIno && hasLocationMeta(fs.readFileSync(path.join(dir, fresh))), 'sweep: never repeats once done (even with a later cutoff)');
  // استئناف بعد توقف: إيقاف عبر signal ثم إكمال من المؤشر
  const dir2 = path.join(tmp, 'media2'); fs.mkdirSync(dir2);
  const names2 = [1, 2, 3, 4].map((i) => oldName(i, 'jpg'));
  for (const n of names2) fs.writeFileSync(path.join(dir2, n), cameraJpeg());
  const ac = new AbortController();
  let seen = 0;
  const part = await sweepMediaMeta({ dir: dir2, nameRe: NAME_RE, batch: 1, pauseMs: 1, before, log: () => {}, signal: { get aborted() { return ++seen > 2; } } });
  void ac;
  const st2 = JSON.parse(fs.readFileSync(path.join(dir2, '.meta-sweep.json'), 'utf8'));
  check(!part.done && st2.done === false && st2.cursor && st2.cursor < names2[3], 'sweep: stopping early keeps the cursor and done=false', JSON.stringify(st2));
  const rest = await sweepMediaMeta({ dir: dir2, nameRe: NAME_RE, batch: 10, pauseMs: 0, before });
  check(rest.done && rest.stripped === 4 && names2.every((n) => !hasLocationMeta(fs.readFileSync(path.join(dir2, n)))), 'sweep: resumes from the cursor and finishes (no file stripped twice)', JSON.stringify(rest));
}
// التمشيط من الإضافة: يعمل بعد المهلة ويظهر في /chat/status، ويتوقف بـ NASLIFE_MEDIA_SWEEP=0
{
  const dir = path.join(tmp, 'media3'); fs.mkdirSync(dir);
  process.env.CHAT_MEDIA_DIR = dir;
  const n = oldName(1, 'jpg');
  fs.writeFileSync(path.join(dir, n), cameraJpeg());
  process.env.NASLIFE_MEDIA_SWEEP = '0';
  let a = await makeApp({ metaSweep: { delayMs: 5 } });
  await new Promise((r) => setTimeout(r, 200));
  let s = (await a.inject({ method: 'GET', url: '/chat/status' })).json().metaSweep;
  check(s.enabled === false && hasLocationMeta(fs.readFileSync(path.join(dir, n))), 'NASLIFE_MEDIA_SWEEP=0: no sweep, old file untouched');
  await a.close();
  delete process.env.NASLIFE_MEDIA_SWEEP;
  logs.length = 0;
  a = await makeApp({ metaSweep: { delayMs: 5, pauseMs: 0 } });
  for (let i = 0; i < 50; i++) { s = (await a.inject({ method: 'GET', url: '/chat/status' })).json().metaSweep; if (s.done) break; await new Promise((r) => setTimeout(r, 50)); }
  check(s.enabled === true && s.done === true && s.stripped === 1 && !hasLocationMeta(fs.readFileSync(path.join(dir, n))) && logs.some((l) => l.includes('media sweep done: scanned 1, with location 1, stripped 1')), 'plugin sweep: runs after the delay, strips, logs a summary and reports in /chat/status', JSON.stringify(s));
  await a.close();
}

fs.rmSync(tmp, { recursive: true, force: true });
await pool.end();
console.log(fails ? `\n${fails} FAILED` : '\nALL MEDIA META TESTS PASSED');
process.exit(fails ? 1 : 0);
