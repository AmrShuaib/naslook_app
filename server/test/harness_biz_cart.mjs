// سلة الدوائر (server/business.js، نوفمبر 2026): خيارات صنف المنتج وفحصها في الخادم، طلب السلة الواحد بأسطره وخياراته ومجموعه
// المحسوب من الأسعار الحالية، المخزون لكل سطر وآخر قطعة تحت التزامن، وقت الاستلام بساعات العمل، والدفع والحجز والإلغاء والاستلام
// والنزاع وقاعدة الدفع في المكان (كل صنف في السلة يقبله) بمسارات الصنف الواحد نفسها.
import Fastify from 'fastify';
import pg from 'pg';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0'; process.env.NODE_ENV = 'test';
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("ALTER TABLE users ADD COLUMN IF NOT EXISTS is_admin BOOLEAN DEFAULT false");
const USERS = ['SC0000001', 'SC0000002', 'SC0000003', 'SC0000004', 'SC0000005', 'SC0000006', 'SC0000007', 'SC0000008', 'SC0000009'];
for (const u of USERS) await pool.query("INSERT INTO users(id,nickname,is_admin) VALUES($1,$2,$3) ON CONFLICT (id) DO UPDATE SET is_admin=EXCLUDED.is_admin", [u, 'u' + u.slice(-1), u === 'SC0000004']);
// بقايا تشغيل سابق (أو حزم أخرى على القاعدة نفسها): نحذف ما يخص هذه الحزمة وحدها
for (const sql of ["DELETE FROM biz_disputes WHERE biz_id LIKE 'bc-%'", "DELETE FROM biz_orders WHERE biz_id LIKE 'bc-%'", "DELETE FROM biz_staff WHERE biz_id LIKE 'bc-%'", "DELETE FROM biz_items WHERE biz_id LIKE 'bc-%'", "DELETE FROM biz WHERE id LIKE 'bc-%'",
  "DELETE FROM wallet_tx WHERE user_id LIKE 'SC%'", "DELETE FROM wallet_accounts WHERE user_id LIKE 'SC%'"]) { try { await pool.query(sql); } catch { /* أول تشغيل */ } }
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
app.register((await import('../commerce.js')).default, { pool, auth });
app.register((await import('../business.js')).default, { pool, auth });
await app.ready(); await new Promise((r) => setTimeout(r, 500));
const { normOptions, priceLine, pickupSlots, pickupError, cartTitle } = await import('../business.js');
const sent = [];
globalThis.naslifeNotify = async (ids, payload) => { sent.push({ ids: [].concat(ids), ...payload }); };
globalThis.naslifeNotifyAdmins = async (payload) => { sent.push({ ids: ['admins'], ...payload }); };
const minors = new Set();
globalThis.naslifeAdultOk = async (uid) => !minors.has(uid);
globalThis.naslifeCheckText = (...t) => (t.some((s) => typeof s === 'string' && s.includes('محظور')) ? 'محظور' : null);

let fails = 0;
const check = (cond, label, extra = '') => { if (!cond) fails++; console.log((cond ? 'OK  ' : 'FAIL') + ' ' + label + (extra ? ' ' + extra : '')); };
const call = async (method, url, { body = {}, user = 'SC0000001', expect } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json' }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url} -> ${r.statusCode}`, r.statusCode === expect ? '' : JSON.stringify(j).slice(0, 240));
  return j;
};
const bal = async (u) => Number((await pool.query('SELECT balance FROM wallet_accounts WHERE user_id=$1', [u])).rows[0]?.balance ?? 0);
const txs = async (u, ref) => (await pool.query('SELECT kind, amount FROM wallet_tx WHERE user_id=$1 AND ref=$2 ORDER BY created_at', [u, ref])).rows.map((t) => `${t.kind}:${t.amount}`);
const stock = async (id) => (await pool.query('SELECT stock FROM biz_items WHERE id=$1', [id])).rows[0].stock;
const [O, C, STAFF, ADMIN, ...BUYERS] = USERS;

