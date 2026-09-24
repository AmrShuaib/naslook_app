// اختبارات تصفح الضيف (مراجِع App Store يرى السوق والفعاليات قبل التسجيل) وحراسة عميل iOS الأصلي ومفاتيح المال:
// القراءة العامة 200 بلا جلسة، والكتابة والقوائم الشخصية 401، ومشاهدات سبوت لايت لا تُحسب للضيف؛
// سبوت لايت يحتاج مشتريات آبل في iOS، والشحن التجريبي والتحويل مطفآن في iOS، وtransfersEnabled يطفئ التحويل للجميع،
// و/settings/public يعيد supportEmail ومفتاحي المال.
import Fastify from 'fastify';
import pg from 'pg';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0'; process.env.NODE_ENV = 'test';
let fails = 0;
const check = (cond, label, extra = '') => { if (!cond) fails++; console.log((cond ? 'OK  ' : 'FAIL') + ' ' + label + (extra ? ' ' + extra : '')); };
const ADMIN = 'SA0000311', SELLER = 'SA0000312', BUYER = 'SA0000313';
const OURS = `('${ADMIN}','${SELLER}','${BUYER}')`;
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("ALTER TABLE users ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now()");
// جدول الدوائر كما في النواة (مثل harness_search): فعاليات الدائرة الخاصة لا تظهر للضيف
await pool.query("CREATE TABLE IF NOT EXISTS vessels (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), name TEXT, topic TEXT, kind TEXT DEFAULT 'general', is_public BOOLEAN DEFAULT true, owner_id TEXT, created_at TIMESTAMPTZ DEFAULT now())");
const PRIV = (await pool.query("INSERT INTO vessels(name,is_public,owner_id) VALUES('دائرة الضيف الخاصة',false,'SA0000312') RETURNING id")).rows[0].id;
await pool.query(`INSERT INTO users(id,nickname,created_at) VALUES('${ADMIN}','guestadmin',now()-interval '60 days'),('${SELLER}','guestseller',now()-interval '60 days'),('${BUYER}','guestbuyer',now()-interval '60 days')
  ON CONFLICT (id) DO UPDATE SET nickname=EXCLUDED.nickname, created_at=EXCLUDED.created_at`);
for (const sql of [`DELETE FROM market_spotlight WHERE seller_id IN ${OURS}`, `DELETE FROM market_listings WHERE seller_id IN ${OURS}`, `DELETE FROM events WHERE host_id IN ${OURS}`, `DELETE FROM user_flags WHERE user_id IN ${OURS}`,
  `DELETE FROM admins WHERE user_id IN ${OURS}`]) { try { await pool.query(sql); } catch { /* أول تشغيل */ } }
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
const dir = new URL('.', import.meta.url).pathname;
app.register((await import('../notify.js')).default, { pool, auth, pollMs: 3600000, opsDir: dir + 'ops' });
app.register((await import('../commerce.js')).default, { pool, auth });
app.register((await import('../business.js')).default, { pool, auth });
app.register((await import('../admin.js')).default, { pool, auth, webappDir: dir + 'webapp', opsDir: dir + 'ops' });
app.register((await import('../market_plus.js')).default, { pool, auth });
app.register((await import('../market_b.js')).default, { pool, auth });
await app.ready(); await new Promise((r) => setTimeout(r, 300));
await pool.query("INSERT INTO admins(user_id,granted_by) VALUES($1,'test') ON CONFLICT DO NOTHING", [ADMIN]);
const IOS = { 'x-naslife-client': 'ios/1.0.0 (build 7)' };
const call = async (method, url, { body = {}, user = null, expect, headers = {} } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json', host: 'naslife.app', ...headers }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url.slice(0, 90)}${user ? '' : ' (guest)'}${headers['x-naslife-client'] ? ' [ios]' : ''} -> ${r.statusCode}`, r.statusCode === expect ? '' : JSON.stringify(j).slice(0, 200));
  return j;
};
await call('POST', '/adminapi/settings', { body: { testTopup: true, transfersEnabled: true, chatPaymentsEnabled: true, supportEmail: '', marketReviewNewAccounts: false, spotlightPricePerDay: 1000, spotlightMaxActive: 50 }, user: ADMIN, expect: 200 });

