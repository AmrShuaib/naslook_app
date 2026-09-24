import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import 'media.dart';
import 'native_io.dart';
import 'permissions.dart';

export 'permissions.dart' show MediaPermissionDenied, showPermissionHelp, handlePermissionError, openAppSettings, openAppSettingsOverride;

/// صورة مختارة من الجهاز (المعرض أو الكاميرا) على كل المنصات.
typedef PickedImage = ({Uint8List bytes, String mime, String name});

/// فيديو مختار مع مدته بالثواني إن أمكن قراءتها.
typedef PickedVideo = ({Uint8List bytes, String mime, String name, int? durationSec});

/// بديل للاختبارات: يُستدعى بدل منتقي الصور الحقيقي إن عُيّن.
Future<PickedImage?> Function({bool camera})? pickImageOverride;

/// بديل للاختبارات: يُستدعى بدل منتقي الفيديو الحقيقي، ويستقبل المصدر المطلوب.
Future<PickedVideo?> Function({required bool gallery})? pickVideoOverride;

/// يختار صورة: على الويب مباشرة من المتصفح (روابط blob تفشل على iOS)، وعلى المنصات الأخرى عبر image_picker.
/// يرمي [MediaPermissionDenied] إن رُفض الوصول إلى الكاميرا أو الصور.
Future<PickedImage?> pickImage({bool camera = false}) async {
  if (pickImageOverride != null) return pickImageOverride!(camera: camera);
  if (kIsWeb && WebMedia.available) {
    final m = await WebMedia.pick(camera ? 'camera' : 'image');
    if (m == null) return null;
    return (bytes: m.bytes, mime: m.mime, name: m.name);
  }
  XFile? x;
  try {
    x = await ImagePicker().pickImage(source: camera ? ImageSource.camera : ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 82);
  } catch (e) {
    throw mapPickerError(e, camera: camera);
  }
  if (x == null) return null;
  final bytes = await x.readAsBytes();
  final name = x.name.isNotEmpty ? x.name : 'image.jpg';
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : 'jpg';
  return (bytes: bytes, mime: x.mimeType ?? (ext == 'png' ? 'image/png' : ext == 'webp' ? 'image/webp' : 'image/jpeg'), name: name);
}

/// يختار فيديو من المعرض ([gallery]) أو يصوّره بكاميرا النظام، حتى [maxDuration].
/// على الجهاز الأصلي تُقرأ المدة من الملف قبل حذفه. يرمي [MediaPermissionDenied] عند رفض الإذن.
Future<PickedVideo?> pickVideo({required bool gallery, Duration? maxDuration}) async {
  final o = pickVideoOverride;
  if (o != null) return o(gallery: gallery);
  if (kIsWeb && WebMedia.available) {
    final m = await WebMedia.pick('video');
    if (m == null) return null;
    return (bytes: m.bytes, mime: m.mime, name: m.name, durationSec: null);
  }
  XFile? x;
  try {
    x = await ImagePicker().pickVideo(source: gallery ? ImageSource.gallery : ImageSource.camera, maxDuration: maxDuration);
  } catch (e) {
    throw mapPickerError(e, camera: !gallery);
  }
  if (x == null) return null;
  final bytes = await x.readAsBytes();
  final sec = await _videoSeconds(x.path);
  // image_picker ينسخ الفيديو إلى مجلد مؤقت (حتى 30 ميجا)؛ لم نعد نحتاجه بعد القراءة
  if (isNativeMobile && x.path.isNotEmpty) { try { await File(x.path).delete(); } catch (_) {} }
  final name = x.name.isNotEmpty ? x.name : 'video.mp4';
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : 'mp4';
  final mime = x.mimeType ?? (ext == 'mov' ? 'video/quicktime' : ext == 'webm' ? 'video/webm' : 'video/mp4');
  return (bytes: bytes, mime: mime, name: name, durationSec: sec);
}

/// مدة ملف فيديو محلي عبر video_player (على الجوال فقط؛ غيره بلا قناة منصة).
Future<int?> _videoSeconds(String path) async {
  if (!isNativeMobile || path.isEmpty) return null;
  VideoPlayerController? c;
  try {
    c = VideoPlayerController.file(File(path));
    await c.initialize().timeout(const Duration(seconds: 5));
    final ms = c.value.duration.inMilliseconds;
    return ms > 0 ? (ms / 1000).round().clamp(1, 3600) : null;
  } catch (_) {
    return null;
  } finally {
    await c?.dispose();
  }
}