// ================= 0) دوال صرفة: الخيارات والسعر ووقت الاستلام والعنوان
console.log('--- pure helpers');
const n1 = normOptions([{ name: ' الحجم ', required: true, choices: [{ name: 'صغير' }, { name: 'كبير', delta: 500 }] }]);
check(n1.options?.[0].name === 'الحجم' && n1.options[0].required === true && n1.options[0].multi === false && /^[0-9a-f]{6}$/.test(n1.options[0].id) && n1.options[0].choices[0].delta === 0, 'normOptions trims, defaults and assigns ids', JSON.stringify(n1));
const kept = normOptions([{ id: 'size', name: 'الحجم', choices: [{ id: 'sm', name: 'صغير' }, { id: 'sm', name: 'وسط' }] }]).options;
check(kept[0].id === 'size' && kept[0].choices[0].id === 'sm' && kept[0].choices[1].id !== 'sm', 'valid ids are kept and duplicates replaced');
check(normOptions([{ name: '', choices: [{ name: 'a' }] }]).error === 'bad-options', 'group needs a name');
check(normOptions([{ name: 'g', choices: [] }]).error === 'bad-options', 'group needs at least one choice');
check(normOptions([{ name: 'g', choices: [{ name: 'a', delta: -100 }] }]).error === 'bad-options', 'negative price delta is refused');
check(normOptions([{ name: 'g', choices: [{ name: 'a', delta: 1.5 }] }]).error === 'bad-options', 'fractional halalas are refused');
check(normOptions([{ name: 'g', choices: [{ name: 'a' }, { name: 'a' }] }]).error === 'bad-options', 'duplicate choice names are refused');
check(normOptions([{ name: 'g', choices: [{ name: 'a' }] }, { name: 'g', choices: [{ name: 'b' }] }]).error === 'bad-options', 'duplicate group names are refused');
check(normOptions(Array.from({ length: 9 }, (_, i) => ({ name: 'g' + i, choices: [{ name: 'a' }] }))).error === 'bad-options', 'at most 8 groups');
check(normOptions('x').error === 'bad-options' && normOptions(null).options.length === 0, 'non-array refused, null is no options');
const item = { id: 'x', price: 1900, meta: { options: [{ id: 'size', name: 'الحجم', required: true, multi: false, choices: [{ id: 's', name: 'صغير', delta: 0 }, { id: 'l', name: 'كبير', delta: 500 }] },
  { id: 'add', name: 'إضافات', required: false, multi: true, choices: [{ id: 'shot', name: 'شوت', delta: 300 }, { id: 'syr', name: 'سيروب', delta: 200 }] }] } };
const p1 = priceLine(item, { size: ['l'], add: ['syr', 'shot'] });
check(p1.unit === 2900 && p1.options.map((o) => o.choice).join(',') === 'كبير,شوت,سيروب', 'unit = price + deltas, choices in the owner order', JSON.stringify(p1));
const thrown = (f) => { try { f(); return null; } catch (e) { return e.code; } };
check(thrown(() => priceLine(item, {})) === 'options-required', 'required group missing');
check(thrown(() => priceLine(item, { size: ['s', 'l'] })) === 'bad-options', 'two choices in a single-choice group');
check(thrown(() => priceLine(item, { size: ['zz'] })) === 'bad-options' && thrown(() => priceLine(item, { size: ['s'], nope: ['s'] })) === 'bad-options', 'unknown choice or group');
check(cartTitle([{ title: 'لاتيه' }]) === 'لاتيه' && cartTitle([{ title: 'لاتيه' }, {}]) === 'لاتيه وصنف آخر' && cartTitle([{ title: 'لاتيه' }, {}, {}]) === 'لاتيه وصنفان آخران' && cartTitle([{ title: 'لاتيه' }, {}, {}, {}]) === 'لاتيه و3 أصناف أخرى', 'cart titles in Arabic counts');
// 10:00 بتوقيت السعودية = 07:00Z، والدائرة 9 ص – 11 م
const H = 'يومياً 9:00 ص – 11:00 م';
const ten = new Date('2026-11-07T07:00:00Z');
const sl = pickupSlots(H, ten);
check(sl[0] === '2026-11-07T07:30:00.000Z' && sl.at(-1) === '2026-11-07T19:30:00.000Z', 'pickup slots every 30 min from +20 min until closing', `${sl[0]} … ${sl.at(-1)} (${sl.length})`);
check(pickupSlots('', ten) === null && pickupSlots('24 ساعة', ten).length > 0, 'unparseable hours give no slots, 24h gives many');
check(pickupSlots(H, new Date('2026-11-07T02:00:00Z'))[0] === '2026-11-07T06:00:00.000Z', 'before opening the first slot is the opening time');
check(pickupError(H, new Date('2026-11-07T17:00:00Z'), ten) === null, '20:00 today is accepted');
check(pickupError(H, new Date('2026-11-07T20:30:00Z'), ten) === 'bad-pickup', '23:30 (closed) is refused');
check(pickupError(H, new Date('2026-11-08T08:00:00Z'), ten) === 'bad-pickup', 'tomorrow is refused');
check(pickupError(H, new Date('2026-11-07T07:02:00Z'), ten) === 'bad-pickup', 'two minutes from now is too soon');
check(pickupError('', new Date('2026-11-07T17:00:00Z'), ten) === 'bad-pickup', 'unparseable hours accept only «as soon as possible»');

