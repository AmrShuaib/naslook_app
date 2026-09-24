// حذف الحساب ذاتياً من داخل التطبيق (شرط متاجر التطبيقات): حذف ناعم يمحو البيانات الشخصية ويخفي المحتوى فوراً
// ويحتفظ بالسجلات المالية (المحفظة، المدفوعات، الطلبات، التذاكر) مرتبطة بمعرّف لم يعد يدل على صاحبه،
// حتى لا تنكسر سجلات الأطراف الأخرى ولا الالتزامات النظامية.
// المسارات:
//   GET  /me/account/delete/preview                  ما يمنع الحذف الآن، وما سيُحذف وما يُحفظ، ورصيد المحفظة
//   POST /me/account/delete {password, confirm, refund?, reason?}
//        confirm يجب أن تكون «حذف»؛ كلمة السر تُتحقق عبر /login في النواة. رصيد موجب يتطلب refund:true (يُسترد خلال 30 يوماً).
//   GET  /adminapi/deletions ، POST /adminapi/deletions/:id/complete {refundRef}   متابعة الاستردادات المعلّقة (للمديرين)
// الخطوات: فحص الموانع → التحقق من كلمة السر → معاملة واحدة تُخفي المحتوى وتمسح البيانات الشخصية وتغيّر اسم المستخدم
// إلى deleted_xxxx وتوقف الحساب → بعدها تدوير كلمة السر في النواة بعبارة الاسترداد المحفوظة (إن وُجدت) ثم حذف الجلسات.
// الأسماء المحذوفة محجوزة 90 يوماً (globalThis.naslifeNickReserved) حتى لا ينتحلها أحد، والمحتوى المخفي يُمسح بعد 30 يوماً.
// جداول النواة (users، الملف، sessions، الاشتراكات، جهات الاتصال، الحظر) تُكتشف بأسماء أعمدتها كما في admin.js.
// التسجيل في register.txt: await app.register((await import("./account_delete.js")).default, { pool, auth });
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { decrypt } from "./auth_alias.js";

const CONFIRM_WORD = "حذف";
const PLATFORM = "SA0000000";
const ID_RE = /^[A-Z]{2}\d{7}$/;
const RESERVE_DAYS = 90, PURGE_DAYS = 30;
const q = (n) => `"${String(n).replace(/"/g, '""')}"`;

/// مفتاح تشفير عبارات الاسترداد نفسه الذي تستخدمه auth_alias.js (لا يُنشأ هنا أبداً: إن غاب فلا تدوير).
function readKey(opsDir) {
  const env = String(process.env.NASLIFE_AUTH_KEY ?? "").trim();
  if (/^[0-9a-f]{64}$/i.test(env)) return Buffer.from(env, "hex");
  try { const t = fs.readFileSync(path.join(opsDir, "auth-key"), "utf8").trim(); if (/^[0-9a-f]{64}$/i.test(t)) return Buffer.from(t, "hex"); } catch { /* لا مفتاح */ }
  return null;
}
const nickHash = (key, nick) => crypto.createHmac("sha256", key ?? Buffer.from("naslife")).update(String(nick ?? "").trim().toLowerCase()).digest("hex");

