// طلب دائرة واحد بمعرّفه (تفتحه إشعارات النزاع وأزرار «عرض النزاع»): التفاصيل، الدفع وحالة المبلغ، وخيط «لدي مشكلة»،
// وأفعال كل طرف: العميل يفتح المشكلة ويرد، فريق الدائرة يؤكد الدفع في المكان أو «لم يحضر» ويرد، والإدارة تحسم.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../api/biz_api.dart';
import '../../api/biz_models.dart';
import '../../api/chat_tools_api.dart';
import '../../api/client.dart';
import '../../api/commerce_models.dart';
import '../../core/app_theme.dart';
import '../../core/media/pick_image.dart';
import '../../state/app_state.dart';
import '../../state/biz_providers.dart';
import '../../ui/widgets.dart';
import 'business_page.dart' show dayLabel, shortDate, bizErrText;

final bizOrderProvider = FutureProvider.autoDispose.family<BizOrder, String>((ref, id) => ref.watch(apiClientProvider).bizOrder(id));

/// رسالة خطأ أفعال الطلب والنزاع والدفع في المكان.
String orderErrText(Object e) {
  final s = e is ApiException ? '${e.body?['error'] ?? ''} $e' : e.toString();
  if (s.contains('not-disputable')) return 'لم يعد ممكناً فتح مشكلة على هذا الطلب (المهلة 7 أيام بعد الاستخدام)';
  if (s.contains('already-disputed')) return 'فتحت مشكلة على هذا الطلب من قبل';
  if (s.contains('bad-reason')) return 'اكتب وصفاً للمشكلة (5 أحرف على الأقل)';
  if (s.contains('bad-text')) return 'اكتب ردك';
  if (s.contains('no-open-dispute')) return 'حُسمت هذه المشكلة';
  if (s.contains('too-early')) return 'لا يُسجَّل «لم يحضر» قبل الموعد، ولا قبل يوم من طلب المنتج';
  if (s.contains('already-paid')) return 'سُجّل الدفع من قبل';
  if (s.contains('not-venue')) return 'هذا الطلب ليس بالدفع في المكان';
  if (s.contains('bad-status')) return 'تغيّرت حالة الطلب، حدّث الصفحة';
  if (s.contains('no-owner')) return 'لا مالك لهذه الدائرة الآن ليُحرَّر له المبلغ';
  if (s.contains('admin-only') || s.contains('forbidden')) return 'ليست لديك صلاحية لهذا الإجراء';
  return bizErrText(e);
}

class BizOrderPage extends ConsumerWidget {
  final String orderId;
  const BizOrderPage({super.key, required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = ref.watch(bizOrderProvider(orderId));
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: const Text('تفاصيل الطلب')),
      body: o.when(
        data: (o) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(bizOrderProvider(orderId)),
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [_OrderBody(o)]),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(bizOrderProvider(orderId))),
      ),
    );
  }
}

