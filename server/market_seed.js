// تمهيد السوق: بائعون وهميون بسِيَر واقعية ومنتجات وخدمات في كل التصنيفات (server/market_seed_data.js).
// الحسابات تُنشأ عبر مسار التسجيل في النواة نفسها (كأي مستخدم)، والعروض تُدرج في market_listings مباشرة،
// وكل عنصر يُسجَّل في market_seed مرة واحدة فلا يعود بعد حذفه أو تعديله من الإدارة.
import crypto from "node:crypto";
import { SELLERS, LISTINGS, AREAS } from "./market_seed_data.js";

const NICK_RE = /^[a-z0-9_]{3,25}$/;
const ID_RE = /^SA\d{7}$/;

export default async function marketSeed(app, { pool, auth }) {
  await pool.query("CREATE TABLE IF NOT EXISTS market_seed (key TEXT PRIMARY KEY, user_id TEXT, at TIMESTAMPTZ NOT NULL DEFAULT now())");
  const BASE = (String(process.env.PUBLIC_BASE_URL ?? process.env.NASLIFE_PUBLIC_URL ?? "").trim() || "https://naslife.app").replace(/\/+$/, "");
  const log = (m, o = {}) => app.log?.info?.({ seed: "market", ...o }, m);
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const parse = (r) => { try { return r.json(); } catch { return {}; } };
  // إزاحة ثابتة من الحيّ حتى لا تتكدّس العروض على نقطة واحدة (±٨٠٠ م تقريباً)
  const jitter = (slug, i) => { const h = crypto.createHash("md5").update(slug + i).digest(); return ((h[0] << 8 | h[1]) / 65535 - 0.5) * 0.016; };
  const claim = async (key, userId = null) => (await pool.query("INSERT INTO market_seed(key, user_id) VALUES($1,$2) ON CONFLICT DO NOTHING RETURNING key", [key, userId])).rowCount > 0;
  const seededUser = async (nick) => (await pool.query("SELECT user_id FROM market_seed WHERE key=$1", ["user:" + nick])).rows[0]?.user_id ?? null;

  // تسجيل بائع عبر النواة ثم ضبط ملفه؛ يعيد المعرّف أو null (مع سبب)
  const registerSeller = async (s, i) => {
    if (!NICK_RE.test(s.nick)) return { error: "bad-nick" };
    const password = crypto.randomBytes(18).toString("base64url");
    const headers = { "content-type": "application/json", "x-forwarded-for": `10.77.${(i >> 8) & 255}.${i & 255}` };
    const r = await app.inject({ method: "POST", url: "/register", headers, payload: JSON.stringify({ handle: s.nick, nickname: s.nick, password }) });
    const body = parse(r);
    if (r.statusCode === 429) return { error: "rate-limited" };
    if (r.statusCode < 200 || r.statusCode >= 300) return { error: body?.error ?? "register-" + r.statusCode };
    const id = String(body.id ?? body.user?.id ?? "").toUpperCase();
    if (!ID_RE.test(id)) return { error: "no-id" };
    const token = body.token;
    if (token) {
      const patch = { bio: s.bio, skills: s.skills ?? [], hobbies: s.hobbies ?? [], lookingFor: s.looking ?? [], offerings: s.offerings ?? [], isPublic: true };
      await app.inject({ method: "PUT", url: "/me/profile", headers: { ...headers, "x-token": token, authorization: "Bearer " + token }, payload: JSON.stringify(patch) }).catch(() => null);
    }
    return { id };
  };

  const insertListing = async (l, sellerId) => {
    const [lat0, lng0] = AREAS[SELLERS.find((s) => s.nick === l.seller)?.area] ?? [null, null];
    const area = SELLERS.find((s) => s.nick === l.seller)?.area ?? null;
    const lat = lat0 == null ? null : lat0 + jitter(l.slug, 1), lng = lng0 == null ? null : lng0 + jitter(l.slug, 2);
    const days = Number(l.days) || 0;
    await pool.query(
      `INSERT INTO market_listings(id,seller_id,kind,category,title,description,price,image_url,place_name,lat,lng,status,created_at)
       VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,'active', now() - ($12 || ' days')::interval - (random() * interval '20 hours'))`,
      [crypto.randomUUID(), sellerId, l.kind === "service" ? "service" : "product", l.category, l.title, l.desc ?? "", Math.round(Number(l.price) * 100),
       `${BASE}/seed/market/${l.slug}.jpg`, area ? area.split("،")[0].trim() : null, lat, lng, String(days)]);
  };

  // تشغيل التمهيد: يعيد ملخصاً؛ يتوقف عند حدّ التسجيل في النواة ويعاود بعد ربع ساعة (حتى ٨ مرات) ثم في الإقلاع التالي
  let running = false, retries = 0;
  const scheduleRetry = () => { if (retries++ >= 8) return; setTimeout(() => run().catch(() => {}), 15 * 60 * 1000).unref?.(); };
  const run = async () => {
    if (running) return { busy: true };
    running = true;
    const out = { users: 0, listings: 0, skipped: [], errors: [] };
    try {
      const ok = (await pool.query("SELECT to_regclass('public.market_listings') AS t")).rows[0]?.t;
      if (!ok) { out.errors.push("no-market-table"); return out; }
      const ids = new Map();
      for (const [i, s] of SELLERS.entries()) {
        let id = await seededUser(s.nick);
        if (!id) {
          const r = await registerSeller(s, i + 1);
          if (r.error === "rate-limited") { out.errors.push("rate-limited at " + s.nick); scheduleRetry(); break; }
          if (r.error) { out.skipped.push(s.nick + ":" + r.error); continue; }
          id = r.id;
          await pool.query("INSERT INTO market_seed(key, user_id) VALUES($1,$2) ON CONFLICT (key) DO UPDATE SET user_id=EXCLUDED.user_id", ["user:" + s.nick, id]);
          out.users++;
          await sleep(250);
        }
        ids.set(s.nick, id);
      }
      for (const l of LISTINGS) {
        const sellerId = ids.get(l.seller); if (!sellerId) continue;
        if (!(await claim("listing:" + l.slug, sellerId))) continue;
        try { await insertListing(l, sellerId); out.listings++; }
        catch (e) { out.errors.push(l.slug + ":" + (e?.message ?? e)); await pool.query("DELETE FROM market_seed WHERE key=$1", ["listing:" + l.slug]); }
      }
      log("market seed done", out);
      return out;
    } finally { running = false; }
  };

  // بعد جاهزية كل الإضافات ومسارات النواة، وبتأخير قصير حتى لا يؤثر على فحص الصحة عند الإقلاع
  app.addHook("onReady", async () => { setTimeout(() => run().catch((e) => log("market seed failed: " + (e?.message ?? e))), 4000); });
  // تشغيل يدوي من الإدارة (بعد إضافة عناصر جديدة للبيانات مثلاً)
  app.post("/adminapi/market-seed/run", async (req, reply) => {
    const a = auth ?? globalThis.naslifeAuth; const uid = a ? await a(req).catch(() => null) : null;
    const isAdmin = await globalThis.naslifeIsAdmin?.(uid ?? "");
    if (!uid || !isAdmin) return reply.code(403).send({ error: "admin-only" });
    return run();
  });
  globalThis.naslifeMarketSeed = run;
}
