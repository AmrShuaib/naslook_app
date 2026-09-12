import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/app_theme.dart';
import '../../core/media/video_view.dart';
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
        if (url != null && url!.isNotEmpty) return Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _fallback(Icons.broken_image_outlined));
        return _fallback(Icons.image_outlined);
      case 'video':
        if (play && url != null && url!.isNotEmpty) return Container(color: Colors.black, child: VideoView(url: url!, autoplay: true));
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
  AudioPlayer? _player;
  bool _loading = false;

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    try {
      if (_player == null) {
        setState(() => _loading = true);
        final p = AudioPlayer();
        if (widget.bytes != null) {
          await p.setAudioSource(AudioSource.uri(Uri.dataFromBytes(widget.bytes!, mimeType: widget.mime ?? 'audio/webm')));
        } else if (widget.url != null) {
          await p.setUrl(widget.url!);
        }
        p.playerStateStream.listen((s) {
          if (s.processingState == ProcessingState.completed) {
            p.seek(Duration.zero);
            p.pause();
          }
        });
        if (!mounted) return;
        setState(() {
          _player = p;
          _loading = false;
        });
      }
      final p = _player!;
      if (p.playing) {
        await p.pause();
      } else {
        await p.play();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
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
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.mic_rounded, size: 56, color: Colors.white),
        const SizedBox(height: 18),
        StreamBuilder<Duration>(
          stream: p?.positionStream,
          builder: (_, snap) {
            final pos = snap.data ?? Duration.zero;
            final frac = total == null || total.inMilliseconds == 0 ? 0.0 : (pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < bars.length; i++)
                  Container(
                    width: 4, height: 14 + bars[i] * 46, margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(color: i / bars.length <= frac && frac > 0 ? Colors.white : Colors.white38, borderRadius: BorderRadius.circular(2)),
                  ),
              ]),
            );
          },
        ),
        const SizedBox(height: 18),
        if (widget.play || widget.bytes != null)
          Material(
            color: Colors.white,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _loading ? null : _toggle,
              child: SizedBox(
                width: 64, height: 64,
                child: _loading
                    ? const Padding(padding: EdgeInsets.all(18), child: CircularProgressIndicator(strokeWidth: 2))
                    : StreamBuilder<PlayerState>(stream: p?.playerStateStream, builder: (_, s) => Icon((s.data?.playing ?? false) ? Icons.pause_rounded : Icons.play_arrow_rounded, color: const Color(0xFF0A6E78), size: 38)),
              ),
            ),
          ),
        const SizedBox(height: 10),
        Text(total == null ? 'تسجيل صوتي' : 'تسجيل صوتي · ${total.inMinutes}:${(total.inSeconds % 60).toString().padLeft(2, '0')}', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
