// معاينة الروابط في المحادثة (Naslife): الخادم يجلب عنوان الصفحة ووصفها وصورتها (Open Graph) نيابةً عن التطبيق، فلا يتصل
// جهاز المستخدم بالموقع الخارجي ولا يكشف عنوانه أو جلسته، وتُخزَّن النتيجة 24 ساعة في chat_link_previews (الفشل ساعة واحدة).
// الحدود: http(s) فقط إلى مضيف عام (الأسماء المحلية مرفوضة، وDNS يُحلّ ويُرفض أي عنوان خاص/حلقة/رابط محلي، ويُثبَّت العنوان
// المحلول عند الاتصال فلا ينفع تبديل DNS بين الفحص والاتصال)، 5 ثوانٍ للكل، 512 كيلوبايت، 3 تحويلات تُفحص كل قفزة منها،
// text/html فقط، و60 جلباً في الدقيقة لكل مستخدم. الأخطاء كلها {ok:false, reason} بلا 5xx.
// التسجيل: سطر في register.txt. أي خطأ في التهيئة يعطّل الإضافة بدل إسقاط الخادم.
import crypto from "node:crypto";
import dns from "node:dns/promises";
import http from "node:http";
import https from "node:https";
import net from "node:net";
import { Transform, pipeline } from "node:stream";

const MAX_BYTES = 512 * 1024;
const TIMEOUT_MS = 5000;
const MAX_REDIRECTS = 3;
const TTL_OK_MS = 24 * 3600 * 1000;
const TTL_FAIL_MS = 3600 * 1000;
const RATE_PER_MIN = 60;
const IMAGE_MAX_BYTES = 3 * 1024 * 1024;
const IMAGE_RATE_PER_MIN = 120;
const UA = "Mozilla/5.0 (compatible; NaslifeBot/1.0; +https://naslife.app)";

export default async function chatPreview(app, opts) {
  try {
    await setup(app, opts);
  } catch (e) {
    (app.log?.error ? app.log.error.bind(app.log) : console.error)(`chat_preview disabled: ${e?.stack || e}`);
  }
}

// ---- العناوين الخاصة: كل ما لا يجوز للخادم الاتصال به نيابةً عن مستخدم (SSRF)
function v4Private(ip) {
  const p = ip.split(".").map(Number);
  if (p.length !== 4 || p.some((x) => !Number.isInteger(x) || x < 0 || x > 255)) return true;
  const [a, b, c] = p;
  return a === 0 || a === 10 || a === 127 // هذه الشبكة، خاص، حلقة
    || (a === 100 && b >= 64 && b <= 127) // CGNAT
    || (a === 169 && b === 254) // رابط محلي (ومنه بيانات السحابة 169.254.169.254)
    || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) // خاص
    || (a === 192 && b === 0 && (c === 0 || c === 2)) || (a === 198 && (b === 18 || b === 19)) || (a === 198 && b === 51 && c === 100) || (a === 203 && b === 0 && c === 113) // محجوز/اختبار
    || a >= 224; // بث متعدد ومحجوز وبث
}

export function isPrivateIp(ip) {
  const s = String(ip ?? "").trim().toLowerCase().replace(/%.*$/, "");
  const fam = net.isIP(s);
  if (fam === 4) return v4Private(s);
  if (fam === 6) {
    if (s === "::1" || s === "::") return true;
    const mapped = /^(?:0*:)*ffff:(\d+\.\d+\.\d+\.\d+)$/.exec(s);
    if (mapped) return v4Private(mapped[1]);
    const mappedHex = /^(?:0*:)*ffff:([0-9a-f]{1,4}):([0-9a-f]{1,4})$/.exec(s);
    if (mappedHex) { const a = parseInt(mappedHex[1], 16), b = parseInt(mappedHex[2], 16); return v4Private(`${a >> 8}.${a & 255}.${b >> 8}.${b & 255}`); }
    if (s.startsWith("64:ff9b:") || s.startsWith("2002:")) return true; // NAT64 و6to4 يضمّنان IPv4 لا نفحصه فنرفضهما احتياطاً
    const first = parseInt(s.split(":")[0] || "0", 16) || 0;
    if (first === 0) return true; // ::/8 (متوافق مع IPv4 وغيره من المحجوز)
    if ((first & 0xfe00) === 0xfc00) return true; // fc00::/7 خاص
    if ((first & 0xffc0) === 0xfe80) return true; // fe80::/10 رابط محلي
    if ((first & 0xff00) === 0xff00) return true; // ff00::/8 بث متعدد
    return false;
  }
  return true; // ليس عنواناً أصلاً
}