// ================= 1) خيارات الصنف في الكتالوج
console.log('\n--- item options in the catalog');
const mk = async (name, id, hours) => { const b = await call('POST', '/biz', { body: { name, nameAr: name, category: 'cafe', sector: 'قهوة', lat: 21.55, lng: 39.17, address: 'الروضة', hours }, expect: 200 }); await pool.query('UPDATE biz SET id=$2 WHERE id=$1', [b.id, id]); return id; };
const B = await mk('Cart Cafe', 'bc-cafe', '24 ساعة');
await pool.query(`UPDATE biz SET verification='{"status":"approved"}' WHERE id=$1`, [B]);
const U = await mk('Cart Unverified', 'bc-unver', '');
await call('POST', `/biz/${B}/team`, { body: { userId: STAFF, role: 'staff' }, expect: 200 });
const OPTS = [
  { id: 'size', name: 'الحجم', required: true, multi: false, choices: [{ id: 'sm', name: 'صغير', delta: 0 }, { id: 'md', name: 'وسط', delta: 300 }, { id: 'lg', name: 'كبير', delta: 500 }] },
  { id: 'milk', name: 'الحليب', required: false, multi: false, choices: [{ id: 'reg', name: 'عادي', delta: 0 }, { id: 'oat', name: 'شوفان', delta: 200 }] },
  { id: 'xtra', name: 'إضافات', required: false, multi: true, choices: [{ id: 'shot', name: 'شوت إضافي', delta: 300 }, { id: 'syr', name: 'سيروب', delta: 200 }] },
];
check((await call('POST', `/biz/${B}/items`, { body: { kind: 'product', title: 'سيء', price: 1000, meta: { options: [{ name: 'الحجم', choices: [] }] } }, expect: 400 })).error === 'bad-options', 'catalog refuses a group without choices');
check((await call('POST', `/biz/${B}/items`, { body: { kind: 'product', title: 'سيء', price: 1000, meta: { options: [{ name: 'الحجم', choices: [{ name: 'كبير', delta: -5 }] }] } }, expect: 400 })).error === 'bad-options', 'catalog refuses a negative delta');
check((await call('POST', `/biz/${B}/items`, { body: { kind: 'clinic', title: 'موعد', price: 1000, meta: { times: ['10:00'], options: OPTS } }, expect: 400 })).error === 'bad-options', 'options are for products only');
check((await call('POST', `/biz/${B}/items`, { body: { kind: 'product', title: 'قهوة', price: 1000, meta: { options: [{ name: 'إضافة محظور', choices: [{ name: 'a' }] }] } }, expect: 400 })).error === 'banned-words', 'option names go through the banned-words filter');
const latte = await call('POST', `/biz/${B}/items`, { body: { kind: 'product', title: 'لاتيه', price: 1900, stock: 5, payAtVenue: true, meta: { options: OPTS } }, expect: 200 });
check(latte.meta.options?.length === 3 && latte.meta.options[0].id === 'size' && latte.meta.options[2].multi === true && latte.meta.options[0].choices[2].delta === 500, 'options saved in item meta with their ids');
const croissant = await call('POST', `/biz/${B}/items`, { body: { kind: 'product', title: 'كرواسون', price: 1200, stock: 1 }, expect: 200 });
const beans = await call('POST', `/biz/${B}/items`, { body: { kind: 'product', title: 'حبوب', price: 6500, payAtVenue: true }, expect: 200 });
const water = await call('POST', `/biz/${B}/items`, { body: { kind: 'product', title: 'ماء', price: 0 }, expect: 200 });
const slotItem = await call('POST', `/biz/${B}/items`, { body: { kind: 'clinic', title: 'تذوق', price: 3000, meta: { times: ['10:00'] } }, expect: 200 });
const uFree = await call('POST', `/biz/${U}/items`, { body: { kind: 'product', title: 'عينة', price: 0 }, expect: 200 });
const uPaid = await call('POST', `/biz/${U}/items`, { body: { kind: 'product', title: 'منتج', price: 3000 }, expect: 200 });
const renamed = await call('PATCH', `/biz/${B}/items/${latte.id}`, { body: { meta: { options: OPTS.map((g, i) => (i === 0 ? { ...g, name: 'المقاس' } : g)) } }, expect: 200 });
check(renamed.meta.options[0].id === 'size' && renamed.meta.options[0].name === 'المقاس', 'renaming a group keeps its id (carts stay valid)');
const partial = await call('PATCH', `/biz/${B}/items/${latte.id}`, { body: { title: 'لاتيه' }, expect: 200 });
check(partial.meta.options?.length === 3, 'a PATCH without meta keeps the options');
check((await call('PATCH', `/biz/${B}/items/${latte.id}`, { body: { meta: { options: 'x' } }, expect: 400 })).error === 'bad-options', 'PATCH validates options too');
const tmp = await call('POST', `/biz/${B}/items`, { body: { kind: 'product', title: 'مؤقت', price: 500, meta: { options: OPTS } }, expect: 200 });
check((await call('PATCH', `/biz/${B}/items/${tmp.id}`, { body: { meta: { options: [] } }, expect: 200 })).meta.options === undefined, 'empty options remove them');
check((await call('GET', `/biz/${B}`, { user: null, expect: 200 })).items.find((i) => i.id === latte.id).meta.options.length === 3, 'public item carries its options');

