// إضافة Fastify للدوائر التجارية في Naslife: براندات عالمية وسينما وفنادق وتأجير سيارات،
// مع لوحة صاحب النشاط: الملكية، الكتالوج، الطلبات وتأكيد الاستلام، الإحصاءات، الأخبار والعروض، الرد على التقييمات، الفريق.
// التسجيل في src/index.js (بعد commerce.js لأن الدفع يمر بجداول المحفظة نفسها):
//   await app.register((await import("./business.js")).default, { pool, auth });
// المبالغ بالهللة. الشراء والحجز يخصمان من محفظة ناس لايف ويُستردان عند الإلغاء، ويُقيَّد المبلغ لمحفظة صاحب النشاط.
import crypto from "node:crypto";
import http from "node:http";
import { SEED } from "./business_seed.js";

const SLUG_RE = /^[a-z0-9-]{3,60}$/;
const UUID_RE = /^[0-9a-f-]{36}$/i;
const ID_RE = /^[A-Z]{2}\d{7}$/;
const CATEGORIES = new Set(["brand", "cinema", "hotel", "car_rental"]);
const KINDS = new Set(["product", "showtime", "room", "car"]);
const POST_KINDS = new Set(["news", "offer"]);
const STAFF_ROLES = new Set(["manager", "staff"]);
const DAY = 86400000;
const SHOWTIME_DAYS = 3;            // عدد الأيام القادمة التي تُعرض لها مواعيد السينما
const RIYADH_OFFSET_MIN = 180;      // توقيت السعودية UTC+3 (بلا توقيت صيفي)
const TIME_RE = /^([01]\d|2[0-3]):[0-5]\d$/;

const str = (v, max = 200) => String(v ?? "").trim().slice(0, max);
const num = (v) => (v == null || v === "" ? null : Number(v));
const isUrl = (v) => typeof v === "string" && (v.startsWith("http://") || v.startsWith("https://") || v.startsWith("/"));

// ---- تطبيع النص العربي للبحث: توحيد الهمزات والتاء المربوطة والألف المقصورة وإزالة التشكيل والتطويل (في SQL وفي JS بالقواعد نفسها)
export const NORM = (expr) => `regexp_replace(translate(lower(${expr}), 'أإآةى', 'اااهي'), '[ً-ْـ]', '', 'g')`;
export const normQ = (s) => String(s ?? "").toLowerCase().replace(/[أإآ]/g, "ا").replace(/ة/g, "ه").replace(/ى/g, "ي").replace(/[ً-ْـ]/g, "").trim();
export const likeOf = (s) => "%" + normQ(s).replace(/[%_\\]/g, "\\$&") + "%";
/// مسافة الطائر بالكيلومتر بين ($lat,$lng) وأعمدة الجدول؛ NULL عندما لا يُمرَّر موقع. تُشير دائماً إلى المعاملين حتى يعرف pg نوعيهما.
export const DIST = (latP, lngP, latCol, lngCol) => `CASE WHEN ${latP}::float8 IS NULL OR ${lngP}::float8 IS NULL THEN NULL::float8 ELSE 6371 * acos(least(1.0, cos(radians(${latP}::float8)) * cos(radians(${latCol})) * cos(radians(${lngCol}) - radians(${lngP}::float8)) + sin(radians(${latP}::float8)) * sin(radians(${latCol})))) END`;
export const roundKm = (v) => (v == null || !Number.isFinite(Number(v)) ? null : Math.round(Number(v) * 10) / 10);

// ---- ساعات العمل: "يومياً 10:00 ص – 12:00 م"، "24 ساعة"، "السبت – الخميس 8:00 ص – 10:00 م"
const DAY_NAMES = { "الاحد": 0, "الأحد": 0, "الاثنين": 1, "الإثنين": 1, "الثلاثاء": 2, "الاربعاء": 3, "الأربعاء": 3, "الخميس": 4, "الجمعة": 5, "السبت": 6 };
/// يعيد { always, days (null = كل الأيام), open, close } بالدقائق من منتصف الليل (close قد يتجاوز 1440 عند الإغلاق بعد منتصف الليل)، أو null إن لم يُفهم النص.
export function parseHours(text) {
  const s = String(text ?? "").replace(/[ً-ْـ]/g, "").trim();
  if (!s) return null;
  if (/24\s*(ساعة|ساعه|h)|24\s*\/\s*7|على مدار الساعة/i.test(s)) return { always: true, days: null, open: 0, close: 1440 };
  const times = [...s.matchAll(/(\d{1,2})(?::(\d{2}))?\s*(ص|م|صباحا|مساء|am|pm)/gi)];
  if (times.length < 2) return null;
  // "12 م" تعني الظهر عند الافتتاح ومنتصف الليل عند الإغلاق (كما تُكتب في اللوحات)
  const toMin = (m, closing) => { const raw = Number(m[1]); const pm = /^(م|مساء|pm)/i.test(m[3]); let h = raw % 12; if (pm) h += 12; if (closing && raw === 12 && pm) h = 24; return h * 60 + Number(m[2] ?? 0); };
  const open = toMin(times[0], false); let close = toMin(times[1], true);
  if (close <= open) close += 1440;
  const names = [...s.matchAll(/(الاحد|الأحد|الاثنين|الإثنين|الثلاثاء|الاربعاء|الأربعاء|الخميس|الجمعة|السبت)/g)].map((m) => DAY_NAMES[m[1]]);
  let days = null;
  if (names.length >= 2) { days = new Set(); for (let d = names[0]; ; d = (d + 1) % 7) { days.add(d); if (d === names[1]) break; } }
  else if (names.length === 1) days = new Set([names[0]]);
  return { always: false, days, open, close };
}
/// هل النشاط مفتوح الآن بتوقيت السعودية؟ true/false، أو null إن لم تُفهم ساعاته.
export function isOpenNow(text, now = new Date()) {
  const h = parseHours(text);
  if (!h) return null;
  if (h.always) return true;
  const local = new Date(now.getTime() + RIYADH_OFFSET_MIN * 60000);
  const day = local.getUTCDay(), min = local.getUTCHours() * 60 + local.getUTCMinutes();
  const openOn = (d) => !h.days || h.days.has(d);
  if (openOn(day) && min >= h.open && min < h.close) return true;
  // نافذة أمس الممتدة بعد منتصف الليل
  return openOn((day + 6) % 7) && h.close > 1440 && min + 1440 >= h.open && min + 1440 < h.close;
}

