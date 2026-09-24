import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

/// أدوات مشتركة للتطبيق الأصلي (iOS/Android): فحص المنصة وملفات مؤقتة.
/// لا تُستخدم على الويب؛ كل دالة تتحقق من kIsWeb أولاً لأن dart:io لا يعمل هناك وقت التشغيل.

/// بديل للاختبارات: يفرض اعتبار البيئة جهازاً جوالاً أصلياً أو لا.
bool? nativeMobileOverride;

/// جهاز جوال أصلي؟ نستخدم Platform لا defaultTargetPlatform لأن الاختبارات تتظاهر بأندرويد وهي تعمل على Linux.
bool get isNativeMobile => nativeMobileOverride ?? (!kIsWeb && (Platform.isIOS || Platform.isAndroid));

/// بديل للاختبارات لمجلد الملفات المؤقتة (path_provider يحتاج قناة المنصة).
Future<String> Function()? tempDirOverride;

int _seq = 0;

/// مسار ملف مؤقت فريد بالبادئة والامتداد المعطيين.
Future<String> tempFilePath(String prefix, String ext) async {
  final dir = await (tempDirOverride?.call() ?? getTemporaryDirectory().then((d) => d.path));
  return '$dir/${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_seq++}.$ext';
}

/// يكتب بايتات في ملف مؤقت ويعيد مساره (just_audio على iOS لا يشغّل روابط data:).
Future<String> writeTempFile(List<int> bytes, {required String prefix, required String ext}) async {
  final path = await tempFilePath(prefix, ext);
  await File(path).writeAsBytes(bytes, flush: true);
  return path;
}

/// حذف صامت لملف مؤقت: الفشل هنا لا يهم المستخدم.
Future<void> deleteQuietly(String? path) async {
  if (kIsWeb || path == null || path.isEmpty) return;
  try {
    final f = File(path);
    if (await f.exists()) await f.delete();
  } catch (_) {}
}

/// امتداد ملف صوتي من نوعه.
String audioExt(String? mime) => switch ((mime ?? '').split(';').first.trim()) {
      'audio/mp4' || 'audio/m4a' || 'audio/x-m4a' || 'audio/aac' => 'm4a',
      'audio/mpeg' || 'audio/mp3' => 'mp3',
      'audio/wav' || 'audio/x-wav' || 'audio/wave' => 'wav',
      'audio/ogg' || 'audio/opus' => 'ogg',
      _ => 'webm',
    };

/// نوع ملف صوتي من امتداده.
String audioMimeOfExt(String ext) => switch (ext.toLowerCase()) {
      'm4a' || 'mp4' || 'aac' => 'audio/mp4',
      'ogg' || 'oga' || 'opus' => 'audio/ogg',
      'wav' => 'audio/wav',
      'mp3' => 'audio/mpeg',
      _ => 'audio/webm',
    };
