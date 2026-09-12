import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/biz_api.dart';
import '../../api/biz_models.dart';
import '../../api/client.dart';
import '../../api/commerce_models.dart';
import '../../core/app_theme.dart';
import '../../core/nav_provider.dart';
import '../../state/app_state.dart';
import '../../state/biz_providers.dart';
import '../../ui/profile_avatar.dart';
import '../../ui/widgets.dart';
import '../wallet/wallet_page.dart';
import 'my_bookings_page.dart';
import 'owner/business_dashboard_page.dart';
import 'owner/dashboard_posts.dart';

const _days = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
const _months = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];

/// "اليوم" أو "غداً" أو اسم اليوم والتاريخ.
String dayLabel(DateTime t) {
  final now = DateTime.now();
  final d0 = DateTime(now.year, now.month, now.day), d = DateTime(t.year, t.month, t.day);
  final diff = d.difference(d0).inDays;
  if (diff == 0) return 'اليوم';
  if (diff == 1) return 'غداً';
  return '${_days[t.weekday - 1]} ${t.day} ${_months[t.month - 1]}';
}

String shortDate(DateTime t) => '${t.day} ${_months[t.month - 1]}';

/// رسالة خطأ الدفع/الحجز المفهومة للمستخدم.
String bizErrText(Object e) {
  final s = e.toString();
  if (s.contains('insufficient-funds')) return 'الرصيد غير كافٍ في المحفظة';
  if (s.contains('sold-out')) return 'نفدت الكمية أو المقاعد';
  if (s.contains('unavailable')) return 'غير متاح في هذه المدة';
  if (s.contains('bad-slot')) return 'هذا الموعد لم يعد متاحاً، اختر موعداً آخر';
  if (s.contains('bad-range') || s.contains('bad-date')) return 'اختر تاريخ بداية ونهاية صحيحين';
  if (s.contains('in-past')) return 'لا يمكن الحجز في تاريخ مضى';
  if (s.contains('not-cancellable')) return 'انتهت مهلة الإلغاء لهذا الحجز';
  if (s.contains('already-owned')) return 'لهذه الدائرة مالك بالفعل';
  if (e is ApiException) return e.message;
  return s;
}

/// يفتح صفحة دائرة تجارية.
void openBusiness(BuildContext context, String id, {Biz? initial}) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BusinessPage(id: id, initial: initial)));

class BusinessPage extends ConsumerStatefulWidget {
  final String id;
  final Biz? initial;
  const BusinessPage({super.key, required this.id, this.initial});
  @override
  ConsumerState<BusinessPage> createState() => _BusinessPageState();
}

