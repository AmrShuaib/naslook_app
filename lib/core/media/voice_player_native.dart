import 'dart:async';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

import 'native_io.dart';
import 'voice_player.dart';

VoicePlayer createPlayer() => _NativeVoicePlayer();

/// خارج الويب لا قيد على الصوت بلا لمسة: مشغّل عادي
VoicePlayer createMomentPlayer() => _NativeVoicePlayer();

void prepareSoundAudio({bool primeNow = false}) {}

/// مشغّل just_audio (iOS/Android/سطح المكتب).
class _NativeVoicePlayer extends VoicePlayerBase {
  final AudioPlayer _p = AudioPlayer();
  Future<void>? _loaded;
  /// يُزاد مع كل play() وpause(): تشغيل ينتظر التحميل لا يبدأ إن جاء بعده إيقاف
  int _playReq = 0;
  String? _tmp;
  bool _disposed = false;
  final _subs = <StreamSubscription<dynamic>>[];

  _NativeVoicePlayer() {
    _subs.add(_p.positionStream.listen((d) => emit(state.copyWith(position: d))));
    _subs.add(_p.durationStream.listen((d) => emit(state.copyWith(duration: d))));
    _subs.add(_p.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) {
        _p.seek(Duration.zero);
        _p.pause();
        emit(state.copyWith(playing: false, loading: false, ended: true, position: Duration.zero));
        return;
      }
      emit(state.copyWith(playing: s.playing, loading: _busyIn(s.processingState)));
    }));
  }

  static bool _busyIn(ProcessingState s) => s == ProcessingState.loading || s == ProcessingState.buffering;

  @override
  void setSource({String? url, Uint8List? bytes, String? mime}) {
    Future<Duration?>? f;
    final old = _tmp;
    _tmp = null;
    deleteQuietly(old);
    if (bytes != null) {
      // just_audio على iOS/Android لا يدعم روابط data:، فنكتب البايتات في ملف مؤقت ونشغّله
      f = writeTempFile(bytes, prefix: 'vp', ext: audioExt(mime)).then((path) {
        if (_disposed) {
          deleteQuietly(path);
          throw StateError('disposed');
        }
        _tmp = path;
        return _p.setFilePath(path);
      });
    } else if (url != null) {
      f = _p.setUrl(url);
    }
    _loaded = f?.then((_) {});
    // الخطأ يُلتقط عند play()؛ هنا فقط نمنع "unhandled exception"
    _loaded?.catchError((_) {});
    emit(const VoiceState());
  }

  @override
  Future<void> play() async {
    // تحميل هذا المصدر: إن غُيّر المصدر أثناء الانتظار (عارض اللحظات ينتقل إلى لحظة أخرى بتسجيل) فخطأ التحميل القديم
    // (PlayerInterruptedException «Loading interrupted») أو نجاحه المتأخر لا يخص المصدر الجديد، فلا يُبلَّغ ولا يُشغَّل
    final loaded = _loaded;
    final req = ++_playReq;
    bool stale(Object e) => e is PlayerInterruptedException || !identical(loaded, _loaded) || _disposed;
    emit(state.copyWith(loading: true, ended: false, clearError: true));
    try {
      await loaded;
      // ولا يبدأ إن أُوقف أثناء التحميل (انتقل العارض إلى لحظة بلا تسجيل أو غُطّي): pause() في just_audio قبل play()
      // لا يمنع play() التي تأتي بعده، بخلاف عنصر <audio> الذي يرفض وعد التشغيل المعلّق
      if (!identical(loaded, _loaded) || _disposed || req != _playReq) return;
      // play() في just_audio لا يكتمل إلا بانتهاء التشغيل أو إيقافه، فلا ننتظره
      unawaited(_p.play().catchError((Object e) {
        if (!stale(e)) emit(state.copyWith(loading: false, playing: false, error: e));
      }));
    } catch (e) {
      if (stale(e)) return;
      emit(state.copyWith(loading: false, playing: false, error: e));
      rethrow;
    }
  }

  @override
  Future<void> pause() {
    _playReq++;
    // إيقاف قبل أن يبدأ تشغيل ينتظر التحميل: لا يصل من just_audio خبر يمسح «يُحمَّل» الذي بلّغه play()
    if (!_p.playing) emit(state.copyWith(loading: _busyIn(_p.processingState)));
    return _p.pause();
  }

  @override
  Future<void> seek(Duration position) => _p.seek(position);

  @override
  void dispose() {
    _disposed = true;
    for (final s in _subs) {
      s.cancel();
    }
    _p.dispose();
    deleteQuietly(_tmp);
    _tmp = null;
    super.dispose();
  }
}
