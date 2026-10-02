// «حجز الفنادق» (server/hotels.js): ربط دائرة فندقية بفندق حقيقي لدى Nuitee Connect (LiteAPI) وحجز غرفة من داخل ناس لايف
// (قرار المالك 1 أكتوبر 2026: تجربة على دائرة واحدة في جدة). كان المزوّد Amadeus Self-Service لكنه أُغلق نهائياً في 17 يوليو 2026،
// وLiteAPI هو البديل بتسجيل ذاتي: مفتاح واحد (ترويسة X-API-Key)، مفتاح تجريبي مجاني يغطي البحث والحجز (الدفع يُحاكى بـ
// ACC_CREDIT_CARD بلا تحصيل)، ومفتاح إنتاج بعد ربط بطاقة. المفتاح والبيئة (test|live) من لوحة الإدارة (جدول hotel_settings) ولهما
// الأولوية على LITEAPI_KEY/LITEAPI_ENV. في البيئة الحية الحجز مرفوض (live-payment-pending) حتى يُعتمد تحصيل كل حجز من المستخدم
// عبر ميسر، لأن LiteAPI يحصّل من حساب ناس لايف لا من الضيف. لا بطاقة ضيف تمر عبرنا. نداءات الشبكة عبر globalThis.naslifeHotelFetch
// (للاختبار) أو fetch.
// التسجيل في register.txt:
//   await app.register((await import("./hotels.js")).default, { pool, auth });
import crypto from "node:crypto";

export const PROVIDER = "liteapi";
const DATA_BASE = "https://api.liteapi.travel/v3.0", BOOK_BASE = "https://book.liteapi.travel/v3.0";
const MAX_NIGHTS = 30, MAX_GUESTS = 9;
const DAY = 86400000;
// رموز المدن التي يكتبها المدير في اللوحة → أسماء المدن لدى LiteAPI (ويقبل اسم المدينة مباشرة)
const CITY_BY_CODE = { JED: "Jeddah", DMM: "Dammam", RUH: "Riyadh", MED: "Medina", KHB: "Al Khobar", JUB: "Jubail", TIF: "Taif", AHB: "Abha", TUU: "Tabuk", YNB: "Yanbu", ELQ: "Buraydah", HAS: "Hofuf", MAK: "Makkah" };

const str = (v, max = 200) => String(v ?? "").trim().slice(0, max);
const num = (v) => { const n = Number(v); return Number.isFinite(n) ? n : null; };
// معامل مكرّر في الرابط يصل مصفوفة: نأخذ أوله
const one = (v) => (Array.isArray(v) ? v[0] : v);
const clampInt = (v, lo, hi, d) => { const n = Math.round(Number(one(v))); return Number.isFinite(n) ? Math.min(hi, Math.max(lo, n)) : d; };
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const dayMs = (s) => { s = one(s); if (!DATE_RE.test(String(s ?? ""))) return NaN; const t = Date.parse(`${s}T00:00:00Z`); return Number.isFinite(t) ? t : NaN; };
const todayKey = (now = Date.now()) => new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Riyadh", year: "numeric", month: "2-digit", day: "2-digit" }).format(now);
const sarText = (n) => (Number.isInteger(n) ? n.toLocaleString("en-US") : n.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })) + " ر.س";
const moneyText = (amount, currency) => (currency === "SAR" ? sarText(amount) : `${amount.toLocaleString("en-US", { maximumFractionDigits: 2 })} ${currency}`);
const MONTHS_AR = ["يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو", "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر"];
const dateAr = (iso) => { const t = new Date(String(iso ?? "").replace(" ", "T") + (/[zZ]|[+-]\d\d:?\d\d$/.test(String(iso ?? "")) ? "" : "Z")); if (Number.isNaN(t.getTime())) return ""; const p = Object.fromEntries(new Intl.DateTimeFormat("en-US", { timeZone: "Asia/Riyadh", day: "numeric", month: "numeric" }).formatToParts(t).map((x) => [x.type, x.value])); return `${p.day} ${MONTHS_AR[Number(p.month) - 1]}`; };
const BOARD_AR = { RO: "الغرفة فقط", BB: "مع الإفطار", BI: "مع الإفطار", HB: "نصف إقامة", FB: "إقامة كاملة", AI: "شامل", TI: "شامل", BD: "إفطار وعشاء", BL: "إفطار وغداء", DI: "عشاء", LU: "غداء", LD: "غداء وعشاء" };
const boardAr = (code, name) => BOARD_AR[String(code ?? "").replace(/\d+$/, "")] ?? str(name, 40);
const PAYMENT_TEXT = { test: "تجربة بلا دفع (بيئة الاختبار)", live: "الدفع عند التأكيد عبر ناس لايف" };