class _BusinessPageState extends ConsumerState<BusinessPage> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(bizDetailProvider(widget.id));
    final b = detail.valueOrNull ?? widget.initial;
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(
        title: Text(b?.title ?? 'الدائرة'),
        actions: [
          if (b != null && b.canOperate) IconButton(tooltip: 'لوحة التحكم', icon: const Icon(Icons.dashboard_customize_outlined, color: Joy.primary), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BusinessDashboardPage(id: b.id, initial: b)))),
          if (b != null) IconButton(tooltip: 'على الخريطة', icon: const Icon(Icons.map_outlined), onPressed: () => _onMap(b)),
          IconButton(tooltip: 'حجوزاتي', icon: const Icon(Icons.receipt_long_outlined), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyBookingsPage()))),
        ],
      ),
      body: detail.when(
        data: (biz) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(bizDetailProvider(widget.id)),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [
              _Header(biz: biz, busy: _busy, onFollow: () => _follow(biz)),
              const SizedBox(height: 12),
              _InfoCard(biz: biz, onMap: () => _onMap(biz)),
              if (biz.highlights.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: [for (final h in biz.highlights) Chip(avatar: const Icon(Icons.check_rounded, size: 14, color: Joy.success), label: Text(h, style: const TextStyle(fontFamily: AppTheme.bodyFont, fontSize: 12.5, color: Joy.text)), visualDensity: VisualDensity.compact, backgroundColor: Joy.surface2, side: BorderSide.none)]),
              ],
              if (!biz.active)
                Container(margin: const EdgeInsets.only(top: 10), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Joy.accentSoft, borderRadius: BorderRadius.circular(14)), child: const Row(children: [Icon(Icons.pause_circle_outline_rounded, color: Joy.accent), SizedBox(width: 8), Expanded(child: Text('الدائرة موقوفة مؤقتاً ولا تظهر للعامة', style: TextStyle(color: Joy.accent, fontWeight: FontWeight.w600, fontSize: 13)))])),
              if (biz.posts.isNotEmpty) ...[
                const SizedBox(height: 16),
                const SectionTitle('الأخبار والعروض'),
                for (final p in biz.posts) Padding(padding: const EdgeInsets.only(bottom: 10), child: PostCard(post: p, biz: biz)),
              ],
              const SizedBox(height: 16),
              SectionTitle(biz.category.catalogTitle),
              if (biz.items.isEmpty) const EmptyState(icon: Icons.inventory_2_outlined, title: 'لا عناصر بعد'),
              for (final it in biz.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: switch (it.kind) {
                    'showtime' => _ShowtimeCard(biz: biz, item: it, onOrder: _order),
                    'room' || 'car' => _BookableCard(biz: biz, item: it, onBook: () => _book(biz, it)),
                    _ => _ProductCard(biz: biz, item: it, onBuy: () => _buy(biz, it)),
                  },
                ),
              if (biz.myOrders.isNotEmpty) ...[
                const SizedBox(height: 8),
                SectionTitle('${biz.category.orderNoun == 'طلب' ? 'طلباتي' : 'حجوزاتي'} هنا', action: 'الكل', onAction: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyBookingsPage()))),
                JoyCard(padding: EdgeInsets.zero, child: Column(children: [for (final (i, o) in biz.myOrders.take(5).indexed) OrderRow(o, last: i == biz.myOrders.take(5).length - 1, onChanged: () => invalidateBiz(ref, biz.id))])),
              ],
              const SizedBox(height: 8),
              SectionTitle('التقييمات', action: 'قيّم', onAction: () => _review(biz)),
              _Reviews(biz: biz),
              const SizedBox(height: 12),
              if (biz.ownerId == null) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text('دائرة تعريفية أنشأها Naslife للعلامة؛ الشراء والحجز يتمّان عبر محفظة ناس لايف وليست الدائرة قناة رسمية للعلامة.', style: TextStyle(color: Joy.textMuted, fontSize: 11.5, height: 1.5)),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(onPressed: () => _claim(biz), icon: const Icon(Icons.verified_user_outlined, size: 18), label: const Text('هل تمثّل هذا النشاط؟ اطلب ملكية الدائرة')),
              ],
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(bizDetailProvider(widget.id))),
      ),
    );
  }

  Future<void> _claim(Biz b) async {
    final note = await askText(context, title: 'طلب ملكية ${b.title}', hint: 'عرّف بنفسك وصلتك بالنشاط (مثلاً: مدير الفرع، رقم السجل التجاري…)', confirm: 'إرسال الطلب');
    if (note == null) return;
    try {
      final status = await ref.read(apiClientProvider).claimBiz(b.id, note: note.trim());
      invalidateBiz(ref, b.id);
      if (mounted) toast(context, status == 'approved' ? 'أصبحت مالك الدائرة؛ افتح لوحة التحكم من أعلى الصفحة' : 'أُرسل طلبك وسيراجعه فريق Naslife');
    } catch (e) {
      if (mounted) toast(context, bizErrText(e), error: true);
    }
  }

  void _onMap(Biz b) {
    ref.read(mapFocusProvider.notifier).state = (lat: b.lat, lng: b.lng);
    ref.read(navIndexProvider.notifier).state = 1;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _follow(Biz b) async {
    setState(() => _busy = true);
    try {
      if (b.following) {
        await ref.read(apiClientProvider).unfollowBiz(b.id);
      } else {
        await ref.read(apiClientProvider).followBiz(b.id);
      }
      invalidateBiz(ref, b.id);
      if (mounted) toast(context, b.following ? 'ألغيت متابعة ${b.title}' : 'أصبحت تتابع ${b.title}');
    } catch (e) {
      if (mounted) toast(context, bizErrText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review(Biz b) async {
    var rating = b.reviews.where((r) => r.mine).firstOrNull?.rating ?? 5;
    final text = TextEditingController(text: b.reviews.where((r) => r.mine).firstOrNull?.text ?? '');
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('قيّم ${b.title}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 1; i <= 5; i++)
                IconButton(iconSize: 34, onPressed: () => setS(() => rating = i), icon: Icon(i <= rating ? Icons.star_rounded : Icons.star_outline_rounded, color: Joy.warning)),
            ]),
            TextField(controller: text, maxLines: 3, decoration: const InputDecoration(hintText: 'شاركنا تجربتك (اختياري)')),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('نشر التقييم')),
          ]),
        ),
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).reviewBiz(b.id, rating: rating, text: text.text.trim());
      invalidateBiz(ref, b.id);
      if (mounted) toast(context, 'شكراً لتقييمك');
    } catch (e) {
      if (mounted) toast(context, bizErrText(e), error: true);
    }
  }

  /// شراء منتج: كمية ثم تأكيد.
  Future<void> _buy(Biz b, BizItem it) async {
    var qty = 1;
    final max = it.stock == null ? 20 : it.stock!.clamp(0, 20);
    if (max == 0) return;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(it.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            if (it.description.isNotEmpty) Text(it.description, style: const TextStyle(color: Joy.textMuted)),
            const SizedBox(height: 12),
            Row(children: [
              const Text('الكمية', style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              _Stepper(value: qty, min: 1, max: max, onChanged: (v) => setS(() => qty = v)),
            ]),
            const SizedBox(height: 8),
            _TotalRow(total: it.price * qty),
            const SizedBox(height: 14),
            FilledButton.icon(onPressed: () => Navigator.pop(ctx, true), icon: const Icon(Icons.shopping_bag_outlined), label: Text('ادفع ${money(it.price * qty)} من المحفظة')),
          ]),
        ),
      ),
    );
    if (ok != true) return;
    await _order(b, it, qty: qty);
  }

  /// حجز غرفة أو سيارة: مدة من التقويم ثم التفاصيل.
  Future<void> _book(Biz b, BizItem it) async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 180)),
      initialDateRange: DateTimeRange(start: now.add(const Duration(days: 1)), end: now.add(Duration(days: it.kind == 'room' ? 3 : 4))),
      helpText: it.kind == 'room' ? 'تاريخا الوصول والمغادرة' : 'تاريخا الاستلام والإرجاع',
      saveText: 'متابعة',
    );
    if (range == null || !mounted) return;
    var units = range.duration.inDays;
    if (units < 1) units = 1;
    final start = DateTime(range.start.year, range.start.month, range.start.day), end = start.add(Duration(days: units));
    var qty = 1, guests = 2;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final total = it.price * units * qty;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(it.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
              Text(it.description, style: const TextStyle(color: Joy.textMuted)),
              const SizedBox(height: 10),
              _kv(it.kind == 'room' ? 'الوصول' : 'الاستلام', '${dayLabel(start)} · ${shortDate(start)}'),
              _kv(it.kind == 'room' ? 'المغادرة' : 'الإرجاع', '${dayLabel(end)} · ${shortDate(end)}'),
              _kv('المدة', '$units ${it.kind == 'room' ? (units == 1 ? 'ليلة' : 'ليالٍ') : (units == 1 ? 'يوم' : 'أيام')}'),
              if (it.kind == 'room') ...[
                Row(children: [const Text('عدد الغرف', style: TextStyle(fontWeight: FontWeight.w600)), const Spacer(), _Stepper(value: qty, min: 1, max: (it.stock ?? 5).clamp(1, 5), onChanged: (v) => setS(() => qty = v))]),
                Row(children: [const Text('عدد النزلاء', style: TextStyle(fontWeight: FontWeight.w600)), const Spacer(), _Stepper(value: guests, min: 1, max: 10, onChanged: (v) => setS(() => guests = v))]),
              ] else if (it.meta['pickup'] != null || b.address.isNotEmpty)
                _kv('الاستلام من', b.address),
              const SizedBox(height: 6),
              _TotalRow(total: total, hint: '${money(it.price)} ${it.unitLabel} × $units${qty > 1 ? ' × $qty' : ''}'),
              const SizedBox(height: 14),
              FilledButton.icon(onPressed: () => Navigator.pop(ctx, true), icon: Icon(b.category.icon), label: Text('تأكيد الحجز ودفع ${money(total)}')),
            ]),
          );
        },
      ),
    );
    if (ok != true) return;
    await _order(b, it, qty: qty, startAt: start, endAt: end, guests: it.kind == 'room' ? guests : null);
  }

  Future<void> _order(Biz b, BizItem it, {required int qty, DateTime? startAt, DateTime? endAt, int? guests}) async {
    try {
      final o = await ref.read(apiClientProvider).orderBiz(b.id, itemId: it.id, qty: qty, startAt: startAt, endAt: endAt, guests: guests);
      invalidateBiz(ref, b.id);
      ref.invalidate(walletProvider);
      if (!mounted) return;
      showOrderSheet(context, o, biz: b);
    } catch (e) {
      if (!mounted) return;
      if (e.toString().contains('insufficient-funds')) {
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('الرصيد غير كافٍ'),
            content: const Text('رصيد محفظتك لا يغطي هذا المبلغ. اشحن المحفظة ثم أعد المحاولة.'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لاحقاً')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('المحفظة'))],
          ),
        );
        if (go == true && mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WalletPage()));
      } else {
        toast(context, bizErrText(e), error: true);
      }
    }
  }
}

