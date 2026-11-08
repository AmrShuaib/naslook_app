// دفتر العناوين (7 نوفمبر 2026، بند 13 من نواقص الإطلاق): عناوين التوصيل المحفوظة للمستخدم، خاصة به وحده.
// التسمية (البيت، العمل…) والحي والتفاصيل والمدينة، ونقطة اختيارية على الخريطة ورقم جوال اختياري؛ حتى عشرة عناوين، وأحدها افتراضي.
// لا يقرأ عناوين المستخدم أحد غيره: طلب السوق بالتوصيل (commerce.js) يأخذ نسخة من العنوان المختار عبر globalThis.naslifeAddressFor،
// والنسخة على الطلب هي ما يراه البائع والمندوب بقواعدهما (docs/addresses.md). عناوين الحساب المحذوف تُمسح في الكنس الدوري.
// التسجيل في register.txt:
//   await app.register((await import("./addresses.js")).default, { pool, auth });
import crypto from "node:crypto";

export const MAX_ADDRESSES = 10;
export const LABEL_MAX = 30, DISTRICT_MAX = 60, DETAILS_MAX = 200, CITY_MAX = 40;
export const SWEEP_MS = 10 * 60 * 1000;
// صيغة UUID صارمة: غيرها 404 قبل Postgres (وإلا 22P02 → 500)
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const latinDigits = (s) => String(s ?? "").replace(/[٠-٩]/g, (d) => String("٠١٢٣٤٥٦٧٨٩".indexOf(d))).replace(/[۰-۹]/g, (d) => String("۰۱۲۳۴۵۶۷۸۹".indexOf(d)));
// محارف التحكم (ومنها NUL الذي يرفضه Postgres في TEXT فيصير الرد 500) تُحذف قبل ضم المسافات؛ الأسطر الجديدة والجدولة تصير مسافة
const clean = (v, max) => { const a = Array.from(String(v ?? "").replace(/[\t\n\r\v\f]/g, " ").replace(/[\u0000-\u001f\u007f]/g, "").replace(/\s+/g, " ").trim()); return (a.length > max ? a.slice(0, max) : a).join(""); };
const len = (s) => Array.from(s).length;
/// جوال سعودي بأي صيغة شائعة إلى +9665XXXXXXXX (كما في biz_onboard.js)؛ null إن لم يكن جوالاً سعودياً
export function normalizePhone(v) {
  const s = latinDigits(v).replace(/[\s\-().]/g, "");
  const m = /^(?:\+966|00966|966)?0?5(\d{8})$/.exec(s);
  return m ? `+9665${m[1]}` : null;
}
const finite = (v) => (typeof v === "number" || (typeof v === "string" && v.trim() !== "")) && Number.isFinite(Number(v)) ? Number(v) : null;

/// يقرأ حقول العنوان من الطلب ويتحقق منها. partial: التعديل يقبل بعض الحقول فقط.
/// يعيد { value } بالحقول الصالحة (بأسماء الأعمدة)، أو { error, extra } للرد 400.
export function addressInput(b, { partial = false } = {}) {
  const v = {};
  const has = (k) => b[k] !== undefined;
  if (!partial || has("label")) {
    const label = clean(b.label, LABEL_MAX + 1);
    if (!label || len(label) > LABEL_MAX) return { error: "bad-label" };
    v.label = label;
  }
  if (!partial || has("district")) {
    const district = clean(b.district, DISTRICT_MAX + 1);
    if (len(district) < 2 || len(district) > DISTRICT_MAX) return { error: "bad-district" };
    v.district = district;
  }
  if (!partial || has("details")) {
    const details = clean(b.details, DETAILS_MAX + 1);
    if (len(details) > DETAILS_MAX) return { error: "bad-details" };
    v.details = details;
  }
  if (!partial || has("city")) {
    const city = clean(b.city, CITY_MAX + 1);
    if (len(city) > CITY_MAX) return { error: "bad-city" };
    v.city = city || null;
  }
  // النقطة كاملة أو لا شيء: خط عرض بلا طول لا يحدد مكاناً
  if (!partial || has("lat") || has("lng")) {
    const none = (x) => x === undefined || x === null || x === "";
    if (none(b.lat) && none(b.lng)) { v.lat = null; v.lng = null; }
    else {
      const lat = finite(b.lat), lng = finite(b.lng);
      if (lat == null || lng == null || Math.abs(lat) > 90 || Math.abs(lng) > 180) return { error: "bad-point" };
      v.lat = lat; v.lng = lng;
    }
  }
  if (!partial || has("phone")) {
    if (b.phone == null || String(b.phone).trim() === "") v.phone = null;
    else { const p = normalizePhone(b.phone); if (!p) return { error: "bad-phone" }; v.phone = p; }
  }
  return { value: v };
}

