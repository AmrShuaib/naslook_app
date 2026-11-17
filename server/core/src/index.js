import Fastify from "fastify"; import websocket from "@fastify/websocket";
import cors from "@fastify/cors"; import fstatic from "@fastify/static";
import multipart from "@fastify/multipart";
import crypto from "node:crypto"; import fs from "node:fs"; import pg from "pg";
import webpush from "web-push";
import rateLimit from "@fastify/rate-limit";
import { runMigrations, withTx } from "./migrate.js";
import sharp from "sharp";
import { execFile } from "node:child_process"; import { promisify } from "node:util"; import path from "node:path";
const run = promisify(execFile);
const UPLOAD_DIR = process.env.UPLOAD_DIR ?? "/opt/naslife/uploads";
const WEBAPP_DIR = process.env.WEBAPP_DIR ?? "/opt/naslife/webapp";
fs.mkdirSync(UPLOAD_DIR, { recursive: true });
const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });
// schema: numbered files in server/db, applied once each; the process exits if one fails
try { await runMigrations(pool, { log: console }); } catch (e) { console.error(String(e)); process.exit(1); }

// system account that owns district circles (cannot log in: no password)
await pool.query("INSERT INTO users(id,nickname,identity_pubkey,recovery_hash,pass_hash) VALUES('SA0000000','naslife','','',NULL) ON CONFLICT DO NOTHING");

// ---- web push (VAPID keys live in .env) ----
const VAPID_PUBLIC = process.env.VAPID_PUBLIC ?? "", VAPID_PRIVATE = process.env.VAPID_PRIVATE ?? "";
if (VAPID_PUBLIC && VAPID_PRIVATE) webpush.setVapidDetails(process.env.VAPID_SUBJECT ?? "mailto:admin@naslife.app", VAPID_PUBLIC, VAPID_PRIVATE);
const pushPreviewAllowed = async uid => (await pool.query("SELECT push_preview FROM users WHERE id=$1", [uid])).rows[0]?.push_preview === true;
async function sendPush(userId, payload) {
  if (!VAPID_PUBLIC) return;
  const r = await pool.query("SELECT endpoint, subscription FROM push_subscriptions WHERE user_id=$1", [userId]);
  await Promise.all(r.rows.map(async row => {
    try { await webpush.sendNotification(row.subscription, JSON.stringify(payload), { TTL: 86400 }); }
    catch (e) { if (e.statusCode === 404 || e.statusCode === 410) await pool.query("DELETE FROM push_subscriptions WHERE endpoint=$1", [row.endpoint]); }
  }));
}
const previewOf = (type, content) => type === "text" ? String(content).slice(0, 80)
  : type === "image" ? "\u{1F4F7} صورة" : type === "video" ? "\u{1F3AC} فيديو" : type === "voice" ? "\u{1F3A4} رسالة صوتية" : type === "location" ? "\u{1F4CD} موقع" : "رسالة جديدة";

// Only the local reverse proxy (Caddy on this host) may set X-Forwarded-For; anything else keeps its socket address.
const TRUSTED_PROXIES = (process.env.TRUSTED_PROXIES ?? "127.0.0.1,::1").split(",").map(x => x.trim()).filter(Boolean);
const app = Fastify({ logger: { level: process.env.LOG_LEVEL ?? "info" }, trustProxy: TRUSTED_PROXIES });
if (process.env.NODE_ENV === "test") app.get("/__test/ip", async req => ({ ip: req.ip })); // test-only: what the app believes the client IP is
const clientIp = req => req.ip;
// ---- rate limiting (@fastify/rate-limit): 600/min per IP by default; stricter per-route limits below ----
await app.register(rateLimit, {
  global: true, max: 600, timeWindow: "1 minute", hook: "preHandler",
  keyGenerator: req => clientIp(req),
  errorResponseBuilder: (req, ctx) => {
    const secs = Math.max(1, Math.ceil(ctx.ttl / 1000));
    return { statusCode: 429, error: "too-many-attempts", retryAfter: secs,
      message: secs >= 120 ? `محاولات كثيرة. انتظر ${Math.ceil(secs / 60)} دقائق ثم أعد المحاولة` : `محاولات كثيرة. انتظر ${secs} ثانية ثم أعد المحاولة` };
  },
});
const perUser = req => "u:" + (req.headers["x-token"] ?? clientIp(req));
const LIMIT_AUTH = { config: { rateLimit: { max: 5, timeWindow: "1 minute" } } };
const LIMIT_REGISTER = { config: { rateLimit: { max: 3, timeWindow: "1 hour" } } };
const LIMIT_USER = { config: { rateLimit: { max: 60, timeWindow: "1 minute", keyGenerator: perUser } } };
const LIMIT_REPORT = { config: { rateLimit: { max: 10, timeWindow: "1 hour", keyGenerator: perUser } } };
// ---- blocking helpers ----
const blockedEither = async (a, b) => (await pool.query(
  "SELECT 1 FROM blocks WHERE (blocker_id=$1 AND blocked_id=$2) OR (blocker_id=$2 AND blocked_id=$1) LIMIT 1", [a, b])).rowCount > 0;
const hasContact = async (owner, contact) => (await pool.query(
  "SELECT 1 FROM contacts WHERE owner_id=$1 AND contact_id=$2", [owner, contact])).rowCount > 0;
const REPORT_REASONS = new Set(["abuse", "fraud", "impersonation", "content", "other"]);
const ADMIN_KEY = process.env.ADMIN_KEY ?? "";
await app.register(cors, { origin: ["https://naslife.app", "https://www.naslife.app", /^http:\/\/localhost(:\d+)?$/] });
// ---- security headers (CSP tuned for Flutter web: CanvasKit wasm, inline styles, Esri tiles, Google fallback fonts) ----
const CSP = [
  "default-src 'self'",
  "script-src 'self' 'wasm-unsafe-eval'",
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data: blob: https://server.arcgisonline.com",
  "media-src 'self' blob:",
  "font-src 'self' data: https://fonts.gstatic.com",
  "connect-src 'self' wss://naslife.app wss://www.naslife.app https://server.arcgisonline.com https://fonts.gstatic.com",
  "worker-src 'self' blob:",
  "manifest-src 'self'",
  "frame-ancestors 'none'", "base-uri 'self'", "form-action 'self'", "object-src 'none'",
].join("; ");
app.addHook("onSend", async (req, reply) => {
  reply.header("X-Content-Type-Options", "nosniff");
  reply.header("Referrer-Policy", "same-origin");
  reply.header("X-Frame-Options", "DENY");
  reply.header("Strict-Transport-Security", "max-age=31536000; includeSubDomains");
  reply.header("Permissions-Policy", "camera=(self), microphone=(self), geolocation=(self), payment=(), usb=()");
  reply.header("Cross-Origin-Opener-Policy", "same-origin");
  reply.header("Content-Security-Policy", CSP);
});
await app.register(websocket);
await app.register(multipart, { limits: { fileSize: 60 * 1024 * 1024 } });
if (fs.existsSync(WEBAPP_DIR)) await app.register(fstatic, { root: WEBAPP_DIR, cacheControl: false,
  setHeaders: (res, path) => res.setHeader("Cache-Control", path.endsWith("build.json") ? "no-store" : "no-cache") });
await app.register(fstatic, { root: UPLOAD_DIR, prefix: "/files/", decorateReply: false,
  cacheControl: true, maxAge: "30d", immutable: true });
const isPremium = n => { const s = String(n);
  return /^(\d)\1+$/.test(s) || s === [...s].reverse().join("") || /^(\d)\1{3}/.test(s) || n < 1100000; };
async function generateUserId(cc) {
  for (let i = 0; i < 50; i++) { const n = crypto.randomInt(1100000, 10000000);
    if (isPremium(n)) continue; const id = cc + n;
    const r = await pool.query("SELECT 1 FROM users WHERE id=$1", [id]);
    if (!r.rowCount) return id; } throw new Error("exhausted"); }
// scrypt off the event loop; hashes stay "salt:hex" so every existing row keeps working
const scrypt = promisify(crypto.scrypt);
const hashPass = async (p, salt) => { salt = salt ?? crypto.randomBytes(16).toString("hex");
  return salt + ":" + (await scrypt(String(p), salt, 32)).toString("hex"); };
const checkPass = async (p, stored) => { if (!stored || !stored.includes(":")) return false;
  const [salt, hex] = stored.split(":"); const got = await scrypt(String(p), salt, 32); const want = Buffer.from(hex, "hex");
  return want.length === got.length && crypto.timingSafeEqual(got, want); };
const PASSWORD_MIN = 8;                       // for new passwords; older shorter ones still sign in and are asked to update
const DUMMY_HASH = await hashPass("dummy");  // burned on unknown handles so "no such user" costs the same time as a wrong password
// ---- recovery phrase: 6 simple Arabic words shown once; only the scrypt hash is stored in users.recovery_hash ----
const AR_WORDS = ["قمر","شمس","نجم","بحر","جبل","نهر","شجر","ورد","بيت","باب","نافذة","مفتاح","كتاب","قلم","ورق","حبر","مكتب","كرسي","طاولة","سرير","وسادة","غطاء","ثوب","حذاء","قبعة","خاتم","ساعة","هاتف","شاشة","صورة","فيلم","أغنية","طبل","عود","ناي","كمان","بيانو","مطر","ثلج","رعد","برق","ريح","سحاب","ضباب","ندى","فجر","ظهر","عصر","مغرب","ليل","نهار","صباح","مساء","أسبوع","شهر","سنة","يوم","دقيقة","لحظة","تفاح","موز","برتقال","عنب","تمر","رمان","تين","خوخ","مشمش","فراولة","بطيخ","شمام","ليمون","جزر","خيار","طماطم","بصل","ثوم","بطاطس","ذرة","أرز","خبز","جبن","زبدة","عسل","سكر","ملح","فلفل","زيت","ماء","حليب","قهوة","شاي","عصير","كعكة","حلوى","شوكولاتة","مربى","لبن","قط","كلب","حصان","جمل","غزال","أسد","نمر","فيل","زرافة","قرد","أرنب","فأر","طائر","نسر","صقر","حمامة","بطة","دجاجة","سمكة","حوت","دلفين","سلحفاة","ضفدع","نحلة","فراشة","نملة","عنكبوت","خروف","بقرة","ماعز","أحمر","أزرق","أخضر","أصفر","أبيض","أسود","بنفسجي","برتقالي","وردي","رمادي","ذهبي","فضي","مدينة","قرية","شارع","طريق","جسر","سوق","مدرسة","جامعة","مستشفى","مسجد","مكتبة","حديقة","ملعب","مطار","ميناء","محطة","فندق","مطعم","مقهى","متحف","سيارة","حافلة","قطار","طائرة","سفينة","قارب","دراجة","عجلة","محرك","وقود","رأس","عين","أذن","أنف","فم","يد","قدم","قلب","كتف","ركبة","أصبع","شعر","أب","أم","أخ","أخت","جد","جدة","عم","خال","ابن","بنت","صديق","جار","معلم","طبيب","مهندس","طيار","نجار","خباز","حداد","فلاح","صياد","لعبة","كرة","سباق","سباحة","جري","قفز","رقص","غناء","رسم","كتابة","قراءة","نوم","أكل","شرب","ضحك","فرح","أمل","حب","سلام","خير","ذهب","فضة","حديد","نحاس","خشب","زجاج","حجر","رمل","تراب","طين","قطن","صوف","حرير","جلد","قفل","صندوق","حقيبة","محفظة","كيس","سلة","زجاجة","كوب","صحن","ملعقة","شوكة","سكين","قدر","مقلاة","فرن","ثلاجة","غسالة","مكنسة","مصباح","شمعة","نار","دخان","رماد","شرارة","ضوء","ظل","نور","لون","شكل","دائرة","مربع","مثلث","خط","نقطة","رقم","حرف","كلمة","جملة","قصة","ورقة","شجرة","غابة","صحراء","واحة","جزيرة","شاطئ","موج","صدف","لؤلؤ","مرجان","خيمة","قصر","برج","سور","قلعة","بئر","نبع","سد","قناة"];
const newRecoveryPhrase = () => Array.from({ length: 6 }, () => AR_WORDS[crypto.randomInt(0, AR_WORDS.length)]).join(" ");
// tolerant matching: strip diacritics/tatweel, unify alef/taa-marbuta/alef-maqsura, collapse spaces
const normPhrase = p => String(p ?? "").replace(/[\u064B-\u0652\u0640]/g, "").replace(/[أإآ]/g, "ا").replace(/ة/g, "ه")
  .replace(/ى/g, "ي").replace(/[^\u0621-\u064A0-9 ]/g, " ").trim().replace(/\s+/g, " ");
const hashRecovery = p => hashPass(normPhrase(p));
const checkRecovery = async (input, stored) => {
  const n = normPhrase(input); if (n && await checkPass(n, stored)) return true;
  const digits = String(input ?? "").replace(/\D/g, ""); // legacy 16-digit codes issued before phrases
  return digits.length === 16 && await checkPass(digits, stored);
};
// ---- simple in-memory rate limiting (per IP and per handle) ----
const attempts = new Map();
function limited(key, max, windowMs = 15 * 60 * 1000) {
  const now = Date.now(); const e = attempts.get(key);
  if (!e || e.reset < now) { attempts.set(key, { n: 1, reset: now + windowMs }); return false; }
  e.n++; return e.n > max;
}
setInterval(() => { const now = Date.now(); for (const [k, e] of attempts) if (e.reset < now) attempts.delete(k); }, 60 * 1000);
// Only a SHA-256 of the session token is stored: a database leak does not hand out live sessions.
export async function migrateLegacySessions() { // raw tokens are 43 chars (base64url), hashes are 64 hex chars; idempotent
  await pool.query("UPDATE sessions SET token=encode(sha256(convert_to(token,'UTF8')),'hex') WHERE length(token) <> 64"); }
await migrateLegacySessions();
const tokenHash = t => crypto.createHash("sha256").update(String(t)).digest("hex");
async function createSession(uid, req) { const t = crypto.randomBytes(32).toString("base64url");
  const ua = String(req?.headers?.["user-agent"] ?? "").slice(0, 200) || null;
  await pool.query("INSERT INTO sessions(token,user_id,expires_at,user_agent,last_used_at) VALUES($1,$2,now()+interval '90 days',$3,now())", [tokenHash(t), uid, ua]);
  return t; }
