import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// «اعرض المحفوظ ثم حدّث» للقوائم التي يراها المستخدم عند الفتح (الصف، المحادثات، الدوائر، الخريطة):
/// أول بناء للمزوّد في الجلسة يعيد آخر رد محفوظ على الجهاز فوراً، ويجلب الجديد في الخلفية ثم يعيد بناء المزوّد به.
/// بلا محفوظ، أو في أي بناء لاحق (سحب للتحديث، تغيّر الموقع)، يُجلب من الشبكة كالمعتاد. فشل التحديث الخلفي يُبقي المحفوظ
/// (فيظهر آخر ما رآه المستخدم بلا اتصال). المحفوظ مفصول لكل جلسة دخول ويُمسح عند الخروج.
/// الآلية: [swr] يشغّل دالة الجلب داخل منطقة (Zone) تحمل الوضع، و[ApiClient.get] يقرأه فيعيد المحفوظ أو يحفظ الرد.
class Swr {
  static const _prefix = 'swr:';
  /// أكبر رد يُحفظ (حروف JSON): تخزين المتصفح محدود بنحو 5 ميغابايت للموقع كله
  static const maxChars = 400000;
  static bool enabled = true;
  static final Set<String> _seen = {};
  static final Map<String, Object?> _fresh = {};

  /// الوضع داخل دالة الجلب الحالية: 'cache' (من المحفوظ فقط) أو 'store' (من الشبكة ويُحفظ) أو null (خارج swr)
  static String? get mode => Zone.current[#swrMode] as String?;
  static bool get cacheMode => mode == 'cache';

  /// مفتاح الطلب التالي داخل دالة الجلب: الوسم ورقم الطلب (دالة تجلب أكثر من طلب تأخذ مفتاحاً لكل واحد) وبصمة الجلسة
  static String? nextKey(String? token) {
    final tag = Zone.current[#swrTag] as String?;
    final n = Zone.current[#swrCount] as List<int>?;
    if (tag == null || n == null) return null;
    return '$_prefix${_session(token)}:$tag:${n[0]++}';
  }

  // بصمة قصيرة لرمز الجلسة: محفوظ حساب لا يظهر لحساب آخر على الجهاز نفسه، والرمز نفسه لا يُكتب في المفتاح
  static String _session(String? token) {
    if (token == null || token.isEmpty) return 'guest';
    var h = 0x811c9dc5;
    for (final c in token.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0x7fffffff;
    }
    return h.toRadixString(36);
  }

  // التخزين يُجهَّز مرة عند إقلاع التطبيق ([prime] من main)، وقبل جهوزه نعمل بلا محفوظ: لا ينتظر أي مزوّد تخزيناً قد لا
  // يرد (منصة بلا إضافة التخزين، أو متصفح يحجبه)، فأسوأ الأحوال هو السلوك القديم نفسه
  static SharedPreferences? _store;
  static Future<void> prime() async {
    try {
      _store = await SharedPreferences.getInstance();
    } catch (_) {
      _store = null;
    }
  }

  static Future<SharedPreferences?> _prefs() async => _store;

  static Future<Map<String, dynamic>?> read(String key) async {
    try {
      final s = (await _prefs())?.getString(key);
      if (s == null) return null;
      final v = jsonDecode(s);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null; // تخزين معطّل أو نص تالف: كأنه لا محفوظ
    }
  }

  static Future<void> write(String key, Map<String, dynamic> data) async {
    try {
      final s = jsonEncode(data);
      if (s.length > maxChars) return;
      await (await _prefs())?.setString(key, s);
    } catch (_) {
      // امتلأ التخزين أو تعطّل: الحفظ تحسين لا شرط
    }
  }

  /// يمسح كل المحفوظ وينسى ما عُرض (عند الخروج، وفي الاختبارات)
  static Future<void> clear() async {
    _seen.clear();
    _fresh.clear();
    try {
      final p = await _prefs();
      if (p == null) return;
      for (final k in p.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
        await p.remove(k);
      }
    } catch (_) {}
  }
}

/// لا محفوظ لأحد طلبات الدالة: يُجلب من الشبكة
class SwrMiss implements Exception {
  const SwrMiss();
}

Future<T> _zoned<T>(String tag, String mode, Future<T> Function() fetch) =>
    runZoned(fetch, zoneValues: {#swrMode: mode, #swrTag: tag, #swrCount: <int>[0]});

/// يُستعمل داخل FutureProvider: `swr(ref, 'chats', () => api.chats())`. [tag] ثابت لكل قائمة (ومعه مفتاح العائلة إن وُجد).
Future<T> swr<T>(Ref ref, String tag, Future<T> Function() fetch) async {
  if (!Swr.enabled) return fetch();
  var alive = true;
  ref.onDispose(() => alive = false);
  if (Swr._seen.add(tag)) {
    try {
      final cached = await _zoned(tag, 'cache', fetch);
      // التحديث في الخلفية: يُخزَّن الجديد ثم يُعاد بناء المزوّد ليأخذه من [Swr._fresh] بلا طلب ثانٍ
      unawaited(() async {
        try {
          final fresh = await _zoned(tag, 'store', fetch);
          if (!alive) return;
          Swr._fresh[tag] = fresh;
          ref.invalidateSelf();
        } catch (_) {
          // بلا اتصال أو خطأ خادم: يبقى المحفوظ معروضاً
        }
      }());
      return cached;
    } on SwrMiss {
      // لا محفوظ بعد: أول استعمال على هذا الجهاز
    }
  }
  if (Swr._fresh.containsKey(tag)) return Swr._fresh.remove(tag) as T;
  return _zoned(tag, 'store', fetch);
}
