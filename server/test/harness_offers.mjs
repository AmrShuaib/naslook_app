// العروض والعضوية (server/offers.js): الأنواع الأربعة، الأهلية، التطبيق التلقائي على الطلب، الإلغاء، الإرسال لصديق، مكافأة الرواد،
// نافذة عروضي، إشعارات الأعضاء، وإدارة المالك بالقوالب والإحصاءات.
import Fastify from 'fastify';
import pg from 'pg';
import { TEMPLATES } from '../offers.js';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0';
let fails = 0;
const check = (c, l, extra = '') => { if (!c) fails++; console.log((c ? 'OK  ' : 'FAIL') + ' ' + l + (extra ? ' ' + extra : '')); };
check(TEMPLATES.length === 6 && TEMPLATES.some((t) => t.id === 'here_now' && t.kind === 'checkin'), 'templates exported');
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("INSERT INTO users(id,nickname) VALUES('SA0000001','amr'),('SA0000002','sara'),('SA0000003','khalid'),('SA0000004','nora') ON CONFLICT DO NOTHING");
for (const sql of ['DROP TABLE IF EXISTS biz_offers, biz_offer_uses, biz_offer_grants, biz_member_prefs, biz_offer_views', "DELETE FROM biz_orders WHERE biz_id LIKE 'off-%'", "DELETE FROM biz_items WHERE biz_id LIKE 'off-%'", "DELETE FROM biz_follows WHERE biz_id LIKE 'off-%'", "DELETE FROM biz_posts WHERE biz_id LIKE 'off-%'", "DELETE FROM biz WHERE id LIKE 'off-%'", 'DELETE FROM app_notifications', "UPDATE wallet_accounts SET balance=0 WHERE user_id IN ('SA0000002','SA0000003','SA0000004')"]) { try { await pool.query(sql); } catch { /* first run */ } }
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
const dir = new URL('.', import.meta.url).pathname;
app.register((await import('../notify.js')).default, { pool, auth, pollMs: 3600000, opsDir: dir + 'ops' });
app.register((await import('../commerce.js')).default, { pool, auth });
app.register((await import('../business.js')).default, { pool, auth });
app.register((await import('../offers.js')).default, { pool, auth });
await app.ready(); await new Promise((r) => setTimeout(r, 300));
const call = async (method, url, { body = {}, user = 'SA0000001', expect } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json' }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url} [${user}] -> ${r.statusCode}`, r.statusCode === expect ? '' : JSON.stringify(j).slice(0, 160));
  return j;
};
const notes = async (kind, user) => (await pool.query("SELECT user_id, title, body, data FROM app_notifications WHERE kind=$1 AND user_id=$2 ORDER BY created_at", [kind, user])).rows;
const OWNER = 'SA0000001', SARA = 'SA0000002', KHALID = 'SA0000003', NORA = 'SA0000004';
const h = (n) => new Date(Date.now() + n * 3600000).toISOString();

// ---- الدائرة والمنتجات والمحافظ
const biz = await call('POST', '/biz', { body: { name: 'Reef Cafe', nameAr: 'مقهى ريف', category: 'cafe', sector: 'قهوة مختصة', lat: 21.5433, lng: 39.1728, address: 'الروضة' }, expect: 200 });
await pool.query("UPDATE biz SET id='off-reef' WHERE id=$1", [biz.id]); const B = 'off-reef';
const cortado = await call('POST', `/biz/${B}/items`, { body: { title: 'كورتادو', price: 1400, stock: 100 }, expect: 200 });
const latte = await call('POST', `/biz/${B}/items`, { body: { title: 'لاتيه', price: 1600, stock: 100 }, expect: 200 });
for (const u of [SARA, KHALID, NORA]) for (let i = 0; i < 2; i++) await call('POST', '/wallet/topup', { body: { amount: 500000 }, user: u, expect: 200 });
// سارة عضو، خالد عضو، نورا ليست عضواً
await call('POST', `/biz/${B}/follow`, { user: SARA, expect: 200 });
await call('POST', `/biz/${B}/follow`, { user: KHALID, expect: 200 });
await call('PUT', `/biz/${B}/notify`, { body: { notify: 'all' }, user: SARA, expect: 200 });
await call('PUT', `/biz/${B}/notify`, { body: { notify: 'weird' }, user: SARA, expect: 400 });
await call('PUT', `/biz/${B}/notify`, { body: { notify: 'all' }, user: NORA, expect: 409 });
let pf = await call('GET', `/biz/${B}/notify`, { user: KHALID, expect: 200 });
check(pf.member === true && pf.notify === 'near', 'default notify level is near');

