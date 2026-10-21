// الموقع المباشر والردود المقترحة (server/chat_live.js): دورة بدء/دفع/قراءة/إيقاف، صلاحية الطرفين فقط، أخطاء التحقق، جلسة واحدة
// نشطة لكل زوج، الانقضاء والكنس، والاقتراحات: قواعد بلا مفتاح، نموذج وهمي يعيد مصفوفة JSON أو كلاماً فارغاً، وحدّ المعدّل.
import Fastify from 'fastify';
import pg from 'pg';
import { rulesFor, parseSuggestions, LIVE_MINUTES, SUGGEST_PER_MIN, SUGGEST_MAX_CHARS } from '../chat_live.js';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0';
let fails = 0;
const check = (c, l, extra = '') => { if (!c) fails++; console.log((c ? 'OK  ' : 'FAIL') + ' ' + l + (extra ? ' ' + extra : '')); };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const UUID_RE = /^[0-9a-f-]{36}$/i;

// ---- القواعد والتحليل وحدهما
{
  check(rulesFor([{ mine: false, text: 'السلام عليكم' }])[0] === 'وعليكم السلام ورحمة الله', 'rules: greeting → greeting replies');
  check(JSON.stringify(rulesFor([{ mine: false, text: 'تجي بكرة؟' }])) === JSON.stringify(['يناسبني', 'أي وقت يناسبك؟', 'خلني أتأكد']), 'rules: meet words win over the question mark', JSON.stringify(rulesFor([{ mine: false, text: 'تجي بكرة؟' }])));
  check(rulesFor([{ mine: false, text: 'هلاوين' }])[0] !== 'أرسل لك موقعي' && rulesFor([{ mine: false, text: 'يا هلا' }])[0] === 'هلا والله', 'rules: Arabic word bounds (no ASCII \\b)');
  check(JSON.stringify(rulesFor([{ mine: false, text: 'خلصت؟' }])) === JSON.stringify(['نعم', 'لا', 'خلني أتأكد']), 'rules: question mark → yes / no / let me check', JSON.stringify(rulesFor([{ mine: false, text: 'خلصت؟' }])));
  check(rulesFor([{ mine: false, text: 'بكم القهوة' }])[0] === 'كم السعر؟', 'rules: price words → price replies');
  check(rulesFor([{ mine: false, text: 'شكراً لك' }])[0] === 'العفو', 'rules: thanks');
  check(rulesFor([{ mine: false, text: 'وين انت الحين' }])[0] === 'أرسل لك موقعي', 'rules: location words');
  check(rulesFor([{ mine: false, text: 'السلام عليكم' }, { mine: true, text: 'وعليكم السلام' }])[0] === 'وعليكم السلام ورحمة الله', 'rules: uses the last peer message even when mine is last');
  const d = rulesFor([]); check(d.length === 3 && d[0] === 'تمام', 'rules: empty → defaults');
  check(rulesFor([{ mine: false, text: 'كلام عادي بلا نمط' }]).length === 3, 'rules: always three');
  check(rulesFor([{ mine: false, text: 'السَّلامُ عَلَيْكُم' }])[0] === 'وعليكم السلام ورحمة الله', 'rules: ignores tashkeel');
  check(parseSuggestions('["أكيد", "خلاص", "بعد شوي"]')?.join('|') === 'أكيد|خلاص|بعد شوي', 'parse: plain JSON array');
  check(parseSuggestions('هذه اقتراحاتي:\n["واحد","اثنان","ثلاثة","أربعة"]\nشكراً')?.length === 3, 'parse: array inside prose, capped at three');
  check(parseSuggestions('["a","a","b"]')?.join('|') === 'a|b', 'parse: duplicates removed');
  const long = parseSuggestions(`["${'ك'.repeat(80)}"]`); check(long && Array.from(long[0]).length === SUGGEST_MAX_CHARS, 'parse: each suggestion capped at 40 chars');
  check(parseSuggestions('garbage') === null && parseSuggestions('[]') === null && parseSuggestions('{"a":1}') === null && parseSuggestions('[1,2]') === null, 'parse: garbage → null');
}

