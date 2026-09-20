// الإعداد الأول للإدارة: تطبيع رمز الإعداد (أرقام عربية، شرطات مختلفة، علامات اتجاه خفية)، تلميح الرمز في الحالة، وملف OPS/admin-ids.
import Fastify from 'fastify';
import pg from 'pg';
import fs from 'node:fs';
process.env.NASLIFE_HEALTH_BRIDGE = '0';
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("INSERT INTO users(id,nickname) VALUES('SA0000001','amr'),('SA0000002','sara'),('SA0000007','founder') ON CONFLICT DO NOTHING");
await pool.query("UPDATE users SET is_admin=false");
await pool.query("DROP TABLE IF EXISTS admins; DROP TABLE IF EXISTS admin_setup");
const auth = async (req) => req.headers['x-user'] || null;
const dir = new URL('.', import.meta.url).pathname + 'ops_boot/';
fs.rmSync(dir, { recursive: true, force: true }); fs.mkdirSync(dir, { recursive: true });
let fails = 0;
const check = (c, l, extra = '') => { if (!c) fails++; console.log((c ? 'OK  ' : 'FAIL') + ' ' + l + (extra ? ' ' + extra : '')); };
const boot = async () => { const app = Fastify(); app.register((await import('../business.js')).default, { pool, auth }); app.register((await import('../admin.js')).default, { pool, auth, webappDir: dir, opsDir: dir }); await app.ready(); await new Promise((r) => setTimeout(r, 300)); return app; };
const call = async (app, method, url, { body, user = 'SA0000001' } = {}) => { const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json' }, payload: body ? JSON.stringify(body) : undefined }); let j; try { j = r.json(); } catch { j = r.body; } return { code: r.statusCode, json: j }; };

// 1) الرمز بتنسيقات مختلفة
let app = await boot();
const code = fs.readFileSync(dir + 'admin-setup-code', 'utf8').trim();
check(/^NL-[0-9A-F]{6}-[0-9A-F]{6}$/.test(code), 'setup code written to ops file', code);
let r = await call(app, 'GET', '/adminapi/status', { user: null });
check(r.json.setupRequired === true && r.json.setupHint === code.slice(-2) && r.json.bootstrapFile === dir + 'admin-ids', 'status exposes a 2-char hint and the bootstrap file path', JSON.stringify(r.json));
const arabicDigits = (s) => s.replace(/[0-9]/g, (d) => '٠١٢٣٤٥٦٧٨٩'[d]);
const messy = '‏ ' + arabicDigits(code.toLowerCase()).replace(/-/g, ' – ') + ' ‎';
r = await call(app, 'POST', '/adminapi/setup', { body: { code: 'NL-000000-000000' } });
check(r.code === 400 && r.json.error === 'bad-code', 'wrong code rejected');
r = await call(app, 'POST', '/adminapi/setup', { body: { code: messy } });
check(r.code === 200 && r.json.ok === true, 'code accepted with arabic digits, en-dashes, spaces and bidi marks', JSON.stringify(messy));
r = await call(app, 'GET', '/adminapi/status');
check(r.json.hasAdmin === true && r.json.isAdmin === true && r.json.setupHint === null, 'first admin set; hint hidden afterwards');
await app.close();

// 2) ملف admin-ids يمنح الإدارة عند الإقلاع (بالمعرّف وبالنك نيم)
await pool.query("DROP TABLE IF EXISTS admins; DROP TABLE IF EXISTS admin_setup");
fs.writeFileSync(dir + 'admin-ids', '# founders\nsa0000007\nsara\nnobody_here\n');
app = await boot();
r = await call(app, 'GET', '/adminapi/status', { user: 'SA0000007' });
check(r.json.hasAdmin === true && r.json.isAdmin === true && r.json.admins === 2, 'ops file grants admin by id and by nickname', JSON.stringify(r.json));
r = await call(app, 'GET', '/adminapi/overview', { user: 'SA0000002' });
check(r.code === 200, 'nickname-granted admin can use the panel');
r = await call(app, 'GET', '/adminapi/overview', { user: 'SA0000001' });
check(r.code === 403, 'others are still not admins');
await app.close();
// تنظيف حتى تبدأ حزمة الإدارة الأصلية من حالة «لا مدير»
await pool.query("DROP TABLE IF EXISTS admins; DROP TABLE IF EXISTS admin_setup"); fs.rmSync(dir, { recursive: true, force: true });
console.log(fails ? `\n${fails} FAILED` : '\nALL ADMIN BOOTSTRAP TESTS PASSED');
await pool.end(); process.exit(fails ? 1 : 0);
