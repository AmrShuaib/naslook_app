import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'encode.dart';

/// فلاتر الصور الخمسة (مع الأصلي) كمصفوفات ألوان: تُعاين حياً بـ[ColorFiltered] وتُخبَز في الصورة قبل الرفع
/// حتى يرى الجميع النتيجة نفسها بلا اعتماد على العارض.
class PhotoFilter {
  final String id, label, hint;
  /// معاملات المعالجة: سطوع، تباين، تشبّع، سيبيا، ميل لوني (دافئ موجب، بارد سالب)
  final double brightness, contrast, saturation, sepia, warmth;
  const PhotoFilter(this.id, this.label, this.hint, {this.brightness = 1, this.contrast = 1, this.saturation = 1, this.sepia = 0, this.warmth = 0});
}

const photoFilters = [
  PhotoFilter('none', 'الأصلي', 'الصورة كما التُقطت'),
  PhotoFilter('clear', 'صافي', 'المنتجات والطعام', brightness: 1.08, contrast: 1.14, saturation: 1.05),
  PhotoFilter('warm', 'دافئ', 'المقاهي والغروب', brightness: 1.04, saturation: 1.3, sepia: .28, warmth: .06),
  PhotoFilter('cool', 'بارد', 'التقنية والفخامة', brightness: 1.03, contrast: 1.05, saturation: .95, warmth: -.12),
  PhotoFilter('vivid', 'حيوي', 'الهدايا والأعمال اليدوية', brightness: 1.02, contrast: 1.12, saturation: 1.7),
  PhotoFilter('mono', 'أبيض وأسود', 'البورتريه والاقتباسات', brightness: 1.02, contrast: 1.15, saturation: 0),
];

PhotoFilter filterById(String? id) => photoFilters.firstWhere((f) => f.id == id, orElse: () => photoFilters.first);

/// ضبط يدوي فوق الفلتر: كل قيمة بين -1 و1 (0 = بلا تغيير).
class PhotoAdjust {
  final double brightness, contrast, warmth;
  const PhotoAdjust({this.brightness = 0, this.contrast = 0, this.warmth = 0});
  bool get isNeutral => brightness == 0 && contrast == 0 && warmth == 0;
  PhotoAdjust copyWith({double? brightness, double? contrast, double? warmth}) => PhotoAdjust(brightness: brightness ?? this.brightness, contrast: contrast ?? this.contrast, warmth: warmth ?? this.warmth);
  Map<String, dynamic> toJson() => {'brightness': brightness, 'contrast': contrast, 'warmth': warmth};
  factory PhotoAdjust.fromJson(Map? m) => m == null ? const PhotoAdjust() : PhotoAdjust(brightness: (m['brightness'] as num?)?.toDouble() ?? 0, contrast: (m['contrast'] as num?)?.toDouble() ?? 0, warmth: (m['warmth'] as num?)?.toDouble() ?? 0);
}

// ---- مصفوفات 4×5 (كما تتوقعها ColorFilter.matrix): ضرب واحد لكل خطوة ثم دمجها
List<double> _identity() => [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0];

List<double> _mul(List<double> a, List<double> b) {
  // النتيجة = a ∘ b (تطبيق b ثم a)
  final out = List<double>.filled(20, 0);
  for (var r = 0; r < 4; r++) {
    for (var c = 0; c < 5; c++) {
      var v = 0.0;
      for (var k = 0; k < 4; k++) {
        v += a[r * 5 + k] * b[k * 5 + c];
      }
      if (c == 4) v += a[r * 5 + 4];
      out[r * 5 + c] = v;
    }
  }
  return out;
}

List<double> _brightness(double b) => [b, 0, 0, 0, 0, 0, b, 0, 0, 0, 0, 0, b, 0, 0, 0, 0, 0, 1, 0];
List<double> _contrast(double c) {
  final t = 128 * (1 - c);
  return [c, 0, 0, 0, t, 0, c, 0, 0, t, 0, 0, c, 0, t, 0, 0, 0, 1, 0];
}
List<double> _saturation(double s) {
  const lr = .2126, lg = .7152, lb = .0722;
  final sr = (1 - s) * lr, sg = (1 - s) * lg, sb = (1 - s) * lb;
  return [sr + s, sg, sb, 0, 0, sr, sg + s, sb, 0, 0, sr, sg, sb + s, 0, 0, 0, 0, 0, 1, 0];
}
List<double> _sepia(double a) {
  final i = 1 - a;
  return [
    .393 * a + i, .769 * a, .189 * a, 0, 0,
    .349 * a, .686 * a + i, .168 * a, 0, 0,
    .272 * a, .534 * a, .131 * a + i, 0, 0,
    0, 0, 0, 1, 0,
  ];
}
/// ميل لوني: موجب يرفع الأحمر ويخفض الأزرق (دفء)، سالب يفعل العكس (برودة)
List<double> _warmth(double w) => [1 + w, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1 - w, 0, 0, 0, 0, 0, 1, 0];