export default async function business(app, opts) {
  const { pool, auth } = opts;
  if (!pool || !auth) throw new Error("business: pool and auth are required");

  await pool.query(`
    CREATE TABLE IF NOT EXISTS wallet_accounts (
      user_id TEXT PRIMARY KEY, balance BIGINT NOT NULL DEFAULT 0, points INT NOT NULL DEFAULT 0, updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE TABLE IF NOT EXISTS wallet_tx (
      id UUID PRIMARY KEY, user_id TEXT NOT NULL, kind TEXT NOT NULL, amount BIGINT NOT NULL, peer_id TEXT, ref TEXT, note TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE TABLE IF NOT EXISTS biz (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, name_ar TEXT NOT NULL DEFAULT '', category TEXT NOT NULL, sector TEXT NOT NULL DEFAULT '',
      description TEXT NOT NULL DEFAULT '', lat DOUBLE PRECISION NOT NULL, lng DOUBLE PRECISION NOT NULL, address TEXT NOT NULL DEFAULT '',
      hours TEXT NOT NULL DEFAULT '', phone TEXT, website TEXT, color TEXT, highlights JSONB NOT NULL DEFAULT '[]', verified BOOLEAN NOT NULL DEFAULT false,
      official BOOLEAN NOT NULL DEFAULT false, active BOOLEAN NOT NULL DEFAULT true, sort INT NOT NULL DEFAULT 0, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    ALTER TABLE biz ADD COLUMN IF NOT EXISTS owner_id TEXT;
    ALTER TABLE biz ADD COLUMN IF NOT EXISTS logo_url TEXT;
    ALTER TABLE biz ADD COLUMN IF NOT EXISTS cover_url TEXT;
    ALTER TABLE biz ADD COLUMN IF NOT EXISTS views INT NOT NULL DEFAULT 0;
    ALTER TABLE biz ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
    CREATE TABLE IF NOT EXISTS biz_items (
      id TEXT PRIMARY KEY, biz_id TEXT NOT NULL REFERENCES biz(id) ON DELETE CASCADE, kind TEXT NOT NULL, title TEXT NOT NULL, description TEXT NOT NULL DEFAULT '',
      price BIGINT NOT NULL, unit TEXT NOT NULL DEFAULT 'item', stock INT, meta JSONB NOT NULL DEFAULT '{}', image_url TEXT, active BOOLEAN NOT NULL DEFAULT true, sort INT NOT NULL DEFAULT 0);
    CREATE INDEX IF NOT EXISTS biz_items_biz ON biz_items(biz_id, sort);
    CREATE TABLE IF NOT EXISTS biz_orders (
      id UUID PRIMARY KEY, biz_id TEXT NOT NULL, item_id TEXT NOT NULL, user_id TEXT NOT NULL, kind TEXT NOT NULL, qty INT NOT NULL DEFAULT 1,
      start_at TIMESTAMPTZ, end_at TIMESTAMPTZ, units INT NOT NULL DEFAULT 1, total BIGINT NOT NULL, status TEXT NOT NULL DEFAULT 'confirmed',
      code TEXT NOT NULL UNIQUE, note TEXT NOT NULL DEFAULT '', meta JSONB NOT NULL DEFAULT '{}', created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE INDEX IF NOT EXISTS biz_orders_user ON biz_orders(user_id, created_at DESC);
    CREATE INDEX IF NOT EXISTS biz_orders_item ON biz_orders(item_id, status);
    CREATE INDEX IF NOT EXISTS biz_orders_biz ON biz_orders(biz_id, created_at DESC);
    CREATE TABLE IF NOT EXISTS biz_follows (biz_id TEXT NOT NULL, user_id TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (biz_id, user_id));
    CREATE TABLE IF NOT EXISTS biz_reviews (
      biz_id TEXT NOT NULL, user_id TEXT NOT NULL, rating INT NOT NULL, text TEXT NOT NULL DEFAULT '', created_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (biz_id, user_id));
    ALTER TABLE biz_reviews ADD COLUMN IF NOT EXISTS reply TEXT;
    ALTER TABLE biz_reviews ADD COLUMN IF NOT EXISTS reply_at TIMESTAMPTZ;
    CREATE TABLE IF NOT EXISTS biz_claims (
      biz_id TEXT NOT NULL, user_id TEXT NOT NULL, note TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'pending', created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      PRIMARY KEY (biz_id, user_id));
    CREATE TABLE IF NOT EXISTS biz_posts (
      id UUID PRIMARY KEY, biz_id TEXT NOT NULL REFERENCES biz(id) ON DELETE CASCADE, kind TEXT NOT NULL DEFAULT 'news', title TEXT NOT NULL, body TEXT NOT NULL DEFAULT '',
      image_url TEXT, starts_at TIMESTAMPTZ, ends_at TIMESTAMPTZ, active BOOLEAN NOT NULL DEFAULT true, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE INDEX IF NOT EXISTS biz_posts_biz ON biz_posts(biz_id, created_at DESC);
    CREATE TABLE IF NOT EXISTS biz_staff (biz_id TEXT NOT NULL, user_id TEXT NOT NULL, role TEXT NOT NULL DEFAULT 'staff', created_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (biz_id, user_id));
  `);

  // ---- بذر البيانات الأولية: استعلامان مجمّعان فقط ولا يوقفان الإقلاع. الدوائر التي صار لها مالك لا تُلمس
  // (حتى لا تُمحى تعديلات أصحابها عند إعادة التشغيل).
  async function seedAll() {
    const bv = [], bp = [];
    SEED.forEach((b, i) => {
      const o = bp.length;
      bv.push(`($${o + 1},$${o + 2},$${o + 3},$${o + 4},$${o + 5},$${o + 6},$${o + 7},$${o + 8},$${o + 9},$${o + 10},$${o + 11},$${o + 12},$${o + 13},$${o + 14},$${o + 15})`);
      bp.push(b.id, b.name, b.nameAr ?? "", b.category, b.sector ?? "", b.description ?? "", b.lat, b.lng, b.address ?? "", b.hours ?? "", b.phone ?? null, b.website ?? null, b.color ?? null, JSON.stringify(b.highlights ?? []), i);
    });
    await pool.query(`INSERT INTO biz(id,name,name_ar,category,sector,description,lat,lng,address,hours,phone,website,color,highlights,sort) VALUES ${bv.join(",")}
      ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, name_ar=EXCLUDED.name_ar, category=EXCLUDED.category, sector=EXCLUDED.sector, description=EXCLUDED.description,
        lat=EXCLUDED.lat, lng=EXCLUDED.lng, address=EXCLUDED.address, hours=EXCLUDED.hours, phone=EXCLUDED.phone, website=EXCLUDED.website, color=EXCLUDED.color,
        highlights=EXCLUDED.highlights, sort=EXCLUDED.sort, active=true WHERE biz.owner_id IS NULL`, bp);
    const iv = [], ip = [];
    for (const b of SEED) {
      (b.items ?? []).forEach((it, j) => {
        const o = ip.length;
        iv.push(`($${o + 1},$${o + 2},$${o + 3},$${o + 4},$${o + 5},$${o + 6},$${o + 7},$${o + 8},$${o + 9},$${o + 10},$${o + 11})`);
        ip.push(it.id, b.id, it.kind, it.title, it.description ?? "", it.price, it.unit ?? "item", it.stock ?? null, JSON.stringify(it.meta ?? {}), it.imageUrl ?? null, j);
      });
    }
    if (iv.length) await pool.query(`INSERT INTO biz_items(id,biz_id,kind,title,description,price,unit,stock,meta,image_url,sort) VALUES ${iv.join(",")}
      ON CONFLICT (id) DO UPDATE SET biz_id=EXCLUDED.biz_id, kind=EXCLUDED.kind, title=EXCLUDED.title, description=EXCLUDED.description, price=EXCLUDED.price,
        unit=EXCLUDED.unit, stock=EXCLUDED.stock, meta=EXCLUDED.meta, image_url=EXCLUDED.image_url, sort=EXCLUDED.sort, active=true
      WHERE (SELECT owner_id FROM biz WHERE id=EXCLUDED.biz_id) IS NULL`, ip);
  }
  let seedState = "pending";
  const seeding = seedAll().then(() => { seedState = "ok"; }).catch((e) => { seedState = "error: " + (e?.message || e); try { app.log.error({ err: e }, "business: seed failed"); } catch { console.error("business: seed failed", e); } });

  // جسر صحة محلي: نسخة النشر التلقائي المثبّتة على الخادم تفحص http://127.0.0.1:3000/health بينما التطبيق
  // يستمع على PORT (4000)، فيفشل الفحص ويتراجع عن كل نشر ويعيد التشغيل كل دقيقتين. نفتح مستمعاً على 3000
  // (localhost فقط) يمرّر GET /health إلى المنفذ الحقيقي حتى يمرّ الفحص. يُعطَّل بـ NASLIFE_HEALTH_BRIDGE=0
  // ويُهمَل تلقائياً إن كان 3000 مشغولاً أو هو منفذ التطبيق نفسه. (تم تصحيح autodeploy.sh أيضاً ليكتشف المنفذ.)
  if (process.env.NASLIFE_HEALTH_BRIDGE !== "0") {
    let tries = 0;
    let bridge = null;
    app.addHook("onClose", async () => { try { bridge?.close(); } catch { /* ignore */ } });
    const arm = () => {
      const addr = (() => { try { return app.server?.address?.(); } catch { return null; } })();
      const real = addr && typeof addr === "object" ? addr.port : null;
      if (!real) { if (++tries < 120) setTimeout(arm, 500).unref(); return; }
      if (real === 3000) return;
      bridge = http.createServer((req, res) => {
        if (req.method !== "GET" || !/^\/(health|biz\/status)(\?|$)/.test(req.url ?? "")) { res.writeHead(404); return res.end(); }
        const up = http.request({ host: "127.0.0.1", port: real, path: req.url, method: "GET", timeout: 4000 }, (r) => { res.writeHead(r.statusCode ?? 502, { "content-type": r.headers["content-type"] ?? "text/plain" }); r.pipe(res); });
        up.on("error", () => { res.writeHead(502); res.end(); });
        up.on("timeout", () => up.destroy(new Error("timeout")));
        up.end();
      });
      bridge.on("error", () => {});
      bridge.listen(3000, "127.0.0.1");
      bridge.unref();
    };
    setTimeout(arm, 500).unref();
  }

  // تشخيص عام خفيف: زمن تشغيل العملية ومنفذ الاستماع الفعلي (يساعد فحص صحة النشر التلقائي)
  app.get("/biz/status", async () => {
    let addr = null; try { addr = app.server?.address?.() ?? null; } catch { addr = null; }
    return { ok: true, uptimeSec: Math.round(process.uptime()), seed: seedState, listen: addr, envPort: process.env.PORT ?? null, node: process.version };
  });

  const unauthorized = (reply) => reply.code(401).send({ error: "auth" });
  const bad = (reply, code, error, extra = {}) => reply.code(code).send({ error, ...extra });
  const optionalAuth = async (req) => { try { return (await auth(req)) || null; } catch { return null; } };
  const userRow = async (id) => { try { return (await pool.query("SELECT * FROM users WHERE id=$1", [id])).rows[0] ?? null; } catch { return null; } };
  // مدير النظام: عمود في جدول المستخدمين أو جدول admins الذي تديره لوحة الإدارة (server/admin.js)
  const isAdmin = async (uid) => {
    const u = await userRow(uid);
    if (u?.is_admin === true || u?.role === "admin") return true;
    try { return (await pool.query("SELECT 1 FROM admins WHERE user_id=$1", [uid])).rowCount > 0; } catch { return false; }
  };
  const isSuspended = async (uid) => { try { return (await pool.query("SELECT 1 FROM user_flags WHERE user_id=$1 AND suspended", [uid])).rowCount > 0; } catch { return false; } };
  const person = async (id) => {
    const u = await userRow(id);
    return u ? { id: u.id, nickname: u.nickname ?? "", avatarUrl: u.avatar_url ?? u.avatarUrl ?? null } : { id, nickname: "", avatarUrl: null };
  };
  const bbox = (s) => {
    const p = String(s ?? "").split(",").map(Number);
    return p.length === 4 && p.every(Number.isFinite) ? { minLng: p[0], minLat: p[1], maxLng: p[2], maxLat: p[3] } : null;
  };

  // ---- الصلاحيات: مالك / مدير / موظف / مدير النظام
  async function roleFor(uid, b) {
    if (!uid || !b) return null;
    if (b.owner_id === uid) return "owner";
    const s = (await pool.query("SELECT role FROM biz_staff WHERE biz_id=$1 AND user_id=$2", [b.id, uid])).rows[0];
    if (s) return s.role;
    return (await isAdmin(uid)) ? "admin" : null;
  }
  const canManage = (r) => r === "owner" || r === "manager" || r === "admin";
  const canOperate = (r) => canManage(r) || r === "staff";
  const canOwn = (r) => r === "owner" || r === "admin";
  async function loadBiz(id, { includeInactive = false } = {}) {
    if (!SLUG_RE.test(id ?? "")) return null;
    const r = await pool.query(`SELECT * FROM biz WHERE id=$1${includeInactive ? "" : " AND active"}`, [id]);
    return r.rows[0] ?? null;
  }
  /// يحمّل الدائرة ويتحقق من الصلاحية؛ يرد بالخطأ المناسب ويعيد null عند الفشل.
  async function guard(req, reply, level) {
    const uid = await auth(req); if (!uid) { unauthorized(reply); return null; }
    const b = await loadBiz(req.params.id, { includeInactive: true });
    if (!b) { bad(reply, 404, "not-found"); return null; }
    const role = await roleFor(uid, b);
    const ok = level === "own" ? canOwn(role) : level === "manage" ? canManage(role) : canOperate(role);
    if (!ok) { bad(reply, 403, "forbidden"); return null; }
    return { uid, b, role };
  }

  // ---- دفتر المحفظة (نفس جداول commerce.js وقواعده: قفل الصف، رصيد لا يقل عن صفر إلا لتسويات صاحب النشاط)
  async function ledger(client, userId, kind, amount, { peerId = null, ref = null, note = null, points = 0, allowNegative = false } = {}) {
    await client.query("INSERT INTO wallet_accounts(user_id) VALUES($1) ON CONFLICT DO NOTHING", [userId]);
    const acc = (await client.query("SELECT balance FROM wallet_accounts WHERE user_id=$1 FOR UPDATE", [userId])).rows[0];
    if (!allowNegative && Number(acc.balance) + amount < 0) throw Object.assign(new Error("insufficient"), { code: "insufficient-funds" });
    await client.query("UPDATE wallet_accounts SET balance=balance+$2, points=points+$3, updated_at=now() WHERE user_id=$1", [userId, amount, points]);
    await client.query("INSERT INTO wallet_tx(id,user_id,kind,amount,peer_id,ref,note) VALUES($1,$2,$3,$4,$5,$6,$7)", [crypto.randomUUID(), userId, kind, amount, peerId, ref, note]);
  }
  async function tx(fn) {
    const c = await pool.connect();
    try { await c.query("BEGIN"); const out = await fn(c); await c.query("COMMIT"); return out; }
    catch (e) { await c.query("ROLLBACK").catch(() => {}); throw e; }
    finally { c.release(); }
  }
  const fail = (code, extra = {}) => Object.assign(new Error(code), { code, ...extra });

  // ---- الإشعارات (server/notify.js إن كانت مسجّلة): لا تُفشل الطلب أبداً
  const notify = async (ids, payload) => { try { await globalThis.naslifeNotify?.(ids, payload); } catch (e) { try { app.log.warn({ err: e?.message }, "business: notify failed"); } catch { /* ignore */ } } };
  const notifyAdmins = async (payload) => { try { await globalThis.naslifeNotifyAdmins?.(payload); } catch { /* ignore */ } };
  const sar = (h) => { const v = Number(h) / 100; return (Number.isInteger(v) ? String(v) : v.toFixed(2)) + " ر.س"; };
  const nickOf = async (id) => (await person(id)).nickname || id;
  const bizName = (b) => b?.name_ar || b?.name || b?.id || "";
  const bizTeam = async (b) => [b.owner_id, ...(await pool.query("SELECT user_id FROM biz_staff WHERE biz_id=$1", [b.id])).rows.map((r) => r.user_id)].filter(Boolean);
  const bizManagers = async (b) => [b.owner_id, ...(await pool.query("SELECT user_id FROM biz_staff WHERE biz_id=$1 AND role='manager'", [b.id])).rows.map((r) => r.user_id)].filter(Boolean);
  const orderNoun = (kind) => (kind === "product" ? "طلب" : "حجز");

  // ---- مواعيد السينما: تُولَّد من أوقات العرض اليومية للأيام القادمة (بتوقيت السعودية)
  function showtimeSlots(item, now = new Date()) {
    const times = Array.isArray(item.meta?.times) ? item.meta.times : [];
    const local = new Date(now.getTime() + RIYADH_OFFSET_MIN * 60000);
    const y = local.getUTCFullYear(), m = local.getUTCMonth(), d = local.getUTCDate();
    const out = [];
    for (let day = 0; day < SHOWTIME_DAYS; day++) {
      for (const t of times) {
        const [hh, mm] = String(t).split(":").map(Number);
        if (!Number.isFinite(hh) || !Number.isFinite(mm)) continue;
        const at = new Date(Date.UTC(y, m, d + day, hh, mm) - RIYADH_OFFSET_MIN * 60000);
        if (at.getTime() > now.getTime() + 15 * 60000) out.push(at);
      }
    }
    return out;
  }
  const isSlot = (item, at) => showtimeSlots(item).some((s) => s.getTime() === at.getTime());

  async function bookedUnits(client, itemId, startAt, endAt) {
    const r = await client.query(
      "SELECT COALESCE(SUM(qty),0)::int AS n FROM biz_orders WHERE item_id=$1 AND status IN ('confirmed','used') AND start_at < $3 AND end_at > $2",
      [itemId, startAt, endAt]);
    return r.rows[0].n;
  }
  async function seatsTaken(client, itemId, at) {
    const r = await client.query("SELECT COALESCE(SUM(qty),0)::int AS n FROM biz_orders WHERE item_id=$1 AND status IN ('confirmed','used') AND start_at=$2", [itemId, at]);
    return r.rows[0].n;
  }

  // ---- المخرجات
  const bizOut = (b, extra = {}) => ({
    id: b.id, name: b.name, nameAr: b.name_ar, category: b.category, sector: b.sector, description: b.description, lat: b.lat, lng: b.lng, address: b.address,
    hours: b.hours, phone: b.phone, website: b.website, color: b.color, highlights: b.highlights ?? [], verified: b.verified, official: b.official, active: b.active !== false,
    logoUrl: b.logo_url ?? null, coverUrl: b.cover_url ?? null, ownerId: b.owner_id ?? null, views: Number(b.views ?? 0),
    followers: Number(b.followers ?? 0), rating: b.rating == null ? null : Number(b.rating), ratingCount: Number(b.rating_count ?? 0), minPrice: b.min_price == null ? null : Number(b.min_price),
    itemsCount: Number(b.items_count ?? 0), following: b.following === true, myRole: b.my_role ?? null, createdAt: b.created_at,
    openNow: isOpenNow(b.hours), distanceKm: roundKm(b.distance_km), ...extra,
  });
  async function itemOut(it, now = new Date()) {
    const base = { id: it.id, bizId: it.biz_id, kind: it.kind, title: it.title, description: it.description, price: Number(it.price), unit: it.unit, stock: it.stock, meta: it.meta ?? {}, imageUrl: it.image_url, active: it.active, sort: it.sort };
    if (it.kind === "showtime") {
      const slots = showtimeSlots(it, now);
      const taken = slots.length ? (await pool.query("SELECT start_at, COALESCE(SUM(qty),0)::int AS n FROM biz_orders WHERE item_id=$1 AND status IN ('confirmed','used') AND start_at = ANY($2) GROUP BY start_at", [it.id, slots])).rows : [];
      const map = new Map(taken.map((r) => [new Date(r.start_at).getTime(), r.n]));
      base.slots = slots.map((s) => ({ startsAt: s.toISOString(), seatsLeft: Math.max(0, (it.stock ?? 0) - (map.get(s.getTime()) ?? 0)) }));
    }
    return base;
  }
  const orderOut = (o, extra = {}) => ({
    id: o.id, bizId: o.biz_id, bizName: o.biz_name ?? null, bizNameAr: o.biz_name_ar ?? null, category: o.category ?? null, itemId: o.item_id, title: o.item_title ?? null, kind: o.kind, qty: o.qty,
    startAt: o.start_at, endAt: o.end_at, units: o.units, total: Number(o.total), status: o.status, code: o.code, note: o.note, meta: o.meta ?? {}, createdAt: o.created_at, updatedAt: o.updated_at,
    cancellable: cancellable(o), ...extra,
  });
  const postOut = (p) => ({ id: p.id, bizId: p.biz_id, kind: p.kind, title: p.title, body: p.body, imageUrl: p.image_url, startsAt: p.starts_at, endsAt: p.ends_at, active: p.active, createdAt: p.created_at });
  // الإلغاء من العميل: المنتجات خلال 24 ساعة من الشراء، التذاكر قبل ساعتين من العرض، الغرف والسيارات قبل 24 ساعة من البداية
  function cancellable(o, now = Date.now()) {
    if (o.status !== "confirmed") return false;
    const start = o.start_at ? new Date(o.start_at).getTime() : null;
    if (o.kind === "product") return now - new Date(o.created_at).getTime() < DAY;
    if (o.kind === "showtime") return start != null && start - now > 2 * 3600000;
    return start != null && start - now > DAY;
  }
  const ORDER_JOIN = "SELECT o.*, i.title AS item_title, b.name AS biz_name, b.name_ar AS biz_name_ar, b.category FROM biz_orders o JOIN biz_items i ON i.id=o.item_id JOIN biz b ON b.id=o.biz_id";

  const LIST_SQL = `
    SELECT b.*, (SELECT count(*) FROM biz_follows f WHERE f.biz_id=b.id) AS followers,
      (SELECT round(avg(rating)::numeric, 1) FROM biz_reviews r WHERE r.biz_id=b.id) AS rating,
      (SELECT count(*) FROM biz_reviews r WHERE r.biz_id=b.id) AS rating_count,
      (SELECT min(price) FROM biz_items i WHERE i.biz_id=b.id AND i.active) AS min_price,
      (SELECT count(*) FROM biz_items i WHERE i.biz_id=b.id AND i.active) AS items_count,
      ($1::text IS NOT NULL AND EXISTS (SELECT 1 FROM biz_follows f WHERE f.biz_id=b.id AND f.user_id=$1)) AS following,
      CASE WHEN $1::text IS NOT NULL AND b.owner_id=$1 THEN 'owner' ELSE (SELECT role FROM biz_staff s WHERE s.biz_id=b.id AND s.user_id=$1) END AS my_role
    FROM biz b WHERE true`;

  // ---- القائمة (عامة) مع تصفية بالفئة والحدود الجغرافية والبحث
  app.get("/biz", async (req) => {
    await seeding;
    const uid = await optionalAuth(req);
    const cat = CATEGORIES.has(req.query?.category) ? req.query.category : null;
    const bb = bbox(req.query?.bbox);
    const q = str(req.query?.q, 60);
    const mine = req.query?.following === "1" && uid;
    // الفلاتر والترتيب: open=1 (مفتوح الآن)، minRating، sort=near|rating|popular|new مع lat/lng للمسافة
    const lat = num(req.query?.lat), lng = num(req.query?.lng);
    const geo = Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180;
    const sort = ["near", "rating", "popular", "new"].includes(req.query?.sort) ? req.query.sort : "default";
    const minRating = Math.min(5, Math.max(0, Number(req.query?.minRating) || 0));
    const openOnly = req.query?.open === "1";
    const order = { near: "distance_km ASC NULLS LAST, x.followers DESC", rating: "x.rating DESC NULLS LAST, x.rating_count DESC, x.followers DESC", popular: "x.followers DESC, x.views DESC, x.rating DESC NULLS LAST", new: "x.created_at DESC", default: "x.category, x.sort, x.name" }[sort];
    const r = await pool.query(`SELECT x.*, ${DIST("$9", "$10", "x.lat", "x.lng")} AS distance_km FROM (${LIST_SQL} AND b.active
      AND ($2::text IS NULL OR b.category=$2)
      AND ($3::float8 IS NULL OR (b.lat BETWEEN $4 AND $6 AND b.lng BETWEEN $3 AND $5))
      AND ($7::text = '' OR ${NORM("b.name")} LIKE $7 OR ${NORM("b.name_ar")} LIKE $7 OR ${NORM("b.sector")} LIKE $7 OR ${NORM("b.address")} LIKE $7
        OR EXISTS (SELECT 1 FROM biz_items i WHERE i.biz_id=b.id AND i.active AND ${NORM("i.title")} LIKE $7))
      AND ($8::bool = false OR EXISTS (SELECT 1 FROM biz_follows f WHERE f.biz_id=b.id AND f.user_id=$1))) x
      WHERE ($11::float8 <= 0 OR x.rating >= $11::float8)
      ORDER BY ${order} LIMIT 200`,
      [uid, cat, bb?.minLng ?? null, bb?.minLat ?? null, bb?.maxLng ?? null, bb?.maxLat ?? null, q ? likeOf(q) : "", !!mine, geo ? lat : null, geo ? lng : null, minRating]);
    const list = r.rows.map((b) => bizOut(b));
    return openOnly ? list.filter((b) => b.openNow === true) : list;
  });

  // ---- دوائري: ما أملكه أو أعمل فيه، وطلبات الملكية المعلّقة
  app.get("/biz/mine", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const admin = await isAdmin(uid);
    const r = await pool.query(`${LIST_SQL} AND (b.owner_id=$1 OR EXISTS (SELECT 1 FROM biz_staff s WHERE s.biz_id=b.id AND s.user_id=$1) OR $2::bool) ORDER BY b.updated_at DESC LIMIT 200`, [uid, admin]);
    const claims = (await pool.query("SELECT c.*, b.name, b.name_ar FROM biz_claims c JOIN biz b ON b.id=c.biz_id WHERE c.user_id=$1 ORDER BY c.created_at DESC", [uid])).rows
      .map((c) => ({ bizId: c.biz_id, name: c.name_ar || c.name, status: c.status, note: c.note, createdAt: c.created_at }));
    return { circles: r.rows.map((b) => bizOut(b, { myRole: admin && b.owner_id !== uid && !b.my_role ? "admin" : b.my_role })), claims, admin };
  });

  // ---- طلبات الملكية (للمدير)
  app.get("/biz/claims", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!(await isAdmin(uid))) return bad(reply, 403, "admin-only");
    const r = await pool.query("SELECT c.*, b.name, b.name_ar FROM biz_claims c JOIN biz b ON b.id=c.biz_id WHERE c.status='pending' ORDER BY c.created_at");
    return Promise.all(r.rows.map(async (c) => ({ bizId: c.biz_id, name: c.name_ar || c.name, user: await person(c.user_id), note: c.note, createdAt: c.created_at })));
  });

  // ---- إنشاء دائرة تجارية جديدة (صاحبها هو المنشئ)
  function bizFieldsFrom(body, { partial = false } = {}) {
    const out = {};
    const has = (k) => body[k] !== undefined;
    if (!partial || has("name")) out.name = str(body.name, 60);
    if (!partial || has("nameAr")) out.name_ar = str(body.nameAr, 60);
    if (!partial || has("category")) out.category = CATEGORIES.has(body.category) ? body.category : (partial ? undefined : "brand");
    if (!partial || has("sector")) out.sector = str(body.sector, 60);
    if (!partial || has("description")) out.description = str(body.description, 2000);
    if (!partial || has("lat")) out.lat = num(body.lat);
    if (!partial || has("lng")) out.lng = num(body.lng);
    if (!partial || has("address")) out.address = str(body.address, 200);
    if (!partial || has("hours")) out.hours = str(body.hours, 120);
    if (!partial || has("phone")) out.phone = str(body.phone, 30) || null;
    if (!partial || has("website")) out.website = isUrl(body.website) ? str(body.website, 200) : null;
    if (!partial || has("color")) out.color = /^#[0-9a-fA-F]{6}$/.test(body.color ?? "") ? body.color : (partial ? undefined : null);
    if (!partial || has("highlights")) out.highlights = JSON.stringify((Array.isArray(body.highlights) ? body.highlights : []).map((h) => str(h, 60)).filter(Boolean).slice(0, 12));
    if (has("logoUrl")) out.logo_url = isUrl(body.logoUrl) ? str(body.logoUrl, 500) : null;
    if (has("coverUrl")) out.cover_url = isUrl(body.coverUrl) ? str(body.coverUrl, 500) : null;
    if (has("active")) out.active = body.active !== false;
    for (const k of Object.keys(out)) if (out[k] === undefined) delete out[k];
    return out;
  }
  app.post("/biz", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const f = bizFieldsFrom(req.body ?? {});
    if (!f.name && !f.name_ar) return bad(reply, 400, "bad-name");
    if (!f.name) f.name = f.name_ar;
    if (!Number.isFinite(f.lat) || !Number.isFinite(f.lng) || Math.abs(f.lat) > 90 || Math.abs(f.lng) > 180) return bad(reply, 400, "bad-location");
    const mineCount = (await pool.query("SELECT count(*)::int AS n FROM biz WHERE owner_id=$1", [uid])).rows[0].n;
    if (mineCount >= 20) return bad(reply, 409, "too-many");
    const slug = f.name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 30) || "biz";
    const id = `biz-${slug}-${crypto.randomBytes(2).toString("hex")}`;
    await pool.query(`INSERT INTO biz(id,name,name_ar,category,sector,description,lat,lng,address,hours,phone,website,color,highlights,owner_id,logo_url,cover_url,sort)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,1000)`,
      [id, f.name, f.name_ar, f.category, f.sector, f.description, f.lat, f.lng, f.address, f.hours, f.phone, f.website, f.color, f.highlights, uid, f.logo_url ?? null, f.cover_url ?? null]);
    const r = await pool.query(`${LIST_SQL} AND b.id=$2`, [uid, id]);
    return bizOut(r.rows[0]);
  });

  // ---- تعديل ملف الدائرة (مالك/مدير)
  app.patch("/biz/:id", async (req, reply) => {
    const g = await guard(req, reply, "manage"); if (!g) return;
    const f = bizFieldsFrom(req.body ?? {}, { partial: true });
    if ("name" in f && !f.name) delete f.name;
    if (("lat" in f || "lng" in f) && (!Number.isFinite(f.lat ?? g.b.lat) || !Number.isFinite(f.lng ?? g.b.lng))) return bad(reply, 400, "bad-location");
    if ("active" in f && !canOwn(g.role) && g.role !== "manager") delete f.active;
    const keys = Object.keys(f);
    if (keys.length) {
      const sets = keys.map((k, i) => `${k}=$${i + 2}`).join(", ");
      await pool.query(`UPDATE biz SET ${sets}, updated_at=now() WHERE id=$1`, [g.b.id, ...keys.map((k) => f[k])]);
    }
    const r = await pool.query(`${LIST_SQL} AND b.id=$2`, [g.uid, g.b.id]);
    return bizOut(r.rows[0]);
  });

  // ---- طلب ملكية دائرة مزروعة (المدير يوافق؛ إن كان الطالب مديراً تُمنح فوراً)
  app.post("/biz/:id/claim", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const b = await loadBiz(req.params.id, { includeInactive: true });
    if (!b) return bad(reply, 404, "not-found");
    if (b.owner_id) return bad(reply, 409, "already-owned");
    if (await isAdmin(uid)) {
      await pool.query("UPDATE biz SET owner_id=$2, updated_at=now() WHERE id=$1", [b.id, uid]);
      return { ok: true, status: "approved" };
    }
    await pool.query("INSERT INTO biz_claims(biz_id,user_id,note) VALUES($1,$2,$3) ON CONFLICT (biz_id,user_id) DO UPDATE SET note=EXCLUDED.note, status='pending', created_at=now()", [b.id, uid, str(req.body?.note, 300)]);
    await notifyAdmins({ kind: "biz_claim", title: "طلب ملكية جديد", body: `${await nickOf(uid)} يطلب ملكية ${bizName(b)}`, data: { bizId: b.id, userId: uid } });
    return { ok: true, status: "pending" };
  });
  app.post("/biz/:id/claims/:userId/:decision", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!(await isAdmin(uid))) return bad(reply, 403, "admin-only");
    if (!SLUG_RE.test(req.params.id) || !ID_RE.test(req.params.userId)) return bad(reply, 400, "bad-id");
    const approve = req.params.decision === "approve";
    if (!approve && req.params.decision !== "reject") return bad(reply, 400, "bad-decision");
    await tx(async (c) => {
      const r = await c.query("UPDATE biz_claims SET status=$3 WHERE biz_id=$1 AND user_id=$2 AND status='pending' RETURNING 1", [req.params.id, req.params.userId, approve ? "approved" : "rejected"]);
      if (!r.rowCount) throw fail("not-found");
      if (approve) {
        await c.query("UPDATE biz SET owner_id=$2, updated_at=now() WHERE id=$1 AND owner_id IS NULL", [req.params.id, req.params.userId]);
        await c.query("UPDATE biz_claims SET status='rejected' WHERE biz_id=$1 AND user_id<>$2 AND status='pending'", [req.params.id, req.params.userId]);
      }
    }).catch((e) => { if (e.code === "not-found") return bad(reply, 404, "not-found"); throw e; });
    if (reply.sent) return;
    const nm = bizName(await loadBiz(req.params.id, { includeInactive: true })) || req.params.id;
    await notify(req.params.userId, { kind: "claim_decided", title: approve ? "قُبل طلب الملكية" : "رُفض طلب الملكية", body: approve ? `أصبحت مالك ${nm}؛ افتح لوحة النشاط لإدارتها` : `لم يُقبل طلبك لملكية ${nm}`, data: { bizId: req.params.id, approved: approve } });
    return { ok: true };
  });
  app.post("/biz/:id/verify", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!(await isAdmin(uid))) return bad(reply, 403, "admin-only");
    if (!SLUG_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    await pool.query("UPDATE biz SET verified=$2, updated_at=now() WHERE id=$1", [req.params.id, req.body?.verified !== false]);
    return { ok: true };
  });

  // ---- التفاصيل (عامة): الكتالوج والأخبار والمراجعات، وطلبات المستخدم إن كان مسجّلاً؛ الدوائر الموقوفة لطاقمها فقط
  app.get("/biz/:id", async (req, reply) => {
    await seeding;
    const uid = await optionalAuth(req);
    if (!SLUG_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const r = await pool.query(`${LIST_SQL} AND b.id=$2`, [uid, req.params.id]);
    if (!r.rowCount) return bad(reply, 404, "not-found");
    const b = r.rows[0];
    const role = uid ? (b.my_role ?? (await roleFor(uid, b))) : null;
    if (!b.active && !canOperate(role)) return bad(reply, 404, "not-found");
    const staffView = canOperate(role);
    if (!staffView) pool.query("UPDATE biz SET views=views+1 WHERE id=$1", [b.id]).catch(() => {});
    const items = await Promise.all((await pool.query(`SELECT * FROM biz_items WHERE biz_id=$1${staffView ? "" : " AND active"} ORDER BY sort, title`, [b.id])).rows.map((it) => itemOut(it)));
    const reviews = await Promise.all((await pool.query("SELECT * FROM biz_reviews WHERE biz_id=$1 ORDER BY created_at DESC LIMIT 50", [b.id])).rows.map(async (x) => ({
      user: await person(x.user_id), rating: x.rating, text: x.text, createdAt: x.created_at, mine: x.user_id === uid, reply: x.reply, replyAt: x.reply_at })));
    const posts = (await pool.query(`SELECT * FROM biz_posts WHERE biz_id=$1${staffView ? "" : " AND active AND (starts_at IS NULL OR starts_at <= now()) AND (ends_at IS NULL OR ends_at >= now())"} ORDER BY created_at DESC LIMIT 30`, [b.id])).rows.map(postOut);
    const myOrders = uid ? (await pool.query(`${ORDER_JOIN} WHERE o.biz_id=$1 AND o.user_id=$2 ORDER BY o.created_at DESC LIMIT 50`, [b.id, uid])).rows.map((o) => orderOut(o)) : [];
    return bizOut(b, { myRole: role, items, reviews, posts, myOrders });
  });

  app.post("/biz/:id/follow", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const b = await loadBiz(req.params.id);
    if (!b) return bad(reply, 404, "not-found");
    await pool.query("INSERT INTO biz_follows(biz_id,user_id) VALUES($1,$2) ON CONFLICT DO NOTHING", [b.id, uid]);
    return { ok: true };
  });
  app.delete("/biz/:id/follow", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!SLUG_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    await pool.query("DELETE FROM biz_follows WHERE biz_id=$1 AND user_id=$2", [req.params.id, uid]);
    return { ok: true };
  });

  app.post("/biz/:id/reviews", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const rating = Math.round(Number(req.body?.rating)); const text = str(req.body?.text, 500);
    if (!(rating >= 1 && rating <= 5)) return bad(reply, 400, "bad-rating");
    const banned = globalThis.naslifeCheckText?.(text);
    if (banned) return reply.code(400).send({ error: "banned-words", word: banned });
    const b = await loadBiz(req.params.id);
    if (!b) return bad(reply, 404, "not-found");
    await pool.query("INSERT INTO biz_reviews(biz_id,user_id,rating,text) VALUES($1,$2,$3,$4) ON CONFLICT (biz_id,user_id) DO UPDATE SET rating=EXCLUDED.rating, text=EXCLUDED.text, created_at=now(), reply=NULL, reply_at=NULL", [b.id, uid, rating, text]);
    await notify(await bizManagers(b), { kind: "biz_review", title: `تقييم جديد ★${rating} · ${bizName(b)}`, body: `${await nickOf(uid)}${text ? ": " + text.slice(0, 100) : " قيّم نشاطك"}`, data: { bizId: b.id, userId: uid }, exclude: uid });
    return { ok: true };
  });
  // رد صاحب النشاط على تقييم
  app.post("/biz/:id/reviews/:userId/reply", async (req, reply) => {
    const g = await guard(req, reply, "manage"); if (!g) return;
    if (!ID_RE.test(req.params.userId)) return bad(reply, 400, "bad-id");
    const text = str(req.body?.text, 500);
    const r = await pool.query("UPDATE biz_reviews SET reply=$3, reply_at=CASE WHEN $3='' THEN NULL ELSE now() END WHERE biz_id=$1 AND user_id=$2 RETURNING 1", [g.b.id, req.params.userId, text || ""]);
    if (!r.rowCount) return bad(reply, 404, "not-found");
    if (text) await notify(req.params.userId, { kind: "review_reply", title: "ردّ على تقييمك", body: `${bizName(g.b)}: ${text.slice(0, 120)}`, data: { bizId: g.b.id }, exclude: g.uid });
    return { ok: true };
  });

  // ---- الكتالوج (مالك/مدير)
  function itemFieldsFrom(body, { partial = false, category = "brand" } = {}) {
    const out = {};
    const has = (k) => body[k] !== undefined;
    if (!partial) out.kind = KINDS.has(body.kind) ? body.kind : ({ cinema: "showtime", hotel: "room", car_rental: "car" }[category] ?? "product");
    if (!partial || has("title")) out.title = str(body.title, 100);
    if (!partial || has("description")) out.description = str(body.description, 500);
    if (!partial || has("price")) out.price = Math.max(0, Math.round(Number(body.price) || 0));
    if (!partial || has("stock")) out.stock = body.stock == null || body.stock === "" ? null : Math.max(0, Math.min(100000, Math.round(Number(body.stock) || 0)));
    if (!partial || has("meta")) {
      const m = body.meta && typeof body.meta === "object" ? { ...body.meta } : {};
      if (Array.isArray(m.times)) m.times = [...new Set(m.times.map((t) => str(t, 5)).filter((t) => TIME_RE.test(t)))].sort();
      if (m.oldPrice != null) m.oldPrice = Math.max(0, Math.round(Number(m.oldPrice) || 0)) || undefined;
      out.meta = JSON.stringify(m);
    }
    if (has("imageUrl")) out.image_url = isUrl(body.imageUrl) ? str(body.imageUrl, 500) : null;
    if (has("sort")) out.sort = Math.round(Number(body.sort) || 0);
    if (has("active")) out.active = body.active !== false;
    return out;
  }
  const unitOf = (kind) => ({ showtime: "ticket", room: "night", car: "day" }[kind] ?? "item");
  app.post("/biz/:id/items", async (req, reply) => {
    const g = await guard(req, reply, "manage"); if (!g) return;
    const f = itemFieldsFrom(req.body ?? {}, { category: g.b.category });
    if (!f.title) return bad(reply, 400, "bad-title");
    if (f.kind === "showtime" && !(JSON.parse(f.meta).times ?? []).length) return bad(reply, 400, "bad-times");
    if (f.kind !== "product" && f.stock == null) f.stock = f.kind === "showtime" ? 100 : 1;
    const count = (await pool.query("SELECT count(*)::int AS n FROM biz_items WHERE biz_id=$1", [g.b.id])).rows[0].n;
    if (count >= 300) return bad(reply, 409, "too-many");
    const id = `${g.b.id.replace(/^biz-/, "").slice(0, 20)}-${crypto.randomBytes(3).toString("hex")}`;
    await pool.query("INSERT INTO biz_items(id,biz_id,kind,title,description,price,unit,stock,meta,image_url,sort,active) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)",
      [id, g.b.id, f.kind, f.title, f.description, f.price, unitOf(f.kind), f.stock, f.meta, f.image_url ?? null, f.sort ?? count, f.active ?? true]);
    await pool.query("UPDATE biz SET updated_at=now() WHERE id=$1", [g.b.id]);
    return itemOut((await pool.query("SELECT * FROM biz_items WHERE id=$1", [id])).rows[0]);
  });
  app.patch("/biz/:id/items/:itemId", async (req, reply) => {
    const g = await guard(req, reply, "manage"); if (!g) return;
    if (!SLUG_RE.test(req.params.itemId)) return bad(reply, 400, "bad-id");
    const it = (await pool.query("SELECT * FROM biz_items WHERE id=$1 AND biz_id=$2", [req.params.itemId, g.b.id])).rows[0];
    if (!it) return bad(reply, 404, "not-found");
    const f = itemFieldsFrom(req.body ?? {}, { partial: true });
    if ("title" in f && !f.title) delete f.title;
    if (it.kind === "showtime" && "meta" in f && !(JSON.parse(f.meta).times ?? []).length) return bad(reply, 400, "bad-times");
    const keys = Object.keys(f);
    if (keys.length) {
      const sets = keys.map((k, i) => `${k}=$${i + 2}`).join(", ");
      await pool.query(`UPDATE biz_items SET ${sets} WHERE id=$1`, [it.id, ...keys.map((k) => f[k])]);
      await pool.query("UPDATE biz SET updated_at=now() WHERE id=$1", [g.b.id]);
    }
    return itemOut((await pool.query("SELECT * FROM biz_items WHERE id=$1", [it.id])).rows[0]);
  });
  app.delete("/biz/:id/items/:itemId", async (req, reply) => {
    const g = await guard(req, reply, "manage"); if (!g) return;
    if (!SLUG_RE.test(req.params.itemId)) return bad(reply, 400, "bad-id");
    // إخفاء لا حذف: الطلبات السابقة تشير إليه
    const r = await pool.query("UPDATE biz_items SET active=false WHERE id=$1 AND biz_id=$2 RETURNING 1", [req.params.itemId, g.b.id]);
    if (!r.rowCount) return bad(reply, 404, "not-found");
    return { ok: true };
  });

  // ---- الأخبار والعروض (مالك/مدير)
  function postFieldsFrom(body, { partial = false } = {}) {
    const out = {};
    const has = (k) => body[k] !== undefined;
    if (!partial || has("kind")) out.kind = POST_KINDS.has(body.kind) ? body.kind : (partial ? undefined : "news");
    if (!partial || has("title")) out.title = str(body.title, 100);
    if (!partial || has("body")) out.body = str(body.body, 2000);
    if (has("imageUrl")) out.image_url = isUrl(body.imageUrl) ? str(body.imageUrl, 500) : null;
    if (has("startsAt")) out.starts_at = body.startsAt ? new Date(body.startsAt) : null;
    if (has("endsAt")) out.ends_at = body.endsAt ? new Date(body.endsAt) : null;
    if (has("active")) out.active = body.active !== false;
    for (const k of Object.keys(out)) if (out[k] === undefined || (out[k] instanceof Date && isNaN(out[k]))) delete out[k];
    return out;
  }
  app.post("/biz/:id/posts", async (req, reply) => {
    const g = await guard(req, reply, "manage"); if (!g) return;
    const f = postFieldsFrom(req.body ?? {});
    if (!f.title) return bad(reply, 400, "bad-title");
    const bannedW = globalThis.naslifeCheckText?.(f.title, f.body);
    if (bannedW) return reply.code(400).send({ error: "banned-words", word: bannedW });
    const id = crypto.randomUUID();
    await pool.query("INSERT INTO biz_posts(id,biz_id,kind,title,body,image_url,starts_at,ends_at,active) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)",
      [id, g.b.id, f.kind, f.title, f.body, f.image_url ?? null, f.starts_at ?? null, f.ends_at ?? null, f.active ?? true]);
    await pool.query("UPDATE biz SET updated_at=now() WHERE id=$1", [g.b.id]);
    return postOut((await pool.query("SELECT * FROM biz_posts WHERE id=$1", [id])).rows[0]);
  });
  app.patch("/biz/:id/posts/:postId", async (req, reply) => {
    const g = await guard(req, reply, "manage"); if (!g) return;
    if (!UUID_RE.test(req.params.postId)) return bad(reply, 400, "bad-id");
    const f = postFieldsFrom(req.body ?? {}, { partial: true });
    if ("title" in f && !f.title) delete f.title;
    const keys = Object.keys(f);
    if (keys.length) {
      const sets = keys.map((k, i) => `${k}=$${i + 3}`).join(", ");
      const r = await pool.query(`UPDATE biz_posts SET ${sets} WHERE id=$1 AND biz_id=$2 RETURNING *`, [req.params.postId, g.b.id, ...keys.map((k) => f[k])]);
      if (!r.rowCount) return bad(reply, 404, "not-found");
      return postOut(r.rows[0]);
    }
    const r = await pool.query("SELECT * FROM biz_posts WHERE id=$1 AND biz_id=$2", [req.params.postId, g.b.id]);
    if (!r.rowCount) return bad(reply, 404, "not-found");
    return postOut(r.rows[0]);
  });
  app.delete("/biz/:id/posts/:postId", async (req, reply) => {
    const g = await guard(req, reply, "manage"); if (!g) return;
    if (!UUID_RE.test(req.params.postId)) return bad(reply, 400, "bad-id");
    const r = await pool.query("DELETE FROM biz_posts WHERE id=$1 AND biz_id=$2 RETURNING 1", [req.params.postId, g.b.id]);
    if (!r.rowCount) return bad(reply, 404, "not-found");
    return { ok: true };
  });

  // ---- الفريق (مالك)
  app.get("/biz/:id/team", async (req, reply) => {
    const g = await guard(req, reply, "manage"); if (!g) return;
    const rows = (await pool.query("SELECT * FROM biz_staff WHERE biz_id=$1 ORDER BY created_at", [g.b.id])).rows;
    return { owner: g.b.owner_id ? await person(g.b.owner_id) : null, staff: await Promise.all(rows.map(async (s) => ({ user: await person(s.user_id), role: s.role, since: s.created_at }))) };
  });
  app.post("/biz/:id/team", async (req, reply) => {
    const g = await guard(req, reply, "own"); if (!g) return;
    const userId = str(req.body?.userId, 12).toUpperCase(); const role = STAFF_ROLES.has(req.body?.role) ? req.body.role : "staff";
    if (!ID_RE.test(userId)) return bad(reply, 400, "bad-id");
    if (userId === g.b.owner_id) return bad(reply, 400, "is-owner");
    if (!(await userRow(userId))) return bad(reply, 404, "user-not-found");
    const n = (await pool.query("SELECT count(*)::int AS n FROM biz_staff WHERE biz_id=$1", [g.b.id])).rows[0].n;
    if (n >= 50) return bad(reply, 409, "too-many");
    await pool.query("INSERT INTO biz_staff(biz_id,user_id,role) VALUES($1,$2,$3) ON CONFLICT (biz_id,user_id) DO UPDATE SET role=EXCLUDED.role", [g.b.id, userId, role]);
    return { ok: true };
  });
  app.delete("/biz/:id/team/:userId", async (req, reply) => {
    const g = await guard(req, reply, "own"); if (!g) return;
    if (!ID_RE.test(req.params.userId)) return bad(reply, 400, "bad-id");
    await pool.query("DELETE FROM biz_staff WHERE biz_id=$1 AND user_id=$2", [g.b.id, req.params.userId]);
    return { ok: true };
  });
  // نقل الملكية (مالك)
  app.post("/biz/:id/transfer", async (req, reply) => {
    const g = await guard(req, reply, "own"); if (!g) return;
    const userId = str(req.body?.userId, 12).toUpperCase();
    if (!ID_RE.test(userId) || !(await userRow(userId))) return bad(reply, 404, "user-not-found");
    await tx(async (c) => {
      await c.query("UPDATE biz SET owner_id=$2, updated_at=now() WHERE id=$1", [g.b.id, userId]);
      await c.query("DELETE FROM biz_staff WHERE biz_id=$1 AND user_id=$2", [g.b.id, userId]);
      if (g.b.owner_id && g.b.owner_id !== userId) await c.query("INSERT INTO biz_staff(biz_id,user_id,role) VALUES($1,$2,'manager') ON CONFLICT DO NOTHING", [g.b.id, g.b.owner_id]);
    });
    await notify(userId, { kind: "biz_owner", title: "أصبحت مالك دائرة", body: `نُقلت إليك ملكية ${bizName(g.b)}؛ افتح لوحة النشاط لإدارتها`, data: { bizId: g.b.id }, exclude: g.uid });
    return { ok: true };
  });

  // ---- الشراء والحجز: منتج (كمية)، تذكرة سينما (موعد + عدد)، غرفة (من/إلى + عدد غرف)، سيارة (من/إلى)
  app.post("/biz/:id/orders", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (await isSuspended(uid)) return bad(reply, 403, "suspended");
    if (!SLUG_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const body = req.body ?? {};
    if (!SLUG_RE.test(body.itemId ?? "")) return bad(reply, 400, "bad-item");
    const qty = Math.max(1, Math.min(20, Math.round(Number(body.qty) || 1)));
    const note = str(body.note, 300);
    const startAt = body.startAt ? new Date(body.startAt) : null, endAt = body.endAt ? new Date(body.endAt) : null;
    if ((startAt && isNaN(startAt)) || (endAt && isNaN(endAt))) return bad(reply, 400, "bad-date");
    const id = crypto.randomUUID();
    let out;
    try {
      out = await tx(async (c) => {
        const b = (await c.query("SELECT * FROM biz WHERE id=$1 AND active", [req.params.id])).rows[0];
        if (!b) throw fail("not-found");
        const it = (await c.query("SELECT * FROM biz_items WHERE id=$1 AND biz_id=$2 AND active FOR UPDATE", [body.itemId, b.id])).rows[0];
        if (!it || !KINDS.has(it.kind)) throw fail("not-found");
        const price = Number(it.price);
        let units = 1, total = 0, s = null, e = null, meta = {};
        if (it.kind === "product") {
          if (it.stock != null && it.stock < qty) throw fail("sold-out", { left: it.stock });
          total = price * qty;
          if (it.stock != null) await c.query("UPDATE biz_items SET stock=stock-$2 WHERE id=$1", [it.id, qty]);
        } else if (it.kind === "showtime") {
          if (!startAt || !isSlot(it, startAt)) throw fail("bad-slot");
          if (qty > 10) throw fail("too-many");
          const taken = await seatsTaken(c, it.id, startAt);
          if (taken + qty > (it.stock ?? 0)) throw fail("sold-out", { left: Math.max(0, (it.stock ?? 0) - taken) });
          total = price * qty; s = startAt; e = new Date(startAt.getTime() + ((it.meta?.minutes ?? 120) * 60000));
          meta = { movie: it.title, hall: it.meta?.hall ?? null };
        } else {
          if (!startAt || !endAt) throw fail("bad-date");
          const days = Math.round((endAt.getTime() - startAt.getTime()) / DAY);
          if (days < 1 || days > 60) throw fail("bad-range");
          if (startAt.getTime() < Date.now() - DAY) throw fail("in-past");
          const rooms = it.kind === "room" ? Math.min(qty, 5) : 1;
          const booked = await bookedUnits(c, it.id, startAt, endAt);
          if (booked + rooms > (it.stock ?? 0)) throw fail("unavailable", { left: Math.max(0, (it.stock ?? 0) - booked) });
          units = days; total = price * days * rooms; s = startAt; e = endAt;
          meta = it.kind === "room" ? { rooms, guests: Math.max(1, Math.min(20, Math.round(Number(body.guests) || 1))) } : { pickup: b.address };
        }
        const finalQty = it.kind === "room" ? Math.min(qty, 5) : it.kind === "car" ? 1 : qty;
        const code = "NAS-" + crypto.randomBytes(4).toString("hex").toUpperCase();
        const label = `${b.name_ar || b.name} · ${it.title}`;
        if (total > 0) {
          await ledger(c, uid, "biz", -total, { ref: id, note: label, points: Math.floor(total / 1000), peerId: b.owner_id ?? null });
          // يُقيَّد المبلغ فوراً لمحفظة صاحب النشاط (كالتذاكر)، ويُخصم منه عند الاسترداد
          if (b.owner_id && b.owner_id !== uid) await ledger(c, b.owner_id, "biz_sale", total, { peerId: uid, ref: id, note: label, allowNegative: true });
        }
        await c.query("INSERT INTO biz_orders(id,biz_id,item_id,user_id,kind,qty,start_at,end_at,units,total,code,note,meta) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)",
          [id, b.id, it.id, uid, it.kind, finalQty, s, e, units, total, code, note, JSON.stringify(meta)]);
        return { id, code, total, b, it, qty: finalQty };
      });
    } catch (err) {
      if (err.code === "insufficient-funds") return bad(reply, 402, "insufficient-funds");
      if (err.code === "not-found") return bad(reply, 404, "not-found");
      if (["sold-out", "unavailable"].includes(err.code)) return bad(reply, 409, err.code, { left: err.left ?? 0 });
      if (["bad-slot", "bad-date", "bad-range", "in-past", "too-many"].includes(err.code)) return bad(reply, 400, err.code);
      throw err;
    }
    await notify(await bizTeam(out.b), { kind: "biz_order", title: `${orderNoun(out.it.kind)} جديد · ${bizName(out.b)}`,
      body: `${await nickOf(uid)}: ${out.it.title}${out.qty > 1 ? " × " + out.qty : ""} بقيمة ${sar(out.total)} · الرمز ${out.code}`, data: { bizId: out.b.id, orderId: out.id }, exclude: uid });
    const r = await pool.query(`${ORDER_JOIN} WHERE o.id=$1`, [out.id]);
    return orderOut(r.rows[0]);
  });

  app.get("/biz/orders/mine", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const r = await pool.query(`${ORDER_JOIN} WHERE o.user_id=$1 ORDER BY o.created_at DESC LIMIT 200`, [uid]);
    return r.rows.map((o) => orderOut(o));
  });

  // إلغاء من العميل (ضمن المهلة) أو من صاحب النشاط (في أي وقت ما دام الطلب مؤكداً): استرداد كامل
  async function cancelOrder(orderId, { byUser = null, force = false } = {}) {
    return tx(async (c) => {
      const o = (await c.query("SELECT o.*, i.title AS item_title, i.stock, b.name_ar, b.name, b.owner_id FROM biz_orders o JOIN biz_items i ON i.id=o.item_id JOIN biz b ON b.id=o.biz_id WHERE o.id=$1 FOR UPDATE OF o", [orderId])).rows[0];
      if (!o || (byUser && o.user_id !== byUser)) throw fail("not-found");
      if (force ? o.status !== "confirmed" : !cancellable(o)) throw fail("not-cancellable");
      await c.query("UPDATE biz_orders SET status='cancelled', updated_at=now() WHERE id=$1", [o.id]);
      if (o.kind === "product" && o.stock != null) await c.query("UPDATE biz_items SET stock=stock+$2 WHERE id=$1", [o.item_id, o.qty]);
      const label = `${o.name_ar || o.name} · ${o.item_title}`;
      if (Number(o.total) > 0) {
        await ledger(c, o.user_id, "biz_refund", Number(o.total), { ref: o.id, note: label, peerId: o.owner_id ?? null });
        if (o.owner_id && o.owner_id !== o.user_id) await ledger(c, o.owner_id, "biz_refund_out", -Number(o.total), { peerId: o.user_id, ref: o.id, note: label, allowNegative: true });
      }
      return o;
    });
  }
  app.post("/biz/orders/:id/cancel", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    let o;
    try { o = await cancelOrder(req.params.id, { byUser: uid }); }
    catch (err) {
      if (err.code === "not-found") return bad(reply, 404, "not-found");
      if (err.code === "not-cancellable") return bad(reply, 409, "not-cancellable");
      throw err;
    }
    await notify(await bizTeam({ id: o.biz_id, owner_id: o.owner_id }), { kind: "order_cancelled", title: `إلغاء ${orderNoun(o.kind)} · ${bizName(o)}`,
      body: `${await nickOf(uid)} ألغى ${o.item_title} (${o.code})${Number(o.total) > 0 ? " واستُرد " + sar(o.total) : ""}`, data: { bizId: o.biz_id, orderId: o.id }, exclude: uid });
    return { ok: true };
  });

  // ---- طلبات الدائرة لصاحبها وطاقمه، مع بيانات العميل وتصفية بالحالة والبحث بالرمز
  app.get("/biz/:id/orders", async (req, reply) => {
    const g = await guard(req, reply, "operate"); if (!g) return;
    const status = ["confirmed", "used", "cancelled", "upcoming", "today"].includes(req.query?.status) ? req.query.status : null;
    const q = str(req.query?.q, 40).toUpperCase();
    const extra = status === "upcoming" ? "AND o.status='confirmed' AND (o.start_at IS NULL OR o.start_at >= now() - interval '6 hours')"
      : status === "today" ? "AND o.status IN ('confirmed','used') AND (((o.start_at IS NOT NULL AND (o.start_at + interval '3 hours')::date = (now() + interval '3 hours')::date)) OR (o.start_at IS NULL AND (o.created_at + interval '3 hours')::date = (now() + interval '3 hours')::date))"
      : "";
    const exact = status && !["upcoming", "today"].includes(status) ? status : null;
    const r = await pool.query(`${ORDER_JOIN} WHERE o.biz_id=$1 AND ($2::text IS NULL OR o.status=$2) ${extra} AND ($3::text = '' OR o.code ILIKE '%' || $3 || '%') ORDER BY o.created_at DESC LIMIT 300`,
      [g.b.id, exact, q]);
    return Promise.all(r.rows.map(async (o) => orderOut(o, { customer: await person(o.user_id) })));
  });
  // تأكيد الاستلام/الاستخدام برمز الحجز (المالك والمدير والموظف)
  app.post("/biz/:id/checkin", async (req, reply) => {
    const g = await guard(req, reply, "operate"); if (!g) return;
    const code = str(req.body?.code, 40).toUpperCase();
    const orderId = UUID_RE.test(req.body?.orderId ?? "") ? req.body.orderId : null;
    if (!code && !orderId) return bad(reply, 400, "bad-code");
    const r = await pool.query("UPDATE biz_orders SET status='used', updated_at=now() WHERE biz_id=$1 AND status='confirmed' AND (($2 <> '' AND code=$2) OR ($3::uuid IS NOT NULL AND id=$3)) RETURNING id", [g.b.id, code, orderId]);
    if (!r.rowCount) {
      const exists = (await pool.query("SELECT status FROM biz_orders WHERE biz_id=$1 AND (($2 <> '' AND code=$2) OR ($3::uuid IS NOT NULL AND id=$3))", [g.b.id, code, orderId])).rows[0];
      return bad(reply, exists ? 409 : 404, exists ? `already-${exists.status}` : "code-invalid");
    }
    const o = (await pool.query(`${ORDER_JOIN} WHERE o.id=$1`, [r.rows[0].id])).rows[0];
    await notify(o.user_id, { kind: "order_status", title: o.kind === "product" ? "تم استلام طلبك" : "تم تأكيد حجزك", body: `${o.biz_name_ar || o.biz_name}: ${o.item_title} (${o.code})`, data: { bizId: o.biz_id, orderId: o.id, status: "used" }, exclude: g.uid });
    return orderOut(o, { customer: await person(o.user_id) });
  });
  app.post("/biz/:id/orders/:orderId/cancel", async (req, reply) => {
    const g = await guard(req, reply, "manage"); if (!g) return;
    if (!UUID_RE.test(req.params.orderId)) return bad(reply, 400, "bad-id");
    const o = (await pool.query("SELECT biz_id FROM biz_orders WHERE id=$1", [req.params.orderId])).rows[0];
    if (!o || o.biz_id !== g.b.id) return bad(reply, 404, "not-found");
    let o2;
    try { o2 = await cancelOrder(req.params.orderId, { force: true }); }
    catch (err) {
      if (err.code === "not-cancellable") return bad(reply, 409, "not-cancellable");
      if (err.code === "not-found") return bad(reply, 404, "not-found");
      throw err;
    }
    await notify(o2.user_id, { kind: "order_status", title: `أُلغي ${orderNoun(o2.kind)}ك`, body: `${bizName(o2)}: ${o2.item_title} (${o2.code})${Number(o2.total) > 0 ? " · استُرد " + sar(o2.total) + " إلى محفظتك" : ""}`,
      data: { bizId: o2.biz_id, orderId: o2.id, status: "cancelled" }, exclude: g.uid });
    return { ok: true };
  });

  // ---- الإحصاءات (المالك وطاقمه)
  app.get("/biz/:id/stats", async (req, reply) => {
    const g = await guard(req, reply, "operate"); if (!g) return;
    const id = g.b.id;
    const totals = (await pool.query(`SELECT
        count(*)::int AS total, count(*) FILTER (WHERE status='confirmed')::int AS confirmed, count(*) FILTER (WHERE status='used')::int AS used, count(*) FILTER (WHERE status='cancelled')::int AS cancelled,
        COALESCE(SUM(total) FILTER (WHERE status IN ('confirmed','used')),0)::bigint AS revenue,
        COALESCE(SUM(total) FILTER (WHERE status IN ('confirmed','used') AND created_at >= now() - interval '7 days'),0)::bigint AS revenue7,
        COALESCE(SUM(total) FILTER (WHERE status IN ('confirmed','used') AND created_at >= now() - interval '30 days'),0)::bigint AS revenue30,
        count(*) FILTER (WHERE status IN ('confirmed','used') AND created_at >= now() - interval '7 days')::int AS orders7,
        count(DISTINCT user_id)::int AS customers
      FROM biz_orders WHERE biz_id=$1`, [id])).rows[0];
    const byKind = (await pool.query("SELECT kind, count(*)::int AS count, COALESCE(SUM(total),0)::bigint AS total FROM biz_orders WHERE biz_id=$1 AND status IN ('confirmed','used') GROUP BY kind ORDER BY total DESC", [id])).rows;
    const daily = (await pool.query(`SELECT d::date AS day,
        COALESCE((SELECT count(*) FROM biz_orders o WHERE o.biz_id=$1 AND o.status IN ('confirmed','used') AND (o.created_at + interval '3 hours')::date = d::date),0)::int AS orders,
        COALESCE((SELECT SUM(total) FROM biz_orders o WHERE o.biz_id=$1 AND o.status IN ('confirmed','used') AND (o.created_at + interval '3 hours')::date = d::date),0)::bigint AS revenue
      FROM generate_series((now() + interval '3 hours')::date - 13, (now() + interval '3 hours')::date, '1 day') AS d ORDER BY d`, [id])).rows;
    const topItems = (await pool.query("SELECT o.item_id, i.title, count(*)::int AS count, COALESCE(SUM(o.total),0)::bigint AS total FROM biz_orders o JOIN biz_items i ON i.id=o.item_id WHERE o.biz_id=$1 AND o.status IN ('confirmed','used') GROUP BY o.item_id, i.title ORDER BY total DESC LIMIT 5", [id])).rows;
    const social = (await pool.query("SELECT (SELECT count(*) FROM biz_follows WHERE biz_id=$1)::int AS followers, (SELECT round(avg(rating)::numeric,1) FROM biz_reviews WHERE biz_id=$1) AS rating, (SELECT count(*) FROM biz_reviews WHERE biz_id=$1)::int AS reviews, (SELECT count(*) FROM biz_reviews WHERE biz_id=$1 AND reply IS NULL)::int AS unanswered, (SELECT views FROM biz WHERE id=$1) AS views", [id])).rows[0];
    const upcoming = (await pool.query("SELECT count(*)::int AS n FROM biz_orders WHERE biz_id=$1 AND status='confirmed' AND start_at IS NOT NULL AND start_at BETWEEN now() AND now() + interval '24 hours'", [id])).rows[0].n;
    return {
      orders: { total: totals.total, confirmed: totals.confirmed, used: totals.used, cancelled: totals.cancelled, last7: totals.orders7, next24h: upcoming, customers: totals.customers },
      revenue: { total: Number(totals.revenue), last7: Number(totals.revenue7), last30: Number(totals.revenue30) },
      byKind: byKind.map((k) => ({ kind: k.kind, count: k.count, total: Number(k.total) })),
      daily: daily.map((d) => ({ day: new Date(d.day).toISOString().slice(0, 10), orders: d.orders, revenue: Number(d.revenue) })),
      topItems: topItems.map((t) => ({ itemId: t.item_id, title: t.title, count: t.count, total: Number(t.total) })),
      followers: social.followers, rating: social.rating == null ? null : Number(social.rating), reviews: social.reviews, unanswered: social.unanswered, views: Number(social.views ?? 0),
    };
  });
}
