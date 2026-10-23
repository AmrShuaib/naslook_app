import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// قائمة المشاركة الأصلية في المتصفح (Web Share API): تظهر على الجوال قائمة التطبيقات (واتساب، إكس…).
/// تعيد false إن لم تكن مدعومة أو تعذّرت، فتبقى خيارات النسخ ورمز QR. إلغاء المستخدم للقائمة (AbortError) يعيد true:
/// رأى القائمة واختار ألا يشارك، فلا نكتب فوق حافظته ولا نقول «نُسخ الرابط».
Future<bool> nativeShare({required String title, required String text, required String url}) async {
  try {
    final nav = web.window.navigator;
    if (!nav.has('share')) return false;
    await nav.share(web.ShareData(title: title, text: text, url: url)).toDart;
    return true;
  } catch (e) {
    return '$e'.contains('AbortError');
  }
}