async function authToken(t) {
  if (!t || typeof t !== "string" || t.length > 200) return null;
  const r = await pool.query("SELECT id, user_id FROM sessions WHERE token=$1 AND expires_at>now()", [tokenHash(t)]);
  const row = r.rows[0]; if (!row) return null;
  pool.query("UPDATE sessions SET last_used_at=now() WHERE id=$1 AND (last_used_at IS NULL OR last_used_at < now() - interval '5 minutes')", [row.id]).catch(() => {});
  return { userId: row.user_id, sessionId: row.id };
}
// the token travels only in the X-Token header (never in the URL, so it never lands in proxy or browser logs)
async function auth(req) { const a = await authToken(req.headers["x-token"]); if (!a) return null; req.sessionId = a.sessionId; return a.userId; }
const NICK_RE = /^[a-z0-9_]{3,32}$/, ID_RE = /^[A-Z]{2}\d{7}$/, UUID_RE = /^[0-9a-f-]{36}$/i;
const MSG_TYPES = new Set(["text", "image", "voice", "video", "location"]);
const FILE_URL_RE = /^(https:\/\/(www\.)?naslife\.app)?\/files\/[0-9a-f-]{36}\.[a-z0-9]{1,5}$/;


app.post("/register", LIMIT_REGISTER, async (req, reply) => {
  const { nickname, password } = req.body ?? {};
  const country = (req.body?.country ?? "SA").toUpperCase();
  if (!NICK_RE.test(nickname ?? "")) return reply.code(400).send({ error: "invalid-nickname" });
  if (String(password ?? "").length < PASSWORD_MIN) return reply.code(400).send({ error: "weak-password" });
  const taken = await pool.query("SELECT 1 FROM users WHERE nickname=$1",[nickname]);
  if (taken.rowCount) return reply.code(409).send({ error: "nickname-taken" });
  const id = await generateUserId(country);
  const recoveryPhrase = newRecoveryPhrase();
  await pool.query("INSERT INTO users(id,nickname,identity_pubkey,recovery_hash,pass_hash) VALUES($1,$2,'',$3,$4)",
    [id, nickname, await hashRecovery(recoveryPhrase), await hashPass(password)]);
  return { id, nickname, token: await createSession(id, req), recoveryPhrase, hasRecovery: true };
});
const tooMany = reply => reply.code(429).send({ error: "too-many-attempts", retryAfter: 60, message: "محاولات كثيرة. انتظر دقيقة ثم أعد المحاولة" });
app.post("/login", LIMIT_AUTH, async (req, reply) => {
  const { handle, password } = req.body ?? {};
  if (limited("login:h:" + String(handle ?? "").toLowerCase(), 5, 60 * 1000)) return tooMany(reply);
  const byId = ID_RE.test(handle ?? "");
  const r = await pool.query(byId ? "SELECT id,nickname,pass_hash,recovery_hash,avatar_url,deleted_at FROM users WHERE id=$1"
    : "SELECT id,nickname,pass_hash,recovery_hash,avatar_url,deleted_at FROM users WHERE nickname=$1", [handle]);
  // same answer and same cost whether the handle exists or the password is wrong
  const ok = await checkPass(password ?? "", r.rows[0]?.pass_hash || DUMMY_HASH);
  if (!r.rowCount || !r.rows[0].pass_hash || !ok || r.rows[0].deleted_at) return reply.code(401).send({ error: "bad-credentials" });
  return { id: r.rows[0].id, nickname: r.rows[0].nickname, token: await createSession(r.rows[0].id, req), hasRecovery: !!r.rows[0].recovery_hash,
    avatarUrl: r.rows[0].avatar_url, weakPassword: String(password).length < PASSWORD_MIN };
});

// ---- password reset: handle + recovery phrase -> new password; all old sessions revoked; a fresh phrase is issued ----
async function resetPassword(req, reply) {
  const { handle, newPassword } = req.body ?? {};
  const phrase = req.body?.recoveryPhrase ?? req.body?.recoveryCode;
  if (limited("recover:h:" + String(handle ?? "").toLowerCase(), 5, 60 * 1000)) return tooMany(reply);
  const byId = ID_RE.test(handle ?? "");
  const r = await pool.query(byId ? "SELECT id,nickname,recovery_hash FROM users WHERE id=$1"
    : "SELECT id,nickname,recovery_hash FROM users WHERE nickname=$1", [handle]);
  if (!r.rowCount) { await checkPass("x", DUMMY_HASH); return reply.code(401).send({ error: "bad-code" }); } // no account enumeration
  if (!r.rows[0].recovery_hash) return reply.code(400).send({ error: "no-recovery" });
  if (!await checkRecovery(phrase, r.rows[0].recovery_hash)) return reply.code(401).send({ error: "bad-code" });
  if (String(newPassword ?? "").length < PASSWORD_MIN) return reply.code(400).send({ error: "weak-password" });
  const uid = r.rows[0].id; const fresh = newRecoveryPhrase();
  await pool.query("UPDATE users SET pass_hash=$1, recovery_hash=$2 WHERE id=$3", [await hashPass(String(newPassword)), await hashRecovery(fresh), uid]);
  await pool.query("DELETE FROM sessions WHERE user_id=$1", [uid]);
  return { id: uid, nickname: r.rows[0].nickname, token: await createSession(uid, req), recoveryPhrase: fresh, hasRecovery: true };
}
app.post("/reset-password", LIMIT_AUTH, resetPassword);
app.post("/recover", LIMIT_AUTH, resetPassword);

// ---- profile ----
app.get("/me", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const r = await pool.query("SELECT id,nickname,created_at,recovery_hash,avatar_url,push_preview,is_admin FROM users WHERE id=$1",[uid]);
  if (!r.rowCount) return reply.code(404).send({ error: "not-found" });
  return { id: r.rows[0].id, nickname: r.rows[0].nickname, createdAt: r.rows[0].created_at, hasRecovery: !!r.rows[0].recovery_hash, avatarUrl: r.rows[0].avatar_url,
    pushPreview: r.rows[0].push_preview === true, isAdmin: r.rows[0].is_admin === true };
});
app.patch("/me/settings", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  if (typeof req.body?.pushPreview === "boolean") await pool.query("UPDATE users SET push_preview=$1 WHERE id=$2", [req.body.pushPreview, uid]);
  const r = await pool.query("SELECT push_preview FROM users WHERE id=$1", [uid]);
  return { pushPreview: r.rows[0].push_preview === true };
});

// ---- data export: everything stored about this account, as one JSON document ----
app.get("/me/export", LIMIT_USER, async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const q = async (sql, args = [uid]) => (await pool.query(sql, args)).rows;
  return {
    exportedAt: new Date().toISOString(),
    account: (await q("SELECT id, nickname, created_at, avatar_url, district_id, push_preview FROM users WHERE id=$1"))[0],
    profile: (await q("SELECT * FROM profiles WHERE user_id=$1"))[0] ?? null,
    contacts: await q("SELECT c.contact_id AS id, u.nickname FROM contacts c JOIN users u ON u.id=c.contact_id WHERE c.owner_id=$1"),
    blocked: await q("SELECT blocked_id AS id FROM blocks WHERE blocker_id=$1"),
    messages: await q("SELECT id, sender_id, recipient_id, type, content, sent_at, delivered_at, read_at FROM messages WHERE sender_id=$1 OR recipient_id=$1 ORDER BY sent_at"),
    posts: await q("SELECT id, vessel_id, type, content, caption, kind, tag, created_at FROM posts WHERE author_id=$1 ORDER BY created_at"),
    comments: await q("SELECT id, post_id, text, created_at FROM comments WHERE author_id=$1 ORDER BY created_at"),
    circles: await q("SELECT v.id, v.name, m.role, m.joined_at FROM vessel_members m JOIN vessels v ON v.id=m.vessel_id WHERE m.user_id=$1"),
    mapPins: await q("SELECT id, lat, lng, type, content, place_name, rating, created_at, expires_at FROM map_pins WHERE owner_id=$1"),
    mapPresence: (await q("SELECT lat, lng, title, visible, updated_at, hide_after_hours, expires_at FROM map_presence WHERE user_id=$1"))[0] ?? null,
    stories: await q("SELECT id, type, content, caption, lat, lng, created_at, expires_at FROM stories WHERE user_id=$1"),
    businesses: await q("SELECT id, name, category, description, lat, lng, address, phone, hours, status, verified, created_at FROM businesses WHERE owner_id=$1"),
    reportsFiled: await q("SELECT id, reported_id, reason, details, status, created_at FROM reports WHERE reporter_id=$1"),
    sessions: await q("SELECT id, created_at, last_used_at, user_agent FROM sessions WHERE user_id=$1"),
  };
});

// ---- account deletion: password-confirmed; the row is anonymised (foreign keys) and everything personal is purged ----
app.delete("/me", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  if (limited("delme:" + uid, 5)) return reply.code(429).send({ error: "too-many-attempts" });
  const cur = await pool.query("SELECT pass_hash, avatar_url FROM users WHERE id=$1", [uid]);
  if (!cur.rowCount) return reply.code(404).send({ error: "not-found" });
  if (!await checkPass(req.body?.password ?? "", cur.rows[0].pass_hash)) return reply.code(401).send({ error: "bad-password" });
  const media = [];
  await withTx(pool, async c => {
    const grab = async (sql) => (await c.query(sql, [uid])).rows.forEach(r => media.push(r.content));
    await grab("DELETE FROM map_pins WHERE owner_id=$1 RETURNING content");
    await grab("DELETE FROM stories WHERE user_id=$1 RETURNING content");
    await grab("UPDATE messages SET type='deleted', content='' WHERE sender_id=$1 AND type IN ('image','voice','video') AND type<>'deleted' RETURNING (SELECT content FROM messages m2 WHERE m2.id=messages.id) AS content");
    await grab("DELETE FROM posts WHERE author_id=$1 RETURNING content");
    await c.query("DELETE FROM comments WHERE author_id=$1", [uid]);
    await c.query("DELETE FROM supports WHERE user_id=$1", [uid]);
    await c.query("DELETE FROM profiles WHERE user_id=$1", [uid]);
    await c.query("DELETE FROM map_presence WHERE user_id=$1", [uid]);
    await c.query("DELETE FROM push_subscriptions WHERE user_id=$1", [uid]);
    await c.query("DELETE FROM contacts WHERE owner_id=$1 OR contact_id=$1", [uid]);
    await c.query("DELETE FROM blocks WHERE blocker_id=$1 OR blocked_id=$1", [uid]);
    await c.query("DELETE FROM request_ignores WHERE user_id=$1 OR peer_id=$1", [uid]);
    // businesses and their circles go entirely; other owned circles pass to the longest-standing member, or are removed when empty
    const biz = await c.query("DELETE FROM businesses WHERE owner_id=$1 RETURNING vessel_id, cover_url", [uid]);
    for (const b of biz.rows) { media.push(b.cover_url); if (b.vessel_id) await c.query("DELETE FROM vessels WHERE id=$1", [b.vessel_id]); }
    const owned = await c.query("SELECT id FROM vessels WHERE owner_id=$1", [uid]);
    for (const v of owned.rows) {
      const heir = await c.query("SELECT user_id FROM vessel_members WHERE vessel_id=$1 AND user_id<>$2 ORDER BY joined_at LIMIT 1", [v.id, uid]);
      if (heir.rowCount) {
        await c.query("UPDATE vessels SET owner_id=$1 WHERE id=$2", [heir.rows[0].user_id, v.id]);
        await c.query("UPDATE vessel_members SET role='owner' WHERE vessel_id=$1 AND user_id=$2", [v.id, heir.rows[0].user_id]);
      } else { const gone = await c.query("DELETE FROM vessels WHERE id=$1 RETURNING cover_url", [v.id]); media.push(gone.rows[0]?.cover_url); }
    }
    await c.query("DELETE FROM vessel_members WHERE user_id=$1", [uid]);
    await c.query("DELETE FROM sessions WHERE user_id=$1", [uid]);
    media.push(cur.rows[0].avatar_url);
    await c.query(`UPDATE users SET nickname=$2, pass_hash=NULL, recovery_hash='', avatar_url=NULL, district_id=NULL, last_seen=NULL,
      push_preview=false, is_admin=false, deleted_at=now() WHERE id=$1`, [uid, "deleted_" + uid.toLowerCase()]);
  });
  for (const m of media) if (m) releaseMedia(m).catch(() => {});
  const set = online.get(uid); if (set) for (const sock of set) { try { sock.close(4002, "account-deleted"); } catch {} }
  return { ok: true };
});
app.post("/me/recovery", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  if (limited("mereco:" + uid, 10)) return reply.code(429).send({ error: "too-many-attempts" });
  const cur = await pool.query("SELECT pass_hash FROM users WHERE id=$1",[uid]);
  if (!cur.rowCount) return reply.code(404).send({ error: "not-found" });
  if (!await checkPass(req.body?.currentPassword ?? "", cur.rows[0].pass_hash)) return reply.code(401).send({ error: "bad-password" });
  const phrase = newRecoveryPhrase();
  await pool.query("UPDATE users SET recovery_hash=$1 WHERE id=$2", [await hashRecovery(phrase), uid]);
  return { recoveryPhrase: phrase };
});
app.patch("/me", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const { nickname, password, currentPassword } = req.body ?? {};
  if (limited("patchme:" + uid, 10)) return reply.code(429).send({ error: "too-many-attempts" });
  const cur = await pool.query("SELECT pass_hash FROM users WHERE id=$1",[uid]);
  if (!cur.rowCount) return reply.code(404).send({ error: "not-found" });
  if (!await checkPass(currentPassword ?? "", cur.rows[0].pass_hash)) return reply.code(401).send({ error: "bad-password" });
  if (nickname != null) {
    if (!NICK_RE.test(nickname)) return reply.code(400).send({ error: "invalid-nickname" });
    const taken = await pool.query("SELECT 1 FROM users WHERE nickname=$1 AND id<>$2",[nickname, uid]);
    if (taken.rowCount) return reply.code(409).send({ error: "nickname-taken" });
    await pool.query("UPDATE users SET nickname=$1 WHERE id=$2",[nickname, uid]);
  }
  if (password != null) {
    if (String(password).length < PASSWORD_MIN) return reply.code(400).send({ error: "weak-password" });
    await pool.query("UPDATE users SET pass_hash=$1 WHERE id=$2",[await hashPass(String(password)), uid]);
    await pool.query("DELETE FROM sessions WHERE user_id=$1 AND id<>$2", [uid, req.sessionId]); // a new password signs every other device out
  }
  const r = await pool.query("SELECT id,nickname FROM users WHERE id=$1",[uid]);
  return r.rows[0];
});
// ---- devices & sessions ----
const sessionOut = (r, current) => ({ id: r.id, createdAt: r.created_at, lastUsedAt: r.last_used_at, userAgent: r.user_agent ?? "", current: r.id === current });
app.get("/me/sessions", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const r = await pool.query("SELECT id, created_at, last_used_at, user_agent FROM sessions WHERE user_id=$1 AND expires_at>now() ORDER BY last_used_at DESC NULLS LAST, created_at DESC", [uid]);
  return r.rows.map(x => sessionOut(x, req.sessionId));
});
app.delete("/me/sessions/:id", async (req, reply) => {   // sign one device out (may be the current one)
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  if (!UUID_RE.test(req.params.id)) return reply.code(400).send({ error: "bad-id" });
  const r = await pool.query("DELETE FROM sessions WHERE user_id=$1 AND id=$2", [uid, req.params.id]);
  if (!r.rowCount) return reply.code(404).send({ error: "not-found" });
  return { ok: true };
});
app.delete("/me/sessions", async (req, reply) => {       // sign every other device out
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const r = await pool.query("DELETE FROM sessions WHERE user_id=$1 AND id<>$2", [uid, req.sessionId]);
  return { ok: true, revoked: r.rowCount };
});
app.post("/logout", async (req, reply) => {
  const t = req.headers["x-token"] ?? "";
  const uid = await auth(req);
  if (uid) await pool.query("UPDATE map_presence SET visible=false, expires_at=NULL WHERE user_id=$1", [uid]); // never keep a pin for someone who left
  await pool.query("DELETE FROM sessions WHERE token=$1", [tokenHash(t)]);
  return { ok: true };
});

