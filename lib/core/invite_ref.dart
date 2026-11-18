import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// القادم من بطاقة دعوة (`naslife.app/hi/<رمز>` ثم زر التسجيل يفتح `#/hi/<رمز>`): نبدأه على شاشة إنشاء الحساب،
/// ونحفظ رمز الداعي على الجهاز حتى أول دخول (التسجيل ثم رمز البريد قد يمران بإعادة تحميل) ليُرسل إلى الخادم مرة واحدة.
class InviteRef {
  static const prefsKey = 'naslife.invite.v1';

  /// وصل هذا التبويب من صفحة الدعوة: شاشة الدخول لا جولة الترحيب ولا واجهة الزائر
  static bool arrived = false;
  static bool _register = false;
  static String? _code;

  /// من main قبل runApp. [code] فارغ للبطاقة العامة (تسجيل بلا داعٍ).
  static void capture(String code) {
    arrived = true;
    _register = true;
    if (code.isEmpty) return;
    _code = code;
    unawaited(_save(code));
  }

  /// مرة واحدة: شاشة الدخول تبدأ على «إنشاء حساب»
  static bool takeRegister() {
    final r = _register;
    _register = false;
    return r;
  }

  static Future<void> _save(String code) async {
    try {
      await (await SharedPreferences.getInstance()).setString(prefsKey, code);
    } catch (_) {
      // تخزين محجوب: يبقى الرمز في الذاكرة لهذه الجلسة
    }
  }

  /// الرمز المنتظر إرساله بعد الدخول، إن وُجد.
  static Future<String?> pending() async {
    if (_code != null) return _code;
    try {
      final c = (await SharedPreferences.getInstance().timeout(const Duration(seconds: 3))).getString(prefsKey);
      return (c == null || c.isEmpty) ? null : c;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    _code = null;
    arrived = false;
    try {
      await (await SharedPreferences.getInstance()).remove(prefsKey);
    } catch (_) {
      // لا شيء يُمسح
    }
  }
}
