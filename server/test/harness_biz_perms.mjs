// صلاحيات الدائرة لكل عضو (docs/circle-permissions.md): القوالب تطابق سلوك الأدوار قبل المفاتيح، كل صلاحية على مساراتها
// (مسموح ومرفوض) للمالك والمدير والموظف وعضو التوظيف وموظف بمفتاح زائد ومدير بمفتاح مطفأ ومدير النظام والغريب، حدود إدارة الفريق،
// مستلمو الإشعارات، حجب أرقام الإيراد، وسجل النشاط. تشغّل الإضافات الحقيقية: business، offers، biz_inbox، jobs، biz_onboard، biz_community.
import Fastify from 'fastify';
import pg from 'pg';
import crypto from 'node:crypto';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0'; process.env.NODE_ENV = 'test';
let fails = 0;
const check = (cond, label, extra = '') => { if (!cond) fails++; console.log((cond ? 'OK  ' : 'FAIL') + ' ' + label + (extra ? ' ' + extra : '')); };
const U = (n) => 'SP' + String(n).padStart(7, '0');
const O = U(1), M = U(2), S = U(3), H = U(4), SX = U(5), MX = U(6), A = U(7), C = U(8), X = U(9), N1 = U(10), N2 = U(11), N3 = U(12), O2 = U(13), M2 = U(14);
const NAMES = { [O]: 'owner', [M]: 'manager', [S]: 'staff', [H]: 'hr', [SX]: 'staffplus', [MX]: 'managerminus', [A]: 'sysadmin', [C]: 'cust', [X]: 'stranger', [N1]: 'new1', [N2]: 'new2', [N3]: 'new3', [O2]: 'owner2', [M2]: 'manager2' };
const FILL = Array.from({ length: 50 }, (_, i) => U(100 + i));
const OURS = [...Object.keys(NAMES), ...FILL];
const BIZ = 'bp-shop';

const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("ALTER TABLE users ADD COLUMN IF NOT EXISTS is_admin BOOLEAN DEFAULT false");
await pool.query(`INSERT INTO users(id,nickname,is_admin) VALUES ${OURS.map((u) => `('${u}','${NAMES[u] ?? 'fill' + u.slice(-3)}',${u === A})`).join(',')} ON CONFLICT (id) DO UPDATE SET nickname=EXCLUDED.nickname, is_admin=EXCLUDED.is_admin`);
await pool.query("CREATE TABLE IF NOT EXISTS user_blocks (user_id TEXT NOT NULL, blocked_id TEXT NOT NULL, created_at TIMESTAMPTZ DEFAULT now(), PRIMARY KEY (user_id, blocked_id))");
await pool.query("CREATE TABLE IF NOT EXISTS user_flags (user_id TEXT PRIMARY KEY, suspended BOOLEAN NOT NULL DEFAULT false, note TEXT NOT NULL DEFAULT '', updated_at TIMESTAMPTZ NOT NULL DEFAULT now())");
// بقايا تشغيل سابق: نحذف ما يخصّنا فقط (القاعدة قد تكون مشتركة مع حزم أخرى)
for (const sql of ["DELETE FROM biz_activity WHERE biz_id LIKE 'bp-%'", "DELETE FROM biz_threads WHERE biz_id LIKE 'bp-%'", "DELETE FROM biz_disputes WHERE biz_id LIKE 'bp-%'", "DELETE FROM biz_orders WHERE biz_id LIKE 'bp-%'",
  "DELETE FROM biz_offers WHERE biz_id LIKE 'bp-%'", "DELETE FROM biz_reviews WHERE biz_id LIKE 'bp-%'", "DELETE FROM biz_posts WHERE biz_id LIKE 'bp-%'", "DELETE FROM biz_community_posts WHERE biz_id LIKE 'bp-%'",
  "DELETE FROM job_matches WHERE biz_id LIKE 'bp-%'", "DELETE FROM jobs WHERE biz_id LIKE 'bp-%'", "DELETE FROM biz_items WHERE biz_id LIKE 'bp-%'", "DELETE FROM biz_staff WHERE biz_id LIKE 'bp-%'", "DELETE FROM biz WHERE id LIKE 'bp-%' OR id LIKE 'biz-bp-%'"]) { try { await pool.query(sql); } catch { /* أول تشغيل */ } }

const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
app.register((await import('../commerce.js')).default, { pool, auth });
app.register((await import('../business.js')).default, { pool, auth });
app.register((await import('../offers.js')).default, { pool, auth });
app.register((await import('../biz_onboard.js')).default, { pool, auth });
app.register((await import('../biz_inbox.js')).default, { pool, auth });
app.register((await import('../biz_community.js')).default, { pool, auth });
app.register((await import('../jobs.js')).default, { pool, auth, sweepMs: 0 });
await app.ready(); await new Promise((r) => setTimeout(r, 400));
const sent = [];
globalThis.naslifeNotify = async (to, payload) => { sent.push({ ids: [].concat(to).filter((x) => x !== payload.exclude), ...payload }); };
globalThis.naslifeNotifyAdmins = async (payload) => { sent.push({ ids: ['admins'], ...payload }); };
globalThis.naslifeIsAdmin = async (u) => u === A;
globalThis.naslifeSettings = { ...(globalThis.naslifeSettings ?? {}), jobsEnabled: true };
const take = (kind) => { const out = sent.filter((n) => !kind || n.kind === kind); sent.length = 0; return out; };
const same = (a, b) => JSON.stringify([...a].sort()) === JSON.stringify([...b].sort());

const req = async (method, url, { body = {}, user = O } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json' }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  return { status: r.statusCode, j };
};
const call = async (method, url, { body = {}, user = O, expect } = {}) => {
  const r = await req(method, url, { body, user });
  if (expect != null) check(r.status === expect, `${method} ${url} [${NAMES[user] ?? user}] -> ${r.status}`, r.status === expect ? '' : JSON.stringify(r.j).slice(0, 240));
  return r.j;
};

// ---- التجهيز: دائرة ثابتة موثّقة، وفريق بالأدوار الثلاثة كما كانت الصفوف قبل المفاتيح (perms = NULL)
await pool.query("INSERT INTO biz(id,name,name_ar,category,lat,lng,owner_id,verified,active,logo_url,hours,description) VALUES($1,'Perms Shop','متجر الصلاحيات','shop',21.55,39.17,$2,true,true,'/chat/media/logo-bp.png','يومياً 9:00 ص – 11:00 م','وصف طويل كفاية لاكتمال الدائرة هنا')", [BIZ, O]);
await pool.query("INSERT INTO biz(id,name,name_ar,category,lat,lng,owner_id,verified,active) VALUES('bp-other','Other','أخرى','shop',21.5,39.1,$1,true,true)", [O2]);
await pool.query("INSERT INTO biz_staff(biz_id,user_id,role) VALUES($1,$2,'manager'),($1,$3,'staff'),($1,$4,'hr'),($1,$5,'staff'),($1,$6,'manager')", [BIZ, M, S, H, SX, MX]);
await pool.query("INSERT INTO biz_staff(biz_id,user_id,role) VALUES('bp-other',$1,'manager')", [M2]);
await pool.query("INSERT INTO biz_items(id,biz_id,kind,title,price,stock) VALUES('bp-shop-free','bp-shop','product','عيّنة',0,100),('bp-shop-oil','bp-shop','product','زيت',5000,100)");
const ALL = ['orders', 'orders_cancel', 'catalog', 'offers', 'posts', 'inbox', 'reviews', 'hiring', 'stats', 'profile', 'team'];
const P = globalThis.naslifeBizPerms;
check(!!P && same(P.PERMS, ALL), 'the shared helper is exposed on globalThis with the eleven switches', JSON.stringify(P?.PERMS));

