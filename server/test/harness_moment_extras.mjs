// اختبارات إضافات عارض «اللحظات» (docs/moments.md):
//  1) قرار «الفيديو الخفيف» دالةً نقية (videoArgs/previewArgs) ثم بترميز حقيقي إن وُجد ffmpeg: 1080p ومعدّل عالٍ و60 إطاراً وعمودي
//     ومدوَّر وHEVC وVP9 تُرمَّز إلى H.264 ≤720p بإطار مرجعي كل ثانية، و720p الخفيف يبقى كما هو؛ ومعاينة /chat/vpreview 360p لست ثوانٍ.
//  2) التفاعلات (server/moment_extras.js): ضبط وتغيير وإزالة، العدّادات، الضيف، 401، 403 للحظر، 404 للمخفي، حدّ الإشعار بالساعة، ولا إشعار لنفسي.
//  3) رابط المشاركة /m/:id (share.js): وسوم Open Graph وتحويل إلى /#/m/<id>.
//  4) «محفوظاتي» (wishlist.js): صورة لحظة الفيديو من /chat/thumb، والكنس في map_posts.js يُبقي اللحظة المحفوظة.
import Fastify from 'fastify';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import pg from 'pg';
import { videoArgs, previewArgs, LIGHT_VIDEO, VIDEO_PREVIEW } from '../chat_tools.js';
import { MOMENT_REACTIONS, cleanEmoji } from '../moment_extras.js';
import { postImage } from '../wishlist.js';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0';
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'naslife-moments-'));
process.env.CHAT_MEDIA_DIR = path.join(tmp, 'media_store');
let fails = 0;
const check = (cond, label, extra = '') => { if (!cond) fails++; console.log((cond ? 'OK  ' : 'FAIL') + ' ' + label + (extra ? ' ' + extra : '')); };
const argOf = (args, flag) => { const i = args.indexOf(flag); return i >= 0 ? args[i + 1] : undefined; };

// ===================== 1) قرار الفيديو الخفيف (بلا ffmpeg)
const pr = (v, a, fmt = {}) => ({ video: v, audio: a, format: fmt });
const h264 = (w, h, fps = '30/1', pix = 'yuv420p') => ({ codec_type: 'video', codec_name: 'h264', width: w, height: h, avg_frame_rate: fps, r_frame_rate: fps, pix_fmt: pix });
const aac = { codec_type: 'audio', codec_name: 'aac' };
let d = videoArgs(pr(h264(1920, 1080), aac, { bit_rate: '8000000' }), 'mp4');
check(!d.keep && !d.copy && d.reasons.includes('size') && d.reasons.includes('bitrate'), '1080p h264 8Mbps → re-encode (size, bitrate)', JSON.stringify(d.reasons));
check(argOf(d.args, '-c:v') === 'libx264' && argOf(d.args, '-preset') === 'veryfast' && argOf(d.args, '-crf') === '26' && argOf(d.args, '-maxrate') === '2M' && argOf(d.args, '-bufsize') === '4M',
  'encode: libx264 veryfast crf 26, maxrate 2M bufsize 4M', d.args.join(' '));