Widget _kv(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(k, style: const TextStyle(color: Joy.textMuted)), const SizedBox(width: 12), Expanded(child: Text(v, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600)))]),
    );

/// ورقة تأكيد الطلب/الحجز برمزه (QR) وتفاصيله.
void showOrderSheet(BuildContext context, BizOrder o, {Biz? biz, VoidCallback? onCancelled}) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .92),
    builder: (ctx) => Consumer(
      builder: (ctx, ref, _) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(o.status == 'cancelled' ? Icons.cancel_outlined : Icons.check_circle_rounded, color: o.status == 'cancelled' ? Joy.textMuted : Joy.success, size: 40),
          const SizedBox(height: 6),
          Text(o.status == 'cancelled' ? 'حجز ملغى' : o.status == 'used' ? 'تم الاستخدام' : (o.kind == 'product' ? 'تم الشراء' : 'تم الحجز'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          Text('${o.bizName.isNotEmpty ? o.bizName : biz?.title ?? ''} · ${o.title}', style: const TextStyle(color: Joy.textMuted), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Joy.line)), child: QrImageView(data: o.code, size: 170)),
          const SizedBox(height: 8),
          SelectableText(o.code, style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 2, fontSize: 16)),
          const SizedBox(height: 10),
          _kv('التفاصيل', o.summary),
          if (o.startAt != null) _kv(o.kind == 'showtime' ? 'الموعد' : 'من', o.kind == 'showtime' ? '${dayLabel(o.startAt!)} · ${clockOf(o.startAt)}' : '${dayLabel(o.startAt!)} · ${shortDate(o.startAt!)}'),
          if (o.endAt != null && o.kind != 'showtime') _kv('إلى', '${dayLabel(o.endAt!)} · ${shortDate(o.endAt!)}'),
          if (o.meta['hall'] != null) _kv('الصالة', o.meta['hall'].toString()),
          _kv('المبلغ', money(o.total)),
          _kv('الحالة', o.statusLabel),
          const SizedBox(height: 12),
          Text(o.kind == 'product' ? 'أظهر الرمز عند الاستلام من الفرع' : 'أظهر الرمز عند الوصول', style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
          if (o.cancellable) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                final ok = await showDialog<bool>(context: ctx, builder: (d) => AlertDialog(title: const Text('إلغاء الحجز؟'), content: const Text('سيُعاد المبلغ كاملاً إلى محفظتك.'), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('تراجع')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('إلغاء الحجز'))]));
                if (ok != true) return;
                try {
                  await ref.read(apiClientProvider).cancelBizOrder(o.id);
                  ref.invalidate(myBizOrdersProvider);
                  ref.invalidate(bizDetailProvider(o.bizId));
                  ref.invalidate(walletProvider);
                  onCancelled?.call();
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    toast(ctx, 'أُلغي الحجز وأُعيد ${money(o.total)} إلى محفظتك');
                  }
                } catch (e) {
                  if (ctx.mounted) toast(ctx, bizErrText(e), error: true);
                }
              },
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('إلغاء واسترداد المبلغ'),
            ),
          ],
        ]),
      ),
    ),
  );
}

