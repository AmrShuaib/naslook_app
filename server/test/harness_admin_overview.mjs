// نظرة عامة الإدارة (server/admin.js): عدّادات توثيق الدوائر ومستويات اكتمالها circles.pendingVerifications وcircles.tiers
// {published, complete, verified, active}. تُحسب عند الطلب بفحص information_schema: قبل وصول عمود biz.verification (يضيفه
// biz_onboard.js) تعود أصفاراً دون خطأ، وبعده تعدّ المعلّقة وتصنّف الدوائر تقريبياً بالساعات والوصف والعناصر وحالة التوثيق.
// التشغيل: NASLIFE_TEST_DB=naslife_test_regmap server/test/run.sh harness_admin_overview.mjs
import Fastify from 'fastify';
import pg from 'pg';
process.env.NASLIFE_HEALTH_BRIDGE = '0'; process.env.NODE_ENV = 'test';
let fails = 0;
const check = (cond, label, extra = '') => { if (!cond) fails++; console.log((cond ? 'OK  ' : 'FAIL') + ' ' + label + (extra ? ' ' + extra : '')); };
const ADMIN = 'SA0000431', OWNER = 'SA0000432';
const OURS = ['ov-pending', 'ov-approved', 'ov-bare'];
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query(`INSERT INTO users(id,nickname) VALUES('${ADMIN}','ovadmin'),('${OWNER}','ovowner') ON CONFLICT (id) DO UPDATE SET nickname=EXCLUDED.nickname`);
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
const dir = new URL('.', import.meta.url).pathname;
app.register((await import('../commerce.js')).default, { pool, auth });
app.register((await import('../business.js')).default, { pool, auth });
app.register((await import('../admin.js')).default, { pool, auth, webappDir: dir + 'webapp', opsDir: dir + 'ops' });
await app.ready(); await new Promise((r) => setTimeout(r, 300));
await pool.query("INSERT INTO admins(user_id,granted_by) VALUES($1,'test') ON CONFLICT DO NOTHING", [ADMIN]);
await pool.query('DELETE FROM biz WHERE id = ANY($1)', [OURS]);
const call = async (method, url, { body = {}, user = null, expect } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json' }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url}${user ? '' : ' (guest)'} -> ${r.statusCode}`, r.statusCode === expect ? '' : JSON.stringify(j).slice(0, 200));
  return { status: r.statusCode, body: j };
};
const isInt = (v) => Number.isInteger(v) && v >= 0;
const tiersOk = (c) => !!c && isInt(c.pendingVerifications) && !!c.tiers && ['published', 'complete', 'verified', 'active'].every((k) => isInt(c.tiers[k]));
const hasCol = async () => (await pool.query("SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='biz' AND column_name='verification'")).rowCount > 0;

// ---- الحارس: المديرون فقط
await call('GET', '/adminapi/overview', { expect: 401 });
const notAdmin = await call('GET', '/adminapi/overview', { user: OWNER });
check(notAdmin.status === 401 || notAdmin.status === 403, 'non-admin cannot read the overview', String(notAdmin.status));

// ---- 1) بلا عمود verification (قبل biz_onboard.js): الحقول موجودة بأصفار ولا خطأ
const had = await hasCol();
if (!had) {
  const { body: o } = await call('GET', '/adminapi/overview', { user: ADMIN, expect: 200 });
  check(tiersOk(o.circles), 'without biz.verification: pendingVerifications and tiers are present', JSON.stringify(o.circles));
  check(o.circles.pendingVerifications === 0 && Object.values(o.circles.tiers).every((n) => n === 0), 'without biz.verification: all zeros', JSON.stringify(o.circles));
  await pool.query("ALTER TABLE biz ADD COLUMN IF NOT EXISTS verification JSONB NOT NULL DEFAULT '{}'");
} else {
  console.log('note: biz.verification already present (biz_onboard.js loaded in this DB); the zero branch is skipped');
}

// ---- 2) بالعمود: معلّقة ومكتملة وموثّقة (المستويات تقريبية: ساعات + وصف ≥ 20 حرفاً + 3 عناصر نشطة، ثم حالة التوثيق)
const ins = async (id, status, { verified = false, hours = 'يومياً 9 ص – 11 م', description = 'وصف طويل بما يكفي ليُعدّ مكتملاً في قائمة الاكتمال', items = 3 } = {}) => {
  await pool.query("INSERT INTO biz(id, name, name_ar, category, description, lat, lng, hours, active, owner_id, verified, verification) VALUES ($1,$2,$2,'cafe',$3,21.5,39.17,$4,true,$5,$6,$7::jsonb)",
    [id, 'OV ' + id, description, hours, OWNER, verified, JSON.stringify({ status })]);
  for (let i = 0; i < items; i++) await pool.query("INSERT INTO biz_items(id, biz_id, kind, title, price, active) VALUES ($1,$2,'product',$3,1000,true)", [`${id}-item-${i}`, id, 'عنصر ' + i]);
};
await ins('ov-pending', 'pending');
await ins('ov-approved', 'approved', { verified: true });
await ins('ov-bare', 'none', { hours: '', description: 'قصير', items: 0 });
await pool.query("INSERT INTO biz_posts(id, biz_id, title) VALUES (gen_random_uuid(), 'ov-approved', 'منشور حديث')");
const { body: o1 } = await call('GET', '/adminapi/overview', { user: ADMIN, expect: 200 });
const c = o1.circles;
check(tiersOk(c), 'with biz.verification: fields present', JSON.stringify(c));
check(c.pendingVerifications >= 1, 'pending count includes the pending circle', String(c.pendingVerifications));
check(c.tiers.published >= 3, 'published counts every active circle (ours included)', JSON.stringify(c.tiers));
check(c.tiers.complete >= 2 && c.tiers.complete < c.tiers.published, 'complete needs hours, description and 3 items, so the bare circle is excluded', JSON.stringify(c.tiers));
check(c.tiers.verified >= 1 && c.tiers.verified <= c.tiers.complete, 'verified is a subset of complete', JSON.stringify(c.tiers));
check(c.tiers.active <= c.tiers.verified, 'active is a subset of verified', JSON.stringify(c.tiers));
// اعتماد المعلّقة (مكتملة أصلاً) ينقلها من المعلّقة إلى الموثّقة
await pool.query(`UPDATE biz SET verification='{"status":"approved"}'::jsonb, verified=true WHERE id='ov-pending'`);
const { body: o2 } = await call('GET', '/adminapi/overview', { user: ADMIN, expect: 200 });
check(o2.circles.pendingVerifications === c.pendingVerifications - 1 && o2.circles.tiers.verified === c.tiers.verified + 1, 'approving moves one circle from pending to verified', JSON.stringify(o2.circles));
// إخفاء الدائرة (إن وُجد العمود) يُخرجها من «منشورة»
const hiddenCol = (await pool.query("SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='biz' AND column_name='hidden'")).rowCount > 0;
if (hiddenCol) {
  await pool.query("UPDATE biz SET hidden=true WHERE id='ov-bare'");
  const { body: o3 } = await call('GET', '/adminapi/overview', { user: ADMIN, expect: 200 });
  check(o3.circles.tiers.published === o2.circles.tiers.published - 1, 'a hidden circle is not published', JSON.stringify(o3.circles.tiers));
}

// ---- تنظيف
await pool.query('DELETE FROM biz WHERE id = ANY($1)', [OURS]);
if (!had) await pool.query('ALTER TABLE biz DROP COLUMN IF EXISTS verification');
await app.close(); await pool.end();
console.log(fails ? `${fails} FAILED` : 'ALL OK');
process.exit(fails ? 1 : 0);
