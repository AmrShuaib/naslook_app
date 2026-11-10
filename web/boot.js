// يُحمَّل من index.html قبل Flutter. كان هذا الكود سكربتاً مضمّناً في الصفحة، لكن سياسة الأمان (CSP) في Caddy
// لا تسمح إلا بالسكربتات من ملفات على الأصل نفسه ('self')، فكان المتصفح يتجاهله في الموقع الحي ولا يعمل إلا محلياً.

// 1) نسخ قديمة (قبل 11 سبتمبر 2026) سجّلت Service Worker من Flutter يخزّن ملفات التطبيق ويقدّمها من المخزن،
// فيبقى بعض المستخدمين على نسخة قديمة مهما نشرنا. نلغي كل تسجيل ليس push_sw.js (الإشعارات الفورية، لا يخزّن
// شيئاً) ونمسح المخزن، وإن كانت الصفحة نفسها قد جاءت من ذلك العامل نعيد تحميلها مرة واحدة لتأتي من الشبكة.
(function () {
  if (!('serviceWorker' in navigator)) return;
  var isPush = function (w) { return !!w && /push_sw\.js/.test(w.scriptURL); };
  var stale = !!navigator.serviceWorker.controller && !isPush(navigator.serviceWorker.controller);
  var clearCaches = function () {
    if (!window.caches) return Promise.resolve();
    return caches.keys().then(function (ks) { return Promise.all(ks.map(function (k) { return caches.delete(k); })); });
  };
  navigator.serviceWorker.getRegistrations()
    .then(function (rs) {
      return Promise.all(rs.map(function (r) {
        // نُبقي التسجيل إن كان push_sw.js في أي حالة (نشط أو ينتظر أو يُثبَّت) حتى لا يضيع اشتراك الإشعارات
        if ([r.active, r.waiting, r.installing].some(isPush)) return null;
        return r.unregister();
      }));
    })
    .then(clearCaches)
    .then(function () {
      if (!stale) return;
      // حارس ضد الحلقة: إعادة تحميل واحدة لكل جلسة تبويب
      try {
        if (sessionStorage.getItem('naslife-sw-reset')) return;
        sessionStorage.setItem('naslife-sw-reset', '1');
      } catch (_) { return; }
      location.reload();
    })
    .catch(function () {});
})();

// 2) مقدمة التطبيق (#splash في index.html): تبقى حتى يرسم Flutter أول إطار، وهو الشعار نفسه (lib/ui/launch_splash.dart)
// فتختفي فوقه بلا قفزة. حد أدنى ثانية من بدء الصفحة حتى يُرى الشعار، واحتياط بعد دقيقة إن تعثّر الإقلاع.
(function () {
  var splash = document.getElementById('splash');
  if (!splash) return;
  var gone = false;
  var hide = function () {
    if (gone) return;
    gone = true;
    var since = window.performance && performance.now ? performance.now() : 1000;
    setTimeout(function () {
      splash.className = 'out';
      setTimeout(function () { if (splash.parentNode) splash.parentNode.removeChild(splash); }, 450);
    }, Math.max(0, 1000 - since));
  };
  window.addEventListener('flutter-first-frame', hide);
  setTimeout(hide, 60000);
})();

// 3) احتياط للحقول التي تُنشأ داخل shadow DOM حيث لا تصل قاعدة CSS في index.html: نضبط اتجاهها عند ظهورها،
// ونحمّل أوزان الخط مسبقاً حتى يكون جاهزاً في حقل الإدخال الخفي منذ أول لمسة.
(function () {
  var fix = function (el) {
    if (!el || (el.tagName !== 'INPUT' && el.tagName !== 'TEXTAREA')) return;
    if (el.style.direction !== 'rtl') el.style.direction = 'rtl';
  };
  var scan = function (root) {
    if (!root || !root.querySelectorAll) return;
    root.querySelectorAll('input, textarea').forEach(fix);
  };
  var observe = function (root) {
    if (!root || root.__naslifeObserved) return;
    root.__naslifeObserved = true;
    scan(root);
    new MutationObserver(function (muts) {
      muts.forEach(function (m) {
        m.addedNodes.forEach(function (n) {
          if (n.nodeType !== 1) return;
          fix(n); scan(n);
          if (n.shadowRoot) observe(n.shadowRoot);
        });
      });
    }).observe(root, { childList: true, subtree: true });
  };
  observe(document);
  if (document.fonts && document.fonts.load) {
    ['400', '500', '600', '700'].forEach(function (w) { document.fonts.load(w + ' 16px Rubik').catch(function () {}); });
    document.fonts.load('700 16px BalooBhaijaan2').catch(function () {});
  }
  // flutter-view قد يُنشأ لاحقاً مع shadow root
  var tick = setInterval(function () {
    document.querySelectorAll('flutter-view, flt-glass-pane').forEach(function (v) { if (v.shadowRoot) observe(v.shadowRoot); });
  }, 1000);
  setTimeout(function () { clearInterval(tick); }, 30000);
})();