/// مصفوفة الفلتر مع الضبط اليدوي؛ [ColorFilter.matrix] تأخذها مباشرة.
List<double> filterMatrix(PhotoFilter f, PhotoAdjust adjust) {
  var m = _identity();
  final bright = f.brightness * (1 + adjust.brightness * .5);
  final contrast = f.contrast * (1 + adjust.contrast * .5);
  final warmth = f.warmth + adjust.warmth * .15;
  if (f.saturation != 1) m = _mul(_saturation(f.saturation), m);
  if (f.sepia > 0) m = _mul(_sepia(f.sepia), m);
  if (warmth != 0) m = _mul(_warmth(warmth), m);
  if (contrast != 1) m = _mul(_contrast(contrast), m);
  if (bright != 1) m = _mul(_brightness(bright), m);
  return m;
}

bool isIdentityLook(PhotoFilter f, PhotoAdjust adjust) => f.id == 'none' && adjust.isNeutral;

ColorFilter? colorFilterFor(PhotoFilter f, PhotoAdjust adjust) => isIdentityLook(f, adjust) ? null : ColorFilter.matrix(filterMatrix(f, adjust));

/// قصّ ودوران: نسبة الإطار (null = كما هي) ودوران بربع لفّة (0..3) في اتجاه عقارب الساعة.
class PhotoFrame {
  final double? aspect;
  final int quarterTurns;
  const PhotoFrame({this.aspect, this.quarterTurns = 0});
  bool get isNeutral => aspect == null && quarterTurns % 4 == 0;
  PhotoFrame copyWith({double? aspect, bool clearAspect = false, int? quarterTurns}) => PhotoFrame(aspect: clearAspect ? null : (aspect ?? this.aspect), quarterTurns: quarterTurns ?? this.quarterTurns);
}

/// نِسب القصّ المتاحة في المحرّر
const photoAspects = <(String, double?)>[('أصلي', null), ('مربع', 1), ('٤:٥', .8), ('٩:١٦', 9 / 16)];

typedef BakedPhoto = ({Uint8List bytes, String mime, String name});

/// بديل للاختبارات: فكّ الصور ورسمها يحتاج زمناً حقيقياً لا يتوفر في اختبارات الودجات.
Future<BakedPhoto> Function(Uint8List src, {required PhotoFilter filter, PhotoAdjust adjust, PhotoFrame frame, String name, String mime})? bakePhotoOverride;

/// يخبز الفلتر والضبط والقصّ والدوران في الصورة ويعيد JPEG (على الويب) أو PNG (غيره).
/// تُعاد البايتات الأصلية كما هي إن لم يكن هناك أي تعديل.
Future<BakedPhoto> bakePhoto(Uint8List src, {required PhotoFilter filter, PhotoAdjust adjust = const PhotoAdjust(), PhotoFrame frame = const PhotoFrame(), String name = 'photo.jpg', String mime = 'image/jpeg'}) async {
  if (isIdentityLook(filter, adjust) && frame.isNeutral) return (bytes: src, mime: mime, name: name);
  final o = bakePhotoOverride;
  if (o != null) return o(src, filter: filter, adjust: adjust, frame: frame, name: name, mime: mime);
  final codec = await ui.instantiateImageCodec(src);
  final fi = await codec.getNextFrame();
  final img = fi.image;
  try {
    final turns = frame.quarterTurns % 4;
    final rotated = turns == 1 || turns == 3;
    final sw = img.width.toDouble(), sh = img.height.toDouble();
    // أبعاد الصورة بعد الدوران
    final rw = rotated ? sh : sw, rh = rotated ? sw : sh;
    // مستطيل القصّ في فضاء الصورة المدارة (مركزي)
    var cw = rw, ch = rh;
    final a = frame.aspect;
    if (a != null) {
      if (rw / rh > a) {
        cw = rh * a;
      } else {
        ch = rw / a;
      }
    }
    final ox = (rw - cw) / 2, oy = (rh - ch) / 2;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    final paint = Paint()..filterQuality = FilterQuality.high;
    final cf = colorFilterFor(filter, adjust);
    if (cf != null) paint.colorFilter = cf;
    canvas.translate(-ox, -oy);
    // دوران حول مركز الإطار المدار
    canvas.translate(rw / 2, rh / 2);
    canvas.rotate(turns * 3.141592653589793 / 2);
    canvas.translate(-sw / 2, -sh / 2);
    canvas.drawImage(img, Offset.zero, paint);
    final pic = rec.endRecording();
    final out = await pic.toImage(cw.round().clamp(1, 8000), ch.round().clamp(1, 8000));
    try {
      final enc = await encodeImage(out);
      return (bytes: enc.bytes, mime: enc.mime, name: enc.mime == 'image/png' ? 'photo.png' : 'photo.jpg');
    } finally {
      out.dispose();
    }
  } finally {
    img.dispose();
  }
}