// Directory lookup: signed-in users only, blocks hide the account in both directions, and no presence
// (online / last seen come from /presence/:id, which applies its own rules).
app.get("/users/:handle", async (req, reply) => {
  const me = await auth(req); if (!me) return reply.code(401).send({ error: "auth" });
  const h = String(req.params.handle ?? ""); const byId = ID_RE.test(h);
  if (!byId && !NICK_RE.test(h)) return reply.code(404).send({ error: "not-found" });
  const r = await pool.query(byId ? "SELECT id,nickname,avatar_url,deleted_at FROM users WHERE id=$1" : "SELECT id,nickname,avatar_url,deleted_at FROM users WHERE nickname=$1", [h]);
  if (!r.rowCount || r.rows[0].deleted_at) return reply.code(404).send({ error: "not-found" });
  if (me !== r.rows[0].id && await blockedEither(me, r.rows[0].id)) return reply.code(404).send({ error: "not-found" });
  const u = r.rows[0];
  return { id: u.id, nickname: u.nickname, avatarUrl: u.avatar_url };
});
// presence for the chat header (polled); blocked users see nothing
app.get("/presence/:id", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const id = req.params.id;
  if (!ID_RE.test(id)) return reply.code(400).send({ error: "bad-user" });
  if (await blockedEither(uid, id)) return { online: false, lastSeen: null };
  const r = await pool.query("SELECT last_seen FROM users WHERE id=$1", [id]);
  if (!r.rowCount) return reply.code(404).send({ error: "not-found" });
  return { online: isOnline(id), lastSeen: r.rows[0].last_seen };
});
// profile picture: same media pipeline as /upload, then users.avatar_url
app.post("/me/avatar", LIMIT_USER, async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const out = await handleUpload(req, reply, { imageOnly: true }); if (!out) return;
  const old = (await pool.query("UPDATE users SET avatar_url=$1 WHERE id=$2 RETURNING (SELECT avatar_url FROM users WHERE id=$2) AS prev", [out.url, uid])).rows[0]?.prev;
  if (old && old !== out.url) releaseMedia(old);
  return { avatarUrl: out.url };
});

// ---- blocks ----
app.get("/blocks", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const r = await pool.query("SELECT u.id, u.nickname, b.created_at FROM blocks b JOIN users u ON u.id=b.blocked_id WHERE b.blocker_id=$1 ORDER BY b.created_at DESC", [uid]);
  return r.rows.map(x => ({ id: x.id, nickname: x.nickname, createdAt: x.created_at }));
});
app.post("/blocks", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const target = req.body?.userId;
  if (!ID_RE.test(target ?? "") || target === uid) return reply.code(400).send({ error: "bad-user" });
  const exists = await pool.query("SELECT 1 FROM users WHERE id=$1", [target]);
  if (!exists.rowCount) return reply.code(404).send({ error: "not-found" });
  await pool.query("INSERT INTO blocks(blocker_id,blocked_id) VALUES($1,$2) ON CONFLICT DO NOTHING", [uid, target]);
  await pool.query("DELETE FROM contacts WHERE owner_id=$1 AND contact_id=$2", [uid, target]);
  return { ok: true };
});
app.delete("/blocks/:id", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  await pool.query("DELETE FROM blocks WHERE blocker_id=$1 AND blocked_id=$2", [uid, req.params.id]);
  return { ok: true };
});

// ---- reports ----
app.post("/reports", LIMIT_REPORT, async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const { userId, reason, messageId, details = "" } = req.body ?? {};
  if (!ID_RE.test(userId ?? "") || userId === uid) return reply.code(400).send({ error: "bad-user" });
  if (!REPORT_REASONS.has(reason)) return reply.code(400).send({ error: "bad-reason" });
  if (typeof details !== "string" || details.length > 1000) return reply.code(400).send({ error: "bad-details" });
  const mid = messageId && UUID_RE.test(messageId) ? messageId : null;
  const id = crypto.randomUUID();
  await pool.query("INSERT INTO reports(id,reporter_id,reported_id,reason,message_id,details) VALUES($1,$2,$3,$4,$5,$6)",
    [id, uid, userId, reason, mid, details.trim()]);
  return { ok: true, id };
});
// ---- administration: signed-in users with is_admin (ops/grant-admin.sh). The static ADMIN_KEY header is still
// accepted while ADMIN_KEY is set in .env so existing tooling keeps working; remove it from .env to retire it.
async function adminAuth(req, reply) {
  const uid = await auth(req);
  if (uid) {
    const r = await pool.query("SELECT is_admin FROM users WHERE id=$1", [uid]);
    if (r.rows[0]?.is_admin) return { actor: "user:" + uid, adminId: uid };
  }
  const key = req.headers["x-admin-key"];
  if (ADMIN_KEY && typeof key === "string" && key.length === ADMIN_KEY.length && crypto.timingSafeEqual(Buffer.from(key), Buffer.from(ADMIN_KEY))) {
    app.log.warn({ path: req.url }, "admin action via static ADMIN_KEY (deprecated; grant is_admin to a user instead)");
    return { actor: "admin-key", adminId: null };
  }
  reply.code(401).send({ error: "auth" }); return null;
}
// append-only record of what an admin did; never receives secrets or session tokens
async function audit(req, who, action, { targetType = null, targetId = null, reason = null, before = null, after = null } = {}) {
  try {
    await pool.query("INSERT INTO audit_log(admin_id,actor,action,target_type,target_id,reason,before,after,ip) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)",
      [who.adminId, who.actor, action, targetType, targetId == null ? null : String(targetId), reason, before, after, req.ip ?? null]);
  } catch (e) { app.log.error({ err: String(e), action }, "audit write failed"); }
}
app.get("/admin/audit", async (req, reply) => {
  const who = await adminAuth(req, reply); if (!who) return;
  const before = req.query?.before && !isNaN(Number(req.query.before)) ? Number(req.query.before) : null;
  const r = await pool.query("SELECT * FROM audit_log WHERE ($1::bigint IS NULL OR id < $1) ORDER BY id DESC LIMIT 200", [before]);
  return r.rows;
});
app.get("/admin/reports", async (req, reply) => {
  const who = await adminAuth(req, reply); if (!who) return;
  const status = req.query?.status;
  const r = await pool.query(`SELECT r.id, r.reason, r.details, r.message_id, r.status, r.created_at,
      r.reporter_id, ru.nickname AS reporter_nickname, r.reported_id, du.nickname AS reported_nickname,
      m.type AS message_type, m.content AS message_content
    FROM reports r JOIN users ru ON ru.id=r.reporter_id JOIN users du ON du.id=r.reported_id
    LEFT JOIN messages m ON m.id=r.message_id
    WHERE ($1::text IS NULL OR r.status=$1) ORDER BY r.created_at DESC LIMIT 500`, [status ?? null]);
  return r.rows;
});
app.patch("/admin/reports/:id", async (req, reply) => {
  const who = await adminAuth(req, reply); if (!who) return;
  if (!UUID_RE.test(req.params.id)) return reply.code(400).send({ error: "bad-id" });
  const status = req.body?.status;
  if (!["new", "reviewed", "actioned", "dismissed"].includes(status)) return reply.code(400).send({ error: "bad-status" });
  const r = await pool.query("UPDATE reports SET status=$1 WHERE id=$2 RETURNING (SELECT status FROM reports WHERE id=$2) AS prev", [status, req.params.id]);
  if (!r.rowCount) return reply.code(404).send({ error: "not-found" });
  await audit(req, who, "report.status", { targetType: "report", targetId: req.params.id, reason: req.body?.reason ?? null,
    before: { status: r.rows[0].prev }, after: { status } });
  return { ok: true };
});

// ---- message requests: senders who are not in my contacts ----
app.get("/requests", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const r = await pool.query(`
    WITH req AS (
      SELECT m.sender_id AS peer, max(m.sent_at) AS last_at, count(*) FILTER (WHERE m.read_at IS NULL)::int AS unread
      FROM messages m WHERE m.recipient_id=$1 AND m.sender_id <> $1
        AND NOT EXISTS (SELECT 1 FROM contacts c WHERE c.owner_id=$1 AND c.contact_id=m.sender_id)
        AND NOT EXISTS (SELECT 1 FROM blocks b WHERE b.blocker_id=$1 AND b.blocked_id=m.sender_id)
      GROUP BY m.sender_id)
    SELECT r.peer AS id, u.nickname, u.avatar_url, r.last_at, r.unread, l.type AS last_type, l.content AS last_content
    FROM req r JOIN users u ON u.id=r.peer
    LEFT JOIN LATERAL (SELECT type, content FROM messages WHERE sender_id=r.peer AND recipient_id=$1 ORDER BY sent_at DESC LIMIT 1) l ON true
    WHERE NOT EXISTS (SELECT 1 FROM request_ignores i WHERE i.user_id=$1 AND i.peer_id=r.peer AND i.created_at >= r.last_at)
    ORDER BY r.last_at DESC`, [uid]);
  return r.rows.map(x => ({ id: x.id, nickname: x.nickname, avatarUrl: x.avatar_url, lastType: x.last_type, lastContent: x.last_content,
    lastAt: x.last_at, lastMine: false, unread: x.unread }));
});
app.post("/requests/:id/ignore", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  if (!ID_RE.test(req.params.id)) return reply.code(400).send({ error: "bad-user" });
  await pool.query("INSERT INTO request_ignores(user_id,peer_id,created_at) VALUES($1,$2,now()) ON CONFLICT (user_id,peer_id) DO UPDATE SET created_at=now()", [uid, req.params.id]);
  return { ok: true };
});
app.post("/contacts", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const cid = req.body?.contactId;
  if (!ID_RE.test(cid ?? "") || cid === uid) return reply.code(400).send({ error: "bad-contact" });
  if (await blockedEither(uid, cid)) return reply.code(403).send({ error: "blocked" });
  await pool.query("INSERT INTO contacts(owner_id,contact_id) VALUES($1,$2) ON CONFLICT DO NOTHING",[uid, cid]);
  return { ok: true };
});
app.get("/contacts", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const r = await pool.query(
    "SELECT u.id, u.nickname, u.avatar_url FROM contacts c JOIN users u ON u.id=c.contact_id WHERE c.owner_id=$1",[uid]);
  return r.rows.map(x => ({ id: x.id, nickname: x.nickname, avatarUrl: x.avatar_url }));
});
app.delete("/contacts/:id", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  await pool.query("DELETE FROM contacts WHERE owner_id=$1 AND contact_id=$2",[uid, req.params.id]);
  return { ok: true };
});
// ---- chat list: every contact or message peer, with last message + unread count, one query ----
app.get("/chats", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const r = await pool.query(`
    WITH peers AS (
      SELECT contact_id AS peer FROM contacts WHERE owner_id=$1
      UNION SELECT recipient_id FROM messages WHERE sender_id=$1),
    last AS (
      SELECT DISTINCT ON (p.peer) p.peer, m.sender_id, m.type, m.content, m.sent_at
      FROM peers p JOIN messages m ON (m.sender_id=$1 AND m.recipient_id=p.peer) OR (m.sender_id=p.peer AND m.recipient_id=$1)
      ORDER BY p.peer, m.sent_at DESC),
    unread AS (
      SELECT sender_id AS peer, count(*)::int AS n FROM messages WHERE recipient_id=$1 AND read_at IS NULL GROUP BY sender_id)
    SELECT p.peer AS id, u.nickname, u.avatar_url, l.type AS last_type, l.content AS last_content, l.sent_at AS last_at,
           (l.sender_id = $1) AS last_mine, COALESCE(un.n, 0) AS unread
    FROM peers p JOIN users u ON u.id=p.peer
    LEFT JOIN last l ON l.peer=p.peer LEFT JOIN unread un ON un.peer=p.peer
    WHERE p.peer <> $1 AND NOT EXISTS (SELECT 1 FROM blocks b WHERE b.blocker_id=$1 AND b.blocked_id=p.peer)
    ORDER BY l.sent_at DESC NULLS LAST, u.nickname`, [uid]);
  return r.rows.map(x => ({ id: x.id, nickname: x.nickname, avatarUrl: x.avatar_url, lastType: x.last_type, lastContent: x.last_content,
    lastAt: x.last_at, lastMine: x.last_mine === true, unread: x.unread }));
});
app.get("/messages/:peer", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const peer = req.params.peer;
  if (!ID_RE.test(peer)) return reply.code(400).send({ error: "bad-peer" });
  // fetching the thread proves delivery of everything the peer sent me
  const d = await pool.query("UPDATE messages SET delivered_at=now() WHERE recipient_id=$1 AND sender_id=$2 AND delivered_at IS NULL RETURNING id", [uid, peer]);
  if (d.rowCount) pushTo(peer, { event: "delivered", peerId: uid, ids: d.rows.map(x => x.id), at: new Date().toISOString() });
  const r = await pool.query(
    "SELECT id, sender_id, type, content, sent_at, delivered_at, read_at FROM messages WHERE (sender_id=$1 AND recipient_id=$2) OR (sender_id=$2 AND recipient_id=$1) ORDER BY sent_at DESC LIMIT 200",
    [uid, peer]);
  return r.rows.reverse();
});
async function markRead(uid, peer, reply) {
  if (!ID_RE.test(peer ?? "")) return reply.code(400).send({ error: "bad-peer" });
  const at = new Date().toISOString();
  const r = await pool.query(
    "UPDATE messages SET read_at=$3, delivered_at=COALESCE(delivered_at,$3) WHERE recipient_id=$1 AND sender_id=$2 AND read_at IS NULL RETURNING id",
    [uid, peer, at]);
  if (r.rowCount) pushTo(peer, { event: "read", peerId: uid, at });
  return { ok: true, count: r.rowCount };
}
app.post("/messages/:peer/read", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  return markRead(uid, req.params.peer, reply);
});
app.post("/messages/read", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  return markRead(uid, req.body?.peer, reply);
});
// delete for everyone (sender only): the row stays as a tombstone so both sides render "deleted"
app.delete("/messages/:id", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const id = req.params.id;
  if (!UUID_RE.test(id)) return reply.code(400).send({ error: "bad-id" });
  const r = await pool.query("UPDATE messages SET type='deleted', content='' WHERE id=$1 AND sender_id=$2 AND type<>'deleted' RETURNING recipient_id, (SELECT content FROM messages WHERE id=$1) AS prev", [id, uid]);
  if (!r.rowCount) return reply.code(404).send({ error: "not-found" });
  releaseMedia(r.rows[0].prev);
  const peer = r.rows[0].recipient_id; const at = new Date().toISOString();
  pushTo(peer, { event: "deleted", id, peerId: uid, at });
  pushTo(uid, { event: "deleted", id, peerId: peer, at });
  return { ok: true };
});
app.get("/push/key", async () => ({ key: VAPID_PUBLIC || null }));
app.post("/push/subscribe", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const sub = req.body?.subscription;
  if (!sub || typeof sub.endpoint !== "string" || !sub.keys) return reply.code(400).send({ error: "bad-subscription" });
  await pool.query("INSERT INTO push_subscriptions(endpoint,user_id,subscription) VALUES($1,$2,$3) ON CONFLICT (endpoint) DO UPDATE SET user_id=EXCLUDED.user_id, subscription=EXCLUDED.subscription, created_at=now()",
    [sub.endpoint, uid, sub]);
  return { ok: true };
});
app.delete("/push/subscribe", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  await pool.query("DELETE FROM push_subscriptions WHERE endpoint=$1 AND user_id=$2", [req.body?.endpoint ?? "", uid]);
  return { ok: true };
});

