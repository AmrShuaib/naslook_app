// اختبارات منشورات الخريطة (server/map_posts.js): الإنشاء بأنواعه، تنظيف الطبقات وزر الإجراء، القوائم بالحدود، التعديل والإخفاء والتمديد،
// المشاهدة والإعجاب مع الإشعار، الحذف، وحجب الإدارة.
import Fastify from 'fastify';
import pg from 'pg';
import { cleanOverlays, cleanCta } from '../map_posts.js';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0';
let fails = 0;
const check = (cond, label, extra = '') => { if (!cond) fails++; console.log((cond ? 'OK  ' : 'FAIL') + ' ' + label + (extra ? ' ' + extra : '')); };
// ---- وحدات التنظيف
let ov = cleanOverlays([{ type: 'text', text: 'عرض خاص', x: 1.7, y: -2, scale: 9, rot: 0.3, color: '#FF0000', bg: 'red', align: 'x', font: 'hand' }, { type: 'sticker', text: '🔥' }, { type: 'bad' }, null, { type: 'text', text: '' }]);
check(ov.length === 2 && ov[0].x === 1 && ov[0].y === 0 && ov[0].scale === 5 && ov[0].bg === null && ov[0].align === 'center' && ov[0].font === 'hand' && ov[1].type === 'sticker', 'overlays cleaned/clamped', JSON.stringify(ov));
check(cleanOverlays(Array.from({ length: 40 }, () => ({ type: 'sticker', text: '⭐' }))).length === 30, 'overlays capped at 30');
check(cleanCta({ type: 'whatsapp', value: '+966 50-123-4567' })?.value === '+966501234567' && cleanCta({ type: 'whatsapp', value: '123' }) === null, 'whatsapp cta cleaned');
check(cleanCta({ type: 'link', value: 'javascript:alert(1)' }) === null && cleanCta({ type: 'link', value: 'https://x.com/a' })?.label === 'افتح الرابط', 'link cta validated');
check(cleanCta({ type: 'biz', value: 'biz-ikea', label: 'زورونا' })?.label === 'زورونا' && cleanCta({ type: 'nope' }) === null, 'biz cta + unknown');

const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("INSERT INTO users(id,nickname) VALUES('SA0000001','amr'),('SA0000002','sara'),('SA0000003','khalid') ON CONFLICT DO NOTHING");
for (const sql of ['DROP TABLE IF EXISTS map_post_likes, map_post_views, map_posts', 'DELETE FROM app_notifications', "INSERT INTO admins(user_id,granted_by) VALUES('SA0000001','test') ON CONFLICT DO NOTHING", 'DELETE FROM user_flags']) { try { await pool.query(sql); } catch { /* ignore */ } }
const auth = async (req) => req.headers['x-user'] || null;
const app = Fastify();
const dir = new URL('.', import.meta.url).pathname;
app.register((await import('../notify.js')).default, { pool, auth, pollMs: 3600000, opsDir: dir + 'ops' });
app.register((await import('../admin.js')).default, { pool, auth, webappDir: dir + 'webapp', opsDir: dir + 'ops' });
app.register((await import('../map_posts.js')).default, { pool, auth });
await app.ready(); await new Promise((r) => setTimeout(r, 600));
const call = async (method, url, { body = {}, user = 'SA0000001', expect } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json', host: 'naslife.app', 'x-forwarded-proto': 'https' }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url} -> ${r.statusCode}`, r.statusCode === expect ? '' : JSON.stringify(j).slice(0, 160));
  return j;
};
// ---- الإنشاء
await call('POST', '/mapposts', { body: { kind: 'image', lat: 21.5, lng: 39.2 }, user: 'SA0000002', expect: 400 });   // بلا وسائط
await call('POST', '/mapposts', { body: { kind: 'text', lat: 21.5, lng: 39.2 }, user: 'SA0000002', expect: 400 });    // نص فارغ
await call('POST', '/mapposts', { body: { kind: 'text', caption: 'x', lat: 95, lng: 39.2 }, user: 'SA0000002', expect: 400 });
await call('POST', '/mapposts', { body: { kind: 'text', caption: 'x', lat: 21.5, lng: 39.2 }, user: null, expect: 401 });
const p1 = await call('POST', '/mapposts', { body: { kind: 'image', mediaUrl: '/chat/media/a.jpg', caption: 'خصم 30٪ اليوم', overlays: [{ type: 'text', text: 'خصم 30٪', x: .5, y: .3, color: '#FFFFFF', bg: '#BF3A1E' }, { type: 'sticker', text: '🔥', x: .8, y: .2, scale: 1.5 }],
  tag: 'offer', title: 'عرض القهوة', price: 1500, cta: { type: 'whatsapp', value: '0501234567' }, lat: 21.5433, lng: 39.1728, placeName: 'الكورنيش', ttlHours: 72 }, user: 'SA0000002', expect: 200 });
