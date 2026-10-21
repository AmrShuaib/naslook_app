// تسجيل الدوائر الموثّقة (21 أكتوبر 2026، قرار المالك): ست خطوات تُظهر الدائرة على الخريطة فوراً (الشعار إلزامي)، نظام اكتمال واحد
// يقود كل دائرة (منشورة ← مكتملة ← موثّقة ← نشطة)، وتوثيق الكيان بسجل تجاري أو وثيقة عمل حر يعتمده المدير يدوياً من اللوحة
// (وثقة لاحقاً)؛ بوابة البيع في business.js لا تُفتح قبل الاعتماد. الدائرة المتنقلة (بلا مقر) لها نطاق خدمة ودبوس «هنا اليوم» مؤقت
// يظهر في الصف (row.js) ويُخبر أصحابها بطلبات السوق القريبة (market_plus.js عبر naslifeBizOwnersNear).
// تعتمد على business.js (الأعمدة، الإنشاء الموحّد naslifeBizCreate، المخرجات) وتُسجَّل بعد offers.js (عمود offer30d):
//   await app.register((await import("./biz_onboard.js")).default, { pool, auth });
import { CATEGORIES, CATEGORY_AR, NORM, normQ, likeOf, DIST, roundKm } from "./business.js";

const SLUG_RE = /^[a-z0-9-]{3,60}$/;
const PRESENCES = new Set(["fixed", "mobile"]);
const ROLES = new Set(["owner", "manager"]);
const ENTITY_KINDS = new Set(["cr", "freelance"]);
const ENTITY_AR = { cr: "سجل تجاري", freelance: "وثيقة عمل حر" };
export const DUP_KM = 3, MAX_DISTRICTS = 10, DEFAULT_RADIUS = 15, MIN_RADIUS = 2, MAX_RADIUS = 50, MAX_HERE_HOURS = 12, DEFAULT_HERE_HOURS = 4;
// صفحتا الاستعلام الرسميتان (يُستبدلان من إعدادات المنصة crLookupUrl / freelanceLookupUrl)
export const CR_LOOKUP_URL = "https://mc.gov.sa/ar/eservices/Pages/ServiceDetails.aspx?sID=91";
export const FREELANCE_LOOKUP_URL = "https://freelance.sa/certificate-validation";
// أوزان قائمة الاكتمال (المجموع 100)
export const WEIGHTS = { logo: 10, location: 10, phone: 10, hours: 10, description: 10, photos: 15, catalog: 15, entity: 20 };
export const NEED_PHOTOS = 3, NEED_ITEMS = 3, MIN_DESC = 20;

const str = (v, max) => String(v ?? "").trim().slice(0, max);
const num = (v) => { if (v == null || v === "") return null; const n = Number(v); return Number.isFinite(n) ? n : null; };
const geoOk = (lat, lng) => lat != null && lng != null && Math.abs(lat) <= 90 && Math.abs(lng) <= 180;
// رابط وسائط مرفوعة: مسار على الخادم أو https (http للتطوير المحلي)
const isMediaUrl = (v) => typeof v === "string" && /^(\/|https?:\/\/)\S+$/.test(v.trim()) && v.trim().length <= 500;
const latinDigits = (s) => String(s ?? "").replace(/[٠-٩]/g, (d) => String("٠١٢٣٤٥٦٧٨٩".indexOf(d))).replace(/[۰-۹]/g, (d) => String("۰۱۲۳۴۵۶۷۸۹".indexOf(d)));
/// جوال سعودي بأي صيغة شائعة (05…، 5…، +9665…، 009665…، 9665…) إلى +9665XXXXXXXX؛ null إن لم يكن جوالاً سعودياً
export function normalizePhone(v) {
  const s = latinDigits(v).replace(/[\s\-().]/g, "");
  const m = /^(?:\+966|00966|966)?0?5(\d{8})$/.exec(s);
  return m ? `+9665${m[1]}` : null;
}
const nPhotos = (n) => (n === 1 ? "صورة واحدة" : n === 2 ? "صورتين" : `${n} صور`);
const nItems = (n) => (n === 1 ? "صنفاً واحداً" : n === 2 ? "صنفين" : `${n} أصناف`);