// ------------------------------------------------------------------ الترويسة

class _Header extends StatelessWidget {
  final Biz biz;
  final bool busy;
  final VoidCallback onFollow;
  const _Header({required this.biz, required this.busy, required this.onFollow});
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(color: Joy.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: Joy.line)),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Consumer(builder: (context, ref, _) {
            final base = ref.read(apiClientProvider).baseUrl;
            return Container(height: biz.coverUrl != null ? 140 : 64, decoration: BoxDecoration(color: biz.color, image: biz.coverUrl != null ? DecorationImage(image: NetworkImage(biz.coverUrl!.startsWith('http') ? biz.coverUrl! : '$base${biz.coverUrl}'), fit: BoxFit.cover) : null));
          }),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Transform.translate(offset: const Offset(0, -26), child: BizLogo(biz: biz, size: 72)),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: busy
                        ? const Align(alignment: AlignmentDirectional.centerEnd, child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))
                        : Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: biz.following
                                ? OutlinedButton.icon(onPressed: onFollow, icon: const Icon(Icons.check_rounded, size: 18, color: Joy.success), label: const Text('متابَع'))
                                : FilledButton.icon(onPressed: onFollow, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('متابعة')),
                          ),
                  ),
                ),
              ]),
              Transform.translate(
                offset: const Offset(0, -14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(biz.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20))),
                    if (biz.verified) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.verified_rounded, color: Joy.primary, size: 18)),
                  ]),
                  if (biz.nameAr.isNotEmpty && biz.name != biz.nameAr) Text(biz.name, style: const TextStyle(color: Joy.textMuted, fontSize: 13)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4), decoration: BoxDecoration(color: Joy.primarySoft, borderRadius: BorderRadius.circular(999)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(biz.category.icon, size: 14, color: Joy.primary), const SizedBox(width: 4), Text(biz.sector.isNotEmpty ? biz.sector : biz.category.label, style: const TextStyle(color: Joy.primary, fontSize: 12, fontWeight: FontWeight.w600))])),
                    Stars(rating: biz.rating, count: biz.ratingCount),
                    Text('${biz.followers} متابع', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
                  ]),
                ]),
              ),
            ]),
          ),
        ]),
      );
}

