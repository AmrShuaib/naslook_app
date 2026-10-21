// الموقع المباشر والردود المقترحة في المحادثة (server/chat_live.js).
// الموقع المباشر: المُشارِك ينشئ جلسة (POST /chat/live) بمدة 15 أو 60 أو 480 دقيقة ثم يرسل رسالة عادية نصها "/live <id>"
// ويدفع موقعه كل 10 ثوانٍ (PUT)؛ الطرف الآخر يقرأ آخر موقع (GET) كل 10 ثوانٍ ما دامت البطاقة ظاهرة. لا يرى الجلسة إلا طرفاها،
// وتتوقف تلقائياً عند انقضاء المدة أو بإيقاف صاحبها (DELETE)؛ جلسة واحدة نشطة لكل زوج (من → إلى): بدء جديدة يوقف السابقة.
// الموقع لا يبقى بعد الانتهاء: الإيقاف والكنس يمسحان الإحداثيات من الصف، وGET لا يعيد موقعاً لجلسة غير نشطة.
// الردود المقترحة: POST /chat/suggest يعيد ثلاث جمل عربية قصيرة عبر مفتاح Anthropic المخزَّن في صندوق البريد
// (globalThis.naslifeAskClaude من inbox.js) أو قواعد محلية حين لا مفتاح أو عند أي خطأ؛ لا تُرسل معرّفات ولا أسماء إلى النموذج.
// التسجيل في register.txt:
//   await app.register((await import("./chat_live.js")).default, { pool, auth });
import crypto from "node:crypto";

const ID_RE = /^[A-Z]{2}\d{7}$/;
// صيغة UUID صارمة (8-4-4-4-12): غيرها 404 قبل الوصول إلى Postgres (وإلا 22P02 → 500)
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const LIVE_MINUTES = [15, 60, 480];
/// أقل فاصل بين دفعتي موقع من المُشارِك (مللي ثانية)
export const PUSH_MIN_MS = 5000;
export const SWEEP_MS = 5 * 60 * 1000;
export const SUGGEST_PER_MIN = 20;
export const SUGGEST_MAX_CHARS = 40;
export const SUGGEST_TURNS = 8;
export const SUGGEST_TEXT_MAX = 300;

const clamp = (s, n) => { const a = Array.from(String(s ?? "")); return (a.length > n ? a.slice(0, n) : a).join(""); };
const finite = (v) => (typeof v === "number" || (typeof v === "string" && v.trim() !== "")) && Number.isFinite(Number(v)) ? Number(v) : null;

