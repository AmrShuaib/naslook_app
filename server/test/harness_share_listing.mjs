// رابط مشاركة العرض /l/:id (server/share.js): صفحة وسوم Open Graph صغيرة تحوّل إلى /#/l/<id> حين يوجد العرض (فيفتح التطبيق
// صفحة العرض بدل الرئيسية)، ووسوم عامة بلا صورة لغير النشط، وتحويل إلى «/» للمجهول والمعرّف المشوّه، وتهريب HTML.
// حزمة مستقلة لأن harness_share.mjs يحتاج تجهيزاً غير موجود في البيئة؛ تعمل على قاعدة NASLIFE_TEST_DB عبر db_env.mjs.
import Fastify from 'fastify';
import pg from 'pg';
import { randomUUID } from 'node:crypto';
process.env.NASLIFE_HEALTH_BRIDGE = '0';
let fails = 0;
const check = (c, l, extra = '') => { if (!c) fails++; console.log((c ? 'OK  ' : 'FAIL') + ' ' + l + (extra ? ' ' + extra : '')); };
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query('DROP TABLE IF EXISTS market_listings CASCADE');
const app = Fastify();
const auth = async (req) => req.headers['x-user'] || null;
// commerce.js ينشئ جدول market_listings بمخططه الحقيقي
await app.register((await import('../commerce.js')).default, { pool, auth });
await app.register((await import('../share.js')).default, { pool, auth, webappDir: '/nonexistent-webapp' });
await app.ready();

const get = async (url) => { const r = await app.inject({ method: 'GET', url, headers: { host: 'www.naslife.app', 'x-forwarded-proto': 'https' } }); return { code: r.statusCode, type: r.headers['content-type'] ?? '', body: r.body }; };
const meta = (html, prop) => (html.match(new RegExp(`<meta (?:property|name)="${prop}" content="([^"]*)"`)) || [])[1];
const refresh = (html) => (html.match(/<meta http-equiv="refresh" content="([^"]*)">/) || [])[1];

const live = randomUUID(), sold = randomUUID(), missing = randomUUID();
await pool.query("INSERT INTO market_listings(id, seller_id, kind, category, title, description, price, image_url, status) VALUES($1,'SA0000002','product','food','كيك <اختبار>','وصف \"الكيك\"',2500,'/chat/media/x.jpg','active')", [live]);
await pool.query("INSERT INTO market_listings(id, seller_id, kind, category, title, description, price, image_url, status) VALUES($1,'SA0000002','product','food','عرض مباع','سر',900,'/chat/media/y.jpg','sold')", [sold]);

// 1) عرض نشط: وسوم المعاينة كاملة وتحويل إلى /#/l/<id> (بلا حاجة إلى حزمة الويب)
let h = await get(`/l/${live}`);
check(h.code === 200 && /text\/html/.test(h.type), 'active listing: 200 html without the web bundle', `${h.code} ${h.type}`);
check(meta(h.body, 'og:title') === 'كيك &lt;اختبار&gt; · ٢٥ ر.س' || (meta(h.body, 'og:title') || '').startsWith('كيك &lt;اختبار&gt; · '), 'active listing: escaped title with price', meta(h.body, 'og:title'));
check(meta(h.body, 'og:type') === 'product' && meta(h.body, 'og:image') === 'https://naslife.app/chat/media/x.jpg' && meta(h.body, 'twitter:card') === 'summary_large_image', 'active listing: product type, absolute image, large card', JSON.stringify({ t: meta(h.body, 'og:type'), i: meta(h.body, 'og:image') }));
check(meta(h.body, 'og:description') === 'وصف &quot;الكيك&quot;', 'active listing: escaped description', meta(h.body, 'og:description'));
check(meta(h.body, 'og:url') === `https://naslife.app/l/${live}`, 'og:url canonical (www stripped)', meta(h.body, 'og:url'));
check(refresh(h.body) === `0; url=/#/l/${live}` && h.body.includes(`href="/#/l/${live}"`), 'active listing: refresh + link to /#/l/<id>', refresh(h.body));
check(!/<script/i.test(h.body), 'no inline script (CSP)');

// 2) المعرّف بأحرف كبيرة يُحوَّل بالصغيرة
h = await get(`/l/${live.toUpperCase()}`);
check(refresh(h.body) === `0; url=/#/l/${live}`, 'uppercase id redirects with the lowercase id', refresh(h.body));

// 3) عرض موجود غير نشط: تحويل إلى صفحة العرض بوسوم عامة بلا صورة ولا وصف
h = await get(`/l/${sold}`);
check(refresh(h.body) === `0; url=/#/l/${sold}`, 'existing non-active listing still redirects to the listing page', refresh(h.body));
check(meta(h.body, 'og:image') === undefined && !h.body.includes('عرض مباع') && !h.body.includes('سر<') && meta(h.body, 'og:type') === 'website', 'non-active listing: generic tags, no title/image');

// 4) مجهول ومشوّه: إلى الرئيسية
h = await get(`/l/${missing}`);
check(h.code === 200 && refresh(h.body) === '0; url=/' && (meta(h.body, 'og:title') || '').startsWith('عرض في سوق'), 'unknown listing redirects home with generic tags', refresh(h.body));
h = await get('/l/not-a-uuid');
check(h.code === 200 && refresh(h.body) === '0; url=/' && meta(h.body, 'og:url') === 'https://naslife.app/l/', 'bad id: home redirect, no id echoed', meta(h.body, 'og:url'));
h = await get('/l/%3Cscript%3E');
check(!h.body.includes('<script>'), 'bad id is never echoed raw');

await pool.query('DELETE FROM market_listings WHERE id = ANY($1::uuid[])', [[live, sold]]);
await app.close(); await pool.end();
console.log(fails ? `\n${fails} FAILED` : '\nALL SHARE LISTING TESTS PASSED');
process.exit(fails ? 1 : 0);
