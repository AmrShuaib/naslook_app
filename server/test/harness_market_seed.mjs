// تمهيد السوق على Postgres المحلي مع نواة وهمية: تسجيل البائعين، إدراج العروض، عدم التكرار، وعدم عودة المحذوف
import Fastify from 'fastify';
import pg from 'pg';
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("DROP TABLE IF EXISTS market_seed"); await pool.query("DELETE FROM users WHERE id LIKE 'SA77%'");
await pool.query("DELETE FROM market_listings WHERE image_url LIKE '%/seed/market/%'").catch(() => {});
const tokens = new Map(); let profileCalls = 0, regCalls = 0;
const auth = async (req) => req.headers['x-user'] || tokens.get(req.headers['x-token']) || null;
const app = Fastify();
// نواة وهمية: التسجيل والملف
app.post('/register', async (req, reply) => {
  regCalls++; const b = req.body ?? {}; const id = 'SA77' + String(regCalls).padStart(5, '0');
  if ((await pool.query('SELECT 1 FROM users WHERE nickname=$1', [b.nickname])).rowCount) return reply.code(409).send({ error: 'nickname-taken' });
  await pool.query('INSERT INTO users(id, nickname) VALUES($1,$2)', [id, b.nickname]); const token = 't-' + id; tokens.set(token, id);
  return { id, nickname: b.nickname, token, recoveryPhrase: 'x y z' };
});
app.put('/me/profile', async (req) => { profileCalls++; return { ok: true, bio: req.body?.bio }; });
app.register((await import('../commerce.js')).default, { pool, auth });
app.register((await import('../market_seed.js')).default, { pool, auth });
await app.ready();
let fails = 0; const check = (ok, m) => { if (!ok) fails++; console.log((ok ? 'OK  ' : 'FAIL') + ' ' + m); };
const { SELLERS, LISTINGS } = await import('../market_seed_data.js');
const r1 = await globalThis.naslifeMarketSeed();
console.log('   run1', JSON.stringify({ users: r1.users, listings: r1.listings, skipped: r1.skipped, errors: r1.errors.slice(0, 3) }));
check(r1.users === SELLERS.length && r1.listings === LISTINGS.length && r1.errors.length === 0, `first run registers ${SELLERS.length} sellers and inserts ${LISTINGS.length} listings`);
check(profileCalls === SELLERS.length, 'every seller profile was set through the core');
const n = async (sql, p = []) => (await pool.query(sql, p)).rowCount;
check((await n("SELECT 1 FROM market_listings WHERE image_url LIKE 'https://naslife.app/seed/market/%.jpg'")) === LISTINGS.length, 'image urls point at /seed/market');
const row = (await pool.query("SELECT * FROM market_listings WHERE title=$1", ['صينية كبسة دجاج كبيرة (تكفي ٦)'])).rows[0];
check(row && Number(row.price) === 18000 && row.place_name === 'الصفا' && Math.abs(row.lat - 21.598) < 0.01 && Math.abs(row.lng - 39.214) < 0.01 && row.created_at < new Date(Date.now() - 2 * 86400000), 'price in halalas, area name and jittered coordinates, dated in the past');
const r2 = await globalThis.naslifeMarketSeed();
check(r2.users === 0 && r2.listings === 0 && regCalls === SELLERS.length, 'second run adds nothing and registers nobody');
await pool.query("DELETE FROM market_listings WHERE id=$1", [row.id]);
const r3 = await globalThis.naslifeMarketSeed();
check(r3.listings === 0 && (await n("SELECT 1 FROM market_listings WHERE title=$1", [row.title])) === 0, 'a deleted seeded listing does not come back');
// القائمة العامة تعرض العروض مع البائع. القاعدة مشتركة مع حزم أخرى تترك عروض قهوة (run.sh all)، فتُسأل القائمة لكل بائع
// مُمهَّد (seller=) وتُقارن بالبيانات عرضاً عرضاً، بدل عدّ كل قهوة في القاعدة
const seededIds = new Map((await pool.query("SELECT key, user_id FROM market_seed WHERE key LIKE 'user:%'")).rows.map((r) => [r.key.slice(5), r.user_id]));
const coffee = LISTINGS.filter((l) => l.category === 'coffee');
const listed = [];
for (const nick of new Set(coffee.map((l) => l.seller))) {
  const page = (await app.inject({ method: 'GET', url: `/market?category=coffee&limit=100&seller=${seededIds.get(nick)}`, headers: { 'x-user': 'SA0000001' } })).json();
  if (Array.isArray(page)) listed.push(...page);
}
check(coffee.length > 0 && listed.length === coffee.length && coffee.every((c) => listed.some((l) => l.title === c.title && l.seller?.id === seededIds.get(c.seller) && l.seller?.nickname === c.seller)),
  `GET /market lists seeded coffee listings with sellers (${listed.length}/${coffee.length})`);
// مسار الإدارة اليدوي محمي
globalThis.naslifeIsAdmin = async (id) => id === 'SA0000001';
check((await app.inject({ method: 'POST', url: '/adminapi/market-seed/run', headers: { 'x-user': 'SA0000002' } })).statusCode === 403, 'manual run is admin-only');
check((await app.inject({ method: 'POST', url: '/adminapi/market-seed/run', headers: { 'x-user': 'SA0000001' } })).statusCode === 200, 'admin can trigger a run');
console.log(fails ? `FAILS: ${fails}` : 'ALL OK'); await app.close(); await pool.end(); process.exit(fails ? 1 : 0);
