// التوظيف (server/jobs.js): ملف التوظيف، محرك الصياغة (ذكاء اصطناعي ثم القالب)، النشر والمطابقة والحد الأسبوعي وحد الباقة،
// بطاقة العرض والقبول والأسئلة وكشف الهوية بعد الإجابة، التقديم بلا دعوة، لوحة المرشحين (مراحل، ملاحظات، مقابلات، إحصاءات،
// تصدير pro)، الإدارة (موافقة، إغلاق، باقات)، المسح الدوري، وبطاقة #job في المحادثة.
import Fastify from 'fastify';
import pg from 'pg';
import { scoreMatch, templateDraft, norm } from '../jobs.js';
process.env.WALLET_TEST_TOPUP = '1'; process.env.NASLIFE_HEALTH_BRIDGE = '0';
const dir = new URL('.', import.meta.url).pathname;
process.env.CHAT_MEDIA_DIR = dir + 'media_store';
let fails = 0;
const check = (c, l, extra = '') => { if (!c) fails++; console.log((c ? 'OK  ' : 'FAIL') + ' ' + l + (extra ? ' ' + extra : '')); };

// ---- وحدات خالصة
check(norm('الْقَهْوَة المختصّة') === 'القهوه المختصه', 'norm strips diacritics and unifies letters', norm('الْقَهْوَة المختصّة'));
const jobA = { title: 'باريستا', skills: ['قهوة مختصة', 'لاتيه آرت'], city: 'جدة', type: 'full', experience_min: 1, salary_max: 5000, department: 'المقهى' };
const s1 = scoreMatch(jobA, { titles: ['باريستا'], skills: ['قهوة مختصة', 'لاتيه ارت'], city: 'جدة', types: ['full'], experience_years: 2, salary_min: 4000, fields: ['مقاهي'] });
const s2 = scoreMatch(jobA, { titles: ['محاسب'], skills: ['اكسل'], city: 'الدمام', types: ['remote'], experience_years: 0, salary_min: 9000, fields: [] });
check(s1.score > 0.85 && s1.reasons.includes('المسمّى مطابق') && s1.reasons.includes('نفس المدينة'), 'strong match scores high with reasons', JSON.stringify(s1));
check(s2.score < 0.3, 'unrelated profile scores low', String(s2.score));
const td = templateDraft({ title: 'باريستا', bullets: ['تحضير القهوة المختصة', 'خدمة العملاء'], type: 'shift', city: 'جدة', bizName: 'مقهى ريف' });
check(td.source === 'template' && td.description.includes('مقهى ريف') && td.requirements.must.length === 2 && td.questions.some((q) => q.id === 'shift'), 'template draft builds description, requirements and shift question');

