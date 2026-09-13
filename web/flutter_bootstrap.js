{{flutter_js}}
{{flutter_build_config}}

// Naslife: نحمّل CanvasKit من مجلد canvaskit/ المحلي دائماً.
// بدون هذا يحاول المحرك (منذ Flutter 3.47) جلبه من www.gstatic.com، وسياسة الأمان (CSP)
// على الخادم تسمح بالسكربتات من الأصل نفسه فقط، فتبقى الصفحة بيضاء.
// لا Service Worker: نريد وصول كل تحديث فوراً دون ملفات مخزّنة قديمة.
_flutter.loader.load({
  // useColorEmoji: الإيموجي الملوّنة (تفاعلات القلب والوجوه) بدل الأحادية؛ يُحمَّل خط Noto Color Emoji مرة واحدة عند أول ظهور
  config: { canvasKitBaseUrl: "canvaskit/", useColorEmoji: true },
});
