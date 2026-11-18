// بطاقة الدعوة (18 نوفمبر 2026، طلب المالك): لكل مستخدم رمز دعوة ثابت يُطبع رمز QR على بطاقته. مسح الرمز يفتح
// naslife.app/hi/<رمز>: صفحة ترحيب قصيرة (تحية باسم الداعي، ما هو ناس لايف، المزايا) ثم زر التسجيل الذي يفتح التطبيق
// على شاشة إنشاء الحساب. بعد أول دخول يرسل التطبيق الرمز (POST /invite/accept) فنعرف من دعا من، ويتابع الجديدُ داعيه.
// الصفحة بلا سكربت مضمّن (سياسة الأمان تمنعه): حركتها CSS، وسكربت صغير في /hi/app.js يحوّلها إلى شاشات متتابعة.
// جدولان: invite_codes و invite_joins. التفاصيل في docs/invite-card.md.
// التسجيل في register.txt:
//   await app.register((await import("./invite.js")).default, { pool, auth });
import crypto from "node:crypto";

export const CODE_RE = /^[a-z0-9]{6,12}$/;
/// الدعوة تُحتسب لحساب جديد فقط: من سجّل قبل أكثر من هذه المدة ومسح بطاقة لا يصير «مدعواً»
export const NEW_ACCOUNT_DAYS = 7;
const ALPHABET = "abcdefghjkmnpqrstuvwxyz23456789"; // بلا المتشابهات (0/o، 1/l/i)
const APP_URL = (process.env.APP_URL || "https://naslife.app").replace(/\/+$/, "");
export const newCode = () => Array.from(crypto.randomBytes(8), (b) => ALPHABET[b % ALPHABET.length]).join("");
export const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