// ---- التجهيز
const pool = new pg.Pool({ host: '127.0.0.1', user: 'postgres', password: 'pg', database: 'naslife_test' });
await pool.query("CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, nickname TEXT, avatar_url TEXT, is_admin BOOLEAN DEFAULT false, created_at TIMESTAMPTZ DEFAULT now())");
await pool.query("INSERT INTO users(id,nickname) VALUES('SA0000001','amr'),('SA0000002','sara'),('SA0000003','khalid'),('SA0000004','nora'),('SA0000005','majed'),('SA0000009','admin') ON CONFLICT (id) DO UPDATE SET nickname=EXCLUDED.nickname");
for (const sql of ['DROP TABLE IF EXISTS job_profiles, jobs, job_matches, job_notes, job_events, job_interviews, job_plans', "DELETE FROM biz_staff WHERE biz_id LIKE 'job-%'", "DELETE FROM biz WHERE id LIKE 'job-%'", 'DELETE FROM app_notifications']) { try { await pool.query(sql); } catch { /* first run */ } }
const auth = async (req) => req.headers['x-user'] || null;
globalThis.naslifeIsAdmin = async (uid) => uid === 'SA0000009';
globalThis.naslifeSettings = { jobsEnabled: true, jobsFreeActive: 1, jobsWeeklyCap: 5, jobsMinScore: 0.45, jobsRequireApproval: false };
let aiCalls = 0;
globalThis.naslifeAskClaude = async ({ system, user }) => { aiCalls++; if (!system.includes('JSON') || !user.includes('باريستا')) throw new Error('bad-prompt'); return 'هذه المسودة:\n{"title":"باريستا محترف","titleEn":"Barista","description":"' + 'نبحث عن باريستا يحب القهوة المختصة ويجيد التعامل مع الزبائن. '.repeat(3) + '","descriptionEn":"We are hiring a barista.","requirements":{"must":["خبرة سنة في القهوة المختصة"],"nice":["لاتيه آرت"]},"skills":["قهوة مختصة","لاتيه آرت","خدمة عملاء"],"questions":[{"id":"start","text":"متى تبدأ؟","kind":"choice","options":["فوراً","خلال شهر"],"required":true},{"id":"yrs","text":"سنوات الخبرة؟","kind":"number","required":true},{"id":"night","text":"ورديات مسائية؟","kind":"yesno","required":false}]}'; };
const app = Fastify();
app.register((await import('../notify.js')).default, { pool, auth, pollMs: 3600000, opsDir: dir + 'ops' });
app.register((await import('../commerce.js')).default, { pool, auth });
app.register((await import('../chat_tools.js')).default, { pool, auth });
app.register((await import('../business.js')).default, { pool, auth });
app.register((await import('../chat_cards.js')).default, { pool, auth });
app.register((await import('../jobs.js')).default, { pool, auth, sweepMs: 0 });
await app.ready(); await new Promise((r) => setTimeout(r, 400));
const call = async (method, url, { body = {}, user = 'SA0000001', expect, raw = false } = {}) => {
  const r = await app.inject({ method, url, headers: { ...(user ? { 'x-user': user } : {}), 'content-type': 'application/json' }, payload: method === 'GET' ? undefined : JSON.stringify(body) });
  let j; try { j = raw ? r.body : r.json(); } catch { j = r.body; }
  if (expect != null) check(r.statusCode === expect, `${method} ${url} [${user}] -> ${r.statusCode}`, r.statusCode === expect ? '' : String(typeof j === 'string' ? j : JSON.stringify(j)).slice(0, 160));
  return j;
};
const notes = async (kind, user) => (await pool.query("SELECT user_id, title, body, data FROM app_notifications WHERE kind=$1 AND user_id=$2 ORDER BY created_at", [kind, user])).rows;
const OWNER = 'SA0000001', SARA = 'SA0000002', KHALID = 'SA0000003', NORA = 'SA0000004', MAJED = 'SA0000005', ADMIN = 'SA0000009';

// ---- الدائرة وفريق التوظيف
const biz = await call('POST', '/biz', { body: { name: 'Reef Cafe', nameAr: 'مقهى ريف', category: 'cafe', sector: 'قهوة مختصة', lat: 21.5433, lng: 39.1728, address: 'الروضة، جدة' }, expect: 200 });
await pool.query("UPDATE biz SET id='job-reef' WHERE id=$1", [biz.id]); const B = 'job-reef';
await call('POST', `/biz/${B}/team`, { body: { userId: SARA, role: 'hr' }, expect: 200 });
const team = await call('GET', `/biz/${B}/team`, { expect: 200 });
check(team.staff.some((s) => s.user.id === SARA && s.role === 'hr'), 'hr role accepted by business team route');
await call('GET', `/biz/${B}/manage/jobs`, { user: KHALID, expect: 403 });
let m = await call('GET', `/biz/${B}/manage/jobs`, { user: SARA, expect: 200 });
check(m.role === 'hr' && m.plan.plan === 'free' && m.plan.freeActive === 1 && m.aiAvailable === true && m.team.length === 2, 'hr sees the jobs board with plan and team', JSON.stringify([m.role, m.plan]));

