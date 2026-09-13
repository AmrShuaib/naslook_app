import 'dart:js_interop';

import 'package:web/web.dart' as web;

web.AudioContext? _ctx;
bool _prepared = false;

bool soundSupported() => true;

/// يفتح سياق الصوت داخل أول تفاعل للمستخدم (شرط المتصفحات، خصوصاً سفاري) ثم يزيل المستمعين.
void soundPrepare() {
  if (_prepared) return;
  _prepared = true;
  late final JSFunction handler;
  handler = ((web.Event _) {
    _unlock();
    for (final t in const ['pointerdown', 'touchend', 'keydown']) {
      web.window.removeEventListener(t, handler, true.toJS);
    }
  }).toJS;
  for (final t in const ['pointerdown', 'touchend', 'keydown']) {
    web.window.addEventListener(t, handler, true.toJS);
  }
}

web.AudioContext? _unlock() {
  try {
    final c = _ctx ??= web.AudioContext();
    if (c.state != 'running') c.resume();
    return c;
  } catch (_) {
    return null;
  }
}

/// نغمة جرس قصيرة: نغمتان جيبيتان (أساسية وخامسة) بذبذبة خفيفة وتلاشٍ أسّي خلال نصف ثانية.
void soundPlay() {
  final c = _unlock();
  if (c == null) return;
  try {
    final t0 = c.currentTime + 0.01;
    for (final (freq, gainPeak, len) in const [(880.0, 0.22, 0.55), (1318.5, 0.10, 0.35)]) {
      final osc = c.createOscillator();
      final gain = c.createGain();
      osc.type = 'sine';
      osc.frequency.setValueAtTime(freq, t0);
      gain.gain.setValueAtTime(0.0001, t0);
      gain.gain.exponentialRampToValueAtTime(gainPeak, t0 + 0.012);
      gain.gain.exponentialRampToValueAtTime(0.0001, t0 + len);
      osc.connect(gain);
      gain.connect(c.destination);
      osc.start(t0);
      osc.stop(t0 + len + 0.05);
    }
  } catch (_) {
    // سياق الصوت غير مفتوح بعد (لم يلمس المستخدم الصفحة): نتجاهل بصمت
  }
}
