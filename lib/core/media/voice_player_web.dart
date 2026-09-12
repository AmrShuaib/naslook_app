import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'voice_player.dart';

VoicePlayer createPlayer() => _WebVoicePlayer();

/// عنصر `<audio>` أصلي: play() يُستدعى فوراً داخل حدث اللمس حتى يقبله iOS Safari.
class _WebVoicePlayer extends VoicePlayerBase {
  final web.HTMLAudioElement _el = web.HTMLAudioElement();
  String? _blobUrl;

  _WebVoicePlayer() {
    _el.preload = 'auto';
    _el.setAttribute('playsinline', 'true');
    void on(String type, void Function() f) => _el.addEventListener(type, ((web.Event _) => f()).toJS);
    on('play', () => emit(state.copyWith(playing: true, clearError: true)));
    on('playing', () => emit(state.copyWith(playing: true, loading: false)));
    on('pause', () => emit(state.copyWith(playing: false, loading: false)));
    on('waiting', () => emit(state.copyWith(loading: true)));
    on('canplay', () => emit(state.copyWith(loading: false)));
    on('timeupdate', () => emit(state.copyWith(position: _pos)));
    on('durationchange', () => emit(state.copyWith(duration: _dur)));
    on('loadedmetadata', () => emit(state.copyWith(duration: _dur)));
    on('ended', () {
      _el.currentTime = 0;
      emit(state.copyWith(playing: false, loading: false, position: Duration.zero));
    });
    on('error', () => emit(state.copyWith(playing: false, loading: false, error: _el.error?.message.isNotEmpty == true ? _el.error!.message : 'media-error')));
  }

  Duration get _pos {
    final t = _el.currentTime;
    return t.isFinite ? Duration(milliseconds: (t * 1000).round()) : Duration.zero;
  }

  Duration? get _dur {
    final d = _el.duration;
    return d.isFinite && d > 0 ? Duration(milliseconds: (d * 1000).round()) : null;
  }

  @override
  void setSource({String? url, Uint8List? bytes, String? mime}) {
    _revoke();
    if (bytes != null) {
      // blob: مسموح في media-src للموقع، بخلاف data: الذي تحجبه سياسة CSP
      final blob = web.Blob(<JSAny>[bytes.toJS].toJS, web.BlobPropertyBag(type: mime ?? 'audio/webm'));
      _blobUrl = web.URL.createObjectURL(blob);
      _el.src = _blobUrl!;
    } else if (url != null) {
      _el.src = url;
    }
    emit(const VoiceState());
  }

  @override
  Future<void> play() async {
    // يجب أن يسبق أي await حتى يُحتسب ضمن حدث المستخدم
    final p = _el.play();
    emit(state.copyWith(loading: true, clearError: true));
    try {
      await p.toDart;
    } catch (e) {
      emit(state.copyWith(playing: false, loading: false, error: e));
      rethrow;
    }
  }

  @override
  Future<void> pause() async => _el.pause();

  @override
  Future<void> seek(Duration position) async {
    _el.currentTime = position.inMilliseconds / 1000;
    emit(state.copyWith(position: position));
  }

  void _revoke() {
    final u = _blobUrl;
    if (u != null) {
      web.URL.revokeObjectURL(u);
      _blobUrl = null;
    }
  }

  @override
  void dispose() {
    _el.pause();
    _el.removeAttribute('src');
    _el.load();
    _revoke();
    super.dispose();
  }
}