// ---- ملفات التوظيف
await call('PUT', '/jobs/profile', { body: { titles: [], city: 'جدة' }, user: KHALID, expect: 400 });
await call('PUT', '/jobs/profile', { body: { titles: ['باريستا'], salaryMin: 5000, salaryMax: 4000 }, user: KHALID, expect: 400 });
let p = await call('PUT', '/jobs/profile', { body: { titles: ['باريستا', 'مساعد مقهى'], fields: ['مقاهي'], city: 'جدة', districts: ['الروضة'], types: ['full', 'shift'], experienceYears: 2, education: 'diploma', skills: ['قهوة مختصة', 'لاتيه آرت', 'خدمة عملاء'], salaryMin: 4000, availability: 'now', summary: 'باريستا منذ سنتين', cvUrl: '/chat/media/cv1.pdf', cvName: 'khalid-cv.pdf' }, user: KHALID, expect: 200 });
check(p.profile.titles.length === 2 && p.profile.types.includes('shift') && p.profile.cvName === 'khalid-cv.pdf' && p.profile.active === true, 'job profile saved');
await call('PUT', '/jobs/profile', { body: { titles: ['محاسبة'], city: 'جدة', skills: ['اكسل'], types: ['full'], experienceYears: 3 }, user: NORA, expect: 200 });
await call('PUT', '/jobs/profile', { body: { titles: ['باريستا'], city: 'الدمام', skills: ['قهوة مختصة'], types: ['full'], experienceYears: 1 }, user: MAJED, expect: 200 });
p = await call('GET', '/jobs/profile', { user: KHALID, expect: 200 });
check(p.profile.city === 'جدة' && p.pending === 0 && p.types.length === 6, 'profile read with enums');

// ---- محرك الصياغة: الذكاء الاصطناعي ثم القالب
await call('POST', `/biz/${B}/manage/jobs/draft`, { body: { bullets: ['x'] }, expect: 400 });
let d = await call('POST', `/biz/${B}/manage/jobs/draft`, { body: { title: 'باريستا', bullets: ['تحضير القهوة المختصة', 'خدمة الزبائن'], type: 'shift' }, user: SARA, expect: 200 });
check(d.source === 'ai' && d.title === 'باريستا محترف' && d.questions.length === 3 && d.questions[0].kind === 'choice' && d.skills.length === 3 && aiCalls === 1, 'ai draft parsed from Claude JSON', JSON.stringify([d.source, d.title, d.questions.length]));
const savedAsk = globalThis.naslifeAskClaude; globalThis.naslifeAskClaude = async () => { throw new Error('ai-failed'); };
d = await call('POST', `/biz/${B}/manage/jobs/draft`, { body: { title: 'باريستا', bullets: ['تحضير القهوة'], type: 'full' }, expect: 200 });
check(d.source === 'template' && d.aiError === 'ai-failed' && d.description.includes('مقهى ريف'), 'template fallback when the ai call fails', JSON.stringify([d.source, d.aiError]));
delete globalThis.naslifeAskClaude;
d = await call('POST', `/biz/${B}/manage/jobs/draft`, { body: { title: 'باريستا', bullets: [], useAi: false }, expect: 200 });
check(d.source === 'template' && d.aiError === null && d.questions.length >= 4, 'template when no ai configured');
globalThis.naslifeAskClaude = savedAsk;

