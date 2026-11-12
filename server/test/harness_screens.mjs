// معرض التصاميم /screens: مقفل بلا رقم، المدير وحده يضبط الرقم، الدخول بكعكة موقّعة، صفحات التبويبات وملفات JS محجوبة بلا دخول،
// تغيير الرقم يُسقط الجلسات، حدّ المحاولات الخاطئة، وانتهاء الجلسة بعد سبعة أيام.
import Fastify from 'fastify';
import pg from 'pg';
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query('DROP TABLE IF EXISTS screens_access');
const ADMIN = 'SA0000971', USER = 'SA0000972';
globalThis.naslifeIsAdmin = async (u) => u === ADMIN;
const auth = async (req) => req.headers['x-user'] || null;
let clock = Date.now();
const PAGES = [{ id: 'one', title: 'الأولى', sub: 'وصف', css: '.x{color:red}', html: '<div id="secret-one">محتوى سري</div>', js: 'window.ONE=1;' }, { id: 'two', title: 'الثانية', sub: '', css: '', html: '<p>two</p>', js: '' }];
const app = Fastify();
app.register((await import('../screens.js')).default, { pool, auth, pages: PAGES, now: () => clock });
await app.ready();

let pass = 0, fail = 0;
const ok = (c, m) => { if (c) pass++; else { fail++; console.log('FAIL', m); } };
const get = (url, cookie, headers = {}) => app.inject({ method: 'GET', url, headers: { ...(cookie ? { cookie } : {}), ...headers } });
const post = (url, body, headers = {}) => app.inject({ method: 'POST', url, payload: body, headers: { 'x-forwarded-for': '10.0.0.1', ...headers } });
const cookieOf = (r) => String(r.headers['set-cookie'] ?? '').split(';')[0];

// بلا رقم: الصفحة تقول إنه لم يُضبط، ولا دخول
let r = await get('/screens');
ok(r.statusCode === 200 && r.body.includes('لم يُضبط') && !r.body.includes('محتوى سري'), 'unset: gate says not set');
ok(/no-store/.test(r.headers['cache-control']) && /noindex/.test(r.headers['x-robots-tag']), 'private + noindex headers');
ok((await post('/screens/login', { pin: '123456' })).statusCode === 401, 'unset: login refused');
ok((await get('/screens/one')).statusCode === 302, 'unset: page redirects to gate');
ok((await get('/SCREENS')).headers.location === '/screens', 'uppercase path redirects');

// الضبط للمدير فقط
ok((await post('/screens/pin', { pin: '482915' })).statusCode === 401, 'pin: anonymous 401');
ok((await post('/screens/pin', { pin: '482915' }, { 'x-user': USER })).statusCode === 403, 'pin: non-admin 403');
ok((await post('/screens/pin', { pin: '12345' }, { 'x-user': ADMIN })).statusCode === 400, 'pin: too short 400');
ok((await post('/screens/pin', { pin: 'abc12345' }, { 'x-user': ADMIN })).statusCode === 400, 'pin: letters 400');
ok((await post('/screens/pin', { pin: '482915' }, { 'x-user': ADMIN })).statusCode === 200, 'pin: admin sets');
r = await get('/screens/pin', null, { 'x-user': ADMIN });
ok(r.json().set === true && !JSON.stringify(r.json()).includes('482915'), 'status: set, pin never returned');
ok((await get('/screens/pin', null, { 'x-user': USER })).statusCode === 403, 'status: admin only');
const stored = (await pool.query('SELECT * FROM screens_access')).rows[0];
ok(stored.hash && !JSON.stringify(stored).includes('482915'), 'db: only a hash is stored');

// الدخول
r = await get('/screens');
ok(r.body.includes('id="pin"') && r.body.includes('/screens/js/login.js') && !/<script>(?!<)/.test(r.body), 'gate: form, external script, no inline script');
ok((await post('/screens/login', { pin: '000000' })).statusCode === 401, 'login: wrong pin');
r = await post('/screens/login', { pin: '٤٨٢٩١٥' });
ok(r.statusCode === 200, 'login: Arabic digits accepted');
const c1 = cookieOf(r);
ok(/^ns_screens=\d+\.[0-9a-f]{64}$/.test(c1) && /HttpOnly/.test(r.headers['set-cookie']) && /Secure/.test(r.headers['set-cookie']) && /Path=\/screens/.test(r.headers['set-cookie']), 'cookie: signed, HttpOnly, Secure, scoped');
ok((await get('/screens', c1)).headers.location === '/screens/one', 'in: /screens goes to first tab');
r = await get('/screens/one', c1);
ok(r.statusCode === 200 && r.body.includes('محتوى سري') && r.body.includes('href="/screens/two"') && r.body.includes('aria-current="page"') && r.body.includes('/screens/js/one.js'), 'page: content, tabs, external js');
ok(!/<script>(?!<)/.test(r.body), 'page: no inline script');
ok((await get('/screens/js/one.js', c1)).body === 'window.ONE=1;', 'js: served when in');
ok((await get('/screens/js/one.js')).statusCode === 401, 'js: locked without cookie');
ok((await get('/screens/js/login.js')).statusCode === 200 && (await get('/screens/js/admin.js')).statusCode === 200, 'js: login and admin scripts are public');
ok((await get('/screens/nope', c1)).headers.location === '/screens', 'unknown tab redirects');
ok((await get('/screens/one', c1.replace(/.$/, 'x'))).statusCode === 302, 'tampered cookie rejected');
ok((await get('/screens/admin')).body.includes('/screens/js/admin.js') && !(await get('/screens/admin')).body.includes('482915'), 'admin page has no secret');

// الخروج، وانتهاء الجلسة، وتغيير الرقم
ok(/Max-Age=0/.test((await post('/screens/logout', {})).headers['set-cookie']), 'logout clears cookie');
clock += 6.9 * 86400000; ok((await get('/screens/one', c1)).statusCode === 200, 'still valid before 7 days');
clock += 0.2 * 86400000; ok((await get('/screens/one', c1)).statusCode === 302, 'expired after 7 days');
const c2 = cookieOf(await post('/screens/login', { pin: '482915' }));
ok((await get('/screens/one', c2)).statusCode === 200, 'fresh login works');
await post('/screens/pin', { pin: '77001122' }, { 'x-user': ADMIN });
ok((await get('/screens/one', c2)).statusCode === 302, 'pin change drops old sessions');
ok((await post('/screens/login', { pin: '482915' })).statusCode === 401 && (await post('/screens/login', { pin: '77001122' })).statusCode === 200, 'old pin dead, new pin works');

// حد المحاولات لكل عنوان
const ip = { 'x-forwarded-for': '10.9.9.9' };
for (let i = 0; i < 8; i++) await post('/screens/login', { pin: '111111' }, ip);
ok((await post('/screens/login', { pin: '77001122' }, ip)).statusCode === 429, 'blocked after 8 wrong tries, even with the right pin');
ok((await post('/screens/login', { pin: '77001122' }, { 'x-forwarded-for': '10.2.2.2' })).statusCode === 200, 'other addresses unaffected');
clock += 16 * 60000; ok((await post('/screens/login', { pin: '77001122' }, ip)).statusCode === 200, 'unblocked after 15 minutes');

console.log(`${pass} passed, ${fail} failed`);
console.log(fail === 0 ? 'ALL OK' : `${fail} FAILED`);
await app.close(); await pool.end(); process.exit(fail ? 1 : 0);
