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
const png = { name: 'logo.png', mimeType: 'image/png', buffer: fs.readFileSync(path.join(ROOT, 'web/favicon.png')) };
let fail = 0; const ok = (c, m) => { console.log((c ? 'ok   ' : 'FAIL ') + m); if (!c) fail++; };
for (const [w, h] of [[390, 844], [1280, 900]]) {
  const page = await (await browser.newContext({ locale: 'ar-SA', viewport: { width: w, height: h }, geolocation: { latitude: 21.5, longitude: 39.2 }, permissions: ['geolocation'] })).newPage();
  const errs = [];
  page.on('pageerror', (e) => errs.push('js: ' + e.message));
  page.on('console', (m) => { if (m.type() === 'error') errs.push(m.text().slice(0, 160)); });
  page.on('requestfailed', (r) => errs.push('failed: ' + r.url().slice(0, 100)));
  let posts = 0; page.on('request', (q) => { if (q.method() !== 'GET') posts++; });
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
    ok(await page.getAttribute('.lp-head .lp-btn', 'href') === '/business/register', 'the header button opens the registration forms');
    await page.locator('.lp-faq summary').nth(1).click();
    ok(await page.evaluate(() => document.querySelectorAll('.lp-faq details')[1].open), 'a question opens without any script');
  }
  // ---- نماذج التسجيل
  await page.goto(base + '/business/register'); await page.evaluate(() => document.fonts.ready); await page.waitForTimeout(300);
  const r = await page.evaluate(() => ({ over: document.documentElement.scrollWidth > document.documentElement.clientWidth, cats: document.querySelectorAll('#rg-cats input').length, imgs: [...document.images].filter((i) => !i.complete || i.naturalWidth === 0).length }));
  ok(!r.over && r.cats === 15 && r.imgs === 0, `${w}px register: no horizontal scroll, ${r.cats} categories, logo loaded`);
  await page.click('button[type=submit]');
  ok(await page.evaluate(() => document.querySelectorAll('.rg-f.bad').length >= 9 && document.getElementById('rg-sum').classList.contains('on') && document.getElementById('rg-done').hidden), `${w}px register: an empty form is refused with field errors`);
  // نموذج العمل الحر، خدمة متنقلة
  await page.check('input[name=entity][value=freelance]', { force: true });
  ok((await page.textContent('#rg-ver-title')) === 'توثيق وثيقة العمل الحر' && (await page.textContent('#rg-entno-lab')).includes('وثيقة العمل الحر'), `${w}px register: the freelance form asks for the freelance document`);
  await page.check('input[name=category][value=services]', { force: true });
  await page.fill('#rg-nameAr', 'صيانة البيت'); await page.setInputFiles('#rg-logo', png); 
  await page.check('input[name=presence][value=mobile]', { force: true });
  ok(await page.evaluate(() => !document.getElementById('rg-radius-f').hidden), `${w}px register: a mobile activity gets the service radius`);
  await page.click('#rg-locate'); await page.waitForFunction(() => /حُدد الموقع/.test(document.getElementById('rg-coord').textContent), null, { timeout: 12000 });
  await page.selectOption('#rg-city', 'جدة'); await page.fill('#rg-phone', '0512345678');
  await page.fill('#rg-entno', '123'); await page.setInputFiles('#rg-doc', png);
  await page.fill('#rg-nick', 'سالم'); await page.fill('#rg-email', 'salem@example.com'); await page.fill('#rg-pass', 'secret-123'); await page.check('#rg-agree');
  await page.click('button[type=submit]');
  ok(await page.evaluate(() => document.querySelector('[data-f=entityNumber]').classList.contains('bad') && document.querySelectorAll('.rg-f.bad').length === 1), `${w}px register: a short document number is the only error left`);
  await page.fill('#rg-entno', 'FL12345678'); await page.click('button[type=submit]');
  ok(await page.evaluate(() => !document.getElementById('rg-done').hidden && document.getElementById('rg-form').hidden && /وثيقة العمل الحر/.test(document.getElementById('rg-done-ver-s').textContent)), `${w}px register: a complete freelance form reaches the final screen`);
  ok((await page.textContent('#pv-name')) === 'صيانة البيت' && /متنقلة/.test(await page.textContent('#pv-pres')), `${w}px register: the side preview follows the form`);
  // نموذج السجل التجاري: عشرة أرقام بالضبط، و«سأوثّق لاحقاً» يعفي من الوثيقة
  await page.click('#rg-again'); await page.check('input[name=entity][value=cr]', { force: true });
  await page.fill('#rg-entno', '10101234'); await page.click('button[type=submit]');
  ok(await page.evaluate(() => document.querySelector('[data-f=entityNumber]').classList.contains('bad')), `${w}px register: a commercial registration number must be ten digits`);
  await page.check('#rg-later'); await page.click('button[type=submit]');
  ok(await page.evaluate(() => !document.getElementById('rg-done').hidden && /لاحقاً/.test(document.getElementById('rg-done-ver').textContent)), `${w}px register: "verify later" completes without a document`);
  ok(posts === 0, `${w}px register: nothing was sent to the server`);
  ok(errs.length === 0, `${w}px register: no CSP, JS or network errors` + (errs.length ? ': ' + errs.slice(0, 3).join(' | ') : ''));
  if (process.env.SHOT && w === 390) await page.screenshot({ path: process.env.SHOT });
  await page.close();
}
await browser.close(); await app.close();
console.log(fail ? `${fail} FAILED` : 'ALL OK'); process.exit(fail ? 1 : 0);
