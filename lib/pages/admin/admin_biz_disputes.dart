// نزاعات طلبات الدوائر في لوحة الإدارة (بجانب نزاعات السوق في قسم السوق): السبب والصور والطرفان وحالة المبلغ،
// والحسم بإعادة المبلغ للعميل أو تحريره للدائرة أو تقسيمه. التفاصيل والرد في صفحة الطلب نفسها.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/biz_api.dart';
import '../../api/biz_models.dart';
import '../../api/commerce_models.dart';
import '../../core/app_theme.dart';
import '../../state/app_state.dart';
import '../../ui/widgets.dart';
import '../business/biz_order_page.dart';
import 'admin_shell.dart';

final adminBizDisputesProvider = FutureProvider.autoDispose<List<BizOrder>>((ref) => ref.watch(apiClientProvider).adminBizDisputes());

class BizDisputesAdmin extends ConsumerWidget {
  const BizDisputesAdmin({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(adminBizDisputesProvider).valueOrNull ?? const <BizOrder>[];
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(key: const Key('admin-biz-disputes'), crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionTitle('نزاعات الدوائر (${list.length})'),
      for (final o in list)
        JoyCard(
          key: Key('cd-${o.id}'),
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => BizOrderPage(orderId: o.id)));
            ref.invalidate(adminBizDisputesProvider);
          },
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('${o.bizName} · ${o.title} · ${money(o.total)}', style: const TextStyle(fontWeight: FontWeight.w700))),
              Text(timeAgo(o.dispute?.createdAt), style: const TextStyle(color: Joy.textMuted, fontSize: 11.5)),
            ]),
            Text('العميل ${o.customer?.nickname ?? ''} · صاحب الدائرة ${o.owner?.nickname ?? '—'} · ${o.code}', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
            Text('${o.statusLabel} · ${o.held ? 'المبلغ محجوز لدى المنصة' : 'المبلغ وصل محفظة الدائرة'}', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
            if (o.dispute != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('السبب: ${o.dispute!.reason}')),
            if ((o.dispute?.photos.length ?? 0) > 0 || (o.dispute?.messages.length ?? 0) > 0)
              Text('${o.dispute!.photos.length} صور · ${o.dispute!.messages.length} ردود', style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, children: [
              FilledButton.tonal(key: Key('cd-refund-${o.id}'), onPressed: () => _resolve(context, ref, o, 'refund'), child: const Text('إعادة المبلغ للعميل')),
              OutlinedButton(key: Key('cd-release-${o.id}'), onPressed: () => _resolve(context, ref, o, 'release'), child: const Text('تحرير المبلغ للدائرة')),
              OutlinedButton(key: Key('cd-split-${o.id}'), onPressed: () => _resolve(context, ref, o, 'split'), child: const Text('تقسيم')),
            ]),
          ]),
        ),
    ]);
  }

  Future<void> _resolve(BuildContext context, WidgetRef ref, BizOrder o, String resolution) async {
    final note = await askText(context, title: 'قرار النزاع', hint: 'ملاحظة تصل للطرفين (اختياري)', confirm: 'تنفيذ');
    if (note == null || !context.mounted) return;
    try {
      await ref.read(apiClientProvider).adminResolveBizDispute(o.id, resolution: resolution, note: note);
      ref.invalidate(adminBizDisputesProvider);
      if (context.mounted) toast(context, 'حُسم النزاع');
    } catch (e) {
      if (context.mounted) toast(context, adminErrText(e), error: true);
    }
  }
}
