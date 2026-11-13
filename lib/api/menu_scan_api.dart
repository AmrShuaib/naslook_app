import 'dart:convert';
import 'dart:typed_data';

import 'client.dart';

/// صنف قرأه الخادم من صورة المنيو (server/menu_scan.js). السعر بالهللات كوحدة الكتالوج، و[priceKnown] false حين لم يُقرأ سعر.
class ScannedItem {
  final String title, description, section;
  final int price;
  final bool priceKnown;
  const ScannedItem({required this.title, this.price = 0, this.priceKnown = true, this.description = '', this.section = ''});
  factory ScannedItem.fromJson(Map m) => ScannedItem(
        title: (m['title'] ?? '').toString().trim(),
        price: (m['price'] as num?)?.round() ?? 0,
        priceKnown: m['priceKnown'] != false,
        description: (m['description'] ?? '').toString().trim(),
        section: (m['section'] ?? '').toString().trim(),
      );
}

/// نتيجة قراءة المنيو: أصناف للمراجعة وتنبيهات بالعربية. لا شيء منها محفوظ في الخادم.
class MenuScanResult {
  final List<ScannedItem> items;
  final List<String> warnings;
  const MenuScanResult({required this.items, this.warnings = const []});
  factory MenuScanResult.fromJson(Map m) => MenuScanResult(
        items: [for (final x in (m['items'] as List? ?? const [])) if (x is Map && (x['title'] ?? '').toString().trim().isNotEmpty) ScannedItem.fromJson(x)],
        warnings: [for (final w in (m['warnings'] as List? ?? const [])) if (w is Map && (w['message'] ?? '').toString().isNotEmpty) w['message'].toString()],
      );
}

/// مسار «صوّر المنيو» (server/menu_scan.js).
extension MenuScanApi on ApiClient {
  /// يقرأ الأصناف من 1 إلى 4 صور مرفوعة للتو عبر /chat/upload. القراءة قد تأخذ دقيقة، فمهلتها أطول من مهلة الطلبات العادية.
  Future<MenuScanResult> scanMenu(List<String> imageUrls) async {
    final body = Uint8List.fromList(utf8.encode(jsonEncode({'images': imageUrls})));
    return MenuScanResult.fromJson(await postBytes('/menu/scan', body, contentType: 'application/json', timeout: const Duration(seconds: 100)));
  }
}

/// نص عربي لخطأ القراءة بحسب رمز الخادم.
String menuScanErrText(Object e) {
  if (e is! ApiException) return 'تعذّرت قراءة المنيو. أعد المحاولة.';
  if (e.isNetwork) return e.message.contains('مهلة') ? 'أخذت القراءة وقتاً طويلاً. أعد المحاولة بصورة أوضح أو بصور أقل.' : 'تعذّر الاتصال. تحقق من الإنترنت ثم أعد المحاولة.';
  final code = (e.body?['error'] ?? '').toString();
  switch (code) {
    case 'ai-unavailable':
      return 'قراءة المنيو غير مفعّلة الآن. أضف الأصناف يدوياً.';
    case 'busy':
      return 'الخدمة مشغولة اليوم. أعد المحاولة غداً أو أضف الأصناف يدوياً.';
    case 'ai-failed':
    case 'scan-failed':
      return 'تعذّرت قراءة الصور. أعد المحاولة بعد قليل.';
    case 'ai-timeout':
      return 'أخذت القراءة وقتاً طويلاً. أعد المحاولة بصورة أوضح أو بصور أقل.';
    case 'rate-limited':
      if (e.body?['scope'] == 'day') return 'بلغت حد اليوم من قراءات المنيو. أعد المحاولة غداً.';
      final sec = (e.body?['retryAfterSec'] as num?)?.toInt() ?? 600;
      return 'قراءات كثيرة. أعد المحاولة بعد ${(sec / 60).ceil()} دقيقة.';
    case 'scan-in-progress':
      return 'قراءة سابقة ما زالت جارية. انتظر قليلاً.';
    case 'image-too-large':
      return 'الصورة كبيرة جداً. صوّرها من جديد أو اختر صورة أصغر.';
    case 'too-many-images':
      return 'أربع صور على الأكثر في القراءة الواحدة.';
    case 'not-image':
    case 'bad-image':
    case 'image-not-found':
    case 'image-expired':
    case 'images-required':
      return 'تعذّر استخدام الصورة. اخترها من جديد.';
    case 'suspended':
      return 'هذا الحساب موقوف. راسل الدعم.';
  }
  return 'تعذّرت قراءة المنيو. أعد المحاولة.';
}
