import 'dart:typed_data';

import 'client.dart';
import 'models.dart';
import '../ui/reactions.dart';

/// نتيجة رفع ملف وسائط إلى الخادم.
class UploadedMedia {
  final String url, type, kind;
  final int size;
  /// موجة الصوت من الخادم (48 قيمة في 0..1) للرسائل الصوتية؛ null لغير الصوت أو حين تعذّر حسابها.
  final List<double>? peaks;
  const UploadedMedia({required this.url, required this.type, required this.kind, required this.size, this.peaks});

  /// بيانات الرسالة الصوتية الإضافية الجاهزة للإرسال: المدة من المسجّل والموجة من الخادم (تُقرأ في فقاعة الصوت من extra.peaks).
  Map<String, dynamic> audioExtra({int? durationMs}) => {
        if (durationMs != null) 'durationMs': durationMs,
        if (peaks != null && peaks!.isNotEmpty) 'peaks': peaks,
      };
}

/// يحوّل قائمة الموجة من JSON إلى أرقام في 0..1؛ null إن غابت أو كانت فارغة.
List<double>? parsePeaks(dynamic v) {
  if (v is! List || v.isEmpty) return null;
  final out = <double>[];
  for (final x in v) {
    final d = x is num ? x.toDouble() : double.tryParse(x.toString());
    if (d == null) return null;
    out.add(d.clamp(0.0, 1.0));
  }
  return out;
}

/// مهلة رفع ملف: الفيديو يمر بطابور ترميز على الخادم (انتظار حتى 90 ث وترميز حتى 100 ث، docs/moments.md) بعد إرسال حتى 30 م.ب
/// من الجوال، فمهلته خمس دقائق؛ الصور والصوت والملفات ثلاث.
Duration uploadTimeoutFor(String contentType, {String? fileName}) {
  final ext = (fileName ?? '').contains('.') ? fileName!.split('.').last.toLowerCase() : '';
  final video = contentType.toLowerCase().startsWith('video/') || const {'mp4', 'mov', 'webm', 'm4v', '3gp'}.contains(ext);
  return video ? const Duration(minutes: 5) : const Duration(minutes: 3);
}

/// هل فشل الرفع لأن المتصفح رفض ترويسة x-file-name نفسها؟ هذا رفض فوري قبل إرسال أي بايت، فإعادة الرفع بلا الترويسة آمنة.
/// المهلة أو انقطاع بعد ثوانٍ لا يُعادان تلقائياً: قد يكون الخادم استلم الملف وما زال يرمّزه، فالإعادة ترفع 30 م.ب مرة ثانية
/// وتبدأ ترميزاً ثانياً بجانب الأول.
bool isHeaderRejection(ApiException e, Duration elapsed) =>
    e.isNetwork && !e.message.contains('مهلة') && elapsed < const Duration(seconds: 3);

/// مسارات إضافة أدوات المحادثات (server/chat_tools.js): رفع الوسائط وبيانات الرسائل الإضافية.
extension ChatToolsApi on ApiClient {
  Future<UploadedMedia> uploadMedia(Uint8List bytes, {required String contentType, String? fileName}) async {
    // ترويسات HTTP لا تقبل إلا حروف ISO-8859-1؛ اسم ملف عربي يجعل WebKit يرمي "Type error"، فنرسل اسماً لاتينياً نظيفاً فقط
    final safeName = _asciiName(fileName, contentType);
    final timeout = uploadTimeoutFor(contentType, fileName: fileName);
    final started = Stopwatch()..start();
    Map<String, dynamic> d;
    try {
      d = await postBytes('/chat/upload', bytes, contentType: contentType, headers: {if (safeName != null) 'x-file-name': safeName}, timeout: timeout);
    } on ApiException catch (e) {
      // احتياط: إن رفض المتصفح الترويسة نعيد المحاولة بدونها (الخادم يستنتج النوع من content-type)، ولا نعيد عند المهلة أو انقطاع متأخر
      if (safeName == null || !isHeaderRejection(e, started.elapsed)) rethrow;
      d = await postBytes('/chat/upload', bytes, contentType: contentType, timeout: timeout);
    }
    final url = (d['url'] ?? '').toString();
    if (url.isEmpty) throw const ApiException(500, 'الخادم لم يُرجع رابط الملف');
    return UploadedMedia(url: url, type: (d['type'] ?? contentType).toString(), kind: (d['kind'] ?? 'file').toString(), size: (d['size'] as num?)?.toInt() ?? bytes.length, peaks: parsePeaks(d['peaks']));
  }

  /// موجة رسالة صوتية قديمة بلا extra.peaks: يحسبها الخادم عند أول طلب ويخزّنها بجانب الملف. يقبل اسم الملف أو رابطه.
  /// لا ترمي: null حين يتعذّر (خادم قديم، ملف مفقود، صوت تالف) فتبقى الفقاعة على الموجة الافتراضية.
  Future<List<double>?> audioPeaks(String nameOrUrl) async {
    try {
      return parsePeaks((await get('/chat/peaks', query: {'name': nameOrUrl}))['peaks']);
    } catch (_) {
      return null;
    }
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
