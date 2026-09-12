// إضافة Fastify للبحث والاكتشاف في Naslife: بحث موحّد (أشخاص، دوائر، أنشطة تجارية وعناصر كتالوجها، السوق، الفعاليات)
// بتطبيع عربي (الهمزات والتاء المربوطة والتشكيل) ومسافة من موقع المستخدم، واكتشاف: المفتوح الآن قريباً، الأعلى تقييماً، فعاليات قادمة، دوائر نشطة.
// جداول الخادم الأساسي (users, vessels, أعضاؤها) تُكتشف أعمدتها عند الإقلاع حتى لا نفترض أسماءً غير موجودة.
// التسجيل في src/index.js بعد business.js:
//   await app.register((await import("./search.js")).default, { pool, auth });
import { NORM, likeOf, normQ, DIST, roundKm, isOpenNow } from "./business.js";

const q = (ident) => `"${String(ident).replace(/"/g, '""')}"`;
const str = (v, max = 200) => String(v ?? "").trim().slice(0, max);
const num = (v) => (v == null || v === "" ? null : Number(v));
const TYPES = ["people", "vessels", "biz", "items", "market", "events"];

export default async function search(app, opts) {
  const { pool, auth } = opts;
  if (!pool || !auth) throw new Error("search: pool and auth are required");

  const cols = (await pool.query("SELECT table_name, column_name, data_type FROM information_schema.columns WHERE table_schema='public'")).rows;
  const tables = new Map();
  for (const c of cols) { if (!tables.has(c.table_name)) tables.set(c.table_name, new Map()); tables.get(c.table_name).set(c.column_name, c.data_type); }
  const pick = (m, ...names) => names.find((n) => m?.has(n)) ?? null;
  const uc = tables.get("users");
  const U = { ok: !!uc?.has("id"), nick: pick(uc, "nickname", "name", "handle", "username"), avatar: pick(uc, "avatar_url", "avatarurl", "avatar"), bio: pick(uc, "bio", "about"), deleted: pick(uc, "deleted_at") };
  const vc = tables.get("vessels");
  const V = { ok: !!vc?.has("id"), name: pick(vc, "name", "title"), topic: pick(vc, "topic", "description"), kind: pick(vc, "kind"), pub: pick(vc, "is_public", "public"), owner: pick(vc, "owner_id", "creator_id"), created: pick(vc, "created_at", "createdat"), lastPost: pick(vc, "last_post_at") };
  const membersTable = [...tables.keys()].find((t) => /vessel_member|vessel_users|membership/.test(t) && tables.get(t).has("vessel_id")) ?? null;
  const MC = membersTable ? { user: pick(tables.get(membersTable), "user_id", "member_id") } : null;
  const bizOk = tables.has("biz") && tables.has("biz_items"), marketOk = tables.has("market_listings"), eventsOk = tables.has("events") && tables.has("ticket_tiers");
  const optionalAuth = async (req) => { try { return (await auth(req)) || null; } catch { return null; } };

  // أشخاص بالدفعة (للبائعين والمضيفين)
  async function people(ids) {
    const out = new Map();
    const uniq = [...new Set(ids.filter(Boolean))];
    if (!uniq.length || !U.ok) return out;
    try {
      for (const r of (await pool.query(`SELECT id ${U.nick ? `, ${q(U.nick)} AS nickname` : ""} ${U.avatar ? `, ${q(U.avatar)} AS avatar_url` : ""} FROM users WHERE id = ANY($1::text[])`, [uniq])).rows) out.set(r.id, { id: r.id, nickname: r.nickname ?? "", avatarUrl: r.avatar_url ?? null });
    } catch { /* ignore */ }
    return out;
  }
  const personOf = (map, id) => map.get(id) ?? { id, nickname: "", avatarUrl: null };
  const bizOut = (b) => ({ id: b.id, name: b.name, nameAr: b.name_ar, category: b.category, sector: b.sector, address: b.address, hours: b.hours, lat: b.lat, lng: b.lng, verified: b.verified, official: b.official, color: b.color, logoUrl: b.logo_url ?? null,
    followers: Number(b.followers ?? 0), rating: b.rating == null ? null : Number(b.rating), ratingCount: Number(b.rating_count ?? 0), minPrice: b.min_price == null ? null : Number(b.min_price), itemsCount: Number(b.items_count ?? 0), views: Number(b.views ?? 0),
    openNow: isOpenNow(b.hours), distanceKm: roundKm(b.distance_km), matchedItem: b.matched_item ?? null });
  const BIZ_COLS = `b.*, (SELECT count(*) FROM biz_follows f WHERE f.biz_id=b.id) AS followers, (SELECT round(avg(rating)::numeric,1) FROM biz_reviews r WHERE r.biz_id=b.id) AS rating,
    (SELECT count(*) FROM biz_reviews r WHERE r.biz_id=b.id) AS rating_count, (SELECT min(price) FROM biz_items i WHERE i.biz_id=b.id AND i.active) AS min_price, (SELECT count(*) FROM biz_items i WHERE i.biz_id=b.id AND i.active) AS items_count`;
  const TIERS = "(SELECT COALESCE(json_agg(json_build_object('id',t.id,'name',t.name,'description',t.description,'price',t.price,'quantity',t.quantity,'sold',t.sold,'left',t.quantity-t.sold) ORDER BY t.sort, t.price), '[]'::json) FROM ticket_tiers t WHERE t.event_id=e.id) AS tiers";
  const eventOut = (e, pm, uid) => ({ id: e.id, host: personOf(pm, e.host_id), vesselId: e.vessel_id, title: e.title, description: e.description, startsAt: e.starts_at, endsAt: e.ends_at, placeName: e.place_name, lat: e.lat, lng: e.lng, cancelled: e.cancelled,
    tiers: (e.tiers ?? []).map((t) => ({ ...t, price: Number(t.price) })), going: Number(e.going ?? 0), myTickets: 0, isHost: e.host_id === uid, distanceKm: roundKm(e.distance_km) });
  const listingOut = (l, pm, uid) => ({ id: l.id, seller: personOf(pm, l.seller_id), kind: l.kind, category: l.category, title: l.title, description: l.description, price: Number(l.price), imageUrl: l.image_url, placeName: l.place_name, lat: l.lat, lng: l.lng, status: l.status, createdAt: l.created_at, mine: l.seller_id === uid, distanceKm: roundKm(l.distance_km) });
  const vesselOut = (v) => ({ id: v.id, name: v.name ?? "", topic: v.topic ?? "", kind: v.kind ?? "general", isPublic: v.is_public !== false, members: Number(v.members ?? 0), member: v.member === true, ownerId: v.owner_id ?? null, lastPostAt: v.last_post_at ?? null });
  const geoOf = (req) => { const lat = num(req.query?.lat), lng = num(req.query?.lng); const ok = Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180; return ok ? { lat, lng } : { lat: null, lng: null }; };

  async function searchVessels({ like, prefix, per, uid }) {
    if (!V.ok || !V.name) return [];
    const memberSel = MC ? `(SELECT count(*) FROM ${q(membersTable)} m WHERE m.vessel_id=v.id) AS members, ($4::text IS NOT NULL AND EXISTS (SELECT 1 FROM ${q(membersTable)} m WHERE m.vessel_id=v.id AND m.${q(MC.user)}::text=$4::text)) AS member` : "0 AS members, ($4::text IS NULL AND false) AS member";
    const visible = V.pub ? `(${q(V.pub)} = true OR ($4::text IS NOT NULL AND ${V.owner ? `${q(V.owner)}::text=$4::text` : "false"}) ${MC ? `OR EXISTS (SELECT 1 FROM ${q(membersTable)} m WHERE m.vessel_id=v.id AND m.${q(MC.user)}::text=$4::text)` : ""})` : "true";
    const rows = (await pool.query(`SELECT v.id, ${q(V.name)} AS name ${V.topic ? `, ${q(V.topic)} AS topic` : ""} ${V.kind ? `, ${q(V.kind)} AS kind` : ""} ${V.pub ? `, ${q(V.pub)} AS is_public` : ""} ${V.owner ? `, ${q(V.owner)} AS owner_id` : ""} ${V.lastPost ? `, ${q(V.lastPost)} AS last_post_at` : ""}, ${memberSel}
      FROM vessels v WHERE ${visible} AND (${NORM(q(V.name))} LIKE $1 ${V.topic ? `OR ${NORM(q(V.topic))} LIKE $1` : ""})
      ORDER BY (${NORM(q(V.name))} LIKE $2) DESC, members DESC LIMIT $3`, [like, prefix, per, uid])).rows;
    return rows.map(vesselOut);
  }

  app.get("/search", async (req) => {
    const uid = await optionalAuth(req);
    const raw = str(req.query?.q, 60);
    const type = TYPES.includes(req.query?.type) ? req.query.type : null;
    const per = type ? Math.max(1, Math.min(50, Number(req.query?.limit) || 30)) : 6;
    const { lat, lng } = geoOf(req);
    const out = { q: raw, people: [], vessels: [], biz: [], items: [], market: [], events: [] };
    const nq = normQ(raw);
    if (!nq) return out;
    const like = likeOf(raw), prefix = likeOf(raw).slice(1);   // بادئة الاسم تتقدم على الاحتواء
    const want = (t) => !type || type === t;
    const P = [like, prefix, per];                            // $1 like, $2 prefix, $3 limit
    if (want("people") && U.ok && U.nick) {
      const rows = (await pool.query(`SELECT id, ${q(U.nick)} AS nickname ${U.avatar ? `, ${q(U.avatar)} AS avatar_url` : ""} ${U.bio ? `, ${q(U.bio)} AS bio` : ""} FROM users
        WHERE ${U.deleted ? `${q(U.deleted)} IS NULL AND` : ""} (${NORM(q(U.nick))} LIKE $1 ${U.bio ? `OR ${NORM(q(U.bio))} LIKE $1` : ""})
        ORDER BY (${NORM(q(U.nick))} LIKE $2) DESC, ${q(U.nick)} LIMIT $3`, P)).rows;
      out.people = rows.map((r) => ({ id: r.id, nickname: r.nickname ?? "", avatarUrl: r.avatar_url ?? null, bio: r.bio ?? "" }));
    }
    if (want("vessels")) out.vessels = await searchVessels({ like, prefix, per, uid });
    if (want("biz") && bizOk) {
      const rows = (await pool.query(`SELECT x.*, ${DIST("$4", "$5", "x.lat", "x.lng")} AS distance_km FROM (SELECT ${BIZ_COLS},
          (SELECT i.title FROM biz_items i WHERE i.biz_id=b.id AND i.active AND ${NORM("i.title")} LIKE $1 ORDER BY i.sort LIMIT 1) AS matched_item
        FROM biz b WHERE b.active AND (${NORM("b.name")} LIKE $1 OR ${NORM("b.name_ar")} LIKE $1 OR ${NORM("b.sector")} LIKE $1 OR ${NORM("b.address")} LIKE $1
          OR EXISTS (SELECT 1 FROM biz_items i WHERE i.biz_id=b.id AND i.active AND ${NORM("i.title")} LIKE $1))) x
        ORDER BY (${NORM("x.name_ar")} LIKE $2 OR ${NORM("x.name")} LIKE $2) DESC, distance_km ASC NULLS LAST, x.followers DESC LIMIT $3`, [...P, lat, lng])).rows;
      out.biz = rows.map(bizOut);
    }
    if (want("items") && bizOk) {
      const rows = (await pool.query(`SELECT i.id, i.biz_id, i.kind, i.title, i.price, i.image_url, b.name, b.name_ar, b.category, ${DIST("$4", "$5", "b.lat", "b.lng")} AS distance_km
        FROM biz_items i JOIN biz b ON b.id=i.biz_id WHERE i.active AND b.active AND (${NORM("i.title")} LIKE $1 OR ${NORM("i.description")} LIKE $1)
        ORDER BY (${NORM("i.title")} LIKE $2) DESC, distance_km ASC NULLS LAST, i.price LIMIT $3`, [...P, lat, lng])).rows;
      out.items = rows.map((i) => ({ id: i.id, bizId: i.biz_id, bizName: i.name_ar || i.name, category: i.category, kind: i.kind, title: i.title, price: Number(i.price), imageUrl: i.image_url, distanceKm: roundKm(i.distance_km) }));
    }
    if (want("market") && marketOk) {
      const rows = (await pool.query(`SELECT l.*, ${DIST("$4", "$5", "l.lat", "l.lng")} AS distance_km FROM market_listings l WHERE l.status='active'
        AND (${NORM("l.title")} LIKE $1 OR ${NORM("l.description")} LIKE $1 OR ${NORM("l.category")} LIKE $1 OR ${NORM("COALESCE(l.place_name,'')")} LIKE $1)
        ORDER BY (${NORM("l.title")} LIKE $2) DESC, distance_km ASC NULLS LAST, l.created_at DESC LIMIT $3`, [...P, lat, lng])).rows;
      const pm = await people(rows.map((r) => r.seller_id));
      out.market = rows.map((l) => listingOut(l, pm, uid));
    }
    if (want("events") && eventsOk) {
      const rows = (await pool.query(`SELECT e.*, ${TIERS}, (SELECT count(DISTINCT user_id) FROM tickets t WHERE t.event_id=e.id AND t.status<>'refunded') AS going, ${DIST("$4", "$5", "e.lat", "e.lng")} AS distance_km
        FROM events e WHERE NOT e.cancelled AND e.starts_at >= now() - interval '6 hours'
        AND (${NORM("e.title")} LIKE $1 OR ${NORM("e.description")} LIKE $1 OR ${NORM("COALESCE(e.place_name,'')")} LIKE $1)
        ORDER BY (${NORM("e.title")} LIKE $2) DESC, e.starts_at LIMIT $3`, [...P, lat, lng])).rows;
      const pm = await people(rows.map((r) => r.host_id));
      out.events = rows.map((e) => eventOut(e, pm, uid));
    }
    return out;
  });

  // ---- الاكتشاف: مفتوح الآن قريباً، الأعلى تقييماً، فعاليات قادمة، دوائر نشطة
  app.get("/search/discover", async (req) => {
    const uid = await optionalAuth(req);
    const { lat, lng } = geoOf(req);
    const out = { openNow: [], topRated: [], events: [], vessels: [], located: lat != null };
    if (bizOk) {
      const rows = (await pool.query(`SELECT x.*, ${DIST("$1", "$2", "x.lat", "x.lng")} AS distance_km FROM (SELECT ${BIZ_COLS} FROM biz b WHERE b.active) x ORDER BY distance_km ASC NULLS LAST, x.followers DESC LIMIT 200`, [lat, lng])).rows.map(bizOut);
      out.openNow = rows.filter((b) => b.openNow === true).slice(0, 8);
      // المقيَّمة أولاً بالتقييم، ثم تُكمَّل القائمة بالأكثر متابعة ومشاهدة
      const rated = rows.filter((b) => b.rating != null).sort((a, b) => (b.rating - a.rating) || (b.ratingCount - a.ratingCount));
      const rest = rows.filter((b) => b.rating == null).sort((a, b) => (b.followers - a.followers) || (b.views - a.views));
      out.topRated = [...rated, ...rest].slice(0, 6);
    }
    if (eventsOk) {
      const rows = (await pool.query(`SELECT e.*, ${TIERS}, (SELECT count(DISTINCT user_id) FROM tickets t WHERE t.event_id=e.id AND t.status<>'refunded') AS going, ${DIST("$1", "$2", "e.lat", "e.lng")} AS distance_km
        FROM events e WHERE NOT e.cancelled AND e.starts_at >= now() - interval '6 hours' ORDER BY e.starts_at LIMIT 6`, [lat, lng])).rows;
      const pm = await people(rows.map((r) => r.host_id));
      out.events = rows.map((e) => eventOut(e, pm, uid));
    }
    if (V.ok && V.name) {
      try {
        const memberSel = MC ? `(SELECT count(*) FROM ${q(membersTable)} m WHERE m.vessel_id=v.id) AS members` : "0 AS members";
        const rows = (await pool.query(`SELECT v.id, ${q(V.name)} AS name ${V.topic ? `, ${q(V.topic)} AS topic` : ""} ${V.kind ? `, ${q(V.kind)} AS kind` : ""} ${V.pub ? `, ${q(V.pub)} AS is_public` : ""} ${V.lastPost ? `, ${q(V.lastPost)} AS last_post_at` : ""}, ${memberSel}
          FROM vessels v WHERE ${V.pub ? `${q(V.pub)} = true` : "true"} ${V.kind ? `AND (${q(V.kind)} IS NULL OR ${q(V.kind)} IN ('general',''))` : ""} ORDER BY ${V.lastPost ? `${q(V.lastPost)} DESC NULLS LAST,` : ""} members DESC LIMIT 6`)).rows;
        out.vessels = rows.map(vesselOut);
      } catch { out.vessels = []; }
    }
    return out;
  });

  app.get("/search/status", async () => ({ ok: true, users: U.ok, vessels: V.ok, membersTable, biz: bizOk, market: marketOk, events: eventsOk }));
}
