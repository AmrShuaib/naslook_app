// التوظيف: ربط دوائر الأعمال بالباحثين عن عمل.
// المستخدم يملأ «ملف توظيف» خاصاً (job_profiles) مستقلاً عن ملفه العام، والدائرة تنشر عرضاً وظيفياً (jobs) من لوحتها
// بمساعدة محرك صياغة (Claude عبر مفتاح صندوق البريد، وقالب محلي احتياطاً). عند النشر يطابق المحرك العرض مع الملفات
// النشطة (job_matches) ويرسل بطاقة إلى تبويب «الطلبات» في الدردشة مع إشعار. الدائرة ترى عدد المطابقين فقط؛ هوية المرشح
// تُكشف بعد إجابته على أسئلة الفرز (قرار المالك)، ثم تُفتح محادثة مع عضو الفريق المسؤول (دور hr). لوحة المرشحين: مراحل
// وملاحظات وتقييم وإسناد ومقابلات وقمع إحصائي وتصدير. باقة pro (تمنحها الإدارة الآن) ترفع حد العروض النشطة وتفتح التصدير.
// لا رسوم على الباحث عن عمل أبداً. التسجيل في src/index.js بعد offers.js:
//   await app.register((await import("./jobs.js")).default, { pool, auth });
import crypto from "node:crypto";

const UUID_RE = /^[0-9a-f-]{36}$/i;
const SLUG_RE = /^[a-z0-9][a-z0-9-]{1,63}$/;
const ID_RE = /^[A-Z]{2}\d{7}$/;
const TYPES = ["full", "part", "remote", "intern", "shift", "freelance"];
const TYPE_AR = { full: "دوام كامل", part: "دوام جزئي", remote: "عن بُعد", intern: "تدريب", shift: "ورديات", freelance: "عمل حر" };
const EDU = ["none", "secondary", "diploma", "bachelor", "master", "phd"];
const AVAIL = ["now", "2w", "1m", "3m"];
const JOB_STATUS = ["draft", "pending", "open", "paused", "closed", "filled"];
const MATCH_STATUS = ["sent", "viewed", "accepted", "declined", "later", "answered", "withdrawn", "expired"];
export const STAGES = ["new", "screening", "answered", "interview", "offer", "hired", "rejected"];
const STAGE_AR = { new: "جديد", screening: "فرز", answered: "أجاب", interview: "مقابلة", offer: "عرض", hired: "تعيين", rejected: "معتذر" };
const Q_KINDS = ["text", "yesno", "choice", "number"];
const HIRING_ROLES = new Set(["owner", "manager", "admin", "hr"]);
const DAY = 86400000;
const str = (v, max) => String(v ?? "").trim().slice(0, max);
const num = (v) => { const n = Number(v); return Number.isFinite(n) ? n : null; };
const intOr = (v, d, lo, hi) => { const n = Math.round(Number(v)); return Number.isFinite(n) ? Math.max(lo, Math.min(hi, n)) : d; };
const list = (v, max, len = 60) => (Array.isArray(v) ? [...new Set(v.map((x) => str(x, len)).filter(Boolean))].slice(0, max) : []);
const STOP = new Set(["في", "من", "على", "الى", "إلى", "عن", "مع", "او", "أو", "و", "ال", "the", "and", "or", "of", "for", "in", "a", "an", "to"]);

/// تطبيع عربي/إنجليزي للمطابقة: حذف التشكيل والتطويل، توحيد الألف والتاء المربوطة والياء، وحروف صغيرة.
export const norm = (s) => String(s ?? "").toLowerCase().replace(/[ً-ْـ]/g, "").replace(/[أإآ]/g, "ا").replace(/ة/g, "ه").replace(/ى/g, "ي").replace(/[^\p{L}\p{N}\s]/gu, " ").replace(/\s+/g, " ").trim();
const tokens = (s) => new Set(norm(s).split(" ").filter((t) => t.length > 1 && !STOP.has(t)));
const overlap = (a, b) => { let n = 0; for (const t of a) if (b.has(t)) n++; return n; };

/// درجة المطابقة (0..1) وأسبابها بالعربية. الأوزان: المسمّى ٠٫٣، المهارات ٠٫٢٥، المدينة ٠٫١٥، نوع الدوام ٠٫١، الخبرة ٠٫٠٨،
/// الراتب ٠٫٠٦، المجال ٠٫٠٦.
export function scoreMatch(job, p) {
  const reasons = [];
  const jt = tokens(job.title);
  let title = 0;
  for (const t of p.titles ?? []) {
    if (norm(t) && norm(t) === norm(job.title)) { title = 1; break; }
    const tt = tokens(t); const o = overlap(tt, jt);
    if (jt.size) title = Math.max(title, o / jt.size);
  }
  if (title >= 1) reasons.push("المسمّى مطابق"); else if (title >= .5) reasons.push("المسمّى قريب");
  const js = new Set((job.skills ?? []).map(norm).filter(Boolean)), ps = new Set((p.skills ?? []).map(norm).filter(Boolean));
  let skills = 0;
  if (js.size) { const o = overlap(js, ps); skills = o / js.size; if (o) reasons.push(o === 1 ? "مهارة مشتركة" : `${o} مهارات مشتركة`); } else skills = title;
  let city = 0;
  if (job.type === "remote") { city = 1; reasons.push("عن بُعد"); }
  else if (!p.city) city = .5;
  else if (norm(p.city) === norm(job.city)) { city = 1; reasons.push("نفس المدينة"); }
  let type = 0;
  const pt = p.types ?? [];
  if (!pt.length) type = .7; else if (pt.includes(job.type)) { type = 1; reasons.push(TYPE_AR[job.type] ?? job.type); } else type = .3;
  const minExp = Number(job.experience_min ?? 0), yrs = Number(p.experience_years ?? 0);
  const exp = yrs >= minExp ? 1 : Math.max(0, 1 - (minExp - yrs) / Math.max(minExp, 1)) * .6;
  if (minExp > 0 && yrs >= minExp) reasons.push(`خبرة ${yrs} سنوات`);
  let salary = .7;
  if (job.salary_max != null && p.salary_min != null) salary = Number(job.salary_max) >= Number(p.salary_min) ? 1 : .3;
  const jf = tokens(job.department), pf = new Set((p.fields ?? []).flatMap((f) => [...tokens(f)]));
  let field = .5;
  if (jf.size && pf.size) field = overlap(jf, pf) ? 1 : .2;
  const score = title * .3 + skills * .25 + city * .15 + type * .1 + exp * .08 + salary * .06 + field * .06;
  return { score: Math.round(score * 1000) / 1000, reasons };
}

/// أسئلة الفرز الافتراضية حين لا يضيف صاحب العرض أسئلته (المحرك أو القالب يقترحان غيرها)
export const DEFAULT_QUESTIONS = (type) => [
  { id: "avail", text: "متى تستطيع البدء؟", kind: "choice", options: ["فوراً", "خلال أسبوعين", "خلال شهر", "بعد أكثر من شهر"], required: true },
  { id: "exp", text: "كم سنة خبرة لديك في هذا المجال؟", kind: "number", required: true },
  { id: "why", text: "صف بإيجاز خبرة أو مشروعاً يشبه هذه الوظيفة.", kind: "text", required: true },
  { id: "salary", text: "ما الراتب الشهري الذي تتوقعه بالريال؟", kind: "number", required: false },
  ...(type === "shift" || type === "part" ? [{ id: "shift", text: "هل تناسبك الورديات المسائية أو نهاية الأسبوع؟", kind: "yesno", required: true }] : []),
];

/// قالب محلي لصياغة العرض حين لا يتوفر مفتاح الذكاء الاصطناعي (أو يفشل): يبني وصفاً ومتطلبات وأسئلة من المدخلات.
export function templateDraft({ title, bullets = [], type = "full", city = "", department = "", bizName = "" }) {
  const t = str(title, 80) || "وظيفة";
  const bl = list(bullets, 8, 200);
  const intro = `${bizName ? `تبحث ${bizName}` : "نبحث"} عن ${t}${city ? ` في ${city}` : ""}${department ? ` للانضمام إلى ${department}` : ""} بنظام ${TYPE_AR[type] ?? "دوام كامل"}.`;
  const duties = bl.length ? `\n\nالمهام:\n${bl.map((b) => `• ${b}`).join("\n")}` : "";
  const outro = "\n\nنقدّم بيئة عمل محترمة ووضوحاً في المهام والرواتب. التقديم عبر ناس لايف، وسنتواصل مع من تنطبق عليهم الشروط خلال أيام.";
  const must = bl.slice(0, 3).map((b) => `خبرة في: ${b}`);
  if (!must.length) must.push("خبرة سابقة في مجال مشابه");
  const nice = ["التواصل الجيد مع العملاء", "الالتزام بالمواعيد", "القدرة على العمل ضمن فريق"];
  const skills = [...new Set(bl.flatMap((b) => [...tokens(b)]).filter((w) => w.length > 3))].slice(0, 8);
  return { source: "template", title: t, titleEn: "", description: intro + duties + outro, descriptionEn: "", requirements: { must, nice }, skills, questions: DEFAULT_QUESTIONS(type) };
}

