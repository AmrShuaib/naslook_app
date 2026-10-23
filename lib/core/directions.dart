import 'package:url_launcher/url_launcher.dart';

import 'share/legal_links.dart';

/// يفتح رابطاً خارج التطبيق عبر الوسيلة نفسها في بقية التطبيق (LegalLinks.openOverride يلتقطه في الاختبارات).
Future<void> openExternalUrl(Uri u) async {
  final o = LegalLinks.openOverride;
  if (o != null) return o(u);
  await launchUrl(u, mode: LaunchMode.externalApplication);
}

Uri directionsUrl(double lat, double lng) => Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');

/// يفتح خرائط جوجل للاتجاهات إلى نقطة (مشترك بين بطاقات المحادثة وعارض اللحظات).
Future<void> openDirections(double lat, double lng) => openExternalUrl(directionsUrl(lat, lng));
