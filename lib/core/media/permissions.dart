import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import 'browser_env.dart';

/// رفض المستخدم (أو النظام) الوصول إلى الكاميرا أو الصور أو الميكروفون.
/// نصّه عربي حتى تبقى رسائل الخطأ الحالية (toast بنص الاستثناء) مفهومة.
class MediaPermissionDenied implements Exception {
  /// camera | photos | mic
  final String what;
  const MediaPermissionDenied(this.what);

  String get label => switch (what) { 'camera' => 'الكاميرا', 'mic' => 'الميكروفون', _ => 'الصور' };

  @override
  String toString() => 'اسمح بالوصول إلى $label من الإعدادات';
}

/// الميكروفون موجود لكنه لا يعمل الآن (لا جهاز، أو يستخدمه تطبيق آخر). نصّه عربي جاهز للعرض.
class MediaUnavailable implements Exception {
  final String message;
  const MediaUnavailable(this.message);

  @override
  String toString() => message;
}

/// يحوّل أخطاء getUserMedia في المتصفح (NotAllowedError وأخواتها، ونصها إنجليزي خام) إلى أخطاء بنص عربي:
/// الرفض يصير [MediaPermissionDenied] فتُعرض خطوات السماح، وغيره [MediaUnavailable].
Object mapMicError(Object e) {
  if (e is MediaPermissionDenied || e is MediaUnavailable) return e;
  final s = '$e';
  if (s.contains('NotAllowedError') || s.contains('SecurityError') || s.contains('PermissionDenied') || s.contains('Permission denied')) return const MediaPermissionDenied('mic');
  if (s.contains('NotFoundError') || s.contains('DevicesNotFound') || s.contains('OverconstrainedError')) return const MediaUnavailable('لا يوجد ميكروفون متاح على هذا الجهاز');
  if (s.contains('NotReadableError') || s.contains('TrackStartError') || s.contains('AbortError')) return const MediaUnavailable('الميكروفون مشغول في تطبيق آخر. أغلقه ثم أعد المحاولة');
  return e;
}

/// يحوّل أخطاء image_picker على iOS/Android (camera_access_denied / photo_access_denied …) إلى [MediaPermissionDenied].
Object mapPickerError(Object e, {required bool camera}) {
  if (e is PlatformException) {
    final c = e.code.toLowerCase();
    if (c.contains('camera_access_denied') || (camera && c.contains('access_denied'))) return const MediaPermissionDenied('camera');
    if (c.contains('photo_access_denied') || c.contains('access_denied') || c.contains('permission')) return MediaPermissionDenied(camera ? 'camera' : 'photos');
  }
  return e;
}

/// بديل للاختبارات: يُستدعى بدل فتح إعدادات التطبيق.
Future<void> Function()? openAppSettingsOverride;

/// يفتح صفحة إعدادات التطبيق في النظام ('app-settings:' على iOS عبر url_launcher، بلا حزمة إضافية).
Future<void> openAppSettings() async {
  final o = openAppSettingsOverride;
  if (o != null) return o();
  if (kIsWeb) return;
  try {
    await launchUrl(Uri.parse('app-settings:'));
  } catch (_) {}
}

/// ورقة تشرح كيف يسمح المستخدم بالوصول، مع زر يفتح الإعدادات مباشرة (شرط Apple: طريق واضح بعد الرفض).
Future<void> showPermissionHelp(BuildContext context, MediaPermissionDenied e) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(e.what == 'camera' ? Icons.photo_camera_outlined : e.what == 'mic' ? Icons.mic_none_rounded : Icons.photo_library_outlined, size: 44, color: Joy.primary),
            const SizedBox(height: 10),
            Text('اسمح بالوصول من الإعدادات', key: const Key('perm-help'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 6),
            Text('ناس لايف لا يملك إذن الوصول إلى ${e.label}. افتح الإعدادات وفعّل الإذن ثم عد وحاول مجدداً.', textAlign: TextAlign.center, style: const TextStyle(color: Joy.textMuted, height: 1.6)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('perm-open-settings'),
                onPressed: () {
                  Navigator.pop(ctx);
                  openAppSettings();
                },
                icon: const Icon(Icons.settings_outlined),
                label: const Text('فتح الإعدادات'),
              ),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ليس الآن')),
          ]),
        ),
      ),
    );

/// ورقة الويب بعد رفض الميكروفون: خطوات السماح في بيئة المستخدم (لا زر إعدادات: الويب لا يفتحها).
Future<void> showMicHelp(BuildContext context, BrowserHost host) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(host == BrowserHost.inApp ? Icons.open_in_browser_rounded : Icons.mic_off_outlined, size: 44, color: Joy.primary),
            const SizedBox(height: 10),
            Text(micDeniedTitle(host), key: const Key('mic-help'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 6),
            Text(micDeniedHelp(host), textAlign: TextAlign.center, style: const TextStyle(color: Joy.textMuted, height: 1.6)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('فهمت')),
            ),
          ]),
        ),
      ),
    );

/// يعرض المساعدة إن كان الخطأ رفضاً للإذن ويعيد true؛ وإلا يعيد false ليعرض المستدعي خطأه المعتاد.
bool handlePermissionError(BuildContext context, Object e) {
  if (e is! MediaPermissionDenied || !context.mounted) return false;
  if (kIsWeb && e.what == 'mic') {
    // طريق السماح يختلف بين سفاري والتطبيق المثبّت والمتصفح الداخلي لتطبيق آخر: نعرض خطوات هذه البيئة بالذات
    showMicHelp(context, browserHost);
    return true;
  }
  if (kIsWeb) {
    // لا يستطيع الويب فتح إعدادات المتصفح؛ نشرح الطريق فقط
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اسمح بالوصول من إعدادات المتصفح لهذا الموقع ثم أعد المحاولة')));
    return true;
  }
  showPermissionHelp(context, e);
  return true;
}
