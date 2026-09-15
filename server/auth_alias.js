// الحسابات بالبريد الإلكتروني فوق نواة الخادم: النواة تملك النك نيم وكلمة السر وعبارة الاسترداد (/register، /login،
// /recover {handle, recoveryPhrase, newPassword})، وهذه الإضافة تربط كل حساب ببريد (login_aliases) وتحفظ عبارة الاسترداد
// مشفّرة (account_recovery) كي تعيد تعيين كلمة السر برمز يصل بالبريد بالطريقة الاعتيادية.
// المسارات:
//   POST /auth/register {email, nickname, password}   تسجيل بالبريد (ينشئ الحساب في النواة ويربط البريد ويحفظ العبارة)
//   POST /auth/login {handle, password}                دخول بالبريد أو النك نيم (يُمرَّر إلى /login في النواة)
//   POST /auth/forgot {email}                          إرسال رمز استعادة (الرد عام دائماً)
//   POST /auth/reset {email, code, password}           تعيين كلمة سر جديدة بالرمز ثم جلسة دخول
//   POST /auth/change-password {current, password}     تغيير كلمة السر (مسجَّل دخول) ويعيد جلسة جديدة
//   GET/PUT /me/recovery                               حالة الاستعادة بالبريد وتفعيلها للحسابات القديمة بعبارتها وكلمة سرها
//   GET/PUT/DELETE /me/login-email، POST /me/login-email/send-code، POST /me/login-email/verify، GET /auth/alias/status
// التشفير بمفتاح في OPS/auth-key (يُنشأ عند أول إقلاع) أو NASLIFE_AUTH_KEY. الرموز 6 أرقام صالحة 15 دقيقة بخمس محاولات.
// التسجيل: await app.register((await import("./auth_alias.js")).default, { pool, auth });
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const EMAIL_RE = /^[a-z0-9][a-z0-9._%+-]{0,63}@[a-z0-9.-]+\.[a-z]{2,}$/;
const ID_RE = /^[A-Z]{2}\d{7}$/;
const NICK_RE = /^[a-z0-9_]{3,32}$/;
const CODE_TTL_MIN = 15, CODE_MAX_ATTEMPTS = 5, RESEND_SECONDS = 60, PW_MIN = 8, PW_MAX = 64;

export const normEmail = (v) => String(v ?? "").trim().toLowerCase();
const hashCode = (email, code) => crypto.createHash("sha256").update(`${email}:${code}`).digest("hex");
const newCode = () => String(crypto.randomInt(0, 1000000)).padStart(6, "0");
const digits = (v) => String(v ?? "").replace(/[^0-9]/g, "");

/// مفتاح التشفير: من البيئة، أو ملف في مجلد التشغيل يُنشأ مرة واحدة.
function loadKey(opsDir) {
  const env = String(process.env.NASLIFE_AUTH_KEY ?? "").trim();
  if (/^[0-9a-f]{64}$/i.test(env)) return Buffer.from(env, "hex");
  const file = path.join(opsDir, "auth-key");
  try { const t = fs.readFileSync(file, "utf8").trim(); if (/^[0-9a-f]{64}$/i.test(t)) return Buffer.from(t, "hex"); } catch { /* لا ملف بعد */ }
  const key = crypto.randomBytes(32);
  try { fs.mkdirSync(opsDir, { recursive: true }); fs.writeFileSync(file, key.toString("hex") + "\n", { mode: 0o600 }); } catch (e) { console.warn("auth_alias: cannot persist auth-key:", e.message); }
  return key;
}
export function encrypt(key, text) {
  const iv = crypto.randomBytes(12);
  const c = crypto.createCipheriv("aes-256-gcm", key, iv);
  const ct = Buffer.concat([c.update(String(text), "utf8"), c.final()]);
  return `v1.${iv.toString("base64url")}.${c.getAuthTag().toString("base64url")}.${ct.toString("base64url")}`;
}
export function decrypt(key, blob) {
  const [v, iv, tag, ct] = String(blob ?? "").split(".");
  if (v !== "v1" || !iv || !tag || !ct) throw new Error("bad-blob");
  const d = crypto.createDecipheriv("aes-256-gcm", key, Buffer.from(iv, "base64url"));
  d.setAuthTag(Buffer.from(tag, "base64url"));
  return Buffer.concat([d.update(Buffer.from(ct, "base64url")), d.final()]).toString("utf8");
}

