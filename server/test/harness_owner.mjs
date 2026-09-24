// اختبارات لوحة صاحب النشاط على Postgres المحلي: إنشاء دائرة، الكتالوج، الطلبات والاستلام، الإحصاءات، الأخبار، الردود، الفريق، الملكية.
import Fastify from 'fastify';
import pg from 'pg';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0';
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false)");
// SA0000009 قد يكون موجوداً من حزمة أخرى (newbie في harness_market2) فيُفرض كونه مديراً هنا ويُعاد في النهاية
await pool.query("INSERT INTO users(id,nickname,is_admin) VALUES('SA0000001','amr',false),('SA0000002','sara',false),('SA0000003','khalid',false),('SA0000009','admin',true) ON CONFLICT (id) DO UPDATE SET is_admin=EXCLUDED.is_admin");
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
app.register((await import('../commerce.js')).default, { pool, auth });
app.register((await import('../business.js')).default, { pool, auth });
await app.ready(); await new Promise(r => setTimeout(r, 300));
let fails = 0;
const call = async (method, url, { body = {}, user = 'SA0000001', expect } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json' }, payload: JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  const ok = expect == null || r.statusCode === expect; if (!ok) fails++;
  console.log((ok ? 'OK  ' : 'FAIL') + ' ' + method + ' ' + url + ' -> ' + r.statusCode + (ok ? '' : ' expected ' + expect) + ' ' + JSON.stringify(j).slice(0, 140));
  return j;
};
const OWNER = 'SA0000001', CUST = 'SA0000002', STAFF = 'SA0000003', ADMIN = 'SA0000009';
// إنشاء دائرة
await call('POST', '/biz', { body: { name: 'Amr Coffee', nameAr: 'قهوة عمرو', category: 'brand', sector: 'مقهى', lat: 21.5, lng: 39.2, address: 'الروضة', hours: '8-12', color: '#123456', highlights: ['توصيل', ''] }, expect: 200 }).then(b => { globalThis.BIZ = b.id; console.log('   id', b.id, 'role', b.myRole, 'active', b.active); });
await call('POST', '/biz', { body: { name: 'x', lat: 'a' }, expect: 400 });
const mine = await call('GET', '/biz/mine', { expect: 200 }); console.log('   mine:', mine.circles.map(c => c.id + ':' + c.myRole).join(','), 'admin', mine.admin);
await call('GET', '/biz/mine', { user: CUST, expect: 200 }).then(m => console.log('   sara mine:', m.circles.length));
// تعديل الملف
await call('PATCH', '/biz/' + BIZ, { body: { description: 'أفضل قهوة', website: 'https://amr.coffee', logoUrl: '/chat/media/logo.png', active: false }, expect: 200 }).then(b => console.log('   patched active', b.active, 'logo', b.logoUrl, 'site', b.website));
await call('GET', '/biz/' + BIZ, { user: CUST, expect: 404 });   // موقوفة للعامة
await call('GET', '/biz/' + BIZ, { user: OWNER, expect: 200 });
await call('PATCH', '/biz/' + BIZ, { body: { description: 'hack' }, user: CUST, expect: 403 });
await call('PATCH', '/biz/' + BIZ, { body: { active: true }, expect: 200 });
// الكتالوج
const it1 = await call('POST', '/biz/' + BIZ + '/items', { body: { title: 'لاتيه', price: 1800, stock: 10, meta: { oldPrice: 2200 } }, expect: 200 });
console.log('   item', it1.id, it1.kind, it1.unit, 'stock', it1.stock, 'old', it1.meta.oldPrice);
await call('POST', '/biz/' + BIZ + '/items', { body: { title: '' }, expect: 400 });
await call('POST', '/biz/' + BIZ + '/items', { body: { title: 'x', price: 1 }, user: CUST, expect: 403 });
await call('PATCH', '/biz/' + BIZ + '/items/' + it1.id, { body: { price: 1500, stock: 3 }, expect: 200 }).then(i => console.log('   price', i.price, 'stock', i.stock));
const it2 = await call('POST', '/biz/' + BIZ + '/items', { body: { title: 'كروسان', price: 900 }, expect: 200 });
await call('DELETE', '/biz/' + BIZ + '/items/' + it2.id, { expect: 200 });
await call('GET', '/biz/' + BIZ, { user: CUST, expect: 200 }).then(b => console.log('   public items:', b.items.map(i => i.title).join(','), '| owner sees:', ''));
await call('GET', '/biz/' + BIZ, { user: OWNER, expect: 200 }).then(b => console.log('   owner items:', b.items.map(i => i.title + (i.active ? '' : '(off)')).join(',')));
// سينما: مواعيد
const cin = await call('POST', '/biz', { body: { name: 'Amr Cinema', category: 'cinema', lat: 21.5, lng: 39.2 }, expect: 200 });
await call('POST', '/biz/' + cin.id + '/items', { body: { title: 'فيلم', price: 5000, meta: { times: ['19:00', 'bad', '21:30', '19:00'], hall: '1', minutes: 120 } }, expect: 200 }).then(i => console.log('   times', JSON.stringify(i.meta.times), 'stock', i.stock, 'slots', i.slots.length));
await call('POST', '/biz/' + cin.id + '/items', { body: { title: 'فيلم بلا مواعيد', price: 5000, meta: {} }, expect: 400 });
// طلب من عميل مع تسوية للمالك
for (let i = 0; i < 2; i++) await call('POST', '/wallet/topup', { body: { amount: 500000 }, user: CUST, expect: 200 });
const w0 = await call('GET', '/wallet', { user: OWNER, expect: 200 });
const o1 = await call('POST', '/biz/' + BIZ + '/orders', { body: { itemId: it1.id, qty: 2 }, user: CUST, expect: 200 });
const w1 = await call('GET', '/wallet', { user: OWNER, expect: 200 });
console.log('   owner balance', w0.balance, '->', w1.balance, '(expect +3000)', 'tx', w1.recent[0]?.kind);
await call('POST', '/biz/' + BIZ + '/orders', { body: { itemId: it1.id, qty: 2 }, user: CUST, expect: 409 });  // stock 3 -> 1 left
// طلبات الدائرة والاستلام
const ords = await call('GET', '/biz/' + BIZ + '/orders', { expect: 200 }); console.log('   orders', ords.length, 'customer', ords[0].customer.nickname, 'status', ords[0].status);
await call('GET', '/biz/' + BIZ + '/orders?status=upcoming&q=' + o1.code.slice(4, 8), { expect: 200 }).then(l => console.log('   filtered', l.length));
await call('GET', '/biz/' + BIZ + '/orders', { user: CUST, expect: 403 });
await call('POST', '/biz/' + BIZ + '/checkin', { body: { code: 'NAS-NOPE' }, expect: 404 });
await call('POST', '/biz/' + BIZ + '/checkin', { body: { code: o1.code.toLowerCase() }, expect: 200 }).then(o => console.log('   checked in', o.status, o.customer.nickname));
await call('POST', '/biz/' + BIZ + '/checkin', { body: { code: o1.code }, expect: 409 });
await call('POST', '/biz/orders/' + o1.id + '/cancel', { user: CUST, expect: 409 });  // مستخدم: لا يُلغى
// إلغاء من المالك لطلب مؤكد
const o2 = await call('POST', '/biz/' + BIZ + '/orders', { body: { itemId: it1.id, qty: 1 }, user: CUST, expect: 200 });
const wc0 = await call('GET', '/wallet', { user: CUST, expect: 200 });
await call('POST', '/biz/' + BIZ + '/orders/' + o2.id + '/cancel', { expect: 200 });
const wc1 = await call('GET', '/wallet', { user: CUST, expect: 200 }); const w2 = await call('GET', '/wallet', { user: OWNER, expect: 200 });
console.log('   customer refunded', wc1.balance - wc0.balance, '(expect 1500); owner', w1.balance, '->', w2.balance, '(expect', w1.balance, ')');
await call('POST', '/biz/' + BIZ + '/orders/' + o2.id + '/cancel', { expect: 409 });
// الإحصاءات
const st = await call('GET', '/biz/' + BIZ + '/stats', { expect: 200 });
console.log('   stats orders', JSON.stringify(st.orders), 'revenue', JSON.stringify(st.revenue), 'daily', st.daily.length, 'top', st.topItems[0]?.title, st.topItems[0]?.count, 'views', st.views);
// أخبار وعروض
const p1 = await call('POST', '/biz/' + BIZ + '/posts', { body: { kind: 'offer', title: 'خصم 20%', body: 'على كل المشروبات', endsAt: new Date(Date.now() + 86400000).toISOString() }, expect: 200 });
const p2 = await call('POST', '/biz/' + BIZ + '/posts', { body: { kind: 'news', title: 'منتهٍ', endsAt: new Date(Date.now() - 1000).toISOString() }, expect: 200 });
await call('GET', '/biz/' + BIZ, { user: CUST, expect: 200 }).then(b => console.log('   public posts:', b.posts.map(p => p.title).join(','), '(expect only خصم)'));
await call('PATCH', '/biz/' + BIZ + '/posts/' + p1.id, { body: { title: 'خصم 30%' }, expect: 200 }).then(p => console.log('   post title', p.title));
await call('DELETE', '/biz/' + BIZ + '/posts/' + p2.id, { expect: 200 });
// تقييم ورد
await call('POST', '/biz/' + BIZ + '/reviews', { body: { rating: 4, text: 'لذيذ' }, user: CUST, expect: 200 });
await call('POST', '/biz/' + BIZ + '/reviews/' + CUST + '/reply', { body: { text: 'شكراً لك' }, expect: 200 });
await call('GET', '/biz/' + BIZ, { user: CUST, expect: 200 }).then(b => console.log('   review reply:', b.reviews[0].reply, 'unanswered stat next'));
// الفريق
await call('POST', '/biz/' + BIZ + '/team', { body: { userId: STAFF, role: 'staff' }, expect: 200 });
await call('POST', '/biz/' + BIZ + '/team', { body: { userId: 'SA9999999', role: 'staff' }, expect: 404 });
await call('GET', '/biz/' + BIZ + '/orders', { user: STAFF, expect: 200 });
await call('PATCH', '/biz/' + BIZ, { body: { description: 'x' }, user: STAFF, expect: 403 });
await call('POST', '/biz/' + BIZ + '/team', { body: { userId: STAFF, role: 'manager' }, expect: 200 });
await call('PATCH', '/biz/' + BIZ, { body: { description: 'by manager' }, user: STAFF, expect: 200 });
await call('GET', '/biz/' + BIZ + '/team', { user: STAFF, expect: 200 }).then(t => console.log('   team owner', t.owner.nickname, 'staff', t.staff.map(s => s.user.nickname + ':' + s.role).join(',')));
await call('POST', '/biz/' + BIZ + '/team', { body: { userId: CUST }, user: STAFF, expect: 403 });
await call('DELETE', '/biz/' + BIZ + '/team/' + STAFF, { expect: 200 });
// ملكية دائرة مزروعة
await call('POST', '/biz/biz-ikea/claim', { body: { note: 'أنا مدير الفرع' }, user: CUST, expect: 200 }).then(r => console.log('   claim', r.status));
await call('GET', '/biz/claims', { user: CUST, expect: 403 });
await call('GET', '/biz/claims', { user: ADMIN, expect: 200 }).then(l => console.log('   pending claims', l.length));
await call('POST', '/biz/biz-ikea/claims/' + CUST + '/approve', { user: ADMIN, expect: 200 });
await call('GET', '/biz/biz-ikea', { user: CUST, expect: 200 }).then(b => console.log('   ikea owner now', b.ownerId, 'role', b.myRole));
await call('POST', '/biz/biz-ikea/claim', { user: STAFF, expect: 409 });
await call('POST', '/biz/biz-vox/claim', { user: ADMIN, expect: 200 }).then(r => console.log('   admin claim', r.status));
await call('GET', '/biz/mine', { user: ADMIN, expect: 200 }).then(m => console.log('   admin mine count', m.circles.length, 'first role', m.circles[0].myRole));
await call('POST', '/biz/biz-ikea/verify', { body: { verified: true }, user: ADMIN, expect: 200 });
await call('POST', '/biz/' + BIZ + '/transfer', { body: { userId: CUST }, expect: 200 });
await call('GET', '/biz/' + BIZ, { user: OWNER, expect: 200 }).then(b => console.log('   after transfer my role', b.myRole, 'owner', b.ownerId));
console.log(fails ? `\n${fails} FAILED` : '\nALL OK');
await pool.query("UPDATE users SET is_admin=false WHERE id='SA0000009'");
await app.close(); await pool.end();