/// شعار الدائرة: أحرف الاسم على لون العلامة.
class BizLogo extends StatelessWidget {
  final Biz biz;
  final double size;
  const BizLogo({super.key, required this.biz, this.size = 48});
  @override
  Widget build(BuildContext context) {
    final letters = biz.name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase()).take(2).join();
    if (biz.logoUrl != null) {
      return Consumer(builder: (context, ref, _) {
        final base = ref.read(apiClientProvider).baseUrl;
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: biz.color, borderRadius: BorderRadius.circular(size * .28), border: Border.all(color: Joy.surface, width: 3), boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 6, offset: Offset(0, 2))]),
          clipBehavior: Clip.antiAlias,
          child: Image.network(biz.logoUrl!.startsWith('http') ? biz.logoUrl! : '$base${biz.logoUrl}', fit: BoxFit.cover, errorBuilder: (_, __, ___) => Center(child: Text(letters, style: TextStyle(color: biz.onColor, fontWeight: FontWeight.w800, fontSize: size * .36, fontFamily: 'Rubik')))),
        );
      });
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: biz.color, borderRadius: BorderRadius.circular(size * .28), border: Border.all(color: Joy.surface, width: 3), boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 6, offset: Offset(0, 2))]),
      child: Text(letters, style: TextStyle(color: biz.onColor, fontWeight: FontWeight.w800, fontSize: size * .36, fontFamily: 'Rubik')),
    );
  }
}

class Stars extends StatelessWidget {
  final double? rating;
  final int count;
  const Stars({super.key, required this.rating, this.count = 0});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.star_rounded, size: 16, color: Joy.warning),
        const SizedBox(width: 2),
        Text(rating == null ? 'بلا تقييم' : '${rating!.toStringAsFixed(1)} ($count)', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
      ]);
}

