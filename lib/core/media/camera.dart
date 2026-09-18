import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'camera_stub.dart' if (dart.library.js_interop) 'camera_web.dart' as impl;

/// لقطة من الكاميرا الحية: صورة JPEG أو مقطع فيديو ببايتاته ونوعه واسمه ومدته.
typedef CameraShot = ({Uint8List bytes, String mime, String name, int? durationSec});

/// الكاميرا الحية داخل التطبيق: معاينة مباشرة (على الويب عبر getUserMedia وعنصر <video>)، التقاط صورة من الإطار الحالي،
/// وتسجيل فيديو قصير عبر MediaRecorder. على المنصات التي لا تدعمها تُعاد [supported] = false فيلجأ المحرّر إلى كاميرا النظام.
/// [factoryOverride] يبدّلها في الاختبارات.
abstract class LiveCamera {
  static LiveCamera Function()? factoryOverride;
  static bool get supported => factoryOverride != null || impl.supported;
  factory LiveCamera() => factoryOverride?.call() ?? impl.createCamera();

  /// يطلب الإذن ويبدأ البث. يرمي إن رُفض الإذن أو لم توجد كاميرا.
  Future<void> start({bool front = false});

  /// ودجت المعاينة الحية (يملأ المساحة المتاحة).
  Widget view();

  bool get front;

  /// يبدّل بين الخلفية والأمامية (إن وُجدت أكثر من كاميرا).
  Future<void> flip();

  /// يلتقط الإطار الحالي كصورة JPEG بحد أقصى 1600 بكسل للضلع.
  Future<CameraShot?> capturePhoto();

  /// يبدأ تسجيل فيديو (بالصوت) من البث الحالي.
  Future<void> startVideo();

  /// يوقف التسجيل ويعيد المقطع، أو null إن لم يُسجَّل شيء.
  Future<CameraShot?> stopVideo();

  bool get recording;

  /// يوقف البث ويحرر الكاميرا.
  void dispose();
}