check(p1.mediaUrl === 'https://naslife.app/chat/media/a.jpg' && p1.overlays.length === 2 && p1.tag === 'offer' && p1.price === 1500 && p1.cta.type === 'whatsapp' && p1.cta.value === '0501234567' && p1.cta.label === 'واتساب' && p1.user.nickname === 'sara' && p1.mine && !p1.expired, 'offer post created', JSON.stringify({ media: p1.mediaUrl, cta: p1.cta }));
const ttlH = (new Date(p1.expiresAt) - new Date(p1.createdAt)) / 3600000; check(Math.abs(ttlH - 72) < 0.1, 'ttl 72h', ttlH.toFixed(1));
const p2 = await call('POST', '/mapposts', { body: { kind: 'audio', mediaUrl: 'https://naslife.app/chat/media/v.weba', durationSec: 42.7, caption: 'رسالة صوتية', lat: 21.55, lng: 39.18, ttlHours: 999 }, user: 'SA0000003', expect: 200 });
check(p2.kind === 'audio' && p2.durationSec === 43 && p2.tag === 'moment', 'audio post, bad ttl → 24h');
const p3 = await call('POST', '/mapposts', { body: { kind: 'text', bg: '#0A6E78', overlays: [{ type: 'text', text: 'صباح الخير جدة' }], lat: 24.7, lng: 46.7 }, user: 'SA0000002', expect: 200 });   // الرياض
check(p3.kind === 'text' && p3.bg === '#0A6E78' && p3.mediaUrl === null, 'text post with bg');
await call('POST', '/mapposts', { body: { kind: 'video', mediaUrl: 'https://evil.example/x.mp4', lat: 21.5, lng: 39.2 }, user: 'SA0000002', expect: 200 }).then((p) => check(p.mediaUrl === 'https://evil.example/x.mp4', 'absolute external url kept as is (upload host enforced client-side)'));
// ---- القوائم
let list = await call('GET', '/mapposts?bbox=39.0,21.0,39.5,22.0', { user: null, expect: 200 });
check(list.some((p) => p.id === p1.id) && list.some((p) => p.id === p2.id) && !list.some((p) => p.id === p3.id), 'bbox filter (Riyadh excluded)', `${list.length}`);
list = await call('GET', '/mapposts?tag=offer', { user: 'SA0000003', expect: 200 }); check(list.length === 1 && list[0].id === p1.id && list[0].mine === false && list[0].liked === false, 'tag filter + flags for viewer');
list = await call('GET', '/mapposts/mine', { user: 'SA0000002', expect: 200 }); check(list.length === 3 && list.every((p) => p.mine), 'mine');
await call('GET', `/mapposts/${p1.id}`, { user: null, expect: 200 });
// ---- مشاهدة وإعجاب
let v = await call('POST', `/mapposts/${p1.id}/view`, { user: 'SA0000003', expect: 200 }); check(v.views === 1, 'first view counts');
v = await call('POST', `/mapposts/${p1.id}/view`, { user: 'SA0000003', expect: 200 }); check(v.views === 1, 'repeat view not counted');
v = await call('POST', `/mapposts/${p1.id}/view`, { user: 'SA0000002', expect: 200 }); check(v.views === 1, 'own view not counted');
let lk = await call('POST', `/mapposts/${p1.id}/like`, { user: 'SA0000003', expect: 200 }); check(lk.liked && lk.likes === 1, 'like');
const n = await call('GET', '/notify', { user: 'SA0000002', expect: 200 }); check(n.items[0]?.kind === 'post_like' && /khalid/.test(n.items[0].body) && n.items[0].data.postId === p1.id, 'like notifies owner', n.items[0]?.body);
lk = await call('POST', `/mapposts/${p1.id}/like`, { user: 'SA0000003', expect: 200 }); check(!lk.liked && lk.likes === 0, 'unlike toggles');
// ---- التعديل والإخفاء والتمديد
await call('PATCH', `/mapposts/${p1.id}`, { body: { caption: 'x' }, user: 'SA0000003', expect: 403 });
let e = await call('PATCH', `/mapposts/${p1.id}`, { body: { caption: 'خصم 40٪', overlays: [{ type: 'sticker', text: '⭐' }], price: null, cta: { type: 'link', value: 'https://naslife.app' }, ttlHours: 168 }, user: 'SA0000002', expect: 200 });
check(e.caption === 'خصم 40٪' && e.overlays.length === 1 && e.price === null && e.cta.type === 'link' && (new Date(e.expiresAt) - Date.now()) / 3600000 > 167, 'edit fields + extend', JSON.stringify(e.cta));
await call('PATCH', `/mapposts/${p1.id}`, { body: { ttlHours: 5 }, user: 'SA0000002', expect: 400 });
e = await call('PATCH', `/mapposts/${p1.id}`, { body: { status: 'hidden' }, user: 'SA0000002', expect: 200 }); check(e.status === 'hidden', 'hide');
check(!(await call('GET', '/mapposts', { user: null })).some((p) => p.id === p1.id), 'hidden not listed');
await call('GET', `/mapposts/${p1.id}`, { user: 'SA0000003', expect: 404 });
await call('GET', `/mapposts/${p1.id}`, { user: 'SA0000002', expect: 200 });
e = await call('PATCH', `/mapposts/${p1.id}`, { body: { status: 'active' }, user: 'SA0000002', expect: 200 }); check(e.status === 'active', 'unhide');
// ---- حجب الإدارة والحذف
await call('POST', `/mapposts/${p1.id}/block`, { user: 'SA0000003', expect: 403 });
let bl = await call('POST', `/mapposts/${p1.id}/block`, { expect: 200 }); check(bl.status === 'blocked', 'admin block');
await call('PATCH', `/mapposts/${p1.id}`, { body: { status: 'active' }, user: 'SA0000002', expect: 403 });
const n2 = await call('GET', '/notify', { user: 'SA0000002', expect: 200 }); check(n2.items[0]?.kind === 'post_blocked', 'block notifies owner');
bl = await call('POST', `/mapposts/${p1.id}/block`, { body: { hidden: false }, expect: 200 }); check(bl.status === 'active', 'admin unblock');
await call('DELETE', `/mapposts/${p2.id}`, { user: 'SA0000002', expect: 403 });
await call('DELETE', `/mapposts/${p2.id}`, { user: 'SA0000003', expect: 200 });
await call('GET', `/mapposts/${p2.id}`, { user: 'SA0000003', expect: 404 });
await call('DELETE', `/mapposts/${p3.id}`, { expect: 200 });   // المدير يحذف
console.log(fails ? `\n${fails} FAILURES` : '\nALL POSTS TESTS PASSED');
await app.close(); await pool.end(); process.exit(fails ? 1 : 0);
