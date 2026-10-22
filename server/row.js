// «الصف» (server/row.js): بث واحد لما حولك الآن — لحظات الخريطة، عروض الدوائر، الفعاليات، الوظائف، إعلانات السوق — مرتّباً بالقرب،
// يعرضه التطبيق بطاقةً واحدة مضغوطة فوق الخريطة يتصفحها المستخدم جانبياً (نظام «واحد»، قرار المالك 1 أكتوبر 2026).
// قراءة فقط من جداول الإضافات الأخرى وبلا جداول خاصة: كل مصدر مغلّف بـ try/catch، فجدول غائب أو عمود مفقود يعني أن نوعه لا يساهم
// بشيء ولا يُسقط الطلب. الدرجة = المسافة بالكيلومتر ناقص دفعات (ينتهي خلال 3 ساعات، نُشر خلال 30 دقيقة، فعالية تبدأ خلال 6 ساعات)،
// ثم توزيع حتى لا تتوالى أكثر من ثلاث بطاقات من نوع واحد، وبحد 12 لكل نوع. المسار عام: الضيف مسموح كما في /offers/near.
// النوع السادس «circle» (21 أكتوبر 2026): دائرة متنقلة ثبّتت دبوس «هنا اليوم» (biz.here من biz_onboard.js) تظهر عند موقع الدبوس ما دام قائماً.
// «التغذية» GET /feed (22 أكتوبر 2026): البطاقات نفسها بالبنّاء نفسه لكن الأحدث نشراً أولاً (لا بالقرب ولا بالتوزيع) مع تصفية بالنوع ومؤشر ترقيم before،
// لتبويب عمودي من بطاقات متوسطة متحركة، التصنيف «عام» افتراضياً وبقية التصانيف في الشريط العلوي (طلب المالك). الترتيب بزمن النشر feedAt
// (حقل إضافي؛ «at» يبقى كما في /row) والمؤشر مركّب معتم «feedAt~رقم النوع~المعرّف» فلا تسقط بطاقات تتشارك الملي ثانية.
// التسجيل في register.txt:
//   await app.register((await import("./row.js")).default, { pool, auth });
import { CATEGORY_AR } from "./business.js";

export const KINDS = ["moment", "offer", "event", "job", "listing", "circle"];
// فعل البطاقة الوحيد لكل نوع: يفتح رحلة الشاشة القائمة (المشاهد، عروض الدائرة، الفعالية، الوظيفة، الإعلان، صفحة الدائرة)
export const ACT = { moment: "شاهد", offer: "استخدم", event: "تذكرة", job: "قدّم", listing: "اطلب", circle: "زيارة" };
// عنوان احتياطي للحظة بلا تعليق: «صورة من الروضة» أو «فيديو من amr»
const MEDIA_AR = { image: "صورة", video: "فيديو", audio: "تسجيل صوتي", text: "لحظة" };
const TABLES = { moment: "map_posts", offer: "biz_offers", event: "events", job: "jobs", listing: "market_listings", circle: "biz" };
const TYPE_AR = { full: "دوام كامل", part: "دوام جزئي", remote: "عن بُعد", intern: "تدريب", shift: "ورديات", freelance: "عمل حر" };
export const CAND = 60, MAX_PER_KIND = 12, MAX_RUN = 3, LIMIT_DEFAULT = 30, LIMIT_MAX = 50, RADIUS_DEFAULT = 15, RADIUS_MAX = 100;
export const FEED_LIMIT_MAX = 40; // صفحة التغذية: 1..40 (الافتراضي LIMIT_DEFAULT)
const MIN = 60000, H = 3600000, DAY = 86400000, TZ = "Asia/Riyadh";

const num = (v) => { if (v == null || v === "") return null; const n = Number(v); return Number.isFinite(n) ? n : null; };
const clampInt = (v, lo, hi, d) => { const n = Math.round(Number(v)); return Number.isFinite(n) ? Math.min(hi, Math.max(lo, n)) : d; };
const iso = (d) => { const t = ms(d); return Number.isFinite(t) ? new Date(t).toISOString() : null; };
const ms = (d) => (d == null ? NaN : new Date(d).getTime());
const round1 = (v) => (v == null || !Number.isFinite(Number(v)) ? null : Math.round(Number(v) * 10) / 10);
// سطر واحد مقصوص بحد n حرفاً (العنوان ≤ 80 والسطر الثاني ≤ 60 كما في العقد)
const cut = (s, n) => { const t = String(s ?? "").replace(/\s+/g, " ").trim(); return t.length > n ? t.slice(0, n - 1).trimEnd() + "…" : t; };
const sar = (h) => { const v = Number(h) / 100; return (Number.isInteger(v) ? v.toLocaleString("en-US") : v.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })) + " ر.س"; };
const first = (a) => (Array.isArray(a) ? a.find((u) => typeof u === "string" && u) ?? null : null);

