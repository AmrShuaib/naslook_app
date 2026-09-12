
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import 'media.dart';

/// صورة مختارة من الجهاز (المعرض أو الكاميرا) على كل المنصات.
typedef PickedImage = ({Uint8List bytes, String mime, String name});

/// بديل للاختبارات: يُستدعى بدل منتقي الصور الحقيقي إن عُيّن.
Future<PickedImage?> Function({bool camera})? pickImageOverride;

/// يختار صورة: على الويب مباشرة من المتصفح (روابط blob تفشل على iOS)، وعلى المنصات الأخرى عبر image_picker.
Future<PickedImage?> pickImage({bool camera = false}) async {
  if (pickImageOverride != null) return pickImageOverride!(camera: camera);
  if (kIsWeb && WebMedia.available) {
    final m = await WebMedia.pick(camera ? 'camera' : 'image');
    if (m == null) return null;
    return (bytes: m.bytes, mime: m.mime, name: m.name);
  }
  final x = await ImagePicker().pickImage(source: camera ? ImageSource.camera : ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 82);
  if (x == null) return null;
  final bytes = await x.readAsBytes();
  final name = x.name.isNotEmpty ? x.name : 'image.jpg';
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : 'jpg';
  return (bytes: bytes, mime: x.mimeType ?? (ext == 'png' ? 'image/png' : ext == 'webp' ? 'image/webp' : 'image/jpeg'), name: name);
}