class _OrderBody extends ConsumerWidget {
  final BizOrder o;
  const _OrderBody(this.o);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customer = o.viewer == null || o.viewer == 'customer';
    final team = o.viewer == 'team' || o.viewer == 'admin';
    Widget kv(String k, String v, {Key? key}) => Padding(
          key: key,
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(k, style: const TextStyle(color: Joy.textMuted)), const SizedBox(width: 12), Expanded(child: Text(v, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600)))]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      JoyCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${o.bizName.isNotEmpty ? '${o.bizName} · ' : ''}${o.title}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(height: 4),
          Text('${o.kindLabel} · ${o.statusLabel}', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
          if (customer && o.status == 'confirmed') ...[
            const SizedBox(height: 12),
            Center(child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Joy.line)), child: QrImageView(data: o.code, size: 150))),
          ],
          const SizedBox(height: 8),
          Center(child: SelectableText(o.code, style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 2, fontSize: 16, color: Joy.primary))),
          const SizedBox(height: 8),
          if (team && o.customer != null) kv('العميل', o.customer!.nickname.isNotEmpty ? o.customer!.nickname : o.customer!.id),
          if (o.isCart) ...[
            OrderLinesBlock(order: o),
            kv('الاستلام', o.pickupLabel, key: const Key('order-page-pickup')),
            if (o.note.isNotEmpty) kv(team ? 'ملاحظة العميل' : 'ملاحظتك', o.note),
          ] else
            kv('التفاصيل', o.summary),
          if (o.startAt != null) kv(isSlotKind(o.kind) ? 'الموعد' : 'من', isSlotKind(o.kind) ? '${dayLabel(o.startAt!)} · ${clockOf(o.startAt)}' : '${dayLabel(o.startAt!)} · ${shortDate(o.startAt!)}'),
          kv('المبلغ', money(o.total)),
          kv('الدفع', team ? o.ownerMoneyLabel : o.paymentLabel, key: const Key('order-payment-line')),
          if (team && (o.noShows ?? 0) > 0) kv('لم يحضر سابقاً', arCount(o.noShows!, one: 'مرة واحدة', two: 'مرتان', few: 'مرات', many: 'مرة'), key: const Key('order-no-shows')),
        ]),
      ),
      if (team && o.venueUnpaid) ...[
        const SizedBox(height: 10),
        VenueActions(order: o, onDone: () => ref.invalidate(bizOrderProvider(o.id))),
      ],
      if (customer && o.disputable && o.dispute == null) ...[
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const Key('order-dispute'),
          onPressed: () async {
            final r = await showDisputeSheet(context, ref, o);
            if (r != null) ref.invalidate(bizOrderProvider(o.id));
          },
          icon: const Icon(Icons.report_problem_outlined, size: 18),
          label: const Text('لدي مشكلة'),
        ),
      ],
      if (o.dispute != null) ...[
        const SectionTitle('المشكلة'),
        DisputeThread(order: o),
      ],
    ]);
  }
}

/// أسطر طلب السلة: الكمية والصنف ومجموع السطر، وتحتها الخيارات المختارة وخصم العرض إن طُبّق عليه.
class OrderLinesBlock extends StatelessWidget {
  final BizOrder order;
  const OrderLinesBlock({super.key, required this.order});

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('order-lines'),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (i, l) in order.lines.indexed)
            Padding(
              key: Key('order-line-$i'),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${l.qty} ×', style: const TextStyle(fontWeight: FontWeight.w800, color: Joy.primary)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (l.optionsLabel.isNotEmpty) Text(l.optionsLabel, key: Key('order-line-options-$i'), style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
                    if (l.discount > 0) Text('${l.offerTitle ?? 'عرض'} · −${money(l.discount)}', style: const TextStyle(color: Joy.success, fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
                ),
                Text(money(l.total), style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
            ),
        ]),
      );
}

/// أزرار الدفع في المكان لفريق الدائرة: «تم الدفع»، و«لم يحضر» بعد حلول الموعد.
class VenueActions extends ConsumerStatefulWidget {
  final BizOrder order;
  final VoidCallback? onDone;
  const VenueActions({super.key, required this.order, this.onDone});
  @override
  ConsumerState<VenueActions> createState() => _VenueActionsState();
}

class _VenueActionsState extends ConsumerState<VenueActions> {
  bool busy = false;

  Future<void> _run(Future<BizOrder> Function() f, String done) async {
    setState(() => busy = true);
    try {
      final r = await f();
      invalidateBizAll(ref, r.bizId);
      widget.onDone?.call();
      if (mounted) toast(context, done);
    } catch (e) {
      if (mounted) toast(context, orderErrText(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    // «لم يحضر» بعد حلول الموعد، أو بعد يوم من طلب المنتج (الخادم يرفض قبلهما)، وللطلب المؤكد
    final canNoShow = o.canNoShowAt(DateTime.now());
    return Container(
      key: const Key('venue-unpaid-banner'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Joy.sunSoft, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.payments_outlined, color: Joy.sunText),
          const SizedBox(width: 8),
          Expanded(child: Text('الدفع في المكان: لم يُدفع بعد · ${money(o.total)}', style: const TextStyle(fontWeight: FontWeight.w700, color: Joy.sunText))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              key: const Key('owner-venue-paid'),
              onPressed: busy ? null : () => _run(() => ref.read(apiClientProvider).markVenuePaid(o.bizId, o.id), 'سُجّل الدفع'),
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('تم الدفع'),
            ),
          ),
          if (canNoShow) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              key: const Key('owner-no-show'),
              onPressed: busy
                  ? null
                  : () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (d) => AlertDialog(
                          title: const Text('لم يحضر؟'),
                          content: const Text('يتحرر الموعد أو المنتج، ويُحسب على العميل. بعد ثلاث مرات في دائرتك لا يتاح له الدفع في المكان.'),
                          actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('تراجع')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('لم يحضر'))],
                        ),
                      );
                      if (ok == true) await _run(() => ref.read(apiClientProvider).markNoShow(o.bizId, o.id), 'سُجّل عدم الحضور');
                    },
              icon: const Icon(Icons.person_off_outlined, size: 18),
              label: const Text('لم يحضر'),
            ),
          ],
        ]),
      ]),
    );
  }
}

