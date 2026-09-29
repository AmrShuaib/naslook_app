import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../api/client.dart';
import '../../api/profile_v2_models.dart';
import '../../core/app_theme.dart';
import '../../core/media/video_view.dart';
import '../../core/media/voice_player.dart';
import '../../ui/widgets.dart';

/// شريط تشغيل صوتي مضغوط: زر تشغيل/إيقاف وشريط تقدّم والزمن. يقبل رابطاً مرفوعاً أو بايتات محلية (معاينة قبل الرفع).
/// التشغيل عبر [VoicePlayer] وplay() داخل حدث اللمس (شرط iOS).
class IntroVoiceBar extends StatefulWidget {
  final String? url, mime;
  final Uint8List? bytes;
  final int sec;
  final Key? playKey;
  const IntroVoiceBar({super.key, this.url, this.bytes, this.mime, required this.sec, this.playKey});
  @override
  State<IntroVoiceBar> createState() => _IntroVoiceBarState();
}

class _IntroVoiceBarState extends State<IntroVoiceBar> {
  VoicePlayer? _player;
  StreamSubscription<VoiceState>? _sub;
  Object? _err;

  @override
  void didUpdateWidget(IntroVoiceBar old) {
    super.didUpdateWidget(old);
    // مصدر جديد (تسجيل آخر): نتخلص من المشغّل القديم
    if (old.url != widget.url || old.bytes != widget.bytes) {
      _sub?.cancel();
      _player?.dispose();
      _player = null;
      _err = null;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  void _toggle() {
    if (widget.bytes == null && (widget.url == null || widget.url!.isEmpty)) return;
    var p = _player;
    if (p == null) {
      p = VoicePlayer()..setSource(url: widget.url == null ? null : mediaUrl(widget.url!), bytes: widget.bytes, mime: widget.mime);
      _sub = p.changes.listen((s) {
        if (s.error != null) _fail(s.error!);
        if (mounted) setState(() {});
      });
      setState(() => _player = p);
    }
    if (p.state.playing) {
      p.pause();
    } else {
      p.play().catchError(_fail);
    }
  }

  void _fail(Object e) {
    if (!mounted || _err != null) return;
    setState(() => _err = e);
    toast(context, 'تعذر تشغيل التسجيل على هذا الجهاز', error: true);
  }

  @override
  Widget build(BuildContext context) {
    final p = _player;
    final s = p?.state ?? const VoiceState();
    final total = s.duration ?? Duration(seconds: widget.sec);
    final frac = total.inMilliseconds == 0 ? 0.0 : (s.position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    return Row(children: [
      Material(
        color: Joy.primary,
        shape: const CircleBorder(),
        child: InkWell(
          key: widget.playKey,
          customBorder: const CircleBorder(),
          onTap: _toggle,
          child: SizedBox(
            width: 44, height: 44,
            child: s.loading && !s.playing && _err == null
                ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Icon(_err != null ? Icons.error_outline_rounded : s.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Joy.primaryOn, size: 26),
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: SliderTheme(
          data: SliderThemeData(trackHeight: 4, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5), overlayShape: SliderComponentShape.noOverlay, activeTrackColor: Joy.primary, inactiveTrackColor: Joy.primarySoft, thumbColor: Joy.primary),
          child: Slider(value: frac, onChanged: p == null ? null : (v) => p.seek(Duration(milliseconds: (v * total.inMilliseconds).round()))),
        ),
      ),
      const SizedBox(width: 8),
      Text('${clockText(s.position.inSeconds)} / ${clockText(total.inSeconds)}', textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 12.5, color: Joy.textMuted, fontWeight: FontWeight.w600)),
    ]);
  }
}

/// بطاقة «عرّف بنفسك» في الملف: صوت (شريط تشغيل) أو فيديو أفقي (ملصق يبدأ التشغيل عند اللمس). لصاحب الحساب زر «تغيير».
class ProfileIntroCard extends StatefulWidget {
  final String name;
  final ProfileIntro intro;
  final bool owner;
  final VoidCallback? onChange;
  const ProfileIntroCard({super.key, required this.name, required this.intro, this.owner = false, this.onChange});
  @override
  State<ProfileIntroCard> createState() => _ProfileIntroCardState();
}

class _ProfileIntroCardState extends State<ProfileIntroCard> {
  bool _playVideo = false;

  @override
  Widget build(BuildContext context) {
    final i = widget.intro;
    final title = widget.owner ? (i.isVideo ? 'تعريفي المرئي' : 'تعريفي الصوتي') : '${widget.name} يعرّف بنفسه';
    final meta = [i.isVideo ? 'فيديو' : 'صوت', i.durationText, if (i.at != null) 'سُجّل ${timeAgo(i.at)}'].join(' · ');
    return JoyCard(
      key: const Key('intro-card'),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(i.isVideo ? Icons.videocam_rounded : Icons.mic_rounded, size: 18, color: Joy.primary),
          const SizedBox(width: 6),
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (widget.owner && widget.onChange != null) TextButton(key: const Key('intro-change'), onPressed: widget.onChange, child: const Text('تغيير')),
        ]),
        Text(meta, style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
        const SizedBox(height: 8),
        if (i.isVideo)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: _playVideo
                  ? Container(key: const Key('intro-video'), color: Colors.black, child: VideoView(url: mediaUrl(i.url), autoplay: true))
                  : InkWell(
                      key: const Key('intro-play'),
                      onTap: () => setState(() => _playVideo = true),
                      child: Container(
                        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0A6E78), Color(0xFF0B2F33)])),
                        child: Stack(alignment: Alignment.center, children: [
                          const Icon(Icons.play_circle_fill_rounded, size: 56, color: Colors.white),
                          Positioned(bottom: 8, right: 10, child: Text(i.durationText, textDirection: TextDirection.ltr, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12))),
                        ]),
                      ),
                    ),
            ),
          )
        else
          IntroVoiceBar(url: i.url, sec: i.sec, playKey: const Key('intro-play')),
      ]),
    );
  }
}

/// دعوة لإضافة تعريف حين لا يوجد (لصاحب الحساب): إطار متقطّع.
class IntroCallToAction extends StatelessWidget {
  final VoidCallback onTap;
  const IntroCallToAction({super.key, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        key: const Key('intro-cta'),
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: CustomPaint(
          painter: _DashedBorder(color: Joy.primary.withValues(alpha: .55)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(width: 44, height: 44, decoration: const BoxDecoration(color: Joy.primarySoft, shape: BoxShape.circle), child: const Icon(Icons.mic_rounded, color: Joy.primary)),
              const SizedBox(width: 12),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('عرّف بنفسك بصوتك أو بفيديو', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                Text('60 ثانية صوت أو 30 ثانية فيديو · يرفع الثقة والرسائل من ملفك', style: TextStyle(color: Joy.textMuted, fontSize: 12)),
              ])),
              const Icon(Icons.chevron_left_rounded, color: Joy.textMuted),
            ]),
          ),
        ),
      );
}

class _DashedBorder extends CustomPainter {
  final Color color;
  const _DashedBorder({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1.5;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16)));
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 6), paint);
        d += 10;
      }
    }
  }
  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}
