import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/app_theme.dart';
import '../../../core/media/voice_player.dart';
import '../../../ui/widgets.dart';

/// عدد أعمدة الموجة الصوتية (يطابق ما يحسبه الخادم في POST /chat/upload ويعيده في extra.peaks).
const waveformBars = 48;

String fmtDuration(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// موجة زائفة ثابتة مشتقة من مفتاح الرسالة حتى لا تكون الفقاعة مسطّحة حين تغيب القمم الحقيقية (رسائل قديمة أو رفع بلا قمم).
List<double> pseudoPeaks(String seed, {int n = waveformBars}) {
  var h = 2166136261;
  for (final c in seed.codeUnits) {
    h = ((h ^ c) * 16777619) & 0xFFFFFFFF;
  }
  var x = h == 0 ? 7 : h;
  final phase = (h % 7).toDouble();
  final out = <double>[];
  for (var i = 0; i < n; i++) {
    x = (x * 1103515245 + 12345) & 0x7FFFFFFF;
    final r = (x >> 8) / 0x7FFFFF;
    // شكل «كلام»: موجة بطيئة يعلوها ضجيج، بين 0.18 و1
    final wave = 0.55 + 0.35 * math.sin(i / n * math.pi * 3 + phase);
    out.add((0.18 + 0.82 * (0.5 * r + 0.5 * wave)).clamp(0.18, 1.0));
  }
  return out;
}

/// قمم الموجة من بيانات الرسالة الإضافية (extra.peaks) إن وُجدت وصالحة، مُعادة إلى 48 عموداً.
List<double>? peaksFromExtra(Map<String, dynamic> extra) {
  final raw = extra['peaks'];
  if (raw is! List || raw.length < 8) return null;
  final out = [for (final v in raw) if (v is num) v.toDouble().clamp(0.0, 1.0)];
  if (out.length < 8) return null;
  return resamplePeaks(out, waveformBars);
}

/// يعيد توزيع القمم على [n] عموداً (بالمتوسط عند التقليص وبالتكرار عند التوسيع).
List<double> resamplePeaks(List<double> src, int n) {
  if (src.length == n) return src;
  final out = <double>[];
  for (var i = 0; i < n; i++) {
    final a = (i * src.length / n).floor();
    final b = math.max(a + 1, ((i + 1) * src.length / n).floor());
    var sum = 0.0;
    var c = 0;
    for (var j = a; j < b && j < src.length; j++) {
      sum += src[j];
      c++;
    }
    out.add(c == 0 ? src[math.min(a, src.length - 1)] : sum / c);
  }
  return out;
}

/// مشغّلات الرسائل الصوتية الحيّة بمفتاح الرابط **لصفحة محادثة واحدة**: وصول رسالة جديدة يزحزح عناصر القائمة
/// فتُعاد فقاعاتها، فيبقى المشغّل هنا ما دام يعمل وتلتقطه الفقاعة الجديدة. كل صفحة تملك سجلّها وتصرفه عند إغلاقها
/// (لا سجل عام: محادثة متداخلة فوق أخرى كانت تصرف مشغّلات الأولى عند إغلاقها).
class VoiceNotePlayers {
  final _byUrl = <String, VoicePlayer>{};
  bool _disposed = false;

  int get length => _byUrl.length;
  bool get disposed => _disposed;

  VoicePlayer? existing(String url) => _byUrl[url];

  VoicePlayer acquire(String url) => _byUrl.putIfAbsent(url, () => VoicePlayer()..setSource(url: url));

  /// يصرف المشغّل إن لم يكن يعمل (أو دائماً مع [force]).
  void release(String url, {bool force = false}) {
    final p = _byUrl[url];
    if (p == null) return;
    if (!force && p.state.playing) return;
    _byUrl.remove(url);
    p.dispose();
  }

  void disposeAll() {
    _disposed = true;
    for (final p in _byUrl.values) {
      p.dispose();
    }
    _byUrl.clear();
  }
}

/// موضع مركز العمود [i] من [n] عمود على عرض [width]: العمود الأول عند حافة **البداية** (اليمين في العربية) حتى
/// يتفق الرسم مع موضع اللمس المعكوس في الاتجاه RTL ومع موضع زر التشغيل.
double waveBarX(int i, int n, double width, TextDirection dir) {
  final slot = width / n;
  final x = slot * i + slot / 2;
  return dir == TextDirection.rtl ? width - x : x;
}

/// أعمدة الموجة: المقطع المسموع بلون التشغيل والباقي باهت؛ [progress] من 0 إلى 1 يُملأ من حافة البداية
/// (حسب [Directionality]) فيتفق مع موضع اللمس المعكوس في RTL.
class WaveformBars extends StatelessWidget {
  final List<double> peaks;
  final double progress;
  final Color color, playedColor;
  final double height;
  const WaveformBars({super.key, required this.peaks, required this.progress, required this.color, required this.playedColor, this.height = 30});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _WavePainter(peaks: peaks, progress: progress, color: color, playedColor: playedColor, textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr),
        ),
      );
}

