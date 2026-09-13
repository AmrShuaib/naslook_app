import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/posts_api.dart';
import '../../core/app_theme.dart';
import '../../state/app_state.dart';
import '../../ui/widgets.dart';

/// مفتاح إحصاءات: منشور واحد، أو منشوراتي (بلا مفاتيح)، أو منشورات دائرة تجارية.
typedef PostStatsKey = ({String? postId, String? bizId, int days});

final postStatsProvider = FutureProvider.family<PostStats, PostStatsKey>((ref, k) {
  final api = ref.watch(apiClientProvider);
  if (k.postId != null) return api.postStats(k.postId!, days: k.days);
  if (k.bizId != null) return api.bizPostStats(k.bizId!, days: k.days);
  return api.myPostStats(days: k.days);
});

/// يفتح ورقة الإحصاءات لمنشور، أو لمنشوراتي، أو لمنشورات دائرة.
Future<void> showPostStats(BuildContext context, {String? postId, String? bizId}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Joy.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .85,
        minChildSize: .5,
        maxChildSize: .95,
        builder: (_, ctl) => PostStatsSheet(postId: postId, bizId: bizId, scroll: ctl),
      ),
    );

/// لوحة إحصاءات: المجاميع، المشاهدات بالساعة (24 ساعة)، بالأيام، وقائمة المنشورات عند التجميع.
class PostStatsSheet extends ConsumerStatefulWidget {
  final String? postId, bizId;
  final ScrollController? scroll;
  const PostStatsSheet({super.key, this.postId, this.bizId, this.scroll});
  @override
  ConsumerState<PostStatsSheet> createState() => _PostStatsSheetState();
}

class _PostStatsSheetState extends ConsumerState<PostStatsSheet> {
  int days = 7;

  @override
  Widget build(BuildContext context) {
    final key = (postId: widget.postId, bizId: widget.bizId, days: days);
    final stats = ref.watch(postStatsProvider(key));
    final title = widget.postId != null ? 'إحصاءات المنشور' : widget.bizId != null ? 'منشورات الخريطة عن الدائرة' : 'إحصاءات منشوراتي';
    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(20, 12, 20, 32), children: [
      Row(children: [
        Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
        for (final d in const [7, 30])
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 6),
            child: ChoiceChip(label: Text('$d يوم'), selected: days == d, showCheckmark: false, onSelected: (_) => setState(() => days = d)),
          ),
      ]),
      const SizedBox(height: 10),
      stats.when(
        data: (s) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: _Tile('مشاهدة', s.totals.views, Icons.visibility_outlined, Joy.primary, hint: s.uniqueViews > 0 ? '${s.uniqueViews} شخصاً' : null)),
            const SizedBox(width: 8),
            Expanded(child: _Tile('إعجاب', s.totals.likes, Icons.favorite_border_rounded, Joy.accent)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _Tile('ضغطة إجراء', s.totals.cta, Icons.ads_click_rounded, Joy.sunText)),
            const SizedBox(width: 8),
            Expanded(child: _Tile('مراسلة', s.totals.contacts, Icons.chat_bubble_outline_rounded, Joy.success)),
          ]),
          if (s.totals.views > 0 && (s.totals.cta > 0 || s.totals.contacts > 0))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('نسبة التفاعل: ${((s.totals.cta + s.totals.contacts) * 100 / s.totals.views).toStringAsFixed(1)}٪ من المشاهدات ضغطت زر الإجراء أو راسلت', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
            ),
          const SizedBox(height: 14),
          const SectionTitle('آخر 24 ساعة'),
          JoyCard(child: MiniBars(values: [for (final p in s.hourly) p.t.views], secondary: [for (final p in s.hourly) p.t.cta + p.t.contacts], labels: [for (final (i, p) in s.hourly.indexed) i % 6 == 5 || i == 0 ? p.label : ''], legend: 'مشاهدات · وبالبرتقالي: إجراء أو مراسلة')),
          const SizedBox(height: 8),
          SectionTitle('آخر $days يوماً'),
          JoyCard(child: MiniBars(values: [for (final p in s.daily) p.t.views], secondary: [for (final p in s.daily) p.t.cta + p.t.contacts], labels: [for (final (i, p) in s.daily.indexed) s.daily.length <= 7 || i % 5 == 0 || i == s.daily.length - 1 ? p.label : ''], legend: 'مشاهدات لكل يوم')),
          if (widget.postId == null) ...[
            const SizedBox(height: 8),
            SectionTitle('حسب المنشور · ${s.posts}'),
            if (s.byPost.isEmpty)
              const JoyCard(child: Text('لا منشورات في هذه الفترة', style: TextStyle(color: Joy.textMuted)))
            else
              JoyCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  for (final (i, p) in s.byPost.indexed)
                    ListRow(
                      leading: Icon(switch (p.kind) { 'image' => Icons.image_outlined, 'video' => Icons.videocam_outlined, 'audio' => Icons.mic_rounded, _ => Icons.text_fields_rounded }, color: Joy.textMuted),
                      title: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${p.t.views} مشاهدة · ${p.t.cta} إجراء · ${p.t.contacts} مراسلة · ${p.t.likes} إعجاب', style: const TextStyle(fontSize: 12)),
                      divider: i < s.byPost.length - 1,
                    ),
                ]),
              ),
          ],
        ]),
        loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(postStatsProvider(key))),
      ),
    ]);
  }
}

class _Tile extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final String? hint;
  const _Tile(this.label, this.value, this.icon, this.color, {this.hint});
  @override
  Widget build(BuildContext context) => JoyCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Container(width: 38, height: 38, decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 20)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$value', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, height: 1.1)),
            Text(hint == null ? label : '$label · $hint', style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
          ])),
        ]),
      );
}

/// أعمدة صغيرة بلا مكتبة رسوم: قيمة أساسية (مشاهدات) وقيمة ثانوية اختيارية فوقها (تفاعل).
class MiniBars extends StatelessWidget {
  final List<int> values;
  final List<int>? secondary;
  final List<String> labels;
  final String? legend;
  const MiniBars({super.key, required this.values, this.secondary, required this.labels, this.legend});

  @override
  Widget build(BuildContext context) {
    final max = values.fold<int>(0, (m, v) => v > m ? v : m);
    final total = values.fold<int>(0, (a, b) => a + b);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: 96,
        child: max == 0
            ? const Center(child: Text('لا بيانات بعد', style: TextStyle(color: Joy.textMuted, fontSize: 12.5)))
            : Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (var i = 0; i < values.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                        if (secondary != null && i < secondary!.length && secondary![i] > 0)
                          Container(height: (secondary![i] / max * 84).clamp(3.0, 84.0), decoration: BoxDecoration(color: Joy.accent, borderRadius: BorderRadius.circular(3))),
                        Container(height: values[i] == 0 ? 2 : (values[i] / max * 84).clamp(3.0, 84.0), decoration: BoxDecoration(color: values[i] == 0 ? Joy.surface2 : Joy.primary, borderRadius: BorderRadius.circular(3))),
                      ]),
                    ),
                  ),
              ]),
      ),
      const SizedBox(height: 4),
      Row(children: [for (final l in labels) Expanded(child: Text(l, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9.5, color: Joy.textMuted), maxLines: 1, overflow: TextOverflow.clip))]),
      if (legend != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('$legend · الإجمالي $total · الأعلى $max', style: const TextStyle(fontSize: 11.5, color: Joy.textMuted))),
    ]);
  }
}
