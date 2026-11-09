// «مفتاح إطفاء» لعامل الخدمة القديم. tools/publish_bundle.sh ينسخ هذا الملف فوق flutter_service_worker.js
// (Flutter يكتبه فارغاً مع --pwa-strategy=none). نسخ ما قبل 11 سبتمبر 2026 سجّلت ذلك العنوان بعامل يقدّم
// main.dart.js وغيره من المخزن، والمتصفح يفحص عنوان العامل المسجّل من الشبكة عند فتح الصفحة؛ فحين يجد هذا الملف
// يثبّته فوراً، فيمسح المخزن ويلغي تسجيله ويعيد تحميل التبويبات المفتوحة لتأتي النسخة الحالية من الشبكة.
// لا يمس push_sw.js: لكل تسجيل عنوان عامله، وهذا لا يصل إلا إلى التسجيلات القديمة.
self.addEventListener('install', function () { self.skipWaiting(); });

self.addEventListener('activate', function (event) {
  event.waitUntil(
    caches.keys()
      .then(function (ks) { return Promise.all(ks.map(function (k) { return caches.delete(k); })); })
      .catch(function () {})
      .then(function () { return self.registration.unregister(); })
      .catch(function () {})
      .then(function () { return self.clients.matchAll({ type: 'window' }); })
      .then(function (list) {
        list.forEach(function (c) { if (c.navigate) c.navigate(c.url).catch(function () {}); });
      })
      .catch(function () {})
  );
});
