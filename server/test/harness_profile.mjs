// اختبارات صورة الحساب (server/profile.js) وتعديل/إخفاء/إظهار عروض السوق وحجب الإدارة (commerce.js/admin.js).
import Fastify from 'fastify';
import pg from 'pg';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0';
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("INSERT INTO users(id,nickname) VALUES('SA0000001','amr'),('SA0000002','sara'),('SA0000003','khalid') ON CONFLICT DO NOTHING");
for (const sql of ['DELETE FROM market_orders', 'DELETE FROM market_listings', "UPDATE users SET avatar_url=NULL", "INSERT INTO admins(user_id,granted_by) VALUES('SA0000001','test') ON CONFLICT DO NOTHING"]) { try { await pool.query(sql); } catch { /* أول تشغيل */ } }
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
const dir = new URL('.', import.meta.url).pathname;
app.register((await import('../commerce.js')).default, { pool, auth });
app.register((await import('../profile.js')).default, { pool, auth });
app.register((await import('../admin.js')).default, { pool, auth, webappDir: dir + 'webapp', opsDir: dir + 'ops' });
await app.ready(); await new Promise((r) => setTimeout(r, 300));
let fails = 0;
const check = (cond, label, extra = '') => { if (!cond) fails++; console.log((cond ? 'OK  ' : 'FAIL') + ' ' + label + (extra ? ' ' + extra : '')); };
const call = async (method, url, { body = {}, user = 'SA0000001', expect } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json', host: 'naslife.app', 'x-forwarded-proto': 'https' }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url} -> ${r.statusCode}`, r.statusCode === expect ? '' : JSON.stringify(j).slice(0, 160));
  return j;
};
// ---- صورة الحساب
const st = await call('GET', '/profile/status', { user: null, expect: 200 }); check(st.avatarColumn === 'avatar_url', 'avatar column discovered', JSON.stringify(st));
await call('POST', '/profile/avatar', { body: { url: '/chat/media/abc.jpg' }, user: null, expect: 401 });
await call('POST', '/profile/avatar', { body: { url: 'https://evil.example/x.jpg' }, expect: 400 });
await call('POST', '/profile/avatar', { body: { url: '/files/x.jpg' }, expect: 400 });
let r = await call('POST', '/profile/avatar', { body: { url: '/chat/media/abc-123.jpg' }, expect: 200 });
check(r.avatarUrl === 'https://naslife.app/chat/media/abc-123.jpg', 'absolute avatar url', r.avatarUrl);
check((await pool.query("SELECT avatar_url FROM users WHERE id='SA0000001'")).rows[0].avatar_url === r.avatarUrl, 'stored in users.avatar_url');
r = await call('POST', '/profile/avatar', { body: { url: 'https://naslife.app/chat/media/def.png' }, expect: 200 }); check(r.avatarUrl.endsWith('/chat/media/def.png'), 'absolute input accepted');
await call('DELETE', '/profile/avatar', { expect: 200 });
check((await pool.query("SELECT avatar_url FROM users WHERE id='SA0000001'")).rows[0].avatar_url === null, 'avatar cleared');
// ---- عروض السوق: صورة مطلقة، تعديل، إخفاء/إظهار، حجب الإدارة
const l = await call('POST', '/market', { body: { kind: 'product', category: 'food', title: 'برجر', description: 'طازج', price: 5000, imageUrl: '/chat/media/b.jpg' }, user: 'SA0000002', expect: 200 });
check(l.imageUrl === 'https://naslife.app/chat/media/b.jpg' && l.status === 'active', 'create with absolute image', l.imageUrl);
await call('PATCH', `/market/${l.id}`, { body: { title: 'x' }, user: 'SA0000003', expect: 403 });
await call('PATCH', `/market/${l.id}`, { body: {}, user: 'SA0000002', expect: 400 });
await call('PATCH', `/market/${l.id}`, { body: { title: '' }, user: 'SA0000002', expect: 400 });
r = await call('PATCH', `/market/${l.id}`, { body: { title: 'برجر لحم', price: 5500, imageUrl: null, placeName: 'جدة' }, user: 'SA0000002', expect: 200 });
check(r.title === 'برجر لحم' && r.price === 5500 && r.imageUrl === null && r.placeName === 'جدة', 'edit fields', JSON.stringify([r.title, r.price, r.imageUrl]));
r = await call('PATCH', `/market/${l.id}`, { body: { status: 'hidden' }, user: 'SA0000002', expect: 200 }); check(r.status === 'hidden', 'hide');
check(!(await call('GET', '/market', { user: 'SA0000003', expect: 200 })).some((x) => x.id === l.id), 'hidden not in public market');
let mine = await call('GET', '/market/mine', { user: 'SA0000002', expect: 200 }); check(mine.some((x) => x.id === l.id && x.status === 'hidden'), 'hidden appears in mine with status');
await call('GET', `/market/${l.id}`, { user: 'SA0000002', expect: 200 });
r = await call('PATCH', `/market/${l.id}`, { body: { status: 'active' }, user: 'SA0000002', expect: 200 }); check(r.status === 'active', 'unhide');
await call('PATCH', `/market/${l.id}`, { body: { status: 'sold' }, user: 'SA0000002', expect: 400 });
r = await call('POST', `/adminapi/market/${l.id}/hide`, { expect: 200 }); check(r.status === 'blocked', 'admin hide → blocked');
await call('PATCH', `/market/${l.id}`, { body: { status: 'active' }, user: 'SA0000002', expect: 403 });
mine = await call('GET', '/market/mine', { user: 'SA0000002', expect: 200 }); check(mine[0].status === 'blocked', 'blocked visible to owner as blocked');
r = await call('POST', `/adminapi/market/${l.id}/hide`, { body: { hidden: false }, expect: 200 }); check(r.status === 'active', 'admin unhide');
await call('DELETE', `/market/${l.id}`, { user: 'SA0000002', expect: 200 });
mine = await call('GET', '/market/mine', { user: 'SA0000002', expect: 200 }); check(mine[0].status === 'hidden', 'legacy delete = hidden, still in mine');
console.log(fails ? `\n${fails} FAILURES` : '\nALL PROFILE/MARKET TESTS PASSED');
await app.close(); await pool.end(); process.exit(fails ? 1 : 0);