/// سبب رفض المضيف قبل أي اتصال (بلا DNS)، أو null إن جاز المتابعة.
export function hostAllowed(hostname) {
  let h = String(hostname ?? "").toLowerCase().replace(/\.$/, "");
  if (h.startsWith("[") && h.endsWith("]")) h = h.slice(1, -1);
  if (!h) return "bad-url";
  if (net.isIP(h)) return isPrivateIp(h) ? "private-host" : null;
  if (h === "localhost" || /\.(localhost|local|internal|lan|home|intranet|corp|arpa|onion)$/.test(h)) return "private-host";
  if (!h.includes(".")) return "private-host"; // اسم بلا نطاق أعلى = شبكة داخلية
  return null;
}

// ---- فكّ كيانات HTML (&amp; &#39; &#x1F600; …) وتنظيف النص
const NAMED = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ", hellip: "…", mdash: "—", ndash: "–", laquo: "«", raquo: "»", copy: "©", reg: "®", trade: "™", lsquo: "‘", rsquo: "’", ldquo: "“", rdquo: "”", middot: "·", bull: "•", zwnj: "‌", zwj: "‍" };
export function decodeEntities(s) {
  return String(s ?? "").replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (all, e) => {
    if (e[0] === "#") {
      const cp = e[1].toLowerCase() === "x" ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
      return Number.isFinite(cp) && cp > 0 && cp <= 0x10ffff ? String.fromCodePoint(cp) : all;
    }
    return NAMED[e.toLowerCase()] ?? all;
  });
}
const clean = (s, max) => decodeEntities(s).replace(/\s+/g, " ").trim().slice(0, max);
const attr = (tag, name) => { const m = new RegExp(`\\s${name}\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s"'>]+))`, "i").exec(tag); return m ? (m[1] ?? m[2] ?? m[3] ?? "") : null; };

