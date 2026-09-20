// اختبارات لوحة الإدارة على Postgres المحلي: الإعداد الأول، النظرة العامة، المستخدمون، البلاغات، الدوائر، المالية، المحتوى، الإعدادات، السجل، وتقديم الواجهة.
import Fastify from 'fastify';
import pg from 'pg';
import fs from 'node:fs';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0';
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("INSERT INTO users(id,nickname) VALUES('SA0000001','amr'),('SA0000002','sara'),('SA0000003','khalid'),('SA0000004','temp') ON CONFLICT DO NOTHING");
await pool.query("ALTER TABLE users ADD COLUMN IF NOT EXISTS password_hash TEXT; UPDATE users SET password_hash='secret' WHERE id='SA0000002'");
// جداول تحاكي النواة لفحص التعديل والحذف النهائي: ملف (مفتاحه معرّف المستخدم)، جلسات، جهات اتصال
await pool.query("DROP TABLE IF EXISTS profiles; CREATE TABLE profiles (id TEXT PRIMARY KEY, bio TEXT NOT NULL DEFAULT '', is_public BOOLEAN NOT NULL DEFAULT true)");
await pool.query("INSERT INTO profiles(id,bio) VALUES('SA0000004','نبذة مؤقتة'),('SA0000002','') ON CONFLICT DO NOTHING");
await pool.query("DROP TABLE IF EXISTS sessions; CREATE TABLE sessions (token TEXT PRIMARY KEY, user_id TEXT NOT NULL)");
await pool.query("INSERT INTO sessions(token,user_id) VALUES('t4','SA0000004'),('t2','SA0000002')");
await pool.query("DROP TABLE IF EXISTS contacts; CREATE TABLE contacts (user_id TEXT NOT NULL, contact_id TEXT NOT NULL)");
await pool.query("INSERT INTO contacts(user_id,contact_id) VALUES('SA0000002','SA0000004'),('SA0000004','SA0000002'),('SA0000002','SA0000003')");
await pool.query("CREATE TABLE IF NOT EXISTS reports (id UUID PRIMARY KEY DEFAULT gen_random_uuid(), reporter_id TEXT, target_id TEXT, reason TEXT, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("INSERT INTO reports(reporter_id,target_id,reason) VALUES('SA0000002','SA0000003','إزعاج')");
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
const dir = new URL('.', import.meta.url).pathname;
app.register((await import('../commerce.js')).default, { pool, auth });
app.register((await import('../business.js')).default, { pool, auth });
app.register((await import('../admin.js')).default, { pool, auth, webappDir: dir + 'webapp', opsDir: dir + 'ops' });
await app.ready(); await new Promise(r => setTimeout(r, 300));
// المؤسسون يُثبَّتون من admin_bootstrap.js عند الإقلاع، فخطوة الإعداد الأول لا تعمل هنا؛ نمنح SA0000001 الإدارة مباشرة
await pool.query("INSERT INTO admins(user_id, granted_by) VALUES('SA0000001','harness') ON CONFLICT DO NOTHING");
let fails = 0;
const call = async (method, url, { body = {}, user = 'SA0000001', expect, headers = {} } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json', ...headers }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  const ok = expect == null || r.statusCode === expect; if (!ok) fails++;
  console.log((ok ? 'OK  ' : 'FAIL') + ' ' + method + ' ' + url + ' -> ' + r.statusCode + (ok ? '' : ' expected ' + expect) + ' ' + (typeof j === 'string' ? j.slice(0, 100) : JSON.stringify(j).slice(0, 140)));
  return j;
};
// الواجهة
const html = await call('GET', '/admin', { user: null, expect: 200 }); console.log('   /admin html?', String(html).includes('<!doctype'));
await call('GET', '/admin/users/SA1', { user: null, expect: 200 });
await call('GET', '/admin/', { user: null, expect: 200 });
await call('GET', '/adminapi/status', { user: null, headers: { host: 'admin.naslife.app' }, expect: 200 });
// الإعداد الأول
const code = fs.readFileSync(dir + 'ops/admin-setup-code', 'utf8').trim(); console.log('   setup code file:', code);
await call('GET', '/adminapi/status', { user: null, expect: 200 }).then(s => console.log('   status', JSON.stringify(s)));
await call('GET', '/adminapi/overview', { expect: 403 });
await call('POST', '/adminapi/setup', { body: { code: 'NL-WRONG' }, expect: 400 });
await call('POST', '/adminapi/setup', { body: { code: code.toLowerCase() }, expect: 200 });
await call('POST', '/adminapi/setup', { body: { code }, user: 'SA0000002', expect: 409 });
await call('GET', '/adminapi/status', { expect: 200 }).then(s => console.log('   status after', s.hasAdmin, s.isAdmin, s.admins));
// النظرة العامة
const ov = await call('GET', '/adminapi/overview', { expect: 200 });
console.log('   overview users', JSON.stringify(ov.users), 'circles', JSON.stringify(ov.circles), 'reports', JSON.stringify(ov.reports), 'daily', ov.daily.length, 'tables', ov.server.tables.join(','));
// المستخدمون
await call('GET', '/adminapi/users?q=sar', { expect: 200 }).then(l => console.log('   search', l.map(u => u.nickname + ':' + u.balance + ':' + u.isAdmin).join(',')));
await call('POST', '/adminapi/users/SA0000002/credit', { body: { amount: 250000, note: 'هدية' }, expect: 200 }).then(r => console.log('   credit balance', r.balance));
await call('POST', '/adminapi/users/SA0000002/credit', { body: { amount: -900000 }, expect: 402 });
await call('POST', '/adminapi/users/SA0000002/credit', { body: { amount: 0 }, expect: 400 });
await call('POST', '/adminapi/users/SA9999999/credit', { body: { amount: 100 }, expect: 404 });
await call('POST', '/adminapi/users/SA0000003/suspend', { body: { suspended: true, note: 'إزعاج' }, expect: 200 });
await call('POST', '/adminapi/users/SA0000001/suspend', { body: { suspended: true }, expect: 400 });
await call('POST', '/biz/biz-ikea/orders', { body: { itemId: 'ikea-lack', qty: 1 }, user: 'SA0000003', expect: 403 });   // موقوف
await call('GET', '/adminapi/users/SA0000003', { expect: 200 }).then(d => console.log('   detail suspended', d.user.suspended, 'reportsAbout', d.reportsAbout.length, 'actions', d.actions.length));
await call('GET', '/adminapi/users?filter=suspended', { expect: 200 }).then(l => console.log('   suspended list', l.map(u => u.id).join(',')));
await call('POST', '/adminapi/users/SA0000003/suspend', { body: { suspended: false }, expect: 200 });
// تعديل الملف من الإدارة: الاسم (النواة) والنبذة والظهور (جدول الملف المكتشف) وإزالة الصورة
await call('PATCH', '/adminapi/users/SA0000004', { body: { nickname: 'Bad Name' }, expect: 400 });
await call('PATCH', '/adminapi/users/SA0000004', { body: { nickname: 'sara' }, expect: 409 });
await call('PATCH', '/adminapi/users/SA0000004', { body: { nickname: 'temp_2', bio: 'نبذة جديدة', isPublic: false, avatarUrl: null }, expect: 200 }).then(r => console.log('   edit changes', JSON.stringify(r.changes), 'user.nickname', r.user.nickname));
{ const p = (await pool.query("SELECT bio, is_public FROM profiles WHERE id='SA0000004'")).rows[0]; const u = (await pool.query("SELECT nickname FROM users WHERE id='SA0000004'")).rows[0];
  const ok = p.bio === 'نبذة جديدة' && p.is_public === false && u.nickname === 'temp_2'; if (!ok) fails++; console.log((ok ? 'OK  ' : 'FAIL') + ' profile table and users row updated by admin edit'); }
// البيانات الشخصية الكاملة في التفاصيل: صف الحساب بلا أسرار، الملف، البُرُد، الاسترداد، الجلسات، الأعداد
{ const d = await call('GET', '/adminapi/users/SA0000002', { expect: 200 });
  console.log('   personal', JSON.stringify(d.personal), 'profile', JSON.stringify(d.profile), 'emails', JSON.stringify(d.emails), 'sessions', JSON.stringify(d.sessions), 'counts', JSON.stringify(d.counts));
  const ok = d.personal && d.personal.id === 'SA0000002' && d.personal.nickname === 'sara' && !('password_hash' in d.personal) && d.profile && 'bio' in d.profile
    && Array.isArray(d.emails) && d.recovery && typeof d.recovery.hasPhrase === 'boolean' && d.sessions && d.sessions.count === 1 && d.counts && typeof d.counts.listings === 'number';
  if (!ok) fails++; console.log((ok ? 'OK  ' : 'FAIL') + ' detail carries personal data without secrets, profile, emails, recovery, sessions and counts'); }
// حساب بلا صف ملف بعد (مسجّل حديثاً): التعديل من الإدارة ينشئ الصف
await call('PATCH', '/adminapi/users/SA0000003', { body: { bio: 'صف جديد', isPublic: false }, expect: 200 });
{ const p = (await pool.query("SELECT bio, is_public FROM profiles WHERE id='SA0000003'")).rows[0];
  const ok = p && p.bio === 'صف جديد' && p.is_public === false; if (!ok) fails++; console.log((ok ? 'OK  ' : 'FAIL') + ' admin edit creates the missing profile row'); }
// الحذف النهائي: تأكيد بالاسم، ثم يختفي من كل الجداول ويبقى في سجل الإجراءات
await call('POST', '/wallet/topup', { body: { amount: 10000 }, user: 'SA0000004', expect: 200 });
await call('DELETE', '/adminapi/users/SA0000004', { body: { confirm: 'wrong' }, expect: 400 });
await call('DELETE', '/adminapi/users/SA0000001', { body: { confirm: 'amr' }, expect: 400 }); // لا يحذف نفسه
const tDel = new Date();
await call('DELETE', '/adminapi/users/SA0000004', { body: { confirm: 'temp_2' }, expect: 200 }).then(r => console.log('   delete report', JSON.stringify(r.report)));
{ const left = async (sql) => (await pool.query(sql)).rowCount;
  const ok = (await left("SELECT 1 FROM users WHERE id='SA0000004'")) === 0 && (await left("SELECT 1 FROM profiles WHERE id='SA0000004'")) === 0 && (await left("SELECT 1 FROM sessions WHERE user_id='SA0000004'")) === 0
    && (await left("SELECT 1 FROM contacts WHERE user_id='SA0000004' OR contact_id='SA0000004'")) === 0 && (await left("SELECT 1 FROM wallet_accounts WHERE user_id='SA0000004'")) === 0
    && (await left("SELECT 1 FROM contacts WHERE user_id='SA0000002' AND contact_id='SA0000003'")) === 1 && (await left("SELECT 1 FROM sessions WHERE user_id='SA0000002'")) === 1
    && (await pool.query("SELECT 1 FROM admin_audit WHERE target='SA0000004' AND action='user.delete' AND created_at >= $1", [tDel])).rowCount === 1;
  if (!ok) fails++; console.log((ok ? 'OK  ' : 'FAIL') + ' permanent delete purged the user from users, profile, sessions, contacts and wallet; others intact; audit kept'); }
await call('GET', '/adminapi/users/SA0000004', { expect: 404 });
await call('POST', '/adminapi/users/SA0000002/admin', { body: { grant: true }, expect: 200 });
await call('GET', '/adminapi/overview', { user: 'SA0000002', expect: 200 });
await call('POST', '/adminapi/users/SA0000002/admin', { body: { grant: false }, user: 'SA0000002', expect: 200 });
await call('POST', '/adminapi/users/SA0000001/admin', { body: { grant: false }, expect: 409 });   // آخر مدير
await call('GET', '/adminapi/admins', { expect: 200 }).then(l => console.log('   admins', l.map(a => a.user.nickname + '/' + a.grantedBy).join(',')));
// البلاغات
const rep = await call('GET', '/adminapi/reports', { expect: 200 }); console.log('   reports table', rep.table, 'open', rep.items.length, 'target', rep.items[0]?.target?.nickname, 'reason', rep.items[0]?.reason);
await call('POST', '/adminapi/reports/' + rep.items[0].id + '/action', { body: { action: 'warn', note: 'تحذير أول' }, expect: 200 });
await call('GET', '/adminapi/reports', { expect: 200 }).then(r => console.log('   open after', r.items.length));
await call('GET', '/adminapi/reports?status=all', { expect: 200 }).then(r => console.log('   all', r.items.length, 'action', r.items[0].action?.action));
// الدوائر
const bl = await call('GET', '/adminapi/biz', { expect: 200 }); console.log('   biz', bl.length, 'first', bl[0].name, bl[0].orders, bl[0].revenue);
await call('POST', '/adminapi/biz/biz-ikea', { body: { verified: true, active: false }, expect: 200 });
await call('GET', '/biz/biz-ikea', { user: 'SA0000002', expect: 404 });
await call('POST', '/adminapi/biz/biz-ikea', { body: { active: true, ownerId: 'SA0000003' }, expect: 200 });
await call('POST', '/biz/biz-vox/claim', { body: { note: 'x' }, user: 'SA0000002', expect: 200 });
await call('GET', '/adminapi/claims', { expect: 200 }).then(l => console.log('   claims', l.length));
await call('POST', '/adminapi/claims/biz-vox/SA0000002/approve', { expect: 200 });
await call('GET', '/adminapi/claims', { expect: 200 }).then(l => console.log('   claims after', l.length));
// المالية
const fin = await call('GET', '/adminapi/finance', { expect: 200 }); console.log('   finance accounts', fin.totals.accounts, 'balance', fin.totals.balance, 'byKind', fin.byKind.map(k => k.kind).join(','), 'daily', fin.daily.length, 'top', fin.topBalances[0]?.user.nickname);
const csv = await call('GET', '/adminapi/finance/export.csv?days=30', { expect: 200 }); console.log('   csv lines', String(csv).split('\n').length, String(csv).split('\n')[0].slice(1));
// المحتوى
await call('POST', '/wallet/topup', { body: { amount: 50000 }, user: 'SA0000002', expect: 200 });
const ev = await call('POST', '/events', { body: { title: 'لقاء', startsAt: new Date(Date.now() + 86400000).toISOString(), tiers: [{ name: 'عادي', price: 1000, quantity: 10 }] }, user: 'SA0000002', expect: 200 });
await call('POST', '/wallet/topup', { body: { amount: 50000 }, user: 'SA0000003', expect: 200 });
await call('POST', '/events/' + ev.id + '/tickets', { body: { tierId: ev.tiers[0].id, qty: 1 }, user: 'SA0000003', expect: 200 });
const ct = await call('GET', '/adminapi/content', { expect: 200 }); console.log('   content events', ct.events.length, 'sold', ct.events[0].sold, 'listings', ct.listings.length);
await call('POST', '/adminapi/events/' + ev.id + '/cancel', { expect: 200 });
await call('POST', '/adminapi/events/' + ev.id + '/cancel', { expect: 409 });
await call('GET', '/wallet', { user: 'SA0000003', expect: 200 }).then(w => console.log('   khalid refunded balance', w.balance, 'last', w.recent[0].kind));
// الإعدادات
await call('GET', '/adminapi/settings', { expect: 200 }).then(s => console.log('   settings', s.testTopup, s.maxTopup, JSON.stringify(s.announcement)));
await call('POST', '/adminapi/settings', { body: { testTopup: false, maxTopup: 500000, announcement: 'صيانة الليلة' }, expect: 200 });
await call('POST', '/wallet/topup', { body: { amount: 1000 }, user: 'SA0000002', expect: 403 });   // شحن معطّل للعامة
await call('POST', '/wallet/topup', { body: { amount: 1000 }, user: 'SA0000001', expect: 200 });  // المدير يستطيع
await call('GET', '/settings/public', { user: null, expect: 200 }).then(s => console.log('   public', JSON.stringify(s)));
await call('POST', '/adminapi/settings', { body: { testTopup: true }, expect: 200 });
await call('POST', '/wallet/topup', { body: { amount: 600000 }, user: 'SA0000002', expect: 400 }); // فوق السقف الجديد
await call('POST', '/wallet/topup', { body: { amount: 400000 }, user: 'SA0000002', expect: 200 });
// السجل
await call('GET', '/adminapi/audit', { expect: 200 }).then(l => console.log('   audit', l.length, l.slice(0, 4).map(a => a.action).join(',')));
console.log(fails ? `\n${fails} FAILED` : '\nALL OK');
await app.close(); await pool.end();
