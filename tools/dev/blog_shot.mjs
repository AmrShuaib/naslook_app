import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';
const b = await chromium.launch({ headless: true, executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--no-sandbox'] });
const c = await b.newContext({ viewport: { width: 400, height: 900 }, deviceScaleFactor: 1 });
const p = await c.newPage();
await p.goto('http://127.0.0.1:8095/blog'); await p.waitForTimeout(500);
await p.screenshot({ path: process.argv[2] + '-list.png' });
await p.goto('http://127.0.0.1:8095/blog/dammam-circles'); await p.waitForTimeout(500);
await p.screenshot({ path: process.argv[2] + '-post.png', fullPage: true });
await b.close(); console.log('shots ok');
