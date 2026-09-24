import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'share_links.dart' show publicOrigin;

/// صفحات الخصوصية والشروط والدعم تُخدم من الخادم (server/legal_pages.js). على iOS تُفتح داخل التطبيق
/// (عارض Safari) فيبقى المستخدم في التطبيق، وعلى الويب في تبويب جديد.
class LegalLinks {
  LegalLinks._();

  /// بديل للاختبارات: يستقبل الرابط بدل فتحه.
  static Future<void> Function(Uri uri)? openOverride;

  static const supportEmail = 'support@naslife.app';

  static Uri uri(String page) => Uri.parse('${publicOrigin()}/$page');

  static Future<void> open(String page) => _launch(uri(page));

  static Future<void> email({String subject = 'دعم ناس لايف'}) => _launch(Uri(scheme: 'mailto', path: supportEmail, query: 'subject=${Uri.encodeComponent(subject)}'));

  static Future<void> _launch(Uri u) async {
    if (openOverride != null) return openOverride!(u);
    final inApp = !kIsWeb && u.scheme.startsWith('http');
    await launchUrl(u, mode: inApp ? LaunchMode.inAppBrowserView : LaunchMode.platformDefault);
  }
}
