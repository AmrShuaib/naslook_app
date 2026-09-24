// الصفحات القانونية العامة لناس لايف وسجل موافقة المستخدمين عليها.
// الصفحات: /privacy (سياسة الخصوصية)، /terms (شروط الاستخدام)، /support (الدعم وحذف الحساب)، و/legal يحوّل إلى /privacy.
// صفحات HTML تُبنى في الخادم بلا أي سكربت: ترويسة CSP العامة في Caddy تمنع السكربتات المضمّنة (server/restore-caddy.sh).
// الموافقة: GET /legal/version، GET /legal/consent (هل يلزم المستخدم أن يوافق على النسخة الحالية)، POST /legal/consent.
// الإضافات الأخرى تسجّل الموافقة عبر globalThis.naslifeLegalConsent(uid, source) (التسجيل في auth_alias.js).
// التسجيل في register.txt: await app.register((await import("./legal_pages.js")).default, { pool, auth });
import { LEGAL_VERSION, privacyBody, termsBody, supportBody } from "./legal_content.js";

const DOCS = ["terms", "privacy"];
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

// نفس ألوان المدونة والتطبيق، مع وضع داكن؛ الخطوط من أصول التطبيق نفسه
const CSS = `
:root{--bg:#FFFFFF;--surface:#F2F2F7;--line:#E5E5EA;--text:#111111;--muted:#6B7280;--accent:#0A6E78;--accent-soft:#E0F3F4;--accent-on:#FFFFFF;--warn:#BF3A1E;--warn-soft:#FDEBE6}
@media (prefers-color-scheme:dark){:root{--bg:#121417;--surface:#1C2024;--line:#2A3036;--text:#F2F2F2;--muted:#9AA3AD;--accent:#4FB3BC;--accent-soft:#163338;--accent-on:#0B1416;--warn:#FF8A6B;--warn-soft:#3A1F17}}
@font-face{font-family:'Rubik';font-weight:500;src:url('/assets/fonts/Rubik-Medium.ttf') format('truetype');font-display:swap}
@font-face{font-family:'Rubik';font-weight:700;src:url('/assets/fonts/Rubik-Bold.ttf') format('truetype');font-display:swap}
@font-face{font-family:'Baloo';font-weight:700;src:url('/assets/fonts/BalooBhaijaan2-Bold.ttf') format('truetype');font-display:swap}
*{box-sizing:border-box}
html{direction:rtl}
body{margin:0;background:var(--bg);color:var(--text);font-family:'Rubik','Segoe UI',Tahoma,sans-serif;font-weight:500;line-height:1.8;font-size:16px;-webkit-text-size-adjust:100%}
a{color:var(--accent)}
.top{position:sticky;top:0;z-index:2;background:var(--bg);border-bottom:1px solid var(--line)}
.top .in{max-width:760px;margin:0 auto;padding:10px 16px;display:flex;align-items:center;gap:14px}
.brand{display:flex;align-items:center;gap:8px;text-decoration:none;color:var(--text);font-family:'Baloo','Rubik',sans-serif;font-weight:700;font-size:21px}
.brand img{width:30px;height:30px;border-radius:9px}
nav.docs{margin-inline-start:auto;display:flex;gap:6px;flex-wrap:wrap}
nav.docs a{text-decoration:none;font-size:13px;font-weight:700;padding:5px 11px;border-radius:999px;border:1px solid var(--line);color:var(--text)}
nav.docs a.on{background:var(--accent);border-color:var(--accent);color:var(--accent-on)}
main{max-width:760px;margin:0 auto;padding:22px 16px 60px}
h1{font-family:'Baloo','Rubik',sans-serif;font-weight:700;font-size:30px;line-height:1.3;margin:0 0 4px}
h2{font-family:'Baloo','Rubik',sans-serif;font-weight:700;font-size:21px;line-height:1.35;margin:26px 0 6px}
.lead{color:var(--muted);margin:0 0 16px;font-size:14px}
p{margin:0 0 12px}
ul,ol{margin:0 0 14px;padding-inline-start:22px}
li{margin:3px 0}
li::marker{color:var(--accent);font-weight:700}
.tbl{overflow-x:auto;margin:0 0 14px}
table{border-collapse:collapse;width:100%;font-size:14px;line-height:1.6}
th,td{border:1px solid var(--line);padding:8px 10px;vertical-align:top;text-align:start}
th{background:var(--accent-soft);color:var(--accent)}
.strong-note{background:var(--warn-soft);color:var(--warn);border-radius:12px;padding:10px 14px}
section#en{margin-top:40px;padding-top:20px;border-top:2px solid var(--line);direction:ltr;text-align:left}
footer{max-width:760px;margin:0 auto;padding:18px 16px 40px;color:var(--muted);font-size:13px;display:flex;gap:14px;flex-wrap:wrap;border-top:1px solid var(--line)}
footer a{color:var(--muted)}
`;