// ---- realtime: one user may have several open tabs/devices ----
const online = new Map(); // userId -> Set<socket>
const touchSeen = uid => pool.query("UPDATE users SET last_seen=now() WHERE id=$1", [uid]).catch(() => {});
const isOnline = uid => (online.get(uid)?.size ?? 0) > 0;
setInterval(() => { for (const uid of online.keys()) touchSeen(uid); }, 2 * 60 * 1000);
const pushTo = (userId, payload) => {
  const set = online.get(userId); if (!set || !set.size) return false;
  const msg = JSON.stringify(payload); let sent = false;
  for (const s of set) { try { s.send(msg); sent = true; } catch {} }
  return sent;
};
app.post("/messages", LIMIT_USER, async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const { to, type, content } = req.body ?? {};
  if (!to || !type || content == null) return reply.code(400).send({ error: "missing" });
  if (!ID_RE.test(to) || to === uid) return reply.code(400).send({ error: "bad-recipient" });
  if (await blockedEither(uid, to)) return reply.code(403).send({ error: "blocked" });
  if (!MSG_TYPES.has(type) || typeof content !== "string" || !content.trim()) return reply.code(400).send({ error: "bad-type" });
  if (type === "text" && content.length > 4000) return reply.code(400).send({ error: "too-long" });
  if ((type === "image" || type === "voice" || type === "video") && !FILE_URL_RE.test(content)) return reply.code(400).send({ error: "bad-content" });
  if (type === "location" && !/^-?\d{1,2}(\.\d+)?,-?\d{1,3}(\.\d+)?$/.test(content)) return reply.code(400).send({ error: "bad-content" });
  const id = crypto.randomUUID(); const sentAt = new Date().toISOString();
  await pool.query("INSERT INTO messages(id,sender_id,recipient_id,type,content) VALUES($1,$2,$3,$4,$5)",
    [id, uid, to, type, content]);
  const u = await pool.query("SELECT nickname FROM users WHERE id=$1",[uid]);
  const nick = u.rows[0]?.nickname ?? "";
  // replying/sending counts as accepting the other side; a message to someone who hasn't got me is a "request" for them
  pool.query("INSERT INTO contacts(owner_id,contact_id) VALUES($1,$2) ON CONFLICT DO NOTHING", [uid, to]).catch(() => {});
  const isRequest = !(await hasContact(to, uid));
  const delivered = pushTo(to, { id, senderId: uid, senderNickname: nick, type, content, sentAt, isRequest });
  let deliveredAt = null;
  if (delivered) { deliveredAt = new Date().toISOString(); pool.query("UPDATE messages SET delivered_at=$2 WHERE id=$1", [id, deliveredAt]).catch(() => {}); }
  else pushPreviewAllowed(to).then(show => sendPush(to, { title: isRequest ? "طلب مراسلة جديد" : (show ? nick : "Naslife"),
    body: show ? previewOf(type, content) : "رسالة جديدة", tag: "chat-" + uid, url: "/" })).catch(() => {});
  return { id, sentAt, deliveredAt };
});
// ---- media pipeline (hardened) ----
// The bytes decide the type (never the filename); hard limits on pixels, sides and duration; the original upload is a
// temp file that is always deleted, so only re-encoded output ever reaches /files/. Optional SCAN_COMMAND hook.
import { pipeline } from "node:stream/promises";
let mediaJobs = 0; const mediaQueue = [];
async function withMediaSlot(fn) {
  if (mediaJobs >= 2) await new Promise(r => mediaQueue.push(r));
  mediaJobs++;
  try { return await fn(); } finally { mediaJobs--; const next = mediaQueue.shift(); if (next) next(); }
}
const ffmpeg = (args, timeout = 240000) =>
  run("nice", ["-n", "10", "ffmpeg", "-y", "-hide_banner", "-loglevel", "error", ...args], { timeout });
async function probe(file) {
  const { stdout } = await run("ffprobe", ["-v", "error", "-show_streams", "-show_format", "-of", "json", file], { timeout: 30000 });
  return JSON.parse(stdout);
}
const unlinkQuiet = f => { try { fs.unlinkSync(f); } catch {} };
const MAX_IMAGE_PIXELS = Number(process.env.MAX_IMAGE_PIXELS ?? 40e6);   // 40 megapixels (all frames for animations)
const MAX_IMAGE_SIDE = 12000, MAX_VIDEO_SIDE = 4096;
const MAX_MEDIA_SECONDS = Number(process.env.MAX_MEDIA_SECONDS ?? 600);
const INCOMING_DIR = path.join(UPLOAD_DIR, ".incoming"); fs.mkdirSync(INCOMING_DIR, { recursive: true });
class MediaError extends Error { constructor(code, status = 415) { super(code); this.code = code; this.status = status; } }
// content sniffing: what the first bytes say
function sniff(h) {
  const t = h.toString("latin1", 0, 16);
  if (h[0] === 0xFF && h[1] === 0xD8 && h[2] === 0xFF) return "jpeg";
  if (t.startsWith("\x89PNG\r\n\x1a\n")) return "png";
  if (t.startsWith("GIF87a") || t.startsWith("GIF89a")) return "gif";
  if (t.startsWith("RIFF") && t.slice(8, 12) === "WEBP") return "webp";
  if (t.startsWith("RIFF") && t.slice(8, 12) === "WAVE") return "wav";
  if (t.slice(4, 8) === "ftyp") return /^(heic|heix|hevc|mif1|msf1)/.test(t.slice(8, 12)) ? "heic" : "mp4"; // mp4/mov/m4a/3gp family
  if (h[0] === 0x1A && h[1] === 0x45 && h[2] === 0xDF && h[3] === 0xA3) return "webm";
  if (t.startsWith("OggS")) return "ogg";
  if (t.startsWith("fLaC")) return "flac";
  if (h[0] === 0xFF && (h[1] & 0xF6) === 0xF0) return "aac";                       // ADTS
  if (t.startsWith("ID3") || (h[0] === 0xFF && (h[1] & 0xE0) === 0xE0)) return "mp3"; // MPEG audio frame sync
  return null;
}
const IMAGE_KINDS = new Set(["jpeg", "png", "gif", "webp", "heic"]);
const AV_KINDS = new Set(["mp4", "webm", "ogg", "wav", "mp3", "aac", "flac"]);
// stream the multipart part to a temp file (never the whole body in memory) and identify it
async function receiveUpload(data) {
  const tmp = path.join(INCOMING_DIR, crypto.randomUUID() + ".bin");
  try {
    await pipeline(data.file, fs.createWriteStream(tmp, { mode: 0o600 }));
    if (data.file.truncated) throw new MediaError("too-large", 413);
    const size = fs.statSync(tmp).size; if (!size) throw new MediaError("bad-file", 400);
    const fd = fs.openSync(tmp, "r"); const head = Buffer.alloc(16); fs.readSync(fd, head, 0, 16, 0); fs.closeSync(fd);
    const kind = sniff(head); if (!kind) throw new MediaError("unsupported-media");
    return { tmp, kind, size };
  } catch (e) { unlinkQuiet(tmp); throw e; }
}
// hook for an external scanner (e.g. SCAN_COMMAND="clamdscan --no-summary"): non-zero exit rejects the file
async function scanFile(file) {
  const cmd = String(process.env.SCAN_COMMAND ?? "").trim(); if (!cmd) return;
  const [bin, ...args] = cmd.split(/\s+/);
  try { await run(bin, [...args, file], { timeout: 120000 }); } catch { throw new MediaError("rejected-by-scan"); }
}
async function processUpload(tmp, kind) {
  const base = crypto.randomUUID();
  const out = ext => path.join(UPLOAD_DIR, base + "." + ext), work = ext => path.join(INCOMING_DIR, base + ".work." + ext);
  const cleanupWork = () => { for (const e of ["jpg", "gif", "mp4", "m4a"]) unlinkQuiet(work(e)); };
  try {
    await scanFile(tmp);
    if (IMAGE_KINDS.has(kind)) {
      let meta;
      try { meta = await sharp(tmp, { failOn: "error", animated: kind === "gif" }).metadata(); } // header only, nothing decoded yet
      catch { throw new MediaError("unsupported-media"); }
      const frameH = meta.pageHeight ?? meta.height, pages = meta.pages ?? 1;
      if (!meta.width || !frameH || meta.width > MAX_IMAGE_SIDE || frameH > MAX_IMAGE_SIDE || meta.width * frameH * pages > MAX_IMAGE_PIXELS)
        throw new MediaError("too-large", 413);
      const img = sharp(tmp, { failOn: "error", limitInputPixels: MAX_IMAGE_PIXELS, animated: kind === "gif" }); // the limit stays as a second guard
      if (kind === "gif" && pages > 1) {          // animated: re-encode (strips anything that is not pixels), capped at 800px wide
        try { await img.resize({ width: 800, withoutEnlargement: true }).gif({ effort: 3 }).toFile(work("gif")); } catch { throw new MediaError("unsupported-media"); }
        fs.renameSync(work("gif"), out("gif"));
        return { url: "/files/" + base + ".gif", kind: "image" };
      }
      try {
        await img.rotate().resize({ width: 1600, height: 1600, fit: "inside", withoutEnlargement: true }).jpeg({ quality: 82, mozjpeg: true }).toFile(work("jpg"));
      } catch { throw new MediaError("unsupported-media"); }
      fs.renameSync(work("jpg"), out("jpg"));
      return { url: "/files/" + base + ".jpg", kind: "image" };
    }
    if (!AV_KINDS.has(kind)) throw new MediaError("unsupported-media");
    let info; try { info = await probe(tmp); } catch { throw new MediaError("unsupported-media"); }
    const streams = info.streams ?? [];
    const video = streams.find(s => s.codec_type === "video" && !(s.disposition && s.disposition.attached_pic));
    const audio = streams.find(s => s.codec_type === "audio");
    const duration = Math.round(Number(info.format?.duration ?? 0));
    if (!video && !audio) throw new MediaError("unsupported-media");
    if (duration > MAX_MEDIA_SECONDS) throw new MediaError("too-long", 413);
    if (video && (Number(video.width) > MAX_VIDEO_SIDE || Number(video.height) > MAX_VIDEO_SIDE)) throw new MediaError("too-large", 413);
    if (video) {
      try {
        await ffmpeg(["-i", tmp, "-t", "90", "-vf", "scale='2*trunc(min(1280,iw)/2)':-2", "-c:v", "libx264", "-preset", "veryfast",
          "-crf", "26", "-pix_fmt", "yuv420p", ...(audio ? ["-c:a", "aac", "-b:a", "96k"] : ["-an"]), "-movflags", "+faststart", work("mp4")]);
      } catch { throw new MediaError("unsupported-media"); }
      fs.renameSync(work("mp4"), out("mp4"));
      await ffmpeg(["-ss", "0.3", "-i", out("mp4"), "-frames:v", "1", "-vf", "scale='2*trunc(min(640,iw)/2)':-2", "-q:v", "5", work("jpg")], 60000)
        .then(() => fs.renameSync(work("jpg"), out("jpg"))).catch(() => {});
      return { url: "/files/" + base + ".mp4", thumb: fs.existsSync(out("jpg")) ? "/files/" + base + ".jpg" : null, kind: "video", duration: Math.min(duration, 90) };
    }
    try { await ffmpeg(["-i", tmp, "-vn", "-c:a", "aac", "-b:a", "64k", "-ar", "44100", "-movflags", "+faststart", work("m4a")]); }
    catch { throw new MediaError("unsupported-media"); }
    fs.renameSync(work("m4a"), out("m4a"));
    return { url: "/files/" + base + ".m4a", kind: "audio", duration };
  } finally { unlinkQuiet(tmp); cleanupWork(); }
}
async function handleUpload(req, reply, { imageOnly = false } = {}) {
  const data = await req.file(); if (!data) { reply.code(400).send({ error: "no-file" }); return null; }
  try {
    const { tmp, kind } = await receiveUpload(data);
    if (imageOnly && !IMAGE_KINDS.has(kind)) { unlinkQuiet(tmp); throw new MediaError("bad-image", 400); }
    return await withMediaSlot(() => processUpload(tmp, kind));
  } catch (e) {
    if (e instanceof MediaError) { reply.code(e.status).send({ error: e.code }); return null; }
    app.log.warn({ err: String(e) }, "upload failed");
    reply.code(415).send({ error: "unsupported-media" }); return null;
  }
}
// delete a file (and a video's thumbnail) once no row references it any more; safe to call for any url
const FILE_REF_SQL = `SELECT (SELECT count(*) FROM messages WHERE content = ANY($1)) + (SELECT count(*) FROM posts WHERE content = ANY($1))
  + (SELECT count(*) FROM map_pins WHERE content = ANY($1)) + (SELECT count(*) FROM stories WHERE content = ANY($1))
  + (SELECT count(*) FROM users WHERE avatar_url = ANY($1)) + (SELECT count(*) FROM vessels WHERE cover_url = ANY($1))
  + (SELECT count(*) FROM businesses WHERE cover_url = ANY($1)) + (SELECT count(*) FROM profiles WHERE voice_intro_url = ANY($1)) AS n`;
