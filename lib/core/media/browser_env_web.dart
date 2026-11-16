import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

String get userAgent {
  try {
    return web.window.navigator.userAgent;
  } catch (_) {
    return '';
  }
}

/// مثبّت على الشاشة الرئيسية (PWA). سفاري iOS يعلنها بـ navigator.standalone لا باستعلام display-mode وحده.
bool get standalone {
  try {
    if (web.window.matchMedia('(display-mode: standalone)').matches) return true;
    final nav = web.window.navigator as JSObject;
    return nav.has('standalone') && nav.getProperty<JSAny?>('standalone'.toJS).dartify() == true;
  } catch (_) {
    return false;
  }
}
