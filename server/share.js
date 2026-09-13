// روابط المشاركة العامة في Naslife: /c/<معرّف الدائرة> و /u/<النك نيم> يقدّمان واجهة التطبيق نفسها مع وسوم Open Graph
// (العنوان والوصف والصورة) حتى تظهر بطاقة معاينة عند لصق الرابط في واتساب وإكس وغيرهما، ثم يفتح التطبيق الوجهة من المسار.
// الملفات الخاصة (is_public=false إن وُجد العمود) تُعرض بوسوم عامة بلا صورة أو نبذة.
// التسجيل في src/index.js: await app.register((await import("./share.js")).default, { pool, webappDir });
import fs from "node:fs";
import path from "node:path";

const SLUG_RE = /^[a-z0-9][a-z0-9-]{1,63}$/;
const NICK_RE = /^[\p{L}\p{N}_.-]{2,40}$/u;
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

export default async function share(app, opts) {
  const { pool } = opts;
  if (!pool) throw new Error("share: pool is required");
  const WEBAPP = opts.webappDir ?? process.env.NASLIFE_WEBAPP_DIR ?? "/opt/naslife/webapp";
  const SITE = "Naslife · ناس لايف";
  const cols = async (table) => { try { return new Set((await pool.query("SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name=$1", [table])).rows.map((r) => r.column_name)); } catch { return new Set(); } };
  const userCols = await cols("users");
  const avatarCol = ["avatar_url", "avatarurl", "avatar", "photo_url", "image_url", "picture"].find((c) => userCols.has(c)) ?? null;
  const profileCols = await cols("profiles");
  const privacy = profileCols.has("is_public") && (profileCols.has("user_id") || profileCols.has("id")) ? (profileCols.has("user_id") ? "user_id" : "id") : null;
  const bioCol = profileCols.has("bio") ? "bio" : null;

  const publicOrigin = (req) => {
    const env = String(process.env.PUBLIC_BASE_URL ?? process.env.NASLIFE_PUBLIC_URL ?? "").trim().replace(/\/+$/, "");
    if (/^https?:\/\//i.test(env)) return env;
    const proto = String(req.headers["x-forwarded-proto"] ?? "https").split(",")[0].trim() || "https";
    const host = String(req.headers["x-forwarded-host"] ?? req.headers.host ?? "naslife.app").split(",")[0].trim().replace(/^www\./i, "");
    return `${proto}://${host}`;
  };
  // صورة عامة مطلقة: شعار مضمّن في حزمة الويب (asset:biz/x.png) أو رابط وسائط مرفوع
  const absImage = (req, u) => {
    const s = String(u ?? "").trim(); if (!s) return null;
    if (s.startsWith("asset:")) return `${publicOrigin(req)}/assets/assets/${s.slice(6)}`;
    if (/^https?:\/\//i.test(s)) return s.replace(/^https?:\/\/www\./i, `${publicOrigin(req).split("://")[0]}://`);
    if (s.startsWith("/")) return `${publicOrigin(req)}${s}`;
    return null;
  };

  let cache = { at: 0, html: null };
  async function indexHtml() {
    const now = Date.now();
    if (cache.html && now - cache.at < 5000) return cache.html;
    try { cache = { at: now, html: await fs.promises.readFile(path.join(WEBAPP, "index.html"), "utf8") }; } catch { return null; }
    return cache.html;
  }
  // يحقن الوسوم بعد <head> ويبدّل <title>؛ الوسوم القديمة من الحزمة (إن وُجدت) تبقى لكن المتصفحات والمعاينات تأخذ الأولى
  function withMeta(html, m) {
    const tags = [
      `<title>${esc(m.title)}</title>`,
      `<meta property="og:site_name" content="${esc(SITE)}">`,
      `<meta property="og:type" content="${esc(m.type ?? "website")}">`,
      `<meta property="og:title" content="${esc(m.title)}">`,
      `<meta property="og:description" content="${esc(m.description)}">`,
      `<meta property="og:url" content="${esc(m.url)}">`,
      m.image ? `<meta property="og:image" content="${esc(m.image)}">` : "",
      `<meta name="description" content="${esc(m.description)}">`,
      `<meta name="twitter:card" content="${m.image ? "summary" : "summary"}">`,
      `<meta name="twitter:title" content="${esc(m.title)}">`,
      `<meta name="twitter:description" content="${esc(m.description)}">`,
      m.image ? `<meta name="twitter:image" content="${esc(m.image)}">` : "",
      `<link rel="canonical" href="${esc(m.url)}">`,
    ].filter(Boolean).join("\n");
    let out = html.replace(/<title>[\s\S]*?<\/title>/i, "");
    out = out.replace(/<head([^>]*)>/i, (all) => `${all}\n${tags}`);
    return out;
  }
  async function serve(req, reply, meta) {
    const html = await indexHtml();
    if (!html) return reply.code(503).type("text/plain").send("web app not deployed yet");
    return reply.type("text/html; charset=utf-8").header("cache-control", "no-cache").send(withMeta(html, meta));
  }

  // ---- دائرة
  app.get("/c/:id", async (req, reply) => {
    const id = String(req.params.id ?? "");
    const url = `${publicOrigin(req)}/c/${esc(id)}`;
    let b = null;
    if (SLUG_RE.test(id)) { try { b = (await pool.query("SELECT id, name, name_ar, description, address, sector, logo_url, category FROM biz WHERE id=$1 AND active", [id])).rows[0] ?? null; } catch { b = null; } }
    if (!b) return serve(req, reply, { title: `دائرة على ${SITE}`, description: "افتح الرابط في ناس لايف لعرض الدائرة.", url });
    const name = b.name_ar || b.name;
    const desc = [b.sector, b.address].filter(Boolean).join(" · ") || b.description || "";
    return serve(req, reply, { title: `${name} · ناس لايف`, description: String(b.description || desc).slice(0, 200) || `دائرة ${name} على ناس لايف`, url, image: absImage(req, b.logo_url) });
  });
  // ---- حساب
  app.get("/u/:nick", async (req, reply) => {
    const nick = String(req.params.nick ?? "").trim();
    const url = `${publicOrigin(req)}/u/${encodeURIComponent(nick)}`;
    let u = null;
    if (NICK_RE.test(nick)) { try { u = (await pool.query(`SELECT id, nickname${avatarCol ? `, ${avatarCol} AS avatar` : ""} FROM users WHERE lower(nickname)=lower($1) LIMIT 1`, [nick])).rows[0] ?? null; } catch { u = null; } }
    if (!u) return serve(req, reply, { title: `حساب على ${SITE}`, description: "افتح الرابط في ناس لايف لعرض الحساب.", url });
    let isPublic = true, bio = "";
    if (privacy) { try { const p = (await pool.query(`SELECT is_public${bioCol ? ", bio" : ""} FROM profiles WHERE ${privacy}=$1`, [u.id])).rows[0]; if (p) { isPublic = p.is_public !== false; bio = String(p.bio ?? ""); } } catch { /* ignore */ } }
    const title = `${u.nickname} · ناس لايف`;
    if (!isPublic) return serve(req, reply, { title, description: `حساب ${u.nickname} على ناس لايف`, url, type: "profile" });
    return serve(req, reply, { title, description: bio.slice(0, 200) || `تواصل مع ${u.nickname} على ناس لايف`, url, type: "profile", image: absImage(req, u.avatar) });
  });
  app.get("/share/status", async () => ({ ok: true, webappDir: WEBAPP, avatarColumn: avatarCol, privacy: !!privacy }));
}