console.log('\n--- presets reproduce the old roles (no stored switches yet)');
const PRESET = { [O]: ALL, [M]: ALL, [S]: ['orders', 'inbox', 'stats'], [H]: ['hiring'], [SX]: ['orders', 'inbox', 'stats'], [MX]: ALL, [A]: ALL.filter((p) => p !== 'inbox'), [X]: [], [C]: [] };
check((await pool.query("SELECT count(*)::int AS n FROM biz_staff WHERE biz_id=$1 AND perms IS NOT NULL", [BIZ])).rows[0].n === 0, 'existing rows keep perms = NULL (no migration rewrites them)');
for (const u of [O, M, S, H, A, X]) {
  const b = await call('GET', `/biz/${BIZ}`, { user: u, expect: 200 });
  const want = PRESET[u];
  check(same(b.myPerms ?? [], want) && (want.length ? Array.isArray(b.myPerms) : b.myPerms == null || u === X), `GET /biz/:id myPerms for ${NAMES[u]} = preset`, JSON.stringify(b.myPerms));
}
check((await call('GET', `/biz/${BIZ}`, { user: M, expect: 200 })).myRole === 'manager', 'myRole is still sent for old app builds');
{
  const mine = await call('GET', '/biz/mine', { user: S, expect: 200 });
  const row = mine.circles.find((c) => c.id === BIZ);
  check(row && row.myRole === 'staff' && same(row.myPerms, PRESET[S]), '/biz/mine carries myRole and myPerms', JSON.stringify(row?.myPerms));
  const am = await call('GET', '/biz/mine', { user: A, expect: 200 });
  const ar = am.circles.find((c) => c.id === BIZ);
  check(ar && ar.myRole === 'admin' && same(ar.myPerms, PRESET[A]) && !ar.myPerms.includes('inbox'), '/biz/mine for the platform admin: everything except the customer inbox');
}

// ---- مسبار لكل صلاحية: مسارات لا تغيّر الحالة (جسم ناقص أو معرّف غير موجود)؛ المسموح = أي رد غير 403، والمرفوض = 403
const RID = crypto.randomUUID();
const PROBES = {
  orders: [['GET', `/biz/${BIZ}/orders`], ['POST', `/biz/${BIZ}/checkin`, { code: 'NOPE-NOPE' }], ['POST', `/biz/${BIZ}/orders/${RID}/paid`], ['POST', `/biz/${BIZ}/orders/${RID}/no-show`]],
  orders_cancel: [['POST', `/biz/${BIZ}/orders/${RID}/cancel`]],
  catalog: [['POST', `/biz/${BIZ}/items`, { title: '' }], ['PATCH', `/biz/${BIZ}/items/nope-item`, {}], ['DELETE', `/biz/${BIZ}/items/nope-item`]],
  offers: [['GET', `/biz/${BIZ}/manage/offers`], ['POST', `/biz/${BIZ}/manage/offers`, {}], ['PATCH', `/biz/${BIZ}/manage/offers/${RID}`, {}], ['DELETE', `/biz/${BIZ}/manage/offers/${RID}`], ['POST', `/biz/${BIZ}/manage/offers/${RID}/duplicate`, {}]],
  posts: [['POST', `/biz/${BIZ}/posts`, { title: '' }], ['PATCH', `/biz/${BIZ}/posts/${RID}`, {}], ['DELETE', `/biz/${BIZ}/posts/${RID}`]],
  inbox: [['GET', `/biz/${BIZ}/inbox`], ['GET', `/biz/${BIZ}/inbox/unread`]],
  reviews: [['POST', `/biz/${BIZ}/reviews/${X}/reply`, { text: 'شكراً' }]],
  hiring: [['GET', `/biz/${BIZ}/manage/jobs`], ['GET', `/biz/${BIZ}/manage/jobs/stats`]],
  stats: [['GET', `/biz/${BIZ}/stats`]],
  profile: [['PATCH', `/biz/${BIZ}`, {}], ['GET', `/biz/${BIZ}/verification`], ['POST', `/biz/${BIZ}/verification`, {}]],
  team: [['GET', `/biz/${BIZ}/team`], ['GET', `/biz/${BIZ}/activity`], ['POST', `/biz/${BIZ}/team`, { userId: 'bad' }], ['DELETE', `/biz/${BIZ}/team/bad`]],
};
async function matrix(user, want, label) {
  const bad = [];
  for (const perm of ALL) {
    for (const [method, url, body] of PROBES[perm]) {
      const r = await req(method, url, { body: body ?? {}, user });
      const allowed = r.status !== 403 && r.status !== 401;
      if (allowed !== want.includes(perm)) bad.push(`${perm}:${method} ${url.replace(`/biz/${BIZ}`, '')}=${r.status}`);
    }
  }
  check(bad.length === 0, `${label}: every route follows the permission set [${want.join(',') || 'none'}]`, bad.join(' | '));
  // «هنا اليوم» لمن يحمل الطلبات أو بيانات الدائرة (409 not-mobile للدائرة الثابتة حين يُسمح)؛ والاكتمال لأي عضو له صلاحية غير التوظيف
  const here = (await req('POST', `/biz/${BIZ}/here`, { body: { lat: 21.5, lng: 39.1 }, user })).status;
  check((here !== 403) === (want.includes('orders') || want.includes('profile')), `${label}: «هنا اليوم» needs orders or profile -> ${here}`);
  const comp = (await req('GET', `/biz/${BIZ}/completeness`, { user })).status;
  check((comp === 200) === want.some((p) => p !== 'hiring'), `${label}: completeness for members with any non-hiring switch -> ${comp}`);
  const tr = (await req('POST', `/biz/${BIZ}/transfer`, { body: { userId: 'nope' }, user })).status;
  check((tr !== 403) === (user === O || user === A), `${label}: ownership transfer is owner-only -> ${tr}`);
}
for (const u of [O, M, S, H, SX, MX, A, X]) await matrix(u, PRESET[u], `${NAMES[u]} (preset)`);
await call('GET', `/biz/${BIZ}/team`, { user: null, expect: 401 });
await call('GET', `/biz/${BIZ}/activity`, { user: null, expect: 401 });

