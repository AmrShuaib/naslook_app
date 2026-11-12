// صفحة /business: تُخدَم وثيقة كاملة بلا سكربتات ولا موارد خارجية (سياسة أمان الموقع)، بخطوط التطبيق، غير مفهرسة،
// وتحمل الشعار الرسمي والحقيقة الأساسية: البيع والحجز بعد التوثيق. وتغيب بأدب حين يغيب ملف المحتوى.
import Fastify from 'fastify';

let pass = 0, fail = 0;
const ok = (c, m) => { console.log((c ? 'ok   ' : 'FAIL ') + m); c ? pass++ : fail++; };

const app = Fastify();
app.register((await import('../biz_landing.js')).default, {});
await app.ready();

const r = await app.inject({ method: 'GET', url: '/business' });
const h = r.body;
ok(r.statusCode === 200 && /text\/html/.test(r.headers['content-type']), 'GET /business serves html');
ok(/noindex/.test(r.headers['x-robots-tag'] || '') && /<meta name="robots" content="noindex/.test(h), 'not indexed while it is a preview');
ok(r.headers['cache-control'] === 'no-store', 'not cached, so edits show at once');
ok(h.startsWith('<!doctype html><html lang="ar" dir="rtl">') && h.trimEnd().endsWith('</body></html>'), 'a full rtl arabic document');
ok(!/<script/i.test(h), 'no scripts (inline scripts are blocked by the site policy)');
ok(!/fonts\.googleapis|fonts\.gstatic/.test(h), 'no google fonts');
ok(/url\('\/assets\/fonts\/Rubik-Regular\.ttf'\)/.test(h) && /BalooBhaijaan2-Bold\.ttf/.test(h), 'fonts come from the app assets');
const ext = [...h.matchAll(/(?:src|href)="(https?:\/\/[^"]+)"/g)].map((m) => m[1]).filter((u) => !u.startsWith('https://naslife.app/'));
ok(ext.length === 0, 'no external resources' + (ext.length ? ': ' + ext[0] : ''));
ok(!/%%\w+%%/.test(h), 'no unfilled placeholders');
ok((h.match(/src="data:image\/png;base64,/g) || []).length >= 4, 'official logo images are embedded');
ok((h.match(/src="data:image\/webp;base64,/g) || []).length >= 6, 'phone screens are embedded');
ok(h.includes('اجعل نشاطك') && h.includes('سجّل دائرتك'), 'headline and call to action');
ok(h.includes('بعد التوثيق') && h.includes('من اليوم الأول'), 'says what opens only after verification');
ok(h.includes('الدفع في المكان') && !h.includes('ادفع من المحفظة'), 'promises pay at the venue only');
ok(/id="lp-start"/.test(h) && /href="#lp-start"/.test(h) && /id="lp-faq"/.test(h), 'in-page anchors resolve');
ok(h.includes('href="/business/register"') && !h.includes('https://naslife.app/business'), 'sign-up buttons open the registration forms (same site, relative)');
const g = await app.inject({ method: 'GET', url: '/business/register' });
ok(g.statusCode === 200 && /text\/html/.test(g.headers['content-type']) && /noindex/.test(g.headers['x-robots-tag'] || ''), 'GET /business/register serves the forms, not indexed');
ok((g.body.match(/<script/g) || []).length === 1 && g.body.includes('<script src="/business/register.js"></script>'), 'the forms page has one external script and no inline script');
ok(g.body.includes('منشأة بسجل تجاري') && g.body.includes('عمل حر') && g.body.includes('سأوثّق لاحقاً'), 'two forms: commercial registration and freelance, with verify later');
ok(!/<form[^>]*action=/.test(g.body) && !g.body.includes('معاينة قبل الاعتماد'), 'the forms submit through the script, and the page no longer says preview');
const j = await app.inject({ method: 'GET', url: '/business/register.js' });
ok(j.statusCode === 200 && /javascript/.test(j.headers['content-type']), 'the script is served');
for (const u of ['/auth/register', '/auth/verify', '/auth/login', '/chat/upload', '/biz/register', '/verification']) ok(j.body.includes(u), 'the script calls ' + u);
ok(!/https?:\/\//.test(j.body.replace(/\/\/[^\n]*/g, '')) && /credentials: 'omit'/.test(j.body), 'every call is same-origin and carries only the x-token header');
ok(!/localStorage|sessionStorage|document\.cookie/.test(j.body), 'the session token is kept in memory only');
ok(j.body.includes("'car_rental'") && j.body.includes('\\d{10}') && j.body.includes('{8,20}') && j.body.includes('[a-z0-9_]{3,25}'), 'the script uses the server rules for categories, document numbers and usernames');
for (const u of ['/business/', '/BUSINESS', '/Business']) {
  const x = await app.inject({ method: 'GET', url: u });
  ok(x.statusCode === 302 && x.headers.location === '/business', `${u} redirects to /business`);
}
const st = (await app.inject({ method: 'GET', url: '/business/status' })).json();
ok(st.ok === true && st.ready === true && st.register === true && st.bytes > 100000, 'status reports the page and the forms are ready');
await app.close();

const empty = Fastify();
empty.register((await import('../biz_landing.js')).default, { html: '' });
await empty.ready();
ok((await empty.inject({ method: 'GET', url: '/business' })).statusCode === 404, 'missing content answers 404, the server stays up');
await empty.close();

console.log(`${pass} passed, ${fail} failed`);
console.log(fail === 0 ? 'ALL OK' : `${fail} FAILED`);
process.exit(fail ? 1 : 0);
