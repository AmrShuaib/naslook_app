import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/client.dart';
import '../../api/commerce_models.dart';
import '../../api/jobs_models.dart';
import '../../core/app_theme.dart';
import '../../state/jobs_public_providers.dart';
import '../../ui/widgets.dart';
import '../events/events_page.dart';
import '../jobs/job_page.dart';
import '../market/market_page.dart';

/// أقسام الرئيسية المضافة مع نظام «الخريطة أولاً»: وظائف جديدة، من السوق، فعاليات قريبة.
/// كل قسم يعرض حتى خمسة عناصر أفقياً ويفتح صفحة العنصر؛ الخطأ لا يُظهر شيئاً حتى لا يعطّل الرئيسية.

class HomeJobsBlock extends ConsumerWidget {
  const HomeJobsBlock({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(jobsListProvider(jobsQueryAll)).valueOrNull?.items ?? const <Job>[];
    if (jobs.isEmpty) return const _Empty(icon: Icons.work_outline_rounded, text: 'لا وظائف منشورة الآن. أضف ملف توظيفك ليصلك المطابق منها.');
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: jobs.length.clamp(0, 6),
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final j = jobs[i];
          return JoyCard(
            key: Key('home-job-${j.id}'),
            padding: const EdgeInsets.all(10),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => JobPage(id: j.id, initial: j))),
            child: SizedBox(
              width: 190,
              child: Row(children: [
                Container(width: 40, height: 40, decoration: BoxDecoration(color: Joy.primarySoft, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.work_outline_rounded, color: Joy.primary)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(j.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                    Text(j.bizName ?? j.biz?.name ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.text, fontSize: 12)),
                    Text([if (j.city.isNotEmpty) j.city, j.typeLabel].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 11.5)),
                  ]),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class HomeMarketBlock extends ConsumerWidget {
  const HomeMarketBlock({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(marketHomeProvider).valueOrNull;
    final list = [...?home?.nearby, ...?home?.popular];
    final seen = <String>{};
    final items = [for (final l in list) if (seen.add(l.id)) l];
    if (items.isEmpty) return const _Empty(icon: Icons.shopping_bag_outlined, text: 'لا إعلانات قريبة الآن.');
    return SizedBox(
      height: 172,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length.clamp(0, 8),
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => _ListingMini(items[i]),
      ),
    );
  }
}

class _ListingMini extends StatelessWidget {
  final Listing l;
  const _ListingMini(this.l);
  @override
  Widget build(BuildContext context) {
    final img = l.imageUrl ?? (l.images.isNotEmpty ? l.images.first : null);
    return SizedBox(
      width: 140,
      child: JoyCard(
        key: Key('home-listing-${l.id}'),
        padding: EdgeInsets.zero,
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ListingPage(l.id))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: SizedBox(
              height: 96,
              width: double.infinity,
              child: img == null
                  ? Container(color: Joy.surface2, child: const Icon(Icons.image_outlined, color: Joy.textMuted))
                  : Image.network(thumbUrl(img), fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: Joy.surface2, child: const Icon(Icons.image_outlined, color: Joy.textMuted))),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 2),
              Text(l.price == 0 ? 'مجاناً' : money(l.price), style: const TextStyle(color: Joy.primary, fontWeight: FontWeight.w700, fontSize: 13)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class HomeEventsBlock extends ConsumerWidget {
  const HomeEventsBlock({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final all = ref.watch(eventsProvider).valueOrNull ?? const <Event>[];
    final events = [for (final e in all) if (!e.cancelled && (e.startsAt == null || e.startsAt!.isAfter(now.subtract(const Duration(hours: 6))))) e];
    if (events.isEmpty) return const _Empty(icon: Icons.event_outlined, text: 'لا فعاليات قادمة قريبة.');
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: events.length.clamp(0, 6),
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final e = events[i];
          return JoyCard(
            key: Key('home-event-${e.id}'),
            padding: const EdgeInsets.all(10),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EventDetailPage(eventId: e.id))),
            child: SizedBox(
              width: 190,
              child: Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: Joy.sunSoft, borderRadius: BorderRadius.circular(12)),
                  child: e.startsAt == null
                      ? const Icon(Icons.event_outlined, color: Joy.sunText)
                      : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text('${e.startsAt!.day}', style: const TextStyle(color: Joy.sunText, fontWeight: FontWeight.w800, fontSize: 16, height: 1.1)),
                          Text(_month(e.startsAt!.month), style: const TextStyle(color: Joy.sunText, fontSize: 10.5)),
                        ]),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                    Text(e.placeName ?? e.host.nickname, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
                    Text('${e.going} ذاهبون', style: const TextStyle(color: Joy.primary, fontSize: 11.5, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  static String _month(int m) => const ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'][m - 1];
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Empty({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [Icon(icon, color: Joy.textMuted, size: 20), const SizedBox(width: 8), Expanded(child: Text(text, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)))]),
      );
}
