// مدونة ناس لايف العامة على /blog: صفحات HTML تُبنى في الخادم (لا تحتاج تطبيق Flutter) بتصميم التطبيق نفسه،
// تعرض التحديثات والأخبار والتدوينات من server/blog_posts.js مع وسوم Open Graph لكل منشور وخلاصتَي JSON وRSS.
// المسارات: /blog (القائمة، مع ?kind=update|news|post)، /blog/<slug> (منشور)، /blog/feed.json، /blog/rss.xml، /blog/status.
// التسجيل في register.txt: await app.register((await import("./blog.js")).default);
import { BLOG_POSTS } from "./blog_posts.js";

const SITE = "ناس لايف";
const KINDS = {
  update: { label: "تحديث", cls: "k-update", plural: "تحديثات" },
  news: { label: "خبر", cls: "k-news", plural: "أخبار" },
  post: { label: "تدوينة", cls: "k-post", plural: "تدوينات" },
};
const MONTHS = ["يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو", "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر"];
const SLUG_RE = /^[a-z0-9][a-z0-9-]{0,63}$/;

export const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
export const fmtDate = (d) => { const [y, m, day] = String(d).split("-").map(Number); return m >= 1 && m <= 12 ? `${day} ${MONTHS[m - 1]} ${y}` : String(d); };
const safeUrl = (u) => (/^(https?:\/\/|\/)/i.test(String(u ?? "").trim()) ? String(u).trim() : null);

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
.meta{display:flex;align-items:center;gap:10px;font-size:13px;color:var(--muted)}
.kind{font-size:12px;font-weight:700;padding:2px 10px;border-radius:999px}
.k-update{background:var(--accent-soft);color:var(--accent)}
.k-news{background:var(--coral-soft);color:var(--coral)}
.k-post{background:var(--sun-soft);color:var(--sun)}
.card h2{font-family:'Baloo','Rubik',sans-serif;font-weight:700;font-size:21px;line-height:1.3;margin:0;text-wrap:balance}
.card h2 a{color:var(--text);text-decoration:none}
.card p{margin:0;color:var(--muted)}
.more{font-size:14px;font-weight:600;text-decoration:none}
article.post header{display:flex;flex-direction:column;gap:6px;margin-bottom:16px}
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