// ---- التجهيز
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("INSERT INTO users(id,nickname) VALUES('SA0000001','amr'),('SA0000002','sara'),('SA0000003','khalid') ON CONFLICT (id) DO UPDATE SET nickname=EXCLUDED.nickname");
for (const sql of ['DROP TABLE IF EXISTS chat_live']) { try { await pool.query(sql); } catch { /* أول تشغيل */ } }
const auth = async (req) => req.headers['x-user'] || null;
delete globalThis.naslifeAskClaude;
const blockedPairs = new Set();
globalThis.naslifeIsBlocked = async (a, b) => blockedPairs.has(a + '|' + b) || blockedPairs.has(b + '|' + a);
const app = Fastify();
app.register((await import('../chat_live.js')).default, { pool, auth, sweepMs: 250 });
await app.ready(); await sleep(300);
const call = async (method, url, { body = {}, user = 'SA0000001', expect } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json', host: 'naslife.app' }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url} [${user}] -> ${r.statusCode}`, r.statusCode === expect ? '' : JSON.stringify(j).slice(0, 200));
  return j;
};

// ---- الحالة والتوثيق
const st = await call('GET', '/chat/live/status', { user: null, expect: 200 });
check(st.ok && JSON.stringify(st.minutes) === JSON.stringify(LIVE_MINUTES) && st.suggest?.ai === false && st.suggest.perMin === SUGGEST_PER_MIN, 'status: minutes, no AI key', JSON.stringify(st));
await call('POST', '/chat/live', { body: { peerId: 'SA0000002', minutes: 15 }, user: null, expect: 401 });
await call('POST', '/chat/suggest', { body: { peerId: 'SA0000002', messages: [] }, user: null, expect: 401 });

// ---- التحقق عند البدء
await call('POST', '/chat/live', { body: { peerId: 'nope', minutes: 15 }, expect: 400 });
await call('POST', '/chat/live', { body: { peerId: 'SA0000001', minutes: 15 }, expect: 400 });
const bm = await call('POST', '/chat/live', { body: { peerId: 'SA0000002', minutes: 20 }, expect: 400 });
check(bm.error === 'bad-minutes' && Array.isArray(bm.allowed), 'bad minutes names the allowed set');
blockedPairs.add('SA0000001|SA0000003');
await call('POST', '/chat/live', { body: { peerId: 'SA0000003', minutes: 15 }, expect: 403 });
blockedPairs.clear();

// ---- الدورة: بدء → دفع → قراءة → إيقاف
const t0 = Date.now();
const s1 = await call('POST', '/chat/live', { body: { peerId: 'sa0000002', minutes: 60 }, expect: 200 });
check(UUID_RE.test(s1.id) && s1.from === 'SA0000001' && s1.to === 'SA0000002' && s1.active === true, 'start returns id/from/to/active (peer id upper-cased)', JSON.stringify(s1));
const untilMs = Date.parse(s1.until); check(untilMs - t0 > 59 * 60000 && untilMs - t0 < 61 * 60000, 'until ≈ now + 60 min');
let g = await call('GET', `/chat/live/${s1.id}`, { user: 'SA0000002', expect: 200 });
check(g.lat === null && g.lng === null && g.at === null && g.active === true, 'peer reads the session before the first position: empty position, active');
await call('PUT', `/chat/live/${s1.id}`, { body: { lat: 21.54, lng: 39.17, accuracy: 12 }, expect: 200 });
g = await call('GET', `/chat/live/${s1.id}`, { user: 'SA0000002', expect: 200 });
check(g.lat === 21.54 && g.lng === 39.17 && g.accuracy === 12 && typeof g.at === 'string' && Date.now() - Date.parse(g.at) < 5000, 'peer sees the pushed position with a fresh timestamp', JSON.stringify(g));
g = await call('GET', `/chat/live/${s1.id}`, { user: 'SA0000001', expect: 200 });
check(g.lat === 21.54 && g.active === true, 'sharer can read his own session too');
const fast = await call('PUT', `/chat/live/${s1.id}`, { body: { lat: 21.541, lng: 39.171 }, expect: 429 });
check(fast.error === 'too-fast' && fast.retryInMs === 5000, 'a second push within 5 s is refused');
g = await call('GET', `/chat/live/${s1.id}`, { user: 'SA0000002', expect: 200 }); check(g.lat === 21.54, 'the refused push did not move the position');
// نرجّع وقت آخر تحديث للوراء ثم ندفع مرة أخرى
await pool.query("UPDATE chat_live SET updated_at = now() - interval '6 seconds' WHERE id=$1", [s1.id]);
await call('PUT', `/chat/live/${s1.id}`, { body: { lat: '21.55', lng: '39.18' }, expect: 200 });
g = await call('GET', `/chat/live/${s1.id}`, { user: 'SA0000002', expect: 200 }); check(g.lat === 21.55 && g.lng === 39.18 && g.accuracy === null, 'numeric strings accepted; accuracy omitted → null');

