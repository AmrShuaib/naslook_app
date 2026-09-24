// تكملة السوق: سبوت لايت (إعلانات مدفوعة يراها كل من يدخل السوق)، التقييمات، ملف البائع وشاراته، المتابعة، الأسئلة والأجوبة،
// طلبات المشترين، الكوبونات، التنبيهات، الإحصاءات، الفواتير، حماية من الاحتيال، وقسم السوق في الإدارة.
// يعتمد على commerce.js (يسجَّل قبله): globalThis.naslifeWallet وnaslifeMarketListingOut وnaslifeMarketOrderOut.
import crypto from "node:crypto";
import { CATEGORY_SET, CATEGORIES, SUBCATEGORIES, subOk } from "./market_taxonomy.js";

const UUID_RE = /^[0-9a-f-]{36}$/i;
const ID_RE = /^[A-Z]{2}\d{7}$/;

export default async function marketPlus(app, opts) {
  const { pool } = opts; const auth = opts.auth ?? globalThis.naslifeAuth;
  if (!pool || !auth) throw new Error("market_plus: pool and auth are required");
  await pool.query("ALTER TABLE market_orders ADD COLUMN IF NOT EXISTS accepted_at TIMESTAMPTZ");
  const W = () => globalThis.naslifeWallet;
  const settings = () => globalThis.naslifeSettings ?? {};
  const unauthorized = (reply) => reply.code(401).send({ error: "auth" });
  const bad = (reply, code, error, extra = {}) => reply.code(code).send({ error, ...extra });
  const notify = async (ids, payload) => { try { await globalThis.naslifeNotify?.(ids, payload); } catch { /* ignore */ } };
  const person = (id) => W().person(id);
  const isAdmin = (id) => W().isAdmin(id);
  const listingOut = (l, uid, o) => globalThis.naslifeMarketListingOut(l, uid, o);
  const orderOut = (o, uid) => globalThis.naslifeMarketOrderOut(o, uid);
  const sar = (h) => W().sar(h);
  const userRow = async (id) => { try { return (await pool.query("SELECT * FROM users WHERE id=$1", [id])).rows[0] ?? null; } catch { return null; } };
  // تصفح الضيف: القراءة العامة بلا جلسة (مراجِع المتجر)، والكتابة والقوائم الشخصية بجلسة
  const optionalAuth = async (req) => { try { return (await auth(req)) || null; } catch { return null; } };
  // عميل iOS الأصلي: سبوت لايت منتج رقمي يُشترى داخل التطبيق فيحتاج مشتريات آبل
  const iosNative = (req) => /^ios\//i.test(String(req.headers["x-naslife-client"] ?? ""));
  const blockedIds = async (uid) => { try { return uid ? (await globalThis.naslifeBlockedIds?.(uid)) ?? [] : []; } catch { return []; } };
  const suspended = async (uid) => { try { if (globalThis.naslifeIsSuspended) return !!(await globalThis.naslifeIsSuspended(uid)); return (await pool.query("SELECT 1 FROM user_flags WHERE user_id=$1 AND suspended", [uid])).rowCount > 0; } catch { return false; } };
  const bannedReply = (reply, ...texts) => {
    let w = null; try { w = globalThis.naslifeCheckText?.(...texts) ?? null; } catch { w = null; }
    if (w) { reply.code(400).send({ error: "banned-words", word: w }); return true; }
    return false;
  };
  const distSql = (la, ln) => `(CASE WHEN lat IS NULL OR lng IS NULL THEN NULL ELSE 6371 * acos(least(1::float8, cos(radians(${la})) * cos(radians(lat)) * cos(radians(lng) - radians(${ln})) + sin(radians(${la})) * sin(radians(lat)))) END)`;

  // ---- حماية: حساب جديد (أقل من ٢٤ ساعة) حتى ٣ عروض، ولا تكرار لعرض نشط بالعنوان والسعر نفسيهما
  globalThis.naslifeMarketGuard = async (uid, { title, price }) => {
    const u = await userRow(uid); const ageH = u?.created_at ? (Date.now() - new Date(u.created_at).getTime()) / 3600000 : 1e9;
    if (ageH < 24) { const n = (await pool.query("SELECT count(*)::int AS n FROM market_listings WHERE seller_id=$1 AND status NOT IN ('hidden','blocked')", [uid])).rows[0].n; if (n >= 3) return "new-account-limit"; }
    const dup = await pool.query("SELECT 1 FROM market_listings WHERE seller_id=$1 AND lower(title)=lower($2) AND price=$3 AND status IN ('active','pending','scheduled')", [uid, title, price]);
    if (dup.rowCount) return "duplicate-listing";
    return null;
  };

  // ---- شارات البائع وإحصاءاته (تُعاد كتابتها بعد كل تقييم أو اكتمال طلب)
  const recompute = async (sellerId) => {
    const r = (await pool.query("SELECT avg(rating)::real AS avg, count(*)::int AS n FROM market_reviews WHERE seller_id=$1 AND NOT hidden", [sellerId])).rows[0];
    const o = (await pool.query(`SELECT count(*) FILTER (WHERE status='completed')::int AS done, count(*) FILTER (WHERE status IN ('cancelled','refunded') AND updated_at > now() - interval '90 days')::int AS cancelled,
      avg(EXTRACT(EPOCH FROM (accepted_at - created_at)) / 3600) FILTER (WHERE accepted_at IS NOT NULL)::real AS resp FROM market_orders WHERE seller_id=$1`, [sellerId])).rows[0];
    let verified = false; try { verified = (await pool.query("SELECT 1 FROM login_aliases WHERE user_id=$1 AND verified", [sellerId])).rowCount > 0; } catch { /* لا جدول */ }
    const flags = (await pool.query("SELECT licensed FROM market_seller_flags WHERE seller_id=$1", [sellerId])).rows[0];
    const badges = [];
    if (verified) badges.push("verified");
    if (o.done >= 10 && o.cancelled <= Math.max(2, o.done * 0.2)) badges.push("trusted");
    if (r.n >= 5 && Number(r.avg) >= 4.5) badges.push("top");
    if (o.resp != null && Number(o.resp) <= 2 && o.done >= 3) badges.push("fast");
    if (flags?.licensed) badges.push("licensed");
    await pool.query(`INSERT INTO market_seller_stats(seller_id, rating_avg, rating_count, completed, cancelled, response_hours, badges, updated_at) VALUES($1,$2,$3,$4,$5,$6,$7,now())
      ON CONFLICT (seller_id) DO UPDATE SET rating_avg=EXCLUDED.rating_avg, rating_count=EXCLUDED.rating_count, completed=EXCLUDED.completed, cancelled=EXCLUDED.cancelled, response_hours=EXCLUDED.response_hours, badges=EXCLUDED.badges, updated_at=now()`,
      [sellerId, r.n ? r.avg : null, r.n, o.done, o.cancelled, o.resp, JSON.stringify(badges)]);
    globalThis.naslifeMarketStatsDirty?.();
  };
  globalThis.naslifeMarketOnComplete = async (o) => recompute(o.seller_id);
  globalThis.naslifeMarketRecomputeSeller = recompute;

  // ---- عند نشر عرض: أخبر متابعي البائع ومن ضبط تنبيهاً يطابقه (تصنيف أو كلمة ضمن نطاقه)
  globalThis.naslifeMarketOnPublish = async (l) => {
    const followers = (await pool.query("SELECT user_id FROM market_follows WHERE seller_id=$1 LIMIT 500", [l.seller_id])).rows.map((x) => x.user_id);
    const nick = (await person(l.seller_id)).nickname || "بائع تتابعه";
    if (followers.length) await notify(followers, { kind: "market_new", title: `جديد من ${nick}`, body: `${l.title} · ${sar(l.price)}`, data: { listingId: l.id } });
    const alerts = (await pool.query(`SELECT * FROM market_alerts WHERE (category IS NULL OR category=$1) AND (subcategory IS NULL OR subcategory=$2) AND (q IS NULL OR $3 ILIKE '%' || q || '%' OR $4 ILIKE '%' || q || '%')
      AND (lat IS NULL OR $5::float8 IS NULL OR ${distSql("$5", "$6").replace(/\blat\b/g, "market_alerts.lat").replace(/\blng\b/g, "market_alerts.lng")} <= radius_km) LIMIT 300`,
      [l.category, l.subcategory, l.title, l.description, l.lat, l.lng])).rows;
    const ids = [...new Set(alerts.map((a) => a.user_id).filter((id) => id !== l.seller_id && !followers.includes(id)))];
    if (ids.length) await notify(ids, { kind: "market_alert", title: "عرض جديد يطابق تنبيهك", body: `${l.title} · ${sar(l.price)}${l.place_name ? " · " + l.place_name : ""}`, data: { listingId: l.id } });
  };

  // ---- التقييمات: بعد اكتمال الطلب، مرة واحدة لكل طلب، مع رد البائع
  app.post("/market/orders/:id/review", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    if (await suspended(uid)) return bad(reply, 403, "suspended");
    const o = (await pool.query("SELECT o.*, l.title FROM market_orders o JOIN market_listings l ON l.id=o.listing_id WHERE o.id=$1", [req.params.id])).rows[0];
    if (!o) return bad(reply, 404, "not-found");
    if (o.buyer_id !== uid) return bad(reply, 403, "buyer-only");
    if (o.status !== "completed") return bad(reply, 409, "not-completed");
    const rating = Math.round(Number(req.body?.rating)); if (!(rating >= 1 && rating <= 5)) return bad(reply, 400, "bad-rating");
    const text = String(req.body?.text ?? "").trim().slice(0, 600);
    const banned = globalThis.naslifeCheckText?.(text); if (banned) return reply.code(400).send({ error: "banned-words", word: banned });
    const ins = await pool.query("INSERT INTO market_reviews(order_id, listing_id, seller_id, buyer_id, rating, text) VALUES($1,$2,$3,$4,$5,$6) ON CONFLICT (order_id) DO NOTHING RETURNING order_id", [o.id, o.listing_id, o.seller_id, uid, rating, text]);
    if (!ins.rowCount) return bad(reply, 409, "already-reviewed");
    await pool.query("UPDATE market_listings SET rating_avg=(SELECT avg(rating) FROM market_reviews WHERE listing_id=$1 AND NOT hidden), rating_count=(SELECT count(*) FROM market_reviews WHERE listing_id=$1 AND NOT hidden) WHERE id=$1", [o.listing_id]);
    await recompute(o.seller_id);
    await notify(o.seller_id, { kind: "market_review", title: `تقييم جديد ${"★".repeat(rating)}`, body: `${o.title}${text ? ": " + text.slice(0, 100) : ""}`, data: { orderId: o.id, listingId: o.listing_id } });
    return { ok: true };
  });
  app.post("/market/reviews/:orderId/reply", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.orderId)) return bad(reply, 400, "bad-id");
    const text = String(req.body?.text ?? "").trim().slice(0, 400); if (!text) return bad(reply, 400, "empty");
    if (bannedReply(reply, text)) return;
    const r = await pool.query("UPDATE market_reviews SET reply=$2, reply_at=now() WHERE order_id=$1 AND seller_id=$3 RETURNING buyer_id, listing_id", [req.params.orderId, text, uid]);
    if (!r.rowCount) return bad(reply, 404, "not-found");
    await notify(r.rows[0].buyer_id, { kind: "market_review", title: "ردّ البائع على تقييمك", body: text.slice(0, 120), data: { listingId: r.rows[0].listing_id } });
    return { ok: true };
  });
  const reviewOut = async (r) => ({ orderId: r.order_id, listingId: r.listing_id, listingTitle: r.title ?? null, rating: r.rating, text: r.text, reply: r.reply, replyAt: r.reply_at, buyer: await person(r.buyer_id), createdAt: r.created_at });
  // التقييمات والأسئلة المخفية بالإشراف لا تظهر إلا لكاتبها، وما كتبه محظور بينه وبين الزائر لا يظهر
  app.get("/market/:id/reviews", async (req, reply) => {
    const uid = await optionalAuth(req);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const r = await pool.query("SELECT r.*, l.title FROM market_reviews r JOIN market_listings l ON l.id=r.listing_id WHERE r.listing_id=$1 AND (NOT r.hidden OR r.buyer_id=$2) AND NOT (r.buyer_id = ANY($3::text[])) ORDER BY r.created_at DESC LIMIT 50", [req.params.id, uid, await blockedIds(uid)]);
    return Promise.all(r.rows.map(reviewOut));
  });

  // ---- ملف البائع: إحصاءات وشارات وعروض وتقييمات ومتابعة
  const sellerProfile = async (id, uid) => {
    const u = await userRow(id); if (!u) return null;
    const s = (await pool.query("SELECT * FROM market_seller_stats WHERE seller_id=$1", [id])).rows[0] ?? null;
    const listings = (await pool.query("SELECT * FROM market_listings WHERE seller_id=$1 AND status='active' ORDER BY bumped_at DESC NULLS LAST LIMIT 60", [id])).rows;
    const reviews = (await pool.query("SELECT r.*, l.title FROM market_reviews r JOIN market_listings l ON l.id=r.listing_id WHERE r.seller_id=$1 AND NOT r.hidden AND NOT (r.buyer_id = ANY($2::text[])) ORDER BY r.created_at DESC LIMIT 20", [id, await blockedIds(uid)])).rows;
    const followers = (await pool.query("SELECT count(*)::int AS n FROM market_follows WHERE seller_id=$1", [id])).rows[0].n;
    const following = uid ? (await pool.query("SELECT 1 FROM market_follows WHERE user_id=$1 AND seller_id=$2", [uid, id])).rowCount > 0 : false;
    // النبذة من ملف عام فقط (الملف الخاص لا تُعرض نبذته في صفحة البائع)
    let bio = ""; try { const pr = (await pool.query("SELECT * FROM profiles WHERE user_id=$1", [id])).rows[0]; bio = pr && pr.is_public !== false ? pr.bio ?? "" : ""; } catch { /* لا جدول */ }
    return {
      seller: await person(id), bio, memberSince: u.created_at ?? null, followers, following, mine: uid === id,
      stats: { ratingAvg: s?.rating_avg == null ? null : Number(s.rating_avg), ratingCount: s?.rating_count ?? 0, completed: s?.completed ?? 0, responseHours: s?.response_hours == null ? null : Number(s.response_hours), activeListings: listings.length },
      badges: Array.isArray(s?.badges) ? s.badges : [], listings: await Promise.all(listings.map((l) => listingOut(l, uid))), reviews: await Promise.all(reviews.map(reviewOut)),
    };
  };
  app.get("/market/sellers/:id", async (req, reply) => {
    const uid = await optionalAuth(req);
    if (!ID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    if (req.params.id !== uid && (await blockedIds(uid)).includes(req.params.id)) return bad(reply, 404, "not-found");
    const p = await sellerProfile(req.params.id, uid); if (!p) return bad(reply, 404, "not-found");
    // الزائر بلا حساب لا يستعرض ملفات من ليسوا بائعين (لا عروض نشطة ولا سجل بيع)
    if (!uid && p.stats.activeListings === 0 && p.stats.completed === 0 && p.stats.ratingCount === 0) return bad(reply, 404, "not-found");
    return p;
  });
  app.post("/market/sellers/:id/follow", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!ID_RE.test(req.params.id) || req.params.id === uid) return bad(reply, 400, "bad-id");
    await pool.query("INSERT INTO market_follows(user_id, seller_id) VALUES($1,$2) ON CONFLICT DO NOTHING", [uid, req.params.id]);
    return { ok: true, following: true };
  });
  app.delete("/market/sellers/:id/follow", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    await pool.query("DELETE FROM market_follows WHERE user_id=$1 AND seller_id=$2", [uid, req.params.id]);
    return { ok: true, following: false };
  });
  app.get("/market/following", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const r = await pool.query("SELECT f.seller_id, s.rating_avg, s.rating_count, (SELECT count(*) FROM market_listings l WHERE l.seller_id=f.seller_id AND l.status='active')::int AS active FROM market_follows f LEFT JOIN market_seller_stats s ON s.seller_id=f.seller_id WHERE f.user_id=$1 ORDER BY f.created_at DESC", [uid]);
    return Promise.all(r.rows.map(async (x) => ({ seller: await person(x.seller_id), ratingAvg: x.rating_avg == null ? null : Number(x.rating_avg), ratingCount: x.rating_count ?? 0, activeListings: x.active })));
  });

  // ---- أسئلة وأجوبة عامة على العرض
  const qOut = async (q) => ({ id: q.id, listingId: q.listing_id, user: await person(q.user_id), text: q.text, answer: q.answer, answeredAt: q.answered_at, createdAt: q.created_at });
  app.get("/market/:id/questions", async (req, reply) => {
    const uid = await optionalAuth(req);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const r = await pool.query("SELECT * FROM market_questions WHERE listing_id=$1 AND (NOT hidden OR user_id=$2) AND NOT (user_id = ANY($3::text[])) ORDER BY created_at DESC LIMIT 50", [req.params.id, uid, await blockedIds(uid)]);
    return Promise.all(r.rows.map(qOut));
  });
  app.post("/market/:id/questions", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    if (await suspended(uid)) return bad(reply, 403, "suspended");
    const l = (await pool.query("SELECT id, seller_id, title FROM market_listings WHERE id=$1 AND status='active'", [req.params.id])).rows[0]; if (!l) return bad(reply, 404, "not-found");
    const text = String(req.body?.text ?? "").trim().slice(0, 400); if (text.length < 3) return bad(reply, 400, "empty");
    const banned = globalThis.naslifeCheckText?.(text); if (banned) return reply.code(400).send({ error: "banned-words", word: banned });
    const id = crypto.randomUUID();
    await pool.query("INSERT INTO market_questions(id, listing_id, user_id, text) VALUES($1,$2,$3,$4)", [id, l.id, uid, text]);
    if (l.seller_id !== uid) await notify(l.seller_id, { kind: "market_question", title: "سؤال على عرضك", body: `${l.title}: ${text.slice(0, 120)}`, data: { listingId: l.id, questionId: id } });
    return qOut((await pool.query("SELECT * FROM market_questions WHERE id=$1", [id])).rows[0]);
  });
  app.post("/market/questions/:qid/answer", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.qid)) return bad(reply, 400, "bad-id");
    const text = String(req.body?.text ?? "").trim().slice(0, 600); if (!text) return bad(reply, 400, "empty");
    if (bannedReply(reply, text)) return;
    const r = await pool.query("UPDATE market_questions q SET answer=$2, answered_at=now() FROM market_listings l WHERE q.id=$1 AND l.id=q.listing_id AND l.seller_id=$3 RETURNING q.user_id, q.listing_id, l.title", [req.params.qid, text, uid]);
    if (!r.rowCount) return bad(reply, 404, "not-found");
    await notify(r.rows[0].user_id, { kind: "market_question", title: "أجاب البائع على سؤالك", body: `${r.rows[0].title}: ${text.slice(0, 120)}`, data: { listingId: r.rows[0].listing_id } });
    return { ok: true };
  });
  app.delete("/market/questions/:qid", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    await pool.query("DELETE FROM market_questions WHERE id=$1 AND (user_id=$2 OR listing_id IN (SELECT id FROM market_listings WHERE seller_id=$2))", [req.params.qid, uid]);
    return { ok: true };
  });

  // ---- طلبات المشترين: «أبحث عن…» فيردّ البائعون بعروض
  const wantedOut = async (w, uid) => ({ id: w.id, user: await person(w.user_id), title: w.title, description: w.description, category: w.category, subcategory: w.subcategory, budgetMin: w.budget_min == null ? null : Number(w.budget_min),
    budgetMax: w.budget_max == null ? null : Number(w.budget_max), placeName: w.place_name, city: w.city, lat: w.lat, lng: w.lng, status: w.status, replies: w.replies, distanceKm: w.dist == null ? null : Math.round(Number(w.dist) * 10) / 10, mine: w.user_id === uid, createdAt: w.created_at });
  app.get("/market/wanted", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const qy = req.query ?? {}; const params = []; const p = (v) => { params.push(v); return `$${params.length}`; };
    const where = ["status='open'"]; if (CATEGORY_SET.has(qy.category)) where.push(`category=${p(qy.category)}`); if (qy.mine === "1") { where.length = 0; where.push(`user_id=${p(uid)}`); }
    else { const blocked = await blockedIds(uid); if (blocked.length) where.push(`NOT (user_id = ANY(${p(blocked)}::text[]))`); }
    const lat = Number(qy.lat), lng = Number(qy.lng); const hasPos = Number.isFinite(lat) && Number.isFinite(lng);
    const dist = hasPos ? distSql(p(lat), p(lng)) : "NULL::float8";
    const r = await pool.query(`SELECT *, ${dist} AS dist FROM market_wanted WHERE ${where.join(" AND ")} ORDER BY ${hasPos ? `${dist} ASC NULLS LAST,` : ""} created_at DESC LIMIT 100`, params);
    return Promise.all(r.rows.map((w) => wantedOut(w, uid)));
  });
  app.post("/market/wanted", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (await suspended(uid)) return bad(reply, 403, "suspended");
    const b = req.body ?? {}; const title = String(b.title ?? "").trim().slice(0, 100); if (title.length < 3) return bad(reply, 400, "bad-title");
    const category = CATEGORY_SET.has(b.category) ? b.category : "other"; const sub = subOk(category, b.subcategory) ? b.subcategory : null;
    const description = String(b.description ?? "").slice(0, 1000);
    const banned = globalThis.naslifeCheckText?.(title, description); if (banned) return reply.code(400).send({ error: "banned-words", word: banned });
    const open = (await pool.query("SELECT count(*)::int AS n FROM market_wanted WHERE user_id=$1 AND status='open'", [uid])).rows[0].n; if (open >= 5) return bad(reply, 429, "too-many-open");
    const id = crypto.randomUUID(); const money = (v) => (v == null || v === "" ? null : Math.max(0, Math.round(Number(v) || 0)));
    await pool.query("INSERT INTO market_wanted(id,user_id,title,description,category,subcategory,budget_min,budget_max,place_name,city,lat,lng) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)",
      [id, uid, title, description, category, sub, money(b.budgetMin), money(b.budgetMax), b.placeName ? String(b.placeName).slice(0, 80) : null, b.city ? String(b.city).slice(0, 40) : null, b.lat == null ? null : Number(b.lat), b.lng == null ? null : Number(b.lng)]);
    // أخبر بائعي التصنيف القريبين (حتى ٣٠ كم إن عُرف الموقع)
    const lat = b.lat == null ? null : Number(b.lat), lng = b.lng == null ? null : Number(b.lng);
    const sellers = (await pool.query(`SELECT DISTINCT seller_id FROM market_listings WHERE status='active' AND category=$1 AND seller_id<>$2 ${lat != null ? `AND lat IS NOT NULL AND ${distSql("$3", "$4")} <= 30` : ""} LIMIT 50`, lat != null ? [category, uid, lat, lng] : [category, uid])).rows.map((x) => x.seller_id);
    if (sellers.length) await notify(sellers, { kind: "market_wanted", title: "مشترٍ يبحث عن شيء تقدّمه", body: `${title}${b.budgetMax ? " · حتى " + sar(money(b.budgetMax)) : ""}`, data: { wantedId: id } });
    return wantedOut((await pool.query("SELECT * FROM market_wanted WHERE id=$1", [id])).rows[0], uid);
  });
  app.get("/market/wanted/:id", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const w = (await pool.query("SELECT * FROM market_wanted WHERE id=$1", [req.params.id])).rows[0]; if (!w) return bad(reply, 404, "not-found");
    const blocked = await blockedIds(uid);
    if (w.user_id !== uid && (w.status === "blocked" || blocked.includes(w.user_id))) return bad(reply, 404, "not-found");
    const replies = (await pool.query("SELECT r.*, l.title AS listing_title, l.image_url FROM market_wanted_replies r LEFT JOIN market_listings l ON l.id=r.listing_id WHERE r.wanted_id=$1 AND (NOT r.hidden OR r.seller_id=$2) AND NOT (r.seller_id = ANY($3::text[])) ORDER BY r.created_at ASC", [w.id, uid, blocked])).rows;
    return { ...(await wantedOut(w, uid)), replyList: await Promise.all(replies.map(async (r) => ({ id: r.id, seller: await person(r.seller_id), text: r.text, price: r.price == null ? null : Number(r.price), listingId: r.listing_id, listingTitle: r.listing_title, imageUrl: r.image_url, mine: r.seller_id === uid, createdAt: r.created_at }))) };
  });
  app.post("/market/wanted/:id/replies", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (await suspended(uid)) return bad(reply, 403, "suspended");
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const w = (await pool.query("SELECT * FROM market_wanted WHERE id=$1 AND status='open'", [req.params.id])).rows[0]; if (!w) return bad(reply, 404, "not-found");
    if (w.user_id === uid) return bad(reply, 400, "own-request");
    const text = String(req.body?.text ?? "").trim().slice(0, 500); const price = req.body?.price == null ? null : Math.max(0, Math.round(Number(req.body.price) || 0));
    const listingId = UUID_RE.test(String(req.body?.listingId ?? "")) ? req.body.listingId : null;
    if (!text && !listingId) return bad(reply, 400, "empty");
    const banned = globalThis.naslifeCheckText?.(text); if (banned) return reply.code(400).send({ error: "banned-words", word: banned });
    const id = crypto.randomUUID();
    await pool.query("INSERT INTO market_wanted_replies(id, wanted_id, seller_id, listing_id, text, price) VALUES($1,$2,$3,$4,$5,$6)", [id, w.id, uid, listingId, text, price]);
    await pool.query("UPDATE market_wanted SET replies=replies+1 WHERE id=$1", [w.id]);
    await notify(w.user_id, { kind: "market_wanted", title: "عرض على طلبك", body: `${(await person(uid)).nickname}: ${text.slice(0, 100)}${price != null ? " · " + sar(price) : ""}`, data: { wantedId: w.id } });
    return { ok: true, id };
  });
  app.patch("/market/wanted/:id", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const status = req.body?.status === "closed" ? "closed" : "open";
    // الطلب الذي أخفاه الإشراف (status=blocked) لا يعيد صاحبه فتحه
    await pool.query("UPDATE market_wanted SET status=$2 WHERE id=$1 AND user_id=$3 AND status<>'blocked'", [req.params.id, status, uid]);
    return { ok: true, status };
  });

  // ---- كوبونات البائع
  const couponOut = (c) => ({ code: c.code, percent: c.percent, amount: c.amount == null ? null : Number(c.amount), minTotal: Number(c.min_total ?? 0), maxUses: c.max_uses, used: c.used, expiresAt: c.expires_at, active: c.active, createdAt: c.created_at });
  app.get("/market/coupons", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    return (await pool.query("SELECT * FROM market_coupons WHERE seller_id=$1 ORDER BY created_at DESC", [uid])).rows.map(couponOut);
  });
  app.post("/market/coupons", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const b = req.body ?? {}; const code = String(b.code ?? "").trim().toUpperCase().replace(/[^A-Z0-9_-]/g, "").slice(0, 24); if (code.length < 3) return bad(reply, 400, "bad-code");
    const percent = b.percent == null || b.percent === "" ? null : Math.round(Number(b.percent)); const amount = b.amount == null || b.amount === "" ? null : Math.round(Number(b.amount));
    if ((percent == null && !(amount > 0)) || (percent != null && !(percent >= 1 && percent <= 90))) return bad(reply, 400, "bad-discount");
    const n = (await pool.query("SELECT count(*)::int AS n FROM market_coupons WHERE seller_id=$1 AND active", [uid])).rows[0].n; if (n >= 20) return bad(reply, 429, "too-many");
    const exp = b.expiresAt ? new Date(b.expiresAt) : null;
    const r = await pool.query("INSERT INTO market_coupons(code, seller_id, percent, amount, min_total, max_uses, expires_at) VALUES($1,$2,$3,$4,$5,$6,$7) ON CONFLICT (seller_id, code) DO NOTHING RETURNING *",
      [code, uid, percent, percent == null ? amount : null, Math.max(0, Math.round(Number(b.minTotal) || 0)), b.maxUses == null || b.maxUses === "" ? null : Math.max(1, Math.round(Number(b.maxUses))), exp && !Number.isNaN(exp.getTime()) ? exp : null]);
    if (!r.rowCount) return bad(reply, 409, "exists");
    return couponOut(r.rows[0]);
  });
  app.patch("/market/coupons/:code", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const r = await pool.query("UPDATE market_coupons SET active=$3 WHERE seller_id=$1 AND code=$2 RETURNING *", [uid, String(req.params.code).toUpperCase(), req.body?.active !== false]);
    if (!r.rowCount) return bad(reply, 404, "not-found");
    return couponOut(r.rows[0]);
  });
  // معاينة الخصم قبل الطلب
  app.get("/market/coupons/check", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const code = String(req.query?.code ?? "").trim().toUpperCase(); const seller = String(req.query?.seller ?? ""); const total = Math.max(0, Math.round(Number(req.query?.total) || 0));
    const c = (await pool.query("SELECT * FROM market_coupons WHERE code=$1 AND seller_id=$2 AND active AND (expires_at IS NULL OR expires_at > now()) AND (max_uses IS NULL OR used < max_uses)", [code, seller])).rows[0];
    if (!c) return { valid: false, error: "bad-coupon" };
    if (total < Number(c.min_total ?? 0)) return { valid: false, error: "coupon-min", minTotal: Number(c.min_total) };
    const discount = c.percent != null ? Math.floor(total * Number(c.percent) / 100) : Math.min(total, Number(c.amount ?? 0));
    return { valid: true, discount, total: Math.max(0, total - discount) };
  });

  // ---- تنبيهات: عرض جديد في تصنيف أو بكلمة قرب موقعي
  const alertOut = (a) => ({ id: a.id, category: a.category, subcategory: a.subcategory, q: a.q, lat: a.lat, lng: a.lng, radiusKm: a.radius_km, createdAt: a.created_at });
  app.get("/market/alerts", async (req, reply) => { const uid = await auth(req); if (!uid) return unauthorized(reply); return (await pool.query("SELECT * FROM market_alerts WHERE user_id=$1 ORDER BY created_at DESC", [uid])).rows.map(alertOut); });
  app.post("/market/alerts", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const b = req.body ?? {}; const category = CATEGORY_SET.has(b.category) ? b.category : null; const sub = category && subOk(category, b.subcategory) ? b.subcategory : null;
    const q = String(b.q ?? "").trim().slice(0, 40) || null; if (!category && !q) return bad(reply, 400, "empty");
    const n = (await pool.query("SELECT count(*)::int AS n FROM market_alerts WHERE user_id=$1", [uid])).rows[0].n; if (n >= 10) return bad(reply, 429, "too-many");
    const id = crypto.randomUUID();
    await pool.query("INSERT INTO market_alerts(id, user_id, category, subcategory, q, lat, lng, radius_km) VALUES($1,$2,$3,$4,$5,$6,$7,$8)", [id, uid, category, sub, q, b.lat == null ? null : Number(b.lat), b.lng == null ? null : Number(b.lng), Math.min(500, Math.max(1, Math.round(Number(b.radiusKm) || 25)))]);
    return alertOut((await pool.query("SELECT * FROM market_alerts WHERE id=$1", [id])).rows[0]);
  });
  app.delete("/market/alerts/:id", async (req, reply) => { const uid = await auth(req); if (!uid) return unauthorized(reply); await pool.query("DELETE FROM market_alerts WHERE id=$1 AND user_id=$2", [req.params.id, uid]); return { ok: true }; });

  // ---- سبوت لايت: مساحة إعلانية في أعلى السوق يراها كل من يدخله؛ يشتريها البائع بالأيام من محفظته أو تمنحها الإدارة
  const spotPrice = () => { const v = Number(settings().spotlightPricePerDay); return Number.isFinite(v) && v >= 0 ? Math.round(v) : 2000; };
  const spotMaxDays = () => Math.min(90, Math.max(1, Number(settings().spotlightMaxDays) || 30));
  const spotOut = async (s, uid, l) => ({ id: s.id, listing: l ? await listingOut(l, uid) : null, startsAt: s.starts_at, endsAt: s.ends_at, days: s.days, paid: Number(s.paid), status: s.status, views: s.views, clicks: s.clicks, granted: !!s.granted_by });
  app.get("/market/spotlight", async (req, reply) => {
    const uid = await optionalAuth(req);
    const r = await pool.query("SELECT s.*, l.* , s.id AS sid, s.status AS sstatus FROM market_spotlight s JOIN market_listings l ON l.id=s.listing_id WHERE s.status='active' AND s.ends_at > now() AND l.status='active' AND NOT (l.seller_id = ANY($1::text[])) ORDER BY random() LIMIT 12", [await blockedIds(uid)]);
    // مشاهدات الضيوف لا تُحسب (يدفع البائع مقابل وصول لمستخدمين حقيقيين)
    if (r.rowCount && uid) await pool.query("UPDATE market_spotlight SET views=views+1 WHERE id = ANY($1::uuid[])", [r.rows.map((x) => x.sid)]);
    return Promise.all(r.rows.map(async (x) => ({ id: x.sid, endsAt: x.ends_at, listing: await listingOut({ ...x, id: x.listing_id, status: x.status }, uid) })));
  });
  app.post("/market/spotlight/:id/click", async (req, reply) => { const uid = await auth(req); if (!uid) return unauthorized(reply); if (UUID_RE.test(req.params.id)) await pool.query("UPDATE market_spotlight SET clicks=clicks+1 WHERE id=$1", [req.params.id]); return { ok: true }; });
  app.get("/market/spotlight/price", async (req, reply) => { const uid = await auth(req); if (!uid) return unauthorized(reply); return { perDay: spotPrice(), maxDays: spotMaxDays(), purchasable: !iosNative(req) }; });
  app.get("/market/spotlight/mine", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const r = await pool.query("SELECT s.*, l.title, l.image_url FROM market_spotlight s JOIN market_listings l ON l.id=s.listing_id WHERE s.seller_id=$1 ORDER BY s.created_at DESC LIMIT 50", [uid]);
    return r.rows.map((s) => ({ id: s.id, listingId: s.listing_id, title: s.title, imageUrl: s.image_url, startsAt: s.starts_at, endsAt: s.ends_at, days: s.days, paid: Number(s.paid), status: s.ends_at > new Date() && s.status === "active" ? "active" : "ended", views: s.views, clicks: s.clicks, granted: !!s.granted_by }));
  });
  const grantSpotlight = async (l, sellerId, days, { paid = 0, grantedBy = null, payer = null } = {}) => {
    const id = crypto.randomUUID();
    await W().tx(async (c) => {
      // يمتد من نهاية السبوت لايت الحالي إن وُجد
      const cur = (await c.query("SELECT spotlight_until FROM market_listings WHERE id=$1 FOR UPDATE", [l.id])).rows[0];
      const base = cur?.spotlight_until && new Date(cur.spotlight_until) > new Date() ? new Date(cur.spotlight_until) : new Date();
      const ends = new Date(base.getTime() + days * 86400000);
      if (paid > 0 && payer) { await W().ledger(c, payer, "spotlight", -paid, { ref: id, note: `سبوت لايت: ${l.title} (${days} يوم)` }); await W().ledger(c, W().PLATFORM, "spotlight_income", paid, { peerId: payer, ref: id, note: l.title }); }
      await c.query("INSERT INTO market_spotlight(id, listing_id, seller_id, starts_at, ends_at, days, paid, granted_by) VALUES($1,$2,$3,$4,$5,$6,$7,$8)", [id, l.id, sellerId, base, ends, days, paid, grantedBy]);
      await c.query("UPDATE market_listings SET spotlight_until=$2, bumped_at=now(), updated_at=now() WHERE id=$1", [l.id, ends]);
      return ends;
    });
    return (await pool.query("SELECT * FROM market_spotlight WHERE id=$1", [id])).rows[0];
  };
  app.post("/market/:id/spotlight", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    // شراء إعلان رقمي من داخل تطبيق iOS يحتاج مشتريات آبل؛ حتى تُربط يُرفض من عميل iOS
    if (iosNative(req)) return bad(reply, 403, "iap-required");
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const l = (await pool.query("SELECT * FROM market_listings WHERE id=$1", [req.params.id])).rows[0]; if (!l) return bad(reply, 404, "not-found");
    if (l.seller_id !== uid) return bad(reply, 403, "forbidden");
    if (l.status !== "active") return bad(reply, 409, "not-active");
    const days = Math.round(Number(req.body?.days) || 0); if (days < 1 || days > spotMaxDays()) return bad(reply, 400, "bad-days", { maxDays: spotMaxDays() });
    const active = (await pool.query("SELECT count(DISTINCT listing_id)::int AS n FROM market_spotlight WHERE status='active' AND ends_at > now()")).rows[0].n;
    const maxActive = Math.max(1, Number(settings().spotlightMaxActive) || 12);
    if (active >= maxActive && !(l.spotlight_until && new Date(l.spotlight_until) > new Date())) return bad(reply, 409, "spotlight-full", { maxActive });
    const cost = spotPrice() * days;
    let s; try { s = await grantSpotlight(l, uid, days, { paid: cost, payer: uid }); } catch (e) { if (e.code === "insufficient-funds") return bad(reply, 402, "insufficient-funds", { cost }); throw e; }
    return { ok: true, id: s.id, endsAt: s.ends_at, paid: cost };
  });
  app.post("/adminapi/market/spotlight", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply); if (!(await isAdmin(uid))) return bad(reply, 403, "admin-only");
    const l = (await pool.query("SELECT * FROM market_listings WHERE id=$1", [String(req.body?.listingId ?? "")])).rows[0]; if (!l) return bad(reply, 404, "not-found");
    const days = Math.min(90, Math.max(1, Math.round(Number(req.body?.days) || 7)));
    const s = await grantSpotlight(l, l.seller_id, days, { grantedBy: uid });
    await notify(l.seller_id, { kind: "market_spotlight", title: "عرضك في سبوت لايت", body: `${l.title}: منحتك الإدارة ${days} يوماً في أعلى السوق`, data: { listingId: l.id } });
    return { ok: true, id: s.id, endsAt: s.ends_at };
  });
  app.delete("/adminapi/market/spotlight/:id", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply); if (!(await isAdmin(uid))) return bad(reply, 403, "admin-only");
    const r = await pool.query("UPDATE market_spotlight SET status='stopped' WHERE id=$1 RETURNING listing_id", [req.params.id]); if (!r.rowCount) return bad(reply, 404, "not-found");
    await pool.query("UPDATE market_listings SET spotlight_until=NULL WHERE id=$1", [r.rows[0].listing_id]);
    return { ok: true };
  });

  // ---- مشاهدات (مرة لكل مستخدم يومياً)
  app.post("/market/:id/view", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const r = await pool.query("INSERT INTO market_views(listing_id, user_id, day) VALUES($1,$2,CURRENT_DATE) ON CONFLICT DO NOTHING RETURNING listing_id", [req.params.id, uid]);
    if (r.rowCount) await pool.query("UPDATE market_listings SET views=views+1 WHERE id=$1 AND seller_id<>$2", [req.params.id, uid]);
    return { ok: true };
  });

  // ---- الصفحة الرئيسية للسوق: سبوت لايت، الأكثر طلباً، الأقرب، وعدّاد كل تصنيف
  app.get("/market/home", async (req, reply) => {
    const uid = await optionalAuth(req);
    const lat = Number(req.query?.lat), lng = Number(req.query?.lng); const hasPos = Number.isFinite(lat) && Number.isFinite(lng);
    const blocked = await blockedIds(uid);
    const spot = await pool.query("SELECT s.id AS sid, s.ends_at, l.* FROM market_spotlight s JOIN market_listings l ON l.id=s.listing_id WHERE s.status='active' AND s.ends_at > now() AND l.status='active' AND NOT (l.seller_id = ANY($1::text[])) ORDER BY random() LIMIT 12", [blocked]);
    if (spot.rowCount && uid) await pool.query("UPDATE market_spotlight SET views=views+1 WHERE id = ANY($1::uuid[])", [spot.rows.map((x) => x.sid)]);
    const popular = await pool.query("SELECT * FROM market_listings WHERE status='active' AND (publish_at IS NULL OR publish_at <= now()) AND NOT (seller_id = ANY($1::text[])) ORDER BY (sold * 3 + views) DESC, bumped_at DESC LIMIT 8", [blocked]);
    const nearby = hasPos ? await pool.query(`SELECT *, ${distSql("$1", "$2")} AS dist FROM market_listings WHERE status='active' AND lat IS NOT NULL AND NOT (seller_id = ANY($3::text[])) ORDER BY dist ASC LIMIT 8`, [lat, lng, blocked]) : { rows: [] };
    const counts = (await pool.query("SELECT category, count(*)::int AS n FROM market_listings WHERE status='active' GROUP BY category")).rows;
    const wanted = (await pool.query("SELECT count(*)::int AS n FROM market_wanted WHERE status='open'")).rows[0].n;
    return {
      spotlight: await Promise.all(spot.rows.map(async (x) => ({ id: x.sid, endsAt: x.ends_at, listing: await listingOut(x, uid) }))),
      popular: await Promise.all(popular.rows.map((l) => listingOut(l, uid))), nearby: await Promise.all(nearby.rows.map((l) => listingOut(l, uid, { dist: l.dist }))),
      categories: Object.fromEntries(CATEGORIES.map((c) => [c, counts.find((x) => x.category === c)?.n ?? 0])), subcategories: SUBCATEGORIES, wantedOpen: wanted,
      bazaars: await (globalThis.naslifeMarketBazaars?.(uid).catch(() => []) ?? []),
      spotlightPricePerDay: spotPrice(), spotlightPurchasable: !iosNative(req), commissionPct: Number(settings().marketCommissionPct) || 0,
    };
  });

  // ---- لوحة البائع
  app.get("/market/seller/stats", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const sums = (await pool.query(`SELECT
      count(*) FILTER (WHERE created_at >= date_trunc('day', now() + interval '3 hours') - interval '3 hours')::int AS today_n, COALESCE(sum(total) FILTER (WHERE created_at >= date_trunc('day', now() + interval '3 hours') - interval '3 hours'),0)::bigint AS today_v,
      count(*) FILTER (WHERE created_at >= now() - interval '7 days')::int AS week_n, COALESCE(sum(total) FILTER (WHERE created_at >= now() - interval '7 days'),0)::bigint AS week_v,
      count(*) FILTER (WHERE created_at >= now() - interval '30 days')::int AS month_n, COALESCE(sum(total) FILTER (WHERE created_at >= now() - interval '30 days'),0)::bigint AS month_v,
      COALESCE(sum(total - commission) FILTER (WHERE status='completed' AND created_at >= now() - interval '30 days'),0)::bigint AS month_net,
      count(*) FILTER (WHERE status IN ('paid','preparing','on_the_way'))::int AS pending, count(*) FILTER (WHERE status='delivered')::int AS awaiting, count(*) FILTER (WHERE status='disputed')::int AS disputed
      FROM market_orders WHERE seller_id=$1 AND status NOT IN ('cancelled','refunded')`, [uid])).rows[0];
    const views7 = (await pool.query("SELECT count(*)::int AS n FROM market_views v JOIN market_listings l ON l.id=v.listing_id WHERE l.seller_id=$1 AND v.day >= CURRENT_DATE - 7", [uid])).rows[0].n;
    const top = (await pool.query(`SELECT l.id, l.title, l.image_url, l.views, l.sold, l.status, COALESCE((SELECT sum(total) FROM market_orders o WHERE o.listing_id=l.id AND o.status NOT IN ('cancelled','refunded')),0)::bigint AS revenue,
      (SELECT count(*) FROM market_views v WHERE v.listing_id=l.id AND v.day >= CURRENT_DATE - 7)::int AS views7 FROM market_listings l WHERE l.seller_id=$1 AND l.status NOT IN ('hidden','blocked') ORDER BY revenue DESC, views DESC LIMIT 8`, [uid])).rows;
    const s = (await pool.query("SELECT * FROM market_seller_stats WHERE seller_id=$1", [uid])).rows[0];
    const followers = (await pool.query("SELECT count(*)::int AS n FROM market_follows WHERE seller_id=$1", [uid])).rows[0].n;
    const spot = (await pool.query("SELECT count(*)::int AS n FROM market_spotlight WHERE seller_id=$1 AND status='active' AND ends_at > now()", [uid])).rows[0].n;
    const listings = (await pool.query("SELECT status, count(*)::int AS n FROM market_listings WHERE seller_id=$1 GROUP BY status", [uid])).rows;
    const orders7 = Number(sums.week_n); const conv = views7 ? Math.round((orders7 / views7) * 1000) / 10 : 0;
    return {
      today: { orders: sums.today_n, revenue: Number(sums.today_v) }, week: { orders: sums.week_n, revenue: Number(sums.week_v) }, month: { orders: sums.month_n, revenue: Number(sums.month_v), net: Number(sums.month_net) },
      pending: sums.pending, awaitingConfirm: sums.awaiting, disputed: sums.disputed, views7, conversionPct: conv, followers, spotlightActive: spot,
      rating: { avg: s?.rating_avg == null ? null : Number(s.rating_avg), count: s?.rating_count ?? 0 }, badges: Array.isArray(s?.badges) ? s.badges : [], responseHours: s?.response_hours == null ? null : Number(s.response_hours),
      listings: Object.fromEntries(listings.map((x) => [x.status, x.n])),
      top: top.map((t) => ({ id: t.id, title: t.title, imageUrl: t.image_url, views: t.views, views7: t.views7, sold: t.sold, revenue: Number(t.revenue), status: t.status })),
    };
  });

  // ---- فاتورة الطلب (HTML قابل للطباعة والحفظ PDF من المتصفح)
  app.get("/market/orders/:id/invoice", async (req, reply) => {
    // تُفتح في تبويب جديد بلا ترويسات، فيُقبل الرمز في الاستعلام
    if (req.query?.token && !req.headers["x-token"]) { req.headers["x-token"] = String(req.query.token); req.headers.authorization = "Bearer " + String(req.query.token); }
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const o = (await pool.query("SELECT o.*, l.title, l.kind FROM market_orders o JOIN market_listings l ON l.id=o.listing_id WHERE o.id=$1", [req.params.id])).rows[0];
    if (!o) return bad(reply, 404, "not-found");
    if (o.buyer_id !== uid && o.seller_id !== uid && !(await isAdmin(uid))) return bad(reply, 403, "forbidden");
    const buyer = await person(o.buyer_id), seller = await person(o.seller_id);
    const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
    const d = (t) => (t ? new Date(new Date(t).getTime() + 3 * 3600000).toISOString().slice(0, 16).replace("T", " ") : "");
    const status = { paid: "مؤكَّد", preparing: "قيد التحضير", on_the_way: "في الطريق", delivered: "تم التسليم", completed: "مكتمل", cancelled: "ملغى", refunded: "مسترد", disputed: "نزاع" }[o.status] ?? o.status;
    const unit = Number(o.total) + Number(o.discount ?? 0);
    const html = `<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8"><title>فاتورة ${esc(o.id.slice(0, 8))}</title>
<style>body{font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;max-width:720px;margin:32px auto;padding:0 20px;color:#111}h1{font-size:22px;margin:0}.muted{color:#6b7280;font-size:13px}table{width:100%;border-collapse:collapse;margin-top:18px}td,th{padding:10px 8px;border-bottom:1px solid #e5e5ea;text-align:right}th{background:#f2f2f7;font-weight:600}.tot td{font-weight:700}.head{display:flex;justify-content:space-between;align-items:center;border-bottom:3px solid #BF3A1E;padding-bottom:12px}.grid{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-top:16px}.box{background:#fafafa;border-radius:12px;padding:12px}@media print{button{display:none}}</style></head><body>
<div class="head"><div><h1>فاتورة سوق ناس لايف</h1><div class="muted">رقم ${esc(o.id)} · ${d(o.created_at)}</div></div><div><strong>${esc(status)}</strong></div></div>
<div class="grid"><div class="box"><div class="muted">المشتري</div><div>${esc(buyer.nickname)} · ${esc(buyer.id)}</div></div><div class="box"><div class="muted">البائع</div><div>${esc(seller.nickname)} · ${esc(seller.id)}</div></div></div>
<table><tr><th>البند</th><th>الكمية</th><th>المبلغ</th></tr><tr><td>${esc(o.title)}${o.variant ? " (" + esc(o.variant) + ")" : ""}${o.slot ? "<div class='muted'>موعد: " + d(o.slot) + "</div>" : ""}</td><td>${o.qty}</td><td>${esc(sar(unit))}</td></tr>
${Number(o.discount) > 0 ? `<tr><td>خصم${o.coupon ? " (" + esc(o.coupon) + ")" : ""}</td><td></td><td>- ${esc(sar(o.discount))}</td></tr>` : ""}
<tr class="tot"><td>الإجمالي المدفوع</td><td></td><td>${esc(sar(o.total))}</td></tr>${o.seller_id === uid && Number(o.commission) > 0 ? `<tr><td class="muted">عمولة المنصة</td><td></td><td class="muted">${esc(sar(o.commission))}</td></tr><tr class="tot"><td>صافي البائع</td><td></td><td>${esc(sar(Number(o.total) - Number(o.commission)))}</td></tr>` : ""}</table>
${o.note ? `<p class="muted">ملاحظة: ${esc(o.note)}</p>` : ""}<p class="muted">المبالغ بالريال السعودي. الدفع عبر محفظة ناس لايف؛ يُحرَّر المبلغ للبائع عند تأكيد الاستلام.</p><button onclick="print()">طباعة / حفظ PDF</button></body></html>`;
    return reply.type("text/html; charset=utf-8").send(html);
  });

  // ---- الإدارة: نظرة عامة، عروض بانتظار المراجعة، نزاعات، أعلى البائعين، تصنيفات راكدة، شارات
  const adminOnly = async (req, reply) => { const uid = await auth(req); if (!uid) { unauthorized(reply); return null; } if (!(await isAdmin(uid))) { bad(reply, 403, "admin-only"); return null; } return uid; };
  app.get("/adminapi/market/overview", async (req, reply) => {
    const uid = await adminOnly(req, reply); if (!uid) return;
    const st = (await pool.query("SELECT status, count(*)::int AS n FROM market_listings GROUP BY status")).rows;
    const o = (await pool.query(`SELECT count(*) FILTER (WHERE status IN ('paid','preparing','on_the_way','delivered'))::int AS open, count(*) FILTER (WHERE status='disputed')::int AS disputed,
      COALESCE(sum(total) FILTER (WHERE status NOT IN ('cancelled','refunded') AND created_at >= now() - interval '30 days'),0)::bigint AS gmv30, COALESCE(sum(commission) FILTER (WHERE status='completed' AND completed_at >= now() - interval '30 days'),0)::bigint AS commission30,
      count(*) FILTER (WHERE created_at >= now() - interval '30 days')::int AS orders30, count(*) FILTER (WHERE status IN ('cancelled','refunded') AND created_at >= now() - interval '30 days')::int AS cancelled30, COALESCE(avg(total) FILTER (WHERE status NOT IN ('cancelled','refunded') AND created_at >= now() - interval '30 days'),0)::bigint AS basket FROM market_orders`)).rows[0];
    const spot = (await pool.query("SELECT COALESCE(sum(paid),0)::bigint AS rev, count(*) FILTER (WHERE status='active' AND ends_at > now())::int AS active FROM market_spotlight WHERE created_at >= now() - interval '30 days'")).rows[0];
    const top = (await pool.query("SELECT seller_id, count(*)::int AS n, COALESCE(sum(total),0)::bigint AS v FROM market_orders WHERE status='completed' AND completed_at >= now() - interval '30 days' GROUP BY seller_id ORDER BY v DESC LIMIT 10")).rows;
    const cats = (await pool.query("SELECT category, count(*)::int AS n FROM market_listings WHERE status='active' GROUP BY category")).rows;
    const cities = (await pool.query("SELECT COALESCE(l.city, split_part(l.place_name, '،', 2), 'غير محدد') AS city, count(*)::int AS n FROM market_orders o JOIN market_listings l ON l.id=o.listing_id WHERE o.created_at >= now() - interval '30 days' GROUP BY 1 ORDER BY n DESC LIMIT 8")).rows;
    const pending = (await pool.query("SELECT * FROM market_listings WHERE status='pending' ORDER BY created_at ASC LIMIT 50")).rows;
    const disputes = (await pool.query("SELECT o.*, l.title, l.image_url, l.kind FROM market_orders o JOIN market_listings l ON l.id=o.listing_id WHERE o.status='disputed' ORDER BY o.updated_at ASC LIMIT 50")).rows;
    return {
      listings: Object.fromEntries(st.map((x) => [x.status, x.n])), ordersOpen: o.open, disputesOpen: o.disputed, gmv30: Number(o.gmv30), commission30: Number(o.commission30), orders30: o.orders30, cancelRatePct: o.orders30 ? Math.round((o.cancelled30 / o.orders30) * 1000) / 10 : 0, basket: Number(o.basket),
      spotlight: { revenue30: Number(spot.rev), active: spot.active, pricePerDay: spotPrice() }, commissionPct: Number(settings().marketCommissionPct) || 0,
      topSellers: await Promise.all(top.map(async (t) => ({ seller: await person(t.seller_id), orders: t.n, revenue: Number(t.v) }))),
      categories: CATEGORIES.map((c) => ({ category: c, active: cats.find((x) => x.category === c)?.n ?? 0, stale: (cats.find((x) => x.category === c)?.n ?? 0) < 3 })), cities: cities.map((c) => ({ city: c.city, orders: c.n })),
      pending: await Promise.all(pending.map((l) => listingOut(l, uid))), disputes: await Promise.all(disputes.map((d) => orderOut(d, uid))),
    };
  });
  app.post("/adminapi/market/pending/:id", async (req, reply) => {
    const uid = await adminOnly(req, reply); if (!uid) return;
    const l = (await pool.query("SELECT * FROM market_listings WHERE id=$1 AND status='pending'", [req.params.id])).rows[0]; if (!l) return bad(reply, 404, "not-found");
    const approve = req.body?.approve !== false; const note = String(req.body?.note ?? "").slice(0, 300);
    await pool.query("UPDATE market_listings SET status=$2, bumped_at=now(), updated_at=now() WHERE id=$1", [l.id, approve ? "active" : "blocked"]);
    if (approve) globalThis.naslifeMarketOnPublish?.({ ...l, status: "active" }).catch?.(() => {});
    await notify(l.seller_id, { kind: "market_review_result", title: approve ? "نُشر عرضك" : "لم يُقبل عرضك", body: `${l.title}${note ? ": " + note : ""}`, data: { listingId: l.id } });
    return { ok: true, status: approve ? "active" : "blocked" };
  });
  app.patch("/adminapi/market/sellers/:id/flags", async (req, reply) => {
    const uid = await adminOnly(req, reply); if (!uid) return;
    if (!ID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    await pool.query("INSERT INTO market_seller_flags(seller_id, licensed, note, updated_at) VALUES($1,$2,$3,now()) ON CONFLICT (seller_id) DO UPDATE SET licensed=EXCLUDED.licensed, note=EXCLUDED.note, updated_at=now()", [req.params.id, req.body?.licensed === true, String(req.body?.note ?? "").slice(0, 200) || null]);
    await recompute(req.params.id);
    return { ok: true };
  });
  app.get("/adminapi/market/listings", async (req, reply) => {
    const uid = await adminOnly(req, reply); if (!uid) return;
    const status = String(req.query?.status ?? ""); const q = String(req.query?.q ?? "").trim();
    const r = await pool.query(`SELECT * FROM market_listings WHERE ($1 = '' OR status=$1) AND ($2 = '' OR title ILIKE '%' || $2 || '%' OR seller_id ILIKE '%' || $2 || '%') ORDER BY created_at DESC LIMIT 200`, [status, q]);
    return Promise.all(r.rows.map((l) => listingOut(l, uid)));
  });
  app.get("/adminapi/market/orders", async (req, reply) => {
    const uid = await adminOnly(req, reply); if (!uid) return;
    const status = String(req.query?.status ?? "");
    const r = await pool.query(`SELECT o.*, l.title, l.image_url, l.kind FROM market_orders o JOIN market_listings l ON l.id=o.listing_id WHERE ($1 = '' OR o.status=$1) ORDER BY o.created_at DESC LIMIT 200`, [status]);
    return Promise.all(r.rows.map((o) => orderOut(o, uid)));
  });
}
