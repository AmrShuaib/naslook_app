// تخصيص الرئيسية (server/layout.js): الحالة، الافتراضيات للضيف والمستخدم بلا صف، الحفظ والقراءة، المثبّت لا يُخفى،
// إسقاط المجهول وإلحاق الكتل الجديدة، الأجسام السيئة، تطبيع الشريط السفلي، تجاوز الإعدادات، الحذف، ومساعد الحذف العام.
import Fastify from 'fastify';
import pg from 'pg';
import { BLOCK_IDS, DEFAULT_ORDER, DEFAULT_NAV, NAV_IDS, defaults, pinned, normalise } from '../layout.js';
let fails = 0;
const check = (c, l, extra = '') => { if (!c) fails++; console.log((c ? 'OK  ' : 'FAIL') + ' ' + l + (extra ? ' ' + extra : '')); };
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// ---- وحدات خالصة (بلا إعدادات)
delete globalThis.naslifeSettings;
check(same(defaults().order, DEFAULT_ORDER) && same(defaults().nav, DEFAULT_NAV) && same(pinned(), ['announce']), 'built-in defaults without settings');
check(same(normalise({}).order, DEFAULT_ORDER) && same(normalise({}).nav, DEFAULT_NAV) && same(normalise({}).hidden, []), 'normalise of an empty layout equals the defaults');
check(same(normalise({ nav: ['me', 'home'] }).nav, ['home', 'circles', 'me']), 'nav with only anchors is padded to the minimum', JSON.stringify(normalise({ nav: ['me', 'home'] }).nav));

// ---- التجهيز
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
try { await pool.query('DROP TABLE IF EXISTS user_layouts'); } catch { /* first run */ }
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
app.register((await import('../layout.js')).default, { pool, auth });
await app.ready();
const call = async (method, url, { body = {}, user = 'SA0000001', expect } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json' }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url} [${user}] -> ${r.statusCode}`, r.statusCode === expect ? '' : String(typeof j === 'string' ? j : JSON.stringify(j)).slice(0, 160));
  return j;
};
const AMR = 'SA0000001', SARA = 'SA0000002';

// ---- الحالة
const st = await call('GET', '/layout/status', { user: null, expect: 200 });
check(st.ok === true && same(st.blocks, BLOCK_IDS) && same(st.nav, NAV_IDS), 'status lists block and nav ids');

// ---- الضيف والمستخدم بلا صف
let g = await call('GET', '/me/layout', { user: null, expect: 200 });
check(g.layout === null && same(g.defaults.order, DEFAULT_ORDER) && same(g.defaults.nav, DEFAULT_NAV) && same(g.pinned, ['announce']) && g.updatedAt === null, 'guest gets null layout with defaults and pinned', JSON.stringify(g));
g = await call('GET', '/me/layout', { expect: 200 });
check(g.layout === null && g.updatedAt === null && same(g.defaults.order, DEFAULT_ORDER), 'signed-in user without a row gets null layout');
await call('PUT', '/me/layout', { body: { order: ['quick'] }, user: null, expect: 401 });
await call('DELETE', '/me/layout', { user: null, expect: 401 });

// ---- حفظ كامل وقراءة
let p = await call('PUT', '/me/layout', { body: { order: ['market', 'jobs', 'announce', 'quick'], hidden: ['trending', 'biz'], nav: ['home', 'market', 'chats', 'me'], opts: { around: ['food', 'cafe'], market: ['new'] } }, expect: 200 });
check(p.ok === true && typeof p.updatedAt === 'string' && !Number.isNaN(Date.parse(p.updatedAt)), 'put returns ok and an iso timestamp', JSON.stringify(p));
const expOrder = ['announce', 'market', 'jobs', 'quick', 'around', 'trending', 'offers', 'open', 'circles', 'feed', 'events', 'biz'];
check(same(p.layout.order, expOrder), 'pinned first, then my order, then the missing blocks in default order', JSON.stringify(p.layout.order));
check(same(p.layout.hidden, ['trending', 'biz']) && same(p.layout.nav, ['home', 'market', 'chats', 'me']) && same(p.layout.opts, { around: ['food', 'cafe'], market: ['new'] }), 'hidden, nav and opts stored as sent');
g = await call('GET', '/me/layout', { expect: 200 });
check(same(g.layout, p.layout) && g.updatedAt === p.updatedAt && same(g.pinned, ['announce']), 'read back matches the put response');
check(BLOCK_IDS.every((id) => g.layout.order.includes(id)) && g.layout.order.length === BLOCK_IDS.length, 'stored order contains every known block once');

