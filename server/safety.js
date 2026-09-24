// الأمان والإشراف في Naslife: كتم المحادثات، بلاغات المحتوى (منشورات الخريطة، السوق، الدوائر، الفعاليات…) مع إخفاء تلقائي
// عند بلوغ حدّ البلاغات، طابور إشراف للإدارة (/adminapi/moderation)، فلتر الكلمات المحظورة (قائمة افتراضية + ما تضبطه الإدارة)،
// وقائمة المحظورين من جدول الحظر في النواة user_blocks لتصفية المحتوى.
// يعرّف للإضافات الأخرى: globalThis.naslifeCheckText(...نصوص) → الكلمة المحظورة أو null،
// وglobalThis.naslifeBlockedIds(uid) → معرّفات من حظرهم المستخدم أو حظروه، وglobalThis.naslifeIsBlocked(a, b) → true/false،
// وglobalThis.naslifeHideContent(type, id, {hide, by}) → true إن تغيّرت حالة المحتوى.
// التسجيل في src/index.js قبل admin.js:
//   await app.register((await import("./safety.js")).default, { pool, auth });
import crypto from "node:crypto";
import { normQ } from "./business.js";

const UUID_RE = /^[0-9a-f-]{36}$/i;
const ID_RE = /^[A-Z]{2}\d{7}$/i;
const SLUG_RE = /^[a-z0-9-]{3,60}$/;
const CORE_ID_RE = /^[A-Za-z0-9_-]{1,64}$/;
export const TARGET_TYPES = ["post", "listing", "community", "vessel-post", "community-reply", "listing-question", "listing-review", "wanted", "wanted-reply",
  "biz", "biz-review", "biz-post", "event", "vessel-comment"];
const TARGETS = new Set(TARGET_TYPES);
export const MOD_ACTIONS = ["dismiss", "hide", "restore", "suspend-owner"];
const q = (ident) => `"${String(ident).replace(/"/g, '""')}"`;
const str = (v, max) => String(v ?? "").trim().slice(0, max);

/// الكلمات المحظورة من نص الإعدادات (سطر أو فاصلة لكل كلمة) مطبّعةً.
export function parseWords(raw) {
  return [...new Set(String(raw ?? "").split(/[\n,،;]+/).map((w) => normQ(w)).filter((w) => w.length >= 2))];
}
/// أول كلمة محظورة تظهر داخل النصوص (بعد التطبيع العربي) أو null.
export function findBanned(words, ...texts) {
  if (!words.length) return null;
  const t = normQ(texts.filter(Boolean).join(" "));
  if (!t) return null;
  for (const w of words) if (t.includes(w)) return w;
  return null;
}

// قائمة افتراضية متواضعة من الشتائم الصريحة (عربي وإنجليزي) حتى يعمل الفلتر من اليوم الأول.
// تُطابَق كلمةً كاملة لا جزءاً من كلمة (فلا تُرفض «زبدة» أو «class»)، مع سوابق عربية شائعة (و، ف، ب، ل، يا، ال).
// تجنّبنا الكلمات ذات المعنى العادي (كلب، حمار، خول، نيك…) لأن الرفض الخاطئ أسوأ من التفويت؛ الإدارة تكمل القائمة.
export const DEFAULT_BANNED = [
  "شرموطه", "شرموط", "شراميط", "قحبه", "قحاب", "كسمك", "كسختك", "كس امك", "كس اختك", "زبي", "طيزك", "منيوك", "منيوكه", "متناك", "متناكه",
  "انيكك", "انيك امك", "نيكني", "عرص", "عرصه", "معرص", "لوطي", "ديوث", "زانيه", "عاهره", "مومس", "ابن الكلب", "بنت الكلب", "ابن القحبه",
  "ابن الشرموطه", "يلعن ابوك", "يلعن امك", "كل زق", "fuck", "fucking", "fucker", "fucked", "motherfucker", "shit", "bullshit", "bitch", "bitches",
  "cunt", "asshole", "whore", "slut", "nigger", "nigga", "faggot", "kike", "porn", "porno",
].map((w) => normQ(w));
const DEFAULT_SINGLE = new Set(DEFAULT_BANNED.filter((w) => !w.includes(" ")));
const DEFAULT_PHRASES = DEFAULT_BANNED.filter((w) => w.includes(" "));
/// أول كلمة من القائمة الافتراضية تظهر كلمةً كاملة في النصوص، أو null.
export function findDefaultBanned(...texts) {
  const t = normQ(texts.filter(Boolean).join(" "));
  if (!t) return null;
  const tokens = t.split(/[^\p{L}\p{N}]+/u).filter(Boolean);
  for (const tok of tokens) {
    const cands = new Set([tok]);
    for (const c of [...cands]) { const m = /^(?:يا|و|ف|ب|ل)(.{2,})$/u.exec(c); if (m) cands.add(m[1]); }
    for (const c of [...cands]) { const m = /^(?:ال|لل)(.{2,})$/u.exec(c); if (m) cands.add(m[1]); }
    for (const c of cands) if (DEFAULT_SINGLE.has(c)) return c;
  }
  const padded = ` ${tokens.join(" ")} `;
  for (const ph of DEFAULT_PHRASES) if (padded.includes(` ${ph} `)) return ph;
  return null;
}


