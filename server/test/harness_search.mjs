// اختبارات البحث والاكتشاف على Postgres المحلي: تحليل ساعات العمل، التطبيع العربي، الأشخاص/الدوائر/الأنشطة/العناصر/السوق/الفعاليات،
// المسافة والترتيب، فلاتر /biz (مفتوح الآن، الأقرب، التقييم)، والاكتشاف.
import Fastify from 'fastify';
import pg from 'pg';
import { parseHours, isOpenNow, normQ } from '../business.js';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0';
let fails = 0;
const check = (cond, label, extra = '') => { if (!cond) fails++; console.log((cond ? 'OK  ' : 'FAIL') + ' ' + label + (extra ? ' ' + extra : '')); };

// ---- ساعات العمل (توقيت السعودية = UTC+3): الثلاثاء 2026-09-15، الجمعة 2026-09-18
const at = (iso) => new Date(iso);
check(isOpenNow('يومياً 10:00 ص – 12:00 م', at('2026-09-15T08:00:00Z')) === true, 'open 11:00 within 10am-midnight');
check(isOpenNow('يومياً 10:00 ص – 12:00 م', at('2026-09-15T20:30:00Z')) === true, 'open 23:30 before midnight close');
check(isOpenNow('يومياً 10:00 ص – 12:00 م', at('2026-09-15T05:00:00Z')) === false, 'closed 08:00 before opening');
check(isOpenNow('يومياً 1:00 م – 2:00 ص', at('2026-09-15T21:30:00Z')) === true, 'open 00:30 via yesterday window (1pm-2am)');
check(isOpenNow('يومياً 1:00 م – 2:00 ص', at('2026-09-15T00:00:00Z')) === false, 'closed 03:00 after 2am');
check(isOpenNow('يومياً 12:00 م – 2:00 ص', at('2026-09-15T09:30:00Z')) === true, 'noon opening parsed as 12:00');
check(isOpenNow('السبت – الخميس 8:00 ص – 10:00 م', at('2026-09-18T09:00:00Z')) === false, 'closed on Friday');
check(isOpenNow('السبت – الخميس 8:00 ص – 10:00 م', at('2026-09-15T09:00:00Z')) === true, 'open Tuesday sat-thu');
check(isOpenNow('الاستقبال 24 ساعة') === true && isOpenNow('24 ساعة') === true, 'always open');
check(isOpenNow('حسب الموسم') === null && isOpenNow('') === null, 'unknown → null');
const ph = parseHours('يومياً 8:00 ص – 1:30 ص'); check(ph.open === 480 && ph.close === 1530, 'parse 8am-1:30am', JSON.stringify(ph));
check(normQ('إِيكْيَا') === 'ايكيا' && normQ('قهوة') === 'قهوه' && normQ('مصطفى') === 'مصطفي' && normQ('BILLY') === 'billy', 'normQ');