// ---- إنشاء عرض، معاينة المطابقة، نشر ومطابقة
const questions = [{ id: 'start', text: 'متى تبدأ؟', kind: 'choice', options: ['فوراً', 'خلال شهر'], required: true }, { id: 'yrs', text: 'سنوات الخبرة؟', kind: 'number', required: true }, { id: 'night', text: 'ورديات مسائية؟', kind: 'yesno', required: false }, { id: 'about', text: 'عرّفنا بنفسك', kind: 'text', required: false }];
await call('POST', `/biz/${B}/manage/jobs`, { body: { title: 'ب' }, expect: 400 });
let job = await call('POST', `/biz/${B}/manage/jobs`, { body: { title: 'باريستا', department: 'المقهى', description: 'نبحث عن باريستا يحب القهوة المختصة ويجيد التعامل مع الزبائن في فرعنا بالروضة.', requirements: { must: ['خبرة سنة'], nice: ['لاتيه آرت'] }, skills: ['قهوة مختصة', 'لاتيه آرت'], type: 'full', experienceMin: 1, salaryMin: 4000, salaryMax: 5500, salaryVisible: true, openings: 1, questions, assigneeId: SARA, draftSource: 'ai' }, user: SARA, expect: 200 });
check(job.status === 'draft' && job.city === 'جدة' && job.assigneeId === SARA && job.questions.length === 4 && job.counts.sent === 0, 'job created as draft with city inferred from address', JSON.stringify([job.status, job.city]));
await call('POST', `/biz/${B}/manage/jobs`, { body: { title: 'كاشير', assigneeId: KHALID }, expect: 400 });
let pv = await call('GET', `/biz/${B}/manage/jobs/${job.id}/preview-match`, { expect: 200 });
check(pv.strong === 1 && pv.good === 0 && pv.profiles === 2, 'preview counts one strong match in the same city', JSON.stringify(pv));
pv = await call('POST', `/biz/${B}/manage/jobs/preview-match`, { body: { title: 'باريستا', skills: ['قهوة مختصة'], type: 'remote' }, expect: 200 });
check(pv.profiles === 3 && pv.strong + pv.good === 2, 'unsaved preview for a remote job counts both cities', JSON.stringify(pv));
job = await call('POST', `/biz/${B}/manage/jobs/${job.id}/publish`, { expect: 200 });
check(job.status === 'open' && job.matched.sent === 1 && job.counts.sent === 1, 'publish matched and sent one card', JSON.stringify(job.matched));
const n1 = await notes('job_offer', KHALID);
check(n1.length === 1 && n1[0].data.jobId === job.id && n1[0].title.includes('باريستا'), 'khalid notified with the job offer');
check((await notes('job_offer', NORA)).length === 0 && (await notes('job_offer', MAJED)).length === 0, 'unrelated and other-city profiles were not matched');
const J = job.id;
// حد الباقة المجانية (١ نشط)
let job2 = await call('POST', `/biz/${B}/manage/jobs`, { body: { title: 'كاشير', description: 'كاشير لفرعنا في الروضة بدوام كامل مع خبرة في أنظمة نقاط البيع.', skills: ['كاشير'], publish: true }, expect: 402 });
check(job2.error === 'plan-limit' && job2.freeActive === 1, 'free plan blocks a second active job');
await call('PUT', `/adminapi/jobs/plans/${B}`, { body: { plan: 'pro', months: 2 }, user: KHALID, expect: 403 });
const plan = await call('PUT', `/adminapi/jobs/plans/${B}`, { body: { plan: 'pro', months: 2 }, user: ADMIN, expect: 200 });
check(plan.plan === 'pro' && plan.until, 'admin granted pro');
job2 = await call('POST', `/biz/${B}/manage/jobs`, { body: { title: 'كاشير', description: 'كاشير لفرعنا في الروضة بدوام كامل مع خبرة في أنظمة نقاط البيع.', skills: ['كاشير'], publish: true }, expect: 200 });
check(job2.status === 'open' && job2.matched.sent === 0, 'pro plan publishes; no profile matches a cashier');

// ---- العام
let pub = await call('GET', '/jobs', { user: null, expect: 200 });
check(pub.items.length === 2 && pub.items.every((j) => j.biz && j.biz.id === B) && pub.items.find((j) => j.id === J).salaryMax === 5500, 'public list shows open jobs with biz summary and visible salary');
pub = await call('GET', '/jobs?q=باريستا', { user: KHALID, expect: 200 });
check(pub.items.length === 1 && pub.items[0].mine?.status === 'sent', 'search filters and marks my match');
const hiring = await call('GET', '/jobs/hiring', { user: null, expect: 200 });
check(hiring.items.length === 1 && hiring.items[0].bizId === B && hiring.items[0].open === 2, 'hiring circles list');
const bj = await call('GET', `/biz/${B}/jobs`, { user: null, expect: 200 });
check(bj.items.length === 2, 'circle jobs list');
let pj = await call('GET', `/jobs/${J}`, { user: null, expect: 200 });
check(pj.title === 'باريستا' && pj.questions === undefined && pj.biz.nameAr === 'مقهى ريف', 'public job hides questions for guests');
pj = await call('GET', `/jobs/${J}`, { user: OWNER, expect: 200 });
check(Array.isArray(pj.questions) && pj.questions.length === 4, 'hiring team sees questions on the public route');
const card = await call('GET', `/chat/cards?refs=${encodeURIComponent('#job/' + J)}`, { user: KHALID, expect: 200 });
const cardVal = Object.values(card.refs ?? card)[0];
check(cardVal && cardVal.type === 'job' && cardVal.title === 'باريستا' && cardVal.subtitle.includes('مقهى ريف') && Number(cardVal.salaryMax) === 5500, 'chat card #job resolves', JSON.stringify(cardVal));