async function releaseMedia(url) {
  const m = /^(?:https:\/\/(?:www\.)?naslife\.app)?\/files\/([0-9a-f-]{36})\.([a-z0-9]{1,5})$/.exec(String(url ?? "")); if (!m) return;
  const rel = "/files/" + m[1] + "." + m[2];
  try {
    const n = Number((await pool.query(FILE_REF_SQL, [[rel, "https://naslife.app" + rel, "https://www.naslife.app" + rel]])).rows[0]?.n ?? 1);
    if (n > 0) return;
    unlinkQuiet(path.join(UPLOAD_DIR, m[1] + "." + m[2]));
    if (m[2] === "mp4") unlinkQuiet(path.join(UPLOAD_DIR, m[1] + ".jpg"));
  } catch (e) { app.log.warn({ err: String(e), url }, "releaseMedia failed"); }
}
app.post("/upload", LIMIT_USER, async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const out = await handleUpload(req, reply); if (!out) return;
  return out;
});

// ---- stories on the map (expire after 24h) ----
const STORY_TYPES = new Set(["text", "image", "video"]);
const storyRow = r => ({ id: r.id, userId: r.user_id, nickname: r.nickname ?? "", type: r.type, content: r.content,
  caption: r.caption, lat: r.lat, lng: r.lng, createdAt: r.created_at, expiresAt: r.expires_at });
function parseBbox(q) {
  const a = String(q ?? "").split(",").map(Number);
  if (a.length !== 4 || a.some(n => !Number.isFinite(n))) return null;
  const [minLng, minLat, maxLng, maxLat] = a;
  if (minLat < -90 || maxLat > 90 || minLng < -180 || maxLng > 180 || minLat > maxLat || minLng > maxLng) return null;
  return { minLng, minLat, maxLng, maxLat };
}
// ~100 m: enough to place a story on the map, not enough to point at a door
const coarse = n => Math.round(Number(n) * 1000) / 1000;
app.get("/stories", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const bb = parseBbox(req.query?.bbox); if (!bb) return reply.code(400).send({ error: "bbox-required" });
  const r = await pool.query(`SELECT s.*, u.nickname FROM stories s JOIN users u ON u.id=s.user_id
    WHERE s.expires_at>now() AND s.lat BETWEEN $2 AND $4 AND s.lng BETWEEN $1 AND $3
      AND NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id=$5 AND b.blocked_id=s.user_id) OR (b.blocker_id=s.user_id AND b.blocked_id=$5))
    ORDER BY s.created_at DESC LIMIT 300`, [bb.minLng, bb.minLat, bb.maxLng, bb.maxLat, uid]);
  return r.rows.map(x => storyRow(x.user_id === uid ? x : { ...x, lat: coarse(x.lat), lng: coarse(x.lng) }));
});
app.post("/stories", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const { type, content, caption = "", lat, lng } = req.body ?? {};
  if (!STORY_TYPES.has(type)) return reply.code(400).send({ error: "bad-type" });
  if (typeof content !== "string" || !content.trim() || content.length > 2000) return reply.code(400).send({ error: "bad-content" });
  if (typeof caption !== "string" || caption.length > 280) return reply.code(400).send({ error: "bad-caption" });
  const la = Number(lat), ln = Number(lng);
  if (!Number.isFinite(la) || !Number.isFinite(ln) || Math.abs(la) > 90 || Math.abs(ln) > 180) return reply.code(400).send({ error: "bad-location" });
  const id = crypto.randomUUID();
  const r = await pool.query(
    "INSERT INTO stories(id,user_id,type,content,caption,lat,lng,expires_at) VALUES($1,$2,$3,$4,$5,$6,$7,now()+interval '24 hours') RETURNING *",
    [id, uid, type, content.trim(), caption.trim(), la, ln]);
  const u = await pool.query("SELECT nickname FROM users WHERE id=$1",[uid]);
  return storyRow({ ...r.rows[0], nickname: u.rows[0]?.nickname ?? "" });
});
app.delete("/stories/:id", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  if (!UUID_RE.test(req.params.id)) return reply.code(400).send({ error: "bad-id" });
  const r = await pool.query("DELETE FROM stories WHERE id=$1 AND user_id=$2 RETURNING content",[req.params.id, uid]);
  if (!r.rowCount) return reply.code(404).send({ error: "not-found" });
  releaseMedia(r.rows[0].content);
  return { ok: true };
});
setInterval(() => {
  pool.query("DELETE FROM stories WHERE expires_at < now() - interval '1 day' RETURNING content").then(r => r.rows.forEach(x => releaseMedia(x.content))).catch(() => {});
  pool.query("DELETE FROM sessions WHERE expires_at < now()").catch(() => {});
  pool.query("DELETE FROM map_pins WHERE expires_at IS NOT NULL AND expires_at < now() - interval '1 day' RETURNING content").then(r => r.rows.forEach(x => releaseMedia(x.content))).catch(() => {});
}, 60 * 60 * 1000);

// ================= map: opt-in presence + content pinned to places =================
const PIN_TYPES = new Set(["text", "voice", "image", "review"]);

const validLatLng = (lat, lng) => Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180;
const presenceExpired = r => !!r.expires_at && new Date(r.expires_at).getTime() <= Date.now();
const presenceOut = r => ({ userId: r.user_id, lat: r.lat, lng: r.lng, title: r.title ?? "", visible: r.visible && !presenceExpired(r),
  updatedAt: r.updated_at, hideAfterHours: r.hide_after_hours ?? null, expiresAt: r.expires_at ?? null });
const HIDE_AFTER_HOURS = new Set([1, 6, 24, 168]);
const pinOut = r => ({ id: r.id, ownerId: r.owner_id, ownerNickname: r.owner_nickname, ownerAvatar: r.owner_avatar, lat: r.lat, lng: r.lng,
  type: r.type, content: r.content, placeName: r.place_name, rating: r.rating, createdAt: r.created_at, expiresAt: r.expires_at });
app.get("/me/map-presence", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const r = await pool.query("SELECT * FROM map_presence WHERE user_id=$1", [uid]);
  return r.rowCount ? presenceOut(r.rows[0]) : { userId: uid, lat: null, lng: null, title: "", visible: false, updatedAt: null, hideAfterHours: null, expiresAt: null };
});
// visible defaults to false; turning it on requires coordinates the user chose explicitly
app.put("/me/map-presence", LIMIT_USER, async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const b = req.body ?? {};
  const cur = (await pool.query("SELECT * FROM map_presence WHERE user_id=$1", [uid])).rows[0];
  const lat = b.lat !== undefined ? Number(b.lat) : cur?.lat, lng = b.lng !== undefined ? Number(b.lng) : cur?.lng;
  const title = b.title !== undefined ? String(b.title).trim().slice(0, 60) : (cur?.title ?? "");
  const visible = b.visible !== undefined ? !!b.visible : (cur?.visible ?? false);
  // hideAfterHours: null/0 = stay until switched off (the default), else one of 1, 6, 24, 168
  let hours = b.hideAfterHours !== undefined ? b.hideAfterHours : (cur?.hide_after_hours ?? null);
  if (hours === 0 || hours === null || hours === "") hours = null;
  else { hours = Number(hours); if (!HIDE_AFTER_HOURS.has(hours)) return reply.code(400).send({ error: "bad-hide-after" }); }
  if ((lat !== undefined && lat !== null) && !validLatLng(lat, lng)) return reply.code(400).send({ error: "bad-location" });
  if (visible && !validLatLng(lat, lng)) return reply.code(400).send({ error: "location-required" });
  if (lat === undefined || lat === null) return { userId: uid, lat: null, lng: null, title, visible: false, updatedAt: null, hideAfterHours: hours, expiresAt: null };
  // every save of a visible pin restarts the countdown; an invisible pin has no expiry
  const expiresAt = visible && hours ? new Date(Date.now() + hours * 3600 * 1000) : null;
  const r = await pool.query(`INSERT INTO map_presence(user_id,lat,lng,title,visible,updated_at,hide_after_hours,expires_at) VALUES($1,$2,$3,$4,$5,now(),$6,$7)
    ON CONFLICT (user_id) DO UPDATE SET lat=EXCLUDED.lat, lng=EXCLUDED.lng, title=EXCLUDED.title, visible=EXCLUDED.visible, updated_at=now(),
      hide_after_hours=EXCLUDED.hide_after_hours, expires_at=EXCLUDED.expires_at RETURNING *`,
    [uid, lat, lng, title, visible, hours, expiresAt]);
  return presenceOut(r.rows[0]);
});
app.get("/map/presence", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const bb = parseBbox(req.query?.bbox); if (!bb) return reply.code(400).send({ error: "bad-bbox" });
  const r = await pool.query(`SELECT p.*, u.nickname, u.avatar_url FROM map_presence p JOIN users u ON u.id=p.user_id
    WHERE p.visible = true AND (p.expires_at IS NULL OR p.expires_at > now()) AND p.lat BETWEEN $2 AND $4 AND p.lng BETWEEN $1 AND $3
      AND NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id=$5 AND b.blocked_id=p.user_id) OR (b.blocker_id=p.user_id AND b.blocked_id=$5))
    ORDER BY p.updated_at DESC LIMIT 200`, [bb.minLng, bb.minLat, bb.maxLng, bb.maxLat, uid]);
  return r.rows.map(x => ({ id: x.user_id, nickname: x.nickname, avatarUrl: x.avatar_url, lat: x.lat, lng: x.lng, title: x.title ?? "",
    updatedAt: x.updated_at, online: isOnline(x.user_id), me: x.user_id === uid }));
});
app.post("/map/pins", LIMIT_USER, async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const { type, content, placeName, rating, expiresIn } = req.body ?? {};
  const lat = Number(req.body?.lat), lng = Number(req.body?.lng);
  if (!validLatLng(lat, lng)) return reply.code(400).send({ error: "bad-location" });
  if (!PIN_TYPES.has(type) || typeof content !== "string" || !content.trim()) return reply.code(400).send({ error: "bad-type" });
  if ((type === "text" || type === "review") && content.length > 1000) return reply.code(400).send({ error: "too-long" });
  if ((type === "voice" || type === "image") && !FILE_URL_RE.test(content)) return reply.code(400).send({ error: "bad-content" });
  const place = placeName == null ? null : String(placeName).trim().slice(0, 80) || null;
  let stars = null;
  if (type === "review") {
    stars = Number(rating);
    if (!place || !Number.isInteger(stars) || stars < 1 || stars > 5) return reply.code(400).send({ error: "bad-review" });
  }
  const ttl = { "24h": 24 * 3600e3, "7d": 7 * 24 * 3600e3 }[expiresIn] ?? null;
  const expiresAt = ttl ? new Date(Date.now() + ttl).toISOString() : null;
  const id = crypto.randomUUID();
  await pool.query("INSERT INTO map_pins(id,owner_id,lat,lng,type,content,place_name,rating,expires_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)",
    [id, uid, lat, lng, type, content.trim(), place, stars, expiresAt]);
  const r = await pool.query("SELECT p.*, u.nickname AS owner_nickname, u.avatar_url AS owner_avatar FROM map_pins p JOIN users u ON u.id=p.owner_id WHERE p.id=$1", [id]);
  return pinOut(r.rows[0]);
});
app.get("/map/pins", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const bb = parseBbox(req.query?.bbox); if (!bb) return reply.code(400).send({ error: "bad-bbox" });
  const types = String(req.query?.type ?? "").split(",").map(t => t.trim()).filter(t => PIN_TYPES.has(t));
  const r = await pool.query(`SELECT p.*, u.nickname AS owner_nickname, u.avatar_url AS owner_avatar FROM map_pins p JOIN users u ON u.id=p.owner_id
    WHERE (p.expires_at IS NULL OR p.expires_at > now()) AND p.lat BETWEEN $2 AND $4 AND p.lng BETWEEN $1 AND $3
      AND ($6::text[] IS NULL OR p.type = ANY($6))
      AND NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id=$5 AND b.blocked_id=p.owner_id) OR (b.blocker_id=p.owner_id AND b.blocked_id=$5))
    ORDER BY p.created_at DESC LIMIT 300`, [bb.minLng, bb.minLat, bb.maxLng, bb.maxLat, uid, types.length ? types : null]);
  return r.rows.map(pinOut);
});
app.delete("/map/pins/:id", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  if (!UUID_RE.test(req.params.id)) return reply.code(400).send({ error: "bad-id" });
  const r = await pool.query("DELETE FROM map_pins WHERE id=$1 AND owner_id=$2 RETURNING content", [req.params.id, uid]);
  if (!r.rowCount) return reply.code(404).send({ error: "not-found" });
  releaseMedia(r.rows[0].content);
  return { ok: true };
});

// ================= rich profiles with per-section visibility =================
const PROFILE_SECTIONS = ["bio", "voice", "skills", "hobbies", "lookingFor", "offerings"];
const EMPTY_PROFILE = { bio: "", voice_intro_url: null, skills: [], hobbies: [], looking_for: [], offerings: [],
  account_type: "personal", visibility: {}, is_public: true, updated_at: null };
