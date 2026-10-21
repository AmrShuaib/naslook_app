// اختبارات موجة الصوت (server/chat_tools.js): الرفع الصوتي يعيد 48 قيمة RMS في 0..1 مطبَّعة على الأعلى، تُخزَّن بجانب الملف،
// وGET /chat/peaks?name= يحسبها عند الطلب للملفات الأقدم، ويرفض الأسماء غير الصالحة وغير الصوتية والمفقودة، ولا يفشل الرفع أبداً.
// النغمة تُولَّد بـ ffmpeg -f lavfi: ثانية عالية، ثانية خافتة (10%)، ثانية عالية، ثانية صمت.
import Fastify from 'fastify';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import pg from 'pg';
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'naslife-peaks-'));
process.env.CHAT_MEDIA_DIR = path.join(tmp, 'media_store');
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
app.register((await import('../chat_tools.js')).default, { pool, auth });
await app.ready();
let fails = 0;
const check = (cond, label, extra = '') => { if (!cond) fails++; console.log((cond ? 'OK  ' : 'FAIL') + ' ' + label + (extra ? ' ' + extra : '')); };

// ---- نغمة الاختبار: 440 هرتز لأربع ثوانٍ مع نمط الصوت (عالٍ/خافت/عالٍ/صمت)
const wav = path.join(tmp, 'tone.wav'), m4a = path.join(tmp, 'tone.m4a');
const filter = "volume=enable='between(t,1,2)':volume=0.1,volume=enable='between(t,3,4)':volume=0";
execFileSync('ffmpeg', ['-y', '-hide_banner', '-loglevel', 'error', '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=16000:duration=4', '-af', filter, '-c:a', 'pcm_s16le', wav]);
execFileSync('ffmpeg', ['-y', '-hide_banner', '-loglevel', 'error', '-i', wav, '-c:a', 'aac', '-b:a', '64k', m4a]);
check(fs.statSync(wav).size > 100000 && fs.statSync(m4a).size > 5000, 'test tone generated (wav + m4a)', `${fs.statSync(wav).size} / ${fs.statSync(m4a).size}`);

const upload = async (file, type, user = 'SA0000001') => {
  const r = await app.inject({ method: 'POST', url: '/chat/upload', headers: { 'x-user': user, 'content-type': type }, payload: fs.readFileSync(file) });
  return { code: r.statusCode, body: r.json() };
};
const avg = (arr) => arr.reduce((a, b) => a + b, 0) / Math.max(1, arr.length);
const slice = (p, from, to) => p.slice(from, to);
// الشرائح 48 على 4 ثوانٍ = 12 شريحة لكل ثانية؛ نتجنّب شرائح الحدود لأن ترميز AAC يلطّخها قليلاً
const checkShape = (p, label) => {
  check(Array.isArray(p) && p.length === 48, `${label}: 48 peaks`, String(p?.length));
  check(p.every((v) => typeof v === 'number' && v >= 0 && v <= 1), `${label}: all in 0..1`);
  check(Math.max(...p) === 1, `${label}: normalised so the loudest slice is 1`, String(Math.max(...p)));
  check(p.every((v) => Math.round(v * 1000) / 1000 === v), `${label}: rounded to 3 decimals`);
  const loud1 = avg(slice(p, 1, 11)), quiet = avg(slice(p, 13, 23)), loud2 = avg(slice(p, 25, 35)), silent = avg(slice(p, 37, 47));
  check(loud1 > 0.7 && loud2 > 0.7, `${label}: loud seconds high`, `${loud1.toFixed(2)} / ${loud2.toFixed(2)}`);
  check(quiet > 0.03 && quiet < 0.3, `${label}: quiet second ~10%`, quiet.toFixed(3));
  check(silent < 0.05, `${label}: silent second ~0`, silent.toFixed(3));
};

const st = (await app.inject({ method: 'GET', url: '/chat/status' })).json();
check(st.ok && st.transcode && st.peaks === true, 'status: peaks available', JSON.stringify(st));

// ---- رفع wav: يُحوَّل إلى m4a ثم تُحسب الموجة من الملف المحوَّل
let r = await upload(wav, 'audio/wav');
check(r.code === 200 && r.body.url.endsWith('.m4a') && r.body.kind === 'audio', 'wav upload → m4a', JSON.stringify({ ...r.body, peaks: undefined }));
checkShape(r.body.peaks, 'wav→m4a upload');
const name1 = r.body.url.split('/').pop();
check(fs.existsSync(path.join(process.env.CHAT_MEDIA_DIR, `${name1}.peaks.json`)), 'peaks cached beside the file as <name>.peaks.json');
const cached = JSON.parse(fs.readFileSync(path.join(process.env.CHAT_MEDIA_DIR, `${name1}.peaks.json`), 'utf8'));
check(JSON.stringify(cached.peaks) === JSON.stringify(r.body.peaks) && cached.n === 48, 'cache holds the same peaks');

// ---- رفع m4a مباشرة (لا تحويل): الموجة تُحسب أيضاً
r = await upload(m4a, 'audio/mp4');
check(r.code === 200 && r.body.url.endsWith('.m4a'), 'm4a upload kept as is', JSON.stringify({ ...r.body, peaks: undefined }));
checkShape(r.body.peaks, 'm4a upload');
const name2 = r.body.url.split('/').pop();