// ---- صندوق العروض: عرض، قبول، أسئلة، كشف الهوية
let inbox = await call('GET', '/jobs/inbox', { user: KHALID, expect: 200 });
check(inbox.pending === 1 && inbox.items[0].status === 'sent' && inbox.items[0].job.title === 'باريستا' && inbox.items[0].assignee.id === SARA && inbox.items[0].questions.length === 4, 'inbox lists the offer card with assignee');
const M = inbox.items[0].id;
await call('GET', `/jobs/offers/${M}`, { user: NORA, expect: 404 });
let off = await call('GET', `/jobs/offers/${M}`, { user: KHALID, expect: 200 });
check(off.status === 'viewed' && off.viewedAt, 'opening the offer marks it viewed');
let cands = await call('GET', `/biz/${B}/manage/jobs/${J}/candidates`, { user: SARA, expect: 200 });
check(cands.items.length === 1 && cands.items[0].anonymous === true && cands.items[0].user === undefined && cands.items[0].label === 'مرشح #1' && cands.items[0].status === 'viewed', 'candidate stays anonymous before answering');
await call('PATCH', `/biz/${B}/manage/jobs/${J}/candidates/${M}`, { body: { stage: 'interview' }, user: SARA, expect: 409 });
await call('POST', `/jobs/offers/${M}/later`, { user: KHALID, expect: 200 });
inbox = await call('GET', '/jobs/inbox', { user: KHALID, expect: 200 });
check(inbox.pending === 0 && inbox.items.length === 1 && inbox.items[0].status === 'later', 'later keeps the card but not pending');
let acc = await call('POST', `/jobs/offers/${M}/accept`, { user: KHALID, expect: 200 });
check(acc.status === 'accepted' && acc.questions.length === 4 && acc.chatWith === null, 'accept returns the screening questions');
check((await notes('job_accept', SARA)).length === 1 && (await notes('job_accept', OWNER)).length === 1 && (await notes('job_accept', SARA))[0].body.includes('مرشح #1'), 'assignee and owner notified anonymously on accept');
await call('POST', `/jobs/offers/${M}/accept`, { user: KHALID, expect: 409 });
await call('POST', `/jobs/offers/${M}/answers`, { body: { answers: [{ id: 'start', value: 'فوراً' }] }, user: KHALID, expect: 400 });
await call('POST', `/jobs/offers/${M}/answers`, { body: { answers: [{ id: 'start', value: 'غداً' }, { id: 'yrs', value: 2 }] }, user: KHALID, expect: 400 });
let ans = await call('POST', `/jobs/offers/${M}/answers`, { body: { answers: [{ id: 'start', value: 'فوراً' }, { id: 'yrs', value: '2' }, { id: 'night', value: 'yes' }, { id: 'about', value: 'أحب القهوة' }] }, user: KHALID, expect: 200 });
check(ans.ok === true && ans.chatWith.id === SARA, 'answers accepted and chat partner is the hr assignee');
check((await notes('job_answers', SARA)).length === 1, 'assignee notified with answers');
await call('POST', `/jobs/offers/${M}/answers`, { body: { answers: [] }, user: KHALID, expect: 409 });
cands = await call('GET', `/biz/${B}/manage/jobs/${J}/candidates`, { user: SARA, expect: 200 });
const c1 = cands.items[0];
check(c1.anonymous === false && c1.user.nickname === 'khalid' && c1.profile.cvName === 'khalid-cv.pdf' && c1.answers.length === 4 && c1.answers.find((a) => a.id === 'night').value === true && c1.answers.find((a) => a.id === 'yrs').value === 2 && c1.stage === 'answered', 'identity, profile and typed answers revealed after answering', JSON.stringify(c1.answers));
let mine = await call('GET', '/jobs/mine', { user: KHALID, expect: 200 });
check(mine.active.length === 1 && mine.active[0].answers.length === 4 && mine.history.length === 0, 'my applications lists the active one');

// ---- التقديم بلا دعوة (نورا)
await call('POST', `/jobs/${J}/apply`, { user: OWNER, expect: 400 });
await pool.query("DELETE FROM job_profiles WHERE user_id=$1", [NORA]);
await call('POST', `/jobs/${J}/apply`, { user: NORA, expect: 409 });
await call('PUT', '/jobs/profile', { body: { titles: ['محاسبة'], city: 'جدة', skills: ['اكسل'], types: ['full'], experienceYears: 3 }, user: NORA, expect: 200 });
let ap = await call('POST', `/jobs/${J}/apply`, { user: NORA, expect: 200 });
check(ap.status === 'accepted' && ap.questions.length === 4 && ap.matchId, 'apply without invitation creates an accepted match');
await call('POST', `/jobs/${J}/apply`, { user: NORA, expect: 409 });
check((await notes('job_apply', SARA)).length === 1, 'hr notified about the applicant');
await call('POST', `/jobs/offers/${ap.matchId}/answers`, { body: { answers: [{ id: 'start', value: 'خلال شهر' }, { id: 'yrs', value: 3 }] }, user: NORA, expect: 200 });
cands = await call('GET', `/biz/${B}/manage/jobs/${J}/candidates`, { user: OWNER, expect: 200 });
check(cands.items.length === 2 && cands.items.find((c) => c.id === ap.matchId).source === 'apply' && cands.counts.answered === 2, 'board shows both candidates');

