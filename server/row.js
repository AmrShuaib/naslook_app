// «الصف» (server/row.js): بث واحد لما حولك الآن — لحظات الخريطة، عروض الدوائر، الفعاليات، الوظائف، إعلانات السوق — مرتّباً بالقرب،
// يعرضه التطبيق بطاقةً واحدة مضغوطة فوق الخريطة يتصفحها المستخدم جانبياً (نظام «واحد»، قرار المالك 1 أكتوبر 2026).
// قراءة فقط من جداول الإضافات الأخرى وبلا جداول خاصة: كل مصدر مغلّف بـ try/catch، فجدول غائب أو عمود مفقود يعني أن نوعه لا يساهم
// بشيء ولا يُسقط الطلب. الدرجة = المسافة بالكيلومتر ناقص دفعات (ينتهي خلال 3 ساعات، نُشر خلال 30 دقيقة، فعالية تبدأ خلال 6 ساعات)،
// ثم توزيع حتى لا تتوالى أكثر من ثلاث بطاقات من نوع واحد، وبحد 12 لكل نوع. المسار عام: الضيف مسموح كما في /offers/near.
// التسجيل في register.txt:
//   await app.register((await import("./row.js")).default, { pool, auth });

export const KINDS = ["moment", "offer", "event", "job", "listing"];
// فعل البطاقة الوحيد لكل نوع: يفتح رحلة الشاشة القائمة (المشاهد، عروض الدائرة، الفعالية، الوظيفة، الإعلان)
export const ACT = { moment: "شاهد", offer: "استخدم", event: "تذكرة", job: "قدّم", listing: "اطلب" };
const TABLES = { moment: "map_posts", offer: "biz_offers", event: "events", job: "jobs", listing: "market_listings" };
const TYPE_AR = { full: "دوام كامل", part: "دوام جزئي", remote: "عن بُعد", intern: "تدريب", shift: "ورديات", freelance: "عمل حر" };
export const CAND = 60, MAX_PER_KIND = 12, MAX_RUN = 3, LIMIT_DEFAULT = 30, LIMIT_MAX = 50, RADIUS_DEFAULT = 15, RADIUS_MAX = 100;
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
  const place = (ctx, r, km) => ({ lat: Number(r.lat), lng: Number(r.lng), distanceKm: ctx.located ? round1(km) : null });

  // الحمولة = شكل المنشور كما يعيده GET /mapposts تماماً (ليفتح التطبيق المشاهد بلا طلب آخر)
  const postOut = (p, uid, user) => ({
    id: p.id, user, kind: p.kind, mediaUrl: p.media_url, caption: p.caption, bg: p.bg, overlays: p.overlays ?? [], tag: p.tag, title: p.title,
    price: p.price == null ? null : Number(p.price), cta: p.cta ?? null, lat: p.lat, lng: p.lng, placeName: p.place_name, durationSec: p.duration_sec, status: p.status,
    views: Number(p.views ?? 0), likes: Number(p.likes ?? 0), liked: p.liked === true, mine: p.user_id === uid, expiresAt: p.expires_at, createdAt: p.created_at,
    expired: new Date(p.expires_at).getTime() < Date.now(), audioUrl: p.audio_url ?? null, audioSec: p.audio_sec ?? null,
  });

  // ---- المصادر الخمسة: استعلام مرشّحين (بحد CAND، الأقرب أولاً ثم الأحدث) ثم تحويل الصف إلى بطاقة
  const SOURCES = {
    moment: {
      rows: (ctx) => q("moment", `SELECT p.*, (SELECT count(*) FROM map_post_likes l WHERE l.post_id=p.id)::int AS likes,
          ($4::text IS NOT NULL AND EXISTS (SELECT 1 FROM map_post_likes l WHERE l.post_id=p.id AND l.user_id=$4)) AS liked, ${KM("p")} AS km
        FROM map_posts p WHERE p.status='active' AND p.expires_at > now() AND NOT (p.user_id = ANY($5::text[])) AND ${WITHIN("p")}
        ORDER BY km ASC NULLS LAST, p.created_at DESC LIMIT ${CAND}`, [...ctx.geo, ctx.uid, ctx.blocked]),
      userId: (p) => p.user_id,
      item: (p, ctx, who) => ({
        kind: "moment", id: p.id, refId: p.id,
        title: cut(p.caption, 60) || cut(p.title, 60) || (p.place_name ? `لحظة من ${cut(p.place_name, 40)}` : "لحظة قريبة"),
        subtitle: cut([agoText(p.created_at, ctx.now), Number(p.likes) > 0 ? likesText(Number(p.likes)) : p.place_name].filter(Boolean).join(" · "), 60),
        who: who.nickname, logoUrl: who.avatarUrl, imageUrl: p.kind === "image" || p.kind === "video" ? p.media_url ?? null : null,
        ...place(ctx, p, p.km), at: iso(p.created_at), endsAt: iso(p.expires_at), act: ACT.moment, payload: postOut(p, ctx.uid, who),
      }),
    },
    offer: {
      rows: (ctx) => q("offer", `SELECT o.*, b.id AS b_id, b.name, b.name_ar, b.logo_url, b.lat, b.lng, ${KM("b")} AS km
        FROM biz_offers o JOIN biz b ON b.id=o.biz_id WHERE ${ACTIVE_OFFER} AND ${WITHIN("b")}
        ORDER BY km ASC NULLS LAST, o.starts_at DESC LIMIT ${CAND}`, ctx.geo),
      userId: () => null,
      item: (o, ctx) => ({
        kind: "offer", id: o.id, refId: o.b_id, title: cut(o.title, 80), subtitle: cut(`${bizName(o)} · ${endsText(o.ends_at, ctx.now)}`, 60),
        who: bizName(o), logoUrl: o.logo_url ?? null, imageUrl: o.logo_url ?? null,
        ...place(ctx, o, o.km), at: iso(o.starts_at), endsAt: iso(o.ends_at), act: ACT.offer, payload: {},
      }),
    },
    event: {
      // الفعاليات الملغاة أو المخفية بالإشراف لا تُعرض (كما في GET /events)؛ الجارية تبقى حتى نهايتها أو 6 ساعات بعد بدايتها
      rows: (ctx) => q("event", `SELECT e.*, (SELECT min(t.price) FROM ticket_tiers t WHERE t.event_id=e.id) AS min_price, ${KM("e")} AS km
        FROM events e WHERE NOT e.cancelled AND NOT e.hidden AND e.lat IS NOT NULL AND e.lng IS NOT NULL AND NOT (e.host_id = ANY($4::text[]))
          AND ((e.ends_at IS NULL AND e.starts_at > now() - interval '6 hours') OR e.ends_at > now()) AND ${WITHIN("e")}
        ORDER BY km ASC NULLS LAST, e.starts_at ASC LIMIT ${CAND}`, [...ctx.geo, ctx.blocked]),
      userId: (e) => e.host_id,
      item: (e, ctx, who) => ({
        kind: "event", id: e.id, refId: e.id, title: cut(e.title, 80),
        subtitle: cut([e.place_name || who.nickname, whenText(e.starts_at, ctx.now), e.min_price == null ? null : Number(e.min_price) === 0 ? "مجاناً" : `من ${sar(e.min_price)}`].filter(Boolean).join(" · "), 60),
        who: who.nickname, logoUrl: who.avatarUrl, imageUrl: null,
        ...place(ctx, e, e.km), at: iso(e.starts_at), endsAt: iso(e.ends_at), act: ACT.event, payload: {},
      }),
    },
    job: {
      rows: (ctx) => q("job", `SELECT j.id, j.title, j.type, j.city, j.district, j.salary_min, j.salary_max, j.salary_visible, j.published_at, j.created_at, j.deadline,
          b.id AS b_id, b.name, b.name_ar, b.logo_url, b.lat, b.lng, ${KM("b")} AS km
        FROM jobs j JOIN biz b ON b.id=j.biz_id WHERE j.status='open' AND j.public=true AND ${WITHIN("b")}
        ORDER BY km ASC NULLS LAST, j.published_at DESC NULLS LAST LIMIT ${CAND}`, ctx.geo),
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
      rows: (ctx) => q("listing", `SELECT l.id, l.seller_id, l.title, l.price, l.image_url, l.images, l.place_name, l.city, l.lat, l.lng, l.created_at, l.bumped_at, ${KM("l")} AS km
        FROM market_listings l WHERE l.status='active' AND l.lat IS NOT NULL AND l.lng IS NOT NULL AND (l.publish_at IS NULL OR l.publish_at <= now())
          AND NOT (l.seller_id = ANY($4::text[])) AND ${WITHIN("l")}
        ORDER BY km ASC NULLS LAST, COALESCE(l.bumped_at, l.created_at) DESC LIMIT ${CAND}`, [...ctx.geo, ctx.blocked]),
      userId: (l) => l.seller_id,
      item: (l, ctx, who) => ({
        kind: "listing", id: l.id, refId: l.id, title: cut(l.title, 80), subtitle: cut(`${sar(l.price)} · ${l.place_name || l.city || who.nickname}`, 60),
        who: who.nickname, logoUrl: who.avatarUrl, imageUrl: first(l.images) ?? l.image_url ?? null,
        ...place(ctx, l, l.km), at: iso(l.bumped_at ?? l.created_at), endsAt: null, act: ACT.listing, payload: {},
      }),
    },
  };

  // ---- GET /row?lat=&lng=&radiusKm=15&limit=30 → { items, located }؛ بلا موقع: الأحدث بلا مسافة
  app.get("/row", async (req) => {
    const uid = await optionalAuth(req);
    const lat = num(req.query?.lat), lng = num(req.query?.lng);
    const located = lat != null && lng != null && Math.abs(lat) <= 90 && Math.abs(lng) <= 180;
    const radius = clampInt(req.query?.radiusKm, 1, RADIUS_MAX, RADIUS_DEFAULT);
    const limit = clampInt(req.query?.limit, 1, LIMIT_MAX, LIMIT_DEFAULT);
    const ctx = { geo: located ? [lat, lng, radius] : [0, 0, 0], uid, blocked: await blockedIds(uid), now: Date.now(), located };
    const batches = await Promise.all(KINDS.map(async (k) => ({ k, rows: await SOURCES[k].rows(ctx) })));
    const people = await persons(batches.flatMap(({ k, rows }) => rows.map(SOURCES[k].userId)));
    const items = batches.flatMap(({ k, rows }) => rows.map((r) => SOURCES[k].item(r, ctx, people.get(SOURCES[k].userId(r)) ?? { id: "", nickname: "", avatarUrl: null })));
    return { items: rankItems(items, limit, ctx.now), located };
  });

  // ---- للفحص الحي: أي الجداول المصدرية موجودة
  app.get("/row/status", async () => {
    const sources = {};
    for (const k of KINDS) sources[k] = await exists(TABLES[k]);
    return { ok: true, sources };
  });
}
