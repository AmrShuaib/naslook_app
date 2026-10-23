// اختبارات طابور الترميز في server/chat_tools.js (docs/moments.md «طابور الترميز» و«معاينة الفيديو»):
//  1) createSlots: ترتيب الوصول، التسليم المباشر بلا تجاوز للعدد، والانتظار بحد أقصى. moovFirst وpreviewInputProblem دوالاً مستقلة.
//  2) الرفع: فتحة ترميز واحدة وطابور بحد؛ الزائد يُخزَّن بالطريق السريع (إعادة تغليف +faststart) بدل الانتظار، والانتظار الطويل كذلك.
//  3) مهلة الترميز: يُقتل ffmpeg ويُخزَّن الأصل مُعاد التغليف (MP4 والفهرس في المقدمة) بدل ترك ملف .mov/.webm ثقيل.
//  4) المعاينة: الفشل يُتذكّر (علامة .fail، 404 بـ cache-control ساعة) ولا يُعاد الترميز مع كل طلب حتى بعد إعادة التشغيل، ورفض
//     المدخل الضخم قبل فكّه، والطابور الممتلئ 503 بلا تذكّر.
import Fastify from 'fastify';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import pg from 'pg';
import { createSlots, moovFirst, previewInputProblem } from '../chat_tools.js';
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'naslife-tq-'));
process.env.CHAT_MEDIA_DIR = path.join(tmp, 'media_store');
let fails = 0;
const check = (cond, label, extra = '') => { if (!cond) fails++; console.log((cond ? 'OK  ' : 'FAIL') + ' ' + label + (extra ? ' ' + extra : '')); };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ===================== 1) الفتحات
{
  const s = createSlots(2);
  const order = [];
  let maxRunning = 0;
  const job = async (id, ms) => { const rel = await s.acquire(); maxRunning = Math.max(maxRunning, s.running); order.push(id); await sleep(ms); rel(); rel(); /* الإفلات مرتين لا يحرر فتحة ثانية */ };
  await Promise.all([job('a', 40), job('b', 40), job('c', 5), job('d', 5), job('e', 5)]);
  check(JSON.stringify(order) === '["a","b","c","d","e"]' && maxRunning <= 2 && s.running === 0 && s.waiting === 0, 'slots: FIFO, never above n, double release is harmless', JSON.stringify({ order, maxRunning, r: s.running }));
  const one = createSlots(1);
  const rel = await one.acquire();
  const t0 = Date.now();
  const late = await one.acquire(60);
  check(late === null && Date.now() - t0 >= 55 && one.waiting === 0, 'slots: acquire(maxWait) gives up with null and leaves the queue');
  const queued = one.acquire(1000);
  check(one.waiting === 1 && one.full, 'slots: waiting counted while the slot is held');
  rel();
  const rel2 = await queued;
  check(typeof rel2 === 'function' && one.running === 1 && one.waiting === 0, 'slots: release hands the slot to the waiter directly');
  rel2();
  check(one.running === 0 && !one.full, 'slots: all free again');
}
// previewInputProblem
const pr = (w, h, fps = '30/1', dur = '10') => ({ video: { width: w, height: h, avg_frame_rate: fps }, format: { duration: dur } });
check(previewInputProblem(pr(1920, 1080)) === null && previewInputProblem(pr(3840, 2160)) === null && previewInputProblem(pr(1080, 1920, '0/0', 'N/A')) === null, 'preview input: 1080p, 4K and unknown fps/duration accepted');
check(previewInputProblem(pr(7680, 4320)) === 'too-large' && previewInputProblem(pr(0, 0)) === 'no-size' && previewInputProblem(pr(1280, 720, '1000/1')) === 'fps' && previewInputProblem(pr(1280, 720, '30/1', '90000')) === 'duration',
  'preview input: 8K, no size, 1000fps and 25h rejected');

let ffmpeg = true;
try { execFileSync('ffmpeg', ['-version'], { stdio: 'ignore' }); execFileSync('ffprobe', ['-version'], { stdio: 'ignore' }); } catch { ffmpeg = false; }
if (!ffmpeg) {
  console.log('SKIP real encoding: ffmpeg not installed');
  fs.rmSync(tmp, { recursive: true, force: true });
  console.log(fails ? `\n${fails} FAILED` : '\nALL TRANSCODE QUEUE TESTS PASSED');
  process.exit(fails ? 1 : 0);
}