class _InfoCard extends StatelessWidget {
  final Biz biz;
  final VoidCallback onMap;
  const _InfoCard({required this.biz, required this.onMap});
  @override
  Widget build(BuildContext context) => JoyCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (biz.description.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(biz.description, style: const TextStyle(height: 1.6))),
          if (biz.address.isNotEmpty) _row(Icons.place_outlined, biz.address, trailing: TextButton(onPressed: onMap, child: const Text('على الخريطة'))),
          if (biz.hours.isNotEmpty) _row(Icons.schedule_outlined, biz.hours),
          if (biz.phone != null && biz.phone!.isNotEmpty) _row(Icons.call_outlined, biz.phone!, onTap: () => launchUrl(Uri(scheme: 'tel', path: biz.phone))),
          if (biz.website != null && biz.website!.isNotEmpty) _row(Icons.language_rounded, biz.website!.replaceFirst(RegExp(r'^https?://(www\.)?'), ''), onTap: () => launchUrl(Uri.parse(biz.website!), mode: LaunchMode.externalApplication)),
        ]),
      );

  Widget _row(IconData icon, String text, {Widget? trailing, VoidCallback? onTap}) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Icon(icon, size: 18, color: Joy.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: TextStyle(color: onTap != null ? Joy.primary : Joy.text, fontSize: 13.5))),
            if (trailing != null) trailing,
          ]),
        ),
      );
}

// ------------------------------------------------------------------ الكتالوج

class _Price extends StatelessWidget {
  final BizItem item;
  const _Price(this.item);
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        Text(money(item.price), style: const TextStyle(fontWeight: FontWeight.w800, color: Joy.primary, fontSize: 16)),
        if (item.unitLabel.isNotEmpty) Padding(padding: const EdgeInsets.only(right: 4), child: Text(item.unitLabel, style: const TextStyle(color: Joy.textMuted, fontSize: 12))),
        if (item.isOffer) Padding(padding: const EdgeInsets.only(right: 6), child: Text(money(item.oldPrice!), style: const TextStyle(color: Joy.textMuted, fontSize: 12, decoration: TextDecoration.lineThrough))),
      ]);
}

class _ProductCard extends StatelessWidget {
  final Biz biz;
  final BizItem item;
  final VoidCallback onBuy;
  const _ProductCard({required this.biz, required this.item, required this.onBuy});
  @override
  Widget build(BuildContext context) => JoyCard(
        child: Row(children: [
          Container(width: 54, height: 54, decoration: BoxDecoration(color: biz.color.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)), child: Icon(Icons.shopping_bag_outlined, color: biz.color.computeLuminance() > .6 ? Joy.text : biz.color)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
                if (item.isOffer) Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: Joy.accentSoft, borderRadius: BorderRadius.circular(999)), child: const Text('عرض', style: TextStyle(color: Joy.accent, fontSize: 10.5, fontWeight: FontWeight.w700))),
              ]),
              if (item.description.isNotEmpty) Text(item.description, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              _Price(item),
            ]),
          ),
          const SizedBox(width: 8),
          item.soldOut
              ? const Text('نفد', style: TextStyle(color: Joy.textMuted, fontWeight: FontWeight.w600))
              : FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(44, 40), padding: const EdgeInsets.symmetric(horizontal: 14)), onPressed: onBuy, child: Text(biz.category.actionLabel)),
        ]),
      );
}

