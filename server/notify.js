// إضافة Fastify للإشعارات في Naslife: إشعارات داخل التطبيق (جدول app_notifications) وإشعارات دفع بالمتصفح (Web Push).
// الدفع يستخدم مفتاح VAPID واشتراكات خادم Naslife الأساسي نفسها (تُكتشف تلقائياً من البيئة/الملفات/قاعدة البيانات
// ويُتحقق منها بمطابقة المفتاح العام الذي يعيده /push/key)، فلا حاجة لإعادة اشتراك المستخدمين.
// بقية الإضافات ترسل عبر globalThis.naslifeNotify(ids, {kind,title,body,data}) وglobalThis.naslifeNotifyAdmins(...).
// التسجيل في src/index.js قبل بقية الإضافات:
//   await app.register((await import("./notify.js")).default, { pool, auth });
import crypto from "node:crypto";
import fs from "node:fs";
import http from "node:http";
import https from "node:https";
import path from "node:path";

const UUID_RE = /^[0-9a-f-]{36}$/i;
const ID_RE = /^[A-Z]{2}\d{7}$/;
const q = (ident) => `"${String(ident).replace(/"/g, '""')}"`;
const str = (v, max = 200) => String(v ?? "").trim().slice(0, max);
const b64u = (buf) => Buffer.from(buf).toString("base64url");
const unb64u = (s) => Buffer.from(String(s ?? "").trim().replace(/=+$/, ""), "base64url");
const hkdf = (salt, ikm, info, len) => Buffer.from(crypto.hkdfSync("sha256", ikm, salt, info, len));

/// تشفير حمولة Web Push وفق RFC 8291 (aes128gcm) بمفتاح المتصفح p256dh وسرّ auth.
export function encryptPush(payload, p256dh, auth) {
  const ua = unb64u(p256dh), secret = unb64u(auth);
  if (ua.length !== 65 || secret.length !== 16) throw new Error("bad-subscription-keys");
  const ecdh = crypto.createECDH("prime256v1"); const asPub = ecdh.generateKeys();
  const shared = ecdh.computeSecret(ua);
  const salt = crypto.randomBytes(16);
  const ikm = hkdf(secret, shared, Buffer.concat([Buffer.from("WebPush: info\0"), ua, asPub]), 32);
  const cek = hkdf(salt, ikm, Buffer.from("Content-Encoding: aes128gcm\0"), 16);
  const nonce = hkdf(salt, ikm, Buffer.from("Content-Encoding: nonce\0"), 12);
  const cipher = crypto.createCipheriv("aes-128-gcm", cek, nonce);
  const body = Buffer.concat([cipher.update(Buffer.concat([Buffer.from(payload), Buffer.from([2])])), cipher.final(), cipher.getAuthTag()]);
  const rs = Buffer.alloc(4); rs.writeUInt32BE(4096);
  return Buffer.concat([salt, rs, Buffer.from([asPub.length]), asPub, body]);
}

/// ترويسة VAPID (JWT موقّع ES256) لخدمة الدفع التي يتبعها الـ endpoint.
export function vapidAuthorization(endpoint, priv, pub, subject) {
  const enc = (o) => b64u(Buffer.from(JSON.stringify(o)));
  const unsigned = enc({ typ: "JWT", alg: "ES256" }) + "." + enc({ aud: new URL(endpoint).origin, exp: Math.floor(Date.now() / 1000) + 12 * 3600, sub: subject });
  const key = crypto.createPrivateKey({ format: "jwk", key: { kty: "EC", crv: "P-256", d: b64u(priv), x: b64u(pub.subarray(1, 33)), y: b64u(pub.subarray(33, 65)) } });
  const sig = crypto.sign("sha256", Buffer.from(unsigned), { key, dsaEncoding: "ieee-p1363" });
  return `vapid t=${unsigned}.${b64u(sig)}, k=${b64u(pub)}`;
}

