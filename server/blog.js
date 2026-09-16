// مدونة ناس لايف العامة على /blog: صفحات HTML تُبنى في الخادم (لا تحتاج تطبيق Flutter) بتصميم التطبيق نفسه،
// تعرض التحديثات والأخبار والتدوينات مع وسوم Open Graph لكل منشور وخلاصتَي JSON وRSS.
// المنشورات تُحفظ في جدول blog_posts (تُبذر أول مرة من server/blog_posts.js) وتُدار من لوحة الإدارة عبر /adminapi/blog:
// إنشاء وتعديل ومسودات ونشر وجدولة وتثبيت ونسخ وحذف وروابط معاينة للمسودات وعدّاد مشاهدات. بلا قاعدة بيانات
// تعمل الصفحات العامة من الملف الثابت فقط.
// المسارات العامة: /blog (القائمة، مع ?kind=update|news|post)، /blog/<slug> (منشور)، /blog/feed.json، /blog/rss.xml، /blog/status.
// التسجيل في register.txt: await app.register((await import("./blog.js")).default, { pool, auth });
import crypto from "node:crypto";
import { BLOG_POSTS } from "./blog_posts.js";

const SITE = "ناس لايف";
export const KINDS = {
  update: { label: "تحديث", cls: "k-update", plural: "تحديثات" },
  news: { label: "خبر", cls: "k-news", plural: "أخبار" },
  post: { label: "تدوينة", cls: "k-post", plural: "تدوينات" },
};
const STATUSES = new Set(["draft", "published"]);
const MONTHS = ["يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو", "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر"];
const SLUG_RE = /^[a-z0-9][a-z0-9-]{0,63}$/;
const PREVIEW_TTL_MS = 24 * 3600 * 1000;