// ---- محتوى للتصفح
await call('POST', '/wallet/topup', { body: { amount: 100000 }, user: SELLER, expect: 200 });
const L = await call('POST', '/market', { body: { kind: 'product', category: 'food', title: 'عسل سدر', price: 9000 }, user: SELLER, expect: 200 });
const L2 = await call('POST', '/market', { body: { kind: 'product', category: 'food', title: 'تمر خلاص', price: 4000 }, user: SELLER, expect: 200 });
await call('POST', `/market/${L.id}/questions`, { body: { text: 'هل هو أصلي؟' }, user: BUYER, expect: 200 });
const EV = await call('POST', '/events', { body: { title: 'سوق الأسر المنتجة', startsAt: new Date(Date.now() + 86400000).toISOString(), placeName: 'جدة', tiers: [{ name: 'دخول', price: 0, quantity: 100 }] }, user: SELLER, expect: 200 });
const BZ = await call('POST', '/adminapi/market/bazaars', { body: { title: 'بازار الضيوف', endsAt: new Date(Date.now() + 5 * 86400000).toISOString() }, user: ADMIN, expect: 200 });
await call('POST', '/adminapi/market/spotlight', { body: { listingId: L.id, days: 3 }, user: ADMIN, expect: 200 });

// ---- الضيف يقرأ
check((await call('GET', '/market', { expect: 200 })).some((x) => x.id === L.id), 'guest: market list');
check((await call('GET', `/market/${L.id}`, { expect: 200 })).mine === false, 'guest: listing detail');
const home = await call('GET', '/market/home', { expect: 200 });
check(Array.isArray(home.popular) && home.spotlightPurchasable === true, 'guest: market home');
check((await call('GET', '/market/spotlight', { expect: 200 })).some((x) => x.listing.id === L.id), 'guest: spotlight');
check(Array.isArray(await call('GET', `/market/${L.id}/reviews`, { expect: 200 })), 'guest: reviews');
check((await call('GET', `/market/${L.id}/questions`, { expect: 200 })).length === 1, 'guest: questions');
check((await call('GET', `/market/sellers/${SELLER}`, { expect: 200 })).seller.id === SELLER, 'guest: seller profile');
// الزائر لا يستعرض ملف مستخدم ليس بائعاً (لا عروض ولا سجل بيع)؛ المسجّل يراه
await pool.query("INSERT INTO users(id,nickname) VALUES('SA0000977','quiet_user') ON CONFLICT (id) DO NOTHING");
await call('GET', '/market/sellers/SA0000977', { expect: 404 });
await call('GET', '/market/sellers/SA0000977', { user: SELLER, expect: 200 });
check((await call('GET', '/market/bazaars', { expect: 200 })).some((x) => x.id === BZ.id), 'guest: bazaars');
check((await call('GET', `/market/bazaars/${BZ.id}`, { expect: 200 })).id === BZ.id, 'guest: bazaar detail');
check((await call('GET', '/events', { expect: 200 })).some((x) => x.id === EV.id), 'guest: events');
check((await call('GET', `/events/${EV.id}`, { expect: 200 })).isHost === false, 'guest: event detail');
const PEV = await call('POST', '/events', { body: { title: 'لقاء أعضاء الدائرة', vesselId: PRIV, startsAt: new Date(Date.now() + 86400000).toISOString(), placeName: 'جدة', tiers: [{ name: 'دخول', price: 0, quantity: 20 }] }, user: SELLER, expect: 200 });
check(!(await call('GET', '/events', { expect: 200 })).some((x) => x.id === PEV.id), 'guest: private-circle event not listed');
check((await call('GET', `/events?vessel=${PRIV}`, { expect: 200 })).length === 0, 'guest: private-circle events by vessel empty');
await call('GET', `/events/${PEV.id}`, { expect: 404 });
check((await call('GET', '/events', { user: BUYER, expect: 200 })).some((x) => x.id === PEV.id), 'signed-in: private-circle event listed as before');
// مشاهدات سبوت لايت للمستخدمين فقط
const views = async () => (await pool.query('SELECT views FROM market_spotlight WHERE listing_id=$1', [L.id])).rows[0].views;
const v0 = await views();
await call('GET', '/market/spotlight', { expect: 200 });
await call('GET', '/market/home', { expect: 200 });
check(await views() === v0, 'guest views do not count for spotlight', `${v0} → ${await views()}`);
await call('GET', '/market/spotlight', { user: BUYER, expect: 200 });
check(await views() === v0 + 1, 'signed-in views count');

// ---- ما يبقى بجلسة
for (const [m, u] of [['GET', '/events?mine=1'], ['GET', '/market/mine'], ['GET', '/market/orders'], ['GET', '/market/wanted'], ['GET', '/market/spotlight/price'], ['GET', '/market/following'],
  ['GET', '/market/spotlight/mine'], ['GET', '/wallet'], ['POST', '/market'], ['POST', `/market/${L.id}/questions`], ['POST', '/events'], ['POST', `/market/${L.id}/order`], ['POST', `/market/${L.id}/spotlight`],
  ['POST', `/market/bazaars/${BZ.id}/join`], ['POST', `/market/spotlight/${BZ.id}/click`], ['POST', '/wallet/transfer'], ['POST', '/wallet/topup']]) {
  await call(m, u, { body: {}, expect: 401 });
}

