import 'dart:async';

import 'package:flutter/foundation.dart';

/// حالة التشغيل كما يبلّغ عنها المشغّل الفعلي (عنصر <video> على الويب، video_player على الجوال، أو مشغّل وهمي في الاختبار).
@immutable
class VideoPlayback {
  final Duration position;
  /// null قبل وصول البيانات الوصفية
  final Duration? duration;
  final bool playing;
  final bool muted;
  /// طلبنا الصوت فرفضه المتصفح (تشغيل تلقائي بلا لمسة): المقطع يعمل صامتاً (أو متوقفاً) حتى يلمس المستخدم
  final bool soundBlocked;
  /// ظهر أول إطار: لا حاجة بعده للغلاف الثابت تحت المشغّل
  final bool firstFrame;
  final bool ended;
  final bool failed;
  /// المتصفح أوقف المقطع بنفسه ونحن نريده يعمل (مكالمة، فصل السماعة، مقاطعة الصوت): رقاقة «اضغط للمتابعة» بدل لحظة متجمدة
  final bool interrupted;
  final double rate;
  /// أبعاد المقطع الطبيعية (صفر قبل البيانات الوصفية)
  final double width, height;
  const VideoPlayback({
    this.position = Duration.zero,
    this.duration,
    this.playing = false,
    this.muted = false,
    this.soundBlocked = false,
    this.firstFrame = false,
    this.ended = false,
    this.failed = false,
    this.interrupted = false,
    this.rate = 1,
    this.width = 0,
    this.height = 0,
  });

  /// المقطع أعرض من طوله: يُعرض كاملاً بلا قص في الإطار العمودي
  bool get landscape => width > 0 && height > 0 && width > height;

  VideoPlayback copyWith({
    Duration? position,
    Duration? duration,
    bool? playing,
    bool? muted,
    bool? soundBlocked,
    bool? firstFrame,
    bool? ended,
    bool? failed,
    bool? interrupted,
    double? rate,
    double? width,
    double? height,
  }) =>
      VideoPlayback(
        position: position ?? this.position,
        duration: duration ?? this.duration,
        playing: playing ?? this.playing,
        muted: muted ?? this.muted,
        soundBlocked: soundBlocked ?? this.soundBlocked,
        firstFrame: firstFrame ?? this.firstFrame,
        ended: ended ?? this.ended,
        failed: failed ?? this.failed,
        interrupted: interrupted ?? this.interrupted,
        rate: rate ?? this.rate,
        width: width ?? this.width,
        height: height ?? this.height,
      );
}

/// سبب الإيقاف المؤقت. لكل سبب علَمه فلا يُلغي أحدها إيقاف الآخر: صفحة العارض تُغطّى بمسار معتم (TickerMode)
/// مستقل عن العارض نفسه حين تفتح فوقه ورقة أو حوار أو يختفي التطبيق.
enum VideoSuspend { ticker, viewer }

/// ما يربطه المشغّل الفعلي (أو الوهمي في الاختبار) بالمتحكم ليستقبل أوامره؛ ويبلّغ حالته عبر [VideoViewController.report].
abstract class VideoViewBackend {
  void play();
  void pause();
  void setRate(double rate);
  void seekBy(Duration delta);
  void setMuted(bool muted);
}

/// متحكم خارجي بمشغّل [VideoView] (عارض اللحظات وبطاقات «اللحظات»): تشغيل وإيقاف، سرعة، قفز، كتم، ومتابعة الموضع
/// والمدة والانتهاء. الأوامر قبل جهوزية المشغّل تُحفظ رغبةً ويطبّقها المشغّل حين يرتبط، فيصح استدعاؤها في أي وقت.
/// بعد [dispose] تصير الأوامر والتبليغات بلا أثر: المشغّل القديم قد يبلّغ لحظة بعد انتقال العارض إلى لحظة أخرى.
class VideoViewController extends ChangeNotifier implements ValueListenable<VideoPlayback> {
  VideoPlayback _value = const VideoPlayback();
  VideoViewBackend? _backend;
  final _ended = StreamController<void>.broadcast();
  bool _wantPlaying = true, _disposed = false;
  final _suspendedBy = <VideoSuspend>{};
  bool? _wantMuted;
  double _rate = 1;
  /// منذ آخر تبليغ بالموضع: المتصفح يبلّغ نحو أربع مرات في الثانية فقط، فنقدّر ما بينها حتى يتحرك شريط التقدّم بسلاسة
  final Stopwatch _since = Stopwatch()..start();

