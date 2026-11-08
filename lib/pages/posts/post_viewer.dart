import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable, listEquals, visibleForTesting;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/client.dart' show ApiException, mediaUrl;
import '../../api/commerce_models.dart';
import '../../api/posts_api.dart';
import '../../api/naslife_api.dart';
import '../../core/app_theme.dart';
import '../../core/media/video_view.dart' show VideoSuspend, VideoView, VideoViewController;
import '../../core/media/voice_player.dart';
import '../../core/require_account.dart';
import '../../state/app_state.dart';
import '../../state/posts_providers.dart';
import '../../state/safety_providers.dart';
import '../../ui/profile_avatar.dart';
import '../../ui/report_sheet.dart';
import '../../ui/widgets.dart';
import '../business/business_page.dart';
import '../chat/chat_thread_page.dart';
import '../market/market_page.dart';
import 'composer/voice_layer.dart';
import 'moment_actions.dart';
import 'overlay_canvas.dart';
import 'post_composer.dart';
import 'post_stats.dart';
import 'post_media.dart';

String _msg(Object e) => e is ApiException ? e.message : e.toString();

/// صوت يقوده العارض: طبقة صوتية على صورة أو نص (الفيديو له صوته)
bool _drivesVoice(MapPost p) => (p.kind == 'image' || p.kind == 'text') && (p.audioUrl ?? '').isNotEmpty;

/// ينفّذ زر الإجراء في المنشور: رابط، واتساب، اتصال، دائرة تجارية، عرض في السوق، مراسلة صاحب المنشور.
Future<void> runPostCta(BuildContext context, MapPost p) async {
  final c = p.cta;
  if (c == null) return;
  try {
    await _runCta(context, c, p);
  } catch (_) {
    if (context.mounted) toast(context, 'تعذر فتح الرابط على هذا الجهاز', error: true);
  }
}

Future<void> _runCta(BuildContext context, PostCta c, MapPost p) async {
  switch (c.type) {
    case 'link':
      await launchUrl(Uri.parse(c.value), mode: LaunchMode.externalApplication);
    case 'whatsapp':
      final d = c.value.replaceAll(RegExp(r'\D'), '');
      final intl = d.startsWith('0') ? '966${d.substring(1)}' : d;
      await launchUrl(Uri.parse('https://wa.me/$intl'), mode: LaunchMode.externalApplication);
    case 'call':
      await launchUrl(Uri.parse('tel:${c.value}'));
    case 'biz':
      if (context.mounted) openBusiness(context, c.value);
    case 'market':
      if (context.mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => ListingPage(c.value)));
    case 'chat':
      // المحادثة تطلب مسارات النواة فوراً؛ الزائر يُدعى للدخول قبل فتحها
      if (context.mounted && requireAccount(context)) Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadPage(peer: p.user)));
  }
}

/// عارض منشورات الخريطة بملء الشاشة: تمرير بين المنشورات، تقدّم تلقائي للصور والنصوص، إعجاب ومشاهدات، زر الإجراء، وأدوات صاحب المنشور.
class PostViewerPage extends ConsumerStatefulWidget {
  final List<MapPost> posts;
  final int initial;
  const PostViewerPage({super.key, required this.posts, this.initial = 0});

  static Future<void> open(BuildContext context, List<MapPost> posts, {int index = 0}) {
    if (posts.isEmpty) return Future.value();
    primeSound();
    return Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => PostViewerPage(posts: posts, initial: index.clamp(0, posts.length - 1))));
  }

  /// يستدعيه [open]: يفتح فتحاً مبدئياً عنصر الصوت وعناصر الفيديو الحرة التي لم تفتحها لمسة بعد (عارض يُفتح بلا لمسة، من
  /// رابط)، لأن سفاري iOS لا يقبل التشغيل بالصوت بلا لمسة إلا لعنصر شُغّل داخل لمسة. الفتح المؤكد من pointerup اللمسة
  /// نفسها (المجمّعان يُنشآن في main())، فيصح ولو فُتح العارض بعد انتظار. بلا أثر خارج الويب.
  static void primeSound() {
    VoicePlayer.prepareSound(primeNow: true);
    VideoView.prepareSound(primeNow: true);
  }

  /// بديل الاختبار لجلب صورة الألبوم التالية مسبقاً (precacheImage لا أثر له يُقاس في اختبار الودجات)
  @visibleForTesting
  static void Function(String url)? warmPhotoOverride;

  @override
  ConsumerState<PostViewerPage> createState() => _PostViewerPageState();
}

/// حال الطبقة الصوتية (تعليق صوتي على صورة أو نص) في اللحظة المعروضة.
enum MomentVoicePhase {
  /// طُلب التشغيل ولم يبدأ (يُحمَّل): الشريط ينتظر، وبعد مهلة التحميل تعود اللحظة إلى مدتها العادية
  loading,
  /// يعمل (أو موقوف مؤقتاً لأن العارض مغطّى أو مضغوط): الشريط يتبع موضعه
  playing,
  /// أوقفه المستخدم بلمسة الشريحة: اللحظة تنتظر حتى يلمسها ثانية
  paused,
  /// رفض المتصفح التشغيل بلا لمسة: رقاقة «اضغط لتشغيل الصوت» واللحظة تنتظر
  blocked,
  /// انتهى التسجيل؛ الأقصر من سبع ثوانٍ تكمل لحظته مدتها العادية
  ended,
  /// تعذّر التحميل أو التشغيل: اللحظة تكمل مدتها العادية (7 ث)
  failed,
}

/// ما تعرضه اللحظة النشطة من طبقتها الصوتية: الحال، وحالة المشغّل (الموجة والزر)، و[stalled] حين أوقفه المتصفح بنفسه.
@immutable
class MomentVoice {
  final MomentVoicePhase phase;
  final VoiceState state;
  final bool stalled;
  const MomentVoice({required this.phase, this.state = const VoiceState(), this.stalled = false});
}

class _PostViewerPageState extends ConsumerState<PostViewerPage> {
  static const _autoMs = 7000;
  /// الألبوم: أربع ثوانٍ لكل صورة، والمدة سبع ثوانٍ على الأقل (كأي لحظة)
  static const _photoMs = 4000;
  /// مدة اللحظة المعروضة بلا صوت: سبع ثوانٍ، وللألبوم أربع لكل صورة؛ والطبقة الصوتية تمدّها إلى طول التسجيل كما كانت
  int _momentMs = _autoMs;

