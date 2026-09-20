// اختبارات رفع الوسائط (server/chat_tools.js): الصور كما هي، الصوت إلى m4a، والفيديو إلى MP4 (H.264/AAC) بإعادة تغليف أو ترميز،
// مع التقديم بدعم Range.
import Fastify from 'fastify';
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
const dir = new URL('.', import.meta.url).pathname;
process.env.CHAT_MEDIA_DIR = path.join(dir, 'media_store');
fs.rmSync(process.env.CHAT_MEDIA_DIR, { recursive: true, force: true });
import pg from 'pg';
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
app.register((await import('../chat_tools.js')).default, { pool, auth });
await app.ready();
let fails = 0;
const check = (cond, label, extra = '') => { if (!cond) fails++; console.log((cond ? 'OK  ' : 'FAIL') + ' ' + label + (extra ? ' ' + extra : '')); };
const probe = (file) => {
  const j = JSON.parse(execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'stream=codec_type,codec_name,width,height', '-of', 'json', file]).toString());
  const v = j.streams.find((s) => s.codec_type === 'video'), a = j.streams.find((s) => s.codec_type === 'audio');
  return { v: v?.codec_name, a: a?.codec_name, w: v?.width, h: v?.height };
};
const faststart = (file) => { const b = fs.readFileSync(file); const moov = b.indexOf('moov'), mdat = b.indexOf('mdat'); return moov > 0 && mdat > 0 && moov < mdat; };
const upload = async (file, type, extraHeaders = {}) => {
  const r = await app.inject({ method: 'POST', url: '/chat/upload', headers: { 'x-user': 'SA0000001', 'content-type': type, ...extraHeaders }, payload: fs.readFileSync(path.join(dir, 'media', file)) });
  return { code: r.statusCode, body: r.json() };
};
const stored = (url) => path.join(process.env.CHAT_MEDIA_DIR, url.split('/').pop());

const st = (await app.inject({ method: 'GET', url: '/chat/status' })).json();
check(st.ok && st.media && st.transcode, 'status: media dir + ffmpeg', JSON.stringify(st));

let r = await upload('test.png', 'image/png');
check(r.code === 200 && r.body.url.endsWith('.png') && r.body.kind === 'image', 'png kept as-is', JSON.stringify(r.body));