export default async function bizOnboard(app, opts = {}) {
  const pool = opts.pool ?? globalThis.naslifePool ?? null;
  const auth = opts.auth ?? globalThis.naslifeAuth ?? null;
  if (!pool || !auth) throw new Error("biz_onboard: pool and auth are required");
  const H = () => globalThis.naslifeBizHelpers;
  if (!H() || typeof globalThis.naslifeBizCreate !== "function") throw new Error("biz_onboard: business.js must be registered first");

  const unauthorized = (reply) => reply.code(401).send({ error: "auth" });
  const bad = (reply, code, error, extra = {}) => reply.code(code).send({ error, ...extra });
  const isAdmin = async (uid) => { try { return !!(await H().isAdmin(uid)); } catch { return false; } };
  const notify = async (ids, payload) => { try { await globalThis.naslifeNotify?.(ids, payload); } catch { /* ignore */ } };
  const notifyAdmins = async (payload) => { try { await globalThis.naslifeNotifyAdmins?.(payload); } catch { /* ignore */ } };
  const audit = (uid, action, target, details) => { try { globalThis.naslifeAudit?.(uid, action, target, details)?.catch?.(() => {}); } catch { /* ignore */ } };
  const settings = () => globalThis.naslifeSettings ?? {};
  const lookupUrl = (kind) => (kind === "cr" ? str(settings().crLookupUrl, 500) || CR_LOOKUP_URL : kind === "freelance" ? str(settings().freelanceLookupUrl, 500) || FREELANCE_LOOKUP_URL : null);
  const person = async (id) => { try { const u = (await pool.query("SELECT id, nickname, avatar_url FROM users WHERE id=$1", [id])).rows[0]; return u ? { id: u.id, nickname: u.nickname ?? "", avatarUrl: u.avatar_url ?? null } : { id, nickname: "", avatarUrl: null }; } catch { return { id, nickname: "", avatarUrl: null }; } };
  const bizName = (b) => b?.name_ar || b?.name || b?.id || "";
  const load = (id, uid) => globalThis.naslifeBizLoadFull(id, uid);
  const out = (b, extra) => globalThis.naslifeBizOut(b, extra);
  let trgm = null;
  const hasTrgm = async () => { if (trgm == null) { try { trgm = (await pool.query("SELECT 1 FROM pg_extension WHERE extname='pg_trgm'")).rowCount > 0; } catch { trgm = false; } } return trgm; };
  /// يحمّل الدائرة (بأعمدتها المحسوبة) ويتحقق من الصلاحية: manage = مالك/مدير/مدير النظام، operate = + موظف
  async function guard(req, reply, level) {
    const uid = await auth(req); if (!uid) { unauthorized(reply); return null; }
    if (!SLUG_RE.test(req.params.id ?? "")) { bad(reply, 404, "not-found"); return null; }
    const b = await load(req.params.id, uid);
    if (!b) { bad(reply, 404, "not-found"); return null; }
    const role = await H().roleFor(uid, b);
    if (!(level === "manage" ? H().canManage(role) : H().canOperate(role))) { bad(reply, 403, "forbidden"); return null; }
    return { uid, b, role };
  }

  // ---- الاكتمال: قائمة موزونة ومستوى تراكمي وخطوة تالية واحدة بتبويبها في لوحة الدائرة
  const verView = (b) => { const v = H().verOf(b); return { status: H().verStatus(b), entityKind: b.entity_kind ?? null, reason: v.reason ?? null, submittedAt: v.submittedAt ?? null, reviewedAt: v.reviewedAt ?? null }; };
  function completeness(b) {
    const vs = H().verStatus(b), photos = Number(b.photos_count ?? 0), items = Number(b.items_count ?? 0), mobile = b.presence === "mobile";
    const checks = {
      logo: !!b.logo_url, location: geoOk(num(b.lat), num(b.lng)), phone: !!str(b.phone, 30), hours: H().hoursOk(b), description: str(b.description, 4000).length >= MIN_DESC,
      photos: { have: photos, need: NEED_PHOTOS }, catalog: { have: items, need: NEED_ITEMS }, entity: { status: vs },
      phoneVerified: b.phone_verified === true, offer30d: b.offer30d === true, post30d: b.post30d === true,
    };
    const percent = (checks.logo ? WEIGHTS.logo : 0) + (checks.location ? WEIGHTS.location : 0) + (checks.phone ? WEIGHTS.phone : 0) + (checks.hours ? WEIGHTS.hours : 0)
      + (checks.description ? WEIGHTS.description : 0) + Math.round(WEIGHTS.photos * Math.min(1, photos / NEED_PHOTOS)) + Math.round(WEIGHTS.catalog * Math.min(1, items / NEED_ITEMS))
      + (vs === "approved" ? WEIGHTS.entity : 0);
    const steps = [
      { key: "logo", done: checks.logo, title: "أضف شعار الدائرة", hint: "الشعار هو ما يراه الناس على الخريطة وفي الصف", minutes: 2, tab: "profile" },
      { key: "location", done: checks.location, title: mobile ? "حدّد مركز نطاق خدمتك" : "ثبّت موقع الدائرة على الخريطة", hint: "من زر «موقعي» في الملف أو بتحريك الدبوس", minutes: 1, tab: "profile" },
      { key: "phone", done: checks.phone, title: "أضف رقم الجوال", hint: "يظهر للعملاء للتواصل والطلب", minutes: 1, tab: "profile" },
      { key: "hours", done: checks.hours, title: mobile ? "اكتب متى تكون متاحاً" : "أضف ساعات العمل", hint: mobile ? "مثل «يومياً 4 م – 11 م» أو أيام الأسبوع التي تخدم فيها" : "مثل «السبت – الخميس 9:00 ص – 11:00 م» ليظهر «مفتوح الآن»", minutes: 2, tab: "profile" },
      { key: "description", done: checks.description, title: "اكتب وصفاً لدائرتك", hint: `${MIN_DESC} حرفاً على الأقل: ماذا تقدّم ولمن`, minutes: 3, tab: "profile" },
      { key: "photos", done: photos >= NEED_PHOTOS, title: `أضف ${nPhotos(Math.max(1, NEED_PHOTOS - photos))}`, hint: b.cover_url ? "صور الأصناف والمنشورات تُحتسب مع الشعار والغلاف" : "ابدأ بصورة الغلاف ثم صور الأصناف", minutes: 5, tab: b.cover_url ? "catalog" : "profile" },
      { key: "catalog", done: items >= NEED_ITEMS, title: `أضف ${nItems(Math.max(1, NEED_ITEMS - items))} إلى الكتالوج`, hint: "أصناف بأسعار وصور حتى يطلب الناس من دائرتك", minutes: 10, tab: "catalog" },
      { key: "entity", done: vs === "approved", title: vs === "pending" ? "التوثيق قيد المراجعة" : vs === "rejected" ? "أعد رفع وثيقة الكيان" : "وثّق دائرتك بالسجل التجاري أو وثيقة العمل الحر", hint: vs === "pending" ? "سنخبرك فور مراجعة الإدارة" : vs === "rejected" ? (H().verOf(b).reason || "راجع سبب الرفض وأعد الإرسال") : "البيع والحجز وربط الدفع تُفتح بعد الاعتماد", minutes: 5, tab: "verify" },
      { key: "offer30d", done: checks.offer30d, title: "أطلق عرضاً", hint: "عرض نشط خلال آخر 30 يوماً يُبقي دائرتك «نشطة»", minutes: 3, tab: "offers" },
      { key: "post30d", done: checks.post30d, title: "انشر تحديثاً", hint: "منشور خلال آخر 30 يوماً يُبقي دائرتك «نشطة»", minutes: 2, tab: "posts" },
    ];
    const next = steps.find((s) => !s.done) ?? null;
    return { tier: H().tierOf(b), percent: Math.max(0, Math.min(100, percent)), canSell: vs === "approved", checks,
      next: next ? { key: next.key, title: next.title, hint: next.hint, minutes: next.minutes, tab: next.tab } : null, verification: verView(b) };
  }

  // ---- خيارات التسجيل للتطبيق (عامة): الفئات بأسمائها العربية وحدود النطاق وروابط الاستعلام
  app.get("/biz/register/options", async () => ({
    categories: [...CATEGORIES].map((key) => ({ key, label: CATEGORY_AR[key] ?? key })), presences: [...PRESENCES], roles: [...ROLES], entityKinds: [...ENTITY_KINDS],
    radiusKm: { min: MIN_RADIUS, max: MAX_RADIUS, default: DEFAULT_RADIUS }, maxDistricts: MAX_DISTRICTS, hereHours: { max: MAX_HERE_HOURS, default: DEFAULT_HERE_HOURS },
    needs: { photos: NEED_PHOTOS, catalog: NEED_ITEMS, description: MIN_DESC }, weights: WEIGHTS, lookup: { cr: lookupUrl("cr"), freelance: lookupUrl("freelance") },
  }));

  // ---- فحص التكرار قبل التسجيل: اسم مشابه (بعد التطبيع، أو تشابه ثلاثي إن توفّر pg_trgm) خلال 3 كم، خمسة على الأكثر
  app.get("/biz/register/check", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const name = str(req.query?.name, 60), lat = num(req.query?.lat), lng = num(req.query?.lng);
    if (name.length < 2 || !geoOk(lat, lng)) return bad(reply, 400, "bad-query");
    const q = normQ(name), sim = (await hasTrgm()) ? ` OR similarity(${NORM("b.name_ar")}, $4) > 0.45 OR similarity(${NORM("b.name")}, $4) > 0.45` : "";
    const r = await pool.query(`SELECT b.id, b.name, b.name_ar, b.category, b.owner_id, b.logo_url, ${DIST("$2", "$3", "b.lat", "b.lng")} AS distance_km FROM biz b
      WHERE b.active AND NOT b.hidden AND ${DIST("$2", "$3", "b.lat", "b.lng")} <= ${DUP_KM}
        AND (${NORM("b.name")} LIKE $1 OR ${NORM("b.name_ar")} LIKE $1
          OR (length(${NORM("b.name_ar")}) >= 2 AND $4 LIKE '%' || ${NORM("b.name_ar")} || '%') OR (length(${NORM("b.name")}) >= 2 AND $4 LIKE '%' || ${NORM("b.name")} || '%')${sim})
      ORDER BY distance_km ASC LIMIT 5`, [likeOf(name), lat, lng, q]);
    return { duplicates: r.rows.map((b) => ({ id: b.id, name: b.name, nameAr: b.name_ar, category: b.category, distanceKm: roundKm(b.distance_km), ownerId: b.owner_id ?? null, logoUrl: b.logo_url ?? null })) };
  });

  // ---- التسجيل بست خطوات: الفئة، الاسم، الشعار (إلزامي)، الحضور والموقع (أو مركز النطاق ونصف قطره)، الجوال السعودي، الدور
  app.post("/biz/register", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    let susp = false; try { susp = !!(await H().isSuspended(uid)); } catch { susp = false; }
    if (susp) return bad(reply, 403, "suspended");
    const b = req.body ?? {};
    const category = str(b.category, 30); if (!CATEGORIES.has(category)) return bad(reply, 400, "bad-category");
    const nameAr = str(b.nameAr, 60); if (nameAr.length < 2) return bad(reply, 400, "bad-name");
    const name = str(b.name, 60);
    const logoUrl = str(b.logoUrl, 500); if (!isMediaUrl(logoUrl)) return bad(reply, 400, "logo-required");
    const presence = str(b.presence, 10); if (!PRESENCES.has(presence)) return bad(reply, 400, "bad-presence");
    const lat = num(b.lat), lng = num(b.lng); if (!geoOk(lat, lng)) return bad(reply, 400, "bad-location");
    let radiusKm = DEFAULT_RADIUS, districts = [];
    if (presence === "mobile") {
      if (b.radiusKm != null && b.radiusKm !== "") { radiusKm = num(b.radiusKm); if (radiusKm == null || radiusKm < MIN_RADIUS || radiusKm > MAX_RADIUS) return bad(reply, 400, "bad-radius"); radiusKm = Math.round(radiusKm * 10) / 10; }
      districts = (Array.isArray(b.districts) ? b.districts : []).map((d) => str(d, 40)).filter(Boolean).slice(0, MAX_DISTRICTS);
    }
    const phone = normalizePhone(b.phone); if (!phone) return bad(reply, 400, "bad-phone");
    const role = b.role == null ? "owner" : str(b.role, 10); if (!ROLES.has(role)) return bad(reply, 400, "bad-role");
    let created;
    try {
      created = await globalThis.naslifeBizCreate(uid, { name, nameAr, category, lat, lng, phone, logoUrl, hours: str(b.hours, 120), description: str(b.description, 2000), address: str(b.address, 200) },
        { presence, service_area: presence === "mobile" ? JSON.stringify({ lat, lng, radiusKm, districts }) : null, owner_role: role, registered_at: new Date(), verification: JSON.stringify({ status: "none" }), active: true });
    } catch (e) {
      if (e.code === "suspended") return bad(reply, 403, "suspended");
      if (e.code === "banned-words") return bad(reply, 400, "banned-words", { word: e.word });
      if (e.code === "bad-name" || e.code === "bad-location") return bad(reply, 400, e.code);
      if (e.code === "too-many") return bad(reply, 409, "too-many");
      throw e;
    }
    return { biz: out(created.row, { myRole: "owner" }), completeness: completeness(created.row) };
  });

  // ---- الاكتمال (المالك والمدير والموظف ومدير النظام)
  app.get("/biz/:id/completeness", async (req, reply) => {
    const g = await guard(req, reply, "operate"); if (!g) return;
    return completeness(g.b);
  });

  // ---- التوثيق: ما أرسله الطاقم (رقم الكيان ووثيقته لا يظهران إلا هنا ولمدير النظام)
  app.get("/biz/:id/verification", async (req, reply) => {
    const g = await guard(req, reply, "manage"); if (!g) return;
    const v = H().verOf(g.b);
    return { ...verView(g.b), entityNumber: g.b.entity_number ?? null, docUrl: v.docUrl ?? null, canSell: H().verStatus(g.b) === "approved", lookupUrl: lookupUrl(g.b.entity_kind) };
  });
  // إرسال الوثيقة (مالك/مدير): سجل تجاري برقم من 10 أرقام أو وثيقة عمل حر برقم من 8–20 حرفاً/رقماً، والوثيقة المرفوعة إلزامية؛
  // يجوز الإرسال من جديد بعد الرفض أو أثناء الانتظار (يستبدل الطلب)، ولا يجوز بعد الاعتماد
  app.post("/biz/:id/verification", async (req, reply) => {
    const g = await guard(req, reply, "manage"); if (!g) return;
    const body = req.body ?? {};
    const entityKind = str(body.entityKind, 10); if (!ENTITY_KINDS.has(entityKind)) return bad(reply, 400, "bad-entity");
    const entityNumber = latinDigits(str(body.entityNumber, 40)).replace(/[\s\-]/g, "");
    if (entityKind === "cr" ? !/^\d{10}$/.test(entityNumber) : !/^[A-Za-z0-9]{8,20}$/.test(entityNumber)) return bad(reply, 400, "bad-number");
    const docUrl = str(body.docUrl, 500); if (!isMediaUrl(docUrl)) return bad(reply, 400, "doc-required");
    if (H().verStatus(g.b) === "approved") return bad(reply, 409, "already-approved");
    const verification = { status: "pending", docUrl, submittedAt: new Date().toISOString(), submittedBy: g.uid };
    await pool.query("UPDATE biz SET entity_kind=$2, entity_number=$3, verification=$4::jsonb, verified=false, verified_at=NULL, updated_at=now() WHERE id=$1", [g.b.id, entityKind, entityNumber, JSON.stringify(verification)]);
    await notifyAdmins({ kind: "biz_verification", title: "طلب توثيق دائرة", body: `${bizName(g.b)} · ${ENTITY_AR[entityKind]} ${entityNumber}`, data: { bizId: g.b.id } });
    return { status: "pending", verification: { ...verView({ ...g.b, verification, entity_kind: entityKind }), entityNumber, docUrl } };
  });

  // ---- الإدارة: قائمة طلبات التوثيق مع رابط الاستعلام الرسمي، والقرار بالاعتماد أو الرفض بسبب
  app.get("/adminapi/biz/verifications", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!(await isAdmin(uid))) return bad(reply, 403, "admin-only");
    const want = str(req.query?.status, 10) || "pending";
    const statuses = want === "all" ? ["pending", "approved", "rejected"] : ["pending", "approved", "rejected"].includes(want) ? [want] : null;
    if (!statuses) return bad(reply, 400, "bad-status");
    const r = await pool.query("SELECT * FROM biz WHERE verification->>'status' = ANY($1::text[]) ORDER BY COALESCE((verification->>'submittedAt')::timestamptz, created_at) DESC LIMIT 200", [statuses]);
    return Promise.all(r.rows.map(async (b) => {
      const v = H().verOf(b);
      return { bizId: b.id, name: b.name, nameAr: b.name_ar, category: b.category, logoUrl: b.logo_url ?? null, presence: b.presence === "mobile" ? "mobile" : "fixed", ownerId: b.owner_id ?? null,
        owner: b.owner_id ? await person(b.owner_id) : null, entityKind: b.entity_kind ?? null, entityNumber: b.entity_number ?? null, docUrl: v.docUrl ?? null, submittedAt: v.submittedAt ?? null,
        status: H().verStatus(b), reason: v.reason ?? null, reviewedAt: v.reviewedAt ?? null, reviewedBy: v.reviewedBy ?? null, lookupUrl: lookupUrl(b.entity_kind) };
    }));
  });
  app.post("/adminapi/biz/:id/verification/:decision", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!(await isAdmin(uid))) return bad(reply, 403, "admin-only");
    const approve = req.params.decision === "approve";
    if (!approve && req.params.decision !== "reject") return bad(reply, 400, "bad-decision");
    if (!SLUG_RE.test(req.params.id ?? "")) return bad(reply, 404, "not-found");
    const b = (await pool.query("SELECT * FROM biz WHERE id=$1", [req.params.id])).rows[0];
    if (!b) return bad(reply, 404, "not-found");
    const reason = str(req.body?.reason, 300);
    if (!approve && reason.length < 3) return bad(reply, 400, "bad-reason");
    const cur = H().verStatus(b);
    // الرفض يحتاج طلباً معلّقاً (أو اعتماداً يُسحب)؛ الاعتماد جائز دائماً (توثيق يدوي أو عبر وثقة لاحقاً)
    if (!approve && cur !== "pending" && cur !== "approved") return bad(reply, 409, "not-pending");
    const v = { ...H().verOf(b), status: approve ? "approved" : "rejected", reviewedBy: uid, reviewedAt: new Date().toISOString(), reason: approve ? null : reason };
    await pool.query("UPDATE biz SET verification=$2::jsonb, verified=$3, verified_at=CASE WHEN $3::bool THEN now() ELSE NULL END, updated_at=now() WHERE id=$1", [b.id, JSON.stringify(v), approve]);
    if (b.owner_id) {
      await notify(b.owner_id, approve
        ? { kind: "biz_verified", title: "تم توثيق دائرتك", body: `${bizName(b)} موثّقة الآن: البيع والحجز مفتوحان`, data: { bizId: b.id } }
        : { kind: "biz_verification_rejected", title: "لم يُقبل توثيق دائرتك", body: `${bizName(b)}: ${reason}`, data: { bizId: b.id, reason } });
    }
    audit(uid, approve ? "biz.verification.approve" : "biz.verification.reject", b.id, { entityKind: b.entity_kind ?? null, entityNumber: b.entity_number ?? null, reason: approve ? null : reason });
    return { ok: true, status: v.status };
  });

  // ---- دبوس «هنا اليوم» للدائرة المتنقلة (المالك والمدير والموظف): موقع مؤقت لساعات يظهر على الخريطة وفي الصف ثم يزول وحده
  app.post("/biz/:id/here", async (req, reply) => {
    const g = await guard(req, reply, "operate"); if (!g) return;
    if (g.b.presence !== "mobile") return bad(reply, 409, "not-mobile");
    const lat = num(req.body?.lat), lng = num(req.body?.lng); if (!geoOk(lat, lng)) return bad(reply, 400, "bad-location");
    const hours = req.body?.hours == null || req.body.hours === "" ? DEFAULT_HERE_HOURS : num(req.body.hours);
    if (hours == null || hours < 1 || hours > MAX_HERE_HOURS) return bad(reply, 400, "bad-hours");
    const now = Date.now();
    const here = { lat, lng, until: new Date(now + hours * 3600000).toISOString(), setAt: new Date(now).toISOString() };
    await pool.query("UPDATE biz SET here=$2::jsonb, updated_at=now() WHERE id=$1", [g.b.id, JSON.stringify(here)]);
    return { here: { lat, lng, until: here.until } };
  });
  app.delete("/biz/:id/here", async (req, reply) => {
    const g = await guard(req, reply, "operate"); if (!g) return;
    await pool.query("UPDATE biz SET here=NULL, updated_at=now() WHERE id=$1", [g.b.id]);
    return { ok: true };
  });

  // ---- لطلبات السوق (market_plus.js): أصحاب الدوائر المتنقلة النشطة التي يغطي نطاق خدمتها نقطة ما
  globalThis.naslifeBizOwnersNear = async (lat, lng) => {
    const la = num(lat), ln = num(lng); if (!geoOk(la, ln)) return [];
    const r = await pool.query(`SELECT DISTINCT b.owner_id FROM biz b WHERE b.active AND NOT b.hidden AND b.owner_id IS NOT NULL AND b.presence='mobile'
      AND ${DIST("$1", "$2", "b.lat", "b.lng")} <= COALESCE((b.service_area->>'radiusKm')::float8, ${DEFAULT_RADIUS}) LIMIT 50`, [la, ln]);
    return r.rows.map((x) => x.owner_id);
  };

  app.get("/biz/onboard/status", async () => ({ ok: true, categories: CATEGORIES.size, trgm: await hasTrgm(), lookup: { cr: lookupUrl("cr"), freelance: lookupUrl("freelance") } }));
}