  // --- الألبوم: السحب يميناً ويساراً بين صوره (النقر بين اللحظات كما كان)، والشريط يقلبها تلقائياً بقدر حصة كل صورة ---
  /// متحكم صفحات ألبوم اللحظة النشطة (null لغير الألبوم)
  PageController? _album;
  /// الصورة المعروضة، وآخر حصة بلغها الشريط: القلب التلقائي إلى الأمام فقط حين يعبر الشريط حصة جديدة
  int _photo = 0, _photoMark = 0;
  /// قلب برمجي جارٍ: لا يُعامل onPageChanged الناتج عنه سحباً من المستخدم
  bool _albumAuto = false;
  /// اللحظة التي يملكها [_album]، والألبوم الذي غادرناه وصورته: onPageChanged يأتي في منتصف انتقال الصفحة، فتبقى الصفحة المغادِرة
  /// على صورتها حتى تستقر الصفحات بدل أن تعود إلى غلافها (وطبقاته ونقطته الأولى) أمام المشاهد في بقية الانتقال
  String? _albumId;
  ({String id, int photo})? _leftAlbum;
  final _warmedPhotos = <String>{};
  late final PageController _ctl = PageController(initialPage: widget.initial);
  late List<MapPost> posts = List.of(widget.posts);
  late int index = widget.initial;
  Timer? _auto;
  double progress = 0;
  final _viewed = <String>{};
  /// متحكم فيديو اللحظة النشطة (null لغير الفيديو): يُنشأ مع كل لحظة ويُحرَّر عند مغادرتها
  VideoViewController? _video;
  StreamSubscription<void>? _videoEnded;
  final _warmed = <String>{};
  late final AppLifecycleListener _life;
  /// مسار العارض نفسه: يُقرأ في didChangeDependencies فيصلنا تغيّر «هل هو الأعلى» حين يُفتح فوقه شيء أو يُغلق
  ModalRoute<Object?>? _route;

  // --- «العارض مغطّى»: مصدر واحد يوقف التقدّم التلقائي والفيديو، ويمنع الانتقال أو الإغلاق خلف ما فوقه ---
  /// أفعال مفتوحة من العارض (القوائم، ورقة المشاركة ثم منتقي المحادثة، الحوارات) بما فيها الفجوة بين ورقة وأخرى؛
  /// عدّاد لا علَم حتى لا يُنهي فعلٌ إيقافَ فعل آخر ما زال مفتوحاً
  int _holds = 0;
  /// التطبيق في الخلفية أو التبويب مخفي
  bool _hidden = false;
  /// ضغطة مطوّلة على صورة أو نص: توقف التقدّم فقط (الفيديو له إيماءاته)
  bool _pressed = false;
  /// انتهت اللحظة والعارض مغطّى: ننتقل حين يظهر بدل أن ننتقل أو نُغلق خلف ما فوقه
  bool _pendingNext = false;

  // --- الطبقة الصوتية لصورة أو نص: تبدأ وحدها حين تظهر اللحظة، ومدة اللحظة مدة التسجيل (سبع ثوانٍ على الأقل) ---
  /// أقصى انتظار لبدء التسجيل والعارض ظاهر، ثم تعود اللحظة إلى مدتها العادية
  static const _voiceLoadMs = 8000;
  /// توقف التشغيل بلا سبب منّا هذه المدة: المتصفح أوقفه (مكالمة، فصل السماعة) فتظهر «اضغط للمتابعة»
  static const _voiceStallMs = 1000;
  /// مشغّل واحد لجلسة العارض كلها يُغيَّر مصدره لكل لحظة: على الويب عنصر <audio> واحد يبقى مفتوحاً بعد أول لمسة
  VoicePlayer? _voice;
  StreamSubscription<VoiceState>? _voiceSub;
  /// اللحظة التي يتبعها المشغّل؛ null حين لا طبقة صوتية للحظة المعروضة
  String? _voiceFor;
  MomentVoicePhase _vphase = MomentVoicePhase.loading;
  /// يُزاد مع كل لحظة: نتيجة تشغيل متأخرة للحظة سابقة لا تغيّر الحالية
  int _voiceGen = 0;
  /// أوقفناه نحن (أو لم نبدأه) لأن العارض مغطّى أو مضغوط: يعود حين يزول السبب
  bool _voiceHeld = false;
  /// ما انتظرناه من التحميل (قبل البدء أو أثناء التشغيل والموضع واقف) والعارض ظاهر، وما توقف فيه التشغيل بلا سبب منّا
  int _voiceWaited = 0, _voiceStalled = 0;
  /// المدة التي يُقاس عليها الشريط الآن: مدة التسجيل وسبع ثوانٍ على الأقل
  int _voiceTotal = _autoMs;
  VoiceState _voiceLast = const VoiceState();
  /// م.ث منذ آخر تبليغ بالموضع بعدّ نبضات المؤقّت لا بساعة حقيقية (حتمي في الاختبار ولا يسبق المؤقّت): المتصفح يبلّغ نحو
  /// أربع مرات في الثانية، فنقدّر ما بينها حتى يتحرك الشريط بسلاسة
  int _voiceSince = 0;
  final _voiceView = ValueNotifier<MomentVoice?>(null);

  /// مسار أو ورقة أو حوار فوق العارض (ومنها دعوة دخول الزائر)، أو فعل مفتوح منه، أو التطبيق مخفي
  bool get _covered => _holds > 0 || _hidden || !(_route?.isCurrent ?? true);
  bool get _frozen => _covered || _pressed;

