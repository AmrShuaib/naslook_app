import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// منصة التشغيل للقرارات التي تخص متجر التطبيقات (المشتريات الرقمية، أدوات المال) وترويسة تعريف العميل.
/// نفحص kIsWeb أولاً لأن Safari على iPhone يعدّ iOS أيضاً، ولأن Platform من dart:io لا يعمل على الويب وقت التشغيل.

/// بديل للاختبارات: يفرض اعتبار التطبيق نسخة iOS أصلية أو لا (null = الفحص الفعلي).
bool? iosNativeOverride;

/// تطبيق iOS أصلي (لا Safari): تُخفى فيه المشتريات الرقمية وأدوات تحويل المال (إرشادات أبل 3.1.1).
bool get isIosNative => iosNativeOverride ?? (!kIsWeb && Platform.isIOS);

/// تطبيق أندرويد أصلي (البديل يعني iOS أو غير أصلي، فلا أندرويد معه).
bool get isAndroidNative => iosNativeOverride == null && !kIsWeb && Platform.isAndroid;

/// إصدار التطبيق كما في pubspec.yaml (يُحدَّث مع كل إصدار للمتاجر).
const appVersion = '1.0.0';

/// وسم العميل: ios/1.0.0 أو android/1.0.0 أو web/1.0.0 أو desktop/1.0.0.
String get clientTag {
  final p = isIosNative ? 'ios' : isAndroidNative ? 'android' : kIsWeb ? 'web' : 'desktop';
  return '$p/$appVersion';
}

/// قيمة ترويسة x-naslife-client أو null: تُرسل من التطبيقات الأصلية فقط؛ على الويب تغيّر طلبات CORS التمهيدية بلا فائدة.
String? get clientHeader => isIosNative || isAndroidNative ? clientTag : null;
