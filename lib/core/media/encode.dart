import 'dart:typed_data';
import 'dart:ui' as ui;

import 'encode_stub.dart' if (dart.library.js_interop) 'encode_web.dart' as impl;

/// صورة مشفّرة جاهزة للرفع.
typedef EncodedImage = ({Uint8List bytes, String mime});

/// يشفّر صورة مرسومة إلى JPEG: عبر canvas على الويب، وعبر حزمة image على iOS/Android.
Future<EncodedImage> encodeImage(ui.Image image) => impl.encodeImage(image);

/// يقصّ تسجيلاً صوتياً بين [start] و[end]: على الويب يُفكّ عبر Web Audio ويُعاد ترميزه WAV (الخادم يحوّله بعد الرفع)؛
/// على غيره يُعاد كما هو (بلا قصّ)، لذلك تُخفى مقابض القصّ هناك (انظر [audioTrimSupported]).
Future<({Uint8List bytes, String mime, String name})> trimAudio(Uint8List bytes, String mime, {required Duration start, required Duration end}) => impl.trimAudio(bytes, mime, start: start, end: end);

/// هل يقصّ [trimAudio] فعلاً على هذه المنصة؟ (الويب نعم، الأصلي لا بعد).
bool get audioTrimSupported => impl.audioTrimSupported;