// ---- الإدارة: التحقق
await call('POST', `/biz/${B}/manage/offers`, { body: { kind: 'coupon', title: 'x', value: { type: 'percent', amount: 10 }, endsAt: h(24) }, user: SARA, expect: 403 });
await call('POST', `/biz/${B}/manage/offers`, { body: { kind: 'magic', title: 'خصم', value: { type: 'percent', amount: 10 }, endsAt: h(24) }, expect: 400 });
await call('POST', `/biz/${B}/manage/offers`, { body: { kind: 'coupon', title: 'خصم', value: { type: 'percent', amount: 150 }, endsAt: h(24) }, expect: 400 });
await call('POST', `/biz/${B}/manage/offers`, { body: { kind: 'coupon', title: 'خصم', value: { type: 'percent', amount: 10 } }, expect: 400 });
await call('POST', `/biz/${B}/manage/offers`, { body: { kind: 'deal', title: 'سعر', value: { type: 'price', amount: 1200 }, endsAt: h(24) }, expect: 400 });
await call('POST', `/biz/${B}/manage/offers`, { body: { kind: 'deal', title: 'سعر', value: { type: 'price', amount: 1600 }, itemId: cortado.id, endsAt: h(24) }, expect: 400 });
await call('POST', `/biz/${B}/manage/offers`, { body: { kind: 'coupon', title: 'خصم', value: { type: 'percent', amount: 10 }, endsAt: h(-1) }, expect: 400 });

// ---- عرض عام: كورتادو بـ 10 بدل 14 (للجميع)
const deal = await call('POST', `/biz/${B}/manage/offers`, { body: { kind: 'deal', title: 'كورتادو بـ 10', value: { type: 'price', amount: 1000 }, itemId: cortado.id, endsAt: h(5), template: 'product_week' }, expect: 200 });
check(deal.kind === 'deal' && deal.membersOnly === false && deal.state === 'active' && deal.itemTitle === 'كورتادو' && deal.notified === 1, 'deal created, public, notified the one all-level member', JSON.stringify([deal.membersOnly, deal.state, deal.notified]));
check((await notes('biz_offer', SARA)).length === 1 && (await notes('biz_offer', KHALID)).length === 0, 'only members on "all" get the offer notification');
let d = await call('GET', `/biz/${B}`, { user: NORA, expect: 200 });
const cIt = d.items.find((i) => i.id === cortado.id);
check(cIt.deal && cIt.deal.price === 1000 && cIt.deal.title === 'كورتادو بـ 10' && !d.items.find((i) => i.id === latte.id).deal && d.offers === 1, 'circle detail annotates the item with the deal price and counts offers', JSON.stringify(cIt.deal));
const lst = await call('GET', '/biz?category=cafe', { user: null, expect: 200 });
check(lst.find((b) => b.id === B)?.offers === 1, 'list carries offer counts for map badges');
// غير عضو يطلب كورتادو: الخصم يُطبَّق تلقائياً
let o = await call('POST', `/biz/${B}/orders`, { body: { itemId: cortado.id, qty: 2 }, user: NORA, expect: 200 });
check(o.total === 2000 && o.offer && o.offer.discount === 800 && o.offer.before === 2800 && o.offer.title === 'كورتادو بـ 10', 'public deal applied automatically to a non-member order', JSON.stringify(o.offer));
o = await call('POST', `/biz/${B}/orders`, { body: { itemId: cortado.id, qty: 1, offerId: 'none' }, user: NORA, expect: 200 });
check(o.total === 1400 && o.offer === null, 'offerId none skips the deal');