console.log('\n--- per-member switches');
// الموظف + «القائمة والأسعار»، والمدير − «المبيعات والإحصاءات»
let r = await call('PATCH', `/biz/${BIZ}/team/${SX}`, { body: { perms: { catalog: true } }, expect: 200 });
check(r.member.role === 'staff' && r.member.custom === true && same(r.member.perms, ['orders', 'inbox', 'stats', 'catalog']), 'owner switches catalog on for a staff member', JSON.stringify(r.member));
r = await call('PATCH', `/biz/${BIZ}/team/${MX}`, { body: { perms: { stats: false } }, expect: 200 });
check(r.member.role === 'manager' && r.member.custom === true && !r.member.perms.includes('stats') && r.member.perms.includes('team'), 'owner switches stats off for a manager');
check(JSON.stringify((await pool.query("SELECT perms FROM biz_staff WHERE biz_id=$1 AND user_id=$2", [BIZ, SX])).rows[0].perms) === '{"catalog":true}', 'only the difference from the preset is stored');
const NOW = { ...PRESET, [SX]: ['orders', 'inbox', 'stats', 'catalog'], [MX]: ALL.filter((p) => p !== 'stats') };
await matrix(SX, NOW[SX], 'staff + catalog');
await matrix(MX, NOW[MX], 'manager − stats');
await matrix(S, NOW[S], 'plain staff is untouched');
check(same((await call('GET', `/biz/${BIZ}`, { user: SX, expect: 200 })).myPerms, NOW[SX]), 'myPerms follows the switches');
// الرجوع إلى القالب يمسح المخزَّن
r = await call('PATCH', `/biz/${BIZ}/team/${SX}`, { body: { perms: { catalog: false } }, expect: 200 });
check(r.member.custom === false && (await pool.query("SELECT perms FROM biz_staff WHERE biz_id=$1 AND user_id=$2", [BIZ, SX])).rows[0].perms === null, 'back to the preset → perms NULL again');
await call('PATCH', `/biz/${BIZ}/team/${SX}`, { body: { perms: { catalog: true } }, expect: 200 });
check((await call('PATCH', `/biz/${BIZ}/team/${SX}`, { body: { perms: { nope: true } }, expect: 400 })).error === 'bad-perms', 'unknown switch refused');
check((await call('PATCH', `/biz/${BIZ}/team/${SX}`, { body: { perms: { catalog: 'yes' } }, expect: 400 })).error === 'bad-perms', 'non-boolean switch refused');
check((await call('PATCH', `/biz/${BIZ}/team/${SX}`, { body: { role: 'boss' }, expect: 400 })).error === 'bad-role', 'unknown role refused on PATCH');
check((await call('PATCH', `/biz/${BIZ}/team/${N3}`, { body: { perms: { catalog: true } }, expect: 404 })).error === 'not-member', 'PATCH on a non-member → 404');
// عضو التوظيف بمفتاح الرسائل يدخل الصندوق، ومدير النظام لا يدخله أبداً
await call('PATCH', `/biz/${BIZ}/team/${H}`, { body: { perms: { inbox: true } }, expect: 200 });
await call('GET', `/biz/${BIZ}/inbox`, { user: H, expect: 200 });
await call('PATCH', `/biz/${BIZ}/team/${H}`, { body: { perms: { inbox: false } }, expect: 200 });
await call('GET', `/biz/${BIZ}/inbox`, { user: H, expect: 403 });
await call('GET', `/biz/${BIZ}/inbox`, { user: A, expect: 403 });

console.log('\n--- team view');
let t = await call('GET', `/biz/${BIZ}/team`, { user: O, expect: 200 });
check(t.owner.id === O && t.staff.length === 5 && same(t.perms, ALL) && t.me.role === 'owner' && t.me.boss === true && t.limit === 50 && same(t.presets.staff, ['orders', 'inbox', 'stats']) && same(t.presets.hr, ['hiring']),
  'owner sees the team with the switch list, presets and own permissions');
check(t.staff.every((s) => s.editable === true && s.lock === null && Array.isArray(s.perms) && s.user?.id && s.role && s.since), 'every member is editable by the owner and keeps the old fields (user, role, since)');
t = await call('GET', `/biz/${BIZ}/team`, { user: M, expect: 200 });
const row = (id) => t.staff.find((s) => s.user.id === id);
check(t.me.role === 'manager' && t.me.boss === false && row(M).lock === 'self' && row(MX).lock === 'team-holder' && row(S).editable === true && row(H).editable === true,
  'a manager sees: self locked, another team holder locked, others editable', JSON.stringify(t.staff.map((s) => [s.user.nickname, s.lock])));