r = await upload('test_h264.mov', 'video/quicktime');
check(r.code === 200 && r.body.url.endsWith('.mp4') && r.body.type === 'video/mp4' && r.body.kind === 'video', 'iPhone .mov (h264/aac) → remuxed .mp4', JSON.stringify(r.body));
let p = probe(stored(r.body.url));
check(p.v === 'h264' && p.a === 'aac' && p.w === 640, 'remux keeps codecs and size', JSON.stringify(p));
check(faststart(stored(r.body.url)), 'remux: moov before mdat (faststart)');
check(!fs.existsSync(stored(r.body.url).replace(/\.mp4$/, '.mov')) && fs.readdirSync(process.env.CHAT_MEDIA_DIR).filter((f) => f.endsWith('.mov')).length === 0, 'original .mov removed');
let g = await app.inject({ method: 'GET', url: r.body.url });
check(g.statusCode === 200 && g.headers['content-type'] === 'video/mp4' && g.headers['accept-ranges'] === 'bytes', 'GET served as video/mp4 with ranges', g.headers['content-type']);
g = await app.inject({ method: 'GET', url: r.body.url, headers: { range: 'bytes=0-99' } });
check(g.statusCode === 206 && g.rawPayload.length === 100 && /^bytes 0-99\//.test(g.headers['content-range']), 'Range → 206', g.headers['content-range']);

r = await upload('test_vp9.webm', 'video/webm');
check(r.code === 200 && r.body.url.endsWith('.mp4') && r.body.type === 'video/mp4', 'Android .webm (vp9/opus) → transcoded .mp4', JSON.stringify(r.body));
p = probe(stored(r.body.url));
check(p.v === 'h264' && p.a === 'aac' && p.w === 640 && p.h === 360, 'webm transcode: h264/aac, size kept under 720', JSON.stringify(p));
check(faststart(stored(r.body.url)), 'transcode: faststart');

r = await upload('test_hevc.mp4', 'video/mp4');
check(r.code === 200 && r.body.url.endsWith('.mp4'), 'HEVC .mp4 → transcoded', JSON.stringify(r.body));
p = probe(stored(r.body.url));
check(p.v === 'h264' && !p.a && p.w === 720 && p.h === 406, 'hevc 1080p → h264 720x406 (no audio stream)', JSON.stringify(p));

const okSize = fs.statSync(path.join(dir, 'media', 'test_ok.mp4')).size;
r = await upload('test_ok.mp4', 'video/mp4');
check(r.code === 200 && r.body.url.endsWith('.mp4') && r.body.size === okSize, 'h264/aac .mp4 kept untouched', JSON.stringify(r.body));

r = await upload('test_h264.mov', 'application/octet-stream', { 'x-file-name': 'IMG_0001.mov' });
check(r.code === 200 && r.body.url.endsWith('.mp4') && r.body.type === 'video/mp4', 'octet-stream + x-file-name .mov → mp4', JSON.stringify(r.body));

r = await upload('test_voice.weba', 'audio/webm');
check(r.code === 200 && r.body.url.endsWith('.m4a') && r.body.type === 'audio/mp4' && r.body.kind === 'audio', 'voice .weba (opus) → m4a', JSON.stringify(r.body));
p = probe(stored(r.body.url));
check(p.a === 'aac' && !p.v, 'voice transcode: aac', JSON.stringify(p));

r = await upload('test.png', 'image/png', { 'x-user': '' });
check(r.code === 401, 'upload requires auth');
r = await app.inject({ method: 'POST', url: '/chat/upload', headers: { 'x-user': 'SA0000001', 'content-type': 'video/mp4' }, payload: Buffer.from('not a video at all') });
check(r.statusCode === 200 && r.json().url.endsWith('.mp4'), 'broken video: kept original (normalize failed gracefully)', r.body.slice(0, 120));

// ---- المصغّرات
const dims = (file) => { const j = JSON.parse(execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'stream=width,height', '-of', 'json', file]).toString()); return [j.streams[0].width, j.streams[0].height]; };
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
r = await upload('big.jpg', 'image/jpeg');
check(r.code === 200 && r.body.thumbUrl === r.body.url.replace('/chat/media/', '/chat/thumb/'), 'upload returns thumbUrl', JSON.stringify(r.body));
await wait(1500);
const thumbStored = path.join(process.env.CHAT_MEDIA_DIR, 'thumbs', r.body.url.split('/').pop().replace(/\.jpg$/, '.jpg'));
check(fs.existsSync(thumbStored), 'thumb generated in background on upload');
g = await app.inject({ method: 'GET', url: r.body.thumbUrl });
check(g.statusCode === 200 && g.headers['content-type'] === 'image/jpeg' && g.rawPayload.length < fs.statSync(path.join(dir, 'media', 'big.jpg')).size / 3, 'thumb served as jpeg and much smaller', `${g.headers['content-type']} ${g.rawPayload.length}`);
check(dims(thumbStored)[0] === 480 && dims(thumbStored)[1] === 270, '1600x900 → 480x270', dims(thumbStored).join('x'));
r = await upload('rotated.jpg', 'image/jpeg'); await wait(1500);
const rotThumb = path.join(process.env.CHAT_MEDIA_DIR, 'thumbs', r.body.url.split('/').pop());
check(fs.existsSync(rotThumb) && dims(rotThumb)[0] === 270 && dims(rotThumb)[1] === 480, 'EXIF orientation applied (portrait thumb)', fs.existsSync(rotThumb) ? dims(rotThumb).join('x') : 'missing');
// ملف قديم بلا مصغّر: يُولَّد عند أول طلب
const oldName = 'mtyoldxx-' + 'a'.repeat(24) + '.png';
fs.copyFileSync(path.join(dir, 'media', 'test.png'), path.join(process.env.CHAT_MEDIA_DIR, oldName));
g = await app.inject({ method: 'GET', url: '/chat/thumb/' + oldName });
check(g.statusCode === 200 && g.headers['content-type'] === 'image/jpeg', 'lazy thumb for an existing file', g.headers['content-type']);
// فيديو: إطار
r = await upload('test_ok.mp4', 'video/mp4'); await wait(2000);
g = await app.inject({ method: 'GET', url: r.body.thumbUrl });
check(g.statusCode === 200 && g.headers['content-type'] === 'image/jpeg' && g.rawPayload.length > 500, 'video poster thumb', `${g.statusCode} ${g.headers['content-type']} ${g.rawPayload.length}`);
// صوت: لا مصغّر
r = await upload('test_voice.weba', 'audio/webm');
check(r.body.thumbUrl === null && (await app.inject({ method: 'GET', url: '/chat/thumb/' + r.body.url.split('/').pop() })).statusCode === 404, 'no thumb for audio');
g = await app.inject({ method: 'GET', url: '/chat/thumb/mtyoldxx-' + 'b'.repeat(24) + '.png' });
check(g.statusCode === 404, 'unknown file → 404');
// ملف صورة تالف: يُقدَّم الأصل بدل الفشل
const badName = 'mtybadxx-' + 'c'.repeat(24) + '.png';
fs.writeFileSync(path.join(process.env.CHAT_MEDIA_DIR, badName), Buffer.from('not an image'));
g = await app.inject({ method: 'GET', url: '/chat/thumb/' + badName });
check(g.statusCode === 200 && g.headers['content-type'] === 'image/png' && g.rawPayload.toString() === 'not an image', 'broken image → original served', `${g.statusCode} ${g.headers['content-type']}`);

