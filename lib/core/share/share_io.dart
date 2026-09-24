import 'dart:ui' show Offset, Rect;

import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:share_plus/share_plus.dart';

import '../media/native_io.dart';

/// بديل للاختبارات: يُستدعى بدل ورقة المشاركة الأصلية ويعيد نتيجتها.
Future<bool> Function({required String title, required String text, required String url})? nativeShareOverride;

/// ورقة المشاركة الأصلية في iOS/Android عبر share_plus. تعيد false على سطح المكتب (ومنه بيئة الاختبار)
/// أو عند الفشل، فتعود الواجهة إلى نسخ الرابط.
Future<bool> nativeShare({required String title, required String text, required String url}) async {
  final o = nativeShareOverride;
  if (o != null) return o(title: title, text: text, url: url);
  if (!isNativeMobile) return false;
  try {
    final r = await SharePlus.instance.share(ShareParams(title: title, subject: title, text: '$text\n$url', sharePositionOrigin: _origin()));
    return r.status != ShareResultStatus.unavailable;
  } catch (_) {
    return false;
  }
}

/// مركز الشاشة: iPad (ومنه تشغيل تطبيق iPhone عليه) يحتاج نقطة ارتكاز لنافذة المشاركة.
Rect? _origin() {
  try {
    final v = WidgetsBinding.instance.platformDispatcher.views.first;
    final s = v.physicalSize / v.devicePixelRatio;
    return Rect.fromCenter(center: s.center(Offset.zero), width: 1, height: 1);
  } catch (_) {
    return null;
  }
}
