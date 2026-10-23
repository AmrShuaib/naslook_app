// إضافات عارض «اللحظات» في Naslife (قرار المالك): تفاعلات سريعة بأربعة وجوه فقط (😍 😂 🔥 👏)، تفاعل واحد لكل مستخدم لكل لحظة.
//   POST   /moments/:id/react {emoji}   يضبط تفاعلي أو يغيّره؛ {emoji:null} يزيله (ومثله DELETE /moments/:id/react)
//   GET    /moments/:id/reactions       عام؛ mine=null للضيف
// كلها تعيد {counts:{"😍":n,"😂":n,"🔥":n,"👏":n}, mine:"😍"|null}. صاحب اللحظة يُشعَر مرة على الأكثر لكل (لحظة، متفاعل) في الساعة،
// ولا إشعار حين أتفاعل مع لحظتي. اللحظة المخفية أو المحجوبة أو المحذوفة = 404، والحظر بين الطرفين = 403.
// باقي إضافات العارض في غير هذا الملف: رابط المشاركة /m/:id في share.js، و«محفوظاتي» في wishlist.js (النوع post)، والمعاينة في chat_tools.js.
// التسجيل في register.txt بعد map_posts.js:
//   await app.register((await import("./moment_extras.js")).default, { pool, auth });
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const MOMENT_REACTIONS = Object.freeze(["😍", "😂", "🔥", "👏"]);
// محدد التنويع (FE0F) يضيفه بعض لوحات المفاتيح للوجه نفسه؛ نحذفه حتى لا يُرفض تفاعل صحيح
export const cleanEmoji = (v) => (v == null ? null : String(v).replace(/️/g, "").trim() || null);

// أي خطأ أثناء التهيئة يُسجَّل ويعطّل الإضافة وحدها بدل إسقاط الخادم
export default async function momentExtras(app, opts) {
  try {
    await setup(app, opts);
  } catch (e) {
    (app.log?.error ? app.log.error.bind(app.log) : console.error)(`moment_extras disabled: ${e?.stack || e}`);
  }
}

