// إضافة Fastify لمنشورات الخريطة في Naslife: منشور بصورة أو فيديو قصير أو تسجيل صوتي أو نص، مع طبقات (نصوص وملصقات) تُرسم
// فوق الوسائط عند العرض، وحقول احترافية للمسوّقين والمستثمرين (نوع المنشور، عنوان، سعر، زر إجراء)، ومدة ظهور (يوم/3 أيام/أسبوع)،
// وإعجابات ومشاهدات. الوسائط تُرفع عبر /chat/upload ثم يُمرَّر رابطها هنا.
// المسارات تحت /mapposts (النواة تستخدم /posts لمنشورات الدوائر) والملف map_posts.js (النواة تملك posts.js).
// البث العمودي: GET /mapposts/feed?lat&lng&radiusKm&cursor&limit&place&tag&authors (مرتّب بالقرب والحداثة) وGET /mapposts/trending?lat&lng&hours
// (الأماكن الأكثر لحظاتٍ: دائرة تجارية قريبة أو اسم المكان المكتوب).
// «الجمهور» لكل لحظة (audience: friends | all، قرار المالك: الافتراضي «الأصدقاء» للحظة الشخصية) يدخل قاعدة الرؤية الواحدة
// momentVisibleSql أدناه فيسري على كل مسار يقرأ اللحظات، وعلى البث الحي (momentAudience).
// «الألبوم» (7 نوفمبر 2026): لحظة الصورة تحمل حتى 8 صور في media (مصفوفة روابط، الغلاف أولاً) وmedia_url يبقى الغلاف لكل قارئ قديم.
// التسجيل في src/index.js:
//   await app.register((await import("./map_posts.js")).default, { pool, auth });
import crypto from "node:crypto";

const UUID_RE = /^[0-9a-f-]{36}$/i;
const SLUG_RE = /^[a-z0-9-]{3,60}$/;
const HEX_RE = /^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/;
const KINDS = new Set(["text", "image", "video", "audio"]);
const TAGS = new Set(["moment", "offer", "ad", "invest", "event", "job"]);
const CTA_TYPES = new Set(["link", "whatsapp", "call", "biz", "market", "chat"]);
const TTL_HOURS = new Set([24, 72, 168]);
export const AUDIENCES = new Set(["friends", "all"]);
const MAX_OVERLAYS = 30;
/// أقصى صور الألبوم: حد الكاميرا في التطبيق (kMaxShots في capture_page.dart)
export const MAX_MEDIA = 8;
const str = (v, max = 200) => String(v ?? "").trim().slice(0, max);
const num = (v) => (v == null || v === "" ? null : Number(v));
const clamp = (v, lo, hi, d) => { const n = Number(v); return Number.isFinite(n) ? Math.min(hi, Math.max(lo, n)) : d; };

/// يتحقق من طبقات المنشور ويعيد نسخة نظيفة: نص أو ملصق بموضع نسبي ومقياس ودوران ولون.
export function cleanOverlays(input) {
  if (!Array.isArray(input)) return [];
  const out = [];
  for (const o of input.slice(0, MAX_OVERLAYS)) {
    if (!o || typeof o !== "object") continue;
    const type = o.type === "sticker" ? "sticker" : o.type === "text" ? "text" : null;
    if (!type) continue;
    const text = str(o.text, type === "sticker" ? 16 : 140);
    if (!text) continue;
    out.push({
      type, text,
      x: clamp(o.x, 0, 1, 0.5), y: clamp(o.y, 0, 1, 0.5), scale: clamp(o.scale, 0.3, 5, 1), rot: clamp(o.rot, -3.2, 3.2, 0),
      color: HEX_RE.test(String(o.color ?? "")) ? String(o.color) : "#FFFFFF",
      bg: HEX_RE.test(String(o.bg ?? "")) ? String(o.bg) : null,
      align: ["start", "center", "end"].includes(o.align) ? o.align : "center",
      font: ["bold", "hand", "serif", "plain"].includes(o.font) ? o.font : "bold",
    });
  }
  return out;
}

/// ينظّف زر الإجراء: رابط، واتساب، اتصال، دائرة تجارية، عرض في السوق، مراسلة.
export function cleanCta(c) {
  if (!c || typeof c !== "object" || !CTA_TYPES.has(c.type)) return null;
  const label = str(c.label, 40);
  let value = str(c.value, 300);
  if (c.type === "link") { if (!/^https?:\/\/[^\s]+$/i.test(value)) return null; }
  else if (c.type === "whatsapp" || c.type === "call") { value = value.replace(/[^\d+]/g, ""); if (value.replace(/\D/g, "").length < 7) return null; }
  else if (c.type === "biz") { if (!SLUG_RE.test(value)) return null; }
  else if (c.type === "market") { if (!UUID_RE.test(value)) return null; }
  else if (c.type === "chat") value = "";
  return { type: c.type, value, label: label || ({ link: "افتح الرابط", whatsapp: "واتساب", call: "اتصال", biz: "زيارة الدائرة", market: "اطلب الآن", chat: "راسلني" })[c.type] };
}

/// جمهور اللحظة حين لا يختاره الناشر صراحةً (تطبيق قديم أو عميل آخر): اللحظة الشخصية (نوع «لحظة») لأصدقائه، والمنشور التجاري
/// (نوع غير «لحظة»: عرض، إعلان، استثمار، فعالية، وظيفة؛ أو بسعر؛ أو بزر إجراء) للجميع لأن غايته الوصول. المدخلات بعد تنظيفها.
/// التطبيق يحسب الافتراضي نفسه ويعرضه قبل النشر (ComposerDraft.defaultAudience) فلا يختلف ما يراه الناشر عمّا يُحفظ.
export function defaultAudience({ tag = "moment", price = null, cta = null } = {}) {
  return (tag && tag !== "moment") || price != null || cta != null ? "all" : "friends";
}

/// صور اللحظة بالترتيب، الغلاف أولاً: media إن وُجد، وإلا [media_url] للحظات ما قبل الألبوم. الغلاف هو media_url دائماً (مصدر الحقيقة
/// لكل قارئ قديم، ولو عدّله إصدار سابق بعد تراجع النشر)، فيُقدَّم إن اختلف أول المصفوفة. غير الصورة لا ألبوم لها: وسيطها وحده.
export function albumOf(p) {
  const cover = p?.media_url ? String(p.media_url) : null;
  if (!cover) return [];
  if (p.kind !== "image") return [cover];
  const list = Array.isArray(p.media) ? p.media.filter((u) => typeof u === "string" && u) : [];
  return [cover, ...list.filter((u) => u !== cover)].slice(0, MAX_MEDIA);
}

