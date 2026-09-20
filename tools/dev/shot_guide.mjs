import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';
const b = await chromium.launch({ headless: true, executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--no-sandbox'] });
const p = await (await b.newContext({ viewport: { width: 820, height: 1000 } })).newPage();
const html = '<!doctype html><html><head><meta charset="utf-8"></head><body>' + (await import('node:fs')).readFileSync(process.argv[2], 'utf8') + '</body></html>';
await p.setContent(html, { waitUntil: 'load' });
await p.waitForTimeout(1500);
await p.screenshot({ path: process.argv[3], fullPage: true });
await b.close();
