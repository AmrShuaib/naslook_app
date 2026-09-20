// السوق v2 على Postgres المحلي: عروض بصور وخيارات ومخزون ومواعيد، بحث بالقرب والفلاتر، طلب بمراحل ورمز وعمولة،
// كوبونات، نزاعات، تقييمات وشارات، متابعة، أسئلة، طلبات مشترين، تنبيهات، سبوت لايت، إحصاءات، فاتورة، إدارة، حماية.
import Fastify from 'fastify';
import pg from 'pg';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NODE_ENV = 'test';
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("INSERT INTO users(id,nickname,created_at) VALUES('SA0000001','amr',now()-interval '30 days'),('SA0000002','sara',now()-interval '30 days'),('SA0000003','khalid',now()-interval '30 days'),('SA0000009','newbie',now()),('SA0000000','naslife',now()-interval '60 days') ON CONFLICT (id) DO UPDATE SET created_at=EXCLUDED.created_at");
await pool.query("UPDATE users SET is_admin=true WHERE id='SA0000001'");
for (const t of ['market_reviews','market_coupons','market_seller_stats','market_seller_flags','market_follows','market_questions','market_wanted','market_wanted_replies','market_spotlight','market_alerts','market_views','market_orders','market_listings']) await pool.query(`DROP TABLE IF EXISTS ${t}`);
await pool.query("DELETE FROM wallet_tx WHERE user_id IN ('SA0000001','SA0000002','SA0000003','SA0000009','SA0000000'); DELETE FROM wallet_accounts WHERE user_id IN ('SA0000001','SA0000002','SA0000003','SA0000009','SA0000000')").catch(() => {});
const notes = []; globalThis.naslifeNotify = async (ids, p) => { notes.push({ ids: [].concat(ids), ...p }); }; globalThis.naslifeNotifyAdmins = async (p) => { notes.push({ ids: ['admins'], ...p }); };
globalThis.naslifeSettings = { marketCommissionPct: 10, spotlightPricePerDay: 1000, marketBlockContacts: true };
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
app.register((await import('../commerce.js')).default, { pool, auth });
app.register((await import('../market_plus.js')).default, { pool, auth });
await app.ready();
let fails = 0;
const call = async (method, url, { body, user = 'SA0000002', expect } = {}) => {
  const r = await app.inject({ method, url, headers: { 'x-user': user, ...(method === 'GET' ? {} : { 'content-type': 'application/json' }) }, payload: method === 'GET' ? undefined : JSON.stringify(body ?? {}) });
  let j; try { j = r.json(); } catch { j = r.body; }
  const ok = expect == null || r.statusCode === expect; if (!ok) fails++;
  console.log((ok ? 'OK  ' : 'FAIL') + ' ' + method + ' ' + url.slice(0, 70) + ' -> ' + r.statusCode + (ok ? '' : ' expected ' + expect) + ' ' + (typeof j === 'string' ? j.slice(0, 80) : JSON.stringify(j).slice(0, 150)));
  return j;
};
const check = (ok, m) => { if (!ok) fails++; console.log((ok ? 'OK  ' : 'FAIL') + ' ' + m); };
const SELLER = 'SA0000002', BUYER = 'SA0000003', ADMIN = 'SA0000001';
await call('POST', '/wallet/topup', { body: { amount: 500000 }, user: BUYER, expect: 200 });
await call('POST', '/wallet/topup', { body: { amount: 100000 }, user: SELLER, expect: 200 });
// إنشاء: صور متعددة، تصنيف فرعي، مخزون، توصيل، مدينة، موقع
const L1 = await call('POST', '/market', { body: { title: 'كيك عيد ميلاد', description: 'كيك فانيلا', kind: 'product', category: 'food', subcategory: 'sweets', price: 22000, images: ['/chat/media/a.jpg', '/seed/market/b.jpg', 'https://naslife.app/chat/media/c.jpg'], stock: 3, delivery: true, city: 'جدة', placeName: 'الروضة', lat: 21.562, lng: 39.165 }, user: SELLER, expect: 200 });
check(L1.images?.length === 3 && L1.imageUrl === L1.images[0] && L1.subcategory === 'sweets' && L1.stock === 3 && L1.delivery === true && L1.status === 'active', 'listing with 3 images, subcategory, stock and delivery');
await call('POST', '/market', { body: { title: 'كيك عيد ميلاد', price: 22000, category: 'food' }, user: SELLER, expect: 429 }); // مكرر
await call('POST', '/market', { body: { title: 'تواصل واتساب', description: 'كلمني على 0551234567', price: 100 }, user: SELLER, expect: 400 }); // رقم جوال
await call('POST', '/market', { body: { title: 'موقعي', description: 'https://example.com', price: 100 }, user: SELLER, expect: 400 });
// خيارات وأسعار
const L2 = await call('POST', '/market', { body: { title: 'عباية على المقاس', kind: 'product', category: 'other', subcategory: 'clothing', price: 30000, variants: [{ name: 'S', price: 30000, stock: 1 }, { name: 'M', price: 32000 }], lat: 21.59, lng: 39.145, city: 'جدة' }, user: SELLER, expect: 200 });
check(L2.variants.length === 2 && L2.variants[0].stock === 1 && L2.variants[1].stock === null, 'variants with prices and optional stock');
// خدمة بمواعيد
const L3 = await call('POST', '/market', { body: { title: 'درس رياضيات', kind: 'service', category: 'services', subcategory: 'education', price: 15000, availability: { days: [0, 1, 2, 3, 4, 5, 6], from: '08:00', to: '23:00', slotMinutes: 90 }, lat: 26.41, lng: 50.10, city: 'الدمام' }, user: SELLER, expect: 200 });
check(L3.availability?.slotMinutes === 90 && L3.availability.days.length === 7, 'service availability stored');
// مسودة ومجدول
const D = await call('POST', '/market', { body: { title: 'مسودة', price: 100, status: 'draft' }, user: SELLER, expect: 200 }); check(D.status === 'draft', 'draft listing');
const SCH = await call('POST', '/market', { body: { title: 'عرض مجدول', price: 100, publishAt: new Date(Date.now() + 3600000).toISOString() }, user: SELLER, expect: 200 }); check(SCH.status === 'scheduled', 'scheduled listing');
// حساب جديد: ٣ عروض ثم منع
for (let i = 1; i <= 3; i++) await call('POST', '/market', { body: { title: 'عرض ' + i, price: 100 * i }, user: 'SA0000009', expect: 200 });
await call('POST', '/market', { body: { title: 'عرض 4', price: 400 }, user: 'SA0000009', expect: 429 });
// بحث: القرب والفلاتر والترتيب
const near = await call('GET', '/market?lat=21.56&lng=39.16&sort=near', { user: BUYER, expect: 200 });
console.log('   near:', near.slice(0, 3).map((l) => l.title + '@' + l.distanceKm).join(' | '));
check(near[0]?.id === L1.id && near[0].distanceKm != null && near[0].distanceKm < 2, 'near sort puts the Jeddah listing first with distance');
const filt = await call('GET', '/market?category=food&sub=sweets&kind=product&min=20000&max=25000&delivery=1', { user: BUYER, expect: 200 }); check(filt.length === 1 && filt[0].id === L1.id, 'filters: category, sub, kind, price range, delivery');
const cheap = await call('GET', '/market?sort=cheap', { user: BUYER, expect: 200 }); check(cheap[0].price <= cheap[cheap.length - 1].price && !cheap.some((l) => l.status !== 'active'), 'cheap sort ascending, drafts and scheduled excluded');
const rad = await call('GET', '/market?lat=26.41&lng=50.10&radius=20', { user: BUYER, expect: 200 }); check(rad.length === 1 && rad[0].id === L3.id, 'radius filter keeps only Dammam listing');
// كوبون
await call('POST', '/market/coupons', { body: { code: 'welcome10', percent: 10, minTotal: 10000, maxUses: 2 }, user: SELLER, expect: 200 });
const chk = await call('GET', `/market/coupons/check?code=WELCOME10&seller=${SELLER}&total=44000`, { user: BUYER, expect: 200 }); check(chk.valid && chk.discount === 4400, 'coupon preview 10%');
// طلب بكمية ٢ وكوبون: المخزون ينقص، الرمز يصل للمشتري، العمولة ١٠٪
await call('POST', `/market/${L1.id}/order`, { body: { qty: 5 }, user: BUYER, expect: 409 }); // فوق المخزون
const O1 = await call('POST', `/market/${L1.id}/order`, { body: { qty: 2, coupon: 'welcome10', note: 'بعد المغرب' }, user: BUYER, expect: 200 });
check(O1.total === 39600 && O1.discount === 4400 && O1.commission === 3960 && /^\d{4}$/.test(O1.code), 'order total after coupon, commission 10%, 4-digit code');
const l1b = await call('GET', `/market/${L1.id}`, { user: BUYER, expect: 200 }); check(l1b.stock === 1 && l1b.sold === 2, 'stock decremented and sold counted');
await call('POST', `/market/${L2.id}/order`, { body: { qty: 1 }, user: BUYER, expect: 400 }); // خيار مطلوب
const O2 = await call('POST', `/market/${L2.id}/order`, { body: { qty: 1, variant: 'S' }, user: BUYER, expect: 200 }); check(O2.total === 30000, 'variant price used');
await call('POST', `/market/${L2.id}/order`, { body: { qty: 1, variant: 'S' }, user: BUYER, expect: 409 }); // نفد مقاس S
// خدمة: موعد مطلوب وداخل الأوقات، ولا تكرار
const slot = new Date(); slot.setUTCHours(9, 0, 0, 0); slot.setDate(slot.getDate() + 1); // 12:00 بتوقيت السعودية
await call('POST', `/market/${L3.id}/order`, { body: { qty: 1 }, user: BUYER, expect: 400 });
const O3 = await call('POST', `/market/${L3.id}/order`, { body: { qty: 1, slot: slot.toISOString() }, user: BUYER, expect: 200 });
await call('POST', `/market/${L3.id}/order`, { body: { qty: 1, slot: slot.toISOString() }, user: BUYER, expect: 409 });
// المراحل: البائع يتقدم، المشتري يرى الرمز، البائع يؤكد بالرمز الخاطئ ثم الصحيح → اكتمال وتحرير المبلغ بعد العمولة
await call('POST', `/market/orders/${O1.id}/stage`, { body: { stage: 'preparing' }, user: SELLER, expect: 200 });
await call('POST', `/market/orders/${O1.id}/stage`, { body: { stage: 'preparing' }, user: SELLER, expect: 409 });
await call('POST', `/market/orders/${O1.id}/stage`, { body: { stage: 'on_the_way' }, user: SELLER, expect: 200 });
await call('POST', `/market/orders/${O1.id}/cancel`, { user: BUYER, expect: 409 }); // بدأ التنفيذ
await call('POST', `/market/orders/${O1.id}/deliver`, { user: SELLER, expect: 200 });
const mine = await call('GET', '/market/orders', { user: BUYER, expect: 200 }); const o1 = mine.find((o) => o.id === O1.id); check(o1.status === 'delivered' && o1.code === O1.code && o1.deliveredAt, 'buyer sees delivered status and the code');
const sellerView = await call('GET', `/market/orders/${O1.id}`, { user: SELLER, expect: 200 }); check(sellerView.code === null && sellerView.commission === 3960, 'seller does not see the code but sees the commission');
await call('POST', `/market/orders/${O1.id}/confirm`, { body: { code: '0000' }, user: SELLER, expect: 400 });
const w0 = await call('GET', '/wallet', { user: SELLER, expect: 200 });
await call('POST', `/market/orders/${O1.id}/confirm`, { body: { code: O1.code }, user: SELLER, expect: 200 });
const w1 = await call('GET', '/wallet', { user: SELLER, expect: 200 }); const wp = await call('GET', '/wallet', { user: 'SA0000000', expect: 200 });
check(w1.balance - w0.balance === 39600 - 3960 && wp.balance === 3960, 'seller received net and platform received the commission');
// المشتري يؤكد بنفسه طلباً آخر
await call('POST', `/market/orders/${O2.id}/confirm`, { user: BUYER, expect: 200 });
// إلغاء يعيد المخزون (الموعد)
await call('POST', `/market/orders/${O3.id}/cancel`, { user: BUYER, expect: 200 });
const l3 = await call('GET', `/market/${L3.id}`, { user: BUYER, expect: 200 }); check(l3.sold === 0, 'cancel restores sold count');
// نزاع وحسمه بالاسترداد
const O4 = await call('POST', `/market/${L1.id}/order`, { body: { qty: 1 }, user: BUYER, expect: 200 });
await call('POST', `/market/orders/${O4.id}/dispute`, { body: { reason: 'لم يصل الطلب أبداً' }, user: BUYER, expect: 200 });
await call('POST', `/market/orders/${O4.id}/stage`, { body: { stage: 'preparing' }, user: SELLER, expect: 409 });
const wb0 = await call('GET', '/wallet', { user: BUYER, expect: 200 });
await call('POST', `/adminapi/market/disputes/${O4.id}`, { body: { resolution: 'refund', note: 'لم يثبت التسليم' }, user: SELLER, expect: 403 });
await call('POST', `/adminapi/market/disputes/${O4.id}`, { body: { resolution: 'refund', note: 'لم يثبت التسليم' }, user: ADMIN, expect: 200 });
const wb1 = await call('GET', '/wallet', { user: BUYER, expect: 200 }); check(wb1.balance - wb0.balance === 22000, 'dispute refund returned the full amount');
check(notes.some((n) => n.kind === 'market_dispute' && n.ids.includes('admins')), 'admins notified of the dispute');
// التقييم بعد الاكتمال فقط، مرة واحدة، مع رد البائع وإحصاءات البائع
await call('POST', `/market/orders/${O4.id}/review`, { body: { rating: 5 }, user: BUYER, expect: 409 });
await call('POST', `/market/orders/${O1.id}/review`, { body: { rating: 5, text: 'كيك رائع' }, user: BUYER, expect: 200 });
await call('POST', `/market/orders/${O1.id}/review`, { body: { rating: 1 }, user: BUYER, expect: 409 });
await call('POST', `/market/orders/${O2.id}/review`, { body: { rating: 4 }, user: BUYER, expect: 200 });
await call('POST', `/market/reviews/${O1.id}/reply`, { body: { text: 'شكراً لك' }, user: SELLER, expect: 200 });
const revs = await call('GET', `/market/${L1.id}/reviews`, { user: BUYER, expect: 200 }); check(revs.length === 1 && revs[0].rating === 5 && revs[0].reply === 'شكراً لك', 'listing reviews with seller reply');
const l1c = await call('GET', `/market/${L1.id}`, { user: BUYER, expect: 200 }); check(l1c.ratingAvg === 5 && l1c.ratingCount === 1 && l1c.sellerRating === 4.5 && l1c.sellerRatingCount === 2, 'listing and seller ratings on the listing');
const prof = await call('GET', `/market/sellers/${SELLER}`, { user: BUYER, expect: 200 }); check(prof.stats.completed === 2 && prof.stats.ratingAvg === 4.5 && prof.listings.length >= 3 && prof.reviews.length === 2, 'seller profile stats, listings and reviews');
// شارات: مرخّص من الإدارة
await call('PATCH', `/adminapi/market/sellers/${SELLER}/flags`, { body: { licensed: true }, user: ADMIN, expect: 200 });
const prof2 = await call('GET', `/market/sellers/${SELLER}`, { user: BUYER, expect: 200 }); check(prof2.badges.includes('licensed'), 'licensed badge');
// متابعة → إشعار عند نشر عرض جديد
await call('POST', `/market/sellers/${SELLER}/follow`, { user: BUYER, expect: 200 });
notes.length = 0;
const L5 = await call('POST', '/market', { body: { title: 'كوكيز', price: 9000, category: 'food', subcategory: 'sweets', lat: 21.56, lng: 39.16 }, user: SELLER, expect: 200 });
await new Promise((r) => setTimeout(r, 100));
check(notes.some((n) => n.kind === 'market_new' && n.ids.includes(BUYER)), 'follower notified of a new listing');
const fol = await call('GET', '/market/following', { user: BUYER, expect: 200 }); check(fol.length === 1 && fol[0].seller.id === SELLER, 'following list');
// تنبيه بكلمة داخل نطاق
await call('POST', '/market/alerts', { body: { q: 'براونيز', lat: 21.56, lng: 39.16, radiusKm: 10 }, user: 'SA0000009', expect: 200 });
notes.length = 0;
await call('POST', '/market', { body: { title: 'براونيز بالشوكولاتة', price: 8000, category: 'food', lat: 21.565, lng: 39.162 }, user: SELLER, expect: 200 });
await new Promise((r) => setTimeout(r, 100));
check(notes.some((n) => n.kind === 'market_alert' && n.ids.includes('SA0000009')), 'alert matched by keyword within radius');
// أسئلة وأجوبة
const q = await call('POST', `/market/${L1.id}/questions`, { body: { text: 'هل يتوفر بدون سكر؟' }, user: BUYER, expect: 200 });
await call('POST', `/market/questions/${q.id}/answer`, { body: { text: 'نعم بالطلب المسبق' }, user: BUYER, expect: 404 });
await call('POST', `/market/questions/${q.id}/answer`, { body: { text: 'نعم بالطلب المسبق' }, user: SELLER, expect: 200 });
const qs = await call('GET', `/market/${L1.id}/questions`, { user: BUYER, expect: 200 }); check(qs.length === 1 && qs[0].answer === 'نعم بالطلب المسبق', 'question answered by seller');
// طلبات المشترين: إشعار لبائعي التصنيف القريبين، ثم رد بعرض
notes.length = 0;
const Wd = await call('POST', '/market/wanted', { body: { title: 'أبحث عن كيك تخرج', category: 'food', budgetMax: 30000, lat: 21.56, lng: 39.16 }, user: BUYER, expect: 200 });
check(notes.some((n) => n.kind === 'market_wanted' && n.ids.includes(SELLER)), 'nearby seller notified of the wanted request');
await call('POST', `/market/wanted/${Wd.id}/replies`, { body: { text: 'عندي كيك تخرج جاهز', price: 25000, listingId: L1.id }, user: SELLER, expect: 200 });
const wd = await call('GET', `/market/wanted/${Wd.id}`, { user: BUYER, expect: 200 }); check(wd.replies === 1 && wd.replyList[0].listingTitle === 'كيك عيد ميلاد', 'wanted request carries the seller reply with its listing');
await call('PATCH', `/market/wanted/${Wd.id}`, { body: { status: 'closed' }, user: BUYER, expect: 200 });
// سبوت لايت: السعر، الشراء من المحفظة، الظهور في الرئيسية، النقر، منحة الإدارة
const price = await call('GET', '/market/spotlight/price', { user: SELLER, expect: 200 }); check(price.perDay === 1000, 'spotlight price from settings');
const ws0 = await call('GET', '/wallet', { user: SELLER, expect: 200 });
const sp = await call('POST', `/market/${L1.id}/spotlight`, { body: { days: 3 }, user: SELLER, expect: 200 });
const ws1 = await call('GET', '/wallet', { user: SELLER, expect: 200 }); check(ws0.balance - ws1.balance === 3000 && sp.paid === 3000, 'spotlight paid 3 days from the seller wallet');
const home = await call('GET', '/market/home?lat=21.56&lng=39.16', { user: BUYER, expect: 200 });
check(home.spotlight.length === 1 && home.spotlight[0].listing.id === L1.id && home.spotlight[0].listing.spotlight === true && home.nearby.length >= 3 && home.categories.food >= 3 && home.popular.length >= 1, 'market home: spotlight, nearby, popular, category counts');
await call('POST', `/market/spotlight/${sp.id}/click`, { user: BUYER, expect: 200 });
const spm = await call('GET', '/market/spotlight/mine', { user: SELLER, expect: 200 }); check(spm[0].clicks === 1 && spm[0].views >= 1 && spm[0].status === 'active', 'spotlight views and clicks tracked');
await call('POST', `/market/${L5.id}/spotlight`, { body: { days: 0 }, user: SELLER, expect: 400 });
await call('POST', '/adminapi/market/spotlight', { body: { listingId: L5.id, days: 2 }, user: ADMIN, expect: 200 });
const spotList = await call('GET', '/market/spotlight', { user: BUYER, expect: 200 }); check(spotList.length === 2, 'admin-granted spotlight appears too');
// مشاهدات وإحصاءات البائع
await call('POST', `/market/${L1.id}/view`, { user: BUYER, expect: 200 }); await call('POST', `/market/${L1.id}/view`, { user: BUYER, expect: 200 });
const st = await call('GET', '/market/seller/stats', { user: SELLER, expect: 200 });
console.log('   stats:', JSON.stringify({ month: st.month, views7: st.views7, followers: st.followers, spot: st.spotlightActive, rating: st.rating, top: st.top.length, badges: st.badges }));
check(st.month.orders >= 2 && st.views7 === 1 && st.followers === 1 && st.spotlightActive >= 1 && st.rating.avg === 4.5 && st.top.length >= 1 && st.badges.includes('licensed'), 'seller dashboard numbers');
// رفع العرض: مرة كل ٢٤ ساعة
await call('POST', `/market/${L5.id}/bump`, { user: SELLER, expect: 429 });
await pool.query("UPDATE market_listings SET bumped_at = now() - interval '2 days' WHERE id=$1", [L5.id]);
await call('POST', `/market/${L5.id}/bump`, { user: SELLER, expect: 200 });
// فاتورة
const inv = await app.inject({ method: 'GET', url: `/market/orders/${O1.id}/invoice`, headers: { 'x-user': BUYER } }); check(inv.statusCode === 200 && inv.body.includes('فاتورة') && inv.body.includes('كيك عيد ميلاد') && inv.body.includes('396'), 'invoice html');
// المسح: نشر المجدول واكتمال المسلَّم بعد ٧٢ ساعة
await pool.query("UPDATE market_listings SET publish_at = now() - interval '1 minute' WHERE id=$1", [SCH.id]);
const O5 = await call('POST', `/market/${L5.id}/order`, { body: { qty: 1 }, user: BUYER, expect: 200 });
await call('POST', `/market/orders/${O5.id}/deliver`, { user: SELLER, expect: 200 });
await pool.query("UPDATE market_orders SET delivered_at = now() - interval '4 days' WHERE id=$1", [O5.id]);
await globalThis.naslifeMarketSweep();
const sch = await call('GET', `/market/${SCH.id}`, { user: BUYER, expect: 200 }); check(sch.status === 'active', 'scheduled listing published by the sweep');
const o5 = await call('GET', `/market/orders/${O5.id}`, { user: BUYER, expect: 200 }); check(o5.status === 'completed', 'delivered order auto-completed after 72h');
// الإدارة: نظرة عامة، مراجعة الحسابات الجديدة
const ov = await call('GET', '/adminapi/market/overview', { user: ADMIN, expect: 200 });
check(ov.listings.active >= 6 && ov.commission30 >= 3960 && ov.spotlight.revenue30 === 3000 && ov.topSellers[0]?.seller.id === SELLER && ov.categories.length === 8, 'admin overview numbers');
globalThis.naslifeSettings.marketReviewNewAccounts = true;
await pool.query("DELETE FROM market_listings WHERE seller_id='SA0000009'");
const P = await call('POST', '/market', { body: { title: 'عرض يحتاج مراجعة', price: 500 }, user: 'SA0000009', expect: 200 }); check(P.status === 'pending', 'new account listing waits for review');
await call('PATCH', `/market/${P.id}`, { body: { status: 'active' }, user: 'SA0000009', expect: 409 });
const ov2 = await call('GET', '/adminapi/market/overview', { user: ADMIN, expect: 200 }); check(ov2.pending.length === 1, 'pending listing shows in admin overview');
await call('POST', `/adminapi/market/pending/${P.id}`, { body: { approve: true }, user: ADMIN, expect: 200 });
const pa = await call('GET', `/market/${P.id}`, { user: BUYER, expect: 200 }); check(pa.status === 'active', 'approved listing is active');
console.log(fails ? `FAILS: ${fails}` : 'ALL OK'); await app.close(); await pool.end(); process.exit(fails ? 1 : 0);
