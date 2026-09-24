import 'dart:typed_data';

import 'client.dart';
import 'models.dart';
import '../ui/reactions.dart';

/// نتيجة رفع ملف وسائط إلى الخادم.
class UploadedMedia {
  final String url, type, kind;
  final int size;
  const UploadedMedia({required this.url, required this.type, required this.kind, required this.size});
}

/// مسارات إضافة أدوات المحادثات (server/chat_tools.js): رفع الوسائط وبيانات الرسائل الإضافية.
extension ChatToolsApi on ApiClient {
  Future<UploadedMedia> uploadMedia(Uint8List bytes, {required String contentType, String? fileName}) async {
    // ترويسات HTTP لا تقبل إلا حروف ISO-8859-1؛ اسم ملف عربي يجعل WebKit يرمي "Type error"، فنرسل اسماً لاتينياً نظيفاً فقط
    final safeName = _asciiName(fileName, contentType);
    Map<String, dynamic> d;
    try {
      d = await postBytes('/chat/upload', bytes, contentType: contentType, headers: {if (safeName != null) 'x-file-name': safeName}, timeout: const Duration(minutes: 3));
    } on ApiException catch (e) {
      // احتياط: إن رفض المتصفح الترويسة لأي سبب نعيد المحاولة بدونها (الخادم يستنتج النوع من content-type)
      if (!e.isNetwork || safeName == null) rethrow;
      d = await postBytes('/chat/upload', bytes, contentType: contentType, timeout: const Duration(minutes: 3));
    }
    final url = (d['url'] ?? '').toString();
    if (url.isEmpty) throw const ApiException(500, 'الخادم لم يُرجع رابط الملف');
    return UploadedMedia(url: url, type: (d['type'] ?? contentType).toString(), kind: (d['kind'] ?? 'file').toString(), size: (d['size'] as num?)?.toInt() ?? bytes.length);
  }

  /// [peerId] الطرف الآخر في المحادثة: يرسله التطبيق ليرفض الخادم البيانات بين طرفين بينهما حظر.
  Future<void> setMessageMeta(String messageId, {String? peerId, String? replyTo, MessageQuote? quote, String? forwardedFrom, Map<String, dynamic>? extra}) =>
      post('/chat/meta', {
        'messageId': messageId,
        if (peerId != null && peerId.isNotEmpty) 'peerId': peerId,
        if (replyTo != null) 'replyTo': replyTo,
        if (quote != null) 'quote': quote.toJson(),
        if (forwardedFrom != null) 'forwardedFrom': forwardedFrom,
        if (extra != null && extra.isNotEmpty) 'extra': extra,
      });

  /// بيانات إضافية لمجموعة رسائل: معرّف → {replyTo, quote, forwardedFrom, extra}
  /// تفاعل بإيموجي على رسالة (فارغ يزيله)؛ يعيد تفاعلات الرسالة المحدّثة.
  /// [peerId] الطرف الآخر في المحادثة (لفحص الحظر على الخادم).
  Future<List<Reaction>> chatReact(String messageId, String? emoji, {String? peerId}) async =>
      parseReactions((await post('/chat/react', {'messageId': messageId, 'emoji': emoji ?? '', if (peerId != null && peerId.isNotEmpty) 'peerId': peerId}))['reactions']);

  Future<Map<String, Map<String, dynamic>>> messageMeta(Iterable<String> ids) async {
    final list = ids.where((s) => s.isNotEmpty).toList();
    if (list.isEmpty) return const {};
    final d = await get('/chat/meta', query: {'ids': list.join(',')});
    return {for (final e in d.entries) if (e.value is Map) e.key: asMap(e.value)};
  }
}

String? _asciiName(String? name, String contentType) {
  if (name == null || name.isEmpty) return null;
  final ext = name.contains('.') ? name.split('.').last.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '') : '';
  final base = name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
  var clean = base.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  if (clean.replaceAll('_', '').isEmpty) clean = 'file';
  final e = ext.isNotEmpty ? ext : contentType.split('/').last.replaceAll(RegExp(r'[^a-z0-9]'), '');
  return e.isEmpty ? clean : '${clean.length > 60 ? clean.substring(0, 60) : clean}.$e';
}
