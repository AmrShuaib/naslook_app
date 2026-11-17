import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// هل رأى هذا الجهاز جولة الترحيب؟ القيمة الافتراضية «رآها» حتى يقرأ [prime] التخزين من main، فلا تظهر الجولة في
/// الاختبارات ولا على منصة لا يرد تخزينها (كنمط [Swr.prime]).
class WelcomeSeen {
  static const prefsKey = 'naslife.welcome.v1';

  /// مهلة قراءة التخزين: بعدها يكون الزائر قد وصل إلى شاشة الدخول، وظهور الجولة فوق ما يكتبه أسوأ من غيابها
  static const primeTimeout = Duration(seconds: 3);

  static final ValueNotifier<bool> seen = ValueNotifier<bool>(true);
  static SharedPreferences? _store;

  /// يُستدعى مرة من main قبل runApp بلا انتظار. تخزين محجوب (نافذة خاصة) يعني «لم يرها»: تظهر مرة في الجلسة ولا تُحفظ.
  static Future<void> prime() async {
    try {
      final p = await SharedPreferences.getInstance().timeout(primeTimeout);
      _store = p;
      seen.value = p.getBool(prefsKey) ?? false;
    } on TimeoutException {
      // التخزين لم يرد: نبقى على «رآها»
    } catch (_) {
      _store = null;
      seen.value = false;
    }
  }

  /// بعد «ابدأ» أو «تخطي»: تختفي الجولة فوراً، والحفظ تحسين لا شرط
  static Future<void> markSeen() async {
    seen.value = true;
    try {
      await _store?.setBool(prefsKey, true);
    } catch (_) {
      // امتلأ التخزين أو تعطّل: لا تعود الجولة في هذه الجلسة على الأقل
    }
  }

  /// للاختبارات: يفرض الحالة بلا تخزين (`false` = زائر لأول مرة)، ويُعاد إلى `true` في tearDown
  @visibleForTesting
  static void debugSet(bool value) {
    _store = null;
    seen.value = value;
  }
}

/// يعيد بناء AuthGate حين تتغير الحالة (انتهاء الجولة، أو وصول قراءة التخزين بعد أول إطار)
final welcomeSeenProvider = Provider<bool>((ref) {
  void changed() => ref.invalidateSelf();
  WelcomeSeen.seen.addListener(changed);
  ref.onDispose(() => WelcomeSeen.seen.removeListener(changed));
  return WelcomeSeen.seen.value;
});