console.log('\n--- team-management limits');
const err = async (method, url, body, user, code, error, label) => { const j = await call(method, url, { body, user, expect: code }); check(j.error === error, label, JSON.stringify(j)); return j; };
// المدير يضيف موظفاً وعضو توظيف (يحمل صلاحياتهما) ويعدّل مفاتيح الموظف
r = await call('POST', `/biz/${BIZ}/team`, { user: M, body: { userId: N1, role: 'staff' }, expect: 200 });
check(r.ok === true && r.member.role === 'staff' && same(r.member.perms, ['orders', 'inbox', 'stats']), 'a manager adds a staff member');
await call('POST', `/biz/${BIZ}/team`, { user: M, body: { userId: N2, role: 'hr' }, expect: 200 });
r = await call('PATCH', `/biz/${BIZ}/team/${N1}`, { user: M, body: { perms: { reviews: true, stats: false } }, expect: 200 });
check(same(r.member.perms, ['orders', 'inbox', 'reviews']), 'a manager edits a member\'s switches');
// لا يمنح «إدارة الفريق» ولا دور المدير (قالبه يحملها) إلا المالك
await err('PATCH', `/biz/${BIZ}/team/${N1}`, { perms: { team: true } }, M, 403, 'owner-only', 'a manager cannot grant the team switch');
await err('POST', `/biz/${BIZ}/team`, { userId: N3, role: 'manager' }, M, 403, 'owner-only', 'a manager cannot add a manager (the preset carries team)');
await err('PATCH', `/biz/${BIZ}/team/${N1}`, { role: 'manager' }, M, 403, 'owner-only', 'a manager cannot promote to manager');
r = await call('POST', `/biz/${BIZ}/team`, { user: M, body: { userId: N3, role: 'manager', perms: { team: false } }, expect: 200 });
check(r.member.role === 'manager' && !r.member.perms.includes('team'), 'a manager may add a manager with the team switch off (holds every other switch)');
// لا يمس غيرُ المالك عضواً يحمل «إدارة الفريق»
await err('PATCH', `/biz/${BIZ}/team/${MX}`, { perms: { catalog: false } }, M, 403, 'team-holder', 'a manager cannot edit another team holder');
await err('PATCH', `/biz/${BIZ}/team/${MX}`, { perms: { team: false } }, M, 403, 'team-holder', 'a manager cannot revoke the team switch');
await err('POST', `/biz/${BIZ}/team`, { userId: MX, role: 'staff' }, M, 403, 'team-holder', 'a manager cannot demote another team holder (old POST route too)');
await err('DELETE', `/biz/${BIZ}/team/${MX}`, {}, M, 403, 'team-holder', 'a manager cannot remove another team holder');
// لا يعدّل أحد مفاتيحه ولا يزيل نفسه
await err('PATCH', `/biz/${BIZ}/team/${M}`, { perms: { stats: false } }, M, 403, 'self', 'nobody edits their own switches');
await err('POST', `/biz/${BIZ}/team`, { userId: M, role: 'manager' }, M, 403, 'self', 'nobody edits themselves through POST either');
await err('DELETE', `/biz/${BIZ}/team/${M}`, {}, M, 403, 'self', 'nobody removes themselves');
// لا يمنح أحد صلاحية لا يحملها: MX بلا «الإحصاءات» لا يشغّلها ولا يضيف موظفاً بقالبه (فيه الإحصاءات)
await err('PATCH', `/biz/${BIZ}/team/${H}`, { perms: { stats: true } }, MX, 403, 'not-held', 'a member cannot grant a switch they do not hold');
r = await err('POST', `/biz/${BIZ}/team`, { userId: U(99), role: 'staff' }, MX, 404, 'user-not-found', 'unknown user → 404');
await pool.query("INSERT INTO users(id,nickname) VALUES($1,'new4') ON CONFLICT (id) DO NOTHING", [U(98)]);
r = await err('POST', `/biz/${BIZ}/team`, { userId: U(98), role: 'staff' }, MX, 403, 'not-held', 'adding with a preset that carries a switch the actor lacks is refused');
check(r.perm === 'stats', 'the refusal names the missing switch', JSON.stringify(r));
r = await call('POST', `/biz/${BIZ}/team`, { user: MX, body: { userId: U(98), role: 'staff', perms: { stats: false } }, expect: 200 });
check(same(r.member.perms, ['orders', 'inbox']), 'the same add without the missing switch is accepted');
// تغيير دور ينقل صلاحية لا يحملها الفاعل: مرفوض؛ وسحب صلاحية لا يحملها مسموح
await call('PATCH', `/biz/${BIZ}/team/${N1}`, { user: O, body: { perms: { stats: true } }, expect: 200 });
// لا يمس غيرُ المالك عضواً يحمل صلاحية ليست عنده، ولو لإطفائها: MX بلا «الإحصاءات» لا يعدّل N1 الذي يحملها ولا يزيله
await err('PATCH', `/biz/${BIZ}/team/${N1}`, { perms: { stats: false } }, MX, 403, 'outranked', 'a member cannot edit someone who holds a switch they lack, even to switch it off');
await err('PATCH', `/biz/${BIZ}/team/${N1}`, { role: 'hr' }, MX, 403, 'outranked', 'nor change their role');
await err('DELETE', `/biz/${BIZ}/team/${N1}`, {}, MX, 403, 'outranked', 'nor remove them');
r = await call('PATCH', `/biz/${BIZ}/team/${N2}`, { user: MX, body: { perms: { orders: true } }, expect: 200 });
check(same(r.member.perms, ['hiring', 'orders']), 'a member whose switches are all held by the actor stays editable');
await call('PATCH', `/biz/${BIZ}/team/${N2}`, { user: MX, body: { perms: { orders: false } }, expect: 200 });
{
  // أقل الفريق صلاحية (مفتاحه الوحيد «إدارة الفريق») لا يجرّد مديراً سُحبت منه «إدارة الفريق» ولا يزيله
  await pool.query("INSERT INTO users(id,nickname) VALUES($1,'teamonly') ON CONFLICT (id) DO NOTHING", [U(97)]);
  const T = U(97); NAMES[T] = 'teamonly';
  r = await call('POST', `/biz/${BIZ}/team`, { user: O, body: { userId: T, role: 'staff', perms: { orders: false, inbox: false, stats: false, team: true } }, expect: 200 });
  check(same(r.member.perms, ['team']), 'the owner adds a member whose only switch is team');
  const before = JSON.stringify((await pool.query("SELECT role, perms FROM biz_staff WHERE biz_id=$1 AND user_id=$2", [BIZ, N3])).rows[0]);
  await err('PATCH', `/biz/${BIZ}/team/${N3}`, { role: 'hr', perms: { hiring: false } }, T, 403, 'outranked', 'a team-only member cannot strip a manager who holds every other switch');
  await err('POST', `/biz/${BIZ}/team`, { userId: N3, role: 'hr' }, T, 403, 'outranked', 'nor through the old POST route');
  await err('DELETE', `/biz/${BIZ}/team/${N3}`, {}, T, 403, 'outranked', 'nor remove that manager');
  await err('DELETE', `/biz/${BIZ}/team/${S}`, {}, T, 403, 'outranked', 'nor remove a plain staff member (orders, inbox, stats are not theirs)');
  check(JSON.stringify((await pool.query("SELECT role, perms FROM biz_staff WHERE biz_id=$1 AND user_id=$2", [BIZ, N3])).rows[0]) === before, 'the manager row is unchanged');
  const tv = await call('GET', `/biz/${BIZ}/team`, { user: T, expect: 200 });
  const lk = (id) => tv.staff.find((x) => x.user.id === id)?.lock;
  check(lk(N3) === 'outranked' && lk(S) === 'outranked' && lk(M) === 'team-holder' && lk(T) === 'self' && tv.staff.find((x) => x.user.id === N3).editable === false, 'the team view marks them locked (outranked) for that member', JSON.stringify(tv.staff.map((x) => [x.user.nickname, x.lock])));
  await err('POST', `/biz/${BIZ}/team`, { userId: X, role: 'hr' }, T, 403, 'not-held', 'and they cannot add anyone with a switch they lack');
  await call('DELETE', `/biz/${BIZ}/team/${T}`, { user: O, expect: 200 });
  const mv = await call('GET', `/biz/${BIZ}/team`, { user: MX, expect: 200 });
  check(mv.staff.find((x) => x.user.id === S)?.lock === 'outranked' && mv.staff.find((x) => x.user.id === H)?.lock === null, 'a manager without stats sees stats holders locked and others editable');
}
// موظف وعضو توظيف لا يديران الفريق أصلاً، والمالك لا يُضاف عضواً
await err('POST', `/biz/${BIZ}/team`, { userId: X, role: 'staff' }, S, 403, 'forbidden', 'staff cannot add members');
await err('DELETE', `/biz/${BIZ}/team/${N2}`, {}, H, 403, 'forbidden', 'hr cannot remove members');
await err('POST', `/biz/${BIZ}/team`, { userId: O, role: 'staff' }, M, 400, 'is-owner', 'the owner cannot be added as a member');
await err('PATCH', `/biz/${BIZ}/team/${S}`, { perms: { catalog: true } }, M2, 403, 'forbidden', 'a manager of another circle has no say here');
// نقل الملكية للمالك وحده
await err('POST', `/biz/${BIZ}/transfer`, { userId: M }, M, 403, 'forbidden', 'a manager cannot transfer ownership');
await err('POST', `/biz/${BIZ}/transfer`, { userId: MX }, MX, 403, 'forbidden', 'nor make themselves owner');
// المالك يفعل كل ما سبق؛ والنسخ الأقدم (POST بالدور وحده) تغيّر الدور وتعيد القالب
r = await call('POST', `/biz/${BIZ}/team`, { user: O, body: { userId: N1, role: 'manager' }, expect: 200 });
check(r.member.role === 'manager' && r.member.custom === false && same(r.member.perms, ALL), 'owner promotes through the old POST route: new role, preset switches');
r = await call('PATCH', `/biz/${BIZ}/team/${N1}`, { user: O, body: { perms: { team: false } }, expect: 200 });
check(!r.member.perms.includes('team'), 'owner revokes the team switch');
r = await call('POST', `/biz/${BIZ}/team`, { user: O, body: { userId: N1, role: 'manager' }, expect: 200 });
check(!r.member.perms.includes('team') && r.member.custom === true, 'POST with the same role keeps the member\'s switches');
r = await call('POST', `/biz/${BIZ}/team`, { user: O, body: { userId: N1, role: 'weird' }, expect: 200 });
check(r.member.role === 'staff', 'old builds: an unknown role on POST falls back to staff as before');
await call('PATCH', `/biz/${BIZ}/team/${N1}`, { user: A, body: { perms: { catalog: true } }, expect: 200 });
await call('DELETE', `/biz/${BIZ}/team/${N1}`, { user: M, expect: 200 });
await call('DELETE', `/biz/${BIZ}/team/${N3}`, { user: O, expect: 200 });
await call('DELETE', `/biz/${BIZ}/team/${U(98)}`, { user: O, expect: 200 });
await call('DELETE', `/biz/${BIZ}/team/${N2}`, { user: O, expect: 200 });

console.log('\n--- the 50-member limit blocks additions only');
{
  const have = (await pool.query("SELECT count(*)::int AS n FROM biz_staff WHERE biz_id=$1", [BIZ])).rows[0].n;
  await pool.query(`INSERT INTO biz_staff(biz_id,user_id,role) VALUES ${FILL.slice(0, 50 - have).map((u) => `('${BIZ}','${u}','staff')`).join(',')}`);
  check((await pool.query("SELECT count(*)::int AS n FROM biz_staff WHERE biz_id=$1", [BIZ])).rows[0].n === 50, 'the team is at the limit');
  await err('POST', `/biz/${BIZ}/team`, { userId: N1, role: 'staff' }, O, 409, 'too-many', 'a 51st member is refused');
  r = await call('POST', `/biz/${BIZ}/team`, { user: O, body: { userId: FILL[0], role: 'hr' }, expect: 200 });
  check(r.member.role === 'hr', 'changing an existing member\'s role at the limit works (was refused before)');
  await call('PATCH', `/biz/${BIZ}/team/${FILL[1]}`, { user: O, body: { perms: { reviews: true } }, expect: 200 });
  await pool.query("DELETE FROM biz_staff WHERE biz_id=$1 AND user_id = ANY($2::text[])", [BIZ, FILL]);
}

