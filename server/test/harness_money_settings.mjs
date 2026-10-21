// اختبارات مفاتيح المال التنظيمية وحدود الشحن (server/admin.js وserver/market_b.js): الافتراضي مطفأ للتحويل بين المستخدمين
// وللدفع داخل المحادثة (محفظة مغلقة حتى يتوفر مسار مرخّص)، والمدير يفعّلهما صراحة؛ حدّا الشحن بالبطاقة minTopup/maxCardTopup
// (بالهللة) يُتحقق منهما ويقرأهما /pay/config و/pay/topup؛ تفعيل الشحن التجريبي مرفوض 409 ومفاتيح ميسر الحية مضبوطة؛
// والمالية تُظهر المال التجريبي (test_topup، والشحن التجريبي الأقدم بنوع topup وملاحظة «شحن» بلا مرجع) منفصلاً عن الشحن الحقيقي؛
// وإن تعثّرت admin.js عند الإقلاع يبقى المفتاحان مطفأين على globalThis فلا يُفتح المال بغياب الإعدادات.
import Fastify from 'fastify';
import pg from 'pg';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0'; process.env.NODE_ENV = 'test';
// بوابة الدفع مفعّلة بمفاتيح اختبار من البيئة حتى يصل /pay/topup إلى فحص الحدود؛ إنشاء الفاتورة لدى ميسر يُحاكى
process.env.MOYASAR_PUBLISHABLE_KEY = 'pk_test_moneysettings1'; process.env.MOYASAR_SECRET_KEY = 'sk_test_moneysettings2';
delete process.env.PAY_MIN; delete process.env.PAY_MAX; delete process.env.PAY_EMBED;
let fails = 0;
const check = (cond, label, extra = '') => { if (!cond) fails++; console.log((cond ? 'OK  ' : 'FAIL') + ' ' + label + (extra ? ' ' + extra : '')); };
const ADMIN = 'SA0000321', U1 = 'SA0000322', U2 = 'SA0000323';
const OURS = `('${ADMIN}','${U1}','${U2}')`;
const KEYS = ['testTopup', 'transfersEnabled', 'chatPaymentsEnabled', 'minTopup', 'maxCardTopup', 'announcement'];
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query(`INSERT INTO users(id,nickname) VALUES('${ADMIN}','moneyadmin'),('${U1}','moneyone'),('${U2}','moneytwo') ON CONFLICT (id) DO UPDATE SET nickname=EXCLUDED.nickname`);
// إعدادات نظيفة قبل تحميل admin.js حتى تُختبر الافتراضيات فعلاً (القاعدة مشتركة بين الحزم)
for (const sql of [`DELETE FROM platform_settings WHERE key = ANY($1)`, `DELETE FROM admins WHERE user_id IN ${OURS}`, `DELETE FROM wallet_tx WHERE user_id IN ${OURS}`, `DELETE FROM wallet_accounts WHERE user_id IN ${OURS}`,
  `DELETE FROM chat_requests WHERE from_id IN ${OURS}`, `DELETE FROM payments WHERE user_id IN ${OURS}`]) { try { await pool.query(sql, sql.includes('$1') ? [KEYS] : []); } catch { /* أول تشغيل */ } }
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
const dir = new URL('.', import.meta.url).pathname;
app.register((await import('../notify.js')).default, { pool, auth, pollMs: 3600000, opsDir: dir + 'ops' });
app.register((await import('../commerce.js')).default, { pool, auth });
app.register((await import('../business.js')).default, { pool, auth });
app.register((await import('../admin.js')).default, { pool, auth, webappDir: dir + 'webapp', opsDir: dir + 'ops' });
app.register((await import('../market_plus.js')).default, { pool, auth });
app.register((await import('../market_b.js')).default, { pool, auth });
app.register((await import('../chat_cards.js')).default, { pool, auth });
await app.ready(); await new Promise((r) => setTimeout(r, 300));
await pool.query("INSERT INTO admins(user_id,granted_by) VALUES($1,'test') ON CONFLICT DO NOTHING", [ADMIN]);
const call = async (method, url, { body = {}, user = null, expect, headers = {} } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json', host: 'naslife.app', ...headers }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url.slice(0, 90)}${user ? '' : ' (guest)'} -> ${r.statusCode}`, r.statusCode === expect ? '' : JSON.stringify(j).slice(0, 200));
  return j;
};
const money = (kind, n = 1) => ({ messageId: `m-money-${kind}-${n}`, peerId: U2, kind, amount: 2500, n: 3, note: 'اختبار' });

