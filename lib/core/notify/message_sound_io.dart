import 'package:just_audio/just_audio.dart';

import '../media/native_io.dart';

/// جرس الرسائل على iOS/Android: ملف صغير مضمّن (assets/sounds/message.m4a) عبر just_audio.
/// على سطح المكتب (ومنه بيئة الاختبار) لا يوجد مشغّل، فيبقى غير مدعوم.
const messageSoundAsset = 'assets/sounds/message.m4a';

AudioPlayer? _player;
Future<void>? _loading;

bool soundSupported() => isNativeMobile;

/// يجهّز المشغّل مبكراً حتى لا يتأخر أول جرس.
void soundPrepare() {
  if (!isNativeMobile) return;
  _ensure();
}

Future<void> _ensure() {
  final l = _loading;
  if (l != null) return l;
  _player?.dispose();
  // لا نتولى جلسة الصوت ولا مقاطعاتها: الجرس قصير ولا يجوز أن يوقف تسجيلاً أو رسالة صوتية تُسمع
  final p = _player = AudioPlayer(handleInterruptions: false, handleAudioSessionActivation: false);
  final f = p.setAsset(messageSoundAsset).then<void>((_) {}, onError: (Object e) {
    _loading = null; // نعيد المحاولة في الجرس التالي
    throw e;
  });
  f.catchError((Object _) {});
  return _loading = f;
}

void soundPlay() {
  if (!isNativeMobile) return;
  () async {
    try {
      await _ensure();
      final p = _player;
      if (p == null) return;
      await p.seek(Duration.zero);
      await p.play();
      await p.pause();
    } catch (_) {
      // تعذّر التشغيل (مثلاً أثناء مكالمة): نتجاهل بصمت
    }
  }();
}
