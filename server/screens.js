// «معرض التصاميم» (server/screens.js): صفحة خاصة على /screens تجمع نماذج التصميم التي يناقشها المالك، كل نسخة في تبويب،
// ولا تُفتح إلا برقم سري يعطيه المالك لمن يشاركه الرابط. الرقم يضبطه المدير من /screens/admin (لا يُكتب في المستودع ولا يُعاد)،
// ويُخزَّن مجزّأً (scrypt). الدخول يضع كعكة موقّعة لسبعة أيام تسقط تلقائياً عند تغيير الرقم. المحاولات الخاطئة محدودة لكل عنوان.
// سياسة الأمان في Caddy تمنع السكربتات المضمّنة، فكود كل صفحة يُقدَّم ملفاً مستقلاً من /screens/js/.
// المحتوى في server/screens_data.js يولّده tools/dev/build_screens.mjs من docs/reports/screens/.
// التسجيل في register.txt:
//   await app.register((await import("./screens.js")).default, { pool, auth });
import crypto from "node:crypto";

export const PIN_RE = /^[0-9]{6,12}$/;
export const MAX_FAILS = 8, FAIL_WINDOW_MS = 15 * 60 * 1000, SESSION_DAYS = 7, COOKIE = "ns_screens";

const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const latinDigits = (s) => String(s ?? "").replace(/[٠-٩]/g, (d) => String("٠١٢٣٤٥٦٧٨٩".indexOf(d))).replace(/[۰-۹]/g, (d) => String("۰۱۲۳۴۵۶۷۸۹".indexOf(d))).trim();
const scrypt = (pin, salt) => new Promise((res, rej) => crypto.scrypt(pin, salt, 32, (e, k) => (e ? rej(e) : res(k.toString("hex")))));

const SHELL_CSS = `
@font-face{font-family:'Rubik';font-weight:400;src:url('/assets/fonts/Rubik-Regular.ttf') format('truetype')}
@font-face{font-family:'Rubik';font-weight:500;src:url('/assets/fonts/Rubik-Medium.ttf') format('truetype')}
@font-face{font-family:'Rubik';font-weight:700;src:url('/assets/fonts/Rubik-Bold.ttf') format('truetype')}
@font-face{font-family:'Baloo Bhaijaan 2';font-weight:600 800;src:url('/assets/fonts/BalooBhaijaan2-Bold.ttf') format('truetype')}
html,body{margin:0}img{max-width:100%}[hidden]{display:none!important}
.nsbar{position:sticky;top:0;z-index:1000;background:#fff;color:#25272A;border-bottom:1px solid #E3E7EC;direction:rtl;font-family:'Rubik',system-ui,sans-serif}
.nsbar::before{content:"";display:block;height:4px;background:linear-gradient(90deg,#FEB304 0 25%,#0275FD 25% 50%,#29B25F 50% 75%,#EE3B2A 75% 100%)}
.nsbar .in{max-width:1240px;margin:0 auto;padding:10px 16px 0;display:grid;gap:6px}
.nsbar .br{display:flex;align-items:baseline;gap:10px;flex-wrap:wrap}
.nsbar .br b{font-family:'Baloo Bhaijaan 2','Rubik',sans-serif;font-size:21px;font-weight:800}
.nsbar .br span{color:#6A7079;font-size:12.5px;flex:1}
.nsbar .br button{border:0;background:#F4F6F9;color:#25272A;border-radius:999px;padding:4px 12px;font:500 12.5px 'Rubik',sans-serif;cursor:pointer}
.nstabs{display:flex;gap:2px;overflow-x:auto;scrollbar-width:none}.nstabs::-webkit-scrollbar{display:none}
.nstabs a{flex:none;padding:8px 13px 9px;font-size:14px;font-weight:500;color:#6A7079;text-decoration:none;border-bottom:3px solid transparent}
.nstabs a[aria-current="page"]{color:#0275FD;border-bottom-color:#0275FD;font-weight:700}
.gate{min-height:100vh;display:grid;place-items:center;background:#F5F7FA;color:#25272A;direction:rtl;font-family:'Rubik',system-ui,sans-serif;padding:16px;box-sizing:border-box}
.gate form,.gate .box{width:min(100%,360px);background:#fff;border:1px solid #E3E7EC;border-radius:22px;padding:24px;display:grid;gap:12px;box-sizing:border-box}
.gate h1{margin:0;font-family:'Baloo Bhaijaan 2','Rubik',sans-serif;font-size:24px}
.gate p{margin:0;color:#6A7079;font-size:14px;line-height:1.6}
.gate input{height:48px;border-radius:14px;border:1px solid #D5DBE3;padding:0 14px;font:500 18px 'Rubik',sans-serif;letter-spacing:3px;text-align:center;direction:ltr}
.gate input:focus{outline:3px solid #B9D8FF;border-color:#0275FD}
.gate button{height:46px;border:0;border-radius:14px;background:#0275FD;color:#fff;font:700 15px 'Rubik',sans-serif;cursor:pointer}
.gate button:disabled{opacity:.6}
.gate .msg{min-height:20px;font-size:13.5px;color:#B02A1D}.gate .msg.ok{color:#14703A}
`;

