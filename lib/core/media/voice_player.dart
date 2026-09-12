import 'dart:async';
import 'dart:typed_data';

import 'voice_player_native.dart' if (dart.library.js_interop) 'voice_player_web.dart' as impl;

/// لقطة من حالة مشغّل الصوت.
class VoiceState {
  final bool playing, loading;
  final Duration position;
  final Duration? duration;
  final Object? error;
  const VoiceState({this.playing = false, this.loading = false, this.position = Duration.zero, this.duration, this.error});

  VoiceState copyWith({bool? playing, bool? loading, Duration? position, Duration? duration, Object? error, bool clearError = false}) => VoiceState(
        playing: playing ?? this.playing,
        loading: loading ?? this.loading,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        error: clearError ? null : (error ?? this.error),
      );
}

/// مشغّل صوت للرسائل الصوتية وبطاقات التسجيل.
///
/// على الويب يغلّف عنصر `<audio>` أصلياً ويستدعي play() فور اللمس وقبل أي انتظار، لأن iOS Safari يرفض بدء
/// التشغيل خارج حدث المستخدم (NotAllowedError) وهو ما كان يحدث مع just_audio بعد انتظار التحميل.
/// على المنصات الأخرى يغلّف just_audio.
abstract class VoicePlayer {
  /// بديل للاختبارات: يُستدعى بدل المشغّل الحقيقي إن عُيّن.
  static VoicePlayer Function()? factoryOverride;
  factory VoicePlayer() => factoryOverride?.call() ?? impl.createPlayer();

  VoiceState get state;
  Stream<VoiceState> get changes;

  /// يحدد المصدر: رابط، أو بايتات محلية (معاينة قبل الرفع). لا ينتظر التحميل.
  void setSource({String? url, Uint8List? bytes, String? mime});

  /// يبدأ التشغيل. يُستدعى مباشرة داخل معالج اللمس (بلا await قبله). يرمي إن رُفض التشغيل أو تعذّر التحميل.
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  void dispose();
}

/// قاعدة مشتركة: الحالة الحالية وبثّ التغييرات.
abstract class VoicePlayerBase implements VoicePlayer {
  final _ctrl = StreamController<VoiceState>.broadcast();
  VoiceState _state = const VoiceState();

  @override
  VoiceState get state => _state;
  @override
  Stream<VoiceState> get changes => _ctrl.stream;

  void emit(VoiceState s) {
    _state = s;
    if (!_ctrl.isClosed) _ctrl.add(s);
  }

  @override
  void dispose() {
    _ctrl.close();
  }
}
