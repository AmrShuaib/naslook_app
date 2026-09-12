import 'dart:typed_data';

import 'client.dart';
import 'models.dart';

/// نتيجة رفع ملف وسائط إلى الخادم.
class UploadedMedia {
  final String url, type, kind;
  final int size;
  const UploadedMedia({required this.url, required this.type, required this.kind, required this.size});
}

/// مسارات إضافة أدوات المحادثات (server/chat_tools.js): رفع الوسائط وبيانات الرسائل الإضافية.
extension ChatToolsApi on ApiClient {
  Future<UploadedMedia> uploadMedia(Uint8List bytes, {required String contentType, String? fileName}) async {
    final d = await postBytes('/chat/upload', bytes, contentType: contentType, headers: {if (fileName != null) 'x-file-name': fileName},
        timeout: const Duration(minutes: 3));
    final url = (d['url'] ?? '').toString();
    if (url.isEmpty) throw const ApiException(500, 'الخادم لم يُرجع رابط الملف');
    return UploadedMedia(url: url, type: (d['type'] ?? contentType).toString(), kind: (d['kind'] ?? 'file').toString(), size: (d['size'] as num?)?.toInt() ?? bytes.length);
  }

  Future<void> setMessageMeta(String messageId, {String? replyTo, MessageQuote? quote, String? forwardedFrom, Map<String, dynamic>? extra}) =>
      post('/chat/meta', {
        'messageId': messageId,
        if (replyTo != null) 'replyTo': replyTo,
        if (quote != null) 'quote': quote.toJson(),
        if (forwardedFrom != null) 'forwardedFrom': forwardedFrom,
        if (extra != null && extra.isNotEmpty) 'extra': extra,
      });

  /// بيانات إضافية لمجموعة رسائل: معرّف → {replyTo, quote, forwardedFrom, extra}
  Future<Map<String, Map<String, dynamic>>> messageMeta(Iterable<String> ids) async {
    final list = ids.where((s) => s.isNotEmpty).toList();
    if (list.isEmpty) return const {};
    final d = await get('/chat/meta', query: {'ids': list.join(',')});
    return {for (final e in d.entries) if (e.value is Map) e.key: asMap(e.value)};
  }
}