export const addressOut = (r) => ({
  id: r.id, label: r.label, district: r.district, details: r.details ?? "", city: r.city ?? null,
  lat: r.lat == null ? null : Number(r.lat), lng: r.lng == null ? null : Number(r.lng), phone: r.phone ?? null, isDefault: r.is_default === true,
  createdAt: r.created_at, updatedAt: r.updated_at,
});
/// النسخة التي تُحفظ على الطلب: بلا معرّف ولا تواريخ، فتبقى كما اختارها المشتري ولو عدّل دفتره أو حذفه لاحقاً
export const addressSnapshot = (r) => ({
  label: r.label, district: r.district, details: r.details ?? "", city: r.city ?? null,
  lat: r.lat == null ? null : Number(r.lat), lng: r.lng == null ? null : Number(r.lng), phone: r.phone ?? null,
});

export default async function addresses(app, opts) {
  try { await setup(app, opts); } catch (e) { (app.log?.error ? app.log.error.bind(app.log) : console.error)(`addresses disabled: ${e?.stack || e}`); }
}

async function setup(app, opts) {
  const { pool } = opts; const auth = opts.auth ?? globalThis.naslifeAuth;
  if (!pool || !auth) throw new Error("addresses: pool and auth are required");
  await pool.query(`
    CREATE TABLE IF NOT EXISTS user_addresses (
      id UUID PRIMARY KEY, user_id TEXT NOT NULL, label TEXT NOT NULL, district TEXT NOT NULL, details TEXT NOT NULL DEFAULT '', city TEXT,
      lat DOUBLE PRECISION, lng DOUBLE PRECISION, phone TEXT, is_default BOOLEAN NOT NULL DEFAULT false,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE INDEX IF NOT EXISTS user_addresses_user ON user_addresses(user_id, created_at);
  `);

  const unauthorized = (reply) => reply.code(401).send({ error: "auth" });
  const bad = (reply, code, error, extra = {}) => reply.code(code).send({ error, ...extra });
  const banned = (...t) => { try { return globalThis.naslifeCheckText?.(...t.filter((x) => typeof x === "string" && x)) ?? null; } catch { return null; } };
  const ORDER = "is_default DESC, updated_at DESC, created_at DESC";
  const list = async (uid) => (await pool.query(`SELECT * FROM user_addresses WHERE user_id=$1 ORDER BY ${ORDER}`, [uid])).rows;
  const mine = async (uid, id) => (UUID_RE.test(String(id ?? "")) ? (await pool.query("SELECT * FROM user_addresses WHERE id=$1 AND user_id=$2", [id, uid])).rows[0] ?? null : null);
  async function tx(fn) {
    const c = await pool.connect();
    try { await c.query("BEGIN"); const out = await fn(c); await c.query("COMMIT"); return out; }
    catch (e) { await c.query("ROLLBACK").catch(() => {}); throw e; }
    finally { c.release(); }
  }
  // قفل لكل مستخدم داخل المعاملة: إضافتان متوازيتان لا تتجاوزان الحد ولا تتركان عنوانين افتراضيين
  const lockUser = (c, uid) => c.query("SELECT pg_advisory_xact_lock(hashtext($1))", [`addresses:${uid}`]);

  app.get("/me/addresses", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    return { items: (await list(uid)).map(addressOut), max: MAX_ADDRESSES };
  });

  app.post("/me/addresses", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const b = req.body ?? {};
    const inp = addressInput(b); if (inp.error) return bad(reply, 400, inp.error);
    const v = inp.value;
    const w = banned(v.label, v.district, v.details, v.city); if (w) return bad(reply, 400, "banned-words", { word: w });
    const id = crypto.randomUUID();
    try {
      await tx(async (c) => {
        await lockUser(c, uid);
        const n = (await c.query("SELECT count(*)::int AS n FROM user_addresses WHERE user_id=$1", [uid])).rows[0].n;
        if (n >= MAX_ADDRESSES) throw Object.assign(new Error("address-limit"), { code: "address-limit" });
        // أول عنوان افتراضي تلقائياً؛ وما طُلب افتراضياً يُسقط الافتراضي السابق
        const makeDefault = n === 0 || b.isDefault === true;
        if (makeDefault) await c.query("UPDATE user_addresses SET is_default=false WHERE user_id=$1 AND is_default", [uid]);
        await c.query("INSERT INTO user_addresses(id,user_id,label,district,details,city,lat,lng,phone,is_default) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)",
          [id, uid, v.label, v.district, v.details, v.city, v.lat, v.lng, v.phone, makeDefault]);
      });
    } catch (e) { if (e.code === "address-limit") return bad(reply, 409, "address-limit", { max: MAX_ADDRESSES }); throw e; }
    return addressOut(await mine(uid, id));
  });

  app.patch("/me/addresses/:id", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    // عنوان غيري وعنوان غير موجود الرد نفسه: لا يُكشف وجوده
    const cur = await mine(uid, req.params.id); if (!cur) return bad(reply, 404, "not-found");
    const b = req.body ?? {};
    const inp = addressInput(b, { partial: true }); if (inp.error) return bad(reply, 400, inp.error);
    const v = inp.value;
    const w = banned(v.label, v.district, v.details, v.city); if (w) return bad(reply, 400, "banned-words", { word: w });
    const cols = Object.keys(v);
    if (!cols.length && b.isDefault !== true) return bad(reply, 400, "empty");
    await tx(async (c) => {
      await lockUser(c, uid);
      if (b.isDefault === true) {
        await c.query("UPDATE user_addresses SET is_default=false WHERE user_id=$1 AND is_default AND id<>$2", [uid, cur.id]);
        await c.query("UPDATE user_addresses SET is_default=true WHERE id=$1", [cur.id]);
      }
      if (cols.length) await c.query(`UPDATE user_addresses SET ${cols.map((k, i) => `${k}=$${i + 2}`).join(", ")}, updated_at=now() WHERE id=$1`, [cur.id, ...cols.map((k) => v[k])]);
    });
    return addressOut(await mine(uid, cur.id));
  });

  app.post("/me/addresses/:id/default", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const cur = await mine(uid, req.params.id); if (!cur) return bad(reply, 404, "not-found");
    await tx(async (c) => {
      await lockUser(c, uid);
      await c.query("UPDATE user_addresses SET is_default=(id=$2) WHERE user_id=$1 AND (is_default OR id=$2)", [uid, cur.id]);
    });
    return addressOut(await mine(uid, cur.id));
  });

  app.delete("/me/addresses/:id", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const cur = await mine(uid, req.params.id); if (!cur) return bad(reply, 404, "not-found");
    await tx(async (c) => {
      await lockUser(c, uid);
      const del = await c.query("DELETE FROM user_addresses WHERE id=$1 AND user_id=$2 RETURNING is_default", [cur.id, uid]);
      // حذف الافتراضي يجعل أحدث الباقين افتراضياً، فلا يبقى الدفتر بلا عنوان مختار
      if (del.rows[0]?.is_default) await c.query(`UPDATE user_addresses SET is_default=true WHERE id=(SELECT id FROM user_addresses WHERE user_id=$1 ORDER BY updated_at DESC, created_at DESC LIMIT 1)`, [uid]);
    });
    // الطلبات القائمة تحمل نسختها الخاصة من العنوان فلا تتأثر بالحذف
    return { ok: true };
  });

  // نسخة العنوان لطلب التوصيل: عنوان المستخدم نفسه فقط، وإلا null
  globalThis.naslifeAddressFor = async (uid, id) => { const r = uid ? await mine(uid, id) : null; return r ? addressSnapshot(r) : null; };

  // عناوين الحسابات المحذوفة (account_delete.js يسجّل كل حذف في account_deletions) تُمسح: لا تبقى بعد صاحبها
  const sweep = async () => {
    try {
      const r = await pool.query("DELETE FROM user_addresses a USING account_deletions d WHERE d.user_id=a.user_id");
      return r.rowCount ?? 0;
    } catch { return 0; /* جدول الحذف غير موجود بعد */ }
  };
  globalThis.naslifeAddressesSweep = sweep;
  sweep().catch(() => {});
  if (process.env.NODE_ENV !== "test") setInterval(() => sweep().catch(() => {}), SWEEP_MS).unref?.();
}
