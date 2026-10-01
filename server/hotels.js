// «حجز الفنادق» (server/hotels.js): ربط دائرة فندقية بفندق حقيقي لدى Amadeus Self-Service وحجز غرفة من داخل ناس لايف
// (قرار المالك 1 أكتوبر 2026: تجربة على دائرة واحدة في جدة). المال لا يمر عبرنا: بطاقة الضيف تُمرَّر إلى الفندق كضمان
// (Hotel Booking v2) ولا تُخزَّن ولا تُسجَّل. المفاتيح (client id/secret وبيئة test|live) من لوحة الإدارة (جدول hotel_settings)
// ولها الأولوية على متغيرات البيئة AMADEUS_CLIENT_ID/AMADEUS_CLIENT_SECRET/AMADEUS_ENV. الرمز (OAuth2 client_credentials) يُخزَّن
// في الذاكرة ويُجدَّد قبل انتهائه بدقيقة. نداءات الشبكة عبر globalThis.naslifeHotelFetch (للاختبار) أو fetch.
// التسجيل في register.txt:
//   await app.register((await import("./hotels.js")).default, { pool, auth });
import crypto from "node:crypto";

const BASES = { test: "https://test.api.amadeus.com", live: "https://api.amadeus.com" };
// بطاقة Amadeus التجريبية الموثّقة: بيئة الاختبار لا تحصّل شيئاً؛ التطبيق يملأ بها النموذج في وضع الاختبار
export const TEST_CARD = { vendorCode: "VI", number: "4151289722471370", expiry: "2028-08", holderName: "TEST GUEST" };
const VENDORS = new Set(["VI", "MC", "AX", "CA", "DC"]);
const TITLES = new Set(["MR", "MS", "MRS"]);
const MAX_NIGHTS = 30, MAX_GUESTS = 9;
const DAY = 86400000;

const str = (v, max = 200) => String(v ?? "").trim().slice(0, max);
const num = (v) => { const n = Number(v); return Number.isFinite(n) ? n : null; };
// معامل مكرّر في الرابط يصل مصفوفة: نأخذ أوله
const one = (v) => (Array.isArray(v) ? v[0] : v);
const clampInt = (v, lo, hi, d) => { const n = Math.round(Number(one(v))); return Number.isFinite(n) ? Math.min(hi, Math.max(lo, n)) : d; };
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const dayMs = (s) => { s = one(s); if (!DATE_RE.test(String(s ?? ""))) return NaN; const t = Date.parse(`${s}T00:00:00Z`); return Number.isFinite(t) ? t : NaN; };
const todayKey = (now = Date.now()) => new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Riyadh", year: "numeric", month: "2-digit", day: "2-digit" }).format(now);
/// فحص لون (Luhn) لرقم البطاقة قبل إرساله: يوفّر رحلة إلى المزوّد لخطأ كتابة
export const luhn = (s) => { const d = String(s ?? "").replace(/\s|-/g, ""); if (!/^\d{12,19}$/.test(d)) return false; let sum = 0, alt = false; for (let i = d.length - 1; i >= 0; i--) { let n = Number(d[i]); if (alt) { n *= 2; if (n > 9) n -= 9; } sum += n; alt = !alt; } return sum % 10 === 0; };
const sarText = (n) => (Number.isInteger(n) ? n.toLocaleString("en-US") : n.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })) + " ر.س";
const moneyText = (amount, currency) => (currency === "SAR" ? sarText(amount) : `${amount.toLocaleString("en-US", { maximumFractionDigits: 2 })} ${currency}`);
const MONTHS_AR = ["يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو", "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر"];
const dateAr = (iso) => { const t = new Date(iso); if (Number.isNaN(t.getTime())) return ""; const p = Object.fromEntries(new Intl.DateTimeFormat("en-US", { timeZone: "Asia/Riyadh", day: "numeric", month: "numeric" }).formatToParts(t).map((x) => [x.type, x.value])); return `${p.day} ${MONTHS_AR[Number(p.month) - 1]}`; };
const BOARD_AR = { ROOM_ONLY: "الغرفة فقط", BREAKFAST: "مع الإفطار", HALF_BOARD: "نصف إقامة", FULL_BOARD: "إقامة كاملة", ALL_INCLUSIVE: "شامل" };
const BED_AR = { KING: "سرير كينغ", QUEEN: "سرير كوين", DOUBLE: "سرير مزدوج", TWIN: "سريران", SINGLE: "سرير فردي" };
const CATEGORY_AR = { STANDARD_ROOM: "غرفة عادية", DELUXE_ROOM: "غرفة ديلوكس", SUPERIOR_ROOM: "غرفة سوبيريور", EXECUTIVE_ROOM: "غرفة تنفيذية", SUITE: "جناح", JUNIOR_SUITE: "جناح صغير", FAMILY_ROOM: "غرفة عائلية", PENTHOUSE: "بنتهاوس", STUDIO: "استوديو", APARTMENT: "شقة", VILLA: "فيلا", ACCESSIBLE_ROOM: "غرفة ميسّرة", RESIDENTIAL_APARTMENT: "شقة سكنية", BUSINESS_ROOM: "غرفة أعمال", COMFORT_ROOM: "غرفة كومفورت", PRIVILEGE_ROOM: "غرفة بريفيليج", DUPLEX: "دوبلكس", SUPERIOR_SUITE: "جناح سوبيريور", EXECUTIVE_SUITE: "جناح تنفيذي" };
const PAYMENT_AR = { guarantee: "بطاقة ضمان؛ الدفع في الفندق", deposit: "عربون يُخصم من البطاقة", prepay: "دفع مسبق كامل من البطاقة" };