// ================= 2) السعر والأسطر
console.log('\n--- cart pricing');
await call('POST', '/wallet/topup', { body: { amount: 500000 }, user: C, expect: 200 });
const cart = (lines, extra = {}) => ({ lines, ...extra });
check((await call('POST', `/biz/${B}/orders`, { body: { itemId: latte.id }, user: C, expect: 400 })).error === 'options-required', 'single-item order on a product with required options is refused');
const miss = await call('POST', `/biz/${B}/orders`, { body: cart([{ itemId: latte.id, qty: 1, options: { milk: 'oat' } }]), user: C, expect: 400 });
check(miss.error === 'options-required' && miss.itemId === latte.id && miss.group === 'المقاس', 'cart line without a required group names the item and group', JSON.stringify(miss));
check((await call('POST', `/biz/${B}/orders`, { body: cart([{ itemId: latte.id, options: { size: ['sm', 'lg'] } }]), user: C, expect: 400 })).error === 'bad-options', 'two sizes refused');
check((await call('POST', `/biz/${B}/orders`, { body: cart([{ itemId: latte.id, options: { size: 'xl' } }]), user: C, expect: 400 })).error === 'bad-options', 'unknown choice refused');
check((await call('POST', `/biz/${B}/orders`, { body: cart([{ itemId: latte.id, options: [] }]), user: C, expect: 400 })).error === 'bad-options', 'options must be a map');
check((await call('POST', `/biz/${B}/orders`, { body: cart([{ itemId: slotItem.id }]), user: C, expect: 400 })).error === 'not-orderable', 'appointments are not cart lines');
check((await call('POST', `/biz/${B}/orders`, { body: cart([{ itemId: uPaid.id }]), user: C, expect: 404 })).error === 'not-found', 'an item of another circle is not found');
check((await call('POST', `/biz/${B}/orders`, { body: cart([]), user: C, expect: 400 })).error === 'bad-lines', 'empty cart refused');
check((await call('POST', `/biz/${B}/orders`, { body: cart([{ itemId: beans.id, qty: 0 }]), user: C, expect: 400 })).error === 'bad-lines', 'qty 0 refused');
check((await call('POST', `/biz/${B}/orders`, { body: cart(Array.from({ length: 21 }, () => ({ itemId: beans.id }))), user: C, expect: 400 })).error === 'bad-lines', 'more than 20 lines refused');
check((await call('POST', `/biz/${B}/orders`, { body: cart([{ itemId: beans.id, qty: 20 }, { itemId: beans.id, qty: 20 }, { itemId: beans.id, qty: 11 }]), user: C, expect: 400 })).error === 'too-many', 'more than 50 pieces refused');
let cb = await bal(C), ob = await bal(O);
sent.length = 0;
// أسعار مرسلة من التطبيق (unit/total) تُهمل: المجموع من الأسعار الحالية في الخادم
const k1 = await call('POST', `/biz/${B}/orders`, { body: cart([
  { itemId: latte.id, qty: 2, options: { size: 'lg', milk: ['oat'], xtra: ['syr', 'shot'] }, unit: 1, total: 1 },
  { itemId: croissant.id, qty: 1, unit: 1 },
], { total: 1, note: 'بدون سكر' }), user: C, expect: 200 });
check(k1.cart === true && k1.lines?.length === 2 && k1.kind === 'product' && k1.qty === 3, 'one order row with two lines', JSON.stringify({ cart: k1.cart, n: k1.lines?.length, qty: k1.qty }));
check(k1.lines[0].unit === 1900 + 500 + 200 + 300 + 200 && k1.lines[0].total === 2 * 3100 && k1.lines[1].unit === 1200 && k1.total === 6200 + 1200, 'unit and line totals from current prices; client prices ignored', JSON.stringify(k1.lines.map((l) => [l.unit, l.total])) + ' ' + k1.total);
check(JSON.stringify(k1.lines[0].options.map((o) => `${o.group}:${o.choice}:${o.delta}`)) === JSON.stringify(['المقاس:كبير:500', 'الحليب:شوفان:200', 'إضافات:شوت إضافي:300', 'إضافات:سيروب:200']), 'line options carry group, choice and delta', JSON.stringify(k1.lines[0].options));
check(k1.title === 'لاتيه وصنف آخر' && k1.note === 'بدون سكر' && k1.pickupAt === null && k1.itemId === latte.id, 'cart title, note, «as soon as possible»');
check(k1.payment === 'wallet' && k1.funds === 'held' && await bal(C) === cb - 7400 && await bal(O) === ob, 'wallet cart is held: buyer debited, owner not credited');
check(JSON.stringify(await txs(C, k1.id)) === '["biz:-7400"]', 'one ledger entry for the whole cart', JSON.stringify(await txs(C, k1.id)));
const relIn = new Date(k1.releaseAt).getTime() - Date.now();
check(relIn > 2.9 * 86400e3 && relIn < 3.1 * 86400e3, 'release 3 days after purchase');
check(sent.some((n) => n.kind === 'biz_order' && n.ids.includes(O) && /لاتيه وصنف آخر/.test(n.body) && /الاستلام في أقرب وقت/.test(n.body)), 'team notified with the cart title and pickup', JSON.stringify(sent.map((n) => n.body)));