// ---- التحقق من الموقع
await pool.query("UPDATE chat_live SET updated_at = NULL WHERE id=$1", [s1.id]);
await call('PUT', `/chat/live/${s1.id}`, { body: { lat: 91, lng: 39 }, expect: 400 });
await call('PUT', `/chat/live/${s1.id}`, { body: { lat: 21, lng: -181 }, expect: 400 });
await call('PUT', `/chat/live/${s1.id}`, { body: { lat: 'x', lng: 39 }, expect: 400 });
await call('PUT', `/chat/live/${s1.id}`, { body: { lng: 39 }, expect: 400 });
const ba = await call('PUT', `/chat/live/${s1.id}`, { body: { lat: 21, lng: 39, accuracy: 9000 }, expect: 400 });
check(ba.error === 'bad-accuracy', 'accuracy above 5000 refused');
await call('PUT', `/chat/live/${s1.id}`, { body: { lat: 21, lng: 39, accuracy: -1 }, expect: 400 });

// ---- الطرفان فقط
await call('GET', `/chat/live/${s1.id}`, { user: 'SA0000003', expect: 404 });
await call('PUT', `/chat/live/${s1.id}`, { body: { lat: 21, lng: 39 }, user: 'SA0000003', expect: 404 });
await call('DELETE', `/chat/live/${s1.id}`, { user: 'SA0000003', expect: 404 });
const np = await call('PUT', `/chat/live/${s1.id}`, { body: { lat: 21, lng: 39 }, user: 'SA0000002', expect: 403 });
check(np.error === 'not-sharer', 'the peer cannot push a position');
await call('DELETE', `/chat/live/${s1.id}`, { user: 'SA0000002', expect: 403 });
await call('GET', '/chat/live/00000000-0000-4000-8000-000000000000', { expect: 404 });
await call('GET', '/chat/live/not-a-uuid', { expect: 404 });

// ---- جلسة واحدة نشطة لكل زوج
const s2 = await call('POST', '/chat/live', { body: { peerId: 'SA0000002', minutes: 15 }, expect: 200 });
check(s2.id !== s1.id && s2.active === true, 'a new session for the same pair starts');
g = await call('GET', `/chat/live/${s1.id}`, { user: 'SA0000002', expect: 200 });
check(g.active === false, 'the previous session for the pair is stopped');
const s3 = await call('POST', '/chat/live', { body: { peerId: 'SA0000001', minutes: 15 }, user: 'SA0000002', expect: 200 });
g = await call('GET', `/chat/live/${s2.id}`, { expect: 200 });
check(g.active === true && s3.active === true, 'the reverse direction is a different pair and does not stop it');
const n = (await pool.query("SELECT count(*)::int AS n FROM chat_live WHERE from_id='SA0000001' AND to_id='SA0000002' AND stopped_at IS NULL")).rows[0].n;
check(n === 1, 'exactly one open row per pair in the table', String(n));

// ---- الإيقاف
const en = await call('PUT', `/chat/live/${s1.id}`, { body: { lat: 21, lng: 39 }, expect: 409 });
check(en.error === 'ended', 'pushing to a stopped session → 409 ended');
await call('DELETE', `/chat/live/${s2.id}`, { expect: 200 });
g = await call('GET', `/chat/live/${s2.id}`, { user: 'SA0000002', expect: 200 });
check(g.active === false && g.id === s2.id, 'after DELETE the peer reads active:false (the row stays readable)');
await call('DELETE', `/chat/live/${s2.id}`, { expect: 200 });
const stoppedAt = (await pool.query('SELECT stopped_at FROM chat_live WHERE id=$1', [s2.id])).rows[0].stopped_at;
check(stoppedAt && Date.now() - new Date(stoppedAt).getTime() < 5000, 'DELETE is idempotent and keeps the first stopped_at');

