// «القناة الحية» (server/live.js): بث فوري داخل العملية لما يتغيّر على الخريطة الآن (لحظة نُشرت، لحظة حُذفت أو أُخفيت) إلى كل
// تطبيق مفتوح، بلا WebSocket من النواة (النواة تملك /ws ولا تعرض خطّاف بث للإضافات). الأسلوب «انتظار طويل» (long-poll):
// يفتح التطبيق GET /live/wait?after=<seq> فيُحجز الطلب حتى يصل حدث أو تنقضي المهلة (≤30 ث) ثم يعاد فتحه فوراً؛ يعمل على
// الويب (XHR) وiOS وخلف Caddy بلا إعداد، وتكلفته طلب واحد كل ~25 ثانية لكل جهاز صامت. الأحداث في حلقة ذاكرة قصيرة
// (RING) حتى يلحق من انقطع لحظات؛ من غاب أطول يأخذ reset:true فيعيد الجلب كاملاً. البث لعملية واحدة (الخادم عملية Node واحدة)؛
// لو تعدّدت العمليات يوماً يُستبدل بـ LISTEN/NOTIFY في Postgres من هذا الملف وحده.
// الإضافات الأخرى تبث عبر globalThis.naslifeLive.emit(kind, data, { only }) (map_posts.js: "post" و"post_removed" و"post_restored").
// only (اختياري) قائمة معرّفات من يُسلَّم إليهم الحدث وحدهم: لحظة صاحب الملف الخاص تصل إليه وإلى أصدقائه فقط. القائمة لا تُرسل
// لأحد (خاصية غير قابلة للعدّ)، والمستمع يُعرف بجلسته الاختيارية؛ الضيف لا يأخذ إلا الأحداث العامة.
// التسجيل في register.txt:
//   await app.register((await import("./live.js")).default, { pool, auth });

export const RING = 300, WAIT_DEFAULT = 25, WAIT_MAX = 30, MAX_WAITERS = 5000, BATCH_MAX = 100;
const clampInt = (v, lo, hi, d) => { const n = Math.round(Number(v)); return Number.isFinite(n) ? Math.min(hi, Math.max(lo, n)) : d; };

/// ناقل أحداث مستقل عن Fastify حتى يُختبر وحده: حلقة ذاكرة بترقيم متسلسل ومنتظرون يُوقَظون عند أول حدث.
export function createBus({ ring = RING } = {}) {
  const events = []; const waiters = new Set(); let seq = 0; let emitted = 0;
  const emit = (kind, data = {}, { only = null } = {}) => {
    const k = String(kind ?? "").trim().slice(0, 40); if (!k) return 0;
    const ev = { seq: ++seq, kind: k, at: new Date().toISOString(), data: data ?? {} };
    // جمهور محدود: غير قابل للعدّ فلا يظهر في JSON الرد
    if (Array.isArray(only)) Object.defineProperty(ev, "only", { value: new Set(only.map(String)), enumerable: false });
    events.push(ev); if (events.length > ring) events.shift();
    emitted++;
    for (const w of [...waiters]) { waiters.delete(w); try { w(ev); } catch { /* ignore */ } }
    return ev.seq;
  };
  const oldest = () => (events.length ? events[0].seq : seq + 1);
  // ما بعد after (مصفّى بالأنواع إن طُلبت، وبالجمهور: حدث له only لا يأخذه إلا من فيها)، وإن كان after أقدم من الحلقة فلا سبيل للحاق: reset
  const since = (after, kinds, viewer = null) => {
    if (after < oldest() - 1) return { reset: true, events: [] };
    const list = events.filter((e) => e.seq > after && (!kinds || kinds.has(e.kind)) && (!e.only || (viewer != null && e.only.has(String(viewer)))));
    return { reset: false, events: list.length > BATCH_MAX ? list.slice(-BATCH_MAX) : list };
  };
  // ينتظر حدثاً أو المهلة؛ onAbort يربط إلغاء الطلب (العميل أغلق) بإزالة المنتظر
  const wait = (ms, hook) => new Promise((resolve) => {
    const w = () => { clearTimeout(t); resolve(true); };
    const t = setTimeout(() => { waiters.delete(w); resolve(false); }, ms);
    waiters.add(w);
    hook?.(() => { clearTimeout(t); waiters.delete(w); resolve(false); });
  });
  return { emit, since, wait, get seq() { return seq; }, get waiting() { return waiters.size; }, get buffered() { return events.length; }, get emitted() { return emitted; } };
}

export default async function live(app, opts = {}) {
  const bus = createBus(opts);
  const auth = opts.auth;
  const optionalAuth = async (req) => { try { return (auth && (await auth(req))) || null; } catch { return null; } };
  globalThis.naslifeLive = { emit: bus.emit, get seq() { return bus.seq; } };

  app.get("/live/status", async () => ({ ok: true, seq: bus.seq, waiting: bus.waiting, buffered: bus.buffered, emitted: bus.emitted, waitDefault: WAIT_DEFAULT, waitMax: WAIT_MAX }));

  // عام للضيف والمسجّل: الحدث العام لكل مستمع، وذو الجمهور (only) لمن فيه فقط حسب جلسة الطلب. بلا after يُعاد المؤشر الحالي فوراً
  // (مصافحة) فيبدأ العميل من «الآن». seq في الرد آخر مؤشر دائماً، فحدث لا يخص المستمع يُتخطّى بلا كشف شيء عنه.
  app.get("/live/wait", async (req, reply) => {
    reply.header("cache-control", "no-store");
    const q = req.query ?? {};
    const after = q.after == null || q.after === "" ? null : Math.round(Number(q.after));
    if (after == null || !Number.isFinite(after) || after < 0) return { seq: bus.seq, events: [], reset: false };
    const kinds = typeof q.kinds === "string" && q.kinds.trim() ? new Set(q.kinds.split(",").map((s) => s.trim()).filter(Boolean)) : null;
    const timeoutS = clampInt(q.timeout, 0, WAIT_MAX, WAIT_DEFAULT);
    const viewer = await optionalAuth(req);
    let r = bus.since(after, kinds, viewer);
    if (r.reset || r.events.length || timeoutS === 0) return { seq: bus.seq, ...r };
    if (bus.waiting >= MAX_WAITERS) return { seq: bus.seq, events: [], reset: false, retryIn: 5 };
    // انتظار حدث يخص هذا المستمع؛ حدث لغيره (جمهور محدود) يعيده إلى الانتظار لبقية المهلة بدل رد فارغ يدوّر العميل.
    // إغلاق العميل للاتصال يحرّر المنتظر فوراً (close على الردّ: على الطلب يُطلق في Node 16+ بمجرد اكتمال قراءته)
    const until = Date.now() + timeoutS * 1000;
    let closed = false, abortNow = null;
    reply.raw.once("close", () => { closed = true; abortNow?.(); });
    while (!closed) {
      const left = until - Date.now();
      if (left <= 0) break;
      const woke = await bus.wait(left, (abort) => { abortNow = abort; });
      abortNow = null;
      r = bus.since(after, kinds, viewer);
      if (!woke || r.reset || r.events.length) break;
    }
    r = bus.since(after, kinds, viewer);
    return { seq: bus.seq, ...r };
  });
}