/// سياسة الإلغاء من شكل LiteAPI: {refundableTag:'RFN'|'NRFN', cancelPolicyInfos:[{cancelTime, amount}]}
export function cancelInfo(pol) {
  const tag = String(pol?.refundableTag ?? "").toUpperCase();
  const infos = Array.isArray(pol?.cancelPolicyInfos) ? pol.cancelPolicyInfos : [];
  const deadline = infos.map((c) => c.cancelTime).filter(Boolean).sort()[0] ?? null;
  if (tag === "NRFN") return { refundable: false, cancelBy: null, cancelText: "غير قابل للاسترداد" };
  if (deadline) return { refundable: true, cancelBy: deadline, cancelText: `إلغاء مجاني حتى ${dateAr(deadline)}` };
  return { refundable: tag === "RFN" ? true : null, cancelBy: null, cancelText: tag === "RFN" ? "قابل للإلغاء" : "سياسة الإلغاء بحسب الفندق" };
}
const amountOf = (v) => (Array.isArray(v) ? v[0] : v) ?? null;

/// تطبيع عرض غرفة من LiteAPI (roomTypes[i] من /hotels/rates) إلى بطاقة عربية واحدة: السعر المعروض هو سعر البيع المقترح
/// (suggestedSellingPrice) وإلا سعر العرض؛ ما ندفعه نحن للمزوّد (offerRetailRate) يُحفظ في cost ولا يُعرض.
export function normalizeOffer(rt, nights, env = "test") {
  const rate = Array.isArray(rt?.rates) ? rt.rates[0] ?? {} : {};
  const retail = amountOf(rt?.offerRetailRate) ?? amountOf(rate.retailRate?.total) ?? null;
  const ssp = amountOf(rt?.suggestedSellingPrice) ?? amountOf(rate.retailRate?.suggestedSellingPrice) ?? null;
  const pick = ssp && num(ssp.amount) > 0 ? ssp : retail;
  const currency = str(pick?.currency, 3) || "SAR";
  const raw = num(pick?.amount) ?? 0;
  const total = currency === "SAR" ? Math.round(raw * 100) : raw;
  const costRaw = num(retail?.amount) ?? raw;
  const perNight = nights > 0 ? raw / nights : raw;
  const c = cancelInfo(rate.cancellationPolicies);
  return {
    id: str(rt?.offerId, 2000), roomName: str(rate.name, 120) || "غرفة", roomCode: str(rate.rateId, 20), bedType: "", beds: null, description: str(String(rate.remarks ?? "").replace(/<[^>]+>/g, " ").replace(/\s+/g, " "), 300),
    boardType: boardAr(rate.boardType, rate.boardName), total, currency, totalText: moneyText(raw, currency), perNightText: `${moneyText(Math.round(perNight * 100) / 100, currency)}/ليلة`,
    cost: currency === "SAR" ? Math.round(costRaw * 100) : costRaw, maxOccupancy: num(rate.maxOccupancy), ...c, paymentType: "prepay", paymentText: PAYMENT_TEXT[env] ?? PAYMENT_TEXT.test, guests: num(rate.adultCount),
  };
}