// ---- الحفظ الجزئي يبقي الباقي
p = await call('PUT', '/me/layout', { body: { nav: ['home', 'offers', 'me'] }, expect: 200 });
check(same(p.layout.nav, ['home', 'offers', 'me']) && same(p.layout.order, expOrder) && same(p.layout.hidden, ['trending', 'biz']) && same(p.layout.opts, { around: ['food', 'cafe'], market: ['new'] }), 'partial put keeps the other fields');

// ---- المثبّت لا يُخفى، والمجهول يُسقط، والمكرر يُزال
p = await call('PUT', '/me/layout', { body: { order: ['feed', 'shiny_new', 'feed', 'quick'], hidden: ['announce', 'feed', 'nope', 'feed'], nav: ['home', 'chats', 'chats', 'vr', 'me'], opts: { feed: ['a', 'a', ' b '], ghost: ['x'] } }, expect: 200 });
check(!p.layout.hidden.includes('announce') && same(p.layout.hidden, ['feed']), 'pinned id removed from hidden, duplicates and unknown dropped', JSON.stringify(p.layout.hidden));
check(p.layout.order[0] === 'announce' && p.layout.order[1] === 'feed' && p.layout.order[2] === 'quick' && !p.layout.order.includes('shiny_new') && new Set(p.layout.order).size === BLOCK_IDS.length, 'unknown and duplicate order ids dropped', JSON.stringify(p.layout.order));
check(same(p.layout.nav, ['home', 'chats', 'me']) && same(p.layout.opts, { feed: ['a', 'b'] }), 'nav and opts cleaned', JSON.stringify([p.layout.nav, p.layout.opts]));

// ---- كتل جديدة ومعرّفات قديمة في صف محفوظ من نسخة سابقة
await pool.query("UPDATE user_layouts SET layout=$2 WHERE user_id=$1", [AMR, JSON.stringify({ order: ['announce', 'legacy', 'quick', 'market'], hidden: ['legacy', 'quick'], nav: ['circles', 'me', 'oldtab'], opts: { quick: 'not-an-array' } })]);
g = await call('GET', '/me/layout', { expect: 200 });
check(same(g.layout.order, ['announce', 'quick', 'market', 'around', 'trending', 'offers', 'open', 'circles', 'feed', 'jobs', 'events', 'biz']), 'missing blocks appended in default order and legacy id dropped', JSON.stringify(g.layout.order));
check(same(g.layout.hidden, ['quick']) && same(g.layout.nav, ['home', 'circles', 'me']) && same(g.layout.opts, {}), 'stored nav forced to start with home and end with me', JSON.stringify([g.layout.hidden, g.layout.nav, g.layout.opts]));

// ---- أجسام سيئة
const bad = async (body, label) => { const r = await call('PUT', '/me/layout', { body, expect: 400 }); check(r.error === 'bad-layout', label, JSON.stringify(r)); };
await bad({ order: 'quick' }, 'order must be an array');
await bad({ hidden: { a: 1 } }, 'hidden must be an array');
await bad({ nav: 'home,me' }, 'nav must be an array');
await bad({ order: ['Bad Id!'] }, 'ids must match the id pattern');
await bad({ order: ['a'.repeat(33)] }, 'ids longer than 32 rejected');
await bad({ order: [1, 2] }, 'non-string ids rejected');
await bad({ hidden: Array.from({ length: 41 }, (_, i) => 'b' + i) }, 'more than 40 entries rejected');
await bad({ nav: ['circles', 'me'] }, 'nav without home rejected');
await bad({ nav: ['home', 'circles'] }, 'nav without me rejected');
await bad({ opts: ['x'] }, 'opts must be an object');
await bad({ opts: { quick: 'x' } }, 'opts values must be arrays');
await bad({ opts: { quick: ['x'.repeat(41)] } }, 'opts strings longer than 40 rejected');
await bad({ opts: { quick: Array.from({ length: 11 }, () => 'v') } }, 'more than 10 opts values rejected');
await bad({ opts: { 'Bad Key': ['v'] } }, 'opts keys must match the id pattern');
const rawBad = await app.inject({ method: 'PUT', url: '/me/layout', headers: { 'x-user': AMR, 'content-type': 'application/json' }, payload: '[1,2]' });
check(rawBad.statusCode === 400, 'array body rejected', String(rawBad.statusCode));
g = await call('GET', '/me/layout', { expect: 200 });
check(same(g.layout.hidden, ['quick']), 'bad payloads did not change the stored layout');