/// تطبيع عرض غرفة من Amadeus (v3 hotel-offers) إلى بطاقة عربية واحدة
export function normalizeOffer(o, nights) {
  const room = o?.room ?? {}, est = room.typeEstimated ?? {}, price = o?.price ?? {}, pol = o?.policies ?? {};
  const currency = str(price.currency, 3) || "SAR";
  const rawTotal = num(price.total) ?? num(price.base) ?? 0;
  const total = currency === "SAR" ? Math.round(rawTotal * 100) : rawTotal;
  const perNight = nights > 0 ? rawTotal / nights : rawTotal;
  const desc = str(room.description?.text, 300);
  const roomName = CATEGORY_AR[est.category] ?? (est.category ? String(est.category).replace(/_/g, " ").toLowerCase() : "") ?? "";
  const bedType = BED_AR[est.bedType] ?? (est.bedType ? String(est.bedType).toLowerCase() : "");
  const cancels = Array.isArray(pol.cancellations) ? pol.cancellations : [];
  const refundFlag = pol.refundable?.cancellationRefund;
  const nonRefundable = refundFlag === "NON_REFUNDABLE" || cancels.some((c) => c.type === "FULL_STAY" && !c.deadline);
  const deadline = cancels.map((c) => c.deadline).filter(Boolean).sort()[0] ?? null;
  const refundable = nonRefundable ? false : deadline ? true : refundFlag === "REFUNDABLE_UP_TO_DEADLINE" ? true : null;
  const cancelText = nonRefundable ? "غير قابل للاسترداد" : deadline ? `إلغاء مجاني حتى ${dateAr(deadline)}` : "سياسة الإلغاء بحسب الفندق";
  const paymentType = ["guarantee", "deposit", "prepay"].includes(pol.paymentType) ? pol.paymentType : "guarantee";
  return {
    id: str(o?.id, 120), roomName: roomName || "غرفة", roomCode: str(room.type, 20), bedType, beds: num(est.beds), description: desc,
    boardType: BOARD_AR[o?.boardType] ?? (o?.boardType ? str(o.boardType, 40) : ""), total, currency, totalText: moneyText(rawTotal, currency),
    perNightText: `${moneyText(Math.round(perNight * 100) / 100, currency)}/ليلة`, refundable, cancelBy: deadline, cancelText, paymentType, paymentText: PAYMENT_AR[paymentType],
    guests: num(o?.guests?.adults),
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
    CREATE INDEX IF NOT EXISTS hotel_bookings_user ON hotel_bookings(user_id, created_at DESC);
  `);

  // ---- الإعدادات: اللوحة أولاً ثم البيئة
  const panel = { clientId: "", clientSecret: "", env: "", updatedAt: null, updatedBy: null };
  const loadPanel = async () => {
    const rows = (await pool.query("SELECT key, value, updated_by, updated_at FROM hotel_settings")).rows;
    panel.clientId = ""; panel.clientSecret = ""; panel.env = ""; panel.updatedAt = null; panel.updatedBy = null;
    for (const r of rows) { if (r.key in panel && typeof panel[r.key] === "string") panel[r.key] = r.value; if (!panel.updatedAt || r.updated_at > panel.updatedAt) { panel.updatedAt = r.updated_at; panel.updatedBy = r.updated_by; } }
  };
  await loadPanel();
  const CFG = () => {
    const env = { clientId: process.env.AMADEUS_CLIENT_ID ?? "", clientSecret: process.env.AMADEUS_CLIENT_SECRET ?? "", env: process.env.AMADEUS_ENV ?? "" };
    const source = panel.clientId && panel.clientSecret ? "panel" : env.clientId && env.clientSecret ? "env" : null;
    const k = source === "panel" ? panel : source === "env" ? env : { clientId: "", clientSecret: "", env: "" };
    const mode = (source === "panel" ? panel.env : env.env) === "live" ? "live" : "test";
    return { configured: !!source, source, env: mode, base: BASES[mode], clientId: k.clientId, clientSecret: k.clientSecret, envPresent: !!(env.clientId && env.clientSecret) };
  };
  const hint = (k) => (k ? `${k.slice(0, 3)}…${k.slice(-4)}` : "");

  // ---- رمز الوصول (يُجدَّد قبل انتهائه بدقيقة؛ تغيّر المفاتيح يُسقطه)
  let token = { value: "", exp: 0, key: "" };
  const getToken = async () => {
    const c = CFG(); if (!c.configured) throw Object.assign(new Error("hotel-disabled"), { code: "hotel-disabled" });
    const key = `${c.env}:${c.clientId}:${c.clientSecret}`;
    if (token.value && token.key === key && token.exp > Date.now() + 60000) return token.value;
    const body = new URLSearchParams({ grant_type: "client_credentials", client_id: c.clientId, client_secret: c.clientSecret }).toString();
    const r = await fetchImpl(`${c.base}/v1/security/oauth2/token`, { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body, signal: AbortSignal.timeout(10000) });
    let j = null; try { j = await r.json(); } catch { /* ignore */ }
    if (!r.ok || !j?.access_token) throw Object.assign(new Error(str(j?.error_description ?? j?.title ?? `token ${r.status}`, 200)), { code: r.status === 401 ? "bad-credentials" : `provider-${r.status}`, status: r.status });
    token = { value: String(j.access_token), exp: Date.now() + (Number(j.expires_in) || 1799) * 1000, key };
    return token.value;
  };
  const api = async (method, path, { query, body } = {}) => {
    const c = CFG(); const t = await getToken();
    const url = `${c.base}${path}${query ? "?" + new URLSearchParams(Object.fromEntries(Object.entries(query).filter(([, v]) => v != null && v !== ""))).toString() : ""}`;
    const r = await fetchImpl(url, { method, headers: { authorization: `Bearer ${t}`, ...(body ? { "content-type": "application/vnd.amadeus+json" } : {}) }, body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(20000) });
    let j = null; try { j = await r.json(); } catch { /* ignore */ }
    return { ok: r.ok, status: r.status, json: j, errors: Array.isArray(j?.errors) ? j.errors : [] };
  };
  const errText = (res) => str(res.errors.map((e) => [e.title, e.detail].filter(Boolean).join(": ")).join(" | ") || `provider ${res.status}`, 300);
  // أخطاء Amadeus التي تعني «لا توفر» لا «عطل»
  const NO_AVAIL = new Set([3664, 1257, 11226, 10604, 23]);
  const isNoAvailability = (res) => res.status === 400 && res.errors.some((e) => NO_AVAIL.has(Number(e.code)) || /NO ROOMS|NOT AVAILABLE|NO AVAILABILITY|INVALID PROPERTY/i.test(String(e.title ?? e.detail ?? "")));

  // ---- الروابط
  const linkOf = async (bizId) => (await pool.query("SELECT * FROM biz_hotel_links WHERE biz_id=$1", [bizId])).rows[0] ?? null;
  const bizOf = async (bizId) => { try { return (await pool.query("SELECT id, name, name_ar, owner_id, category, lat, lng FROM biz WHERE id=$1", [bizId])).rows[0] ?? null; } catch { return null; } };
  const linkOut = (l, c = CFG()) => (l ? { linked: true, bizId: l.biz_id, hotelId: l.hotel_id, hotelName: l.hotel_name, cityCode: l.city_code, env: c.env, configured: c.configured } : { linked: false });
  const countLinks = async () => Number((await pool.query("SELECT count(*)::int AS n FROM biz_hotel_links")).rows[0].n);

  app.get("/hotel/status", async () => { const c = CFG(); return { ok: true, configured: c.configured, env: c.configured ? c.env : null, source: c.source, linked: await countLinks(), testCard: c.configured && c.env === "test" ? TEST_CARD : null }; });
  app.get("/biz/:id/hotel", async (req) => linkOut(await linkOf(str(req.params.id, 80))));

  // ---- العروض: تواريخ وضيوف → غرف بأسعار اليوم
  const parseStay = (q, reply) => {
    const inMs = dayMs(q?.checkIn), outMs = dayMs(q?.checkOut);
    if (!Number.isFinite(inMs) || !Number.isFinite(outMs)) return bad(reply, 400, "bad-dates");
    const nights = Math.round((outMs - inMs) / DAY);
    if (nights < 1 || nights > MAX_NIGHTS || inMs < dayMs(todayKey())) return bad(reply, 400, "bad-dates");
    const adults = clampInt(q?.adults, 0, 99, 2), rooms = clampInt(q?.rooms, 0, 99, 1);
    if (adults < 1 || adults > MAX_GUESTS || rooms < 1 || rooms > MAX_GUESTS) return bad(reply, 400, "bad-guests");
    return { checkIn: q.checkIn, checkOut: q.checkOut, nights, adults, rooms };
  };
  const fetchOffers = async (link, stay) => api("GET", "/v3/shopping/hotel-offers", { query: { hotelIds: link.hotel_id, adults: stay.adults, checkInDate: stay.checkIn, checkOutDate: stay.checkOut, roomQuantity: stay.rooms, currency: "SAR", bestRateOnly: "false", includeClosed: "false" } });
  app.get("/biz/:id/hotel/offers", async (req, reply) => {
    const c = CFG(); if (!c.configured) return bad(reply, 503, "hotel-disabled");
    const link = await linkOf(str(req.params.id, 80)); if (!link) return bad(reply, 404, "not-linked");
    const stay = parseStay(req.query ?? {}, reply); if (reply.sent) return;
    let res;
    try { res = await fetchOffers(link, stay); } catch (e) { return bad(reply, e.code === "hotel-disabled" ? 503 : 502, e.code === "hotel-disabled" ? "hotel-disabled" : "provider-error", { message: str(e.message, 200) }); }
    const base = { hotel: { hotelId: link.hotel_id, name: link.hotel_name, cityCode: link.city_code }, ...stay, currency: "SAR", env: c.env };
    if (!res.ok) { if (isNoAvailability(res)) return { ...base, available: false, offers: [] }; return bad(reply, 502, "provider-error", { message: errText(res) }); }
    const d = Array.isArray(res.json?.data) ? res.json.data[0] : null;
    const offers = (Array.isArray(d?.offers) ? d.offers : []).map((o) => normalizeOffer(o, stay.nights)).filter((o) => o.id);
    if (d?.hotel?.name && d.hotel.name !== link.hotel_name) base.hotel.name = str(d.hotel.name, 120);
    return { ...base, available: d?.available !== false && offers.length > 0, offers };
  });

  // ---- الحجز: بطاقة الضيف تُمرَّر إلى الفندق ولا تُحفظ
  const bookingOut = (b) => {
    const total = Number(b.total), cur = b.currency || "SAR";
    const totalText = cur === "SAR" ? sarText(total / 100) : moneyText(total, cur);
    return { id: b.id, bizId: b.biz_id, bizName: b.biz_name ?? "", hotelId: b.hotel_id, hotelName: b.hotel_name, orderId: b.order_id, confirmation: b.confirmation, status: b.status,
      checkIn: typeof b.check_in === "string" ? b.check_in : todayLike(b.check_in), checkOut: typeof b.check_out === "string" ? b.check_out : todayLike(b.check_out), nights: b.nights, adults: b.adults, rooms: b.rooms, roomName: b.room_name,
      total, currency: cur, totalText, guestName: b.guest_name, guestEmail: b.guest_email, cancelText: b.cancel_text, env: b.env, upcoming: b.status !== "failed" && dayMs(todayLike(b.check_out)) >= dayMs(todayKey()), createdAt: b.created_at };
  };
  const todayLike = (d) => (d instanceof Date ? new Intl.DateTimeFormat("en-CA", { timeZone: "UTC", year: "numeric", month: "2-digit", day: "2-digit" }).format(d) : String(d ?? ""));
  const SELECT_B = "SELECT b.*, COALESCE(NULLIF(z.name_ar,''), z.name) AS biz_name FROM hotel_bookings b LEFT JOIN biz z ON z.id=b.biz_id";
  app.post("/biz/:id/hotel/book", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const c = CFG(); if (!c.configured) return bad(reply, 503, "hotel-disabled");
    const bizId = str(req.params.id, 80);
    const link = await linkOf(bizId); if (!link) return bad(reply, 404, "not-linked");
    const b = req.body ?? {}, g = b.guest ?? {}, card = b.card ?? {};
    const offerId = str(b.offerId, 120); if (!offerId) return bad(reply, 400, "bad-offer");
    const guest = { title: TITLES.has(String(g.title ?? "").toUpperCase()) ? String(g.title).toUpperCase() : "MR", firstName: str(g.firstName, 60), lastName: str(g.lastName, 60), phone: str(g.phone, 30).replace(/[^\d+]/g, ""), email: str(g.email, 120).toLowerCase() };
    if (!guest.firstName || !guest.lastName || !/^\S+@\S+\.\S+$/.test(guest.email) || guest.phone.replace(/\D/g, "").length < 8) return bad(reply, 400, "bad-guest");
    const number = str(card.number, 25).replace(/\s|-/g, ""), expiry = str(card.expiry, 7), vendor = String(card.vendorCode ?? "VI").toUpperCase(), holder = str(card.holderName, 60) || `${guest.firstName} ${guest.lastName}`;
    const expMs = /^\d{4}-\d{2}$/.test(expiry) ? Date.parse(`${expiry}-01T00:00:00Z`) : NaN;
    if (!luhn(number) || !VENDORS.has(vendor) || !Number.isFinite(expMs) || expMs < dayMs(todayKey().slice(0, 7) + "-01")) return bad(reply, 400, "bad-card");
    // العرض يُسعَّر أولاً لنعرف الغرفة والمبلغ الفعليين (قد يتغيّر السعر بين العرض والحجز)
    let priced;
    try { priced = await api("GET", `/v3/shopping/hotel-offers/${encodeURIComponent(offerId)}`); } catch (e) { return bad(reply, e.code === "hotel-disabled" ? 503 : 502, e.code === "hotel-disabled" ? "hotel-disabled" : "provider-error", { message: str(e.message, 200) }); }
    if (!priced.ok) { if (priced.status === 404 || isNoAvailability(priced)) return bad(reply, 409, "offer-unavailable", { message: errText(priced) }); return bad(reply, 502, "provider-error", { message: errText(priced) }); }
    const pd = priced.json?.data ?? {}, po = Array.isArray(pd.offers) ? pd.offers[0] : null;
    if (!po) return bad(reply, 409, "offer-unavailable");
    const inMs = dayMs(po.checkInDate), outMs = dayMs(po.checkOutDate);
    const nights = Number.isFinite(inMs) && Number.isFinite(outMs) ? Math.max(1, Math.round((outMs - inMs) / DAY)) : 1;
    const offer = normalizeOffer(po, nights);
    const order = { data: { type: "hotel-order", guests: [{ tid: 1, title: guest.title, firstName: guest.firstName, lastName: guest.lastName, phone: guest.phone, email: guest.email }],
      travelAgent: { contact: { email: process.env.HOTEL_AGENT_EMAIL || "bookings@naslife.app" } },
      roomAssociations: [{ guestReferences: [{ guestReference: "1" }], hotelOfferId: offerId }],
      payment: { method: "CREDIT_CARD", paymentCard: { paymentCardInfo: { vendorCode: vendor, cardNumber: number, expiryDate: expiry, holderName: holder } } } } };
    let res;
    try { res = await api("POST", "/v2/booking/hotel-orders", { body: order }); } catch (e) { return bad(reply, 502, "provider-error", { message: str(e.message, 200) }); }
    if (!res.ok) { if (isNoAvailability(res) || res.status === 404) return bad(reply, 409, "offer-unavailable", { message: errText(res) }); return bad(reply, 502, "provider-error", { message: errText(res) }); }
    const data = res.json?.data ?? {}, hb = Array.isArray(data.hotelBookings) ? data.hotelBookings[0] : null;
    const confirmation = str(hb?.hotelProviderInformation?.[0]?.confirmationNumber ?? data.associatedRecords?.[0]?.reference ?? "", 60);
    const status = /CONFIRMED/i.test(String(hb?.bookingStatus ?? "")) ? "confirmed" : "pending";
    const id = crypto.randomUUID();
    // raw بلا بيانات البطاقة: نحفظ ردّ المزوّد فقط (لا الطلب)
    const raw = { orderId: data.id ?? null, bookingId: hb?.id ?? null, bookingStatus: hb?.bookingStatus ?? null, provider: hb?.hotelProviderInformation ?? null, associatedRecords: data.associatedRecords ?? null };
    await pool.query(`INSERT INTO hotel_bookings(id,user_id,biz_id,hotel_id,hotel_name,offer_id,order_id,confirmation,status,check_in,check_out,nights,adults,rooms,room_name,total,currency,guest_name,guest_email,guest_phone,cancel_text,env,raw)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23)`,
      [id, uid, bizId, link.hotel_id, str(pd.hotel?.name, 120) || link.hotel_name, offerId, str(data.id, 60) || null, confirmation || null, status, po.checkInDate, po.checkOutDate, nights, Number(po.guests?.adults) || 1, 1, offer.roomName,
       offer.total, offer.currency, `${guest.firstName} ${guest.lastName}`, guest.email, guest.phone, offer.cancelText, c.env, JSON.stringify(raw)]);
    const row = (await pool.query(`${SELECT_B} WHERE b.id=$1`, [id])).rows[0];
    const out = bookingOut(row);
    await notify(uid, { kind: "hotel_booked", title: `تم حجزك في ${out.hotelName}`, body: `${dateAr(po.checkInDate)} إلى ${dateAr(po.checkOutDate)} · رقم التأكيد ${confirmation || out.orderId || ""}`.trim(), data: { bookingId: id, bizId } });
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

  // ---- الربط: مالك الدائرة أو الإدارة
  const canLink = async (uid, biz) => biz && (biz.owner_id === uid || (await isAdmin(uid)));
  app.put("/biz/:id/hotel/link", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const bizId = str(req.params.id, 80); const biz = await bizOf(bizId); if (!biz) return bad(reply, 404, "not-found");
    if (!(await canLink(uid, biz))) return bad(reply, 403, "forbidden");
    const b = req.body ?? {}; const hotelId = str(b.hotelId, 40).toUpperCase(); if (!/^[A-Z0-9]{4,20}$/.test(hotelId)) return bad(reply, 400, "bad-hotel");
    await pool.query(`INSERT INTO biz_hotel_links(biz_id,hotel_id,hotel_name,city_code,lat,lng,linked_by) VALUES($1,$2,$3,$4,$5,$6,$7)
      ON CONFLICT (biz_id) DO UPDATE SET hotel_id=EXCLUDED.hotel_id, hotel_name=EXCLUDED.hotel_name, city_code=EXCLUDED.city_code, lat=EXCLUDED.lat, lng=EXCLUDED.lng, linked_by=EXCLUDED.linked_by, created_at=now()`,
      [bizId, hotelId, str(b.hotelName, 120) || biz.name_ar || biz.name, str(b.cityCode, 3).toUpperCase(), num(b.lat), num(b.lng), uid]);
    return linkOut(await linkOf(bizId));
  });
  app.delete("/biz/:id/hotel/link", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const bizId = str(req.params.id, 80); const biz = await bizOf(bizId); if (!biz) return bad(reply, 404, "not-found");
    if (!(await canLink(uid, biz))) return bad(reply, 403, "forbidden");
    await pool.query("DELETE FROM biz_hotel_links WHERE biz_id=$1", [bizId]);
    return { ok: true };
  });

  // ---- الإدارة: المفاتيح والفحص والبحث عن فندق للربط
  const adminOnly = async (req, reply) => { const uid = await auth(req); if (!uid) { unauthorized(reply); return null; } if (!(await isAdmin(uid))) { bad(reply, 403, "admin-only"); return null; } return uid; };
  const configOut = async () => { const c = CFG(); return { configured: c.configured, env: c.env, source: c.source, clientIdSet: !!c.clientId, clientIdHint: hint(c.clientId), secretSet: !!c.clientSecret, secretHint: hint(c.clientSecret), panelSet: !!(panel.clientId && panel.clientSecret), envPresent: c.envPresent, updatedAt: panel.updatedAt, updatedBy: panel.updatedBy, linked: await countLinks(), bookings: Number((await pool.query("SELECT count(*)::int AS n FROM hotel_bookings")).rows[0].n) }; };
  app.get("/adminapi/hotels/config", async (req, reply) => { if (!(await adminOnly(req, reply))) return; return configOut(); });
  app.put("/adminapi/hotels/config", async (req, reply) => {
    const uid = await adminOnly(req, reply); if (!uid) return;
    const b = req.body ?? {}; const next = { clientId: panel.clientId, clientSecret: panel.clientSecret, env: panel.env };
    for (const f of ["clientId", "clientSecret"]) {
      if (b[f] === undefined) continue;
      const v = str(b[f], 200).replace(/\s+/g, "");
      if (v && /[*•●]/.test(v)) return bad(reply, 400, "masked-key", { field: f });
      if (v && !/^[A-Za-z0-9_\-]{8,120}$/.test(v)) return bad(reply, 400, "bad-key", { field: f });
      next[f] = v;
    }
    if (b.env !== undefined) { const e = str(b.env, 8).toLowerCase(); if (e && !["test", "live"].includes(e)) return bad(reply, 400, "bad-env"); next.env = e; }
    if (!!next.clientId !== !!next.clientSecret) return bad(reply, 400, "both-keys-required");
    for (const f of ["clientId", "clientSecret", "env"]) {
      if (next[f]) await pool.query("INSERT INTO hotel_settings(key, value, updated_by, updated_at) VALUES($1,$2,$3,now()) ON CONFLICT (key) DO UPDATE SET value=EXCLUDED.value, updated_by=EXCLUDED.updated_by, updated_at=now()", [f, next[f], uid]);
      else await pool.query("DELETE FROM hotel_settings WHERE key=$1", [f]);
    }
    await loadPanel(); token = { value: "", exp: 0, key: "" };
    globalThis.naslifeAudit?.(uid, "hotels.config", "amadeus", { env: CFG().env, source: CFG().source })?.catch?.(() => {});
    return configOut();
  });
  app.post("/adminapi/hotels/test", async (req, reply) => {
    if (!(await adminOnly(req, reply))) return;
    const c = CFG(); if (!c.configured) return { ok: false, error: "hotel-disabled", env: null, source: null };
    try { token = { value: "", exp: 0, key: "" }; await getToken(); return { ok: true, env: c.env, source: c.source, expiresIn: Math.max(0, Math.round((token.exp - Date.now()) / 1000)) }; }
    catch (e) { return { ok: false, error: e.code === "bad-credentials" ? "bad-credentials" : e.code?.startsWith?.("provider-") ? e.code : "provider-unreachable", message: str(e.message, 200), env: c.env, source: c.source }; }
  });
  app.get("/adminapi/hotels/search", async (req, reply) => {
    if (!(await adminOnly(req, reply))) return;
    const c = CFG(); if (!c.configured) return bad(reply, 503, "hotel-disabled");
    const q = req.query ?? {}; const lat = num(q.lat), lng = num(q.lng); const city = str(q.cityCode, 3).toUpperCase();
    let res;
    try {
      res = lat != null && lng != null
        ? await api("GET", "/v1/reference-data/locations/hotels/by-geocode", { query: { latitude: lat, longitude: lng, radius: clampInt(q.radiusKm, 1, 50, 5), radiusUnit: "KM", hotelSource: "ALL" } })
        : /^[A-Z]{3}$/.test(city) ? await api("GET", "/v1/reference-data/locations/hotels/by-city", { query: { cityCode: city, radius: 30, radiusUnit: "KM", hotelSource: "ALL" } }) : null;
    } catch (e) { return bad(reply, e.code === "bad-credentials" ? 502 : 502, "provider-error", { message: str(e.message, 200) }); }
    if (!res) return bad(reply, 400, "bad-query");
    if (!res.ok) return bad(reply, 502, "provider-error", { message: errText(res) });
    const needle = str(q.q, 60).toLowerCase();
    const hotels = (Array.isArray(res.json?.data) ? res.json.data : []).map((h) => ({ hotelId: str(h.hotelId, 20), name: str(h.name, 120), lat: num(h.geoCode?.latitude), lng: num(h.geoCode?.longitude), distanceKm: h.distance?.value != null ? Math.round(Number(h.distance.value) * 10) / 10 : null }))
      .filter((h) => h.hotelId && (!needle || h.name.toLowerCase().includes(needle))).slice(0, 50);
    return { hotels };
  });
  app.get("/adminapi/hotels/links", async (req, reply) => {
    if (!(await adminOnly(req, reply))) return;
    return (await pool.query("SELECT l.*, COALESCE(NULLIF(z.name_ar,''), z.name) AS biz_name FROM biz_hotel_links l LEFT JOIN biz z ON z.id=l.biz_id ORDER BY l.created_at DESC")).rows
      .map((l) => ({ bizId: l.biz_id, bizName: l.biz_name ?? "", hotelId: l.hotel_id, hotelName: l.hotel_name, cityCode: l.city_code, createdAt: l.created_at }));
  });
}