async function setup(app, opts) {
  const { pool, auth } = opts;
  if (!pool || !auth) throw new Error("moment_extras: pool and auth are required");
  // بلا مفتاح أجنبي إلى map_posts: الجدول قد يُنشأ بعدنا في بيئة أخرى، واليتامى تُكنس دورياً أدناه
  await pool.query(`
    CREATE TABLE IF NOT EXISTS map_post_reactions (
      post_id UUID NOT NULL, user_id TEXT NOT NULL, emoji TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      PRIMARY KEY (post_id, user_id));
    -- آخر إشعار لكل (لحظة، متفاعل): منفصل عن التفاعل نفسه حتى لا يتجاوز «أزل ثم أعد» حدّ الساعة
    CREATE TABLE IF NOT EXISTS map_post_react_notified (
      post_id UUID NOT NULL, user_id TEXT NOT NULL, at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (post_id, user_id));
  `);
  const unauthorized = (reply) => reply.code(401).send({ error: "auth" });
  const bad = (reply, code, error, extra = {}) => reply.code(code).send({ error, ...extra });
  const optionalAuth = async (req) => { try { return (await auth(req)) || null; } catch { return null; } };
  const isBlocked = async (a, b) => {
    if (!a || !b || a === b) return false;
    try {
      const f = globalThis.naslifeIsBlocked;
      if (f) return !!(await f(a, b));
      const ids = await globalThis.naslifeBlockedIds?.(a);
      return Array.isArray(ids) && ids.includes(b);
    } catch { return false; }
  };
  const nickname = async (id) => { try { return (await pool.query("SELECT nickname FROM users WHERE id=$1", [id])).rows[0]?.nickname || ""; } catch { return ""; } };

  // اللحظة التي يُتفاعل معها: موجودة ونشطة (إلا قراءة صاحبها للحظته المخفية)، وبلا حظر بين المشاهد وصاحبها
  async function load(id, uid, { ownerMayRead = false } = {}) {
    if (!UUID_RE.test(id)) return { code: 404, error: "not-found" };
    const p = (await pool.query("SELECT id, user_id, status FROM map_posts WHERE id=$1", [id])).rows[0];
    if (!p) return { code: 404, error: "not-found" };
    if (p.status !== "active" && !(ownerMayRead && uid && p.user_id === uid)) return { code: 404, error: "not-found" };
    if (uid && (await isBlocked(uid, p.user_id))) return { code: 403, error: "blocked" };
    return { post: p };
  }
  async function summary(postId, uid) {
    const rows = (await pool.query(
      "SELECT emoji, count(*)::int AS n, bool_or(user_id = $2::text) AS mine FROM map_post_reactions WHERE post_id=$1 GROUP BY emoji",
      [postId, uid ?? null])).rows;
    const counts = Object.fromEntries(MOMENT_REACTIONS.map((e) => [e, 0]));
    let mine = null;
    for (const r of rows) {
      if (!(r.emoji in counts)) continue;
      counts[r.emoji] = r.n;
      if (r.mine === true) mine = r.emoji;
    }
    return { counts, mine };
  }
  // إشعار واحد على الأكثر لكل (لحظة، متفاعل) في الساعة: الإدراج الذري يقرر من يُرسل حتى مع طلبين متزامنين
  async function notifyOwner(post, uid, emoji) {
    if (post.user_id === uid) return;
    const ok = await pool.query(
      `INSERT INTO map_post_react_notified(post_id,user_id,at) VALUES($1,$2,now())
       ON CONFLICT (post_id,user_id) DO UPDATE SET at=now() WHERE map_post_react_notified.at < now() - interval '1 hour' RETURNING 1`,
      [post.id, uid]);
    if (!ok.rowCount) return;
    try {
      await globalThis.naslifeNotify?.(post.user_id, { kind: "moment_react", title: `${(await nickname(uid)) || uid} تفاعل مع لحظتك ${emoji}`, data: { postId: post.id } });
    } catch { /* الإشعار لا يعطّل التفاعل */ }
  }
  async function react(req, reply, raw) {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const emoji = cleanEmoji(raw);
    if (emoji && !MOMENT_REACTIONS.includes(emoji)) return bad(reply, 400, "bad-emoji", { allowed: MOMENT_REACTIONS });
    const g = await load(String(req.params.id ?? ""), uid);
    if (g.error) return bad(reply, g.code, g.error);
    if (!emoji) {
      await pool.query("DELETE FROM map_post_reactions WHERE post_id=$1 AND user_id=$2", [g.post.id, uid]);
    } else {
      // الوجه نفسه مرة ثانية لا يغيّر شيئاً (ولا يُشعر)؛ الإزالة صريحة بـ null أو DELETE
      const r = await pool.query(
        `INSERT INTO map_post_reactions(post_id,user_id,emoji) VALUES($1,$2,$3)
         ON CONFLICT (post_id,user_id) DO UPDATE SET emoji=EXCLUDED.emoji, created_at=now() WHERE map_post_reactions.emoji <> EXCLUDED.emoji RETURNING 1`,
        [g.post.id, uid, emoji]);
      if (r.rowCount) await notifyOwner(g.post, uid, emoji);
    }
    return summary(g.post.id, uid);
  }

  // جسم بلا المفتاح emoji خطأ لا إزالة: الإزالة تُطلب صراحةً بـ {emoji:null}
  app.post("/moments/:id/react", async (req, reply) => {
    const b = req.body;
    if (!b || typeof b !== "object" || !("emoji" in b)) {
      if (!(await auth(req))) return unauthorized(reply);
      return bad(reply, 400, "bad-emoji", { allowed: MOMENT_REACTIONS });
    }
    return react(req, reply, b.emoji);
  });
  app.delete("/moments/:id/react", async (req, reply) => react(req, reply, null));
  app.get("/moments/:id/reactions", async (req, reply) => {
    const uid = await optionalAuth(req);
    const g = await load(String(req.params.id ?? ""), uid, { ownerMayRead: true });
    if (g.error) return bad(reply, g.code, g.error);
    return summary(g.post.id, uid);
  });
  app.get("/moments/status", async () => ({ ok: true, reactions: MOMENT_REACTIONS }));

  // كنس دوري: تفاعلات لحظات حُذفت (map_posts تحذف ما انتهى منذ 30 يوماً ولا تعرف هذا الجدول)، وسجلات إشعار مضت عليها الساعة
  async function sweep() {
    const a = await pool.query("DELETE FROM map_post_reactions r WHERE NOT EXISTS (SELECT 1 FROM map_posts p WHERE p.id=r.post_id)");
    const b = await pool.query("DELETE FROM map_post_react_notified WHERE at < now() - interval '1 hour'");
    return { reactions: a.rowCount, notified: b.rowCount };
  }
  globalThis.naslifeMomentExtrasSweep = sweep;
  const SWEEP_MS = opts.sweepMs ?? 6 * 3600 * 1000;
  if (SWEEP_MS > 0) {
    const timer = setInterval(() => { sweep().catch(() => {}); }, SWEEP_MS);
    timer.unref?.();
    app.addHook("onClose", async () => clearInterval(timer));
  }
}