export default async function hotels(app, opts) {
  const { pool, auth } = opts;
  const fetchImpl = (...a) => (globalThis.naslifeHotelFetch ?? globalThis.fetch)(...a);
  const unauthorized = (reply) => reply.code(401).send({ error: "auth" });
  const bad = (reply, code, error, extra = {}) => reply.code(code).send({ error, ...extra });
  const isAdmin = async (uid) => { try { return !!(await globalThis.naslifeIsAdmin?.(uid)); } catch { return false; } };
  const notify = async (ids, payload) => { try { await globalThis.naslifeNotify?.(ids, payload); } catch { /* ignore */ } };

  await pool.query(`
    CREATE TABLE IF NOT EXISTS hotel_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_by TEXT, updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE TABLE IF NOT EXISTS biz_hotel_links (biz_id TEXT PRIMARY KEY, hotel_id TEXT NOT NULL, hotel_name TEXT NOT NULL DEFAULT '', city_code TEXT NOT NULL DEFAULT '',
      lat DOUBLE PRECISION, lng DOUBLE PRECISION, linked_by TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE TABLE IF NOT EXISTS hotel_bookings (id UUID PRIMARY KEY, user_id TEXT NOT NULL, biz_id TEXT NOT NULL, hotel_id TEXT NOT NULL, hotel_name TEXT NOT NULL DEFAULT '',
      offer_id TEXT NOT NULL, order_id TEXT, confirmation TEXT, status TEXT NOT NULL DEFAULT 'pending', check_in DATE NOT NULL, check_out DATE NOT NULL, nights INT NOT NULL,
      adults INT NOT NULL DEFAULT 1, rooms INT NOT NULL DEFAULT 1, room_name TEXT NOT NULL DEFAULT '', total NUMERIC NOT NULL DEFAULT 0, currency TEXT NOT NULL DEFAULT 'SAR',
      guest_name TEXT NOT NULL DEFAULT '', guest_email TEXT NOT NULL DEFAULT '', guest_phone TEXT NOT NULL DEFAULT '', cancel_text TEXT NOT NULL DEFAULT '', env TEXT NOT NULL DEFAULT 'test',
      raw JSONB NOT NULL DEFAULT '{}', created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    ALTER TABLE hotel_bookings ADD COLUMN IF NOT EXISTS provider TEXT NOT NULL DEFAULT 'liteapi';
    ALTER TABLE hotel_bookings ADD COLUMN IF NOT EXISTS cost NUMERIC NOT NULL DEFAULT 0;
    CREATE INDEX IF NOT EXISTS hotel_bookings_user ON hotel_bookings(user_id, created_at DESC);
  `);

  // ---- الإعدادات: اللوحة أولاً ثم البيئة (مفتاح واحد)
  const panel = { apiKey: "", env: "", updatedAt: null, updatedBy: null };
  const loadPanel = async () => {
    const rows = (await pool.query("SELECT key, value, updated_by, updated_at FROM hotel_settings")).rows;
    panel.apiKey = ""; panel.env = ""; panel.updatedAt = null; panel.updatedBy = null;
    for (const r of rows) { if (r.key in panel && typeof panel[r.key] === "string") panel[r.key] = r.value; if (!panel.updatedAt || r.updated_at > panel.updatedAt) { panel.updatedAt = r.updated_at; panel.updatedBy = r.updated_by; } }
  };
  await loadPanel();
  const CFG = () => {
    const env = { apiKey: process.env.LITEAPI_KEY ?? "", env: process.env.LITEAPI_ENV ?? "" };
    const source = panel.apiKey ? "panel" : env.apiKey ? "env" : null;
    const apiKey = source === "panel" ? panel.apiKey : source === "env" ? env.apiKey : "";
    const mode = (source === "panel" ? panel.env : env.env) === "live" ? "live" : "test";
    return { configured: !!source, source, env: mode, apiKey, envPresent: !!env.apiKey };
  };
  const hint = (k) => (k ? `${k.slice(0, 4)}…${k.slice(-4)}` : "");

  // ---- نداء LiteAPI: المفتاح في الترويسة، والأخطاء بشكل {error:{code,message,description}}
  const api = async (method, url, { query, body, timeoutMs = 20000 } = {}) => {
    const c = CFG(); if (!c.configured) throw Object.assign(new Error("hotel-disabled"), { code: "hotel-disabled" });
    const full = `${url}${query ? "?" + new URLSearchParams(Object.fromEntries(Object.entries(query).filter(([, v]) => v != null && v !== ""))).toString() : ""}`;
    const r = await fetchImpl(full, { method, headers: { "X-API-Key": c.apiKey, accept: "application/json", ...(body ? { "content-type": "application/json" } : {}) }, body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(timeoutMs) });
    let j = null; try { j = await r.json(); } catch { /* 204 بلا جسم */ }
    return { ok: r.ok, status: r.status, json: j, err: j?.error ?? null };
  };
  const errText = (res) => str([res.err?.message, res.err?.description].filter(Boolean).join(": ") || `provider ${res.status}`, 300);
  const isNoAvailability = (res) => res.status === 204 || Number(res.err?.code) === 2001 || /no availability|not available|sold out/i.test(String(res.err?.message ?? res.err?.description ?? ""));
  const isAuthError = (res) => res.status === 401 || res.status === 403;
  const providerFail = (reply, e) => bad(reply, e.code === "hotel-disabled" ? 503 : 502, e.code === "hotel-disabled" ? "hotel-disabled" : "provider-error", { message: str(e.message, 200) });

  // ---- الروابط
  const linkOf = async (bizId) => (await pool.query("SELECT * FROM biz_hotel_links WHERE biz_id=$1", [bizId])).rows[0] ?? null;
  const bizOf = async (bizId) => { try { return (await pool.query("SELECT id, name, name_ar, owner_id, category, lat, lng FROM biz WHERE id=$1", [bizId])).rows[0] ?? null; } catch { return null; } };
  const linkOut = (l, c = CFG()) => (l ? { linked: true, bizId: l.biz_id, hotelId: l.hotel_id, hotelName: l.hotel_name, cityCode: l.city_code, env: c.env, configured: c.configured, provider: PROVIDER } : { linked: false });
  const countLinks = async () => Number((await pool.query("SELECT count(*)::int AS n FROM biz_hotel_links")).rows[0].n);

  // cardRequired:false: لا بطاقة ضيف في هذا المزوّد (الاختبار يُحاكي الدفع، والحي يحصّل من ناس لايف)
  app.get("/hotel/status", async () => { const c = CFG(); return { ok: true, provider: PROVIDER, configured: c.configured, env: c.configured ? c.env : null, source: c.source, linked: await countLinks(), cardRequired: false, testCard: null, liveBooking: false }; });
  app.get("/biz/:id/hotel", async (req) => linkOut(await linkOf(str(req.params.id, 80))));

  // ---- العروض: تواريخ وضيوف → غرف بأسعار اليوم
  const parseStay = (q, reply) => {
    const inMs = dayMs(q?.checkIn), outMs = dayMs(q?.checkOut);
    if (!Number.isFinite(inMs) || !Number.isFinite(outMs)) return bad(reply, 400, "bad-dates");
    const nights = Math.round((outMs - inMs) / DAY);
    if (nights < 1 || nights > MAX_NIGHTS || inMs < dayMs(todayKey())) return bad(reply, 400, "bad-dates");
    const adults = clampInt(q?.adults, 0, 99, 2), rooms = clampInt(q?.rooms, 0, 99, 1);
    if (adults < 1 || adults > MAX_GUESTS || rooms < 1 || rooms > MAX_GUESTS) return bad(reply, 400, "bad-guests");
    return { checkIn: one(q.checkIn), checkOut: one(q.checkOut), nights, adults, rooms };
  };
  const fetchRates = (hotelId, stay) => api("POST", `${DATA_BASE}/hotels/rates`, { body: { hotelIds: [hotelId], occupancies: [{ rooms: stay.rooms, adults: stay.adults }], currency: "SAR", guestNationality: "SA", checkin: stay.checkIn, checkout: stay.checkOut, timeout: 8, includeHotelData: false } });
  app.get("/biz/:id/hotel/offers", async (req, reply) => {
    const c = CFG(); if (!c.configured) return bad(reply, 503, "hotel-disabled");
    const link = await linkOf(str(req.params.id, 80)); if (!link) return bad(reply, 404, "not-linked");
    const stay = parseStay(req.query ?? {}, reply); if (reply.sent) return;
    let res;
    try { res = await fetchRates(link.hotel_id, stay); } catch (e) { return providerFail(reply, e); }
    // البيئة الفعلية من ردّ المزوّد (sandbox:true) حتى تصدق شارة «اختبار» في التطبيق
    const env = res.json?.sandbox === true ? "test" : res.json?.sandbox === false ? "live" : c.env;
    const base = { hotel: { hotelId: link.hotel_id, name: link.hotel_name, cityCode: link.city_code }, ...stay, currency: "SAR", env, provider: PROVIDER };
    if (!res.ok || !res.json) { if (isNoAvailability(res)) return { ...base, available: false, offers: [] }; if (isAuthError(res)) return bad(reply, 502, "provider-error", { message: "bad-credentials" }); return bad(reply, 502, "provider-error", { message: errText(res) }); }
    const d = Array.isArray(res.json?.data) ? res.json.data.find((h) => h.hotelId === link.hotel_id) ?? res.json.data[0] : null;
    const offers = (Array.isArray(d?.roomTypes) ? d.roomTypes : []).map((rt) => normalizeOffer(rt, stay.nights, env)).filter((o) => o.id && o.total > 0).sort((a, b) => a.total - b.total);
    const hotelRow = Array.isArray(res.json?.hotels) ? res.json.hotels.find((h) => h.id === link.hotel_id) : null;
    if (hotelRow?.name && hotelRow.name !== link.hotel_name) base.hotel.name = str(hotelRow.name, 120);
    return { ...base, available: offers.length > 0, offers };
  });

  // ---- الحجز: تسعير مسبق (prebook) ثم حجز؛ بلا بطاقة ضيف
  const bookingOut = (b) => {
    const total = Number(b.total), cur = b.currency || "SAR";
    const totalText = cur === "SAR" ? sarText(total / 100) : moneyText(total, cur);
    return { id: b.id, bizId: b.biz_id, bizName: b.biz_name ?? "", hotelId: b.hotel_id, hotelName: b.hotel_name, orderId: b.order_id, confirmation: b.confirmation, status: b.status,
      checkIn: todayLike(b.check_in), checkOut: todayLike(b.check_out), nights: b.nights, adults: b.adults, rooms: b.rooms, roomName: b.room_name,
      total, currency: cur, totalText, guestName: b.guest_name, guestEmail: b.guest_email, cancelText: b.cancel_text, env: b.env, provider: b.provider ?? PROVIDER, upcoming: b.status !== "failed" && dayMs(todayLike(b.check_out)) >= dayMs(todayKey()), createdAt: b.created_at };
  };
  const todayLike = (d) => (d instanceof Date ? new Intl.DateTimeFormat("en-CA", { timeZone: "UTC", year: "numeric", month: "2-digit", day: "2-digit" }).format(d) : String(d ?? ""));
  const SELECT_B = "SELECT b.*, COALESCE(NULLIF(z.name_ar,''), z.name) AS biz_name FROM hotel_bookings b LEFT JOIN biz z ON z.id=b.biz_id";
  app.post("/biz/:id/hotel/book", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const c = CFG(); if (!c.configured) return bad(reply, 503, "hotel-disabled");
    // الحي: LiteAPI يحصّل من حساب ناس لايف، فلا حجز حقيقي قبل اعتماد تحصيل كل حجز من المستخدم عبر ميسر
    if (c.env === "live") return bad(reply, 503, "live-payment-pending");
    const bizId = str(req.params.id, 80);
    const link = await linkOf(bizId); if (!link) return bad(reply, 404, "not-linked");
    const b = req.body ?? {}, g = b.guest ?? {};
    const offerId = str(b.offerId, 2000); if (!offerId) return bad(reply, 400, "bad-offer");
    const guest = { firstName: str(g.firstName, 60), lastName: str(g.lastName, 60), phone: str(g.phone, 30).replace(/[^\d+]/g, ""), email: str(g.email, 120).toLowerCase() };
    if (!guest.firstName || !guest.lastName || !/^\S+@\S+\.\S+$/.test(guest.email) || guest.phone.replace(/\D/g, "").length < 8) return bad(reply, 400, "bad-guest");
    let pre;
    try { pre = await api("POST", `${BOOK_BASE}/rates/prebook`, { body: { offerId, usePaymentSdk: false } }); } catch (e) { return providerFail(reply, e); }
    if (!pre.ok || !pre.json?.data?.prebookId) { if (isNoAvailability(pre) || pre.status === 400 || pre.status === 404) return bad(reply, 409, "offer-unavailable", { message: errText(pre) }); return bad(reply, 502, "provider-error", { message: errText(pre) }); }
    const pd = pre.json.data;
    const inMs = dayMs(pd.checkin), outMs = dayMs(pd.checkout);
    const nights = Number.isFinite(inMs) && Number.isFinite(outMs) ? Math.max(1, Math.round((outMs - inMs) / DAY)) : 1;
    const rt = Array.isArray(pd.roomTypes) ? pd.roomTypes[0] : null;
    // السعر المؤكد من التسعير المسبق (وقد يختلف عن العرض)؛ السعر المعروض للمستخدم هو سعر البيع المقترح وإلا السعر المؤكد
    const offer = normalizeOffer({ ...rt, offerId, offerRetailRate: { amount: num(pd.price), currency: pd.currency }, suggestedSellingPrice: pd.suggestedSellingPrice }, nights, "test");
    const id = crypto.randomUUID();
    const order = { prebookId: pd.prebookId, clientReference: `naslife-${id}`, holder: { firstName: guest.firstName, lastName: guest.lastName, email: guest.email, phone: guest.phone },
      guests: [{ occupancyNumber: 1, firstName: guest.firstName, lastName: guest.lastName, email: guest.email }], payment: { method: "ACC_CREDIT_CARD" } };
    let res;
    try { res = await api("POST", `${BOOK_BASE}/rates/book`, { body: order, timeoutMs: 30000 }); } catch (e) { return providerFail(reply, e); }
    if (!res.ok || !res.json?.data) { if (isNoAvailability(res) || res.status === 400 || res.status === 404) return bad(reply, 409, "offer-unavailable", { message: errText(res) }); return bad(reply, 502, "provider-error", { message: errText(res) }); }
    const data = res.json.data;
    const confirmation = str(data.hotelConfirmationCode ?? data.supplierBookingId ?? "", 60);
    const status = /CONFIRMED/i.test(String(data.status ?? "")) ? "confirmed" : /FAILED|CANCELLED|REJECTED/i.test(String(data.status ?? "")) ? "failed" : "pending";
    const room = Array.isArray(data.bookedRooms) ? data.bookedRooms[0] : null;
    const cancel = cancelInfo(data.cancellationPolicies ?? room?.rate?.cancellationPolicies);
    const raw = { bookingId: data.bookingId ?? null, status: data.status ?? null, hotelConfirmationCode: data.hotelConfirmationCode ?? null, supplierBookingId: data.supplierBookingId ?? null, prebookId: pd.prebookId, price: data.price ?? null, currency: data.currency ?? null, sandbox: res.json.sandbox ?? null };
    await pool.query(`INSERT INTO hotel_bookings(id,user_id,biz_id,hotel_id,hotel_name,offer_id,order_id,confirmation,status,check_in,check_out,nights,adults,rooms,room_name,total,currency,guest_name,guest_email,guest_phone,cancel_text,env,raw,provider,cost)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23,$24,$25)`,
      [id, uid, bizId, link.hotel_id, str(data.hotel?.name, 120) || link.hotel_name, str(offerId, 2000), str(data.bookingId, 60) || null, confirmation || null, status, str(data.checkin ?? pd.checkin, 10), str(data.checkout ?? pd.checkout, 10), nights,
       Number(room?.adults) || Number(rt?.rates?.[0]?.adultCount) || 1, 1, str(room?.roomType?.name, 120) || offer.roomName, offer.total, offer.currency, `${guest.firstName} ${guest.lastName}`, guest.email, guest.phone, cancel.cancelText, c.env, JSON.stringify(raw), PROVIDER, offer.cost]);
    const row = (await pool.query(`${SELECT_B} WHERE b.id=$1`, [id])).rows[0];
    const out = bookingOut(row);
    await notify(uid, { kind: "hotel_booked", title: `تم حجزك في ${out.hotelName}`, body: `${dateAr(out.checkIn)} إلى ${dateAr(out.checkOut)} · رقم التأكيد ${confirmation || out.orderId || ""}`.trim(), data: { bookingId: id, bizId } });
    return out;
  });
  app.get("/hotel/bookings/mine", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    return (await pool.query(`${SELECT_B} WHERE b.user_id=$1 ORDER BY b.created_at DESC LIMIT 100`, [uid])).rows.map(bookingOut);
  });
  app.get("/hotel/bookings/:id", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!/^[0-9a-f-]{36}$/i.test(req.params.id)) return bad(reply, 400, "bad-id");
    const r = (await pool.query(`${SELECT_B} WHERE b.id=$1`, [req.params.id])).rows[0];
    if (!r) return bad(reply, 404, "not-found");
    if (r.user_id !== uid && !(await isAdmin(uid))) return bad(reply, 403, "forbidden");
    return bookingOut(r);
  });

  // ---- الربط: مالك الدائرة أو الإدارة (معرّف LiteAPI مثل lp1897)
  const canLink = async (uid, biz) => biz && (biz.owner_id === uid || (await isAdmin(uid)));
  app.put("/biz/:id/hotel/link", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const bizId = str(req.params.id, 80); const biz = await bizOf(bizId); if (!biz) return bad(reply, 404, "not-found");
    if (!(await canLink(uid, biz))) return bad(reply, 403, "forbidden");
    const b = req.body ?? {}; const hotelId = str(b.hotelId, 40); if (!/^[A-Za-z0-9_-]{3,40}$/.test(hotelId)) return bad(reply, 400, "bad-hotel");
    await pool.query(`INSERT INTO biz_hotel_links(biz_id,hotel_id,hotel_name,city_code,lat,lng,linked_by) VALUES($1,$2,$3,$4,$5,$6,$7)
      ON CONFLICT (biz_id) DO UPDATE SET hotel_id=EXCLUDED.hotel_id, hotel_name=EXCLUDED.hotel_name, city_code=EXCLUDED.city_code, lat=EXCLUDED.lat, lng=EXCLUDED.lng, linked_by=EXCLUDED.linked_by, created_at=now()`,
      [bizId, hotelId, str(b.hotelName, 120) || biz.name_ar || biz.name, str(b.cityCode, 40).toUpperCase(), num(b.lat), num(b.lng), uid]);
    return linkOut(await linkOf(bizId));
  });
  app.delete("/biz/:id/hotel/link", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const bizId = str(req.params.id, 80); const biz = await bizOf(bizId); if (!biz) return bad(reply, 404, "not-found");
    if (!(await canLink(uid, biz))) return bad(reply, 403, "forbidden");
    await pool.query("DELETE FROM biz_hotel_links WHERE biz_id=$1", [bizId]);
    return { ok: true };
  });

  // ---- الإدارة: المفتاح والفحص والبحث عن فندق للربط
  const adminOnly = async (req, reply) => { const uid = await auth(req); if (!uid) { unauthorized(reply); return null; } if (!(await isAdmin(uid))) { bad(reply, 403, "admin-only"); return null; } return uid; };
  const configOut = async () => { const c = CFG(); return { provider: PROVIDER, configured: c.configured, env: c.env, source: c.source, secretSet: !!c.apiKey, secretHint: hint(c.apiKey), panelSet: !!panel.apiKey, envPresent: c.envPresent, updatedAt: panel.updatedAt, updatedBy: panel.updatedBy, linked: await countLinks(), bookings: Number((await pool.query("SELECT count(*)::int AS n FROM hotel_bookings")).rows[0].n) }; };
  app.get("/adminapi/hotels/config", async (req, reply) => { if (!(await adminOnly(req, reply))) return; return configOut(); });
  app.put("/adminapi/hotels/config", async (req, reply) => {
    const uid = await adminOnly(req, reply); if (!uid) return;
    const b = req.body ?? {}; const next = { apiKey: panel.apiKey, env: panel.env };
    if (b.apiKey !== undefined) {
      const v = str(b.apiKey, 200).replace(/\s+/g, "");
      if (v && /[*•●]/.test(v)) return bad(reply, 400, "masked-key", { field: "apiKey" });
      if (v && !/^[A-Za-z0-9_\-]{12,200}$/.test(v)) return bad(reply, 400, "bad-key", { field: "apiKey" });
      next.apiKey = v;
    }
    if (b.env !== undefined) { const e = str(b.env, 8).toLowerCase(); if (e && !["test", "live"].includes(e)) return bad(reply, 400, "bad-env"); next.env = e; }
    for (const f of ["apiKey", "env"]) {
      if (next[f]) await pool.query("INSERT INTO hotel_settings(key, value, updated_by, updated_at) VALUES($1,$2,$3,now()) ON CONFLICT (key) DO UPDATE SET value=EXCLUDED.value, updated_by=EXCLUDED.updated_by, updated_at=now()", [f, next[f], uid]);
      else await pool.query("DELETE FROM hotel_settings WHERE key=$1", [f]);
    }
    await loadPanel();
    globalThis.naslifeAudit?.(uid, "hotels.config", PROVIDER, { env: CFG().env, source: CFG().source })?.catch?.(() => {});
    return configOut();
  });
  // فحص الاتصال: طلب صغير لقائمة فنادق جدة بالمفتاح الحالي (200 = المفتاح صحيح، 401/403 = خاطئ)
  app.post("/adminapi/hotels/test", async (req, reply) => {
    if (!(await adminOnly(req, reply))) return;
    const c = CFG(); if (!c.configured) return { ok: false, error: "hotel-disabled", env: null, source: null };
    try {
      const r = await api("GET", `${DATA_BASE}/data/hotels`, { query: { countryCode: "SA", cityName: "Jeddah", limit: 1 }, timeoutMs: 10000 });
      if (isAuthError(r)) return { ok: false, error: "bad-credentials", message: errText(r), env: c.env, source: c.source };
      if (!r.ok) return { ok: false, error: `provider-${r.status}`, message: errText(r), env: c.env, source: c.source };
      return { ok: true, env: c.env, source: c.source, hotels: Array.isArray(r.json?.data) ? r.json.data.length : null };
    } catch (e) { return { ok: false, error: "provider-unreachable", message: str(e.message, 200), env: c.env, source: c.source }; }
  });
  app.get("/adminapi/hotels/search", async (req, reply) => {
    if (!(await adminOnly(req, reply))) return;
    const c = CFG(); if (!c.configured) return bad(reply, 503, "hotel-disabled");
    const q = req.query ?? {}; const lat = num(q.lat), lng = num(q.lng); const cityIn = str(q.cityCode ?? q.city, 40);
    const cityName = CITY_BY_CODE[cityIn.toUpperCase()] ?? cityIn;
    const needle = str(q.q, 60);
    let res;
    try {
      res = lat != null && lng != null
        ? await api("GET", `${DATA_BASE}/data/hotels`, { query: { latitude: lat, longitude: lng, radius: clampInt(q.radiusKm, 1, 50, 5) * 1000, hotelName: needle || undefined, limit: 50 } })
        : cityName ? await api("GET", `${DATA_BASE}/data/hotels`, { query: { countryCode: str(q.countryCode, 2).toUpperCase() || "SA", cityName, hotelName: needle || undefined, limit: 50 } }) : null;
    } catch (e) { return providerFail(reply, e); }
    if (!res) return bad(reply, 400, "bad-query");
    if (!res.ok) return bad(reply, 502, "provider-error", { message: isAuthError(res) ? "bad-credentials" : errText(res) });
    const nl = needle.toLowerCase();
    const hotels = (Array.isArray(res.json?.data) ? res.json.data : []).map((h) => ({ hotelId: str(h.id, 40), name: str(h.name, 120), lat: num(h.latitude), lng: num(h.longitude), distanceKm: null, stars: num(h.stars), city: str(h.city, 60), address: str(h.address, 120), photo: str(h.thumbnail ?? h.main_photo, 300) || null }))
      .filter((h) => h.hotelId && (!nl || h.name.toLowerCase().includes(nl))).slice(0, 50);
    return { hotels };
  });
  app.get("/adminapi/hotels/links", async (req, reply) => {
    if (!(await adminOnly(req, reply))) return;
    return (await pool.query("SELECT l.*, COALESCE(NULLIF(z.name_ar,''), z.name) AS biz_name FROM biz_hotel_links l LEFT JOIN biz z ON z.id=l.biz_id ORDER BY l.created_at DESC")).rows
      .map((l) => ({ bizId: l.biz_id, bizName: l.biz_name ?? "", hotelId: l.hotel_id, hotelName: l.hotel_name, cityCode: l.city_code, createdAt: l.created_at }));
  });
}
