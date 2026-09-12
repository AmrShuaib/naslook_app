// إضافة Fastify لملف المستخدم في Naslife: صورة الحساب.
// الخادم الأساسي يقرأ صورة المستخدم من عمود في جدول users (يُكتشف اسمه عند الإقلاع)، فنكتب فيه رابط صورة مرفوعة عبر /chat/upload
// لتظهر في كل مكان (الملف، الدردشة، الخريطة، الدوائر) دون تعديل النواة.
// التسجيل في src/index.js:
//   await app.register((await import("./profile.js")).default, { pool, auth });
export default async function profile(app, opts) {
  const { pool, auth } = opts;
  if (!pool || !auth) throw new Error("profile: pool and auth are required");
  const cols = new Set((await pool.query("SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name='users'")).rows.map((r) => r.column_name));
  const col = ["avatar_url", "avatarurl", "avatar", "photo_url", "image_url", "picture"].find((c) => cols.has(c)) ?? null;
  const q = (ident) => `"${String(ident).replace(/"/g, '""')}"`;
  const unauthorized = (reply) => reply.code(401).send({ error: "auth" });
  const bad = (reply, code, error, extra = {}) => reply.code(code).send({ error, ...extra });
  /// رابط مطلق على مضيف الطلب نفسه (خلف Caddy: x-forwarded-proto/host)
  const absolute = (req, path) => {
    const proto = String(req.headers["x-forwarded-proto"] ?? "https").split(",")[0].trim() || "https";
    const host = String(req.headers["x-forwarded-host"] ?? req.headers.host ?? "naslife.app").split(",")[0].trim();
    return `${proto}://${host}${path}`;
  };

  app.get("/profile/status", async () => ({ ok: true, avatarColumn: col }));

  // نقبل روابط وسائط الخادم نفسه فقط (المرفوعة عبر /chat/upload)
  app.post("/profile/avatar", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!col) return bad(reply, 501, "unsupported");
    const m = String(req.body?.url ?? "").trim().match(/^(?:https?:\/\/[^/]+)?(\/chat\/media\/[A-Za-z0-9._-]{1,120})$/);
    if (!m) return bad(reply, 400, "bad-url");
    const full = absolute(req, m[1]);
    const r = await pool.query(`UPDATE users SET ${q(col)}=$1 WHERE id=$2 RETURNING id`, [full, uid]);
    if (!r.rowCount) return bad(reply, 404, "not-found");
    return { ok: true, avatarUrl: full };
  });
  app.delete("/profile/avatar", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!col) return bad(reply, 501, "unsupported");
    await pool.query(`UPDATE users SET ${q(col)}=NULL WHERE id=$1`, [uid]);
    return { ok: true, avatarUrl: null };
  });
}