export default async function legalPages(app, opts = {}) {
  const pool = opts.pool ?? globalThis.naslifePool ?? null;
  const auth = opts.auth ?? globalThis.naslifeAuth ?? null;
  let dbOk = false;
  if (pool) {
    try {
      await pool.query(`CREATE TABLE IF NOT EXISTS legal_consents (user_id TEXT NOT NULL, doc TEXT NOT NULL, version TEXT NOT NULL, source TEXT NOT NULL DEFAULT 'app',
        accepted_at TIMESTAMPTZ NOT NULL DEFAULT now(), PRIMARY KEY (user_id, doc, version))`);
      dbOk = true;
    } catch (e) { app.log?.warn?.({ err: e }, "legal_pages: consents table unavailable"); }
  }
  const settings = () => globalThis.naslifeSettings ?? {};
  const supportEmail = () => { const e = String(settings().supportEmail ?? "").trim(); return /^[^\s@<>"']+@[^\s@<>"']+\.[a-z]{2,}$/i.test(e) ? e : "support@naslife.app"; };
  const supportHandle = () => String(settings().supportHandle ?? "").trim().replace(/^@/, "").replace(/[^a-z0-9_]/gi, "").slice(0, 25);

  const page = (key, title, body) => `<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)} · ناس لايف</title>
<meta name="description" content="${esc(title)} لتطبيق ناس لايف">
<link rel="canonical" href="https://naslife.app/${key}">
<link rel="icon" type="image/png" href="/favicon.png">
<style>${CSS}</style>
</head>
<body>
<div class="top"><div class="in"><a class="brand" href="/"><img src="/icons/Icon-192.png" alt=""><span>ناس لايف</span></a>
<nav class="docs"><a href="/privacy"${key === "privacy" ? ' class="on"' : ""}>الخصوصية</a><a href="/terms"${key === "terms" ? ' class="on"' : ""}>الشروط</a><a href="/support"${key === "support" ? ' class="on"' : ""}>الدعم</a></nav></div></div>
<main>
${body}
</main>
<footer><span>© ${new Date().getFullYear()} شركة أريب الرقمية · Areeb Digital</span><a href="/privacy">سياسة الخصوصية</a><a href="/terms">شروط الاستخدام</a><a href="/support">الدعم</a><a href="/">naslife.app</a></footer>
</body>
</html>`;
  const send = (reply, html) => reply.type("text/html; charset=utf-8").header("cache-control", "public, max-age=300").send(html);

  app.get("/privacy", async (req, reply) => send(reply, page("privacy", "سياسة الخصوصية", privacyBody({ supportEmail: supportEmail() }))));
  app.get("/terms", async (req, reply) => send(reply, page("terms", "شروط الاستخدام", termsBody({ supportEmail: supportEmail() }))));
  app.get("/support", async (req, reply) => send(reply, page("support", "الدعم والمساعدة", supportBody({ supportEmail: supportEmail(), supportHandle: supportHandle() }))));
  app.get("/legal", async (req, reply) => reply.redirect("/privacy", 301));
  app.get("/legal/version", async () => ({ version: LEGAL_VERSION, docs: DOCS, supportEmail: supportEmail(), urls: { privacy: "https://naslife.app/privacy", terms: "https://naslife.app/terms", support: "https://naslife.app/support" } }));

  /// تسجيل موافقة مستخدم على النسخة الحالية من الوثيقتين (لا تُفشل أبداً الطلب الذي يستدعيها).
  const record = async (uid, source = "app") => {
    if (!dbOk || !uid) return false;
    try {
      for (const doc of DOCS) await pool.query("INSERT INTO legal_consents(user_id, doc, version, source) VALUES($1,$2,$3,$4) ON CONFLICT DO NOTHING", [uid, doc, LEGAL_VERSION, String(source).slice(0, 20)]);
      return true;
    } catch { return false; }
  };
  globalThis.naslifeLegalConsent = record;

  const me = async (req, reply) => { const uid = auth ? await auth(req) : null; if (!uid) { reply.code(401).send({ error: "auth" }); return null; } return uid; };
  app.get("/legal/consent", async (req, reply) => {
    const uid = await me(req, reply); if (!uid) return;
    if (!dbOk) return { needs: false, version: LEGAL_VERSION };
    const n = (await pool.query("SELECT count(DISTINCT doc)::int AS n FROM legal_consents WHERE user_id=$1 AND version=$2", [uid, LEGAL_VERSION])).rows[0]?.n ?? 0;
    return { needs: n < DOCS.length, version: LEGAL_VERSION };
  });
  app.post("/legal/consent", async (req, reply) => {
    const uid = await me(req, reply); if (!uid) return;
    const v = String(req.body?.version ?? LEGAL_VERSION);
    if (v !== LEGAL_VERSION) return reply.code(409).send({ error: "stale-version", version: LEGAL_VERSION });
    const src = ["app", "ios", "android", "web"].includes(req.body?.source) ? req.body.source : "app";
    const ok = await record(uid, src);
    return { ok, version: LEGAL_VERSION };
  });
}
