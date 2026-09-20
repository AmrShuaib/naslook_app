import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';
const url = process.argv[2] || 'https://naslife.app/';
const browser = await chromium.launch({ headless: true, executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--no-sandbox', '--disable-features=PostQuantumKyber,UseMLKEM,EncryptedClientHello', '--disable-background-networking', '--disable-component-update'], ...(process.env.PROBE_PROXY ? { proxy: { server: process.env.HTTPS_PROXY } } : {}) });
const ctx = await browser.newContext({ viewport: { width: 420, height: 860 }, locale: 'ar' });
if (process.env.SESSION_JSON) { await ctx.addInitScript((v) => { try { localStorage.setItem('flutter.naslife.session.v2', v); } catch (e) {} }, JSON.stringify(process.env.SESSION_JSON)); }
const page = await ctx.newPage();
const logs = [];
page.on('console', m => logs.push(`[console.${m.type()}] ${m.text().slice(0, 400)}`));
page.on('pageerror', e => logs.push(`[pageerror] ${String(e)} :: ${(e.message||'')} :: ${String(e.stack||'').slice(0, 700)}`));
page.on('requestfailed', r => logs.push(`[reqfail] ${r.url()} ${r.failure()?.errorText}`));
page.on('response', r => { if (r.status() >= 400) logs.push(`[http ${r.status()}] ${r.url()}`); });
const t0 = Date.now();
try { await page.goto(url, { waitUntil: 'load', timeout: 60000 }); } catch (e) { logs.push(`[goto] ${e.message}`); }
await page.waitForTimeout(Number(process.env.WAIT_MS || 15000));
const text = await page.evaluate(() => document.body?.innerText?.slice(0, 500) || '');
const canvases = await page.evaluate(() => document.querySelectorAll('canvas, flt-glass-pane, flutter-view').length);
const sw = await page.evaluate(async () => (await navigator.serviceWorker?.getRegistrations?.())?.length ?? -1);
await page.screenshot({ path: process.argv[3] || '/tmp/shot.png' });
console.log(`loaded in ${Date.now() - t0}ms; flutter nodes=${canvases}; sw=${sw}; text="${text.replace(/\s+/g, ' ').slice(0, 200)}"`);
console.log(logs.join('\n') || '(no console/network issues)');
await browser.close();
