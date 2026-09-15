// الدخول بالبريد الإلكتروني: النواة لا تقبل «@» في النك نيم، فنحفظ لكل مستخدم بريداً بديلاً (login_aliases) ونحوّل
// طلب الدخول بالبريد إلى دخول النواة بالنك نيم نفسه وكلمة السر نفسها (طلب داخلي إلى /login) فيبقى التحقق كله في النواة.
// التحقق من البريد: عند تعيين بريد جديد يُرسل رمز من 6 أرقام عبر خدمة البريد (server/mail.js عبر globalThis.naslifeMail)
// صالح 15 دقيقة وبخمس محاولات؛ الدخول بالبريد ممكن قبل التحقق، والتحقق يثبت أن البريد يخص صاحب الحساب.
// المسارات: POST /auth/login {handle, password} (بريد أو نك نيم)، GET/PUT/DELETE /me/login-email (للمستخدم نفسه)،
// POST /me/login-email/send-code، POST /me/login-email/verify {code}، GET /auth/alias/status،
// وتمهيد من server/admin_bootstrap.js (LOGIN_ALIASES، تُعدّ مؤكَّدة) عند الإقلاع.
// التسجيل: await app.register((await import("./auth_alias.js")).default, { pool, auth });
import crypto from "node:crypto";

const EMAIL_RE = /^[a-z0-9][a-z0-9._%+-]{0,63}@[a-z0-9.-]+\.[a-z]{2,}$/;
const ID_RE = /^[A-Z]{2}\d{7}$/;
const CODE_TTL_MIN = 15, CODE_MAX_ATTEMPTS = 5, RESEND_SECONDS = 60;

export const normEmail = (v) => String(v ?? "").trim().toLowerCase();
const hashCode = (email, code) => crypto.createHash("sha256").update(`${email}:${code}`).digest("hex");

