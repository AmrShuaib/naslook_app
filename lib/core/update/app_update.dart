import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_update_stub.dart' if (dart.library.js_interop) 'app_update_web.dart';

/// يكتشف نشر نسخة ويب جديدة بينما التطبيق مفتوح. الصفحة المفتوحة تبقى على الشيفرة القديمة حتى يُعاد تحميلها، فكان
/// الإصلاح لا يصل المستخدم إلا بعد وقت (أو أبداً في تبويب لا يُغلق). نقرأ `build.json` (بصمة الحزمة التي كتبها سكربت
/// النشر) عند الإقلاع ثم كل [every] وعند العودة إلى التطبيق؛ تغيّر البصمة يرفع [available] فيظهر شريط «تحديث الآن».
class AppUpdate {
  AppUpdate._();
  static final ValueNotifier<bool> available = ValueNotifier<bool>(false);
  /// بصمة الحزمة التي يعمل بها التطبيق الآن (أول قراءة ناجحة).
  static String? current;
  static Timer? _timer;
  static bool _checking = false;

  /// بدائل الاختبار: جالب نص build.json، وإعادة التحميل، وتفعيل خارج الويب.
  static Future<String> Function()? fetchOverride;
  static void Function()? reloadOverride;
  static bool? supportedOverride;

  static bool get _supported => supportedOverride ?? appUpdateSupported;

  /// يبدأ المراقبة (مرة واحدة)؛ آمن الاستدعاء المتكرر.
  static void start({Duration every = const Duration(minutes: 10)}) {
    if (!_supported || _timer != null) return;
    unawaited(check());
    _timer = Timer.periodic(every, (_) => check());
  }

  static void stop() { _timer?.cancel(); _timer = null; }

  /// يقرأ البصمة؛ أول قراءة تُثبّت [current]، وأي اختلاف لاحق يعني نسخة جديدة. الأخطاء تُبتلع (لا شبكة مثلاً).
  static Future<void> check() async {
    if (!_supported || _checking) return;
    _checking = true;
    try {
      final text = fetchOverride != null ? await fetchOverride!() : await _fetch();
      final m = jsonDecode(text);
      final bundle = m is Map ? m['bundle']?.toString() : null;
      if (bundle == null || bundle.isEmpty) return;
      if (current == null) { current = bundle; return; }
      if (bundle != current && !available.value) available.value = true;
    } catch (_) {
      // لا شبكة أو ملف غائب: نحاول في الدورة التالية
    } finally {
      _checking = false;
    }
  }

  static Future<String> _fetch() async {
    final url = Uri.parse('${appUpdateBuildUrl()}?t=${DateTime.now().millisecondsSinceEpoch}');
    final r = await http.get(url, headers: const {'cache-control': 'no-store'}).timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) throw Exception('build.json ${r.statusCode}');
    return r.body;
  }

  /// يعيد تحميل الصفحة لجلب النسخة الجديدة (index.html يمسح الكاش أولاً).
  static void reload() {
    if (reloadOverride != null) { reloadOverride!(); return; }
    appUpdateReload();
  }

  /// للاختبارات.
  @visibleForTesting
  static void reset() { stop(); current = null; available.value = false; _checking = false; }
}