/// عدّاد محاولات بسيط في الذاكرة: يعيد true إن تجاوز المفتاح الحد داخل النافذة.
function makeLimiter() {
  const hits = new Map();
  return (key, max, windowMs) => {
    const now = Date.now();
    const arr = (hits.get(key) ?? []).filter((t) => now - t < windowMs);
    arr.push(now); hits.set(key, arr);
    if (hits.size > 5000) for (const [k, v] of hits) if (!v.some((t) => now - t < windowMs)) hits.delete(k);
    return arr.length > max;
  };
}

export default async function authAlias(app, opts = {}) {
  const pool = opts.pool ?? globalThis.naslifePool ?? null;
  const auth = opts.auth ?? globalThis.naslifeAuth ?? null;
  if (!pool) throw new Error("auth_alias: pool is required");
  const key = loadKey(opts.opsDir ?? process.env.NASLIFE_OPS_DIR ?? "/opt/naslife/ops");
  await pool.query(`CREATE TABLE IF NOT EXISTS login_aliases (alias TEXT PRIMARY KEY, user_id TEXT NOT NULL, nickname TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE INDEX IF NOT EXISTS login_aliases_user ON login_aliases(user_id);
    ALTER TABLE login_aliases ADD COLUMN IF NOT EXISTS verified BOOLEAN NOT NULL DEFAULT false, ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ,
      ADD COLUMN IF NOT EXISTS code_hash TEXT, ADD COLUMN IF NOT EXISTS code_exp TIMESTAMPTZ, ADD COLUMN IF NOT EXISTS code_sent_at TIMESTAMPTZ,
      ADD COLUMN IF NOT EXISTS attempts INT NOT NULL DEFAULT 0,
      ADD COLUMN IF NOT EXISTS reset_hash TEXT, ADD COLUMN IF NOT EXISTS reset_exp TIMESTAMPTZ, ADD COLUMN IF NOT EXISTS reset_sent_at TIMESTAMPTZ,
      ADD COLUMN IF NOT EXISTS reset_attempts INT NOT NULL DEFAULT 0;
    CREATE TABLE IF NOT EXISTS account_recovery (user_id TEXT PRIMARY KEY, phrase_enc TEXT NOT NULL, source TEXT NOT NULL DEFAULT 'register', updated_at TIMESTAMPTZ NOT NULL DEFAULT now())`);
  const bad = (reply, code, error, extra = {}) => reply.code(code).send({ error, ...extra });
  const limited = makeLimiter();
  const ipOf = (req) => String(req.headers["x-forwarded-for"] ?? req.ip ?? "").split(",")[0].trim();
  const nickOf = async (userId) => { try { return (await pool.query("SELECT nickname FROM users WHERE id=$1", [userId])).rows[0]?.nickname ?? null; } catch { return null; } };
  const mailSvc = () => globalThis.naslifeMail ?? null;
  const mailOn = () => { try { return mailSvc()?.configured?.() === true; } catch { return false; } };
  const rowOf = async (uid) => (await pool.query("SELECT alias, user_id, nickname, verified, verified_at, code_hash, code_exp, code_sent_at, attempts FROM login_aliases WHERE user_id=$1 ORDER BY created_at DESC LIMIT 1", [uid])).rows[0] ?? null;
  const rowByEmail = async (email) => (await pool.query("SELECT alias, user_id, nickname, verified, reset_hash, reset_exp, reset_sent_at, reset_attempts FROM login_aliases WHERE alias=$1", [email])).rows[0] ?? null;
  const recoveryOf = async (uid) => (await pool.query("SELECT phrase_enc FROM account_recovery WHERE user_id=$1", [uid])).rows[0]?.phrase_enc ?? null;
  const saveRecovery = (uid, phrase, source) => pool.query("INSERT INTO account_recovery(user_id, phrase_enc, source, updated_at) VALUES($1,$2,$3,now()) ON CONFLICT (user_id) DO UPDATE SET phrase_enc=EXCLUDED.phrase_enc, source=EXCLUDED.source, updated_at=now()", [uid, encrypt(key, phrase), source]);
  const info = (row) => ({ email: row?.alias ?? null, verified: row?.verified === true, mailConfigured: mailOn(), codeSentAt: row?.code_sent_at ?? null, codePending: !!(row?.code_hash && row.code_exp && new Date(row.code_exp) > new Date()) });
  const parseBody = (r) => { try { return r.json(); } catch { return {}; } };

  // ---- طلبات داخلية إلى النواة
  const core = (req, url, payload) => app.inject({ method: "POST", url, headers: { "content-type": "application/json", "x-forwarded-for": ipOf(req) }, payload: JSON.stringify(payload) });
  const coreRegister = (req, nickname, password) => core(req, "/register", { handle: nickname, nickname, password });
  const coreLogin = (req, handle, password) => core(req, "/login", { handle, password });
  const coreRecover = (req, nickname, phrase, newPassword) => core(req, "/recover", { handle: nickname, nickname, recoveryPhrase: phrase, newPassword, password: newPassword });
  const forward = (reply, r) => reply.code(r.statusCode).type(r.headers["content-type"] ?? "application/json; charset=utf-8").send(r.body);

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

  /// يولّد رمز تأكيد البريد ويرسله ويخزّن تجزئته؛ يرمي خطأً إن فشل الإرسال.
  async function sendVerifyCode(email) {
    const svc = mailSvc();
    if (!svc || !mailOn()) throw new Error("mail-not-configured");
    const code = newCode();
    const t = svc.template({ title: "رمز تأكيد بريدك في ناس لايف", lines: ["أدخل هذا الرمز في التطبيق لتأكيد بريد الدخول.", `الرمز صالح لمدة ${CODE_TTL_MIN} دقيقة. إن لم تطلبه فتجاهل هذه الرسالة.`], code });
    await svc.send({ to: email, subject: "رمز تأكيد البريد · ناس لايف", ...t, tag: "verify" });
    await pool.query("UPDATE login_aliases SET code_hash=$2, code_exp=now() + ($3 || ' minutes')::interval, code_sent_at=now(), attempts=0 WHERE alias=$1", [email, hashCode(email, code), String(CODE_TTL_MIN)]);
    return code;
  }
  /// يولّد رمز استعادة كلمة السر ويرسله.
  async function sendResetCode(email, nickname) {
    const svc = mailSvc();
    const code = newCode();
    const t = svc.template({ title: "رمز استعادة كلمة السر", lines: [`طلب أحدهم إعادة تعيين كلمة السر لحساب «${nickname}» في ناس لايف. أدخل هذا الرمز في التطبيق مع كلمة السر الجديدة.`, `الرمز صالح لمدة ${CODE_TTL_MIN} دقيقة. إن لم تطلبه فتجاهل هذه الرسالة وكلمة سرك تبقى كما هي.`], code });
    await svc.send({ to: email, subject: "استعادة كلمة السر · ناس لايف", ...t, tag: "reset" });
    await pool.query("UPDATE login_aliases SET reset_hash=$2, reset_exp=now() + ($3 || ' minutes')::interval, reset_sent_at=now(), reset_attempts=0 WHERE alias=$1", [email, hashCode("reset:" + email, code), String(CODE_TTL_MIN)]);
    return code;
  }

  // ================= التسجيل بالبريد =================
  app.post("/auth/register", async (req, reply) => {
    const b = req.body && typeof req.body === "object" ? req.body : {};
    const email = normEmail(b.email), nickname = String(b.nickname ?? b.handle ?? "").trim().toLowerCase(), password = String(b.password ?? "");
    if (!EMAIL_RE.test(email)) return bad(reply, 400, "bad-email");
    if (!NICK_RE.test(nickname)) return bad(reply, 400, "invalid-nickname");
    if (password.length < PW_MIN || password.length > PW_MAX) return bad(reply, 400, "weak-password");
    if (limited("reg:" + ipOf(req), 10, 15 * 60000)) return bad(reply, 429, "too-many-attempts");
    if (await rowByEmail(email)) return bad(reply, 409, "email-taken");
    const r = await coreRegister(req, nickname, password);
    if (r.statusCode < 200 || r.statusCode >= 300) return forward(reply, r);
    const body = parseBody(r);
    const userId = String(body.id ?? body.user?.id ?? "").toUpperCase();
    if (!ID_RE.test(userId)) return forward(reply, r);
    await pool.query("INSERT INTO login_aliases(alias, user_id, nickname) VALUES($1,$2,$3) ON CONFLICT (alias) DO NOTHING", [email, userId, nickname]);
    if (typeof body.recoveryPhrase === "string" && body.recoveryPhrase.trim()) await saveRecovery(userId, body.recoveryPhrase.trim(), "register");
    let codeSent = false;
    if (mailOn()) { try { await sendVerifyCode(email); codeSent = true; } catch { /* يُعاد الإرسال من ماي سبيس */ } }
    return reply.code(r.statusCode).send({ ...body, email, verified: false, codeSent });
  });

  // ================= الدخول بالبريد أو النك نيم =================
  app.post("/auth/login", async (req, reply) => {
    const body = req.body && typeof req.body === "object" ? req.body : {};
    const raw = String(body.handle ?? body.nickname ?? body.email ?? "").trim();
    const password = String(body.password ?? body.pin ?? "");
    let handle = raw;
    if (limited("login:" + ipOf(req), 30, 15 * 60000)) return bad(reply, 429, "too-many-attempts");
    if (raw.includes("@")) {
      const row = (await pool.query("SELECT user_id, nickname FROM login_aliases WHERE alias=$1", [normEmail(raw)])).rows[0];
      if (!row) return bad(reply, 401, "bad-credentials");
      handle = (await nickOf(row.user_id)) ?? row.nickname; // النك نيم الحالي إن تغيّر
    }
    return forward(reply, await coreLogin(req, handle, password));
  });

  // ================= نسيت كلمة السر =================
  app.post("/auth/forgot", async (req, reply) => {
    const email = normEmail(req.body?.email);
    if (!EMAIL_RE.test(email)) return bad(reply, 400, "bad-email");
    if (!mailOn()) return bad(reply, 503, "mail-not-configured");
    if (limited("forgot-ip:" + ipOf(req), 20, 15 * 60000) || limited("forgot:" + email, 5, 15 * 60000)) return bad(reply, 429, "too-many-attempts");
    const row = await rowByEmail(email);
    if (row) {
      const since = row.reset_sent_at ? (Date.now() - new Date(row.reset_sent_at).getTime()) / 1000 : Infinity;
      if (since < RESEND_SECONDS) return bad(reply, 429, "too-soon", { retryIn: Math.ceil(RESEND_SECONDS - since) });
      const nickname = (await nickOf(row.user_id)) ?? row.nickname;
      try {
        if (await recoveryOf(row.user_id)) await sendResetCode(email, nickname);
        else {
          const t = mailSvc().template({ title: "تعذّر إعادة تعيين كلمة السر", lines: [`طُلبت استعادة كلمة السر لحساب «${nickname}»، لكن الاستعادة بالبريد غير مفعّلة لهذا الحساب بعد.`, "ادخل بكلمة سرك الحالية ثم فعّلها من ماي سبيس ← «الاستعادة بالبريد» بإدخال عبارة الاسترداد، أو استخدم عبارة الاسترداد مباشرة."] });
          await mailSvc().send({ to: email, subject: "استعادة كلمة السر · ناس لايف", ...t, tag: "reset" });
          await pool.query("UPDATE login_aliases SET reset_sent_at=now() WHERE alias=$1", [email]);
        }
      } catch (e) { return bad(reply, 502, "send-failed", { detail: String(e?.message ?? e).slice(0, 200) }); }
    }
    return { ok: true };
  });

  app.post("/auth/reset", async (req, reply) => {
    const b = req.body && typeof req.body === "object" ? req.body : {};
    const email = normEmail(b.email), code = digits(b.code), password = String(b.password ?? b.newPassword ?? "");
    if (!EMAIL_RE.test(email)) return bad(reply, 400, "bad-email");
    if (password.length < PW_MIN || password.length > PW_MAX) return bad(reply, 400, "weak-password");
    if (limited("reset:" + email, 10, 15 * 60000)) return bad(reply, 429, "too-many-attempts");
    const row = await rowByEmail(email);
    if (!row || !row.reset_hash || !row.reset_exp) return bad(reply, 400, "bad-code");
    if (new Date(row.reset_exp) < new Date()) return bad(reply, 410, "code-expired");
    if (row.reset_attempts >= CODE_MAX_ATTEMPTS) return bad(reply, 429, "too-many-attempts");
    if (code.length !== 6 || hashCode("reset:" + email, code) !== row.reset_hash) {
      const r = await pool.query("UPDATE login_aliases SET reset_attempts=reset_attempts+1 WHERE alias=$1 RETURNING reset_attempts", [email]);
      return bad(reply, 400, "bad-code", { attemptsLeft: Math.max(0, CODE_MAX_ATTEMPTS - (r.rows[0]?.reset_attempts ?? CODE_MAX_ATTEMPTS)) });
    }
    const enc = await recoveryOf(row.user_id);
    if (!enc) return bad(reply, 409, "no-recovery");
    let phrase; try { phrase = decrypt(key, enc); } catch { return bad(reply, 500, "recovery-unreadable"); }
    const nickname = (await nickOf(row.user_id)) ?? row.nickname;
    const r = await coreRecover(req, nickname, phrase, password);
    if (r.statusCode < 200 || r.statusCode >= 300) {
      const eb = parseBody(r);
      if (r.statusCode === 401 && eb.error === "bad-code") { await pool.query("DELETE FROM account_recovery WHERE user_id=$1", [row.user_id]); return bad(reply, 409, "no-recovery"); }
      return forward(reply, r);
    }
    const body = parseBody(r);
    if (typeof body.recoveryPhrase === "string" && body.recoveryPhrase.trim()) await saveRecovery(row.user_id, body.recoveryPhrase.trim(), "reset");
    await pool.query("UPDATE login_aliases SET reset_hash=NULL, reset_exp=NULL, reset_attempts=0, verified=true, verified_at=COALESCE(verified_at, now()), code_hash=NULL, code_exp=NULL WHERE alias=$1", [email]);
    const { recoveryPhrase: _p, ...rest } = body;
    return { ...rest, email, verified: true };
  });

  // ================= المستخدم المسجَّل =================
  const me = async (req, reply) => { if (!auth) { bad(reply, 503, "auth-unavailable"); return null; } const uid = await auth(req); if (!uid) { bad(reply, 401, "auth"); return null; } return uid; };

  /// تغيير كلمة السر: نتحقق من الحالية عبر /login ثم نعيد التعيين بالعبارة المحفوظة (النواة تصدر جلسة جديدة وتلغي القديمة).
  app.post("/auth/change-password", async (req, reply) => {
    const uid = await me(req, reply); if (!uid) return;
    const current = String(req.body?.current ?? req.body?.currentPassword ?? ""), password = String(req.body?.password ?? req.body?.newPassword ?? "");
    if (password.length < PW_MIN || password.length > PW_MAX) return bad(reply, 400, "weak-password");
    if (limited("chpw:" + uid, 10, 15 * 60000)) return bad(reply, 429, "too-many-attempts");
    const nickname = await nickOf(uid);
    if (!nickname) return bad(reply, 404, "not-found");
    const l = await coreLogin(req, nickname, current);
    if (l.statusCode !== 200) return bad(reply, 403, "bad-password");
    const enc = await recoveryOf(uid);
    if (!enc) return bad(reply, 409, "no-recovery");
    let phrase; try { phrase = decrypt(key, enc); } catch { return bad(reply, 500, "recovery-unreadable"); }
    const r = await coreRecover(req, nickname, phrase, password);
    if (r.statusCode < 200 || r.statusCode >= 300) {
      const eb = parseBody(r);
      if (r.statusCode === 401 && eb.error === "bad-code") { await pool.query("DELETE FROM account_recovery WHERE user_id=$1", [uid]); return bad(reply, 409, "no-recovery"); }
      return forward(reply, r);
    }
    const body = parseBody(r);
    if (typeof body.recoveryPhrase === "string" && body.recoveryPhrase.trim()) await saveRecovery(uid, body.recoveryPhrase.trim(), "change");
    return { ok: true, token: body.token ?? null };
  });

  app.get("/me/recovery", async (req, reply) => {
    const uid = await me(req, reply); if (!uid) return;
    const row = await rowOf(uid);
    return { enabled: !!(await recoveryOf(uid)), email: row?.alias ?? null, verified: row?.verified === true, mailConfigured: mailOn() };
  });
  /// تفعيل الاستعادة بالبريد لحساب قديم: العبارة + كلمة السر الحالية (تُعاد كلمة السر نفسها فتُصدر النواة عبارة جديدة نحفظها).
  app.put("/me/recovery", async (req, reply) => {
    const uid = await me(req, reply); if (!uid) return;
    const phrase = String(req.body?.phrase ?? req.body?.recoveryPhrase ?? "").trim().replace(/\s+/g, " "), password = String(req.body?.password ?? "");
    if (!phrase) return bad(reply, 400, "bad-phrase");
    if (password.length < 1) return bad(reply, 400, "bad-password");
    if (limited("recov:" + uid, 10, 15 * 60000)) return bad(reply, 429, "too-many-attempts");
    const nickname = await nickOf(uid);
    if (!nickname) return bad(reply, 404, "not-found");
    const l = await coreLogin(req, nickname, password);
    if (l.statusCode !== 200) return bad(reply, 403, "bad-password");
    const r = await coreRecover(req, nickname, phrase, password);
    if (r.statusCode === 401) return bad(reply, 400, "bad-phrase");
    if (r.statusCode < 200 || r.statusCode >= 300) return forward(reply, r);
    const body = parseBody(r);
    if (typeof body.recoveryPhrase === "string" && body.recoveryPhrase.trim()) await saveRecovery(uid, body.recoveryPhrase.trim(), "manual");
    return { enabled: true, token: body.token ?? null };
  });

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
    if (mailOn()) { try { await sendVerifyCode(email); codeSent = true; } catch (e) { sendError = String(e?.message ?? e).slice(0, 200); } }
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
    try { await sendVerifyCode(row.alias); } catch (e) { return bad(reply, 502, "send-failed", { detail: String(e?.message ?? e).slice(0, 200) }); }
    return { ok: true, email: row.alias, expiresIn: CODE_TTL_MIN * 60 };
  });
  /// التحقق من الرمز: خمس محاولات ثم يلزم طلب رمز جديد.
  app.post("/me/login-email/verify", async (req, reply) => {
    const uid = await me(req, reply); if (!uid) return;
    const code = digits(req.body?.code);
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
    const r = (await pool.query("SELECT count(*)::int AS n FROM account_recovery")).rows[0];
    return { ok: true, aliases: c.n, verified: c.v, recoverable: r.n, mailConfigured: mailOn() };
  });
}
