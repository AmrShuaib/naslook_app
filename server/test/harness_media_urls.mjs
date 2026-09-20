// روابط الوسائط المطلقة (map_posts.js / commerce.js / profile.js): المضيف الأساسي بلا www.، إعادة بناء الروابط المطلقة لمساراتنا،
// وترحيل الصفوف المحفوظة بمضيف www. عند الإقلاع.
import Fastify from 'fastify';
import pg from 'pg';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0'; delete process.env.PUBLIC_BASE_URL;
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("INSERT INTO users(id,nickname) VALUES('SA0000001','amr'),('SA0000002','sara') ON CONFLICT DO NOTHING");
const auth = async (req) => req.headers['x-user'] || null;
let fails = 0;
const check = (cond, label, extra = '') => { if (!cond) fails++; console.log((cond ? 'OK  ' : 'FAIL') + ' ' + label + (extra ? ' ' + extra : '')); };
const build = async () => {
  const app = Fastify();
  app.register((await import('../commerce.js')).default, { pool, auth });
  app.register((await import('../profile.js')).default, { pool, auth });
  app.register((await import('../map_posts.js')).default, { pool, auth });
  await app.ready(); await new Promise((r) => setTimeout(r, 300));
  return app;
};
let app = await build();
const call = async (method, url, { body = {}, user = 'SA0000001', headers = {}, expect } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json', host: 'naslife.app', 'x-forwarded-proto': 'https', ...headers }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url} -> ${r.statusCode}`, r.statusCode === expect ? '' : JSON.stringify(j).slice(0, 160));
  return j;
};
const media = '/chat/media/mtyuxqhz-601bfd3b704da415a40b9837.mp4';
const post = (headers, mediaUrl) => call('POST', '/mapposts', { body: { kind: 'video', mediaUrl, lat: 21.5, lng: 39.2, ttlHours: 24 }, headers, expect: 200 });
let p = await post({ host: 'www.naslife.app' }, media);
check(p.mediaUrl === 'https://naslife.app' + media, 'post via www host → apex URL', p.mediaUrl);
p = await post({ 'x-forwarded-host': 'www.naslife.app' }, media);
check(p.mediaUrl === 'https://naslife.app' + media, 'post via x-forwarded-host www → apex URL', p.mediaUrl);
p = await post({}, 'https://www.naslife.app' + media);
check(p.mediaUrl === 'https://naslife.app' + media, 'absolute www URL rebuilt on apex', p.mediaUrl);
p = await post({ host: 'admin.naslife.app' }, 'https://www.naslife.app' + media);
check(p.mediaUrl === 'https://admin.naslife.app' + media, 'other subdomains kept as request host', p.mediaUrl);
p = await post({}, 'https://example.com/v.mp4');
check(p.mediaUrl === 'https://example.com/v.mp4', 'foreign absolute URL untouched', p.mediaUrl);
let e = await call('POST', '/mapposts', { body: { kind: 'video', mediaUrl: 'chat/media/x.mp4', lat: 21.5, lng: 39.2 }, expect: 400 });
check(e.error === 'bad-media', 'relative without leading slash rejected');

const l = await call('POST', '/market', { body: { kind: 'product', category: 'food', title: 'برجر', description: 'طازج', price: 5000, imageUrl: '/chat/media/b.jpg' }, headers: { host: 'www.naslife.app' }, expect: 200 });
check(l.imageUrl === 'https://naslife.app/chat/media/b.jpg', 'market image via www → apex', l.imageUrl);
const l2 = await call('PATCH', `/market/${l.id}`, { body: { imageUrl: 'https://www.naslife.app/chat/media/c.jpg' }, expect: 200 });
check(l2.imageUrl === 'https://naslife.app/chat/media/c.jpg', 'market patch absolute www → apex', l2.imageUrl);

const av = await call('POST', '/profile/avatar', { body: { url: 'https://www.naslife.app/chat/media/a.jpg' }, headers: { host: 'www.naslife.app' }, expect: 200 });
check(av.avatarUrl === 'https://naslife.app/chat/media/a.jpg', 'avatar via www → apex', av.avatarUrl);

// PUBLIC_BASE_URL يفرض الأصل
process.env.PUBLIC_BASE_URL = 'https://cdn.example.org/';
p = await post({ host: 'www.naslife.app' }, media);
check(p.mediaUrl === 'https://cdn.example.org' + media, 'PUBLIC_BASE_URL wins', p.mediaUrl);
const av2 = await call('POST', '/profile/avatar', { body: { url: '/chat/media/z.jpg' }, expect: 200 });
check(av2.avatarUrl === 'https://cdn.example.org/chat/media/z.jpg', 'PUBLIC_BASE_URL for avatar', av2.avatarUrl);
delete process.env.PUBLIC_BASE_URL;

// الترحيل عند الإقلاع: صفوف قديمة بمضيف www.
await pool.query("UPDATE map_posts SET media_url = 'https://www.naslife.app' || $1 WHERE id = $2", [media, p.id]);
await pool.query("UPDATE market_listings SET image_url = 'https://WWW.naslife.app/chat/media/c.jpg' WHERE id = $1", [l.id]);
await pool.query("UPDATE users SET avatar_url = 'http://www.naslife.app/chat/media/a.jpg' WHERE id = 'SA0000001'");
await app.close(); app = await build();
const rows = await pool.query('SELECT media_url FROM map_posts WHERE id = $1', [p.id]);
check(rows.rows[0]?.media_url === 'https://naslife.app' + media, 'startup migration: map_posts www → apex', rows.rows[0]?.media_url);
const lr = await pool.query('SELECT image_url FROM market_listings WHERE id = $1', [l.id]);
check(lr.rows[0]?.image_url === 'https://naslife.app/chat/media/c.jpg', 'startup migration: market_listings (case-insensitive)', lr.rows[0]?.image_url);
const ur = await pool.query("SELECT avatar_url FROM users WHERE id = 'SA0000001'");
check(ur.rows[0]?.avatar_url === 'http://naslife.app/chat/media/a.jpg', 'startup migration: users avatar', ur.rows[0]?.avatar_url);
await pool.query('DELETE FROM map_posts WHERE user_id = $1', ['SA0000001']); await pool.query('DELETE FROM market_listings WHERE id = $1', [l.id]);
await app.close(); await pool.end();
console.log(fails ? `\n${fails} FAILED` : '\nALL MEDIA URL TESTS PASSED');
process.exit(fails ? 1 : 0);
