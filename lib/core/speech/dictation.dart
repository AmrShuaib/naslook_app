import 'dictation_stub.dart' if (dart.library.js_interop) 'dictation_web.dart' as impl;

/// نص إملاء جزئي (isFinal=false) أو نهائي (isFinal=true).
typedef DictationText = void Function(String text, bool isFinal);

/// إملاء صوتي أثناء الكتابة (كلام → نص): على الويب عبر SpeechRecognition في المتصفح باللغة العربية،
/// وغير مدعوم على بقية المنصات حتى يُضاف محرك أصلي. [factoryOverride] يبدّله في الاختبارات.
abstract class Dictation {
  static Dictation Function()? factoryOverride;
  factory Dictation() => factoryOverride?.call() ?? impl.createDictation();

  /// هل الإملاء متاح هنا؟ (البديل الاختباري يُعدّ مدعوماً)
  static bool get supported => factoryOverride != null || impl.supported;

  bool get active;

  /// يبدأ الاستماع: [onText] يصل مع كل جزء ثم بالنص النهائي؛ يتوقف تلقائياً بعد صمت ويُستدعى [onEnd].
  Future<void> start({required DictationText onText, void Function(Object error)? onError, void Function()? onEnd});
  Future<void> stop();
  void dispose();
}