// ---- كوبون للأعضاء: 20٪ لأول طلب، حد 2 إجمالاً
const first = await call('POST', `/biz/${B}/manage/offers`, { body: { kind: 'coupon', title: 'أول طلب 20٪', value: { type: 'percent', amount: 20 }, conditions: { firstOrder: true, total: 2, perUser: 1 }, endsAt: h(48) }, expect: 200 });
check(first.membersOnly === true && first.transferable === true && first.conditions.firstOrder === true && first.left === undefined, 'coupon defaults: members only, transferable');
let list = await call('GET', `/biz/${B}/offers`, { user: NORA, expect: 200 });
let f = list.active.find((x) => x.id === first.id);
check(list.member === false && list.notify === null && f.eligible === false && f.lockedReason === 'members' && list.active.find((x) => x.id === deal.id).eligible === true, 'non-member sees the coupon locked and the deal open', JSON.stringify([f.eligible, f.lockedReason]));
list = await call('GET', `/biz/${B}/offers`, { user: SARA, expect: 200 });
f = list.active.find((x) => x.id === first.id);
check(list.member === true && list.notify === 'all' && f.eligible === true && f.via === 'member' && f.canSend === true && f.left === 2, 'member is eligible and can send', JSON.stringify([f.eligible, f.via, f.canSend, f.left]));
list = await call('GET', `/biz/${B}/offers`, { user: null, expect: 200 });
check(list.active.length === 2 && list.active.every((x) => x.eligible === false) && list.active.find((x) => x.id === deal.id).lockedReason === null, 'guest sees offers without eligibility');
// نورا طلبت سابقاً فلا يناسبها "أول طلب"؛ سارة لم تطلب
o = await call('POST', `/biz/${B}/orders`, { body: { itemId: latte.id, qty: 2 }, user: SARA, expect: 200 });
check(o.total === 2560 && o.offer.discount === 640 && o.offer.id === first.id, 'best eligible coupon applied to the member order (20% of 32)', JSON.stringify(o.offer));
o = await call('POST', `/biz/${B}/orders`, { body: { itemId: latte.id, qty: 1 }, user: SARA, expect: 200 });
check(o.offer === null && o.total === 1600, 'per-user limit reached: no coupon on the second order');
o = await call('POST', `/biz/${B}/orders`, { body: { itemId: latte.id, qty: 1, offerId: first.id }, user: SARA, expect: 409 });
check(o.error === 'offer-unavailable' && o.reason === 'used', 'explicit offerId that is used up is rejected with the reason');
o = await call('POST', `/biz/${B}/orders`, { body: { itemId: latte.id, qty: 1, offerId: first.id }, user: NORA, expect: 409 });
check(o.reason === 'members', 'non-member cannot force a members coupon');
// الإلغاء يعيد الاستحقاق
const sOrders = await call('GET', '/biz/orders/mine', { user: SARA, expect: 200 });
const withCoupon = sOrders.find((x) => x.offer && x.offer.id === first.id);
await call('POST', `/biz/orders/${withCoupon.id}/cancel`, { user: SARA, expect: 200 });
list = await call('GET', `/biz/${B}/offers`, { user: SARA, expect: 200 });
f = list.active.find((x) => x.id === first.id);
check(f.eligible === true && f.note === 'first-order' && (await pool.query('SELECT count(*)::int AS n FROM biz_offer_uses WHERE offer_id=$1 AND user_id=$2', [first.id, SARA])).rows[0].n === 0, 'cancelling the order restores the allowance; listing notes the first-order condition', JSON.stringify([f.eligible, f.note]));
// خالد عضو ولم يطلب: أول طلب يناسبه؛ الحد الإجمالي 2 يُستهلك بعده (سارة واحد + خالد واحد)
o = await call('POST', `/biz/${B}/orders`, { body: { itemId: cortado.id, qty: 1 }, user: KHALID, expect: 200 });
check(o.offer && o.offer.id === deal.id && o.offer.discount === 400, 'best discount wins: deal (400) beats 20% coupon (280) on a 14 SAR cortado', JSON.stringify(o.offer));
o = await call('POST', `/biz/${B}/orders`, { body: { itemId: latte.id, qty: 3, offerId: first.id }, user: KHALID, expect: 409 });
check(o.reason === 'first-order', 'first-order coupon refused after a prior order');