function decodeBody(buf, ctHeader) {
  let charset = /charset=["']?([\w-]+)/i.exec(ctHeader || "")?.[1];
  if (!charset) charset = /<meta[^>]+charset=["']?([\w-]+)/i.exec(buf.subarray(0, 4096).toString("latin1"))?.[1];
  try { return new TextDecoder((charset || "utf-8").toLowerCase()).decode(buf); } catch { return buf.toString("utf8"); }
}

/// يستخرج og:title/og:description/og:image/og:site_name مع <title> و<meta name=description> احتياطاً؛ الصورة تُحوَّل إلى رابط مطلق http(s).
export function parsePreview(buf, ctHeader, finalUrl) {
  const html = decodeBody(buf, ctHeader);
  const headEnd = html.search(/<\/head\s*>/i);
  const head = headEnd > 0 ? html.slice(0, headEnd) : html;
  const metas = {};
  for (const tag of head.match(/<meta\b[^>]*>/gi) ?? []) {
    const key = (attr(tag, "property") || attr(tag, "name") || attr(tag, "itemprop") || "").toLowerCase();
    const content = attr(tag, "content");
    if (key && content != null && !(key in metas)) metas[key] = content;
  }
  const title = clean(metas["og:title"] || metas["twitter:title"] || (/<title[^>]*>([\s\S]*?)<\/title>/i.exec(head)?.[1] ?? ""), 200);
  if (!title) return { ok: false, reason: "no-title" };
  const description = clean(metas["og:description"] || metas["twitter:description"] || metas["description"] || "", 300);
  let image = "";
  const rawImage = (metas["og:image"] || metas["og:image:secure_url"] || metas["og:image:url"] || metas["twitter:image"] || metas["twitter:image:src"] || "").trim();
  if (rawImage) { try { const iu = new URL(decodeEntities(rawImage), finalUrl); if (iu.protocol === "http:" || iu.protocol === "https:") image = iu.href.slice(0, 2048); } catch { /* صورة غير صالحة تُهمل */ } }
  let site = clean(metas["og:site_name"] || "", 80);
  if (!site) { try { site = new URL(finalUrl).hostname.replace(/^www\./, ""); } catch { site = ""; } }
  return { ok: true, title, description, image, site, finalUrl };
}

// ---- الجلب بعنوان مثبّت: lookup مخصّص يحلّ الاسم ويرفض أي عنوان خاص، ويعيد العنوان نفسه الذي سيتصل به net
// resolve قابل للحقن في الاختبارات فقط (اسم عام يحلّ إلى عنوان خاص = هجوم إعادة ربط DNS يجب رفضه هنا)
function makeLookup(allowPrivate, resolve = (h) => dns.lookup(h, { all: true, verbatim: true })) {
  return (hostname, options, cb) => {
    if (typeof options === "function") { cb = options; options = {}; }
    Promise.resolve().then(() => resolve(hostname)).then((addrs) => {
      if (!addrs?.length) return cb(Object.assign(new Error("dns"), { code: "ENOTFOUND" }));
      if (!allowPrivate && addrs.some((a) => isPrivateIp(a.address))) return cb(Object.assign(new Error("private-host"), { code: "EPRIVATE" }));
      if (options?.all) return cb(null, addrs);
      cb(null, addrs[0].address, addrs[0].family);
    }).catch((e) => cb(Object.assign(e instanceof Error ? e : new Error(String(e)), { code: e?.code || "ENOTFOUND" })));
  };
}

function fetchOnce(urlStr, { deadline, maxBytes, lookup }) {
  return new Promise((resolve, reject) => {
    const u = new URL(urlStr);
    const mod = u.protocol === "https:" ? https : http;
    const remaining = deadline - Date.now();
    if (remaining <= 0) return reject(Object.assign(new Error("timeout"), { code: "ETIMEDOUT" }));
    let done = false;
    const finish = (v) => { if (!done) { done = true; clearTimeout(timer); resolve(v); } };
    const fail = (e) => { if (!done) { done = true; clearTimeout(timer); reject(e); } };
    const req = mod.request(u, { method: "GET", lookup, headers: { "user-agent": UA, accept: "text/html,application/xhtml+xml;q=0.9,*/*;q=0.1", "accept-language": "ar,en;q=0.8" } }, (res) => {
      const status = res.statusCode || 0, headers = res.headers;
      if (status >= 300 && status < 400 && headers.location) { res.resume(); return finish({ status, headers, body: null }); }
      if (status !== 200) { res.resume(); return finish({ status, headers, body: null }); }
      const ct = String(headers["content-type"] || "").split(";")[0].trim().toLowerCase();
      if (ct !== "text/html" && ct !== "application/xhtml+xml") { finish({ status, headers, body: null, notHtml: true }); req.destroy(); return; }
      const chunks = []; let size = 0;
      const end = () => finish({ status, headers, body: Buffer.concat(chunks).subarray(0, maxBytes) });
      res.on("data", (c) => { chunks.push(c); size += c.length; if (size >= maxBytes) { end(); req.destroy(); } });
      res.on("end", end);
      res.on("error", end); // ما وصل يكفي
    });
    const timer = setTimeout(() => { fail(Object.assign(new Error("timeout"), { code: "ETIMEDOUT" })); req.destroy(); }, remaining);
    req.on("error", fail);
    req.end();
  });
}

async function setup(app, opts) {
  const { pool, auth } = opts;
  if (!pool || !auth) throw new Error("chat_preview: pool and auth are required");
  // allowPrivate للاختبارات فقط (خادم محلي)؛ لا يُفعَّل في الإنتاج
  const allowPrivate = opts.allowPrivate === true || process.env.CHAT_PREVIEW_ALLOW_PRIVATE === "1";
  const timeoutMs = Number(opts.timeoutMs) || TIMEOUT_MS;
  const maxBytes = Number(opts.maxBytes) || MAX_BYTES;
  const lookup = makeLookup(allowPrivate, typeof opts.resolve === "function" ? opts.resolve : undefined);
  await pool.query(`CREATE TABLE IF NOT EXISTS chat_link_previews (url_hash TEXT PRIMARY KEY, url TEXT NOT NULL, data JSONB NOT NULL, fetched_at TIMESTAMPTZ NOT NULL DEFAULT now())`);
  const logger = app.log?.info ? app.log.info.bind(app.log) : console.log;
  const fail = (reason) => ({ ok: false, reason });

  async function fetchPreview(startUrl) {
    const deadline = Date.now() + timeoutMs;
    let current = startUrl;
    for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
      let cu;
      try { cu = new URL(current); } catch { return fail("bad-url"); }
      if ((cu.protocol !== "http:" && cu.protocol !== "https:") || cu.username || cu.password) return fail("bad-url");
      const why = allowPrivate ? null : hostAllowed(cu.hostname);
      if (why) return fail(why);
      let res;
      try { res = await fetchOnce(cu.href, { deadline, maxBytes, lookup }); }
      catch (e) {
        const code = e?.code || "";
        return fail(code === "EPRIVATE" ? "private-host" : code === "ETIMEDOUT" ? "timeout" : code === "ENOTFOUND" || code === "EAI_AGAIN" ? "dns" : "fetch-failed");
      }
      if (res.status >= 300 && res.status < 400 && res.headers.location) {
        if (hop === MAX_REDIRECTS) return fail("too-many-redirects");
        try { current = new URL(String(res.headers.location), cu.href).href; } catch { return fail("bad-redirect"); }
        continue;
      }
      if (res.notHtml) return fail("not-html");
      if (res.status !== 200) return fail(`http-${res.status}`);
      try { return parsePreview(res.body, res.headers["content-type"], cu.href); } catch { return fail("parse-failed"); }
    }
    return fail("too-many-redirects");
  }

  // ---- الذاكرة: sha256 للرابط (بلا الجزء #) مفتاحاً، 24 ساعة للنجاح وساعة للفشل
  const hashOf = (url) => crypto.createHash("sha256").update(url).digest("hex");
  async function cached(url) {
    const r = (await pool.query("SELECT data, fetched_at FROM chat_link_previews WHERE url_hash=$1", [hashOf(url)])).rows[0];
    if (!r || !r.data || typeof r.data !== "object") return null;
    const age = Date.now() - new Date(r.fetched_at).getTime();
    if (!(age < (r.data.ok ? TTL_OK_MS : TTL_FAIL_MS))) return null;
    return { ...r.data, url, cachedAt: new Date(r.fetched_at).toISOString() };
  }
  const store = (url, data) => pool.query(
    "INSERT INTO chat_link_previews(url_hash,url,data,fetched_at) VALUES($1,$2,$3,now()) ON CONFLICT (url_hash) DO UPDATE SET url=EXCLUDED.url, data=EXCLUDED.data, fetched_at=now()",
    [hashOf(url), url, data]).catch((e) => logger(`chat_preview: cache write failed: ${e?.message || e}`));
  const inflight = new Map();
  function resolveUrl(url) {
    if (inflight.has(url)) return inflight.get(url);
    const job = (async () => {
      try { const data = await fetchPreview(url); await store(url, data); return data; }
      finally { inflight.delete(url); }
    })();
    inflight.set(url, job);
    return job;
  }

  // ---- حدّ المعدل في الذاكرة: 60 جلباً حقيقياً في الدقيقة لكل مستخدم (الإصابات من الذاكرة لا تُحسب)، و120 صورة في الدقيقة لكل عنوان IP
  const rate = new Map(), imgRate = new Map();
  function limitedBy(map, key, max) {
    const now = Date.now();
    if (map.size > 5000) for (const [k, v] of map) if (now - v.at >= 60000) map.delete(k);
    const r = map.get(key);
    if (!r || now - r.at >= 60000) { map.set(key, { n: 1, at: now }); return false; }
    r.n++;
    return r.n > max;
  }
  const limited = (uid) => limitedBy(rate, uid, RATE_PER_MIN);
  // خلف Caddy يصل req.ip دائماً 127.0.0.1 (النواة لا تضبط trustProxy) فالعنوان الحقيقي أول عنصر في x-forwarded-for، كما في
  // account_delete.js وauth_alias.js؛ بدونه (اختبار أو اتصال مباشر) يُستخدم req.ip
  const ipOf = (req) => String(req.headers["x-forwarded-for"] ?? req.ip ?? "").split(",")[0].trim() || "?";

  // ---- فتح تدفّق (للصور): القواعد نفسها (مضيف عام، عنوان مثبّت، مهلة، 3 تحويلات) لكن الجسم يُمرَّر كما هو بلا تخزين
  async function openStream(startUrl) {
    const deadline = Date.now() + timeoutMs;
    let current = startUrl;
    for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
      const cu = new URL(current);
      if ((cu.protocol !== "http:" && cu.protocol !== "https:") || cu.username || cu.password || (!allowPrivate && hostAllowed(cu.hostname))) throw new Error("refused");
      const r = await new Promise((resolve, reject) => {
        const mod = cu.protocol === "https:" ? https : http;
        const remaining = deadline - Date.now();
        if (remaining <= 0) return reject(new Error("timeout"));
        const req = mod.request(cu, { method: "GET", lookup, headers: { "user-agent": UA, accept: "image/*,*/*;q=0.5" } }, (res) => { clearTimeout(timer); resolve({ status: res.statusCode || 0, headers: res.headers, res }); });
        const timer = setTimeout(() => req.destroy(new Error("timeout")), remaining);
        req.on("error", (e) => { clearTimeout(timer); reject(e); });
        req.end();
      });
      if (r.status >= 300 && r.status < 400 && r.headers.location) {
        r.res.resume();
        if (hop === MAX_REDIRECTS) throw new Error("redirects");
        current = new URL(String(r.headers.location), cu.href).href;
        continue;
      }
      r.res.setTimeout(timeoutMs, () => r.res.destroy()); // تعثّر الجسم بعد الترويسات لا يعلّق الطلب
      return r;
    }
    throw new Error("redirects");
  }

  const normalize = (raw) => {
    if (!raw || raw.length > 2048) return null;
    let u;
    try { u = new URL(raw); } catch { return null; }
    if ((u.protocol !== "http:" && u.protocol !== "https:") || u.username || u.password) return null;
    u.hash = "";
    return u;
  };

  app.get("/chat/preview/status", async () => {
    let n = 0;
    try { n = Number((await pool.query("SELECT count(*)::int AS n FROM chat_link_previews")).rows[0]?.n ?? 0); } catch { n = 0; }
    return { ok: true, cached: n, maxBytes, timeoutMs, maxRedirects: MAX_REDIRECTS, ttlHours: TTL_OK_MS / 3600000, ratePerMin: RATE_PER_MIN };
  });

  app.get("/chat/preview", async (req, reply) => {
    const uid = await auth(req); if (!uid) return reply.code(401).send({ error: "auth" });
    const u = normalize(String(req.query?.url ?? "").trim());
    if (!u) return fail("bad-url");
    // رفض المضيفين المحليين قبل الذاكرة حتى لا يعيد المسار نتيجة خُزِّنت بإعداد اختبار
    const why = allowPrivate ? null : hostAllowed(u.hostname);
    if (why) return fail(why);
    const url = u.href;
    try {
      const hit = await cached(url);
      if (hit) return hit;
    } catch (e) { logger(`chat_preview: cache read failed: ${e?.message || e}`); }
    if (limited(uid)) return reply.code(429).send({ ok: false, reason: "rate-limited" });
    try {
      const data = await resolveUrl(url);
      return { ...data, url, cachedAt: new Date().toISOString() };
    } catch (e) {
      logger(`chat_preview: ${url}: ${e?.message || e}`);
      return fail("fetch-failed");
    }
  });

  // ---- وكيل صور المعاينة: Caddy يفرض img-src 'self' فلا يحمّل المتصفح صورة من مضيف خارجي، وتُقدَّم من هنا بالقواعد نفسها
  // (مضيف عام بعنوان مثبّت، مهلة، 3 ميغابايت، image/* فقط) ولصور اكتشفتها معاينة مخزَّنة فقط (ليس وكيلاً مفتوحاً).
  // بلا مصادقة لأن <img> لا يحمل رمز الجلسة؛ حدّ 120 في الدقيقة لكل IP (أول x-forwarded-for خلف Caddy). الجهاز لا يتصل بالموقع الخارجي أبداً.
  await pool.query("CREATE INDEX IF NOT EXISTS chat_link_previews_image ON chat_link_previews ((data->>'image'))");
  app.get("/chat/preview/image", async (req, reply) => {
    const u = normalize(String(req.query?.u ?? "").trim());
    if (!u || (!allowPrivate && hostAllowed(u.hostname))) return reply.code(404).send({ error: "not-found" });
    let known = false;
    try { known = (await pool.query("SELECT 1 FROM chat_link_previews WHERE data->>'image' = $1 LIMIT 1", [u.href])).rowCount > 0; } catch { known = false; }
    if (!known) return reply.code(404).send({ error: "not-found" });
    if (limitedBy(imgRate, ipOf(req), IMAGE_RATE_PER_MIN)) return reply.code(429).send({ error: "rate-limited" });
    let r;
    try { r = await openStream(u.href); } catch { return reply.code(404).send({ error: "fetch-failed" }); }
    const ct = String(r.headers["content-type"] || "").split(";")[0].trim().toLowerCase();
    const len = Number(r.headers["content-length"] || 0);
    if (r.status !== 200) { r.res.destroy(); return reply.code(404).send({ error: `http-${r.status}` }); }
    if (!ct.startsWith("image/")) { r.res.destroy(); return reply.code(415).send({ error: "not-image" }); }
    if (len > IMAGE_MAX_BYTES) { r.res.destroy(); return reply.code(413).send({ error: "too-large" }); }
    reply.header("content-type", ct).header("cache-control", "public, max-age=86400").header("x-content-type-options", "nosniff");
    if (len) reply.header("content-length", len);
    // العدّ داخل التدفّق المُرسَل لا بمستمع data على المصدر: المستمع يجعل المصدر يتدفّق قبل أن يربطه Fastify بالرد، ومع أي
    // onSend غير متزامن في النواة تضيع البايتات الأولى. pipeline يُسقط المصدر عند تجاوز الحدّ أو انقطاع العميل (fastify يدمّر guard).
    let size = 0;
    const guard = new Transform({ transform(c, _enc, cb) { size += c.length; if (size > IMAGE_MAX_BYTES) cb(new Error("too-large")); else cb(null, c); } });
    pipeline(r.res, guard, (e) => { if (e && e.message === "too-large") logger(`chat_preview: image ${u.href} cut at ${IMAGE_MAX_BYTES} bytes`); });
    return reply.send(guard);
  });

  globalThis.naslifeLinkPreview = { fetch: fetchPreview, isPrivateIp, hostAllowed, decodeEntities, parsePreview };
  logger(`chat_preview: ready (timeout ${timeoutMs} ms, ${Math.round(maxBytes / 1024)} KB, ${MAX_REDIRECTS} redirects${allowPrivate ? ", PRIVATE HOSTS ALLOWED (test only)" : ""})`);
}