// ---- الانقضاء والكنس
const s4 = await call('POST', '/chat/live', { body: { peerId: 'SA0000003', minutes: 480 }, expect: 200 });
check(Date.parse(s4.until) - Date.now() > 479 * 60000, '480 minutes accepted');
await pool.query("UPDATE chat_live SET until = now() - interval '1 second' WHERE id=$1", [s4.id]);
g = await call('GET', `/chat/live/${s4.id}`, { user: 'SA0000003', expect: 200 });
check(g.active === false, 'past until → active:false even before the sweep');
await call('PUT', `/chat/live/${s4.id}`, { body: { lat: 21, lng: 39 }, expect: 409 });
let row = (await pool.query('SELECT stopped_at FROM chat_live WHERE id=$1', [s4.id])).rows[0];
const swept = row.stopped_at ? 0 : await globalThis.naslifeChatLive.sweep();
row = (await pool.query('SELECT stopped_at, until FROM chat_live WHERE id=$1', [s4.id])).rows[0];
check(row.stopped_at && new Date(row.stopped_at).getTime() === new Date(row.until).getTime(), 'sweep closes expired rows at their until', `swept=${swept}`);
const s5 = await call('POST', '/chat/live', { body: { peerId: 'SA0000003', minutes: 15 }, expect: 200 });
await pool.query("UPDATE chat_live SET until = now() - interval '1 second' WHERE id=$1", [s5.id]);
await sleep(600);
row = (await pool.query('SELECT stopped_at FROM chat_live WHERE id=$1', [s5.id])).rows[0];
check(!!row.stopped_at, 'the periodic sweep (sweepMs) closes expired rows on its own');
check((await globalThis.naslifeChatLive.sweep()) === 0, 'nothing left to sweep');

// ---- الاقتراحات: قواعد بلا مفتاح
let sg = await call('POST', '/chat/suggest', { body: { peerId: 'SA0000002', messages: [{ mine: false, text: 'السلام عليكم' }] }, expect: 200 });
check(sg.source === 'rules' && sg.suggestions.length === 3 && sg.suggestions[0] === 'وعليكم السلام ورحمة الله', 'no key → rules, greeting', JSON.stringify(sg));
check(sg.suggestions.every((s) => typeof s === 'string' && s.length > 0 && Array.from(s).length <= SUGGEST_MAX_CHARS), 'each suggestion is a short string');
sg = await call('POST', '/chat/suggest', { body: { peerId: 'SA0000002', messages: [{ mine: false, text: 'بكم الكيلو؟' }] }, expect: 200 });
check(sg.suggestions[0] === 'كم السعر؟', 'price words → price suggestions');
sg = await call('POST', '/chat/suggest', { body: { peerId: 'SA0000002', messages: [] }, expect: 200 });
check(sg.source === 'rules' && sg.suggestions.length === 3, 'empty messages → default rules');
await call('POST', '/chat/suggest', { body: { peerId: 'x', messages: [] }, expect: 400 });
sg = await call('POST', '/chat/suggest', { body: { peerId: 'SA0000002', messages: 'nope' }, expect: 200 });
check(sg.suggestions.length === 3, 'non-array messages tolerated');

