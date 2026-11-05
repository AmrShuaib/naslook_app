import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../api/client.dart';
import '../../state/app_state.dart';
import 'push_stub.dart' if (dart.library.js_interop) 'push_web.dart' as impl;

/// الإشعارات الفورية (Web Push). على غير الويب: غير مدعومة حالياً.
class PushService {
  static bool get supported => impl.pushSupported();
  /// 'default' | 'granted' | 'denied'
  static String get permission => impl.pushPermission();
  static Future<bool> isSubscribed() => impl.pushIsSubscribed();
  /// يطلب الإذن، يسجّل عامل الخدمة الخاص بالإشعارات، ويشترك ويرسل الاشتراك للخادم.
  static Future<bool> subscribe(ApiClient api) {
    _bindSignOut(api);
    return impl.pushSubscribe(api);
  }
  static Future<void> unsubscribe(ApiClient api) => impl.pushUnsubscribe(api);
  /// عند بدء التطبيق: إن كان الإذن ممنوحاً واشتراك موجوداً نعيد إرساله للخادم (قد يتغيّر بعد تحديث المتصفح).
  static Future<void> resubscribeIfGranted(ApiClient api) {
    _bindSignOut(api);
    return impl.pushResubscribeIfGranted(api);
  }

  // ---- الخروج وتبديل الحساب (البند 6 في docs/reports/naslife_gaps_2026-11-05.md)
  static ApiClient? _api;
  /// مهلة حذف الاشتراك من الخادم: أقصر من مهلة خطّافات الخروج (AppStateNotifier.liveStopTimeout، 3 ث)، والإلغاء المحلي قبلها.
  static const signOutServerTimeout = Duration(milliseconds: 1500);
  /// خطّاف في AppStateNotifier.signOutHooks (المجموعة تمنع التكرار) بالعميل الحامل لرمز الجلسة. الخروج يشغّله قبل مسح الرمز،
  /// ومتابعة خروج تبويب آخر تشغّله بلا رمز فيكتفي بالإلغاء المحلي (التبويب الآخر حذفه من الخادم).
  static void _bindSignOut(ApiClient api) {
    _api = api;
    AppStateNotifier.signOutHooks.add(_onSignOut);
  }
  static Future<void> _onSignOut(bool _) => impl.pushSignOut(_api, serverTimeout: signOutServerTimeout);

  // ---- نقرة إشعار والتطبيق مفتوح
  static final _opens = StreamController<String>.broadcast();
  /// معرّفات إشعارات نُقرت والتطبيق مفتوح (رسالة من عامل الخدمة، أو تغيّر الجزء إلى `#/n/<id>`)، بلا تكرار خلال ثوانٍ.
  static Stream<String> get openRequests => _opens.stream;
  static String? _lastId;
  static DateTime? _lastAt;
  static final _idRe = RegExp(r'(?:^|#)/?n/([0-9a-fA-F-]{36})');

  /// يبدأ الاستماع مرة واحدة (main()). على غير الويب لا شيء.
  static void listenForOpens() => impl.pushListenOpens(handleOpenUrl);

  /// يحلل رابط الإشعار (`https://naslife.app/#/n/<id>` أو `#/n/<id>`) ويبث معرّفه؛ true = رابط إشعار (يُؤكَّد لعامل الخدمة).
  /// الرسالة وتغيّر الجزء قد يصلان معاً للنقرة نفسها، فالمعرّف نفسه خلال 3 ثوانٍ يُبث مرة واحدة.
  @visibleForTesting
  static bool handleOpenUrl(String url) {
    final frag = url.contains('#') ? url.substring(url.indexOf('#')) : url;
    final id = _idRe.firstMatch(frag)?.group(1);
    if (id == null) return false;
    final now = DateTime.now();
    if (id == _lastId && _lastAt != null && now.difference(_lastAt!) < const Duration(seconds: 3)) return true;
    _lastId = id;
    _lastAt = now;
    _opens.add(id);
    return true;
  }

  @visibleForTesting
  static void resetOpensForTest() {
    _lastId = null;
    _lastAt = null;
  }
}