class _WavePainter extends CustomPainter {
  final List<double> peaks;
  final double progress;
  final Color color, playedColor;
  final TextDirection textDirection;
  _WavePainter({required this.peaks, required this.progress, required this.color, required this.playedColor, required this.textDirection});

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty) return;
    final n = peaks.length;
    final slot = size.width / n;
    final w = math.max(1.5, slot * 0.6);
    final played = Paint()..color = playedColor..strokeCap = StrokeCap.round..strokeWidth = w;
    final rest = Paint()..color = color..strokeCap = StrokeCap.round..strokeWidth = w;
    final cut = progress * n;
    for (var i = 0; i < n; i++) {
      final h = math.max(3.0, peaks[i].clamp(0.0, 1.0) * size.height);
      final x = waveBarX(i, n, size.width, textDirection);
      final y0 = (size.height - h) / 2, y1 = y0 + h;
      canvas.drawLine(Offset(x, y0), Offset(x, y1), i < cut ? played : rest);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.progress != progress || old.peaks != peaks || old.color != color || old.playedColor != playedColor || old.textDirection != textDirection;
}

/// مشغّل رسالة صوتية: تشغيل/إيقاف، موجة من 48 عموداً تُسحب للانتقال، والوقت المتبقي. يعمل عبر [VoicePlayer]
/// (عنصر <audio> أصلي على الويب). لا زر سرعة لأن [VoicePlayer] لا يدعم تغيير السرعة بعد.
class AudioBubble extends StatefulWidget {
  final String? url;
  final int? durationMs;
  final bool mine, pending;
  /// القمم الحقيقية من extra.peaks، وإلا موجة زائفة من [seed] (مفتاح الرسالة).
  final List<double>? peaks;
  final String seed;
  /// سجل مشغّلات الصفحة (يبقي المشغّل حياً حين تُعاد الفقاعة)؛ بلا سجل تملك الفقاعة مشغّلها وتصرفه بنفسها.
  final VoiceNotePlayers? players;
  const AudioBubble({super.key, required this.url, this.durationMs, required this.mine, this.pending = false, this.peaks, required this.seed, this.players});

  @override
  State<AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<AudioBubble> {
  VoicePlayer? _player;
  /// المشغّل ملك هذه الفقاعة (لا سجل) فتصرفه عند إزالتها.
  bool _owned = false;
  StreamSubscription<VoiceState>? _sub;
  Object? _err;
  /// موضع السحب على الموجة أثناء السحب (كسر من 0 إلى 1) قبل تنفيذ الانتقال.
  double? _scrub;
  late List<double> _bars = widget.peaks ?? pseudoPeaks(widget.seed);

  @override
  void initState() {
    super.initState();
    // فقاعة أُعيد إنشاؤها ومشغّلها ما زال يعمل: نلتقطه بدل البدء من الصفر
    final url = widget.url;
    if (url != null) {
      final p = widget.players?.existing(url);
      if (p != null) _attach(p);
    }
  }

  @override
  void didUpdateWidget(AudioBubble old) {
    super.didUpdateWidget(old);
    if (old.peaks != widget.peaks || old.seed != widget.seed) _bars = widget.peaks ?? pseudoPeaks(widget.seed);
    if (old.url != widget.url || old.players != widget.players) {
      _detach(old.url, old.players);
      _err = null;
      final url = widget.url;
      final p = url == null ? null : widget.players?.existing(url);
      if (p != null) _attach(p);
    }
  }

  @override
  void dispose() {
    _detach(widget.url, widget.players);
    super.dispose();
  }

  /// يفكّ الاشتراك ويعيد المشغّل إلى السجل (يُصرف إن لم يكن يعمل) أو يصرفه إن كان ملك الفقاعة.
  void _detach(String? url, VoiceNotePlayers? players) {
    _sub?.cancel();
    _sub = null;
    final p = _player;
    _player = null;
    if (p == null) return;
    if (_owned) {
      p.dispose();
    } else if (url != null) {
      players?.release(url);
    }
    _owned = false;
  }

  void _attach(VoicePlayer p) {
    // اشتراك يدوي بدل StreamBuilder: التغيير الأول (بدء التشغيل) يصدر قبل أن يشترك StreamBuilder فيضيع
    _sub = p.changes.listen((s) {
      if (s.error != null) _fail(s.error!);
      if (mounted) setState(() {});
    });
    _player = p;
  }

  VoicePlayer? _ensure() {
    final url = widget.url;
    if (url == null) return null;
    var p = _player;
    if (p == null) {
      final reg = widget.players;
      if (reg != null && !reg.disposed) {
        p = reg.acquire(url);
        _owned = false;
      } else {
        p = VoicePlayer()..setSource(url: url);
        _owned = true;
      }
      _attach(p);
      setState(() {});
    }
    return p;
  }

  void _toggle() {
    final url = widget.url;
    if (url == null) return;
    if (_err != null) {
      // فشل التشغيل داخل الصفحة: نفتح الملف خارجياً (ضمن حدث اللمس حتى لا يُحجب)
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return;
    }
    final p = _ensure();
    if (p == null) return;
    if (p.state.playing) {
      p.pause();
    } else {
      // play() قبل أي await: iOS لا يقبل بدء التشغيل إلا داخل حدث المستخدم
      p.play().catchError(_fail);
    }
  }

  void _fail(Object e) {
    if (!mounted || _err != null) return;
    setState(() => _err = e);
    toast(context, 'تعذر تشغيل التسجيل على هذا الجهاز، اضغط عليه مجدداً لفتحه خارجياً', error: true);
  }

  Duration get _total {
    final p = _player;
    final known = p?.state.duration;
    if (known != null && known > Duration.zero) return known;
    return widget.durationMs != null ? Duration(milliseconds: widget.durationMs!) : Duration.zero;
  }

  void _seekTo(double frac) {
    final dur = _total;
    if (dur == Duration.zero || widget.pending || _err != null) return;
    final p = _ensure();
    if (p == null) return;
    p.seek(Duration(milliseconds: (frac.clamp(0.0, 1.0) * dur.inMilliseconds).round()));
    if (!p.state.playing) p.play().catchError(_fail);
  }

  double _fracAt(Offset local, double width) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final f = (local.dx / width).clamp(0.0, 1.0);
    return rtl ? 1 - f : f;
  }

