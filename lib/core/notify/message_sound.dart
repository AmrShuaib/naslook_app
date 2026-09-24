/// جرس الرسائل الجديدة عند وصول رسالة عبر الاتصال المباشر.
/// على الويب: نغمة تُولَّد ببرمجة الصوت في المتصفح، ويُفتح سياق الصوت عند أول لمسة أو ضغطة مفتاح (شرط المتصفحات).
/// على iOS/Android: ملف صغير مضمّن يُشغَّل عبر just_audio. على سطح المكتب لا يفعل شيئاً.
library;

import 'package:shared_preferences/shared_preferences.dart';

import 'message_sound_stub.dart' if (dart.library.js_interop) 'message_sound_web.dart' if (dart.library.io) 'message_sound_io.dart' as impl;

class MessageSound {
  static const prefKey = 'naslife.sound.messages';
  /// أقل فاصل بين جرسين حتى لا تتحوّل دفعة رسائل إلى ضجيج.
  static const minGap = Duration(milliseconds: 1500);
  static DateTime? _last;
  /// يُبدَّل في الاختبارات لالتقاط نداءات التشغيل.
  static void Function()? playOverride;
  /// يُبدَّل في الاختبارات لمحاكاة جهاز يدعم الجرس (بيئة الاختبار ليست iOS ولا Android).
  static bool? supportedOverride;

  static bool get supported => supportedOverride ?? impl.soundSupported();

  /// يسجّل مستمعي أول تفاعل (لمسة/مفتاح) لفتح سياق الصوت؛ يُستدعى مرة عند بدء التطبيق.
  static void prepare() => impl.soundPrepare();

  /// يشغّل الجرس الآن (زر التجربة).
  static void play() {
    final o = playOverride;
    if (o != null) return o();
    impl.soundPlay();
  }

  /// هل يُقرع الجرس لهذه الرسالة؟ رسالة من شخص آخر، والصوت مفعّل، والطرف غير مكتوم، ومضى الفاصل الأدنى منذ آخر جرس.
  static bool shouldRing({required bool enabled, required String? senderId, required String myId, required Set<String> mutedPeers, DateTime? now}) {
    if (!enabled || senderId == null || senderId.isEmpty || senderId == myId) return false;
    if (mutedPeers.contains(senderId.toUpperCase())) return false;
    final t = now ?? DateTime.now();
    if (_last != null && t.difference(_last!) < minGap) return false;
    _last = t;
    return true;
  }

  /// لأغراض الاختبار.
  static void resetThrottle() => _last = null;

  static Future<bool> loadEnabled() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(prefKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> saveEnabled(bool v) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(prefKey, v);
    } catch (_) {}
  }
}