// ---- إرسال كوبون لصديق
let snd = await call('POST', `/biz/${B}/offers/${first.id}/send`, { body: { toUserId: SARA }, user: SARA, expect: 400 });
snd = await call('POST', `/biz/${B}/offers/${first.id}/send`, { body: { toUserId: 'SA9999999' }, user: SARA, expect: 404 });
snd = await call('POST', `/biz/${B}/offers/${first.id}/send`, { body: { toUserId: KHALID }, user: SARA, expect: 409 });
check(snd.error === 'already-has', 'member who still holds an allowance cannot receive');
snd = await call('POST', `/biz/${B}/offers/${deal.id}/send`, { body: { toUserId: NORA }, user: SARA, expect: 409 });
check(snd.error === 'not-transferable', 'deals are not transferable');
snd = await call('POST', `/biz/${B}/offers/${first.id}/send`, { body: { toUserId: NORA }, user: SARA, expect: 200 });
check(snd.ok && snd.to.id === NORA, 'coupon sent to a non-member');
check((await notes('offer_received', NORA)).length === 1, 'recipient notified');
list = await call('GET', `/biz/${B}/offers`, { user: SARA, expect: 200 });
check(list.active.find((x) => x.id === first.id).eligible === false && list.active.find((x) => x.id === first.id).lockedReason === 'used', 'sender lost the allowance');
list = await call('GET', `/biz/${B}/offers`, { user: NORA, expect: 200 });
f = list.active.find((x) => x.id === first.id);
check(f.eligible === true && f.via === 'grant' && f.grant.from.id === SARA && f.canSend === false, 'recipient eligible through the grant, cannot re-send', JSON.stringify([f.via, f.canSend]));
snd = await call('POST', `/biz/${B}/offers/${first.id}/send`, { body: { toUserId: KHALID }, user: NORA, expect: 409 });
check(snd.error === 'not-transferable', 'a received coupon moves only once');
// نورا طلبت سابقاً لكن firstOrder شرط على العرض؛ الشرط يُطبَّق على المستلم أيضاً
o = await call('POST', `/biz/${B}/orders`, { body: { itemId: latte.id, qty: 1, offerId: first.id }, user: NORA, expect: 409 });
check(o.reason === 'first-order', 'grant still obeys the offer conditions');
// كوبون بلا شرط أول طلب يُرسل ويُستخدم
const ten = await call('POST', `/biz/${B}/manage/offers`, { body: { kind: 'coupon', title: '10 ريالات', value: { type: 'amount', amount: 1000 }, conditions: { minTotal: 3000 }, endsAt: h(48) }, expect: 200 });
o = await call('POST', `/biz/${B}/orders`, { body: { itemId: latte.id, qty: 1, offerId: ten.id }, user: KHALID, expect: 409 });
check(o.reason === 'min-total', 'minimum total enforced');
await call('POST', `/biz/${B}/offers/${ten.id}/send`, { body: { toUserId: NORA }, user: KHALID, expect: 200 });
o = await call('POST', `/biz/${B}/orders`, { body: { itemId: latte.id, qty: 2 }, user: NORA, expect: 200 });
check(o.offer && o.offer.id === ten.id && o.total === 2200, 'recipient used the sent coupon automatically (32 - 10)', JSON.stringify(o.offer));
const gr = (await pool.query('SELECT used_at, order_id FROM biz_offer_grants WHERE offer_id=$1 AND user_id=$2', [ten.id, NORA])).rows[0];
check(gr.used_at && gr.order_id === o.id, 'grant marked used with the order');

// ---- خصم لحظي: يحتاج موقعاً قريباً
const here = await call('POST', `/biz/${B}/manage/offers`, { body: { kind: 'checkin', title: '15٪ لمن هنا الآن', value: { type: 'percent', amount: 15 }, conditions: { radiusM: 300 }, endsAt: h(3), template: 'here_now' }, expect: 200 });
o = await call('POST', `/biz/${B}/orders`, { body: { itemId: latte.id, qty: 1, offerId: here.id }, user: KHALID, expect: 409 });
check(o.reason === 'near', 'check-in deal needs a location');
o = await call('POST', `/biz/${B}/orders`, { body: { itemId: latte.id, qty: 1, offerId: here.id, lat: 21.60, lng: 39.20 }, user: KHALID, expect: 409 });
check(o.reason === 'near', 'far away location rejected');
o = await call('POST', `/biz/${B}/orders`, { body: { itemId: latte.id, qty: 1, lat: 21.5434, lng: 39.1729 }, user: KHALID, expect: 200 });
check(o.offer && o.offer.id === here.id && o.total === 1360, 'nearby member gets the instant discount automatically', JSON.stringify(o.offer));
o = await call('POST', `/biz/${B}/orders`, { body: { itemId: latte.id, qty: 1, offerId: here.id, lat: 21.5434, lng: 39.1729 }, user: KHALID, expect: 409 });
check(o.reason === 'used-today', 'instant discount once per day');
list = await call('GET', `/biz/${B}/offers`, { user: SARA, expect: 200 });
f = list.active.find((x) => x.id === here.id);
check(f.eligible === true && f.canSend === true, 'listing does not require location; eligibility is checked at order time');