  @override
  Widget build(BuildContext context) {
    final mine = widget.mine;
    final fg = mine ? Joy.primaryOn : Joy.text;
    final p = _player;
    final s = p?.state ?? const VoiceState();
    final dur = _total;
    final pos = s.position;
    final frac = _scrub ?? (dur.inMilliseconds == 0 ? 0.0 : (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0));
    final started = s.playing || pos > Duration.zero;
    // الوقت: قبل التشغيل «الموضع / المدة»، وأثناءه أو بعد الإيقاف المؤقت المتبقي
    final remaining = dur - (_scrub != null ? Duration(milliseconds: (frac * dur.inMilliseconds).round()) : pos);
    final label = started || _scrub != null ? '−${fmtDuration(remaining.isNegative ? Duration.zero : remaining)}' : '${fmtDuration(pos)} / ${fmtDuration(dur)}';
    final busy = (s.loading && !s.playing && _err == null) || widget.pending;
    return SizedBox(
      width: 236,
      child: Row(children: [
        Material(
          color: mine ? Colors.white.withValues(alpha: .18) : Joy.primarySoft,
          shape: const CircleBorder(),
          child: InkWell(
            key: const Key('audio-play'),
            customBorder: const CircleBorder(),
            onTap: widget.pending || widget.url == null ? null : _toggle,
            child: SizedBox(
              width: 40,
              height: 40,
              child: busy
                  ? Padding(padding: const EdgeInsets.all(11), child: CircularProgressIndicator(strokeWidth: 2, color: mine ? Joy.primaryOn : Joy.primary))
                  : Icon(_err != null ? Icons.error_outline_rounded : s.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: mine ? Joy.primaryOn : Joy.primary, size: 26),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            LayoutBuilder(
              builder: (_, c) => GestureDetector(
                key: const Key('audio-bars'),
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _seekTo(_fracAt(d.localPosition, c.maxWidth)),
                onHorizontalDragStart: (d) => setState(() => _scrub = _fracAt(d.localPosition, c.maxWidth)),
                onHorizontalDragUpdate: (d) => setState(() => _scrub = _fracAt(d.localPosition, c.maxWidth)),
                onHorizontalDragEnd: (_) {
                  final f = _scrub;
                  setState(() => _scrub = null);
                  if (f != null) _seekTo(f);
                },
                onHorizontalDragCancel: () => setState(() => _scrub = null),
                child: WaveformBars(
                  peaks: _bars,
                  progress: frac,
                  color: fg.withValues(alpha: mine ? .45 : .28),
                  playedColor: mine ? Joy.primaryOn : Joy.primary,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 2),
              child: Text(label, textDirection: TextDirection.ltr, style: TextStyle(fontSize: 11, color: fg.withValues(alpha: .8), fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      ]),
    );
  }
}
