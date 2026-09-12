import 'dart:async';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

import 'voice_player.dart';

VoicePlayer createPlayer() => _NativeVoicePlayer();

/// مشغّل just_audio (iOS/Android/سطح المكتب).
class _NativeVoicePlayer extends VoicePlayerBase {
  final AudioPlayer _p = AudioPlayer();
  Future<void>? _loaded;
  final _subs = <StreamSubscription<dynamic>>[];

  _NativeVoicePlayer() {
    _subs.add(_p.positionStream.listen((d) => emit(state.copyWith(position: d))));
    _subs.add(_p.durationStream.listen((d) => emit(state.copyWith(duration: d))));
    _subs.add(_p.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) {
        _p.seek(Duration.zero);
        _p.pause();
        emit(state.copyWith(playing: false, loading: false, position: Duration.zero));
        return;
      }
      emit(state.copyWith(playing: s.playing, loading: s.processingState == ProcessingState.loading || s.processingState == ProcessingState.buffering));
    }));
  }

  @override
  void setSource({String? url, Uint8List? bytes, String? mime}) {
    Future<Duration?>? f;
    if (bytes != null) {
      f = _p.setAudioSource(AudioSource.uri(Uri.dataFromBytes(bytes, mimeType: mime ?? 'audio/webm')));
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
    emit(state.copyWith(loading: true, clearError: true));
    try {
      await _loaded;
      // play() في just_audio لا يكتمل إلا بانتهاء التشغيل أو إيقافه، فلا ننتظره
      unawaited(_p.play().catchError((Object e) => emit(state.copyWith(loading: false, playing: false, error: e))));
    } catch (e) {
      emit(state.copyWith(loading: false, playing: false, error: e));
      rethrow;
    }
  }

  @override
  Future<void> pause() => _p.pause();

  @override
  Future<void> seek(Duration position) => _p.seek(position);

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _p.dispose();
    super.dispose();
  }
}
