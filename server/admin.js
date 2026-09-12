// إضافة Fastify للوحة إدارة Naslife: المديرون وأول إعداد، نظرة عامة، المستخدمون والأرصدة والإيقاف،
// البلاغات، الدوائر التجارية وطلبات الملكية، المالية والتصدير، المحتوى، الإعدادات، سجل الإجراءات،
// وتقديم واجهة الإدارة على /admin (والنطاق الفرعي admin.* عبر إعادة توجيه Caddy إلى /admin).
// التسجيل في src/index.js بعد بقية الإضافات:
//   await app.register((await import("./admin.js")).default, { pool, auth });
// واجهة الإدارة نفسها هي تطبيق Naslife (Flutter) الذي يفتح في وضع الإدارة عند المسار /admin أو المضيف admin.*.
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const ID_RE = /^[A-Z]{2}\d{7}$/;
const UUID_RE = /^[0-9a-f-]{36}$/i;
const SLUG_RE = /^[a-z0-9-]{3,60}$/;
const q = (ident) => `"${String(ident).replace(/"/g, '""')}"`;
const str = (v, max = 200) => String(v ?? "").trim().slice(0, max);

export default async function admin(app, opts) {
  const { pool, auth } = opts;
  if (!pool || !auth) throw new Error("admin: pool and auth are required");
  const WEBAPP = opts.webappDir ?? process.env.NASLIFE_WEBAPP_DIR ?? "/opt/naslife/webapp";
  const OPS = opts.opsDir ?? process.env.NASLIFE_OPS_DIR ?? "/opt/naslife/ops";

  await pool.query(`
    CREATE TABLE IF NOT EXISTS admins (user_id TEXT PRIMARY KEY, granted_by TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE TABLE IF NOT EXISTS admin_audit (id UUID PRIMARY KEY, admin_id TEXT NOT NULL, action TEXT NOT NULL, target TEXT, details JSONB NOT NULL DEFAULT '{}', created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE INDEX IF NOT EXISTS admin_audit_time ON admin_audit(created_at DESC);
    CREATE TABLE IF NOT EXISTS user_flags (user_id TEXT PRIMARY KEY, suspended BOOLEAN NOT NULL DEFAULT false, note TEXT NOT NULL DEFAULT '', updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE TABLE IF NOT EXISTS platform_settings (key TEXT PRIMARY KEY, value JSONB NOT NULL, updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE TABLE IF NOT EXISTS admin_setup (code TEXT PRIMARY KEY, used_by TEXT, used_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE TABLE IF NOT EXISTS report_actions (report_id TEXT PRIMARY KEY, action TEXT NOT NULL, note TEXT NOT NULL DEFAULT '', admin_id TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE TABLE IF NOT EXISTS wallet_accounts (user_id TEXT PRIMARY KEY, balance BIGINT NOT NULL DEFAULT 0, points INT NOT NULL DEFAULT 0, updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE TABLE IF NOT EXISTS wallet_tx (id UUID PRIMARY KEY, user_id TEXT NOT NULL, kind TEXT NOT NULL, amount BIGINT NOT NULL, peer_id TEXT, ref TEXT, note TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
  `);

  // ---- اكتشاف أعمدة جداول الخادم الأساسي (ليست في المستودع) حتى لا نفترض أسماءً غير موجودة
  const tables = new Set((await pool.query("SELECT table_name FROM information_schema.tables WHERE table_schema='public'")).rows.map((r) => r.table_name));
  const colsOf = async (t) => new Set((await pool.query("SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name=$1", [t])).rows.map((r) => r.column_name));
  const pick = (set, ...names) => names.find((n) => set.has(n)) ?? null;
  const userCols = tables.has("users") ? await colsOf("users") : new Set();
  const U = {
    ok: tables.has("users") && userCols.has("id"),
    nick: pick(userCols, "nickname", "name", "handle", "username"), avatar: pick(userCols, "avatar_url", "avatarurl", "avatar"),
    created: pick(userCols, "created_at", "createdat", "joined_at", "registered_at"), admin: pick(userCols, "is_admin"), role: pick(userCols, "role"),
    deleted: pick(userCols, "deleted_at"), bio: pick(userCols, "bio"), seen: pick(userCols, "last_seen_at", "last_seen", "last_active_at", "updated_at"),
  };
  const reportsTable = [...tables].find((t) => /report/.test(t) && t !== "report_actions") ?? null;
  const R = reportsTable ? await colsOf(reportsTable) : new Set();
  const RC = { id: pick(R, "id"), reporter: pick(R, "reporter_id", "from_id", "user_id", "by_id"), target: pick(R, "target_id", "reported_id", "user_id_reported", "to_id", "subject_id"), reason: pick(R, "reason", "type", "category"), text: pick(R, "text", "details", "note", "message"), created: pick(R, "created_at", "createdat") };
  const blocksTable = [...tables].find((t) => /block/.test(t)) ?? null;
  const eventsOk = tables.has("events"), marketOk = tables.has("market_listings"), bizOk = tables.has("biz"), vesselsTable = [...tables].find((t) => /^vessels$/.test(t)) ?? null;

  const unauthorized = (reply) => reply.code(401).send({ error: "auth" });
  const bad = (reply, code, error, extra = {}) => reply.code(code).send({ error, ...extra });
  const userRow = async (id) => { try { return (await pool.query("SELECT * FROM users WHERE id=$1", [id])).rows[0] ?? null; } catch { return null; } };
  const personOf = (u, id) => ({ id: u?.id ?? id, nickname: u ? (U.nick ? u[U.nick] ?? "" : "") : "", avatarUrl: u && U.avatar ? u[U.avatar] ?? null : null });
  const person = async (id) => personOf(await userRow(id), id);
  // الإشعارات (server/notify.js إن كانت مسجّلة): لا تُفشل الطلب أبداً
  const notify = async (ids, payload) => { try { await globalThis.naslifeNotify?.(ids, payload); } catch { /* ignore */ } };
  const sar = (h) => { const v = Number(h) / 100; return (Number.isInteger(v) ? String(v) : v.toFixed(2)) + " ر.س"; };

  // ---- المديرون: عمود في جدول المستخدمين إن وُجد، أو جدول admins الخاص بنا
  const isAdmin = async (uid) => {
    if (!uid) return false;
    const u = await userRow(uid);
    if (u && ((U.admin && u[U.admin] === true) || (U.role && u[U.role] === "admin"))) return true;
    return (await pool.query("SELECT 1 FROM admins WHERE user_id=$1", [uid])).rowCount > 0;
  };
  const adminCount = async () => {
    let n = (await pool.query("SELECT count(*)::int AS n FROM admins")).rows[0].n;
    if (U.ok && (U.admin || U.role)) {
      const conds = [U.admin ? `${q(U.admin)}=true` : null, U.role ? `${q(U.role)}='admin'` : null].filter(Boolean).join(" OR ");
      try { n += (await pool.query(`SELECT count(*)::int AS n FROM users WHERE ${conds}`)).rows[0].n; } catch { /* ignore */ }
    }
    return n;
  };
  globalThis.naslifeIsAdmin = isAdmin;

  // ---- أول مدير: من NASLIFE_ADMIN_IDS، أو برمز إعداد يُكتب في مجلد التشغيل ويُطبع في السجل عند غياب أي مدير
  for (const id of String(process.env.NASLIFE_ADMIN_IDS ?? "").split(",").map((s) => s.trim().toUpperCase()).filter((s) => ID_RE.test(s))) {
    await pool.query("INSERT INTO admins(user_id, granted_by) VALUES($1,'env') ON CONFLICT DO NOTHING", [id]);
  }
  let setupCode = null;
  async function ensureSetupCode() {
    if ((await adminCount()) > 0) { setupCode = null; return; }
    const row = (await pool.query("SELECT code FROM admin_setup WHERE used_at IS NULL ORDER BY created_at DESC LIMIT 1")).rows[0];
    setupCode = row?.code ?? ("NL-" + crypto.randomBytes(3).toString("hex").toUpperCase() + "-" + crypto.randomBytes(3).toString("hex").toUpperCase());
    if (!row) await pool.query("INSERT INTO admin_setup(code) VALUES($1)", [setupCode]);
    try { fs.mkdirSync(OPS, { recursive: true }); fs.writeFileSync(path.join(OPS, "admin-setup-code"), setupCode + "\n", { mode: 0o600 }); } catch { /* ignore */ }
    const msg = `NASLIFE ADMIN SETUP CODE: ${setupCode} (افتح /admin وأدخل الرمز ليصبح حسابك أول مدير)`;
    try { app.log.warn(msg); } catch { /* ignore */ }
    console.log(msg);
  }
  await ensureSetupCode();

  // ---- الإعدادات الحية: تُطبَّق على العملية نفسها (الشحن التجريبي وسقفه) وتُقرأ من الإضافات الأخرى
  const DEFAULT_SETTINGS = { testTopup: process.env.WALLET_TEST_TOPUP === "1", maxTopup: 10000000, announcement: "", maintenance: false, supportHandle: "" };
  async function loadSettings() {
    const rows = (await pool.query("SELECT key, value FROM platform_settings")).rows;
    const s = { ...DEFAULT_SETTINGS };
    for (const r of rows) s[r.key] = r.value;
    process.env.WALLET_TEST_TOPUP = s.testTopup ? "1" : "0";
    globalThis.naslifeSettings = s;
    return s;
  }
  await loadSettings();
  async function saveSettings(patch) {
    for (const [k, v] of Object.entries(patch)) await pool.query("INSERT INTO platform_settings(key,value,updated_at) VALUES($1,$2,now()) ON CONFLICT (key) DO UPDATE SET value=EXCLUDED.value, updated_at=now()", [k, JSON.stringify(v)]);
    return loadSettings();
  }
  app.get("/settings/public", async () => { const s = globalThis.naslifeSettings ?? DEFAULT_SETTINGS; return { announcement: s.announcement ?? "", maintenance: s.maintenance === true, supportHandle: s.supportHandle ?? "", testTopup: s.testTopup === true }; });

  const audit = async (adminId, action, target, details = {}) => { try { await pool.query("INSERT INTO admin_audit(id,admin_id,action,target,details) VALUES($1,$2,$3,$4,$5)", [crypto.randomUUID(), adminId, action, target, JSON.stringify(details)]); } catch { /* ignore */ } };
  async function ledger(client, userId, kind, amount, { peerId = null, ref = null, note = null, allowNegative = false } = {}) {
    await client.query("INSERT INTO wallet_accounts(user_id) VALUES($1) ON CONFLICT DO NOTHING", [userId]);
    const acc = (await client.query("SELECT balance FROM wallet_accounts WHERE user_id=$1 FOR UPDATE", [userId])).rows[0];
    if (!allowNegative && Number(acc.balance) + amount < 0) throw Object.assign(new Error("insufficient"), { code: "insufficient-funds" });
    await client.query("UPDATE wallet_accounts SET balance=balance+$2, updated_at=now() WHERE user_id=$1", [userId, amount]);
    await client.query("INSERT INTO wallet_tx(id,user_id,kind,amount,peer_id,ref,note) VALUES($1,$2,$3,$4,$5,$6,$7)", [crypto.randomUUID(), userId, kind, amount, peerId, ref, note]);
  }
  async function tx(fn) {
    const c = await pool.connect();
    try { await c.query("BEGIN"); const out = await fn(c); await c.query("COMMIT"); return out; }
    catch (e) { await c.query("ROLLBACK").catch(() => {}); throw e; }
    finally { c.release(); }
  }
  /// حارس مسارات الإدارة
  async function guard(req, reply) {
    const uid = await auth(req); if (!uid) { unauthorized(reply); return null; }
    if (!(await isAdmin(uid))) { bad(reply, 403, "admin-only"); return null; }
    return uid;
  }

  // ---- تقديم واجهة الإدارة: /admin و/admin/* وأي طلب HTML على مضيف admin.*
  let indexCache = { at: 0, html: null };
  async function indexHtml() {
    const now = Date.now();
    if (indexCache.html && now - indexCache.at < 5000) return indexCache.html;
    try { indexCache = { at: now, html: await fs.promises.readFile(path.join(WEBAPP, "index.html"), "utf8") }; } catch { return null; }
    return indexCache.html;
  }
  const serveIndex = async (req, reply) => {
    const html = await indexHtml();
    if (!html) return reply.code(503).type("text/plain").send("admin UI not deployed yet");
    return reply.type("text/html; charset=utf-8").header("cache-control", "no-cache").send(html);
  };
  app.get("/admin", serveIndex);
  app.get("/admin/*", serveIndex);
  // النطاق الفرعي admin.*: يُعاد توجيه جذره إلى /admin من Caddy (انظر server/install-admin-subdomain.sh)
  // لأن الخطافات داخل إضافة معزولة لا تصل إلى مسار / المسجّل في الخادم الأساسي.

  // ---- الحالة والإعداد الأول
  app.get("/adminapi/status", async (req) => {
    const uid = (await auth(req).catch(() => null)) || null;
    const n = await adminCount();
    return { hasAdmin: n > 0, setupRequired: n === 0, isAdmin: uid ? await isAdmin(uid) : false, user: uid ? await person(uid) : null, admins: n, version: 1 };
  });
  app.post("/adminapi/setup", async (req, reply) => {
    const uid = await auth(req); if (!uid) return unauthorized(reply);
    if ((await adminCount()) > 0) return bad(reply, 409, "already-set-up");
    const code = str(req.body?.code, 40).toUpperCase().replace(/\s+/g, "");
    const row = (await pool.query("SELECT code FROM admin_setup WHERE used_at IS NULL AND code=$1", [code])).rows[0];
    if (!row) return bad(reply, 400, "bad-code");
    await tx(async (c) => {
      await c.query("UPDATE admin_setup SET used_by=$2, used_at=now() WHERE code=$1", [code, uid]);
      await c.query("INSERT INTO admins(user_id, granted_by) VALUES($1,'setup') ON CONFLICT DO NOTHING", [uid]);
    });
    setupCode = null;
    await audit(uid, "setup.first-admin", uid, {});
    return { ok: true };
  });

  // ---- نظرة عامة
  app.get("/adminapi/overview", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    const days = 14;
    const users = { total: 0, new7: 0, active7: null };
    if (U.ok) {
      const where = U.deleted ? `WHERE ${q(U.deleted)} IS NULL` : "";
      users.total = (await pool.query(`SELECT count(*)::int AS n FROM users ${where}`)).rows[0].n;
      if (U.created) users.new7 = (await pool.query(`SELECT count(*)::int AS n FROM users WHERE ${q(U.created)} >= now() - interval '7 days'`)).rows[0].n;
      if (U.seen) users.active7 = (await pool.query(`SELECT count(*)::int AS n FROM users WHERE ${q(U.seen)} >= now() - interval '7 days'`)).rows[0].n;
    }
    const orders7 = (await pool.query(`SELECT
        (SELECT count(*) FROM biz_orders WHERE status IN ('confirmed','used') AND created_at >= now() - interval '7 days')::int AS biz,
        (SELECT COALESCE(SUM(total),0) FROM biz_orders WHERE status IN ('confirmed','used') AND created_at >= now() - interval '7 days')::bigint AS biz_rev,
        ${marketOk ? "(SELECT count(*) FROM market_orders WHERE status<>'cancelled' AND created_at >= now() - interval '7 days')::int" : "0"} AS market,
        ${marketOk ? "(SELECT COALESCE(SUM(total),0) FROM market_orders WHERE status<>'cancelled' AND created_at >= now() - interval '7 days')::bigint" : "0"} AS market_rev,
        ${eventsOk ? "(SELECT count(*) FROM tickets WHERE status<>'refunded' AND created_at >= now() - interval '7 days')::int" : "0"} AS tickets,
        ${eventsOk ? "(SELECT COALESCE(SUM(paid),0) FROM tickets WHERE status<>'refunded' AND created_at >= now() - interval '7 days')::bigint" : "0"} AS tickets_rev`)).rows[0];
    const circles = bizOk ? (await pool.query("SELECT count(*) FILTER (WHERE active)::int AS active, count(*) FILTER (WHERE NOT active)::int AS inactive, count(*) FILTER (WHERE owner_id IS NOT NULL)::int AS owned, (SELECT count(*) FROM biz_claims WHERE status='pending')::int AS claims FROM biz")).rows[0] : { active: 0, inactive: 0, owned: 0, claims: 0 };
    let reports = { open: 0, total: 0, available: !!reportsTable };
    if (reportsTable && RC.id) {
      const r = (await pool.query(`SELECT count(*)::int AS total, count(*) FILTER (WHERE a.report_id IS NULL)::int AS open FROM ${q(reportsTable)} r LEFT JOIN report_actions a ON a.report_id = r.${q(RC.id)}::text`)).rows[0];
      reports = { ...reports, ...r };
    }
    const wallets = (await pool.query("SELECT count(*)::int AS accounts, COALESCE(SUM(balance),0)::bigint AS balance FROM wallet_accounts")).rows[0];
    const daily = (await pool.query(`SELECT d::date AS day,
        ${U.ok && U.created ? `(SELECT count(*) FROM users u WHERE (u.${q(U.created)} + interval '3 hours')::date = d::date)::int` : "0"} AS users,
        (SELECT count(*) FROM biz_orders o WHERE o.status IN ('confirmed','used') AND (o.created_at + interval '3 hours')::date = d::date)::int
          + ${marketOk ? "(SELECT count(*) FROM market_orders m WHERE m.status<>'cancelled' AND (m.created_at + interval '3 hours')::date = d::date)::int" : "0"}
          + ${eventsOk ? "(SELECT count(*) FROM tickets t WHERE t.status<>'refunded' AND (t.created_at + interval '3 hours')::date = d::date)::int" : "0"} AS orders,
        (SELECT COALESCE(SUM(total),0) FROM biz_orders o WHERE o.status IN ('confirmed','used') AND (o.created_at + interval '3 hours')::date = d::date)::bigint
          + ${marketOk ? "(SELECT COALESCE(SUM(total),0) FROM market_orders m WHERE m.status<>'cancelled' AND (m.created_at + interval '3 hours')::date = d::date)::bigint" : "0"}
          + ${eventsOk ? "(SELECT COALESCE(SUM(paid),0) FROM tickets t WHERE t.status<>'refunded' AND (t.created_at + interval '3 hours')::date = d::date)::bigint" : "0"} AS revenue
      FROM generate_series((now() + interval '3 hours')::date - ${days - 1}, (now() + interval '3 hours')::date, '1 day') AS d ORDER BY d`)).rows;
    const suspended = (await pool.query("SELECT count(*)::int AS n FROM user_flags WHERE suspended")).rows[0].n;
    return {
      users: { ...users, suspended, admins: await adminCount() },
      orders7: { count: orders7.biz + orders7.market + orders7.tickets, revenue: Number(orders7.biz_rev) + Number(orders7.market_rev) + Number(orders7.tickets_rev), biz: orders7.biz, market: orders7.market, tickets: orders7.tickets },
      circles, reports, wallets: { accounts: wallets.accounts, balance: Number(wallets.balance) },
      daily: daily.map((d) => ({ day: new Date(d.day).toISOString().slice(0, 10), users: d.users, orders: d.orders, revenue: Number(d.revenue) })),
      server: { node: process.version, uptimeSec: Math.round(process.uptime()), testTopup: process.env.WALLET_TEST_TOPUP === "1", reportsTable, blocksTable, usersColumns: [...userCols].length, tables: [...tables].filter((t) => /^(biz|market|events|tickets|wallet|vessels|users|messages)/.test(t)) },
    };
  });

  // ---- المستخدمون
  const userOut = async (u, { flags = null, balance = null, admin = null } = {}) => ({
    ...personOf(u, u.id), bio: U.bio ? u[U.bio] ?? "" : "", createdAt: U.created ? u[U.created] : null, lastSeen: U.seen ? u[U.seen] : null, deleted: U.deleted ? !!u[U.deleted] : false,
    isAdmin: admin ?? (await isAdmin(u.id)), suspended: flags?.suspended === true, flagNote: flags?.note ?? "", balance: balance == null ? null : Number(balance),
  });
  app.get("/adminapi/users", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    if (!U.ok) return [];
    const term = str(req.query?.q, 60);
    const limit = Math.max(1, Math.min(200, Number(req.query?.limit) || 50));
    const filter = req.query?.filter; // suspended | admins | recent
    const order = U.created ? `ORDER BY u.${q(U.created)} DESC NULLS LAST` : "ORDER BY u.id";
    const where = [];
    const params = [];
    if (term) { params.push(`%${term}%`); where.push(`(u.id ILIKE $${params.length}${U.nick ? ` OR u.${q(U.nick)} ILIKE $${params.length}` : ""})`); }
    if (filter === "suspended") where.push("f.suspended = true");
    if (filter === "admins") where.push("(a.user_id IS NOT NULL" + (U.admin ? ` OR u.${q(U.admin)}=true` : "") + (U.role ? ` OR u.${q(U.role)}='admin'` : "") + ")");
    const sql = `SELECT u.*, f.suspended, f.note AS flag_note, w.balance, (a.user_id IS NOT NULL) AS in_admins FROM users u
      LEFT JOIN user_flags f ON f.user_id=u.id LEFT JOIN wallet_accounts w ON w.user_id=u.id LEFT JOIN admins a ON a.user_id=u.id
      ${where.length ? "WHERE " + where.join(" AND ") : ""} ${order} LIMIT ${limit}`;
    const rows = (await pool.query(sql, params)).rows;
    return Promise.all(rows.map((u) => userOut(u, { flags: { suspended: u.suspended, note: u.flag_note }, balance: u.balance ?? 0, admin: u.in_admins || (U.admin && u[U.admin] === true) || (U.role && u[U.role] === "admin") })));
  });
  app.get("/adminapi/users/:id", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    const id = str(req.params.id, 12).toUpperCase();
    if (!ID_RE.test(id)) return bad(reply, 400, "bad-id");
    const u = await userRow(id);
    if (!u) return bad(reply, 404, "not-found");
    const flags = (await pool.query("SELECT * FROM user_flags WHERE user_id=$1", [id])).rows[0] ?? null;
    const w = (await pool.query("SELECT balance, points FROM wallet_accounts WHERE user_id=$1", [id])).rows[0];
    const txs = (await pool.query("SELECT * FROM wallet_tx WHERE user_id=$1 ORDER BY created_at DESC LIMIT 30", [id])).rows;
    const orders = (await pool.query("SELECT count(*)::int AS n, COALESCE(SUM(total),0)::bigint AS total FROM biz_orders WHERE user_id=$1 AND status IN ('confirmed','used')", [id])).rows[0];
    const circles = bizOk ? (await pool.query("SELECT id, name, name_ar, category, active FROM biz WHERE owner_id=$1 ORDER BY created_at DESC", [id])).rows.map((b) => ({ id: b.id, name: b.name_ar || b.name, category: b.category, active: b.active })) : [];
    let reportsAbout = [];
    if (reportsTable && RC.target) reportsAbout = (await pool.query(`SELECT * FROM ${q(reportsTable)} WHERE ${q(RC.target)}::text=$1 ORDER BY ${RC.created ? q(RC.created) : "1"} DESC LIMIT 20`, [id])).rows.map(reportOut);
    const actions = (await pool.query("SELECT * FROM admin_audit WHERE target=$1 ORDER BY created_at DESC LIMIT 20", [id])).rows.map(auditOut);
    return { user: await userOut(u, { flags, balance: w?.balance ?? 0 }), points: w?.points ?? 0, transactions: txs.map(txOut), orders: { count: orders.n, total: Number(orders.total) }, circles, reportsAbout, actions };
  });
  const txOut = (x) => ({ id: x.id, kind: x.kind, amount: Number(x.amount), peerId: x.peer_id, ref: x.ref, note: x.note, createdAt: x.created_at, userId: x.user_id });
  const auditOut = (a) => ({ id: a.id, adminId: a.admin_id, action: a.action, target: a.target, details: a.details ?? {}, createdAt: a.created_at });
  app.post("/adminapi/users/:id/credit", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    const id = str(req.params.id, 12).toUpperCase();
    const amount = Math.round(Number(req.body?.amount) || 0); const note = str(req.body?.note, 120);
    if (!ID_RE.test(id)) return bad(reply, 400, "bad-id");
    if (amount === 0 || Math.abs(amount) > 100000000) return bad(reply, 400, "bad-amount");
    if (!(await userRow(id)) && !U.ok) { /* بلا جدول مستخدمين: نسمح بالقيد على المعرّف مباشرة */ }
    else if (!(await userRow(id))) return bad(reply, 404, "not-found");
    try { await tx((c) => ledger(c, id, amount > 0 ? "credit" : "debit", amount, { note: note || (amount > 0 ? "إضافة رصيد من الإدارة" : "خصم من الإدارة"), peerId: uid, allowNegative: false })); }
    catch (e) { if (e.code === "insufficient-funds") return bad(reply, 402, "insufficient-funds"); throw e; }
    await audit(uid, amount > 0 ? "wallet.credit" : "wallet.debit", id, { amount, note });
    await notify(id, { kind: "wallet_credit", title: amount > 0 ? "أُضيف رصيد إلى محفظتك" : "خُصم من محفظتك", body: `${sar(Math.abs(amount))}${note ? " · " + note : ""}`, data: { amount } });
    const w = (await pool.query("SELECT balance FROM wallet_accounts WHERE user_id=$1", [id])).rows[0];
    return { ok: true, balance: Number(w?.balance ?? 0) };
  });
  app.post("/adminapi/users/:id/suspend", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    const id = str(req.params.id, 12).toUpperCase();
    if (!ID_RE.test(id)) return bad(reply, 400, "bad-id");
    if (id === uid) return bad(reply, 400, "self");
    const suspended = req.body?.suspended !== false; const note = str(req.body?.note, 200);
    await pool.query("INSERT INTO user_flags(user_id,suspended,note,updated_at) VALUES($1,$2,$3,now()) ON CONFLICT (user_id) DO UPDATE SET suspended=EXCLUDED.suspended, note=EXCLUDED.note, updated_at=now()", [id, suspended, note]);
    await audit(uid, suspended ? "user.suspend" : "user.unsuspend", id, { note });
    await notify(id, { kind: suspended ? "account_suspended" : "account_restored", title: suspended ? "أُوقف حسابك" : "أُعيد تفعيل حسابك", body: suspended ? (note || "تواصل مع الدعم للمراجعة") : "يمكنك الشراء والحجز والتحويل من جديد", data: {} });
    return { ok: true, suspended };
  });
  app.post("/adminapi/users/:id/admin", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    const id = str(req.params.id, 12).toUpperCase();
    if (!ID_RE.test(id)) return bad(reply, 400, "bad-id");
    const grant = req.body?.grant !== false;
    if (!grant && id === uid && (await adminCount()) <= 1) return bad(reply, 409, "last-admin");
    if (grant) {
      if (U.ok && !(await userRow(id))) return bad(reply, 404, "not-found");
      await pool.query("INSERT INTO admins(user_id, granted_by) VALUES($1,$2) ON CONFLICT DO NOTHING", [id, uid]);
    } else {
      await pool.query("DELETE FROM admins WHERE user_id=$1", [id]);
    }
    await audit(uid, grant ? "admin.grant" : "admin.revoke", id, {});
    if (grant) await notify(id, { kind: "admin_granted", title: "أصبحت مديراً في ناس لايف", body: "تجد لوحة الإدارة في ماي سبيس وعلى naslife.app/admin", data: {}, exclude: uid });
    return { ok: true };
  });

  // ---- البلاغات (جدول الخادم الأساسي إن وُجد) وإجراءاتها
  const reportOut = (r) => ({
    id: RC.id ? String(r[RC.id]) : null, reporterId: RC.reporter ? r[RC.reporter] : null, targetId: RC.target ? r[RC.target] : null,
    reason: RC.reason ? r[RC.reason] : null, text: RC.text ? r[RC.text] : null, createdAt: RC.created ? r[RC.created] : null, raw: r,
  });
  app.get("/adminapi/reports", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    if (!reportsTable || !RC.id) return { available: false, table: null, items: [], blocks: null };
    const status = req.query?.status === "all" ? "all" : "open";
    const rows = (await pool.query(`SELECT r.*, a.action AS admin_action, a.note AS admin_note, a.admin_id AS action_by, a.created_at AS action_at FROM ${q(reportsTable)} r
      LEFT JOIN report_actions a ON a.report_id = r.${q(RC.id)}::text ${status === "open" ? "WHERE a.report_id IS NULL" : ""} ORDER BY ${RC.created ? "r." + q(RC.created) : "1"} DESC LIMIT 200`)).rows;
    const items = await Promise.all(rows.map(async (r) => ({ ...reportOut(r), reporter: RC.reporter ? await person(r[RC.reporter]) : null, target: RC.target ? await person(r[RC.target]) : null, action: r.admin_action ? { action: r.admin_action, note: r.admin_note, by: r.action_by, at: r.action_at } : null })));
    let blocks = null;
    if (blocksTable) { try { blocks = (await pool.query(`SELECT count(*)::int AS n FROM ${q(blocksTable)}`)).rows[0].n; } catch { blocks = null; } }
    return { available: true, table: reportsTable, items, blocks };
  });
  app.post("/adminapi/reports/:id/action", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    const id = str(req.params.id, 60); const action = ["ignore", "warn", "suspend"].includes(req.body?.action) ? req.body.action : null; const note = str(req.body?.note, 300);
    if (!id || !action) return bad(reply, 400, "bad-request");
    const targetId = ID_RE.test(String(req.body?.targetId ?? "").toUpperCase()) ? String(req.body.targetId).toUpperCase() : null;
    await pool.query("INSERT INTO report_actions(report_id,action,note,admin_id) VALUES($1,$2,$3,$4) ON CONFLICT (report_id) DO UPDATE SET action=EXCLUDED.action, note=EXCLUDED.note, admin_id=EXCLUDED.admin_id, created_at=now()", [id, action, note, uid]);
    if (action === "suspend" && targetId && targetId !== uid) await pool.query("INSERT INTO user_flags(user_id,suspended,note,updated_at) VALUES($1,true,$2,now()) ON CONFLICT (user_id) DO UPDATE SET suspended=true, note=EXCLUDED.note, updated_at=now()", [targetId, note || "بلاغ"]);
    await audit(uid, `report.${action}`, targetId ?? id, { reportId: id, note });
    if (targetId && targetId !== uid && action !== "ignore") await notify(targetId, { kind: action === "warn" ? "account_warning" : "account_suspended", title: action === "warn" ? "تنبيه من الإدارة" : "أُوقف حسابك",
      body: note || (action === "warn" ? "وردنا بلاغ عن حسابك؛ يرجى الالتزام بقواعد المجتمع" : "تواصل مع الدعم للمراجعة"), data: { reportId: id } });
    return { ok: true };
  });

  // ---- الدوائر التجارية وطلبات الملكية
  app.get("/adminapi/biz", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    if (!bizOk) return [];
    const rows = (await pool.query(`SELECT b.*, (SELECT count(*) FROM biz_orders o WHERE o.biz_id=b.id AND o.status IN ('confirmed','used'))::int AS orders,
      (SELECT COALESCE(SUM(total),0) FROM biz_orders o WHERE o.biz_id=b.id AND o.status IN ('confirmed','used'))::bigint AS revenue,
      (SELECT count(*) FROM biz_follows f WHERE f.biz_id=b.id)::int AS followers, (SELECT count(*) FROM biz_items i WHERE i.biz_id=b.id AND i.active)::int AS items
      FROM biz b ORDER BY b.active DESC, b.category, b.sort, b.name`)).rows;
    return Promise.all(rows.map(async (b) => ({ id: b.id, name: b.name_ar || b.name, latin: b.name, category: b.category, sector: b.sector, active: b.active, verified: b.verified, ownerId: b.owner_id, owner: b.owner_id ? await person(b.owner_id) : null, orders: b.orders, revenue: Number(b.revenue), followers: b.followers, items: b.items, views: Number(b.views ?? 0), createdAt: b.created_at })));
  });
  app.post("/adminapi/biz/:id", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    if (!SLUG_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const sets = []; const params = [req.params.id]; const details = {};
    if (req.body?.verified !== undefined) { params.push(req.body.verified === true); sets.push(`verified=$${params.length}`); details.verified = req.body.verified === true; }
    if (req.body?.active !== undefined) { params.push(req.body.active !== false); sets.push(`active=$${params.length}`); details.active = req.body.active !== false; }
    if (req.body?.ownerId !== undefined) { const o = req.body.ownerId ? String(req.body.ownerId).toUpperCase() : null; if (o && !ID_RE.test(o)) return bad(reply, 400, "bad-owner"); params.push(o); sets.push(`owner_id=$${params.length}`); details.ownerId = o; }
    if (!sets.length) return bad(reply, 400, "nothing-to-update");
    const r = await pool.query(`UPDATE biz SET ${sets.join(", ")}, updated_at=now() WHERE id=$1 RETURNING id`, params);
    if (!r.rowCount) return bad(reply, 404, "not-found");
    await audit(uid, "biz.update", req.params.id, details);
    return { ok: true };
  });
  app.get("/adminapi/claims", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    if (!bizOk) return [];
    const r = await pool.query("SELECT c.*, b.name, b.name_ar FROM biz_claims c JOIN biz b ON b.id=c.biz_id WHERE c.status='pending' ORDER BY c.created_at");
    return Promise.all(r.rows.map(async (c) => ({ bizId: c.biz_id, name: c.name_ar || c.name, user: await person(c.user_id), note: c.note, createdAt: c.created_at })));
  });
  app.post("/adminapi/claims/:bizId/:userId/:decision", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    const { bizId, userId, decision } = req.params;
    if (!SLUG_RE.test(bizId) || !ID_RE.test(userId) || !["approve", "reject"].includes(decision)) return bad(reply, 400, "bad-request");
    const ok = await tx(async (c) => {
      const r = await c.query("UPDATE biz_claims SET status=$3 WHERE biz_id=$1 AND user_id=$2 AND status='pending' RETURNING 1", [bizId, userId, decision === "approve" ? "approved" : "rejected"]);
      if (!r.rowCount) return false;
      if (decision === "approve") {
        await c.query("UPDATE biz SET owner_id=$2, updated_at=now() WHERE id=$1 AND owner_id IS NULL", [bizId, userId]);
        await c.query("UPDATE biz_claims SET status='rejected' WHERE biz_id=$1 AND user_id<>$2 AND status='pending'", [bizId, userId]);
      }
      return true;
    });
    if (!ok) return bad(reply, 404, "not-found");
    await audit(uid, `claim.${decision}`, bizId, { userId });
    const bz = (await pool.query("SELECT name_ar, name FROM biz WHERE id=$1", [bizId])).rows[0]; const nm = bz?.name_ar || bz?.name || bizId;
    await notify(userId, { kind: "claim_decided", title: decision === "approve" ? "قُبل طلب الملكية" : "رُفض طلب الملكية", body: decision === "approve" ? `أصبحت مالك ${nm}؛ افتح لوحة النشاط لإدارتها` : `لم يُقبل طلبك لملكية ${nm}`, data: { bizId, approved: decision === "approve" } });
    return { ok: true };
  });

  // ---- المالية
  app.get("/adminapi/finance", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    const days = Math.max(7, Math.min(90, Number(req.query?.days) || 14));
    const totals = (await pool.query("SELECT count(*)::int AS accounts, COALESCE(SUM(balance),0)::bigint AS balance, COALESCE(SUM(points),0)::bigint AS points FROM wallet_accounts")).rows[0];
    const byKind = (await pool.query(`SELECT kind, count(*)::int AS count, COALESCE(SUM(amount),0)::bigint AS amount FROM wallet_tx WHERE created_at >= now() - interval '${days} days' GROUP BY kind ORDER BY abs(SUM(amount)) DESC`)).rows;
    const daily = (await pool.query(`SELECT d::date AS day,
        COALESCE((SELECT SUM(amount) FROM wallet_tx t WHERE t.amount > 0 AND t.kind IN ('topup','credit') AND (t.created_at + interval '3 hours')::date = d::date),0)::bigint AS topups,
        COALESCE((SELECT SUM(-amount) FROM wallet_tx t WHERE t.amount < 0 AND t.kind IN ('biz','market','ticket') AND (t.created_at + interval '3 hours')::date = d::date),0)::bigint AS purchases,
        COALESCE((SELECT SUM(amount) FROM wallet_tx t WHERE t.kind IN ('refund','biz_refund') AND (t.created_at + interval '3 hours')::date = d::date),0)::bigint AS refunds
      FROM generate_series((now() + interval '3 hours')::date - ${days - 1}, (now() + interval '3 hours')::date, '1 day') AS d ORDER BY d`)).rows;
    const recent = (await pool.query("SELECT * FROM wallet_tx ORDER BY created_at DESC LIMIT 50")).rows.map(txOut);
    const top = (await pool.query("SELECT user_id, balance FROM wallet_accounts ORDER BY balance DESC LIMIT 10")).rows;
    return {
      totals: { accounts: totals.accounts, balance: Number(totals.balance), points: Number(totals.points) },
      byKind: byKind.map((k) => ({ kind: k.kind, count: k.count, amount: Number(k.amount) })),
      daily: daily.map((d) => ({ day: new Date(d.day).toISOString().slice(0, 10), topups: Number(d.topups), purchases: Number(d.purchases), refunds: Number(d.refunds) })),
      recent: await Promise.all(recent.map(async (t) => ({ ...t, user: await person(t.userId) }))),
      topBalances: await Promise.all(top.map(async (t) => ({ user: await person(t.user_id), balance: Number(t.balance) }))),
    };
  });
  app.get("/adminapi/finance/export.csv", async (req, reply) => {
    // رابط التنزيل لا يحمل ترويسات؛ نقبل الرمز من الاستعلام ونمرّره بالطريقتين الشائعتين
    const t = str(req.query?.token, 500);
    if (t) { req.headers["x-token"] = req.headers["x-token"] || t; req.headers.authorization = req.headers.authorization || `Bearer ${t}`; }
    const uid = await guard(req, reply); if (!uid) return;
    const days = Math.max(1, Math.min(365, Number(req.query?.days) || 30));
    const user = ID_RE.test(String(req.query?.user ?? "").toUpperCase()) ? String(req.query.user).toUpperCase() : null;
    const rows = (await pool.query(`SELECT * FROM wallet_tx WHERE created_at >= now() - interval '${days} days' AND ($1::text IS NULL OR user_id=$1) ORDER BY created_at DESC LIMIT 20000`, [user])).rows;
    const esc = (v) => `"${String(v ?? "").replace(/"/g, '""')}"`;
    const csv = ["﻿id,user_id,kind,amount_sar,peer_id,ref,note,created_at", ...rows.map((r) => [r.id, r.user_id, r.kind, (Number(r.amount) / 100).toFixed(2), r.peer_id, r.ref, r.note, new Date(r.created_at).toISOString()].map(esc).join(","))].join("\n");
    await audit(uid, "finance.export", user ?? "all", { days, rows: rows.length });
    return reply.type("text/csv; charset=utf-8").header("content-disposition", `attachment; filename="naslife-wallet-${days}d.csv"`).send(csv);
  });

  // ---- المحتوى: الفعاليات والسوق والدوائر الاجتماعية
  app.get("/adminapi/content", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    const events = eventsOk ? (await pool.query("SELECT e.*, (SELECT count(*) FROM tickets t WHERE t.event_id=e.id AND t.status<>'refunded')::int AS sold FROM events e ORDER BY e.starts_at DESC LIMIT 100")).rows : [];
    const listings = marketOk ? (await pool.query("SELECT * FROM market_listings WHERE status<>'hidden' ORDER BY created_at DESC LIMIT 100")).rows : [];
    let vessels = [];
    if (vesselsTable) { try { vessels = (await pool.query(`SELECT * FROM ${q(vesselsTable)} ORDER BY 1 DESC LIMIT 100`)).rows; } catch { vessels = []; } }
    return {
      events: await Promise.all(events.map(async (e) => ({ id: e.id, title: e.title, host: await person(e.host_id), startsAt: e.starts_at, placeName: e.place_name, cancelled: e.cancelled, sold: e.sold }))),
      listings: await Promise.all(listings.map(async (l) => ({ id: l.id, title: l.title, seller: await person(l.seller_id), price: Number(l.price), category: l.category, status: l.status, createdAt: l.created_at }))),
      vessels: vessels.map((v) => ({ id: v.id, name: v.name ?? v.title ?? "", kind: v.kind ?? "", members: v.members ?? v.member_count ?? null, isPublic: v.is_public ?? v.ispublic ?? null })),
    };
  });
  app.post("/adminapi/events/:id/cancel", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    if (!eventsOk || !UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    const ev = (await pool.query("SELECT * FROM events WHERE id=$1", [req.params.id])).rows[0];
    if (!ev) return bad(reply, 404, "not-found");
    if (ev.cancelled) return bad(reply, 409, "already-cancelled");
    const holders = await tx(async (c) => {
      await c.query("UPDATE events SET cancelled=true WHERE id=$1", [ev.id]);
      const ts = (await c.query("UPDATE tickets SET status='refunded' WHERE event_id=$1 AND status='valid' RETURNING user_id, paid", [ev.id])).rows;
      for (const t of ts) if (Number(t.paid) > 0) {
        await ledger(c, t.user_id, "refund", Number(t.paid), { peerId: ev.host_id, ref: ev.id, note: ev.title });
        await ledger(c, ev.host_id, "refund_out", -Number(t.paid), { peerId: t.user_id, ref: ev.id, note: ev.title, allowNegative: true });
      }
      return ts;
    });
    await audit(uid, "event.cancel", ev.id, { title: ev.title });
    const refunded = new Map();
    for (const t of holders) refunded.set(t.user_id, (refunded.get(t.user_id) ?? 0) + Number(t.paid));
    for (const [u, paid] of refunded) await notify(u, { kind: "event_cancelled", title: "أُلغيت الفعالية", body: `${ev.title} · ألغتها الإدارة${paid > 0 ? " واستُرد " + sar(paid) + " إلى محفظتك" : ""}`, data: { eventId: ev.id } });
    await notify(ev.host_id, { kind: "event_cancelled", title: "ألغت الإدارة فعاليتك", body: `${ev.title}: أُعيدت مبالغ التذاكر إلى المشترين`, data: { eventId: ev.id }, exclude: uid });
    return { ok: true };
  });
  app.post("/adminapi/market/:id/hide", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    if (!marketOk || !UUID_RE.test(req.params.id)) return bad(reply, 400, "bad-id");
    // blocked: أخفته الإدارة ولا يستطيع صاحبه إظهاره (بخلاف hidden الذي يخفيه صاحبه بنفسه)
    const hidden = req.body?.hidden !== false;
    const r = await pool.query("UPDATE market_listings SET status=$2 WHERE id=$1 RETURNING title, seller_id", [req.params.id, hidden ? "blocked" : "active"]);
    if (!r.rowCount) return bad(reply, 404, "not-found");
    await audit(uid, hidden ? "market.hide" : "market.unhide", req.params.id, { title: r.rows[0].title });
    if (hidden) await notify(r.rows[0].seller_id, { kind: "listing_hidden", title: "أُخفي إعلانك", body: `${r.rows[0].title}: أخفته الإدارة من السوق`, data: { listingId: req.params.id }, exclude: uid });
    return { ok: true, status: hidden ? "blocked" : "active" };
  });

  // ---- الإعدادات وسجل الإجراءات
  app.get("/adminapi/settings", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    return { ...(await loadSettings()), setupCodePresent: !!setupCode, opsDir: OPS, webappDir: WEBAPP };
  });
  app.post("/adminapi/settings", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    const b = req.body ?? {}; const patch = {};
    if (b.testTopup !== undefined) patch.testTopup = b.testTopup === true;
    if (b.maxTopup !== undefined) patch.maxTopup = Math.max(100, Math.min(1000000000, Math.round(Number(b.maxTopup) || 0)));
    if (b.announcement !== undefined) patch.announcement = str(b.announcement, 300);
    if (b.maintenance !== undefined) patch.maintenance = b.maintenance === true;
    if (b.supportHandle !== undefined) patch.supportHandle = str(b.supportHandle, 40);
    const s = await saveSettings(patch);
    await audit(uid, "settings.update", "platform", patch);
    return s;
  });
  app.get("/adminapi/audit", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    const limit = Math.max(1, Math.min(500, Number(req.query?.limit) || 100));
    const rows = (await pool.query("SELECT * FROM admin_audit ORDER BY created_at DESC LIMIT $1", [limit])).rows;
    return Promise.all(rows.map(async (a) => ({ ...auditOut(a), admin: await person(a.admin_id) })));
  });
  app.get("/adminapi/admins", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    const rows = (await pool.query("SELECT * FROM admins ORDER BY created_at")).rows;
    return Promise.all(rows.map(async (a) => ({ user: await person(a.user_id), grantedBy: a.granted_by, since: a.created_at })));
  });
}
