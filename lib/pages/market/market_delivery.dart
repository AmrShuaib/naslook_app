// التوصيل في السوق (بند 13 من نواقص الإطلاق): اختيار «استلام» أو «توصيل» عند الطلب برسمه وعنوان من «عناويني»، وبطاقة التوصيل في
// صفحة الطلب بحسب الطرف: المشتري يرى عنوانه دائماً، والبائع بعد قبول الطلب وما دام قائماً، والمندوب ما دام مكلّفاً (القواعد في commerce.js).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/address_models.dart';
import '../../api/commerce_models.dart';
import '../../core/app_theme.dart';
import '../../core/directions.dart';
import '../../state/app_state.dart';
import '../../ui/widgets.dart';
import '../addresses/addresses_page.dart';

String _km(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// نص رسم التوصيل: «مجاني» أو المبلغ
String deliveryFeeText(int fee) => fee > 0 ? money(fee) : 'مجاني';

/// السعر على بطاقات السوق ورأس العرض، ورسم التوصيل بجانبه («+ توصيل 15 ر.س») حين للتوصيل رسم: يعرفه المشتري قبل زر الطلب.
/// العرض بلا مكان استلام (التوصيل افتراضي) وله رسم لا يُسمّى «مجاناً» وإن كان سعره صفراً: يظهر «توصيل 15 ر.س» بدل السعر.
/// [price] سعر الخيار المختار في صفحة العرض بدل سعر العرض.
({String price, String? fee}) listingPriceParts(Listing l, {int? price}) {
  final p = price ?? l.price;
  final fee = l.delivery ? l.deliveryFee : 0;
  final base = p == 0 ? 'مجاناً' : money(p);
  if (fee <= 0) return (price: base, fee: null);
  if (p == 0 && (l.placeName ?? '').trim().isEmpty) return (price: 'توصيل ${money(fee)}', fee: null);
  return (price: base, fee: '+ توصيل ${money(fee)}');
}

/// السعر ورسم التوصيل في سطر واحد (قوائم البائع والمقارنة)
String listingPriceText(Listing l) {
  final x = listingPriceParts(l);
  return x.fee == null ? x.price : '${x.price} ${x.fee}';
}

/// «استلام» أو «توصيل» في صفحة العرض. حين يُختار التوصيل ولا عنوان بعد، يُملأ الافتراضي من «عناويني» تلقائياً مرة واحدة.
class DeliveryChoice extends ConsumerStatefulWidget {
  final Listing listing;
  final bool delivery;
  final SavedAddress? address;
  final ValueChanged<bool> onMode;
  final ValueChanged<SavedAddress> onAddress;
  /// يُستدعى لاختيار العنوان (الزائر يُدعى للدخول أولاً)
  final VoidCallback onPick;
  const DeliveryChoice({super.key, required this.listing, required this.delivery, required this.address, required this.onMode, required this.onAddress, required this.onPick});
  @override
  ConsumerState<DeliveryChoice> createState() => _DeliveryChoiceState();
}

class _DeliveryChoiceState extends ConsumerState<DeliveryChoice> {
  bool _autoPicked = false;

  @override
  Widget build(BuildContext context) {
    final x = widget.listing;
    final signedIn = ref.watch(appStateProvider.select((s) => s.user != null));
    if (widget.delivery && widget.address == null && signedIn && !_autoPicked) {
      final pref = ref.watch(addressBookProvider).valueOrNull?.preferred;
      if (pref != null) {
        _autoPicked = true;
        WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted && widget.address == null) widget.onAddress(pref); });
      }
    }
    final a = widget.address;
    return Column(key: const Key('delivery-choice'), crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('طريقة الاستلام', style: TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 8, children: [
        ChoiceChip(key: const Key('ful-pickup'), avatar: const Icon(Icons.storefront_outlined, size: 18), label: Text((x.placeName ?? '').trim().isEmpty ? 'استلام' : 'استلام · ${x.placeName}'), selected: !widget.delivery, showCheckmark: false, selectedColor: Joy.primarySoft, onSelected: (_) => widget.onMode(false)),
        ChoiceChip(key: const Key('ful-delivery'), avatar: const Icon(Icons.local_shipping_outlined, size: 18), label: Text('توصيل · ${deliveryFeeText(x.deliveryFee)}'), selected: widget.delivery, showCheckmark: false, selectedColor: Joy.primarySoft, onSelected: (_) => widget.onMode(true)),
      ]),
      if (widget.delivery) ...[
        const SizedBox(height: 8),
        if (a != null)
          KeyedSubtree(key: const Key('delivery-address'), child: AddressTile(a, onTap: widget.onPick, trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            // تعديل العنوان المختار هنا (ومنه تحديد نقطته على الخريطة) بدل الخروج من العرض إلى «عناويني»
            IconButton(key: const Key('delivery-address-edit'), tooltip: 'تعديل العنوان', visualDensity: VisualDensity.compact, icon: const Icon(Icons.edit_outlined, size: 18, color: Joy.primary), onPressed: () => _edit(a)),
            const Padding(padding: EdgeInsetsDirectional.only(end: 8), child: Text('تغيير', style: TextStyle(color: Joy.primary, fontWeight: FontWeight.w700, fontSize: 12.5))),
          ])))
        else
          OutlinedButton.icon(key: const Key('delivery-pick'), onPressed: widget.onPick, icon: const Icon(Icons.add_location_alt_outlined, size: 18), label: const Text('اختر عنوان التوصيل')),
        if (x.deliveryMaxKm != null)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(
            a != null && !a.hasPoint ? 'يوصّل حتى ${_km(x.deliveryMaxKm!)} كم. عدّل العنوان وحدّد موقعه على الخريطة ليتأكد البائع من المسافة.' : 'يوصّل حتى ${_km(x.deliveryMaxKm!)} كم من موقعه.',
            key: const Key('delivery-range'), style: const TextStyle(color: Joy.textMuted, fontSize: 12))),
      ],
    ]);
  }

  Future<void> _edit(SavedAddress a) async {
    final u = await openAddressForm(context, ref, initial: a);
    if (u != null && mounted) widget.onAddress(u);
  }
}

