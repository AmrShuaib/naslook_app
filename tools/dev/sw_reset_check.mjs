// فحص في متصفح حقيقي: مستخدم سجّلت نسخة قديمة عنده عامل خدمة يخزّن التطبيق، ثم نشرنا النسخة الجديدة.
// يتحقق أن web/boot.js وweb/sw_reset.js (منشوراً باسم flutter_service_worker.js) يعيدانه إلى النسخة الجديدة وحده،
// تحت سياسة أمان الموقع الحي نفسها (لا سكربتات مضمّنة)، وأن تسجيل الإشعارات push_sw.js يبقى.
// التشغيل: node tools/dev/sw_reset_check.mjs
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { chromium } = require('playwright');
const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), '../..');
const CSP = "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; worker-src 'self' blob:";

// عامل خدمة على نمط Flutter القديم: index أونلاين أولاً (أو من المخزن في الحالة الأسوأ) وبقية الملفات من المخزن أولاً
const oldSw = (indexCacheFirst) => `
const CACHE = 'flutter-app-cache';
const RESOURCES = { '/': 1, 'old_boot.js': 1, 'app.js': 1 };
self.addEventListener('install', (e) => { self.skipWaiting(); e.waitUntil(caches.open(CACHE).then((c) => c.addAll(['/', 'old_boot.js', 'app.js']))); });
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));
self.addEventListener('fetch', (e) => {
  const origin = self.location.origin;
  let key = e.request.url.substring(origin.length + 1).split('?')[0];
  if (key === '' || key === 'index.html') key = '/';
  if (!RESOURCES[key]) return;
  const fromCache = () => caches.open(CACHE).then((c) => c.match(key === '/' ? '/' : e.request.url.split('?')[0]).then((r) => r || fetch(e.request)));
  if (key === '/' && !${indexCacheFirst}) {
    e.respondWith(fetch(e.request).catch(fromCache));
    return;
  }
  e.respondWith(fromCache());
});`;

function makeDirs(indexCacheFirst) {
  const base = fs.mkdtempSync(path.join(os.tmpdir(), 'swcheck-'));
  const oldDir = path.join(base, 'old'), newDir = path.join(base, 'new');
  fs.mkdirSync(oldDir); fs.mkdirSync(newDir);
  fs.writeFileSync(path.join(oldDir, 'index.html'), '<!DOCTYPE html><html><body><script src="old_boot.js"></script><script src="app.js"></script></body></html>');
  fs.writeFileSync(path.join(oldDir, 'old_boot.js'), "navigator.serviceWorker.register('flutter_service_worker.js?v=111');");
  fs.writeFileSync(path.join(oldDir, 'app.js'), "document.body.dataset.v = 'OLD';");
  fs.writeFileSync(path.join(oldDir, 'flutter_service_worker.js'), oldSw(indexCacheFirst));
  // النسخة الجديدة: index.html الحقيقي يحمّل boot.js ثم التطبيق (هنا app.js بدل flutter_bootstrap.js)
  const realIndex = fs.readFileSync(path.join(ROOT, 'web/index.html'), 'utf8');
  if (!/<script src="boot\.js"><\/script>/.test(realIndex) || /<script>(?!<)/.test(realIndex)) throw new Error('web/index.html: يجب أن يحمّل boot.js وألا يحوي سكربتاً مضمّناً');
  fs.writeFileSync(path.join(newDir, 'index.html'), '<!DOCTYPE html><html><body><script src="boot.js"></script><script src="app.js"></script></body></html>');
  fs.copyFileSync(path.join(ROOT, 'web/boot.js'), path.join(newDir, 'boot.js'));
  fs.copyFileSync(path.join(ROOT, 'web/sw_reset.js'), path.join(newDir, 'flutter_service_worker.js'));
  fs.copyFileSync(path.join(ROOT, 'web/push_sw.js'), path.join(newDir, 'push_sw.js'));
  fs.writeFileSync(path.join(newDir, 'app.js'), "document.body.dataset.v = 'NEW';");
  return { oldDir, newDir };
}

async function scenario(name, indexCacheFirst) {
  const { oldDir, newDir } = makeDirs(indexCacheFirst);
  let dir = oldDir;
  const server = http.createServer((req, res) => {
    let p = decodeURIComponent(req.url.split('?')[0]);
    if (p === '/') p = '/index.html';
    const f = path.join(dir, p);
    if (!f.startsWith(dir) || !fs.existsSync(f)) { res.writeHead(404); res.end(); return; }
    const type = f.endsWith('.html') ? 'text/html' : 'application/javascript';
    res.writeHead(200, { 'content-type': type, 'cache-control': 'no-cache', 'content-security-policy': CSP });
    res.end(fs.readFileSync(f));
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const url = `http://127.0.0.1:${server.address().port}/`;
  const browser = await chromium.launch();
  const page = await (await browser.newContext()).newPage();
  const errors = [];
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  const version = () => page.evaluate(() => document.body && document.body.dataset.v);
  const controller = () => page.evaluate(() => (navigator.serviceWorker.controller ? navigator.serviceWorker.controller.scriptURL : null));
  try {
    await page.goto(url);
    await page.waitForFunction(() => !!navigator.serviceWorker.controller, null, { timeout: 10000 });
    await page.reload();
    if ((await version()) !== 'OLD' || !(await controller())) throw new Error('الإعداد: النسخة القديمة لم تُخزَّن');
    dir = newDir; // نشر النسخة الجديدة
    await page.reload().catch(() => {});
    await page.waitForFunction(() => document.body && document.body.dataset.v === 'NEW' && !navigator.serviceWorker.controller, null, { timeout: 20000 });
    const regs = await page.evaluate(async () => (await navigator.serviceWorker.getRegistrations()).map((r) => (r.active || r.waiting || r.installing || {}).scriptURL));
    const caches = await page.evaluate(async () => caches.keys());
    if (regs.some((u) => u && /flutter_service_worker/.test(u))) throw new Error('بقي تسجيل العامل القديم: ' + regs);
    if (caches.length) throw new Error('بقي مخزن: ' + caches);
    // الإشعارات: تسجيل push_sw.js يبقى بعد إعادة التحميل ولا تحدث إعادة تحميل إضافية
    await page.evaluate(async () => { await navigator.serviceWorker.register('push_sw.js'); await navigator.serviceWorker.ready; });
    await page.reload();
    await page.waitForTimeout(1500);
    const after = await page.evaluate(async () => (await navigator.serviceWorker.getRegistrations()).map((r) => (r.active || r.waiting || r.installing || {}).scriptURL));
    if (!after.some((u) => u && /push_sw\.js/.test(u))) throw new Error('أُلغي تسجيل الإشعارات: ' + after);
    if ((await version()) !== 'NEW') throw new Error('بعد تسجيل الإشعارات: ' + (await version()));
    const csp = errors.filter((e) => /Content Security Policy/i.test(e));
    if (csp.length) throw new Error('مخالفة CSP: ' + csp.join(' | '));
    console.log(`ok  ${name}`);
    return true;
  } catch (e) {
    console.log(`FAIL ${name}: ${e.message}`);
    return false;
  } finally {
    await browser.close();
    server.close();
  }
}

const results = [
  await scenario('index online-first (Flutter old SW): boot.js reloads once to the new version', false),
  await scenario('index cache-first (worst case): sw_reset.js kills the worker and reloads the tab', true),
];
process.exit(results.every(Boolean) ? 0 : 1);