const head = (title) => `<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><meta name="robots" content="noindex,nofollow"><title>${esc(title)}</title><link rel="icon" type="image/png" href="/favicon.png">`;

export default async function screens(app, opts = {}) {
  const pool = opts.pool ?? globalThis.naslifePool ?? null;
  const auth = typeof opts.auth === "function" ? opts.auth : async () => null;
  const now = typeof opts.now === "function" ? opts.now : () => Date.now();
  let PAGES = opts.pages ?? null;
  if (!PAGES) { try { PAGES = (await import("./screens_data.js")).PAGES; } catch (e) { app.log?.warn?.({ err: e }, "screens: no data file"); PAGES = []; } }
  const byId = new Map(PAGES.map((p) => [p.id, p]));
  if (!pool) { app.log?.warn?.("screens: no database, disabled"); return; }
  await pool.query(`CREATE TABLE IF NOT EXISTS screens_access (id INT PRIMARY KEY DEFAULT 1 CHECK (id = 1), salt TEXT, hash TEXT, secret TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_by TEXT)`);
  await pool.query("INSERT INTO screens_access(id, secret) VALUES(1, $1) ON CONFLICT (id) DO NOTHING", [crypto.randomBytes(32).toString("hex")]);

  const row = async () => (await pool.query("SELECT salt, hash, secret, updated_at FROM screens_access WHERE id=1")).rows[0];
  // التوقيع يدخل فيه تجزئة الرقم، فتغيير الرقم يُسقط كل الجلسات السابقة
  const sign = (r, exp) => crypto.createHmac("sha256", r.secret).update(`${exp}.${r.hash}`).digest("hex");
  const cookieOf = (req) => { const m = /(?:^|;\s*)ns_screens=([^;]+)/.exec(String(req.headers.cookie ?? "")); return m ? m[1] : null; };
  const allowed = async (req) => {
    const c = cookieOf(req); if (!c) return false;
    const [exp, mac] = c.split("."); const r = await row();
    if (!r?.hash || !mac || !/^\d+$/.test(exp) || Number(exp) < now()) return false;
    const good = sign(r, exp);
    return mac.length === good.length && crypto.timingSafeEqual(Buffer.from(mac), Buffer.from(good));
  };
  const priv = (reply) => reply.header("cache-control", "private, no-store").header("x-robots-tag", "noindex, nofollow");
  const ipOf = (req) => String(req.headers["x-forwarded-for"] ?? "").split(",")[0].trim() || req.ip || "?";
  const fails = new Map();
  const blocked = (ip) => { const f = fails.get(ip); if (!f) return false; if (now() - f.at > FAIL_WINDOW_MS) { fails.delete(ip); return false; } return f.n >= MAX_FAILS; };
  const adminOnly = async (req, reply) => {
    const uid = await auth(req); if (!uid) { reply.code(401).send({ error: "auth" }); return null; }
    let ok = false; try { ok = !!(await globalThis.naslifeIsAdmin?.(uid)); } catch { ok = false; }
    if (!ok) { reply.code(403).send({ error: "admin-only" }); return null; }
    return uid;
  };

  const loginPage = (set) => `${head("تصاميم ناس لايف")}<style>${SHELL_CSS}</style></head><body><div class="gate"><form id="f" autocomplete="off"><h1>تصاميم ناس لايف</h1>` +
    (set ? `<p>صفحة خاصة. أدخل الرقم السري الذي وصلك مع الرابط.</p><input id="pin" inputmode="numeric" maxlength="12" aria-label="الرقم السري" placeholder="••••••" autofocus><button type="submit">دخول</button><div class="msg" id="msg" role="alert"></div>`
      : `<p>لم يُضبط الرقم السري بعد. يضبطه مدير المنصة من صفحة الإدارة.</p>`) + `</form></div><script src="/screens/js/login.js"></script></body></html>`;

  const pageHtml = (p) => `${head(p.title + " · تصاميم ناس لايف")}<style>${SHELL_CSS}</style><style>${p.css}</style></head><body>` +
    `<div class="nsbar"><div class="in"><div class="br"><b>تصاميم ناس لايف</b><span>${esc(p.sub)}</span><button type="button" id="ns-out">خروج</button></div>` +
    `<nav class="nstabs" aria-label="النسخ">${PAGES.map((x) => `<a href="/screens/${x.id}"${x.id === p.id ? ' aria-current="page"' : ""}>${esc(x.title)}</a>`).join("")}</nav></div></div>` +
    `${p.html}<script src="/screens/js/shell.js"></script><script src="/screens/js/${p.id}.js"></script></body></html>`;

  const JS = {
    login: `(function(){var f=document.getElementById('f'),pin=document.getElementById('pin'),msg=document.getElementById('msg');if(!pin)return;
f.addEventListener('submit',function(e){e.preventDefault();var b=f.querySelector('button');b.disabled=true;msg.textContent='';
fetch('/screens/login',{method:'POST',headers:{'content-type':'application/json'},credentials:'same-origin',body:JSON.stringify({pin:pin.value})})
.then(function(r){if(r.ok){location.replace('/screens');return;}b.disabled=false;pin.value='';pin.focus();msg.textContent=r.status===429?'محاولات كثيرة. حاول بعد ربع ساعة.':'الرقم غير صحيح.';})
.catch(function(){b.disabled=false;msg.textContent='تعذر الاتصال. حاول مرة أخرى.';});});})();`,
    shell: `(function(){var o=document.getElementById('ns-out');if(o)o.addEventListener('click',function(){fetch('/screens/logout',{method:'POST',credentials:'same-origin'}).then(function(){location.replace('/screens');});});})();`,
    admin: `(function(){var box=document.getElementById('box'),msg=document.getElementById('msg'),st=document.getElementById('st'),f=document.getElementById('f'),pin=document.getElementById('pin');
function tok(){try{var v=JSON.parse(localStorage.getItem('flutter.naslife.session.v2'));if(typeof v==='string')v=JSON.parse(v);return v&&v.token||'';}catch(e){return '';}}
var t=tok();function say(s,ok){msg.textContent=s;msg.className='msg'+(ok?' ok':'');}
function load(){fetch('/screens/pin',{headers:{'x-token':t}}).then(function(r){if(r.status===401||r.status===403){st.textContent='سجّل الدخول بحساب المدير في naslife.app من هذا المتصفح، ثم أعد فتح هذه الصفحة.';f.hidden=true;return null;}return r.json();})
.then(function(d){if(!d)return;st.textContent=d.set?'الرقم السري مضبوط. آخر تغيير: '+new Date(d.updatedAt).toLocaleString('ar-SA')+'. اكتب رقماً جديداً لتغييره، وسيخرج كل من دخل بالرقم القديم.':'لم يُضبط رقم بعد. اختر رقماً من 6 إلى 12 خانة.';f.hidden=false;});}
f.addEventListener('submit',function(e){e.preventDefault();fetch('/screens/pin',{method:'POST',headers:{'content-type':'application/json','x-token':t},body:JSON.stringify({pin:pin.value})})
.then(function(r){if(r.ok){say('تم الحفظ. شارك الرابط naslife.app/screens مع الرقم.',true);pin.value='';load();}else say(r.status===400?'الرقم يجب أن يكون من 6 إلى 12 خانة، أرقاماً فقط.':'تعذر الحفظ.');});});
load();})();`,
  };

  app.get("/SCREENS", async (req, reply) => reply.redirect("/screens"));
  app.get("/screens", async (req, reply) => {
    priv(reply);
    if (await allowed(req)) return PAGES.length ? reply.redirect(`/screens/${PAGES[0].id}`) : reply.type("text/html; charset=utf-8").send(`${head("تصاميم ناس لايف")}</head><body>لا تصاميم بعد</body></html>`);
    const r = await row();
    return reply.type("text/html; charset=utf-8").send(loginPage(!!r?.hash));
  });
  app.post("/screens/login", { config: { rateLimit: false } }, async (req, reply) => {
    priv(reply);
    const ip = ipOf(req);
    if (blocked(ip)) return reply.code(429).send({ error: "too-many" });
    const pin = latinDigits(req.body?.pin), r = await row();
    let ok = false;
    if (r?.hash && PIN_RE.test(pin)) { const h = await scrypt(pin, r.salt); ok = h.length === r.hash.length && crypto.timingSafeEqual(Buffer.from(h), Buffer.from(r.hash)); }
    if (!ok) { const f = fails.get(ip); fails.set(ip, f && now() - f.at <= FAIL_WINDOW_MS ? { n: f.n + 1, at: f.at } : { n: 1, at: now() }); return reply.code(401).send({ error: "bad-pin" }); }
    fails.delete(ip);
    const exp = now() + SESSION_DAYS * 86400000;
    reply.header("set-cookie", `${COOKIE}=${exp}.${sign(r, exp)}; Path=/screens; Max-Age=${SESSION_DAYS * 86400}; HttpOnly; Secure; SameSite=Lax`);
    return { ok: true };
  });
  app.post("/screens/logout", async (req, reply) => { priv(reply); reply.header("set-cookie", `${COOKIE}=; Path=/screens; Max-Age=0; HttpOnly; Secure; SameSite=Lax`); return { ok: true }; });

  app.get("/screens/admin", async (req, reply) => priv(reply).type("text/html; charset=utf-8").send(
    `${head("الرقم السري للتصاميم")}<style>${SHELL_CSS}</style></head><body><div class="gate"><div class="box" id="box"><h1>الرقم السري للتصاميم</h1><p id="st">جارٍ التحقق…</p>` +
    `<form id="f" hidden style="border:0;padding:0;width:auto"><input id="pin" inputmode="numeric" maxlength="12" aria-label="الرقم السري الجديد" placeholder="رقم من 6 إلى 12 خانة"><button type="submit">احفظ الرقم</button></form><div class="msg" id="msg" role="status"></div></div></div><script src="/screens/js/admin.js"></script></body></html>`));
  app.get("/screens/pin", async (req, reply) => { priv(reply); if (!(await adminOnly(req, reply))) return; const r = await row(); return { set: !!r?.hash, updatedAt: r?.updated_at ?? null }; });
  app.post("/screens/pin", async (req, reply) => {
    priv(reply);
    const uid = await adminOnly(req, reply); if (!uid) return;
    const pin = latinDigits(req.body?.pin);
    if (!PIN_RE.test(pin)) return reply.code(400).send({ error: "bad-pin" });
    const salt = crypto.randomBytes(16).toString("hex");
    await pool.query("UPDATE screens_access SET salt=$1, hash=$2, updated_at=now(), updated_by=$3 WHERE id=1", [salt, await scrypt(pin, salt), uid]);
    fails.clear();
    return { ok: true };
  });

  app.get("/screens/js/:name", async (req, reply) => {
    priv(reply);
    const name = String(req.params.name ?? "").replace(/\.js$/, "");
    if (JS[name]) return reply.type("application/javascript; charset=utf-8").send(JS[name]);
    const p = byId.get(name);
    if (!p) return reply.code(404).send({ error: "not-found" });
    if (!(await allowed(req))) return reply.code(401).send({ error: "locked" });
    return reply.type("application/javascript; charset=utf-8").send(p.js);
  });
  app.get("/screens/:id", async (req, reply) => {
    priv(reply);
    if (!(await allowed(req))) return reply.redirect("/screens");
    const p = byId.get(String(req.params.id ?? ""));
    if (!p) return reply.redirect("/screens");
    return reply.type("text/html; charset=utf-8").send(pageHtml(p));
  });
}
