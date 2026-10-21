// اختبارات معاينة الروابط (server/chat_preview.js): خادم HTML محلي بصفحات Open Graph وتحويلات وأنواع غير HTML وبطء وأخطاء،
// وتطبيقان: واحد يسمح بالمضيفين المحليين (للاختبار) وآخر بالإعداد الافتراضي يرفضهم. يفحص التحليل وفكّ الكيانات والصور النسبية
// والترميز، والحدود (الحجم، التحويلات، المهلة، النوع)، ورفض العناوين الخاصة، والذاكرة، وحدّ المعدل، والحالة.
import Fastify from 'fastify';
import http from 'node:http';
import pg from 'pg';
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
const auth = async (req) => req.headers['x-user'] || null;
let fails = 0;
const check = (cond, label, extra = '') => { if (!cond) fails++; console.log((cond ? 'OK  ' : 'FAIL') + ' ' + label + (extra ? ' ' + extra : '')); };

// ---- خادم الصفحات المحلي
const hits = {};
const slowHolders = [];
const big = '<html><head><title>Big page</title>' + '<!-- ' + 'x'.repeat(700 * 1024) + ' -->' + '<meta property="og:title" content="Beyond the cap"></head></html>';
const PNG = Buffer.concat([Buffer.from('89504e470d0a1a0a0000000d49484452', 'hex'), Buffer.alloc(64, 7)]);
const cp1256Title = Buffer.concat([Buffer.from('<html><head><title>'), Buffer.from([0xcc, 0xcf, 0xc9]), Buffer.from('</title></head><body></body></html>')]);
const site = http.createServer((req, res) => {
  const p = req.url.split('?')[0];
  hits[p] = (hits[p] ?? 0) + 1;
  const html = (body, extra = {}) => { res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', ...extra }); res.end(body); };
  if (p === '/ok') return html('<html><head><title>Fallback title</title><meta property="og:title" content="قهوة &amp; كيك &mdash; برو 92"/><meta property=\'og:description\' content=\'أفضل V60 في جدة &#x1F600; &quot;مختصة&quot;\'><meta property="og:image" content="/img/og.jpg?x=1&amp;y=2"><meta property="og:site_name" content="Brew92"></head><body>hi</body></html>');
  if (p === '/title-only') return html('<html><head><title>\n  Just   a title &copy; 2026 </title><meta name="description" content="desc here"></head><body><meta property="og:title" content="not in head but still parsed? no: body"></body></html>');
  if (p === '/no-title') return html('<html><head><meta name="description" content="x"></head></html>');
  if (p === '/redirect') { res.writeHead(302, { location: '/ok' }); return res.end(); }
  if (p === '/redirect-rel') { res.writeHead(301, { location: 'ok' }); return res.end(); }
  if (p === '/loop') { res.writeHead(302, { location: '/loop' }); return res.end(); }
  if (/^\/chain(\d)$/.test(p)) { const n = Number(p.slice(6)); res.writeHead(302, { location: n >= 4 ? '/ok' : `/chain${n + 1}` }); return res.end(); }
  if (p === '/json') { res.writeHead(200, { 'content-type': 'application/json' }); return res.end('{"title":"nope"}'); }
  if (p === '/image') { res.writeHead(200, { 'content-type': 'image/png' }); return res.end(Buffer.alloc(10)); }
  if (p === '/slow') { slowHolders.push(res); return; }
  if (p === '/500') { res.writeHead(500, { 'content-type': 'text/html' }); return res.end('<title>err</title>'); }
  if (p === '/404') { res.writeHead(404, { 'content-type': 'text/html' }); return res.end('<title>missing</title>'); }
  if (p === '/big') return html(big);
  if (p === '/cp1256') { res.writeHead(200, { 'content-type': 'text/html; charset=windows-1256' }); return res.end(cp1256Title); }
  if (p === '/meta-charset') { res.writeHead(200, { 'content-type': 'text/html' }); return res.end(Buffer.concat([Buffer.from('<html><head><meta charset="windows-1256"><title>'), Buffer.from([0xcc, 0xcf, 0xc9]), Buffer.from(' 2026</title></head></html>')])); }
  if (p === '/xhtml') { res.writeHead(200, { 'content-type': 'application/xhtml+xml' }); return res.end('<html><head><title>XHTML ok</title></head></html>'); }
  if (p === '/abs-image') return html('<html><head><title>Abs</title><meta property="og:image" content="https://cdn.example.com/a.png"></head></html>');
  if (p === '/bad-image') return html('<html><head><title>BadImg</title><meta property="og:image" content="javascript:alert(1)"></head></html>');
  if (p === '/to-private') { res.writeHead(302, { location: 'http://169.254.169.254/latest/meta-data' }); return res.end(); }
  if (p === '/to-ftp') { res.writeHead(302, { location: 'ftp://example.com/x' }); return res.end(); }
  if (/^\/rl\/\d+$/.test(p)) return html('<title>rl</title>');
  if (p === '/img/og.jpg') { res.writeHead(200, { 'content-type': 'image/png', 'content-length': PNG.length }); return res.end(PNG); }
  if (p === '/img/redir') { res.writeHead(302, { location: '/img/og.jpg?x=1&y=2' }); return res.end(); }
  if (p === '/img/huge') { res.writeHead(200, { 'content-type': 'image/jpeg', 'content-length': 4 * 1024 * 1024 }); return res.end(Buffer.alloc(1024)); }
  if (p === '/img/notimage') return html('<title>not an image</title>');
  if (p === '/huge-page') return html('<html><head><title>Huge</title><meta property="og:image" content="/img/huge"></head></html>');
  if (p === '/notimg-page') return html('<html><head><title>NotImg</title><meta property="og:image" content="/img/notimage"></head></html>');
  if (p === '/redir-img-page') return html('<html><head><title>RedirImg</title><meta property="og:image" content="/img/redir"></head></html>');
  res.writeHead(404); res.end();
});
await new Promise((r) => site.listen(0, '127.0.0.1', r));
const base = `http://127.0.0.1:${site.address().port}`;

// ---- تطبيقان
const appPriv = Fastify();
appPriv.register((await import('../chat_preview.js')).default, { pool, auth, allowPrivate: true, timeoutMs: 1500 });
const appPub = Fastify();
appPub.register((await import('../chat_preview.js')).default, { pool, auth, timeoutMs: 1500 });
await appPriv.ready(); await appPub.ready();
await pool.query('DELETE FROM chat_link_previews');
const lp = globalThis.naslifeLinkPreview;
const preview = async (url, { app = appPriv, user = 'SA0000001' } = {}) => {
  const r = await app.inject({ method: 'GET', url: `/chat/preview?url=${encodeURIComponent(url)}`, headers: user ? { 'x-user': user } : {} });
  return { code: r.statusCode, body: r.json() };
};

// ---- وحدات: العناوين الخاصة والمضيفون
for (const ip of ['127.0.0.1', '10.1.2.3', '172.16.0.1', '172.31.255.255', '192.168.1.1', '169.254.169.254', '0.0.0.0', '100.64.0.1', '224.0.0.1', '255.255.255.255', '::1', '::', '::ffff:127.0.0.1', '::ffff:7f00:1', 'fc00::1', 'fd12::1', 'fe80::1', 'fe80::1%eth0', 'ff02::1', '64:ff9b::7f00:1', '2002:7f00:1::1', 'not-an-ip'])
  check(lp.isPrivateIp(ip) === true, `private: ${ip}`);
for (const ip of ['8.8.8.8', '1.1.1.1', '172.32.0.1', '172.15.0.1', '192.169.0.1', '100.128.0.1', '2606:4700::6810:84e5', '2a00:1450:4001::1'])
  check(lp.isPrivateIp(ip) === false, `public: ${ip}`);
for (const h of ['localhost', 'LOCALHOST.', 'db.localhost', 'printer.local', 'api.internal', 'nas.lan', 'router.home', 'intranet', '[::1]', '127.0.0.1', '10.0.0.5', 'x.onion'])
  check(lp.hostAllowed(h) === 'private-host', `host refused: ${h}`, String(lp.hostAllowed(h)));
for (const h of ['naslife.app', 'www.example.com', 'مثال.sa', '8.8.8.8', 'cdn.example.co.uk'])
  check(lp.hostAllowed(h) === null, `host allowed: ${h}`);
check(lp.decodeEntities('A &amp; B &lt;c&gt; &quot;d&quot; &#39;e&#39; &#x1F600; &copy; &unknown; &#0;') === 'A & B <c> "d" \'e\' 😀 © &unknown; &#0;', 'entities decoded (named, decimal, hex; unknown kept)', lp.decodeEntities('A &amp; B &lt;c&gt; &quot;d&quot; &#39;e&#39; &#x1F600; &copy; &unknown; &#0;'));

// ---- المصادقة والروابط غير الصالحة
let r = await preview(`${base}/ok`, { user: null });
check(r.code === 401, 'preview requires auth', String(r.code));
for (const bad of ['', 'not a url', 'ftp://example.com/x', 'javascript:alert(1)', 'file:///etc/passwd', 'http://user:pw@example.com/', 'http://' + 'a'.repeat(2100) + '.com/'])
  { r = await preview(bad); check(r.code === 200 && r.body.ok === false && r.body.reason === 'bad-url', `bad url → ok:false bad-url (${bad.slice(0, 24) || 'empty'})`, JSON.stringify(r.body)); }

// ---- الإعداد الافتراضي يرفض المضيفين الخاصين قبل أي اتصال أو ذاكرة
for (const u of [`${base}/ok`, 'http://localhost/x', 'http://10.0.0.1/', 'http://[::1]/', 'http://169.254.169.254/latest/meta-data', 'http://0x7f.1/', 'http://2130706433/', 'http://intranet/'])
  { r = await preview(u, { app: appPub }); check(r.code === 200 && r.body.ok === false && r.body.reason === 'private-host', `default app refuses ${u}`, JSON.stringify(r.body)); }
check(Object.keys(hits).length === 0, 'no request reached the local site from the default app', JSON.stringify(hits));
// إعادة ربط DNS: اسم عام يحلّ إلى عنوان خاص يُرفض عند الحلّ نفسه (محلّل محقون يعيد 127.0.0.1 لأي اسم) ولا يصل أي طلب إلى الموقع
const appDns = Fastify();
appDns.register((await import('../chat_preview.js')).default, { pool, auth, timeoutMs: 1500, resolve: async (h) => (h === 'evil.example.com' ? [{ address: '127.0.0.1', family: 4 }] : h === 'dual.example.com' ? [{ address: '93.184.216.34', family: 4 }, { address: '::ffff:127.0.0.1', family: 6 }] : []) });
await appDns.ready();
r = await preview(`http://evil.example.com:${site.address().port}/ok`, { app: appDns });
check(r.code === 200 && r.body.ok === false && r.body.reason === 'private-host' && !hits['/ok'], 'public name resolving to 127.0.0.1 refused at lookup (DNS rebinding)', JSON.stringify(r.body));
r = await preview(`http://dual.example.com:${site.address().port}/ok`, { app: appDns });
check(r.body.ok === false && r.body.reason === 'private-host' && !hits['/ok'], 'any private address among the answers refuses the whole host', JSON.stringify(r.body));
r = await preview(`http://ghost.example.com/ok`, { app: appDns });
check(r.body.ok === false && r.body.reason === 'dns', 'empty DNS answer → dns', JSON.stringify(r.body));
await appDns.close();

// ---- التحليل الكامل عبر التطبيق المسموح له محلياً
r = await preview(`${base}/ok`);
check(r.code === 200 && r.body.ok === true, 'ok page → ok:true', JSON.stringify(r.body));
check(r.body.title === 'قهوة & كيك — برو 92', 'og:title with entities decoded', r.body.title);
check(r.body.description === 'أفضل V60 في جدة 😀 "مختصة"', 'og:description decoded (hex entity, quotes)', r.body.description);
check(r.body.image === `${base}/img/og.jpg?x=1&y=2`, 'relative og:image resolved to an absolute url with decoded query', r.body.image);
check(r.body.site === 'Brew92', 'og:site_name', r.body.site);
check(r.body.url === `${base}/ok` && typeof r.body.cachedAt === 'string' && r.body.finalUrl === `${base}/ok`, 'url, finalUrl and cachedAt present', JSON.stringify(r.body));
check(hits['/ok'] === 1, 'fetched once');

// ---- الذاكرة: الطلب الثاني من القاعدة بلا جلب، والجزء # لا يغيّر المفتاح، والتطبيق الآخر يشارك الذاكرة نفسها
const r2 = await preview(`${base}/ok#section`);
check(r2.body.ok === true && r2.body.title === r.body.title && hits['/ok'] === 1, 'second call served from cache (fragment ignored)', String(hits['/ok']));
const row = (await pool.query('SELECT url, data FROM chat_link_previews WHERE url = $1', [`${base}/ok`])).rows;
check(row.length === 1 && row[0].data.ok === true && row[0].data.title === r.body.title, 'row stored in chat_link_previews', JSON.stringify(row).slice(0, 160));

// ---- وكيل الصور: صورة اكتشفتها المعاينة تُقدَّم من أصلنا بنوعها وبترويسة تخزين؛ غيرها 404 (لا وكيل مفتوح)
const imgUrl = `${base}/img/og.jpg?x=1&y=2`;
let ir = await appPriv.inject({ method: 'GET', url: `/chat/preview/image?u=${encodeURIComponent(imgUrl)}` });
check(ir.statusCode === 200 && ir.headers['content-type'] === 'image/png' && ir.rawPayload.equals(PNG) && /max-age=86400/.test(ir.headers['cache-control'] || ''), 'known preview image proxied with its type and cache headers', `${ir.statusCode} ${ir.headers['content-type']} ${ir.rawPayload.length}`);
check(hits['/img/og.jpg'] === 1, 'image fetched from the site by the server');
ir = await appPriv.inject({ method: 'GET', url: `/chat/preview/image?u=${encodeURIComponent(base + '/img/other.png')}` });
check(ir.statusCode === 404 && !hits['/img/other.png'], 'image not discovered by any preview → 404 without fetching');
ir = await appPub.inject({ method: 'GET', url: `/chat/preview/image?u=${encodeURIComponent(imgUrl)}` });
check(ir.statusCode === 404, 'default app refuses a private image host');
ir = await appPriv.inject({ method: 'GET', url: '/chat/preview/image?u=javascript:x' });
check(ir.statusCode === 404, 'non-http image url → 404');
await preview(`${base}/huge-page`); await preview(`${base}/notimg-page`); await preview(`${base}/redir-img-page`);
ir = await appPriv.inject({ method: 'GET', url: `/chat/preview/image?u=${encodeURIComponent(base + '/img/huge')}` });
check(ir.statusCode === 413, 'declared 4 MB image → 413', String(ir.statusCode));
ir = await appPriv.inject({ method: 'GET', url: `/chat/preview/image?u=${encodeURIComponent(base + '/img/notimage')}` });
check(ir.statusCode === 415, 'text/html at an image url → 415', String(ir.statusCode));
ir = await appPriv.inject({ method: 'GET', url: `/chat/preview/image?u=${encodeURIComponent(base + '/img/redir')}` });
check(ir.statusCode === 200 && ir.rawPayload.equals(PNG), 'image behind a redirect proxied', String(ir.statusCode));
// ذاكرة منتهية: تُجلب من جديد
await pool.query("UPDATE chat_link_previews SET fetched_at = now() - interval '25 hours'");
await preview(`${base}/ok`);
check(hits['/ok'] === 2, 'expired cache (25 h) → refetched');
// الفشل يُخزَّن ساعة فقط
await preview(`${base}/404`);
await preview(`${base}/404`);
check(hits['/404'] === 1, 'failure cached (second call not fetched)');
await pool.query("UPDATE chat_link_previews SET fetched_at = now() - interval '2 hours' WHERE url LIKE '%/404'");
r = await preview(`${base}/404`);
check(hits['/404'] === 2 && r.body.ok === false && r.body.reason === 'http-404', 'failure cache expires after an hour; reason http-404', JSON.stringify(r.body));

// ---- احتياطات التحليل
r = await preview(`${base}/title-only`);
check(r.body.ok === true && r.body.title === 'Just a title © 2026' && r.body.description === 'desc here' && r.body.image === '' && r.body.site === '127.0.0.1', '<title> + meta description fallback; whitespace collapsed; site = hostname', JSON.stringify(r.body));
r = await preview(`${base}/no-title`);
check(r.body.ok === false && r.body.reason === 'no-title', 'page without a title → no-title', JSON.stringify(r.body));
r = await preview(`${base}/xhtml`);
check(r.body.ok === true && r.body.title === 'XHTML ok', 'application/xhtml+xml accepted');
r = await preview(`${base}/abs-image`);
check(r.body.image === 'https://cdn.example.com/a.png', 'absolute og:image kept');
r = await preview(`${base}/bad-image`);
check(r.body.ok === true && r.body.image === '', 'non-http og:image dropped');
r = await preview(`${base}/cp1256`);
check(r.body.ok === true && r.body.title === 'جدة', 'charset from content-type (windows-1256) decoded', r.body.title);
r = await preview(`${base}/meta-charset`);
check(r.body.ok === true && r.body.title === 'جدة 2026', 'charset from <meta charset> decoded', r.body.title);
r = await preview(`${base}/big`);
check(r.body.ok === true && r.body.title === 'Big page', 'body capped at 512 KB: <title> at the start wins, og:title beyond the cap ignored', r.body.title);

// ---- التحويلات
r = await preview(`${base}/redirect`);
check(r.body.ok === true && r.body.title.startsWith('قهوة') && r.body.url === `${base}/redirect` && r.body.finalUrl === `${base}/ok`, '302 followed; url is the requested one, finalUrl the landing page', JSON.stringify(r.body));
r = await preview(`${base}/redirect-rel`);
check(r.body.ok === true && r.body.finalUrl === `${base}/ok`, 'relative Location resolved');
r = await preview(`${base}/chain1`);
check(r.body.ok === false && r.body.reason === 'too-many-redirects' && hits['/chain4'] === 1 && !hits['/chain5'], '4 redirects → too-many-redirects (3 followed)', JSON.stringify(r.body) + ' ' + JSON.stringify(hits));
r = await preview(`${base}/loop`);
check(r.body.ok === false && r.body.reason === 'too-many-redirects', 'redirect loop stops', JSON.stringify(r.body));
r = await preview(`${base}/to-ftp`);
check(r.body.ok === false && r.body.reason === 'bad-url', 'redirect to ftp refused');
r = await preview(`${base}/to-private`, { app: appPriv });
check(hits['/to-private'] === 1, 'redirect hop fetched');
// التطبيق المسموح له محلياً يسمح بـ169.254 أيضاً (allowPrivate يعطّل الفحص كله)، فنفحص قفزة التحويل إلى عنوان خاص بالمحلل مباشرة
check(lp.hostAllowed('169.254.169.254') === 'private-host', 'metadata address refused by the host check used on every redirect hop');

// ---- أنواع غير HTML وأخطاء ومهلة: كلها ok:false بلا 5xx
r = await preview(`${base}/json`);
check(r.code === 200 && r.body.ok === false && r.body.reason === 'not-html', 'application/json → not-html', JSON.stringify(r.body));
r = await preview(`${base}/image`);
check(r.body.ok === false && r.body.reason === 'not-html', 'image/png → not-html');
r = await preview(`${base}/500`);
check(r.code === 200 && r.body.ok === false && r.body.reason === 'http-500', 'upstream 500 → ok:false http-500 (our status stays 200)', JSON.stringify(r.body));
const t0 = Date.now();
r = await preview(`${base}/slow`);
check(r.code === 200 && r.body.ok === false && r.body.reason === 'timeout' && Date.now() - t0 < 4000, 'slow page → timeout within the limit', `${JSON.stringify(r.body)} ${Date.now() - t0}ms`);
for (const h of slowHolders) h.end();
r = await preview(`http://127.0.0.1:1/ok`);
check(r.body.ok === false && r.body.reason === 'fetch-failed', 'connection refused → fetch-failed', JSON.stringify(r.body));
r = await preview('http://nonexistent-host-naslife-test.invalid/x', { app: appPub });
check(r.code === 200 && r.body.ok === false && ['dns', 'fetch-failed'].includes(r.body.reason), 'unresolvable host → dns', JSON.stringify(r.body));

// ---- حدّ المعدل: 60 جلباً في الدقيقة لكل مستخدم؛ الإصابات من الذاكرة لا تُحسب
let last;
for (let i = 1; i <= 60; i++) last = await preview(`${base}/rl/${i}`, { user: 'SA0000007' });
check(last.code === 200 && last.body.ok === true, '60 fetches allowed', JSON.stringify(last.body));
last = await preview(`${base}/rl/61`, { user: 'SA0000007' });
check(last.code === 429 && last.body.ok === false && last.body.reason === 'rate-limited', '61st fetch → 429 rate-limited', JSON.stringify(last.body));
last = await preview(`${base}/rl/1`, { user: 'SA0000007' });
check(last.code === 200 && last.body.ok === true, 'cached hit still served while limited');
last = await preview(`${base}/rl/61`, { user: 'SA0000008' });
check(last.code === 200 && last.body.ok === true, 'another user is not limited');

// ---- الحالة
const st = (await appPriv.inject({ method: 'GET', url: '/chat/preview/status' })).json();
check(st.ok === true && st.cached >= 60 && st.maxBytes === 512 * 1024 && st.maxRedirects === 3 && st.ttlHours === 24 && st.ratePerMin === 60, 'status: ok + cached count + limits', JSON.stringify(st));

await appPriv.close(); await appPub.close(); site.close(); await pool.end();
console.log(fails ? `\n${fails} FAILED` : '\nALL CHAT PREVIEW TESTS PASSED');
process.exit(fails ? 1 : 0);
