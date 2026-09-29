// الملف الشخصي v2 في Naslife: غلاف واسم ظاهر ومسمّى وظيفي ومدينة وروابط تواصل، تعريف صوتي أو مرئي قصير، متابعة، إحصاءات
// زيارات سبعة أيام، خصوصية (من يراسلني، إظهار الاتصال والمدينة والأصدقاء)، وفحص توفر الاسم. النواة (ليست في المستودع) تملك
// users/profiles/contacts فنقرأها فقط ونكتشف أعمدتها عند الإقلاع، وكل ما يخصنا في أربعة جداول هنا حتى لا نعدّل جداول النواة.
// التسجيل في src/index.js:
//   await app.register((await import("./profile_v2.js")).default, { pool, auth });

export const LINK_KINDS = ["instagram", "x", "tiktok", "snapchat", "website", "other"];
export const RESERVED_HANDLES = ["naslife", "admin", "support", "jeddah", "dammam"];
export const HANDLE_RE = /^[a-z0-9._]{3,20}$/;
const MEDIA_RE = /^(?:https?:\/\/[^/]+)?(\/chat\/media\/[A-Za-z0-9._-]{1,120})$/;
const SOCIAL_VALUE_RE = /^[A-Za-z0-9._-]{1,120}$/;
const MAX_LINKS = 3, MAX_SHORT = 40, MAX_LINK = 120, INTRO_VOICE_SEC = 60, INTRO_VIDEO_SEC = 30;
const MSG_POLICIES = ["all", "friends", "none"], VISIBILITIES = ["all", "friends"], EVENT_KINDS = ["message", "share", "link"];
const ID_RE = /^[A-Z]{2}\d{7}$/;
const COMPLETION_LABELS = { avatar: "صورة الحساب", cover: "صورة الغلاف", bio: "النبذة", links: "روابط التواصل", intro: "تعريف صوتي أو مرئي", email: "تأكيد البريد", skills: "المهارات" };

