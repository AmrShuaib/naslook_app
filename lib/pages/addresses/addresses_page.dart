// «عناويني»: دفتر عناوين التوصيل الخاص بالمستخدم (server/addresses.js). حتى عشرة عناوين، أحدها افتراضي، ولكل عنوان تسمية وحي
// وتفاصيل ومدينة، ونقطة اختيارية على الخريطة (منتقي الخريطة المشترك) وجوال اختياري. يُفتح من ماي سبيس ومن صفحة الطلب في السوق،
// ولا يراه أحد غير صاحبه: البائع يرى نسخة العنوان الذي اخترته على طلبه فقط (docs/addresses.md).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../api/address_models.dart';
import '../../api/addresses_api.dart';
import '../../api/client.dart';
import '../../core/app_theme.dart';
import '../../state/app_state.dart';
import '../../ui/map_pick_page.dart';
import '../../ui/widgets.dart';

final addressBookProvider = FutureProvider<AddressBook>((ref) => ref.watch(apiClientProvider).addresses());

/// نص خطأ الدفتر بالعربية
String addressErrText(Object e) {
  final code = e is ApiException ? (e.body?['error']?.toString() ?? '') : e.toString();
  return switch (code) {
    'address-limit' => 'وصلت إلى ١٠ عناوين. احذف عنواناً لا تحتاجه أولاً',
    'bad-label' => 'اختر تسمية للعنوان',
    'bad-district' => 'اكتب اسم الحي',
    'bad-details' => 'التفاصيل طويلة، اختصرها',
    'bad-phone' => 'رقم الجوال غير صحيح. اكتبه هكذا: 05xxxxxxxx',
    'bad-point' => 'حدّد النقطة على الخريطة من جديد',
    'banned-words' => 'يحتوي كلمات غير مسموح بها',
    _ => e is ApiException ? e.message : 'تعذّر الحفظ',
  };
}

/// جوال سعودي (05… أو 5… أو +9665…) أو فارغ
bool addressPhoneOk(String s) {
  final t = s.replaceAll(RegExp(r'[\s\-().]'), '');
  return t.isEmpty || RegExp(r'^(?:\+966|00966|966)?0?5\d{8}$').hasMatch(t);
}

class AddressesPage extends ConsumerWidget {
  const AddressesPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(addressBookProvider);
    final full = book.valueOrNull?.full ?? false;
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: const Text('عناويني')),
      floatingActionButton: book.hasValue && !full
          ? FloatingActionButton.extended(key: const Key('addresses-add'), onPressed: () => openAddressForm(context, ref), icon: const Icon(Icons.add_location_alt_outlined), label: const Text('عنوان جديد'))
          : null,
      body: book.when(
        data: (b) => b.items.isEmpty
            ? EmptyState(
                icon: Icons.home_work_outlined, title: 'لا عناوين محفوظة',
                subtitle: 'احفظ عنوان البيت أو العمل مرة واحدة واختره عند طلب التوصيل من السوق. لا يراه إلا أنت، ويصل البائع عنوان طلبه فقط.',
                action: FilledButton.icon(key: const Key('addresses-add-first'), onPressed: () => openAddressForm(context, ref), icon: const Icon(Icons.add_location_alt_outlined), label: const Text('أضف عنواناً')),
              )
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(addressBookProvider),
                child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 96), children: [
                  for (final a in b.items) Padding(padding: const EdgeInsets.only(bottom: 10), child: AddressTile(a, trailing: _menu(context, ref, a))),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(full ? 'وصلت إلى ${b.max} عناوين، وهو الحد. احذف عنواناً لتضيف غيره.' : '${b.items.length} من ${b.max} عناوين · لا يراها إلا أنت، والبائع يرى عنوان طلبه بعد تأكيده فقط',
                        key: const Key('addresses-count'), style: TextStyle(color: full ? Joy.warning : Joy.textMuted, fontSize: 12)),
                  ),
                ]),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(addressBookProvider)),
      ),
    );
  }

  Widget _menu(BuildContext context, WidgetRef ref, SavedAddress a) => PopupMenuButton<String>(
        key: Key('addr-menu-${a.id}'),
        tooltip: 'خيارات',
        onSelected: (v) async {
          final api = ref.read(apiClientProvider);
          try {
            if (v == 'edit') {
              await openAddressForm(context, ref, initial: a);
            } else if (v == 'default') {
              await api.setDefaultAddress(a.id);
              ref.invalidate(addressBookProvider);
            } else if (v == 'delete') {
              final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
                title: Text('حذف «${a.label}»؟'),
                content: const Text('لن يظهر في عناوينك بعد الآن. الطلبات التي أرسلتها إليه تبقى كما هي.'),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(key: const Key('addr-delete-go'), style: FilledButton.styleFrom(backgroundColor: Joy.danger), onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف'))],
              ));
              if (ok != true) return;
              await api.deleteAddress(a.id);
              ref.invalidate(addressBookProvider);
              if (context.mounted) toast(context, 'حُذف العنوان');
            }
          } catch (e) {
            if (context.mounted) toast(context, addressErrText(e), error: true);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(key: Key('addr-edit'), value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('تعديل'))),
          if (!a.isDefault) const PopupMenuItem(key: Key('addr-make-default'), value: 'default', child: ListTile(leading: Icon(Icons.star_outline_rounded), title: Text('اجعله الافتراضي'))),
          const PopupMenuItem(key: Key('addr-delete'), value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline_rounded, color: Joy.danger), title: Text('حذف', style: TextStyle(color: Joy.danger)))),
        ],
      );
}