// ---- لوحة المرشحين: مراحل، ملاحظات، مقابلات، إحصاءات، تصدير
let st = await call('PATCH', `/biz/${B}/manage/jobs/${J}/candidates/${M}`, { body: { stage: 'interview', assigneeId: SARA }, user: OWNER, expect: 200 });
check(st.stage === 'interview' && st.assignee.id === SARA, 'stage and assignee updated');
check((await notes('job_stage', KHALID)).length === 1 && (await notes('job_stage', KHALID))[0].title.includes('مقابلة'), 'candidate notified about the interview stage');
await call('PATCH', `/biz/${B}/manage/jobs/${J}/candidates/${M}`, { body: { stage: 'weird' }, user: OWNER, expect: 400 });
await call('PATCH', `/biz/${B}/manage/jobs/${J}/candidates/${M}`, { body: { assigneeId: KHALID }, user: OWNER, expect: 400 });
const note = await call('POST', `/biz/${B}/manage/jobs/${J}/candidates/${M}/notes`, { body: { text: 'ممتاز في المقابلة الهاتفية', rating: 5 }, user: SARA, expect: 200 });
await call('POST', `/biz/${B}/manage/jobs/${J}/candidates/${M}/notes`, { body: { rating: 3 }, user: OWNER, expect: 200 });
await call('POST', `/biz/${B}/manage/jobs/${J}/candidates/${M}/notes`, { body: {}, user: OWNER, expect: 400 });
let det = await call('GET', `/biz/${B}/manage/jobs/${J}/candidates/${M}`, { user: SARA, expect: 200 });
check(det.notes.length === 2 && det.rating === 4 && det.notesCount === 2 && det.events.some((e) => e.kind === 'stage.changed') && det.events.some((e) => e.kind === 'match.answered'), 'candidate detail with notes, average rating and timeline', JSON.stringify([det.rating, det.notesCount]));
await call('DELETE', `/biz/${B}/manage/jobs/${J}/candidates/${M}/notes/${note.id}`, { user: SARA, expect: 200 });
const at = new Date(Date.now() + 5 * 3600000).toISOString();
await call('POST', `/biz/${B}/manage/jobs/${J}/candidates/${M}/interviews`, { body: { at: '2020-01-01T10:00:00Z' }, user: SARA, expect: 400 });
const iv = await call('POST', `/biz/${B}/manage/jobs/${J}/candidates/${M}/interviews`, { body: { at, mode: 'onsite', place: 'فرع الروضة', note: 'أحضر بورتفوليو' }, user: SARA, expect: 200 });
check(iv.status === 'scheduled' && iv.place === 'فرع الروضة', 'interview scheduled');
check((await notes('job_interview', KHALID)).length === 1 && (await notes('job_interview', KHALID))[0].body.includes('فرع الروضة'), 'candidate notified about the interview');
mine = await call('GET', '/jobs/mine', { user: KHALID, expect: 200 });
check(mine.active[0].interview?.place === 'فرع الروضة' && mine.active[0].stage === 'interview', 'candidate sees the interview on the application');
await call('POST', `/biz/${B}/manage/jobs/${J}/candidates/${ap.matchId}/interviews`, { body: { at }, user: KHALID, expect: 403 });
const sw = await call('POST', '/adminapi/jobs/sweep', { user: ADMIN, expect: 200 });
check(sw.reminded === 1 && (await notes('job_interview', KHALID)).length === 2 && (await notes('job_interview', SARA)).length === 1, 'sweep sends the 24h reminder once', JSON.stringify(sw));
check((await call('POST', '/adminapi/jobs/sweep', { user: ADMIN, expect: 200 })).reminded === 0, 'reminder not repeated');
await call('PATCH', `/biz/${B}/manage/jobs/${J}/candidates/${M}/interviews/${iv.id}`, { body: { status: 'done' }, user: SARA, expect: 200 });
let stats = await call('GET', `/biz/${B}/manage/jobs/${J}/stats`, { user: OWNER, expect: 200 });
const fn = Object.fromEntries(stats.funnel.map((f) => [f.id, f.n]));
check(fn.sent === 2 && fn.accepted === 2 && fn.answered === 2 && fn.interview === 1 && fn.hired === 0 && stats.avgDaysToAnswer != null, 'job funnel', JSON.stringify(fn));
const ov = await call('GET', `/biz/${B}/manage/jobs/stats`, { user: SARA, expect: 200 });
check(ov.open === 2 && ov.candidates === 2 && ov.answered === 2 && ov.plan.plan === 'pro', 'circle overview stats', JSON.stringify(ov));
const csv = await call('GET', `/biz/${B}/manage/jobs/${J}/export`, { user: OWNER, expect: 200, raw: true });
check(csv.startsWith('﻿"المرشح"') && csv.includes('khalid') && csv.includes('nora') && csv.includes('"نعم"') && csv.split('\n').length === 3, 'csv export for pro');
await call('PUT', `/adminapi/jobs/plans/${B}`, { body: { plan: 'free' }, user: ADMIN, expect: 200 });
await call('GET', `/biz/${B}/manage/jobs/${J}/export`, { user: OWNER, expect: 402 });
// تعيين يملأ الشاغر الوحيد فيغلق العرض
st = await call('PATCH', `/biz/${B}/manage/jobs/${J}/candidates/${M}`, { body: { stage: 'hired' }, user: OWNER, expect: 200 });
check(st.stage === 'hired' && (await notes('job_stage', KHALID)).length === 2, 'hired stage notifies the candidate');
let jl = await call('GET', `/biz/${B}/manage/jobs`, { user: OWNER, expect: 200 });
check(jl.items.find((j) => j.id === J).status === 'filled', 'job auto-filled when openings are hired', jl.items.find((j) => j.id === J).status);
mine = await call('GET', '/jobs/mine', { user: KHALID, expect: 200 });
check(mine.history.length === 1 && mine.history[0].stage === 'hired' && mine.active.length === 0, 'hired application moves to history');
await call('POST', `/jobs/offers/${M}/withdraw`, { user: KHALID, expect: 409 });
await call('POST', `/jobs/offers/${ap.matchId}/withdraw`, { user: NORA, expect: 200 });
check((await notes('job_stage', SARA)).length === 1, 'withdrawal notifies the team');