// ---- مكافأة الرواد: كل 3 طلبات مستلمة كورتادو مجاني
const loyal = await call('POST', `/biz/${B}/manage/offers`, { body: { kind: 'loyalty', title: 'الطلب الرابع كورتادو مجاني', value: { type: 'free_item' }, itemId: cortado.id, conditions: { every: 3 } }, expect: 200 });
check(loyal.transferable === false && loyal.endsAt === null && loyal.state === 'active', 'loyalty: open-ended, not transferable');
list = await call('GET', `/biz/${B}/offers`, { user: SARA, expect: 200 });
f = list.active.find((x) => x.id === loyal.id);
check(f.eligible === false && f.lockedReason === 'loyalty' && f.loyalty.every === 3 && f.loyalty.count === 0, 'loyalty shows progress instead of eligibility', JSON.stringify(f.loyalty));
const sOrd = await call('GET', '/biz/orders/mine', { user: SARA, expect: 200 });
const live = sOrd.filter((x) => x.status === 'confirmed');
for (const x of live) await call('POST', `/biz/${B}/checkin`, { body: { code: x.code }, expect: 200 });
for (let i = live.length; i < 3; i++) { const oo = await call('POST', `/biz/${B}/orders`, { body: { itemId: latte.id, qty: 1, offerId: 'none' }, user: SARA, expect: 200 }); await call('POST', `/biz/${B}/checkin`, { body: { code: oo.code }, expect: 200 }); }
check((await notes('offer_loyalty', SARA)).length === 1, 'third redeemed order grants the reward and notifies');
list = await call('GET', `/biz/${B}/offers`, { user: SARA, expect: 200 });
f = list.active.find((x) => x.id === loyal.id);
check(f.eligible === true && f.via === 'grant' && f.grant.reason === 'loyalty' && f.loyalty.count === 0 && f.loyalty.total === 3, 'reward grant is usable', JSON.stringify([f.via, f.grant?.reason, f.loyalty]));
o = await call('POST', `/biz/${B}/orders`, { body: { itemId: cortado.id, qty: 1 }, user: SARA, expect: 200 });
check(o.offer && o.offer.id === loyal.id && o.total === 0 && o.offer.discount === 1400, 'free cortado: total zero, no wallet charge', JSON.stringify(o.offer));
const wal = (await pool.query("SELECT amount FROM wallet_tx WHERE user_id=$1 AND ref=$2", [SARA, o.id])).rows;
check(wal.length === 0, 'zero total order writes no wallet transaction');
snd = await call('POST', `/biz/${B}/offers/${loyal.id}/send`, { body: { toUserId: NORA }, user: SARA, expect: 409 });
check(snd.error === 'not-transferable', 'loyalty rewards stay personal');

