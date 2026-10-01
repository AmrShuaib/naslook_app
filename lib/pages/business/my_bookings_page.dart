import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/hotel_api.dart';
import '../../core/app_theme.dart';
import '../../state/biz_providers.dart';
import '../../state/hotel_providers.dart';
import '../../ui/widgets.dart';
import 'business_page.dart';

/// كل طلبات وحجوزات المستخدم لدى الدوائر التجارية، وفوقها حجوزاته الفندقية عبر Amadeus إن وُجدت.
class MyBookingsPage extends ConsumerWidget {
  const MyBookingsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(myBizOrdersProvider);
    // الحجوزات الفندقية لا تعطّل الصفحة إن تعذّر جلبها (قائمة فارغة)
    final hotels = ref.watch(myHotelBookingsProvider).valueOrNull ?? const <HotelBooking>[];
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: const Text('حجوزاتي وطلباتي')),
      body: orders.when(
        data: (list) {
          if (list.isEmpty && hotels.isEmpty) return const EmptyState(icon: Icons.receipt_long_outlined, title: 'لا حجوزات بعد', subtitle: 'احجز فندقاً أو سيارة أو تذاكر سينما أو اشترِ من براند، وستظهر هنا برموزها.');
          final up = list.where((o) => o.upcoming).toList(), past = list.where((o) => !o.upcoming).toList();
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(myBizOrdersProvider);
              ref.invalidate(myHotelBookingsProvider);
            },
            child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
              if (hotels.isNotEmpty) ...[
                const SectionTitle('حجوزات الفنادق'),
                JoyCard(key: const Key('hotel-bookings'), padding: EdgeInsets.zero, child: Column(children: [for (final (i, b) in hotels.indexed) _HotelRow(b, last: i == hotels.length - 1)])),
                const SizedBox(height: 8),
              ],
              if (up.isNotEmpty) ...[
                const SectionTitle('السارية'),
                JoyCard(padding: EdgeInsets.zero, child: Column(children: [for (final (i, o) in up.indexed) OrderRow(o, showBiz: true, last: i == up.length - 1, onChanged: () => ref.invalidate(myBizOrdersProvider))])),
              ],
              if (past.isNotEmpty) ...[
                const SectionTitle('السابقة'),
                Opacity(opacity: .7, child: JoyCard(padding: EdgeInsets.zero, child: Column(children: [for (final (i, o) in past.indexed) OrderRow(o, showBiz: true, last: i == past.length - 1)]))),
              ],
            ]),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(myBizOrdersProvider)),
      ),
    );
  }
}

/// صف حجز فندقي: الفندق، الوصول ← المغادرة، الغرفة ورقم التأكيد، وشارة الحالة والإجمالي؛ لمسه يعرض التفاصيل.
class _HotelRow extends StatelessWidget {
  final HotelBooking b;
  final bool last;
  const _HotelRow(this.b, {this.last = false});

  static String _d(String ymd) {
    final t = parseHotelDate(ymd);
    return t == null ? ymd : shortDate(t);
  }

  @override
  Widget build(BuildContext context) {
    final active = b.status == 'confirmed' && b.upcoming;
    final color = switch (b.status) { 'confirmed' => Joy.success, 'pending' => Joy.sunText, _ => Joy.textMuted };
    return ListRow(
      key: Key('hotel-booking-${b.id}'),
      leading: Container(width: 46, height: 46, decoration: BoxDecoration(color: active ? Joy.primarySoft : Joy.surface2, borderRadius: BorderRadius.circular(14)), child: Icon(Icons.hotel_outlined, color: active ? Joy.primary : Joy.textMuted)),
      title: Text(b.hotelName.isNotEmpty ? b.hotelName : b.bizName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${_d(b.checkIn)} ← ${_d(b.checkOut)}${b.roomName.isNotEmpty ? ' · ${b.roomName}' : ''}${b.confirmation.isNotEmpty ? ' · ${b.confirmation}' : ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(b.priceText, style: TextStyle(fontWeight: FontWeight.w700, color: active ? Joy.text : Joy.textMuted, fontSize: 13.5)),
        const SizedBox(height: 3),
        Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(999)), child: Text(b.statusLabel, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w700))),
      ]),
      onTap: () => _showDetails(context),
      divider: !last,
    );
  }

  void _showDetails(BuildContext context) {
    Widget kv(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(k, style: const TextStyle(color: Joy.textMuted, fontSize: 13.5)), const SizedBox(width: 12), Expanded(child: Text(v, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600)))]),
        );
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(b.hotelName.isNotEmpty ? b.hotelName : b.bizName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 4),
          Text(b.statusLabel, style: const TextStyle(color: Joy.textMuted)),
          const SizedBox(height: 12),
          if (b.confirmation.isNotEmpty) ...[
            const Text('رقم التأكيد', style: TextStyle(color: Joy.textMuted, fontSize: 12.5)),
            SelectableText(b.confirmation, textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22, letterSpacing: 1.5)),
            const SizedBox(height: 10),
          ],
          kv('الوصول', _d(b.checkIn)),
          kv('المغادرة', _d(b.checkOut)),
          if (b.roomName.isNotEmpty) kv('الغرفة', b.roomName),
          kv('الضيف', b.guestName),
          kv('الإجمالي', b.priceText),
          if (b.cancelText.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(b.cancelText, textAlign: TextAlign.center, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5, height: 1.5))),
          const Padding(padding: EdgeInsets.only(top: 6), child: Text('أظهر رقم التأكيد عند الوصول؛ الدفع في الفندق بحسب سياسته.', textAlign: TextAlign.center, style: TextStyle(color: Joy.textMuted, fontSize: 12))),
        ]),
      ),
    );
  }
}
