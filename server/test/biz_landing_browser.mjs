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
// خادم وهمي للتسجيل بأشكال الردود الحقيقية؛ يسجّل كل نداء لنفحص التسلسل والحمولة
const calls = []; let codeOk = false, ups = 0;
app.addContentTypeParser(['image/png', 'image/jpeg', 'image/webp'], { parseAs: 'buffer' }, (req, body, done) => done(null, body));
const rec = (req) => { const c = { url: req.url, body: Buffer.isBuffer(req.body) ? null : req.body, token: req.headers['x-token'] || null, type: String(req.headers['content-type'] || '').split(';')[0], bytes: Buffer.isBuffer(req.body) ? req.body.length : 0 }; calls.push(c); return c; };
app.post('/auth/register', async (req, reply) => { rec(req); return reply.code(202).send({ email: req.body.email, verified: false, pending: true, codeSent: true }); });
app.post('/auth/verify', async (req, reply) => { rec(req); return codeOk ? { ok: true, verified: true } : reply.code(400).send({ error: 'bad-code' }); });
app.post('/auth/resend', async (req) => { rec(req); return { ok: true }; });
app.post('/auth/login', async (req, reply) => { rec(req); return req.body.password === 'wrong' ? reply.code(401).send({ error: 'bad-credentials' }) : { token: 'TOK', user: { id: 'SA1234567' } }; });
app.post('/me/adult-attest', async (req) => { rec(req); return { ok: true, adult: true }; });
app.post('/chat/upload', async (req, reply) => { const c = rec(req); if (c.token !== 'TOK') return reply.code(401).send({ error: 'unauthorized' }); ups++; return { url: `/chat/media/up${ups}.png`, type: 'image/png', kind: 'image', size: c.bytes }; });
app.post('/biz/register', async (req, reply) => { const c = rec(req); if (c.token !== 'TOK') return reply.code(401).send({ error: 'unauthorized' }); return { biz: { id: 'biz-test-1', nameAr: req.body.nameAr }, completeness: {} }; });
app.post('/biz/:id/verification', async (req) => { rec(req); return { status: 'pending' }; });
app.patch('/biz/:id', async (req) => { rec(req); return { id: req.params.id }; });
app.post('/biz/:id/items', async (req, reply) => { rec(req); return req.body.title === 'ممنوع' ? reply.code(400).send({ error: 'banned-words' }) : { id: 'it-' + calls.length }; });
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
  // ---- نماذج التسجيل: تسلسل حقيقي على خادم وهمي بأشكال ردود الخادم (auth_alias, chat_tools, biz_onboard)
  calls.length = 0; codeOk = false; ups = 0;
  await page.goto(base + '/business/register'); await page.evaluate(() => document.fonts.ready); await page.waitForTimeout(300);
  const r = await page.evaluate(() => ({ over: document.documentElement.scrollWidth > document.documentElement.clientWidth, cats: document.querySelectorAll('#rg-cats input').length, imgs: [...document.images].filter((i) => !i.complete || i.naturalWidth === 0).length }));
  ok(!r.over && r.cats === 15 && r.imgs === 0, `${w}px register: no horizontal scroll, ${r.cats} categories, logo loaded`);
  await page.click('#rg-go');
  ok(await page.evaluate(() => document.querySelectorAll('.rg-f.bad').length >= 8 && document.getElementById('rg-sum').classList.contains('on')) && calls.length === 0, `${w}px register: an empty form is refused before any request`);
  // نموذج العمل الحر، خدمة متنقلة، حساب جديد
  await page.check('input[name=entity][value=freelance]', { force: true });
  ok((await page.textContent('#rg-ver-title')) === 'توثيق وثيقة العمل الحر', `${w}px register: the freelance form asks for the freelance document`);
  await page.check('input[name=category][value=salon]', { force: true });
  await page.fill('#rg-nameAr', 'صيانة البيت'); await page.setInputFiles('#rg-logo', png);
  await page.check('input[name=presence][value=mobile]', { force: true });
  await page.click('#rg-locate'); await page.waitForFunction(() => /حُدد موقعك/.test(document.getElementById('rg-coord').textContent), null, { timeout: 12000 });
  await page.selectOption('#rg-city', 'جدة'); await page.fill('#rg-phone', '0512345678');
  await page.fill('#rg-entno', 'FL12345678'); await page.setInputFiles('#rg-doc', png);
  await page.click('#rg-item-add');
  ok(await page.evaluate(() => !document.querySelector('.rg-item .times').hidden && /خدمة/.test(document.getElementById('rg-item-add').textContent)), `${w}px register: a salon circle asks each service for its daily times`);
  await page.fill('.rg-item .t', 'صيانة مكيف'); await page.fill('.rg-item .price', '150'); await page.fill('.rg-item .times', '9:00، 16:30');
  await page.fill('#rg-nick', 'Bad Nick'); await page.fill('#rg-email', 'Salem@Example.com'); await page.fill('#rg-pass', 'secret-123'); await page.check('#rg-agree');
  await page.click('#rg-go');
  ok(await page.evaluate(() => document.querySelector('[data-f=nick]').classList.contains('bad')) && calls.length === 0, `${w}px register: a username the server would reject is caught first`);
  await page.fill('#rg-nick', 'salem_fix'); await page.click('#rg-go');
  await page.waitForFunction(() => !document.getElementById('rg-code').hidden, null, { timeout: 8000 });
  ok(calls.length === 1 && calls[0].url === '/auth/register' && calls[0].body.email === 'salem@example.com' && calls[0].body.nickname === 'salem_fix' && calls[0].body.acceptTerms === true, `${w}px register: a new account is created first and the email code is asked for`);
  await page.fill('#rg-code-in', '111111'); await page.click('#rg-code-go');
  await page.waitForFunction(() => /غير صحيح/.test(document.getElementById('rg-code-msg').textContent), null, { timeout: 8000 });
  ok(true, `${w}px register: a wrong code is refused with a message`);
  codeOk = true; await page.fill('#rg-code-in', '246810'); await page.click('#rg-code-go');
  await page.waitForFunction(() => !document.getElementById('rg-done').hidden, null, { timeout: 15000 });
  const seq = calls.map((c) => c.url);
  ok(JSON.stringify(seq.filter((u) => u !== '/me/adult-attest')) === JSON.stringify(['/auth/register', '/auth/verify', '/auth/verify', '/auth/login', '/chat/upload', '/biz/register', '/chat/upload', '/biz/biz-test-1/verification', '/biz/biz-test-1/items']), `${w}px register: verify, login, upload logo, register, upload document, verification` + ' [' + seq.join(' ') + ']');
  const reg = calls.find((c) => c.url === '/biz/register'), ver = calls.find((c) => /verification/.test(c.url)), svc = calls.find((c) => /items$/.test(c.url));
  ok(svc.body.title === 'صيانة مكيف' && svc.body.price === 150 && JSON.stringify(svc.body.meta.times) === '["09:00","16:30"]', `${w}px register: the service is added with its price and normalised times`);
  ok(reg.token === 'TOK' && reg.body.category === 'salon' && reg.body.nameAr === 'صيانة البيت' && reg.body.presence === 'mobile' && reg.body.radiusKm === 15 && reg.body.phone === '+966512345678' && reg.body.role === 'owner' && reg.body.logoUrl === '/chat/media/up1.png' && Math.abs(reg.body.lat - 21.5) < 0.01, `${w}px register: the circle is sent with the server's field names and the device location`);
  ok(ver.body.entityKind === 'freelance' && ver.body.entityNumber === 'FL12345678' && ver.body.docUrl === '/chat/media/up2.png', `${w}px register: the freelance document goes to verification`);
  ok(calls.filter((c) => c.url === '/chat/upload').every((c) => c.type === 'image/png' && c.bytes > 100 && c.token === 'TOK'), `${w}px register: images are uploaded as raw bytes with the session`);
  ok(/c\/biz-test-1$/.test(await page.getAttribute('#rg-done-link', 'href')) && (await page.textContent('#rg-done-name')) === 'صيانة البيت' && /أُرسل/.test(await page.textContent('#rg-done-ver')), `${w}px register: the final screen shows the circle link`);
  // حساب قائم، سجل تجاري، «سأوثّق لاحقاً»، بلا إذن موقع: وسط المدينة
  calls.length = 0;
  await page.goto(base + '/business/register'); await page.waitForTimeout(200);
  await page.check('input[name=category][value=company]', { force: true }); await page.fill('#rg-nameAr', 'أريب الرقمية'); await page.setInputFiles('#rg-logo', png);
  await page.selectOption('#rg-city', 'الدمام'); await page.fill('#rg-phone', '512345678');
  await page.fill('#rg-desc', 'قصير'); await page.fill('#rg-sector', 'حلول رقمية'); await page.fill('#rg-web', 'https://areebd.sa'); await page.fill('#rg-address', 'طريق الملك فهد');
  await page.selectOption('#rg-hmode', 'range'); await page.selectOption('#rg-hfrom', '0'); await page.selectOption('#rg-hto', '4'); await page.fill('#rg-hopen', '09:00'); await page.fill('#rg-hclose', '17:30');
  ok(/الأحد إلى الخميس 9:00 ص – 5:30 م/.test(await page.textContent('#rg-hprev')), `${w}px register: working hours are written in the form the server parses`);
  await page.setInputFiles('#rg-cover', png);
  for (const [t, d] of [['تطوير التطبيقات', 'تطبيقات جوال وويب'], ['ممنوع', ''], ['الاستشارات', '']]) { await page.click('#rg-item-add'); const row = page.locator('.rg-item').last(); await row.locator('.t').fill(t); if (d) await row.locator('.d').fill(d); }
  await page.click('#rg-item-add'); // صف فارغ يُتجاهل
  await page.fill('#rg-entno', '10101234'); await page.check('input[name=acc][value=login]', { force: true });
  ok(await page.evaluate(() => document.querySelector('[data-f=nick]').hidden), `${w}px register: an existing account needs no username`);
  await page.fill('#rg-email', 'owner@example.com'); await page.fill('#rg-pass', 'wrong'); await page.check('#rg-agree'); await page.click('#rg-go');
  ok(await page.evaluate(() => document.querySelector('[data-f=entityNumber]').classList.contains('bad') && document.querySelector('[data-f=description]').classList.contains('bad')) && calls.length === 0, `${w}px register: a ten-digit registration number and a real description are required`);
  await page.fill('#rg-desc', 'شركة سعودية تبني منتجات رقمية للأعمال.');
  await page.check('#rg-later'); await page.click('#rg-go');
  await page.waitForFunction(() => document.getElementById('rg-sum').classList.contains('on') && /غير صحيحة/.test(document.getElementById('rg-sum').textContent), null, { timeout: 8000 });
  ok(calls.length === 1 && calls[0].url === '/auth/login' && calls[0].body.handle === 'owner@example.com', `${w}px register: a wrong password stops at login with a clear message`);
  await page.fill('#rg-pass', 'right-pass'); await page.click('#rg-go');
  await page.waitForFunction(() => !document.getElementById('rg-done').hidden, null, { timeout: 15000 });
  const reg2 = calls.find((c) => c.url === '/biz/register');
  const patch = calls.find((c) => c.url === '/biz/biz-test-1' ), its = calls.filter((c) => /items$/.test(c.url));
  ok(reg2.body.hours === 'الأحد إلى الخميس 9:00 ص – 5:30 م' && /شركة سعودية/.test(reg2.body.description) && reg2.body.address === 'طريق الملك فهد، الدمام', `${w}px register: description, hours and address go with the circle`);
  ok(patch && patch.body.sector === 'حلول رقمية' && patch.body.website === 'https://areebd.sa' && /^\/chat\/media\//.test(patch.body.coverUrl), `${w}px register: speciality, website and cover are saved`);
  ok(its.length === 3 && its[0].body.title === 'تطوير التطبيقات' && its[0].body.description === 'تطبيقات جوال وويب' && its[0].body.price === 0 && its[0].body.meta === undefined, `${w}px register: three items are added and the empty row is skipped`);
  ok(/لم يُحفظ/.test(await page.textContent('#rg-done-warn')) && /ممنوع/.test(await page.textContent('#rg-done-warn')) && /2 من الأصناف/.test(await page.textContent('#rg-done-data-s')), `${w}px register: a refused item is reported without losing the circle or the other items`);
  ok(reg2.body.presence === 'fixed' && reg2.body.radiusKm === undefined && Math.abs(reg2.body.lat - 26.4207) < 0.001 && !calls.some((c) => /verification/.test(c.url)) && calls.filter((c) => c.url === '/chat/upload').length === 2, `${w}px register: verify later sends no document, and the city centre stands in for the location`);
  ok(/لاحقاً/.test(await page.textContent('#rg-done-ver')), `${w}px register: the final screen says verification is still to do`);
  ok(errs.filter((e) => !/401|400/.test(e)).length === 0, `${w}px register: no CSP or JS errors` + (errs.length ? ': ' + errs.slice(0, 3).join(' | ') : ''));
  if (process.env.SHOT && w === 390) await page.screenshot({ path: process.env.SHOT });
  await page.close();
}
await browser.close(); await app.close();
console.log(fail ? `${fail} FAILED` : 'ALL OK'); process.exit(fail ? 1 : 0);