check(argOf(d.args, '-g') === '30' && argOf(d.args, '-keyint_min') === '30' && argOf(d.args, '-sc_threshold') === '0' && argOf(d.args, '-pix_fmt') === 'yuv420p', 'encode: keyframe every second (-g 30 -keyint_min 30 -sc_threshold 0), yuv420p');
check(argOf(d.args, '-c:a') === 'aac' && argOf(d.args, '-b:a') === '96k', 'encode: aac 96k');
check(/min\(1280,iw\)/.test(argOf(d.args, '-vf')) && /min\(720,ih\)/.test(argOf(d.args, '-vf')) && /force_original_aspect_ratio=decrease/.test(argOf(d.args, '-vf')) && !/fps=/.test(argOf(d.args, '-vf')), 'encode: 720p box by orientation, no fps filter at 30fps', argOf(d.args, '-vf'));
d = videoArgs(pr(h264(1280, 720), aac, { bit_rate: '1500000' }), 'mp4');
check(d.keep && d.copy && !d.reasons.length && !d.args.length, '720p h264 low bitrate .mp4 → kept as is', JSON.stringify(d));
d = videoArgs(pr(h264(720, 1280), null, { bit_rate: '2900000' }), 'mp4');
check(d.keep, '720p portrait h264 without audio under 3Mbps → kept');
d = videoArgs(pr(h264(1280, 720), aac, { bit_rate: '1500000' }), 'mov');
check(!d.keep && d.copy && d.args.join(' ') === '-c copy', '720p h264 .mov → remux only (-c copy)', JSON.stringify(d));
d = videoArgs(pr({ ...h264(1280, 720), codec_name: 'hevc' }, aac, { bit_rate: '1000000' }), 'mp4');
check(!d.copy && JSON.stringify(d.reasons) === '["codec"]', 'hevc → re-encode (codec)', JSON.stringify(d.reasons));
d = videoArgs(pr({ ...h264(640, 360), codec_name: 'vp9' }, { codec_type: 'audio', codec_name: 'opus' }, { bit_rate: '600000' }), 'webm');
check(!d.copy && d.reasons.includes('codec') && d.reasons.includes('audio') && !d.reasons.includes('size'), 'webm vp9/opus → re-encode (codec, audio)', JSON.stringify(d.reasons));
d = videoArgs(pr(h264(640, 360), aac, { bit_rate: '5000000' }), 'mp4');
check(!d.copy && JSON.stringify(d.reasons) === '["bitrate"]', 'small but 5Mbps → re-encode (bitrate)', JSON.stringify(d.reasons));
d = videoArgs(pr(h264(640, 360), aac, {}), 'mp4');
check(d.keep, 'unknown bitrate does not force a re-encode');
d = videoArgs(pr({ ...h264(640, 360), bit_rate: '4000000' }, aac, {}), 'mp4');
check(!d.copy && d.reasons.includes('bitrate'), 'stream bit_rate used when the container has none');
d = videoArgs(pr(h264(1920, 1080, '60/1'), aac, { bit_rate: '9000000' }), 'mp4');
check(/^fps=30,/.test(argOf(d.args, '-vf')) && argOf(d.args, '-g') === '30', '60fps → fps capped at 30, gop 30', argOf(d.args, '-vf'));
d = videoArgs(pr(h264(1920, 1080, '24000/1001'), aac, { bit_rate: '9000000' }), 'mp4');
check(!/fps=/.test(argOf(d.args, '-vf')) && argOf(d.args, '-g') === '24', '23.976fps kept, keyframe every second (gop 24)', argOf(d.args, '-g'));
d = videoArgs(pr(h264(1280, 720, '30/1', 'yuv420p10le'), aac, { bit_rate: '1000000' }), 'mp4');
check(!d.copy && JSON.stringify(d.reasons) === '["pix_fmt"]', '10-bit h264 → re-encode (pix_fmt)');
d = videoArgs(pr(h264(1300, 700), aac, { bit_rate: '1000000' }), 'mp4');
check(!d.copy && d.reasons.includes('size'), 'long side over 1280 → re-encode (size)');
const pa = previewArgs(pr(h264(1920, 1080, '60/1'), aac));
check(argOf(pa, '-t') === '6' && pa.includes('-an') && argOf(pa, '-crf') === '30' && argOf(pa, '-movflags') === '+faststart' && /^fps=30,/.test(argOf(pa, '-vf')) && /min\(640,iw\)/.test(argOf(pa, '-vf')) && /min\(360,ih\)/.test(argOf(pa, '-vf')),
  'preview args: first 6s, muted, crf 30, 360p box, faststart', pa.join(' '));
check(LIGHT_VIDEO.maxShort === 720 && LIGHT_VIDEO.maxBitrate === 3000000 && VIDEO_PREVIEW.seconds === 6, 'exported limits');
check(JSON.stringify(MOMENT_REACTIONS) === JSON.stringify(['😍', '😂', '🔥', '👏']) && cleanEmoji('👏️') === '👏' && cleanEmoji(null) === null && cleanEmoji('  ') === null, 'reaction set and emoji cleaning');
const vName = 'mtyvideo1-' + 'a'.repeat(24) + '.mp4', iName = 'mtyimage1-' + 'b'.repeat(24) + '.jpg';
check(postImage({ kind: 'video', media_url: `https://naslife.app/chat/media/${vName}` }) === `/chat/thumb/${vName}` && postImage({ kind: 'image', media_url: `https://naslife.app/chat/media/${iName}` }) === `https://naslife.app/chat/media/${iName}`
  && postImage({ kind: 'video', media_url: 'https://other.example/v.mp4' }) === null && postImage({ kind: 'text', media_url: null }) === null, 'postImage: image itself, video thumb, foreign video none');