const gen = (name, lavfi, args) => { const f = path.join(tmp, name); execFileSync('ffmpeg', ['-y', '-hide_banner', '-loglevel', 'error', ...lavfi, ...args, f]); return f; };
const src = (size, rate, sec) => ['-f', 'lavfi', '-i', `testsrc2=size=${size}:rate=${rate}:duration=${sec}`];
const tone = (sec) => ['-f', 'lavfi', '-i', `sine=frequency=440:duration=${sec}`];
const probe = (file) => {
  const j = JSON.parse(execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'stream=codec_type,codec_name,width,height:format=format_name', '-of', 'json', file]).toString());
  const v = j.streams.find((s) => s.codec_type === 'video'), a = j.streams.find((s) => s.codec_type === 'audio');
  return { v: v?.codec_name, a: a?.codec_name ?? null, w: v?.width, h: v?.height, fmt: j.format?.format_name };
};
const stored = (url) => path.join(process.env.CHAT_MEDIA_DIR, url.split('/').pop());

// moovFirst على ملفات حقيقية
const light = gen('light_fs.mp4', src('640x360', 30, 1), ['-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p', '-movflags', '+faststart']);
const lightEnd = gen('light_end.mp4', src('640x360', 30, 1), ['-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p']);
fs.writeFileSync(path.join(tmp, 'junk.mp4'), 'not a video at all');
check(await moovFirst(light) === true && await moovFirst(lightEnd) === false && await moovFirst(path.join(tmp, 'junk.mp4')) === false && await moovFirst(path.join(tmp, 'missing.mp4')) === false,
  'moovFirst: +faststart true, moov at end false, junk/missing false');

