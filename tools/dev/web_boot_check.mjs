// فحص إقلاع نسخة الويب المبنية في متصفح حقيقي تحت سياسة أمان الموقع الحي (لا سكربتات مضمّنة):
// boot.js يُحمَّل، مقدمة الشعار تظهر فوراً ثم تُزال بعد أول إطار من Flutter، وFlutter يرسم، ولا مخالفة CSP.
// التشغيل: node tools/dev/web_boot_check.mjs [build/web]
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const DIR = path.resolve(process.argv[2] || 'build/web');
const CSP = "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; media-src 'self' blob:; font-src 'self' data: https://fonts.gstatic.com; connect-src 'self' https://fonts.gstatic.com; worker-src 'self' blob:; manifest-src 'self'";
const TYPES = { '.html': 'text/html', '.js': 'application/javascript', '.mjs': 'application/javascript', '.json': 'application/json', '.wasm': 'application/wasm', '.png': 'image/png', '.ttf': 'font/ttf', '.otf': 'font/otf' };

const server = http.createServer((req, res) => {
  let p = decodeURIComponent(req.url.split('?')[0]);
  if (p === '/') p = '/index.html';
  const f = path.join(DIR, p);
  if (!f.startsWith(DIR) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404, { 'content-type': 'application/json' }); res.end('{}'); return; }
  res.writeHead(200, { 'content-type': TYPES[path.extname(f)] || 'application/octet-stream', 'cache-control': 'no-cache', 'content-security-policy': CSP });
  res.end(fs.readFileSync(f));
});
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const browser = await chromium.launch();
const page = await (await browser.newContext({ locale: 'ar-SA', viewport: { width: 390, height: 844 } })).newPage();
const errors = [];
page.on('console', (m) => { if (m.type() === 'error' && /Content Security Policy/i.test(m.text())) errors.push(m.text()); });
page.on('pageerror', (e) => errors.push('pageerror ' + e.message));
const fail = [];
try {
  await page.goto(`http://127.0.0.1:${server.address().port}/`);
  const early = await page.evaluate(() => {
    const s = document.getElementById('splash'), img = s && s.querySelector('img');
    return { present: !!s, visible: !!s && getComputedStyle(s).visibility !== 'hidden', imgOk: !!img && img.complete && img.naturalWidth > 0, imgW: img ? img.getBoundingClientRect().width : 0 };
  });
  if (!early.present || !early.visible) fail.push('splash not shown at start');
  await page.waitForFunction(() => { const i = document.querySelector('#splash img'); return !i || (i.complete && i.naturalWidth > 0); }, null, { timeout: 5000 }).catch(() => fail.push('splash logo did not load'));
  await page.waitForSelector('flutter-view', { timeout: 40000 }).catch(() => fail.push('flutter-view never appeared'));
  await page.waitForFunction(() => !document.getElementById('splash'), null, { timeout: 8000 }).catch(() => fail.push('splash not removed after first frame'));
  const boot = await page.evaluate(() => performance.getEntriesByType('resource').some((e) => /boot\.js/.test(e.name)));
  if (!boot) fail.push('boot.js not loaded');
  if (errors.length) fail.push('errors: ' + errors.slice(0, 3).join(' | '));
  console.log(JSON.stringify({ early, boot }));
} finally {
  await browser.close();
  server.close();
}
console.log(fail.length ? 'FAIL\n- ' + fail.join('\n- ') : 'ok  splash shown, removed after first frame; boot.js loaded; no CSP errors');
process.exit(fail.length ? 1 : 0);
