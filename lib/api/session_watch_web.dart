import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// يراقب تغيّر الجلسة المحفوظة من تبويب آخر في المتصفح نفسه (حدث storage لا يصل إلى التبويب الذي كتب القيمة).
/// shared_preferences تخزّن المفاتيح في localStorage بسابقة "flutter.".
void watchSessionStorage(String key, void Function() onChange) {
  final wanted = 'flutter.$key';
  web.window.addEventListener('storage', ((web.StorageEvent e) {
    if (e.key == null || e.key == wanted) onChange();
  }).toJS);
}
