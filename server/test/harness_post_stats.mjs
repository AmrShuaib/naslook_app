// إحصاءات منشورات الخريطة (server/map_posts.js): تسجيل الأحداث (مشاهدة، إجراء، مراسلة، إعجاب) واستبعاد المالك،
// إحصاءات المنشور والمنشورات كلها ومنشورات الدائرة التجارية مع سلاسل الساعات والأيام والصلاحيات.
import Fastify from 'fastify';
import pg from 'pg';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0';
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("INSERT INTO users(id,nickname) VALUES('SA0000001','amr'),('SA0000002','sara'),('SA0000003','khalid'),('SA0000004','nora') ON CONFLICT DO NOTHING");
for (const sql of ['DELETE FROM map_posts', 'DROP TABLE IF EXISTS map_post_events', "INSERT INTO admins(user_id,granted_by) VALUES('SA0000004','test') ON CONFLICT DO NOTHING", "UPDATE biz SET owner_id='SA0000003' WHERE id='biz-ikea'"]) { try { await pool.query(sql); } catch { /* أول تشغيل */ } }
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
const dir = new URL('.', import.meta.url).pathname;
app.register((await import('../notify.js')).default, { pool, auth, pollMs: 3600000, opsDir: dir + 'ops' });
app.register((await import('../business.js')).default, { pool, auth });
app.register((await import('../map_posts.js')).default, { pool, auth });
app.register((await import('../admin.js')).default, { pool, auth, webappDir: dir + 'webapp', opsDir: dir + 'ops' });
await app.ready(); await new Promise((r) => setTimeout(r, 400));
await pool.query("UPDATE biz SET owner_id='SA0000003' WHERE id='biz-ikea'");
let fails = 0;
const check = (cond, label, extra = '') => { if (!cond) fails++; console.log((cond ? 'OK  ' : 'FAIL') + ' ' + label + (extra ? ' ' + extra : '')); };
const call = async (method, url, { body = {}, user = 'SA0000001', expect } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json', host: 'naslife.app' }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url} -> ${r.statusCode}`, r.statusCode === expect ? '' : JSON.stringify(j).slice(0, 160));
  return j;
};
const p1 = await call('POST', '/mapposts', { body: { kind: 'text', bg: '#000', caption: 'عرض إيكيا', title: 'خصم', tag: 'offer', cta: { type: 'biz', value: 'biz-ikea' }, lat: 21.5, lng: 39.2 }, expect: 200 });
const p2 = await call('POST', '/mapposts', { body: { kind: 'text', bg: '#000', caption: 'لحظة', lat: 21.5, lng: 39.2 }, expect: 200 });
// أحداث: المالك لا يُحتسب
await call('POST', `/mapposts/${p1.id}/view`, { expect: 200 });
await call('POST', `/mapposts/${p1.id}/cta`, { expect: 200 });
await call('POST', `/mapposts/${p1.id}/view`, { user: 'SA0000002', expect: 200 });
await call('POST', `/mapposts/${p1.id}/view`, { user: 'SA0000002', expect: 200 });
await call('POST', `/mapposts/${p1.id}/view`, { user: 'SA0000003', expect: 200 });
await call('POST', `/mapposts/${p1.id}/cta`, { user: 'SA0000002', expect: 200 });
await call('POST', `/mapposts/${p1.id}/contact`, { user: 'SA0000003', expect: 200 });
await call('POST', `/mapposts/${p1.id}/like`, { user: 'SA0000002', expect: 200 });
await call('POST', `/mapposts/${p1.id}/like`, { user: 'SA0000002', expect: 200 }); // إلغاء الإعجاب لا يسجَّل
await call('POST', `/mapposts/${p2.id}/view`, { user: 'SA0000002', expect: 200 });
await call('POST', `/mapposts/${p1.id}/cta`, { user: null, expect: 401 });
await call('POST', `/mapposts/aaaaaaaa-0000-4000-8000-000000000000/cta`, { user: 'SA0000002', expect: 404 });
let st = await call('GET', `/mapposts/${p1.id}/stats`, { expect: 200 });
check(st.totals.views === 3 && st.totals.cta === 1 && st.totals.contacts === 1 && st.totals.likes === 1 && st.uniqueViews === 2, 'per-post totals (impressions 3, unique 2, owner excluded, unlike not logged)', JSON.stringify(st.totals) + ' uniq ' + st.uniqueViews);
check(st.hourly.length === 24 && st.hourly[23].views === 3 && st.hourly[23].cta === 1, 'hourly series: last slot holds the events', JSON.stringify(st.hourly[23]));
check(st.daily.length === 7 && st.daily[6].views === 3 && st.daily[6].contacts === 1, 'daily series: today holds the events', JSON.stringify(st.daily[6]));
check(st.post.title === 'خصم' && st.viewsTotal === 2 && st.likesTotal === 0, 'post brief + counters', JSON.stringify(st.post));
await call('GET', `/mapposts/${p1.id}/stats`, { user: 'SA0000002', expect: 403 });
await call('GET', `/mapposts/${p1.id}/stats`, { user: 'SA0000004', expect: 200 });
st = await call('GET', '/mapposts/stats/mine?days=30', { expect: 200 });
check(st.posts === 2 && st.totals.views === 4 && st.daily.length === 30 && st.byPost.length === 2 && st.byPost.find((x) => x.id === p2.id).views === 1, 'my posts summary aggregates both posts', JSON.stringify(st.totals));
check((await call('GET', '/mapposts/stats/mine', { user: 'SA0000002', expect: 200 })).posts === 0, 'other user has no posts');
await call('GET', '/mapposts/stats/biz/biz-ikea', { user: 'SA0000002', expect: 403 });
st = await call('GET', '/mapposts/stats/biz/biz-ikea', { user: 'SA0000003', expect: 200 });
check(st.posts === 1 && st.totals.cta === 1 && st.byPost[0].id === p1.id && st.byPost[0].author === 'SA0000001', 'business owner sees posts promoting the business', JSON.stringify(st.totals));
check((await call('GET', '/mapposts/stats/biz/biz-ikea', { user: 'SA0000004', expect: 200 })).posts === 1, 'admin allowed');
await call('GET', '/mapposts/stats/biz/nope', { user: 'SA0000003', expect: 403 });
await pool.query('DELETE FROM map_posts'); await pool.query('DELETE FROM map_post_events');
await app.close(); await pool.end();
console.log(fails ? `\n${fails} FAILED` : '\nALL POST STATS TESTS PASSED');
process.exit(fails ? 1 : 0);
