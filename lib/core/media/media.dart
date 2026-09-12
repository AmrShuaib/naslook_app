import 'dart:typed_data';

import 'media_stub.dart' if (dart.library.js_interop) 'media_web.dart' as impl;

/// ملف وسائط مختار أو مسجّل: بايتاته ونوعه واسمه.
class PickedMedia {
  final Uint8List bytes;
  final String mime;
  final String name;
  const PickedMedia(this.bytes, this.mime, this.name);
}

/// وسائط الويب بلا روابط blob (تفشل قراءتها على iOS): اختيار ملفات وتسجيل صوت مباشرة من المتصفح.
class WebMedia {
  static bool get available => impl.available;
  /// kind: image | camera | video
  static Future<PickedMedia?> pick(String kind) => impl.pick(kind);
}

/// مسجّل صوتي عبر MediaRecorder في المتصفح.
abstract class VoiceRecorder {
  factory VoiceRecorder() => impl.createRecorder();
  Future<void> start();
  Future<PickedMedia?> stop();
  Future<void> cancel();
}
