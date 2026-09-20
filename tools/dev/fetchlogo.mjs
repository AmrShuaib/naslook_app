// يفتح موقع المقهى في كروم عبر وكيل الشبكة، يجمع مرشّحي الشعار (apple-touch-icon, og:image, <img> فيه logo) ويحمّل أفضلها.
import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';
import fs from 'node:fs';
const [outDir, ...sites] = process.argv.slice(2);
const proxy = process.env.HTTPS_PROXY || process.env.https_proxy;
const browser = await chromium.launch({ headless: true, executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome', args: ['--no-sandbox'], proxy: proxy ? { server: proxy } : undefined });
const ctx = await browser.newContext({ ignoreHTTPSErrors: true, userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36', viewport: { width: 1280, height: 900 } });
for (const site of sites) {
  const name = site.replace(/^https?:\/\/(www\.)?/, '').split('/')[0].split('.')[0];
  const page = await ctx.newPage();
  try {
    const resp = await page.goto(site, { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(2500);
    const cands = await page.evaluate(() => {
      const abs = (u) => { try { return new URL(u, location.href).href; } catch { return null; } };
      const out = [];
      for (const l of document.querySelectorAll('link[rel]')) { const rel = (l.getAttribute('rel') || '').toLowerCase(); if (rel.includes('icon')) out.push({ kind: rel, url: abs(l.getAttribute('href')), sizes: l.getAttribute('sizes') || '' }); }
      const og = document.querySelector('meta[property="og:image"]'); if (og) out.push({ kind: 'og:image', url: abs(og.getAttribute('content')) });
      for (const img of document.querySelectorAll('img')) { const src = img.currentSrc || img.src || ''; const alt = (img.alt || '').toLowerCase(); if (/logo/i.test(src) || alt.includes('logo') || img.closest('header, nav, .header, .navbar, .logo')) out.push({ kind: 'img', url: abs(src), w: img.naturalWidth, h: img.naturalHeight, alt: img.alt }); }
      return out.filter((c) => c.url && !c.url.startsWith('data:'));
    });
    console.log(`\n== ${name} (${resp?.status()}) ${page.url()}`);
    const uniq = [...new Map(cands.map((c) => [c.url, c])).values()];
    for (const c of uniq.slice(0, 12)) console.log('  ', c.kind, c.sizes || '', c.w ? `${c.w}x${c.h}` : '', c.url.slice(0, 140));
    let i = 0;
    for (const c of uniq.slice(0, 8)) {
      try {
        const r = await ctx.request.get(c.url, { timeout: 20000 });
        const ct = r.headers()['content-type'] || '';
        if (!r.ok() || !/image|svg|octet/.test(ct)) continue;
        const ext = ct.includes('svg') ? 'svg' : ct.includes('png') ? 'png' : ct.includes('webp') ? 'webp' : ct.includes('jpeg') ? 'jpg' : ct.includes('icon') || c.url.endsWith('.ico') ? 'ico' : 'bin';
        const body = await r.body();
        const f = `${outDir}/${name}-${i++}-${c.kind.replace(/[^a-z]/g, '')}.${ext}`;
        fs.writeFileSync(f, body); console.log('   saved', f.split('/').pop(), body.length, ct);
      } catch (e) { console.log('   dl fail', c.url.slice(0, 80), e.message.slice(0, 60)); }
    }
  } catch (e) { console.log(`\n== ${name} FAILED ${e.message.slice(0, 120)}`); }
  await page.close();
}
await browser.close();