// ===================== الخادم
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("INSERT INTO users(id,nickname) VALUES('SA0000001','amr'),('SA0000002','sara'),('SA0000003','khalid'),('SA0000004','noura') ON CONFLICT (id) DO UPDATE SET nickname=EXCLUDED.nickname");
await pool.query("CREATE TABLE IF NOT EXISTS user_blocks (user_id TEXT NOT NULL, blocked_id TEXT NOT NULL, created_at TIMESTAMPTZ DEFAULT now(), PRIMARY KEY (user_id, blocked_id))");
for (const sql of ['DELETE FROM user_blocks', 'DROP TABLE IF EXISTS map_post_reactions, map_post_react_notified, wishlist_items', 'DROP TABLE IF EXISTS map_post_likes, map_post_views, map_posts', 'DELETE FROM app_notifications', 'DELETE FROM user_flags']) { try { await pool.query(sql); } catch { /* أول تشغيل */ } }
const auth = async (req) => req.headers['x-user'] || null;
const dir = new URL('.', import.meta.url).pathname;
const app = Fastify({ bodyLimit: 40 * 1024 * 1024 });
app.register((await import('../notify.js')).default, { pool, auth, pollMs: 3600000, opsDir: dir + 'ops' });
app.register((await import('../chat_tools.js')).default, { pool, auth });
app.register((await import('../map_posts.js')).default, { pool, auth });
app.register((await import('../moment_extras.js')).default, { pool, auth, sweepMs: 0 });
app.register((await import('../wishlist.js')).default, { pool, auth, sweepMs: 0 });
app.register((await import('../safety.js')).default, { pool, auth });
app.register((await import('../share.js')).default, { pool, auth, webappDir: path.join(tmp, 'webapp') });
await app.ready(); await new Promise((r) => setTimeout(r, 600));
const call = async (method, url, { body, user = 'SA0000001', expect, headers = {} } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), ...(body !== undefined ? { 'content-type': 'application/json' } : {}), host: 'naslife.app', 'x-forwarded-proto': 'https', ...headers }, payload: body === undefined ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url} -> ${r.statusCode}`, r.statusCode === expect ? '' : JSON.stringify(j).slice(0, 160));
  return j;
};
const notes = async (uid = 'SA0000002') => (await pool.query("SELECT kind, title, data FROM app_notifications WHERE user_id=$1 AND kind='moment_react' ORDER BY created_at", [uid])).rows;

// ===================== 1-ب) ترميز حقيقي ومعاينة (إن وُجد ffmpeg)
let ffmpeg = true;
try { execFileSync('ffmpeg', ['-version'], { stdio: 'ignore' }); execFileSync('ffprobe', ['-version'], { stdio: 'ignore' }); } catch { ffmpeg = false; }
const st = await call('GET', '/chat/status', { user: null, expect: 200 });
check(st.vpreview === ffmpeg && st.transcode === ffmpeg, 'status: vpreview flag follows ffmpeg', JSON.stringify(st));
if (!ffmpeg) console.log('SKIP real encoding: ffmpeg not installed');
else {
  const encoders = execFileSync('ffmpeg', ['-hide_banner', '-encoders']).toString();
  const gen = (name, lavfi, args) => { const f = path.join(tmp, name); execFileSync('ffmpeg', ['-y', '-hide_banner', '-loglevel', 'error', ...lavfi, ...args, f]); return f; };
  const src = (size, rate, sec = 3) => ['-f', 'lavfi', '-i', `testsrc2=size=${size}:rate=${rate}:duration=${sec}`];
  const tone = (sec = 3) => ['-f', 'lavfi', '-i', `sine=frequency=440:duration=${sec}`];
  const probe = (file) => {
    const j = JSON.parse(execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'stream=codec_type,codec_name,width,height,avg_frame_rate,pix_fmt:format=duration,bit_rate', '-of', 'json', file]).toString());
    const v = j.streams.find((s) => s.codec_type === 'video'), a = j.streams.find((s) => s.codec_type === 'audio');
    const [n, dd] = String(v?.avg_frame_rate ?? '0/1').split('/').map(Number);
    return { v: v?.codec_name, a: a?.codec_name ?? null, w: v?.width, h: v?.height, fps: dd ? n / dd : n, pix: v?.pix_fmt, dur: Number(j.format?.duration), br: Number(j.format?.bit_rate) };
  };
  const keyGaps = (file) => {
    const t = execFileSync('ffprobe', ['-v', 'error', '-select_streams', 'v:0', '-skip_frame', 'nokey', '-show_entries', 'frame=pts_time', '-of', 'csv=p=0', file]).toString().trim().split('\n').map((l) => parseFloat(l)).filter(Number.isFinite);
    return t.slice(1).map((x, i) => x - t[i]);
  };
  const faststart = (file) => { const b = fs.readFileSync(file); const moov = b.indexOf('moov'), mdat = b.indexOf('mdat'); return moov > 0 && mdat > 0 && moov < mdat; };
  const stored = (url) => path.join(process.env.CHAT_MEDIA_DIR, url.split('/').pop());
  const upload = async (file, type) => {
    const r = await app.inject({ method: 'POST', url: '/chat/upload', headers: { 'x-user': 'SA0000002', 'content-type': type }, payload: fs.readFileSync(file) });
    return { code: r.statusCode, body: r.json() };
  };

  const big = gen('big1080p60.mp4', [...src('1920x1080', 60), ...tone()], ['-map', '0:v', '-map', '1:a', '-c:v', 'libx264', '-preset', 'ultrafast', '-b:v', '8M', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-shortest']);
  check(probe(big).br > 3000000 && probe(big).fps === 60, 'fixture: 1080p60 h264 over 3Mbps', JSON.stringify(probe(big)));
  let r = await upload(big, 'video/mp4');
  check(r.code === 200 && r.body.type === 'video/mp4' && r.body.size < fs.statSync(big).size, '1080p60 upload re-encoded and lighter', `${fs.statSync(big).size} → ${r.body.size}`);
  let p = probe(stored(r.body.url));
  check(p.v === 'h264' && p.a === 'aac' && p.w === 1280 && p.h === 720 && Math.round(p.fps) === 30 && p.pix === 'yuv420p', '→ h264/aac 1280x720 at 30fps yuv420p', JSON.stringify(p));
  check(p.br < 2600000, 'bitrate held near the 2M cap', String(p.br));
  const gaps = keyGaps(stored(r.body.url));
  check(gaps.length >= 2 && gaps.every((g) => g <= 1.01), 'keyframe every second', JSON.stringify(gaps));
  check(faststart(stored(r.body.url)), 'faststart (moov before mdat)');
  const bigUrl = r.body.url;

  const tall = gen('portrait.mp4', src('1080x1920', 30, 2), ['-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '30', '-pix_fmt', 'yuv420p']);
  r = await upload(tall, 'video/mp4');
  p = probe(stored(r.body.url));
  check(p.w === 720 && p.h === 1280 && p.a === null, 'portrait 1080x1920 → 720x1280 (no audio stream invented)', JSON.stringify(p));

  const land = gen('land.mp4', src('1920x1080', 30, 2), ['-c:v', 'libx264', '-preset', 'ultrafast', '-crf', '30', '-pix_fmt', 'yuv420p']);
  const rot = path.join(tmp, 'rotated.mov');
  let rotated = true;
  try { execFileSync('ffmpeg', ['-y', '-hide_banner', '-loglevel', 'error', '-display_rotation', '90', '-i', land, '-c', 'copy', rot]); } catch { rotated = false; }
  if (rotated) {
    r = await upload(rot, 'video/quicktime');
    p = probe(stored(r.body.url));
    check(r.body.url.endsWith('.mp4') && p.w === 720 && p.h === 1280, 'iPhone-style rotated 1920x1080 .mov (shown portrait) → 720x1280, not shrunk to 405x720', JSON.stringify(p));
  } else console.log('SKIP rotation fixture: this ffmpeg has no -display_rotation');

  const light = gen('light720.mp4', [...src('1280x720', 30), ...tone()], ['-map', '0:v', '-map', '1:a', '-c:v', 'libx264', '-preset', 'veryfast', '-b:v', '700k', '-maxrate', '900k', '-bufsize', '1800k', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '64k', '-shortest', '-movflags', '+faststart']);
  r = await upload(light, 'video/mp4');
  check(r.code === 200 && r.body.size === fs.statSync(light).size && fs.readFileSync(stored(r.body.url)).equals(fs.readFileSync(light)), '720p h264/aac under 3Mbps .mp4 kept byte-for-byte', `${r.body.size} vs ${fs.statSync(light).size}`);
  const lightMov = path.join(tmp, 'light720.mov');
  execFileSync('ffmpeg', ['-y', '-hide_banner', '-loglevel', 'error', '-i', light, '-c', 'copy', lightMov]);
  r = await upload(lightMov, 'video/quicktime');
  p = probe(stored(r.body.url));
  check(r.body.url.endsWith('.mp4') && p.w === 1280 && p.h === 720 && faststart(stored(r.body.url)), 'light .mov → remuxed .mp4 (size kept, faststart)', JSON.stringify(p));

  if (encoders.includes('libx265')) {
    const hevc = gen('hevc.mp4', src('1280x720', 30, 2), ['-c:v', 'libx265', '-preset', 'ultrafast', '-x265-params', 'log-level=error', '-tag:v', 'hvc1']);
    r = await upload(hevc, 'video/mp4');
    p = probe(stored(r.body.url));
    check(p.v === 'h264' && p.w === 1280 && p.h === 720, 'hevc 720p → h264, size kept', JSON.stringify(p));
  } else console.log('SKIP hevc fixture: no libx265');
  if (encoders.includes('libvpx-vp9') && encoders.includes('libopus')) {
    const vp9 = gen('vp9.webm', [...src('640x360', 30, 2), ...tone(2)], ['-map', '0:v', '-map', '1:a', '-c:v', 'libvpx-vp9', '-deadline', 'realtime', '-cpu-used', '8', '-b:v', '400k', '-c:a', 'libopus', '-shortest']);
    r = await upload(vp9, 'video/webm');
    p = probe(stored(r.body.url));
    check(r.body.url.endsWith('.mp4') && p.v === 'h264' && p.a === 'aac' && p.w === 640 && p.h === 360, 'webm vp9/opus → h264/aac mp4, 640x360 kept', JSON.stringify(p));
  } else console.log('SKIP vp9 fixture: no libvpx-vp9/libopus');

  // ---- المعاينة
  const bigName = bigUrl.split('/').pop();
  let g = await app.inject({ method: 'GET', url: `/chat/vpreview/${bigName}` });
  const cacheFile = path.join(process.env.CHAT_MEDIA_DIR, 'vpreviews', bigName);
  check(g.statusCode === 200 && g.headers['content-type'] === 'video/mp4' && g.headers['accept-ranges'] === 'bytes' && /immutable/.test(g.headers['cache-control']), 'vpreview: 200 video/mp4, ranges, immutable', `${g.statusCode} ${g.headers['content-type']} ${g.headers['cache-control']}`);
  check(fs.existsSync(cacheFile), 'vpreview cached under MEDIA_DIR/vpreviews');
  p = probe(cacheFile);
  check(p.v === 'h264' && p.a === null && p.w === 640 && p.h === 360 && p.dur <= 6.1 && Math.round(p.fps) <= 30 && faststart(cacheFile), 'vpreview: h264 640x360, muted, ≤6s, faststart', JSON.stringify(p));
  check(g.rawPayload.length === fs.statSync(cacheFile).size && g.rawPayload.length < fs.statSync(stored(bigUrl)).size, 'vpreview much smaller than the video', `${g.rawPayload.length} vs ${fs.statSync(stored(bigUrl)).size}`);
  const mtime = fs.statSync(cacheFile).mtimeMs;
  g = await app.inject({ method: 'GET', url: `/chat/vpreview/${bigName}`, headers: { range: 'bytes=0-99' } });
  check(g.statusCode === 206 && g.rawPayload.length === 100 && /^bytes 0-99\//.test(g.headers['content-range']) && fs.statSync(cacheFile).mtimeMs === mtime, 'vpreview Range → 206 from cache', g.headers['content-range']);
  const tallName = (await upload(tall, 'video/mp4')).body.url.split('/').pop();
  const [g1, g2] = await Promise.all([app.inject({ method: 'GET', url: `/chat/vpreview/${tallName}` }), app.inject({ method: 'GET', url: `/chat/vpreview/${tallName}` })]);
  p = probe(path.join(process.env.CHAT_MEDIA_DIR, 'vpreviews', tallName));
  check(g1.statusCode === 200 && g2.statusCode === 200 && g1.rawPayload.equals(g2.rawPayload) && p.w === 360 && p.h === 640 && p.dur <= 2.1, 'portrait vpreview 360x640; concurrent first requests share one encode', JSON.stringify(p));
  const wav = gen('tone.wav', tone(2), ['-c:a', 'pcm_s16le']);
  const audioName = (await upload(wav, 'audio/wav')).body.url.split('/').pop();
  check((await app.inject({ method: 'GET', url: `/chat/vpreview/${audioName}` })).statusCode === 404, 'vpreview of audio → 404');
  check((await app.inject({ method: 'GET', url: '/chat/vpreview/mtynofile-' + 'c'.repeat(24) + '.mp4' })).statusCode === 404, 'vpreview of a missing file → 404');
  check((await app.inject({ method: 'GET', url: '/chat/vpreview/..%2F..%2Fetc%2Fpasswd' })).statusCode === 404, 'vpreview rejects bad names');
  const brokenName = 'mtybroken-' + 'd'.repeat(24) + '.mp4';
  fs.writeFileSync(path.join(process.env.CHAT_MEDIA_DIR, brokenName), 'not a video');
  check((await app.inject({ method: 'GET', url: `/chat/vpreview/${brokenName}` })).statusCode === 404 && !fs.readdirSync(path.join(process.env.CHAT_MEDIA_DIR, 'vpreviews')).some((f) => f.includes('.part')), 'broken video → 404, no partial file left');
  await globalThis.naslifeMediaDelete(bigUrl);
  check(!fs.existsSync(cacheFile) && !fs.existsSync(stored(bigUrl)), 'media delete removes the vpreview too');
  g = await app.inject({ method: 'GET', url: bigUrl });
  check(g.statusCode === 404, 'deleted media → 404');
}

// ===================== 2) التفاعلات
const vUrl = `https://naslife.app/chat/media/${vName}`, iUrl = `https://naslife.app/chat/media/${iName}`;
const pImg = await call('POST', '/mapposts', { body: { kind: 'image', mediaUrl: `/chat/media/${iName}`, caption: 'غروب <b>الكورنيش</b>', lat: 21.54, lng: 39.17, placeName: 'الكورنيش' }, user: 'SA0000002', expect: 200 });
const pVid = await call('POST', '/mapposts', { body: { kind: 'video', mediaUrl: `/chat/media/${vName}`, caption: 'موج', durationSec: 12, lat: 21.54, lng: 39.17 }, user: 'SA0000002', expect: 200 });
const pTxt = await call('POST', '/mapposts', { body: { kind: 'text', caption: 'صباح الخير يا جدة', bg: '#0B3D4F', lat: 21.5, lng: 39.2 }, user: 'SA0000003', expect: 200 });
check(pImg.mediaUrl === iUrl && pVid.mediaUrl === vUrl, 'posts created with absolute media urls');
const R = `/moments/${pImg.id}`;
const zero = { '😍': 0, '😂': 0, '🔥': 0, '👏': 0 };
let x = await call('GET', `${R}/reactions`, { user: null, expect: 200 });
check(JSON.stringify(x) === JSON.stringify({ counts: zero, mine: null }), 'guest GET: four zero counts, mine null', JSON.stringify(x));
await call('POST', `${R}/react`, { body: { emoji: '😍' }, user: null, expect: 401 });
await call('DELETE', `${R}/react`, { user: null, expect: 401 });
x = await call('POST', `${R}/react`, { body: { emoji: '💩' }, expect: 400 });
check(x.error === 'bad-emoji' && JSON.stringify(x.allowed) === JSON.stringify(MOMENT_REACTIONS), 'unknown emoji → 400 with the allowed set');
x = await call('POST', `${R}/react`, { body: {}, expect: 400 });
check(x.error === 'bad-emoji', 'body without emoji → 400 (removal must be explicit)');
x = await call('POST', `${R}/react`, { body: { emoji: '😍' }, expect: 200 });
check(x.counts['😍'] === 1 && x.mine === '😍' && Object.keys(x.counts).length === 4, 'set 😍', JSON.stringify(x));
let ns = await notes();
check(ns.length === 1 && ns[0].title === 'amr تفاعل مع لحظتك 😍' && ns[0].data.postId === pImg.id, 'owner notified: «amr تفاعل مع لحظتك 😍» with postId', JSON.stringify(ns));
x = await call('POST', `${R}/react`, { body: { emoji: '🔥' }, expect: 200 });
check(x.counts['😍'] === 0 && x.counts['🔥'] === 1 && x.mine === '🔥', 'change to 🔥 (one reaction per user)', JSON.stringify(x));
check((await notes()).length === 1, 'change within the hour: no second notification');
x = await call('POST', `${R}/react`, { body: { emoji: '🔥' }, expect: 200 });
check(x.counts['🔥'] === 1 && x.mine === '🔥', 'same emoji again: unchanged (not a toggle)');
x = await call('POST', `${R}/react`, { body: { emoji: '😂' }, user: 'SA0000003', expect: 200 });
check(x.counts['😂'] === 1 && x.counts['🔥'] === 1 && x.mine === '😂', 'second reactor counted separately');
ns = await notes();
check(ns.length === 2 && ns[1].title === 'khalid تفاعل مع لحظتك 😂', 'another reactor notifies once', JSON.stringify(ns.map((n) => n.title)));
x = await call('GET', `${R}/reactions`, { expect: 200 });
check(x.mine === '🔥' && x.counts['🔥'] === 1 && x.counts['😂'] === 1, 'GET as amr: mine 🔥');
x = await call('GET', `${R}/reactions`, { user: null, expect: 200 });
check(x.mine === null && x.counts['🔥'] === 1, 'GET as guest: same counts, mine null');
x = await call('POST', `${R}/react`, { body: { emoji: null }, expect: 200 });
check(x.mine === null && x.counts['🔥'] === 0 && x.counts['😂'] === 1, '{emoji:null} removes my reaction', JSON.stringify(x));
x = await call('DELETE', `${R}/react`, { expect: 200 });
check(x.mine === null && x.counts['😂'] === 1, 'DELETE is idempotent and returns the same shape');
x = await call('POST', `${R}/react`, { body: { emoji: '👏️' }, expect: 200 });
check(x.mine === '👏', 'emoji with a variation selector accepted as 👏');
check((await notes()).length === 2, 'remove then react again within the hour: still throttled');
await pool.query("UPDATE map_post_react_notified SET at = now() - interval '2 hours' WHERE user_id='SA0000001'");
x = await call('POST', `${R}/react`, { body: { emoji: '😍' }, expect: 200 });
ns = await notes();
check(ns.length === 3 && ns[2].title === 'amr تفاعل مع لحظتك 😍', 'after an hour the same reactor notifies again', JSON.stringify(ns.map((n) => n.title)));
x = await call('POST', `${R}/react`, { body: { emoji: '🔥' }, user: 'SA0000002', expect: 200 });
check(x.mine === '🔥' && x.counts['🔥'] === 1 && (await notes()).length === 3, 'owner may react to own moment, without a notification');
check((await pool.query("SELECT count(*)::int AS n FROM map_post_react_notified WHERE user_id='SA0000002'")).rows[0].n === 0, 'self reaction leaves no throttle row');
// الحظر
await pool.query("INSERT INTO user_blocks(user_id,blocked_id) VALUES('SA0000002','SA0000004')");
x = await call('POST', `${R}/react`, { body: { emoji: '😍' }, user: 'SA0000004', expect: 403 });
check(x.error === 'blocked', 'blocked pair → 403 blocked');
await call('DELETE', `${R}/react`, { user: 'SA0000004', expect: 403 });
await call('GET', `${R}/reactions`, { user: 'SA0000004', expect: 403 });
await call('GET', `${R}/reactions`, { user: null, expect: 200 });
await pool.query('DELETE FROM user_blocks');
await call('POST', `${R}/react`, { body: { emoji: '😂' }, user: 'SA0000004', expect: 200 });
// المخفي والمحجوب والمحذوف وغير الموجود
await call('PATCH', `/mapposts/${pImg.id}`, { body: { status: 'hidden' }, user: 'SA0000002', expect: 200 });
await call('POST', `${R}/react`, { body: { emoji: '😍' }, expect: 404 });
await call('DELETE', `${R}/react`, { expect: 404 });
await call('GET', `${R}/reactions`, { user: null, expect: 404 });
x = await call('GET', `${R}/reactions`, { user: 'SA0000002', expect: 200 });
check(x.counts['😍'] === 1 && x.counts['🔥'] === 1 && x.counts['😂'] === 2, 'owner still reads counts of own hidden moment', JSON.stringify(x));
await call('PATCH', `/mapposts/${pImg.id}`, { body: { status: 'active' }, user: 'SA0000002', expect: 200 });
await pool.query("UPDATE map_posts SET status='blocked' WHERE id=$1", [pVid.id]);
await call('POST', `/moments/${pVid.id}/react`, { body: { emoji: '😍' }, expect: 404 });
await call('GET', `/moments/${pVid.id}/reactions`, { user: null, expect: 404 });
await pool.query("UPDATE map_posts SET status='active' WHERE id=$1", [pVid.id]);
await call('GET', '/moments/aaaaaaaa-0000-4000-8000-000000000000/reactions', { user: null, expect: 404 });
await call('POST', '/moments/not-a-uuid/react', { body: { emoji: '😍' }, expect: 404 });
x = await call('GET', '/moments/status', { user: null, expect: 200 });
check(x.ok && x.reactions.length === 4, 'status lists the four reactions');
// كنس اليتامى: لحظة محذوفة تأخذ تفاعلاتها معها
await call('POST', `/moments/${pTxt.id}/react`, { body: { emoji: '👏' }, expect: 200 });
await call('DELETE', `/mapposts/${pTxt.id}`, { user: 'SA0000003', expect: 200 });
const sw = await globalThis.naslifeMomentExtrasSweep();
check(sw.reactions === 1 && (await pool.query('SELECT count(*)::int AS n FROM map_post_reactions WHERE post_id=$1', [pTxt.id])).rows[0].n === 0, 'sweep drops reactions of deleted moments', JSON.stringify(sw));
check((await pool.query('SELECT count(*)::int AS n FROM map_post_reactions WHERE post_id=$1', [pImg.id])).rows[0].n === 4, 'sweep keeps live reactions (amr, khalid, sara, noura)');

