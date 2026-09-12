import '../../api/client.dart';
import 'push_stub.dart' if (dart.library.js_interop) 'push_web.dart' as impl;

/// الإشعارات الفورية (Web Push). على غير الويب: غير مدعومة حالياً.
class PushService {
  static bool get supported => impl.pushSupported();
  /// 'default' | 'granted' | 'denied'
  static String get permission => impl.pushPermission();
  static Future<bool> isSubscribed() => impl.pushIsSubscribed();
  /// يطلب الإذن، يسجّل عامل الخدمة الخاص بالإشعارات، ويشترك ويرسل الاشتراك للخادم.
  static Future<bool> subscribe(ApiClient api) => impl.pushSubscribe(api);
  static Future<void> unsubscribe(ApiClient api) => impl.pushUnsubscribe(api);
  /// عند بدء التطبيق: إن كان الإذن ممنوحاً واشتراك موجوداً نعيد إرساله للخادم (قد يتغيّر بعد تحديث المتصفح).
  static Future<void> resubscribeIfGranted(ApiClient api) => impl.pushResubscribeIfGranted(api);
}