// ---- GET /chat/peaks: بالاسم، وبالرابط كاملاً، ومن الذاكرة
let g = await app.inject({ method: 'GET', url: `/chat/peaks?name=${name1}` });
check(g.statusCode === 200 && JSON.stringify(g.json().peaks) === JSON.stringify(cached.peaks) && g.json().n === 48, 'GET /chat/peaks?name= returns the cached peaks', String(g.statusCode));
check(/immutable/.test(g.headers['cache-control'] || ''), 'computed peaks are cacheable');
g = await app.inject({ method: 'GET', url: `/chat/peaks?name=${encodeURIComponent('/chat/media/' + name2)}` });
check(g.statusCode === 200 && g.json().peaks.length === 48, 'full url accepted as name');
g = await app.inject({ method: 'GET', url: `/chat/peaks?name=${encodeURIComponent('https://naslife.app/chat/media/' + name2 + '?x=1')}` });
check(g.statusCode === 200 && g.json().peaks.length === 48, 'absolute url with query accepted');

// ---- ملف قديم بلا ذاكرة: يُحسب عند أول طلب
const oldName = 'mtyold01-' + 'a'.repeat(24) + '.m4a';
fs.copyFileSync(m4a, path.join(process.env.CHAT_MEDIA_DIR, oldName));
g = await app.inject({ method: 'GET', url: `/chat/peaks?name=${oldName}` });
check(g.statusCode === 200 && g.json().peaks.length === 48 && Math.max(...g.json().peaks) === 1, 'old file: computed on demand');
check(fs.existsSync(path.join(process.env.CHAT_MEDIA_DIR, `${oldName}.peaks.json`)), 'old file: cache written');
// طلبان متزامنان لملف واحد يتشاركان الحساب
const old2 = 'mtyold02-' + 'b'.repeat(24) + '.m4a';
fs.copyFileSync(m4a, path.join(process.env.CHAT_MEDIA_DIR, old2));
const [c1, c2] = await Promise.all([app.inject({ method: 'GET', url: `/chat/peaks?name=${old2}` }), app.inject({ method: 'GET', url: `/chat/peaks?name=${old2}` })]);
check(c1.statusCode === 200 && c2.statusCode === 200 && JSON.stringify(c1.json()) === JSON.stringify(c2.json()), 'concurrent requests share one computation');

// ---- الرفض: اسم غير صالح، تجاوز مسار، ملف غير صوتي، ملف مفقود
for (const bad of ['../../etc/passwd', 'x.m4a', 'mtyold01-' + 'a'.repeat(24) + '.m4a.peaks.json', '']) {
  g = await app.inject({ method: 'GET', url: `/chat/peaks?name=${encodeURIComponent(bad)}` });
  check(g.statusCode === 404, `invalid name → 404 (${bad || 'empty'})`, String(g.statusCode));
}
g = await app.inject({ method: 'GET', url: `/chat/peaks?name=mtyold09-${'c'.repeat(24)}.m4a` });
check(g.statusCode === 404, 'missing file → 404');
const pngName = 'mtypng01-' + 'd'.repeat(24) + '.png';
fs.writeFileSync(path.join(process.env.CHAT_MEDIA_DIR, pngName), Buffer.from('not an image'));
g = await app.inject({ method: 'GET', url: `/chat/peaks?name=${pngName}` });
check(g.statusCode === 404, 'non-audio file → 404');
// الملف المسمّى بالموجة لا يُقدَّم من /chat/media (النقطتان لا تطابقان النمط)
g = await app.inject({ method: 'GET', url: `/chat/media/${name1}.peaks.json` });
check(g.statusCode === 404, 'peaks cache file is not servable as media');

// ---- صوت تالف: الرفع ينجح بلا موجة، والطلب يعيد peaks:null بلا 5xx
r = await app.inject({ method: 'POST', url: '/chat/upload', headers: { 'x-user': 'SA0000001', 'content-type': 'audio/mp4' }, payload: Buffer.from('definitely not audio') });
check(r.statusCode === 200 && r.json().url.endsWith('.m4a') && r.json().peaks === null, 'broken audio: upload ok, peaks null', r.body.slice(0, 120));
const brokenName = r.json().url.split('/').pop();
g = await app.inject({ method: 'GET', url: `/chat/peaks?name=${brokenName}` });
check(g.statusCode === 200 && g.json().peaks === null && !/immutable/.test(g.headers['cache-control'] || ''), 'broken audio: GET → 200 {peaks:null}, not cached');
check(!fs.existsSync(path.join(process.env.CHAT_MEDIA_DIR, `${brokenName}.peaks.json`)), 'no cache file for a failed computation');

// ---- الصور والفيديو لا تحمل peaks
r = await app.inject({ method: 'POST', url: '/chat/upload', headers: { 'x-user': 'SA0000001', 'content-type': 'image/png' }, payload: Buffer.from('png?') });
check(r.statusCode === 200 && !('peaks' in r.json()), 'image upload has no peaks field');

// ---- الحذف يزيل ملف الموجة أيضاً
await globalThis.naslifeMediaDelete(`/chat/media/${name1}`);
check(!fs.existsSync(path.join(process.env.CHAT_MEDIA_DIR, name1)) && !fs.existsSync(path.join(process.env.CHAT_MEDIA_DIR, `${name1}.peaks.json`)), 'naslifeMediaDelete removes the peaks cache too');

await app.close(); await pool.end();
fs.rmSync(tmp, { recursive: true, force: true });
console.log(fails ? `\n${fails} FAILED` : '\nALL CHAT PEAKS TESTS PASSED');
process.exit(fails ? 1 : 0);