  /// يطبّق حالة التغطية على الفيديو، وينفّذ الانتقال المؤجّل حين يظهر العارض (بعد الإطار: قد نكون داخل البناء).
  void _syncCovered() {
    if (!mounted) return;
    final covered = _covered;
    _video?.setSuspended(covered, reason: VideoSuspend.viewer);
    _syncVoice();
    if (!covered && _pendingNext) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _covered || !_pendingNext) return;
        _pendingNext = false;
        _next(auto: true);
      });
    }
  }

  void _hold(bool on) {
    _holds = on ? _holds + 1 : (_holds - 1).clamp(0, 1 << 20);
    _syncCovered();
  }

  /// يوقف العارض طوال [body] (قائمة ثم حوار أو صفحة بعدها) ويعيده بعدها مهما حدث.
  Future<T> _held<T>(Future<T> Function() body) async {
    _hold(true);
    try {
      return await body();
    } finally {
      _hold(false);
    }
  }

  void _onLifecycle(AppLifecycleState s) {
    // المخفي فقط (لا inactive): فقدان التركيز أو سحب مركز التحكم لا يوقف اللحظة
    final hidden = s == AppLifecycleState.hidden || s == AppLifecycleState.paused || s == AppLifecycleState.detached;
    if (hidden == _hidden) return;
    _hidden = hidden;
    _syncCovered();
  }

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(onStateChange: _onLifecycle);
    VideoView.prepareSound();
    // مجمّع عناصر الصوت من الآن: لمسات التنقل قبل أول لحظة بتسجيل تفتح عنصرها (العارض قد يُفتح بلا لمسة، من رابط)
    VoicePlayer.prepareSound();
    _onShown();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    _syncCovered();
  }

  @override
  void dispose() {
    _life.dispose();
    _auto?.cancel();
    _releaseVideo();
    // صفحات الألبوم أُزيلت قبلنا (الأبناء يُفكّون أولاً) فيُحرَّر متحكمها مباشرة
    _album?.dispose();
    _voiceGen++;
    _voiceSub?.cancel();
    _voice?.dispose();
    _voiceView.dispose();
    _ctl.dispose();
    super.dispose();
  }

  void _releaseVideo() {
    _videoEnded?.cancel();
    _videoEnded = null;
    _video?.dispose();
    _video = null;
  }

  void _onShown() {
    _markViewed();
    _auto?.cancel();
    _releaseVideo();
    _pendingNext = false;
    progress = 0;
    final p = posts[index];
    _showAlbum(p);
    // تسجيل اللحظة السابقة يتوقف، وتسجيل هذه (إن وُجد) يبدأ وحده
    final voiced = _voiceShow(p);
    if (p.kind == 'image' || p.kind == 'text') {
      _auto = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (!mounted) return;
        // كل نبضة تعيد قراءة التغطية فلا يفوتنا تغيّر لم يصلنا خبره
        _syncCovered();
        if (voiced) return _voiceTick();
        if (_frozen) return;
        _timedStep();
      });
    } else if (p.kind == 'video' && (p.mediaUrl ?? '').isNotEmpty) {
      // الفيديو: الشريط يتبع موضع المقطع، وانتهاؤه ينقل إلى التالية؛ وإن تعذّر تشغيله يتقدّم كالصورة حتى لا يعلق العارض
      final c = _video = VideoViewController();
      // لحظة تُعرض والعارض مغطّى (حُذفت سابقتها من قائمة مفتوحة): تنتظر حتى يظهر
      c.setSuspended(_covered, reason: VideoSuspend.viewer);
      _videoEnded = c.onEnded.listen((_) {
        if (mounted && identical(c, _video)) _next(auto: true);
      });
      _auto = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (!mounted) return;
        _syncCovered();
        final v = c.value;
        if (v.failed) {
          if (!_frozen) _timedStep();
          return;
        }
        final d = v.duration;
        final f = d == null || d.inMilliseconds <= 0 ? 0.0 : (c.estimatedPosition.inMilliseconds / d.inMilliseconds).clamp(0.0, 1.0);
        if ((f - progress).abs() >= .001) setState(() => progress = f);
      });
    }
    // اللحظة التالية فيديو: غلافها وأول المقطع يُجلبان الآن فتبدأ فوراً حين تصلها (بعد الإطار لأن السياق يلزمه)
    WidgetsBinding.instance.addPostFrameCallback((_) => _warmNext());
  }

  /// خطوة المؤقّت للصورة والنص (والفيديو المتعذّر): عند الامتلاء ينتقل مرة واحدة ويتوقف المؤقّت، فلا يُعاد بدء حركة الانتقال
  /// كل 50 م.ث قبل اكتمالها؛ ظهور اللحظة التالية يبدأ مؤقّتها
  void _timedStep() {
    setState(() => progress += 50 / _momentMs);
    _followAlbum();
    if (progress < 1) return;
    _auto?.cancel();
    _next(auto: true);
  }

  // --- الألبوم ---

  /// متحكم جديد لألبوم اللحظة المعروضة (والقديم يُحرَّر بعد الإطار: صفحاته ما زالت في الشجرة حتى يُعاد البناء)، ومدتها
  void _showAlbum(MapPost p) {
    final old = _album;
    if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    // اللحظة نفسها تُعرض من جديد (تعديل) تبدأ من غلافها؛ غيرها يبقى على صورته حتى يختفي
    final leftId = _albumId;
    _leftAlbum = old != null && leftId != null && leftId != p.id ? (id: leftId, photo: _photo) : null;
    _albumId = p.isAlbum ? p.id : null;
    _album = p.isAlbum ? PageController() : null;
    _photo = _photoMark = 0;
    _albumAuto = false;
    _momentMs = p.isAlbum ? math.max(_autoMs, _photoMs * p.album.length) : _autoMs;
    if (p.isAlbum) WidgetsBinding.instance.addPostFrameCallback((_) => _warmPhoto(1));
  }

  int get _albumSize => _album == null ? 0 : posts[index].album.length;

  /// الشريط بلغ حصة صورة جديدة: تُقلب إليها إن لم يسبقها المشاهد بالسحب
  void _followAlbum() {
    final n = _albumSize;
    if (n < 2) return;
    final at = math.min(n - 1, (progress * n).floor());
    if (at <= _photoMark) return;
    _photoMark = at;
    if (at > _photo) _flipTo(at);
  }

  void _flipTo(int i) {
    final c = _album;
    setState(() => _photo = i);
    _warmPhoto(i + 1);
    if (c == null) return;
    if (!c.hasClients) {
      // الصفحات لم تُبنَ بعد: تلحق بالصورة بعد الإطار فلا تختلف عن النقاط
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(c, _album) && c.hasClients) c.jumpToPage(_photo);
      });
      return;
    }
    _albumAuto = true;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce) {
      c.jumpToPage(i);
      _albumAuto = false;
    } else {
      c.animateToPage(i, duration: const Duration(milliseconds: 260), curve: Curves.easeOut).whenComplete(() => _albumAuto = false);
    }
  }

  /// سحب المشاهد إلى صورة: بلا صوت يقود اللحظة يقفز الشريط إلى بداية حصتها فيبقى لكل صورة بعدها وقتها؛ ومع الصوت
  /// يبقى الشريط مع التسجيل ويكمل القلب التلقائي من الحصة التالية
  void _onPhoto(int i) {
    final n = _albumSize;
    if (_albumAuto || n < 2 || i == _photo) return;
    setState(() {
      _photo = i;
      if (!_voiceLeads) {
        progress = i / n;
        _photoMark = i;
      }
    });
    _warmPhoto(i + 1);
  }

  /// الطبقة الصوتية تقود الشريط الآن (لم تنتهِ ولم تتعذّر)
  bool get _voiceLeads => _voiceFor != null && _vphase != MomentVoicePhase.ended && _vphase != MomentVoicePhase.failed;

  /// تجلب الصورة [i] من ألبوم اللحظة المعروضة قبل أن تُعرض فلا تظهر فارغة لحظة القلب
  void _warmPhoto(int i) {
    if (!mounted || _album == null) return;
    final album = posts[index].album;
    if (i < 1 || i >= album.length || !_warmedPhotos.add(album[i])) return;
    final url = mediaUrl(album[i]);
    final o = PostViewerPage.warmPhotoOverride;
    if (o != null) return o(url);
    unawaited(precacheImage(NetworkImage(mediaUrl(album[i])), context, onError: (_, __) {}));
  }

  // --- الطبقة الصوتية ---

  /// يبدأ تسجيل اللحظة المعروضة بالمشغّل نفسه، أو يوقف تسجيل السابقة إن لم يكن لها تسجيل. يعيد هل للحظة تسجيل يقودها.
  bool _voiceShow(MapPost p) {
    _voiceGen++;
    if (!_drivesVoice(p)) {
      if (_voiceFor != null) {
        _voiceFor = null;
        _voice?.pause();
        _voiceView.value = null;
      }
      return false;
    }
    final v = _voice ??= _newVoice();
    _voiceFor = p.id;
    _vphase = MomentVoicePhase.loading;
    _voiceWaited = _voiceStalled = _voiceSince = 0;
    _voiceTotal = _momentMs;
    _voiceLast = const VoiceState();
    v.setSource(url: mediaUrl(p.audioUrl!));
    // لحظة تُعرض والعارض مغطّى (حُذفت سابقتها من قائمة مفتوحة): تبدأ حين يظهر
    _voiceHeld = _frozen;
    if (!_voiceHeld) _voicePlay();
    _publishVoice();
    return true;
  }

  VoicePlayer _newVoice() {
    final v = VoicePlayer.moment();
    _voiceSub = v.changes.listen(_onVoice);
    return v;
  }

  /// يشغّل التسجيل. play() يُستدعى قبل أي انتظار فيُحتسب داخل اللمسة إن جاء منها (رقاقة الصوت).
  void _voicePlay() {
    final v = _voice;
    if (v == null || _voiceFor == null) return;
    final gen = _voiceGen;
    _voiceStalled = 0;
    Future<void>.sync(v.play).then((_) {
      if (!mounted || gen != _voiceGen) return;
      // بدأ بعد أن غُطّي العارض أو ضُغط أو أوقفه المستخدم أو تعذّر: لا يُسمع خلف ما فوقه ولا فوق ما بعده
      if (_voiceHeld || _vphase == MomentVoicePhase.paused || _vphase == MomentVoicePhase.failed) v.pause();
    }, onError: (Object e) {
      if (!mounted || gen != _voiceGen) return;
      final why = '$e';
      // إيقاف منّا قبل أن يبدأ، أو مصدر جديد قاطع التحميل: ليس رفضاً
      if (why.contains('AbortError') || why.contains('Loading interrupted')) return;
      if (why.contains('NotAllowedError')) {
        // المتصفح يرفض الصوت بلا لمسة: اللحظة تنتظر لمسة الرقاقة بدل أن تمضي صامتة قبل أن يُسمع التسجيل
        _vphase = MomentVoicePhase.blocked;
        _publishVoice();
      } else {
        _voiceFail();
      }
    });
  }

  /// رفض الصوت بلا لمسة، أو إيقاف قبل البدء، أو تحميل سابق قاطعه مصدر جديد (just_audio): ليست تعذّراً
  static bool _refusal(Object? e) => '$e'.contains('NotAllowedError') || '$e'.contains('AbortError') || '$e'.contains('Loading interrupted');

  /// بدأ يُسمع فعلاً: عنصر <audio> يبلّغ playing عند استدعاء play() قبل وصول أي بيانات (loading باقٍ)، فلا نعدّه
  /// بدءاً حتى يزول التحميل أو يتحرك الموضع، وإلا تجاوزت اللحظة مهلة التحميل وعلقت إلى الأبد مع شبكة متوقفة
  static bool _voiceStarted(VoiceState s) => s.playing && (!s.loading || s.position > Duration.zero);

  void _onVoice(VoiceState s) {
    if (!mounted || _voiceFor == null) return;
    final last = _voiceLast;
    if (s.position != last.position || s.playing != last.playing || s.loading != last.loading) _voiceSince = 0;
    // الموضع تحرّك: ليس تحميلاً عالقاً
    if (s.position != last.position) _voiceWaited = 0;
    _voiceLast = s;
    switch (_vphase) {
      case MomentVoicePhase.loading || MomentVoicePhase.blocked || MomentVoicePhase.playing:
        if (s.ended) {
          _voiceEnded();
        } else if (_voiceStarted(s)) {
          if (_vphase != MomentVoicePhase.playing) {
            _vphase = MomentVoicePhase.playing;
            _voiceWaited = 0;
          }
        } else if (s.error != null && !_refusal(s.error)) {
          _voiceFail();
        }
      case MomentVoicePhase.paused || MomentVoicePhase.ended || MomentVoicePhase.failed:
        break;
    }
    _publishVoice();
  }

  /// من الشريط المقاس على التسجيل إلى مدة اللحظة العادية: ما مضى من اللحظة يبقى كما هو بالمللي ثانية ([heard] على الأقل)
  void _voiceToTimed({int heard = 0}) {
    final at = math.max(progress * _voiceTotal, heard.toDouble());
    _voiceTotal = _momentMs;
    progress = (at / _momentMs).clamp(0.0, 1.0);
  }

  /// طول التسجيل كما بلّغه المشغّل، وإلا كما حُفظ مع اللحظة
  int _voiceLength(VoiceState? s) {
    final known = s?.duration?.inMilliseconds ?? 0;
    return known > 0 ? known : (posts[index].audioSec ?? 0) * 1000;
  }

  /// انتهى التسجيل: إن مضت سبع ثوانٍ على الأقل ينتقل العارض الآن، وإلا تكمل اللحظة ما بقي من مدتها العادية.
  /// ما سُمع هو طول التسجيل كله ولو فاتتنا تبليغات الموضع.
  void _voiceEnded() {
    _vphase = MomentVoicePhase.ended;
    _voiceToTimed(heard: _voiceLength(_voice?.state));
    if (progress < .98) return;
    _auto?.cancel();
    setState(() => progress = 1);
    _next(auto: true);
  }

  /// تعذّر التسجيل: اللحظة تكمل مدتها العادية من حيث هي، ولا يبدأ صوت متأخر فوق ما بعدها.
  void _voiceFail() {
    if (_vphase == MomentVoicePhase.failed || _vphase == MomentVoicePhase.ended) return;
    _vphase = MomentVoicePhase.failed;
    _voiceToTimed();
    _voice?.pause();
    _publishVoice();
  }

  /// نبضة لحظة لها تسجيل: الشريط يتبع موضع التسجيل ولا يمتلئ قبل انتهائه؛ وبعد انتهائه أو تعذّره كالصورة.
  void _voiceTick() {
    switch (_vphase) {
      case MomentVoicePhase.ended || MomentVoicePhase.failed:
        if (!_frozen) _timedStep();
      case MomentVoicePhase.blocked || MomentVoicePhase.paused:
        break;
      case MomentVoicePhase.loading:
        if (_frozen) return;
        _voiceWaited += 50;
        if (_voiceWaited >= _voiceLoadMs) _voiceFail();
      case MomentVoicePhase.playing:
        final s = _voice?.state;
        if (s == null) return;
        final wasStalled = _voiceStalled >= _voiceStallMs;
        // التحميل أثناء التشغيل (شبكة ضعيفة) انتظار له مهلة، لا إيقاف من المتصفح
        _voiceStalled = !s.playing && !s.loading && !_frozen ? _voiceStalled + 50 : 0;
        if (wasStalled != (_voiceStalled >= _voiceStallMs)) _publishVoice();
        if (!s.loading) {
          _voiceWaited = 0;
        } else if (!_frozen) {
          // انقطعت الشبكة أثناء التشغيل والموضع واقف (يُصفَّر عند كل حركة): بعد المهلة تكمل اللحظة مدتها العادية
          _voiceWaited += 50;
          if (_voiceWaited >= _voiceLoadMs) return _voiceFail();
        }
        _voiceTotal = math.max(_momentMs, _voiceLength(s));
        var pos = s.position.inMilliseconds;
        // التقدير بين التبليغات والتسجيل يُسمع فقط: أثناء التحميل يقف الشريط مع الصوت
        if (s.playing && !s.loading) {
          _voiceSince += 50;
          pos += math.min(_voiceSince, 1500);
        }
        // لا يمتلئ قبل الانتهاء (المدة قد تكون أطول مما بُلّغ)، ولا يرجع بتصحيح التقدير
        final f = math.min(pos / _voiceTotal, .995);
        if (f > progress + .001) setState(() => progress = f);
        _followAlbum();
    }
  }

  /// يوقف التسجيل حين يُغطّى العارض أو يُضغط أو يختفي التطبيق، ويعيده حين يزول آخر سبب.
  void _syncVoice() {
    final v = _voice;
    if (v == null || _voiceFor == null) return;
    final hold = _frozen;
    if (hold == _voiceHeld) return;
    _voiceHeld = hold;
    if (hold) {
      v.pause();
    } else if (_vphase == MomentVoicePhase.loading || _vphase == MomentVoicePhase.playing) {
      _voicePlay();
    }
  }

  /// لمسة شريحة الصوت أو رقاقته (داخل اللمسة): يشغّل المتوقف (رفض المتصفح، مقاطعة، إيقاف المستخدم)، ويوقف ما يعمل.
  void _voiceTap() {
    final v = _voice;
    if (v == null || _voiceFor == null || _vphase == MomentVoicePhase.ended || _vphase == MomentVoicePhase.failed) return;
    if (v.state.playing) {
      _vphase = MomentVoicePhase.paused;
      v.pause();
    } else {
      if (_vphase == MomentVoicePhase.blocked) {
        _vphase = MomentVoicePhase.loading;
        _voiceWaited = 0;
      } else if (_vphase == MomentVoicePhase.paused) {
        _vphase = MomentVoicePhase.playing;
      }
      _voicePlay();
    }
    _publishVoice();
  }

  void _publishVoice() {
    if (!mounted) return;
    _voiceView.value = _voiceFor == null
        ? null
        : MomentVoice(phase: _vphase, state: _voice?.state ?? const VoiceState(), stalled: _vphase == MomentVoicePhase.playing && _voiceStalled >= _voiceStallMs);
  }

  void _warmNext() {
    if (!mounted || index + 1 >= posts.length) return;
    final n = posts[index + 1];
    final media = n.mediaUrl ?? '';
    if (n.kind != 'video' || media.isEmpty || !_warmed.add(n.id)) return;
    warmMomentVideo(context, ref.read(apiClientProvider), media);
  }

  void _markViewed() {
    final p = posts[index];
    if (p.mine || !_viewed.add(p.id)) return;
    ref.read(apiClientProvider).viewPost(p.id).then((v) {
      // بالمعرّف لا بالموضع: العارض قد يكون انتقل إلى لحظة أخرى قبل الرد
      if (mounted) _replace(p.id, (x) => x.copyWith(views: v));
    }).catchError((_) {});
  }

  void _replace(String id, MapPost Function(MapPost p) f) {
    final at = posts.indexWhere((x) => x.id == id);
    if (at >= 0) setState(() => posts[at] = f(posts[at]));
  }

  /// التالية، أو إغلاق العارض بعد الأخيرة. [auto] من انتهاء المقطع أو المؤقّت: لا يحدث والعارض مغطّى (يُؤجَّل حتى يظهر)،
  /// فلا تنتقل اللحظات خلف ورقة ولا يُغلق ما فوق العارض.
  void _next({bool auto = false}) {
    if (!mounted) return;
    if (auto && _covered) {
      _pendingNext = true;
      return;
    }
    if (index + 1 < posts.length) {
      _ctl.nextPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    } else {
      _auto?.cancel();
      _close();
    }
  }

  void _prev() {
    if (index > 0) _ctl.previousPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  /// يغلق العارض نفسه لا أعلى المستكشف: Navigator.pop كان يغلق الورقة أو الحوار أو الصفحة المفتوحة فوقه.
  void _close() {
    if (!mounted) return;
    final r = _route;
    if (r == null || r.isCurrent) {
      Navigator.of(context).pop();
    } else if (r.isActive) {
      Navigator.of(context).removeRoute(r);
    }
  }

  Future<void> _like(int i) async {
    final p = posts[i];
    _replace(p.id, (_) => p.copyWith(liked: !p.liked, likes: p.likes + (p.liked ? -1 : 1)));
    try {
      final r = await ref.read(apiClientProvider).likePost(p.id);
      if (mounted) _replace(p.id, (x) => x.copyWith(liked: r.liked, likes: r.likes));
    } catch (e) {
      if (mounted) {
        _replace(p.id, (_) => p);
        toast(context, _msg(e), error: true);
      }
    }
  }

  /// قائمة منشور شخص آخر: إبلاغ عن المنشور أو حظر ناشره. العارض موقوف طوال القائمة وما يتبعها (ورقة الأسباب، دعوة الدخول).
  Future<void> _otherMenu(int i) => _held(() async {
        final p = posts[i];
        final choice = await showModalBottomSheet<String>(
          context: context,
          backgroundColor: const Color(0xFF1C1F24),
          builder: (ctx) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(key: const Key('moment-directions'), leading: const Icon(Icons.directions_rounded, color: Colors.white), title: const Text('الاتجاهات', style: TextStyle(color: Colors.white)), onTap: () => Navigator.pop(ctx, 'directions')),
              ListTile(key: const Key('moment-report'), leading: const Icon(Icons.flag_outlined, color: Colors.white), title: const Text('إبلاغ عن المنشور', style: TextStyle(color: Colors.white)), onTap: () => Navigator.pop(ctx, 'report')),
              ListTile(leading: const Icon(Icons.block_rounded, color: Joy.danger), title: Text('حظر ${p.user.nickname}', style: const TextStyle(color: Joy.danger)), onTap: () => Navigator.pop(ctx, 'block')),
              const SizedBox(height: 8),
            ]),
          ),
        );
        if (!mounted || choice == null) return;
        if (choice == 'directions') return openMomentDirections(context, p);
        // الإبلاغ والحظر يحتاجان حساباً: ندعو الزائر للدخول قبل ورقة الأسباب بدل رفض 401 بعدها
        if (!requireAccount(context)) return;
        final api = ref.read(apiClientProvider);
        try {
          if (choice == 'report') {
            final r = await showReportSheet(context, ref, type: 'post', id: p.id, author: p.user, title: 'إبلاغ عن المنشور');
            if (r != null && (r.blocked || r.hidden)) {
              invalidatePosts(ref, removedPostId: r.hidden ? p.id : null);
              if (!mounted) return;
              if (r.blocked) return _close();
              // أُخفي المنشور تلقائياً بالبلاغ: يختفي من العارض كما يختفي من البث
              _remove(p.id);
            }
          } else if (choice == 'block') {
            await api.blockUser(p.user.id);
            // قائمة المحظورين تصفّي منشورات الدوائر وتعليقاتها وحالة الملف؛ بلا تحديثها يبقى محتواه ظاهراً حتى إعادة التشغيل
            ref.invalidate(blockedUsersProvider);
            invalidatePosts(ref);
            if (mounted) {
              toast(context, 'تم حظر ${p.user.nickname}');
              _close();
            }
          }
        } catch (e) {
          if (mounted) toast(context, _msg(e), error: true);
        }
      });

  /// يزيل منشوراً من العارض (حُذف أو أُخفي) بمعرّفه لا بموضعه، ويغلق العارض إن كان الأخير.
  void _remove(String id) {
    final at = posts.indexWhere((x) => x.id == id);
    if (at < 0) return;
    if (posts.length == 1) {
      _auto?.cancel();
      _close();
      return;
    }
    final shown = at == index;
    setState(() {
      posts.removeAt(at);
      if (at < index) index--;
      index = index.clamp(0, posts.length - 1);
    });
    if (shown) {
      _onShown();
    } else {
      _ctl.jumpToPage(index);
    }
  }

  /// قائمة صاحب اللحظة. العارض موقوف طوال القائمة وما يتبعها (الإحصاءات، المحرّر، حوار الحذف)، فلا ينتهي المقطع
  /// خلف حوار الحذف فيغلقه ويُلغى الحذف بصمت.
  Future<void> _menu(int i) => _held(() async {
        final p = posts[i];
        final choice = await showModalBottomSheet<String>(
          context: context,
          backgroundColor: const Color(0xFF1C1F24),
          builder: (ctx) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(leading: const Icon(Icons.insights_outlined, color: Colors.white), title: const Text('الإحصاءات', style: TextStyle(color: Colors.white)), onTap: () => Navigator.pop(ctx, 'stats')),
              ListTile(key: const Key('moment-directions'), leading: const Icon(Icons.directions_rounded, color: Colors.white), title: const Text('الاتجاهات', style: TextStyle(color: Colors.white)), onTap: () => Navigator.pop(ctx, 'directions')),
              ListTile(key: const Key('moment-edit'), leading: const Icon(Icons.edit_outlined, color: Colors.white), title: const Text('تعديل المنشور', style: TextStyle(color: Colors.white)), onTap: () => Navigator.pop(ctx, 'edit')),
              ListTile(leading: Icon(p.status == 'active' ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.white), title: Text(p.status == 'active' ? 'إخفاء من الخريطة' : 'إظهار على الخريطة', style: const TextStyle(color: Colors.white)), onTap: () => Navigator.pop(ctx, 'toggle')),
              ListTile(key: const Key('moment-delete'), leading: const Icon(Icons.delete_outline_rounded, color: Joy.danger), title: const Text('حذف المنشور', style: TextStyle(color: Joy.danger)), onTap: () => Navigator.pop(ctx, 'delete')),
              const SizedBox(height: 8),
            ]),
          ),
        );
        if (!mounted || choice == null) return;
        if (choice == 'directions') return openMomentDirections(context, p);
        final api = ref.read(apiClientProvider);
        try {
          if (choice == 'stats') {
            await showPostStats(context, postId: p.id);
            return;
          }
          if (choice == 'edit') {
            final updated = await PostComposerPage.open(context, lat: p.lat, lng: p.lng, placeName: p.placeName, edit: p);
            if (updated != null && mounted) {
              _replace(p.id, (_) => updated);
              // التعديل غيّر الطبقة الصوتية أو النوع للحظة المعروضة: تُعرض من جديد، فلا يبقى التسجيل القديم يعمل ويحدد
              // مدتها، ولا تبقى شريحة جديدة بلا مشغّل
              if (posts[index].id == p.id && (updated.kind != p.kind || updated.audioUrl != p.audioUrl || !listEquals(updated.album, p.album))) _onShown();
            }
          } else if (choice == 'toggle') {
            if (p.status == 'blocked') {
              toast(context, 'أخفته الإدارة؛ تواصل مع الدعم', error: true);
              return;
            }
            final updated = await api.updatePost(p.id, {'status': p.status == 'active' ? 'hidden' : 'active'});
            invalidatePosts(ref, removedPostId: updated.status == 'active' ? null : p.id);
            if (mounted) _replace(p.id, (_) => updated);
          } else if (choice == 'delete') {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('حذف المنشور'),
                content: const Text('سيُزال من الخريطة نهائياً.'),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(key: const Key('moment-delete-confirm'), style: FilledButton.styleFrom(backgroundColor: Joy.danger), onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف'))],
              ),
            );
            if (ok != true || !mounted) return;
            await api.deletePost(p.id);
            invalidatePosts(ref, removedPostId: p.id);
            if (!mounted) return;
            _remove(p.id);
          }
        } catch (e) {
          if (mounted) toast(context, _msg(e), error: true);
        }
      });

  @override
  Widget build(BuildContext context) => Theme(
        data: ThemeData(brightness: Brightness.dark, useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: Joy.primary, brightness: Brightness.dark), fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            // متحكم فيديو اللحظة النشطة لوسائطها ومنطقة لمسها
            child: MomentPlayback(controller: _video, child: NotificationListener<ScrollEndNotification>(
              // استقرت صفحات العارض (لا صفحات الألبوم الأعمق): الألبوم المغادَر خرج من الشاشة، فإن عاد إليه المشاهد بدأ من غلافه كما
              // سيبدأ حين ينشط (بلا setState: صفحته غير مبنية الآن)
              onNotification: (n) {
                if (n.depth == 0) _leftAlbum = null;
                return false;
              },
              child: PageView.builder(
                controller: _ctl,
                itemCount: posts.length,
                onPageChanged: (i) {
                  setState(() => index = i);
                  _onShown();
                },
                itemBuilder: (_, i) => PostView(
                  post: posts[i],
                  active: i == index,
                  progress: i == index ? progress : 0,
                  total: posts.length,
                  position: i,
                  onPrev: _prev,
                  onNext: _next,
                  onLike: () => _like(i),
                  onMenu: posts[i].mine ? () => _menu(i) : () => _otherMenu(i),
                  // الضغطة المطوّلة على صورة أو نص توقف التقدّم؛ وأفعال العمود (التفاعل، المشاركة) توقف العارض حتى تنتهي سلسلتها
                  onPress: (h) {
                    _pressed = h;
                    _syncCovered();
                  },
                  onHold: _hold,
                  voice: i == index ? _voiceView : null,
                  onVoiceTap: _voiceTap,
                  album: i == index ? _album : null,
                  photo: i == index ? _photo : _leftAlbum?.id == posts[i].id ? _leftAlbum!.photo : 0,
                  onPhoto: _onPhoto,
                ),
              ),
            )),
          ),
        ),
      );
}