/// بطاقة عنوان: التسمية والافتراضي، ثم الحي والمدينة والتفاصيل، والجوال والنقطة إن وُجدا.
class AddressTile extends StatelessWidget {
  final DeliveryAddress a;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;
  const AddressTile(this.a, {super.key, this.trailing, this.onTap, this.selected = false});
  @override
  Widget build(BuildContext context) {
    final s = a;
    final def = s is SavedAddress && s.isDefault;
    return JoyCard(
      key: s is SavedAddress ? Key('addr-${s.id}') : null,
      onTap: onTap,
      color: selected ? Joy.primarySoft : null,
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      child: Row(children: [
        Icon(a.label == 'العمل' ? Icons.work_outline_rounded : Icons.home_outlined, color: Joy.primary),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(child: Text(a.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
            if (def) Container(margin: const EdgeInsets.only(right: 6), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: Joy.primarySoft, borderRadius: BorderRadius.circular(999)), child: const Text('الافتراضي', style: TextStyle(color: Joy.primary, fontSize: 10.5, fontWeight: FontWeight.w700))),
          ]),
          Text(a.line, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
          if (a.localPhone != null || a.hasPoint)
            Text([if (a.localPhone != null) a.localPhone!, if (a.hasPoint) 'محدد على الخريطة'].join(' · '), textDirection: TextDirection.rtl, style: const TextStyle(color: Joy.textMuted, fontSize: 11.5)),
        ])),
        if (selected) const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.check_circle_rounded, color: Joy.primary)),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// يفتح نموذج العنوان (إضافة أو تعديل) ويعيد العنوان المحفوظ، أو null إن رجع المستخدم.
Future<SavedAddress?> openAddressForm(BuildContext context, WidgetRef ref, {SavedAddress? initial}) async {
  final saved = await Navigator.of(context).push<SavedAddress>(MaterialPageRoute(builder: (_) => AddressFormPage(initial: initial), fullscreenDialog: true));
  if (saved != null) ref.invalidate(addressBookProvider);
  return saved;
}

class AddressFormPage extends ConsumerStatefulWidget {
  final SavedAddress? initial;
  const AddressFormPage({super.key, this.initial});
  @override
  ConsumerState<AddressFormPage> createState() => _AddressFormPageState();
}