// ================= 3) المخزون لكل سطر
console.log('\n--- stock per line');
check(await stock(latte.id) === 3 && await stock(croissant.id) === 0 && await stock(beans.id) === null, 'stock decremented per item; open stock untouched', JSON.stringify([await stock(latte.id), await stock(croissant.id)]));
const so = await call('POST', `/biz/${B}/orders`, { body: cart([{ itemId: latte.id, qty: 2, options: { size: 'sm' } }, { itemId: latte.id, qty: 2, options: { size: 'md' } }]), user: C, expect: 409 });
check(so.error === 'sold-out' && so.left === 3 && so.itemId === latte.id, 'two lines of one item are summed against its stock', JSON.stringify(so));
check(await stock(latte.id) === 3, 'a refused cart decrements nothing');
const k2 = await call('POST', `/biz/${B}/orders`, { body: cart([{ itemId: latte.id, qty: 1, options: { size: 'sm' } }, { itemId: latte.id, qty: 2, options: { size: 'md' } }]), user: C, expect: 200 });
check(k2.lines.length === 2 && k2.total === 1900 + 2 * 2200 && await stock(latte.id) === 0, 'same item with different options is two lines', String(k2.total));
// إلغاء العميل أثناء الحجز: استرداد كامل بلا خصم من المالك، ويعود مخزون كل صنف
cb = await bal(C); ob = await bal(O);
const cc = await call('POST', `/biz/orders/${k2.id}/cancel`, { user: C, expect: 200 });
check(cc.refunded === 6300 && await bal(C) === cb + 6300 && await bal(O) === ob && await stock(latte.id) === 3, 'customer cancel refunds the cart and restocks every line');
check((await call('GET', `/biz/orders/${k2.id}`, { user: C })).funds === 'refunded' && (await txs(O, k2.id)).length === 0, 'refunded from held, no owner entry');
// إلغاء صاحب الدائرة
await call('POST', '/wallet/topup', { body: { amount: 500000 }, user: C, expect: 200 });
const k3 = await call('POST', `/biz/${B}/orders`, { body: cart([{ itemId: latte.id, qty: 3, options: { size: 'sm' } }, { itemId: beans.id, qty: 2 }]), user: C, expect: 200 });
check(await stock(latte.id) === 0, 'latte sold out');
cb = await bal(C); ob = await bal(O);
const oc = await call('POST', `/biz/${B}/orders/${k3.id}/cancel`, { expect: 200 });
check(oc.refunded === 3 * 1900 + 2 * 6500 && await bal(C) === cb + oc.refunded && await bal(O) === ob && await stock(latte.id) === 3, 'owner cancel refunds held and restocks');