/// منشور واحد داخل العارض.
class PostView extends ConsumerWidget {
  final MapPost post;
  final bool active;
  final double progress;
  final int total, position;
  final VoidCallback onPrev, onNext, onLike;
  final VoidCallback? onMenu;
  /// ضغطة مطوّلة على صورة أو نص (بدايتها ونهايتها)
  final ValueChanged<bool>? onPress;
  /// فعل من عمود الأفعال بدأ أو انتهى (true ثم false دائماً بأزواج)
  final ValueChanged<bool>? onHold;
  /// الطبقة الصوتية للحظة النشطة كما يشغّلها العارض (null لغير النشطة): الشريحة تعرضها ولا تحتاج لمسة لتبدأ
  final ValueListenable<MomentVoice?>? voice;
  /// لمسة شريحة الصوت أو رقاقة «اضغط لتشغيل الصوت»
  final VoidCallback? onVoiceTap;
  /// صفحات ألبوم اللحظة النشطة (null لغيرها: صورة [photo] ثابتة، والغلاف إلا للألبوم المغادَر أثناء الانتقال)، والصورة المعروضة،
  /// وسحب المشاهد إلى صورة
  final PageController? album;
  final int photo;
  final ValueChanged<int>? onPhoto;
  const PostView({super.key, required this.post, required this.active, required this.progress, required this.total, required this.position, required this.onPrev, required this.onNext, required this.onLike, this.onMenu, this.onPress, this.onHold, this.voice, this.onVoiceTap, this.album, this.photo = 0, this.onPhoto});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = post;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final me = ref.watch(appStateProvider.select((s) => s.user?.id));
    final voiced = _drivesVoice(p);
    return LayoutBuilder(builder: (context, box) {
      final w = (box.maxHeight * 9 / 16).clamp(200.0, box.maxWidth);
      return Stack(fit: StackFit.expand, children: [
        Center(
          child: SizedBox(
            width: w,
            height: box.maxHeight,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(box.maxWidth > w + 8 ? 20 : 0),
              child: Stack(fit: StackFit.expand, children: [
                // الألبوم: صفحات تُسحب يميناً ويساراً بين صوره، وعند طرفيه يكمل السحب إلى اللحظة المجاورة
                if (p.isAlbum && album != null)
                  MomentAlbum(key: ObjectKey(album), urls: p.album, controller: album!, onPage: (i) => onPhoto?.call(i), onPastEnd: onNext, onPastStart: onPrev)
                else
                  PostMedia(kind: p.kind, url: p.isAlbum ? p.album[photo.clamp(0, p.album.length - 1)] : p.mediaUrl, bg: p.bg, durationSec: p.durationSec, play: active),
                // نصوص الألبوم وملصقاته رُسمت على الغلاف في «راجع وعدّل» (كالفلتر والقصّ)، فتظهر معه وتختفي عن بقية الصور
                IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: !p.isAlbum || photo == 0 ? 1 : 0,
                    duration: (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ? Duration.zero : const Duration(milliseconds: 180),
                    child: OverlayCanvas(overlays: p.overlays, shadow: p.kind != 'text'),
                  ),
                ),
                if (p.isAlbum) Positioned(top: 64, left: 0, right: 0, child: IgnorePointer(child: Center(child: AlbumDots(count: p.album.length, index: photo)))),
                // الطبقة الصوتية: تعليق صوتي على الصورة أو لوحة النص، يشغّله العارض وحده والشريحة تعرض موجته وتقدّمه
                if (p.audioUrl != null && p.audioUrl!.isNotEmpty) Positioned(bottom: 96, left: 0, right: 0, child: Center(child: _voiceChip(p))),
                // مناطق النقر للتنقل (النصف الأعلى فقط حتى تبقى أدوات الفيديو والأزرار متاحة)
                if (p.kind != 'video')
                  Positioned(
                    top: 0, left: 0, right: 0, height: box.maxHeight * .55,
                    child: Row(children: [
                      Expanded(child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: rtl ? onNext : onPrev, onLongPressStart: (_) => onPress?.call(true), onLongPressEnd: (_) => onPress?.call(false))),
                      Expanded(child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: rtl ? onPrev : onNext, onLongPressStart: (_) => onPress?.call(true), onLongPressEnd: (_) => onPress?.call(false))),
                    ]),
                  )
                // الفيديو بلا أزرار تحكم (كسناب): اللحظة كلها للمس — النقر للتنقل كالصور (الصف أعلاه ينعكس مع الاتجاه فيبقى
                // اليسار الفعلي للسابقة واليمين للتالية)، والضغط المطوّل يسرّع أو يرجّع أو يوقف
                else if (active)
                  Positioned.fill(child: MomentVideoGestures(controller: MomentPlayback.maybeOf(context), onLeftTap: onPrev, onRightTap: onNext)),
                // المتصفح رفض الصوت بلا لمسة (اللحظة تنتظر)، أو أوقفه بنفسه: لمسة تشغّله داخل حدث اللمس
                if (voiced && voice != null) Positioned(top: 76, left: 12, right: 12, child: _voicePrompt(context, voice!)),
              ]),
            ),
          ),
        ),
        // الشريط العلوي: تقدّم، إغلاق، تنقّل، صاحب المنشور
        Positioned(
          top: 6, left: 10, right: 10,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              for (var i = 0; i < total; i++)
                Expanded(child: Container(height: 3, margin: const EdgeInsets.symmetric(horizontal: 1.5), decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(2)),
                    child: FractionallySizedBox(alignment: AlignmentDirectional.centerStart, widthFactor: i < position ? 1 : i == position ? progress.clamp(0, 1) : 0, child: Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)))))),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              // الاسم والوقت يتقلّصان (بنقاط) قبل العلامات وأزرار التنقل حتى لا يفيض الصف على شاشة ضيقة: المجموعة تأخذ الفراغ كله
              // والاسم وحده مرن داخلها
              Expanded(
                child: Row(children: [
                  Flexible(
                    child: InkWell(
                      onTap: () => openProfile(context, p.user),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        ProfileAvatar(person: p.user, size: 38),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(p.user.nickname, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14, shadows: [Shadow(color: Colors.black54, blurRadius: 4)])),
                            Text('${timeAgo(p.createdAt)}${p.placeName != null && p.placeName!.isNotEmpty ? ' · ${p.placeName}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 11.5, shadows: [Shadow(color: Colors.black54, blurRadius: 4)])),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (p.tag != 'moment') _pill(p.tagLabel, Joy.sun, Joy.sunText),
                  // لحظة «الأصدقاء»: لا تصل إلا صاحبها وأصدقاءه، فالعلامة تذكّرهم أنها ليست عامة
                  if (p.friendsOnly)
                    Padding(
                      padding: EdgeInsetsDirectional.only(start: p.tag != 'moment' ? 6 : 0),
                      child: Container(
                        key: const Key('moment-friends-mark'),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(999)),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.people_alt_rounded, size: 13, color: Colors.white),
                          SizedBox(width: 4),
                          Text('للأصدقاء', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ),
                  if (p.mine && p.status != 'active') Padding(padding: const EdgeInsetsDirectional.only(start: 6), child: _pill(p.status == 'blocked' ? 'أخفته الإدارة' : 'مخفي', Colors.white24, Colors.white)),
                ]),
              ),
              if (total > 1) ...[
                IconButton(tooltip: 'السابق', onPressed: onPrev, icon: const Icon(Icons.chevron_right_rounded, color: Colors.white)),
                IconButton(tooltip: 'التالي', onPressed: onNext, icon: const Icon(Icons.chevron_left_rounded, color: Colors.white)),
              ],
              IconButton(tooltip: 'إغلاق', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: Colors.white)),
            ]),
          ]),
        ),
        // الأسفل: العنوان والسعر والتعليق، وبجانبها عمود الأفعال على الحافة كسناب وتيك توك (إعجاب، تفاعل، حفظ، مشاركة، خريطة)،
        // ثم زر الإجراء، وصف المراسلة والمشاهدات والخيارات
        Positioned(
          bottom: 10, left: 12, right: 12,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  if (p.title.isNotEmpty || p.price != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(14)),
                      child: Row(children: [
                        if (p.title.isNotEmpty) Expanded(child: Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15))),
                        if (p.price != null) Text(p.price == 0 ? 'مجاناً' : money(p.price!), style: const TextStyle(color: Joy.sun, fontWeight: FontWeight.w800, fontSize: 16)),
                      ]),
                    ),
                  if (p.caption.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(p.caption, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5, shadows: [Shadow(color: Colors.black87, blurRadius: 6)]))),
                ]),
              ),
              const SizedBox(width: 8),
              // شاشة قصيرة: أيقونات بلا تسميات حتى يبقى للتعليق مكان
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: MomentRail(key: ValueKey('moment-rail-${p.id}'), post: p, active: active, onLike: onLike, onHold: onHold, compact: box.maxHeight < 640),
              ),
            ]),
            if (p.cta != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () { if (!p.mine) unawaited(ref.read(apiClientProvider).trackCta(p.id)); runPostCta(context, p); }, icon: Icon(_ctaIcon(p.cta!.type)), label: Text(p.cta!.label.isNotEmpty ? p.cta!.label : postCtaTypes[p.cta!.type] ?? ''))),
              ),
            Row(children: [
              if (p.mine) _action(Icons.visibility_outlined, '${p.views}', null),
              if (!p.mine && me != null) ...[
                _action(Icons.chat_bubble_outline_rounded, 'مراسلة', () {
                  if (!requireAccount(context)) return;
                  unawaited(ref.read(apiClientProvider).trackContact(p.id));
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadPage(peer: p.user)));
                }),
                const SizedBox(width: 6),
                // «رد خاص»: يفتح المحادثة والحقل مملوء برمز اللحظة (#post/…) فتظهر بطاقتها داخل الرسالة؛ أيقونة فقط لأن الصف ضيّق على الجوال
                _action(Icons.reply_rounded, '', () {
                  if (!requireAccount(context)) return;
                  unawaited(ref.read(apiClientProvider).trackContact(p.id));
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadPage(peer: p.user, initialText: '#post/${p.id} ')));
                }, key: const Key('post-reply-private'), tooltip: 'رد خاص'),
              ],
              const Spacer(),
              if (onMenu != null) IconButton(tooltip: 'خيارات', onPressed: onMenu, icon: const Icon(Icons.more_horiz_rounded, color: Colors.white)),
            ]),
          ]),
        ),
      ]);
    });
  }

  Widget _voiceChip(MapPost p) {
    final url = mediaUrl(p.audioUrl!);
    final light = p.kind == 'text' && colorFromHex(p.bg, Colors.white).computeLuminance() > .5;
    // الفيديو بطبقة صوتية (نادر): الشريحة بمشغّلها الخاص كما كانت
    if (!_drivesVoice(p)) return VoiceChip(url: url, seconds: p.audioSec, light: light);
    final v = voice;
    if (v == null) return VoiceChip(url: url, seconds: p.audioSec, light: light, state: const VoiceState());
    return ValueListenableBuilder<MomentVoice?>(
      valueListenable: v,
      builder: (_, m, __) => VoiceChip(url: url, seconds: p.audioSec, light: light, state: m?.state ?? const VoiceState(), onTap: onVoiceTap),
    );
  }

  Widget _voicePrompt(BuildContext context, ValueListenable<MomentVoice?> voice) {
    final fade = (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ? Duration.zero : const Duration(milliseconds: 160);
    Widget chip(String text, Key key) => Center(
          key: key,
          child: Material(
            color: Colors.black54,
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onVoiceTap,
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7), child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5))),
            ),
          ),
        );
    return ValueListenableBuilder<MomentVoice?>(
      valueListenable: voice,
      builder: (_, m, __) => AnimatedSwitcher(
        duration: fade,
        child: m?.phase == MomentVoicePhase.blocked
            ? chip('🔇 اضغط لتشغيل الصوت', const Key('moment-voice-unmute'))
            : m != null && m.stalled
                ? chip('▶ اضغط للمتابعة', const Key('moment-voice-resume'))
                : const SizedBox.shrink(),
      ),
    );
  }

  static IconData _ctaIcon(String t) => switch (t) { 'whatsapp' => Icons.chat_rounded, 'call' => Icons.call_rounded, 'biz' => Icons.storefront_rounded, 'market' => Icons.shopping_bag_rounded, 'chat' => Icons.chat_bubble_outline_rounded, _ => Icons.open_in_new_rounded };

  Widget _pill(String t, Color bg, Color fg) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)), child: Text(t, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700)));

  /// زر دائري في صف الأسفل؛ بلا [label] يكون أيقونة فقط (مع [tooltip] لتسميته).
  Widget _action(IconData icon, String label, VoidCallback? onTap, {Color color = Colors.white, Key? key, String? tooltip}) {
    final pill = Material(
      key: key,
      color: Colors.black45,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: label.isEmpty ? 10 : 12, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 20, color: color),
            if (label.isNotEmpty) ...[const SizedBox(width: 6), Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13))],
          ]),
        ),
      ),
    );
    return tooltip == null ? pill : Tooltip(message: tooltip, child: pill);
  }
}