// ---- تطبيع الشريط السفلي
p = await call('PUT', '/me/layout', { body: { nav: ['me', 'market', 'home', 'chats'] }, expect: 200 });
check(same(p.layout.nav, ['home', 'market', 'chats', 'me']), 'home moved first and me last', JSON.stringify(p.layout.nav));
p = await call('PUT', '/me/layout', { body: { nav: ['home', 'circles', 'chats', 'market', 'offers', 'jobs', 'events', 'me'] }, expect: 200 });
check(same(p.layout.nav, ['home', 'circles', 'chats', 'market', 'offers', 'me']), 'nav clamped to six tabs', JSON.stringify(p.layout.nav));
p = await call('PUT', '/me/layout', { body: { nav: ['home', 'me', 'home'] }, expect: 200 });
check(same(p.layout.nav, ['home', 'circles', 'me']), 'nav padded to three tabs from the defaults', JSON.stringify(p.layout.nav));

// ---- تجاوز الإعدادات: ترتيب افتراضي وكتل مثبّتة من الإدارة
globalThis.naslifeSettings = { homeLayoutOrder: 'market, jobs,bogus,market', homeLayoutPinned: 'announce,quick' };
g = await call('GET', '/me/layout', { user: null, expect: 200 });
check(same(g.defaults.order, ['announce', 'quick', 'market', 'jobs', 'around', 'trending', 'offers', 'open', 'circles', 'feed', 'events', 'biz']) && same(g.pinned, ['announce', 'quick']), 'settings order and pinned applied to defaults', JSON.stringify([g.defaults.order, g.pinned]));
g = await call('GET', '/me/layout', { expect: 200 });
check(g.layout.order[0] === 'announce' && g.layout.order[1] === 'quick' && !g.layout.hidden.includes('quick'), 'newly pinned block moves first and leaves hidden', JSON.stringify([g.layout.order.slice(0, 3), g.layout.hidden]));
globalThis.naslifeSettings = { homeLayoutOrder: '', homeLayoutPinned: '' };
g = await call('GET', '/me/layout', { user: null, expect: 200 });
check(same(g.defaults.order, DEFAULT_ORDER) && same(g.pinned, []), 'empty settings mean built-in order and nothing pinned', JSON.stringify(g.pinned));
p = await call('PUT', '/me/layout', { body: { hidden: ['announce'] }, expect: 200 });
check(same(p.layout.hidden, ['announce']), 'announce can be hidden when nothing is pinned');
globalThis.naslifeSettings = { homeLayoutOrder: '', homeLayoutPinned: 'announce' };
g = await call('GET', '/me/layout', { expect: 200 });
check(same(g.layout.hidden, []), 'restoring the pin drops announce from hidden again');

// ---- الحذف يعيد الافتراضيات
await call('DELETE', '/me/layout', { expect: 200 });
g = await call('GET', '/me/layout', { expect: 200 });
check(g.layout === null && g.updatedAt === null, 'delete resets to null layout');
await call('DELETE', '/me/layout', { expect: 200 });

// ---- مساعد الحذف العام (لحذف الحساب)
await call('PUT', '/me/layout', { body: { hidden: ['biz'] }, user: SARA, expect: 200 });
check(typeof globalThis.naslifeLayoutDelete === 'function' && (await globalThis.naslifeLayoutDelete(SARA)) === true, 'naslifeLayoutDelete helper returns true');
g = await call('GET', '/me/layout', { user: SARA, expect: 200 });
check(g.layout === null, 'helper removed the row');
check((await globalThis.naslifeLayoutDelete('SA0000000')) === true, 'helper is idempotent for a missing row');

await app.close(); await pool.end();
console.log(fails ? `\n${fails} FAILED` : '\nALL LAYOUT TESTS PASSED');
process.exit(fails ? 1 : 0);