class _AddressFormPageState extends ConsumerState<AddressFormPage> {
  late String label = widget.initial?.label ?? addressLabelPresets.first;
  late final custom = TextEditingController(text: addressLabelPresets.contains(widget.initial?.label) || widget.initial == null ? '' : widget.initial!.label);
  late final district = TextEditingController(text: widget.initial?.district ?? '');
  late final details = TextEditingController(text: widget.initial?.details ?? '');
  late final city = TextEditingController(text: widget.initial?.city ?? '');
  late final phone = TextEditingController(text: widget.initial?.localPhone ?? '');
  late LatLng? point = widget.initial?.hasPoint == true ? LatLng(widget.initial!.lat!, widget.initial!.lng!) : null;
  late bool makeDefault = widget.initial?.isDefault ?? false;
  late bool other = widget.initial != null && !addressLabelPresets.contains(widget.initial!.label);
  bool saving = false;

  @override
  void dispose() { for (final c in [custom, district, details, city, phone]) { c.dispose(); } super.dispose(); }

  String get _label => other ? custom.text.trim() : label;

  Future<void> _save() async {
    if (saving) return;
    if (_label.isEmpty) { toast(context, 'اكتب تسمية للعنوان', error: true); return; }
    if (district.text.trim().length < 2) { toast(context, 'اكتب اسم الحي', error: true); return; }
    if (!addressPhoneOk(phone.text)) { toast(context, 'رقم الجوال غير صحيح. اكتبه هكذا: 05xxxxxxxx', error: true); return; }
    final body = <String, dynamic>{
      'label': _label, 'district': district.text.trim(), 'details': details.text.trim(), 'city': city.text.trim(), 'phone': phone.text.trim(),
      'lat': point?.latitude, 'lng': point?.longitude, if (makeDefault) 'isDefault': true,
    };
    setState(() => saving = true);
    try {
      final api = ref.read(apiClientProvider);
      final a = widget.initial == null ? await api.addAddress(body) : await api.updateAddress(widget.initial!.id, body);
      if (mounted) Navigator.pop(context, a);
    } catch (e) {
      if (mounted) { setState(() => saving = false); toast(context, addressErrText(e), error: true); }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Joy.bg,
        appBar: AppBar(title: Text(widget.initial == null ? 'عنوان جديد' : 'تعديل العنوان')),
        body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
          const Text('التسمية', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in addressLabelPresets)
              ChoiceChip(key: Key('addr-label-$p'), label: Text(p), selected: !other && label == p, showCheckmark: false, selectedColor: Joy.primarySoft, onSelected: (_) => setState(() { other = false; label = p; })),
            ChoiceChip(key: const Key('addr-label-other'), label: const Text('أخرى'), selected: other, showCheckmark: false, selectedColor: Joy.primarySoft, onSelected: (_) => setState(() => other = true)),
          ]),
          if (other) Padding(padding: const EdgeInsets.only(top: 8), child: TextField(key: const Key('addr-label'), controller: custom, maxLength: 30, decoration: const InputDecoration(labelText: 'اسم العنوان', hintText: 'مثال: الاستراحة'))),
          const SizedBox(height: 12),
          TextField(key: const Key('addr-district'), controller: district, maxLength: 60, decoration: const InputDecoration(labelText: 'الحي', hintText: 'مثال: الروضة')),
          TextField(key: const Key('addr-details'), controller: details, maxLength: 200, maxLines: 2, decoration: const InputDecoration(labelText: 'الشارع والتفاصيل (اختياري)', hintText: 'الشارع، رقم المبنى، الدور، علامة مميزة')),
          TextField(key: const Key('addr-city'), controller: city, maxLength: 40, decoration: const InputDecoration(labelText: 'المدينة (اختياري)', hintText: 'جدة')),
          TextField(key: const Key('addr-phone'), controller: phone, keyboardType: TextInputType.phone, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'جوال للتوصيل (اختياري)', hintText: '05xxxxxxxx', helperText: 'يراه البائع والمندوب لطلبك فقط')),
          const SizedBox(height: 8),
          ListTile(
            key: const Key('addr-point'), contentPadding: EdgeInsets.zero,
            leading: Icon(point == null ? Icons.add_location_outlined : Icons.location_on_rounded, color: Joy.primary),
            title: Text(point == null ? 'حدّد الموقع على الخريطة (اختياري)' : 'الموقع محدد على الخريطة'),
            subtitle: Text(point == null ? 'يساعد المندوب ويتيح للبائع معرفة المسافة' : 'اضغط لتغييره', style: const TextStyle(fontSize: 12)),
            trailing: point == null ? null : IconButton(key: const Key('addr-point-clear'), tooltip: 'إزالة', icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => setState(() => point = null)),
            onTap: () async {
              final p = await MapPickPage.open(context, initial: point, title: 'موقع العنوان');
              if (p != null && mounted) setState(() => point = p);
            },
          ),
          SwitchListTile(key: const Key('addr-default'), contentPadding: EdgeInsets.zero, value: makeDefault, onChanged: widget.initial?.isDefault == true ? null : (v) => setState(() => makeDefault = v), title: const Text('العنوان الافتراضي'), subtitle: const Text('يُختار تلقائياً عند طلب التوصيل', style: TextStyle(fontSize: 12))),
          const SizedBox(height: 14),
          FilledButton(key: const Key('addr-save'), onPressed: saving ? null : _save, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)), child: Text(saving ? 'جارٍ الحفظ…' : 'حفظ العنوان')),
        ]),
      );
}

