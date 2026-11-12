// فحص معرض التصاميم بمحتواه الحقيقي في متصفح، تحت سياسة أمان الموقع الحي (لا سكربتات مضمّنة ولا خطوط خارجية):
// الدخول بالرقم، ثم كل تبويب يرسم هواتفه بلا مخالفة CSP ولا خطأ JS. ليس ضمن «all» (يحتاج Chromium).
// التشغيل: cd server/test && node --import ./db_env.mjs screens_browser.mjs
import Fastify from 'fastify';
import pg from 'pg';
import { createRequire } from 'node:module';
const { chromium } = createRequire(import.meta.url)('playwright');
const CSP = "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob: https://server.arcgisonline.com; font-src 'self' data: https://fonts.gstatic.com; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'; object-src 'none'";
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query('DROP TABLE IF EXISTS screens_access');
globalThis.naslifeIsAdmin = async (u) => u === 'ADMIN';
const app = Fastify();
app.addHook('onSend', async (req, reply) => { reply.header('content-security-policy', CSP); });
app.register((await import('../screens.js')).default, { pool, auth: async (req) => req.headers['x-user'] || null });
await app.listen({ port: 0, host: '127.0.0.1' });
const base = `http://localhost:${app.server.address().port}`;
await app.inject({ method: 'POST', url: '/screens/pin', payload: { pin: '246810' }, headers: { 'x-user': 'ADMIN' } });
const { PAGES } = await import('../screens_data.js');
const browser = await chromium.launch(); const page = await (await browser.newContext({ locale: 'ar-SA', viewport: { width: 1280, height: 900 } })).newPage();
const errs = [];
page.on('pageerror', (e) => errs.push('js: ' + e.message));
page.on('console', (m) => { if (m.type() === 'error' && /Content Security Policy/i.test(m.text())) errs.push('csp: ' + m.text().slice(0, 140)); });
let fail = 0; const ok = (c, m) => { console.log((c ? 'ok   ' : 'FAIL ') + m); if (!c) fail++; };
await page.goto(base + '/screens');
await page.fill('#pin', '111111'); await page.click('button[type=submit]');
await page.waitForFunction(() => document.getElementById('msg').textContent.length > 0);
ok((await page.textContent('#msg')).includes('غير صحيح'), 'wrong pin shows a message');
await page.fill('#pin', '246810'); await page.click('button[type=submit]');
await page.waitForURL('**/screens/' + PAGES[0].id);
for (const p of PAGES) {
  await page.goto(`${base}/screens/${p.id}`); await page.waitForTimeout(400);
  const n = await page.evaluate(() => ({ phones: document.querySelectorAll('.phone').length, tabs: document.querySelectorAll('.nstabs a').length, cur: document.querySelector('.nstabs a[aria-current]')?.textContent }));
  ok(n.phones >= 1 && n.tabs === PAGES.length && n.cur === p.title, `${p.id}: ${n.phones} phones, ${n.tabs} tabs`);
}
await page.goto(`${base}/screens/buy`); await page.click('.act'); await page.waitForTimeout(300);
ok(await page.evaluate(() => !!document.querySelector('.sheet')), 'buy: action sheet opens');
await page.screenshot({ path: process.env.SHOT || '/tmp/screens_check.png' });
await page.click('#ns-out'); await page.waitForURL('**/screens');
ok(await page.evaluate(() => !!document.getElementById('pin')), 'logout returns to the gate');
ok(errs.length === 0, 'no CSP or JS errors' + (errs.length ? ': ' + errs.slice(0, 3).join(' | ') : ''));
await browser.close(); await app.close(); await pool.end();
console.log(fail ? `${fail} FAILED` : 'ALL OK'); process.exit(fail ? 1 : 0);