// تطبيع رابط تواصل: اسم المستخدم فقط للشبكات (بلا @ ولا رابط كامل ولا شرطة أخيرة)، والموقع كما هو بعد التشذيب. يعيد null عند الرفض
export function normaliseLink(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const kind = String(raw.kind ?? "").trim().toLowerCase();
  if (!LINK_KINDS.includes(kind)) return null;
  let value = String(raw.value ?? "").trim();
  if (kind === "website" || kind === "other") {
    if (!value || /\s/.test(value) || value.length > MAX_LINK) return null;
    return { kind, value };
  }
  value = value.replace(/^https?:\/\/(?:www\.)?(?:instagram|x|twitter|tiktok|snapchat)\.com\//i, "").replace(/^add\//i, "").replace(/^@/, "").split(/[/?#]/)[0].trim();
  if (!SOCIAL_VALUE_RE.test(value)) return null;
  return { kind, value };
}

// الرابط القياسي للعرض والنقر
export function linkUrl(kind, value) {
  switch (kind) {
    case "instagram": return `https://instagram.com/${value}`;
    case "x": return `https://x.com/${value}`;
    case "tiktok": return `https://tiktok.com/@${value}`;
    case "snapchat": return `https://snapchat.com/add/${value}`;
    default: return /^https?:\/\//i.test(value) ? value : `https://${value}`;
  }
}

// صلاحية اسم المستخدم (بلا فحص القاعدة): reason = short | chars | null
export function handleShape(nickname) {
  const n = String(nickname ?? "").trim().toLowerCase();
  if (n.length < 3) return { nickname: n, valid: false, reason: "short" };
  if (!HANDLE_RE.test(n)) return { nickname: n, valid: false, reason: "chars" };
  return { nickname: n, valid: true, reason: null };
}

export default async function profileV2(app, opts) {
  const { pool, auth } = opts;
  if (!pool || !auth) throw new Error("profile_v2: pool and auth are required");
  await pool.query(`
    CREATE TABLE IF NOT EXISTS profile_ext (
      user_id TEXT PRIMARY KEY, cover_url TEXT,
      display_name TEXT NOT NULL DEFAULT '', job_title TEXT NOT NULL DEFAULT '', city TEXT NOT NULL DEFAULT '', district TEXT NOT NULL DEFAULT '',
      links JSONB NOT NULL DEFAULT '[]',
      intro_kind TEXT, intro_url TEXT, intro_sec INT, intro_at TIMESTAMPTZ, intro_visibility TEXT NOT NULL DEFAULT 'all',
      msg_policy TEXT NOT NULL DEFAULT 'all', show_online BOOLEAN NOT NULL DEFAULT true, show_city BOOLEAN NOT NULL DEFAULT true, show_friends BOOLEAN NOT NULL DEFAULT false,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE TABLE IF NOT EXISTS user_follows (follower_id TEXT NOT NULL, user_id TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (follower_id, user_id));
    CREATE INDEX IF NOT EXISTS user_follows_user ON user_follows(user_id, created_at DESC);
    CREATE TABLE IF NOT EXISTS profile_views (user_id TEXT NOT NULL, viewer_id TEXT NOT NULL, day DATE NOT NULL, PRIMARY KEY (user_id, viewer_id, day));
    CREATE INDEX IF NOT EXISTS profile_views_user_day ON profile_views(user_id, day);
    CREATE TABLE IF NOT EXISTS profile_events (id BIGSERIAL PRIMARY KEY, user_id TEXT NOT NULL, actor_id TEXT, kind TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE INDEX IF NOT EXISTS profile_events_user_at ON profile_events(user_id, created_at DESC);
  `);

  // ---- اكتشاف جداول النواة وأعمدتها (كما في profile.js وadmin.js) حتى لا نفترض أسماءً غير موجودة
  const q = (ident) => `"${String(ident).replace(/"/g, '""')}"`;
  const tables = new Set((await pool.query("SELECT table_name FROM information_schema.tables WHERE table_schema='public'")).rows.map((r) => r.table_name));
  const colsOf = async (t) => (tables.has(t) ? new Set((await pool.query("SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name=$1", [t])).rows.map((r) => r.column_name)) : new Set());
  const pick = (set, ...names) => names.find((n) => set.has(n)) ?? null;
  const has = async (t, ...cols) => { if (!tables.has(t)) return false; const c = await colsOf(t); return cols.every((x) => c.has(x)); };
  const userCols = await colsOf("users");
  const U = {
    ok: userCols.has("id"),
    nick: pick(userCols, "nickname", "name", "handle", "username"),
    avatar: pick(userCols, "avatar_url", "avatarurl", "avatar", "photo_url", "image_url", "picture"),
    created: pick(userCols, "created_at", "createdat", "joined_at", "registered_at"),
    verified: pick(userCols, "login_verified"), email: pick(userCols, "login_email"), isPublic: pick(userCols, "is_public"),
  };
  // جدول ملف النواة: profiles صراحةً، وإلا الاكتشاف بالأعمدة (النبذة والمهارات علامتان قويتان)
  let P = null;
  if (tables.has("profiles")) { const c = await colsOf("profiles"); const key = pick(c, "user_id", "id", "uid"); if (key) P = { table: "profiles", key, cols: c }; }
  if (!P) {
    let best = 0;
    for (const t of tables) {
      if (t === "users" || t === "profile_ext") continue;
      const c = await colsOf(t);
      const score = (c.has("bio") ? 2 : 0) + (c.has("skills") ? 2 : 0) + (c.has("is_public") ? 1 : 0) + (/profile/.test(t) ? 3 : 0);
      if (score < 4 || score <= best) continue;
      const key = pick(c, "user_id", "id", "uid"); if (!key) continue;
      P = { table: t, key, cols: c }; best = score;
    }
  }
  const PC = P ? { bio: pick(P.cols, "bio"), skills: pick(P.cols, "skills"), isPublic: pick(P.cols, "is_public"), accountType: pick(P.cols, "account_type") } : {};
  const contactsOk = await has("contacts", "user_id", "contact_id");
  const postsOk = await has("map_posts", "user_id", "status", "expires_at");
  const reviewsOk = await has("market_reviews", "seller_id", "rating");
  const ordersOk = await has("market_orders", "seller_id", "status");
  // عضويات الدوائر: أول جدول معروف بعمود مستخدم
  let M = null;
  for (const t of ["vessel_members", "memberships", "circle_members"]) {
    if (!tables.has(t)) continue;
    const c = await colsOf(t); const key = pick(c, "user_id", "member_id", "uid"); if (key) { M = { table: t, key }; break; }
  }
  // الحضور: جدول النواة إن وُجد (متصل = تحديث خلال خمس دقائق)
  let PR = null;
  for (const t of ["presence", "map_presence"]) {
    if (!tables.has(t)) continue;
    const c = await colsOf(t); const key = pick(c, "user_id", "uid"); const at = pick(c, "updated_at", "last_seen_at", "seen_at", "at"); if (key && at) { PR = { table: t, key, at }; break; }
  }

  const unauthorized = (reply) => reply.code(401).send({ error: "auth" });
  const bad = (reply, code, error, extra = {}) => reply.code(code).send({ error, ...extra });
  const iso = (d) => (d ? new Date(d).toISOString() : null);
  const count = async (sql, params) => { try { return Number((await pool.query(sql, params)).rows[0]?.n ?? 0); } catch { return 0; } };
  const exists = async (sql, params) => { try { return (await pool.query(sql, params)).rowCount > 0; } catch { return false; } };
  // رابط مطلق على الأصل العام (نفس قاعدة صورة الحساب في profile.js)
  const absolute = (req, path) => {
    const env = String(process.env.PUBLIC_BASE_URL ?? process.env.NASLIFE_PUBLIC_URL ?? "").trim().replace(/\/+$/, "");
    if (/^https?:\/\//i.test(env)) return `${env}${path}`;
    const proto = String(req.headers["x-forwarded-proto"] ?? "https").split(",")[0].trim() || "https";
    const host = String(req.headers["x-forwarded-host"] ?? req.headers.host ?? "naslife.app").split(",")[0].trim().replace(/^www\./i, "");
    return `${proto}://${host}${path}`;
  };
  const mediaPath = (v) => String(v ?? "").trim().match(MEDIA_RE)?.[1] ?? null;

  // ---- قراءة النواة
  const userSelect = `SELECT id${U.nick ? `, ${q(U.nick)} AS nickname` : ""}${U.avatar ? `, ${q(U.avatar)} AS avatar_url` : ""}${U.created ? `, ${q(U.created)} AS created_at` : ""}${U.verified ? `, ${q(U.verified)} AS login_verified` : ""}${U.email ? `, ${q(U.email)} AS login_email` : ""}${U.isPublic ? `, ${q(U.isPublic)} AS is_public` : ""} FROM users`;
  const userRow = (r) => (r ? { id: r.id, nickname: r.nickname ?? null, avatarUrl: r.avatar_url ?? null, createdAt: r.created_at ?? null, emailVerified: r.login_verified === true, hasEmail: !!r.login_email, isPublicUser: r.is_public } : null);
  // :id معرّف مستخدم أو اسم (بلا حساسية لحالة الأحرف)؛ بلا جدول users نقبل المعرّف كما هو
  const findUser = async (idOrHandle) => {
    const s = String(idOrHandle ?? "").trim();
    if (!s) return null;
    if (!U.ok) return ID_RE.test(s) ? { id: s, nickname: null, avatarUrl: null, createdAt: null, emailVerified: false, hasEmail: false } : null;
    try {
      if (ID_RE.test(s)) { const r = await pool.query(`${userSelect} WHERE id=$1`, [s]); if (r.rows[0]) return userRow(r.rows[0]); }
      if (U.nick) { const r = await pool.query(`${userSelect} WHERE lower(${q(U.nick)})=lower($1)`, [s.replace(/^@/, "")]); if (r.rows[0]) return userRow(r.rows[0]); }
    } catch { /* ignore */ }
    return null;
  };
  const usersByIds = async (ids) => {
    if (!U.ok || !ids.length) return new Map(ids.map((id) => [id, { id, nickname: null, avatarUrl: null }]));
    try { const r = await pool.query(`${userSelect} WHERE id = ANY($1)`, [ids]); return new Map(r.rows.map((x) => [x.id, { id: x.id, nickname: x.nickname ?? null, avatarUrl: x.avatar_url ?? null }])); } catch { return new Map(); }
  };
  const coreProfile = async (id, u) => {
    const out = { bio: "", skills: [], isPublic: u?.isPublicUser === false ? false : true, accountType: "personal" };
    if (!P) return out;
    try {
      const sel = [PC.bio && `${q(PC.bio)} AS bio`, PC.skills && `${q(PC.skills)} AS skills`, PC.isPublic && `${q(PC.isPublic)} AS is_public`, PC.accountType && `${q(PC.accountType)} AS account_type`].filter(Boolean);
      if (!sel.length) return out;
      const r = (await pool.query(`SELECT ${sel.join(", ")} FROM ${q(P.table)} WHERE ${q(P.key)}=$1`, [id])).rows[0];
      if (!r) return out;
      out.bio = typeof r.bio === "string" ? r.bio : "";
      out.skills = Array.isArray(r.skills) ? r.skills.filter((s) => typeof s === "string") : [];
      if (r.is_public === false) out.isPublic = false;
      if (String(r.account_type ?? "").toLowerCase() === "pro") out.accountType = "pro";
    } catch { /* ignore */ }
    return out;
  };
  const isFriend = async (a, b) => (a && b && a !== b && contactsOk ? exists("SELECT 1 FROM contacts WHERE (user_id=$1 AND contact_id=$2) OR (user_id=$2 AND contact_id=$1) LIMIT 1", [a, b]) : false);
  const isOnline = async (id) => (PR ? exists(`SELECT 1 FROM ${q(PR.table)} WHERE ${q(PR.key)}=$1 AND ${q(PR.at)} > now() - interval '5 minutes' LIMIT 1`, [id]) : null);
  const loadExt = async (id) => { try { return (await pool.query("SELECT * FROM profile_ext WHERE user_id=$1", [id])).rows[0] ?? null; } catch { return null; } };
  const EXT_DEFAULTS = { cover_url: null, display_name: "", job_title: "", city: "", district: "", links: [], intro_kind: null, intro_url: null, intro_sec: null, intro_at: null, intro_visibility: "all", msg_policy: "all", show_online: true, show_city: true, show_friends: false };
  const followersOf = (id) => count("SELECT count(*)::int AS n FROM user_follows WHERE user_id=$1", [id]);
  const stats = async (id) => {
    const [posts, followers, following, circles, friends, completedOrders] = await Promise.all([
      postsOk ? count("SELECT count(*)::int AS n FROM map_posts WHERE user_id=$1 AND status='active' AND expires_at > now()", [id]) : 0,
      followersOf(id),
      count("SELECT count(*)::int AS n FROM user_follows WHERE follower_id=$1", [id]),
      M ? count(`SELECT count(*)::int AS n FROM ${q(M.table)} WHERE ${q(M.key)}=$1`, [id]) : 0,
      contactsOk ? count("SELECT count(*)::int AS n FROM contacts WHERE user_id=$1", [id]) : 0,
      ordersOk ? count("SELECT count(*)::int AS n FROM market_orders WHERE seller_id=$1 AND status IN ('completed','delivered','done')", [id]) : 0,
    ]);
    let ratingAvg = null, ratingCount = 0;
    if (reviewsOk) { try { const r = (await pool.query("SELECT avg(rating)::float AS avg, count(*)::int AS n FROM market_reviews WHERE seller_id=$1", [id])).rows[0]; ratingCount = Number(r?.n ?? 0); ratingAvg = ratingCount ? Math.round(Number(r.avg) * 10) / 10 : null; } catch { /* ignore */ } }
    return { posts, followers, following, circles, ratingAvg, ratingCount, completedOrders, friends };
  };

  // ---- بناء كائن الملف كما يراه الزائر (أو صاحبه)
  async function buildProfile(u, viewer) {
    const id = u.id, isMe = !!viewer && viewer === id;
    const [ext0, core, friend, following] = await Promise.all([loadExt(id), coreProfile(id, u), isFriend(viewer, id), viewer && viewer !== id ? exists("SELECT 1 FROM user_follows WHERE follower_id=$1 AND user_id=$2", [viewer, id]) : false]);
    const ext = { ...EXT_DEFAULTS, ...(ext0 ?? {}) };
    const links = (Array.isArray(ext.links) ? ext.links : []).map(normaliseLink).filter(Boolean).slice(0, MAX_LINKS).map((l) => ({ ...l, url: linkUrl(l.kind, l.value) }));
    const isPrivate = core.isPublic === false;
    const flagsBase = { isMe, isFollowing: following, isFriend: friend, isPrivate, blocked: false };
    const head = { id, nickname: u.nickname, displayName: ext.display_name, avatarUrl: u.avatarUrl, coverUrl: ext.cover_url };
    if (isPrivate && !isMe && !friend) return { ...head, flags: { ...flagsBase, canMessage: ext.msg_policy === "all", online: null }, stats: {} };
    const canMessage = isMe ? true : ext.msg_policy === "all" ? true : ext.msg_policy === "friends" ? friend : false;
    const online = ext.show_online ? await isOnline(id) : null;
    const showCity = isMe || ext.show_city === true;
    const showFriends = isMe || ext.show_friends === true;
    const introVisible = !!ext.intro_kind && (isMe || ext.intro_visibility === "all" || friend);
    const st = await stats(id);
    const memberSince = iso(u.createdAt);
    return {
      ...head, bio: core.bio, accountType: core.accountType, jobTitle: ext.job_title, city: showCity ? ext.city : "", district: showCity ? ext.district : "", links,
      intro: introVisible ? { kind: ext.intro_kind, url: ext.intro_url, sec: ext.intro_sec, at: iso(ext.intro_at) } : null,
      stats: { ...st, friends: showFriends ? st.friends : 0 },
      trust: { emailVerified: u.emailVerified === true, phoneVerified: false, memberSince, respondsFast: null },
      flags: { ...flagsBase, canMessage, online, showFriends: ext.show_friends === true },
      memberSince,
      _core: core, _ext: ext, // للمالك فقط (تُحذف قبل الإرسال)
    };
  }
  const strip = (p) => { const { _core, _ext, ...rest } = p; return rest; };
  async function mine(u) {
    const p = await buildProfile(u, u.id);
    const ext = p._ext, core = p._core;
    const steps = [
      { id: "avatar", done: !!u.avatarUrl }, { id: "cover", done: !!ext.cover_url }, { id: "bio", done: core.bio.trim().length > 0 }, { id: "links", done: p.links.length > 0 },
      { id: "intro", done: !!ext.intro_kind }, { id: "email", done: u.emailVerified === true }, { id: "skills", done: core.skills.length > 0 },
    ].map((s) => ({ ...s, label: COMPLETION_LABELS[s.id] }));
    const done = steps.filter((s) => s.done).length;
    return {
      ...strip(p),
      settings: { msgPolicy: ext.msg_policy, showOnline: ext.show_online === true, showCity: ext.show_city === true, showFriends: ext.show_friends === true, introVisibility: ext.intro_visibility },
      completion: { pct: Math.round((done / steps.length) * 20) * 5, steps },
    };
  }

  app.get("/profile/v2/status", async () => ({ ok: true, users: U.ok, profiles: P?.table ?? null, contacts: contactsOk, posts: postsOk, reviews: reviewsOk, orders: ordersOk, members: M?.table ?? null, presence: PR?.table ?? null }));

  // ---- ملف مستخدم كما يراه الزائر؛ الزيارة تُسجَّل مرة في اليوم لكل زائر مسجّل غير المالك
  app.get("/profiles/:id/v2", async (req, reply) => {
    const viewer = await auth(req);
    const u = await findUser(req.params.id); if (!u) return bad(reply, 404, "not-found");
    if (viewer && viewer !== u.id) { try { await pool.query("INSERT INTO profile_views(user_id, viewer_id, day) VALUES($1,$2,current_date) ON CONFLICT DO NOTHING", [u.id, viewer]); } catch { /* ignore */ } }
    return strip(await buildProfile(u, viewer));
  });

  app.get("/me/profile/v2", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const u = (await findUser(uid)) ?? { id: uid, nickname: null, avatarUrl: null, createdAt: null, emailVerified: false, hasEmail: false };
    return mine(u);
  });

  // ---- تعديل الحقول: كل حقل وارد يُفحص ثم يُكتب، والغائب يبقى كما هو
  app.put("/me/profile/v2", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const b = req.body && typeof req.body === "object" && !Array.isArray(req.body) ? req.body : null;
    if (!b) return bad(reply, 400, "bad-field", { field: "body" });
    const set = {};
    for (const [field, col] of [["displayName", "display_name"], ["jobTitle", "job_title"], ["city", "city"], ["district", "district"]]) {
      if (b[field] === undefined) continue;
      if (typeof b[field] !== "string") return bad(reply, 400, "bad-field", { field });
      const v = b[field].trim(); if (v.length > MAX_SHORT) return bad(reply, 400, "bad-field", { field });
      set[col] = v;
    }
    if (b.coverUrl !== undefined) {
      if (b.coverUrl === null || b.coverUrl === "") set.cover_url = null;
      else { const p = typeof b.coverUrl === "string" ? mediaPath(b.coverUrl) : null; if (!p) return bad(reply, 400, "bad-field", { field: "coverUrl" }); set.cover_url = absolute(req, p); }
    }
    if (b.links !== undefined) {
      if (!Array.isArray(b.links) || b.links.length > MAX_LINKS) return bad(reply, 400, "bad-field", { field: "links" });
      const links = b.links.map(normaliseLink);
      if (links.some((l) => !l)) return bad(reply, 400, "bad-field", { field: "links" });
      set.links = JSON.stringify(links);
    }
    if (b.msgPolicy !== undefined) { if (!MSG_POLICIES.includes(b.msgPolicy)) return bad(reply, 400, "bad-field", { field: "msgPolicy" }); set.msg_policy = b.msgPolicy; }
    if (b.introVisibility !== undefined) { if (!VISIBILITIES.includes(b.introVisibility)) return bad(reply, 400, "bad-field", { field: "introVisibility" }); set.intro_visibility = b.introVisibility; }
    for (const [field, col] of [["showOnline", "show_online"], ["showCity", "show_city"], ["showFriends", "show_friends"]]) {
      if (b[field] === undefined) continue;
      if (typeof b[field] !== "boolean") return bad(reply, 400, "bad-field", { field });
      set[col] = b[field];
    }
    const cols = Object.keys(set);
    if (cols.length) {
      const vals = cols.map((c) => set[c]);
      await pool.query(
        `INSERT INTO profile_ext(user_id, ${cols.map(q).join(", ")}, updated_at) VALUES($1, ${cols.map((_, i) => `$${i + 2}`).join(", ")}, now())
         ON CONFLICT (user_id) DO UPDATE SET ${cols.map((c) => `${q(c)}=EXCLUDED.${q(c)}`).join(", ")}, updated_at=now()`, [uid, ...vals]);
    }
    const u = (await findUser(uid)) ?? { id: uid, nickname: null, avatarUrl: null, createdAt: null, emailVerified: false, hasEmail: false };
    return mine(u);
  });

  // ---- التعريف الصوتي (≤60ث) أو المرئي (≤30ث): رابط وسائط الخادم فقط؛ الملف القديم يُحذف إن توفّر مساعد الحذف
  const dropMedia = async (url) => { if (!url) return; try { await globalThis.naslifeMediaDelete?.(url); } catch { /* ignore */ } };
  app.put("/me/profile/intro", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const b = req.body && typeof req.body === "object" ? req.body : {};
    const kind = b.kind === "voice" || b.kind === "video" ? b.kind : null;
    const p = typeof b.url === "string" ? mediaPath(b.url) : null;
    const sec = Number.isInteger(b.sec) ? b.sec : null;
    if (!kind || !p || sec == null || sec < 1 || sec > (kind === "voice" ? INTRO_VOICE_SEC : INTRO_VIDEO_SEC)) return bad(reply, 400, "bad-intro");
    const url = absolute(req, p);
    const old = (await loadExt(uid))?.intro_url ?? null;
    const r = await pool.query(
      `INSERT INTO profile_ext(user_id, intro_kind, intro_url, intro_sec, intro_at, updated_at) VALUES($1,$2,$3,$4,now(),now())
       ON CONFLICT (user_id) DO UPDATE SET intro_kind=EXCLUDED.intro_kind, intro_url=EXCLUDED.intro_url, intro_sec=EXCLUDED.intro_sec, intro_at=now(), updated_at=now() RETURNING intro_at`, [uid, kind, url, sec]);
    if (old && old !== url) await dropMedia(old);
    return { ok: true, intro: { kind, url, sec, at: iso(r.rows[0]?.intro_at) } };
  });
  app.delete("/me/profile/intro", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const old = (await loadExt(uid))?.intro_url ?? null;
    await pool.query("UPDATE profile_ext SET intro_kind=NULL, intro_url=NULL, intro_sec=NULL, intro_at=NULL, updated_at=now() WHERE user_id=$1", [uid]);
    await dropMedia(old);
    return { ok: true };
  });

  // ---- المتابعة: إشعار مرة واحدة لكل متابع (سجل الأحداث يمنع التكرار عند إلغاء المتابعة وإعادتها)
  const followTarget = async (req, reply) => {
    const uid = await auth(req); if (!uid) { unauthorized(reply); return null; }
    const u = await findUser(req.params.id); if (!u) { bad(reply, 404, "not-found"); return null; }
    if (u.id === uid) { bad(reply, 400, "self"); return null; }
    return { uid, u };
  };
  app.post("/profiles/:id/follow", async (req, reply) => {
    const t = await followTarget(req, reply); if (!t) return;
    const r = await pool.query("INSERT INTO user_follows(follower_id, user_id) VALUES($1,$2) ON CONFLICT DO NOTHING", [t.uid, t.u.id]);
    if (r.rowCount) {
      const before = await exists("SELECT 1 FROM profile_events WHERE user_id=$1 AND actor_id=$2 AND kind='follow' LIMIT 1", [t.u.id, t.uid]);
      try { await pool.query("INSERT INTO profile_events(user_id, actor_id, kind) VALUES($1,$2,'follow')", [t.u.id, t.uid]); } catch { /* ignore */ }
      if (!before) {
        const me = await findUser(t.uid);
        try { await globalThis.naslifeNotify?.([t.u.id], { kind: "profile_follow", title: `${me?.nickname || t.uid} يتابعك`, body: "", data: { userId: t.uid } }); } catch { /* ignore */ }
      }
    }
    return { ok: true, following: true, followers: await followersOf(t.u.id) };
  });
  app.delete("/profiles/:id/follow", async (req, reply) => {
    const t = await followTarget(req, reply); if (!t) return;
    await pool.query("DELETE FROM user_follows WHERE follower_id=$1 AND user_id=$2", [t.uid, t.u.id]);
    return { ok: true, following: false, followers: await followersOf(t.u.id) };
  });
  const followList = async (req, reply, mineCol, otherCol) => {
    const u = await findUser(req.params.id); if (!u) return bad(reply, 404, "not-found");
    const limit = Math.min(100, Math.max(1, Number.parseInt(String(req.query?.limit ?? "50"), 10) || 50));
    const rows = (await pool.query(`SELECT ${q(otherCol)} AS id FROM user_follows WHERE ${q(mineCol)}=$1 ORDER BY created_at DESC LIMIT $2`, [u.id, limit])).rows;
    const people = await usersByIds(rows.map((r) => r.id));
    return { items: rows.map((r) => people.get(r.id) ?? { id: r.id, nickname: null, avatarUrl: null }) };
  };
  app.get("/profiles/:id/followers", (req, reply) => followList(req, reply, "user_id", "follower_id"));
  app.get("/profiles/:id/following", (req, reply) => followList(req, reply, "follower_id", "user_id"));

  // ---- أحداث الملف (مراسلة، مشاركة، نقر رابط) للإحصاءات؛ أفعال المالك على ملفه لا تُحسب
  app.post("/profiles/:id/event", async (req, reply) => {
    const actor = await auth(req);
    const kind = req.body?.kind;
    if (!EVENT_KINDS.includes(kind)) return bad(reply, 400, "bad-kind");
    const u = await findUser(req.params.id); if (!u) return bad(reply, 404, "not-found");
    if (actor && actor === u.id) return { ok: true };
    try { await pool.query("INSERT INTO profile_events(user_id, actor_id, kind) VALUES($1,$2,$3)", [u.id, actor, kind]); } catch { /* ignore */ }
    return { ok: true };
  });

  // ---- إحصاءات سبعة أيام للمالك: الزيارات (فريدة لكل زائر ويوم) والأسبوع السابق للمقارنة، والأحداث، وسلسلة يومية
  app.get("/me/profile/stats", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const [visits7, visits7Prev, ev, series] = await Promise.all([
      count("SELECT count(*)::int AS n FROM profile_views WHERE user_id=$1 AND day >= current_date - 6", [uid]),
      count("SELECT count(*)::int AS n FROM profile_views WHERE user_id=$1 AND day BETWEEN current_date - 13 AND current_date - 7", [uid]),
      pool.query("SELECT kind, count(*)::int AS n FROM profile_events WHERE user_id=$1 AND created_at >= now() - interval '7 days' GROUP BY kind", [uid]).then((r) => Object.fromEntries(r.rows.map((x) => [x.kind, Number(x.n)]))).catch(() => ({})),
      pool.query(`SELECT to_char(d::date, 'YYYY-MM-DD') AS day, (SELECT count(*)::int FROM profile_views v WHERE v.user_id=$1 AND v.day=d::date) AS visits
                  FROM generate_series(current_date - 6, current_date, interval '1 day') AS d ORDER BY d`, [uid]).then((r) => r.rows.map((x) => ({ day: x.day, visits: Number(x.visits) }))).catch(() => []),
    ]);
    return { visits7, visits7Prev, messages7: ev.message ?? 0, follows7: ev.follow ?? 0, shares7: ev.share ?? 0, links7: ev.link ?? 0, series };
  });

  // ---- فحص توفر اسم المستخدم: الشكل ثم المحجوز ثم القاعدة (بلا حساسية للحالة) ثم الأسماء المحذوفة المحجوزة 90 يوماً
  app.get("/handles/check", async (req) => {
    const s = handleShape(req.query?.nickname);
    if (!s.valid) return { valid: false, available: false, reason: s.reason };
    if (RESERVED_HANDLES.includes(s.nickname)) return { valid: true, available: false, reason: "taken" };
    if (U.ok && U.nick && (await exists(`SELECT 1 FROM users WHERE lower(${q(U.nick)})=$1 LIMIT 1`, [s.nickname]))) return { valid: true, available: false, reason: "taken" };
    try { if ((await globalThis.naslifeNickReserved?.(s.nickname)) === true) return { valid: true, available: false, reason: "taken" }; } catch { /* ignore */ }
    return { valid: true, available: true, reason: null };
  });

  // ---- للإضافات الأخرى وحذف الحساب
  globalThis.naslifeProfileExt = async (uid) => loadExt(String(uid ?? ""));
  globalThis.naslifeProfileV2Delete = async (uid) => {
    const id = String(uid ?? ""); if (!id) return false;
    try {
      await pool.query("DELETE FROM profile_ext WHERE user_id=$1", [id]);
      await pool.query("DELETE FROM user_follows WHERE follower_id=$1 OR user_id=$1", [id]);
      await pool.query("DELETE FROM profile_views WHERE user_id=$1 OR viewer_id=$1", [id]);
      await pool.query("DELETE FROM profile_events WHERE user_id=$1 OR actor_id=$1", [id]);
      return true;
    } catch { return false; }
  };
}