export default async function accountDelete(app, opts = {}) {
  const pool = opts.pool ?? globalThis.naslifePool ?? null;
  const auth = opts.auth ?? globalThis.naslifeAuth ?? null;
  if (!pool) throw new Error("account_delete: pool is required");
  const opsDir = opts.opsDir ?? process.env.NASLIFE_OPS_DIR ?? "/opt/naslife/ops";
  // المفتاح نفسه الذي تستخدمه auth_alias.js (يُقرأ عند الطلب لأن ترتيب التحميل قد يتغير)، ثم الملف احتياطاً
  const keyOf = () => { try { const k = globalThis.naslifeAuthKey?.(); if (k) return k; } catch { /* ignore */ } return readKey(opsDir); };

  await pool.query(`CREATE TABLE IF NOT EXISTS account_deletions (user_id TEXT PRIMARY KEY, status TEXT NOT NULL DEFAULT 'done', by_id TEXT NOT NULL,
      nick_hash TEXT, reason TEXT NOT NULL DEFAULT '', balance BIGINT NOT NULL DEFAULT 0, report JSONB NOT NULL DEFAULT '{}',
      refund_ref TEXT, reserved_until TIMESTAMPTZ, purge_after TIMESTAMPTZ, purged_at TIMESTAMPTZ,
      requested_at TIMESTAMPTZ NOT NULL DEFAULT now(), completed_at TIMESTAMPTZ);
    CREATE INDEX IF NOT EXISTS account_deletions_nick ON account_deletions(nick_hash)`);

  // ---- اكتشاف الجداول والأعمدة (تُعاد عند كل طلب حذف: الجداول قد تُنشأ من إضافات تُحمَّل بعدنا)
  const schema = async () => {
    const rows = (await pool.query("SELECT table_name, column_name FROM information_schema.columns WHERE table_schema='public'")).rows;
    const t = new Map();
    for (const r of rows) { if (!t.has(r.table_name)) t.set(r.table_name, new Set()); t.get(r.table_name).add(r.column_name); }
    return t;
  };
  const pick = (set, ...names) => (set ? names.find((n) => set.has(n)) ?? null : null);

  const bad = (reply, code, error, extra = {}) => reply.code(code).send({ error, ...extra });
  const me = async (req, reply) => { const uid = auth ? await auth(req) : null; if (!uid) { bad(reply, 401, "auth"); return null; } return uid; };
  const ipOf = (req) => String(req.headers["x-forwarded-for"] ?? req.ip ?? "").split(",")[0].trim();
  const hits = new Map();
  const limited = (k, max, win) => { const now = Date.now(); const a = (hits.get(k) ?? []).filter((x) => now - x < win); a.push(now); hits.set(k, a); return a.length > max; };
  const count = async (sql, params) => { try { return (await pool.query(sql, params)).rows[0]?.n ?? 0; } catch { return 0; } };
  const core = (req, url, payload) => app.inject({ method: "POST", url, headers: { "content-type": "application/json", "x-forwarded-for": ipOf(req) }, payload: JSON.stringify(payload) });

  /// ما يمنع الحذف الآن: التزامات مفتوحة تجاه آخرين أو رصيد لم يُحسم.
  async function blockersOf(uid, T, { refund = false } = {}) {
    const has = (t) => T.has(t);
    const out = [], warn = [];
    const add = (arr, code, n) => { if (n > 0) arr.push({ code, count: n }); };
    if (uid === PLATFORM) out.push({ code: "platform-account", count: 1 });
    if (has("market_orders")) {
      add(out, "open-orders", await count("SELECT count(*)::int AS n FROM market_orders WHERE (buyer_id=$1 OR seller_id=$1) AND status IN ('paid','preparing','on_the_way','delivered','disputed')", [uid]));
      if (T.get("market_orders").has("courier_id")) add(out, "courier-orders", await count("SELECT count(*)::int AS n FROM market_orders WHERE courier_id=$1 AND status IN ('paid','preparing','on_the_way')", [uid]));
    }
    if (has("events") && has("tickets")) add(out, "hosted-events", await count("SELECT count(*)::int AS n FROM events e WHERE e.host_id=$1 AND NOT e.cancelled AND e.starts_at > now() AND EXISTS (SELECT 1 FROM tickets t WHERE t.event_id=e.id AND t.status='valid')", [uid]));
    if (has("biz_orders")) {
      add(out, "bookings", await count("SELECT count(*)::int AS n FROM biz_orders WHERE user_id=$1 AND status='confirmed' AND start_at > now()", [uid]));
      if (has("biz")) add(out, "circle-bookings", await count("SELECT count(*)::int AS n FROM biz_orders o JOIN biz b ON b.id=o.biz_id WHERE b.owner_id=$1 AND o.status='confirmed' AND (o.start_at IS NULL OR o.start_at > now())", [uid]));
    }
    if (has("payments")) add(out, "pending-payment", await count("SELECT count(*)::int AS n FROM payments WHERE user_id=$1 AND status='created' AND created_at > now() - interval '45 minutes'", [uid]));
    let balance = 0;
    if (has("wallet_accounts")) balance = Number((await pool.query("SELECT balance FROM wallet_accounts WHERE user_id=$1", [uid])).rows[0]?.balance ?? 0);
    if (balance < 0) out.push({ code: "wallet-debt", count: 1 });
    if (balance > 0 && !refund) out.push({ code: "wallet-balance", count: 1 });
    // حسابات الفريق والإدارة تُزال من الفريق أولاً حتى لا تنقطع صلاحيات أو صناديق بريد
    let staff = false;
    if (has("admins")) staff = (await count("SELECT count(*)::int AS n FROM admins WHERE user_id=$1", [uid])) > 0;
    if (!staff && has("team_members")) staff = (await count("SELECT count(*)::int AS n FROM team_members WHERE user_id=$1 AND active", [uid])) > 0;
    if (!staff && T.get("users")?.has("is_admin")) staff = (await count("SELECT count(*)::int AS n FROM users WHERE id=$1 AND is_admin", [uid])) > 0;
    if (staff) out.push({ code: "staff-account", count: 1 });
    if (has("tickets")) add(warn, "tickets", await count("SELECT count(*)::int AS n FROM tickets t JOIN events e ON e.id=t.event_id WHERE t.user_id=$1 AND t.status='valid' AND e.starts_at > now()", [uid]));
    if (has("market_listings")) add(warn, "listings", await count("SELECT count(*)::int AS n FROM market_listings WHERE seller_id=$1 AND status IN ('active','pending','scheduled')", [uid]));
    if (has("biz")) add(warn, "circles", await count("SELECT count(*)::int AS n FROM biz WHERE owner_id=$1", [uid]));
    if (has("biz_offer_grants")) add(warn, "offers", await count("SELECT count(*)::int AS n FROM biz_offer_grants WHERE user_id=$1 AND used_at IS NULL AND (expires_at IS NULL OR expires_at > now())", [uid]));
    return { blockers: out, warnings: warn, balance };
  }

  const REMOVES = ["email", "profile", "photo", "location", "posts", "listings", "community", "follows", "notifications", "sessions"];
  const KEEPS = ["financial-records", "delivered-messages", "reports"];

  app.get("/me/account/delete/preview", async (req, reply) => {
    const uid = await me(req, reply); if (!uid) return;
    const T = await schema();
    const { blockers, warnings, balance } = await blockersOf(uid, T, { refund: true });
    const balanceBlock = balance > 0 ? [{ code: "wallet-balance", count: 1 }] : [];
    const hasRecovery = T.has("account_recovery") ? (await count("SELECT count(*)::int AS n FROM account_recovery WHERE user_id=$1", [uid])) > 0 : false;
    return { canDelete: blockers.length === 0, blockers, warnings: [...balanceBlock, ...warnings], balance, confirmWord: CONFIRM_WORD, removes: REMOVES, keeps: KEEPS, hasRecovery, refundDays: 30 };
  });

  /// تنفيذ الحذف الناعم داخل معاملة واحدة؛ كل عبارة تعمل فقط إن وُجد جدولها وأعمدتها، وداخل نقطة حفظ حتى لا يُسقط فشلُ عبارة واحدة الباقي.
  async function softDelete(uid, T, { by, reason = "", refund = false, balance = 0 }) {
    const has = (t, ...cols) => T.has(t) && cols.every((c) => T.get(t).has(c));
    const U = T.get("users") ?? new Set();
    const nickCol = pick(U, "nickname", "name", "handle", "username");
    const avatarCol = pick(U, "avatar_url", "avatarurl", "avatar");
    const c = await pool.connect();
    const report = {}, errors = [];
    let oldNick = null, oldAvatar = null, emails = [];
    const newNick = "deleted_" + crypto.randomBytes(6).toString("hex");
    const run = async (label, sql, params = [uid]) => {
      await c.query("SAVEPOINT s");
      try { const r = await c.query(sql, params); report[label] = (report[label] ?? 0) + (r.rowCount ?? 0); await c.query("RELEASE SAVEPOINT s"); }
      catch (e) { await c.query("ROLLBACK TO SAVEPOINT s"); errors.push(`${label}: ${String(e?.message ?? e).slice(0, 120)}`); }
    };
    try {
      await c.query("BEGIN");
      const u = (await c.query("SELECT * FROM users WHERE id=$1 FOR UPDATE", [uid])).rows[0];
      if (!u) throw Object.assign(new Error("not-found"), { code: "not-found" });
      oldNick = nickCol ? u[nickCol] ?? null : null;
      oldAvatar = avatarCol ? u[avatarCol] ?? null : null;
      if (T.has("login_aliases")) emails = (await c.query("SELECT alias FROM login_aliases WHERE user_id=$1", [uid])).rows.map((r) => r.alias);

      // ---- صف المستخدم في النواة: اسم جديد لا يدل عليه، بلا صورة ولا نبذة، ووقت الحذف إن كان العمود موجوداً
      // تغيير الاسم شرط لازم (الدخول في النواة بالاسم): إن فشل تُلغى العملية كلها
      if (!nickCol) throw Object.assign(new Error("no-nickname-column"), { code: "schema" });
      await c.query(`UPDATE users SET ${q(nickCol)}=$2 WHERE id=$1`, [uid, newNick]);
      report.users = 1;
      // بقية الأعمدة كل واحد وحده: عمود بقيد غير متوقع لا يوقف الباقي
      if (avatarCol) await run("users.avatar", `UPDATE users SET ${q(avatarCol)}=NULL WHERE id=$1`);
      for (const col of ["display_name", "full_name", "bio", "phone", "mobile", "email", "city", "district", "birth_date", "gender", "voice_intro_url", "last_ip"]) if (U.has(col)) await run(`users.${col}`, `UPDATE users SET ${q(col)}=DEFAULT WHERE id=$1`);
      if (U.has("deleted_at")) await run("users.deleted_at", `UPDATE users SET "deleted_at"=now() WHERE id=$1`);
      if (U.has("is_public")) await run("users.is_public", `UPDATE users SET "is_public"=false WHERE id=$1`);
      // الدوائر أولاً (قبل مسح المطالبات): ما أنشأه المستخدم يُعطَّل، وما طالب بملكيته من الدوائر المبذورة يعود بلا مالك
      if (has("biz", "owner_id", "active")) {
        const claimed = has("biz_claims", "biz_id", "user_id") ? " AND NOT EXISTS (SELECT 1 FROM biz_claims c WHERE c.biz_id=biz.id AND c.user_id=$1)" : "";
        await run("biz.deactivated", `UPDATE biz SET active=false WHERE owner_id=$1${claimed}`);
        await run("biz.unowned", "UPDATE biz SET owner_id=NULL WHERE owner_id=$1");
      }
      // جدول الملف في النواة (يُكتشف بالنبذة والمهارات): يُحذف صفه كاملاً
      for (const [t, cols] of T) {
        if (t === "users") continue;
        const score = (cols.has("bio") ? 2 : 0) + (cols.has("skills") ? 2 : 0) + (/profile/.test(t) ? 3 : 0);
        if (score < 4) continue;
        const k = pick(cols, "user_id", "uid") ?? (cols.has("id") ? "id" : null);
        if (k) await run(`${t}.profile`, `DELETE FROM ${q(t)} WHERE ${q(k)}=$1`);
      }
      // ---- بيانات الدخول والاستعادة والاشتراكات والعلاقات
      if (has("login_aliases", "user_id")) await run("login_aliases", "DELETE FROM login_aliases WHERE user_id=$1");
      for (const [t, cols] of T) {
        if (cols.has("endpoint")) { const k = pick(cols, "user_id", "uid"); if (k) await run(`${t}.push`, `DELETE FROM ${q(t)} WHERE ${q(k)}=$1`); }
      }
      if (has("contacts", "user_id", "contact_id")) await run("contacts", "DELETE FROM contacts WHERE user_id=$1 OR contact_id=$1");
      for (const [t, cols] of T) {
        if (!/^(blocks|user_blocks|blocked_users)$/.test(t)) continue;
        const k = pick(cols, "blocker_id", "user_id", "uid", "by_id"); if (k) await run(`${t}.blocks`, `DELETE FROM ${q(t)} WHERE ${q(k)}=$1`);
      }
      if (has("chat_mutes", "user_id", "peer_id")) await run("chat_mutes", "DELETE FROM chat_mutes WHERE user_id=$1 OR peer_id=$1");
      if (has("chat_reactions", "user_id")) await run("chat_reactions", "DELETE FROM chat_reactions WHERE user_id=$1");
      if (has("chat_requests", "from_id", "to_id", "status")) await run("chat_requests", "UPDATE chat_requests SET status='cancelled' WHERE status='pending' AND (from_id=$1 OR to_id=$1)");
      // ---- المحتوى: يُخفى فوراً ويُمسح بعد 30 يوماً (يبقى المخالف منه للتحقيق في البلاغات)
      if (has("map_posts", "user_id", "status")) await run("map_posts", "UPDATE map_posts SET status='hidden' WHERE user_id=$1 AND status NOT IN ('blocked','hidden')");
      if (has("map_post_likes", "user_id")) await run("map_post_likes", "DELETE FROM map_post_likes WHERE user_id=$1");
      if (has("map_post_views", "user_id")) await run("map_post_views", "DELETE FROM map_post_views WHERE user_id=$1");
      if (has("map_post_events", "user_id")) await run("map_post_events", "UPDATE map_post_events SET user_id=NULL WHERE user_id=$1");
      if (has("biz_community_posts", "user_id", "hidden")) await run("community_posts", "UPDATE biz_community_posts SET hidden=true, hidden_by='account-deleted' WHERE user_id=$1 AND NOT hidden");
      if (has("biz_community_replies", "user_id", "hidden")) await run("community_replies", "UPDATE biz_community_replies SET hidden=true WHERE user_id=$1 AND NOT hidden");
      for (const t of ["biz_community_likes", "biz_community_reply_likes", "biz_community_reactions"]) if (has(t, "user_id")) await run(t, `DELETE FROM ${q(t)} WHERE user_id=$1`);
      if (has("market_listings", "seller_id", "status")) await run("market_listings", "UPDATE market_listings SET status='hidden' WHERE seller_id=$1 AND status NOT IN ('blocked','hidden')");
      if (has("market_listings", "seller_id", "bazaar_id")) await run("market_listings.bazaar", "UPDATE market_listings SET bazaar_id=NULL WHERE seller_id=$1 AND bazaar_id IS NOT NULL");
      if (has("market_spotlight", "seller_id", "status")) await run("market_spotlight", "UPDATE market_spotlight SET status='stopped' WHERE seller_id=$1 AND status='active'");
      if (has("market_coupons", "seller_id", "active")) await run("market_coupons", "UPDATE market_coupons SET active=false WHERE seller_id=$1 AND active");
      if (has("market_wanted", "user_id", "status")) await run("market_wanted", "UPDATE market_wanted SET status='closed' WHERE user_id=$1 AND status<>'closed'");
      if (has("market_wanted_replies", "seller_id")) await run("market_wanted_replies", "DELETE FROM market_wanted_replies WHERE seller_id=$1");
      if (has("market_questions", "user_id")) await run("market_questions", "DELETE FROM market_questions WHERE user_id=$1");
      if (has("market_reviews", "buyer_id", "text")) await run("market_reviews", "UPDATE market_reviews SET text='' WHERE buyer_id=$1 AND text<>''"); // التقييم يبقى لإحصاءات البائع بلا نص
      if (has("market_follows", "user_id", "seller_id")) await run("market_follows", "DELETE FROM market_follows WHERE user_id=$1 OR seller_id=$1");
      for (const t of ["market_alerts", "market_views", "saved_searches", "wishlist_items", "app_notifications", "biz_follows", "biz_member_prefs", "biz_offer_views", "biz_staff", "biz_claims"]) if (has(t, "user_id")) await run(t, `DELETE FROM ${q(t)} WHERE user_id=$1`);
      if (has("biz_reviews", "user_id")) await run("biz_reviews", "DELETE FROM biz_reviews WHERE user_id=$1");
      if (has("market_seller_upgrades", "seller_id")) await run("market_seller_upgrades", "DELETE FROM market_seller_upgrades WHERE seller_id=$1");
      if (has("biz_offer_grants", "user_id", "used_at", "expires_at")) await run("biz_offer_grants", "UPDATE biz_offer_grants SET expires_at=now() WHERE user_id=$1 AND used_at IS NULL");
      if (has("events", "host_id", "cancelled", "starts_at")) await run("events", "UPDATE events SET cancelled=true WHERE host_id=$1 AND starts_at > now() AND NOT cancelled");
      // ملاحظات الطلبات المنتهية قد تحمل عناوين أو أرقاماً
      if (has("market_orders", "buyer_id", "seller_id", "note")) await run("market_orders.notes", "UPDATE market_orders SET note='' WHERE (buyer_id=$1 OR seller_id=$1) AND note<>'' AND status IN ('completed','cancelled','refunded')");
      if (has("user_flags", "user_id", "suspended", "note")) await run("user_flags", "INSERT INTO user_flags(user_id, suspended, note) VALUES($1, true, 'account-deleted') ON CONFLICT (user_id) DO UPDATE SET suspended=true, note='account-deleted', updated_at=now()");
      const status = balance > 0 && refund ? "pending_refund" : "done";
      await c.query(`INSERT INTO account_deletions(user_id, status, by_id, nick_hash, reason, balance, report, reserved_until, purge_after, completed_at)
        VALUES($1,$2,$3,$4,$5,$6,$7, now() + ($8 || ' days')::interval, now() + ($9 || ' days')::interval, CASE WHEN $2='done' THEN now() ELSE NULL END)
        ON CONFLICT (user_id) DO UPDATE SET status=EXCLUDED.status, by_id=EXCLUDED.by_id, nick_hash=EXCLUDED.nick_hash, reason=EXCLUDED.reason, balance=EXCLUDED.balance,
          report=EXCLUDED.report, reserved_until=EXCLUDED.reserved_until, purge_after=EXCLUDED.purge_after, completed_at=EXCLUDED.completed_at, requested_at=now()`,
        [uid, status, by, oldNick ? nickHash(keyOf(), oldNick) : null, String(reason ?? "").slice(0, 300), balance, JSON.stringify({ ...report, errors }), String(RESERVE_DAYS), String(PURGE_DAYS)]);
      if (T.has("admin_audit")) await run("admin_audit", "INSERT INTO admin_audit(id, admin_id, action, target, details) VALUES($2, $3, 'user.self_delete', $1, $4)", [uid, crypto.randomUUID(), by, JSON.stringify({ status, balance })]);
      await c.query("COMMIT");
      return { status, report, errors, oldNick, oldAvatar, newNick, emails };
    } catch (e) {
      await c.query("ROLLBACK").catch(() => {});
      throw e;
    } finally { c.release(); }
  }

  /// بعد المعاملة: كلمة السر القديمة تموت (تدوير بعبارة الاسترداد)، ثم تُحذف كل الجلسات والصورة، وتصل رسالة تأكيد.
  async function afterCommit(req, uid, T, res) {
    const steps = {};
    const key = keyOf();
    if (key && T.has("account_recovery")) {
      try {
        const enc = (await pool.query("SELECT phrase_enc FROM account_recovery WHERE user_id=$1", [uid])).rows[0]?.phrase_enc;
        if (enc) {
          const phrase = decrypt(key, enc);
          const pw = crypto.randomBytes(24).toString("base64url") + "Aa1!";
          const r = await core(req, "/recover", { handle: res.newNick, nickname: res.newNick, recoveryPhrase: phrase, newPassword: pw, password: pw });
          steps.passwordRotated = r.statusCode >= 200 && r.statusCode < 300;
        }
      } catch { steps.passwordRotated = false; }
      await pool.query("DELETE FROM account_recovery WHERE user_id=$1", [uid]).catch(() => {});
    }
    const S = T.get("sessions"); const sk = pick(S, "user_id", "uid");
    if (sk) steps.sessions = (await pool.query(`DELETE FROM sessions WHERE ${q(sk)}=$1`, [uid]).catch(() => ({ rowCount: 0 }))).rowCount;
    if (res.oldAvatar) { try { await globalThis.naslifeMediaDelete?.(res.oldAvatar); steps.avatarDeleted = true; } catch { steps.avatarDeleted = false; } }
    const svc = globalThis.naslifeMail;
    if (svc?.configured?.() && res.emails.length) {
      try {
        const t = svc.template({
          title: "تم حذف حسابك في ناس لايف",
          greeting: `حذفنا حسابك «${res.oldNick ?? ""}» بناءً على طلبك من داخل التطبيق.`,
          stepsTitle: "ما الذي حدث",
          steps: ["حُذف بريدك وملفك وصورتك واشتراكات الإشعارات", "أُخفي محتواك وسيُمسح خلال 30 يوماً", "السجلات المالية محفوظة نظاماً بمعرّف لا يدل عليك",
            ...(res.status === "pending_refund" ? ["رصيد محفظتك سيُعاد إلى وسيلة الدفع خلال 30 يوماً"] : [])],
          note: "إن لم تطلب الحذف فراسلنا فوراً على support@naslife.app.", reason: "وصلتك هذه الرسالة لأن هذا البريد كان بريد الدخول لحسابك في ناس لايف.",
        });
        for (const to of res.emails.slice(0, 3)) await svc.send({ to, subject: "تم حذف حسابك · ناس لايف", ...t, tag: "account-deleted" });
        steps.mailed = true;
      } catch { steps.mailed = false; }
    }
    if (res.status === "pending_refund") { try { await globalThis.naslifeNotifyAdmins?.({ kind: "account_refund", title: "استرداد رصيد لحساب محذوف", body: `حساب ${uid} حُذف وبرصيده مبلغ يلزم استرداده خلال 30 يوماً`, data: { userId: uid } }); } catch { /* ignore */ } }
    await pool.query("UPDATE account_deletions SET report = report || $2::jsonb WHERE user_id=$1", [uid, JSON.stringify({ after: steps })]).catch(() => {});
    return steps;
  }

  app.post("/me/account/delete", async (req, reply) => {
    const uid = await me(req, reply); if (!uid) return;
    const b = req.body && typeof req.body === "object" ? req.body : {};
    if (limited("del:" + uid, 5, 15 * 60000)) return bad(reply, 429, "too-many-attempts");
    if (String(b.confirm ?? "").trim() !== CONFIRM_WORD) return bad(reply, 400, "confirm-mismatch", { expected: CONFIRM_WORD });
    const password = String(b.password ?? "");
    if (!password) return bad(reply, 400, "bad-password");
    const T = await schema();
    const refund = b.refund === true;
    const { blockers, balance } = await blockersOf(uid, T, { refund });
    if (blockers.length) return bad(reply, 409, "blocked", { blockers, balance });
    const U = T.get("users"); const nickCol = pick(U, "nickname", "name", "handle", "username");
    const nick = nickCol ? (await pool.query(`SELECT ${q(nickCol)} AS n FROM users WHERE id=$1`, [uid])).rows[0]?.n : null;
    if (!nick) return bad(reply, 404, "not-found");
    const l = await core(req, "/login", { handle: nick, password });
    if (l.statusCode !== 200) return bad(reply, 403, "bad-password");
    let res;
    try { res = await softDelete(uid, T, { by: uid, reason: b.reason, refund, balance }); }
    catch (e) { req.log?.error?.({ err: e }, "account_delete failed"); return bad(reply, 500, "delete-failed"); }
    const steps = await afterCommit(req, uid, T, res);
    return { ok: true, status: res.status, refundDays: res.status === "pending_refund" ? 30 : 0, steps: { sessions: steps.sessions ?? 0, passwordRotated: steps.passwordRotated ?? null } };
  });

  // ---- للمديرين: الحذف نفسه (يُستدعى من لوحة الإدارة لاحقاً) ومتابعة الاستردادات المعلّقة
  globalThis.naslifeAccountDelete = async (uid, { by = "admin", refund = true, req = null } = {}) => {
    const T = await schema();
    const bal = T.has("wallet_accounts") ? Number((await pool.query("SELECT balance FROM wallet_accounts WHERE user_id=$1", [uid])).rows[0]?.balance ?? 0) : 0;
    const res = await softDelete(uid, T, { by, refund, balance: bal });
    if (req) await afterCommit(req, uid, T, res);
    return res;
  };
  globalThis.naslifeNickReserved = async (nick) => {
    const n = String(nick ?? "").trim().toLowerCase();
    if (!n) return false;
    if (n.startsWith("deleted_")) return true;
    try { return (await pool.query("SELECT 1 FROM account_deletions WHERE nick_hash=$1 AND reserved_until > now() LIMIT 1", [nickHash(keyOf(), n)])).rowCount > 0; } catch { return false; }
  };
  const isAdmin = async (uid) => { try { return (await globalThis.naslifeIsAdmin?.(uid)) === true || (await globalThis.naslifeTeamCan?.(uid, "users.manage")) === true; } catch { return false; } };
  app.get("/adminapi/deletions", async (req, reply) => {
    const uid = await me(req, reply); if (!uid) return;
    if (!(await isAdmin(uid))) return bad(reply, 403, "forbidden");
    const rows = (await pool.query("SELECT user_id, status, balance, reason, refund_ref, requested_at, completed_at FROM account_deletions ORDER BY (status='pending_refund') DESC, requested_at DESC LIMIT 200")).rows;
    return { items: rows.map((r) => ({ userId: r.user_id, status: r.status, balance: Number(r.balance), reason: r.reason, refundRef: r.refund_ref, requestedAt: r.requested_at, completedAt: r.completed_at })) };
  });
  app.post("/adminapi/deletions/:id/complete", async (req, reply) => {
    const uid = await me(req, reply); if (!uid) return;
    if (!(await isAdmin(uid))) return bad(reply, 403, "forbidden");
    const id = String(req.params.id ?? "").toUpperCase();
    if (!ID_RE.test(id)) return bad(reply, 400, "bad-id");
    const ref = String(req.body?.refundRef ?? "").trim().slice(0, 120);
    if (!ref) return bad(reply, 400, "refund-ref-required");
    const r = await pool.query("UPDATE account_deletions SET status='done', refund_ref=$2, completed_at=now() WHERE user_id=$1 AND status='pending_refund' RETURNING user_id", [id, ref]);
    if (!r.rowCount) return bad(reply, 404, "not-pending");
    try { await pool.query("INSERT INTO admin_audit(id, admin_id, action, target, details) VALUES($1,$2,'user.refund_done',$3,$4)", [crypto.randomUUID(), uid, id, JSON.stringify({ refundRef: ref })]); } catch { /* ignore */ }
    return { ok: true };
  });

  // ---- كنس دوري: المحتوى المخفي لحساب محذوف يُمسح بعد 30 يوماً (والملفات من التخزين)
  async function sweep() {
    try {
      const due = (await pool.query("SELECT user_id FROM account_deletions WHERE purged_at IS NULL AND purge_after <= now() LIMIT 20")).rows;
      if (!due.length) return;
      const T = await schema();
      for (const { user_id: id } of due) {
        const media = [];
        if (T.has("map_posts")) for (const r of (await pool.query("DELETE FROM map_posts WHERE user_id=$1 AND status='hidden' RETURNING media_url, audio_url", [id]).catch(() => ({ rows: [] }))).rows) media.push(r.media_url, r.audio_url);
        if (T.has("biz_community_posts")) await pool.query("DELETE FROM biz_community_posts WHERE user_id=$1 AND hidden_by='account-deleted'", [id]).catch(() => {});
        if (T.has("biz_community_replies")) await pool.query("DELETE FROM biz_community_replies WHERE user_id=$1 AND hidden", [id]).catch(() => {});
        for (const u of media) if (u) { try { await globalThis.naslifeMediaDelete?.(u); } catch { /* ignore */ } }
        await pool.query("UPDATE account_deletions SET purged_at=now() WHERE user_id=$1", [id]);
      }
    } catch (e) { app.log?.warn?.({ err: e }, "account_delete: sweep failed"); }
  }
  globalThis.naslifeAccountSweep = sweep; // للاختبار والتشغيل اليدوي
  const timer = setInterval(sweep, 6 * 3600e3); timer.unref?.();
  setTimeout(sweep, 60e3).unref?.();
  app.addHook("onClose", async () => clearInterval(timer));
  app.get("/me/account/delete/status", async () => ({ ok: true, key: !!keyOf(), confirmWord: CONFIRM_WORD }));
}