// ---- عميل iOS: سبوت لايت يحتاج مشتريات آبل
let e = await call('POST', `/market/${L2.id}/spotlight`, { body: { days: 1 }, user: SELLER, headers: IOS, expect: 403 });
check(e.error === 'iap-required', 'iOS: spotlight purchase needs IAP');
check((await call('GET', '/market/spotlight/price', { user: SELLER, headers: IOS, expect: 200 })).purchasable === false, 'iOS: spotlight price is not purchasable');
check((await call('GET', '/market/spotlight/price', { user: SELLER, expect: 200 })).purchasable === true, 'web: spotlight price purchasable');
check((await call('GET', '/market/home', { user: SELLER, headers: IOS, expect: 200 })).spotlightPurchasable === false, 'iOS: home says spotlight not purchasable');
await call('POST', `/market/${L2.id}/spotlight`, { body: { days: 1 }, user: SELLER, expect: 200 });
// ---- عميل iOS: لا شحن تجريبي لغير المدير، ولا تحويل
e = await call('POST', '/wallet/topup', { body: { amount: 1000 }, user: BUYER, headers: IOS, expect: 403 });
check(e.error === 'unavailable', 'iOS: test top-up refused for users');
await call('POST', '/wallet/topup', { body: { amount: 1000 }, user: ADMIN, headers: IOS, expect: 200 });
await call('POST', '/wallet/topup', { body: { amount: 5000 }, user: BUYER, expect: 200 });
e = await call('POST', '/wallet/transfer', { body: { to: SELLER, amount: 100 }, user: BUYER, headers: IOS, expect: 403 });
check(e.error === 'unavailable', 'iOS: transfers refused');
await call('POST', '/wallet/transfer', { body: { to: SELLER, amount: 100 }, user: BUYER, expect: 200 });
// ---- المفتاح transfersEnabled
await call('POST', '/adminapi/settings', { body: { transfersEnabled: false }, user: ADMIN, expect: 200 });
e = await call('POST', '/wallet/transfer', { body: { to: SELLER, amount: 100 }, user: BUYER, expect: 403 });
check(e.error === 'unavailable', 'transfersEnabled=false refuses transfers for everyone');
let pub = await call('GET', '/settings/public', { expect: 200 });
check(pub.transfersEnabled === false && pub.chatPaymentsEnabled === true, 'public settings expose the money switches', JSON.stringify(pub));
await call('POST', '/adminapi/settings', { body: { transfersEnabled: true }, user: ADMIN, expect: 200 });
await call('POST', '/wallet/transfer', { body: { to: SELLER, amount: 100 }, user: BUYER, expect: 200 });
// ---- بريد الدعم
await call('POST', '/adminapi/settings', { body: { supportEmail: 'not-an-email' }, user: ADMIN, expect: 400 });
await call('POST', '/adminapi/settings', { body: { supportEmail: 'support@areebd.sa' }, user: BUYER, expect: 403 });
await call('POST', '/adminapi/settings', { body: { supportEmail: 'support@areebd.sa' }, user: ADMIN, expect: 200 });
pub = await call('GET', '/settings/public', { expect: 200 });
check(pub.supportEmail === 'support@areebd.sa' && pub.transfersEnabled === true && typeof pub.supportHandle === 'string', 'public settings include supportEmail', JSON.stringify(pub));
await call('POST', '/adminapi/settings', { body: { supportEmail: '' }, user: ADMIN, expect: 200 });

await pool.query("DELETE FROM market_spotlight WHERE listing_id IN ($1,$2)", [L.id, L2.id]);
await pool.query('DELETE FROM market_bazaars WHERE id=$1', [BZ.id]);
// إعدادات هذه الحزمة لا تبقى للحزم التالية (القاعدة مشتركة)
await pool.query("DELETE FROM platform_settings WHERE key = ANY($1)", [['testTopup', 'transfersEnabled', 'chatPaymentsEnabled', 'supportEmail', 'marketReviewNewAccounts', 'spotlightPricePerDay', 'spotlightMaxActive']]);
await app.close(); await pool.end();
console.log(fails ? `\n${fails} FAILED` : '\nALL GUEST TESTS PASSED');
process.exit(fails ? 1 : 0);