// ---- نصوص الوقت بتوقيت الرياض (الأرقام لاتينية؛ التطبيق يعرّبها إن شاء)
const dayKey = (t) => new Intl.DateTimeFormat("en-CA", { timeZone: TZ, year: "numeric", month: "2-digit", day: "2-digit" }).format(t);
const WEEKDAY_AR = { Sunday: "الأحد", Monday: "الاثنين", Tuesday: "الثلاثاء", Wednesday: "الأربعاء", Thursday: "الخميس", Friday: "الجمعة", Saturday: "السبت" };
const weekday = (t) => WEEKDAY_AR[new Intl.DateTimeFormat("en-US", { timeZone: TZ, weekday: "long" }).format(t)] ?? "";
const clock = (t) => {
  const p = Object.fromEntries(new Intl.DateTimeFormat("en-US", { timeZone: TZ, hour: "numeric", minute: "2-digit", hour12: true }).formatToParts(t).map((x) => [x.type, x.value]));
  return `${p.hour}${p.minute === "00" ? "" : ":" + p.minute} ${p.dayPeriod === "AM" ? "ص" : "م"}`;
};
const daysText = (n) => (n === 1 ? "يوم" : n === 2 ? "يومين" : n <= 10 ? `${n} أيام` : `${n} يوماً`);
// ساعة بصيغة HH:MM بتوقيت الرياض (لدبوس «هنا اليوم حتى 17:30»)
export const hhmm = (t) => { const d = ms(t); return Number.isFinite(d) ? new Intl.DateTimeFormat("en-GB", { timeZone: TZ, hour: "2-digit", minute: "2-digit", hour12: false }).format(d) : ""; };
// موعد الفعالية: «اليوم 5 م» / «غداً 5 م» / «الجمعة 5 م» / «12/10 5 م»
export const whenText = (t, now = Date.now()) => {
  const d = ms(t); if (!Number.isFinite(d)) return "";
  const k = dayKey(d);
  const day = k === dayKey(now) ? "اليوم" : k === dayKey(now + DAY) ? "غداً" : d - now < 6 * DAY && d > now ? weekday(d) : k.slice(5).split("-").reverse().join("/");
  return `${day} ${clock(d)}`;
};
// نهاية العرض: «ينتهي خلال ساعة» / «ينتهي خلال 3 س» / «ينتهي الليلة» / «ينتهي غداً» / «ينتهي بعد 4 أيام» / «عرض مستمر»
export const endsText = (t, now = Date.now()) => {
  const d = ms(t); if (!Number.isFinite(d)) return "عرض مستمر";
  const left = d - now;
  if (left <= 0) return "انتهى";
  if (left <= H) return "ينتهي خلال ساعة";
  if (left <= 6 * H) return `ينتهي خلال ${Math.ceil(left / H)} س`;
  const k = dayKey(d);
  if (k === dayKey(now)) return "ينتهي الليلة";
  if (k === dayKey(now + DAY)) return "ينتهي غداً";
  return `ينتهي بعد ${daysText(Math.ceil(left / DAY))}`;
};
// منذ النشر: «الآن» / «قبل 12 د» / «قبل 3 س» / «قبل يومين»
export const agoText = (t, now = Date.now()) => {
  const d = now - ms(t);
  if (!Number.isFinite(d) || d < MIN) return "الآن";
  if (d < H) return `قبل ${Math.floor(d / MIN)} د`;
  if (d < DAY) return `قبل ${Math.floor(d / H)} س`;
  return `قبل ${daysText(Math.floor(d / DAY))}`;
};
const likesText = (n) => (n === 1 ? "إعجاب واحد" : n === 2 ? "إعجابان" : n <= 10 ? `${n} إعجابات` : `${n} إعجاباً`);