export default async function posts(app, opts) {
  const { pool, auth } = opts;
  if (!pool || !auth) throw new Error("posts: pool and auth are required");

  await pool.query(`
    CREATE TABLE IF NOT EXISTS map_posts (
      id UUID PRIMARY KEY, user_id TEXT NOT NULL, kind TEXT NOT NULL, media_url TEXT, caption TEXT NOT NULL DEFAULT '', bg TEXT,
      overlays JSONB NOT NULL DEFAULT '[]', tag TEXT NOT NULL DEFAULT 'moment', title TEXT NOT NULL DEFAULT '', price BIGINT, cta JSONB,
      lat DOUBLE PRECISION NOT NULL, lng DOUBLE PRECISION NOT NULL, place_name TEXT, duration_sec INT, status TEXT NOT NULL DEFAULT 'active',
      views INT NOT NULL DEFAULT 0, expires_at TIMESTAMPTZ NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE INDEX IF NOT EXISTS map_posts_user ON map_posts(user_id, created_at DESC);
    CREATE INDEX IF NOT EXISTS map_posts_active ON map_posts(expires_at) WHERE status='active';
    -- «التغذية» (row.js GET /feed) تقرأ اللحظات الأحدث أولاً وتقارن مؤشرها بـ created_at مباشرة
    CREATE INDEX IF NOT EXISTS map_posts_active_created ON map_posts(created_at DESC) WHERE status='active';
    CREATE TABLE IF NOT EXISTS map_post_likes (post_id UUID NOT NULL, user_id TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (post_id, user_id));
    CREATE TABLE IF NOT EXISTS map_post_views (post_id UUID NOT NULL, user_id TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (post_id, user_id));
    ALTER TABLE map_posts ADD COLUMN IF NOT EXISTS audio_url TEXT, ADD COLUMN IF NOT EXISTS audio_sec INT;
    -- الجمهور: ما نُشر قبل الميزة نُشر للعموم فيبقى 'all' (افتراضي العمود)؛ الجديد يحدده POST /mapposts صراحةً
    ALTER TABLE map_posts ADD COLUMN IF NOT EXISTS audience TEXT NOT NULL DEFAULT 'all';
    -- الألبوم: روابط الصور بالترتيب والغلاف أولاً (= media_url)؛ NULL = لحظة قبل الميزة، تُملأ أدناه بغلافها
    ALTER TABLE map_posts ADD COLUMN IF NOT EXISTS media JSONB;
  `);
  // سجل أحداث المنشورات للإحصاءات: مشاهدة (كل فتح)، ضغطة زر الإجراء، مراسلة الناشر، إعجاب
  await pool.query(`
    CREATE TABLE IF NOT EXISTS map_post_events (
      id BIGSERIAL PRIMARY KEY, post_id UUID NOT NULL, user_id TEXT, kind TEXT NOT NULL, at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE INDEX IF NOT EXISTS map_post_events_post_at ON map_post_events(post_id, at DESC);
  `);
  const EVENT_KINDS = new Set(["view", "cta", "contact", "like"]);
  const logEvent = async (postId, uid, kind) => { try { await pool.query("INSERT INTO map_post_events(post_id,user_id,kind) VALUES($1,$2,$3)", [postId, uid, kind]); } catch { /* ignore */ } };
  // روابط حُفظت سابقاً بمضيف www. تُعاد إلى المضيف الأساسي (انظر publicOrigin)
  try { await pool.query(String.raw`UPDATE map_posts SET media_url = regexp_replace(media_url, '^(https?://)www\.', '\1', 'i') WHERE media_url ~* '^https?://www\.'`); } catch { /* ignore */ }
  try {
    await pool.query(String.raw`UPDATE map_posts SET media = (SELECT jsonb_agg(regexp_replace(e, '^(https?://)www\.', '\1', 'i') ORDER BY i) FROM jsonb_array_elements_text(media) WITH ORDINALITY t(e, i))
      WHERE jsonb_typeof(media) = 'array' AND media::text ~* '"https?://www\.'`);
    // لحظات ما قبل الألبوم: media = [media_url] (مرة واحدة فعلياً: الجديد يُكتب بمصفوفته عند النشر)
    await pool.query("UPDATE map_posts SET media = CASE WHEN media_url IS NULL THEN '[]'::jsonb ELSE jsonb_build_array(media_url) END WHERE media IS NULL");
  } catch { /* القرّاء يستنتجون الألبوم من media_url (albumOf) فلا يتعطل شيء */ }

  const unauthorized = (reply) => reply.code(401).send({ error: "auth" });
  const bad = (reply, code, error, extra = {}) => reply.code(code).send({ error, ...extra });
  const optionalAuth = async (req) => { try { return (await auth(req)) || null; } catch { return null; } };
  const userRow = async (id) => { try { return (await pool.query("SELECT * FROM users WHERE id=$1", [id])).rows[0] ?? null; } catch { return null; } };
  const person = async (id) => { const u = await userRow(id); return u ? { id: u.id, nickname: u.nickname ?? "", avatarUrl: u.avatar_url ?? u.avatarUrl ?? null } : { id, nickname: "", avatarUrl: null }; };
  const isSuspended = async (uid) => { try { return (await pool.query("SELECT 1 FROM user_flags WHERE user_id=$1 AND suspended", [uid])).rowCount > 0; } catch { return false; } };
  const isAdmin = async (uid) => { try { return !!(await globalThis.naslifeIsAdmin?.(uid)); } catch { return false; } };
  const notify = async (ids, payload) => { try { await globalThis.naslifeNotify?.(ids, payload); } catch { /* ignore */ } };
  // الأصل العام للروابط المطلقة: PUBLIC_BASE_URL إن ضُبط، وإلا مضيف الطلب بلا "www." — الموقع يُقدَّم على naslife.app
  // وwww.naslife.app معاً، وسياسة CSP تقبل الوسائط من الأصل ذاته فقط، فرابط بمضيف يخالف صفحة المستخدم لا يُعرض.
  const publicOrigin = (req) => {
    const env = String(process.env.PUBLIC_BASE_URL ?? process.env.NASLIFE_PUBLIC_URL ?? "").trim().replace(/\/+$/, "");
    if (/^https?:\/\//i.test(env)) return env;
    const proto = String(req.headers["x-forwarded-proto"] ?? "https").split(",")[0].trim() || "https";
    const host = String(req.headers["x-forwarded-host"] ?? req.headers.host ?? "naslife.app").split(",")[0].trim().replace(/^www\./i, "");
    return `${proto}://${host}`;
  };
  const OWN_MEDIA = /^https?:\/\/[^/]+(\/(?:chat\/media|files|media|uploads)\/.*)$/i;
  const absUrl = (req, url) => {
    const s = str(url, 500); if (!s) return null;
    const own = OWN_MEDIA.exec(s); if (own) return `${publicOrigin(req)}${own[1]}`;
    if (/^https?:\/\//i.test(s)) return s;
    if (!s.startsWith("/")) return null;
    return `${publicOrigin(req)}${s}`;
  };
  const bbox = (s) => { const p = String(s ?? "").split(",").map(Number); return p.length === 4 && p.every(Number.isFinite) ? { minLng: p[0], minLat: p[1], maxLng: p[2], maxLat: p[3] } : null; };
  // ---- الألبوم: صورة الألبوم ملف رفعه التطبيق عبر /chat/upload فقط (اسم ذلك المسار)، لا رابط خارجي ولا مسار آخر، وصورةٌ لا غير:
  // الرفع يقبل الفيديو والصوت وPDF أيضاً، وصفحة الألبوم والغلاف والبطاقات وog:image تعرضها صورة فتظهر مكسورة. الامتدادات هي امتدادات
  // الصور في TYPES بـ chat_tools.js، بأحرف صغيرة كـ NAME_RE هناك (المسار بغيرها لا يُقدَّم)
  const MEDIA_PATH = /^\/chat\/media\/[a-z0-9]{6,16}-[a-f0-9]{24}\.(?:jpg|png|webp|gif)$/;
  const ownMedia = (req, url) => { const u = absUrl(req, url); const own = u ? OWN_MEDIA.exec(u) : null; return own && MEDIA_PATH.test(own[1]) ? u : null; };
  // مفتاح المقارنة بين رابطين لملف واحد: المسار (المضيف قد يختلف بين رابط مخزّن وآخر مرسل)
  const mediaKey = (u) => OWN_MEDIA.exec(String(u ?? ""))?.[1] ?? String(u ?? "");
  /// صور الألبوم المرسلة: مصفوفة غير فارغة، كل عنصر من وسائطنا (أو من الألبوم الحالي [within] في التعديل: ترتيب وحذف فقط)،
  /// بلا تكرار وحتى MAX_MEDIA. يعيد {list} أو {error}.
  const albumInput = (req, input, within = null) => {
    if (!Array.isArray(input) || !input.length) return { error: "bad-media" };
    const list = [], seen = new Set();
    for (const raw of input) {
      let u;
      if (within) { const k = mediaKey(absUrl(req, raw)); u = within.find((x) => mediaKey(x) === k); if (!u) return { error: "media-not-in-album" }; }
      else { u = ownMedia(req, raw); if (!u) return { error: "bad-media" }; }
      if (seen.has(mediaKey(u))) continue;
      seen.add(mediaKey(u)); list.push(u);
    }
    return list.length > MAX_MEDIA ? { error: "too-many-media" } : { list };
  };
  const hasAlbum = (v) => (Array.isArray(v) ? v.length > 0 : v != null);

  const SELECT = `SELECT p.*, (SELECT count(*) FROM map_post_likes l WHERE l.post_id=p.id)::int AS likes,
    ($1::text IS NOT NULL AND EXISTS (SELECT 1 FROM map_post_likes l WHERE l.post_id=p.id AND l.user_id=$1)) AS liked FROM map_posts p`;
  const out = async (p, uid) => ({
    id: p.id, user: await person(p.user_id), kind: p.kind, mediaUrl: p.media_url, caption: p.caption, bg: p.bg, overlays: p.overlays ?? [], tag: p.tag, title: p.title,
    price: p.price == null ? null : Number(p.price), cta: p.cta ?? null, lat: p.lat, lng: p.lng, placeName: p.place_name, durationSec: p.duration_sec, status: p.status,
    views: Number(p.views ?? 0), likes: Number(p.likes ?? 0), liked: p.liked === true, mine: p.user_id === uid, expiresAt: p.expires_at, createdAt: p.created_at,
    expired: new Date(p.expires_at).getTime() < Date.now(),
    // طبقة صوتية اختيارية على منشور صورة أو نص (تعليق صوتي يُشغَّل مع المنشور)
    audioUrl: p.audio_url ?? null, audioSec: p.audio_sec ?? null,
    // من يرى اللحظة يعرف جمهورها (لحظة «الأصدقاء» لا تصل غيرهم أصلاً)؛ قيمة غير معروفة تُعرض «الأصدقاء» كما تعاملها القاعدة
    audience: p.audience === "all" ? "all" : "friends",
    // صور الألبوم بالترتيب والغلاف أولاً (= mediaUrl)؛ لحظة قبل الميزة = [mediaUrl]
    media: albumOf(p),
  });
  const many = async (rows, uid) => { const cache = new Map(); const res = []; for (const r of rows) { if (!cache.has(r.user_id)) cache.set(r.user_id, await person(r.user_id)); res.push({ ...(await out(r, uid)), user: cache.get(r.user_id) }); } return res; };

  // ---- من يرى اللحظة: جزء SQL واحد تستعمله كل قراءة للحظات (القوائم هنا، والصف والتغذية في row.js، ورابط المشاركة في share.js،
  // والتفاعلات في moment_extras.js، والمحفوظات في wishlist.js، وبطاقة المحادثة في chat_cards.js، والبحث المحفوظ في saved_search.js، وعدّ
  // المنشورات في profile_ext.js). يراها: صاحبها دائماً، أو صديقه (من أضافه صاحبها إلى جهات اتصاله، تعريف «من يراسلني»)، أو أي أحد حين
  // يكون جمهورها «الجميع» وملف صاحبها عاماً. فلحظة «الأصدقاء» لا يراها غريب ولا ضيف ولو كان الملف عاماً، ولحظات الملف الخاص («ملف عام»
  // مطفأ) لأصدقائه وحدهم مهما كان جمهورها. الأصدقاء والملف الخاص من قاعدة profile_ext.js (naslifeAuthorVisibleSql) وشرط الجمهور يُمرَّر
  // إليها (publicWhen) فيقيّد فرع «الملف العام» وحده. alias اسم جدول map_posts في الاستعلام (يُقرأ منه user_id وaudience)، وviewerExpr تعبير
  // نصي لمعرّف المشاهد (NULL للضيف)، و{ single: true } لاستعلام يقرأ لحظة واحدة (فحص مفتاح مرتبط بالصف بدل مجموعة تُجزَّأ للقائمة كلها؛
  // السبب في profile_ext.js). بلا عمود الخصوصية في النواة = كل ملف عام، فيبقى شرط الجمهور وحده.
  //
  // احتياط مغلق: هذه الإضافة تُقلع قبل profile_ext.js، ولو غابت قاعدته (لم تُسجَّل، أو تعثّرت قبل نشرها لو غُلّفت يوماً بـtry/catch، أو
  // نسخة قديمة لا تفهم شرط الجمهور) لا تصير لحظات الملفات الخاصة ولا لحظات «الأصدقاء» عامة. نكتشف عمود الخصوصية بأنفسنا عند الإقلاع
  // (users.is_public، وجدول ملف بمفتاح مستخدم: profiles وما يشبهه كما في profile_ext.js) ونبني جزءاً محافظاً: صاحبها، أو جمهورها «الجميع»
  // وصاحبها ليس ملفه خاصاً. الأصدقاء لا يرون لحظات «الأصدقاء» ولا لحظات الملف الخاص حتى تعود القاعدة (إغلاق عند الشك).
  const TEXTY = new Set(["text", "character varying", "character"]);
  const qi = (ident) => `"${String(ident).replace(/"/g, '""')}"`;
  const privProbes = [];
  {
    const cols = new Map();
    for (const r of (await pool.query(`SELECT table_name, column_name, data_type FROM information_schema.columns WHERE table_schema='public'
        AND table_name IN (SELECT table_name FROM information_schema.columns WHERE table_schema='public' AND column_name='is_public')`)).rows) {
      if (!cols.has(r.table_name)) cols.set(r.table_name, new Map());
      cols.get(r.table_name).set(r.column_name, r.data_type);
    }
    // لكل جدول شكلان كقاعدة profile_ext.js: مجموعة المعرّفات الخاصة للقوائم، وفحص مفتاح لصف واحد
    const probe = (table, key, type) => {
      const k = TEXTY.has(type) ? `vis_f.${qi(key)}` : `vis_f.${qi(key)}::text`;
      return {
        ids: `SELECT ${k} FROM ${qi(table)} vis_f WHERE vis_f.is_public = false AND vis_f.${qi(key)} IS NOT NULL`,
        one: (who) => `EXISTS (SELECT 1 FROM ${qi(table)} vis_f WHERE ${k} = ${who} AND vis_f.is_public = false)`,
      };
    };
    const u = cols.get("users");
    if (u?.has("id")) privProbes.push(probe("users", "id", u.get("id")));
    for (const [t, c] of cols) {
      if (t === "users") continue;
      // ما قد يختاره profile_ext.js جدولاً للملف: اسمه فيه profile أو فيه النبذة والمهارات (لا جداول الدوائر وغيرها بعمود is_public)
      if (!/profile/.test(t) && !(c.has("bio") && c.has("skills"))) continue;
      const key = ["user_id", "id", "uid"].find((k) => c.has(k));
      if (key) privProbes.push(probe(t, key, c.get(key)));
    }
  }
  const privateOf = (who) => (privProbes.length ? `(${privProbes.map((x) => x.one(who)).join(" OR ")})` : null);
  const PRIVATE_IDS = privProbes.length ? privProbes.map((x) => x.ids).join(" UNION ALL ") : null;
  // «الجمهور: الجميع» شرط على الصف نفسه؛ أي قيمة أخرى (ومنها NULL) = «الأصدقاء» (إغلاق عند الشك)
  const audienceAll = (alias) => `${alias}.audience = 'all'`;
  const closedVisibleSql = (alias, viewerExpr, { single = false } = {}) => {
    // يذكر معامل المشاهد دائماً: Postgres يرفض معاملاً مرسلاً لا يظهر في الاستعلام (الإعجاب يمرّره لهذا الجزء وحده)
    const open = !PRIVATE_IDS ? audienceAll(alias)
      : `(${audienceAll(alias)} AND ${single ? `NOT ${privateOf(`${alias}.user_id`)}` : `${alias}.user_id NOT IN (${PRIVATE_IDS})`})`;
    return `COALESCE((${alias}.user_id = ${viewerExpr} OR ${open}), false)`;
  };
  // القاعدة تفهم شرط الجمهور؟ (علامة publicWhen في profile_ext.js) نسخة لا تفهمه كانت ستتجاهله فتفتح لحظات «الأصدقاء» للعموم
  const fullRule = () => { const f = globalThis.naslifeAuthorVisibleSql; return typeof f === "function" && f.publicWhen === true ? f : null; };
  const momentVisibleSql = (alias, viewerExpr, opts = {}) => {
    const f = fullRule();
    return f ? f(`${alias}.user_id`, viewerExpr, { ...opts, publicWhen: audienceAll(alias) }) : closedVisibleSql(alias, viewerExpr, opts);
  };
  globalThis.naslifeMomentVisibleSql = momentVisibleSql;
  // صور الألبوم لصف map_posts (الغلاف أولاً) للإضافات التي تبني شكل اللحظة بنفسها (row.js) أو تنظّف وسائطها
  globalThis.naslifeMomentMedia = albumOf;
  // بعد تحميل الإضافات كلها: بلا قاعدة profile_ext.js يعمل الاحتياط المغلق (لحظات «الأصدقاء» لصاحبها وحده، ولحظات الملف الخاص كذلك
  // إن وُجد عمود الخصوصية)، فننبّه في السجل
  app.addHook("onReady", async () => {
    if (!fullRule()) {
      console.warn(`map_posts: profile_ext.js rule (naslifeAuthorVisibleSql with audience support) is missing; friends-only moments${privProbes.length ? " and private profiles' moments" : ""} are shown to their authors only until it loads`);
    }
  });
  // جمهور البث الحي للحظة جديدة بالقاعدة نفسها: null = الجميع، وإلا من تُسلَّم إليهم فقط (صاحبها وأصدقاؤه). لحظة «الأصدقاء» أو ملف
  // خاص = صاحبها وأصدقاؤه. بلا قاعدة profile_ext.js فالاحتياط نفسه (صاحبها وحده لغير العام)، وعند الشك (خطأ القاعدة) صاحبها وحده
  const momentAudience = async (p) => {
    try {
      const everyone = p.audience === "all";
      if (fullRule() && typeof globalThis.naslifeIsPublic === "function") {
        if (everyone && (await globalThis.naslifeIsPublic(p.user_id))) return null;
        return [p.user_id, ...((await globalThis.naslifeFriendIds?.(p.user_id)) ?? [])];
      }
      if (!everyone) return [p.user_id];
      const priv = privateOf("$1::text");
      if (!priv) return null;
      return (await pool.query(`SELECT ${priv} AS priv`, [p.user_id])).rows[0]?.priv === false ? null : [p.user_id];
    } catch { return [p.user_id]; }
  };

  // ---- إنشاء
  app.post("/mapposts", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (await isSuspended(uid)) return bad(reply, 403, "suspended");
    const b = req.body ?? {};
    const kind = KINDS.has(b.kind) ? b.kind : null; if (!kind) return bad(reply, 400, "bad-kind");
    let mediaUrl = kind === "text" ? null : absUrl(req, b.mediaUrl);
    // الألبوم (mediaUrls، لحظة الصورة فقط): الغلاف أولها، وmediaUrl إن أُرسل معه يجب أن يكون هو الغلاف
    let media = mediaUrl ? [mediaUrl] : [];
    if (hasAlbum(b.mediaUrls)) {
      if (kind !== "image") return bad(reply, 400, "album-images-only");
      const a = albumInput(req, b.mediaUrls);
      if (a.error) return bad(reply, 400, a.error, { max: MAX_MEDIA });
      if (mediaUrl && mediaKey(mediaUrl) !== mediaKey(a.list[0])) return bad(reply, 400, "cover-mismatch");
      media = a.list; mediaUrl = media[0];
    }
    if (kind !== "text" && !mediaUrl) return bad(reply, 400, "bad-media");
    const lat = num(b.lat), lng = num(b.lng);
    if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) return bad(reply, 400, "bad-location");
    const caption = str(b.caption, 500);
    const overlays = cleanOverlays(b.overlays);
    if (kind === "text" && !caption && !overlays.some((o) => o.type === "text") && !absUrl(req, b.audioUrl)) return bad(reply, 400, "empty");
    const banned = globalThis.naslifeCheckText?.(caption, str(b.title, 80), str(b.placeName, 80), ...overlays.filter((o) => o.type === "text").map((o) => o.text));
    if (banned) return reply.code(400).send({ error: "banned-words", word: banned });
    const ttl = TTL_HOURS.has(Number(b.ttlHours)) ? Number(b.ttlHours) : 24;
    const price = b.price == null || b.price === "" ? null : Math.max(0, Math.round(Number(b.price) || 0));
    const tag = TAGS.has(b.tag) ? b.tag : "moment", cta = cleanCta(b.cta);
    // الجمهور: اختيار الناشر إن أرسله، وإلا الافتراضي بنوع المنشور (defaultAudience أعلاه)
    const missing = b.audience == null || b.audience === "";
    if (!missing && !AUDIENCES.has(b.audience)) return bad(reply, 400, "bad-audience");
    const audience = missing ? defaultAudience({ tag, price, cta }) : b.audience;
    const id = crypto.randomUUID();
    const audioUrl = kind === "image" || kind === "text" ? absUrl(req, b.audioUrl) : null;
    const audioSec = audioUrl && b.audioSec != null ? Math.round(clamp(b.audioSec, 1, 600, 0)) || null : null;
    // منشور نصي بلا نص لكن بتسجيل صوتي: مقبول (لوحة صوتية)
    if (kind === "text" && !caption && !overlays.some((o) => o.type === "text") && !audioUrl) return bad(reply, 400, "empty");
    await pool.query(`INSERT INTO map_posts(id,user_id,kind,media_url,caption,bg,overlays,tag,title,price,cta,lat,lng,place_name,duration_sec,expires_at,audio_url,audio_sec,audience,media)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15, now() + ($16 || ' hours')::interval,$17,$18,$19,$20)`,
      [id, uid, kind, mediaUrl, caption, HEX_RE.test(String(b.bg ?? "")) ? String(b.bg) : null, JSON.stringify(overlays), tag, str(b.title, 80), price,
       JSON.stringify(cta), lat, lng, str(b.placeName, 80) || null, b.durationSec == null ? null : Math.round(clamp(b.durationSec, 0, 600, 0)), String(ttl), audioUrl, audioSec, audience, JSON.stringify(media)]);
    const row = (await pool.query(`${SELECT} WHERE p.id=$2`, [uid, id])).rows[0];
    // بث فوري للتطبيقات المفتوحة (الخط الزمني والخريطة) بصيغة المشاهد نفسها؛ من منظور عام (لا mine ولا liked)،
    // ولحظة «الأصدقاء» أو لحظة صاحب الملف الخاص تُسلَّم لجمهورها فقط (live.js يصفّي لكل مستمع)
    try { globalThis.naslifeLive?.emit("post", { ...(await out(row, null)), user: await person(uid) }, { only: await momentAudience(row) }); } catch { /* البث لا يعطّل النشر */ }
    // إشعار من يتابع الناشر ويرى اللحظة (profile_ext.js: قاعدة الرؤية والحظر والإيقاف وحد 6 ساعات)؛ النشر لا ينتظره
    Promise.resolve().then(() => globalThis.naslifeNotifyFollowers?.(row)).catch(() => {});
    return out(row, uid);
  });

  // ---- القوائم: على الخريطة (حدود)، الأحدث للرئيسية، منشوراتي
  app.get("/mapposts", async (req) => {
    const uid = await optionalAuth(req);
    const bb = bbox(req.query?.bbox);
    const limit = Math.max(1, Math.min(300, Number(req.query?.limit) || 200));
    const tag = TAGS.has(req.query?.tag) ? req.query.tag : null;
    // من حظرهم المستخدم أو حظروه لا يظهر محتواهم له
    const blocked = uid ? await (globalThis.naslifeBlockedIds?.(uid) ?? []) : [];
    const rows = (await pool.query(`${SELECT} WHERE p.status='active' AND p.expires_at > now()
      AND ($2::float8 IS NULL OR (p.lat BETWEEN $3 AND $5 AND p.lng BETWEEN $2 AND $4)) AND ($6::text IS NULL OR p.tag=$6)
      AND NOT (p.user_id = ANY($8::text[])) AND ${momentVisibleSql("p", "$1::text")}
      ORDER BY p.created_at DESC LIMIT $7`, [uid, bb?.minLng ?? null, bb?.minLat ?? null, bb?.maxLng ?? null, bb?.maxLat ?? null, tag, limit, blocked])).rows;
    return many(rows, uid);
  });
  // ---- البث العمودي «الآن حولك» والأماكن الرائجة
  // مسافة هافرساين بالكيلومتر بين نقطة الطلب ($2, $3) والمنشور
  const DIST_P = `(2 * 6371 * asin(least(1, sqrt(power(sin(radians(($2::float8 - p.lat) / 2)), 2) + cos(radians($2::float8)) * cos(radians(p.lat)) * power(sin(radians(($3::float8 - p.lng) / 2)), 2)))))`;
  // أقرب دائرة تجارية ضمن 250 متراً من المنشور (إن وُجد جدول الدوائر) لنسب اللحظة إلى مكان معروف
  let hasBiz = false;
  const checkBiz = async () => { try { hasBiz = (await pool.query("SELECT to_regclass('biz') IS NOT NULL AS ok")).rows[0]?.ok === true; } catch { hasBiz = false; } };
  await checkBiz();
  const BIZ_JOIN = `LEFT JOIN LATERAL (SELECT b.id, b.name_ar, b.name, b.category, b.logo_url, b.lat AS blat, b.lng AS blng,
      (2 * 6371 * asin(least(1, sqrt(power(sin(radians((p.lat - b.lat) / 2)), 2) + cos(radians(p.lat)) * cos(radians(b.lat)) * power(sin(radians((p.lng - b.lng) / 2)), 2))))) AS bdist
      FROM biz b WHERE b.active AND abs(b.lat - p.lat) < 0.004 AND abs(b.lng - p.lng) < 0.004 ORDER BY bdist LIMIT 1) nb ON nb.bdist < 0.25`;
  const NO_BIZ_JOIN = `LEFT JOIN LATERAL (SELECT NULL::text AS id, NULL::text AS name_ar, NULL::text AS name, NULL::text AS category, NULL::text AS logo_url, NULL::float8 AS blat, NULL::float8 AS blng, NULL::float8 AS bdist) nb ON false`;
  const bizJoin = () => (hasBiz ? BIZ_JOIN : NO_BIZ_JOIN);
  // مفتاح المكان: الدائرة القريبة، وإلا اسم المكان المكتوب، وإلا خلية جغرافية صغيرة
  const PLACE_KEY = `COALESCE('biz:' || nb.id, CASE WHEN p.place_name IS NOT NULL AND p.place_name <> '' THEN 'name:' || lower(p.place_name) END, 'cell:' || round(p.lat::numeric, 3) || ',' || round(p.lng::numeric, 3))`;
  const PLACE_NAME = `COALESCE(NULLIF(nb.name_ar, ''), nb.name, NULLIF(p.place_name, ''))`;
  const placeOf = (r) => (r.place_key ? { key: r.place_key, name: r.place_name_r ?? r.place_name ?? null, bizId: r.nb_id ?? null, category: r.nb_category ?? null, logoUrl: r.nb_logo ?? null } : null);
  const round1 = (v) => (v == null ? null : Math.round(Number(v) * 10) / 10);

  app.get("/mapposts/feed", async (req) => {
    const uid = await optionalAuth(req);
    const lat = num(req.query?.lat), lng = num(req.query?.lng);
    const has = Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180;
    const radius = clamp(req.query?.radiusKm, 1, 200, 30);
    const limit = Math.round(clamp(req.query?.limit, 1, 60, 20));
    const offset = Math.round(clamp(req.query?.cursor, 0, 100000, 0));
    const place = str(req.query?.place, 120) || null;
    const tag = TAGS.has(req.query?.tag) ? req.query.tag : null;
    // «أصدقائي فقط»: التطبيق يمرّر معرّفات جهات اتصاله (النواة تملك جدول الأصدقاء)؛ قائمة فارغة تعني لا نتائج
    const authorsRaw = req.query?.authors;
    const authors = authorsRaw == null ? null : String(authorsRaw).split(",").map((v) => v.trim().toUpperCase()).filter((v) => /^[A-Z]{2}\d{7}$/.test(v)).slice(0, 300);
    const blocked = uid ? await (globalThis.naslifeBlockedIds?.(uid) ?? []) : [];
    // «لحظات هنا» (place=biz:<id>) بلا موقع: بلا هذا الصندوق يُحسب أقرب دائرة لكل لحظة نشطة في المنصة ثم يُصفّى بالمفتاح.
    // اللحظة تُنسب إلى دائرة ضمن 250 م فقط، فصندوق ±0.003° (أوسع قليلاً) حول الدائرة يحصر الحساب فيما يمكن أن يُنسب إليها
    let box = null;
    const placeBiz = hasBiz && place?.startsWith("biz:") ? place.slice(4) : null;
    if (placeBiz) {
      try {
        const c = (await pool.query("SELECT lat, lng FROM biz WHERE id=$1 AND active", [placeBiz])).rows[0];
        if (!c) return { items: [], nextCursor: null, radiusKm: radius, located: has };
        const dLat = 0.003, dLng = 0.003 / Math.max(0.2, Math.cos((Number(c.lat) * Math.PI) / 180));
        box = [Number(c.lat) - dLat, Number(c.lat) + dLat, Number(c.lng) - dLng, Number(c.lng) + dLng];
      } catch { box = null; /* بلا صندوق: الاستعلام الكامل يبقى صحيحاً */ }
    }
    const run = () => pool.query(`SELECT * FROM (${SELECT.replace("FROM map_posts p", "")}, (CASE WHEN $2::float8 IS NULL OR $3::float8 IS NULL THEN NULL ELSE ${DIST_P} END) AS dist,
        ${PLACE_KEY} AS place_key, ${PLACE_NAME} AS place_name_r, nb.id AS nb_id, nb.category AS nb_category, nb.logo_url AS nb_logo
        FROM map_posts p ${bizJoin()}
        WHERE p.status='active' AND p.expires_at > now() AND NOT (p.user_id = ANY($4::text[])) AND ($5::text IS NULL OR p.tag=$5)
          AND ($10::text[] IS NULL OR p.user_id = ANY($10::text[])) AND ${momentVisibleSql("p", "$1::text")}
          AND ($11::float8 IS NULL OR (p.lat BETWEEN $11 AND $12 AND p.lng BETWEEN $13 AND $14))) x
      WHERE (x.dist IS NULL OR x.dist <= $6) AND ($7::text IS NULL OR x.place_key = $7)
      ORDER BY (EXTRACT(EPOCH FROM (now() - x.created_at)) / 3600.0) + COALESCE(x.dist, 0) * 1.5 ASC, x.created_at DESC
      LIMIT $8 OFFSET $9`, [uid, has ? lat : null, has ? lng : null, blocked, tag, radius, place, limit + 1, offset, authors, ...(box ?? [null, null, null, null])]);
    let rows;
    try { rows = (await run()).rows; } catch (e) { if (hasBiz) { hasBiz = false; rows = (await run()).rows; } else throw e; }
    const more = rows.length > limit;
    const page = more ? rows.slice(0, limit) : rows;
    const items = (await many(page, uid)).map((o, i) => ({ ...o, distanceKm: round1(page[i].dist), place: placeOf(page[i]) }));
    return { items, nextCursor: more ? offset + limit : null, radiusKm: radius, located: has };
  });

  app.get("/mapposts/trending", async (req) => {
    const uid = await optionalAuth(req);
    const lat = num(req.query?.lat), lng = num(req.query?.lng);
    const has = Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180;
    const hours = Math.round(clamp(req.query?.hours, 1, 168, 24));
    const radius = clamp(req.query?.radiusKm, 1, 500, 60);
    const limit = Math.round(clamp(req.query?.limit, 1, 30, 10));
    const blocked = uid ? await (globalThis.naslifeBlockedIds?.(uid) ?? []) : [];
    const run = () => pool.query(`WITH x AS (
        SELECT p.id, p.kind, p.media_url, p.bg, p.user_id, p.created_at, p.lat, p.lng, $1::text AS viewer, (CASE WHEN $2::float8 IS NULL OR $3::float8 IS NULL THEN NULL ELSE ${DIST_P} END) AS dist,
          ${PLACE_KEY} AS key, ${PLACE_NAME} AS name, nb.id AS biz_id, nb.category, nb.logo_url, nb.blat, nb.blng
        FROM map_posts p ${bizJoin()}
        WHERE p.status='active' AND p.expires_at > now() AND p.created_at > now() - ($4 || ' hours')::interval AND NOT (p.user_id = ANY($5::text[]))
          AND ${momentVisibleSql("p", "$1::text")})
      SELECT key, max(name) AS name, max(biz_id) AS biz_id, max(category) AS category, max(logo_url) AS logo_url,
        COALESCE(max(blat), avg(lat)) AS lat, COALESCE(max(blng), avg(lng)) AS lng, min(dist) AS dist, count(*)::int AS posts, count(DISTINCT user_id)::int AS authors, max(created_at) AS latest,
        (array_agg(id ORDER BY created_at DESC))[1] AS sample_id, (array_agg(kind ORDER BY created_at DESC))[1] AS sample_kind,
        (array_agg(media_url ORDER BY created_at DESC))[1] AS sample_url, (array_agg(bg ORDER BY created_at DESC))[1] AS sample_bg
      FROM x WHERE name IS NOT NULL AND (dist IS NULL OR dist <= $6)
      GROUP BY key ORDER BY posts DESC, latest DESC LIMIT $7`, [uid, has ? lat : null, has ? lng : null, String(hours), blocked, radius, limit]);
    let rows;
    try { rows = (await run()).rows; } catch (e) { if (hasBiz) { hasBiz = false; rows = (await run()).rows; } else throw e; }
    return { hours, places: rows.map((r) => ({ key: r.key, name: r.name, bizId: r.biz_id, category: r.category, logoUrl: r.logo_url, lat: Number(r.lat), lng: Number(r.lng), distanceKm: round1(r.dist), posts: r.posts, authors: r.authors, latest: r.latest, sampleId: r.sample_id, sampleKind: r.sample_kind, sampleUrl: r.sample_url, sampleBg: r.sample_bg })) };
  });

  app.get("/mapposts/mine", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const rows = (await pool.query(`${SELECT} WHERE p.user_id=$1 AND p.created_at > now() - interval '30 days' ORDER BY p.created_at DESC LIMIT 200`, [uid])).rows;
    return many(rows, uid);
  });
  app.get("/mapposts/:id", async (req, reply) => {
    const uid = await optionalAuth(req);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const p = (await pool.query(`${SELECT.replace(" FROM map_posts p", `, ${momentVisibleSql("p", "$1::text", { single: true })} AS visible FROM map_posts p`)} WHERE p.id=$2`, [uid, req.params.id])).rows[0];
    if (!p) return bad(reply, 404, "not-found");
    if (p.status !== "active" && p.user_id !== uid && !(await isAdmin(uid))) return bad(reply, 404, "not-found");
    // لحظة «الأصدقاء» أو لحظة صاحب ملف خاص لغير أصدقائه (والضيف) كأنها غير موجودة؛ الإدارة تراها للإشراف على البلاغات
    if (p.visible === false && p.user_id !== uid && !(await isAdmin(uid))) return bad(reply, 404, "not-found");
    // رابط مباشر لمنشور كاتبه محظور (في أي اتجاه) يُعامل كأنه غير موجود
    if (uid && p.user_id !== uid) { let bl = []; try { bl = (await globalThis.naslifeBlockedIds?.(uid)) ?? []; } catch { bl = []; } if (bl.includes(p.user_id)) return bad(reply, 404, "not-found"); }
    return out(p, uid);
  });

  // ---- تعديل (صاحب المنشور): النص والطبقات والحقول الاحترافية والإظهار/الإخفاء وتمديد المدة
  app.patch("/mapposts/:id", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const p = (await pool.query("SELECT * FROM map_posts WHERE id=$1", [req.params.id])).rows[0];
    if (!p) return bad(reply, 404, "not-found");
    if (p.user_id !== uid) return bad(reply, 403, "forbidden");
    const b = req.body ?? {}; const sets = []; const vals = [];
    const set = (c, v) => { vals.push(v); sets.push(`${c}=$${vals.length}`); };
    const bannedP = globalThis.naslifeCheckText?.(b.caption, b.title, b.placeName, ...(Array.isArray(b.overlays) ? b.overlays.map((o) => o?.text) : []));
    if (bannedP) return reply.code(400).send({ error: "banned-words", word: bannedP });
    if (b.caption !== undefined) set("caption", str(b.caption, 500));
    if (b.overlays !== undefined) set("overlays", JSON.stringify(cleanOverlays(b.overlays)));
    if (b.bg !== undefined) set("bg", HEX_RE.test(String(b.bg ?? "")) ? String(b.bg) : null);
    if (b.tag !== undefined) set("tag", TAGS.has(b.tag) ? b.tag : "moment");
    if (b.title !== undefined) set("title", str(b.title, 80));
    if (b.price !== undefined) set("price", b.price == null || b.price === "" ? null : Math.max(0, Math.round(Number(b.price) || 0)));
    if (b.cta !== undefined) set("cta", JSON.stringify(cleanCta(b.cta)));
    if (b.placeName !== undefined) set("place_name", str(b.placeName, 80) || null);
    // الألبوم: mediaUrls يرتّب صور الألبوم الحالي أو يحذف منها (لا إضافة)، والأولى هي الغلاف. mediaUrl وحده (عميل قديم أو وسيط
    // جديد) يحل محل الغلاف وتبقى بقية الألبوم، وصورة من الألبوم نفسه تتقدّم غلافاً بلا حذف شيء
    const album = albumOf(p);
    if (hasAlbum(b.mediaUrls)) {
      if (p.kind !== "image") return bad(reply, 400, "album-images-only");
      const a = albumInput(req, b.mediaUrls, album);
      if (a.error) return bad(reply, 400, a.error, { max: MAX_MEDIA });
      if (b.mediaUrl != null && b.mediaUrl !== "" && mediaKey(absUrl(req, b.mediaUrl)) !== mediaKey(a.list[0])) return bad(reply, 400, "cover-mismatch");
      set("media_url", a.list[0]); set("media", JSON.stringify(a.list));
    } else if (b.mediaUrl !== undefined && p.kind !== "text") {
      const u = absUrl(req, b.mediaUrl); if (!u) return bad(reply, 400, "bad-media");
      const at = album.findIndex((x) => mediaKey(x) === mediaKey(u));
      const next = p.kind !== "image" ? [u] : at >= 0 ? [album[at], ...album.filter((_, i) => i !== at)] : [u, ...album.slice(1)];
      set("media_url", next[0]); set("media", JSON.stringify(next));
    }
    if (b.audioUrl !== undefined && (p.kind === "image" || p.kind === "text")) { const u = absUrl(req, b.audioUrl); set("audio_url", u); set("audio_sec", u && b.audioSec != null ? Math.round(clamp(b.audioSec, 1, 600, 0)) || null : null); }
    if (b.status !== undefined) { if (!["active", "hidden"].includes(b.status)) return bad(reply, 400, "bad-status"); if (p.status === "blocked") return bad(reply, 403, "blocked"); set("status", b.status); }
    if (b.ttlHours !== undefined) { if (!TTL_HOURS.has(Number(b.ttlHours))) return bad(reply, 400, "bad-ttl"); vals.push(String(Number(b.ttlHours))); sets.push(`expires_at=now() + ($${vals.length} || ' hours')::interval`); }
    // الجمهور يغيّره صاحبها وحده (فحص الملكية أعلاه)؛ القيمة إما «الأصدقاء» أو «الجميع» صراحةً
    if (b.audience !== undefined) { if (!AUDIENCES.has(b.audience)) return bad(reply, 400, "bad-audience"); set("audience", b.audience); }
    if (!sets.length) return bad(reply, 400, "empty");
    sets.push("updated_at=now()");
    vals.push(p.id);
    await pool.query(`UPDATE map_posts SET ${sets.join(", ")} WHERE id=$${vals.length}`, vals);
    const row = (await pool.query(`${SELECT} WHERE p.id=$2`, [uid, p.id])).rows[0];
    if (b.audience !== undefined && b.audience !== (p.audience === "all" ? "all" : "friends")) await liveAudienceChanged(row);
    return out(row, uid);
  });
  // تغيّر جمهور لحظة ظاهرة: التطبيقات المفتوحة تتبع القاعدة بلا انتظار تحديث. التضييق إلى «الأصدقاء» يُزيلها من كل قائمة مفتوحة
  // (post_removed للجميع: معرّف بلا محتوى) ثم يعيد جلب جمهورها الجديد (post_restored لصاحبها وأصدقائه) فتعود عندهم؛ والتوسيع إلى
  // «الجميع» يعيد الجلب عند من صار يراها (الجميع إن كان الملف عاماً، وإلا لا جديد: أصدقاؤه كانوا يرونها)
  const liveAudienceChanged = async (row) => {
    try {
      if (!row || row.status !== "active" || new Date(row.expires_at).getTime() < Date.now()) return;
      const only = await momentAudience(row);
      if (row.audience !== "all") {
        globalThis.naslifeLive?.emit("post_removed", { id: row.id });
        globalThis.naslifeLive?.emit("post_restored", { id: row.id }, { only });
      } else if (only === null) globalThis.naslifeLive?.emit("post_restored", { id: row.id });
    } catch { /* البث لا يعطّل الحفظ */ }
  };
  app.delete("/mapposts/:id", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const p = (await pool.query("SELECT user_id FROM map_posts WHERE id=$1", [req.params.id])).rows[0];
    if (!p) return bad(reply, 404, "not-found");
    if (p.user_id !== uid && !(await isAdmin(uid))) return bad(reply, 403, "forbidden");
    await pool.query("DELETE FROM map_post_likes WHERE post_id=$1", [req.params.id]);
    await pool.query("DELETE FROM map_post_views WHERE post_id=$1", [req.params.id]);
    await pool.query("DELETE FROM map_posts WHERE id=$1", [req.params.id]);
    globalThis.naslifeLive?.emit("post_removed", { id: req.params.id });
    return { ok: true };
  });

  // يرى المشاهد هذه اللحظة؟ (القاعدة الواحدة بفحص مفتاح)؛ خطأ القاعدة = لا (إغلاق عند الشك)
  const canSee = async (id, uid) => {
    try { return (await pool.query(`SELECT ${momentVisibleSql("map_posts", "$2::text", { single: true })} AS v FROM map_posts WHERE id=$1`, [id, uid ?? null])).rows[0]?.v === true; } catch { return false; }
  };

  // ---- مشاهدة (مرة لكل مستخدم) وإعجاب (تبديل) وحجب إداري
  app.post("/mapposts/:id/view", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    // من لا يرى اللحظة (جمهورها «الأصدقاء» أو ملف صاحبها خاص) لا يُحسب مشاهداً ولا يأخذ عدد مشاهداتها
    if (!(await canSee(req.params.id, uid))) return bad(reply, 404, "not-found");
    const r = await pool.query("INSERT INTO map_post_views(post_id,user_id) VALUES($1,$2) ON CONFLICT DO NOTHING RETURNING 1", [req.params.id, uid]);
    if (r.rowCount) await pool.query("UPDATE map_posts SET views=views+1 WHERE id=$1 AND user_id<>$2", [req.params.id, uid]);
    const own = (await pool.query("SELECT 1 FROM map_posts WHERE id=$1 AND user_id=$2", [req.params.id, uid])).rowCount > 0;
    if (!own) await logEvent(req.params.id, uid, "view");
    const v = (await pool.query("SELECT views FROM map_posts WHERE id=$1", [req.params.id])).rows[0];
    return { ok: true, views: Number(v?.views ?? 0) };
  });
  app.post("/mapposts/:id/like", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const p = (await pool.query(`SELECT user_id, caption, title, ${momentVisibleSql("map_posts", "$2::text", { single: true })} AS visible FROM map_posts WHERE id=$1 AND status='active'`, [req.params.id, uid])).rows[0];
    // من لا يرى اللحظة (ملف صاحبها خاص وليس صديقاً) لا يعجب بها
    if (!p || p.visible === false) return bad(reply, 404, "not-found");
    const del = await pool.query("DELETE FROM map_post_likes WHERE post_id=$1 AND user_id=$2 RETURNING 1", [req.params.id, uid]);
    let liked = false;
    if (!del.rowCount) {
      await pool.query("INSERT INTO map_post_likes(post_id,user_id) VALUES($1,$2) ON CONFLICT DO NOTHING", [req.params.id, uid]);
      liked = true;
      if (p.user_id !== uid) await logEvent(req.params.id, uid, "like");
      if (p.user_id !== uid) await notify(p.user_id, { kind: "post_like", title: "إعجاب بمنشورك", body: `${(await person(uid)).nickname || uid} أعجب بمنشورك${p.title ? " «" + p.title + "»" : ""}`, data: { postId: req.params.id } });
    }
    const n = (await pool.query("SELECT count(*)::int AS n FROM map_post_likes WHERE post_id=$1", [req.params.id])).rows[0].n;
    return { ok: true, liked, likes: n };
  });
  // ---- تتبّع زر الإجراء والمراسلة (للإحصاءات)
  for (const kind of ["cta", "contact"]) {
    app.post(`/mapposts/:id/${kind}`, async (req, reply) => {
      const uid = await auth(req); if (!uid) return unauthorized(reply);
      if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
      const p = (await pool.query("SELECT user_id FROM map_posts WHERE id=$1", [req.params.id])).rows[0];
      if (!p) return bad(reply, 404, "not-found");
      // إحصاءات الناشر تعدّ من يرى اللحظة فقط
      if (p.user_id !== uid && (await canSee(req.params.id, uid))) await logEvent(req.params.id, uid, kind);
      return { ok: true };
    });
  }

  // ---- الإحصاءات: لكل منشور (المالك أو الإدارة)، ولكل منشوراتي، ولمنشورات دائرة تجارية (مالكها أو طاقمها أو الإدارة)
  const daysOf = (v) => Math.max(1, Math.min(90, Math.round(Number(v)) || 7));
  const emptyTotals = () => ({ views: 0, cta: 0, contacts: 0, likes: 0 });
  const fieldOf = (kind) => ({ view: "views", like: "likes", contact: "contacts", cta: "cta" })[kind] ?? null;
  async function series(postIds, days) {
    if (!postIds.length) return { totals: emptyTotals(), uniqueViews: 0, hourly: [], daily: [] };
    const t = (await pool.query(`SELECT kind, count(*)::int AS n FROM map_post_events WHERE post_id = ANY($1::uuid[]) AND at > now() - ($2 || ' days')::interval GROUP BY kind`, [postIds, String(days)])).rows;
    const totals = emptyTotals(); for (const r of t) { const f = fieldOf(r.kind); if (f) totals[f] = r.n; }
    const uniq = (await pool.query("SELECT count(*)::int AS n FROM map_post_views v JOIN map_posts p ON p.id=v.post_id WHERE v.post_id = ANY($1::uuid[]) AND v.user_id <> p.user_id", [postIds])).rows[0].n;
    const h = (await pool.query(`SELECT date_trunc('hour', at) AS h, kind, count(*)::int AS n FROM map_post_events WHERE post_id = ANY($1::uuid[]) AND at > now() - interval '24 hours' GROUP BY 1, 2`, [postIds])).rows;
    const hourly = []; const nowH = new Date(); nowH.setMinutes(0, 0, 0);
    for (let i = 23; i >= 0; i--) { const at = new Date(nowH.getTime() - i * 3600e3); hourly.push({ at: at.toISOString(), views: 0, cta: 0, contacts: 0, likes: 0 }); }
    for (const r of h) { const slot = hourly.find((x) => x.at === new Date(r.h).toISOString()); const f = fieldOf(r.kind); if (slot && f) slot[f] = r.n; }
    const d = (await pool.query(`SELECT (at AT TIME ZONE 'Asia/Riyadh')::date AS d, kind, count(*)::int AS n FROM map_post_events WHERE post_id = ANY($1::uuid[]) AND at > now() - ($2 || ' days')::interval GROUP BY 1, 2`, [postIds, String(days)])).rows;
    const daily = []; const today = new Date(Date.now() + 3 * 3600e3);
    for (let i = days - 1; i >= 0; i--) { const dd = new Date(today.getTime() - i * 86400e3); daily.push({ date: dd.toISOString().slice(0, 10), views: 0, cta: 0, contacts: 0, likes: 0 }); }
    for (const r of d) { const key = r.d instanceof Date ? new Date(r.d.getTime() - r.d.getTimezoneOffset() * 60000).toISOString().slice(0, 10) : String(r.d).slice(0, 10); const slot = daily.find((x) => x.date === key); const f = fieldOf(r.kind); if (slot && f) slot[f] = r.n; }
    return { totals, uniqueViews: uniq, hourly, daily };
  }
  const postBrief = (p) => ({ id: p.id, title: p.title || p.caption || (p.kind === "text" ? "منشور نصي" : "منشور"), kind: p.kind, tag: p.tag, status: p.status, createdAt: p.created_at, expiresAt: p.expires_at });
  async function perPost(postIds, days) {
    if (!postIds.length) return new Map();
    const rows = (await pool.query(`SELECT post_id, kind, count(*)::int AS n FROM map_post_events WHERE post_id = ANY($1::uuid[]) AND at > now() - ($2 || ' days')::interval GROUP BY 1, 2`, [postIds, String(days)])).rows;
    const m = new Map(); for (const id of postIds) m.set(id, emptyTotals());
    for (const r of rows) { const t = m.get(r.post_id); const f = fieldOf(r.kind); if (t && f) t[f] = r.n; }
    return m;
  }
  app.get("/mapposts/stats/mine", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const days = daysOf(req.query?.days);
    const posts = (await pool.query("SELECT * FROM map_posts WHERE user_id=$1 AND created_at > now() - interval '90 days' ORDER BY created_at DESC LIMIT 200", [uid])).rows;
    const ids = posts.map((p) => p.id);
    const agg = await series(ids, days); const per = await perPost(ids, days);
    return { days, posts: posts.length, ...agg, byPost: posts.map((p) => ({ ...postBrief(p), ...per.get(p.id) })) };
  });
  app.get("/mapposts/stats/biz/:slug", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const slug = str(req.params.slug, 64); const days = daysOf(req.query?.days);
    const admin = await isAdmin(uid);
    let allowed = admin;
    if (!allowed) {
      try {
        const b = (await pool.query("SELECT owner_id FROM biz WHERE id=$1", [slug])).rows[0];
        // صلاحيات الدائرة لكل عضو (business.js): الإحصاءات بمفتاحها؛ وإن غابت الإضافة فالمالك وحده
        const P = globalThis.naslifeBizPerms;
        if (!b) allowed = false;
        else if (b.owner_id === uid) allowed = true;
        else if (P?.memberOf) { const m = await P.memberOf(uid, { id: slug, owner_id: b.owner_id }); allowed = !!m && m.perms?.has?.("stats") === true; }
        else allowed = false;
      } catch { allowed = false; }
    }
    if (!allowed) return bad(reply, 403, "forbidden");
    // أي أحد يضع زر دائرة على لحظته، فصاحب الدائرة ليس بالضرورة ممن يرونها: لحظة لا تفتحها له قاعدة الرؤية (جمهور «الأصدقاء» أو ملف
    // خاص) تبقى في المجاميع بلا نصها ولا صاحبها، وإلا قرأ هنا ما يرده عنه GET /mapposts/:id بـ404
    const posts = (await pool.query(`SELECT *, ${momentVisibleSql("map_posts", "$2::text")} AS visible FROM map_posts WHERE cta->>'type'='biz' AND cta->>'value'=$1 AND created_at > now() - interval '90 days' ORDER BY created_at DESC LIMIT 200`, [slug, uid])).rows;
    const ids = posts.map((p) => p.id);
    const agg = await series(ids, days); const per = await perPost(ids, days);
    const brief = (p) => (admin || p.visible === true ? { ...postBrief(p), author: p.user_id } : { ...postBrief(p), title: "منشور خاص", author: null });
    return { days, posts: posts.length, ...agg, byPost: posts.map((p) => ({ ...brief(p), ...per.get(p.id) })) };
  });
  app.get("/mapposts/:id/stats", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const p = (await pool.query("SELECT * FROM map_posts WHERE id=$1", [req.params.id])).rows[0];
    if (!p) return bad(reply, 404, "not-found");
    if (p.user_id !== uid && !(await isAdmin(uid))) return bad(reply, 403, "forbidden");
    const days = daysOf(req.query?.days);
    const agg = await series([p.id], days);
    const likes = (await pool.query("SELECT count(*)::int AS n FROM map_post_likes WHERE post_id=$1", [p.id])).rows[0].n;
    return { days, post: postBrief(p), ...agg, likesTotal: likes, viewsTotal: Number(p.views ?? 0) };
  });

  app.post("/mapposts/:id/block", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!(await isAdmin(uid))) return bad(reply, 403, "admin-only");
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const hidden = req.body?.hidden !== false;
    const r = await pool.query("UPDATE map_posts SET status=$2, updated_at=now() WHERE id=$1 RETURNING user_id, title", [req.params.id, hidden ? "blocked" : "active"]);
    if (!r.rowCount) return bad(reply, 404, "not-found");
    globalThis.naslifeLive?.emit(hidden ? "post_removed" : "post_restored", { id: req.params.id });
    if (hidden) await notify(r.rows[0].user_id, { kind: "post_blocked", title: "أُخفي منشورك", body: "أخفت الإدارة منشورك من الخريطة لمخالفته قواعد المجتمع", data: { postId: req.params.id }, exclude: uid });
    return { ok: true, status: hidden ? "blocked" : "active" };
  });

  // تنظيف دوري: حذف ما انتهت مدته منذ أكثر من 30 يوماً، إلا لحظة نشطة حفظها أحد في «محفوظاتي» (wishlist_items بالنوع post) فتبقى
  // حتى يزيلها من حفظها. المخفية والمحجوبة لا يحميها الحفظ: قرار صاحبها أو الإدارة يسبق الحفظ، فتُكنس كغيرها.
  // جدول الأمنيات قد لا يوجد (wishlist.js تُسجَّل بعدنا)، فيُفحص وجوده عند كل كنس.
  const sweep = async () => {
    try {
      const saved = (await pool.query("SELECT to_regclass('wishlist_items') IS NOT NULL AS ok")).rows[0]?.ok === true;
      const keep = saved ? " AND NOT (p.status='active' AND EXISTS (SELECT 1 FROM wishlist_items w WHERE w.kind='post' AND lower(w.ref_id) = p.id::text))" : "";
      return (await pool.query(`DELETE FROM map_posts p WHERE p.expires_at < now() - interval '30 days'${keep}`)).rowCount;
    } catch { return 0; }
  };
  globalThis.naslifeMapPostsSweep = sweep;
  const timer = setInterval(sweep, 6 * 3600 * 1000); timer.unref?.();
  app.addHook("onClose", async () => clearInterval(timer));
}
