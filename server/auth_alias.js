// الدخول بالبريد الإلكتروني: النواة لا تقبل «@» في النك نيم، فنحفظ لكل مستخدم بريداً بديلاً (login_aliases) ونحوّل
// طلب الدخول بالبريد إلى دخول النواة بالنك نيم نفسه وكلمة السر نفسها (طلب داخلي إلى /login) فيبقى التحقق كله في النواة.
// المسارات: POST /auth/login {handle, password} (بريد أو نك نيم)، GET/PUT/DELETE /me/login-email (للمستخدم نفسه)،
// وتمهيد من server/admin_bootstrap.js (LOGIN_ALIASES) عند الإقلاع. التسجيل: await app.register((await import("./auth_alias.js")).default, { pool, auth });
const EMAIL_RE = /^[a-z0-9][a-z0-9._%+-]{0,63}@[a-z0-9.-]+\.[a-z]{2,}$/;
const ID_RE = /^[A-Z]{2}\d{7}$/;

export const normEmail = (v) => String(v ?? "").trim().toLowerCase();

export default async function authAlias(app, opts = {}) {
  const pool = opts.pool ?? globalThis.naslifePool ?? null;
  const auth = opts.auth ?? globalThis.naslifeAuth ?? null;
  if (!pool) throw new Error("auth_alias: pool is required");
  await pool.query(`CREATE TABLE IF NOT EXISTS login_aliases (alias TEXT PRIMARY KEY, user_id TEXT NOT NULL, nickname TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE INDEX IF NOT EXISTS login_aliases_user ON login_aliases(user_id)`);
  const bad = (reply, code, error, extra = {}) => reply.code(code).send({ error, ...extra });
  const nickOf = async (userId) => { try { return (await pool.query("SELECT nickname FROM users WHERE id=$1", [userId])).rows[0]?.nickname ?? null; } catch { return null; } };

  // ---- تمهيد من المستودع: بريد ← معرّف مستخدم (لا يُعاد تعيين بريد مستخدم غيّره بنفسه)
  try {
    const { LOGIN_ALIASES } = await import("./admin_bootstrap.js");
    for (const a of Array.isArray(LOGIN_ALIASES) ? LOGIN_ALIASES : []) {
      const email = normEmail(a?.email), userId = String(a?.userId ?? "").trim().toUpperCase();
      if (!EMAIL_RE.test(email) || !ID_RE.test(userId)) continue;
      const nickname = await nickOf(userId);
      if (!nickname) continue;
      const mine = (await pool.query("SELECT 1 FROM login_aliases WHERE user_id=$1", [userId])).rowCount > 0;
      if (mine) continue;
      await pool.query("INSERT INTO login_aliases(alias, user_id, nickname) VALUES($1,$2,$3) ON CONFLICT (alias) DO NOTHING", [email, userId, nickname]);
    }
  } catch { /* لا ملف تمهيد */ }

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
    const row = (await pool.query("SELECT alias FROM login_aliases WHERE user_id=$1 ORDER BY created_at DESC LIMIT 1", [uid])).rows[0];
    return { email: row?.alias ?? null };
  });
  app.put("/me/login-email", async (req, reply) => {
    const uid = await me(req, reply); if (!uid) return;
    const email = normEmail(req.body?.email);
    if (!EMAIL_RE.test(email)) return bad(reply, 400, "bad-email");
    const taken = (await pool.query("SELECT user_id FROM login_aliases WHERE alias=$1", [email])).rows[0];
    if (taken && taken.user_id !== uid) return bad(reply, 409, "email-taken");
    const nickname = (await nickOf(uid)) ?? "";
    await pool.query("DELETE FROM login_aliases WHERE user_id=$1", [uid]);
    await pool.query("INSERT INTO login_aliases(alias, user_id, nickname) VALUES($1,$2,$3)", [email, uid, nickname]);
    return { email };
  });
  app.delete("/me/login-email", async (req, reply) => {
    const uid = await me(req, reply); if (!uid) return;
    await pool.query("DELETE FROM login_aliases WHERE user_id=$1", [uid]);
    return { ok: true };
  });
  app.get("/auth/alias/status", async () => ({ ok: true, aliases: (await pool.query("SELECT count(*)::int AS n FROM login_aliases")).rows[0].n }));
}