export const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
/// تاريخ بتوقيت الرياض (UTC+3) بصيغة YYYY-MM-DD.
export const riyadhDate = (ts) => { const d = new Date(new Date(ts).getTime() + 3 * 3600e3); return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}-${String(d.getUTCDate()).padStart(2, "0")}`; };
export const fmtDate = (d) => { const [y, m, day] = String(d).split("-").map(Number); return m >= 1 && m <= 12 ? `${day} ${MONTHS[m - 1]} ${y}` : String(d); };
const safeUrl = (u) => (/^(https?:\/\/|\/)[^\s"'<>]*$/i.test(String(u ?? "").trim()) ? String(u).trim() : null);

/// الأجزاء داخل السطر: عريض، صورة، رابط بعنوان، رابط خام. يُهرَّب النص أولاً ثم تُبنى الوسوم.
const INLINE = /\*\*(.+?)\*\*|!\[([^\]]*)\]\((https?:\/\/[^\s)]+|\/[^\s)]+)\)|\[([^\]]+)\]\((https?:\/\/[^\s)]+|\/[^\s)]+)\)|(https?:\/\/[^\s<>()\[\]]+)/g;
export function inlineHtml(text) {
  let out = "", i = 0;
  for (const m of String(text).matchAll(INLINE)) {
    out += esc(text.slice(i, m.index));
    if (m[1] != null) out += `<strong>${esc(m[1])}</strong>`;
    else if (m[2] != null) out += `<img src="${esc(m[3])}" alt="${esc(m[2])}" loading="lazy">`;
    else if (m[4] != null) out += `<a href="${esc(m[5])}" rel="noopener">${esc(m[4])}</a>`;
    else out += `<a href="${esc(m[6])}" rel="noopener">${esc(m[6])}</a>`;
    i = m.index + m[0].length;
  }
  return out + esc(text.slice(i));
}

/// التنسيق الخفيف نفسه المستخدم في منشورات التطبيق (core/text/post_markup.dart) إلى HTML.
export function markupHtml(text) {
  const lines = String(text ?? "").replace(/\r\n/g, "\n").split("\n");
  const out = [];
  let para = [], list = null;
  const flushPara = () => { if (para.length) { out.push(`<p>${para.map(inlineHtml).join("<br>")}</p>`); para = []; } };
  const flushList = () => { if (list) { out.push(`<${list.tag}>${list.items.map((x) => `<li>${inlineHtml(x)}</li>`).join("")}</${list.tag}>`); list = null; } };
  const flush = () => { flushPara(); flushList(); };
  for (const raw of lines) {
    const line = raw.trim();
    if (!line) { flush(); continue; }
    let m;
    if ((m = line.match(/^##\s+(.*)$/))) { flush(); out.push(`<h3>${inlineHtml(m[1])}</h3>`); continue; }
    if ((m = line.match(/^#\s+(.*)$/))) { flush(); out.push(`<h2>${inlineHtml(m[1])}</h2>`); continue; }
    if (/^(-{3,}|_{3,}|\*{3,})$/.test(line)) { flush(); out.push("<hr>"); continue; }
    if ((m = line.match(/^!\[([^\]]*)\]\((https?:\/\/[^\s)]+|\/[^\s)]+)\)$/))) { flush(); out.push(`<figure><img src="${esc(m[2])}" alt="${esc(m[1])}" loading="lazy">${m[1] ? `<figcaption>${esc(m[1])}</figcaption>` : ""}</figure>`); continue; }
    if ((m = line.match(/^[0-9٠-٩]{1,3}[.)]\s+(.*)$/))) { flushPara(); if (!list || list.tag !== "ol") { flushList(); list = { tag: "ol", items: [] }; } list.items.push(m[1]); continue; }
    if ((m = line.match(/^[-•*]\s+(.*)$/))) { flushPara(); if (!list || list.tag !== "ul") { flushList(); list = { tag: "ul", items: [] }; } list.items.push(m[1]); continue; }
    if ((m = line.match(/^>\s?(.*)$/))) { flush(); out.push(`<blockquote>${inlineHtml(m[1])}</blockquote>`); continue; }
    flushList();
    para.push(line);
  }
  flush();
  return out.join("\n");
}

/// معرّف رابط من العنوان: حروف لاتينية وأرقام وشرطات؛ العناوين العربية تأخذ التاريخ ومقطعاً عشوائياً.
export function slugify(title, now = new Date()) {
  const s = String(title ?? "").toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 60).replace(/-+$/g, "");
  if (s.length >= 3) return s;
  return `${riyadhDate(now).replace(/-/g, "")}-${crypto.randomBytes(2).toString("hex")}`;
}

/// منشورات الملف الثابت بالشكل نفسه الذي تعيده قاعدة البيانات (احتياط بلا قاعدة، وبذرة أول تشغيل).
export function staticPosts() {
  return BLOG_POSTS.filter((p) => p && p.slug && p.title).map((p) => ({
    id: p.slug, slug: p.slug, kind: KINDS[p.kind] ? p.kind : "update", title: p.title, summary: p.summary ?? "", body: p.body ?? "", coverUrl: null, tags: [],
    status: "published", pinned: false, publishedAt: new Date(new Date(`${p.date}T09:00:00+03:00`).getTime() + (p.order ?? 0) * 60e3), views: 0, createdAt: null, updatedAt: null, authorId: null,
  })).sort((a, b) => b.publishedAt - a.publishedAt);
}

const CSS = `
:root{--bg:#FFFFFF;--surface:#F2F2F7;--line:#E5E5EA;--text:#111111;--muted:#6B7280;--accent:#0A6E78;--accent-soft:#E0F3F4;--accent-on:#FFFFFF;--coral:#BF3A1E;--coral-soft:#FDEBE6;--sun:#5A4200;--sun-soft:#FFF4D6}
@media (prefers-color-scheme:dark){:root{--bg:#121417;--surface:#1C2024;--line:#2A3036;--text:#F2F2F2;--muted:#9AA3AD;--accent:#4FB3BC;--accent-soft:#163338;--accent-on:#0B1416;--coral:#FF8A6B;--coral-soft:#3A1F17;--sun:#FFD66B;--sun-soft:#3A3010}}
@font-face{font-family:'Rubik';font-weight:400;src:url('/assets/fonts/Rubik-Regular.ttf') format('truetype');font-display:swap}
@font-face{font-family:'Rubik';font-weight:500;src:url('/assets/fonts/Rubik-Medium.ttf') format('truetype');font-display:swap}
@font-face{font-family:'Rubik';font-weight:600;src:url('/assets/fonts/Rubik-SemiBold.ttf') format('truetype');font-display:swap}
@font-face{font-family:'Rubik';font-weight:700;src:url('/assets/fonts/Rubik-Bold.ttf') format('truetype');font-display:swap}
@font-face{font-family:'Baloo';font-weight:700;src:url('/assets/fonts/BalooBhaijaan2-Bold.ttf') format('truetype');font-display:swap}
*{box-sizing:border-box}
html{direction:rtl}
body{margin:0;background:var(--bg);color:var(--text);font-family:'Rubik','Segoe UI',Tahoma,sans-serif;font-weight:500;line-height:1.75;font-size:16px;-webkit-text-size-adjust:100%}
a{color:var(--accent)}
.top{position:sticky;top:0;z-index:2;background:var(--bg);border-bottom:1px solid var(--line)}
.top .in{max-width:720px;margin:0 auto;padding:10px 16px;display:flex;align-items:center;gap:14px}
.brand{display:flex;align-items:center;gap:8px;text-decoration:none;color:var(--text);font-family:'Baloo','Rubik',sans-serif;font-weight:700;font-size:21px}
.brand img{width:30px;height:30px;border-radius:9px}
.brand small{font-family:'Rubik',sans-serif;font-weight:600;font-size:13px;color:var(--muted)}
.open{margin-inline-start:auto;text-decoration:none;background:var(--accent);color:var(--accent-on);font-weight:600;font-size:14px;padding:8px 14px;border-radius:999px;white-space:nowrap}
main{max-width:720px;margin:0 auto;padding:22px 16px 60px}
h1{font-family:'Baloo','Rubik',sans-serif;font-weight:700;font-size:30px;line-height:1.25;margin:0 0 4px;text-wrap:balance}
.lead{color:var(--muted);margin:0 0 18px;font-size:15px}
.filters{display:flex;gap:8px;flex-wrap:wrap;margin:0 0 18px}
.filters a{text-decoration:none;border:1px solid var(--line);color:var(--text);border-radius:999px;padding:6px 14px;font-size:14px;font-weight:600}
.filters a.on{background:var(--accent);border-color:var(--accent);color:var(--accent-on)}
.list{display:flex;flex-direction:column;gap:14px}
.card{border:1px solid var(--line);border-radius:16px;padding:16px 18px;display:flex;flex-direction:column;gap:6px}
.card.pinned{border-color:var(--accent)}
.card .cover{width:100%;aspect-ratio:16/9;object-fit:cover;border-radius:12px;margin-bottom:6px;display:block}
.meta{display:flex;align-items:center;gap:10px;font-size:13px;color:var(--muted);flex-wrap:wrap}
.kind{font-size:12px;font-weight:700;padding:2px 10px;border-radius:999px}
.k-update{background:var(--accent-soft);color:var(--accent)}
.k-news{background:var(--coral-soft);color:var(--coral)}
.k-post{background:var(--sun-soft);color:var(--sun)}
.pin{font-size:12px;font-weight:700;color:var(--accent)}
.card h2{font-family:'Baloo','Rubik',sans-serif;font-weight:700;font-size:21px;line-height:1.3;margin:0;text-wrap:balance}
.card h2 a{color:var(--text);text-decoration:none}
.card p{margin:0;color:var(--muted)}
.more{font-size:14px;font-weight:600;text-decoration:none}
.tags{display:flex;gap:6px;flex-wrap:wrap}
.tags span{font-size:12px;background:var(--surface);border-radius:999px;padding:2px 10px;color:var(--muted)}
.banner{background:var(--sun-soft);color:var(--sun);border-radius:12px;padding:10px 14px;font-size:14px;font-weight:600;margin-bottom:16px}
article.post header{display:flex;flex-direction:column;gap:6px;margin-bottom:16px}
article.post .cover{width:100%;max-height:420px;object-fit:cover;border-radius:16px;display:block;margin:4px 0 16px}
article.post .body{font-size:16.5px}
article.post .body h2{font-family:'Baloo','Rubik',sans-serif;font-size:23px;line-height:1.3;margin:22px 0 6px}
article.post .body h3{font-size:18px;font-weight:700;margin:18px 0 4px}
article.post .body p{margin:0 0 12px}
article.post .body ul,article.post .body ol{margin:0 0 14px;padding-inline-start:22px}
article.post .body li{margin:2px 0}
article.post .body li::marker{color:var(--accent);font-weight:700}
article.post .body blockquote{margin:0 0 14px;border-inline-start:3px solid var(--accent);padding-inline-start:12px;color:var(--muted)}
article.post .body hr{border:0;border-top:1px solid var(--line);margin:18px 0}
article.post .body img{max-width:100%;border-radius:14px;display:block}
article.post .body figure{margin:0 0 14px}
article.post .body figcaption{font-size:13px;color:var(--muted);margin-top:6px}
.share{display:flex;gap:8px;flex-wrap:wrap;margin:22px 0 8px;padding-top:16px;border-top:1px solid var(--line)}
.share a,.share button{font:inherit;font-size:14px;font-weight:600;text-decoration:none;border:1px solid var(--line);color:var(--text);background:var(--bg);border-radius:999px;padding:8px 14px;cursor:pointer}
.share button:focus-visible,.share a:focus-visible{outline:2px solid var(--accent);outline-offset:2px}
.pn{display:flex;justify-content:space-between;gap:12px;margin-top:20px;font-size:14px}
.pn a{text-decoration:none;max-width:48%}
.pn span{display:block;color:var(--muted);font-size:12px}
footer{max-width:720px;margin:0 auto;padding:0 16px 40px;color:var(--muted);font-size:13px;display:flex;gap:14px;flex-wrap:wrap}
footer a{color:var(--muted)}
.empty{color:var(--muted);padding:30px 0;text-align:center}
`;

export default async function blog(app, opts = {}) {
  // قد تُسجَّل الإضافة بلا خيارات (سطر التسجيل الأول في index.js لا يُحدَّث تلقائياً)، فنأخذ الاتصال والمصادقة من business.js
  const pool = opts.pool ?? globalThis.naslifePool ?? null;
  const auth = opts.auth ?? globalThis.naslifeAuth ?? null;
  let dbOk = false;
  const log = (lvl, ...a) => { try { app.log[lvl]?.(...a); } catch { /* ignore */ } };

  const toPost = (r) => ({
    id: r.id, slug: r.slug, kind: KINDS[r.kind] ? r.kind : "update", title: r.title, summary: r.summary ?? "", body: r.body ?? "", coverUrl: r.cover_url ?? null,
    tags: Array.isArray(r.tags) ? r.tags : [], status: r.status, pinned: r.pinned === true, publishedAt: r.published_at ? new Date(r.published_at) : null, views: Number(r.views ?? 0),
    createdAt: r.created_at ? new Date(r.created_at) : null, updatedAt: r.updated_at ? new Date(r.updated_at) : null, authorId: r.author_id ?? null, bodyLength: r.body_len != null ? Number(r.body_len) : undefined,
  });
  const effective = (p, now = Date.now()) => (p.status !== "published" ? "draft" : p.publishedAt && p.publishedAt.getTime() > now ? "scheduled" : "published");
  const COLS = "id, slug, kind, title, summary, body, cover_url, tags, status, pinned, published_at, views, created_at, updated_at, author_id";

  let dbError = null, lastInit = 0;
  async function initDb() {
    if (!pool || dbOk) return;
    lastInit = Date.now();
    try {
      await pool.query(`CREATE TABLE IF NOT EXISTS blog_posts (
        id UUID PRIMARY KEY, slug TEXT NOT NULL UNIQUE, kind TEXT NOT NULL DEFAULT 'update', title TEXT NOT NULL, summary TEXT NOT NULL DEFAULT '', body TEXT NOT NULL DEFAULT '',
        cover_url TEXT, tags TEXT[] NOT NULL DEFAULT '{}', status TEXT NOT NULL DEFAULT 'draft', pinned BOOLEAN NOT NULL DEFAULT false, published_at TIMESTAMPTZ, author_id TEXT,
        views INTEGER NOT NULL DEFAULT 0, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now());
        CREATE INDEX IF NOT EXISTS blog_posts_pub ON blog_posts(status, published_at DESC);`);
      // البذرة: منشورات الملف الثابت تُدرج مرة واحدة (بحسب slug) ولا تُعاد كتابتها بعد تعديلها من اللوحة
      for (const p of staticPosts()) {
        await pool.query(`INSERT INTO blog_posts(id, slug, kind, title, summary, body, status, published_at, created_at, updated_at) VALUES($1,$2,$3,$4,$5,$6,'published',$7,$7,$7) ON CONFLICT (slug) DO NOTHING`,
          [crypto.randomUUID(), p.slug, p.kind, p.title, p.summary, p.body, p.publishedAt]);
      }
      dbOk = true; dbError = null;
    } catch (e) { dbError = String(e?.message ?? e).slice(0, 300); log("error", { err: e }, "blog: table/seed failed; serving static posts"); }
  }
  await initDb();
  // إعادة محاولة التهيئة عند أول طلب بعد دقيقة إن فشلت (قاعدة البيانات قد تكون متأخرة عند الإقلاع)
  app.addHook("onRequest", async () => { if (pool && !dbOk && Date.now() - lastInit > 60e3) await initDb(); });

  async function publicPosts() {
    if (!dbOk) return staticPosts();
    try { return (await pool.query(`SELECT ${COLS} FROM blog_posts WHERE status='published' AND published_at <= now() ORDER BY pinned DESC, published_at DESC`)).rows.map(toPost); }
    catch (e) { log("warn", { err: e }, "blog: query failed; serving static posts"); return staticPosts(); }
  }
  async function bySlug(slug, { any = false } = {}) {
    if (!SLUG_RE.test(slug)) return null;
    if (!dbOk) return staticPosts().find((p) => p.slug === slug) ?? null;
    try {
      const r = await pool.query(`SELECT ${COLS} FROM blog_posts WHERE slug=$1${any ? "" : " AND status='published' AND published_at <= now()"} LIMIT 1`, [slug]);
      return r.rows[0] ? toPost(r.rows[0]) : null;
    } catch { return staticPosts().find((p) => p.slug === slug) ?? null; }
  }
  const byId = async (id) => { if (!dbOk || !/^[0-9a-f-]{36}$/i.test(id)) return null; const r = await pool.query(`SELECT ${COLS} FROM blog_posts WHERE id=$1`, [id]); return r.rows[0] ? toPost(r.rows[0]) : null; };
  const slugExists = async (slug, exceptId = null) => (await pool.query("SELECT 1 FROM blog_posts WHERE slug=$1 AND ($2::uuid IS NULL OR id<>$2)", [slug, exceptId])).rowCount > 0;
  async function uniqueSlug(base, exceptId = null) {
    let s = base, n = 2;
    while (await slugExists(s, exceptId)) s = `${base}-${n++}`.slice(0, 64);
    return s;
  }
  const audit = async (adminId, action, target, details = {}) => { try { await pool.query("INSERT INTO admin_audit(id,admin_id,action,target,details) VALUES($1,$2,$3,$4,$5)", [crypto.randomUUID(), adminId, action, target, JSON.stringify(details)]); } catch { /* الجدول من admin.js قد لا يكون موجوداً */ } };

  // ---- روابط معاينة المسودات: مفتاح عشوائي لكل منشور صالح 24 ساعة
  const previews = new Map();
  const previewKey = (id) => { const cur = previews.get(id); if (cur && cur.exp > Date.now()) return cur.key; const key = crypto.randomBytes(12).toString("hex"); previews.set(id, { key, exp: Date.now() + PREVIEW_TTL_MS }); return key; };
  const previewOk = (id, key) => { const cur = previews.get(id); return !!cur && cur.exp > Date.now() && key && crypto.timingSafeEqual(Buffer.from(cur.key), Buffer.from(String(key).padEnd(cur.key.length).slice(0, cur.key.length))); };

  const publicOrigin = (req) => {
    const env = String(process.env.PUBLIC_BASE_URL ?? process.env.NASLIFE_PUBLIC_URL ?? "").trim().replace(/\/+$/, "");
    if (/^https?:\/\//i.test(env)) return env;
    const proto = String(req.headers["x-forwarded-proto"] ?? "https").split(",")[0].trim() || "https";
    const host = String(req.headers["x-forwarded-host"] ?? req.headers.host ?? "naslife.app").split(",")[0].trim().replace(/^www\./i, "");
    return `${proto}://${host}`;
  };
  const absUrl = (req, u) => (u && u.startsWith("/") ? `${publicOrigin(req)}${u}` : u);
  const dateOf = (p) => riyadhDate(p.publishedAt ?? p.createdAt ?? new Date());
  const kindBadge = (k) => { const d = KINDS[k] ?? KINDS.update; return `<span class="kind ${d.cls}">${d.label}</span>`; };
  const page = ({ title, description, url, image, body, ogType = "website", extraHead = "", noindex = false }) => `<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<meta name="description" content="${esc(description)}">
${noindex ? '<meta name="robots" content="noindex">' : ""}
<meta property="og:site_name" content="${esc(SITE)}">
<meta property="og:type" content="${esc(ogType)}">
<meta property="og:title" content="${esc(title)}">
<meta property="og:description" content="${esc(description)}">
<meta property="og:url" content="${esc(url)}">
${image ? `<meta property="og:image" content="${esc(image)}">` : ""}
<meta name="twitter:card" content="${image ? "summary_large_image" : "summary"}">
<meta name="twitter:title" content="${esc(title)}">
<meta name="twitter:description" content="${esc(description)}">
<link rel="canonical" href="${esc(url)}">
<link rel="icon" type="image/png" href="/favicon.png">
<link rel="alternate" type="application/feed+json" title="${esc(SITE)}" href="/blog/feed.json">
<link rel="alternate" type="application/rss+xml" title="${esc(SITE)}" href="/blog/rss.xml">
${extraHead}
<style>${CSS}</style>
</head>
<body>
<div class="top"><div class="in"><a class="brand" href="/blog"><img src="/icons/Icon-192.png" alt=""><span>ناس لايف</span><small>المدونة</small></a><a class="open" href="/">افتح التطبيق</a></div></div>
<main>
${body}
</main>
<footer><span>© ${new Date().getFullYear()} ناس لايف</span><a href="/blog/rss.xml">RSS</a><a href="/blog/feed.json">JSON</a><a href="/">naslife.app</a></footer>
</body>
</html>`;
  const send = (reply, html, code = 200, cache = "public, max-age=120") => reply.code(code).type("text/html; charset=utf-8").header("cache-control", cache).send(html);

  async function listPage(req, kind) {
    const origin = publicOrigin(req);
    const all = await publicPosts();
    const list = kind ? all.filter((p) => p.kind === kind) : all;
    const filters = [["", "الكل"], ...Object.entries(KINDS).map(([k, d]) => [k, d.plural])]
      .map(([k, l]) => `<a class="${(kind ?? "") === k ? "on" : ""}" href="/blog${k ? `?kind=${k}` : ""}">${l}</a>`).join("");
    const cards = list.map((p) => `<article class="card${p.pinned ? " pinned" : ""}">
${p.coverUrl ? `<a href="/blog/${esc(p.slug)}"><img class="cover" src="${esc(p.coverUrl)}" alt="" loading="lazy"></a>` : ""}
<div class="meta">${kindBadge(p.kind)}<time datetime="${esc(dateOf(p))}">${esc(fmtDate(dateOf(p)))}</time>${p.pinned ? '<span class="pin">مثبّت</span>' : ""}</div>
<h2><a href="/blog/${esc(p.slug)}">${esc(p.title)}</a></h2>
${p.summary ? `<p>${inlineHtml(p.summary)}</p>` : ""}
<a class="more" href="/blog/${esc(p.slug)}">اقرأ المزيد</a>
</article>`).join("\n");
    const heading = kind ? KINDS[kind]?.plural ?? "المدونة" : "التحديثات والأخبار";
    const body = `<h1>${esc(heading)}</h1>
<p class="lead">كل جديد في ناس لايف، من الأحدث إلى الأقدم.</p>
<div class="filters">${filters}</div>
<div class="list">${cards || '<div class="empty">لا منشورات بعد.</div>'}</div>`;
    return page({ title: kind ? `${heading} · ${SITE}` : `مدونة ${SITE}`, description: "تحديثات وأخبار وتدوينات ناس لايف: الخريطة والدردشة والدوائر التجارية.", url: `${origin}/blog${kind ? `?kind=${kind}` : ""}`, body });
  }

  async function postPage(req, p, { preview = false } = {}) {
    const origin = publicOrigin(req);
    const url = `${origin}/blog/${p.slug}`;
    const all = preview ? [] : await publicPosts();
    const i = all.findIndex((x) => x.slug === p.slug);
    const newer = i > 0 ? all[i - 1] : null, older = i >= 0 && i < all.length - 1 ? all[i + 1] : null;
    const text = encodeURIComponent(`${p.title} · ناس لايف`);
    const st = effective(p);
    const body = `${preview ? `<div class="banner">معاينة ${st === "draft" ? "مسودة" : st === "scheduled" ? "منشور مجدول" : "منشور"}: هذه الصفحة لا تظهر للزوار${st === "published" ? "" : " حتى النشر"}.</div>` : ""}<article class="post">
<header>
<div class="meta">${kindBadge(p.kind)}<time datetime="${esc(dateOf(p))}">${esc(fmtDate(dateOf(p)))}</time>${p.pinned ? '<span class="pin">مثبّت</span>' : ""}</div>
<h1>${esc(p.title)}</h1>
${p.tags.length ? `<div class="tags">${p.tags.map((t) => `<span>${esc(t)}</span>`).join("")}</div>` : ""}
</header>
${p.coverUrl ? `<img class="cover" src="${esc(p.coverUrl)}" alt="">` : ""}
<div class="body">${markupHtml(p.body)}</div>
<div class="share">
<a href="https://wa.me/?text=${text}%20${encodeURIComponent(url)}" rel="noopener" target="_blank">واتساب</a>
<a href="https://twitter.com/intent/tweet?text=${text}&url=${encodeURIComponent(url)}" rel="noopener" target="_blank">إكس</a>
<button type="button" id="copy-link" data-url="${esc(url)}">نسخ الرابط</button>
</div>
<nav class="pn">
${older ? `<a href="/blog/${esc(older.slug)}"><span>الأقدم</span>${esc(older.title)}</a>` : "<span></span>"}
${newer ? `<a href="/blog/${esc(newer.slug)}" style="text-align:left"><span>الأحدث</span>${esc(newer.title)}</a>` : "<span></span>"}
</nav>
<p style="margin-top:22px"><a href="/blog">← كل التحديثات</a></p>
</article>
<script>
(function(){var b=document.getElementById('copy-link');if(!b)return;b.addEventListener('click',function(){var u=b.getAttribute('data-url');var done=function(ok){b.textContent=ok?'نُسخ الرابط':'تعذّر النسخ';setTimeout(function(){b.textContent='نسخ الرابط';},1600);};if(navigator.clipboard&&navigator.clipboard.writeText){navigator.clipboard.writeText(u).then(function(){done(true);},function(){done(false);});}else{done(false);}});})();
</script>`;
    const ld = `<script type="application/ld+json">${JSON.stringify({ "@context": "https://schema.org", "@type": p.kind === "news" ? "NewsArticle" : "BlogPosting", headline: p.title, datePublished: dateOf(p), inLanguage: "ar", url, image: p.coverUrl ? absUrl(req, p.coverUrl) : undefined, publisher: { "@type": "Organization", name: SITE } })}</script>`;
    return page({ title: `${p.title} · ${SITE}`, description: p.summary || p.title, url, body, ogType: "article", extraHead: ld, image: p.coverUrl ? absUrl(req, p.coverUrl) : null, noindex: preview });
  }

  const notFound = (req, reply) => send(reply, page({ title: `غير موجود · ${SITE}`, description: "المنشور غير موجود", url: `${publicOrigin(req)}/blog`, body: `<h1>المنشور غير موجود</h1><p class="lead">ربما تغيّر رابطه أو حُذف.</p><p><a href="/blog">← كل التحديثات</a></p>`, noindex: true }), 404, "no-store");

  // ---------------- الصفحات العامة ----------------
  app.get("/blog", async (req, reply) => {
    const k = String(req.query?.kind ?? "").trim();
    return send(reply, await listPage(req, KINDS[k] ? k : null));
  });
  app.get("/blog/", async (req, reply) => reply.redirect(`/blog${req.query?.kind ? `?kind=${encodeURIComponent(String(req.query.kind))}` : ""}`, 301));
  app.get("/blog/feed.json", async (req, reply) => {
    const origin = publicOrigin(req);
    const list = await publicPosts();
    return reply.type("application/feed+json; charset=utf-8").header("cache-control", "public, max-age=120").send({
      version: "https://jsonfeed.org/version/1.1", title: `مدونة ${SITE}`, home_page_url: `${origin}/blog`, feed_url: `${origin}/blog/feed.json`, language: "ar",
      items: list.map((p) => ({ id: `${origin}/blog/${p.slug}`, url: `${origin}/blog/${p.slug}`, title: p.title, summary: p.summary || "", image: p.coverUrl ? absUrl(req, p.coverUrl) : undefined, date_published: (p.publishedAt ?? new Date()).toISOString(), tags: [KINDS[p.kind]?.label ?? p.kind, ...p.tags], content_html: markupHtml(p.body) })),
    });
  });
  app.get("/blog/rss.xml", async (req, reply) => {
    const origin = publicOrigin(req);
    const list = await publicPosts();
    const items = list.map((p) => `<item><title>${esc(p.title)}</title><link>${origin}/blog/${esc(p.slug)}</link><guid isPermaLink="true">${origin}/blog/${esc(p.slug)}</guid><pubDate>${(p.publishedAt ?? new Date()).toUTCString()}</pubDate><category>${esc(KINDS[p.kind]?.label ?? p.kind)}</category><description><![CDATA[${markupHtml(p.body).replace(/]]>/g, "]]]]><![CDATA[>")}]]></description></item>`).join("\n");
    const xml = `<?xml version="1.0" encoding="UTF-8"?>\n<rss version="2.0"><channel><title>مدونة ${esc(SITE)}</title><link>${origin}/blog</link><description>تحديثات وأخبار وتدوينات ناس لايف</description><language>ar</language>\n${items}\n</channel></rss>`;
    return reply.type("application/rss+xml; charset=utf-8").header("cache-control", "public, max-age=120").send(xml);
  });
  app.get("/blog/status", async () => { const list = await publicPosts(); return { ok: true, db: dbOk, dbError, posts: list.length, latest: list[0]?.slug ?? null, kinds: Object.keys(KINDS) }; });
  app.get("/blog/:slug", async (req, reply) => {
    const slug = String(req.params.slug ?? "");
    const key = req.query?.key ? String(req.query.key) : null;
    if (key) {
      const p = await bySlug(slug, { any: true });
      if (p && previewOk(p.id, key)) return send(reply, await postPage(req, p, { preview: true }), 200, "no-store");
      return notFound(req, reply);
    }
    const p = await bySlug(slug);
    if (!p) return notFound(req, reply);
    if (dbOk) pool.query("UPDATE blog_posts SET views=views+1 WHERE id=$1", [p.id]).catch(() => {});
    return send(reply, await postPage(req, p));
  });

  // ---------------- واجهة الإدارة ----------------
  const bad = (reply, code, error, extra = {}) => reply.code(code).send({ error, ...extra });
  async function guard(req, reply) {
    if (!dbOk || !auth) { bad(reply, 503, "blog-admin-unavailable"); return null; }
    const uid = await auth(req);
    if (!uid) { bad(reply, 401, "auth"); return null; }
    const isAdmin = globalThis.naslifeIsAdmin;
    if (isAdmin && (await isAdmin(uid))) return uid;
    let ok = false; try { ok = !!(await globalThis.naslifeTeamAccess?.(uid, req.method, req.url)); } catch { ok = false; }
    if (!ok) { bad(reply, 403, "admin-only"); return null; }
    return uid;
  }
  const adminJson = (req, p) => ({ ...p, body: p.body, effectiveStatus: effective(p), date: dateOf(p), url: `${publicOrigin(req)}/blog/${p.slug}` });
  /// يتحقق من حقول المنشور ويعيد القيم النظيفة أو { error }.
  function clean(b, { partial = false } = {}) {
    const out = {};
    if (!partial || b.title !== undefined) { const t = String(b.title ?? "").trim(); if (!t || t.length > 160) return { error: "bad-title" }; out.title = t; }
    if (!partial || b.kind !== undefined) { const k = String(b.kind ?? "update"); if (!KINDS[k]) return { error: "bad-kind" }; out.kind = k; }
    if (b.summary !== undefined) out.summary = String(b.summary ?? "").trim().slice(0, 300);
    if (b.body !== undefined) { const s = String(b.body ?? ""); if (s.length > 60000) return { error: "bad-body" }; out.body = s; }
    if (b.coverUrl !== undefined) { const u = b.coverUrl == null || b.coverUrl === "" ? null : safeUrl(b.coverUrl); if (b.coverUrl && !u) return { error: "bad-cover" }; out.coverUrl = u; }
    if (b.tags !== undefined) { if (!Array.isArray(b.tags)) return { error: "bad-tags" }; out.tags = [...new Set(b.tags.map((t) => String(t).trim()).filter(Boolean))].slice(0, 10).map((t) => t.slice(0, 30)); }
    if (b.pinned !== undefined) out.pinned = b.pinned === true;
    if (b.status !== undefined) { if (!STATUSES.has(String(b.status))) return { error: "bad-status" }; out.status = String(b.status); }
    if (b.publishedAt !== undefined) { if (b.publishedAt == null || b.publishedAt === "") out.publishedAt = null; else { const d = new Date(b.publishedAt); if (Number.isNaN(d.getTime())) return { error: "bad-date" }; out.publishedAt = d; } }
    if (b.slug !== undefined && b.slug !== null && String(b.slug).trim() !== "") { const s = String(b.slug).trim().toLowerCase(); if (!SLUG_RE.test(s)) return { error: "bad-slug" }; out.slug = s; }
    return out;
  }
  const counts = async () => (await pool.query(`SELECT count(*)::int AS all, count(*) FILTER (WHERE status='draft')::int AS draft,
      count(*) FILTER (WHERE status='published' AND published_at <= now())::int AS published, count(*) FILTER (WHERE status='published' AND published_at > now())::int AS scheduled,
      coalesce(sum(views),0)::int AS views FROM blog_posts`)).rows[0];

  app.get("/adminapi/blog", async (req, reply) => {
    if (!(await guard(req, reply))) return;
    const q = String(req.query?.q ?? "").trim(), kind = String(req.query?.kind ?? "").trim(), status = String(req.query?.status ?? "all").trim();
    const limit = Math.min(200, Math.max(1, Number(req.query?.limit) || 100)), offset = Math.max(0, Number(req.query?.offset) || 0);
    const where = ["true"], args = [];
    if (q) { args.push(`%${q}%`); where.push(`(title ILIKE $${args.length} OR summary ILIKE $${args.length} OR slug ILIKE $${args.length} OR body ILIKE $${args.length})`); }
    if (KINDS[kind]) { args.push(kind); where.push(`kind=$${args.length}`); }
    if (status === "draft") where.push("status='draft'");
    else if (status === "published") where.push("status='published' AND published_at <= now()");
    else if (status === "scheduled") where.push("status='published' AND published_at > now()");
    args.push(limit, offset);
    const rows = (await pool.query(`SELECT id, slug, kind, title, summary, cover_url, tags, status, pinned, published_at, views, created_at, updated_at, author_id, length(body) AS body_len FROM blog_posts WHERE ${where.join(" AND ")}
      ORDER BY pinned DESC, coalesce(published_at, updated_at) DESC LIMIT $${args.length - 1} OFFSET $${args.length}`, args)).rows;
    const total = (await pool.query(`SELECT count(*)::int AS n FROM blog_posts WHERE ${where.join(" AND ")}`, args.slice(0, -2))).rows[0].n;
    return { posts: rows.map((r) => { const p = toPost(r); const { body: _b, ...rest } = adminJson(req, p); return rest; }), total, counts: await counts() };
  });
  app.get("/adminapi/blog/:id", async (req, reply) => {
    if (!(await guard(req, reply))) return;
    const p = await byId(String(req.params.id));
    if (!p) return bad(reply, 404, "not-found");
    return adminJson(req, p);
  });
  app.post("/adminapi/blog", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    const b = req.body && typeof req.body === "object" ? req.body : {};
    const c = clean(b); if (c.error) return bad(reply, 400, c.error);
    const status = c.status ?? "draft";
    const publishedAt = status === "published" ? (c.publishedAt ?? new Date()) : (c.publishedAt ?? null);
    const slug = await uniqueSlug(c.slug ?? slugify(c.title));
    const id = crypto.randomUUID();
    await pool.query(`INSERT INTO blog_posts(id, slug, kind, title, summary, body, cover_url, tags, status, pinned, published_at, author_id) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)`,
      [id, slug, c.kind, c.title, c.summary ?? "", c.body ?? "", c.coverUrl ?? null, c.tags ?? [], status, c.pinned === true, publishedAt, uid]);
    await audit(uid, "blog.create", id, { title: c.title, status });
    return adminJson(req, await byId(id));
  });
  app.patch("/adminapi/blog/:id", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    const p = await byId(String(req.params.id));
    if (!p) return bad(reply, 404, "not-found");
    const b = req.body && typeof req.body === "object" ? req.body : {};
    const c = clean(b, { partial: true }); if (c.error) return bad(reply, 400, c.error);
    if (c.slug !== undefined && c.slug !== p.slug && (await slugExists(c.slug, p.id))) return bad(reply, 409, "slug-taken");
    const sets = [], args = [];
    const put = (col, v) => { args.push(v); sets.push(`${col}=$${args.length}`); };
    if (c.title !== undefined) put("title", c.title);
    if (c.kind !== undefined) put("kind", c.kind);
    if (c.summary !== undefined) put("summary", c.summary);
    if (c.body !== undefined) put("body", c.body);
    if (c.coverUrl !== undefined) put("cover_url", c.coverUrl);
    if (c.tags !== undefined) put("tags", c.tags);
    if (c.pinned !== undefined) put("pinned", c.pinned);
    if (c.slug !== undefined) put("slug", c.slug);
    if (c.status !== undefined) put("status", c.status);
    if (c.publishedAt !== undefined) put("published_at", c.publishedAt);
    // النشر بلا تاريخ = الآن
    if (c.status === "published" && c.publishedAt === undefined && !p.publishedAt) put("published_at", new Date());
    if (!sets.length) return adminJson(req, p);
    args.push(p.id);
    await pool.query(`UPDATE blog_posts SET ${sets.join(", ")}, updated_at=now() WHERE id=$${args.length}`, args);
    await audit(uid, "blog.update", p.id, { fields: Object.keys(c) });
    return adminJson(req, await byId(p.id));
  });
  app.post("/adminapi/blog/:id/publish", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    const p = await byId(String(req.params.id));
    if (!p) return bad(reply, 404, "not-found");
    const at = req.body?.publishedAt ? new Date(req.body.publishedAt) : new Date();
    if (Number.isNaN(at.getTime())) return bad(reply, 400, "bad-date");
    await pool.query("UPDATE blog_posts SET status='published', published_at=$2, updated_at=now() WHERE id=$1", [p.id, at]);
    await audit(uid, at.getTime() > Date.now() + 60e3 ? "blog.schedule" : "blog.publish", p.id, { title: p.title, at: at.toISOString() });
    return adminJson(req, await byId(p.id));
  });
  app.post("/adminapi/blog/:id/unpublish", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    const p = await byId(String(req.params.id));
    if (!p) return bad(reply, 404, "not-found");
    await pool.query("UPDATE blog_posts SET status='draft', updated_at=now() WHERE id=$1", [p.id]);
    await audit(uid, "blog.unpublish", p.id, { title: p.title });
    return adminJson(req, await byId(p.id));
  });
  app.post("/adminapi/blog/:id/pin", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    const p = await byId(String(req.params.id));
    if (!p) return bad(reply, 404, "not-found");
    const pinned = req.body?.pinned === true;
    await pool.query("UPDATE blog_posts SET pinned=$2, updated_at=now() WHERE id=$1", [p.id, pinned]);
    await audit(uid, pinned ? "blog.pin" : "blog.unpin", p.id, { title: p.title });
    return adminJson(req, await byId(p.id));
  });
  app.post("/adminapi/blog/:id/duplicate", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    const p = await byId(String(req.params.id));
    if (!p) return bad(reply, 404, "not-found");
    const id = crypto.randomUUID();
    const slug = await uniqueSlug(`${p.slug}-copy`.slice(0, 60));
    await pool.query(`INSERT INTO blog_posts(id, slug, kind, title, summary, body, cover_url, tags, status, pinned, published_at, author_id) VALUES($1,$2,$3,$4,$5,$6,$7,$8,'draft',false,NULL,$9)`,
      [id, slug, p.kind, `نسخة من ${p.title}`.slice(0, 160), p.summary, p.body, p.coverUrl, p.tags, uid]);
    await audit(uid, "blog.duplicate", id, { from: p.id });
    return adminJson(req, await byId(id));
  });
  app.post("/adminapi/blog/:id/preview", async (req, reply) => {
    if (!(await guard(req, reply))) return;
    const p = await byId(String(req.params.id));
    if (!p) return bad(reply, 404, "not-found");
    return { url: `${publicOrigin(req)}/blog/${p.slug}?key=${previewKey(p.id)}`, expiresInHours: 24 };
  });
  app.delete("/adminapi/blog/:id", async (req, reply) => {
    const uid = await guard(req, reply); if (!uid) return;
    const p = await byId(String(req.params.id));
    if (!p) return bad(reply, 404, "not-found");
    await pool.query("DELETE FROM blog_posts WHERE id=$1", [p.id]);
    previews.delete(p.id);
    await audit(uid, "blog.delete", p.id, { title: p.title, slug: p.slug });
    return { ok: true };
  });
}