// ثمانية ثوانٍ 1080p بثمانية ميغابت: تحتاج ترميزاً (size, bitrate) يأخذ ثانيتين تقريباً، والفهرس في الآخر (ffmpeg بلا +faststart)
const big = gen('big1080.mp4', [...src('1920x1080', 30, 8), ...tone(8)], ['-map', '0:v', '-map', '1:a', '-c:v', 'libx264', '-preset', 'ultrafast', '-b:v', '8M', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-shortest']);
check(!(await moovFirst(big)), 'fixture: heavy 1080p mp4 with moov at the end');

const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
const auth = async (req) => req.headers['x-user'] || null;
// تطبيق مستقل بخيارات الطابور، وسجله يُجمع لعدّ محاولات الترميز
const makeApp = async (opts = {}) => {
  const logs = [];
  const app = Fastify({ bodyLimit: 40 * 1024 * 1024, logger: { level: 'info', stream: { write: (s) => { try { logs.push(JSON.parse(s).msg ?? s); } catch { logs.push(s); } } } } });
  app.register((await import('../chat_tools.js')).default, { pool, auth, ...opts });
  await app.ready();
  return { app, logs };
};
const upload = async (app, file, type) => {
  const r = await app.inject({ method: 'POST', url: '/chat/upload', headers: { 'x-user': 'SA0000001', 'content-type': type }, payload: fs.readFileSync(file) });
  return { code: r.statusCode, body: r.json() };
};

// ===================== 2) فتحة واحدة وطابور بواحد: أربعة رفوع معاً = ترميزان (الجاري والمنتظر) وطريقان سريعان
{
  const { app, logs } = await makeApp({ transcode: { slots: 1, queue: 1, waitMs: 120000, timeoutMs: 120000 } });
  const st0 = (await app.inject({ method: 'GET', url: '/chat/status' })).json();
  check(st0.encode?.slots === 1 && st0.encode?.queue === 1 && st0.encode?.running === 0 && st0.encode?.timeoutMs === 120000, 'status: encode queue limits reported', JSON.stringify(st0.encode));
  let maxRunning = 0, maxWaiting = 0, polling = true;
  const poller = (async () => { while (polling) { const s = (await app.inject({ method: 'GET', url: '/chat/status' })).json().encode; maxRunning = Math.max(maxRunning, s.running); maxWaiting = Math.max(maxWaiting, s.waiting); await sleep(20); } })();
  const t0 = Date.now();
  const rs = await Promise.all([0, 1, 2, 3].map(() => upload(app, big, 'video/mp4')));
  polling = false; await poller;
  const dims = rs.map((r) => { const p = probe(stored(r.body.url)); return `${p.w}x${p.h}`; });
  check(rs.every((r) => r.code === 200 && r.body.type === 'video/mp4' && r.body.url.endsWith('.mp4')), 'four concurrent heavy uploads all stored as mp4', JSON.stringify(rs.map((r) => r.code)));
  check(dims.filter((d) => d === '1280x720').length === 2 && dims.filter((d) => d === '1920x1080').length === 2, 'one running + one waiting re-encoded, the two over the queue stored by the fast path', JSON.stringify(dims));
  check(maxRunning === 1 && maxWaiting <= 1, 'never more than one encode at a time, at most one waiting', JSON.stringify({ maxRunning, maxWaiting }));
  const fast = rs.filter((_, i) => dims[i] === '1920x1080').map((r) => stored(r.body.url));
  check((await Promise.all(fast.map((f) => moovFirst(f)))).every(Boolean) && fast.every((f) => probe(f).v === 'h264' && probe(f).a === 'aac'), 'fast path: remuxed with the index at the front, codecs kept');
  check(logs.filter((l) => /\(queue-full\)/.test(l)).length === 2 && logs.filter((l) => /light video .*\(size,bitrate\)/.test(l)).length === 2, 'log: two «queue-full» fast paths and two light encodes', JSON.stringify(logs.filter((l) => /video/.test(l))));
  console.log(`     (4 uploads in ${Date.now() - t0} ms)`);
  const st1 = (await app.inject({ method: 'GET', url: '/chat/status' })).json();
  check(st1.encode.running === 0 && st1.encode.waiting === 0, 'queue drained after the uploads');
  await app.close();
}

// ===================== 2-ب) الانتظار بحد: الثاني لا ينتظر أكثر من waitMs ثم يُخزَّن بالطريق السريع
{
  const { app, logs } = await makeApp({ transcode: { slots: 1, queue: 5, waitMs: 300, timeoutMs: 120000 } });
  const rs = await Promise.all([upload(app, big, 'video/mp4'), sleep(150).then(() => upload(app, big, 'video/mp4'))]);
  const dims = rs.map((r) => { const p = probe(stored(r.body.url)); return `${p.w}x${p.h}`; });
  check(dims[0] === '1280x720' && dims[1] === '1920x1080' && logs.some((l) => /\(queue-wait\)/.test(l)), 'a waiter past waitMs takes the fast path', JSON.stringify(dims));
  await app.close();
}

// ===================== 3) مهلة الترميز: يُقتل ffmpeg ويُخزَّن الأصل مُعاد التغليف (لا يبقى .mov أو .webm ثقيل)
{
  const { app, logs } = await makeApp({ transcode: { slots: 1, queue: 3, waitMs: 120000, timeoutMs: 300 } });
  const t0 = Date.now();
  let r = await upload(app, big, 'video/mp4');
  let p = probe(stored(r.body.url));
  check(r.code === 200 && r.body.type === 'video/mp4' && p.w === 1920 && p.h === 1080 && await moovFirst(stored(r.body.url)) && Date.now() - t0 < 8000,
    'encode timeout → original kept, remuxed with +faststart, answered quickly', `${JSON.stringify(p)} ${Date.now() - t0}ms`);
  check(logs.some((l) => /encode timed out/.test(l)) && logs.some((l) => /\(encode-failed\)/.test(l)), 'log: «timed out» then fast path', JSON.stringify(logs.filter((l) => /video/.test(l))));
  const mov = path.join(tmp, 'big.mov');
  execFileSync('ffmpeg', ['-y', '-hide_banner', '-loglevel', 'error', '-i', big, '-c', 'copy', mov]);
  r = await upload(app, mov, 'video/quicktime');
  p = probe(stored(r.body.url));
  check(r.body.url.endsWith('.mp4') && r.body.type === 'video/mp4' && p.w === 1920 && await moovFirst(stored(r.body.url)), 'heavy .mov on timeout → .mp4 remux (plays on Android/Chrome)', r.body.url);
  const encoders = execFileSync('ffmpeg', ['-hide_banner', '-encoders']).toString();
  if (encoders.includes('libvpx-vp9') && encoders.includes('libopus')) {
    const vp9 = gen('heavy.webm', [...src('1920x1080', 30, 2), ...tone(2)], ['-map', '0:v', '-map', '1:a', '-c:v', 'libvpx-vp9', '-deadline', 'realtime', '-cpu-used', '8', '-b:v', '2M', '-c:a', 'libopus', '-shortest']);
    r = await upload(app, vp9, 'video/webm');
    p = probe(stored(r.body.url));
    check(r.body.url.endsWith('.mp4') && r.body.type === 'video/mp4' && p.v === 'vp9' && p.a === 'aac', 'webm on timeout → mp4 with the video copied and opus → aac', JSON.stringify(p));
  } else console.log('SKIP vp9 fixture: no libvpx-vp9/libopus');
  await app.close();
}

// ===================== 4) المعاينة: تذكّر الفشل، رفض المدخل الضخم، والطابور الممتلئ
{
  let { app, logs } = await makeApp({ vpreview: { slots: 1, queue: 0, waitMs: 30000 } });
  const PV_DIR = path.join(process.env.CHAT_MEDIA_DIR, 'vpreviews');
  const broken = 'tqbroken1-' + 'd'.repeat(24) + '.mp4';
  fs.writeFileSync(path.join(process.env.CHAT_MEDIA_DIR, broken), Buffer.alloc(2048, 7));
  const failures = () => logs.filter((l) => l.includes(`vpreview failed for ${broken}`)).length;
  let g = await app.inject({ method: 'GET', url: `/chat/vpreview/${broken}` });
  check(g.statusCode === 404 && g.headers['cache-control'] === 'public, max-age=3600' && failures() === 1 && fs.existsSync(path.join(PV_DIR, `${broken}.fail`)), 'broken video: 404 cached for an hour, failure marker written', `${g.statusCode} ${g.headers['cache-control']} ${failures()}`);
  for (let i = 0; i < 5; i++) g = await app.inject({ method: 'GET', url: `/chat/vpreview/${broken}` });
  check(g.statusCode === 404 && g.headers['cache-control'] === 'public, max-age=3600' && failures() === 1, 'five more requests: 404 without probing or encoding again', String(failures()));
  await app.close();
  // إعادة التشغيل: العلامة على القرص تكفي
  ({ app, logs } = await makeApp({ vpreview: { slots: 1, queue: 0, waitMs: 30000 } }));
  g = await app.inject({ method: 'GET', url: `/chat/vpreview/${broken}` });
  check(g.statusCode === 404 && failures() === 0, 'after a restart the marker still prevents a retry');
  // بعد يوم تُعاد المحاولة مرة (علامة قديمة على القرص بعد إعادة تشغيل، ثم تُتذكّر من جديد)
  await app.close();
  const old = new Date(Date.now() - 25 * 3600e3);
  fs.utimesSync(path.join(PV_DIR, `${broken}.fail`), old, old);
  ({ app, logs } = await makeApp({ vpreview: { slots: 1, queue: 0, waitMs: 30000 } }));
  g = await app.inject({ method: 'GET', url: `/chat/vpreview/${broken}` });
  await app.inject({ method: 'GET', url: `/chat/vpreview/${broken}` });
  check(g.statusCode === 404 && failures() === 1 && Date.now() - fs.statSync(path.join(PV_DIR, `${broken}.fail`)).mtimeMs < 60000, 'a marker older than a day allows one new attempt, then is renewed', String(failures()));
  await globalThis.naslifeMediaDelete(`/chat/media/${broken}`);
  check(!fs.existsSync(path.join(PV_DIR, `${broken}.fail`)), 'media delete removes the failure marker');
  // مدخل أكبر من 4096×2304: يُرفض من ffprobe قبل فك الترميز
  const hugeName = 'tqhugevid-' + 'e'.repeat(24) + '.mp4';
  gen('huge.mp4', src('4320x2432', 1, 1), ['-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p']);
  fs.copyFileSync(path.join(tmp, 'huge.mp4'), path.join(process.env.CHAT_MEDIA_DIR, hugeName));
  g = await app.inject({ method: 'GET', url: `/chat/vpreview/${hugeName}` });
  check(g.statusCode === 404 && logs.some((l) => l.includes(`vpreview failed for ${hugeName}: input rejected: too-large`)), 'oversized input rejected before decoding');
  // طابور المعاينات صفر وفتحة واحدة مشغولة: طلب ملف آخر 503 بلا تخزين ولا علامة فشل، ثم ينجح لاحقاً
  const a = 'tqprevaaa-' + 'a'.repeat(24) + '.mp4', b = 'tqprevbbb-' + 'b'.repeat(24) + '.mp4';
  fs.copyFileSync(big, path.join(process.env.CHAT_MEDIA_DIR, a)); fs.copyFileSync(big, path.join(process.env.CHAT_MEDIA_DIR, b));
  const ga = app.inject({ method: 'GET', url: `/chat/vpreview/${a}` });
  for (let i = 0; i < 200 && (await app.inject({ method: 'GET', url: '/chat/status' })).json().previews.running === 0; i++) await sleep(10);
  const gb = await app.inject({ method: 'GET', url: `/chat/vpreview/${b}` });
  check(gb.statusCode === 503 && gb.headers['cache-control'] === 'no-store' && gb.json().error === 'busy' && !fs.existsSync(path.join(PV_DIR, `${b}.fail`)), 'preview queue full → 503 busy, no-store, not remembered as a failure', `${gb.statusCode} ${gb.headers['cache-control']}`);
  check((await ga).statusCode === 200, 'the running preview still completes');
  check((await app.inject({ method: 'GET', url: `/chat/vpreview/${b}` })).statusCode === 200, 'the busy file succeeds once a slot is free');
  await app.close();
}

await pool.end();
fs.rmSync(tmp, { recursive: true, force: true });
console.log(fails ? `\n${fails} FAILED` : '\nALL TRANSCODE QUEUE TESTS PASSED');
process.exit(fails ? 1 : 0);