// ---- الافتراضيات: المفتاحان مطفآن وحدّا الشحن بالبطاقة 100 و5,000 ريال
let pub = await call('GET', '/settings/public', { expect: 200 });
check(pub.transfersEnabled === false && pub.chatPaymentsEnabled === false, 'fresh: public settings have both money switches off', JSON.stringify(pub));
let s = await call('GET', '/adminapi/settings', { user: ADMIN, expect: 200 });
check(s.transfersEnabled === false && s.chatPaymentsEnabled === false, 'fresh: admin settings have both money switches off');
check(s.minTopup === 10000 && s.maxCardTopup === 500000 && s.maxTopup === 10000000, 'fresh: minTopup 100 SAR, maxCardTopup 5,000 SAR, test top-up cap untouched', JSON.stringify({ min: s.minTopup, max: s.maxCardTopup, test: s.maxTopup }));
await call('POST', '/wallet/topup', { body: { amount: 50000 }, user: U1, expect: 200 });
let e = await call('POST', '/wallet/transfer', { body: { to: U2, amount: 1000 }, user: U1, expect: 403 });
check(e.error === 'unavailable', 'fresh: wallet transfer refused (unavailable)');
for (const k of ['pay', 'split', 'send']) { e = await call('POST', '/chat/requests', { body: money(k), user: U1, expect: 403 }); check(e.error === 'unavailable', `fresh: chat money request "${k}" refused`); }
await call('POST', '/chat/requests', { body: { messageId: 'm-money-meet-1', peerId: U2, kind: 'meet', when: 'غداً 5م', place: 'جدة' }, user: U1, expect: 200 });

// ---- إقلاع متعثر: لو فشلت admin.js قبل تحميل الإعدادات (قاعدة متوقفة) تكون قد نشرت المفتاحين مطفأين على globalThis قبل أول استعلام،
// فيبقى commerce.js وchat_cards.js يرفضان المال بدل أن يفتحاه بغياب الإعدادات
const liveSettings = globalThis.naslifeSettings; delete globalThis.naslifeSettings;
const broken = Fastify(); let bootErr = null;
broken.register((await import('../admin.js')).default, { pool: { query: async () => { throw new Error('db down'); } }, auth });
try { await broken.ready(); } catch (err) { bootErr = err; }
check(bootErr !== null, 'admin.js does not come up on a failing pool', String(bootErr?.message ?? '').slice(0, 60));
check(globalThis.naslifeSettings?.transfersEnabled === false && globalThis.naslifeSettings?.chatPaymentsEnabled === false, 'money switches are published off before the first DB query', JSON.stringify(globalThis.naslifeSettings));
e = await call('POST', '/wallet/transfer', { body: { to: U2, amount: 1000 }, user: U1, expect: 403 });
check(e.error === 'unavailable', 'transfer refused after a failed admin boot');
e = await call('POST', '/chat/requests', { body: money('pay', 9), user: U1, expect: 403 });
check(e.error === 'unavailable', 'chat money refused after a failed admin boot');
try { await broken.close(); } catch { /* لم يكتمل الإقلاع */ }
globalThis.naslifeSettings = liveSettings;

// ---- المدير يفعّل: التحويل وحده لا يكفي للمحادثة (تحتاج المفتاحين)، ثم الدفع في المحادثة
await call('POST', '/adminapi/settings', { body: { transfersEnabled: true }, user: U1, expect: 403 });
s = await call('POST', '/adminapi/settings', { body: { transfersEnabled: true }, user: ADMIN, expect: 200 });
check(s.transfersEnabled === true && s.chatPaymentsEnabled === false, 'admin enables transfers only');
await call('POST', '/wallet/transfer', { body: { to: U2, amount: 1000 }, user: U1, expect: 200 });
e = await call('POST', '/chat/requests', { body: money('pay', 2), user: U1, expect: 403 });
check(e.error === 'unavailable', 'chat money still refused while chatPaymentsEnabled is off');
s = await call('POST', '/adminapi/settings', { body: { chatPaymentsEnabled: true }, user: ADMIN, expect: 200 });
check(s.chatPaymentsEnabled === true, 'admin enables chat payments');
pub = await call('GET', '/settings/public', { expect: 200 });
check(pub.transfersEnabled === true && pub.chatPaymentsEnabled === true, 'public settings reflect both switches on');
const rq = await call('POST', '/chat/requests', { body: money('pay', 3), user: U1, expect: 200 });
check(rq.ok === true && rq.request?.kind === 'pay', 'chat pay request accepted with both switches on');
// أي قيمة غير true صريحة تعني مطفأ
s = await call('POST', '/adminapi/settings', { body: { transfersEnabled: 'yes', chatPaymentsEnabled: 1 }, user: ADMIN, expect: 200 });
check(s.transfersEnabled === false && s.chatPaymentsEnabled === false, 'non-boolean values switch the money off (=== true)');
e = await call('POST', '/wallet/transfer', { body: { to: U2, amount: 1000 }, user: U1, expect: 403 });
check(e.error === 'unavailable', 'transfer refused again after switching off');

