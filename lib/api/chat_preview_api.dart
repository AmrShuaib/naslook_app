import 'client.dart';
import 'models.dart';

/// معاينة رابط كما أعادها الخادم (server/chat_preview.js): الخادم يجلب الصفحة نيابةً عن الجهاز (فلا يتصل الجوال بالموقع
/// الخارجي) ويخزّنها يوماً. [ok] false مع [reason] حين لا معاينة (ليست HTML، مضيف خاص، مهلة…).
class LinkPreview {
  final bool ok;
  final String url, title, description, image, site, reason;
  final DateTime? cachedAt;
  const LinkPreview({required this.ok, required this.url, this.title = '', this.description = '', this.image = '', this.site = '', this.reason = '', this.cachedAt});
  const LinkPreview.failed(this.url, [this.reason = 'failed']) : ok = false, title = '', description = '', image = '', site = '', cachedAt = null;
  factory LinkPreview.fromJson(Map m, {required String url}) => LinkPreview(
        ok: m['ok'] == true,
        url: (m['url'] ?? url).toString(),
        title: (m['title'] ?? '').toString().trim(),
        description: (m['description'] ?? '').toString().trim(),
        image: (m['image'] ?? '').toString().trim(),
        site: (m['site'] ?? '').toString().trim(),
        reason: (m['reason'] ?? '').toString(),
        cachedAt: DateTime.tryParse((m['cachedAt'] ?? '').toString()),
      );
  bool get hasImage => image.startsWith('http');
  /// فيها ما يستحق العرض: نجاح وعنوان.
  bool get showable => ok && title.isNotEmpty;
}

/// مسارات إضافة معاينة الروابط (server/chat_preview.js).
extension ChatPreviewApi on ApiClient {
  /// لا ترمي أبداً: أي خطأ (شبكة، 429، خادم قديم بلا الإضافة) يعود ok:false فتختفي البطاقة بهدوء.
  Future<LinkPreview> linkPreview(String url) async {
    try {
      return LinkPreview.fromJson(await get('/chat/preview', query: {'url': url}), url: url);
    } on ApiException catch (e) {
      return LinkPreview.failed(url, (e.body?['reason'] ?? 'http-${e.statusCode}').toString());
    } catch (_) {
      return LinkPreview.failed(url);
    }
  }
}

final _linkRe = RegExp(r'''(?:https?://|www\.)[^\s<>"'«»()]+''', caseSensitive: false);

/// أول رابط في نص الرسالة يصلح للمعاينة: http(s) أو www.، بلا علامات الترقيم العالقة في نهايته، ويتجاهل روابط وسائط
/// الخادم (تُعرض وسائط لا بطاقة). null إن لم يوجد.
String? firstLinkIn(String text) {
  for (final m in _linkRe.allMatches(text)) {
    var s = m.group(0)!.replaceAll(RegExp(r'[.,،;:!?؟…]+$'), '');
    if (s.toLowerCase().startsWith('www.')) s = 'https://$s';
    final u = Uri.tryParse(s);
    if (u == null || !u.hasAuthority || u.host.isEmpty || !u.host.contains('.')) continue;
    if (Message.kindOf('text', s) != 'text') continue;
    return s;
  }
  return null;
}