// ===================== 3) رابط المشاركة /m/:id
const getHtml = async (url) => { const r = await app.inject({ method: 'GET', url, headers: { host: 'www.naslife.app', 'x-forwarded-proto': 'https' } }); return { code: r.statusCode, type: r.headers['content-type'], body: r.body }; };
const meta = (html, prop) => (html.match(new RegExp(`<meta (?:property|name)="${prop}" content="([^"]*)"`)) || [])[1];
const refresh = (html) => (html.match(/<meta http-equiv="refresh" content="([^"]*)"/) || [])[1];
let h = await getHtml(`/m/${pImg.id}`);
check(h.code === 200 && /text\/html/.test(h.type) && !/<script/i.test(h.body), 'moment link: html page without scripts (CSP)');
check(meta(h.body, 'og:title') === 'غروب &lt;b&gt;الكورنيش&lt;/b&gt;' && h.body.includes('<title>غروب &lt;b&gt;الكورنيش&lt;/b&gt;</title>'), 'og:title = caption (escaped)', meta(h.body, 'og:title'));
check(meta(h.body, 'og:image') === iUrl && meta(h.body, 'twitter:card') === 'summary_large_image', 'og:image = the image itself on the bare host', meta(h.body, 'og:image'));
check(meta(h.body, 'og:description') === 'sara · الكورنيش', 'og:description = nickname · place', meta(h.body, 'og:description'));
check(meta(h.body, 'og:url') === `https://naslife.app/m/${pImg.id}` && refresh(h.body) === `0; url=/#/m/${pImg.id}` && h.body.includes(`href="/#/m/${pImg.id}"`), 'og:url canonical, refresh + link to /#/m/<id>', refresh(h.body));
h = await getHtml(`/m/${pVid.id.toUpperCase()}`);
check(meta(h.body, 'og:image') === `https://naslife.app/chat/thumb/${vName}` && meta(h.body, 'og:title') === 'موج' && meta(h.body, 'og:description') === 'sara' && meta(h.body, 'og:type') === 'video.other', 'video moment: og:image = /chat/thumb/<name>, id case-insensitive', JSON.stringify({ i: meta(h.body, 'og:image'), d: meta(h.body, 'og:description') }));
check(refresh(h.body) === `0; url=/#/m/${pVid.id}`, 'redirect uses the lowercase id');
const pBare = await call('POST', '/mapposts', { body: { kind: 'image', mediaUrl: `/chat/media/${iName}`, lat: 21.5, lng: 39.2 }, user: 'SA0000001', expect: 200 });
h = await getHtml(`/m/${pBare.id}`);
check(meta(h.body, 'og:title') === 'لحظة على ناس لايف' && meta(h.body, 'og:description') === 'amr', 'no caption → «لحظة على ناس لايف»', meta(h.body, 'og:title'));
await call('PATCH', `/mapposts/${pVid.id}`, { body: { status: 'hidden' }, user: 'SA0000002', expect: 200 });
h = await getHtml(`/m/${pVid.id}`);
check(h.code === 200 && meta(h.body, 'og:title') === 'لحظة على ناس لايف' && meta(h.body, 'og:image') === undefined && !h.body.includes('موج') && !h.body.includes('sara'), 'hidden moment: generic tags, no caption/image/author');
await call('PATCH', `/mapposts/${pVid.id}`, { body: { status: 'active' }, user: 'SA0000002', expect: 200 });
h = await getHtml('/m/aaaaaaaa-0000-4000-8000-000000000000');
check(h.code === 200 && meta(h.body, 'og:title') === 'لحظة على ناس لايف' && refresh(h.body) === '0; url=/#/m/aaaaaaaa-0000-4000-8000-000000000000', 'unknown moment: generic tags, still redirects to the viewer');
h = await getHtml('/m/%22%3E%3Cscript%3Ealert(1)%3C%2Fscript%3E');
check(h.code === 200 && !/<script/i.test(h.body) && refresh(h.body) === '0; url=/', 'bad id: safe page redirecting home');