const strList = (v, maxItems, maxLen) => Array.isArray(v) && v.length <= maxItems && v.every(x => typeof x === "string" && x.trim().length > 0 && x.length <= maxLen)
  ? v.map(x => x.trim()) : null;
function profileOut(row, u, { full, viewer }) {
  const vis = row.visibility ?? {};
  const show = k => full || vis[k] !== false;
  const out = { id: u.id, nickname: u.nickname, avatarUrl: u.avatar_url, accountType: row.account_type, isPublic: row.is_public,
    createdAt: u.created_at, online: isOnline(u.id), lastSeen: u.last_seen, restricted: false, updatedAt: row.updated_at };
  if (show("bio")) out.bio = row.bio;
  if (show("voice")) out.voiceIntroUrl = row.voice_intro_url;
  if (show("skills")) out.skills = row.skills;
  if (show("hobbies")) out.hobbies = row.hobbies;
  if (show("lookingFor")) out.lookingFor = row.looking_for;
  if (show("offerings")) out.offerings = row.offerings;
  if (full) out.visibility = Object.fromEntries(PROFILE_SECTIONS.map(k => [k, vis[k] !== false]));
  return out;
}
async function loadProfile(uid) {
  const u = await pool.query("SELECT id, nickname, avatar_url, created_at, last_seen FROM users WHERE id=$1", [uid]);
  if (!u.rowCount) return null;
  const p = await pool.query("SELECT * FROM profiles WHERE user_id=$1", [uid]);
  return { u: u.rows[0], row: p.rows[0] ?? EMPTY_PROFILE };
}
app.get("/me/profile", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const d = await loadProfile(uid); if (!d) return reply.code(404).send({ error: "not-found" });
  return profileOut(d.row, d.u, { full: true, viewer: uid });
});
app.put("/me/profile", LIMIT_USER, async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const b = req.body ?? {};
  const cur = (await loadProfile(uid)).row;
  const next = { bio: cur.bio, voice_intro_url: cur.voice_intro_url, skills: cur.skills, hobbies: cur.hobbies, looking_for: cur.looking_for,
    offerings: cur.offerings, account_type: cur.account_type, visibility: cur.visibility ?? {}, is_public: cur.is_public };
  if (b.bio !== undefined) { if (typeof b.bio !== "string" || b.bio.length > 1000) return reply.code(400).send({ error: "bad-bio" }); next.bio = b.bio.trim(); }
  if (b.voiceIntroUrl !== undefined) {
    if (b.voiceIntroUrl !== null && !(typeof b.voiceIntroUrl === "string" && FILE_URL_RE.test(b.voiceIntroUrl))) return reply.code(400).send({ error: "bad-voice" });
    next.voice_intro_url = b.voiceIntroUrl;
  }
  for (const [key, col] of [["skills", "skills"], ["hobbies", "hobbies"], ["lookingFor", "looking_for"]]) {
    if (b[key] !== undefined) { const l = strList(b[key], 30, 40); if (!l) return reply.code(400).send({ error: "bad-" + key }); next[col] = l; }
  }
  if (b.offerings !== undefined) {
    if (!Array.isArray(b.offerings) || b.offerings.length > 20) return reply.code(400).send({ error: "bad-offerings" });
    const list = [];
    for (const o of b.offerings) {
      const name = String(o?.name ?? "").trim(), description = String(o?.description ?? "").trim();
      const imageUrl = o?.imageUrl ? String(o.imageUrl) : null;
      if (!name || name.length > 60 || description.length > 500 || (imageUrl && !FILE_URL_RE.test(imageUrl))) return reply.code(400).send({ error: "bad-offerings" });
      list.push({ name, description, imageUrl });
    }
    next.offerings = list;
  }
  if (b.accountType !== undefined) { if (!["personal", "business"].includes(b.accountType)) return reply.code(400).send({ error: "bad-account-type" }); next.account_type = b.accountType; }
  if (b.visibility !== undefined) {
    if (typeof b.visibility !== "object" || b.visibility === null) return reply.code(400).send({ error: "bad-visibility" });
    const v = { ...next.visibility };
    for (const k of PROFILE_SECTIONS) if (b.visibility[k] !== undefined) v[k] = !!b.visibility[k];
    next.visibility = v;
  }
  if (b.isPublic !== undefined) next.is_public = !!b.isPublic;
  await pool.query(`INSERT INTO profiles(user_id,bio,voice_intro_url,skills,hobbies,looking_for,offerings,account_type,visibility,is_public,updated_at)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,now())
    ON CONFLICT (user_id) DO UPDATE SET bio=EXCLUDED.bio, voice_intro_url=EXCLUDED.voice_intro_url, skills=EXCLUDED.skills, hobbies=EXCLUDED.hobbies,
      looking_for=EXCLUDED.looking_for, offerings=EXCLUDED.offerings, account_type=EXCLUDED.account_type, visibility=EXCLUDED.visibility,
      is_public=EXCLUDED.is_public, updated_at=now()`,
    [uid, next.bio, next.voice_intro_url, JSON.stringify(next.skills), JSON.stringify(next.hobbies), JSON.stringify(next.looking_for),
     JSON.stringify(next.offerings), next.account_type, JSON.stringify(next.visibility), next.is_public]);
  const d = await loadProfile(uid);
  return profileOut(d.row, d.u, { full: true, viewer: uid });
});
// someone else's profile: only the sections they allow; private profiles only for their contacts
app.get("/profiles/:id", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const id = req.params.id;
  if (!ID_RE.test(id)) return reply.code(400).send({ error: "bad-user" });
  const d = await loadProfile(id); if (!d) return reply.code(404).send({ error: "not-found" });
  if (id === uid) return profileOut(d.row, d.u, { full: true, viewer: uid });
  if (await blockedEither(uid, id)) return reply.code(404).send({ error: "not-found" });
  if (!d.row.is_public && !(await hasContact(id, uid))) {
    return { id: d.u.id, nickname: d.u.nickname, avatarUrl: d.u.avatar_url, accountType: d.row.account_type, isPublic: false,
      restricted: true, online: isOnline(id), lastSeen: d.u.last_seen, createdAt: d.u.created_at };
  }
  return profileOut(d.row, d.u, { full: false, viewer: uid });
});

// ================= vessels: topic circles with posts, comments and symbolic support =================
const LIMIT_CREATE = { config: { rateLimit: { max: 10, timeWindow: "1 hour", keyGenerator: perUser } } };
const POST_TYPES = new Set(["text", "image", "voice"]);
const VESSEL_SELECT = `
  SELECT v.*, u.nickname AS owner_nickname, u.avatar_url AS owner_avatar,
    (SELECT count(*)::int FROM vessel_members m WHERE m.vessel_id=v.id) AS members,
    (SELECT count(*)::int FROM posts p WHERE p.vessel_id=v.id) AS posts,
    (SELECT max(p.created_at) FROM posts p WHERE p.vessel_id=v.id) AS last_post_at,
    (SELECT role FROM vessel_members m WHERE m.vessel_id=v.id AND m.user_id=$1) AS my_role,
    (SELECT muted FROM vessel_members m WHERE m.vessel_id=v.id AND m.user_id=$1) AS my_muted,
    (SELECT count(*)::int FROM posts p WHERE p.vessel_id=v.id AND p.author_id <> $1
       AND p.created_at > COALESCE((SELECT last_read_at FROM vessel_members m WHERE m.vessel_id=v.id AND m.user_id=$1), 'epoch')) AS unread,
    (SELECT verified FROM businesses b WHERE b.id=v.business_id) AS business_verified
  FROM vessels v JOIN users u ON u.id=v.owner_id`;
const vesselRow = r => ({ id: r.id, name: r.name, topic: r.topic, description: r.description, ownerId: r.owner_id,
  ownerNickname: r.owner_nickname, ownerAvatar: r.owner_avatar, coverUrl: r.cover_url, isPublic: r.is_public,
  createdAt: r.created_at, members: r.members, posts: r.posts, lastPostAt: r.last_post_at, role: r.my_role ?? null, joined: !!r.my_role,
  kind: r.kind ?? "general", districtId: r.district_id, businessId: r.business_id, lat: r.lat, lng: r.lng,
  unread: r.my_role ? (r.unread ?? 0) : 0, muted: r.my_muted === true, businessVerified: r.business_verified === true });
const POST_SELECT = `
  SELECT p.*, u.nickname AS author_nickname, u.avatar_url AS author_avatar, v.name AS vessel_name, v.kind AS vessel_kind,
    (SELECT count(*)::int FROM supports s WHERE s.post_id=p.id) AS supports,
    (SELECT count(*)::int FROM comments c WHERE c.post_id=p.id) AS comments,
    EXISTS (SELECT 1 FROM supports s WHERE s.post_id=p.id AND s.user_id=$1) AS supported
  FROM posts p JOIN users u ON u.id=p.author_id JOIN vessels v ON v.id=p.vessel_id`;
const postRow = r => ({ id: r.id, vesselId: r.vessel_id, vesselName: r.vessel_name, vesselKind: r.vessel_kind, authorId: r.author_id,
  authorNickname: r.author_nickname, authorAvatar: r.author_avatar, type: r.type, content: r.content, caption: r.caption,
  kind: r.kind ?? "discussion", tag: r.tag, createdAt: r.created_at, supports: r.supports, comments: r.comments, supported: r.supported === true });
const POST_KINDS = new Set(["discussion", "announcement"]);
const POST_TAGS = new Set(["lost", "warning", "event", "volunteer", "offer", "news"]);
const BUSINESS_CATEGORIES = new Set(["restaurant", "cafe", "grocery", "pharmacy", "clinic", "salon", "gym", "shop", "services", "education", "auto", "other"]);
const businessRow = r => ({ id: r.id, ownerId: r.owner_id, ownerNickname: r.owner_nickname ?? null, name: r.name, category: r.category,
  description: r.description, lat: r.lat, lng: r.lng, address: r.address, phone: r.phone, hours: r.hours, coverUrl: r.cover_url,
  verified: r.verified, status: r.status, vesselId: r.vessel_id, createdAt: r.created_at, followers: r.followers ?? 0, following: r.following === true });
const BUSINESS_SELECT = `
  SELECT b.*, u.nickname AS owner_nickname,
    (SELECT count(*)::int FROM vessel_members m WHERE m.vessel_id=b.vessel_id) AS followers,
    EXISTS (SELECT 1 FROM vessel_members m WHERE m.vessel_id=b.vessel_id AND m.user_id=$1) AS following
  FROM businesses b JOIN users u ON u.id=b.owner_id`;
// fan-out a new post to the circle's members: ws when online, web push otherwise (muted members skipped)
async function notifyVesselPost(post) {
  try {
    const m = await pool.query("SELECT user_id FROM vessel_members WHERE vessel_id=$1 AND user_id<>$2 AND muted=false LIMIT 500", [post.vesselId, post.authorId]);
    const body = `${post.authorNickname}: ${previewOf(post.type, post.type === "text" ? post.content : post.caption || post.content)}`;
    const title = (post.kind === "announcement" ? "📣 " : "") + post.vesselName;
    for (const row of m.rows) {
      if (!pushTo(row.user_id, { event: "vesselPost", vesselId: post.vesselId, vesselName: post.vesselName, post }))
        sendPush(row.user_id, { title, body, tag: "vessel-" + post.vesselId, url: "/" }).catch(() => {});
    }
  } catch (e) { app.log.warn({ err: String(e) }, "vessel notify failed"); }
}
const memberRole = async (vid, uid) => (await pool.query("SELECT role FROM vessel_members WHERE vessel_id=$1 AND user_id=$2", [vid, uid])).rows[0]?.role ?? null;
// ---- vessel access: the single place that decides who may see or write in a circle ----
// null = no such vessel. canView: public, or a member; a banned user can neither view nor rejoin. canWrite: member (not banned).
async function vesselAccess(vid, uid) {
  const v = (await pool.query("SELECT id, is_public, kind, owner_id FROM vessels WHERE id=$1", [vid])).rows[0];
  if (!v) return null;
  const [m, b] = await Promise.all([
    pool.query("SELECT role FROM vessel_members WHERE vessel_id=$1 AND user_id=$2", [vid, uid]),
    pool.query("SELECT 1 FROM vessel_bans WHERE vessel_id=$1 AND user_id=$2", [vid, uid]),
  ]);
  const banned = b.rowCount > 0, role = banned ? null : (m.rows[0]?.role ?? null);
  return { vessel: v, role, banned, canView: !banned && (v.is_public || !!role), canWrite: !!role };
}
// Sends the right error and returns null when the caller may not view/write; otherwise the access record.
async function requireVessel(reply, vid, uid, { write = false } = {}) {
  if (!UUID_RE.test(vid)) { reply.code(400).send({ error: "bad-id" }); return null; }
  const a = await vesselAccess(vid, uid);
  if (!a) { reply.code(404).send({ error: "not-found" }); return null; }
  if (a.banned) { reply.code(403).send({ error: "banned" }); return null; }
  if (!a.canView) { reply.code(403).send({ error: "private" }); return null; }
  if (write && !a.canWrite) { reply.code(403).send({ error: "members-only" }); return null; }
  return a;
}
// Same, starting from a post id (vessel access is inherited from the post's circle).
async function requirePost(reply, pid, uid, opts) {
  if (!UUID_RE.test(pid)) { reply.code(400).send({ error: "bad-id" }); return null; }
  const p = (await pool.query("SELECT id, vessel_id, author_id FROM posts WHERE id=$1", [pid])).rows[0];
  if (!p) { reply.code(404).send({ error: "not-found" }); return null; }
  const a = await requireVessel(reply, p.vessel_id, uid, opts);
  return a ? { ...a, post: p } : null;
}
const canModerate = role => role === "owner" || role === "moderator";
const validVesselFields = body => {
  const name = String(body?.name ?? "").trim(), topic = String(body?.topic ?? "").trim(), description = String(body?.description ?? "").trim();
  if (name.length < 2 || name.length > 60) return { error: "bad-name" };
  if (topic.length < 2 || topic.length > 60) return { error: "bad-topic" };
  if (description.length > 1000) return { error: "bad-description" };
  const coverUrl = body?.coverUrl ? String(body.coverUrl) : null;
  if (coverUrl && !FILE_URL_RE.test(coverUrl)) return { error: "bad-cover" };
  return { name, topic, description, coverUrl, isPublic: body?.isPublic === undefined ? true : !!body.isPublic };
};

