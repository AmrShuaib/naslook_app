import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:web/web.dart' as web;

import 'video_pool.dart';
import 'voice_player.dart';

VoicePlayer createPlayer() => _WebVoicePlayer(web.HTMLAudioElement());

// --- عناصر الصوت المفتوحة لعارض اللحظات (سفاري iOS) ------------------------------------------------------------
// الطبقة الصوتية على صورة أو نص تبدأ وحدها حين تظهر اللحظة، وWebKit لا يقبل الصوت بلا لمسة إلا لعنصر شُغّل داخل لمسة.
// فعارض اللحظات يأخذ عنصراً واحداً من مجمّع يُعاد استعماله طوال جلسته ويغيّر مصدره لكل لحظة، وكل pointerup في التطبيق
// يفتح العناصر الحرة (كمجمّع عناصر الفيديو في video_view_web.dart).

MediaSlotPool<web.HTMLAudioElement>? _pool;

MediaSlotPool<web.HTMLAudioElement> _soundPool() {
  final existing = _pool;
  if (existing != null) return existing;
  // عنصر حر واحد يكفي: العارض يملك عنصراً واحداً لجلسته، والثاني لعارض يُفتح فوقه
  final pool = _pool = MediaSlotPool<web.HTMLAudioElement>(create: _newAudio, bless: _bless, spare: 1);
  // المسار العام يُستدعى متزامناً داخل حدث pointerup نفسه (قبل onTap)، فيُحتسب لمسةً عند المتصفح
  GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  return pool;
}

void _onPointer(PointerEvent e) {
  if (e is PointerUpEvent) _pool?.userGesture();
}

void prepareSoundAudio({bool primeNow = false}) {
  final pool = _soundPool();
  if (primeNow) pool.prime();
}

web.HTMLAudioElement _newAudio() => web.HTMLAudioElement();

void _bless(web.HTMLAudioElement a) {
  // تشغيل صامت بلا مصدر ثم إيقاف فوري داخل اللمسة: WebKit يرفع قيد الصوت عن العنصر ولا يُسمع شيء. الصمت حتى لا يوقف
  // iOS فيديو اللحظة المعروضة بالصوت
  a.muted = true;
  final p = a.play();
  a.pause();
  unawaited(p.toDart.then<void>((_) {}, onError: (Object _) {}));
}

VoicePlayer createMomentPlayer() {
  final pool = _soundPool();
  final slot = pool.acquire();
  return _WebVoicePlayer(slot.element, onSounded: () => pool.markBlessed(slot), onRelease: () => pool.release(slot));
}

/// عنصر `<audio>` أصلي: play() يُستدعى فوراً داخل حدث اللمس حتى يقبله iOS Safari.
/// العنصر قد يكون من المجمّع (عارض اللحظات): مستمعوه يُزالون عند التحرير ويعود العنصر مفتوحاً للمشغّل التالي.
class _WebVoicePlayer extends VoicePlayerBase {
  final web.HTMLAudioElement _el;
  /// بدأ بالصوت: العنصر مفتوح (للمجمّع)
  final void Function()? onSounded;
  /// يعيد العنصر إلى المجمّع
  final void Function()? onRelease;
  final _listeners = <(String, JSFunction)>[];
  String? _blobUrl;

  _WebVoicePlayer(this._el, {this.onSounded, this.onRelease}) {
    _el.preload = 'auto';
    _el.setAttribute('playsinline', 'true');
    // عنصر المجمّع فُتح صامتاً
    _el.muted = false;
    _el.removeAttribute('muted');
    void on(String type, void Function() f) {
      final js = ((web.Event _) => f()).toJS;
      _listeners.add((type, js));
      _el.addEventListener(type, js);
    }

    on('play', () => emit(state.copyWith(playing: true, ended: false, clearError: true)));
    on('playing', () => emit(state.copyWith(playing: true, loading: false)));
    on('pause', () => emit(state.copyWith(playing: false, loading: false)));
    on('waiting', () => emit(state.copyWith(loading: true)));
    on('canplay', () => emit(state.copyWith(loading: false)));
    on('timeupdate', () => emit(state.copyWith(position: _pos)));
    on('durationchange', () => emit(state.copyWith(duration: _dur)));
    on('loadedmetadata', () => emit(state.copyWith(duration: _dur)));
    on('ended', () {
      _el.currentTime = 0;
      emit(state.copyWith(playing: false, loading: false, ended: true, position: Duration.zero));
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
    emit(state.copyWith(loading: true, ended: false, clearError: true));
    try {
      await p.toDart;
      if (!_el.muted) onSounded?.call();
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
    for (final (type, js) in _listeners) {
      _el.removeEventListener(type, js);
    }
    _listeners.clear();
    _el.pause();
    _el.removeAttribute('src');
    _el.load();
    _revoke();
    onRelease?.call();
    super.dispose();
  }
}
