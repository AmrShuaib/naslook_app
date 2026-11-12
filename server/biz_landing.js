// صفحة «ناس لايف للأعمال» على /business: تعريف الدائرة ودعوة الأنشطة التجارية والعمل الحر إلى التسجيل.
// صفحة ثابتة بلا سكربتات (سياسة الأمان في الموقع تمنع المضمّن منها)، محتواها مولَّد في biz_landing_data.js
// من docs/reports/screens/naslife-business.html بالمولّد tools/dev/build_biz_landing.mjs.
// ما دامت معاينة قبل الاعتماد: لا تُفهرس (noindex) ولا تُخزَّن (no-store) حتى يصل كل تعديل فوراً، ولا رابط إليها من التطبيق.
// التسجيل في register.txt:
//   await app.register((await import("./biz_landing.js")).default, {});

export default async function bizLanding(app, opts = {}) {
  let html = typeof opts.html === "string" ? opts.html : null;
  if (html == null) {
    try { html = (await import("./biz_landing_data.js")).HTML; }
    catch (e) { app.log?.warn?.({ err: e }, "biz_landing: no data file"); html = null; }
  }
  const page = async (req, reply) => {
    reply.header("cache-control", "no-store").header("x-robots-tag", "noindex, nofollow");
    if (!html) return reply.code(404).type("text/plain; charset=utf-8").send("not found");
    return reply.type("text/html; charset=utf-8").send(html);
  };
  app.get("/business", page);
  // من يكتب العنوان بأحرف كبيرة أو بشرطة أخيرة يصل إلى الصفحة نفسها
  app.get("/business/", async (req, reply) => reply.redirect("/business"));
  app.get("/BUSINESS", async (req, reply) => reply.redirect("/business"));
  app.get("/Business", async (req, reply) => reply.redirect("/business"));
  app.get("/business/status", async () => ({ ok: true, ready: !!html, bytes: html ? Buffer.byteLength(html) : 0 }));
}