/// ألبوم اللحظة في العارض: صفحات أفقية بصوره (الغلاف أولاً) تتبع اتجاه الكتابة كصفحات العارض نفسها، والصورة المجاورة تُبنى
/// مسبقاً. صفحات الألبوم تأخذ السحب من صفحات العارض، فالسحب بعد آخر صورة أو قبل الأولى ينقل إلى اللحظة المجاورة مرة واحدة
/// لكل سحبة. الفأرة ولوحة اللمس تسحبان أيضاً (سطح المكتب بلا لمس).
class MomentAlbum extends StatefulWidget {
  final List<String> urls;
  final PageController controller;
  final ValueChanged<int> onPage;
  final VoidCallback onPastEnd, onPastStart;
  const MomentAlbum({super.key, required this.urls, required this.controller, required this.onPage, required this.onPastEnd, required this.onPastStart});

  /// سحب يتجاوز طرف الألبوم بهذا القدر (بكسل) ينقل إلى اللحظة المجاورة؛ أقل منه لا شيء
  static const handOff = 24.0;

  @override
  State<MomentAlbum> createState() => _MomentAlbumState();
}

class _MomentAlbumState extends State<MomentAlbum> {
  double _over = 0;
  bool _handed = false;

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    if (n is ScrollStartNotification) {
      _over = 0;
      _handed = false;
    } else if (n is OverscrollNotification && n.dragDetails != null && !_handed) {
      // الموضع لا يتجاوز الطرف (ClampingScrollPhysics) فيصل التجاوز هنا؛ موجبه بعد آخر صورة وسالبه قبل الأولى في أي اتجاه كتابة
      _over += n.overscroll;
      if (_over.abs() >= MomentAlbum.handOff) {
        _handed = true;
        _over > 0 ? widget.onPastEnd() : widget.onPastStart();
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: PageView.builder(
          key: const Key('moment-album'),
          controller: widget.controller,
          physics: const ClampingScrollPhysics(),
          scrollBehavior: ScrollConfiguration.of(context).copyWith(dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.stylus, PointerDeviceKind.trackpad}),
          // الصورة المجاورة مبنية مسبقاً فلا تظهر فارغة أثناء السحب
          allowImplicitScrolling: true,
          itemCount: widget.urls.length,
          onPageChanged: widget.onPage,
          itemBuilder: (_, i) => PostMedia(key: ValueKey('album-photo-$i'), kind: 'image', url: widget.urls[i]),
        ),
      );
}

/// نقاط صور الألبوم فوق اللحظة: النشطة أعرض وبيضاء.
class AlbumDots extends StatelessWidget {
  final int count, index;
  const AlbumDots({super.key, required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    final fast = (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ? Duration.zero : const Duration(milliseconds: 180);
    return Container(
      key: const Key('album-dots'),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            key: Key(i == index ? 'album-dot-on-$i' : 'album-dot-$i'),
            duration: fast,
            margin: const EdgeInsets.symmetric(horizontal: 2.5),
            width: i == index ? 14 : 6,
            height: 6,
            decoration: BoxDecoration(color: i == index ? Colors.white : Colors.white54, borderRadius: BorderRadius.circular(3)),
          ),
      ]),
    );
  }
}