console.log('\n--- notification recipients follow the switches');
// الآن: O مالك، M مدير، S موظف، H توظيف، SX موظف + القائمة، MX مدير − الإحصاءات
take();
const ord = await call('POST', `/biz/${BIZ}/orders`, { user: C, body: { itemId: 'bp-shop-free', qty: 1 }, expect: 200 });
let n = take('biz_order');
check(n.length === 1 && same(n[0].ids, [O, M, S, SX, MX]), 'a new order notifies holders of «orders» only (not the hr member)', JSON.stringify(n.map((x) => x.ids)));
check(!n[0].ids.includes(H) && n[0].body.includes(ord.code), 'the hr member no longer receives the customer name and pickup code');
await call('PATCH', `/biz/${BIZ}/team/${S}`, { body: { perms: { orders: false } }, expect: 200 });
await call('PATCH', `/biz/${BIZ}/team/${H}`, { body: { perms: { orders: true } }, expect: 200 });
take();
await call('POST', `/biz/orders/${ord.id}/cancel`, { user: C, expect: 200 });
n = take('order_cancelled');
check(n.length === 1 && same(n[0].ids, [O, M, SX, MX, H]), 'a cancellation follows the switch: off for the staff member, on for the hr member', JSON.stringify(n.map((x) => x.ids)));
await call('PATCH', `/biz/${BIZ}/team/${S}`, { body: { perms: { orders: true } }, expect: 200 });
await call('PATCH', `/biz/${BIZ}/team/${H}`, { body: { perms: { orders: false } }, expect: 200 });
// نزاع على طلب مدفوع محجوز
const paid = (await pool.query("INSERT INTO biz_orders(id,biz_id,item_id,user_id,kind,qty,units,total,code,payment,funds,release_at) VALUES(gen_random_uuid(),$1,'bp-shop-oil',$2,'product',1,1,5000,'NAS-PERMS01','wallet','held',now() + interval '3 days') RETURNING id", [BIZ, C])).rows[0];
take();
await call('POST', `/biz/orders/${paid.id}/dispute`, { user: C, body: { reason: 'المنتج لم يصل كاملاً' }, expect: 200 });
n = take('biz_dispute').filter((x) => x.data?.side === 'team');
check(n.length === 1 && same(n[0].ids, [O, M, S, SX, MX]), 'a dispute notifies holders of «orders» only', JSON.stringify(n.map((x) => x.ids)));
// الطلب بمعرّفه والرد في النزاع لمن يحمل «الطلبات»
await call('GET', `/biz/orders/${paid.id}`, { user: S, expect: 200 });
await call('GET', `/biz/orders/${paid.id}`, { user: H, expect: 404 });
await call('POST', `/biz/orders/${paid.id}/dispute/reply`, { user: H, body: { text: 'رد من غير مخوّل' }, expect: 404 });
// التقييم الجديد لمن يحمل «الرد على التقييمات»
await call('PATCH', `/biz/${BIZ}/team/${S}`, { body: { perms: { reviews: true } }, expect: 200 });
take();
await call('POST', `/biz/${BIZ}/reviews`, { user: C, body: { rating: 4, text: 'جيد' }, expect: 200 });
n = take('biz_review');
check(n.length === 1 && same(n[0].ids, [O, M, MX, S]), 'a new review notifies holders of «reviews» (managers by preset, plus the staff member switched on)', JSON.stringify(n.map((x) => x.ids)));
await call('PATCH', `/biz/${BIZ}/team/${S}`, { body: { perms: { reviews: false } }, expect: 200 });
// رسالة العميل لمن يحمل «رسائل العملاء»
await call('PATCH', `/biz/${BIZ}/team/${MX}`, { body: { perms: { inbox: false } }, expect: 200 });
take();
await call('POST', `/biz/${BIZ}/thread`, { user: C, body: { text: 'هل الزيت متوفر؟' }, expect: 200 });
n = take('biz_inbox_message');
check(n.length === 1 && same(n[0].ids, [O, M, S, SX]), 'a customer message notifies holders of «inbox» only', JSON.stringify(n.map((x) => x.ids)));
const ib = await call('GET', `/biz/${BIZ}/inbox`, { user: S, expect: 200 });
check(same(ib.team.map((x) => x.id), [O, M, S, SX]), 'the inbox team list is the holders of «inbox»');
await call('PATCH', `/biz/${BIZ}/team/${MX}`, { body: { perms: { inbox: true } }, expect: 200 });
// فريق التوظيف: من يحمل «التوظيف»
await call('PATCH', `/biz/${BIZ}/team/${S}`, { body: { perms: { hiring: true } }, expect: 200 });
await call('PATCH', `/biz/${BIZ}/team/${M}`, { body: { perms: { hiring: false } }, expect: 200 });
const mj = await call('GET', `/biz/${BIZ}/manage/jobs`, { user: H, expect: 200 });
check(same(mj.team.map((x) => x.id), [O, S, H, MX]), 'the hiring team (and candidate notifications) is the holders of «hiring»', JSON.stringify(mj.team.map((x) => x.nickname)));
check(same(await P.holders({ id: BIZ, owner_id: O }, 'hiring'), [O, S, H, MX]), 'holders(hiring) from the shared helper');
await call('GET', `/biz/${BIZ}/manage/jobs`, { user: M, expect: 403 });
{
  const q = (await pool.query(`SELECT s.user_id FROM biz_staff s WHERE s.biz_id=$1 AND ${P.permSql('s', 'hiring')}`, [BIZ])).rows.map((x) => x.user_id);
  check(same(q, [S, H, MX]), 'permSql agrees with the JS helper (switch first, then the role preset)', JSON.stringify(q));
}
await call('PATCH', `/biz/${BIZ}/team/${S}`, { body: { perms: { hiring: false } }, expect: 200 });
await call('PATCH', `/biz/${BIZ}/team/${M}`, { body: { perms: { hiring: true } }, expect: 200 });
{
  // مسؤول العرض الذي سُحبت منه «التوظيف» أو أُزيل: لا يُوجَّه إليه المرشح ولا يبقى له استثناء المراسلة
  await call('POST', `/biz/${BIZ}/team`, { user: O, body: { userId: N2, role: 'hr' }, expect: 200 });
  const jid = crypto.randomUUID(), mid = crypto.randomUUID();
  await pool.query("INSERT INTO jobs(id,biz_id,created_by,assignee_id,title,status,published_at) VALUES($1,$2,$3,$4,'محاسب','open',now())", [jid, BIZ, O, N2]);
  await pool.query("INSERT INTO job_matches(id,job_id,biz_id,user_id,status,stage,answered_at,accepted_at) VALUES($1,$2,$3,$4,'answered','new',now(),now())", [mid, jid, BIZ, C]);
  const allow = globalThis.naslifeMessageAllow.get('jobs');
  const contact = async () => (await call('GET', '/jobs/mine', { user: C, expect: 200 })).items.find((x) => x.id === mid)?.assignee?.id;
  check((await allow(C, N2)) === true && (await allow(N2, C)) === true && (await contact()) === N2, 'the job assignee who holds hiring is the candidate\'s contact and may message them');
  await call('PATCH', `/biz/${BIZ}/team/${N2}`, { body: { perms: { hiring: false, orders: true } }, expect: 200 });
  check((await allow(C, N2)) === false && (await allow(N2, C)) === false, 'hiring switched off → the message exemption closes for the old assignee');
  check((await contact()) === O, 'and candidates are pointed at the owner instead', String(await contact()));
  check((await allow(C, O)) === true && (await allow(C, H)) === true, 'the owner and current hiring members keep the exemption');
  await call('PATCH', `/biz/${BIZ}/team/${N2}`, { body: { perms: { hiring: true } }, expect: 200 });
  check((await allow(C, N2)) === true && (await contact()) === N2, 'switched back on → the assignee is the contact again');
  await call('DELETE', `/biz/${BIZ}/team/${N2}`, { user: O, expect: 200 });
  check((await allow(C, N2)) === false && (await contact()) === O, 'removed from the team → no exemption, contact falls back to the owner');
  await pool.query("DELETE FROM job_matches WHERE id=$1", [mid]); await pool.query("DELETE FROM jobs WHERE id=$1", [jid]);
}

