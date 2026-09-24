import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:record/record.dart';

import 'media.dart';
import 'native_io.dart';
import 'permissions.dart';

/// تسجيل صوتي مكتمل: بايتاته ونوعه واسمه ومدته.
typedef RecordedVoice = ({Uint8List bytes, String mime, String name, Duration duration});

/// الحد الأقصى لتسجيل صوتي واحد.
const maxVoiceRecord = Duration(minutes: 5);

/// إعداد التسجيل الأصلي: AAC داخل m4a يشغّله AVPlayer والمتصفحات مباشرة بلا تحويل على الخادم
/// (opus غير مدعوم في مسجّل iOS).
const nativeVoiceConfig = RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100, numChannels: 1);

/// مسار ملف التسجيل الأصلي: حزمة record تحتاج مساراً حقيقياً على iOS/Android (المسار الفارغ يفشل بصمت).
Future<String> nativeVoicePath() => tempFilePath('voice', 'm4a');

/// جلسة تسجيل صوتي واحدة: على الويب عبر MediaRecorder، وعلى iOS/Android عبر حزمة record إلى ملف m4a مؤقت.
/// تُستخدم في المحادثات ومساحات المجتمع والمنشئ؛ [factoryOverride] يُبدّلها في الاختبارات.
abstract class VoiceRecordSession {
  static VoiceRecordSession Function()? factoryOverride;
  factory VoiceRecordSession() => factoryOverride?.call() ?? _RealVoiceRecordSession();

  bool get recording;
  Duration get elapsed;

  /// يطلب إذن الميكروفون ويبدأ التسجيل. يرمي [MediaPermissionDenied] إن رُفض الإذن.
  Future<void> start();

  /// يوقف التسجيل ويعيد الملف، أو null إن لم يُسجَّل شيء.
  Future<RecordedVoice?> stop();
  Future<void> cancel();
  void dispose();
}

class _RealVoiceRecordSession implements VoiceRecordSession {
  // يُنشأ عند الحاجة فقط: الويب لا يستخدمه
  AudioRecorder? _nativeRec;
  AudioRecorder get _native => _nativeRec ??= AudioRecorder();
  VoiceRecorder? _web;
  DateTime? _startedAt;
  String? _path;

  @override
  bool get recording => _startedAt != null;
  @override
  Duration get elapsed => _startedAt == null ? Duration.zero : DateTime.now().difference(_startedAt!);

  @override
  Future<void> start() async {
    if (kIsWeb) {
      // الويب كما هو: MediaRecorder (webm/opus) بلا مسار ملف
      if (WebMedia.available) {
        _web = VoiceRecorder();
        await _web!.start();
      } else {
        if (!await _native.hasPermission()) throw const MediaPermissionDenied('mic');
        await _native.start(const RecordConfig(encoder: AudioEncoder.opus, bitRate: 64000, sampleRate: 48000, numChannels: 1), path: '');
      }
    } else {
      if (!await _native.hasPermission()) throw const MediaPermissionDenied('mic');
      final path = await nativeVoicePath();
      try {
        await _native.start(nativeVoiceConfig, path: path);
      } catch (_) {
        try { await File(path).delete(); } catch (_) {}
        rethrow;
      }
      _path = path;
    }
    _startedAt = DateTime.now();
  }

  @override
  Future<RecordedVoice?> stop() async {
    final duration = elapsed;
    _startedAt = null;
    if (kIsWeb && _web != null) {
      final rec = _web!;
      _web = null;
      final m = await rec.stop();
      if (m == null) return null;
      return (bytes: m.bytes, mime: m.mime, name: m.name, duration: duration);
    }
    final path = await _native.stop() ?? _path;
    _path = null;
    if (path == null || path.isEmpty) return null;
    try {
      final bytes = await XFile(path).readAsBytes();
      final ext = path.contains('.') ? path.split('.').last.toLowerCase() : 'm4a';
      return (bytes: bytes, mime: audioMimeOfExt(ext), name: 'voice.$ext', duration: duration);
    } finally {
      // الملف المؤقت لم يعد لازماً بعد قراءة بايتاته
      await deleteQuietly(path);
    }
  }

  @override
  Future<void> cancel() async {
    _startedAt = null;
    if (kIsWeb && _web != null) {
      final rec = _web!;
      _web = null;
      await rec.cancel();
      return;
    }
    final path = _path;
    _path = null;
    await _nativeRec?.cancel();
    await deleteQuietly(path);
  }

  @override
  void dispose() {
    _nativeRec?.dispose();
    final path = _path;
    _path = null;
    deleteQuietly(path);
  }
}