// ---- الترتيب: درجة أقل = أبكر. المسافة بالكيلومتر (صفر بلا موقع) ناقص دفعات الإلحاح والطزاجة
export function scoreOf(it, now = Date.now()) {
  const km = it.distanceKm != null && Number.isFinite(Number(it.distanceKm)) ? Number(it.distanceKm) : 0;
  const ends = ms(it.endsAt), at = ms(it.at);
  let s = km;
  if (Number.isFinite(ends) && ends > now && ends - now <= 3 * H) s -= 2; // ينتهي خلال 3 ساعات: فرصة تفوت
  if (Number.isFinite(at) && at <= now && now - at <= 30 * MIN) s -= 1.5; // نُشر للتو: الطازج أولاً
  if (it.kind === "event" && Number.isFinite(at) && at > now && at - now <= 6 * H) s -= 1; // فعالية تبدأ قريباً
  return s;
}

// توزيع مستقر: لا أكثر من maxRun بطاقات متتالية من نوع واحد؛ حين تتكرر الرابعة يُسحب أول عنصر من نوع آخر إلى الأمام،
// وإن لم يبقَ نوع آخر فالتكرار يستمر (لا شيء نضيفه)
export function interleave(list, maxRun = MAX_RUN) {
  const rest = [...list], out = []; let run = 0;
  while (rest.length) {
    const last = out.length ? out[out.length - 1].kind : null;
    let idx = 0;
    if (run >= maxRun && rest[0].kind === last) { const j = rest.findIndex((x) => x.kind !== last); if (j > 0) idx = j; }
    const [it] = rest.splice(idx, 1);
    run = it.kind === last ? run + 1 : 1;
    out.push(it);
  }
  return out;
}

// الدرجة تصاعدياً (ثم الأحدث ثم ترتيب الورود)، حد 12 لكل نوع، التوزيع، ثم الحد
export function rankItems(items, limit = LIMIT_DEFAULT, now = Date.now()) {
  const scored = items.map((it, i) => ({ it, s: scoreOf(it, now), at: Number.isFinite(ms(it.at)) ? ms(it.at) : 0, i })).sort((a, b) => a.s - b.s || b.at - a.at || a.i - b.i);
  const perKind = {}, pool = [];
  for (const { it } of scored) { const n = perKind[it.kind] ?? 0; if (n >= MAX_PER_KIND) continue; perKind[it.kind] = n + 1; pool.push(it); }
  return interleave(pool).slice(0, limit);
}