// ---- محرّك القواعد: يُستعمل حين لا مفتاح أو عند فشل النموذج؛ يُختبر وحده
// توحيد الرسم: بلا تشكيل ولا تطويل، الهمزات ألفاً، التاء المربوطة هاءً، الألف المقصورة ياءً (تجي بكرة؟ = بكره)
const strip = (s) => String(s ?? "").replace(/[\u064B-\u0652\u0640]/g, "").replace(/[إأآ]/g, "ا").replace(/ة/g, "ه").replace(/ى/g, "ي").toLowerCase();
const RULES = [
  { re: /السلام عليكم|سلام عليكم/, out: ["وعليكم السلام ورحمة الله", "هلا والله", "أهلاً، كيف الحال؟"] },
  { re: /صباح الخير|صباح النور/, out: ["صباح النور", "صباح الخير، كيف الحال؟", "يسعد صباحك"] },
  { re: /مساء الخير|مساء النور/, out: ["مساء النور", "مساء الخير، كيف الحال؟", "يسعد مساك"] },
  { re: /(?<!\p{L})(هلا|مرحبا|اهلا|هاي|هلو)(?!\p{L})/u, out: ["هلا والله", "أهلاً وسهلاً", "كيف الحال؟"] },
  { re: /شكرا|مشكور|يعطيك العافيه|تسلم|ما قصرت/, out: ["العفو", "الله يعافيك", "بالخدمة دائماً"] },
  { re: /سعر|بكم|ريال|تكلف|خصم|عرض|ثمن|الحساب/, out: ["كم السعر؟", "فيه خصم؟", "تمام، أبغى واحد"] },
  { re: /(?<!\p{L})(وين|فين|اين)(?!\p{L})|موقع|مكان|وصلت|قريب من/u, out: ["أرسل لك موقعي", "أنا في الطريق", "كم باقي لك؟"] },
  { re: /موعد|متى|الساعه|نتقابل|نلتقي|بكره|الليله|نجتمع/, out: ["يناسبني", "أي وقت يناسبك؟", "خلني أتأكد"] },
  { re: /[؟?]/, out: ["نعم", "لا", "خلني أتأكد"] },
];
const DEFAULT_REPLIES = ["تمام", "أبشر", "خلني أرجع لك"];
/// ثلاث جمل قصيرة بحسب آخر رسالة من الطرف الآخر (وإلا آخر رسالة)
export function rulesFor(messages) {
  const list = Array.isArray(messages) ? messages : [];
  const peer = [...list].reverse().find((m) => m && m.mine !== true) ?? list[list.length - 1];
  const t = strip(peer?.text);
  if (!t) return [...DEFAULT_REPLIES];
  for (const r of RULES) if (r.re.test(t)) return [...r.out];
  return [...DEFAULT_REPLIES];
}
/// ينظّف ما أعاده النموذج: مصفوفة JSON من نصوص قصيرة، بلا تكرار، ثلاثة على الأكثر؛ null إن لم يُفهم
export function parseSuggestions(text) {
  const s = String(text ?? ""); const a = s.indexOf("["), b = s.lastIndexOf("]");
  if (a < 0 || b <= a) return null;
  let arr; try { arr = JSON.parse(s.slice(a, b + 1)); } catch { return null; }
  if (!Array.isArray(arr)) return null;
  const out = [];
  for (const v of arr) {
    const t = clamp(String(typeof v === "string" ? v : v?.text ?? "").replace(/\s+/g, " ").trim(), SUGGEST_MAX_CHARS).trim();
    if (t && !out.includes(t)) out.push(t);
    if (out.length === 3) break;
  }
  return out.length ? out : null;
}

export default async function chatLive(app, opts) {
  try {
    await setup(app, opts);
  } catch (e) {
    (app.log?.error ? app.log.error.bind(app.log) : console.error)(`chat_live disabled: ${e?.stack || e}`);
  }
}