export default async function safety(app, opts) {
  const { pool, auth } = opts;
  if (!pool || !auth) throw new Error("safety: pool and auth are required");
  await pool.query(`
    CREATE TABLE IF NOT EXISTS chat_mutes (
      user_id TEXT NOT NULL, peer_id TEXT NOT NULL, until TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      PRIMARY KEY (user_id, peer_id));
    CREATE TABLE IF NOT EXISTS content_reports (
      id UUID PRIMARY KEY, reporter_id TEXT NOT NULL, target_type TEXT NOT NULL, target_id TEXT NOT NULL,
      reason TEXT NOT NULL DEFAULT '', created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      UNIQUE (reporter_id, target_type, target_id));
    CREATE INDEX IF NOT EXISTS content_reports_target ON content_reports(target_type, target_id);
    CREATE TABLE IF NOT EXISTS content_report_actions (
      id UUID PRIMARY KEY, target_type TEXT NOT NULL, target_id TEXT NOT NULL, action TEXT NOT NULL, note TEXT NOT NULL DEFAULT '',
      admin_id TEXT NOT NULL, owner_id TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE INDEX IF NOT EXISTS content_report_actions_target ON content_report_actions(target_type, target_id, created_at DESC);
    -- الحالة قبل الإخفاء: «إعادة الإظهار» ترجعها كما كانت (مسودة أو مخفي من صاحبه أو قيد المراجعة) لا «نشط» دائماً
    CREATE TABLE IF NOT EXISTS content_prev_state (target_type TEXT NOT NULL, target_id TEXT NOT NULL, prev TEXT NOT NULL,
      at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (target_type, target_id));
  `);
  const pick = (m, ...names) => names.find((n) => m?.has(n)) ?? null;

  // ---- جدول الحظر: user_blocks في النواة صراحةً. الاكتشاف الاحتياطي يستثني inbox_* (قائمة حظر البريد) وجداول البلاغات
  // ويرتّب الأسماء حتى لا يتغيّر الاختيار بين إقلاع وآخر (كان يلتقط inbox_blocked فيتعطل الحظر كله).
  let blocksTable = null, BC = null, blocksOk = false, blocksCheckedAt = 0;
  async function discoverBlocks() {
    blocksCheckedAt = Date.now();
    const cols = (await pool.query("SELECT table_name, column_name FROM information_schema.columns WHERE table_schema='public' AND table_name LIKE '%block%'")).rows;
    const tables = new Map();
    for (const c of cols) { if (!tables.has(c.table_name)) tables.set(c.table_name, new Set()); tables.get(c.table_name).add(c.column_name); }
    const fallback = [...tables.keys()].filter((t) => /block/.test(t) && !/report|^inbox_/.test(t)).sort()
      .find((t) => pick(tables.get(t), "user_id", "blocker_id", "by_id", "owner_id") && pick(tables.get(t), "blocked_id", "blocked_user_id", "target_id", "to_id"));
    blocksTable = tables.has("user_blocks") ? "user_blocks" : (fallback ?? null);
    BC = blocksTable === "user_blocks" && tables.get("user_blocks").has("user_id") && tables.get("user_blocks").has("blocked_id")
      ? { user: "user_id", blocked: "blocked_id" }
      : blocksTable ? { user: pick(tables.get(blocksTable), "user_id", "blocker_id", "by_id", "owner_id"), blocked: pick(tables.get(blocksTable), "blocked_id", "blocked_user_id", "target_id", "to_id") } : null;
    blocksOk = !!(BC?.user && BC?.blocked);
  }
  await discoverBlocks();
  if (!blocksOk) { try { app.log.warn("safety: no user blocks table found; blocking filters are inactive until the core creates user_blocks"); } catch { /* ignore */ } }
  async function blockedIds(uid) {
    if (!uid) return [];
    // النواة قد تنشئ الجدول بعد إقلاعنا: نعيد الاكتشاف مرة في الدقيقة على الأكثر
    if (!blocksOk && Date.now() - blocksCheckedAt > 60000) { try { await discoverBlocks(); } catch { /* ignore */ } }
    if (!blocksOk) return [];
    try {
      const r = await pool.query(`SELECT ${q(BC.user)} AS a, ${q(BC.blocked)} AS b FROM ${q(blocksTable)} WHERE ${q(BC.user)}=$1 OR ${q(BC.blocked)}=$1`, [uid]);
      const s = new Set();
      for (const row of r.rows) { if (row.a && row.a !== uid) s.add(row.a); if (row.b && row.b !== uid) s.add(row.b); }
      return [...s];
    } catch { return []; }
  }
  const isBlocked = async (a, b) => !!a && !!b && a !== b && (await blockedIds(a)).includes(b);
  const words = () => parseWords(globalThis.naslifeSettings?.bannedWords);
  const defaultsOn = () => globalThis.naslifeSettings?.bannedWordsDefault !== false;
  const checkText = (...texts) => findBanned(words(), ...texts) ?? (defaultsOn() ? findDefaultBanned(...texts) : null);
  const threshold = () => Math.max(1, Math.min(50, Math.round(Number(globalThis.naslifeSettings?.reportThreshold)) || 3));
  globalThis.naslifeCheckText = checkText;
  globalThis.naslifeBlockedIds = blockedIds;
  globalThis.naslifeIsBlocked = isBlocked;
  globalThis.naslifeSafetyStatus = () => ({ blocks: blocksOk, blocksTable });
  const notify = async (ids, payload) => { try { await globalThis.naslifeNotify?.(ids, payload); } catch { /* ignore */ } };
  const notifyAdmins = async (payload) => { try { await globalThis.naslifeNotifyAdmins?.(payload); } catch { /* ignore */ } };
  const unauthorized = (reply) => reply.code(401).send({ error: "auth" });
  const bad = (reply, code, error, extra = {}) => reply.code(code).send({ error, ...extra });
  const TYPE_NAMES = {
    post: "منشور", listing: "عرض", community: "منشور مجتمع", "vessel-post": "منشور دائرة", "community-reply": "رد في مساحة الدائرة",
    "listing-question": "سؤال على عرض", "listing-review": "تقييم في السوق", wanted: "طلب «أبحث عن»", "wanted-reply": "رد على طلب",
    biz: "دائرة تجارية", "biz-review": "تقييم دائرة", "biz-post": "خبر دائرة", event: "فعالية", "vessel-comment": "تعليق في دائرة",
  };
  const typeName = (type) => TYPE_NAMES[type] ?? "محتوى";

  // الحالة العامة بلا أسماء جداول داخلية (أسماء الجداول للإدارة فقط عبر /adminapi/overview)
  app.get("/safety/status", async () => ({ ok: true, blocks: blocksOk, words: words().length + (defaultsOn() ? DEFAULT_BANNED.length : 0), threshold: threshold() }));

  // ---- كتم المحادثات (الإشعارات في التطبيق؛ رسائل النواة تصل لكن بلا شارة)
  const muteOut = (r) => ({ peerId: r.peer_id, until: r.until, createdAt: r.created_at });
  app.get("/safety/mutes", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    await pool.query("DELETE FROM chat_mutes WHERE user_id=$1 AND until IS NOT NULL AND until < now()", [uid]);
    return (await pool.query("SELECT * FROM chat_mutes WHERE user_id=$1 ORDER BY created_at DESC", [uid])).rows.map(muteOut);
  });
  app.post("/safety/mutes", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const peer = str(req.body?.peerId, 12).toUpperCase();
    if (!ID_RE.test(peer) || peer === uid) return bad(reply, 400, "bad-peer");
    const hours = req.body?.hours == null ? null : Math.max(1, Math.min(24 * 365, Number(req.body.hours) || 0));
    const r = await pool.query(
      "INSERT INTO chat_mutes(user_id,peer_id,until) VALUES($1,$2, CASE WHEN $3::float8 IS NULL THEN NULL ELSE now() + ($3::float8 || ' hours')::interval END) ON CONFLICT (user_id,peer_id) DO UPDATE SET until=EXCLUDED.until, created_at=now() RETURNING *",
      [uid, peer, hours]);
    return muteOut(r.rows[0]);
  });
  app.delete("/safety/mutes/:peerId", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    await pool.query("DELETE FROM chat_mutes WHERE user_id=$1 AND peer_id=$2", [uid, str(req.params.peerId, 12).toUpperCase()]);
    return { ok: true };
  });

  // ---- الكلمات المحظورة: قائمة الإدارة للتحقق المسبق في التطبيق (القائمة الافتراضية تُطبَّق في الخادم فقط بمطابقة الكلمة الكاملة)، وفحص نص
  app.get("/safety/words", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    return { words: words(), threshold: threshold(), defaults: defaultsOn() ? DEFAULT_BANNED.length : 0 };
  });
  app.post("/safety/check", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const word = checkText(str(req.body?.text, 5000));
    return { ok: !word, word };
  });

  // ---- معرّفات المحتوى حسب النوع
  function validId(type, id) {
    if (!id) return false;
    if (type === "biz") return SLUG_RE.test(id);
    if (type === "biz-review") return /^[a-z0-9-]{3,60}:[A-Z]{2}\d{7}$/i.test(id);
    if (type === "vessel-post" || type === "vessel-comment") return CORE_ID_RE.test(id);
    return UUID_RE.test(id);
  }
  const normId = (type, id) => type === "biz-review" ? id.replace(/:(.+)$/, (_, u) => ":" + u.toUpperCase()) : id;
  const one = async (sql, params) => { try { return (await pool.query(sql, params)).rows[0] ?? null; } catch { return null; } };

  /// معلومات المحتوى المُبلَّغ عنه: المالك والعنوان والنص والوسائط وحالته (active|blocked) ومعرّفات مرتبطة
  async function targetInfo(type, id) {
    if (!validId(type, id)) return null;
    switch (type) {
      case "post": return one("SELECT user_id AS owner, COALESCE(NULLIF(title,''), NULLIF(caption,''), 'منشور') AS title, caption AS text, media_url AS media, status FROM map_posts WHERE id=$1", [id]);
      case "listing": return one("SELECT seller_id AS owner, title, description AS text, image_url AS media, status FROM market_listings WHERE id=$1", [id]);
      case "community": return one("SELECT user_id AS owner, COALESCE(NULLIF(left(text, 80), ''), 'منشور في مساحة الدائرة') AS title, text, images->>0 AS media, CASE WHEN hidden THEN 'blocked' ELSE 'active' END AS status, biz_id FROM biz_community_posts WHERE id=$1", [id]);
      case "community-reply": return one(`SELECT r.user_id AS owner, COALESCE(NULLIF(left(r.text, 80), ''), 'رد في مساحة الدائرة') AS title, r.text, r.images->>0 AS media,
        CASE WHEN r.hidden THEN 'blocked' ELSE 'active' END AS status, p.biz_id, r.post_id FROM biz_community_replies r JOIN biz_community_posts p ON p.id=r.post_id WHERE r.id=$1`, [id]);
      case "listing-question": return one(`SELECT q.user_id AS owner, left(q.text, 80) AS title, q.text, l.image_url AS media, CASE WHEN q.hidden THEN 'blocked' ELSE 'active' END AS status, q.listing_id
        FROM market_questions q LEFT JOIN market_listings l ON l.id=q.listing_id WHERE q.id=$1`, [id]);
      case "listing-review": return one(`SELECT r.buyer_id AS owner, COALESCE(NULLIF(left(r.text, 80), ''), 'تقييم ' || r.rating || '★') AS title, r.text, CASE WHEN r.hidden THEN 'blocked' ELSE 'active' END AS status,
        r.listing_id, r.seller_id FROM market_reviews r WHERE r.order_id=$1`, [id]);
      case "wanted": return one("SELECT user_id AS owner, title, description AS text, CASE WHEN status='blocked' THEN 'blocked' ELSE 'active' END AS status, id AS wanted_id FROM market_wanted WHERE id=$1", [id]);
      case "wanted-reply": return one(`SELECT r.seller_id AS owner, COALESCE(NULLIF(left(r.text, 80), ''), 'رد على طلب') AS title, r.text, l.image_url AS media, CASE WHEN r.hidden THEN 'blocked' ELSE 'active' END AS status, r.wanted_id
        FROM market_wanted_replies r LEFT JOIN market_listings l ON l.id=r.listing_id WHERE r.id=$1`, [id]);
      case "biz": return one("SELECT owner_id AS owner, COALESCE(NULLIF(name_ar,''), name) AS title, description AS text, COALESCE(cover_url, logo_url) AS media, CASE WHEN hidden THEN 'blocked' ELSE 'active' END AS status, id AS biz_id FROM biz WHERE id=$1", [id]);
      case "biz-review": {
        const [bizId, userId] = id.split(":");
        return one("SELECT user_id AS owner, COALESCE(NULLIF(left(text, 80), ''), 'تقييم ' || rating || '★') AS title, text, CASE WHEN hidden THEN 'blocked' ELSE 'active' END AS status, biz_id FROM biz_reviews WHERE biz_id=$1 AND user_id=$2", [bizId, userId]);
      }
      case "biz-post": return one("SELECT b.owner_id AS owner, p.title, p.body AS text, p.image_url AS media, CASE WHEN p.hidden THEN 'blocked' ELSE 'active' END AS status, p.biz_id FROM biz_posts p JOIN biz b ON b.id=p.biz_id WHERE p.id=$1", [id]);
      case "event": return one("SELECT host_id AS owner, title, description AS text, CASE WHEN hidden THEN 'blocked' ELSE 'active' END AS status FROM events WHERE id=$1", [id]);
      case "vessel-post": case "vessel-comment": {
        // المحتوى في النواة: المعلومات من vessel_mod.js إن وُجد، وإلا يُقبل البلاغ بلا تفاصيل
        const fn = type === "vessel-post" ? globalThis.naslifeVesselPostInfo : globalThis.naslifeVesselCommentInfo;
        try {
          const r = await fn?.(id);
          if (r === null) return null;
          if (r) return r;
        } catch { /* ignore */ }
        return { owner: null, title: type === "vessel-post" ? "منشور في دائرة" : "تعليق في دائرة", status: "active" };
      }
      default: return null;
    }
  }

  const savePrev = async (type, id, sql) => {
    try {
      const cur = (await pool.query(sql, [id])).rows[0]?.v;
      if (cur != null && String(cur) !== "blocked") await pool.query("INSERT INTO content_prev_state(target_type,target_id,prev) VALUES($1,$2,$3) ON CONFLICT (target_type,target_id) DO UPDATE SET prev=EXCLUDED.prev, at=now()", [type, id, String(cur)]);
    } catch { /* ignore */ }
  };
  const takePrev = async (type, id, allowed, def) => {
    try {
      const v = (await pool.query("DELETE FROM content_prev_state WHERE target_type=$1 AND target_id=$2 RETURNING prev", [type, id])).rows[0]?.prev;
      return allowed.includes(v) ? v : def;
    } catch { return def; }
  };

  /// إخفاء المحتوى أو إعادته؛ يعيد true إن تغيّرت حالته الآن
  async function setHidden(type, id, hide, { by = "reports", reason = "", info = null } = {}) {
    const upd = async (sql, params) => { try { return (await pool.query(sql, params)).rowCount > 0; } catch { return false; } };
    const flag = (table, key = "id") => upd(`UPDATE ${table} SET hidden=$2 WHERE ${key}=$1 AND hidden<>$2`, [id, hide]);
    switch (type) {
      case "post":
        if (hide) { await savePrev(type, id, "SELECT status AS v FROM map_posts WHERE id=$1"); return upd("UPDATE map_posts SET status='blocked', updated_at=now() WHERE id=$1 AND status<>'blocked'", [id]); }
        return upd("UPDATE map_posts SET status=$2, updated_at=now() WHERE id=$1 AND status='blocked'", [id, await takePrev(type, id, ["active", "hidden"], "active")]);
      case "listing":
        if (hide) { await savePrev(type, id, "SELECT status AS v FROM market_listings WHERE id=$1"); return upd("UPDATE market_listings SET status='blocked' WHERE id=$1 AND status<>'blocked'", [id]); }
        return upd("UPDATE market_listings SET status=$2 WHERE id=$1 AND status='blocked'", [id, await takePrev(type, id, ["active", "hidden", "draft", "pending", "scheduled", "sold"], "active")]);
      case "community":
        if (hide && globalThis.naslifeCommunityHide) { try { return !!(await globalThis.naslifeCommunityHide(id)); } catch { return false; } }
        return upd("UPDATE biz_community_posts SET hidden=$2, hidden_by=CASE WHEN $2 THEN $3 ELSE NULL END, updated_at=now() WHERE id=$1 AND hidden<>$2", [id, hide, str(by, 32)]);
      case "community-reply": return flag("biz_community_replies");
      case "listing-question": return flag("market_questions");
      case "listing-review": {
        const ok = await flag("market_reviews", "order_id");
        // التقييم المخفي لا يدخل في متوسط العرض ولا شارات البائع
        if (ok && info?.listing_id) {
          await upd("UPDATE market_listings SET rating_avg=(SELECT avg(rating) FROM market_reviews WHERE listing_id=$1 AND NOT hidden), rating_count=(SELECT count(*) FROM market_reviews WHERE listing_id=$1 AND NOT hidden) WHERE id=$1", [info.listing_id]);
          try { await globalThis.naslifeMarketRecomputeSeller?.(info.seller_id); } catch { /* ignore */ }
        }
        return ok;
      }
      case "wanted":
        if (hide) { await savePrev(type, id, "SELECT status AS v FROM market_wanted WHERE id=$1"); return upd("UPDATE market_wanted SET status='blocked' WHERE id=$1 AND status<>'blocked'", [id]); }
        return upd("UPDATE market_wanted SET status=$2 WHERE id=$1 AND status='blocked'", [id, await takePrev(type, id, ["open", "closed"], "open")]);
      case "wanted-reply": return flag("market_wanted_replies");
      case "biz":
        if (hide) { await savePrev(type, id, "SELECT CASE WHEN active THEN 'true' ELSE 'false' END AS v FROM biz WHERE id=$1"); return upd("UPDATE biz SET hidden=true, active=false, updated_at=now() WHERE id=$1 AND NOT hidden", [id]); }
        return upd("UPDATE biz SET hidden=false, active=$2, updated_at=now() WHERE id=$1 AND hidden", [id, (await takePrev(type, id, ["true", "false"], "true")) === "true"]);
      case "biz-review": { const [bizId, userId] = id.split(":"); return upd("UPDATE biz_reviews SET hidden=$3 WHERE biz_id=$1 AND user_id=$2 AND hidden<>$3", [bizId, userId, hide]); }
      case "biz-post": return flag("biz_posts");
      case "event": return flag("events");
      case "vessel-post": {
        try {
          return hide ? !!(await globalThis.naslifeVesselPostHide?.(id, { vesselId: info?.vessel_id ?? "", by, reason })) : !!(await globalThis.naslifeVesselPostUnhide?.(id));
        } catch { return false; }
      }
      case "vessel-comment": {
        try {
          return hide ? !!(await globalThis.naslifeVesselCommentHide?.(id, { postId: info?.post_id ?? "", vesselId: info?.vessel_id ?? "", by, reason })) : !!(await globalThis.naslifeVesselCommentUnhide?.(id));
        } catch { return false; }
      }
      default: return false;
    }
  }
  globalThis.naslifeHideContent = async (type, id, { hide = true, by = "system", reason = "" } = {}) => {
    if (!TARGETS.has(type) || !validId(type, id)) return false;
    const nid = normId(type, id);
    return setHidden(type, nid, hide, { by, reason, info: await targetInfo(type, nid) });
  };

  /// إشعار صاحب المحتوى بإخفائه أو إعادته (أنواع الإشعار القديمة محفوظة لأن التطبيق يفتح وجهتها)
  async function notifyOwner(type, id, info, { hidden, reports = 0, byAdmin = false, note = "" }) {
    if (!info?.owner) return;
    const name = typeName(type);
    const data = { targetType: type, targetId: id, reason: byAdmin ? "moderation" : "reports", reports };
    if (info.biz_id) data.bizId = info.biz_id;
    if (info.vessel_id) data.vesselId = info.vessel_id;
    if (info.listing_id) data.listingId = info.listing_id;
    if (info.wanted_id) data.wantedId = info.wanted_id;
    if (info.post_id) data.parentId = info.post_id;
    if (type === "post" || type === "community" || type === "vessel-post") data.postId = id;
    if (type === "listing") data.listingId = id;
    if (!hidden) {
      await notify([info.owner], { kind: "content_restored", title: `أُعيد إظهار ${name}`, body: `«${info.title}» ظاهر من جديد بعد المراجعة`, data });
      return;
    }
    const kind = { post: "post_blocked", listing: "listing_hidden", community: "community_hidden", "vessel-post": "vessel_post_hidden" }[type] ?? "content_hidden";
    const why = byAdmin ? "أخفته الإدارة بعد مراجعة البلاغات" : "قيد مراجعة الإدارة";
    await notify([info.owner], { kind, title: byAdmin ? `أخفت الإدارة ${name}` : `أُخفي ${name} بعد عدة بلاغات`, body: `«${info.title}» ${why}${note ? ` — ${note}` : ""}`, data });
  }

  async function autoHide(type, id, info, n) {
    const done = await setHidden(type, id, true, { by: "reports", reason: `${n} بلاغات`, info });
    if (!done) return false;
    await notifyOwner(type, id, info, { hidden: true, reports: n });
    await notifyAdmins({ kind: "content_autohidden", title: `أُخفي ${typeName(type)} تلقائياً بعد ${n} بلاغات`, body: `«${info.title}» — راجعه في طابور الإشراف`, data: { targetType: type, targetId: id, reports: n } });
    return true;
  }
  app.post("/safety/report", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const type = String(req.body?.targetType ?? ""); const reason = str(req.body?.reason, 300);
    if (!TARGETS.has(type)) return bad(reply, 400, "bad-target");
    const id = normId(type, str(req.body?.targetId, 128));
    const info = await targetInfo(type, id);
    if (!info) return bad(reply, 404, "not-found");
    if (info.owner === uid) return bad(reply, 400, "own-content");
    await pool.query("INSERT INTO content_reports(id,reporter_id,target_type,target_id,reason) VALUES($1,$2,$3,$4,$5) ON CONFLICT (reporter_id,target_type,target_id) DO UPDATE SET reason=EXCLUDED.reason, created_at=now()", [crypto.randomUUID(), uid, type, id, reason]);
    // بعد «إعادة الإظهار» أو «التجاهل» من الإدارة يبدأ العد من جديد، وإلا يعيد بلاغ واحد إخفاء ما راجعته الإدارة
    const n = (await pool.query(`SELECT count(DISTINCT reporter_id)::int AS n FROM content_reports WHERE target_type=$1 AND target_id=$2
      AND created_at > COALESCE((SELECT max(created_at) FROM content_report_actions WHERE target_type=$1 AND target_id=$2 AND action IN ('restore','dismiss')), '-infinity'::timestamptz)`, [type, id])).rows[0].n;
    let hidden = false;
    // الدائرة التجارية لا تُخفى تلقائياً (ثلاثة حسابات لا تُسقط نشاطاً)؛ تذهب لطابور الإشراف وتُنبَّه الإدارة
    if (type === "biz") { if (n === threshold()) await notifyAdmins({ kind: "content_reported_many", title: `${n} بلاغات على دائرة تجارية`, body: `«${info.title}» — راجعها في طابور الإشراف`, data: { targetType: type, targetId: id, reports: n } }); }
    else if (n >= threshold() && info.status !== "blocked") hidden = await autoHide(type, id, info, n);
    else if (n === 1) await notifyAdmins({ kind: "report_new", title: `بلاغ على ${typeName(type)}`, body: `«${info.title}»${reason ? ` — ${reason}` : ""}`, data: { targetType: type, targetId: id, reports: n }, push: false });
    return { ok: true, reports: n, hidden, threshold: threshold() };
  });

  // ---- صلاحية الإشراف: مدير النظام، أو عضو فريق بصلاحية البلاغات (server/team.js)
  async function modGuard(req, reply, perm) {
    const uid = await auth(req); if (!uid) { unauthorized(reply); return null; }
    let ok = false;
    try { ok = !!(await globalThis.naslifeIsAdmin?.(uid)); } catch { ok = false; }
    if (!ok) { try { ok = !!(await globalThis.naslifeTeamCan?.(uid, perm)); } catch { ok = false; } }
    if (!ok) { bad(reply, 403, "forbidden"); return null; }
    return uid;
  }
  // بلاغات عنصر (للإدارة)
  app.get("/safety/reports/:type/:id", async (req, reply) => {
    const uid = await modGuard(req, reply, "reports.view"); if (!uid) return;
    const r = await pool.query("SELECT reporter_id, reason, created_at FROM content_reports WHERE target_type=$1 AND target_id=$2 ORDER BY created_at DESC LIMIT 100", [String(req.params.type), str(req.params.id, 128)]);
    return r.rows.map((x) => ({ reporterId: x.reporter_id, reason: x.reason, createdAt: x.created_at }));
  });

  // ---- طابور الإشراف: بلاغات المحتوى مجمّعة لكل عنصر مع معاينته وحالته وآخر إجراء
  const people = async (ids) => {
    const m = new Map(); const uniq = [...new Set(ids.filter(Boolean))];
    if (!uniq.length) return m;
    try { for (const u of (await pool.query("SELECT * FROM users WHERE id = ANY($1::text[])", [uniq])).rows) m.set(u.id, { id: u.id, nickname: u.nickname ?? u.name ?? "", avatarUrl: u.avatar_url ?? u.avatar ?? null }); } catch { /* ignore */ }
    return m;
  };
  const personIn = (pm, id) => pm.get(id) ?? { id, nickname: "", avatarUrl: null };
  const audit = async (adminId, action, target, details = {}) => { try { await pool.query("INSERT INTO admin_audit(id,admin_id,action,target,details) VALUES($1,$2,$3,$4,$5)", [crypto.randomUUID(), adminId, action, target, JSON.stringify(details)]); } catch { /* ignore */ } };
  const OPEN_SQL = "a.created_at IS NULL OR a.created_at < g.last_at";
  app.get("/adminapi/moderation", async (req, reply) => {
    const uid = await modGuard(req, reply, "reports.view"); if (!uid) return;
    const status = req.query?.status === "all" ? "all" : "open";
    const type = TARGETS.has(req.query?.type) ? req.query.type : null;
    const GROUPS = `SELECT g.*, a.action, a.note, a.admin_id, a.created_at AS action_at FROM (
        SELECT target_type, target_id, count(DISTINCT reporter_id)::int AS reports, array_remove(array_agg(DISTINCT NULLIF(reason, '')), NULL) AS reasons,
          min(created_at) AS first_at, max(created_at) AS last_at FROM content_reports WHERE ($1::text IS NULL OR target_type=$1) GROUP BY target_type, target_id) g
      LEFT JOIN LATERAL (SELECT * FROM content_report_actions x WHERE x.target_type=g.target_type AND x.target_id=g.target_id ORDER BY x.created_at DESC LIMIT 1) a ON true`;
    const rows = (await pool.query(`${GROUPS} ${status === "open" ? `WHERE ${OPEN_SQL}` : ""} ORDER BY g.last_at DESC LIMIT 200`, [type])).rows;
    const open = (await pool.query(`SELECT count(*)::int AS n FROM (${GROUPS} WHERE ${OPEN_SQL}) z`, [null])).rows[0].n;
    const infos = await Promise.all(rows.map((r) => targetInfo(r.target_type, r.target_id)));
    const pm = await people([...infos.map((i) => i?.owner), ...rows.map((r) => r.admin_id)]);
    const items = rows.map((r, i) => {
      const info = infos[i];
      return {
        targetType: r.target_type, targetId: r.target_id, typeName: typeName(r.target_type), reports: r.reports, reasons: r.reasons ?? [], firstAt: r.first_at, lastAt: r.last_at,
        owner: info?.owner ? personIn(pm, info.owner) : null,
        title: info?.title ?? null, text: info?.text ? String(info.text).slice(0, 300) : null, mediaUrl: info?.media ?? null,
        status: info ? (info.status === "blocked" ? "hidden" : "visible") : "missing", hidden: info?.status === "blocked",
        bizId: info?.biz_id ?? null, listingId: info?.listing_id ?? null, wantedId: info?.wanted_id ?? null, vesselId: info?.vessel_id ?? null, parentId: info?.post_id ?? null,
        action: r.action ? { action: r.action, note: r.note, by: personIn(pm, r.admin_id), at: r.action_at } : null,
      };
    });
    return { status, open, threshold: threshold(), actions: MOD_ACTIONS, types: TARGET_TYPES.map((t) => ({ id: t, name: typeName(t) })), items };
  });
  app.post("/adminapi/moderation/:type/:id", async (req, reply) => {
    const uid = await modGuard(req, reply, "reports.act"); if (!uid) return;
    const type = String(req.params.type);
    if (!TARGETS.has(type)) return bad(reply, 400, "bad-target");
    const id = normId(type, str(req.params.id, 128));
    if (!validId(type, id)) return bad(reply, 400, "bad-id");
    const action = MOD_ACTIONS.includes(req.body?.action) ? req.body.action : null;
    if (!action) return bad(reply, 400, "bad-action", { allowed: MOD_ACTIONS });
    const note = str(req.body?.note, 300);
    const info = await targetInfo(type, id);
    if (!info && action !== "dismiss") return bad(reply, 404, "not-found");
    // صاحب المحتوى يُؤخذ من المحتوى نفسه دائماً، لا من جسم الطلب
    const owner = info?.owner ?? null;
    let changed = false;
    if (action === "suspend-owner") {
      if (!owner) return bad(reply, 409, "no-owner");
      if (owner === uid) return bad(reply, 400, "self");
      let ownerIsAdmin = false; try { ownerIsAdmin = !!(await globalThis.naslifeIsAdmin?.(owner)); } catch { ownerIsAdmin = false; }
      if (ownerIsAdmin) return bad(reply, 403, "owner-is-admin");
      await pool.query("INSERT INTO user_flags(user_id,suspended,note,updated_at) VALUES($1,true,$2,now()) ON CONFLICT (user_id) DO UPDATE SET suspended=true, note=EXCLUDED.note, updated_at=now()", [owner, note || `بلاغات على ${typeName(type)}`]);
      changed = await setHidden(type, id, true, { by: uid, reason: note, info });
      await notify([owner], { kind: "account_suspended", title: "أُوقف حسابك", body: note || "بسبب محتوى مخالف لقواعد المجتمع؛ تواصل مع الدعم للمراجعة", data: { targetType: type, targetId: id } });
    } else if (action === "hide") {
      changed = await setHidden(type, id, true, { by: uid, reason: note, info });
      if (changed) await notifyOwner(type, id, info, { hidden: true, byAdmin: true, note });
    } else if (action === "restore") {
      changed = await setHidden(type, id, false, { by: uid, info });
      if (changed) await notifyOwner(type, id, info, { hidden: false, byAdmin: true });
    }
    await pool.query("INSERT INTO content_report_actions(id,target_type,target_id,action,note,admin_id,owner_id) VALUES($1,$2,$3,$4,$5,$6,$7)", [crypto.randomUUID(), type, id, action, note, uid, owner]);
    await audit(uid, `moderation.${action}`, `${type}:${id}`, { note, owner, changed });
    const now = info ? await targetInfo(type, id) : null;
    return { ok: true, action, changed, status: now ? (now.status === "blocked" ? "hidden" : "visible") : "missing", owner };
  });
}