// ---- حدّا الشحن بالبطاقة
let cfg = await call('GET', '/pay/config', { user: U1, expect: 200 });
check(cfg.enabled === true && cfg.min === 10000 && cfg.max === 500000, '/pay/config defaults: min 100 SAR, max 5,000 SAR', JSON.stringify({ min: cfg.min, max: cfg.max }));
s = await call('POST', '/adminapi/settings', { body: { minTopup: 500, maxCardTopup: 999999999 }, user: ADMIN, expect: 200 });
check(s.minTopup === 1000 && s.maxCardTopup === 100000000, 'limits are clamped to 1,000..100,000,000 halalas', JSON.stringify({ min: s.minTopup, max: s.maxCardTopup }));
e = await call('POST', '/adminapi/settings', { body: { minTopup: 600000, maxCardTopup: 500000 }, user: ADMIN, expect: 400 });
check(e.error === 'bad-topup-limits', 'min above max is rejected');
s = await call('POST', '/adminapi/settings', { body: { minTopup: 20000, maxCardTopup: 300000 }, user: ADMIN, expect: 200 });
check(s.minTopup === 20000 && s.maxCardTopup === 300000, 'valid limits are saved');
e = await call('POST', '/adminapi/settings', { body: { maxCardTopup: 15000 }, user: ADMIN, expect: 400 });
check(e.error === 'bad-topup-limits', 'max below the stored min is rejected');
e = await call('POST', '/adminapi/settings', { body: { minTopup: 350000 }, user: ADMIN, expect: 400 });
check(e.error === 'bad-topup-limits', 'min above the stored max is rejected');
s = await call('GET', '/adminapi/settings', { user: ADMIN, expect: 200 });
check(s.minTopup === 20000 && s.maxCardTopup === 300000, 'rejected limits saved nothing');
cfg = await call('GET', '/pay/config', { user: U1, expect: 200 });
check(cfg.min === 20000 && cfg.max === 300000, '/pay/config reflects the saved limits', JSON.stringify({ min: cfg.min, max: cfg.max }));
const adminCfg = await call('GET', '/adminapi/payments/config', { user: ADMIN, expect: 200 });
check(adminCfg.min === 20000 && adminCfg.max === 300000, 'admin payments config reflects the saved limits');
e = await call('POST', '/pay/topup', { body: { amount: 15000 }, user: U1, expect: 400 });
check(e.error === 'bad-amount' && e.min === 20000 && e.max === 300000, '/pay/topup below min → bad-amount {min,max}', JSON.stringify(e));
e = await call('POST', '/pay/topup', { body: { amount: 400000 }, user: U1, expect: 400 });
check(e.error === 'bad-amount' && e.min === 20000 && e.max === 300000, '/pay/topup above max → bad-amount {min,max}', JSON.stringify(e));
// مبلغ داخل الحدود يصل إلى ميسر (محاكاة إنشاء الفاتورة المستضافة)
globalThis.naslifePayFetch = async () => ({ ok: true, status: 201, json: async () => ({ id: 'inv_money_1', status: 'initiated', url: 'https://invoice.moyasar.com/inv_money_1' }) });
const tp = await call('POST', '/pay/topup', { body: { amount: 25000 }, user: U1, expect: 200 });
check(tp.hosted === true && tp.amount === 25000 && /invoice\.moyasar\.com/.test(tp.checkoutUrl ?? ''), '/pay/topup inside the limits creates the hosted invoice', JSON.stringify(tp).slice(0, 160));
// الشحن التجريبي يبقى بسقفه المستقل maxTopup
e = await call('POST', '/wallet/topup', { body: { amount: 10000001 }, user: U1, expect: 400 });
check(e.error === 'bad-amount', 'test top-up still capped by maxTopup, not maxCardTopup');
await call('POST', '/wallet/topup', { body: { amount: 400000 }, user: U1, expect: 200 });

