// فحص صفحة /business في متصفح حقيقي تحت سياسة أمان الموقع الحي: لا مخالفة CSP، الخطوط والصور تُحمَّل،
// ولا تمرير أفقي على الجوال وسطح المكتب. ليس ضمن «all» (يحتاج Chromium).
// التشغيل: cd server/test && node biz_landing_browser.mjs   (SHOT=/path.png لحفظ لقطة)
import Fastify from 'fastify';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
const { chromium } = createRequire(import.meta.url)('playwright');
const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), '../..');
const CSP = "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob: https://server.arcgisonline.com; font-src 'self' data: https://fonts.gstatic.com; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'; object-src 'none'";
const app = Fastify();
app.addHook('onSend', async (req, reply) => { reply.header('content-security-policy', CSP); });
app.register((await import('../biz_landing.js')).default, {});
// خطوط التطبيق كما يخدمها الموقع الحي من /assets/fonts
app.get('/assets/fonts/:f', async (req, reply) => {
  const f = path.join(ROOT, 'fonts', path.basename(req.params.f));
  return fs.existsSync(f) ? reply.type('font/ttf').send(fs.readFileSync(f)) : reply.code(404).send('');
});
app.get('/favicon.png', async (req, reply) => reply.type('image/png').send(fs.readFileSync(path.join(ROOT, 'web/favicon.png'))));
await app.listen({ port: 0, host: '127.0.0.1' });
const base = `http://localhost:${app.server.address().port}`;
const browser = await chromium.launch();
let fail = 0; const ok = (c, m) => { console.log((c ? 'ok   ' : 'FAIL ') + m); if (!c) fail++; };
for (const [w, h] of [[390, 844], [1280, 900]]) {
  const page = await (await browser.newContext({ locale: 'ar-SA', viewport: { width: w, height: h } })).newPage();
  const errs = [];
  page.on('pageerror', (e) => errs.push('js: ' + e.message));
  page.on('console', (m) => { if (m.type() === 'error') errs.push(m.text().slice(0, 160)); });
  page.on('requestfailed', (r) => errs.push('failed: ' + r.url().slice(0, 100)));
  await page.goto(base + '/business'); await page.evaluate(() => document.fonts.ready); await page.waitForTimeout(300);
  const n = await page.evaluate(() => ({
    over: document.documentElement.scrollWidth > document.documentElement.clientWidth,
    imgs: [...document.images].filter((i) => !i.complete || i.naturalWidth === 0).length, total: document.images.length,
    fonts: document.fonts.check('700 20px "Baloo Bhaijaan 2"') && document.fonts.check('400 16px Rubik') && document.fonts.check('700 16px Rubik'),
    h1: getComputedStyle(document.querySelector('.lp h1')).fontFamily, dir: getComputedStyle(document.querySelector('.lp')).direction,
    icons: [...document.querySelectorAll('.lp svg.i use')].every((u) => document.querySelector(u.getAttribute('href'))),
  }));
  ok(!n.over, `${w}px: no horizontal scroll`);
  ok(n.imgs === 0 && n.total >= 10, `${w}px: all ${n.total} images loaded`);
  ok(n.fonts && /Baloo/.test(n.h1), `${w}px: app fonts loaded`);
  ok(n.dir === 'rtl' && n.icons, `${w}px: rtl, every icon resolves`);
  ok(errs.length === 0, `${w}px: no CSP, JS or network errors` + (errs.length ? ': ' + errs.slice(0, 3).join(' | ') : ''));
  if (w === 390) {
    await page.click('.lp-head .lp-btn'); // زر الرأس الظاهر على الجوال (روابط القائمة مخفية في هذا المقاس) 
    const at = await page.waitForFunction(() => { const r = document.getElementById('lp-start').getBoundingClientRect(); return r.top < 200 && r.bottom > 0; }, null, { timeout: 6000 }).then(() => true, () => false);
    ok(at, 'the call to action scrolls to "how to start"');
    await page.locator('.lp-faq summary').nth(1).click();
    ok(await page.evaluate(() => document.querySelectorAll('.lp-faq details')[1].open), 'a question opens without any script');
  }
  if (process.env.SHOT && w === 390) await page.screenshot({ path: process.env.SHOT });
  await page.close();
}
await browser.close(); await app.close();
console.log(fail ? `${fail} FAILED` : 'ALL OK'); process.exit(fail ? 1 : 0);
