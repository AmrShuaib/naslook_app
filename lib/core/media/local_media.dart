import 'dart:typed_data';

import 'local_media_stub.dart' if (dart.library.js_interop) 'local_media_web.dart' if (dart.library.io) 'local_media_io.dart' as impl;

/// بديل للاختبارات: يعيد رابطاً وهمياً بدل لمس المتصفح أو مجلد الملفات المؤقتة.
Future<String?> Function(Uint8List bytes, String mime)? localMediaUrlOverride;

/// رابط يشغّل وسائط ما زالت على الجهاز (فيديو صُوّر للتو ولم يُرفع): على الويب blob: (مسموح في media-src للموقع)،
/// وعلى الجوال ملف مؤقت. null إن تعذّر، فيعرض المستدعي بديله الثابت.
Future<String?> localMediaUrl(Uint8List bytes, String mime) async {
  try {
    return await (localMediaUrlOverride?.call(bytes, mime) ?? impl.createLocalUrl(bytes, mime));
  } catch (_) {
    return null;
  }
}

/// يحرّر الرابط (الذاكرة على الويب، والملف المؤقت على الجوال).
void releaseLocalMediaUrl(String? url) {
  if (url == null || localMediaUrlOverride != null) return;
  try {
    impl.releaseLocalUrl(url);
  } catch (_) {}
}
