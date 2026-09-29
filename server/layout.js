// تخصيص الشاشة الرئيسية في Naslife: كل مستخدم يخفي كتل الرئيسية ويعيد ترتيبها ويختار تبويبات الشريط السفلي، ويُحفظ ذلك
// صفاً واحداً بصيغة JSON لكل مستخدم. المعرّفات المعروفة ثابتة هنا وتطابق التطبيق؛ ما لا يعرفه الخادم يُسقَط بصمت حتى لا
// تكسر نسخة تطبيق أحدث الحفظ، والكتل الجديدة تُلحَق تلقائياً بآخر الترتيب حتى لا تضيع عند من خصّص شاشته قبل إضافتها.
// التسجيل في src/index.js قبل app.listen:
//   await app.register((await import("./layout.js")).default, { pool, auth });

export const BLOCK_IDS = ["announce", "quick", "around", "trending", "offers", "open", "circles", "feed", "biz", "jobs", "market", "events"];
export const DEFAULT_ORDER = ["announce", "quick", "around", "trending", "offers", "open", "circles", "feed", "jobs", "market", "events", "biz"];
export const DEFAULT_PINNED = ["announce"]; // المثبّت لا يُخفى ويبقى أولاً
export const NAV_IDS = ["home", "circles", "chats", "me", "market", "offers", "jobs", "events"];
export const DEFAULT_NAV = ["home", "circles", "chats", "me"];
const NAV_MIN = 3, NAV_MAX = 6; // «الرئيسية» أولاً و«أنا» أخيراً بينهما تبويب واحد على الأقل وأربعة على الأكثر

const ID_RE = /^[a-z0-9_-]{1,32}$/;
const MAX_ENTRIES = 40, MAX_OPT_VALUES = 10, MAX_OPT_LEN = 40;
const uniq = (a) => [...new Set(a)];
const splitIds = (v, known) => uniq(String(v ?? "").split(",").map((s) => s.trim()).filter((s) => known.includes(s)));

// الكتل المثبّتة من الإعدادات (homeLayoutPinned)؛ نص فارغ = لا شيء مثبّت، وغياب المفتاح = الافتراضي
export function pinned() {
  const v = globalThis.naslifeSettings?.homeLayoutPinned;
  return typeof v === "string" ? splitIds(v, BLOCK_IDS) : [...DEFAULT_PINNED];
}

// الافتراضيات: ترتيب الإعدادات (homeLayoutOrder) مع إلحاق ما نقص بترتيب DEFAULT_ORDER، والمثبّت أولاً دائماً
export function defaults() {
  const pin = pinned();
  const fromSetting = splitIds(globalThis.naslifeSettings?.homeLayoutOrder, BLOCK_IDS);
  const order = uniq([...pin, ...fromSetting, ...DEFAULT_ORDER]);
  return { order, nav: [...DEFAULT_NAV] };
}

// تطبيع تخطيط محفوظ أو وارد: إسقاط المجهول، المثبّت أولاً ولا يُخفى، إلحاق الكتل الناقصة، والشريط يبدأ بالرئيسية وينتهي بـ«أنا»
export function normalise(raw = {}) {
  const d = defaults(), pin = pinned();
  const arr = (v) => (Array.isArray(v) ? v.filter((x) => typeof x === "string") : []);
  const order = uniq([...pin, ...arr(raw.order).filter((id) => BLOCK_IDS.includes(id)), ...d.order]);
  const hidden = uniq(arr(raw.hidden).filter((id) => BLOCK_IDS.includes(id) && !pin.includes(id)));
  // شريط غائب = الافتراضي؛ شريط وارد يُنقّى ثم يُكمَّل من الافتراضي إن قصُر ويُقصّ إن طال
  let mid = uniq(arr(Array.isArray(raw.nav) ? raw.nav : d.nav).filter((id) => NAV_IDS.includes(id) && id !== "home" && id !== "me"));
  for (const id of DEFAULT_NAV) if (mid.length + 2 < NAV_MIN && id !== "home" && id !== "me" && !mid.includes(id)) mid.push(id);
  mid = mid.slice(0, NAV_MAX - 2);
  const nav = ["home", ...mid, "me"];
  const opts = {};
  if (raw.opts && typeof raw.opts === "object" && !Array.isArray(raw.opts)) {
    for (const [k, v] of Object.entries(raw.opts)) {
      if (!BLOCK_IDS.includes(k) || !Array.isArray(v)) continue;
      const vals = v.filter((s) => typeof s === "string").map((s) => s.trim().slice(0, MAX_OPT_LEN)).filter(Boolean).slice(0, MAX_OPT_VALUES);
      if (vals.length) opts[k] = uniq(vals);
    }
  }
  return { order, hidden, nav, opts };
}

