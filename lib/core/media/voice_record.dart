import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:record/record.dart';

import 'media.dart';

/// تسجيل صوتي مكتمل: بايتاته ونوعه واسمه ومدته.
typedef RecordedVoice = ({Uint8List bytes, String mime, String name, Duration duration});

/// الحد الأقصى لتسجيل صوتي واحد.
const maxVoiceRecord = Duration(minutes: 5);

/// جلسة تسجيل صوتي واحدة: على الويب عبر MediaRecorder في المتصفح، وعلى المنصات الأخرى عبر حزمة record.
/// تُستخدم في المحادثات ومساحات المجتمع؛ [factoryOverride] يُبدّلها في الاختبارات.
abstract class VoiceRecordSession {
  static VoiceRecordSession Function()? factoryOverride;
  factory VoiceRecordSession() => factoryOverride?.call() ?? _RealVoiceRecordSession();

  bool get recording;
  Duration get elapsed;

  /// يطلب إذن الميكروفون ويبدأ التسجيل. يرمي إن رُفض الإذن.
  Future<void> start();

  /// يوقف التسجيل ويعيد الملف، أو null إن لم يُسجَّل شيء.
  Future<RecordedVoice?> stop();
  Future<void> cancel();
  void dispose();
}

class _RealVoiceRecordSession implements VoiceRecordSession {
  final _native = AudioRecorder();
  VoiceRecorder? _web;
  DateTime? _startedAt;

  @override
  bool get recording => _startedAt != null;
  @override
  Duration get elapsed => _startedAt == null ? Duration.zero : DateTime.now().difference(_startedAt!);

  @override
  Future<void> start() async {
    if (kIsWeb && WebMedia.available) {
      _web = VoiceRecorder();
      await _web!.start();
    } else {
      if (!await _native.hasPermission()) throw StateError('اسمح بالوصول إلى الميكروفون أولاً');
      await _native.start(const RecordConfig(encoder: AudioEncoder.opus, bitRate: 64000, sampleRate: 48000, numChannels: 1), path: '');
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
    final path = await _native.stop();
    if (path == null) return null;
    final bytes = await XFile(path).readAsBytes();
    final ext = path.split('.').last.toLowerCase();
    final mime = switch (ext) { 'm4a' || 'mp4' || 'aac' => 'audio/mp4', 'ogg' || 'oga' || 'opus' => 'audio/ogg', 'wav' => 'audio/wav', 'mp3' => 'audio/mpeg', _ => 'audio/webm' };
    return (bytes: bytes, mime: mime, name: 'voice.$ext', duration: duration);
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
    await _native.cancel();
  }

  @override
  void dispose() {
    _native.dispose();
  }
}