// ---- الاقتراحات مع نموذج وهمي
let prompts = [];
globalThis.naslifeAskClaude = async ({ system, user }) => { prompts.push({ system, user }); return 'تفضّل:\n["أكيد أجي", "خلاص اتفقنا", "بعد شوي أرد عليك"]'; };
const history = [{ mine: false, text: 'سلام يا amr' }, { mine: true, text: 'هلا sara' }, { mine: false, text: 'SA0000002 تجي بكرة؟ ' + 'ط'.repeat(500) }];
sg = await call('POST', '/chat/suggest', { body: { peerId: 'SA0000002', messages: history }, expect: 200 });
check(sg.source === 'ai' && sg.suggestions.join('|') === 'أكيد أجي|خلاص اتفقنا|بعد شوي أرد عليك', 'fake model array → ai suggestions', JSON.stringify(sg));
check(prompts.length === 1 && /أنا: هلا sara/.test(prompts[0].user) && /الطرف الآخر: سلام/.test(prompts[0].user), 'prompt labels turns as me / the other side');
const lastLine = prompts[0].user.split('\n').pop();
check(Array.from(lastLine).length <= 300 + 20 && !prompts[0].user.includes('ط'.repeat(301)), 'each message truncated to 300 chars before the model');
check(!prompts[0].user.includes('SA0000001') && !prompts[0].system.includes('SA0000002') && !/peerId|nickname/.test(prompts[0].user), 'no ids of the caller nor field names reach the model (text only)');
prompts = [];
globalThis.naslifeAskClaude = async ({ user }) => { prompts.push(user); return '["واحد"]'; };
sg = await call('POST', '/chat/suggest', { body: { peerId: 'SA0000002', messages: [{ mine: false, text: 'خلصت؟' }] }, expect: 200 });
check(sg.source === 'ai' && sg.suggestions.length === 3 && sg.suggestions[0] === 'واحد' && sg.suggestions[1] === 'نعم', 'a short model answer is padded from the rules');
globalThis.naslifeAskClaude = async () => 'آسف لا أستطيع المساعدة';
sg = await call('POST', '/chat/suggest', { body: { peerId: 'SA0000002', messages: [{ mine: false, text: 'خلصت؟' }] }, expect: 200 });
check(sg.source === 'rules' && sg.suggestions[0] === 'نعم', 'garbage from the model → rules');
globalThis.naslifeAskClaude = async () => { throw Object.assign(new Error('ai-not-configured'), { code: 400 }); };
sg = await call('POST', '/chat/suggest', { body: { peerId: 'SA0000002', messages: [{ mine: false, text: 'شكراً' }] }, expect: 200 });
check(sg.source === 'rules' && sg.suggestions[0] === 'العفو', 'model error (no key) → rules');
globalThis.naslifeAskClaude = async () => `["${'ك'.repeat(100)}", "b", "c", "d"]`;
sg = await call('POST', '/chat/suggest', { body: { peerId: 'SA0000002', messages: [{ mine: false, text: 'هلا' }] }, expect: 200 });
check(sg.source === 'ai' && sg.suggestions.length === 3 && Array.from(sg.suggestions[0]).length === SUGGEST_MAX_CHARS, 'model output limited: 40 chars each, three at most');
let asked = 0;
globalThis.naslifeAskClaude = async () => { asked++; return '["a","b","c"]'; };
sg = await call('POST', '/chat/suggest', { body: { peerId: 'SA0000002', messages: [{ mine: true, text: '' }, { mine: false, text: '   ' }] }, expect: 200 });
check(asked === 0 && sg.source === 'rules', 'blank-only history never calls the model');
const st2 = await call('GET', '/chat/live/status', { user: null, expect: 200 }); check(st2.suggest.ai === true, 'status reports the AI hook once present');

// ---- حدّ المعدّل: 20 في الدقيقة لكل مستخدم (المستخدم الثالث لم يطلب شيئاً بعد)
let okCount = 0, limited = null;
for (let i = 0; i < SUGGEST_PER_MIN + 2; i++) {
  const r = await app.inject({ method: 'POST', url: '/chat/suggest', headers: { 'x-user': 'SA0000003', 'content-type': 'application/json' }, payload: JSON.stringify({ peerId: 'SA0000001', messages: [{ mine: false, text: 'هلا' }] }) });
  if (r.statusCode === 200) okCount++; else if (limited == null) limited = { i, code: r.statusCode, body: r.json() };
}
check(okCount === SUGGEST_PER_MIN && limited?.code === 429 && limited.body.error === 'rate-limit' && limited.i === SUGGEST_PER_MIN, `rate limit: ${SUGGEST_PER_MIN} allowed per minute then 429`, JSON.stringify(limited));
const other = await call('POST', '/chat/suggest', { body: { peerId: 'SA0000003', messages: [{ mine: false, text: 'هلا' }] }, user: 'SA0000002', expect: 200 });
check(other.suggestions.length === 3, 'the limit is per user: another user still gets suggestions');

delete globalThis.naslifeAskClaude; delete globalThis.naslifeIsBlocked;
await app.close(); await pool.end();
console.log(fails ? `${fails} FAILED` : 'ALL OK');
process.exit(fails ? 1 : 0);