// ---- الحد الأسبوعي، الرفض، الإغلاق
globalThis.naslifeSettings.jobsWeeklyCap = 1; globalThis.naslifeSettings.jobsFreeActive = 5;
const job3 = await call('POST', `/biz/${B}/manage/jobs`, { body: { title: 'باريستا مسائي', description: 'باريستا للفترة المسائية في فرع الروضة، خبرة في القهوة المختصة وخدمة الزبائن.', skills: ['قهوة مختصة'], type: 'shift', publish: true }, expect: 200 });
check(job3.status === 'open' && job3.matched.sent === 0 && job3.matched.considered === 1, 'weekly cap blocks a second card to the same user', JSON.stringify(job3.matched));
globalThis.naslifeSettings.jobsWeeklyCap = 5;
await pool.query("UPDATE job_matches SET sent_at = now() - interval '8 days' WHERE user_id=$1", [KHALID]);
await pool.query("UPDATE jobs SET last_matched_at = now() - interval '1 hour' WHERE id=$1", [job3.id]);
const sw2 = await call('POST', '/adminapi/jobs/sweep', { user: ADMIN, expect: 200 });
check(sw2.matched === 1, 'sweep matches once the weekly window passes', JSON.stringify(sw2));
inbox = await call('GET', '/jobs/inbox', { user: KHALID, expect: 200 });
const M3 = inbox.items.find((i) => i.jobId === job3.id)?.id;
check(!!M3 && inbox.pending === 1, 'new card in the inbox');
await call('POST', `/jobs/offers/${M3}/decline`, { body: { reason: 'الدوام لا يناسبني' }, user: KHALID, expect: 200 });
await call('POST', `/jobs/offers/${M3}/decline`, { user: KHALID, expect: 409 });
stats = await call('GET', `/biz/${B}/manage/jobs/${job3.id}/stats`, { user: OWNER, expect: 200 });
check(stats.declines.length === 1 && stats.declines[0].reason === 'الدوام لا يناسبني', 'decline reasons aggregated');
acc = await call('POST', `/jobs/offers/${M3}/accept`, { user: KHALID, expect: 200 });
check(acc.status === 'answered' && acc.chatWith.id === OWNER, 'a declined card can be accepted later; no questions means answered immediately with the owner as contact');
await call('POST', `/biz/${B}/manage/jobs/${job2.id}/close`, { body: { filled: false }, expect: 200 });
await call('GET', `/jobs/${job2.id}`, { user: NORA, expect: 404 });
await call('GET', `/jobs/${job2.id}`, { user: OWNER, expect: 200 });
await call('POST', `/biz/${B}/manage/jobs/${job2.id}/close`, { expect: 409 });
const dup = await call('POST', `/biz/${B}/manage/jobs/${job2.id}/duplicate`, { user: SARA, expect: 200 });
check(dup.status === 'draft' && dup.title === 'كاشير' && dup.id !== job2.id, 'duplicate makes a new draft');
await call('DELETE', `/biz/${B}/manage/jobs/${dup.id}`, { user: SARA, expect: 200 });
await call('DELETE', `/biz/${B}/manage/jobs/${job2.id}`, { expect: 409 });
await call('POST', `/biz/${B}/manage/jobs/${job3.id}/pause`, { expect: 200 });
pub = await call('GET', '/jobs', { user: null, expect: 200 });
check(pub.items.length === 0, 'paused, filled and closed jobs leave the public list');