// ---- مسافة هافرساين بالكيلومتر داخل SQL كما في offers.js؛ $1 lat و$2 lng و$3 نصف القطر (صفر = بلا موقع فلا تصفية ولا مسافة)
const dist = (a) => `(6371*acos(least(1, cos(radians($1::float8))*cos(radians(${a}.lat))*cos(radians(${a}.lng)-radians($2::float8))+sin(radians($1::float8))*sin(radians(${a}.lat)))))`;
const KM = (a) => `CASE WHEN $3::float8 > 0 THEN ${dist(a)} END`;
const WITHIN = (a) => `($3::float8 <= 0 OR ${dist(a)} <= $3::float8)`;
const ACTIVE_OFFER = "o.active AND b.active AND o.starts_at <= now() AND (o.ends_at IS NULL OR o.ends_at > now())";
// ---- التغذية: زمن النشر لكل نوع (feedAt) به تُرتَّب وتُرقَّم، منفصلاً عن «at» الذي يبقى كما يبنيه /row (موعد الفعالية مثلاً)، لأن التغذية «ما الجديد»:
// فعالية بعد شهر لا تتصدر. العرض المجدول يُعدّ منشوراً حين يبدأ (الأحدث من إنشائه وبدايته)، والدائرة بلا setAt تأخذ آخر تحديث لها (يُكتب مع الدبوس)
const FEED_TIME = { moment: "p.created_at", offer: "GREATEST(o.created_at, o.starts_at)", event: "e.created_at", job: "COALESCE(j.published_at, j.created_at)", listing: "COALESCE(l.bumped_at, l.created_at)", circle: "COALESCE(c.set_at::timestamptz, c.updated_at)" };
const FEED_ID = { moment: "p.id", offer: "o.id", event: "e.id", job: "j.id", listing: "l.id", circle: "c.id" };
// المعرّف نصاً بترتيب نقاط الترميز: COLLATE "C" يقارن بايتات UTF-8 كما يفعل byteCmp في JS، فلا يختلف فضّ التعادل بين القاعدة والدمج
const idText = (kind) => `${FEED_ID[kind]}::text COLLATE "C"`;
export const byteCmp = (a, b) => Buffer.compare(Buffer.from(String(a)), Buffer.from(String(b)));
// عمود feed_ms (التغذية فقط): زمن النشر بالملي ثانية مقصوصاً من القاعدة نفسها، فيطابق شريط [C, C+1ms) في الشرط تماماً بلا تقريب عشري في JS
const feedMs = (ctx, kind) => (ctx.sort === "time" ? `, floor(extract(epoch FROM ${FEED_TIME[kind]}) * 1000)::bigint AS feed_ms` : "");
// ذيل الاستعلام ومعاملاته: /row الأقرب أولاً بحد CAND كما كان. التغذية (ctx.sort = "time"): الأحدث أولاً بالعمود الخام (يصلح له الفهرس) ثم المعرّف،
// والمؤشر المركّب {at, k, id} يُقارن بالعمود الخام مع شريط ملي ثانية للتعادل (لا date_trunc ولا دوال على العمود): نوع بعد نوع المؤشر يأخذ شريط at كله،
// ونوع قبله لا يأخذ منه شيئاً، ونوع المؤشر يأخذ منه ما معرّفه بعد معرّف المؤشر. ctx.band = جلب شريط ملي ثانية واحد بترتيب المعرّف (انظر sourceRows)
const tail = (ctx, kind, params, rowOrder) => {
  if (ctx.sort !== "time") return [`ORDER BY km ASC NULLS LAST, ${rowOrder} LIMIT ${CAND}`, params];
  const t = FEED_TIME[kind], id = idText(kind), P = [...params], w = [];
  const arg = (v) => { P.push(v); return `$${P.length}`; };
  const c = ctx.cursor;
  if (c) {
    const at = arg(c.at), ki = KINDS.indexOf(kind);
    w.push(ki < c.k ? `${t} < ${at}::timestamptz` : `${t} < ${at}::timestamptz + interval '1 millisecond'`);
    if (ki === c.k) w.push(`(${t} < ${at}::timestamptz OR ${id} > ${arg(c.id)})`);
  }
  if (ctx.band) { const b = arg(ctx.band); w.push(`${t} >= ${b}::timestamptz AND ${t} < ${b}::timestamptz + interval '1 millisecond'`); }
  return [`${w.map((x) => `AND ${x} `).join("")}ORDER BY ${ctx.band ? "" : `${t} DESC, `}${id} LIMIT ${ctx.cand}`, P];
};
// المؤشر المعتم «<feedAt ISO>~<رقم النوع في KINDS>~<المعرّف>». ISO وحده (عملاء أقدم) = أقدم من ذلك الزمن تماماً: k = عدد الأنواع فلا يُؤخذ شيء من شريطه.
// قيمة غير مفهومة = بلا مؤشر (من الأول) كما كان
export const parseCursor = (s) => {
  if (typeof s !== "string" || !s || s.length > 300) return null;
  const i = s.indexOf("~");
  if (i < 0) { const at = iso(s); return at ? { at, k: KINDS.length, id: "" } : null; }
  const j = s.indexOf("~", i + 1);
  if (j < 0) return null;
  const at = iso(s.slice(0, i)), k = s.slice(i + 1, j), id = s.slice(j + 1);
  return at && /^\d{1,2}$/.test(k) && Number(k) < KINDS.length && id ? { at, k: Number(k), id } : null;
};
// ترتيب التغذية الواحد (القاعدة والدمج والمؤشر): زمن النشر بالملي ثانية تنازلياً، ثم ترتيب النوع، ثم المعرّف بنقاط الترميز
export const feedCmp = (a, b) => b.ms - a.ms || a.k - b.k || byteCmp(a.id, b.id);
export const cursorOf = (e) => `${new Date(e.ms).toISOString()}~${e.k}~${e.id}`;