// ---- عروضي
let mine = await call('GET', '/offers/mine', { user: NORA, expect: 200 });
check(mine.active.length === 1 && mine.active[0].id === first.id && mine.active[0].biz.name === 'مقهى ريف' && mine.used.length === 2 && mine.savings.total === 800 + 1000 && mine.counts.used === 2, 'non-member sees granted coupon and her uses with savings', JSON.stringify([mine.active.map((x) => x.title), mine.savings]));
mine = await call('GET', '/offers/mine', { user: SARA, expect: 200 });
check(mine.active.some((x) => x.id === here.id) && mine.active.some((x) => x.id === deal.id) && !mine.active.some((x) => x.id === first.id) && mine.active.find((x) => x.id === loyal.id)?.loyalty?.total === 3, 'member sees what she can still use plus loyalty progress; sent ones drop out', JSON.stringify(mine.active.map((x) => x.title)));
check(mine.used.some((u) => u.offerId === loyal.id && u.amount === 1400 && u.itemTitle === 'كورتادو'), 'used list carries item and amount');
// انتهاء: عرض منتهٍ خلال 30 يوماً يظهر في المنتهية لمن لم يستخدمه
await pool.query("UPDATE biz_offers SET ends_at=now() - interval '1 hour' WHERE id=$1", [here.id]);
mine = await call('GET', '/offers/mine', { user: SARA, expect: 200 });
check(mine.expired.some((x) => x.id === here.id) && !mine.active.some((x) => x.id === here.id), 'ended offer moves to expired for a member who did not use it');
mine = await call('GET', '/offers/mine', { user: KHALID, expect: 200 });
check(!mine.expired.some((x) => x.id === here.id), 'used offers are not listed as expired');
list = await call('GET', `/biz/${B}/offers`, { user: null, expect: 200 });
check(list.past.some((x) => x.id === here.id) && !list.active.some((x) => x.id === here.id), 'circle page shows the ended offer under past');

// ---- الإدارة: الإحصاءات، التعديل، الإنهاء، التكرار، الحذف
let mg = await call('GET', `/biz/${B}/manage/offers`, { expect: 200 });
const dealRow = mg.offers.find((x) => x.id === deal.id);
check(mg.members === 2 && mg.templates.length === 6 && dealRow.stats.uses === 2 && dealRow.stats.discount === 1200 && dealRow.stats.revenue === 2000 + 1000 && dealRow.stats.views >= 1, 'owner stats: uses, discount, revenue, views', JSON.stringify(dealRow.stats));
const firstRow = mg.offers.find((x) => x.id === first.id);
check(firstRow.stats.sent === 1 && firstRow.stats.uses === 0, 'transfer counted separately from uses');
await call('GET', `/biz/${B}/manage/offers`, { user: SARA, expect: 403 });
let up = await call('PATCH', `/biz/${B}/manage/offers/${deal.id}`, { body: { title: 'كورتادو بـ 9', value: { type: 'price', amount: 900 } }, expect: 200 });
check(up.title === 'كورتادو بـ 9' && up.value.amount === 900, 'offer edited');
up = await call('PATCH', `/biz/${B}/manage/offers/${deal.id}`, { body: { endNow: true }, expect: 200 });
check(up.state === 'ended', 'end now');
d = await call('GET', `/biz/${B}`, { user: NORA, expect: 200 });
check(!d.items.find((i) => i.id === cortado.id).deal, 'ended deal no longer annotates the item');
const dup = await call('POST', `/biz/${B}/manage/offers/${deal.id}/duplicate`, { body: {}, expect: 200 });
check(dup.id !== deal.id && dup.title === 'كورتادو بـ 9' && dup.state === 'active' && dup.endsAt && dup.notified === 0, 'duplicate creates a fresh active copy; daily notification cap holds', JSON.stringify([dup.state, dup.notified]));
let del = await call('DELETE', `/biz/${B}/manage/offers/${deal.id}`, { expect: 200 });
check(del.archived === true, 'used offer is archived, not deleted');
del = await call('DELETE', `/biz/${B}/manage/offers/${dup.id}`, { expect: 200 });
check(del.archived === false, 'unused offer deleted');
await call('DELETE', `/biz/${B}/manage/offers/${dup.id}`, { expect: 404 });
// تحديث (منشور) يُشعر الأعضاء على "all" بسقف يومي
await pool.query("UPDATE biz_member_prefs SET last_notified_at=NULL WHERE biz_id=$1", [B]);
await call('POST', `/biz/${B}/posts`, { body: { kind: 'update', title: 'منيو جديد', body: 'أضفنا الكولد برو' }, expect: 200 });
check((await notes('biz_update', SARA)).length === 1 && (await notes('biz_update', KHALID)).length === 0, 'update post notifies members on all only');
await call('POST', `/biz/${B}/posts`, { body: { kind: 'update', title: 'ثانٍ', body: 'x' }, expect: 200 });
check((await notes('biz_update', SARA)).length === 1, 'daily cap: second update the same day is silent');
await app.close(); await pool.end();
console.log(fails ? `\n${fails} FAILED` : '\nALL OFFERS TESTS PASSED');
process.exit(fails ? 1 : 0);