export default async function jobs(app, opts = {}) {
  const pool = opts.pool ?? globalThis.naslifePool ?? null;
  const auth = opts.auth ?? globalThis.naslifeAuth ?? null;
  if (!pool || !auth) throw new Error("jobs: pool and auth are required");
  await pool.query(`
    CREATE TABLE IF NOT EXISTS job_profiles (
      user_id TEXT PRIMARY KEY, active BOOLEAN NOT NULL DEFAULT true, titles TEXT[] NOT NULL DEFAULT '{}', fields TEXT[] NOT NULL DEFAULT '{}',
      city TEXT, districts TEXT[] NOT NULL DEFAULT '{}', types TEXT[] NOT NULL DEFAULT '{}', experience_years INT NOT NULL DEFAULT 0,
      education TEXT NOT NULL DEFAULT 'none', skills TEXT[] NOT NULL DEFAULT '{}', languages TEXT[] NOT NULL DEFAULT '{}',
      salary_min INT, salary_max INT, availability TEXT NOT NULL DEFAULT 'now', summary TEXT NOT NULL DEFAULT '', cv_url TEXT, cv_name TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE TABLE IF NOT EXISTS jobs (
      id UUID PRIMARY KEY, biz_id TEXT NOT NULL, created_by TEXT NOT NULL, assignee_id TEXT, title TEXT NOT NULL, title_en TEXT NOT NULL DEFAULT '',
      department TEXT NOT NULL DEFAULT '', description TEXT NOT NULL DEFAULT '', description_en TEXT NOT NULL DEFAULT '',
      requirements JSONB NOT NULL DEFAULT '{"must":[],"nice":[]}', skills TEXT[] NOT NULL DEFAULT '{}', city TEXT NOT NULL DEFAULT '', district TEXT NOT NULL DEFAULT '',
      type TEXT NOT NULL DEFAULT 'full', experience_min INT NOT NULL DEFAULT 0, education TEXT NOT NULL DEFAULT 'none', salary_min INT, salary_max INT,
      salary_visible BOOLEAN NOT NULL DEFAULT false, openings INT NOT NULL DEFAULT 1, deadline TIMESTAMPTZ, status TEXT NOT NULL DEFAULT 'draft',
      public BOOLEAN NOT NULL DEFAULT true, questions JSONB NOT NULL DEFAULT '[]', views INT NOT NULL DEFAULT 0, draft_source TEXT,
      published_at TIMESTAMPTZ, closed_at TIMESTAMPTZ, last_matched_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE INDEX IF NOT EXISTS jobs_biz_idx ON jobs(biz_id, status);
    CREATE INDEX IF NOT EXISTS jobs_open_idx ON jobs(status, public, published_at DESC);
    CREATE TABLE IF NOT EXISTS job_matches (
      id UUID PRIMARY KEY, job_id UUID NOT NULL, biz_id TEXT NOT NULL, user_id TEXT NOT NULL, score NUMERIC(5,3) NOT NULL DEFAULT 0, reasons JSONB NOT NULL DEFAULT '[]',
      source TEXT NOT NULL DEFAULT 'match', status TEXT NOT NULL DEFAULT 'sent', stage TEXT NOT NULL DEFAULT 'new', seq INT NOT NULL DEFAULT 0,
      answers JSONB, answered_at TIMESTAMPTZ, accepted_at TIMESTAMPTZ, declined_at TIMESTAMPTZ, decline_reason TEXT, viewed_at TIMESTAMPTZ,
      assignee_id TEXT, sent_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), UNIQUE (job_id, user_id));
    CREATE INDEX IF NOT EXISTS job_matches_user_idx ON job_matches(user_id, status);
    CREATE TABLE IF NOT EXISTS job_notes (id UUID PRIMARY KEY, match_id UUID NOT NULL, author_id TEXT NOT NULL, text TEXT NOT NULL DEFAULT '', rating INT, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE TABLE IF NOT EXISTS job_events (id UUID PRIMARY KEY, job_id UUID NOT NULL, match_id UUID, actor_id TEXT, kind TEXT NOT NULL, data JSONB NOT NULL DEFAULT '{}', created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE INDEX IF NOT EXISTS job_events_job_idx ON job_events(job_id, created_at);
    CREATE TABLE IF NOT EXISTS job_interviews (
      id UUID PRIMARY KEY, match_id UUID NOT NULL, job_id UUID NOT NULL, at TIMESTAMPTZ NOT NULL, mode TEXT NOT NULL DEFAULT 'onsite', place TEXT NOT NULL DEFAULT '',
      note TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'scheduled', created_by TEXT NOT NULL, reminded_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE TABLE IF NOT EXISTS job_plans (biz_id TEXT PRIMARY KEY, plan TEXT NOT NULL DEFAULT 'free', until TIMESTAMPTZ, granted_by TEXT, updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
  `);

  const unauthorized = (reply) => reply.code(401).send({ error: "auth" });
  const bad = (reply, code, error, extra = {}) => reply.code(code).send({ error, ...extra });
  const settings = () => globalThis.naslifeSettings ?? {};
  const enabled = () => settings().jobsEnabled !== false;
  const freeActive = () => intOr(settings().jobsFreeActive, 3, 1, 100);
  const weeklyCap = () => intOr(settings().jobsWeeklyCap, 5, 1, 50);
  const minScore = () => { const n = Number(settings().jobsMinScore); return Number.isFinite(n) && n > 0 && n <= 1 ? n : .45; };
  const requireApproval = () => settings().jobsRequireApproval === true;
  const userRow = async (id) => { try { return (await pool.query("SELECT * FROM users WHERE id=$1", [id])).rows[0] ?? null; } catch { return null; } };
  const person = async (id) => { const u = id ? await userRow(id) : null; return u ? { id: u.id, nickname: u.nickname ?? "", avatarUrl: u.avatar_url ?? u.avatarUrl ?? null } : { id: id ?? "", nickname: "", avatarUrl: null }; };
  const bizRow = async (id) => (SLUG_RE.test(id ?? "") ? (await pool.query("SELECT * FROM biz WHERE id=$1", [id])).rows[0] ?? null : null);
  const bizName = (b) => b?.name_ar || b?.name || b?.id || "";
  const bizSummary = (b) => (b ? { id: b.id, name: b.name, nameAr: b.name_ar, category: b.category, logoUrl: b.logo_url ?? null, verified: b.verified === true, address: b.address ?? "", city: cityOfBiz(b), lat: b.lat, lng: b.lng } : null);
  const cityOfBiz = (b) => { const a = String(b?.address ?? ""); return /الدمام|dammam/i.test(a) ? "الدمام" : /جدة|jeddah/i.test(a) ? "جدة" : /الرياض|riyadh/i.test(a) ? "الرياض" : ""; };
  const isAdmin = async (uid) => { try { return !!(await globalThis.naslifeIsAdmin?.(uid)); } catch { return false; } };
  const roleFor = async (uid, b) => { if (!uid || !b) return null; if (b.owner_id === uid) return "owner"; const s = (await pool.query("SELECT role FROM biz_staff WHERE biz_id=$1 AND user_id=$2", [b.id, uid])).rows[0]; if (s) return s.role; return (await isAdmin(uid)) ? "admin" : null; };
  const notify = async (ids, payload) => { try { await globalThis.naslifeNotify?.(ids, payload); } catch { /* لا تُفشل الطلب */ } };
  const notifyAdmins = async (payload) => { try { await globalThis.naslifeNotifyAdmins?.(payload); } catch { /* ignore */ } };
  const blockedIds = async (uid) => { try { return (await globalThis.naslifeBlockedIds?.(uid)) ?? []; } catch { return []; } };
  const rejectBanned = (reply, ...texts) => { let w = null; try { w = globalThis.naslifeCheckText?.(...texts.flat().filter((t) => typeof t === "string")) ?? null; } catch { w = null; } if (w) { reply.code(400).send({ error: "banned-words", word: w }); return true; } return false; };
  const event = async (jobId, matchId, actorId, kind, data = {}) => { try { await pool.query("INSERT INTO job_events(id,job_id,match_id,actor_id,kind,data) VALUES($1,$2,$3,$4,$5,$6)", [crypto.randomUUID(), jobId, matchId, actorId, kind, JSON.stringify(data)]); } catch { /* ignore */ } };

  /// صلاحية التوظيف في دائرة: المالك والمدير والإدارة ودور hr
  async function hiringGuard(req, reply) {
    const uid = await auth(req); if (!uid) { unauthorized(reply); return null; }
    const b = await bizRow(req.params.id); if (!b) { bad(reply, 404, "not-found"); return null; }
    const role = await roleFor(uid, b);
    if (!HIRING_ROLES.has(role)) { bad(reply, 403, "forbidden"); return null; }
    return { uid, b, role };
  }
  const hiringTeam = async (b) => [b.owner_id, ...(await pool.query("SELECT user_id FROM biz_staff WHERE biz_id=$1 AND role IN ('manager','hr')", [b.id])).rows.map((r) => r.user_id)].filter(Boolean);
  const recipientsFor = async (job, b) => { const t = await hiringTeam(b); return job.assignee_id && t.includes(job.assignee_id) ? [job.assignee_id, b.owner_id].filter(Boolean) : t; };

  // ---- الباقة: free (حد للعروض النشطة) أو pro (بلا حد + تصدير)
  async function planOf(bizId) {
    const r = (await pool.query("SELECT * FROM job_plans WHERE biz_id=$1", [bizId])).rows[0];
    const pro = r?.plan === "pro" && (!r.until || new Date(r.until) > new Date());
    return { plan: pro ? "pro" : "free", until: pro ? r.until : null, freeActive: freeActive() };
  }
  const activeCount = async (bizId) => (await pool.query("SELECT count(*)::int AS n FROM jobs WHERE biz_id=$1 AND status IN ('open','pending','paused')", [bizId])).rows[0].n;

  // ---- الإخراج
  const parseJson = (v, d) => { if (v == null) return d; if (typeof v === "object") return v; try { return JSON.parse(v); } catch { return d; } };
  const profileOut = (p) => ({
    userId: p.user_id, active: p.active !== false, titles: p.titles ?? [], fields: p.fields ?? [], city: p.city ?? "", districts: p.districts ?? [], types: p.types ?? [],
    experienceYears: Number(p.experience_years ?? 0), education: p.education ?? "none", skills: p.skills ?? [], languages: p.languages ?? [],
    salaryMin: p.salary_min == null ? null : Number(p.salary_min), salaryMax: p.salary_max == null ? null : Number(p.salary_max), availability: p.availability ?? "now",
    summary: p.summary ?? "", cvUrl: p.cv_url ?? null, cvName: p.cv_name ?? null, updatedAt: p.updated_at, createdAt: p.created_at,
  });
  const jobOut = (j, extra = {}) => ({
    id: j.id, bizId: j.biz_id, createdBy: j.created_by, assigneeId: j.assignee_id ?? null, title: j.title, titleEn: j.title_en ?? "", department: j.department ?? "",
    description: j.description ?? "", descriptionEn: j.description_en ?? "", requirements: parseJson(j.requirements, { must: [], nice: [] }), skills: j.skills ?? [],
    city: j.city ?? "", district: j.district ?? "", type: j.type, typeLabel: TYPE_AR[j.type] ?? j.type, experienceMin: Number(j.experience_min ?? 0), education: j.education ?? "none",
    salaryMin: j.salary_min == null ? null : Number(j.salary_min), salaryMax: j.salary_max == null ? null : Number(j.salary_max), salaryVisible: j.salary_visible === true,
    openings: Number(j.openings ?? 1), deadline: j.deadline, status: j.status, public: j.public !== false, questions: parseJson(j.questions, []), views: Number(j.views ?? 0),
    draftSource: j.draft_source ?? null, publishedAt: j.published_at, closedAt: j.closed_at, createdAt: j.created_at, updatedAt: j.updated_at, ...extra,
  });
  /// للعامة: الراتب يظهر فقط إن سمح صاحب العرض
  const publicJobOut = (j, b, extra = {}) => { const o = jobOut(j, extra); if (!o.salaryVisible) { o.salaryMin = null; o.salaryMax = null; } delete o.questions; delete o.createdBy; delete o.assigneeId; return { ...o, biz: bizSummary(b) }; };
  const cleanQuestions = (qs) => {
    if (!Array.isArray(qs)) return [];
    return qs.slice(0, 10).map((q, i) => {
      const kind = Q_KINDS.includes(q?.kind) ? q.kind : "text";
      const options = kind === "choice" ? list(q?.options, 8, 80) : [];
      const text = str(q?.text, 300); if (!text) return null;
      return { id: /^[a-z0-9_-]{1,20}$/i.test(String(q?.id ?? "")) ? String(q.id) : `q${i + 1}`, text, kind, options, required: q?.required !== false };
    }).filter(Boolean).filter((q) => q.kind !== "choice" || q.options.length >= 2);
  };
  const cleanRequirements = (r) => ({ must: list(r?.must, 12, 200), nice: list(r?.nice, 12, 200) });

  // ---- المطابقة
  async function candidateProfiles(job) {
    const rows = (await pool.query("SELECT * FROM job_profiles WHERE active=true ORDER BY updated_at DESC LIMIT 5000")).rows;
    if (job.type === "remote" || !job.city) return rows;
    const c = norm(job.city);
    return rows.filter((p) => !p.city || norm(p.city) === c);
  }
  /// يطابق عرضاً مفتوحاً مع الملفات النشطة، يرسل البطاقات ويُخطر؛ يتجاوز من طابقناهم سابقاً وفريق الدائرة ومن تجاوز حده الأسبوعي.
  async function matchJob(job, { notifyUsers = true } = {}) {
    if (job.status !== "open") return { sent: 0, considered: 0 };
    const b = await bizRow(job.biz_id); if (!b) return { sent: 0, considered: 0 };
    const team = new Set((await pool.query("SELECT user_id FROM biz_staff WHERE biz_id=$1", [b.id])).rows.map((r) => r.user_id).concat([b.owner_id]).filter(Boolean));
    const already = new Set((await pool.query("SELECT user_id FROM job_matches WHERE job_id=$1", [job.id])).rows.map((r) => r.user_id));
    const blocked = new Set(await blockedIds(job.created_by));
    const existing = already.size;
    const cap = Math.min(100, Math.max(20, Number(job.openings ?? 1) * 20));
    const room = Math.max(0, cap - existing);
    const th = minScore();
    const scored = [];
    const profiles = await candidateProfiles(job);
    for (const p of profiles) {
      if (team.has(p.user_id) || already.has(p.user_id) || blocked.has(p.user_id)) continue;
      const { score, reasons } = scoreMatch(job, p);
      if (score >= th) scored.push({ p, score, reasons });
    }
    scored.sort((x, y) => y.score - x.score);
    let sent = 0;
    let seq = (await pool.query("SELECT coalesce(max(seq),0)::int AS n FROM job_matches WHERE job_id=$1", [job.id])).rows[0].n;
    for (const { p, score, reasons } of scored) {
      if (sent >= room) break;
      const wk = (await pool.query("SELECT count(*)::int AS n FROM job_matches WHERE user_id=$1 AND source='match' AND sent_at > now() - interval '7 days'", [p.user_id])).rows[0].n;
      if (wk >= weeklyCap()) continue;
      const id = crypto.randomUUID(); seq++;
      try {
        await pool.query("INSERT INTO job_matches(id,job_id,biz_id,user_id,score,reasons,source,status,stage,seq) VALUES($1,$2,$3,$4,$5,$6,'match','sent','new',$7)", [id, job.id, job.biz_id, p.user_id, score, JSON.stringify(reasons), seq]);
      } catch { continue; }
      sent++;
      await event(job.id, id, null, "match.sent", { score });
      if (notifyUsers) await notify(p.user_id, { kind: "job_offer", title: `عرض وظيفي: ${job.title}`, body: `${bizName(b)}${job.city ? ` · ${job.city}` : ""} · ${TYPE_AR[job.type] ?? ""}`, data: { jobId: job.id, matchId: id, bizId: job.biz_id } });
    }
    await pool.query("UPDATE jobs SET last_matched_at=now() WHERE id=$1", [job.id]);
    return { sent, considered: scored.length, capped: scored.length > room };
  }
  /// معاينة قبل النشر: أعداد فقط بلا هويات
  async function previewMatch(job) {
    const profiles = await candidateProfiles(job);
    const team = new Set((await pool.query("SELECT user_id FROM biz_staff WHERE biz_id=$1", [job.biz_id])).rows.map((r) => r.user_id));
    const th = minScore(); let strong = 0, good = 0, weak = 0;
    for (const p of profiles) { if (team.has(p.user_id)) continue; const { score } = scoreMatch(job, p); if (score >= .75) strong++; else if (score >= th) good++; else if (score >= th - .15) weak++; }
    return { strong, good, weak, threshold: th, profiles: profiles.length };
  }

  // ---- المسح الدوري: مطابقة جديدة للعروض المفتوحة، إغلاق عند الموعد، انتهاء البطاقات القديمة، تذكير المقابلات
  let sweeping = false;
  async function sweep() {
    if (sweeping) return { skipped: true };
    sweeping = true;
    const st = { matched: 0, closed: 0, expired: 0, reminded: 0 };
    try {
      const closed = (await pool.query("UPDATE jobs SET status='closed', closed_at=now(), updated_at=now() WHERE status IN ('open','paused') AND deadline IS NOT NULL AND deadline < now() RETURNING id, biz_id, title")).rows;
      st.closed = closed.length;
      for (const j of closed) await event(j.id, null, null, "job.closed", { reason: "deadline" });
      st.expired = (await pool.query("UPDATE job_matches SET status='expired', updated_at=now() WHERE status='sent' AND sent_at < now() - interval '21 days'")).rowCount;
      const open = (await pool.query("SELECT * FROM jobs WHERE status='open' AND (last_matched_at IS NULL OR last_matched_at < now() - interval '20 minutes') ORDER BY last_matched_at NULLS FIRST LIMIT 200")).rows;
      for (const j of open) { try { st.matched += (await matchJob(j)).sent; } catch { /* عرض واحد لا يوقف الباقي */ } }
      const soon = (await pool.query("SELECT i.*, m.user_id, j.title, j.biz_id, j.assignee_id FROM job_interviews i JOIN job_matches m ON m.id=i.match_id JOIN jobs j ON j.id=i.job_id WHERE i.status='scheduled' AND i.reminded_at IS NULL AND i.at BETWEEN now() AND now() + interval '24 hours'")).rows;
      for (const i of soon) {
        const when = new Date(i.at).toISOString().slice(0, 16).replace("T", " ");
        await notify(i.user_id, { kind: "job_interview", title: `تذكير: مقابلة غداً · ${i.title}`, body: `${when} · ${i.mode === "onsite" ? i.place || "في المقر" : i.mode === "video" ? "اتصال مرئي" : "اتصال هاتفي"}`, data: { jobId: i.job_id, matchId: i.match_id, interviewId: i.id, bizId: i.biz_id } });
        if (i.assignee_id) await notify(i.assignee_id, { kind: "job_interview", title: `تذكير: مقابلة غداً · ${i.title}`, body: when, data: { jobId: i.job_id, matchId: i.match_id, bizId: i.biz_id, manage: true } });
        await pool.query("UPDATE job_interviews SET reminded_at=now() WHERE id=$1", [i.id]);
        st.reminded++;
      }
    } finally { sweeping = false; }
    return st;
  }
  globalThis.naslifeJobsSweep = sweep;
  const SWEEP_MS = opts.sweepMs ?? (Number(process.env.JOBS_SWEEP_MS) || 30 * 60 * 1000);
  let timer = null;
  if (SWEEP_MS > 0) { timer = setInterval(() => sweep().catch(() => {}), SWEEP_MS); timer.unref?.(); app.addHook("onClose", async () => { if (timer) clearInterval(timer); }); }

  // ---- محرك الصياغة: Claude عبر مفتاح صندوق البريد (inbox.js)، وإلا القالب المحلي
  async function draftWithAi(input, b) {
    const ask = globalThis.naslifeAskClaude;
    if (typeof ask !== "function") return null;
    const system = "أنت مساعد توظيف لمنصة «ناس لايف» السعودية (جدة والدمام). تكتب عروضاً وظيفية عربية واضحة ومحترمة بلا مبالغة ولا تمييز بالجنس أو العمر أو الجنسية، وأسئلة فرز لا تسأل عن الدين أو الحالة الاجتماعية. أجب بكائن JSON فقط بلا أي نص آخر، بالمفاتيح: title (نص عربي قصير)، titleEn، description (عربي ٨٠–١٨٠ كلمة بفقرات ونقاط تبدأ بـ•)، descriptionEn (ترجمة موجزة)، requirements {must: [٣–٦ نصوص], nice: [٢–٤ نصوص]}، skills [٥–١٠ كلمات مفتاحية عربية قصيرة]، questions [٤–٦ عناصر بالشكل {id, text, kind: text|yesno|choice|number, options: [] للاختيار, required: true|false}].";
    const user = JSON.stringify({ بيانات: { الدائرة: bizName(b), الفئة: b?.category ?? "", المسمى: input.title, القسم: input.department, نوع_الدوام: TYPE_AR[input.type] ?? input.type, المدينة: input.city, نقاط_من_صاحب_العمل: input.bullets, نطاق_الراتب: input.salaryMin || input.salaryMax ? `${input.salaryMin ?? ""}-${input.salaryMax ?? ""} ريال` : "غير محدد" } });
    const text = await ask({ system, user, maxTokens: 3000, effort: "medium" });
    const m = String(text ?? "").match(/\{[\s\S]*\}/);
    if (!m) throw new Error("ai-bad-json");
    const j = JSON.parse(m[0]);
    const out = {
      source: "ai", title: str(j.title, 80) || input.title, titleEn: str(j.titleEn, 80), description: str(j.description, 4000), descriptionEn: str(j.descriptionEn, 4000),
      requirements: cleanRequirements(j.requirements), skills: list(j.skills, 10, 40), questions: cleanQuestions(j.questions),
    };
    if (!out.description) throw new Error("ai-empty");
    if (!out.questions.length) out.questions = DEFAULT_QUESTIONS(input.type);
    return out;
  }

  // ================================================================ ملف التوظيف (المستخدم)
  app.get("/jobs/profile", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const p = (await pool.query("SELECT * FROM job_profiles WHERE user_id=$1", [uid])).rows[0];
    const inbox = (await pool.query("SELECT count(*) FILTER (WHERE status='sent')::int AS pending, count(*)::int AS total FROM job_matches WHERE user_id=$1", [uid])).rows[0];
    return { profile: p ? profileOut(p) : null, pending: inbox.pending, total: inbox.total, types: TYPES, education: EDU, availability: AVAIL };
  });
  app.put("/jobs/profile", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!enabled()) return bad(reply, 403, "unavailable");
    const b = req.body ?? {};
    const titles = list(b.titles, 6, 60); if (!titles.length) return bad(reply, 400, "titles-required");
    const types = list(b.types, 6, 20).filter((t) => TYPES.includes(t));
    const education = EDU.includes(b.education) ? b.education : "none";
    const availability = AVAIL.includes(b.availability) ? b.availability : "now";
    const salaryMin = b.salaryMin == null || b.salaryMin === "" ? null : intOr(b.salaryMin, null, 0, 1000000);
    const salaryMax = b.salaryMax == null || b.salaryMax === "" ? null : intOr(b.salaryMax, null, 0, 1000000);
    if (salaryMin != null && salaryMax != null && salaryMax < salaryMin) return bad(reply, 400, "bad-salary");
    const summary = str(b.summary, 600);
    if (rejectBanned(reply, summary, ...titles)) return;
    const cvUrl = str(b.cvUrl, 400) || null;
    if (cvUrl && !/^(https?:\/\/|\/)/.test(cvUrl)) return bad(reply, 400, "bad-cv");
    const vals = [uid, b.active !== false, titles, list(b.fields, 6, 60), str(b.city, 40) || null, list(b.districts, 8, 60), types, intOr(b.experienceYears, 0, 0, 50), education, list(b.skills, 20, 40), list(b.languages, 6, 30), salaryMin, salaryMax, availability, summary, cvUrl, cvUrl ? str(b.cvName, 120) || "cv.pdf" : null];
    const r = await pool.query(`INSERT INTO job_profiles(user_id,active,titles,fields,city,districts,types,experience_years,education,skills,languages,salary_min,salary_max,availability,summary,cv_url,cv_name)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17)
      ON CONFLICT (user_id) DO UPDATE SET active=EXCLUDED.active, titles=EXCLUDED.titles, fields=EXCLUDED.fields, city=EXCLUDED.city, districts=EXCLUDED.districts, types=EXCLUDED.types, experience_years=EXCLUDED.experience_years,
        education=EXCLUDED.education, skills=EXCLUDED.skills, languages=EXCLUDED.languages, salary_min=EXCLUDED.salary_min, salary_max=EXCLUDED.salary_max, availability=EXCLUDED.availability, summary=EXCLUDED.summary, cv_url=EXCLUDED.cv_url, cv_name=EXCLUDED.cv_name, updated_at=now()
      RETURNING *`, vals);
    return { profile: profileOut(r.rows[0]) };
  });
  app.delete("/jobs/profile", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    await pool.query("DELETE FROM job_profiles WHERE user_id=$1", [uid]);
    return { ok: true };
  });

  // ---- صندوق العروض (بطاقات تبويب «الطلبات») وعروضي
  const matchRowsOut = async (rows) => Promise.all(rows.map(async (m) => {
    const b = await bizRow(m.biz_id);
    const j = (await pool.query("SELECT * FROM jobs WHERE id=$1", [m.job_id])).rows[0];
    const iv = (await pool.query("SELECT * FROM job_interviews WHERE match_id=$1 AND status='scheduled' ORDER BY at LIMIT 1", [m.id])).rows[0];
    return {
      id: m.id, jobId: m.job_id, bizId: m.biz_id, status: m.status, stage: m.stage, stageLabel: STAGE_AR[m.stage] ?? m.stage, source: m.source, score: Number(m.score), reasons: parseJson(m.reasons, []),
      sentAt: m.sent_at, viewedAt: m.viewed_at, acceptedAt: m.accepted_at, answeredAt: m.answered_at, declinedAt: m.declined_at, answers: parseJson(m.answers, null),
      job: j ? publicJobOut(j, b) : null, questions: j ? parseJson(j.questions, []) : [], assignee: j?.assignee_id ? await person(j.assignee_id) : (b?.owner_id ? await person(b.owner_id) : null),
      interview: iv ? { id: iv.id, at: iv.at, mode: iv.mode, place: iv.place, note: iv.note, status: iv.status } : null,
    };
  }));
  app.get("/jobs/inbox", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const rows = (await pool.query("SELECT m.* FROM job_matches m JOIN jobs j ON j.id=m.job_id WHERE m.user_id=$1 AND m.status IN ('sent','viewed','later') AND j.status='open' ORDER BY m.sent_at DESC LIMIT 50", [uid])).rows;
    const items = await matchRowsOut(rows);
    return { items, pending: items.filter((i) => i.status !== "later").length };
  });
  app.get("/jobs/mine", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const rows = (await pool.query("SELECT * FROM job_matches WHERE user_id=$1 ORDER BY updated_at DESC LIMIT 100", [uid])).rows;
    const items = await matchRowsOut(rows);
    return { items, active: items.filter((i) => ["accepted", "answered"].includes(i.status) && !["hired", "rejected"].includes(i.stage)), history: items.filter((i) => !["sent", "viewed", "later", "accepted", "answered"].includes(i.status) || ["hired", "rejected"].includes(i.stage)) };
  });
  async function matchFor(req, reply, uid) {
    const id = String(req.params.matchId ?? ""); if (!UUID_RE.test(id)) { bad(reply, 400, "bad-id"); return null; }
    const m = (await pool.query("SELECT * FROM job_matches WHERE id=$1 AND user_id=$2", [id, uid])).rows[0];
    if (!m) { bad(reply, 404, "not-found"); return null; }
    const j = (await pool.query("SELECT * FROM jobs WHERE id=$1", [m.job_id])).rows[0];
    return { m, j, b: await bizRow(m.biz_id) };
  }
  app.get("/jobs/offers/:matchId", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const x = await matchFor(req, reply, uid); if (!x) return;
    if (x.m.status === "sent") { await pool.query("UPDATE job_matches SET status='viewed', viewed_at=now(), updated_at=now() WHERE id=$1", [x.m.id]); x.m.status = "viewed"; x.m.viewed_at = new Date(); await event(x.j.id, x.m.id, uid, "match.viewed"); }
    return (await matchRowsOut([x.m]))[0];
  });
  /// القبول: يُخطر فريق التوظيف بمرشح مجهول؛ بلا أسئلة يُعدّ «أجاب» فوراً فتُكشف هويته وتُفتح المحادثة
  app.post("/jobs/offers/:matchId/accept", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const x = await matchFor(req, reply, uid); if (!x) return;
    if (!x.j || x.j.status !== "open") return bad(reply, 409, "job-closed");
    if (!["sent", "viewed", "later", "declined"].includes(x.m.status)) return bad(reply, 409, "bad-state", { status: x.m.status });
    const qs = parseJson(x.j.questions, []);
    const answeredNow = qs.length === 0;
    await pool.query("UPDATE job_matches SET status=$2, stage=$3, accepted_at=now(), answered_at=CASE WHEN $4 THEN now() ELSE answered_at END, answers=CASE WHEN $4 THEN '[]'::jsonb ELSE answers END, updated_at=now() WHERE id=$1", [x.m.id, answeredNow ? "answered" : "accepted", answeredNow ? "answered" : "screening", answeredNow]);
    await event(x.j.id, x.m.id, uid, "match.accepted");
    const to = await recipientsFor(x.j, x.b);
    if (answeredNow) { const u = await person(uid); await notify(to, { kind: "job_answers", title: `مرشح جديد: ${x.j.title}`, body: `${u.nickname || "مرشح"} قبل العرض وهو جاهز للتواصل`, data: { jobId: x.j.id, matchId: x.m.id, bizId: x.j.biz_id, manage: true } }); }
    else await notify(to, { kind: "job_accept", title: `قبول عرض: ${x.j.title}`, body: `مرشح #${x.m.seq} قبل العرض ويجيب الآن على أسئلة الفرز`, data: { jobId: x.j.id, matchId: x.m.id, bizId: x.j.biz_id, manage: true } });
    return { ok: true, status: answeredNow ? "answered" : "accepted", questions: qs, chatWith: answeredNow ? (x.j.assignee_id ? await person(x.j.assignee_id) : await person(x.b?.owner_id)) : null };
  });
  app.post("/jobs/offers/:matchId/decline", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const x = await matchFor(req, reply, uid); if (!x) return;
    if (!["sent", "viewed", "later"].includes(x.m.status)) return bad(reply, 409, "bad-state", { status: x.m.status });
    const reason = str(req.body?.reason, 200);
    await pool.query("UPDATE job_matches SET status='declined', declined_at=now(), decline_reason=$2, updated_at=now() WHERE id=$1", [x.m.id, reason || null]);
    await event(x.j.id, x.m.id, uid, "match.declined", { reason });
    return { ok: true };
  });
  app.post("/jobs/offers/:matchId/later", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const x = await matchFor(req, reply, uid); if (!x) return;
    if (!["sent", "viewed"].includes(x.m.status)) return bad(reply, 409, "bad-state", { status: x.m.status });
    await pool.query("UPDATE job_matches SET status='later', updated_at=now() WHERE id=$1", [x.m.id]);
    return { ok: true };
  });
  /// الإجابات: تُتحقق الإلزامية والأنواع، ثم تُكشف الهوية للدائرة وتُفتح المحادثة مع المسؤول
  app.post("/jobs/offers/:matchId/answers", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const x = await matchFor(req, reply, uid); if (!x) return;
    if (!x.j || x.j.status !== "open") return bad(reply, 409, "job-closed");
    if (x.m.status !== "accepted") return bad(reply, 409, "bad-state", { status: x.m.status });
    const qs = parseJson(x.j.questions, []);
    const given = Array.isArray(req.body?.answers) ? req.body.answers : [];
    const answers = [];
    for (const q of qs) {
      const a = given.find((g) => String(g?.id) === q.id);
      let value = a?.value;
      if (q.kind === "yesno") value = value === true || value === "yes" || value === "نعم" ? true : value === false || value === "no" || value === "لا" ? false : null;
      else if (q.kind === "number") value = value == null || value === "" ? null : num(value);
      else if (q.kind === "choice") value = q.options.includes(String(value ?? "")) ? String(value) : null;
      else value = str(value, 1500) || null;
      if (q.required && (value == null || value === "")) return bad(reply, 400, "answer-required", { id: q.id });
      answers.push({ id: q.id, text: q.text, kind: q.kind, value });
    }
    if (rejectBanned(reply, ...answers.map((a) => (typeof a.value === "string" ? a.value : "")))) return;
    await pool.query("UPDATE job_matches SET status='answered', stage='answered', answers=$2, answered_at=now(), updated_at=now() WHERE id=$1", [x.m.id, JSON.stringify(answers)]);
    await event(x.j.id, x.m.id, uid, "match.answered");
    const u = await person(uid);
    await notify(await recipientsFor(x.j, x.b), { kind: "job_answers", title: `إجابات مرشح: ${x.j.title}`, body: `${u.nickname || "مرشح"} أجاب على أسئلة الفرز؛ افتح لوحة التوظيف`, data: { jobId: x.j.id, matchId: x.m.id, bizId: x.j.biz_id, manage: true } });
    return { ok: true, chatWith: x.j.assignee_id ? await person(x.j.assignee_id) : await person(x.b?.owner_id) };
  });
  app.post("/jobs/offers/:matchId/withdraw", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const x = await matchFor(req, reply, uid); if (!x) return;
    if (!["accepted", "answered"].includes(x.m.status) || ["hired", "rejected"].includes(x.m.stage)) return bad(reply, 409, "bad-state");
    await pool.query("UPDATE job_matches SET status='withdrawn', stage='rejected', updated_at=now() WHERE id=$1", [x.m.id]);
    await event(x.j.id, x.m.id, uid, "match.withdrawn");
    if (x.j) await notify(await recipientsFor(x.j, x.b), { kind: "job_stage", title: `انسحاب مرشح: ${x.j.title}`, body: "انسحب أحد المرشحين من العرض", data: { jobId: x.j.id, matchId: x.m.id, bizId: x.j.biz_id, manage: true } });
    return { ok: true };
  });

  // ================================================================ العام: قائمة الوظائف، الوظيفة، وظائف دائرة، الدوائر التي توظّف
  const openFilter = "j.status='open' AND j.public=true";
  app.get("/jobs", async (req, reply) => {
    const uid = await auth(req).catch(() => null);
    const q = norm(str(req.query?.q, 80)), city = str(req.query?.city, 40), type = TYPES.includes(req.query?.type) ? req.query.type : null, bizId = str(req.query?.bizId, 64);
    const where = [openFilter]; const vals = [];
    if (city) { vals.push(city); where.push(`j.city=$${vals.length}`); }
    if (type) { vals.push(type); where.push(`j.type=$${vals.length}`); }
    if (bizId) { vals.push(bizId); where.push(`j.biz_id=$${vals.length}`); }
    const rows = (await pool.query(`SELECT j.* FROM jobs j WHERE ${where.join(" AND ")} ORDER BY j.published_at DESC NULLS LAST LIMIT 200`, vals)).rows
      .filter((j) => !q || norm(`${j.title} ${j.department} ${(j.skills ?? []).join(" ")} ${j.description}`).includes(q)).slice(0, 60);
    const mine = uid ? Object.fromEntries((await pool.query("SELECT job_id, status, stage FROM job_matches WHERE user_id=$1", [uid])).rows.map((r) => [r.job_id, r])) : {};
    const items = await Promise.all(rows.map(async (j) => publicJobOut(j, await bizRow(j.biz_id), { mine: mine[j.id] ? { status: mine[j.id].status, stage: mine[j.id].stage } : null, candidates: undefined })));
    return { items, types: TYPES.map((t) => ({ id: t, label: TYPE_AR[t] })), cities: [...new Set(rows.map((j) => j.city).filter(Boolean))] };
  });
  app.get("/jobs/hiring", async () => {
    const rows = (await pool.query(`SELECT j.biz_id, count(*)::int AS n FROM jobs j WHERE ${openFilter} GROUP BY j.biz_id`)).rows;
    return { items: rows.map((r) => ({ bizId: r.biz_id, open: r.n })) };
  });
  app.get("/biz/:id/jobs", async (req, reply) => {
    const b = await bizRow(req.params.id); if (!b) return bad(reply, 404, "not-found");
    const uid = await auth(req).catch(() => null);
    const rows = (await pool.query(`SELECT j.* FROM jobs j WHERE j.biz_id=$1 AND ${openFilter} ORDER BY j.published_at DESC`, [b.id])).rows;
    const mine = uid ? Object.fromEntries((await pool.query("SELECT job_id, status, stage FROM job_matches WHERE user_id=$1 AND biz_id=$2", [uid, b.id])).rows.map((r) => [r.job_id, r])) : {};
    return { items: rows.map((j) => publicJobOut(j, b, { mine: mine[j.id] ? { status: mine[j.id].status, stage: mine[j.id].stage } : null })) };
  });
  app.get("/jobs/:id", async (req, reply) => {
    const id = String(req.params.id ?? ""); if (!UUID_RE.test(id)) return bad(reply, 400, "bad-id");
    const j = (await pool.query("SELECT * FROM jobs WHERE id=$1", [id])).rows[0]; if (!j) return bad(reply, 404, "not-found");
    const uid = await auth(req).catch(() => null);
    const b = await bizRow(j.biz_id);
    const role = uid ? await roleFor(uid, b) : null;
    if (!(j.status === "open" && j.public) && !HIRING_ROLES.has(role)) return bad(reply, 404, "not-found");
    if (!HIRING_ROLES.has(role)) pool.query("UPDATE jobs SET views=views+1 WHERE id=$1", [id]).catch(() => {});
    const mine = uid ? (await pool.query("SELECT id, status, stage FROM job_matches WHERE user_id=$1 AND job_id=$2", [uid, id])).rows[0] : null;
    const out = publicJobOut(j, b, { mine: mine ? { matchId: mine.id, status: mine.status, stage: mine.stage } : null });
    if (mine || HIRING_ROLES.has(role)) out.questions = parseJson(j.questions, []);
    return out;
  });
  /// التقديم بلا دعوة (المرحلة الثالثة): يحتاج ملف توظيف نشطاً؛ يُعدّ قبولاً مباشراً ثم الأسئلة
  app.post("/jobs/:id/apply", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!enabled()) return bad(reply, 403, "unavailable");
    const id = String(req.params.id ?? ""); if (!UUID_RE.test(id)) return bad(reply, 400, "bad-id");
    const j = (await pool.query("SELECT * FROM jobs WHERE id=$1 AND status='open' AND public=true", [id])).rows[0]; if (!j) return bad(reply, 404, "not-found");
    const b = await bizRow(j.biz_id);
    if (HIRING_ROLES.has(await roleFor(uid, b)) || (await pool.query("SELECT 1 FROM biz_staff WHERE biz_id=$1 AND user_id=$2", [j.biz_id, uid])).rowCount) return bad(reply, 400, "own-circle");
    const p = (await pool.query("SELECT * FROM job_profiles WHERE user_id=$1", [uid])).rows[0]; if (!p) return bad(reply, 409, "profile-required");
    const exists = (await pool.query("SELECT * FROM job_matches WHERE job_id=$1 AND user_id=$2", [id, uid])).rows[0];
    const qs = parseJson(j.questions, []); const answeredNow = qs.length === 0;
    const { score, reasons } = scoreMatch(j, p);
    let mid = exists?.id;
    if (exists) {
      if (!["sent", "viewed", "later", "declined", "expired"].includes(exists.status)) return bad(reply, 409, "already", { matchId: exists.id, status: exists.status });
      await pool.query("UPDATE job_matches SET status=$2, stage=$3, source='apply', accepted_at=now(), answered_at=CASE WHEN $4 THEN now() ELSE NULL END, answers=CASE WHEN $4 THEN '[]'::jsonb ELSE NULL END, updated_at=now() WHERE id=$1", [exists.id, answeredNow ? "answered" : "accepted", answeredNow ? "answered" : "screening", answeredNow]);
    } else {
      mid = crypto.randomUUID();
      const seq = (await pool.query("SELECT coalesce(max(seq),0)::int + 1 AS n FROM job_matches WHERE job_id=$1", [id])).rows[0].n;
      await pool.query("INSERT INTO job_matches(id,job_id,biz_id,user_id,score,reasons,source,status,stage,seq,accepted_at,answered_at,answers) VALUES($1,$2,$3,$4,$5,$6,'apply',$7,$8,$9,now(),$10,$11)", [mid, id, j.biz_id, uid, score, JSON.stringify(reasons), answeredNow ? "answered" : "accepted", answeredNow ? "answered" : "screening", seq, answeredNow ? new Date() : null, answeredNow ? "[]" : null]);
    }
    await event(id, mid, uid, "match.applied", { score });
    const u = await person(uid);
    await notify(await recipientsFor(j, b), { kind: answeredNow ? "job_answers" : "job_apply", title: `متقدم جديد: ${j.title}`, body: answeredNow ? `${u.nickname || "مرشح"} تقدّم للوظيفة وهو جاهز للتواصل` : `مرشح تقدّم للوظيفة ويجيب الآن على أسئلة الفرز`, data: { jobId: id, matchId: mid, bizId: j.biz_id, manage: true } });
    return { ok: true, matchId: mid, status: answeredNow ? "answered" : "accepted", questions: qs, chatWith: answeredNow ? (j.assignee_id ? await person(j.assignee_id) : await person(b?.owner_id)) : null };
  });

  // ================================================================ الإدارة داخل الدائرة
  const jobFor = async (req, reply, g) => {
    const id = String(req.params.jobId ?? ""); if (!UUID_RE.test(id)) { bad(reply, 400, "bad-id"); return null; }
    const j = (await pool.query("SELECT * FROM jobs WHERE id=$1 AND biz_id=$2", [id, g.b.id])).rows[0];
    if (!j) { bad(reply, 404, "not-found"); return null; }
    return j;
  };
  const counts = async (jobId) => {
    const r = (await pool.query("SELECT status, stage, count(*)::int AS n FROM job_matches WHERE job_id=$1 GROUP BY status, stage", [jobId])).rows;
    const byStatus = {}, byStage = {};
    for (const x of r) { byStatus[x.status] = (byStatus[x.status] ?? 0) + x.n; byStage[x.stage] = (byStage[x.stage] ?? 0) + x.n; }
    const sent = Object.values(byStatus).reduce((a, n) => a + n, 0);
    return { sent, viewed: (byStatus.viewed ?? 0) + (byStatus.accepted ?? 0) + (byStatus.answered ?? 0) + (byStatus.withdrawn ?? 0), accepted: (byStatus.accepted ?? 0) + (byStatus.answered ?? 0) + (byStatus.withdrawn ?? 0), answered: (byStatus.answered ?? 0) + (byStatus.withdrawn ?? 0), declined: byStatus.declined ?? 0, byStage };
  };
  app.get("/biz/:id/manage/jobs", async (req, reply) => {
    const g = await hiringGuard(req, reply); if (!g) return;
    const rows = (await pool.query("SELECT * FROM jobs WHERE biz_id=$1 ORDER BY CASE status WHEN 'open' THEN 0 WHEN 'pending' THEN 1 WHEN 'paused' THEN 2 WHEN 'draft' THEN 3 ELSE 4 END, updated_at DESC", [g.b.id])).rows;
    const items = await Promise.all(rows.map(async (j) => jobOut(j, { counts: await counts(j.id), assignee: j.assignee_id ? await person(j.assignee_id) : null })));
    const plan = await planOf(g.b.id);
    const team = await Promise.all((await hiringTeam(g.b)).map(person));
    const upcoming = (await pool.query("SELECT count(*)::int AS n FROM job_interviews i JOIN jobs j ON j.id=i.job_id WHERE j.biz_id=$1 AND i.status='scheduled' AND i.at > now()", [g.b.id])).rows[0].n;
    return { items, plan: { ...plan, active: await activeCount(g.b.id) }, team, role: g.role, enabled: enabled(), requireApproval: requireApproval(), upcomingInterviews: upcoming, types: TYPES.map((t) => ({ id: t, label: TYPE_AR[t] })), stages: STAGES.map((s) => ({ id: s, label: STAGE_AR[s] })), aiAvailable: typeof globalThis.naslifeAskClaude === "function" };
  });
  /// محرك الصياغة: يعيد مسودة كاملة (المصدر ai أو template) لا تُحفظ حتى يضغط صاحب العرض حفظاً
  app.post("/biz/:id/manage/jobs/draft", async (req, reply) => {
    const g = await hiringGuard(req, reply); if (!g) return;
    const b = req.body ?? {};
    const input = { title: str(b.title, 80), bullets: list(b.bullets, 8, 200), type: TYPES.includes(b.type) ? b.type : "full", city: str(b.city, 40) || cityOfBiz(g.b), department: str(b.department, 60), salaryMin: num(b.salaryMin), salaryMax: num(b.salaryMax), bizName: bizName(g.b) };
    if (!input.title) return bad(reply, 400, "title-required");
    if (rejectBanned(reply, input.title, ...input.bullets)) return;
    let out = null, aiError = null;
    if (b.useAi !== false) { try { out = await draftWithAi(input, g.b); } catch (e) { aiError = String(e?.message || e).slice(0, 80); out = null; } }
    if (!out) out = templateDraft(input);
    return { ...out, aiError, input };
  });
  const applyJobPatch = (j, b, { creating = false } = {}) => {
    const p = {};
    if (creating || b.title !== undefined) p.title = str(b.title, 80);
    if (b.titleEn !== undefined) p.title_en = str(b.titleEn, 80);
    if (b.department !== undefined) p.department = str(b.department, 60);
    if (b.description !== undefined) p.description = str(b.description, 6000);
    if (b.descriptionEn !== undefined) p.description_en = str(b.descriptionEn, 6000);
    if (b.requirements !== undefined) p.requirements = JSON.stringify(cleanRequirements(b.requirements));
    if (b.skills !== undefined) p.skills = list(b.skills, 12, 40);
    if (b.city !== undefined) p.city = str(b.city, 40);
    if (b.district !== undefined) p.district = str(b.district, 60);
    if (b.type !== undefined) p.type = TYPES.includes(b.type) ? b.type : "full";
    if (b.experienceMin !== undefined) p.experience_min = intOr(b.experienceMin, 0, 0, 30);
    if (b.education !== undefined) p.education = EDU.includes(b.education) ? b.education : "none";
    if (b.salaryMin !== undefined) p.salary_min = b.salaryMin == null || b.salaryMin === "" ? null : intOr(b.salaryMin, null, 0, 1000000);
    if (b.salaryMax !== undefined) p.salary_max = b.salaryMax == null || b.salaryMax === "" ? null : intOr(b.salaryMax, null, 0, 1000000);
    if (b.salaryVisible !== undefined) p.salary_visible = b.salaryVisible === true;
    if (b.openings !== undefined) p.openings = intOr(b.openings, 1, 1, 50);
    if (b.deadline !== undefined) { const d = b.deadline ? new Date(b.deadline) : null; p.deadline = d && !Number.isNaN(d.getTime()) ? d : null; }
    if (b.public !== undefined) p.public = b.public !== false;
    if (b.questions !== undefined) p.questions = JSON.stringify(cleanQuestions(b.questions));
    if (b.draftSource !== undefined) p.draft_source = ["ai", "template", "manual"].includes(b.draftSource) ? b.draftSource : null;
    return p;
  };
  const validJob = (j) => {
    if (!j.title || j.title.length < 3) return "bad-title";
    if (j.salary_min != null && j.salary_max != null && Number(j.salary_max) < Number(j.salary_min)) return "bad-salary";
    return null;
  };
  app.post("/biz/:id/manage/jobs", async (req, reply) => {
    const g = await hiringGuard(req, reply); if (!g) return;
    if (!enabled()) return bad(reply, 403, "unavailable");
    const b = req.body ?? {};
    const p = applyJobPatch(null, b, { creating: true });
    if (!p.city) p.city = cityOfBiz(g.b);
    if (b.assigneeId !== undefined) { const a = str(b.assigneeId, 12).toUpperCase(); if (a && !(await hiringTeam(g.b)).includes(a)) return bad(reply, 400, "bad-assignee"); p.assignee_id = a || null; }
    const err = validJob({ title: p.title, salary_min: p.salary_min, salary_max: p.salary_max }); if (err) return bad(reply, 400, err);
    if (rejectBanned(reply, p.title, p.description ?? "", p.department ?? "")) return;
    const id = crypto.randomUUID();
    const cols = ["id", "biz_id", "created_by", ...Object.keys(p)]; const vals = [id, g.b.id, g.uid, ...Object.values(p)];
    const r = await pool.query(`INSERT INTO jobs(${cols.join(",")}) VALUES(${cols.map((_, i) => `$${i + 1}`).join(",")}) RETURNING *`, vals);
    await event(id, null, g.uid, "job.created");
    let job = r.rows[0];
    if (b.publish === true) { const pub = await publishJob(job, g); if (pub.error) return bad(reply, pub.code, pub.error, pub.extra); job = pub.job; }
    return jobOut(job, { counts: await counts(job.id), matched: job.__matched });
  });
  app.patch("/biz/:id/manage/jobs/:jobId", async (req, reply) => {
    const g = await hiringGuard(req, reply); if (!g) return;
    const j = await jobFor(req, reply, g); if (!j) return;
    const b = req.body ?? {};
    const p = applyJobPatch(j, b);
    if (b.assigneeId !== undefined) { const a = str(b.assigneeId, 12).toUpperCase(); if (a && !(await hiringTeam(g.b)).includes(a)) return bad(reply, 400, "bad-assignee"); p.assignee_id = a || null; }
    if (!Object.keys(p).length) return jobOut(j, { counts: await counts(j.id) });
    const merged = { ...j, ...p }; const err = validJob(merged); if (err) return bad(reply, 400, err);
    if (rejectBanned(reply, p.title ?? "", p.description ?? "", p.department ?? "")) return;
    const keys = Object.keys(p);
    const r = await pool.query(`UPDATE jobs SET ${keys.map((k, i) => `${k}=$${i + 2}`).join(", ")}, updated_at=now() WHERE id=$1 RETURNING *`, [j.id, ...keys.map((k) => p[k])]);
    await event(j.id, null, g.uid, "job.updated", { fields: keys });
    return jobOut(r.rows[0], { counts: await counts(j.id) });
  });
  async function publishJob(j, g) {
    if (!enabled()) return { error: "unavailable", code: 403 };
    if (!["draft", "paused", "closed", "filled", "pending"].includes(j.status)) return { error: "bad-state", code: 409, extra: { status: j.status } };
    const err = validJob(j); if (err) return { error: err, code: 400 };
    if (!j.description || j.description.length < 30) return { error: "description-required", code: 400 };
    const plan = await planOf(j.biz_id);
    if (plan.plan === "free" && ["draft", "closed", "filled"].includes(j.status) && (await activeCount(j.biz_id)) >= plan.freeActive) return { error: "plan-limit", code: 402, extra: { freeActive: plan.freeActive } };
    const pending = requireApproval() && j.status !== "paused" && !(await isAdmin(g.uid));
    const status = pending ? "pending" : "open";
    const r = await pool.query("UPDATE jobs SET status=$2, published_at=coalesce(published_at, now()), closed_at=NULL, updated_at=now() WHERE id=$1 RETURNING *", [j.id, status]);
    const job = r.rows[0];
    await event(job.id, null, g.uid, pending ? "job.pending" : "job.published");
    if (pending) { await notifyAdmins({ kind: "job_review", title: `عرض وظيفي بانتظار الموافقة: ${job.title}`, body: bizName(g.b), data: { jobId: job.id, bizId: job.biz_id } }); job.__matched = null; }
    else job.__matched = await matchJob(job);
    return { job };
  }
  app.post("/biz/:id/manage/jobs/:jobId/publish", async (req, reply) => {
    const g = await hiringGuard(req, reply); if (!g) return;
    const j = await jobFor(req, reply, g); if (!j) return;
    const pub = await publishJob(j, g); if (pub.error) return bad(reply, pub.code, pub.error, pub.extra);
    return jobOut(pub.job, { counts: await counts(j.id), matched: pub.job.__matched });
  });
  app.post("/biz/:id/manage/jobs/:jobId/pause", async (req, reply) => {
    const g = await hiringGuard(req, reply); if (!g) return;
    const j = await jobFor(req, reply, g); if (!j) return;
    if (j.status !== "open") return bad(reply, 409, "bad-state", { status: j.status });
    const r = await pool.query("UPDATE jobs SET status='paused', updated_at=now() WHERE id=$1 RETURNING *", [j.id]);
    await event(j.id, null, g.uid, "job.paused");
    return jobOut(r.rows[0], { counts: await counts(j.id) });
  });
  app.post("/biz/:id/manage/jobs/:jobId/close", async (req, reply) => {
    const g = await hiringGuard(req, reply); if (!g) return;
    const j = await jobFor(req, reply, g); if (!j) return;
    if (["closed", "filled"].includes(j.status)) return bad(reply, 409, "bad-state", { status: j.status });
    const filled = req.body?.filled === true;
    const r = await pool.query("UPDATE jobs SET status=$2, closed_at=now(), updated_at=now() WHERE id=$1 RETURNING *", [j.id, filled ? "filled" : "closed"]);
    await pool.query("UPDATE job_matches SET status='expired', updated_at=now() WHERE job_id=$1 AND status IN ('sent','viewed','later')", [j.id]);
    await event(j.id, null, g.uid, filled ? "job.filled" : "job.closed");
    return jobOut(r.rows[0], { counts: await counts(j.id) });
  });
  app.post("/biz/:id/manage/jobs/:jobId/duplicate", async (req, reply) => {
    const g = await hiringGuard(req, reply); if (!g) return;
    const j = await jobFor(req, reply, g); if (!j) return;
    const id = crypto.randomUUID();
    const r = await pool.query(`INSERT INTO jobs(id,biz_id,created_by,assignee_id,title,title_en,department,description,description_en,requirements,skills,city,district,type,experience_min,education,salary_min,salary_max,salary_visible,openings,questions,public,draft_source)
      SELECT $1,biz_id,$3,assignee_id,title,title_en,department,description,description_en,requirements,skills,city,district,type,experience_min,education,salary_min,salary_max,salary_visible,openings,questions,public,draft_source FROM jobs WHERE id=$2 RETURNING *`, [id, j.id, g.uid]);
    await event(id, null, g.uid, "job.duplicated", { from: j.id });
    return jobOut(r.rows[0], { counts: await counts(id) });
  });
  app.delete("/biz/:id/manage/jobs/:jobId", async (req, reply) => {
    const g = await hiringGuard(req, reply); if (!g) return;
    const j = await jobFor(req, reply, g); if (!j) return;
    if (j.status !== "draft") return bad(reply, 409, "not-draft");
    await pool.query("DELETE FROM jobs WHERE id=$1", [j.id]);
    await pool.query("DELETE FROM job_events WHERE job_id=$1", [j.id]);
    return { ok: true };
  });
  app.get("/biz/:id/manage/jobs/:jobId/preview-match", async (req, reply) => {
    const g = await hiringGuard(req, reply); if (!g) return;
    const j = await jobFor(req, reply, g); if (!j) return;
    return previewMatch(j);
  });
  /// معاينة لمسودة غير محفوظة (المنشئ قبل الحفظ)
  app.post("/biz/:id/manage/jobs/preview-match", async (req, reply) => {
    const g = await hiringGuard(req, reply); if (!g) return;
    const p = applyJobPatch(null, req.body ?? {}, { creating: true });
    return previewMatch({ biz_id: g.b.id, title: p.title ?? "", skills: p.skills ?? [], city: p.city ?? cityOfBiz(g.b), type: p.type ?? "full", experience_min: p.experience_min ?? 0, salary_max: p.salary_max ?? null, department: p.department ?? "" });
  });

  // ---- المرشحون: مجهولون حتى يجيبوا (قرار المالك)، ثم الملف العام وملف التوظيف والإجابات
  const candidateOut = async (m, { reveal }) => {
    const notes = (await pool.query("SELECT count(*)::int AS n, avg(rating)::numeric(3,1) AS r FROM job_notes WHERE match_id=$1", [m.id])).rows[0];
    const iv = (await pool.query("SELECT * FROM job_interviews WHERE match_id=$1 ORDER BY at DESC", [m.id])).rows;
    const base = {
      id: m.id, jobId: m.job_id, seq: Number(m.seq), label: `مرشح #${m.seq}`, anonymous: !reveal, status: m.status, stage: m.stage, stageLabel: STAGE_AR[m.stage] ?? m.stage, source: m.source,
      score: Number(m.score), reasons: parseJson(m.reasons, []), sentAt: m.sent_at, viewedAt: m.viewed_at, acceptedAt: m.accepted_at, answeredAt: m.answered_at, declinedAt: m.declined_at,
      assignee: m.assignee_id ? await person(m.assignee_id) : null, notesCount: notes.n, rating: notes.r == null ? null : Number(notes.r), updatedAt: m.updated_at,
      interviews: iv.map((i) => ({ id: i.id, at: i.at, mode: i.mode, place: i.place, note: i.note, status: i.status })),
    };
    if (!reveal) return base;
    const p = (await pool.query("SELECT * FROM job_profiles WHERE user_id=$1", [m.user_id])).rows[0];
    return { ...base, user: await person(m.user_id), profile: p ? profileOut(p) : null, answers: parseJson(m.answers, []) };
  };
  const revealed = (m) => ["answered", "withdrawn"].includes(m.status) || m.answered_at != null;
  app.get("/biz/:id/manage/jobs/:jobId/candidates", async (req, reply) => {
    const g = await hiringGuard(req, reply); if (!g) return;
    const j = await jobFor(req, reply, g); if (!j) return;
    const stage = STAGES.includes(req.query?.stage) ? req.query.stage : null;
    const rows = (await pool.query(`SELECT * FROM job_matches WHERE job_id=$1 ${stage ? "AND stage=$2" : ""} ORDER BY CASE WHEN answered_at IS NULL THEN 1 ELSE 0 END, score DESC, sent_at DESC LIMIT 300`, stage ? [j.id, stage] : [j.id])).rows;
    const items = await Promise.all(rows.map((m) => candidateOut(m, { reveal: revealed(m) })));
    return { job: jobOut(j), items, counts: await counts(j.id), stages: STAGES.map((s) => ({ id: s, label: STAGE_AR[s], n: items.filter((i) => i.stage === s).length })) };
  });
  const candidateFor = async (req, reply, g) => {
    const j = await jobFor(req, reply, g); if (!j) return null;
    const id = String(req.params.matchId ?? ""); if (!UUID_RE.test(id)) { bad(reply, 400, "bad-id"); return null; }
    const m = (await pool.query("SELECT * FROM job_matches WHERE id=$1 AND job_id=$2", [id, j.id])).rows[0];
    if (!m) { bad(reply, 404, "not-found"); return null; }
    return { j, m };
  };
  app.get("/biz/:id/manage/jobs/:jobId/candidates/:matchId", async (req, reply) => {
    const g = await hiringGuard(req, reply); if (!g) return;
    const x = await candidateFor(req, reply, g); if (!x) return;
    const notes = (await pool.query("SELECT * FROM job_notes WHERE match_id=$1 ORDER BY created_at DESC", [x.m.id])).rows;
    const events = (await pool.query("SELECT * FROM job_events WHERE match_id=$1 ORDER BY created_at DESC LIMIT 50", [x.m.id])).rows;
    return { ...(await candidateOut(x.m, { reveal: revealed(x.m) })), notes: await Promise.all(notes.map(async (n) => ({ id: n.id, author: await person(n.author_id), text: n.text, rating: n.rating, createdAt: n.created_at }))), events: events.map((e) => ({ kind: e.kind, actorId: e.actor_id, data: parseJson(e.data, {}), at: e.created_at })) };
  });
  /// تغيير المرحلة أو الإسناد؛ المراحل المتقدمة (مقابلة/عرض/تعيين/اعتذار) تُخطر المرشح
  app.patch("/biz/:id/manage/jobs/:jobId/candidates/:matchId", async (req, reply) => {
    const g = await hiringGuard(req, reply); if (!g) return;
    const x = await candidateFor(req, reply, g); if (!x) return;
    const b = req.body ?? {}; const sets = []; const vals = [x.m.id];
    if (b.stage !== undefined) {
      if (!STAGES.includes(b.stage)) return bad(reply, 400, "bad-stage");
      if (!revealed(x.m) && ["interview", "offer", "hired"].includes(b.stage)) return bad(reply, 409, "not-revealed");
      vals.push(b.stage); sets.push(`stage=$${vals.length}`);
    }
    if (b.assigneeId !== undefined) { const a = str(b.assigneeId, 12).toUpperCase(); if (a && !(await hiringTeam(g.b)).includes(a)) return bad(reply, 400, "bad-assignee"); vals.push(a || null); sets.push(`assignee_id=$${vals.length}`); }
    if (!sets.length) return bad(reply, 400, "nothing");
    const r = await pool.query(`UPDATE job_matches SET ${sets.join(", ")}, updated_at=now() WHERE id=$1 RETURNING *`, vals);
    const m = r.rows[0];
    if (b.stage !== undefined && b.stage !== x.m.stage) {
      await event(x.j.id, m.id, g.uid, "stage.changed", { from: x.m.stage, to: b.stage });
      const msgs = { interview: "انتقلت إلى مرحلة المقابلة", offer: "لديك عرض عمل من الدائرة", hired: "مبروك، تم تعيينك", rejected: "شكراً لاهتمامك؛ اعتذرت الدائرة هذه المرة" };
      if (msgs[b.stage]) await notify(m.user_id, { kind: "job_stage", title: `${x.j.title} · ${STAGE_AR[b.stage]}`, body: `${bizName(g.b)}: ${msgs[b.stage]}`, data: { jobId: x.j.id, matchId: m.id, bizId: g.b.id, stage: b.stage } });
      if (b.stage === "hired") await pool.query("UPDATE jobs SET status=CASE WHEN (SELECT count(*) FROM job_matches WHERE job_id=$1 AND stage='hired') >= openings THEN 'filled' ELSE status END, closed_at=CASE WHEN (SELECT count(*) FROM job_matches WHERE job_id=$1 AND stage='hired') >= openings THEN now() ELSE closed_at END WHERE id=$1", [x.j.id]);
    }
    return candidateOut(m, { reveal: revealed(m) });
  });
  app.post("/biz/:id/manage/jobs/:jobId/candidates/:matchId/notes", async (req, reply) => {
    const g = await hiringGuard(req, reply); if (!g) return;
    const x = await candidateFor(req, reply, g); if (!x) return;
    const text = str(req.body?.text, 1500); const rating = req.body?.rating == null ? null : intOr(req.body.rating, null, 1, 5);
    if (!text && rating == null) return bad(reply, 400, "empty");
    const id = crypto.randomUUID();
    await pool.query("INSERT INTO job_notes(id,match_id,author_id,text,rating) VALUES($1,$2,$3,$4,$5)", [id, x.m.id, g.uid, text, rating]);
    await event(x.j.id, x.m.id, g.uid, "note.added", { rating });
    return { id, author: await person(g.uid), text, rating, createdAt: new Date() };
  });
  app.delete("/biz/:id/manage/jobs/:jobId/candidates/:matchId/notes/:noteId", async (req, reply) => {
    const g = await hiringGuard(req, reply); if (!g) return;
    const x = await candidateFor(req, reply, g); if (!x) return;
    const nid = String(req.params.noteId ?? ""); if (!UUID_RE.test(nid)) return bad(reply, 400, "bad-id");
    const r = await pool.query("DELETE FROM job_notes WHERE id=$1 AND match_id=$2 AND (author_id=$3 OR $4)", [nid, x.m.id, g.uid, g.role !== "hr"]);
    return { ok: r.rowCount > 0 };
  });
  app.post("/biz/:id/manage/jobs/:jobId/candidates/:matchId/interviews", async (req, reply) => {
    const g = await hiringGuard(req, reply); if (!g) return;
    const x = await candidateFor(req, reply, g); if (!x) return;
    if (!revealed(x.m)) return bad(reply, 409, "not-revealed");
    const at = new Date(req.body?.at ?? ""); if (Number.isNaN(at.getTime()) || at.getTime() < Date.now() - 3600000) return bad(reply, 400, "bad-time");
    const mode = ["onsite", "call", "video"].includes(req.body?.mode) ? req.body.mode : "onsite";
    const place = str(req.body?.place, 200), note = str(req.body?.note, 500);
    const id = crypto.randomUUID();
    await pool.query("INSERT INTO job_interviews(id,match_id,job_id,at,mode,place,note,created_by) VALUES($1,$2,$3,$4,$5,$6,$7,$8)", [id, x.m.id, x.j.id, at, mode, place, note, g.uid]);
    if (x.m.stage === "answered" || x.m.stage === "screening" || x.m.stage === "new") await pool.query("UPDATE job_matches SET stage='interview', updated_at=now() WHERE id=$1", [x.m.id]);
    await event(x.j.id, x.m.id, g.uid, "interview.scheduled", { at, mode });
    const when = at.toISOString().slice(0, 16).replace("T", " ");
    await notify(x.m.user_id, { kind: "job_interview", title: `موعد مقابلة: ${x.j.title}`, body: `${bizName(g.b)} · ${when} · ${mode === "onsite" ? place || "في المقر" : mode === "video" ? "اتصال مرئي" : "اتصال هاتفي"}`, data: { jobId: x.j.id, matchId: x.m.id, interviewId: id, bizId: g.b.id } });
    return { id, at, mode, place, note, status: "scheduled" };
  });
  app.patch("/biz/:id/manage/jobs/:jobId/candidates/:matchId/interviews/:interviewId", async (req, reply) => {
    const g = await hiringGuard(req, reply); if (!g) return;
    const x = await candidateFor(req, reply, g); if (!x) return;
    const iid = String(req.params.interviewId ?? ""); if (!UUID_RE.test(iid)) return bad(reply, 400, "bad-id");
    const status = ["scheduled", "done", "cancelled"].includes(req.body?.status) ? req.body.status : null; if (!status) return bad(reply, 400, "bad-status");
    const r = await pool.query("UPDATE job_interviews SET status=$3 WHERE id=$1 AND match_id=$2 RETURNING *", [iid, x.m.id, status]);
    if (!r.rowCount) return bad(reply, 404, "not-found");
    await event(x.j.id, x.m.id, g.uid, `interview.${status}`);
    if (status === "cancelled") await notify(x.m.user_id, { kind: "job_interview", title: `أُلغيت المقابلة: ${x.j.title}`, body: bizName(g.b), data: { jobId: x.j.id, matchId: x.m.id, bizId: g.b.id } });
    return { ok: true, status };
  });
  app.get("/biz/:id/manage/jobs/:jobId/stats", async (req, reply) => {
    const g = await hiringGuard(req, reply); if (!g) return;
    const j = await jobFor(req, reply, g); if (!j) return;
    const c = await counts(j.id);
    const t = (await pool.query("SELECT avg(EXTRACT(EPOCH FROM (answered_at - sent_at))/86400)::numeric(6,1) AS d_answer, avg(EXTRACT(EPOCH FROM (viewed_at - sent_at))/3600)::numeric(6,1) AS h_view FROM job_matches WHERE job_id=$1", [j.id])).rows[0];
    const funnel = [["sent", "أُرسل", c.sent], ["viewed", "شاهد", c.viewed], ["accepted", "قبِل", c.accepted], ["answered", "أجاب", c.answered], ["interview", "مقابلة", (c.byStage.interview ?? 0) + (c.byStage.offer ?? 0) + (c.byStage.hired ?? 0)], ["hired", "تعيين", c.byStage.hired ?? 0]].map(([id, label, n]) => ({ id, label, n }));
    const declines = (await pool.query("SELECT decline_reason AS reason, count(*)::int AS n FROM job_matches WHERE job_id=$1 AND status='declined' AND decline_reason IS NOT NULL GROUP BY 1 ORDER BY 2 DESC LIMIT 5", [j.id])).rows;
    return { job: jobOut(j), funnel, avgDaysToAnswer: t.d_answer == null ? null : Number(t.d_answer), avgHoursToView: t.h_view == null ? null : Number(t.h_view), views: Number(j.views ?? 0), declines, byStage: c.byStage };
  });
  app.get("/biz/:id/manage/jobs/stats", async (req, reply) => {
    const g = await hiringGuard(req, reply); if (!g) return;
    const r = (await pool.query(`SELECT count(*) FILTER (WHERE j.status='open')::int AS open, count(*) FILTER (WHERE j.status='filled')::int AS filled,
      (SELECT count(*)::int FROM job_matches m JOIN jobs jj ON jj.id=m.job_id WHERE jj.biz_id=$1) AS candidates,
      (SELECT count(*)::int FROM job_matches m JOIN jobs jj ON jj.id=m.job_id WHERE jj.biz_id=$1 AND m.answered_at IS NOT NULL) AS answered,
      (SELECT count(*)::int FROM job_matches m JOIN jobs jj ON jj.id=m.job_id WHERE jj.biz_id=$1 AND m.stage='hired') AS hired,
      (SELECT count(*)::int FROM job_interviews i JOIN jobs jj ON jj.id=i.job_id WHERE jj.biz_id=$1 AND i.status='scheduled' AND i.at > now()) AS interviews
      FROM jobs j WHERE j.biz_id=$1`, [g.b.id])).rows[0];
    return { open: r.open, filled: r.filled, candidates: r.candidates, answered: r.answered, hired: r.hired, upcomingInterviews: r.interviews, plan: await planOf(g.b.id) };
  });
  /// تصدير CSV للمرشحين الذين أجابوا (باقة pro)
  app.get("/biz/:id/manage/jobs/:jobId/export", async (req, reply) => {
    const g = await hiringGuard(req, reply); if (!g) return;
    const j = await jobFor(req, reply, g); if (!j) return;
    if ((await planOf(g.b.id)).plan !== "pro") return bad(reply, 402, "pro-required");
    const rows = (await pool.query("SELECT * FROM job_matches WHERE job_id=$1 AND answered_at IS NOT NULL ORDER BY score DESC", [j.id])).rows;
    const qs = parseJson(j.questions, []);
    const esc = (v) => `"${String(v ?? "").replace(/"/g, '""')}"`;
    const head = ["المرشح", "الرقم", "المرحلة", "الدرجة", "المدينة", "الخبرة", "الراتب المتوقع", ...qs.map((q) => q.text)];
    const lines = [head.map(esc).join(",")];
    for (const m of rows) {
      const u = await person(m.user_id); const p = (await pool.query("SELECT * FROM job_profiles WHERE user_id=$1", [m.user_id])).rows[0];
      const ans = parseJson(m.answers, []);
      lines.push([u.nickname, m.user_id, STAGE_AR[m.stage] ?? m.stage, Number(m.score), p?.city ?? "", p?.experience_years ?? "", p?.salary_min ?? "", ...qs.map((q) => { const a = ans.find((x) => x.id === q.id); const v = a?.value; return v === true ? "نعم" : v === false ? "لا" : v ?? ""; })].map(esc).join(","));
    }
    reply.header("content-type", "text/csv; charset=utf-8").header("content-disposition", `attachment; filename="candidates-${j.id.slice(0, 8)}.csv"`);
    return "﻿" + lines.join("\n");
  });

  // ================================================================ الإدارة العامة
  const adminGuard = async (req, reply) => { const uid = await auth(req); if (!uid) { unauthorized(reply); return null; } if (!(await isAdmin(uid))) { bad(reply, 403, "admin-only"); return null; } return uid; };
  app.get("/adminapi/jobs", async (req, reply) => {
    const uid = await adminGuard(req, reply); if (!uid) return;
    const status = JOB_STATUS.includes(req.query?.status) ? req.query.status : null;
    const rows = (await pool.query(`SELECT j.*, b.name AS biz_name, b.name_ar AS biz_name_ar FROM jobs j LEFT JOIN biz b ON b.id=j.biz_id ${status ? "WHERE j.status=$1" : ""} ORDER BY CASE j.status WHEN 'pending' THEN 0 ELSE 1 END, j.updated_at DESC LIMIT 200`, status ? [status] : [])).rows;
    const items = await Promise.all(rows.map(async (j) => jobOut(j, { bizName: j.biz_name_ar || j.biz_name || j.biz_id, counts: await counts(j.id), plan: (await planOf(j.biz_id)).plan })));
    const totals = (await pool.query("SELECT (SELECT count(*)::int FROM jobs WHERE status='open') AS open, (SELECT count(*)::int FROM jobs WHERE status='pending') AS pending, (SELECT count(*)::int FROM job_profiles WHERE active) AS seekers, (SELECT count(*)::int FROM job_matches WHERE stage='hired') AS hired")).rows[0];
    return { items, totals, settings: { jobsEnabled: enabled(), jobsFreeActive: freeActive(), jobsWeeklyCap: weeklyCap(), jobsMinScore: minScore(), jobsRequireApproval: requireApproval() } };
  });
  app.post("/adminapi/jobs/:id/approve", async (req, reply) => {
    const uid = await adminGuard(req, reply); if (!uid) return;
    const j = (await pool.query("SELECT * FROM jobs WHERE id=$1 AND status='pending'", [String(req.params.id)])).rows[0]; if (!j) return bad(reply, 404, "not-found");
    const r = await pool.query("UPDATE jobs SET status='open', updated_at=now() WHERE id=$1 RETURNING *", [j.id]);
    await event(j.id, null, uid, "job.approved");
    const matched = await matchJob(r.rows[0]);
    const b = await bizRow(j.biz_id);
    await notify(await hiringTeam(b), { kind: "job_review", title: `نُشر عرضك: ${j.title}`, body: `وصل إلى ${matched.sent} مرشحاً مطابقاً`, data: { jobId: j.id, bizId: j.biz_id, manage: true } });
    return jobOut(r.rows[0], { matched });
  });
  app.post("/adminapi/jobs/:id/close", async (req, reply) => {
    const uid = await adminGuard(req, reply); if (!uid) return;
    const j = (await pool.query("SELECT * FROM jobs WHERE id=$1", [String(req.params.id)])).rows[0]; if (!j) return bad(reply, 404, "not-found");
    const reason = str(req.body?.reason, 300);
    await pool.query("UPDATE jobs SET status='closed', closed_at=now(), updated_at=now() WHERE id=$1", [j.id]);
    await pool.query("UPDATE job_matches SET status='expired', updated_at=now() WHERE job_id=$1 AND status IN ('sent','viewed','later')", [j.id]);
    await event(j.id, null, uid, "job.closed", { by: "admin", reason });
    const b = await bizRow(j.biz_id);
    await notify(await hiringTeam(b), { kind: "job_review", title: `أغلقت الإدارة عرض: ${j.title}`, body: reason || "خالف سياسة النشر", data: { jobId: j.id, bizId: j.biz_id, manage: true } });
    return { ok: true };
  });
  app.get("/adminapi/jobs/plans/:bizId", async (req, reply) => { const uid = await adminGuard(req, reply); if (!uid) return; return planOf(String(req.params.bizId)); });
  app.put("/adminapi/jobs/plans/:bizId", async (req, reply) => {
    const uid = await adminGuard(req, reply); if (!uid) return;
    const b = await bizRow(String(req.params.bizId)); if (!b) return bad(reply, 404, "not-found");
    const plan = req.body?.plan === "pro" ? "pro" : "free";
    const months = intOr(req.body?.months, 1, 1, 36);
    const until = plan === "pro" ? new Date(Date.now() + months * 30 * DAY) : null;
    await pool.query("INSERT INTO job_plans(biz_id,plan,until,granted_by,updated_at) VALUES($1,$2,$3,$4,now()) ON CONFLICT (biz_id) DO UPDATE SET plan=EXCLUDED.plan, until=EXCLUDED.until, granted_by=EXCLUDED.granted_by, updated_at=now()", [b.id, plan, until, uid]);
    if (plan === "pro") await notify(await hiringTeam(b), { kind: "job_review", title: "باقة التوظيف المتقدمة مفعّلة", body: `${bizName(b)}: عروض بلا حد وتصدير المرشحين حتى ${until.toISOString().slice(0, 10)}`, data: { bizId: b.id, manage: true } });
    return planOf(b.id);
  });
  app.post("/adminapi/jobs/sweep", async (req, reply) => { const uid = await adminGuard(req, reply); if (!uid) return; return sweep(); });
  app.get("/jobs/status", async () => ({ ok: true, enabled: enabled(), sweepEveryMs: SWEEP_MS, ai: typeof globalThis.naslifeAskClaude === "function" }));
}
