// طلبات المشترين: «أبحث عن…» يراه بائعو التصنيف القريبون ويردّون بعروضهم
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/commerce_api.dart';
import '../../api/commerce_models.dart';
import '../../core/app_theme.dart';
import '../../state/app_state.dart';
import '../../state/safety_providers.dart';
import '../../ui/profile_avatar.dart';
import '../../ui/report_sheet.dart';
import '../../ui/widgets.dart';
import '../chat/chat_thread_page.dart';
import 'market_page.dart';

final wantedListProvider = FutureProvider.family<List<Wanted>, bool>((ref, mine) async {
  final pos = await ref.watch(marketPosProvider.future);
  return ref.watch(apiClientProvider).wanted(lat: pos?.lat, lng: pos?.lng, mine: mine);
});
final wantedProvider = FutureProvider.family<Wanted, String>((ref, id) => ref.watch(apiClientProvider).wantedDetail(id));

class WantedPage extends ConsumerWidget {
  const WantedPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => DefaultTabController(length: 2, child: Scaffold(
        backgroundColor: Joy.bg,
        appBar: AppBar(title: const Text('طلبات المشترين'), bottom: const TabBar(tabs: [Tab(text: 'الكل'), Tab(text: 'طلباتي')])),
        floatingActionButton: FloatingActionButton.extended(key: const Key('wanted-new'), onPressed: () => _create(context, ref), backgroundColor: Joy.primary, foregroundColor: Joy.primaryOn, icon: const Icon(Icons.campaign_outlined), label: const Text('أبحث عن…')),
        body: const TabBarView(children: [_List(mine: false), _List(mine: true)]),
      ));

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController(), desc = TextEditingController(), budget = TextEditingController(); String cat = 'services';
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(title: const Text('ماذا تبحث عنه؟'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(key: const Key('wanted-title'), controller: title, decoration: const InputDecoration(labelText: 'مثال: مدرّس فيزياء ثانوي في الدمام'), autofocus: true),
      TextField(controller: desc, maxLines: 3, decoration: const InputDecoration(labelText: 'تفاصيل (اختياري)')),
      DropdownButtonFormField<String>(initialValue: cat, decoration: const InputDecoration(labelText: 'التصنيف'), items: [for (final e in marketCategories.entries) DropdownMenuItem(value: e.key, child: Text(e.value))], onChanged: (v) => setS(() => cat = v ?? 'other')),
      TextField(key: const Key('wanted-budget'), controller: budget, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الميزانية القصوى (ر.س، اختياري)')),
    ])), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(key: const Key('wanted-send'), onPressed: () => Navigator.pop(ctx, true), child: const Text('نشر الطلب'))])));
    if (ok != true || !context.mounted) return;
    final pos = ref.read(marketPosProvider).valueOrNull;
    try { await ref.read(apiClientProvider).createWanted({'title': title.text.trim(), 'description': desc.text.trim(), 'category': cat, if (budget.text.trim().isNotEmpty) 'budgetMax': parseSar(budget.text), if (pos != null) ...{'lat': pos.lat, 'lng': pos.lng}}); ref.invalidate(wantedListProvider); if (context.mounted) toast(context, 'نُشر طلبك وسيصل بائعي التصنيف القريبين'); }
    catch (e) { if (context.mounted) toast(context, e.toString().contains('too-many-open') ? 'لديك ٥ طلبات مفتوحة، أغلق أحدها أولاً' : marketErrText(e), error: true); }
  }
}

class _List extends ConsumerWidget {
  final bool mine;
  const _List({required this.mine});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = ref.watch(wantedListProvider(mine));
    final blocked = ref.watch(blockedIdsProvider);
    return l.when(
      data: (all) => switch ([for (final w in all) if (!isBlockedId(blocked, w.user.id)) w]) { final items => items.isEmpty ? EmptyState(icon: Icons.campaign_outlined, title: mine ? 'لم تنشر طلباً بعد' : 'لا طلبات مفتوحة حالياً', subtitle: mine ? 'اضغط «أبحث عن…» واكتب ما تحتاجه.' : 'الطلبات القريبة منك تظهر هنا ويمكنك الرد عليها بعرض.')
          : RefreshIndicator(onRefresh: () async => ref.invalidate(wantedListProvider), child: ListView.separated(padding: const EdgeInsets.all(20), itemCount: items.length, separatorBuilder: (_, __) => const SizedBox(height: 10), itemBuilder: (_, i) {
              final w = items[i];
              return JoyCard(onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => WantedDetailPage(w.id))), child: Row(children: [
                ProfileAvatar(person: w.user, size: 40), const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(w.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                  Text('${marketCategories[w.category] ?? w.category}${w.budgetMax != null ? ' · حتى ${money(w.budgetMax!)}' : ''}${w.distanceKm != null ? ' · ${w.distanceKm!.toStringAsFixed(0)} كم' : ''} · ${timeAgo(w.createdAt)}', style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
                ])),
                Column(children: [Text('${w.replies}', style: const TextStyle(fontWeight: FontWeight.w800)), const Text('عروض', style: TextStyle(color: Joy.textMuted, fontSize: 10.5))]),
              ]));
            })) },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(wantedListProvider)),
    );
  }
}