// ================= 4) آخر قطعة تحت التزامن، وسلال متعاكسة الترتيب بلا تشابك
console.log('\n--- concurrency');
await pool.query('UPDATE biz_items SET stock=1 WHERE id=$1', [croissant.id]);
for (const u of BUYERS) await call('POST', '/wallet/topup', { body: { amount: 100000 }, user: u, expect: 200 });
const before = await Promise.all(BUYERS.map(bal));
const race = await Promise.all(BUYERS.map((u) => app.inject({ method: 'POST', url: `/biz/${B}/orders`, headers: { 'x-user': u, 'content-type': 'application/json' }, payload: JSON.stringify(cart([{ itemId: beans.id }, { itemId: croissant.id }])) })));
const codes = race.map((r) => r.statusCode).sort();
const after = await Promise.all(BUYERS.map(bal));
const charged = BUYERS.filter((_, i) => after[i] !== before[i]).length;
check(codes.filter((s) => s === 200).length === 1 && codes.filter((s) => s === 409).length === BUYERS.length - 1, 'only one cart gets the last croissant', JSON.stringify(codes));
check(await stock(croissant.id) === 0 && charged === 1, 'stock 0 and only the winner charged', JSON.stringify({ s: await stock(croissant.id), charged }));
check(race.filter((r) => r.statusCode === 409).every((r) => r.json().error === 'sold-out' && r.json().itemId === croissant.id), 'losers get sold-out naming the item');
await pool.query('UPDATE biz_items SET stock=50 WHERE id IN ($1,$2)', [croissant.id, latte.id]);
const crossed = await Promise.all(BUYERS.map((u, i) => app.inject({ method: 'POST', url: `/biz/${B}/orders`, headers: { 'x-user': u, 'content-type': 'application/json' },
  payload: JSON.stringify(cart(i % 2 ? [{ itemId: croissant.id }, { itemId: latte.id, options: { size: 'sm' } }] : [{ itemId: latte.id, options: { size: 'sm' } }, { itemId: croissant.id }])) })));
check(crossed.every((r) => r.statusCode === 200) && await stock(croissant.id) === 50 - BUYERS.length && await stock(latte.id) === 50 - BUYERS.length, 'carts in opposite line order all succeed (locks taken in id order)', JSON.stringify(crossed.map((r) => r.statusCode)));

// ================= 5) الاستلام والتحرير والنزاع والاسترداد
console.log('\n--- check-in, release, dispute');
const k4 = await call('POST', `/biz/${B}/orders`, { body: cart([{ itemId: latte.id, qty: 1, options: { size: 'md', milk: 'oat' } }, { itemId: beans.id, qty: 1 }]), user: C, expect: 200 });
ob = await bal(O);
const ci = await call('POST', `/biz/${B}/checkin`, { body: { code: k4.code }, user: STAFF, expect: 200 });
check(ci.status === 'used' && ci.funds === 'released' && ci.lines?.length === 2 && ci.lines[0].options.length === 2 && await bal(O) === ob + k4.total, 'check-in shows the lines and releases the whole cart', JSON.stringify({ f: ci.funds, n: ci.lines?.length }));
check(JSON.stringify(await txs(O, k4.id)) === `["biz_sale:${k4.total}"]`, 'one biz_sale entry for the cart');
check(sent.some((n) => n.kind === 'order_status' && n.ids.includes(C) && /لاتيه وصنف آخر/.test(n.body)), 'customer told about the pickup with the cart title');
const k5 = await call('POST', `/biz/${B}/orders`, { body: cart([{ itemId: latte.id, qty: 2, options: { size: 'lg' } }, { itemId: croissant.id, qty: 1 }]), user: C, expect: 200 });
const s5 = [await stock(latte.id), await stock(croissant.id)];
await call('POST', `/biz/orders/${k5.id}/dispute`, { body: { reason: 'الطلب ناقص صنفاً' }, user: C, expect: 200 });
await pool.query("UPDATE biz_orders SET release_at=now() - interval '1 minute' WHERE id=$1", [k5.id]);
ob = await bal(O);
await globalThis.naslifeBizReleaseDue();
check(await bal(O) === ob && (await call('GET', `/biz/orders/${k5.id}`, { user: C })).funds === 'held', 'an open dispute freezes the cart money');
cb = await bal(C);
const rf = await call('POST', `/adminapi/biz/disputes/${k5.id}`, { body: { resolution: 'refund' }, user: ADMIN, expect: 200 });
check(rf.order.status === 'cancelled' && rf.order.funds === 'refunded' && await bal(C) === cb + k5.total && await bal(O) === ob, 'refund decision returns the whole cart from held');
check(await stock(latte.id) === s5[0] + 2 && await stock(croissant.id) === s5[1] + 1, 'and restocks every line', JSON.stringify([await stock(latte.id), await stock(croissant.id), s5]));
const k6 = await call('POST', `/biz/${B}/orders`, { body: cart([{ itemId: beans.id, qty: 1 }]), user: C, expect: 200 });
await pool.query("UPDATE biz_orders SET release_at=now() - interval '1 minute' WHERE id=$1", [k6.id]);
ob = await bal(O);
const swept = await globalThis.naslifeBizReleaseDue();
check(swept >= 1 && await bal(O) === ob + 6500, 'the sweep releases a cart once');
check((await call('POST', `/biz/orders/${k1.id}/cancel`, { user: STAFF, expect: 404 })).error === 'not-found', 'only the customer cancels from the customer route');