// ---- الشحن التجريبي مرفوض ومفاتيح ميسر الحية مضبوطة
globalThis.naslifePayMode = () => 'live';
e = await call('POST', '/adminapi/settings', { body: { testTopup: true, announcement: 'لن يُحفظ' }, user: ADMIN, expect: 409 });
check(e.error === 'test-topup-live', 'testTopup:true while pay mode is live → 409 test-topup-live');
s = await call('GET', '/adminapi/settings', { user: ADMIN, expect: 200 });
check(s.announcement !== 'لن يُحفظ', 'nothing from the refused request was saved');
s = await call('POST', '/adminapi/settings', { body: { testTopup: false }, user: ADMIN, expect: 200 });
check(s.testTopup === false && process.env.WALLET_TEST_TOPUP === '0', 'switching the test top-up off is allowed while live');
globalThis.naslifePayMode = () => 'test';
s = await call('POST', '/adminapi/settings', { body: { testTopup: true }, user: ADMIN, expect: 200 });
check(s.testTopup === true && process.env.WALLET_TEST_TOPUP === '1', 'test top-up can be switched on again with test keys');
delete globalThis.naslifePayMode;

// ---- المالية: المال التجريبي منفصل عن الشحن الحقيقي
const today = async () => { const f = await call('GET', '/adminapi/finance', { user: ADMIN, expect: 200 }); return { f, day: f.daily[f.daily.length - 1] }; };
let { f: fin0, day: d0 } = await today();
check(fin0.testTopups && typeof fin0.testTopups.count === 'number' && typeof fin0.testTopups.amount === 'number', 'finance returns testTopups {count, amount}', JSON.stringify(fin0.testTopups));
await pool.query("INSERT INTO wallet_tx(id,user_id,kind,amount,note) VALUES(gen_random_uuid(),$1,'test_topup',12345,'شحن تجريبي')", [U1]);
const { f: fin1, day: d1 } = await today();
check(fin1.testTopups.count === fin0.testTopups.count + 1 && fin1.testTopups.amount === fin0.testTopups.amount + 12345, 'test_topup rows are summed all-time', JSON.stringify(fin1.testTopups));
check(d1.topups === d0.topups, 'daily topups count only topup/credit (test_topup excluded)', `${d0.topups} → ${d1.topups}`);
// الشحن التجريبي الأقدم (قبل الحزمة: نوع topup بملاحظة «شحن» وبلا مرجع، كما يكتبه /wallet/topup) مال تجريبي لا شحن حقيقي؛
// وشحن ميسر (نوع topup مع ref وملاحظة «شحن بالبطاقة») يبقى حقيقياً
await pool.query("INSERT INTO wallet_tx(id,user_id,kind,amount,note) VALUES(gen_random_uuid(),$1,'topup',777,'شحن')", [U1]);
const { f: fin2, day: d2 } = await today();
check(fin2.testTopups.count === fin1.testTopups.count + 1 && fin2.testTopups.amount === fin1.testTopups.amount + 777, 'legacy test top-ups (topup/«شحن», no ref) count as test money', JSON.stringify(fin2.testTopups));
check(d2.topups === d1.topups, 'legacy test top-ups are not real daily topups', `${d1.topups} → ${d2.topups}`);
await pool.query("INSERT INTO wallet_tx(id,user_id,kind,amount,note,ref) VALUES(gen_random_uuid(),$1,'topup',888,'شحن بالبطاقة (mada)','pay_money_1')", [U1]);
const { f: fin3, day: d3 } = await today();
check(fin3.testTopups.count === fin2.testTopups.count && fin3.testTopups.amount === fin2.testTopups.amount, 'gateway top-ups (ref + «شحن بالبطاقة») are not test money', JSON.stringify(fin3.testTopups));
check(d3.topups === d2.topups + 888, 'gateway top-ups count as real daily topups', `${d2.topups} → ${d3.topups}`);

// ---- تنظيف: إعدادات هذه الحزمة لا تبقى للحزم التالية (القاعدة مشتركة)
await pool.query("DELETE FROM platform_settings WHERE key = ANY($1)", [KEYS]);
for (const sql of [`DELETE FROM chat_requests WHERE from_id IN ${OURS}`, `DELETE FROM payments WHERE user_id IN ${OURS}`, `DELETE FROM wallet_tx WHERE user_id IN ${OURS}`, `DELETE FROM wallet_accounts WHERE user_id IN ${OURS}`, `DELETE FROM admins WHERE user_id IN ${OURS}`]) { try { await pool.query(sql); } catch { /* ignore */ } }
await app.close(); await pool.end();
console.log(fails ? `\n${fails} FAILED` : '\nALL MONEY SETTINGS TESTS PASSED');
process.exit(fails ? 1 : 0);
