// اختبارات مدونة /blog (server/blog.js) مع قاعدة بيانات: البذرة، القائمة والمرشّحات، صفحة المنشور، الخلاصتان، التهريب،
// وواجهة الإدارة /adminapi/blog: الحماية، الإنشاء بمعرّف تلقائي، المسودات والمعاينة، النشر والجدولة، التثبيت، النسخ، الحذف، المشاهدات.
import Fastify from 'fastify';
import pg from 'pg';
process.env.NASLIFE_HEALTH_BRIDGE = '0';
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query('DROP TABLE IF EXISTS blog_posts; DROP TABLE IF EXISTS blog_seeded');
await pool.query("CREATE TABLE IF NOT EXISTS admin_audit (id UUID PRIMARY KEY, admin_id TEXT, action TEXT, target TEXT, details JSONB, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("DELETE FROM admin_audit WHERE action LIKE 'blog.%'");
globalThis.naslifeIsAdmin = async (uid) => uid === 'SA0000001';
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
app.register((await import('../blog.js')).default, { pool, auth });
await app.ready();
let fails = 0;
const check = (cond, label, extra = '') => { if (!cond) fails++; console.log((cond ? 'OK  ' : 'FAIL') + ' ' + label + (extra ? ' ' + extra : '')); };
const call = async (method, url, { user = 'SA0000001', body } = {}) => { const r = await app.inject({ method, url, headers: { host: 'www.naslife.app', 'x-forwarded-proto': 'https', ...(user ? { 'x-user': user } : {}) }, payload: body }); let j = null; try { j = JSON.parse(r.body); } catch { /* html */ } return { code: r.statusCode, type: r.headers['content-type'] || '', body: r.body, json: j, headers: r.headers }; };
const get = (url) => call('GET', url, { user: null });
const meta = (html, prop) => (html.match(new RegExp(`<meta (?:property|name)="${prop}" content="([^"]*)"`)) || [])[1];
const { markupHtml, inlineHtml, slugify } = await import('../blog.js');

// ---- البذرة والعام
let r = await get('/blog/status');
check(r.code === 200 && r.json.db === true && r.json.posts === 19 && r.json.latest === 'whats-next', 'seeded 19 posts into the table', r.body);
r = await get('/blog');
check(r.code === 200 && /text\/html/.test(r.type) && r.body.includes('lang="ar" dir="rtl"') && (r.body.match(/<article class="card/g) || []).length === 19, 'list page with 19 cards');
check(r.body.indexOf('ما القادم؟') < r.body.indexOf('انطلاق ناس لايف على الويب') && meta(r.body, 'og:url') === 'https://naslife.app/blog', 'newest first, canonical without www');
r = await get('/blog?kind=news');
check(r.code === 200 && (r.body.match(/<article class="card/g) || []).length === 4 && r.body.includes('<h1>أخبار</h1>'), 'news filter');
r = await get('/blog/');
check(r.code === 301 && r.headers.location === '/blog', 'trailing slash redirects');
r = await get('/blog/dammam-circles');
check(r.code === 200 && r.body.includes('<title>ناس لايف يصل إلى الدمام · ناس لايف</title>') && meta(r.body, 'og:type') === 'article' && r.body.includes('<ul><li>20 مقهى') && r.body.includes('<time datetime="2026-09-13">13 سبتمبر 2026</time>'), 'post page rendered with date and list');
check(r.body.includes('href="/blog/post-editor"') && r.body.includes('href="/blog/analytics"') && r.body.includes('id="copy-link"'), 'prev/next and share row');
r = await get('/blog/nope-nope');
check(r.code === 404 && r.body.includes('المنشور غير موجود'), '404 page for unknown slug');
r = await get('/blog/feed.json');
check(r.code === 200 && r.json.items.length === 19 && r.json.items[0].url === 'https://naslife.app/blog/whats-next' && r.json.items[0].content_html.includes('<ul>'), 'json feed');
r = await get('/blog/rss.xml');
check(r.code === 200 && /application\/rss\+xml/.test(r.type) && (r.body.match(/<item>/g) || []).length === 19, 'rss feed');
// ---- المشاهدات
await get('/blog/dammam-circles'); await get('/blog/dammam-circles');
const views = (await pool.query("SELECT views FROM blog_posts WHERE slug='dammam-circles'")).rows[0].views;
check(views === 3, 'views counted per page view', String(views));

// ---- الحماية
r = await call('GET', '/adminapi/blog', { user: null });
check(r.code === 401, 'admin list requires auth');
r = await call('GET', '/adminapi/blog', { user: 'SA0000002' });
check(r.code === 403 && r.json.error === 'admin-only', 'admin list is admin-only');
r = await call('GET', '/adminapi/blog');
// 19 منشوراً ثابتاً منشوراً + 6 مسودات جاهزة (تُرتَّب أولاً لأن تاريخ تعديلها الآن)
check(r.code === 200 && r.json.total === 25 && r.json.counts.published === 19 && r.json.counts.draft === 6 && r.json.posts[0].effectiveStatus === 'draft' && r.json.posts[0].body === undefined && r.json.posts[0].bodyLength > 0 && r.json.posts.some((p) => p.slug === 'whats-next' && p.effectiveStatus === 'published'), 'admin list with counts, seeded drafts first, no bodies');
r = await call('GET', '/adminapi/blog?status=draft');
check(r.code === 200 && r.json.total === 6 && r.json.posts.every((p) => p.status === 'draft') && r.json.posts.some((p) => p.slug === 'circle-offers'), 'seeded drafts listed with status=draft');
check((await pool.query("SELECT count(*)::int AS n FROM blog_seeded")).rows[0].n === 6, 'blog_seeded records the drafts so they never come back after publish or delete');
r = await call('GET', '/adminapi/blog?q=الدمام&kind=news&status=published');
check(r.code === 200 && r.json.total === 1 && r.json.posts[0].slug === 'dammam-circles', 'admin search + kind + status filter');
r = await call('GET', `/adminapi/blog/${r.json.posts[0].id}`);
check(r.code === 200 && r.json.body.includes('59 دائرة') && r.json.url === 'https://naslife.app/blog/dammam-circles' && r.json.date === '2026-09-13', 'admin get returns body and url');

// ---- الإنشاء والتحقق
r = await call('POST', '/adminapi/blog', { body: { title: '' } });
check(r.code === 400 && r.json.error === 'bad-title', 'create rejects empty title');
r = await call('POST', '/adminapi/blog', { body: { title: 'x', kind: 'bogus' } });
check(r.code === 400 && r.json.error === 'bad-kind', 'create rejects bad kind');
r = await call('POST', '/adminapi/blog', { body: { title: 'x', slug: 'Bad Slug!' } });
check(r.code === 400 && r.json.error === 'bad-slug', 'create rejects bad slug');
r = await call('POST', '/adminapi/blog', { body: { title: 'x', coverUrl: 'javascript:alert(1)' } });
check(r.code === 400 && r.json.error === 'bad-cover', 'create rejects unsafe cover url');
r = await call('POST', '/adminapi/blog', { body: { title: 'ساعات العمل في رمضان', kind: 'news', summary: 'ملخص <b>خطير</b>', body: '## الفروع\n- جدة\n- الدمام', tags: ['رمضان', 'رمضان', ' فروع '], coverUrl: '/files/cover.jpg' } });
check(r.code === 201 || r.code === 200, 'create draft', r.body);
const draft = r.json;
check(/^\d{8}-[0-9a-f]{4}$/.test(draft.slug) && draft.status === 'draft' && draft.effectiveStatus === 'draft' && draft.tags.length === 2 && draft.tags[1] === 'فروع' && draft.coverUrl === '/files/cover.jpg' && draft.publishedAt === null, 'auto slug for arabic title, tags de-duplicated, draft status', JSON.stringify({ slug: draft.slug, tags: draft.tags }));
r = await call('POST', '/adminapi/blog', { body: { title: 'Ramadan hours update', kind: 'update' } });
check(r.json.slug === 'ramadan-hours-update', 'latin titles become readable slugs', r.json.slug);
const latin = r.json;
r = await call('POST', '/adminapi/blog', { body: { title: 'Ramadan hours update', kind: 'update' } });
check(r.json.slug === 'ramadan-hours-update-2', 'duplicate slugs get a suffix', r.json.slug);
const latin2 = r.json;
r = await get(`/blog/${draft.slug}`);
check(r.code === 404, 'draft is not public');
r = await get('/blog/feed.json');
check(r.json.items.every((x) => !x.url.endsWith(draft.slug)), 'draft is not in the feed');
r = await call('GET', '/adminapi/blog?status=draft');
check(r.json.total === 9 && r.json.counts.draft === 9, 'draft filter and counts (3 created + 6 seeded)');

// ---- المعاينة
r = await call('POST', `/adminapi/blog/${draft.id}/preview`);
check(r.code === 200 && r.json.url.startsWith(`https://naslife.app/blog/${draft.slug}?key=`), 'preview link issued');
const previewUrl = new URL(r.json.url);
r = await get(previewUrl.pathname + previewUrl.search);
check(r.code === 200 && r.body.includes('معاينة مسودة') && r.body.includes('<title>ساعات العمل في رمضان · ناس لايف</title>') && r.body.includes('<h3>الفروع</h3>') && r.body.includes('ملخص &lt;b&gt;خطير&lt;/b&gt;') && r.body.includes('name="robots" content="noindex"') && r.body.includes('<span>رمضان</span>'), 'preview renders draft with banner, escaping, tags and noindex');
r = await get(previewUrl.pathname + '?key=wrong');
check(r.code === 404, 'wrong preview key is rejected');

// ---- التعديل
r = await call('PATCH', `/adminapi/blog/${draft.id}`, { body: { slug: latin.slug } });
check(r.code === 409 && r.json.error === 'slug-taken', 'slug collision on update');
r = await call('PATCH', `/adminapi/blog/${draft.id}`, { body: { slug: 'ramadan-hours', title: 'ساعات العمل في رمضان 1448', pinned: true } });
check(r.code === 200 && r.json.slug === 'ramadan-hours' && r.json.pinned === true && r.json.title.endsWith('1448'), 'update slug, title and pin');
r = await call('PATCH', `/adminapi/blog/${draft.id}`, { body: { publishedAt: 'not a date' } });
check(r.code === 400 && r.json.error === 'bad-date', 'bad date rejected');

// ---- النشر
r = await call('POST', `/adminapi/blog/${draft.id}/publish`);
check(r.code === 200 && r.json.status === 'published' && r.json.effectiveStatus === 'published' && r.json.publishedAt, 'publish now');
r = await get('/blog');
const firstCard = r.body.indexOf('<article class="card');
check(r.body.slice(firstCard, firstCard + 400).includes('ramadan-hours') && r.body.includes('class="pin">مثبّت</span>'), 'pinned published post is first in the public list');
r = await get('/blog/ramadan-hours');
check(r.code === 200 && r.body.includes('<img class="cover" src="/files/cover.jpg"') && meta(r.body, 'og:image') === 'https://naslife.app/files/cover.jpg' && !r.body.includes('معاينة'), 'public post page shows cover and absolute og:image');
r = await call('POST', `/adminapi/blog/${draft.id}/pin`, { body: { pinned: false } });
check(r.code === 200 && r.json.pinned === false, 'unpin');
// جدولة
const future = new Date(Date.now() + 2 * 3600e3).toISOString();
r = await call('POST', `/adminapi/blog/${latin.id}/publish`, { body: { publishedAt: future } });
check(r.code === 200 && r.json.effectiveStatus === 'scheduled', 'schedule for later');
r = await get(`/blog/${latin.slug}`);
check(r.code === 404, 'scheduled post is not public yet');
r = await call('GET', '/adminapi/blog?status=scheduled');
check(r.json.total === 1 && r.json.counts.scheduled === 1 && r.json.counts.published === 20, 'scheduled filter and counts');
r = await call('POST', `/adminapi/blog/${latin.id}/unpublish`);
check(r.code === 200 && r.json.status === 'draft', 'unpublish back to draft');

// ---- النسخ والحذف
r = await call('POST', `/adminapi/blog/${draft.id}/duplicate`);
check(r.code === 200 && r.json.slug === 'ramadan-hours-copy' && r.json.status === 'draft' && r.json.title.startsWith('نسخة من') && r.json.body === '## الفروع\n- جدة\n- الدمام', 'duplicate as draft copy');
const copy = r.json;
r = await call('DELETE', `/adminapi/blog/${copy.id}`);
check(r.code === 200 && r.json.ok === true, 'delete');
r = await call('GET', `/adminapi/blog/${copy.id}`);
check(r.code === 404, 'deleted post is gone');
r = await call('DELETE', `/adminapi/blog/${latin2.id}`);
r = await call('DELETE', `/adminapi/blog/${latin.id}`);
r = await call('DELETE', '/adminapi/blog/not-a-uuid');
check(r.code === 404, 'bad id is safe');
const audit = (await pool.query("SELECT action FROM admin_audit WHERE action LIKE 'blog.%' ORDER BY created_at")).rows.map((x) => x.action);
check(audit.includes('blog.create') && audit.includes('blog.publish') && audit.includes('blog.schedule') && audit.includes('blog.delete') && audit.includes('blog.duplicate'), 'audit trail written', audit.join(','));

// ---- التنسيق
check(inlineHtml('a <b>x</b> **مهم** [رابط](https://naslife.app/c/x) https://naslife.app') === 'a &lt;b&gt;x&lt;/b&gt; <strong>مهم</strong> <a href="https://naslife.app/c/x" rel="noopener">رابط</a> <a href="https://naslife.app" rel="noopener">https://naslife.app</a>', 'inline escaping, bold and links');
check(inlineHtml('[x](javascript:alert(1))') === '[x](javascript:alert(1))', 'javascript: links are not linkified');
check(markupHtml('## فرعي\n\nسطر أول\nسطر ثانٍ\n\n1. أ\n2. ب\n\n- ج\n> اقتباس\n---\n![صورة](https://naslife.app/x.png)') === '<h3>فرعي</h3>\n<p>سطر أول<br>سطر ثانٍ</p>\n<ol><li>أ</li><li>ب</li></ol>\n<ul><li>ج</li></ul>\n<blockquote>اقتباس</blockquote>\n<hr>\n<figure><img src="https://naslife.app/x.png" alt="صورة" loading="lazy"><figcaption>صورة</figcaption></figure>', 'block markup');
check(slugify('Hello World, 2026!') === 'hello-world-2026' && /^\d{8}-[0-9a-f]{4}$/.test(slugify('عنوان عربي')), 'slugify');
console.log(fails ? `\n${fails} FAILED` : '\nALL BLOG TESTS PASSED');
await app.close(); await pool.end();
process.exit(fails ? 1 : 0);
