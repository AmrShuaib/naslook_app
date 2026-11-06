import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/client.dart';
import '../../api/posts_api.dart';
import '../../core/app_theme.dart';
import '../../state/app_state.dart';
import '../../state/safety_providers.dart';
import '../../ui/widgets.dart';
import 'overlay_canvas.dart' show colorFromHex;
import 'post_viewer.dart';

/// لحظات مكان واحد: ما نسبه الخادم إلى هذا المفتاح (server/map_posts.js: أقرب دائرة نشطة ضمن 250 متراً من اللحظة = `biz:<id>`)،
/// بلا موقع للمشاهد حتى لا يقصّها نطاق المسافة (من يتصفح دائرة في الدمام وهو في جدة يرى لحظاتها). عام للزائر (optionalAuth).
final placeMomentsProvider = FutureProvider.autoDispose.family<List<MapPost>, String>((ref, placeKey) async =>
    (await ref.watch(apiClientProvider).postsFeed(place: placeKey, limit: 30, radiusKm: 200)).items);

/// مدخل «لحظات هنا» في صفحة الدائرة العامة: شريط مصغّرات يفتح عارض اللحظات الحالي (PostViewerPage) على اللحظة المختارة.
/// لا يظهر شيء أثناء التحميل أو عند الخطأ أو حين لا لحظات (يحمل هامشه السفلي بنفسه).
class PlaceMomentsEntry extends ConsumerWidget {
  final String bizId;
  const PlaceMomentsEntry({super.key, required this.bizId});

  static String placeKeyOf(String bizId) => 'biz:$bizId';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = ref.watch(blockedIdsProvider);
    final all = ref.watch(placeMomentsProvider(placeKeyOf(bizId))).valueOrNull ?? const <MapPost>[];
    final posts = [for (final p in all) if (!isBlockedId(blocked, p.user.id)) p];
    if (posts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: JoyCard(
        key: const Key('place-moments'),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.auto_awesome_rounded, color: Joy.accent, size: 20),
            const SizedBox(width: 8),
            const Text('لحظات هنا', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(width: 6),
            Text(posts.length == 1 ? 'لحظة واحدة' : '${posts.length} لحظة', key: const Key('place-moments-count'), style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
            const Spacer(),
            TextButton(key: const Key('place-moments-all'), onPressed: () => PostViewerPage.open(context, posts), child: const Text('شاهد')),
          ]),
          const Text('ما شاركه الناس من هذا المكان مؤخراً', style: TextStyle(color: Joy.textMuted, fontSize: 12)),
          const SizedBox(height: 10),
          SizedBox(
            height: 128,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: posts.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => _Thumb(post: posts[i], onTap: () => PostViewerPage.open(context, posts, index: i)),
            ),
          ),
        ]),
      ),
    );
  }
}

/// مصغّرة لحظة: إطار الصورة أو الفيديو (مع رمز التشغيل)، أو لوحة بلون اللحظة النصية ونصها، ثم اسم الناشر ووقتها.
class _Thumb extends StatelessWidget {
  final MapPost post;
  final VoidCallback onTap;
  const _Thumb({required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = post;
    final url = p.mediaUrl;
    final hasFrame = url != null && url.isNotEmpty && (p.kind == 'image' || p.kind == 'video');
    final bg = colorFromHex(p.bg, Joy.accent);
    final dark = bg.computeLuminance() < .45;
    Widget board() => Container(
          color: p.kind == 'audio' ? const Color(0xFF0A6E78) : bg,
          padding: const EdgeInsets.all(8),
          alignment: Alignment.center,
          child: p.kind == 'audio'
              ? const Icon(Icons.mic_rounded, color: Colors.white, size: 28)
              : Text(p.summary, maxLines: 4, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontFamily: AppTheme.displayFont, fontWeight: FontWeight.w800, fontSize: 12.5, height: 1.3, color: dark ? Colors.white : Joy.text)),
        );
    return SizedBox(
      width: 84,
      child: Material(
        color: Joy.surface2,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('place-moment-${p.id}'),
          onTap: onTap,
          child: Stack(fit: StackFit.expand, children: [
            hasFrame ? Image.network(thumbUrl(url), fit: BoxFit.cover, errorBuilder: (_, __, ___) => board()) : board(),
            if (p.kind == 'video') const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 30, shadows: [Shadow(color: Colors.black45, blurRadius: 8)])),
            PositionedDirectional(
              start: 0, end: 0, bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(6, 10, 6, 5),
                decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black54])),
                child: Text('${p.user.nickname} · ${timeAgo(p.createdAt)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