export default async function row(app, opts = {}) {
  const pool = opts.pool ?? globalThis.naslifePool ?? null;
  const auth = opts.auth ?? globalThis.naslifeAuth ?? null;
  if (!pool || !auth) throw new Error("row: pool and auth are required");

  const optionalAuth = async (req) => { try { return (await auth(req)) || null; } catch { return null; } };
  const blockedIds = async (uid) => { try { return uid ? (await globalThis.naslifeBlockedIds?.(uid)) ?? [] : []; } catch { return []; } };
  const exists = async (t) => { try { return (await pool.query("SELECT to_regclass($1) IS NOT NULL AS ok", [t])).rows[0]?.ok === true; } catch { return false; } };
  // استعلام مصدر: أي خطأ (جدول غائب، عمود مفقود) يعني أن هذا النوع لا يساهم في هذا الطلب
  const q = async (kind, sql, params) => { try { return (await pool.query(sql, params)).rows; } catch (e) { app.log?.debug?.({ err: e.message, kind }, "row: source skipped"); return []; } };
  // أسماء الأشخاص دفعة واحدة (ناشر اللحظة، مضيف الفعالية، بائع الإعلان)؛ جدول المستخدمين من النواة وغيابه لا يُسقط الصف
  const persons = async (ids) => {
    const out = new Map(), list = [...new Set(ids.filter(Boolean))];
    if (list.length) { try { for (const u of (await pool.query("SELECT id, nickname, avatar_url FROM users WHERE id = ANY($1::text[])", [list])).rows) out.set(u.id, { id: u.id, nickname: u.nickname ?? "", avatarUrl: u.avatar_url ?? null }); } catch { /* بلا أسماء */ } }
    for (const id of list) if (!out.has(id)) out.set(id, { id, nickname: "", avatarUrl: null });
    return out;
  };
  const bizName = (r) => r.name_ar || r.name || "";
  // شرط الضيف على الفعاليات من commerce.js (عمود خصوصية الدوائر يُكتشف هناك)؛ إن غابت الإضافة نُخفي فعاليات الدوائر كلها عن الضيف احتياطاً
  const guestEvents = async () => { try { const f = globalThis.naslifeGuestEventsSql; return typeof f === "function" ? String(await f(null, "e")) : " AND e.vessel_id IS NULL"; } catch { return " AND e.vessel_id IS NULL"; } };
  const place = (ctx, r, km) => ({ lat: Number(r.lat), lng: Number(r.lng), distanceKm: ctx.located ? round1(km) : null });

  // الحمولة = شكل المنشور كما يعيده GET /mapposts تماماً (ليفتح التطبيق المشاهد بلا طلب آخر)
  const postOut = (p, uid, user) => ({
    id: p.id, user, kind: p.kind, mediaUrl: p.media_url, caption: p.caption, bg: p.bg, overlays: p.overlays ?? [], tag: p.tag, title: p.title,
    price: p.price == null ? null : Number(p.price), cta: p.cta ?? null, lat: p.lat, lng: p.lng, placeName: p.place_name, durationSec: p.duration_sec, status: p.status,
    views: Number(p.views ?? 0), likes: Number(p.likes ?? 0), liked: p.liked === true, mine: p.user_id === uid, expiresAt: p.expires_at, createdAt: p.created_at,
    expired: new Date(p.expires_at).getTime() < Date.now(), audioUrl: p.audio_url ?? null, audioSec: p.audio_sec ?? null,
  });

  // ---- المصادر الستة: استعلام مرشّحين (الصف: بحد CAND الأقرب أولاً ثم الأحدث؛ التغذية: الأحدث أولاً بحد الصفحة) ثم تحويل الصف إلى بطاقة
  const SOURCES = {
    moment: {
      rows: (ctx) => { const [t, P] = tail(ctx, "moment", [...ctx.geo, ctx.uid, ctx.blocked], "p.created_at DESC"); return q("moment", `SELECT p.*, (SELECT count(*) FROM map_post_likes l WHERE l.post_id=p.id)::int AS likes,
          ($4::text IS NOT NULL AND EXISTS (SELECT 1 FROM map_post_likes l WHERE l.post_id=p.id AND l.user_id=$4)) AS liked, ${KM("p")} AS km${feedMs(ctx, "moment")}
        FROM map_posts p WHERE p.status='active' AND p.expires_at > now() AND NOT (p.user_id = ANY($5::text[])) AND ${WITHIN("p")} ${t}`, P); },
      userId: (p) => p.user_id,
      item: (p, ctx, who) => ({
        kind: "moment", id: p.id, refId: p.id,
        title: cut(p.caption, 60) || cut(p.title, 60) || `${MEDIA_AR[p.kind] ?? "لحظة"} من ${p.place_name ? cut(p.place_name, 40) : who.nickname || "جار قريب"}`,
        subtitle: cut([agoText(p.created_at, ctx.now), Number(p.likes) > 0 ? likesText(Number(p.likes)) : p.place_name].filter(Boolean).join(" · "), 60),
        who: who.nickname, logoUrl: who.avatarUrl, imageUrl: p.kind === "image" || p.kind === "video" ? p.media_url ?? null : null,
        ...place(ctx, p, p.km), at: iso(p.created_at), endsAt: iso(p.expires_at), act: ACT.moment, payload: postOut(p, ctx.uid, who),
      }),
    },
    offer: {
      rows: (ctx) => { const [t, P] = tail(ctx, "offer", ctx.geo, "o.starts_at DESC"); return q("offer", `SELECT o.*, b.id AS b_id, b.name, b.name_ar, b.logo_url, b.lat, b.lng, ${KM("b")} AS km${feedMs(ctx, "offer")}
        FROM biz_offers o JOIN biz b ON b.id=o.biz_id WHERE ${ACTIVE_OFFER} AND ${WITHIN("b")} ${t}`, P); },
      userId: () => null,
      item: (o, ctx) => ({
        kind: "offer", id: o.id, refId: o.b_id, title: cut(o.title, 80), subtitle: cut(`${bizName(o)} · ${endsText(o.ends_at, ctx.now)}`, 60),
        who: bizName(o), logoUrl: o.logo_url ?? null, imageUrl: o.logo_url ?? null,
        ...place(ctx, o, o.km), at: iso(o.starts_at), endsAt: iso(o.ends_at), act: ACT.offer, payload: {},
      }),
    },
    event: {
      // الفعاليات الملغاة أو المخفية بالإشراف لا تُعرض (كما في GET /events)؛ الجارية تبقى حتى نهايتها أو 6 ساعات بعد بدايتها.
      // والضيف لا يرى فعاليات الدوائر الخاصة بقاعدة GET /events نفسها (guestEvents)
      rows: async (ctx) => { const [t, P] = tail(ctx, "event", [...ctx.geo, ctx.blocked], "e.starts_at ASC"); const g = ctx.uid ? "" : await guestEvents(); return q("event", `SELECT e.*, (SELECT min(t.price) FROM ticket_tiers t WHERE t.event_id=e.id) AS min_price, ${KM("e")} AS km${feedMs(ctx, "event")}
        FROM events e WHERE NOT e.cancelled AND NOT e.hidden AND e.lat IS NOT NULL AND e.lng IS NOT NULL AND NOT (e.host_id = ANY($4::text[]))
          AND ((e.ends_at IS NULL AND e.starts_at > now() - interval '6 hours') OR e.ends_at > now())${g} AND ${WITHIN("e")} ${t}`, P); },
      userId: (e) => e.host_id,
      item: (e, ctx, who) => ({
        kind: "event", id: e.id, refId: e.id, title: cut(e.title, 80),
        subtitle: cut([e.place_name || who.nickname, whenText(e.starts_at, ctx.now), e.min_price == null ? null : Number(e.min_price) === 0 ? "مجاناً" : `من ${sar(e.min_price)}`].filter(Boolean).join(" · "), 60),
        who: who.nickname, logoUrl: who.avatarUrl, imageUrl: null,
        ...place(ctx, e, e.km), at: iso(e.starts_at), endsAt: iso(e.ends_at), act: ACT.event, payload: {},
      }),
    },
    job: {
      // وظائف دائرة موقوفة أو مخفية بالإشراف لا تظهر (كما تختفي الدائرة نفسها)
      rows: (ctx) => { const [t, P] = tail(ctx, "job", ctx.geo, "j.published_at DESC NULLS LAST"); return q("job", `SELECT j.id, j.title, j.type, j.city, j.district, j.salary_min, j.salary_max, j.salary_visible, j.published_at, j.created_at, j.deadline,
          b.id AS b_id, b.name, b.name_ar, b.logo_url, b.lat, b.lng, ${KM("b")} AS km${feedMs(ctx, "job")}
        FROM jobs j JOIN biz b ON b.id=j.biz_id WHERE j.status='open' AND j.public=true AND b.active AND NOT b.hidden AND ${WITHIN("b")} ${t}`, P); },
      userId: () => null,
      item: (j, ctx) => {
        // الراتب يظهر فقط حين أذن صاحب العمل (كما في publicJobOut)؛ وإلا الحي أو المدينة أو اسم الدائرة
        const salary = j.salary_visible && (j.salary_min || j.salary_max)
          ? (j.salary_min && j.salary_max && j.salary_min !== j.salary_max ? `${Number(j.salary_min).toLocaleString("en-US")}–${Number(j.salary_max).toLocaleString("en-US")}` : Number(j.salary_max || j.salary_min).toLocaleString("en-US")) + " ر.س"
          : (j.district || j.city || bizName(j));
        return {
          kind: "job", id: j.id, refId: j.b_id, title: cut(j.title, 80), subtitle: cut(`${TYPE_AR[j.type] ?? j.type ?? ""} · ${salary}`, 60),
          who: bizName(j), logoUrl: j.logo_url ?? null, imageUrl: null,
          ...place(ctx, j, j.km), at: iso(j.published_at ?? j.created_at), endsAt: iso(j.deadline), act: ACT.job, payload: {},
        };
      },
    },
    listing: {
      rows: (ctx) => { const [t, P] = tail(ctx, "listing", [...ctx.geo, ctx.blocked], "COALESCE(l.bumped_at, l.created_at) DESC"); return q("listing", `SELECT l.id, l.seller_id, l.title, l.price, l.image_url, l.images, l.place_name, l.city, l.lat, l.lng, l.created_at, l.bumped_at, ${KM("l")} AS km${feedMs(ctx, "listing")}
        FROM market_listings l WHERE l.status='active' AND l.lat IS NOT NULL AND l.lng IS NOT NULL AND (l.publish_at IS NULL OR l.publish_at <= now())
          AND NOT (l.seller_id = ANY($4::text[])) AND ${WITHIN("l")} ${t}`, P); },
      userId: (l) => l.seller_id,
      item: (l, ctx, who) => ({
        kind: "listing", id: l.id, refId: l.id, title: cut(l.title, 80), subtitle: cut(`${sar(l.price)} · ${l.place_name || l.city || who.nickname}`, 60),
        who: who.nickname, logoUrl: who.avatarUrl, imageUrl: first(l.images) ?? l.image_url ?? null,
        ...place(ctx, l, l.km), at: iso(l.bumped_at ?? l.created_at), endsAt: null, act: ACT.listing, payload: {},
      }),
    },
    circle: {
      // الدائرة المتنقلة التي ثبّتت دبوس «هنا اليوم»: تُعرض عند موقع الدبوس ما دام until في المستقبل (business.js يملك العمود here)
      rows: (ctx) => { const [t, P] = tail(ctx, "circle", ctx.geo, "c.set_at DESC NULLS LAST"); return q("circle", `SELECT c.*, ${KM("c")} AS km${feedMs(ctx, "circle")} FROM (
          SELECT b.id, b.name, b.name_ar, b.category, b.logo_url, (b.here->>'lat')::float8 AS lat, (b.here->>'lng')::float8 AS lng, b.here->>'until' AS until, b.here->>'setAt' AS set_at, b.updated_at
          FROM biz b WHERE b.active AND NOT b.hidden AND b.here IS NOT NULL AND jsonb_typeof(b.here->'until')='string' AND (b.here->>'until')::timestamptz > now()) c
        WHERE c.lat IS NOT NULL AND c.lng IS NOT NULL AND ${WITHIN("c")} ${t}`, P); },
      userId: () => null,
      item: (c, ctx) => ({
        kind: "circle", id: c.id, refId: c.id, title: cut(bizName(c), 80), subtitle: cut(`هنا اليوم حتى ${hhmm(c.until)} · ${CATEGORY_AR[c.category] ?? c.category ?? ""}`, 60),
        who: bizName(c), logoUrl: c.logo_url ?? null, imageUrl: c.logo_url ?? null,
        ...place(ctx, c, c.km), at: iso(c.set_at) ?? iso(ctx.now), endsAt: iso(c.until), act: ACT.circle, cta: ACT.circle, payload: { here: true, until: iso(c.until) },
      }),
    },
  };

  // صفوف مصدر واحد. التغذية: القاعدة ترتّب بالعمود الخام (بالميكروثانية) والصفحة ترتّب بالملي ثانية ثم المعرّف، ويختلفان داخل آخر ملي ثانية جُلبت فقط؛
  // فإن امتلأ الحد يُجلب شريط تلك الملي ثانية بترتيب المعرّف حتى لا تسقط بطاقة تشاركها الزمن ولا تُسبق بمن بعدها
  const sourceRows = async (k, ctx) => {
    const rows = await SOURCES[k].rows(ctx);
    if (ctx.sort !== "time" || rows.length < ctx.cand) return rows;
    const band = await SOURCES[k].rows({ ...ctx, band: new Date(Number(rows[rows.length - 1].feed_ms)).toISOString() });
    const seen = new Set(rows.map((r) => String(r.id)));
    return [...rows, ...band.filter((r) => !seen.has(String(r.id)))];
  };
  // جمع البطاقات من الأنواع المطلوبة: استعلامات المصادر معاً، ثم أسماء الأشخاص دفعة واحدة، ثم التحويل إلى بطاقات (مشترك بين /row و/feed).
  // كل عنصر { card, ms, k, id }: ms/k/id مفتاح ترتيب التغذية (ms = زمن النشر من القاعدة) ولا يدخل البطاقة
  const collect = async (kinds, ctx) => {
    const batches = await Promise.all(kinds.map(async (k) => ({ k, rows: await sourceRows(k, ctx) })));
    const people = await persons(batches.flatMap(({ k, rows }) => rows.map(SOURCES[k].userId)));
    return batches.flatMap(({ k, rows }) => rows.map((r) => ({
      card: SOURCES[k].item(r, ctx, people.get(SOURCES[k].userId(r)) ?? { id: "", nickname: "", avatarUrl: null }),
      ms: Number(r.feed_ms ?? 0), k: KINDS.indexOf(k), id: String(r.id),
    })));
  };
  // الموقع ونصف القطر من الاستعلام كما في /offers/near؛ الإحداثيات خارج النطاق = بلا موقع
  const geoOf = (query) => {
    const lat = num(query?.lat), lng = num(query?.lng);
    const located = lat != null && lng != null && Math.abs(lat) <= 90 && Math.abs(lng) <= 180;
    return { located, geo: located ? [lat, lng, clampInt(query?.radiusKm, 1, RADIUS_MAX, RADIUS_DEFAULT)] : [0, 0, 0] };
  };

  // ---- GET /row?lat=&lng=&radiusKm=15&limit=30 → { items, located }؛ بلا موقع: الأحدث بلا مسافة
  app.get("/row", async (req) => {
    const uid = await optionalAuth(req);
    const { located, geo } = geoOf(req.query);
    const limit = clampInt(req.query?.limit, 1, LIMIT_MAX, LIMIT_DEFAULT);
    const ctx = { geo, uid, blocked: await blockedIds(uid), now: Date.now(), located };
    return { items: rankItems((await collect(KINDS, ctx)).map((e) => e.card), limit, ctx.now), located };
  });

  // ---- GET /feed?kind=all|moment|offer|event|job|listing|circle&lat=&lng=&radiusKm=15&limit=30&before=<next> → { items, next, located }
  // التغذية العمودية: البطاقات نفسها (البنّاء نفسه، واللحظة تحمل المنشور في payload) وفي كل بطاقة feedAt = زمن النشر، الأحدث نشراً أولاً،
  // بلا دفعات ولا حد لكل نوع ولا توزيع؛ الموقع يقصر على نصف القطر ويملأ المسافة فقط، وبلا موقع الأحدث أياً كان بعده.
  // kind واحد يصفّي إليه، وall (أو قيمة غير معروفة) يدمج الأنواع كلها. next = مؤشر آخر بطاقة «feedAt~k~id» حين تمتلئ الصفحة وإلا null،
  // ويُعاد في before كما هو؛ ISO وحده (عملاء أقدم) = البطاقات التي feedAt < before.
  app.get("/feed", async (req) => {
    const uid = await optionalAuth(req);
    const { located, geo } = geoOf(req.query);
    const limit = clampInt(req.query?.limit, 1, FEED_LIMIT_MAX, LIMIT_DEFAULT);
    const kinds = KINDS.includes(req.query?.kind) ? [req.query.kind] : KINDS;
    const ctx = { geo, uid, blocked: await blockedIds(uid), now: Date.now(), located, sort: "time", cursor: parseCursor(req.query?.before), cand: limit };
    const page = (await collect(kinds, ctx)).sort(feedCmp).slice(0, limit);
    return { items: page.map((e) => ({ ...e.card, feedAt: new Date(e.ms).toISOString() })), next: page.length === limit ? cursorOf(page[page.length - 1]) : null, located };
  });

  // ---- للفحص الحي: أي الجداول المصدرية موجودة
  app.get("/row/status", async () => {
    const sources = {};
    for (const k of KINDS) sources[k] = await exists(TABLES[k]);
    return { ok: true, sources };
  });
}