class WantedDetailPage extends ConsumerWidget {
  final String id;
  const WantedDetailPage(this.id, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(wantedProvider(id));
    final blocked = ref.watch(blockedIdsProvider);
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: const Text('طلب مشترٍ'), actions: [
        if (w.valueOrNull?.mine == true && w.valueOrNull?.status == 'open') TextButton(onPressed: () async { await ref.read(apiClientProvider).closeWanted(id); ref.invalidate(wantedProvider(id)); ref.invalidate(wantedListProvider); }, child: const Text('إغلاق الطلب')),
        if (w.valueOrNull case final x? when !x.mine)
          ReportMenuButton(type: 'wanted', id: x.id, author: x.user, keyPrefix: 'wanted', iconSize: 24, color: Joy.text, reportLabel: 'إبلاغ عن الطلب',
            onReported: (r) { if (r.hidden || r.blocked) { ref.invalidate(wantedListProvider); if (context.mounted) Navigator.of(context).maybePop(); } },
            onBlocked: () { ref.invalidate(wantedListProvider); if (context.mounted) Navigator.of(context).maybePop(); }),
      ]),
      body: w.when(
        data: (x) => ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
          Row(children: [ProfileAvatar(person: x.user, size: 44), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(x.user.nickname, style: const TextStyle(fontWeight: FontWeight.w700)), Text('${timeAgo(x.createdAt)} · ${x.status == 'open' ? 'مفتوح' : 'مغلق'}', style: const TextStyle(color: Joy.textMuted, fontSize: 12))]))]),
          const SizedBox(height: 12),
          Text(x.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          if (x.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(x.description, style: const TextStyle(height: 1.6))),
          Padding(padding: const EdgeInsets.only(top: 6), child: Text('${marketCategories[x.category] ?? x.category}${x.budgetMax != null ? ' · الميزانية حتى ${money(x.budgetMax!)}' : ''}${x.placeName != null ? ' · ${x.placeName}' : ''}', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5))),
          SectionTitle('العروض (${x.replyList.length})'),
          if (x.replyList.isEmpty) const Text('لا عروض بعد', style: TextStyle(color: Joy.textMuted)),
          for (final r in x.replyList) if (!isBlockedId(blocked, r.seller.id)) JoyCard(key: Key('wanted-reply-${r.id}'), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [ProfileAvatar(person: r.seller, size: 32), const SizedBox(width: 8), Expanded(child: Text(r.seller.nickname, style: const TextStyle(fontWeight: FontWeight.w600))), if (r.price != null) Text(money(r.price!), style: const TextStyle(fontWeight: FontWeight.w800, color: Joy.primary)),
              if (!r.mine) SizedBox(height: 32, child: ReportMenuButton(type: 'wanted-reply', id: r.id, author: r.seller, keyPrefix: 'wreply-${r.id}', reportLabel: 'إبلاغ عن الرد',
                onReported: (o) { if (o.hidden) ref.invalidate(wantedProvider(id)); }))]),
            if (r.text.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(r.text)),
            Row(children: [
              if (r.listingId != null) TextButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ListingPage(r.listingId!))), icon: const Icon(Icons.storefront_outlined, size: 18), label: Text(r.listingTitle ?? 'العرض')),
              if (x.mine && !r.mine) TextButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadPage(peer: r.seller))), icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18), label: const Text('مراسلة')),
            ]),
          ])),
          if (!x.mine && x.status == 'open') Padding(padding: const EdgeInsets.only(top: 12), child: FilledButton.icon(key: const Key('wanted-reply'), onPressed: () => _reply(context, ref, x), icon: const Icon(Icons.reply_rounded, size: 18), label: const Text('قدّم عرضك'))),
        ]),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(wantedProvider(id))),
      ),
    );
  }

  Future<void> _reply(BuildContext context, WidgetRef ref, Wanted w) async {
    final text = TextEditingController(), price = TextEditingController(); String? listingId;
    List<Listing> mine = const []; try { mine = (await ref.read(apiClientProvider).myListings()).where((l) => l.status == 'active').toList(); } catch (_) {}
    if (!context.mounted) return;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(title: const Text('عرضك'), content: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(key: const Key('wanted-reply-text'), controller: text, maxLines: 3, decoration: const InputDecoration(labelText: 'ما تقدّمه وشروطه'), autofocus: true),
      TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعر (ر.س، اختياري)')),
      if (mine.isNotEmpty) DropdownButtonFormField<String?>(initialValue: listingId, decoration: const InputDecoration(labelText: 'اربط عرضاً من عروضك (اختياري)'), items: [const DropdownMenuItem(value: null, child: Text('بلا')), for (final l in mine) DropdownMenuItem(value: l.id, child: Text(l.title, overflow: TextOverflow.ellipsis))], onChanged: (v) => setS(() => listingId = v)),
    ]), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(key: const Key('wanted-reply-send'), onPressed: () => Navigator.pop(ctx, true), child: const Text('إرسال'))])));
    if (ok != true || !context.mounted) return;
    try { await ref.read(apiClientProvider).replyWanted(w.id, text: text.text.trim(), price: price.text.trim().isEmpty ? null : parseSar(price.text), listingId: listingId); ref.invalidate(wantedProvider(w.id)); ref.invalidate(wantedListProvider); if (context.mounted) toast(context, 'وصل عرضك للمشتري'); }
    catch (e) { if (context.mounted) toast(context, marketErrText(e), error: true); }
  }
}