/// خيط النزاع: السبب والصور ورسائل الطرفين وقرار الإدارة، مع حقل الرد ما دام مفتوحاً، وأزرار الحسم للإدارة.
class DisputeThread extends ConsumerStatefulWidget {
  final BizOrder order;
  const DisputeThread({super.key, required this.order});
  @override
  ConsumerState<DisputeThread> createState() => _DisputeThreadState();
}

class _DisputeThreadState extends ConsumerState<DisputeThread> {
  final reply = TextEditingController();
  bool busy = false;

  @override
  void dispose() {
    reply.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = reply.text.trim();
    if (t.length < 2) return;
    setState(() => busy = true);
    try {
      await ref.read(apiClientProvider).replyBizDispute(widget.order.id, t);
      reply.clear();
      ref.invalidate(bizOrderProvider(widget.order.id));
    } catch (e) {
      if (mounted) toast(context, orderErrText(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _resolve(String resolution) async {
    final note = await askText(context, title: 'قرار النزاع', hint: 'ملاحظة تصل للطرفين (اختياري)', confirm: 'تنفيذ');
    if (note == null || !mounted) return;
    setState(() => busy = true);
    try {
      await ref.read(apiClientProvider).adminResolveBizDispute(widget.order.id, resolution: resolution, note: note);
      ref.invalidate(bizOrderProvider(widget.order.id));
      if (mounted) toast(context, 'حُسم النزاع');
    } catch (e) {
      if (mounted) toast(context, orderErrText(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order, d = o.dispute!;
    return JoyCard(
      key: const Key('dispute-thread'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(d.open ? Icons.gavel_rounded : Icons.task_alt_rounded, color: d.open ? Joy.danger : Joy.success, size: 20),
          const SizedBox(width: 6),
          Expanded(child: Text(d.open ? 'قيد المراجعة · المبلغ مجمّد حتى تحسمه الإدارة' : 'حُسم: ${d.resolutionLabel}', key: const Key('dispute-status'), style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 8),
        Text(d.reason, style: const TextStyle(height: 1.5)),
        if (d.photos.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final p in d.photos)
              ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(thumbUrl(p), width: 72, height: 72, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 72, height: 72, color: Joy.surface2, child: const Icon(Icons.image_outlined, color: Joy.textMuted)))),
          ]),
        ],
        for (final m in d.messages)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: m.by == 'customer' ? Joy.surface2 : m.by == 'admin' ? Joy.sunSoft : Joy.primarySoft, borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${m.byLabel}${m.at != null ? ' · ${timeAgo(m.at)}' : ''}', style: const TextStyle(color: Joy.textMuted, fontSize: 11.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(m.text),
              ]),
            ),
          ),
        if (!d.open && (d.note ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('ملاحظة الإدارة: ${d.note}', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5))),
        if (d.open) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(key: const Key('dispute-reply-field'), controller: reply, maxLines: 3, minLines: 1, decoration: const InputDecoration(hintText: 'اكتب ردك…', isDense: true))),
            IconButton(key: const Key('dispute-reply-send'), onPressed: busy ? null : _send, icon: const Icon(Icons.send_rounded, color: Joy.primary)),
          ]),
          if (o.viewer == 'admin') ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, children: [
              FilledButton.tonal(key: const Key('order-resolve-refund'), onPressed: busy ? null : () => _resolve('refund'), child: const Text('إعادة المبلغ للعميل')),
              OutlinedButton(key: const Key('order-resolve-release'), onPressed: busy ? null : () => _resolve('release'), child: const Text('تحرير المبلغ للدائرة')),
              OutlinedButton(key: const Key('order-resolve-split'), onPressed: busy ? null : () => _resolve('split'), child: const Text('تقسيم')),
            ]),
          ],
        ],
      ]),
    );
  }
}