// ---- الموافقة الإدارية والإغلاق الإداري والموعد النهائي
globalThis.naslifeSettings.jobsRequireApproval = true;
const job4 = await call('POST', `/biz/${B}/manage/jobs`, { body: { title: 'مشرف مقهى', description: 'مشرف للفرع يدير الورديات والمخزون ويتابع جودة القهوة والخدمة يومياً.', skills: ['إشراف', 'قهوة مختصة'], publish: true, deadline: new Date(Date.now() - 3600000).toISOString() }, expect: 200 });
check(job4.status === 'pending' && job4.matched === null, 'approval required puts the job in pending');
let al = await call('GET', '/adminapi/jobs?status=pending', { user: ADMIN, expect: 200 });
check(al.items.length === 1 && al.items[0].bizName === 'مقهى ريف' && al.totals.pending === 1 && al.settings.jobsRequireApproval === true, 'admin list shows pending job with settings');
await call('POST', `/adminapi/jobs/${job4.id}/approve`, { user: OWNER, expect: 403 });
const apr = await call('POST', `/adminapi/jobs/${job4.id}/approve`, { user: ADMIN, expect: 200 });
check(apr.status === 'open' && (await notes('job_review', OWNER)).length >= 1, 'admin approval opens and matches');
globalThis.naslifeSettings.jobsRequireApproval = false;
const sw3 = await call('POST', '/adminapi/jobs/sweep', { user: ADMIN, expect: 200 });
check(sw3.closed === 1, 'sweep closes a job past its deadline', JSON.stringify(sw3));
await call('POST', `/biz/${B}/manage/jobs/${job3.id}/publish`, { expect: 200 });
await call('POST', `/adminapi/jobs/${job3.id}/close`, { body: { reason: 'إعلان مكرر' }, user: ADMIN, expect: 200 });
check((await notes('job_review', OWNER)).some((n) => n.body === 'إعلان مكرر'), 'admin close notifies the team with the reason');
globalThis.naslifeSettings.jobsEnabled = false;
await call('PUT', '/jobs/profile', { body: { titles: ['x'] }, user: MAJED, expect: 403 });
await call('POST', `/biz/${B}/manage/jobs`, { body: { title: 'كاشير' }, expect: 403 });
globalThis.naslifeSettings.jobsEnabled = true;
await call('DELETE', '/jobs/profile', { user: MAJED, expect: 200 });
check((await call('GET', '/jobs/profile', { user: MAJED, expect: 200 })).profile === null, 'profile deleted');

await app.close(); await pool.end();
console.log(fails ? `\n${fails} FAILED` : '\nALL JOBS TESTS PASSED');
process.exit(fails ? 1 : 0);