class _BookableCard extends StatelessWidget {
  final Biz biz;
  final BizItem item;
  final VoidCallback onBook;
  const _BookableCard({required this.biz, required this.item, required this.onBook});
  @override
  Widget build(BuildContext context) {
    final m = item.meta;
    final facts = item.kind == 'room'
        ? [if (m['beds'] != null) (Icons.bed_outlined, m['beds'].toString()), if (m['guests'] != null) (Icons.people_outline_rounded, '${m['guests']} أشخاص'), if (m['view'] != null) (Icons.landscape_outlined, 'إطلالة ${m['view']}'), if (m['breakfast'] == true) (Icons.free_breakfast_outlined, 'إفطار')]
        : [if (m['cls'] != null) (Icons.directions_car_outlined, m['cls'].toString()), if (m['seats'] != null) (Icons.airline_seat_recline_normal_outlined, '${m['seats']} مقاعد'), if (m['transmission'] != null) (Icons.settings_outlined, m['transmission'].toString()), if (m['fuel'] != null) (Icons.local_gas_station_outlined, m['fuel'].toString())];
    return JoyCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 54, height: 54, decoration: BoxDecoration(color: biz.color.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)), child: Icon(item.kind == 'room' ? Icons.king_bed_outlined : Icons.directions_car_filled_outlined, color: biz.color.computeLuminance() > .6 ? Joy.text : biz.color)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 2),
            _Price(item),
          ])),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(44, 40), padding: const EdgeInsets.symmetric(horizontal: 14)), onPressed: onBook, child: Text(biz.category.actionLabel)),
        ]),
        if (facts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(spacing: 12, runSpacing: 6, children: [for (final (icon, text) in facts) Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 15, color: Joy.textMuted), const SizedBox(width: 4), Text(text, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5))])]),
          ),
        if (item.stock != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(item.kind == 'room' ? '${item.stock} غرف من هذا النوع' : '${item.stock} سيارات متاحة', style: const TextStyle(color: Joy.textMuted, fontSize: 11.5))),
      ]),
    );
  }
}

/// فيلم بمواعيد عرضه للأيام القادمة؛ اختيار الموعد وعدد التذاكر ثم الدفع.
class _ShowtimeCard extends StatefulWidget {
  final Biz biz;
  final BizItem item;
  final Future<void> Function(Biz, BizItem, {required int qty, DateTime? startAt, DateTime? endAt, int? guests}) onOrder;
  const _ShowtimeCard({required this.biz, required this.item, required this.onOrder});
  @override
  State<_ShowtimeCard> createState() => _ShowtimeCardState();
}

class _ShowtimeCardState extends State<_ShowtimeCard> {
  DateTime? picked;
  int qty = 2;
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final byDay = <String, List<Showtime>>{};
    for (final s in it.slots) {
      byDay.putIfAbsent(dayLabel(s.startsAt), () => []).add(s);
    }
    final sel = picked == null ? null : it.slots.where((s) => s.startsAt == picked).firstOrNull;
    return JoyCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 54, height: 72, decoration: BoxDecoration(color: widget.biz.color.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.movie_outlined, color: widget.biz.color.computeLuminance() > .6 ? Joy.text : widget.biz.color)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(it.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
            Text(it.description, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
            if (it.meta['hall'] != null) Text('الصالة: ${it.meta['hall']}', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
            const SizedBox(height: 2),
            _Price(it),
          ])),
        ]),
        if (it.slots.isEmpty)
          const Padding(padding: EdgeInsets.only(top: 8), child: Text('لا مواعيد متاحة حالياً', style: TextStyle(color: Joy.textMuted)))
        else
          for (final e in byDay.entries) ...[
            Padding(padding: const EdgeInsets.only(top: 10, bottom: 4), child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final s in e.value)
                ChoiceChip(
                  label: Text('${clockOf(s.startsAt)}${s.seatsLeft < 15 ? ' · ${s.seatsLeft}' : ''}'),
                  selected: picked == s.startsAt,
                  onSelected: s.seatsLeft == 0 ? null : (_) => setState(() => picked = s.startsAt),
                  showCheckmark: false,
                  selectedColor: Joy.primary,
                  labelStyle: TextStyle(color: picked == s.startsAt ? Joy.primaryOn : Joy.text, fontSize: 12.5),
                ),
            ]),
          ],
        if (sel != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(children: [
              const Text('التذاكر', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              _Stepper(value: qty, min: 1, max: sel.seatsLeft.clamp(1, 10), onChanged: (v) => setState(() => qty = v)),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(44, 40)),
                onPressed: busy
                    ? null
                    : () async {
                        setState(() => busy = true);
                        try {
                          await widget.onOrder(widget.biz, it, qty: qty, startAt: picked);
                        } finally {
                          if (mounted) setState(() => busy = false);
                        }
                      },
                child: Text('ادفع ${money(it.price * qty)}'),
              ),
            ]),
          ),
      ]),
    );
  }
}

