import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../api/client.dart';
import '../../core/app_theme.dart';
import '../../core/media/video_view.dart';
import '../../core/media/voice_player.dart';
import 'overlay_canvas.dart';

/// وسائط المنشور خلف الطبقات: صورة (رابط أو بايتات)، فيديو (مشغّل أصلي عند العرض أو معاينة عند التحرير)،
/// تسجيل صوتي (بطاقة تشغيل بموجات)، أو خلفية ملونة للنص.
class PostMedia extends StatelessWidget {
  final String kind;
  final String? url;
  final Uint8List? bytes;
  final String? mime;
  final String? bg;
  final int? durationSec;
  final bool play;
  const PostMedia({super.key, required this.kind, this.url, this.bytes, this.mime, this.bg, this.durationSec, this.play = false});

  @override
  Widget build(BuildContext context) {
    switch (kind) {
      case 'image':
        if (bytes != null) return Image.memory(bytes!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _fallback(Icons.broken_image_outlined));
        if (url != null && url!.isNotEmpty) return Image.network(mediaUrl(url!), fit: BoxFit.cover, errorBuilder: (_, __, ___) => _fallback(Icons.broken_image_outlined));
        return _fallback(Icons.image_outlined);
      case 'video':
        if (play && url != null && url!.isNotEmpty) return Container(color: Colors.black, child: VideoView(url: mediaUrl(url!), autoplay: true));
        return Container(
          color: const Color(0xFF14181C),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.play_circle_fill_rounded, size: 72, color: Colors.white),
            const SizedBox(height: 8),
            Text('فيديو قصير${durationSec != null ? ' · $durationSec ث' : ''}', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
          ]),
        );
      case 'audio':
        return _AudioCard(url: url, bytes: bytes, mime: mime, durationSec: durationSec, play: play);
      default:
        final c = colorFromHex(bg, Joy.primary);
        return Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [c, Color.lerp(c, Colors.black, .45)!])));
    }
  }

  Widget _fallback(IconData icon) => Container(color: const Color(0xFF14181C), child: Icon(icon, size: 64, color: Colors.white38));
}

/// بطاقة التسجيل الصوتي: موجات ثابتة شبه عشوائية (بذرة من الرابط حتى تتطابق بين المحرّر والعارض) وزر تشغيل بتقدم.
/// التشغيل عبر [VoicePlayer]: عنصر <audio> أصلي على الويب يبدأ داخل حدث اللمس (شرط iOS).
class _AudioCard extends StatefulWidget {
  final String? url, mime;
  final Uint8List? bytes;
  final int? durationSec;
  final bool play;
  const _AudioCard({this.url, this.bytes, this.mime, this.durationSec, required this.play});
  @override
  State<_AudioCard> createState() => _AudioCardState();
}

class _AudioCardState extends State<_AudioCard> {
  VoicePlayer? _player;
  StreamSubscription<VoiceState>? _sub;
  Object? _err;

  @override
  void dispose() {
    _sub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  void _toggle() {
    var p = _player;
    if (p == null) {
      if (widget.bytes == null && (widget.url == null || widget.url!.isEmpty)) return;
      p = VoicePlayer()..setSource(url: widget.url == null ? null : mediaUrl(widget.url!), bytes: widget.bytes, mime: widget.mime);
      _sub = p.changes.listen((_) {
        if (mounted) setState(() {});
      });
      setState(() => _player = p);
    }
    if (p.state.playing) {
      p.pause();
    } else {
      p.play().catchError((Object e) {
        if (mounted) setState(() => _err = e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final seed = (widget.url ?? widget.bytes?.length.toString() ?? 'x').hashCode;
    final rnd = math.Random(seed);
    final bars = List.generate(28, (_) => .25 + rnd.nextDouble() * .75);
    final p = _player;
    final total = widget.durationSec != null ? Duration(seconds: widget.durationSec!) : null;
    return Container(
      decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0A6E78), Color(0xFF0B2F33)])),
      child: Builder(
        builder: (_) {
          final s = p?.state ?? const VoiceState();
          final failed = _err != null || s.error != null;
          final dur = s.duration ?? total;
          final frac = dur == null || dur.inMilliseconds == 0 ? 0.0 : (s.position.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
          return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.mic_rounded, size: 56, color: Colors.white),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < bars.length; i++)
                  Container(
                    width: 4, height: 14 + bars[i] * 46, margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(color: i / bars.length <= frac && frac > 0 ? Colors.white : Colors.white38, borderRadius: BorderRadius.circular(2)),
                  ),
              ]),
            ),
            const SizedBox(height: 18),
            if (widget.play || widget.bytes != null)
              Material(
                color: Colors.white,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _toggle,
                  child: SizedBox(
                    width: 64, height: 64,
                    child: s.loading && !s.playing && !failed
                        ? const Padding(padding: EdgeInsets.all(18), child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(failed ? Icons.error_outline_rounded : s.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: const Color(0xFF0A6E78), size: 38),
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Text(
              failed ? 'تعذر تشغيل التسجيل على هذا الجهاز' : dur == null ? 'تسجيل صوتي' : 'تسجيل صوتي · ${dur.inMinutes}:${(dur.inSeconds % 60).toString().padLeft(2, '0')}',
              style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
            ),
          ]);
        },
      ),
    );
  }
}
