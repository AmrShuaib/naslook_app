import 'package:audio_session/audio_session.dart';

import 'native_io.dart';

bool _configured = false;

/// يضبط جلسة الصوت مرة واحدة عند الإقلاع على iOS/Android فقط (لا على الويب ولا في الاختبارات).
///
/// نستخدم فئة التشغيل للكلام (playback/spokenAudio) لا playAndRecord: الأولى تُسمع الرسائل الصوتية رغم مفتاح الصامت
/// وتخرج من السماعة، والثانية قد تُظهر طلب إذن الميكروفون عند أول تشغيل لرسالة. أثناء التسجيل تضبط حزمة record
/// الجلسة بنفسها (playAndRecord + defaultToSpeaker) فيبقى الصوت بعدها على السماعة الخارجية.
Future<void> configureAudioSession() async {
  if (_configured || !isNativeMobile) return;
  _configured = true;
  try {
    final s = await AudioSession.instance;
    await s.configure(const AudioSessionConfiguration.speech());
  } catch (_) {
    // فشل الضبط لا يمنع التشغيل؛ يبقى الإعداد الافتراضي للنظام
  }
}
