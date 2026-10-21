import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../api/chat_preview_api.dart';
import '../../../core/app_theme.dart';
import '../../../core/share/legal_links.dart';
import '../../../state/app_state.dart';

/// معاينة مخبّأة لكل رابط في الجلسة (الخادم يخزّن يوماً أيضاً) فلا يُعاد الجلب مع كل إعادة بناء للفقاعة.
final linkPreviewProvider = FutureProvider.family<LinkPreview, String>((ref, url) => ref.watch(apiClientProvider).linkPreview(url));

/// يفتح رابط المعاينة خارج التطبيق بالوسيلة نفسها في بقية التطبيق (LegalLinks.openOverride يلتقطه في الاختبارات).
Future<void> openPreviewLink(Uri u) async {
  final o = LegalLinks.openOverride;
  if (o != null) return o(u);
  await launchUrl(u, mode: LaunchMode.externalApplication);
}

/// بطاقة معاينة رابط داخل فقاعة الرسالة: شريط جانبي بلون العلامة، صورة صغيرة (عبر وكيل الخادم `/chat/preview/image`
/// لأن CSP الموقع لا يسمح بصور من مضيف خارجي، وحتى لا يتصل الجهاز بالموقع)، عنوان عريض، وصف قصير، واسم الموقع.
/// تختفي تماماً أثناء الجلب وحين لا معاينة (ok:false أو بلا عنوان)، فلا تقفز الفقاعة ولا تظهر بطاقة فارغة.
class LinkPreviewCard extends ConsumerWidget {
  final String url;
  /// في الفقاعة الصادرة الخلفية ملوّنة فتُستخدم صبغة أدكن قليلاً ونص الفقاعة.
  final bool mine;
  const LinkPreviewCard(this.url, {super.key, this.mine = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(linkPreviewProvider(url)).valueOrNull;
    if (p == null || !p.showable) return const SizedBox.shrink();
    final api = ref.watch(apiClientProvider);
    final titleColor = mine ? Joy.bubbleOutText : Joy.text;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Semantics(
          button: true,
          label: 'فتح الرابط: ${p.title}',
          child: Material(
            key: const Key('link-preview-card'),
            color: mine ? Joy.bubbleOutText.withValues(alpha: .07) : Joy.surface2,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => openPreviewLink(Uri.parse(p.url)),
              child: IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 4, color: Joy.primary),
                  // الصورة عبر وكيل الخادم على أصل التطبيق (api.media يبني الرابط المطلق فيعمل على iOS أيضاً)
                  if (p.hasImage)
                    SizedBox(
                      width: 72,
                      child: Image.network(api.media('/chat/preview/image?u=${Uri.encodeQueryComponent(p.image)}'), key: const Key('link-preview-image'), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                    ),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: titleColor, height: 1.3)),
                        if (p.description.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(p.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Joy.textMuted, fontWeight: FontWeight.w500, height: 1.3)),
                          ),
                        if (p.site.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.link_rounded, size: 13, color: Joy.primary),
                              const SizedBox(width: 4),
                              Flexible(child: Text(p.site, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Joy.primary, fontWeight: FontWeight.w600))),
                            ]),
                          ),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
