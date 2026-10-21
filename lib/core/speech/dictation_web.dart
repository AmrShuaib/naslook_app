import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'dictation.dart';

/// منشئ SpeechRecognition: كروم وسفاري يعرّفانه بالسابقة webkit فلا يكفي الاسم القياسي
JSFunction? _ctor() {
  for (final name in const ['SpeechRecognition', 'webkitSpeechRecognition']) {
    final v = web.window.getProperty<JSAny?>(name.toJS);
    if (v != null && v.isA<JSFunction>()) return v as JSFunction;
  }
  return null;
}

bool get supported => _ctor() != null;

Dictation createDictation() => _WebDictation();

class _WebDictation implements Dictation {
  web.SpeechRecognition? _rec;

  @override
  bool get active => _rec != null;

  @override
  Future<void> start({required DictationText onText, void Function(Object error)? onError, void Function()? onEnd}) async {
    final ctor = _ctor();
    if (ctor == null) throw UnsupportedError('الإملاء غير مدعوم في هذا المتصفح');
    await stop();
    final rec = ctor.callAsConstructor<web.SpeechRecognition>();
    rec.lang = 'ar-SA';
    // جملة واحدة في كل مرة مع نتائج مؤقتة تظهر أثناء الكلام
    rec.continuous = false;
    rec.interimResults = true;
    rec.onresult = ((web.SpeechRecognitionEvent e) {
      final results = e.results;
      final finals = StringBuffer(), interim = StringBuffer();
      for (var i = 0; i < results.length; i++) {
        final r = results.item(i);
        final t = r.length > 0 ? r.item(0).transcript : '';
        if (r.isFinal) {
          finals.write(t);
        } else {
          interim.write(t);
        }
      }
      final isFinal = interim.isEmpty && finals.isNotEmpty;
      onText('$finals$interim'.trim(), isFinal);
    }).toJS;
    rec.onerror = ((web.SpeechRecognitionErrorEvent e) {
      onError?.call(StateError(e.error));
    }).toJS;
    rec.onend = ((web.Event _) {
      if (identical(_rec, rec)) _rec = null;
      onEnd?.call();
    }).toJS;
    _rec = rec;
    rec.start();
  }

  @override
  Future<void> stop() async {
    final rec = _rec;
    _rec = null;
    if (rec == null) return;
    try {
      rec.stop();
    } catch (_) {}
  }

  @override
  void dispose() {
    final rec = _rec;
    _rec = null;
    try {
      rec?.abort();
    } catch (_) {}
  }
}