const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("INSERT INTO users(id,nickname) VALUES('SA0000001','amr'),('SA0000002','sara'),('SA0000003','khalid'),('SA0000004','سارة الجدة') ON CONFLICT (id) DO UPDATE SET nickname=EXCLUDED.nickname");
await pool.query("CREATE TABLE IF NOT EXISTS vessels (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), name TEXT, topic TEXT, kind TEXT DEFAULT 'general', is_public BOOLEAN DEFAULT true, owner_id TEXT, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("CREATE TABLE IF NOT EXISTS vessel_members (vessel_id UUID, user_id TEXT, PRIMARY KEY (vessel_id, user_id))");
await pool.query('DELETE FROM vessel_members'); await pool.query('DELETE FROM vessels');
const v1 = (await pool.query("INSERT INTO vessels(name,topic,owner_id) VALUES('دائرة جدة','عام','SA0000001') RETURNING id")).rows[0].id;
const v2 = (await pool.query("INSERT INTO vessels(name,topic,is_public,owner_id) VALUES('دائرة جدة السرية','خاص',false,'SA0000002') RETURNING id")).rows[0].id;
await pool.query('INSERT INTO vessel_members(vessel_id,user_id) VALUES($1,$2),($1,$3),($4,$3)', [v1, 'SA0000001', 'SA0000002', v2]);
for (const sql of ['DELETE FROM market_orders', 'DELETE FROM market_listings', 'DELETE FROM tickets', 'DELETE FROM events', 'UPDATE biz SET owner_id=NULL', 'DELETE FROM biz_reviews']) { try { await pool.query(sql); } catch { /* أول تشغيل */ } }

const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
app.register((await import('../commerce.js')).default, { pool, auth });
app.register((await import('../business.js')).default, { pool, auth });
app.register((await import('../search.js')).default, { pool, auth });
await app.ready(); await new Promise((r) => setTimeout(r, 500));
await pool.query("INSERT INTO biz_reviews(biz_id,user_id,rating,text) VALUES('biz-ikea','SA0000002',5,'ممتاز'),('biz-vox','SA0000002',3,'عادي'),('biz-vox','SA0000003',4,'جيد') ON CONFLICT DO NOTHING");
await pool.query("INSERT INTO wallet_accounts(user_id,balance) VALUES('SA0000003',5000000) ON CONFLICT (user_id) DO UPDATE SET balance=5000000");

const call = async (method, url, { body = {}, user = 'SA0000001', expect } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json' }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url} -> ${r.statusCode}`, r.statusCode === expect ? '' : JSON.stringify(j).slice(0, 200));
  return j;
};
const enc = encodeURIComponent;
const st = await call('GET', '/search/status', { user: null, expect: 200 }); check(st.users && st.vessels && st.membersTable === 'vessel_members' && st.biz && st.market && st.events, 'discovery', JSON.stringify(st));

// ---- التطبيع العربي والأنواع
let r = await call('GET', `/search?q=${enc('ايكيا')}`, { user: null, expect: 200 });
check(r.biz.some((b) => b.id === 'biz-ikea'), 'ايكيا finds إيكيا (hamza normalization)', r.biz.map((b) => b.id).join(','));
r = await call('GET', `/search?q=${enc('BILLY')}`, { user: null, expect: 200 });
check(r.items.some((i) => i.bizId === 'biz-ikea' && /BILLY/.test(i.title)) && r.biz.find((b) => b.id === 'biz-ikea')?.matchedItem, 'item search + matchedItem', JSON.stringify(r.items[0]));
r = await call('GET', `/search?q=sar`, { user: null, expect: 200 });
check(r.people.some((p) => p.nickname === 'sara') && r.people.length <= 6, 'people prefix search', r.people.map((p) => p.nickname).join(','));
r = await call('GET', `/search?q=${enc('ساره')}`, { user: null, expect: 200 });
check(r.people.some((p) => p.nickname === 'سارة الجدة'), 'taa marbuta normalization in people');
r = await call('GET', `/search?q=${enc('جده')}`, { user: 'SA0000003', expect: 200 });
check(r.vessels.length === 1 && r.vessels[0].name === 'دائرة جدة' && r.vessels[0].members === 2, 'public vessel only for non-member', JSON.stringify(r.vessels));
r = await call('GET', `/search?q=${enc('جده')}`, { user: 'SA0000002', expect: 200 });
check(r.vessels.length === 2 && r.vessels.some((v) => v.id === v2 && v.member), 'private vessel visible to member with member flag');
r = await call('GET', `/search?q=${enc('جده')}`, { user: null, expect: 200 });
check(r.vessels.length === 1, 'anonymous sees public only');
// السوق والفعاليات
const lst = await call('POST', '/market', { body: { kind: 'product', category: 'coffee', title: 'قهوة مختصة', description: 'حبوب إثيوبية', price: 4500, placeName: 'جدة', lat: 21.6, lng: 39.2 }, user: 'SA0000002', expect: 200 });
r = await call('GET', `/search?q=${enc('قهوه')}&lat=21.54&lng=39.17`, { user: 'SA0000003', expect: 200 });
check(r.market.some((l) => l.id === lst.id && l.seller.nickname === 'sara' && l.distanceKm > 0), 'market search with seller + distance', JSON.stringify(r.market[0]?.distanceKm));
const ev = await call('POST', '/events', { body: { title: 'لقاء المطورين', description: 'Flutter', startsAt: new Date(Date.now() + 86400000).toISOString(), placeName: 'الكورنيش', lat: 21.5, lng: 39.15, tiers: [{ name: 'عادي', price: 2000, quantity: 10 }] }, user: 'SA0000002', expect: 200 });
r = await call('GET', `/search?q=${enc('المطورين')}`, { user: 'SA0000002', expect: 200 });
check(r.events.some((e) => e.id === ev.id && e.host.nickname === 'sara' && e.tiers[0]?.price === 2000 && e.isHost), 'event search with host + tiers', JSON.stringify(r.events[0]?.tiers));
r = await call('GET', `/search?q=${enc('سينما')}&lat=21.54&lng=39.17&type=biz&limit=50`, { user: null, expect: 200 });
const d = r.biz.map((b) => b.distanceKm);
check(r.biz.length >= 3 && r.people.length === 0 && r.items.length === 0 && d.every((x) => x != null) && d.every((x, i) => i === 0 || x >= d[i - 1]), 'type=biz cinemas sorted by distance', d.join(','));
r = await call('GET', '/search?q=', { user: null, expect: 200 }); check(r.biz.length === 0 && r.people.length === 0, 'empty q → empty');
r = await call('GET', `/search?q=${enc('%')}`, { user: null, expect: 200 }); check(r.biz.length === 0, 'wildcard escaped');

// ---- فلاتر /biz
r = await call('GET', '/biz?open=1', { user: null, expect: 200 }); check(r.length > 0 && r.every((b) => b.openNow === true), 'open=1 only open', `${r.length} open`);
const all = await call('GET', '/biz', { user: null, expect: 200 }); check(all.some((b) => b.openNow === true) && all.every((b) => 'openNow' in b) && all[0].distanceKm === null, 'openNow present, distance null without geo', `${all.filter((b) => b.openNow).length}/${all.length} open`);
r = await call('GET', '/biz?sort=near&lat=21.54&lng=39.17', { user: null, expect: 200 });
const dd = r.map((b) => b.distanceKm); check(dd.every((x) => x != null) && dd.every((x, i) => i === 0 || x >= dd[i - 1]), 'sort=near ascending', dd.slice(0, 5).join(','));
r = await call('GET', '/biz?sort=rating', { user: null, expect: 200 }); check(r[0].id === 'biz-ikea' && r[1].id === 'biz-vox', 'sort=rating', r.slice(0, 3).map((b) => b.id + ':' + b.rating).join(','));
r = await call('GET', '/biz?minRating=4', { user: null, expect: 200 }); check(r.length === 1 && r[0].id === 'biz-ikea', 'minRating=4', r.map((b) => b.id).join(','));
r = await call('GET', `/biz?q=${enc('بيلي')}`, { user: null, expect: 200 }); check(r.length === 0, 'arabic transliteration not matched (expected)');
r = await call('GET', `/biz?q=${enc('billy')}`, { user: null, expect: 200 }); check(r.length === 1 && r[0].id === 'biz-ikea', 'q matches item title');
r = await call('GET', `/biz?category=hotel&sort=popular`, { user: null, expect: 200 }); check(r.length === 5 && r.every((b) => b.category === 'hotel'), 'category + popular');

// ---- الاكتشاف
r = await call('GET', '/search/discover?lat=21.54&lng=39.17', { user: null, expect: 200 });
check(r.located && r.openNow.every((b) => b.openNow === true) && r.openNow.length <= 8 && r.topRated[0]?.id === 'biz-ikea' && r.events.some((e) => e.id === ev.id) && r.vessels.some((v) => v.name === 'دائرة جدة') && !r.vessels.some((v) => v.id === v2), 'discover sections', `open=${r.openNow.length} top=${r.topRated.map((b) => b.id).join(',')} ev=${r.events.length} v=${r.vessels.length}`);
const od = r.openNow.map((b) => b.distanceKm); check(od.every((x, i) => i === 0 || x >= od[i - 1]), 'openNow nearest first', od.join(','));
r = await call('GET', '/search/discover', { user: null, expect: 200 }); check(!r.located && r.openNow[0]?.distanceKm === null, 'discover without location');

console.log(fails ? `\n${fails} FAILURES` : '\nALL SEARCH TESTS PASSED');
await app.close(); await pool.end(); process.exit(fails ? 1 : 0);
