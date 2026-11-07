// مداخل رسائل الدوائر للعميل: «راسل الدائرة» في صفحة الدائرة العامة، وقسم «رسائل الدوائر» في قائمة المحادثات.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/biz_inbox_api.dart';
import '../../../api/biz_models.dart';
import '../../../core/app_theme.dart';
import '../../../core/require_account.dart';
import '../../../ui/widgets.dart';
import 'biz_inbox_providers.dart';
import 'biz_thread_page.dart';
import 'inbox_widgets.dart';

/// يفتح محادثتي الخاصة مع الدائرة (الزائر يرى دعوة الدخول أولاً)، مع مرجع اختياري يُرفق بأول رسالة.
void openBizThread(BuildContext context, Biz biz, {BizMsgRef? ref}) {
  if (!requireAccount(context)) return;
  final circle = BizInboxCircle(id: biz.id, name: biz.title, logoUrl: biz.logoUrl, category: biz.category.key, ownerId: biz.ownerId, verified: biz.verified);
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => BizThreadPage(bizId: biz.id, circle: circle, initialRef: ref)));
}

/// «راسل الدائرة»: رسالة خاصة لفريقها بدل السؤال العلني في مساحتها. لا يظهر لفريق الدائرة نفسها ولا لدائرة بلا مالك (لا أحد يرد).
class BizMessageButton extends StatelessWidget {
  final Biz biz;
  const BizMessageButton({super.key, required this.biz});

  @override
  Widget build(BuildContext context) {
    if (biz.ownerId == null || biz.canOperate) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Joy.surface2,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: const Key('biz-message'),
          borderRadius: BorderRadius.circular(16),
          onTap: () => openBizThread(context, biz),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Container(width: 40, height: 40, decoration: BoxDecoration(color: Joy.primarySoft, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.chat_bubble_outline_rounded, color: Joy.primary)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('راسل الدائرة', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                  Text('رسالة خاصة لفريق ${biz.title}، لا تظهر في المساحة العامة', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
                ]),
              ),
              const Icon(Icons.chevron_left_rounded, color: Joy.textMuted),
            ]),
          ),
        ),
      ),
    );
  }
}

/// تبويب «الدوائر» في قائمة المحادثات: محادثاتي الخاصة مع الدوائر، الأحدث أولاً.
class BizThreadsTab extends ConsumerWidget {
  const BizThreadsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(myBizThreadsProvider);
    return data.when(
      data: (d) => d.threads.isEmpty
          ? const EmptyState(icon: Icons.storefront_outlined, title: 'لا رسائل مع الدوائر بعد', subtitle: 'افتح صفحة أي دائرة واضغط «راسل الدائرة» لتسأل فريقها بشكل خاص.')
          : RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(myBizThreadsProvider);
                try { await ref.read(myBizThreadsProvider.future); } catch (_) { /* الخطأ يظهر في القائمة */ }
              },
              child: ListView.builder(
                key: const Key('biz-threads-list'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 96),
                itemCount: d.threads.length,
                itemBuilder: (_, i) => BizThreadRow(d.threads[i], divider: i < d.threads.length - 1),
              ),
            ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(myBizThreadsProvider)),
    );
  }
}

/// صف محادثة مع دائرة: الشعار، الاسم مع التوثيق أو «دائرة غير موثّقة»، آخر رسالة («أنت:» لرسالتي)، الوقت وشارة غير المقروء.
class BizThreadRow extends ConsumerWidget {
  final BizThread t;
  final bool divider;
  const BizThreadRow(this.t, {super.key, this.divider = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = t.biz ?? BizInboxCircle(id: t.bizId);
    final unread = t.unread > 0;
    return InkWell(
      key: Key('biz-thread-row-${t.id}'),
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => BizThreadPage(threadId: t.id, circle: c)));
        ref.invalidate(myBizThreadsProvider);
      },
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 12, 10),
          child: Row(children: [
            BizCircleLogo(circle: c, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(c.name.isEmpty ? 'دائرة' : c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w700, fontSize: 15.5))),
                  const SizedBox(width: 4),
                  if (c.verified) const Icon(Icons.verified_rounded, size: 15, color: Joy.success) else UnverifiedTag(key: Key('biz-thread-unverified-${t.id}'), compact: true),
                ]),
                const SizedBox(height: 3),
                Text('${t.lastSide == 'customer' ? 'أنت: ' : ''}${t.lastText}', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: unread ? Joy.text : Joy.textMuted, fontWeight: unread ? FontWeight.w600 : FontWeight.w500)),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
              Text(timeAgo(t.lastAt), style: TextStyle(fontSize: 11.5, color: unread ? Joy.primary : Joy.textMuted)),
              const SizedBox(height: 5),
              if (unread) UnreadBadge(t.unread, key: Key('biz-thread-unread-${t.id}')) else if (t.closed) const Text('مغلقة', style: TextStyle(fontSize: 11, color: Joy.textMuted)) else const SizedBox(height: 18),
            ]),
          ]),
        ),
        if (divider) const Padding(padding: EdgeInsetsDirectional.only(start: 76), child: Divider(height: 1)),
      ]),
    );
  }
}