export default async function blog(app) {
  const posts = () => [...BLOG_POSTS].filter((p) => p && p.slug && p.title).sort((a, b) => String(b.date).localeCompare(String(a.date)) || (b.order ?? 0) - (a.order ?? 0));
  const publicOrigin = (req) => {
    const env = String(process.env.PUBLIC_BASE_URL ?? process.env.NASLIFE_PUBLIC_URL ?? "").trim().replace(/\/+$/, "");
    if (/^https?:\/\//i.test(env)) return env;
    const proto = String(req.headers["x-forwarded-proto"] ?? "https").split(",")[0].trim() || "https";
    const host = String(req.headers["x-forwarded-host"] ?? req.headers.host ?? "naslife.app").split(",")[0].trim().replace(/^www\./i, "");
    return `${proto}://${host}`;
  };
  const kindBadge = (k) => { const d = KINDS[k] ?? KINDS.update; return `<span class="kind ${d.cls}">${d.label}</span>`; };
  const page = ({ title, description, url, image, body, ogType = "website", extraHead = "" }) => `<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<meta name="description" content="${esc(description)}">
<meta property="og:site_name" content="${esc(SITE)}">
<meta property="og:type" content="${esc(ogType)}">
<meta property="og:title" content="${esc(title)}">
<meta property="og:description" content="${esc(description)}">
<meta property="og:url" content="${esc(url)}">
${image ? `<meta property="og:image" content="${esc(image)}">` : ""}
<meta name="twitter:card" content="summary">
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
  const send = (reply, html, code = 200) => reply.code(code).type("text/html; charset=utf-8").header("cache-control", "public, max-age=300").send(html);

  function listPage(req, kind) {
    const origin = publicOrigin(req);
    const all = posts();
    const list = kind ? all.filter((p) => p.kind === kind) : all;
    const filters = [["", "الكل"], ...Object.entries(KINDS).map(([k, d]) => [k, d.plural])]
      .map(([k, l]) => `<a class="${(kind ?? "") === k ? "on" : ""}" href="/blog${k ? `?kind=${k}` : ""}">${l}</a>`).join("");
    const cards = list.map((p) => `<article class="card">
<div class="meta">${kindBadge(p.kind)}<time datetime="${esc(p.date)}">${esc(fmtDate(p.date))}</time></div>
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

  function postPage(req, p) {
    const origin = publicOrigin(req);
    const url = `${origin}/blog/${p.slug}`;
    const all = posts();
    const i = all.findIndex((x) => x.slug === p.slug);
    const newer = i > 0 ? all[i - 1] : null, older = i >= 0 && i < all.length - 1 ? all[i + 1] : null;
    const text = encodeURIComponent(`${p.title} · ناس لايف`);
    const body = `<article class="post">
<header>
<div class="meta">${kindBadge(p.kind)}<time datetime="${esc(p.date)}">${esc(fmtDate(p.date))}</time></div>
<h1>${esc(p.title)}</h1>
</header>
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
    const ld = `<script type="application/ld+json">${JSON.stringify({ "@context": "https://schema.org", "@type": p.kind === "news" ? "NewsArticle" : "BlogPosting", headline: p.title, datePublished: p.date, inLanguage: "ar", url, publisher: { "@type": "Organization", name: SITE } })}</script>`;
    return page({ title: `${p.title} · ${SITE}`, description: p.summary || p.title, url, body, ogType: "article", extraHead: ld });
  }

  const notFound = (req, reply) => send(reply, page({ title: `غير موجود · ${SITE}`, description: "المنشور غير موجود", url: `${publicOrigin(req)}/blog`, body: `<h1>المنشور غير موجود</h1><p class="lead">ربما تغيّر رابطه أو حُذف.</p><p><a href="/blog">← كل التحديثات</a></p>` }), 404);

  app.get("/blog", async (req, reply) => {
    const k = String(req.query?.kind ?? "").trim();
    return send(reply, listPage(req, KINDS[k] ? k : null));
  });
  app.get("/blog/", async (req, reply) => reply.redirect(`/blog${req.query?.kind ? `?kind=${encodeURIComponent(String(req.query.kind))}` : ""}`, 301));
  app.get("/blog/feed.json", async (req, reply) => {
    const origin = publicOrigin(req);
    return reply.type("application/feed+json; charset=utf-8").header("cache-control", "public, max-age=300").send({
      version: "https://jsonfeed.org/version/1.1", title: `مدونة ${SITE}`, home_page_url: `${origin}/blog`, feed_url: `${origin}/blog/feed.json`, language: "ar",
      items: posts().map((p) => ({ id: `${origin}/blog/${p.slug}`, url: `${origin}/blog/${p.slug}`, title: p.title, summary: p.summary || "", date_published: `${p.date}T09:00:00+03:00`, tags: [KINDS[p.kind]?.label ?? p.kind], content_html: markupHtml(p.body) })),
    });
  });
  app.get("/blog/rss.xml", async (req, reply) => {
    const origin = publicOrigin(req);
    const items = posts().map((p) => `<item><title>${esc(p.title)}</title><link>${origin}/blog/${esc(p.slug)}</link><guid isPermaLink="true">${origin}/blog/${esc(p.slug)}</guid><pubDate>${new Date(`${p.date}T09:00:00+03:00`).toUTCString()}</pubDate><category>${esc(KINDS[p.kind]?.label ?? p.kind)}</category><description><![CDATA[${markupHtml(p.body).replace(/]]>/g, "]]]]><![CDATA[>")}]]></description></item>`).join("\n");
    const xml = `<?xml version="1.0" encoding="UTF-8"?>\n<rss version="2.0"><channel><title>مدونة ${esc(SITE)}</title><link>${origin}/blog</link><description>تحديثات وأخبار وتدوينات ناس لايف</description><language>ar</language>\n${items}\n</channel></rss>`;
    return reply.type("application/rss+xml; charset=utf-8").header("cache-control", "public, max-age=300").send(xml);
  });
  app.get("/blog/status", async () => ({ ok: true, posts: BLOG_POSTS.length, latest: posts()[0]?.slug ?? null, kinds: Object.keys(KINDS) }));
  app.get("/blog/:slug", async (req, reply) => {
    const slug = String(req.params.slug ?? "");
    const p = SLUG_RE.test(slug) ? posts().find((x) => x.slug === slug) : null;
    if (!p) return notFound(req, reply);
    return send(reply, postPage(req, p));
  });
}