// ================= 6) الدفع في المكان والتوثيق و18+
console.log('\n--- pay at venue, verification, 18+');
const mixed = await call('POST', `/biz/${B}/orders`, { body: cart([{ itemId: latte.id, options: { size: 'sm' } }, { itemId: croissant.id }], { payment: 'at_venue' }), user: C, expect: 409 });
check(mixed.error === 'venue-not-allowed', 'pay at venue refused when one line does not allow it');
cb = await bal(C);
const sv = [await stock(latte.id), await stock(beans.id)];
const v1 = await call('POST', `/biz/${B}/orders`, { body: cart([{ itemId: latte.id, qty: 2, options: { size: 'sm' } }, { itemId: beans.id }], { payment: 'at_venue' }), user: C, expect: 200 });
check(v1.payment === 'at_venue' && v1.paid === false && v1.funds === null && v1.total === 2 * 1900 + 6500 && await bal(C) === cb && (await txs(C, v1.id)).length === 0, 'all-venue cart is booked to pay at the venue without the wallet');
check(await stock(latte.id) === sv[0] - 2, 'pay-at-venue cart reserves stock');
await pool.query("UPDATE biz_orders SET created_at=now() - interval '25 hours' WHERE id=$1", [v1.id]);
const ns = await call('POST', `/biz/${B}/orders/${v1.id}/no-show`, { user: STAFF, expect: 200 });
check(ns.status === 'no_show' && await stock(latte.id) === sv[0], 'no-show on a cart restocks its lines');
const v2 = await call('POST', `/biz/${B}/orders`, { body: cart([{ itemId: beans.id }], { payment: 'at_venue' }), user: C, expect: 200 });
const pd = await call('POST', `/biz/${B}/orders/${v2.id}/paid`, { user: STAFF, expect: 200 });
check(pd.paid === true && pd.status === 'used', '«تم الدفع» on a cart');
check((await call('POST', `/biz/${U}/orders`, { body: cart([{ itemId: uPaid.id }]), user: C, expect: 403 })).error === 'not-verified', 'paid cart on an unverified circle is refused');
const fr = await call('POST', `/biz/${U}/orders`, { body: cart([{ itemId: uFree.id, qty: 2 }]), user: C, expect: 200 });
check(fr.payment === 'free' && fr.total === 0 && fr.cart === true, 'a free cart on an unverified circle is allowed');
minors.add(C);
check((await call('POST', `/biz/${B}/orders`, { body: cart([{ itemId: beans.id }]), user: C, expect: 403 })).error === 'adult-required', 'paid cart needs the 18+ declaration');
check((await call('POST', `/biz/${B}/orders`, { body: cart([{ itemId: water.id }]), user: C, expect: 200 })).payment === 'free', 'free cart without the declaration');
minors.delete(C);
check((await call('POST', `/biz/${B}/orders`, { body: cart([{ itemId: beans.id }], { note: 'كلام محظور' }), user: C, expect: 400 })).error === 'banned-words', 'the note goes through the banned-words filter');
// صنف واحد بخياراته يُطلب كسلة بسطر واحد
const one = await call('POST', `/biz/${B}/orders`, { body: { itemId: latte.id, qty: 1, options: { size: 'md' } }, user: C, expect: 200 });
check(one.cart === true && one.lines.length === 1 && one.total === 2200 && one.title === 'لاتيه', 'single item with options becomes a one-line cart');
// طلب الصنف الواحد بلا خيارات يبقى كما كان
const plain = await call('POST', `/biz/${B}/orders`, { body: { itemId: beans.id, qty: 2 }, user: C, expect: 200 });
check(plain.cart === false && plain.lines === null && plain.total === 13000 && plain.title === 'حبوب', 'plain single-item order unchanged');