async function setup(app, opts) {
  const { pool, auth } = opts;
  if (!pool || !auth) throw new Error("chat_live: pool and auth are required");
  await pool.query(`
    CREATE TABLE IF NOT EXISTS chat_live (
      id UUID PRIMARY KEY, from_id TEXT NOT NULL, to_id TEXT NOT NULL,
      lat DOUBLE PRECISION, lng DOUBLE PRECISION, accuracy REAL, updated_at TIMESTAMPTZ,
      until TIMESTAMPTZ NOT NULL, stopped_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE INDEX IF NOT EXISTS chat_live_pair ON chat_live(from_id, to_id) WHERE stopped_at IS NULL;
  `);
  const unauthorized = (reply) => reply.code(401).send({ error: "auth" });
  const bad = (reply, code, error, extra = {}) => reply.code(code).send({ error, ...extra });
  const blocked = async (a, b) => { try { const f = globalThis.naslifeIsBlocked; return f ? !!(await f(a, b)) : false; } catch { return false; } };

  // ---- الموقع المباشر
  const isActive = (r) => r.stopped_at == null && new Date(r.until).getTime() > Date.now();
  // الموقع يُرى ما دامت الجلسة نشطة فقط: بعد المدة أو الإيقاف يعود null ولو بقي في الصف لحظة قبل المسح
  const out = (r) => {
    const active = isActive(r);
    return {
      id: r.id, from: r.from_id, to: r.to_id,
      lat: active && r.lat != null ? Number(r.lat) : null, lng: active && r.lng != null ? Number(r.lng) : null,
      accuracy: active && r.accuracy != null ? Number(r.accuracy) : null, at: active && r.updated_at ? new Date(r.updated_at).toISOString() : null,
      until: new Date(r.until).toISOString(), active,
    };
  };
  const rowOf = async (id) => {
    if (!UUID_RE.test(String(id ?? ""))) return null;
    try { return (await pool.query("SELECT * FROM chat_live WHERE id=$1", [id])).rows[0] ?? null; } catch (e) { if (e?.code === "22P02") return null; throw e; }
  };
  const hasPosition = (r) => r.lat != null || r.lng != null || r.accuracy != null || r.updated_at != null;
  // إنهاء جلسة: يثبّت stopped_at (إن لم يكن: الآن، أو until للمنقضية) ويمسح الإحداثيات ووقتها حتى لا يبقى أثر للموقع بعد الموافقة
  const WIPE = "lat=NULL, lng=NULL, accuracy=NULL, updated_at=NULL";
  const end = (id, expired = false) => pool.query(`UPDATE chat_live SET stopped_at=COALESCE(stopped_at, ${expired ? "until" : "now()"}), ${WIPE} WHERE id=$1`, [id]);
  // كنس المنتهية: يُثبّت stopped_at = until للمنقضية (فلا يبقى صف «نشط» بلا نهاية في الفهرس الجزئي) ويمسح الإحداثيات من كل صف
  // منتهٍ ما زال يحملها (ومنها ما تركته نسخة سابقة كانت تُبقيها)؛ يعيد عدد الصفوف المعدّلة
  const sweep = async () => {
    try {
      return (await pool.query(`UPDATE chat_live SET stopped_at=COALESCE(stopped_at, until), ${WIPE}
        WHERE (stopped_at IS NULL AND until <= now())
           OR (stopped_at IS NOT NULL AND (lat IS NOT NULL OR lng IS NOT NULL OR accuracy IS NOT NULL OR updated_at IS NOT NULL))`)).rowCount;
    } catch { return 0; }
  };
  await sweep(); // عند الإقلاع: صفوف منتهية بمواقع من قبل هذه النسخة
  const sweepMs = opts.sweepMs ?? SWEEP_MS;
  const timer = setInterval(sweep, sweepMs); timer.unref?.();
  app.addHook("onClose", async () => clearInterval(timer));
  globalThis.naslifeChatLive = { sweep };

  app.get("/chat/live/status", async () => ({ ok: true, minutes: LIVE_MINUTES, pushMinMs: PUSH_MIN_MS, suggest: { ai: typeof globalThis.naslifeAskClaude === "function", perMin: SUGGEST_PER_MIN } }));

  app.post("/chat/live", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const b = req.body ?? {};
    const peer = String(b.peerId ?? "").trim().toUpperCase();
    if (!ID_RE.test(peer)) return bad(reply, 400, "bad-peer");
    if (peer === uid) return bad(reply, 400, "self");
    const minutes = Math.round(Number(b.minutes));
    if (!LIVE_MINUTES.includes(minutes)) return bad(reply, 400, "bad-minutes", { allowed: LIVE_MINUTES });
    if (await blocked(uid, peer)) return bad(reply, 403, "blocked");
    // جلسة واحدة نشطة لكل زوج: الجديدة توقف السابقة وتمسح موقعها
    await pool.query(`UPDATE chat_live SET stopped_at=now(), ${WIPE} WHERE from_id=$1 AND to_id=$2 AND stopped_at IS NULL`, [uid, peer]);
    const id = crypto.randomUUID();
    const r = await pool.query("INSERT INTO chat_live(id, from_id, to_id, until) VALUES($1,$2,$3, now() + ($4::int * interval '1 minute')) RETURNING *", [id, uid, peer, minutes]);
    return out(r.rows[0]);
  });

  app.put("/chat/live/:id", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const r = await rowOf(req.params.id);
    if (!r || (r.from_id !== uid && r.to_id !== uid)) return bad(reply, 404, "not-found");
    if (r.from_id !== uid) return bad(reply, 403, "not-sharer");
    if (!isActive(r)) return bad(reply, 409, "ended");
    const b = req.body ?? {};
    const lat = finite(b.lat), lng = finite(b.lng);
    if (lat == null || lng == null || Math.abs(lat) > 90 || Math.abs(lng) > 180) return bad(reply, 400, "bad-position");
    let acc = b.accuracy == null || b.accuracy === "" ? null : finite(b.accuracy);
    if (b.accuracy != null && b.accuracy !== "" && (acc == null || acc < 0 || acc > 5000)) return bad(reply, 400, "bad-accuracy");
    if (r.updated_at && Date.now() - new Date(r.updated_at).getTime() < PUSH_MIN_MS) return bad(reply, 429, "too-fast", { retryInMs: PUSH_MIN_MS });
    await pool.query("UPDATE chat_live SET lat=$2, lng=$3, accuracy=$4, updated_at=now() WHERE id=$1", [r.id, lat, lng, acc]);
    return { ok: true };
  });

  app.get("/chat/live/:id", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const r = await rowOf(req.params.id);
    if (!r || (r.from_id !== uid && r.to_id !== uid)) return bad(reply, 404, "not-found");
    // انقضت المدة ولم يمرّ الكنس بعد: نمسح الموقع عند أول قراءة (الرد لا يحمله على أي حال)
    if (!isActive(r) && hasPosition(r)) await end(r.id, r.stopped_at == null);
    return out(r);
  });

  app.delete("/chat/live/:id", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const r = await rowOf(req.params.id);
    if (!r || (r.from_id !== uid && r.to_id !== uid)) return bad(reply, 404, "not-found");
    if (r.from_id !== uid) return bad(reply, 403, "not-sharer");
    // idempotent: يحتفظ بأول stopped_at ويمسح الموقع
    if (r.stopped_at == null || hasPosition(r)) await end(r.id);
    return { ok: true };
  });

  // ---- الردود المقترحة
  const rate = new Map(); // uid → أوقات آخر الطلبات خلال دقيقة
  const allow = (uid) => {
    const now = Date.now(); const list = (rate.get(uid) ?? []).filter((t) => now - t < 60000);
    if (list.length >= SUGGEST_PER_MIN) { rate.set(uid, list); return false; }
    list.push(now); rate.set(uid, list); return true;
  };
  const SYSTEM = "أنت تقترح ردوداً جاهزة لمستخدم في تطبيق دردشة سعودي (ناس لايف). أعد مصفوفة JSON فقط فيها ثلاث جمل عربية قصيرة (أربعون حرفاً على الأكثر لكل جملة) تصلح رداً تالياً من «أنا» على آخر رسالة من الطرف الآخر، بلهجة ودّية طبيعية ومتنوّعة (موافقة، سؤال، تأجيل). لا شرح ولا ترقيم ولا أي نص خارج المصفوفة.";
  const transcript = (turns) => turns.map((m) => `${m.mine ? "أنا" : "الطرف الآخر"}: ${m.text}`).join("\n");
  app.post("/chat/suggest", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!allow(uid)) return bad(reply, 429, "rate-limit", { perMin: SUGGEST_PER_MIN });
    const b = req.body ?? {};
    const peer = String(b.peerId ?? "").trim().toUpperCase();
    if (!ID_RE.test(peer)) return bad(reply, 400, "bad-peer");
    const turns = (Array.isArray(b.messages) ? b.messages : []).slice(-SUGGEST_TURNS)
      .map((m) => ({ mine: m?.mine === true, text: clamp(String(m?.text ?? "").replace(/\s+/g, " ").trim(), SUGGEST_TEXT_MAX) }))
      .filter((m) => m.text);
    const rules = rulesFor(turns);
    const ask = globalThis.naslifeAskClaude;
    if (typeof ask !== "function" || !turns.length) return { suggestions: rules, source: "rules" };
    try {
      // لا معرّفات ولا أسماء: النص فقط بصفة «أنا» و«الطرف الآخر»
      const text = await ask({ system: SYSTEM, user: transcript(turns), maxTokens: 200, effort: "low" });
      const got = parseSuggestions(text);
      if (!got) return { suggestions: rules, source: "rules" };
      for (const r of rules) { if (got.length === 3) break; if (!got.includes(r)) got.push(r); }
      return { suggestions: got.slice(0, 3), source: "ai" };
    } catch (e) {
      app.log?.warn?.({ err: e?.message }, "chat_live: suggest fell back to rules");
      return { suggestions: rules, source: "rules" };
    }
  });
}