const pubFromPriv = (d) => { try { if (d.length !== 32) return null; const e = crypto.createECDH("prime256v1"); e.setPrivateKey(d); return e.getPublicKey(); } catch { return null; } };
/// كل الصيغ المحتملة لمفتاح خاص: base64url خام (43 حرفاً)، hex، PEM، JWK، أو كائن يحويها.
function privCandidates(v, depth = 0) {
  const out = [];
  if (v == null || depth > 4) return out;
  if (typeof v === "object") { for (const x of Object.values(v)) out.push(...privCandidates(x, depth + 1)); return out; }
  const s = String(v).trim();
  if (!s) return out;
  if (s.startsWith("-----BEGIN")) { try { const j = crypto.createPrivateKey(s).export({ format: "jwk" }); if (j.d) out.push(unb64u(j.d)); } catch { /* ليس مفتاحاً */ } return out; }
  if (s.startsWith("{")) { try { return privCandidates(JSON.parse(s), depth + 1); } catch { return out; } }
  if (/^[A-Za-z0-9_-]{43}=?$/.test(s)) out.push(unb64u(s));
  else if (/^[0-9a-fA-F]{64}$/.test(s)) out.push(Buffer.from(s, "hex"));
  return out;
}

export default async function notify(app, opts) {
  const { pool, auth } = opts;
  if (!pool || !auth) throw new Error("notify: pool and auth are required");
  const OPS = opts.opsDir ?? process.env.NASLIFE_OPS_DIR ?? "/opt/naslife/ops";
  const POLL_MS = opts.pollMs ?? Number(process.env.NASLIFE_NOTIFY_POLL_MS || 60000);
  const SUBJECT = process.env.VAPID_SUBJECT ?? process.env.VAPID_EMAIL ?? process.env.VAPID_MAILTO ?? "mailto:admin@naslife.app";
  const log = (level, obj, msg) => { try { app.log[level](obj, msg); } catch { console[level === "error" ? "error" : "log"](msg, obj); } };

  await pool.query(`
    CREATE TABLE IF NOT EXISTS app_notifications (
      id UUID PRIMARY KEY, user_id TEXT NOT NULL, kind TEXT NOT NULL, title TEXT NOT NULL, body TEXT NOT NULL DEFAULT '',
      data JSONB NOT NULL DEFAULT '{}', read_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE INDEX IF NOT EXISTS app_notifications_user ON app_notifications(user_id, created_at DESC);
    CREATE INDEX IF NOT EXISTS app_notifications_unread ON app_notifications(user_id) WHERE read_at IS NULL;
    CREATE TABLE IF NOT EXISTS notify_state (key TEXT PRIMARY KEY, value JSONB NOT NULL, updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE TABLE IF NOT EXISTS admins (user_id TEXT PRIMARY KEY, granted_by TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
  `);

  // ---- اكتشاف جداول الخادم الأساسي: المستخدمون (أعمدة المدير)، البلاغات، اشتراكات الدفع
  const cols = (await pool.query("SELECT table_name, column_name, data_type FROM information_schema.columns WHERE table_schema='public' ORDER BY ordinal_position")).rows;
  const tables = new Map();
  for (const c of cols) { if (!tables.has(c.table_name)) tables.set(c.table_name, new Map()); tables.get(c.table_name).set(c.column_name, c.data_type); }
  const pick = (m, ...names) => names.find((n) => m?.has(n)) ?? null;
  const userCols = tables.get("users") ?? new Map();
  const U = { ok: userCols.has("id"), admin: pick(userCols, "is_admin"), role: pick(userCols, "role"), nick: pick(userCols, "nickname", "name", "handle", "username") };
  const reportsTable = [...tables.keys()].find((t) => /report/.test(t) && t !== "report_actions") ?? null;
  const RC = { created: pick(tables.get(reportsTable), "created_at", "createdat"), reporter: pick(tables.get(reportsTable), "reporter_id", "from_id", "user_id", "by_id"), target: pick(tables.get(reportsTable), "target_id", "reported_id", "user_id_reported", "to_id", "subject_id"), reason: pick(tables.get(reportsTable), "reason", "type", "category") };
  let S = null;   // جدول الاشتراكات
  for (const [t, m] of tables) {
    if (!m.has("endpoint")) continue;
    const user = pick(m, "user_id", "userid", "uid", "owner_id", "user");
    if (!user) continue;
    const json = [...m].find(([n, ty]) => /json/.test(ty) && /^(keys|subscription|sub|data|json|payload)$/.test(n))?.[0] ?? [...m].find(([, ty]) => /json/.test(ty))?.[0] ?? pick(m, "keys", "subscription", "sub", "data");
    S = { table: t, user, p256dh: pick(m, "p256dh", "p256dh_key", "key_p256dh"), auth: pick(m, "auth", "auth_key", "key_auth", "auth_secret"), json };
    break;
  }

  const unauthorized = (reply) => reply.code(401).send({ error: "auth" });
  const bad = (reply, code, error, extra = {}) => reply.code(code).send({ error, ...extra });
  const parseJson = (v) => { if (v == null) return null; if (typeof v === "object") return v; try { return JSON.parse(v); } catch { return null; } };

  // ---- مفتاح VAPID: يُبحث عنه في البيئة والملفات وقاعدة البيانات، ويُقبل فقط ما يطابق المفتاح العام المعلن في /push/key
  const push = { ready: false, ok: false, reason: "pending", source: null, publicKey: null, priv: null, pub: null, sent: 0, failed: 0, pruned: 0, lastError: null };
  async function livePublicKey() {
    if (opts.publicKey) return opts.publicKey;
    const parse = (body) => { try { const j = JSON.parse(body); return str(j.key ?? j.publicKey ?? j.vapidPublicKey, 200) || null; } catch { return null; } };
    try { const r = await app.inject({ method: "GET", url: "/push/key" }); if (r.statusCode === 200) return parse(r.body); } catch { /* نجرب المنفذ الحقيقي */ }
    const addr = (() => { try { return app.server?.address?.(); } catch { return null; } })();
    const port = addr && typeof addr === "object" ? addr.port : Number(process.env.PORT || 0);
    if (!port) return null;
    return new Promise((resolve) => {
      const rq = http.request({ host: "127.0.0.1", port, path: "/push/key", method: "GET", timeout: 4000 }, (res) => { let d = ""; res.on("data", (c) => d += c); res.on("end", () => resolve(res.statusCode === 200 ? parse(d) : null)); });
      rq.on("error", () => resolve(null)); rq.on("timeout", () => rq.destroy()); rq.end();
    });
  }
  async function findPrivate(publicKey) {
    const want = unb64u(publicKey);
    const matches = (cands, source) => { for (const d of cands) { const p = pubFromPriv(d); if (p && p.equals(want)) return { priv: d, pub: p, source }; } return null; };
    if (opts.privateKey) { const m = matches(privCandidates(opts.privateKey), "opts"); if (m) return m; }
    // البيئة: أي متغير يذكر vapid/push
    for (const [k, v] of Object.entries(process.env)) if (/vapid|web_?push|push_?(priv|key|secret)/i.test(k)) { const m = matches(privCandidates(v), "env:" + k); if (m) return m; }
    // ملفات شائعة بجوار التطبيق
    const roots = [OPS, process.cwd(), path.dirname(process.argv[1] ?? ""), "/opt/naslife", "/opt/naslife/src", "/opt/naslife/data", "/opt/naslife/config", "/etc/naslife", "/var/lib/naslife"];
    const names = ["vapid.json", "vapid-keys.json", "push-keys.json", "push.json", "keys.json", ".vapid.json", "vapid.pem", "vapid-private.pem", "vapid.key", ".env", ".env.production", "config.json", "secrets.json"];
    for (const r of roots) for (const n of names) {
      const f = path.join(r, n); let txt; try { txt = fs.readFileSync(f, "utf8"); } catch { continue; }
      if (txt.length > 200000) continue;
      const cands = n.startsWith(".env") ? txt.split(/\r?\n/).map((l) => l.replace(/^\s*(export\s+)?[A-Za-z0-9_]+\s*=\s*/, "").replace(/^["']|["']$/g, "")).flatMap((v) => privCandidates(v)) : privCandidates(txt);
      const m = matches(cands, "file:" + f); if (m) return m;
    }
    // قاعدة البيانات: جداول تبدو حاوية للمفاتيح/الإعدادات
    for (const [t] of tables) {
      if (!/vapid|push|key|secret|setting|config|kv|meta|option/i.test(t) || t === S?.table || t === "notify_state" || t === "platform_settings") continue;
      let rows; try { rows = (await pool.query(`SELECT * FROM ${q(t)} LIMIT 50`)).rows; } catch { continue; }
      const m = matches(rows.flatMap((r) => privCandidates(r)), "db:" + t); if (m) return m;
    }
    return null;
  }
  async function discover() {
    try {
      const publicKey = await livePublicKey();
      push.publicKey = publicKey;
      if (!publicKey) { Object.assign(push, { ready: true, ok: false, reason: "no-public-key" }); return; }
      const m = await findPrivate(publicKey);
      if (!m) { Object.assign(push, { ready: true, ok: false, reason: S ? "private-key-not-found" : "private-key-and-subscriptions-not-found" }); return; }
      Object.assign(push, { ready: true, ok: !!S, reason: S ? "ok" : "subscriptions-table-not-found", priv: m.priv, pub: m.pub, source: m.source });
      log("info", { source: m.source, table: S?.table }, "notify: web push " + (S ? "ready" : "without subscriptions table"));
    } catch (e) { Object.assign(push, { ready: true, ok: false, reason: "discover-failed: " + (e?.message || e) }); }
  }
  app.addHook("onReady", async () => { setTimeout(() => { discover().catch(() => {}); }, opts.discoverDelayMs ?? 300).unref?.(); });

  async function subsFor(userId) {
    if (!S) return [];
    let rows; try { rows = (await pool.query(`SELECT * FROM ${q(S.table)} WHERE ${q(S.user)}::text=$1`, [userId])).rows; } catch { return []; }
    return rows.map((r) => {
      let endpoint = r.endpoint, p256dh = S.p256dh ? r[S.p256dh] : null, a = S.auth ? r[S.auth] : null;
      if ((!p256dh || !a) && S.json) { const j = parseJson(r[S.json]); const k = j?.keys ?? j; p256dh ||= k?.p256dh; a ||= k?.auth; endpoint ||= j?.endpoint; }
      return endpoint && p256dh && a ? { endpoint, p256dh, auth: a } : null;
    }).filter(Boolean);
  }
  function postPush(endpoint, body, authorization) {
    return new Promise((resolve) => {
      let u; try { u = new URL(endpoint); } catch { return resolve({ status: 0, body: "bad-endpoint" }); }
      const mod = u.protocol === "http:" ? http : https;
      const rq = mod.request({ host: u.hostname, port: u.port || (u.protocol === "http:" ? 80 : 443), path: u.pathname + u.search, method: "POST", timeout: 10000,
        headers: { Authorization: authorization, "Content-Type": "application/octet-stream", "Content-Encoding": "aes128gcm", TTL: "86400", Urgency: "normal", "Content-Length": body.length } },
        (res) => { let d = ""; res.on("data", (c) => d += c); res.on("end", () => resolve({ status: res.statusCode ?? 0, body: d.slice(0, 200) })); });
      rq.on("error", (e) => resolve({ status: 0, body: e.message })); rq.on("timeout", () => rq.destroy(new Error("timeout")));
      rq.end(body);
    });
  }
  /// يرسل حمولة إلى كل اشتراكات المستخدم؛ الاشتراكات المنتهية (404/410) تُحذف. يعيد عدد الإرسالات الناجحة.
  async function sendPush(userId, payload) {
    if (!push.ok) return 0;
    let n = 0;
    for (const s of await subsFor(userId)) {
      try {
        const body = encryptPush(JSON.stringify(payload), s.p256dh, s.auth);
        const r = await postPush(s.endpoint, body, vapidAuthorization(s.endpoint, push.priv, push.pub, SUBJECT));
        if (r.status >= 200 && r.status < 300) { n++; push.sent++; }
        else if (r.status === 404 || r.status === 410) { push.pruned++; try { await pool.query(`DELETE FROM ${q(S.table)} WHERE endpoint=$1`, [s.endpoint]); } catch { /* ignore */ } }
        else { push.failed++; push.lastError = `${r.status} ${r.body}`.slice(0, 200); }
      } catch (e) { push.failed++; push.lastError = String(e?.message || e).slice(0, 200); }
    }
    return n;
  }

  // ---- الإرسال: صف لكل مستقبل + دفع للمتصفح (لا ينتظر)
  const out = (r) => ({ id: r.id, kind: r.kind, title: r.title, body: r.body, data: r.data ?? {}, url: `/#/n/${r.id}`, readAt: r.read_at, createdAt: r.created_at });
  async function send(ids, { kind, title, body = "", data = {}, exclude = null, push: doPush = true } = {}) {
    const list = [...new Set((Array.isArray(ids) ? ids : [ids]).map((x) => str(x, 12).toUpperCase()).filter((x) => ID_RE.test(x) && x !== exclude))];
    if (!list.length || !kind || !title) return [];
    const made = [];
    for (const uid of list) {
      const id = crypto.randomUUID();
      await pool.query("INSERT INTO app_notifications(id,user_id,kind,title,body,data) VALUES($1,$2,$3,$4,$5,$6)", [id, uid, str(kind, 40), str(title, 120), str(body, 400), JSON.stringify(data ?? {})]);
      made.push(id);
      if (doPush) sendPush(uid, { title: str(title, 120), body: str(body, 400), url: `/#/n/${id}`, tag: str(kind, 40) }).catch(() => {});
    }
    return made;
  }
  async function adminIds() {
    const ids = new Set((await pool.query("SELECT user_id FROM admins")).rows.map((r) => r.user_id));
    if (U.ok && (U.admin || U.role)) {
      const conds = [U.admin ? `${q(U.admin)}=true` : null, U.role ? `${q(U.role)}='admin'` : null].filter(Boolean).join(" OR ");
      try { for (const r of (await pool.query(`SELECT id FROM users WHERE ${conds}`)).rows) ids.add(r.id); } catch { /* ignore */ }
    }
    return [...ids];
  }
  const sendAdmins = async (payload) => send(await adminIds(), payload);
  globalThis.naslifeNotify = send;
  globalThis.naslifeNotifyAdmins = sendAdmins;
  globalThis.naslifeNotifyPushStatus = () => ({ ...push, priv: undefined, pub: undefined });

  // ---- مراقبة البلاغات الجديدة في جدول الخادم الأساسي (لا نملك مساره) وإبلاغ المديرين
  let timer = null;
  if (reportsTable && RC.created && POLL_MS > 0) {
    const key = "reports.seen";
    let since = null;
    // آخر وقت مُعالج يُحفظ نصاً كما يعيده Postgres (بالميكروثانية)؛ تحويله إلى Date يفقد الدقة فيتكرر البلاغ نفسه
    const load = async () => {
      const r = (await pool.query("SELECT value FROM notify_state WHERE key=$1", [key])).rows[0];
      since = r ? String(r.value.at) : (await pool.query("SELECT now()::text AS t")).rows[0].t;
      if (!r) await pool.query("INSERT INTO notify_state(key,value) VALUES($1,$2) ON CONFLICT DO NOTHING", [key, JSON.stringify({ at: since })]);
    };
    const tick = async () => {
      try {
        if (!since) await load();
        const r = (await pool.query(`SELECT count(*)::int AS n, max(${q(RC.created)})::text AS last FROM ${q(reportsTable)} WHERE ${q(RC.created)} > $1::timestamptz`, [since])).rows[0];
        if (!r.n) return;
        since = String(r.last);
        await pool.query("INSERT INTO notify_state(key,value,updated_at) VALUES($1,$2,now()) ON CONFLICT (key) DO UPDATE SET value=EXCLUDED.value, updated_at=now()", [key, JSON.stringify({ at: since })]);
        await sendAdmins({ kind: "report_new", title: r.n === 1 ? "بلاغ جديد" : `${r.n} بلاغات جديدة`, body: "افتح قسم البلاغات في لوحة الإدارة للمراجعة", data: { count: r.n } });
      } catch (e) { log("warn", { err: e?.message }, "notify: reports poll failed"); }
    };
    timer = setInterval(tick, POLL_MS); timer.unref?.();
    app.addHook("onClose", async () => { if (timer) clearInterval(timer); });
    globalThis.naslifeNotifyPollReports = tick;
  }

  // ---- المسارات
  app.get("/notify/status", async () => ({
    ok: true, push: { ready: push.ready, ok: push.ok, reason: push.reason, source: push.source ? push.source.replace(/:.*/, "") : null, subscriptions: S ? { table: S.table, keys: S.p256dh ? "columns" : S.json ? "json:" + S.json : "none" } : null, sent: push.sent, failed: push.failed, pruned: push.pruned, lastError: push.lastError },
    reports: { table: reportsTable, polling: !!timer, everyMs: timer ? POLL_MS : 0 },
  }));
  app.get("/notify", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const limit = Math.max(1, Math.min(100, Number(req.query?.limit) || 50));
    const before = req.query?.before && !isNaN(new Date(req.query.before)) ? new Date(req.query.before) : null;
    const rows = (await pool.query("SELECT * FROM app_notifications WHERE user_id=$1 AND ($2::timestamptz IS NULL OR created_at < $2) ORDER BY created_at DESC LIMIT $3", [uid, before, limit])).rows;
    const unread = (await pool.query("SELECT count(*)::int AS n FROM app_notifications WHERE user_id=$1 AND read_at IS NULL", [uid])).rows[0].n;
    return { items: rows.map(out), unread };
  });
  app.get("/notify/unread", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    return { unread: (await pool.query("SELECT count(*)::int AS n FROM app_notifications WHERE user_id=$1 AND read_at IS NULL", [uid])).rows[0].n };
  });
  app.post("/notify/read", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const ids = Array.isArray(req.body?.ids) ? req.body.ids.filter((x) => UUID_RE.test(String(x))).slice(0, 200) : [];
    if (req.body?.all === true) await pool.query("UPDATE app_notifications SET read_at=now() WHERE user_id=$1 AND read_at IS NULL", [uid]);
    else if (ids.length) await pool.query("UPDATE app_notifications SET read_at=now() WHERE user_id=$1 AND read_at IS NULL AND id = ANY($2::uuid[])", [uid, ids]);
    else return bad(reply, 400, "bad-request");
    return { ok: true, unread: (await pool.query("SELECT count(*)::int AS n FROM app_notifications WHERE user_id=$1 AND read_at IS NULL", [uid])).rows[0].n };
  });
  app.post("/notify/test", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    const [id] = await send(uid, { kind: "test", title: "إشعار تجريبي", body: "الإشعارات تعمل في هذا المتصفح", data: {}, push: false });
    const pushed = await sendPush(uid, { title: "إشعار تجريبي", body: "الإشعارات تعمل في هذا المتصفح", url: `/#/n/${id}`, tag: "test" });
    return { ok: true, id, pushed, push: push.ok, reason: push.reason, subscriptions: (await subsFor(uid)).length };
  });
  app.get("/notify/:id", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const r = (await pool.query("SELECT * FROM app_notifications WHERE id=$1 AND user_id=$2", [req.params.id, uid])).rows[0];
    if (!r) return bad(reply, 404, "not-found");
    return out(r);
  });
  app.delete("/notify/:id", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if (!UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    await pool.query("DELETE FROM app_notifications WHERE id=$1 AND user_id=$2", [req.params.id, uid]);
    return { ok: true };
  });
}