app.post("/vessels", LIMIT_CREATE, async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const f = validVesselFields(req.body); if (f.error) return reply.code(400).send({ error: f.error });
  const id = crypto.randomUUID();
  await withTx(pool, async c => {
    await c.query("INSERT INTO vessels(id,name,topic,description,owner_id,cover_url,is_public) VALUES($1,$2,$3,$4,$5,$6,$7)",
      [id, f.name, f.topic, f.description, uid, f.coverUrl, f.isPublic]);
    await c.query("INSERT INTO vessel_members(vessel_id,user_id,role) VALUES($1,$2,'owner')", [id, uid]);
  });
  const r = await pool.query(VESSEL_SELECT + " WHERE v.id=$2", [uid, id]);
  return vesselRow(r.rows[0]);
});
// public directory: sort=new|active, optional q (name/topic search)
app.get("/vessels", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const q = String(req.query?.q ?? "").trim().slice(0, 60);
  const active = req.query?.sort === "active";
  const kind = ["general", "district", "business"].includes(req.query?.kind) ? req.query.kind : "general";
  const r = await pool.query(VESSEL_SELECT + ` WHERE v.is_public = true AND v.kind = $3 AND ($2 = '' OR v.name ILIKE '%' || $2 || '%' OR v.topic ILIKE '%' || $2 || '%')
    ORDER BY ${active ? "last_post_at DESC NULLS LAST, members DESC," : ""} v.created_at DESC LIMIT 100`, [uid, q, kind]);
  return r.rows.map(vesselRow);
});
// what's new across my circles (newest first); unread = newer than my last visit to that circle
app.get("/vessels/feed", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const r = await pool.query(POST_SELECT + ` JOIN vessel_members mm ON mm.vessel_id=p.vessel_id AND mm.user_id=$1
    ORDER BY p.created_at DESC LIMIT 60`, [uid]);
  const seen = await pool.query("SELECT vessel_id, last_read_at FROM vessel_members WHERE user_id=$1", [uid]);
  const lastRead = Object.fromEntries(seen.rows.map(x => [x.vessel_id, new Date(x.last_read_at).getTime()]));
  return r.rows.map(x => ({ ...postRow(x), unread: x.author_id !== uid && new Date(x.created_at).getTime() > (lastRead[x.vessel_id] ?? 0) }));
});
app.post("/vessels/:id/seen", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  if (!UUID_RE.test(req.params.id)) return reply.code(400).send({ error: "bad-id" });
  await pool.query("UPDATE vessel_members SET last_read_at=now() WHERE vessel_id=$1 AND user_id=$2", [req.params.id, uid]);
  return { ok: true };
});
app.post("/vessels/:id/mute", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  if (!UUID_RE.test(req.params.id)) return reply.code(400).send({ error: "bad-id" });
  await pool.query("UPDATE vessel_members SET muted=$3 WHERE vessel_id=$1 AND user_id=$2", [req.params.id, uid, !!req.body?.muted]);
  return { ok: true, muted: !!req.body?.muted };
});

// ================= districts of Jeddah: one circle per neighbourhood, owned by the system account =================
async function ensureDistrictVessel(d) {
  if (d.vessel_id) return d.vessel_id;
  const id = crypto.randomUUID();
  await pool.query("INSERT INTO vessels(id,name,topic,description,owner_id,is_public,kind,district_id,lat,lng) VALUES($1,$2,$3,$4,'SA0000000',true,'district',$5,$6,$7)",
    [id, d.name_ar, "حي في جدة", `دائرة سكان حي ${d.name_ar} في جدة: نقاشات الجيران وإعلانات الحي.`, d.id, d.lat, d.lng]);
  await pool.query("UPDATE districts SET vessel_id=$1 WHERE id=$2", [id, d.id]);
  return id;
}
app.post("/admin/districts/import", async (req, reply) => {
  const who = await adminAuth(req, reply); if (!who) return;
  await audit(req, who, "districts.import", { targetType: "districts", after: { rows: Array.isArray(req.body) ? req.body.length : 0 } });
  const rows = Array.isArray(req.body) ? req.body : [];
  let created = 0;
  for (const r of rows) {
    if (!r.nameAr || !validLatLng(Number(r.lat), Number(r.lng))) continue;
    const d = (await pool.query(`INSERT INTO districts(city,osm_id,name_ar,name_en,lat,lng) VALUES('jeddah',$1,$2,$3,$4,$5)
      ON CONFLICT (osm_id) DO UPDATE SET name_ar=EXCLUDED.name_ar, name_en=EXCLUDED.name_en, lat=EXCLUDED.lat, lng=EXCLUDED.lng RETURNING *`,
      [r.osmId ?? null, String(r.nameAr).slice(0, 80), r.nameEn ? String(r.nameEn).slice(0, 80) : null, Number(r.lat), Number(r.lng)])).rows[0];
    if (!d.vessel_id) { await ensureDistrictVessel(d); created++; }
  }
  const n = await pool.query("SELECT count(*)::int AS n FROM districts");
  return { ok: true, districts: n.rows[0].n, circlesCreated: created };
});
const districtRow = r => ({ id: r.id, city: r.city, nameAr: r.name_ar, nameEn: r.name_en, lat: r.lat, lng: r.lng, vesselId: r.vessel_id, members: r.members ?? 0 });
app.get("/districts", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const q = String(req.query?.q ?? "").trim().slice(0, 60);
  const r = await pool.query(`SELECT d.*, (SELECT count(*)::int FROM vessel_members m WHERE m.vessel_id=d.vessel_id) AS members
    FROM districts d WHERE d.city='jeddah' AND ($1 = '' OR d.name_ar ILIKE '%' || $1 || '%' OR d.name_en ILIKE '%' || $1 || '%') ORDER BY d.name_ar LIMIT 300`, [q]);
  return r.rows.map(districtRow);
});
app.get("/me/district", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const r = await pool.query(`SELECT d.*, (SELECT count(*)::int FROM vessel_members m WHERE m.vessel_id=d.vessel_id) AS members
    FROM users u JOIN districts d ON d.id=u.district_id WHERE u.id=$1`, [uid]);
  return r.rowCount ? districtRow(r.rows[0]) : null;
});
// choosing a district joins its circle (and leaves the previous district circle); null clears it
app.put("/me/district", LIMIT_USER, async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const did = req.body?.districtId == null ? null : Number(req.body.districtId);
  const d = did === null ? null : await pool.query("SELECT * FROM districts WHERE id=$1", [did]);
  if (d && !d.rowCount) return reply.code(404).send({ error: "not-found" });
  const vid = d ? await ensureDistrictVessel(d.rows[0]) : null;
  await withTx(pool, async c => {   // leave the old district circle, set the district, join the new circle: atomically
    const prev = await c.query("SELECT d.vessel_id FROM users u JOIN districts d ON d.id=u.district_id WHERE u.id=$1", [uid]);
    if (prev.rowCount && prev.rows[0].vessel_id) await c.query("DELETE FROM vessel_members WHERE vessel_id=$1 AND user_id=$2 AND role='member'", [prev.rows[0].vessel_id, uid]);
    await c.query("UPDATE users SET district_id=$1 WHERE id=$2", [did, uid]);
    if (vid) await c.query("INSERT INTO vessel_members(vessel_id,user_id) VALUES($1,$2) ON CONFLICT DO NOTHING", [vid, uid]);
  });
  if (did === null) return null;
  const r = await pool.query(`SELECT d.*, (SELECT count(*)::int FROM vessel_members m WHERE m.vessel_id=d.vessel_id) AS members FROM districts d WHERE d.id=$1`, [did]);
  return districtRow(r.rows[0]);
});