// فحص الجسم قبل التطبيع: يعيد اسم الخطأ أو null. المعرّفات المجهولة ليست خطأ (تُسقط لاحقاً) لكن الشكل يجب أن يكون سليماً
function validate(b) {
  for (const k of ["order", "hidden", "nav"]) {
    if (b[k] === undefined) continue;
    if (!Array.isArray(b[k]) || b[k].length > MAX_ENTRIES) return "bad-layout";
    if (!b[k].every((id) => typeof id === "string" && ID_RE.test(id))) return "bad-layout";
  }
  if (b.nav !== undefined && (!b.nav.includes("home") || !b.nav.includes("me"))) return "bad-layout";
  if (b.opts !== undefined) {
    if (!b.opts || typeof b.opts !== "object" || Array.isArray(b.opts)) return "bad-layout";
    const entries = Object.entries(b.opts);
    if (entries.length > MAX_ENTRIES) return "bad-layout";
    for (const [k, v] of entries) {
      if (!ID_RE.test(k) || !Array.isArray(v) || v.length > MAX_OPT_VALUES) return "bad-layout";
      if (!v.every((s) => typeof s === "string" && s.length <= MAX_OPT_LEN)) return "bad-layout";
    }
  }
  return null;
}

export default async function layout(app, opts) {
  const { pool, auth } = opts;
  if (!pool || !auth) throw new Error("layout: pool and auth are required");
  await pool.query(`
    CREATE TABLE IF NOT EXISTS user_layouts (
      user_id TEXT PRIMARY KEY,
      layout JSONB NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
  `);
  const unauthorized = (reply) => reply.code(401).send({ error: "auth" });
  const bad = (reply, code, error) => reply.code(code).send({ error });
  const iso = (d) => (d ? new Date(d).toISOString() : null);
  const load = async (uid) => (await pool.query("SELECT layout, updated_at FROM user_layouts WHERE user_id=$1", [uid])).rows[0] ?? null;

  // ---- تخطيطي: للضيف الافتراضيات فقط؛ للمستخدم تخطيطه المحفوظ بعد التطبيع (أو null إن لم يخصّص شيئاً)
  app.get("/me/layout", async (req) => {
    const uid = await auth(req);
    const row = uid ? await load(uid) : null;
    return { layout: row ? normalise(row.layout ?? {}) : null, defaults: defaults(), pinned: pinned(), updatedAt: iso(row?.updated_at) };
  });

  // ---- حفظ: الحقول الواردة تحلّ محل نظيرتها المحفوظة والباقي يبقى (فكل ورقة في التطبيق تحفظ جزءها وحده)
  app.put("/me/layout", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const b = req.body && typeof req.body === "object" && !Array.isArray(req.body) ? req.body : null;
    if (!b) return bad(reply, 400, "bad-layout");
    const err = validate(b); if (err) return bad(reply, 400, err);
    const cur = (await load(uid))?.layout ?? {};
    const merged = normalise({ order: b.order ?? cur.order, hidden: b.hidden ?? cur.hidden, nav: b.nav ?? cur.nav, opts: b.opts ?? cur.opts });
    const r = await pool.query(
      "INSERT INTO user_layouts(user_id, layout, updated_at) VALUES($1,$2,now()) ON CONFLICT (user_id) DO UPDATE SET layout=EXCLUDED.layout, updated_at=now() RETURNING updated_at",
      [uid, JSON.stringify(merged)]);
    return { ok: true, layout: merged, updatedAt: iso(r.rows[0]?.updated_at) };
  });

  // ---- إعادة الافتراضيات: حذف الصف
  app.delete("/me/layout", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    await pool.query("DELETE FROM user_layouts WHERE user_id=$1", [uid]);
    return { ok: true };
  });

  // لحذف الحساب وأدوات الإدارة؛ الجدول قد يكون غائباً في بيئة أقدم فلا نُسقط المستدعي
  globalThis.naslifeLayoutDelete = async (userId) => {
    try { await pool.query("DELETE FROM user_layouts WHERE user_id=$1", [String(userId ?? "")]); return true; } catch { return false; }
  };

  app.get("/layout/status", async () => ({ ok: true, blocks: BLOCK_IDS, nav: NAV_IDS }));
}