/// ورقة «لدي مشكلة»: وصف المشكلة وحتى أربع صور، ثم يُجمَّد تحرير المبلغ حتى تحسمه الإدارة. تعيد الطلب بعد الفتح.
Future<BizOrder?> showDisputeSheet(BuildContext context, WidgetRef ref, BizOrder o) => showModalBottomSheet<BizOrder>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => _DisputeSheet(order: o),
    );

class _DisputeSheet extends ConsumerStatefulWidget {
  final BizOrder order;
  const _DisputeSheet({required this.order});
  @override
  ConsumerState<_DisputeSheet> createState() => _DisputeSheetState();
}

class _DisputeSheetState extends ConsumerState<_DisputeSheet> {
  final reason = TextEditingController();
  final photos = <String>[];
  bool busy = false, uploading = false;

  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  Future<void> _addPhoto() async {
    try {
      final img = await pickImage();
      if (img == null) return;
      setState(() => uploading = true);
      final up = await ref.read(apiClientProvider).uploadMedia(img.bytes, contentType: img.mime, fileName: img.name);
      if (mounted) setState(() => photos.add(up.url));
    } catch (e) {
      if (mounted) toast(context, orderErrText(e), error: true);
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> _submit() async {
    final t = reason.text.trim();
    if (t.length < 5) {
      toast(context, 'اكتب وصفاً للمشكلة (5 أحرف على الأقل)', error: true);
      return;
    }
    setState(() => busy = true);
    try {
      final r = await ref.read(apiClientProvider).openBizDispute(widget.order.id, reason: t, photos: photos);
      ref.invalidate(myBizOrdersProvider);
      ref.invalidate(bizDetailProvider(widget.order.bizId));
      if (mounted) {
        Navigator.pop(context, r);
        toast(context, 'وصلت مشكلتك للدائرة والإدارة؛ المبلغ مجمّد حتى الحسم');
      }
    } catch (e) {
      if (mounted) toast(context, orderErrText(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        const Text('لدي مشكلة', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 4),
        Text('${o.title} · ${money(o.total)} · ${o.code}', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
        const SizedBox(height: 4),
        Text(o.held ? 'يتجمد المبلغ المحجوز فلا يصل للدائرة حتى تحسم الإدارة المشكلة.' : 'تراجع الإدارة المشكلة مع الدائرة، وقد تقرر إعادة المبلغ كله أو بعضه.',
            style: const TextStyle(color: Joy.textMuted, fontSize: 12.5, height: 1.5)),
        const SizedBox(height: 12),
        TextField(key: const Key('dispute-reason'), controller: reason, maxLines: 4, maxLength: 600, decoration: const InputDecoration(labelText: 'ما المشكلة؟', hintText: 'مثلاً: وصل المنتج مكسوراً، أو لم تُقدَّم الخدمة كما وُصفت')),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final p in photos)
            Stack(children: [
              ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(thumbUrl(p), width: 64, height: 64, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 64, height: 64, color: Joy.surface2))),
              Positioned(top: 0, left: 0, child: InkWell(onTap: () => setState(() => photos.remove(p)), child: const Icon(Icons.cancel_rounded, size: 18, color: Joy.danger))),
            ]),
          if (photos.length < 4)
            OutlinedButton.icon(
              key: const Key('dispute-photo'),
              onPressed: uploading ? null : _addPhoto,
              icon: uploading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add_a_photo_outlined, size: 18),
              label: Text('صورة (${photos.length}/4)'),
            ),
        ]),
        const SizedBox(height: 14),
        FilledButton.icon(key: const Key('dispute-submit'), onPressed: busy || uploading ? null : _submit, icon: const Icon(Icons.send_rounded), label: const Text('إرسال')),
      ]),
    );
  }
}