// ===================== 4) «محفوظاتي» والكنس
let w = await call('POST', '/wishlist', { body: { kind: 'post', refId: pVid.id }, expect: 200 });
check(w.imageUrl === `/chat/thumb/${vName}` && w.title === 'موج' && w.available === true, 'saved video moment: imageUrl = /chat/thumb/<name>', JSON.stringify(w));
const wi = await call('POST', '/wishlist', { body: { kind: 'post', refId: pImg.id }, expect: 200 });
check(wi.imageUrl === iUrl, 'saved image moment: imageUrl = the image', wi.imageUrl);
const list = await call('GET', '/wishlist', { expect: 200 });
check(list.find((x2) => x2.refId === pVid.id)?.imageUrl === `/chat/thumb/${vName}`, 'list keeps the video thumb');
// ثلاث لحظات منتهية منذ 31 يوماً: محفوظة، ومحفوظة بمعرّف بأحرف كبيرة، وغير محفوظة
const old = [];
for (const c of ['محفوظة', 'محفوظة بأحرف كبيرة', 'غير محفوظة']) old.push(await call('POST', '/mapposts', { body: { kind: 'text', caption: c, lat: 21.5, lng: 39.2 }, user: 'SA0000003', expect: 200 }));
await call('POST', '/wishlist', { body: { kind: 'post', refId: old[0].id }, expect: 200 });
await call('POST', '/wishlist', { body: { kind: 'post', refId: old[1].id.toUpperCase() }, user: 'SA0000004', expect: 200 });
await pool.query("UPDATE map_posts SET expires_at = now() - interval '31 days', created_at = now() - interval '32 days' WHERE id = ANY($1::uuid[])", [old.map((o) => o.id)]);
const exists = async (id) => (await pool.query('SELECT 1 FROM map_posts WHERE id=$1', [id])).rowCount > 0;
const swept = await globalThis.naslifeMapPostsSweep();
check(swept === 1 && await exists(old[0].id) && await exists(old[1].id) && !(await exists(old[2].id)), 'sweep deletes the unsaved expired moment, keeps saved ones (any id case)', String(swept));
x = await call('GET', `/mapposts/${old[0].id}`, { expect: 200 });
check(x.expired === true && x.caption === 'محفوظة', 'saver still opens the expired moment (expired:true)');
const savedRow = (await call('GET', '/wishlist', { expect: 200 })).find((x2) => x2.refId === old[0].id);
check(savedRow && savedRow.available === false, 'expired saved moment is listed as unavailable');
await call('DELETE', `/wishlist/${savedRow.id}`, { expect: 200 });
await globalThis.naslifeMapPostsSweep();
check(!(await exists(old[0].id)) && await exists(old[1].id), 'unsaving lets the next sweep delete it');

await pool.query('DROP TABLE IF EXISTS map_post_reactions, map_post_react_notified');
await pool.query('DELETE FROM wishlist_items'); await pool.query('DELETE FROM user_blocks');
await app.close(); await pool.end();
fs.rmSync(tmp, { recursive: true, force: true });
console.log(fails ? `\n${fails} FAILED` : '\nALL MOMENT EXTRAS TESTS PASSED');
process.exit(fails ? 1 : 0);