// ---- تفاعلات الرسائل: قلب بالنقر المزدوج أو إيموجي من الضغط المطوّل
const jreq = async (method, url, user, payload) => { const r = await app.inject({ method, url, headers: { 'x-user': user, 'content-type': 'application/json' }, payload: payload === undefined ? undefined : JSON.stringify(payload) }); return { code: r.statusCode, body: r.json() }; };
let rx = await jreq('POST', '/chat/react', 'SA0000001', { messageId: 'm-1', emoji: '❤️' });
check(rx.code === 200 && rx.body.reactions.length === 1 && rx.body.reactions[0].emoji === '❤️' && rx.body.reactions[0].mine === true, 'heart on a message', JSON.stringify(rx.body));
rx = await jreq('POST', '/chat/react', 'SA0000002', { messageId: 'm-1', emoji: '❤️' });
check(rx.body.reactions[0].count === 2 && rx.body.reactions[0].mine === true, 'peer heart aggregated');
rx = await jreq('POST', '/chat/react', 'SA0000002', { messageId: 'm-1', emoji: '😂' });
check(rx.body.reactions.length === 2 && rx.body.reactions.find((x) => x.emoji === '❤️').count === 1 && rx.body.reactions.find((x) => x.emoji === '😂').mine === true, 'new emoji replaces the previous one');
rx = await jreq('POST', '/chat/react', 'SA0000002', { messageId: 'm-1', emoji: '😂' });
check(!rx.body.reactions.some((x) => x.emoji === '😂'), 'same emoji again removes it');
rx = await jreq('POST', '/chat/react', 'SA0000001', { messageId: 'm-1', emoji: '💩' });
check(rx.code === 400 && rx.body.error === 'bad-emoji', 'unknown emoji rejected');
await jreq('POST', '/chat/react', 'SA0000002', { messageId: 'm-2', emoji: '🔥' });
const meta = (await app.inject({ method: 'GET', url: '/chat/meta?ids=m-1,m-2,m-3', headers: { 'x-user': 'SA0000001' } })).json();
check(meta['m-1'].reactions[0].emoji === '❤️' && meta['m-1'].reactions[0].mine === true && meta['m-2'].reactions[0].emoji === '🔥' && meta['m-2'].reactions[0].mine === false && meta['m-3'] === undefined, 'meta carries reactions per message with my state', JSON.stringify(meta));
await pool.query('DELETE FROM chat_reactions');

await app.close(); await pool.end();
console.log(fails ? `\n${fails} FAILED` : '\nALL CHAT TOOLS TESTS PASSED');
process.exit(fails ? 1 : 0);