class _Stepper extends StatelessWidget {
  final int value, min, max;
  final ValueChanged<int> onChanged;
  const _Stepper({required this.value, required this.min, required this.max, required this.onChanged});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(visualDensity: VisualDensity.compact, onPressed: value > min ? () => onChanged(value - 1) : null, icon: const Icon(Icons.remove_circle_outline_rounded)),
        Text('$value', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        IconButton(visualDensity: VisualDensity.compact, onPressed: value < max ? () => onChanged(value + 1) : null, icon: const Icon(Icons.add_circle_outline_rounded)),
      ]);
}

class _TotalRow extends StatelessWidget {
  final int total;
  final String? hint;
  const _TotalRow({required this.total, this.hint});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          const Text('الإجمالي', style: TextStyle(fontWeight: FontWeight.w600)),
          if (hint != null) Padding(padding: const EdgeInsets.only(right: 8), child: Text(hint!, style: const TextStyle(color: Joy.textMuted, fontSize: 11.5))),
          const Spacer(),
          Text(money(total), style: const TextStyle(fontWeight: FontWeight.w800, color: Joy.primary, fontSize: 17)),
        ]),
      );
}

// ------------------------------------------------------------------ الطلبات والتقييمات

/// صف طلب/حجز مختصر؛ الضغط يفتح ورقة الرمز والتفاصيل.
class OrderRow extends StatelessWidget {
  final BizOrder o;
  final bool last;
  final bool showBiz;
  final VoidCallback? onChanged;
  const OrderRow(this.o, {super.key, this.last = false, this.showBiz = false, this.onChanged});
  @override
  Widget build(BuildContext context) {
    final active = o.status == 'confirmed';
    final icon = switch (o.kind) { 'showtime' => Icons.local_movies_outlined, 'room' => Icons.hotel_outlined, 'car' => Icons.directions_car_outlined, _ => Icons.shopping_bag_outlined };
    return ListRow(
      leading: Container(width: 46, height: 46, decoration: BoxDecoration(color: active ? Joy.primarySoft : Joy.surface2, borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: active ? Joy.primary : Joy.textMuted)),
      title: Text(showBiz ? '${o.bizName} · ${o.title}' : o.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${o.summary}${o.startAt != null ? ' · ${dayLabel(o.startAt!)}${o.kind == 'showtime' ? ' ${clockOf(o.startAt)}' : ''}' : ''} · ${o.statusLabel}', maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(money(o.total), style: TextStyle(fontWeight: FontWeight.w700, color: active ? Joy.text : Joy.textMuted, fontSize: 13.5)),
        const Icon(Icons.qr_code_2_rounded, size: 18, color: Joy.textMuted),
      ]),
      onTap: () => showOrderSheet(context, o, onCancelled: onChanged),
      divider: !last,
    );
  }
}

class _Reviews extends StatelessWidget {
  final Biz biz;
  const _Reviews({required this.biz});
  @override
  Widget build(BuildContext context) {
    if (biz.reviews.isEmpty) return const EmptyState(icon: Icons.star_outline_rounded, title: 'لا تقييمات بعد', subtitle: 'كن أول من يقيّم هذه الدائرة.');
    return JoyCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        for (final (i, r) in biz.reviews.indexed)
          ListRow(
            leading: ProfileAvatar(person: r.user, size: 42),
            title: Row(children: [Expanded(child: Text(r.user.nickname.isEmpty ? 'مستخدم' : r.user.nickname)), Row(children: [for (var s = 1; s <= 5; s++) Icon(s <= r.rating ? Icons.star_rounded : Icons.star_outline_rounded, size: 14, color: Joy.warning)])]),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.text.isEmpty ? timeAgo(r.createdAt) : '${r.text} · ${timeAgo(r.createdAt)}', maxLines: 3),
              if (r.reply != null)
                Container(margin: const EdgeInsets.only(top: 6), padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Joy.primarySoft, borderRadius: BorderRadius.circular(10)), child: Text('رد ${biz.title}: ${r.reply}', style: const TextStyle(color: Joy.text, fontSize: 12.5))),
            ]),
            divider: i < biz.reviews.length - 1,
          ),
      ]),
    );
  }
}
