// يفتح التطبيق بجلسة محقونة وينفّذ خطوات (نقر/كتابة/انتظار) ثم يلتقط صوراً.
import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';
const [url, outPrefix, stepsJson] = process.argv.slice(2);
const steps = JSON.parse(stepsJson || '[]');
const browser = await chromium.launch({ headless: true, proxy: { server: process.env.HTTPS_PROXY }, ignoreHTTPSErrors: false, executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--no-sandbox', '--disable-http2', '--disable-quic', '--use-fake-device-for-media-stream', '--use-fake-ui-for-media-stream', '--autoplay-policy=no-user-gesture-required'] });
const ctx = await browser.newContext({ ignoreHTTPSErrors: true, viewport: { width: Number(process.env.VIEWPORT_W || 420), height: Number(process.env.VIEWPORT_H || 860) }, locale: 'ar', permissions: ['microphone', 'notifications'] });
// جلسة محقونة من متغير البيئة (رمز حي + معرّف + اسم) قبل تحميل التطبيق
if (process.env.LIVE_TOKEN) {
  await ctx.addInitScript((v) => { try { localStorage.setItem('flutter.naslife.session.v2', v); } catch (e) {} },
    JSON.stringify(JSON.stringify({ token: process.env.LIVE_TOKEN, user: { id: process.env.LIVE_ID || 'SA9954961', nickname: process.env.LIVE_NICK || 'jeddahh' } })));
}
const page = await ctx.newPage();
const logs = [];
page.on('pageerror', e => logs.push('[pageerror] ' + String(e) + ' ' + String(e.stack || '').slice(0, 300)));
page.on('console', m => { if (!/tiles\//.test(m.text())) logs.push('[console.' + m.type() + '] ' + m.text().slice(0, 600)); });
await page.goto(url, { waitUntil: 'load', timeout: 60000 });
await page.waitForTimeout(Number(process.env.BOOT_MS || 14000));
let shot = 0;
for (const s of steps) {
  if (s.click) await page.mouse.click(s.click[0], s.click[1]);
  if (s.longpress) { await page.mouse.move(s.longpress[0], s.longpress[1]); await page.mouse.down(); await page.waitForTimeout(700); await page.mouse.up(); }
  if (s.type) await page.keyboard.type(s.type, { delay: 20 });
  if (s.key) await page.keyboard.press(s.key);
  if (s.upload) {
    // ننقر خيار الاختيار ثم نضع الملف مباشرة في <input type=file> الذي ينشئه image_picker (المتصفح الخفي لا يفتح نافذة اختيار)
    await page.mouse.click(s.upload[0], s.upload[1]);
    await page.waitForTimeout(1200);
    const n = await page.evaluate(() => document.querySelectorAll('input[type=file]').length);
    console.log('[upload] file inputs found: ' + n);
    if (n > 0) await page.setInputFiles('input[type=file] >> nth=-1', s.file);
  }
  if (s.move) await page.mouse.move(s.move[0], s.move[1]);
  if (s.drag) { await page.mouse.move(s.drag[0], s.drag[1]); await page.mouse.down(); for (let i = 1; i <= 12; i++) { await page.mouse.move(s.drag[0] + (s.drag[2] - s.drag[0]) * i / 12, s.drag[1] + (s.drag[3] - s.drag[1]) * i / 12); await page.waitForTimeout(16); } await page.mouse.up(); }
  if (s.wheel) await page.mouse.wheel(s.wheel[0], s.wheel[1]);
  if (s.eval) { try { console.log('[eval] ' + String(await page.evaluate(s.eval)).slice(0, 1500)); } catch (e) { console.log('[eval error] ' + e.message); } }
  await page.waitForTimeout(s.wait ?? 1200);
  if (s.shot) await page.screenshot({ path: `${outPrefix}-${++shot}-${s.shot}.png` });
}
console.log('done; shots=' + shot); console.log(logs.join('\n') || '(no page errors)');
await browser.close();
