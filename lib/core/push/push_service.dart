import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/client.dart';
import '../../api/naslife_api.dart';
import '../../state/app_state.dart';
import 'push_stub.dart' if (dart.library.js_interop) 'push_web.dart' as impl;

/// الإشعارات الفورية (Web Push). على غير الويب: غير مدعومة حالياً.
///
/// الاشتراك يخص **المتصفح** لا الحساب (docs/notifications.md): يُلغى عند الخروج، ويُحفظ محلياً معرّف الحساب صاحبه، فاشتراك
/// حساب سابق لم يخرج (انتهت جلسته) لا يُنقل إلى من يدخل بعده بل يُلغى.
class PushService {
  static bool get supported => impl.pushSupported();
  /// 'default' | 'granted' | 'denied'
  static String get permission => impl.pushPermission();
  static Future<bool> isSubscribed() => impl.pushIsSubscribed();

  /// يطلب الإذن، يسجّل عامل الخدمة الخاص بالإشعارات، ويشترك ويرسل الاشتراك للخادم.
  static Future<bool> subscribe(ApiClient api) async {
    _bindSignOut(api);
    // اشتراك قائم لحساب آخر: يُلغى أولاً فيُنشأ عنوان جديد لا تصله إشعارات ذلك الحساب
    if (await _foreign()) await _dropLocal();
    final ok = await impl.pushSubscribe(api);
    if (ok) await _setOwner(_userId);
    return ok;
  }

  static Future<void> unsubscribe(ApiClient api) async {
    await impl.pushUnsubscribe(api);
    await _setOwner(null);
  }

  /// عند بدء التطبيق ([userId] الحساب الداخل): إن كان الإذن ممنوحاً واشتراك موجوداً نعيد إرساله للخادم (قد يتغيّر بعد تحديث
  /// المتصفح)، إلا إن كان لحساب آخر على هذا المتصفح فيُلغى.
  static Future<void> resubscribeIfGranted(ApiClient api, {String? userId}) async {
    _bindSignOut(api);
    if (userId != null && userId.isNotEmpty) _userId = userId;
    try {
      final sub = await (subscriptionOverride ?? impl.pushGrantedSubscription)();
      if (sub == null) return;
      if (await _foreign()) {
        await _dropLocal();
        return;
      }
      await api.pushSubscribe(sub);
      // اشتراك أقدم من حفظ صاحبه: يُنسب إلى الحساب الداخل الآن
      if (_userId != null) await _setOwner(_userId);
    } catch (_) {}
  }

  // ---- صاحب الاشتراك على هذا المتصفح
  static String? _userId;
  static const ownerKey = 'push.owner';

  static Future<String?> _owner() async {
    try {
      return (await SharedPreferences.getInstance()).getString(ownerKey);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _setOwner(String? id) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (id == null || id.isEmpty) {
        await p.remove(ownerKey);
      } else {
        await p.setString(ownerKey, id);
      }
    } catch (_) {}
  }

  /// الاشتراك المحفوظ لحساب غير الداخل الآن؟ (صاحب غير معروف = لا: اشتراكات ما قبل الحفظ تبقى لصاحب الجهاز)
  static Future<bool> _foreign() async {
    final me = _userId, owner = await _owner();
    return me != null && owner != null && owner != me;
  }

  /// يلغي الاشتراك محلياً ويعيد عنوانه. صاحبه يُنسى فقط إن لم يبق اشتراك (إن تعذّر الإلغاء يبقى ليُكشف عند الدخول التالي).
  static Future<String?> _dropLocal() async {
    try {
      final r = await (dropLocalOverride ?? impl.pushDropLocal)();
      if (r.dropped) await _setOwner(null);
      return r.endpoint;
    } catch (_) {
      return null;
    }
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

  /// يُلغى محلياً أولاً (الضمان)، ثم يُحذف من الخادم برمز الجلسة ما دام صالحاً، بمهلة قصيرة وبأفضل جهد.
  static Future<void> _onSignOut(bool _) async {
    _userId = null;
    final endpoint = await _dropLocal();
    final api = _api;
    if (endpoint == null || api == null || api.token == null) return;
    try {
      await api.pushUnsubscribe(endpoint).timeout(signOutServerTimeout);
    } catch (_) {}
  }

  /// بدائل الاختبار (flutter test يعمل كسطح مكتب بلا Push API): الاشتراك القائم بإذن ممنوح، والإلغاء المحلي.
  @visibleForTesting
  static Future<Map<String, dynamic>?> Function()? subscriptionOverride;
  @visibleForTesting
  static Future<({String? endpoint, bool dropped})> Function()? dropLocalOverride;
  @visibleForTesting
  static void resetForTest() {
    subscriptionOverride = null;
    dropLocalOverride = null;
    _userId = null;
    _api = null;
  }

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