// ================= businesses: a place on the map + a circle its followers get updates from =================
app.post("/businesses", LIMIT_CREATE, async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const b = req.body ?? {};
  const name = String(b.name ?? "").trim(), category = String(b.category ?? "other");
  const lat = Number(b.lat), lng = Number(b.lng);
  if (name.length < 2 || name.length > 80) return reply.code(400).send({ error: "bad-name" });
  if (!BUSINESS_CATEGORIES.has(category)) return reply.code(400).send({ error: "bad-category" });
  if (!validLatLng(lat, lng)) return reply.code(400).send({ error: "bad-location" });
  const description = String(b.description ?? "").trim().slice(0, 1000);
  const address = b.address ? String(b.address).trim().slice(0, 160) : null, phone = b.phone ? String(b.phone).trim().slice(0, 30) : null;
  const hours = b.hours ? String(b.hours).trim().slice(0, 120) : null;
  const coverUrl = b.coverUrl ? String(b.coverUrl) : null;
  if (coverUrl && !FILE_URL_RE.test(coverUrl)) return reply.code(400).send({ error: "bad-cover" });
  const id = crypto.randomUUID(), vid = crypto.randomUUID();
  await withTx(pool, async c => {   // circle + owner membership + business row: all or nothing
    await c.query("INSERT INTO vessels(id,name,topic,description,owner_id,cover_url,is_public,kind,business_id,lat,lng) VALUES($1,$2,$3,$4,$5,$6,true,'business',$7,$8,$9)",
      [vid, name, category, description, uid, coverUrl, id, lat, lng]);
    await c.query("INSERT INTO vessel_members(vessel_id,user_id,role) VALUES($1,$2,'owner')", [vid, uid]);
    await c.query("INSERT INTO businesses(id,owner_id,name,category,description,lat,lng,address,phone,hours,cover_url,vessel_id) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)",
      [id, uid, name, category, description, lat, lng, address, phone, hours, coverUrl, vid]);
  });
  const r = await pool.query(BUSINESS_SELECT + " WHERE b.id=$2", [uid, id]);
  return businessRow(r.rows[0]);
});
app.get("/businesses", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const bb = parseBbox(req.query?.bbox);
  const mine = req.query?.mine === "1";
  if (!bb && !mine) return reply.code(400).send({ error: "bad-bbox" });
  const cat = BUSINESS_CATEGORIES.has(req.query?.category) ? req.query.category : null;
  const r = mine
    ? await pool.query(BUSINESS_SELECT + " WHERE b.owner_id=$1 ORDER BY b.created_at DESC", [uid])
    : await pool.query(BUSINESS_SELECT + ` WHERE b.status <> 'rejected' AND b.lat BETWEEN $3 AND $5 AND b.lng BETWEEN $2 AND $4 AND ($6::text IS NULL OR b.category=$6)
        AND NOT EXISTS (SELECT 1 FROM blocks bl WHERE (bl.blocker_id=$1 AND bl.blocked_id=b.owner_id) OR (bl.blocker_id=b.owner_id AND bl.blocked_id=$1))
        ORDER BY b.verified DESC, followers DESC LIMIT 300`, [uid, bb.minLng, bb.minLat, bb.maxLng, bb.maxLat, cat]);
  return r.rows.map(businessRow);
});
app.get("/businesses/:id", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  if (!UUID_RE.test(req.params.id)) return reply.code(400).send({ error: "bad-id" });
  const r = await pool.query(BUSINESS_SELECT + " WHERE b.id=$2", [uid, req.params.id]);
  if (!r.rowCount) return reply.code(404).send({ error: "not-found" });
  return businessRow(r.rows[0]);
});
app.patch("/businesses/:id", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  if (!UUID_RE.test(req.params.id)) return reply.code(400).send({ error: "bad-id" });
  const cur = await pool.query("SELECT * FROM businesses WHERE id=$1 AND owner_id=$2", [req.params.id, uid]);
  if (!cur.rowCount) return reply.code(403).send({ error: "owner-only" });
  const c = cur.rows[0], b = req.body ?? {};
  const name = b.name !== undefined ? String(b.name).trim().slice(0, 80) : c.name;
  const category = b.category !== undefined ? String(b.category) : c.category;
  if (name.length < 2 || !BUSINESS_CATEGORIES.has(category)) return reply.code(400).send({ error: "bad-fields" });
  const lat = b.lat !== undefined ? Number(b.lat) : c.lat, lng = b.lng !== undefined ? Number(b.lng) : c.lng;
  if (!validLatLng(lat, lng)) return reply.code(400).send({ error: "bad-location" });
  const coverUrl = b.coverUrl !== undefined ? (b.coverUrl ? String(b.coverUrl) : null) : c.cover_url;
  if (coverUrl && !FILE_URL_RE.test(coverUrl)) return reply.code(400).send({ error: "bad-cover" });
  await pool.query(`UPDATE businesses SET name=$1, category=$2, description=$3, lat=$4, lng=$5, address=$6, phone=$7, hours=$8, cover_url=$9 WHERE id=$10`,
    [name, category, b.description !== undefined ? String(b.description).slice(0, 1000) : c.description, lat, lng,
     b.address !== undefined ? (b.address ? String(b.address).slice(0, 160) : null) : c.address,
     b.phone !== undefined ? (b.phone ? String(b.phone).slice(0, 30) : null) : c.phone,
     b.hours !== undefined ? (b.hours ? String(b.hours).slice(0, 120) : null) : c.hours, coverUrl, req.params.id]);
  if (c.vessel_id) await pool.query("UPDATE vessels SET name=$1, topic=$2, cover_url=$3, lat=$4, lng=$5 WHERE id=$6", [name, category, coverUrl, lat, lng, c.vessel_id]);
  const r = await pool.query(BUSINESS_SELECT + " WHERE b.id=$2", [uid, req.params.id]);
  return businessRow(r.rows[0]);
});
app.get("/admin/businesses", async (req, reply) => {
  const who = await adminAuth(req, reply); if (!who) return;
  const status = req.query?.status;
  const r = await pool.query(BUSINESS_SELECT + " WHERE ($2::text IS NULL OR b.status=$2) ORDER BY b.created_at DESC LIMIT 500", ["SA0000000", status ?? null]);
  return r.rows.map(businessRow);
});
app.patch("/admin/businesses/:id", async (req, reply) => {
  const who = await adminAuth(req, reply); if (!who) return;
  if (!UUID_RE.test(req.params.id)) return reply.code(400).send({ error: "bad-id" });
  const status = req.body?.status;
  if (!["pending", "approved", "rejected"].includes(status)) return reply.code(400).send({ error: "bad-status" });
  const r = await pool.query("UPDATE businesses SET status=$1, verified=$2 WHERE id=$3 RETURNING (SELECT status FROM businesses WHERE id=$3) AS prev", [status, status === "approved", req.params.id]);
  if (!r.rowCount) return reply.code(404).send({ error: "not-found" });
  await audit(req, who, "business.status", { targetType: "business", targetId: req.params.id, reason: req.body?.reason ?? null,
    before: { status: r.rows[0].prev }, after: { status, verified: status === "approved" } });
  return { ok: true };
});
app.get("/vessels/mine", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const r = await pool.query(VESSEL_SELECT + " WHERE EXISTS (SELECT 1 FROM vessel_members m WHERE m.vessel_id=v.id AND m.user_id=$1) ORDER BY last_post_at DESC NULLS LAST, v.created_at DESC", [uid]);
  return r.rows.map(vesselRow);
});
app.get("/vessels/:id", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  if (!await requireVessel(reply, req.params.id, uid)) return;
  const r = await pool.query(VESSEL_SELECT + " WHERE v.id=$2", [uid, req.params.id]);
  if (!r.rowCount) return reply.code(404).send({ error: "not-found" });
  const v = vesselRow(r.rows[0]);
  const p = await pool.query(POST_SELECT + " WHERE p.vessel_id=$2 ORDER BY p.created_at DESC LIMIT 20", [uid, v.id]);
  return { ...v, postsPage: p.rows.map(postRow) };
});
app.patch("/vessels/:id", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  if (!UUID_RE.test(req.params.id)) return reply.code(400).send({ error: "bad-id" });
  if ((await memberRole(req.params.id, uid)) !== "owner") return reply.code(403).send({ error: "owner-only" });
  const cur = await pool.query("SELECT name,topic,description,cover_url,is_public FROM vessels WHERE id=$1", [req.params.id]);
  if (!cur.rowCount) return reply.code(404).send({ error: "not-found" });
  const merged = { name: cur.rows[0].name, topic: cur.rows[0].topic, description: cur.rows[0].description,
    coverUrl: cur.rows[0].cover_url, isPublic: cur.rows[0].is_public, ...(req.body ?? {}) };
  const f = validVesselFields(merged); if (f.error) return reply.code(400).send({ error: f.error });
  await pool.query("UPDATE vessels SET name=$1, topic=$2, description=$3, cover_url=$4, is_public=$5 WHERE id=$6",
    [f.name, f.topic, f.description, f.coverUrl, f.isPublic, req.params.id]);
  const r = await pool.query(VESSEL_SELECT + " WHERE v.id=$2", [uid, req.params.id]);
  return vesselRow(r.rows[0]);
});
app.delete("/vessels/:id", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  if (!UUID_RE.test(req.params.id)) return reply.code(400).send({ error: "bad-id" });
  const r = await pool.query("DELETE FROM vessels WHERE id=$1 AND owner_id=$2", [req.params.id, uid]);
  if (!r.rowCount) return reply.code(403).send({ error: "owner-only" });
  return { ok: true };
});
app.post("/vessels/:id/join", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  if (!UUID_RE.test(req.params.id)) return reply.code(400).send({ error: "bad-id" });
  const a = await vesselAccess(req.params.id, uid);
  if (!a) return reply.code(404).send({ error: "not-found" });
  if (a.banned) return reply.code(403).send({ error: "banned" });
  if (!a.vessel.is_public) return reply.code(403).send({ error: "private" });
  await pool.query("INSERT INTO vessel_members(vessel_id,user_id) VALUES($1,$2) ON CONFLICT DO NOTHING", [req.params.id, uid]);
  return { ok: true };
});
app.post("/vessels/:id/leave", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  if (!UUID_RE.test(req.params.id)) return reply.code(400).send({ error: "bad-id" });
  if ((await memberRole(req.params.id, uid)) === "owner") return reply.code(400).send({ error: "owner-cannot-leave" });
  await pool.query("DELETE FROM vessel_members WHERE vessel_id=$1 AND user_id=$2", [req.params.id, uid]);
  return { ok: true };
});
// owner/moderator removes a member; ?ban=1 also keeps them out for good
app.delete("/vessels/:id/members/:userId", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const a = await requireVessel(reply, req.params.id, uid); if (!a) return;
  if (!canModerate(a.role)) return reply.code(403).send({ error: "owner-only" });
  const target = req.params.userId;
  if (!ID_RE.test(target)) return reply.code(400).send({ error: "bad-id" });
  if (target === a.vessel.owner_id) return reply.code(400).send({ error: "cannot-remove-owner" });
  await pool.query("DELETE FROM vessel_members WHERE vessel_id=$1 AND user_id=$2", [req.params.id, target]);
  if (req.query?.ban === "1") await pool.query("INSERT INTO vessel_bans(vessel_id,user_id,by_id) VALUES($1,$2,$3) ON CONFLICT DO NOTHING", [req.params.id, target, uid]);
  return { ok: true };
});
app.get("/vessels/:id/members", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  if (!await requireVessel(reply, req.params.id, uid)) return;
  const r = await pool.query("SELECT u.id, u.nickname, u.avatar_url, m.role, m.joined_at FROM vessel_members m JOIN users u ON u.id=m.user_id WHERE m.vessel_id=$1 ORDER BY m.role='owner' DESC, m.joined_at LIMIT 500", [req.params.id]);
  return r.rows.map(x => ({ id: x.id, nickname: x.nickname, avatarUrl: x.avatar_url, role: x.role, joinedAt: x.joined_at }));
});
// posts
app.post("/vessels/:id/posts", LIMIT_USER, async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const access = await requireVessel(reply, req.params.id, uid, { write: true }); if (!access) return;
  const role = access.role;
  const vk = (await pool.query("SELECT kind FROM vessels WHERE id=$1", [req.params.id])).rows[0]?.kind ?? "general";
  const kind = req.body?.kind === "announcement" ? "announcement" : "discussion";
  const tag = req.body?.tag && POST_TAGS.has(req.body.tag) ? req.body.tag : null;
  if (vk === "business" && !canModerate(role)) return reply.code(403).send({ error: "owner-only" });
  if (kind === "announcement" && !canModerate(role)) return reply.code(403).send({ error: "moderators-only" });
  const { type, content, caption = "" } = req.body ?? {};
  if (!POST_TYPES.has(type) || typeof content !== "string" || !content.trim()) return reply.code(400).send({ error: "bad-type" });
  if (type === "text" && content.length > 4000) return reply.code(400).send({ error: "too-long" });
  if (type !== "text" && !FILE_URL_RE.test(content)) return reply.code(400).send({ error: "bad-content" });
  if (typeof caption !== "string" || caption.length > 500) return reply.code(400).send({ error: "bad-caption" });
  const id = crypto.randomUUID();
  await pool.query("INSERT INTO posts(id,vessel_id,author_id,type,content,caption,kind,tag) VALUES($1,$2,$3,$4,$5,$6,$7,$8)",
    [id, req.params.id, uid, type, content.trim(), caption.trim(), kind, tag]);
  const r = await pool.query(POST_SELECT + " WHERE p.id=$2", [uid, id]);
  const out = postRow(r.rows[0]);
  notifyVesselPost(out);
  return out;
});
app.get("/vessels/:id/posts", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  if (!await requireVessel(reply, req.params.id, uid)) return;
  const before = req.query?.before && !isNaN(Date.parse(req.query.before)) ? new Date(req.query.before).toISOString() : null;
  const kind = POST_KINDS.has(req.query?.kind) ? req.query.kind : null;
  const r = await pool.query(POST_SELECT + " WHERE p.vessel_id=$2 AND ($3::timestamptz IS NULL OR p.created_at < $3) AND ($4::text IS NULL OR p.kind=$4) ORDER BY p.created_at DESC LIMIT 20",
    [uid, req.params.id, before, kind]);
  return r.rows.map(postRow);
});
app.get("/posts/:id", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  if (!await requirePost(reply, req.params.id, uid)) return;
  const r = await pool.query(POST_SELECT + " WHERE p.id=$2", [uid, req.params.id]);
  if (!r.rowCount) return reply.code(404).send({ error: "not-found" });
  return postRow(r.rows[0]);
});
app.delete("/posts/:id", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  if (!UUID_RE.test(req.params.id)) return reply.code(400).send({ error: "bad-id" });
  const p = await pool.query("SELECT author_id, vessel_id FROM posts WHERE id=$1", [req.params.id]);
  if (!p.rowCount) return reply.code(404).send({ error: "not-found" });
  const allowed = p.rows[0].author_id === uid || canModerate(await memberRole(p.rows[0].vessel_id, uid));
  if (!allowed) return reply.code(403).send({ error: "forbidden" });
  const gone = await pool.query("DELETE FROM posts WHERE id=$1 RETURNING content", [req.params.id]);
  releaseMedia(gone.rows[0]?.content);
  return { ok: true };
});
// comments
app.get("/posts/:id/comments", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  if (!await requirePost(reply, req.params.id, uid)) return;
  const r = await pool.query("SELECT c.*, u.nickname AS author_nickname, u.avatar_url AS author_avatar FROM comments c JOIN users u ON u.id=c.author_id WHERE c.post_id=$1 ORDER BY c.created_at LIMIT 200", [req.params.id]);
  return r.rows.map(c => ({ id: c.id, postId: c.post_id, authorId: c.author_id, authorNickname: c.author_nickname, authorAvatar: c.author_avatar, text: c.text, createdAt: c.created_at }));
});
app.post("/posts/:id/comments", LIMIT_USER, async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  const pa = await requirePost(reply, req.params.id, uid, { write: true }); if (!pa) return;
  const p = { rows: [{ vessel_id: pa.post.vessel_id }] };
  const text = String(req.body?.text ?? "").trim();
  if (!text || text.length > 1000) return reply.code(400).send({ error: "bad-text" });
  const id = crypto.randomUUID();
  await pool.query("INSERT INTO comments(id,post_id,author_id,text) VALUES($1,$2,$3,$4)", [id, req.params.id, uid, text]);
  const u = await pool.query("SELECT nickname, avatar_url FROM users WHERE id=$1", [uid]);
  return { id, postId: req.params.id, authorId: uid, authorNickname: u.rows[0].nickname, authorAvatar: u.rows[0].avatar_url, text, createdAt: new Date().toISOString() };
});
app.delete("/comments/:id", async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  if (!UUID_RE.test(req.params.id)) return reply.code(400).send({ error: "bad-id" });
  const c = await pool.query("SELECT c.author_id, p.vessel_id FROM comments c JOIN posts p ON p.id=c.post_id WHERE c.id=$1", [req.params.id]);
  if (!c.rowCount) return reply.code(404).send({ error: "not-found" });
  const allowed = c.rows[0].author_id === uid || canModerate(await memberRole(c.rows[0].vessel_id, uid));
  if (!allowed) return reply.code(403).send({ error: "forbidden" });
  await pool.query("DELETE FROM comments WHERE id=$1", [req.params.id]);
  return { ok: true };
});
// support toggle (symbolic; a paid tier can hang off this table later)
app.post("/posts/:id/support", LIMIT_USER, async (req, reply) => {
  const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
  if (!await requirePost(reply, req.params.id, uid, { write: true })) return;
  const del = await pool.query("DELETE FROM supports WHERE post_id=$1 AND user_id=$2", [req.params.id, uid]);
  if (!del.rowCount) await pool.query("INSERT INTO supports(post_id,user_id) VALUES($1,$2)", [req.params.id, uid]);
  const n = await pool.query("SELECT count(*)::int AS n FROM supports WHERE post_id=$1", [req.params.id]);
  return { supported: !del.rowCount, count: n.rows[0].n };
});

const WS_AUTH_TIMEOUT_MS = Number(process.env.WS_AUTH_TIMEOUT_MS ?? 5000);
const WS_LEGACY_QUERY_TOKEN = process.env.WS_LEGACY_QUERY_TOKEN !== "0";
app.get("/ws", { websocket: true, config: { rateLimit: false } }, async (socket, req) => {
  // preferred: first frame {type:"auth", token}; transition: ?token= in the URL (old web builds) until WS_LEGACY_QUERY_TOKEN=0
  let session = WS_LEGACY_QUERY_TOKEN ? await authToken(new URL(req.url, "http://x").searchParams.get("token")) : null;
  if (!session) session = await new Promise(resolve => {
    const timer = setTimeout(() => resolve(null), WS_AUTH_TIMEOUT_MS);
    socket.once("message", async raw => { clearTimeout(timer);
      let j; try { j = JSON.parse(String(raw)); } catch { return resolve(null); }
      resolve(j?.type === "auth" ? await authToken(j.token) : null); });
    socket.once("close", () => { clearTimeout(timer); resolve(null); });
  });
  const userId = session?.userId ?? null;
  if (!userId) return socket.close(4001, "unauthorized");
  try { socket.send(JSON.stringify({ event: "ready" })); } catch {}
  if (!online.has(userId)) online.set(userId, new Set());
  online.get(userId).add(socket);
  touchSeen(userId);
  socket.on("message", async raw => {
    let j; try { j = JSON.parse(String(raw)); } catch { return; }
    if (j?.type === "ping") { touchSeen(userId); return; }
    if (j?.type === "typing" && ID_RE.test(j.to ?? "") && j.to !== userId && isOnline(j.to)) {
      if (await blockedEither(userId, j.to)) return;
      pushTo(j.to, { event: "typing", peerId: userId });
    }
  });
  socket.on("close", () => { const set = online.get(userId); if (!set) return;
    set.delete(socket); if (!set.size) online.delete(userId); touchSeen(userId); });
});
app.addHook("onRequest", async (req, reply) => { reply.header("X-Request-Id", req.id); });
app.get("/health", { config: { rateLimit: false } }, async (req, reply) => {
  try { await pool.query("SELECT 1"); } catch { return reply.code(503).send({ ok: false, app: "naslife", db: false }); }
  return { ok: true, db: true, app: "naslife", v: 13, features: ["sessions", "ws-auth", "media-guard", "vessel-access", "districts", "businesses", "feed", "map", "profiles", "vessels", "stories", "profile", "avatars", "presence", "typing", "delete", "recovery-phrase", "ratelimit", "blocks", "reports", "requests", "chats", "receipts", "hardened", "media", VAPID_PUBLIC ? "push" : "push-disabled", "admin-audit", "account-delete", "export"] };
});
// Loopback only: the public entry point is the reverse proxy on 443. Set HOST=0.0.0.0 explicitly to expose it.
export { app, pool };
if (process.env.NASLIFE_NO_LISTEN !== "1") await app.listen({ port: Number(process.env.PORT ?? 4000), host: process.env.HOST ?? "127.0.0.1" });
