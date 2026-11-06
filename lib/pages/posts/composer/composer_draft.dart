import 'dart:typed_data';

import '../../../api/posts_api.dart';
import '../../../core/media/filters.dart';

/// لقطة ملتقطة أو مختارة: بايتاتها ونوعها واسمها.
typedef Shot = ({Uint8List bytes, String mime, String name});

/// تسجيل صوتي مرفق بالمنشور (طبقة صوتية).
class VoiceLayer {
  final Uint8List bytes;
  final String mime, name;
  final Duration duration;
  const VoiceLayer({required this.bytes, required this.mime, required this.name, required this.duration});
}

/// قوالب لوحة النص: كل قالب يضبط لون اللوحة ووسماً صغيراً فوق النص.
class BoardTemplate {
  final String id, label, badge, board;
  const BoardTemplate(this.id, this.label, this.badge, this.board);
}

const boardTemplates = [
  BoardTemplate('plain', 'عادي', '', '#FFFFFF'),
  BoardTemplate('question', 'سؤال', 'سؤال', '#FFF4D6'),
  BoardTemplate('alert', 'تنبيه', 'تنبيه', '#FDEBE6'),
  BoardTemplate('quote', 'اقتباس', 'اقتباس', '#E0F3F4'),
];
const boardColors = ['#FFFFFF', '#FFF4D6', '#E0F3F4', '#FDEBE6', '#111111'];

/// أين يُنشر المحتوى: على الخريطة عند موقعك، في مجتمع دائرة، أو كعرض في السوق.
enum Destination { map, circle, market }

/// حالة المحرّر من الالتقاط حتى النشر؛ كائن واحد يتنقّل بين الشاشات الثلاث.
class ComposerDraft {
  /// image | video | text
  String kind;
  final List<Shot> shots;
  int cover;
  Shot? video;
  int? videoSec;
  /// لوحة النص
  String board;
  String template;
  List<PostOverlay> overlays;
  /// الفلتر والضبط والقصّ (تُخبز في الصورة عند النشر)
  String filter;
  PhotoAdjust adjust;
  PhotoFrame frame;
  VoiceLayer? voice;
  /// النشر
  String caption;
  Destination destination;
  int ttlHours;
  String placeName;
  double lat, lng;
  // تفاصيل احترافية (اختيارية)
  String tag, title, price, ctaValue, ctaLabel;
  String? ctaType;
  /// من يرى المنشور على الخريطة: 'friends' أو 'all'، وnull = لم يختر الناشر فيُعرض ويُرسل [defaultAudience]
  String? audience;
  // وجهة الدائرة
  String? circleId, circleName;
  // نموذج العرض السريع
  String listingTitle, listingPrice, listingCategory, listingKind;
  bool delivery;
  /// عند تعديل منشور قائم
  final MapPost? editing;

  ComposerDraft({
    required this.lat, required this.lng, this.placeName = '', this.kind = 'image', List<Shot>? shots, this.cover = 0, this.video, this.videoSec,
    this.board = '#FFFFFF', this.template = 'plain', List<PostOverlay>? overlays, this.filter = 'none', this.adjust = const PhotoAdjust(), this.frame = const PhotoFrame(), this.voice,
    this.caption = '', this.destination = Destination.map, this.ttlHours = 24, this.tag = 'moment', this.title = '', this.price = '', this.ctaType, this.ctaValue = '', this.ctaLabel = '',
    this.circleId, this.circleName, this.listingTitle = '', this.listingPrice = '', this.listingCategory = 'other', this.listingKind = 'product', this.delivery = false, this.editing,
    String? audience,
  })  : shots = shots ?? [],
        overlays = overlays ?? [],
        // تعديل منشور قائم يبدأ بجمهوره الحالي
        audience = audience ?? editing?.audience;

  Shot? get coverShot => shots.isEmpty ? null : shots[cover.clamp(0, shots.length - 1)];
  bool get isText => kind == 'text';
  bool get isVideo => kind == 'video';
  bool get hasPro => tag != 'moment' || title.isNotEmpty || price.isNotEmpty || ctaType != null;
  /// زر الإجراء يُرسل فعلاً (كما في شاشة النشر): «مراسلة» بلا قيمة، وغيره بقيمة
  bool get hasCta => ctaType != null && (ctaType == 'chat' || ctaValue.isNotEmpty);
  /// الافتراضي بقاعدة الخادم نفسها (defaultAudience في server/map_posts.js، قرار المالك): اللحظة الشخصية للأصدقاء، والمنشور التجاري
  /// (نوع غير «لحظة» أو بسعر أو بزر إجراء) للجميع لأن غايته الوصول
  String get defaultAudience => tag != 'moment' || price.isNotEmpty || hasCta ? 'all' : 'friends';
  String get effectiveAudience => audience ?? defaultAudience;
  bool get hasContent => isText ? (overlays.any((o) => !o.isSticker) || caption.isNotEmpty || voice != null) : isVideo ? video != null : shots.isNotEmpty || editing != null;
}