const font = (fam, w, f) => `@font-face{font-family:'${fam}';font-weight:${w};font-display:swap;src:url('/assets/fonts/${f}') format('truetype')}`;
const CSS = [
  font("Rubik", 400, "Rubik-Regular.ttf"), font("Rubik", 500, "Rubik-Medium.ttf"), font("Rubik", 700, "Rubik-Bold.ttf"), font("Baloo Bhaijaan 2", "600 800", "BalooBhaijaan2-Bold.ttf"),
  `:root{--ink:#25272A;--ink2:#4A5863;--soft:#F3F6FA;--b:#0275FD;--g:#29B25F;--y:#FEB304;--r:#EE3B2A;color-scheme:light}
*{box-sizing:border-box}html,body{margin:0;height:100%}body{background:#fff;color:var(--ink);font-family:'Rubik',system-ui,sans-serif;font-size:17px;line-height:1.8;direction:rtl;-webkit-text-size-adjust:100%}
h1,h2,p{margin:0}h1,h2{font-family:'Baloo Bhaijaan 2','Rubik',sans-serif;font-weight:700;line-height:1.3;text-wrap:balance}h1{font-size:44px}h2{font-size:30px}
p{color:var(--ink2)}b{color:var(--ink)}
.strip{height:6px;display:flex;flex:none}.strip i{flex:1}.strip i:nth-child(1){background:var(--b)}.strip i:nth-child(2){background:var(--g)}.strip i:nth-child(3){background:var(--y)}.strip i:nth-child(4){background:var(--r)}
main{max-width:460px;margin:0 auto;padding:0 max(22px,env(safe-area-inset-left,0px)) 0 max(22px,env(safe-area-inset-right,0px))}
.s{display:flex;flex-direction:column;gap:16px;padding:34px 0 26px;position:relative}
.mid{display:grid;justify-items:center;gap:8px;text-align:center}
.logo{width:160px;height:160px;animation:pop .7s cubic-bezier(.2,1.5,.4,1) both}
.wave{display:inline-block;transform-origin:70% 80%;animation:wave 1.6s ease-in-out .6s 2}
.cta{display:flex;align-items:center;justify-content:center;min-height:56px;border-radius:28px;background:var(--b);color:#fff;font-weight:700;font-size:18px;text-decoration:none;border:0;width:100%;font-family:inherit;cursor:pointer}
.ghost{display:flex;align-items:center;justify-content:center;min-height:46px;color:var(--ink2);font-size:16px;text-decoration:none}
.cta:focus-visible,.ghost:focus-visible{outline:3px solid var(--ink);outline-offset:3px}
.conf{position:fixed;inset:0;pointer-events:none;overflow:hidden}.conf i{position:absolute;top:-14px;width:10px;height:10px;border-radius:3px;animation:fall 2.8s ease-in both}
.map{width:100%;aspect-ratio:1.2;border-radius:24px;position:relative;overflow:hidden;background:linear-gradient(0deg,transparent 48%,#fff 48% 52%,transparent 52%) 0 0/100% 72px,linear-gradient(90deg,transparent 47%,#fff 47% 53%,transparent 53%) 0 0/88px 100%,#E4EDF5}
.pin{position:absolute;width:44px;height:44px;border-radius:50% 50% 50% 7px;transform:rotate(-45deg);display:grid;place-items:center;animation:drop .5s cubic-bezier(.2,1.4,.4,1) both}.pin span{transform:rotate(45deg);font-size:20px}
.feats{display:grid;gap:10px}.feat{display:grid;grid-template-columns:48px 1fr;gap:14px;align-items:center;background:var(--soft);border-radius:20px;padding:12px 14px}
.feat i{font-style:normal;width:48px;height:48px;border-radius:16px;display:grid;place-items:center;font-size:23px}.feat b{display:block;font-size:17px;line-height:1.5}.feat span{display:block;font-size:15px;color:var(--ink2);line-height:1.6}
.dots{display:none;gap:7px;justify-content:center}.dots i{width:8px;height:8px;border-radius:50%;background:#D5DBE2}.dots i.on{width:24px;border-radius:4px;background:var(--b)}
.next{display:none}
@keyframes pop{from{transform:scale(.3) rotate(-12deg);opacity:0}to{transform:none;opacity:1}}
@keyframes wave{0%,100%{transform:none}25%{transform:rotate(18deg)}75%{transform:rotate(-10deg)}}
@keyframes fall{from{transform:translateY(0) rotate(0);opacity:1}to{transform:translateY(105vh) rotate(520deg);opacity:0}}
@keyframes drop{from{transform:translateY(-70px) rotate(-45deg);opacity:0}to{transform:rotate(-45deg);opacity:1}}
/* مع السكربت: شاشة واحدة في كل مرة تملأ الجوال. بلا سكربت: الصفحة كلها تُقرأ بالتمرير */
.js body{display:flex;flex-direction:column}.js main{flex:1;width:100%;display:flex;min-height:0}
.js .s{display:none;flex:1;min-height:0;padding-bottom:max(20px,env(safe-area-inset-bottom,0px))}.js .s.on{display:flex}
.js .grow{flex:1;min-height:0;display:grid;place-items:center}.js .dots{display:flex}.js .next{display:flex}.js .feats{align-self:start;width:100%}
@media (max-height:640px){h1{font-size:36px}h2{font-size:26px}.logo{width:120px;height:120px}.feat{padding:8px 12px}}
@media (prefers-reduced-motion:reduce){.logo,.wave,.pin{animation:none}.conf{display:none}}`,
].join("");

const PINS = [[16, 20, "b", "📸", 0], [62, 12, "g", "🛍️", .18], [40, 44, "r", "🎟️", .36], [74, 58, "y", "🏷️", .54], [12, 64, "b", "☕", .72]];
const FEATS = [
  ["#E6F1FF", "📸", "شارك لحظتك", "صورة أو فيديو يظهر في مكانه على الخريطة"],
  ["#E7F6ED", "🛍️", "بِع واشترِ من جيرانك", "سوق قريب منك وتسليم يداً بيد"],
  ["#FFF4D6", "🏷️", "عروض المحلات حولك", "خصومات تُستخدم من جوالك"],
  ["#FDEBE8", "🎟️", "فعاليات وتذاكر", "احجز ووزّع التذاكر على أصحابك"],
  ["#EEF0F3", "💬", "دوائر ومحادثات", "مجتمعك وشلّتك في مكان واحد"],
];
const dots = (n) => `<div class="dots" aria-hidden="true">${[0, 1, 2].map((i) => `<i${i === n ? ' class="on"' : ""}></i>`).join("")}</div>`;