console.log('\n--- community moderation: posts or inbox');
{
  const post = await call('POST', `/biz/${BIZ}/community`, { user: C, body: { text: 'منشور عميل في مجتمع الدائرة', topic: 'general' } });
  const pid = post?.id ?? post?.post?.id;
  check(!!pid, 'a customer posts in the circle community', JSON.stringify(post).slice(0, 160));
  if (pid) {
    const st = async (u) => (await req('POST', `/biz/${BIZ}/community/${pid}/hide`, { user: u })).status;
    check((await st(H)) === 403, 'the hr member does not moderate (as before)');
    check((await st(X)) === 403, 'a stranger does not moderate');
    check((await st(S)) !== 403, 'a staff member still moderates (holds inbox), as before the switches');
    await call('PATCH', `/biz/${BIZ}/team/${S}`, { body: { perms: { inbox: false } }, expect: 200 });
    check((await st(S)) === 403, 'without inbox and posts the staff member no longer moderates');
    await call('PATCH', `/biz/${BIZ}/team/${S}`, { body: { perms: { inbox: true } }, expect: 200 });
    await call('PATCH', `/biz/${BIZ}/team/${H}`, { body: { perms: { posts: true } }, expect: 200 });
    check((await st(H)) !== 403, 'the hr member moderates once «posts» is switched on');
    await call('PATCH', `/biz/${BIZ}/team/${H}`, { body: { perms: { posts: false } }, expect: 200 });
  }
}