/// ورقة اختيار عنوان التوصيل عند الطلب: عناويني (الافتراضي أولاً) وزر «عنوان جديد» يضيف ويختار في خطوة واحدة.
Future<SavedAddress?> pickDeliveryAddress(BuildContext context, WidgetRef ref, {String? selectedId}) => showModalBottomSheet<SavedAddress>(
      context: context, isScrollControlled: true, showDragHandle: true, backgroundColor: Joy.bg,
      builder: (ctx) => _PickSheet(selectedId: selectedId),
    );

class _PickSheet extends ConsumerWidget {
  final String? selectedId;
  const _PickSheet({this.selectedId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(addressBookProvider);
    return SafeArea(child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .75),
      child: book.when(
        data: (b) => ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), children: [
          const Text('التوصيل إلى', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(height: 4),
          const Text('يرى البائع العنوان الذي تختاره لهذا الطلب فقط، بعد تأكيده.', style: TextStyle(color: Joy.textMuted, fontSize: 12)),
          const SizedBox(height: 12),
          for (final a in b.items) Padding(padding: const EdgeInsets.only(bottom: 8), child: KeyedSubtree(key: Key('pick-addr-${a.id}'), child: AddressTile(a, selected: a.id == selectedId, onTap: () => Navigator.pop(context, a)))),
          if (b.full)
            const Text('وصلت إلى ١٠ عناوين. احذف أحدها من «إدارة عناويني» لتضيف غيره.', style: TextStyle(color: Joy.warning, fontSize: 12))
          else
            OutlinedButton.icon(
              key: const Key('pick-addr-add'),
              onPressed: () async {
                final a = await openAddressForm(context, ref);
                if (a != null && context.mounted) Navigator.pop(context, a);
              },
              icon: const Icon(Icons.add_location_alt_outlined), label: Text(b.items.isEmpty ? 'أضف عنوان التوصيل' : 'عنوان جديد'),
            ),
          // «عناويني» كاملة من الطلب نفسه (تعديل وحذف وافتراضي) دون مغادرة العرض؛ الورقة تُبنى من جديد بالدفتر المحدَّث عند العودة
          if (b.items.isNotEmpty)
            Align(alignment: AlignmentDirectional.centerStart, child: TextButton.icon(
              key: const Key('pick-addr-manage'),
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddressesPage()));
                if (context.mounted) ref.invalidate(addressBookProvider);
              },
              icon: const Icon(Icons.edit_location_alt_outlined, size: 18), label: const Text('إدارة عناويني'),
            )),
        ]),
        loading: () => const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(addressBookProvider)),
      ),
    ));
  }
}