/// شارة «توصيل» على بطاقة الطلب.
class OrderDeliveryChip extends StatelessWidget {
  final Order o;
  const OrderDeliveryChip(this.o, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        key: Key('order-ful-${o.id}'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: Joy.primarySoft, borderRadius: BorderRadius.circular(999)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.local_shipping_outlined, size: 14, color: Joy.primary), SizedBox(width: 4),
          Flexible(child: Text('توصيل', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Joy.primary))),
        ]),
      );
}

/// سبب غياب العنوان عن الطرف الذي يفتح الطلب (قواعد الرؤية في commerce.js)؛ [isBuyer] لأن المدير يفتح الطلب من إشعار النزاع
/// والخادم لا يميّزه بعلامة، فمن ليس بائعاً ولا مندوباً ولا مشترياً هو الإدارة.
String orderAddressHiddenWhy(Order x, {required bool isBuyer}) {
  if (x.addressPurged) return 'حُذف العنوان من الطلب بعد ٣٠ يوماً من انتهائه، حفاظاً على الخصوصية.';
  if (x.mineAsSeller && x.awaitingSeller) return 'يظهر لك عنوان المشتري بعد قبول الطلب.';
  // اعتذار أو انتهاء مهلة قبل القبول: لم يرَ البائع العنوان أصلاً ولم يُوصَّل شيء
  if (x.mineAsSeller && x.cod && x.acceptedAt == null) return 'لم يُقبل الطلب فلم يظهر لك العنوان.';
  if (!x.mineAsSeller && !x.mineAsCourier && !isBuyer) return 'يظهر العنوان للإدارة عند النزاع فقط.';
  if (x.done || (x.mineAsCourier && x.status == 'delivered')) return 'لم يعد العنوان ظاهراً لك بعد انتهاء التوصيل.';
  if (x.status == 'cancelled' || x.status == 'refunded') return 'أُغلق الطلب فلم يعد العنوان ظاهراً لك.';
  return 'العنوان غير ظاهر لك الآن.';
}

/// بطاقة التوصيل في صفحة الطلب: الرسم والمسافة، والعنوان لمن يحق له رؤيته الآن، وإلا سبب غيابه.
class OrderDeliveryCard extends ConsumerWidget {
  final Order x;
  const OrderDeliveryCard(this.x, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = x.address;
    final me = ref.watch(appStateProvider.select((s) => s.user?.id));
    final hiddenWhy = a != null ? null : orderAddressHiddenWhy(x, isBuyer: me != null && x.buyer.id == me);
    return JoyCard(key: const Key('order-delivery'), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.local_shipping_outlined, color: Joy.primary), const SizedBox(width: 8),
        const Expanded(child: Text('التوصيل', style: TextStyle(fontWeight: FontWeight.w800))),
        Text('${deliveryFeeText(x.deliveryFee)}${x.deliveryKm != null ? ' · ${_km(x.deliveryKm!)} كم' : ''}', key: const Key('order-delivery-fee'), style: const TextStyle(color: Joy.textMuted, fontSize: 12.5, fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 8),
      if (a != null) ...[
        Text(a.label, key: const Key('order-address'), style: const TextStyle(fontWeight: FontWeight.w700)),
        Text(a.line, style: const TextStyle(fontSize: 13, height: 1.5)),
        if (a.hasPoint || a.localPhone != null) Padding(padding: const EdgeInsets.only(top: 6), child: Wrap(spacing: 8, runSpacing: 6, children: [
          if (a.localPhone != null) OutlinedButton.icon(key: const Key('order-address-call'), onPressed: () => openExternalUrl(Uri.parse('tel:${a.phone}')), icon: const Icon(Icons.call_outlined, size: 16), label: Text(a.localPhone!, textDirection: TextDirection.ltr)),
          if (a.hasPoint) OutlinedButton.icon(key: const Key('order-address-directions'), onPressed: () => openDirections(a.lat!, a.lng!), icon: const Icon(Icons.directions_outlined, size: 16), label: const Text('الاتجاهات')),
        ])),
        if (!x.mineAsBuyer) const Padding(padding: EdgeInsets.only(top: 6), child: Text('للتوصيل فقط: لا تشاركه ولا تحفظه خارج الطلب.', style: TextStyle(color: Joy.textMuted, fontSize: 11.5))),
      ] else
        Text(hiddenWhy!, key: const Key('order-address-hidden'), style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
    ]));
  }
}