console.log('\n--- revenue figures need the stats switch');
{
  const s1 = await call('GET', `/biz/${BIZ}/stats`, { user: S, expect: 200 });
  check(typeof s1.revenue?.total === 'number' && typeof s1.money?.held === 'number', 'a staff member (stats in the preset) still gets the figures, as today');
  await call('PATCH', `/biz/${BIZ}/team/${S}`, { body: { perms: { stats: false } }, expect: 200 });
  const s2 = await call('GET', `/biz/${BIZ}/stats`, { user: S, expect: 403 });
  check(s2.error === 'forbidden' && s2.revenue === undefined && s2.money === undefined, 'stats switched off → 403 with no figures');
  const comp = await call('GET', `/biz/${BIZ}/completeness`, { user: S, expect: 200 });
  const flat = JSON.stringify(comp);
  check(!/revenue|money|held|total"/.test(flat), 'completeness carries no revenue figures');
  const detail = await call('GET', `/biz/${BIZ}`, { user: S, expect: 200 });
  check(!/"revenue"|"money"/.test(JSON.stringify(detail)), 'the circle detail carries no revenue figures');
  // سجل الطلبات المنتهية بلا مبالغ لمن لا يحمل الإحصاءات؛ يبقى مبلغ ما ينتظر فعله (مؤكد، لم يُدفع في المكان، نزاع مفتوح)
  const ins = async (code, total, cols, vals) => (await pool.query(`INSERT INTO biz_orders(id,biz_id,item_id,user_id,kind,qty,units,total,code,${cols}) VALUES(gen_random_uuid(),$1,'bp-shop-oil',$2,'product',1,1,${total},'${code}',${vals}) RETURNING id`, [BIZ, C])).rows[0].id;
  const done = await ins('NAS-PERMS10', 7000, 'payment,funds,status,used_at,released_at', "'wallet','released','used',now() - interval '9 days',now() - interval '9 days'");
  const donePaid = await ins('NAS-PERMS11', 6000, 'payment,status,used_at,paid_at', "'at_venue','used',now(),now()");
  const gone = await ins('NAS-PERMS12', 4000, 'payment,funds,status', "'wallet','refunded','cancelled'");
  const due = await ins('NAS-PERMS13', 3000, 'payment,status,used_at', "'at_venue','used',now()");
  const open = await ins('NAS-PERMS14', 2000, 'payment', "'at_venue'");
  await pool.query(`UPDATE biz_orders SET lines='[{"itemId":"bp-shop-oil","title":"زيت","qty":1,"unit":7000,"total":7000,"options":[{"groupId":"g","group":"الحجم","choiceId":"c","choice":"كبير","delta":2000}]}]'::jsonb, meta='{"cartTitle":"زيت","offer":{"id":"x","title":"خصم","discount":500,"before":7500}}'::jsonb WHERE id=$1`, [done]);
  const orders = await call('GET', `/biz/${BIZ}/orders`, { user: S, expect: 200 });
  const by = (list, id) => list.find((o) => o.id === id);
  check([done, donePaid, gone].every((id) => by(orders, id)?.total === null && by(orders, id)?.amountHidden === true), 'finished, paid and cancelled orders come without their amount', JSON.stringify([done, donePaid, gone].map((id) => by(orders, id)?.total)));
  const d = by(orders, done);
  check(d.offer === null && d.meta.offer === undefined && d.lines[0].unit === null && d.lines[0].total === null && d.lines[0].options[0].delta === null && d.lines[0].title === 'زيت' && d.code === 'NAS-PERMS10' && d.customer?.id === C,
    'the hidden order keeps what the member needs (item, code, customer) and drops line prices and the offer discount', JSON.stringify(d).slice(0, 300));
  check(by(orders, due)?.total === 3000 && by(orders, open)?.total === 2000 && by(orders, paid.id)?.total === 5000 && !by(orders, open).amountHidden, 'orders awaiting action keep the amount: unpaid at the venue, confirmed, open dispute');
  const sum = (list) => list.reduce((n, o) => n + (o.total ?? 0), 0);
  const full = await call('GET', `/biz/${BIZ}/orders`, { user: O, expect: 200 });
  check(sum(full) - sum(orders) === 17000 && full.every((o) => typeof o.total === 'number' && !o.amountHidden), 'the list no longer adds up to the circle revenue for that member; the owner still gets every amount', `${sum(orders)} / ${sum(full)}`);
  check(!/7000|6000|4000/.test(JSON.stringify(orders)), 'no hidden amount appears anywhere in the list payload');
  check((await call('GET', `/biz/orders/${done}`, { user: S, expect: 200 })).total === null, 'the single order route hides it too');
  check((await call('GET', `/biz/orders/${done}`, { user: M, expect: 200 })).total === 7000, 'a member with stats gets it');
  check((await call('GET', `/biz/orders/${done}`, { user: C, expect: 200 })).total === 7000, 'the customer always sees their own amount');
  r = await call('POST', `/biz/${BIZ}/orders/${due}/paid`, { user: S, expect: 200 });
  check(r.total === null && r.amountHidden === true && r.paid === true, 'once paid, the reply to that member no longer carries the amount');
  await call('PATCH', `/biz/${BIZ}/team/${S}`, { body: { perms: { stats: true } }, expect: 200 });
  check(by(await call('GET', `/biz/${BIZ}/orders`, { user: S, expect: 200 }), done)?.total === 7000, 'with stats back on the amounts return');
  await pool.query("DELETE FROM biz_orders WHERE id = ANY($1::uuid[])", [[done, donePaid, gone, due, open]]);
  // العروض: MX يدير العروض بلا «الإحصاءات» فلا يرى إيراد العرض
  const starts = new Date(Date.now() - 3600000).toISOString(), ends = new Date(Date.now() + 5 * 86400000).toISOString();
  const offer = await call('POST', `/biz/${BIZ}/manage/offers`, { user: M, body: { kind: 'coupon', title: 'خصم الصلاحيات', value: { type: 'percent', amount: 10 }, startsAt: starts, endsAt: ends }, expect: 200 });
  check(typeof offer.stats?.revenue === 'number', 'a manager with stats sees the offer revenue', JSON.stringify(offer.stats));
  const lm = await call('GET', `/biz/${BIZ}/manage/offers`, { user: MX, expect: 200 });
  check(lm.offers.length === 1 && lm.offers[0].stats.revenue === null && lm.offers[0].stats.discount === null && lm.offers[0].stats.hidden === true && typeof lm.offers[0].stats.views === 'number', 'a manager without stats manages offers but gets no revenue figure', JSON.stringify(lm.offers[0]?.stats));
  const lo = await call('GET', `/biz/${BIZ}/manage/offers`, { user: O, expect: 200 });
  check(typeof lo.offers[0].stats.revenue === 'number', 'the owner sees it');
  globalThis.__offerId = offer.id;
}

console.log('\n--- activity log');
await pool.query("DELETE FROM biz_activity WHERE biz_id=$1", [BIZ]);
const acts = async () => (await pool.query("SELECT * FROM biz_activity WHERE biz_id=$1 ORDER BY id", [BIZ])).rows;
const last = async () => (await acts()).at(-1);
const logged = async (action, actor, re, label) => { const a = await last(); check(a?.action === action && a?.actor_id === actor && re.test(a?.summary ?? ''), `log ${action}: ${label}`, JSON.stringify(a)); return a; };
// الفريق
await call('POST', `/biz/${BIZ}/team`, { user: M, body: { userId: N1, role: 'staff' }, expect: 200 });
let a = await logged('team.add', M, /أضاف new1 بدور موظف/, 'member added by the manager');
check(a.target === N1, 'the target is the member id');
await call('PATCH', `/biz/${BIZ}/team/${N1}`, { user: O, body: { perms: { catalog: true, stats: false } }, expect: 200 });
await logged('team.perms', O, /شغّل القائمة والأسعار.*أطفأ المبيعات والإحصاءات/, 'switch change names what went on and off');
const before = (await acts()).length;
await call('PATCH', `/biz/${BIZ}/team/${N1}`, { user: O, body: { perms: { catalog: true } }, expect: 200 });
check((await acts()).length === before, 'a no-op edit writes nothing');
await call('PATCH', `/biz/${BIZ}/team/${N1}`, { user: O, body: { role: 'hr' }, expect: 200 });
await logged('team.role', O, /غيّر دور new1 من موظف إلى توظيف/, 'role change');
await call('DELETE', `/biz/${BIZ}/team/${N1}`, { user: O, expect: 200 });
await logged('team.remove', O, /أزال new1 من الفريق/, 'member removed');
// القائمة
const item = await call('POST', `/biz/${BIZ}/items`, { user: SX, body: { title: 'قهوة مختصة', price: 1500 }, expect: 200 });
a = await logged('item.create', SX, /أضاف «قهوة مختصة» بسعر 15 ر\.س/, 'item created by the staff member with the catalog switch');
await call('PATCH', `/biz/${BIZ}/items/${item.id}`, { user: SX, body: { price: 1800 }, expect: 200 });
a = await logged('item.price', SX, /غيّر سعر «قهوة مختصة» من 15 ر\.س إلى 18 ر\.س/, 'price change with old and new');
check(a.target === item.id, 'the target is the item id');
await call('PATCH', `/biz/${BIZ}/items/${item.id}`, { user: M, body: { description: 'محمصة محلية' }, expect: 200 });
await logged('item.update', M, /عدّل «قهوة مختصة»/, 'item edited');
await call('DELETE', `/biz/${BIZ}/items/${item.id}`, { user: M, expect: 200 });
await logged('item.delete', M, /حذف «قهوة مختصة»/, 'item deleted');
// العروض
const oid = globalThis.__offerId;
await call('PATCH', `/biz/${BIZ}/manage/offers/${oid}`, { user: M, body: { active: false }, expect: 200 });
await logged('offer.update', M, /أوقف عرض «خصم الصلاحيات»/, 'offer paused');
const starts2 = new Date(Date.now() - 3600000).toISOString(), ends2 = new Date(Date.now() + 5 * 86400000).toISOString();
const of2 = await call('POST', `/biz/${BIZ}/manage/offers`, { user: O, body: { kind: 'coupon', title: 'عرض السجل', value: { type: 'percent', amount: 5 }, startsAt: starts2, endsAt: ends2 }, expect: 200 });
await logged('offer.create', O, /أنشأ عرض «عرض السجل»/, 'offer created');
await call('PATCH', `/biz/${BIZ}/manage/offers/${of2.id}`, { user: O, body: { kind: 'coupon', title: 'عرض السجل 2', value: { type: 'percent', amount: 7 }, startsAt: starts2, endsAt: ends2 }, expect: 200 });
await logged('offer.update', O, /عدّل عرض «عرض السجل 2»/, 'offer edited');
await call('DELETE', `/biz/${BIZ}/manage/offers/${of2.id}`, { user: O, expect: 200 });
await logged('offer.delete', O, /حذف عرض «عرض السجل 2»/, 'offer deleted');
// الطلبات
const o1 = await call('POST', `/biz/${BIZ}/orders`, { user: C, body: { itemId: 'bp-shop-free', qty: 1 }, expect: 200 });
await call('POST', `/biz/${BIZ}/checkin`, { user: S, body: { code: o1.code }, expect: 200 });
a = await logged('order.checkin', S, new RegExp(`أكّد استلام «عيّنة» \\(${o1.code}\\)`), 'check-in by the staff member');
check(a.target === o1.id && !/cust/.test(a.summary), 'the row points at the order and holds no customer name');
const o2 = await call('POST', `/biz/${BIZ}/orders`, { user: C, body: { itemId: 'bp-shop-free', qty: 1 }, expect: 200 });
await call('POST', `/biz/${BIZ}/orders/${o2.id}/cancel`, { user: S, expect: 403 });
await call('POST', `/biz/${BIZ}/orders/${o2.id}/cancel`, { user: M, expect: 200 });
await logged('order.cancel', M, new RegExp(`ألغى «عيّنة» \\(${o2.code}\\)`), 'order cancelled by the manager');
const venue = (await pool.query("INSERT INTO biz_orders(id,biz_id,item_id,user_id,kind,qty,units,total,code,payment,created_at) VALUES(gen_random_uuid(),$1,'bp-shop-oil',$2,'product',1,1,5000,'NAS-PERMS02','at_venue',now() - interval '2 days') RETURNING id", [BIZ, C])).rows[0];
const venue2 = (await pool.query("INSERT INTO biz_orders(id,biz_id,item_id,user_id,kind,qty,units,total,code,payment,created_at) VALUES(gen_random_uuid(),$1,'bp-shop-oil',$2,'product',1,1,5000,'NAS-PERMS03','at_venue',now() - interval '2 days') RETURNING id", [BIZ, C])).rows[0];
await call('POST', `/biz/${BIZ}/orders/${venue.id}/paid`, { user: S, expect: 200 });
await logged('order.paid', S, /^سجّل دفع «زيت» \(NAS-PERMS02\) في المكان$/, 'marked paid at the venue, without the amount');
const held = (await pool.query("INSERT INTO biz_orders(id,biz_id,item_id,user_id,kind,qty,units,total,code,payment,funds,release_at) VALUES(gen_random_uuid(),$1,'bp-shop-oil',$2,'product',1,1,15000,'NAS-PERMS04','wallet','held',now() + interval '3 days') RETURNING id", [BIZ, C])).rows[0];
r = await call('POST', `/biz/${BIZ}/orders/${held.id}/cancel`, { user: M, expect: 200 });
check(r.refunded === 15000, 'a held paid order is refunded on cancel', JSON.stringify(r));
await logged('order.cancel', M, /^ألغى «زيت» \(NAS-PERMS04\) مع استرداد المبلغ$/, 'refund noted without the amount');
await call('POST', `/biz/${BIZ}/orders/${venue2.id}/no-show`, { user: S, expect: 200 });
await logged('order.no_show', S, /لم يحضر.*NAS-PERMS03/, 'no-show');
// بيانات الدائرة والتوثيق
await call('PATCH', `/biz/${BIZ}`, { user: M, body: { hours: 'يومياً 8:00 ص – 10:00 م', phone: '0500000000' }, expect: 200 });
await logged('profile.edit', M, /عدّل بيانات الدائرة: .*ساعات العمل.*الهاتف|عدّل بيانات الدائرة: .*الهاتف.*ساعات العمل/, 'profile edit lists the changed fields, not their values');
await call('PATCH', `/biz/${BIZ}`, { user: O, body: { active: false }, expect: 200 });
await logged('profile.pause', O, /أوقف الدائرة/, 'pause');
await call('PATCH', `/biz/${BIZ}`, { user: O, body: { active: true }, expect: 200 });
await logged('profile.resume', O, /أعاد نشر الدائرة/, 'republish');
await pool.query("UPDATE biz SET verified=false, verification='{\"status\":\"none\"}'::jsonb WHERE id=$1", [BIZ]);
await call('POST', `/biz/${BIZ}/verification`, { user: O, body: { entityKind: 'cr', entityNumber: '1010101010', docUrl: '/chat/media/k9x1zz-abcdef0123456789abcdef01.pdf' }, expect: 200 });
a = await logged('verification.submit', O, /أرسل طلب التوثيق/, 'verification submitted');
check(!/1010101010/.test(a.summary), 'the entity number is not copied into the log');
// المنشورات والتقييمات
const post = await call('POST', `/biz/${BIZ}/posts`, { user: M, body: { title: 'خبر جديد', body: 'تفاصيل' }, expect: 200 });
await logged('post.create', M, /نشر «خبر جديد»/, 'post created');
await call('DELETE', `/biz/${BIZ}/posts/${post.id}`, { user: M, expect: 200 });
await logged('post.delete', M, /حذف منشور «خبر جديد»/, 'post deleted');
await call('POST', `/biz/${BIZ}/reviews/${C}/reply`, { user: M, body: { text: 'شكراً لك على التقييم الجميل' }, expect: 200 });
a = await logged('review.reply', M, /^ردّ على تقييم$/, 'review reply');
check(!/شكراً/.test(a.summary), 'the reply text is not stored in the log');
// القراءة: المالك ومن يحمل «إدارة الفريق»، الأحدث أولاً، صفحات، واسم الفاعل
let page = await call('GET', `/biz/${BIZ}/activity?limit=5`, { user: O, expect: 200 });
const total = (await acts()).length;
check(page.items.length === 5 && page.items[0].action === 'review.reply' && page.items[0].actor?.nickname === 'manager' && page.next && page.keepDays === 180, 'newest first with the actor nickname and a cursor', JSON.stringify(page.items[0]));
check(page.items.every((x, i) => i === 0 || BigInt(x.id) < BigInt(page.items[i - 1].id)), 'ids strictly descending');
const seen = [...page.items];
while (page.next) { page = await call('GET', `/biz/${BIZ}/activity?limit=5&before=${page.next}`, { user: M }); seen.push(...page.items); }
check(seen.length === total && new Set(seen.map((x) => x.id)).size === total, `paging walks every row once (${total})`);
{
  // من يحمل «إدارة الفريق» بلا «الإحصاءات» ولا «الطلبات» يقرأ السجل: لا مبلغ دفع أو استرداد فيه
  const T = U(97);
  await call('POST', `/biz/${BIZ}/team`, { user: O, body: { userId: T, role: 'staff', perms: { orders: false, inbox: false, stats: false, team: true } }, expect: 200 });
  await call('GET', `/biz/${BIZ}/stats`, { user: T, expect: 403 });
  await call('GET', `/biz/${BIZ}/orders`, { user: T, expect: 403 });
  const all = []; let pg2 = await call('GET', `/biz/${BIZ}/activity?limit=100`, { user: T, expect: 200 }); all.push(...pg2.items);
  const ord = all.filter((x) => x.action.startsWith('order.'));
  check(ord.length >= 5 && ord.every((x) => !/ر\.س|\d+\s*ريال|150|\b50\b/.test(x.summary)), 'order rows in the log carry no payment or refund amounts for a team holder without stats', JSON.stringify(ord.map((x) => x.summary)));
  check((await acts()).filter((x) => x.action.startsWith('order.')).every((x) => !/ر\.س/.test(x.summary)), 'and none is stored at all');
  await pool.query("DELETE FROM biz_staff WHERE biz_id=$1 AND user_id=$2", [BIZ, T]);
  await pool.query("DELETE FROM biz_activity WHERE biz_id=$1 AND target=$2", [BIZ, T]);
}
await call('GET', `/biz/${BIZ}/activity`, { user: S, expect: 403 });
await call('GET', `/biz/${BIZ}/activity`, { user: H, expect: 403 });
await call('GET', `/biz/${BIZ}/activity`, { user: A, expect: 200 });
check((await call('GET', '/biz/bp-other/activity', { user: O2, expect: 200 })).items.length === 0, 'another circle\'s log is separate');
await call('GET', '/biz/bp-other/activity', { user: O, expect: 403 });
// نقل الملكية والكنس
await call('POST', `/biz/${BIZ}/transfer`, { user: O, body: { userId: M }, expect: 200 });
await logged('owner.transfer', O, /نقل ملكية الدائرة إلى manager/, 'ownership transfer');
check((await call('GET', `/biz/${BIZ}`, { user: O, expect: 200 })).myRole === 'manager', 'the previous owner stays as a manager');
await call('POST', `/biz/${BIZ}/transfer`, { user: M, body: { userId: O }, expect: 200 });
await pool.query("UPDATE biz_activity SET created_at = now() - interval '181 days' WHERE biz_id=$1 AND action LIKE 'team.%'", [BIZ]);
const old = (await pool.query("SELECT count(*)::int AS n FROM biz_activity WHERE biz_id=$1 AND action LIKE 'team.%'", [BIZ])).rows[0].n;
const swept = await P.sweepActivity();
check(old > 0 && swept >= old && (await pool.query("SELECT count(*)::int AS n FROM biz_activity WHERE biz_id=$1 AND action LIKE 'team.%'", [BIZ])).rows[0].n === 0, `the retention sweep drops rows older than 180 days (${old})`);
check((await acts()).length > 0, 'recent rows stay');

await app.close(); await pool.end();
console.log(fails ? `\n${fails} FAILED` : '\nALL BIZ PERMS TESTS PASSED');
process.exit(fails ? 1 : 0);