  @override
  VideoPlayback get value => _value;
  /// يُطلق مرة عند انتهاء المقطع (لا يُطلق مع التكرار)
  Stream<void> get onEnded => _ended.stream;
  bool get wantsPlaying => _wantPlaying;
  /// كتم طُلب صراحة؛ null = ما طلبه الودجت
  bool? get wantsMuted => _wantMuted;
  double get rate => _rate;
  /// متوقف مؤقتاً لأن الصفحة أو العارض مغطّى أو التطبيق مخفي ([VideoSuspend])؛ يعود حين يزول آخر سبب إن كان مطلوباً
  bool get suspended => _suspendedBy.isNotEmpty;
  bool get attached => _backend != null;
  bool get disposed => _disposed;

  /// الموضع المقدّر الآن: آخر موضع مبلَّغ مضافاً إليه ما مضى بحسب السرعة، بحد ثانية ونصف حتى لا يسبق مقطعاً متعثراً.
  Duration get estimatedPosition {
    final v = _value;
    if (!v.playing || v.ended) return v.position;
    final ms = _since.elapsedMilliseconds.clamp(0, 1500) * v.rate;
    var p = v.position + Duration(milliseconds: ms.round());
    final d = v.duration;
    if (d != null && p > d) p = d;
    return p;
  }

  void play() {
    if (_disposed) return;
    _wantPlaying = true;
    if (!suspended) _backend?.play();
  }

  void pause() {
    if (_disposed) return;
    _wantPlaying = false;
    _backend?.pause();
  }

  void setRate(double rate) {
    if (_disposed) return;
    _rate = rate;
    _backend?.setRate(rate);
  }

  void seekBy(Duration delta) {
    if (_disposed) return;
    _backend?.seekBy(delta);
  }

  void setMuted(bool muted) {
    if (_disposed) return;
    _wantMuted = muted;
    _backend?.setMuted(muted);
  }

  void toggleMuted() => setMuted(!_value.muted);

  /// من لمسة المستخدم مباشرة: يرفع الكتم ويشغّل في الحدث نفسه (المتصفح لا يقبل الصوت إلا داخل حدث لمس).
  void unmute() {
    setMuted(false);
    play();
  }

  /// للمشغّل: يرتبط بالمتحكم فتصله الأوامر. يطبّق الرغبات المحفوظة بنفسه عند الجهوزية (wantsPlaying وwantsMuted وrate).
  void attach(VideoViewBackend backend) {
    if (_disposed) return;
    _backend = backend;
  }

  void detach(VideoViewBackend backend) {
    if (identical(_backend, backend)) _backend = null;
  }

  /// للمشغّل: يبلّغ حالته. الانتقال إلى «انتهى» يُطلق [onEnded].
  /// القيمة تتغير فوراً والإخبار بعد المهمة الجارية (مجمّعاً): المشغّل قد يبلّغ وهو يُبنى (عنصر الويب يُنشأ أثناء البناء)
  /// ولا يجوز إعادة بناء المستمعين حينها.
  void report(VideoPlayback v) {
    if (_disposed) return;
    final wasEnded = _value.ended;
    // التقدير يُرسى من جديد فقط حين يتغير الموضع أو حالة التشغيل؛ تبليغ آخر (الصوت مثلاً) بموضع قديم لا يرجع الشريط
    if (v.position != _value.position || v.playing != _value.playing) _since.reset();
    _value = v;
    if (!_notifyPending) {
      _notifyPending = true;
      scheduleMicrotask(() {
        _notifyPending = false;
        if (!_disposed) notifyListeners();
      });
    }
    if (v.ended && !wasEnded) _ended.add(null);
  }

  bool _notifyPending = false;

  /// إيقاف مؤقت لسبب [reason] لا يغيّر رغبة التشغيل: الصفحة غُطّيت بمسار آخر (TickerMode)، أو العارض مغطّى بورقة
  /// أو حوار أو التطبيق في الخلفية. يعود التشغيل حين يزول آخر سبب فقط.
  void setSuspended(bool on, {VideoSuspend reason = VideoSuspend.ticker}) {
    if (_disposed) return;
    final was = suspended;
    on ? _suspendedBy.add(reason) : _suspendedBy.remove(reason);
    if (was == suspended) return;
    if (suspended) {
      _backend?.pause();
    } else if (_wantPlaying) {
      _backend?.play();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _backend = null;
    _ended.close();
    super.dispose();
  }
}