/// صفحة الترحيب. [inviter] اسم الداعي للعرض (أو فارغ للبطاقة العامة)، و[code] رمزه ليحمله زر التسجيل إلى التطبيق.
export function welcomeHtml({ inviter = "", code = "" } = {}) {
  const join = code ? `/#/hi/${code}` : "/#/hi";
  const who = inviter ? `وصلتك دعوة من <b>${esc(inviter)}</b><br>إلى ناس لايف` : "أهلاً بك في ناس لايف";
  const title = inviter ? `${esc(inviter)} يدعوك إلى ناس لايف` : "انضم إلى ناس لايف";
  const desc = "ناسك وأماكنك في خريطة واحدة: لحظات، سوق، عروض، فعاليات، ودوائر.";
  return '<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8">' +
    '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><meta name="robots" content="noindex,nofollow"><meta name="theme-color" content="#FFFFFF">' +
    `<title>${title}</title><meta name="description" content="${desc}"><meta property="og:title" content="${title}"><meta property="og:description" content="${desc}"><meta property="og:type" content="website">` +
    `<link rel="icon" type="image/png" href="/favicon.png"><style>${CSS}</style></head><body><div class="strip"><i></i><i></i><i></i><i></i></div><main>` +
    `<section class="s on" id="s0"><div class="conf" id="conf" aria-hidden="true"></div><div class="grow"><div class="mid"><img class="logo" src="/icons/Icon-512.png" alt="شعار ناس لايف" width="160" height="160"><h1>يا هلا <span class="wave">👋</span></h1><p>${who}</p></div></div><button class="cta next" type="button" data-go="1">تعرّف علينا</button>${dots(0)}</section>` +
    `<section class="s" id="s1"><h2>كل ما حولك في خريطة حيّة</h2><p>افتح الخريطة وشاهد ما يحدث قربك الآن.</p><div class="grow"><div class="map" aria-hidden="true">${PINS.map(([x, y, c, e, d]) => `<div class="pin" style="left:${x}%;top:${y}%;background:var(--${c});animation-delay:${d}s"><span>${e}</span></div>`).join("")}</div></div><button class="cta next" type="button" data-go="2">التالي</button>${dots(1)}</section>` +
    `<section class="s" id="s2"><h2>ماذا تفعل فيه؟</h2><div class="feats">${FEATS.map(([bg, e, t, d]) => `<div class="feat"><i style="background:${bg}" aria-hidden="true">${e}</i><div><b>${t}</b><span>${d}</span></div></div>`).join("")}</div><div class="grow"></div><a class="cta" id="join" href="${join}">سجّل مجاناً</a><a class="ghost" href="/">تصفّح أولاً بلا حساب</a>${dots(2)}</section>` +
    '</main><script src="/hi/app.js"></script></body></html>';
}

/// سكربت الصفحة: شاشات متتابعة وقصاصات بألوان الشعار. يُقدَّم ملفاً لأن سياسة الأمان تمنع المضمّن.
export const APP_JS = `(function(){var d=document,C=['#0275FD','#29B25F','#FEB304','#EE3B2A'];d.documentElement.className+=' js';
function show(n){var s=d.querySelectorAll('.s');for(var i=0;i<s.length;i++)s[i].className=i===n?'s on':'s';window.scrollTo(0,0);}
d.addEventListener('click',function(e){var t=e.target;while(t&&t!==d){if(t.getAttribute&&t.getAttribute('data-go')!==null){show(+t.getAttribute('data-go'));return;}t=t.parentNode;}});
var c=d.getElementById('conf');if(c&&!(window.matchMedia&&matchMedia('(prefers-reduced-motion: reduce)').matches)){for(var i=0;i<28;i++){var p=d.createElement('i');p.style.left=(4+(i*37)%92)+'%';p.style.background=C[i%4];p.style.animationDelay=((i*7)%12)/10+'s';c.appendChild(p);}}
})();`;