// ================= 7) وقت الاستلام
console.log('\n--- pickup time');
const pub = await call('GET', `/biz/${B}`, { user: C, expect: 200 });
check(Array.isArray(pub.pickupTimes) && (await call('GET', `/biz/${U}`, { user: C, expect: 200 })).pickupTimes === null, 'detail carries pickup times only when hours are understood');
check((await call('POST', `/biz/${U}/orders`, { body: cart([{ itemId: uFree.id }], { pickupAt: new Date(Date.now() + 3600e3).toISOString() }), user: C, expect: 400 })).error === 'bad-pickup', 'unparseable hours: only «as soon as possible»');
check((await call('POST', `/biz/${B}/orders`, { body: cart([{ itemId: beans.id }], { pickupAt: new Date(Date.now() - 3600e3).toISOString() }), user: C, expect: 400 })).error === 'bad-pickup', 'a past pickup time is refused');
check((await call('POST', `/biz/${B}/orders`, { body: cart([{ itemId: beans.id }], { pickupAt: 'غداً' }), user: C, expect: 400 })).error === 'bad-pickup', 'a malformed pickup time is refused');
if (pub.pickupTimes.length) {
  const at = pub.pickupTimes[0];
  const pk = await call('POST', `/biz/${B}/orders`, { body: cart([{ itemId: beans.id }], { pickupAt: at }), user: C, expect: 200 });
  check(new Date(pk.pickupAt).getTime() === new Date(at).getTime() && new Date(pk.releaseAt).getTime() === new Date(at).getTime() + 3 * 86400e3, 'pickup time stored; release counts from it');
  check(sent.some((n) => n.kind === 'biz_order' && n.data.orderId === pk.id && /الاستلام \d\d:\d\d/.test(n.body)), 'team notice carries the pickup clock');
} else console.log('SKIP pickup slot order (near midnight in Riyadh: no slot left today)');

// ================= 8) القوائم والإحصاءات
console.log('\n--- lists and stats');
const mine = await call('GET', '/biz/orders/mine', { user: C, expect: 200 });
check(mine.find((o) => o.id === k1.id)?.lines?.length === 2, 'my orders carry the lines');
const team = await call('GET', `/biz/${B}/orders`, { user: STAFF, expect: 200 });
check(team.find((o) => o.id === k1.id)?.lines?.[0].options.length === 4 && team.find((o) => o.id === k1.id).customer?.id === C, 'owner list carries lines, options and the customer');
const detail = await call('GET', `/biz/${B}`, { user: C, expect: 200 });
check(detail.myOrders.find((o) => o.id === k1.id)?.cart === true, 'circle page «my orders» carries carts');
const st = await call('GET', `/biz/${B}/stats`, { user: STAFF, expect: 200 });
check(st.topItems.some((t) => t.itemId === croissant.id) && st.topItems.some((t) => t.itemId === latte.id), 'top items count cart lines per item', JSON.stringify(st.topItems));

// ================= 9) العروض لكل سطر (بديل محلي لـ offers.js)
console.log('\n--- offers per line');
const released = [];
globalThis.naslifeOffersApply = async (c, { item, total }) => (item.id === beans.id ? { id: '00000000-0000-4000-8000-000000000001', kind: 'deal', title: 'سعر الأسبوع', discount: Math.min(total, 1000) } : null);
globalThis.naslifeOffersRelease = async (c, orderId) => { released.push(orderId); return 0; };
const of1 = await call('POST', `/biz/${B}/orders`, { body: cart([{ itemId: beans.id, qty: 2 }, { itemId: latte.id, options: { size: 'sm' } }]), user: C, expect: 200 });
check(of1.total === 13000 + 1900 - 1000 && of1.lines[0].offer?.discount === 1000 && !of1.lines[1].offer && of1.offer?.discount === 1000 && of1.offer?.before === 14900, 'the offer applies to its line and the order shows the saving', JSON.stringify({ t: of1.total, o: of1.offer }));
const of2 = await call('POST', `/biz/${B}/orders`, { body: cart([{ itemId: beans.id }], { offerId: 'none' }), user: C, expect: 200 });
check(of2.total === 6500 && of2.offer === null, 'offerId none skips offers');
await call('POST', `/biz/orders/${of1.id}/cancel`, { user: C, expect: 200 });
check(released.includes(of1.id), 'cancelling a cart releases its offer uses');
delete globalThis.naslifeOffersApply; delete globalThis.naslifeOffersRelease;

// دوائر هذه الحزمة لا تبقى في القاعدة المشتركة (حزمة البحث تقيس ترتيب المقاهي)
for (const sql of ["DELETE FROM biz_disputes WHERE biz_id LIKE 'bc-%'", "DELETE FROM biz_orders WHERE biz_id LIKE 'bc-%'", "DELETE FROM biz_staff WHERE biz_id LIKE 'bc-%'", "DELETE FROM biz_items WHERE biz_id LIKE 'bc-%'", "DELETE FROM biz WHERE id LIKE 'bc-%'"]) await pool.query(sql);
await app.close(); await pool.end();
console.log(fails ? `\n${fails} FAILED` : '\nALL BIZ CART TESTS PASSED');
process.exit(fails ? 1 : 0);