export default async function authAlias(app, opts = {}) {
  const pool = opts.pool ?? globalThis.naslifePool ?? null;
  const auth = opts.auth ?? globalThis.naslifeAuth ?? null;
  if (!pool) throw new Error("auth_alias: pool is required");
  await pool.query(`CREATE TABLE IF NOT EXISTS login_aliases (alias TEXT PRIMARY KEY, user_id TEXT NOT NULL, nickname TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE INDEX IF NOT EXISTS login_aliases_user ON login_aliases(user_id);
    ALTER TABLE login_aliases ADD COLUMN IF NOT EXISTS verified BOOLEAN NOT NULL DEFAULT false, ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ,
      ADD COLUMN IF NOT EXISTS code_hash TEXT, ADD COLUMN IF NOT EXISTS code_exp TIMESTAMPTZ, ADD COLUMN IF NOT EXISTS code_sent_at TIMESTAMPTZ,
      ADD COLUMN IF NOT EXISTS attempts INT NOT NULL DEFAULT 0`);
  const bad = (reply, code, error, extra = {}) => reply.code(code).send({ error, ...extra });
  const nickOf = async (userId) => { try { return (await pool.query("SELECT nickname FROM users WHERE id=$1", [userId])).rows[0]?.nickname ?? null; } catch { return null; } };
  const mailSvc = () => globalThis.naslifeMail ?? null;
  const mailOn = () => { try { return mailSvc()?.configured?.() === true; } catch { return false; } };
  const rowOf = async (uid) => (await pool.query("SELECT alias, verified, verified_at, code_hash, code_exp, code_sent_at, attempts FROM login_aliases WHERE user_id=$1 ORDER BY created_at DESC LIMIT 1", [uid])).rows[0] ?? null;
  const info = (row) => ({ email: row?.alias ?? null, verified: row?.verified === true, mailConfigured: mailOn(), codeSentAt: row?.code_sent_at ?? null, codePending: !!(row?.code_hash && row.code_exp && new Date(row.code_exp) > new Date()) });

  // ---- تمهيد من المستودع: بريد ← معرّف مستخدم (مؤكَّد لأنه من المستودع؛ لا يُعاد تعيين بريد مستخدم غيّره بنفسه)
  try {
    const { LOGIN_ALIASES } = await import("./admin_bootstrap.js");
    for (const a of Array.isArray(LOGIN_ALIASES) ? LOGIN_ALIASES : []) {
      const email = normEmail(a?.email), userId = String(a?.userId ?? "").trim().toUpperCase();
      if (!EMAIL_RE.test(email) || !ID_RE.test(userId)) continue;
      const nickname = await nickOf(userId);
      if (!nickname) continue;
      const mine = (await pool.query("SELECT alias, verified FROM login_aliases WHERE user_id=$1", [userId])).rows;
      if (mine.length) { if (mine.some((r) => r.alias === email && !r.verified)) await pool.query("UPDATE login_aliases SET verified=true, verified_at=now() WHERE alias=$1", [email]); continue; }
      await pool.query("INSERT INTO login_aliases(alias, user_id, nickname, verified, verified_at) VALUES($1,$2,$3,true,now()) ON CONFLICT (alias) DO NOTHING", [email, userId, nickname]);
    }
  } catch { /* لا ملف تمهيد */ }

  /// يولّد رمزاً ويرسله بالبريد ويخزّن تجزئته؛ يرمي خطأً إن فشل الإرسال.
  async function sendCode(uid, email) {
    const svc = mailSvc();
    if (!svc || !mailOn()) throw new Error("mail-not-configured");
    const code = String(crypto.randomInt(0, 1000000)).padStart(6, "0");
    const t = svc.template({ title: "رمز تأكيد بريدك في ناس لايف", lines: ["أدخل هذا الرمز في التطبيق لتأكيد بريد الدخول.", `الرمز صالح لمدة ${CODE_TTL_MIN} دقيقة. إن لم تطلبه فتجاهل هذه الرسالة.`], code });
    await svc.send({ to: email, subject: "رمز تأكيد البريد · ناس لايف", ...t, tag: "verify" });
    await pool.query("UPDATE login_aliases SET code_hash=$2, code_exp=now() + ($3 || ' minutes')::interval, code_sent_at=now(), attempts=0 WHERE alias=$1", [email, hashCode(email, code), String(CODE_TTL_MIN)]);
    return code;
  }

  /// دخول بالبريد أو النك نيم: نحوّل البريد إلى نك نيم ثم نمرّر الطلب إلى /login في النواة كما هو.
  app.post("/auth/login", async (req, reply) => {
    const body = req.body && typeof req.body === "object" ? req.body : {};
    const raw = String(body.handle ?? body.nickname ?? body.email ?? "").trim();
    const password = String(body.password ?? body.pin ?? "");
    let handle = raw;
    if (raw.includes("@")) {
      const row = (await pool.query("SELECT user_id, nickname FROM login_aliases WHERE alias=$1", [normEmail(raw)])).rows[0];
      if (!row) return bad(reply, 401, "bad-credentials");
      handle = (await nickOf(row.user_id)) ?? row.nickname; // النك نيم الحالي إن تغيّر
    }
    const r = await app.inject({ method: "POST", url: "/login", headers: { "content-type": "application/json", "x-forwarded-for": String(req.headers["x-forwarded-for"] ?? req.ip ?? "") }, payload: JSON.stringify({ handle, password }) });
    return reply.code(r.statusCode).type(r.headers["content-type"] ?? "application/json; charset=utf-8").send(r.body);
  });

  const me = async (req, reply) => { if (!auth) { bad(reply, 503, "auth-unavailable"); return null; } const uid = await auth(req); if (!uid) { bad(reply, 401, "auth"); return null; } return uid; };
  app.get("/me/login-email", async (req, reply) => {
    const uid = await me(req, reply); if (!uid) return;
    return info(await rowOf(uid));
  });
  app.put("/me/login-email", async (req, reply) => {
    const uid = await me(req, reply); if (!uid) return;
    const email = normEmail(req.body?.email);
    if (!EMAIL_RE.test(email)) return bad(reply, 400, "bad-email");
    const taken = (await pool.query("SELECT user_id FROM login_aliases WHERE alias=$1", [email])).rows[0];
    if (taken && taken.user_id !== uid) return bad(reply, 409, "email-taken");
    const current = await rowOf(uid);
    if (current?.alias === email) return { ...info(current), codeSent: false };
    const nickname = (await nickOf(uid)) ?? "";
    await pool.query("DELETE FROM login_aliases WHERE user_id=$1", [uid]);
    await pool.query("INSERT INTO login_aliases(alias, user_id, nickname) VALUES($1,$2,$3)", [email, uid, nickname]);
    let codeSent = false, sendError = null;
    if (mailOn()) { try { await sendCode(uid, email); codeSent = true; } catch (e) { sendError = String(e?.message ?? e).slice(0, 200); } }
    return { ...info(await rowOf(uid)), codeSent, ...(sendError ? { sendError } : {}) };
  });
  app.delete("/me/login-email", async (req, reply) => {
    const uid = await me(req, reply); if (!uid) return;
    await pool.query("DELETE FROM login_aliases WHERE user_id=$1", [uid]);
    return { ok: true };
  });
  /// إرسال رمز التأكيد (أو إعادته): مرة كل 60 ثانية.
  app.post("/me/login-email/send-code", async (req, reply) => {
    const uid = await me(req, reply); if (!uid) return;
    const row = await rowOf(uid);
    if (!row) return bad(reply, 400, "no-email");
    if (row.verified) return bad(reply, 400, "already-verified");
    if (!mailOn()) return bad(reply, 503, "mail-not-configured");
    const since = row.code_sent_at ? (Date.now() - new Date(row.code_sent_at).getTime()) / 1000 : Infinity;
    if (since < RESEND_SECONDS) return bad(reply, 429, "too-soon", { retryIn: Math.ceil(RESEND_SECONDS - since) });
    try { await sendCode(uid, row.alias); } catch (e) { return bad(reply, 502, "send-failed", { detail: String(e?.message ?? e).slice(0, 200) }); }
    return { ok: true, email: row.alias, expiresIn: CODE_TTL_MIN * 60 };
  });
  /// التحقق من الرمز: خمس محاولات ثم يلزم طلب رمز جديد.
  app.post("/me/login-email/verify", async (req, reply) => {
    const uid = await me(req, reply); if (!uid) return;
    const code = String(req.body?.code ?? "").replace(/[^0-9]/g, "");
    const row = await rowOf(uid);
    if (!row) return bad(reply, 400, "no-email");
    if (row.verified) return { ok: true, ...info(row) };
    if (!row.code_hash || !row.code_exp) return bad(reply, 400, "no-code");
    if (new Date(row.code_exp) < new Date()) return bad(reply, 410, "code-expired");
    if (row.attempts >= CODE_MAX_ATTEMPTS) return bad(reply, 429, "too-many-attempts");
    if (code.length !== 6 || hashCode(row.alias, code) !== row.code_hash) {
      const r = await pool.query("UPDATE login_aliases SET attempts=attempts+1 WHERE alias=$1 RETURNING attempts", [row.alias]);
      return bad(reply, 400, "bad-code", { attemptsLeft: Math.max(0, CODE_MAX_ATTEMPTS - (r.rows[0]?.attempts ?? CODE_MAX_ATTEMPTS)) });
    }
    await pool.query("UPDATE login_aliases SET verified=true, verified_at=now(), code_hash=NULL, code_exp=NULL, attempts=0 WHERE alias=$1", [row.alias]);
    return { ok: true, ...info(await rowOf(uid)) };
  });
  app.get("/auth/alias/status", async () => {
    const c = (await pool.query("SELECT count(*)::int AS n, count(*) FILTER (WHERE verified)::int AS v FROM login_aliases")).rows[0];
    return { ok: true, aliases: c.n, verified: c.v, mailConfigured: mailOn() };
  });
}