export default async function invitePlugin(app, { pool, auth }) {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS invite_codes (user_id TEXT PRIMARY KEY, code TEXT NOT NULL UNIQUE, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    -- المدعو يُحتسب مرة واحدة ولداعٍ واحد: المفتاح على المدعو يحسم السباق
    CREATE TABLE IF NOT EXISTS invite_joins (invitee_id TEXT PRIMARY KEY, inviter_id TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT now());
    CREATE INDEX IF NOT EXISTS invite_joins_inviter ON invite_joins(inviter_id, created_at DESC);
  `);

  const bad = (reply, code, error) => reply.code(code).send({ error });
  const notify = async (ids, payload) => { try { await globalThis.naslifeNotify?.(ids, payload); } catch { /* الإشعار لا يُفشل الدعوة */ } };
  /// الاسم الظاهر من الملف إن وُجد، وإلا اسم الحساب
  const person = async (id) => {
    let u = null;
    try { u = (await pool.query("SELECT * FROM users WHERE id=$1", [id])).rows[0] ?? null; } catch { u = null; }
    if (!u) return null;
    let display = "";
    try { display = (await pool.query("SELECT display_name FROM profile_ext WHERE user_id=$1", [id])).rows[0]?.display_name ?? ""; } catch { display = ""; }
    return { id: u.id, nickname: u.nickname ?? "", name: String(display || u.nickname || "").trim(), createdAt: u.created_at ?? null };
  };
  const codeOf = async (uid) => {
    for (let i = 0; i < 5; i++) {
      const have = (await pool.query("SELECT code FROM invite_codes WHERE user_id=$1", [uid])).rows[0];
      if (have) return have.code;
      // تصادم الرمز (نادر) أو سباق على الصف نفسه: نعيد القراءة ثم المحاولة
      try { await pool.query("INSERT INTO invite_codes(user_id, code) VALUES($1,$2) ON CONFLICT (user_id) DO NOTHING", [uid, newCode()]); } catch (e) { if (e?.code !== "23505") throw e; }
    }
    throw new Error("invite: no code");
  };
  const ownerOf = async (code) => CODE_RE.test(code) ? (await pool.query("SELECT user_id FROM invite_codes WHERE code=$1", [code])).rows[0]?.user_id ?? null : null;

  // بطاقتي: الرمز والرابط وعدد من انضموا بها
  app.get("/me/invite", async (req, reply) => {
    const uid = await auth(req); if (!uid) return bad(reply, 401, "unauthorized");
    const code = await codeOf(uid);
    const joined = (await pool.query("SELECT count(*)::int AS n FROM invite_joins WHERE inviter_id=$1", [uid])).rows[0].n;
    return { code, url: `${APP_URL}/hi/${code}`, joined };
  });

  // بعد أول دخول لحساب جديد جاء من بطاقة: يُسجَّل الداعي مرة واحدة، يتابعه الجديد، ويصله إشعار
  app.post("/invite/accept", async (req, reply) => {
    const uid = await auth(req); if (!uid) return bad(reply, 401, "unauthorized");
    const code = String(req.body?.code ?? "").trim().toLowerCase();
    const inviterId = await ownerOf(code);
    if (!inviterId) return bad(reply, 404, "not-found");
    if (inviterId === uid) return bad(reply, 400, "self");
    const [me, inviter] = await Promise.all([person(uid), person(inviterId)]);
    if (!me || !inviter) return bad(reply, 404, "not-found");
    if (me.createdAt && Date.now() - new Date(me.createdAt).getTime() > NEW_ACCOUNT_DAYS * 86400000) return bad(reply, 409, "not-new");
    const ins = await pool.query("INSERT INTO invite_joins(invitee_id, inviter_id) VALUES($1,$2) ON CONFLICT (invitee_id) DO NOTHING", [uid, inviterId]);
    const out = { ok: true, inviter: { id: inviter.id, nickname: inviter.nickname, name: inviter.name } };
    if (ins.rowCount === 0) return { ...out, already: true };
    // المتابعة تحسين: غياب جدولها (profile_ext معطّلة) لا يُفشل الدعوة
    try { await pool.query("INSERT INTO user_follows(follower_id, user_id) VALUES($1,$2) ON CONFLICT DO NOTHING", [uid, inviterId]); } catch { /* ignore */ }
    await notify(inviterId, { kind: "invite_joined", title: "انضم صديق بدعوتك", body: `${me.name || "صديقك"} سجّل في ناس لايف ببطاقتك`, data: { userId: uid, nickname: me.nickname }, exclude: uid });
    return out;
  });

  const head = (reply) => reply.header("cache-control", "no-store").header("x-robots-tag", "noindex, nofollow");
  app.get("/hi/app.js", async (req, reply) => reply.header("cache-control", "public, max-age=300").type("application/javascript; charset=utf-8").send(APP_JS));
  app.get("/hi", async (req, reply) => head(reply).type("text/html; charset=utf-8").send(welcomeHtml()));
  app.get("/hi/", async (req, reply) => reply.redirect("/hi"));
  app.get("/hi/:code", async (req, reply) => {
    const code = String(req.params.code ?? "").toLowerCase();
    let inviter = null;
    try { const id = await ownerOf(code); inviter = id ? await person(id) : null; } catch { inviter = null; }
    // رمز غير معروف أو حساب حُذف: الصفحة العامة، فالبطاقة المطبوعة تبقى تعمل
    return head(reply).type("text/html; charset=utf-8").send(inviter ? welcomeHtml({ inviter: inviter.name, code }) : welcomeHtml());
  });
}
