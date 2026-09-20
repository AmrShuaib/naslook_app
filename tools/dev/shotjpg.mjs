// لقطات JPEG لشاشات التطبيق التجريبي بحجم هاتف لاستخدامها في صفحات الهبوط.
import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';
const out = process.argv[2];
const browser = await chromium.launch({ headless: true, executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--no-sandbox'] });
const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 1, locale: 'ar' });
await ctx.addInitScript((v) => { try { localStorage.setItem('flutter.naslife.session.v2', v); } catch (e) {} }, JSON.stringify(JSON.stringify({ token: 'tok', user: { id: 'SA0000001', nickname: 'amr' } })));
const page = await ctx.newPage();
await page.goto('http://127.0.0.1:8091/', { waitUntil: 'load', timeout: 60000 });
await page.waitForTimeout(14000);
const shots = [['home', null], ['map', [272, 815]], ['circles', [194, 815]], ['chats', [116, 815]]];
for (const [name, click] of shots) {
  if (click) { await page.mouse.click(click[0], click[1]); await page.waitForTimeout(2500); }
  await page.screenshot({ path: `${out}/${name}.jpg`, type: 'jpeg', quality: 72 });
}
await browser.close();
console.log('done');
