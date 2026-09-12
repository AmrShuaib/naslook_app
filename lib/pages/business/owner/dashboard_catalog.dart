import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/biz_api.dart';
import '../../../api/biz_models.dart';
import '../../../api/chat_tools_api.dart';
import '../../../api/commerce_models.dart';
import '../../../core/app_theme.dart';
import '../../../core/media/pick_image.dart';
import '../../../state/app_state.dart';
import '../../../state/biz_providers.dart';
import '../../../ui/widgets.dart';
import 'business_editor.dart';

/// كتالوج الدائرة لصاحبها: تفعيل/إيقاف، تعديل، إضافة، حسب التخصص.
class CatalogTab extends ConsumerWidget {
  final Biz biz;
  const CatalogTab({super.key, required this.biz});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = biz.items;
    return Scaffold(
      backgroundColor: Joy.bg,
      floatingActionButton: biz.canManage ? FloatingActionButton.extended(onPressed: () => openItemEditor(context, biz), backgroundColor: Joy.primary, foregroundColor: Joy.primaryOn, icon: const Icon(Icons.add_rounded), label: Text(_addLabel(biz.category))) : null,
      body: items.isEmpty
          ? EmptyState(icon: Icons.inventory_2_outlined, title: 'الكتالوج فارغ', subtitle: 'أضف ${_addLabel(biz.category).replaceFirst('إضافة ', '')} ليظهر في صفحتك ويستطيع العملاء طلبه.')
          : RefreshIndicator(
              onRefresh: () async => invalidateBizAll(ref, biz.id),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _ItemRow(biz: biz, item: items[i]),
              ),
            ),
    );
  }
}

String _addLabel(BizCategory c) => switch (c) { BizCategory.brand => 'إضافة منتج', BizCategory.cinema => 'إضافة فيلم', BizCategory.hotel => 'إضافة غرفة', BizCategory.carRental => 'إضافة سيارة' };

class _ItemRow extends ConsumerWidget {
  final Biz biz;
  final BizItem item;
  const _ItemRow({required this.biz, required this.item});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final base = ref.read(apiClientProvider).baseUrl;
    final stockLabel = switch (item.kind) { 'showtime' => '${item.stock ?? 0} مقعد/عرض', 'room' => '${item.stock ?? 0} غرف', 'car' => '${item.stock ?? 0} سيارات', _ => item.stock == null ? 'كمية مفتوحة' : '${item.stock} متبقٍ' };
    return Opacity(
      opacity: item.active ? 1 : .55,
      child: JoyCard(
        onTap: biz.canManage ? () => openItemEditor(context, biz, item: item) : null,
        child: Row(children: [
          Container(
            width: 54, height: 54,
            decoration: BoxDecoration(color: biz.color.withValues(alpha: .12), borderRadius: BorderRadius.circular(14), image: item.imageUrl != null ? DecorationImage(image: NetworkImage(item.imageUrl!.startsWith('http') ? item.imageUrl! : '$base${item.imageUrl}'), fit: BoxFit.cover) : null),
            child: item.imageUrl == null ? Icon(switch (item.kind) { 'showtime' => Icons.movie_outlined, 'room' => Icons.king_bed_outlined, 'car' => Icons.directions_car_outlined, _ => Icons.shopping_bag_outlined }, color: biz.color.computeLuminance() > .6 ? Joy.text : biz.color) : null,
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (item.isOffer) Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: Joy.accentSoft, borderRadius: BorderRadius.circular(999)), child: const Text('عرض', style: TextStyle(color: Joy.accent, fontSize: 10.5, fontWeight: FontWeight.w700))),
            ]),
            Text('${money(item.price)} ${item.unitLabel} · $stockLabel${item.kind == 'showtime' ? ' · ${(item.meta['times'] as List?)?.join(' ، ') ?? ''}' : ''}', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5), maxLines: 2, overflow: TextOverflow.ellipsis),
          ])),
          if (biz.canManage)
            Switch(
              value: item.active,
              onChanged: (v) async {
                try {
                  await ref.read(apiClientProvider).updateBizItem(biz.id, item.id, {'active': v});
                  invalidateBizAll(ref, biz.id);
                } catch (e) {
                  if (context.mounted) toast(context, ownerErrText(e), error: true);
                }
              },
            ),
        ]),
      ),
    );
  }
}

/// محرّر عنصر الكتالوج حسب نوعه: منتج / فيلم بمواعيد / غرفة / سيارة.
Future<void> openItemEditor(BuildContext context, Biz biz, {BizItem? item}) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .92),
      builder: (_) => ItemEditor(biz: biz, item: item),
    );

class ItemEditor extends ConsumerStatefulWidget {
  final Biz biz;
  final BizItem? item;
  const ItemEditor({super.key, required this.biz, this.item});
  @override
  ConsumerState<ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends ConsumerState<ItemEditor> {
  late final TextEditingController title, description, price, oldPrice, stock, hall, minutes, genre, rating, beds, guests, size, view, cls, seats, transmission, year, fuel, time;
  late List<String> times;
  bool breakfast = false, busy = false, uploading = false;
  String? imageUrl;

  BizItem? get it => widget.item;
  String get kind => it?.kind ?? widget.biz.category.itemKind;
  Map<String, dynamic> get m => it?.meta ?? const {};

  @override
  void initState() {
    super.initState();
    String sar(int? h) => h == null ? '' : (h / 100).toStringAsFixed(h % 100 == 0 ? 0 : 2);
    title = TextEditingController(text: it?.title ?? '');
    description = TextEditingController(text: it?.description ?? '');
    price = TextEditingController(text: sar(it?.price));
    oldPrice = TextEditingController(text: sar(it?.oldPrice));
    stock = TextEditingController(text: it?.stock?.toString() ?? (kind == 'showtime' ? '100' : kind == 'product' ? '' : '1'));
    hall = TextEditingController(text: m['hall']?.toString() ?? '');
    minutes = TextEditingController(text: m['minutes']?.toString() ?? '');
    genre = TextEditingController(text: m['genre']?.toString() ?? '');
    rating = TextEditingController(text: m['rating']?.toString() ?? '');
    beds = TextEditingController(text: m['beds']?.toString() ?? '');
    guests = TextEditingController(text: m['guests']?.toString() ?? '');
    size = TextEditingController(text: m['size']?.toString() ?? '');
    view = TextEditingController(text: m['view']?.toString() ?? '');
    cls = TextEditingController(text: m['cls']?.toString() ?? '');
    seats = TextEditingController(text: m['seats']?.toString() ?? '');
    transmission = TextEditingController(text: m['transmission']?.toString() ?? 'أوتوماتيك');
    year = TextEditingController(text: m['year']?.toString() ?? '');
    fuel = TextEditingController(text: m['fuel']?.toString() ?? '');
    time = TextEditingController();
    times = List<String>.from((m['times'] as List?)?.map((e) => e.toString()) ?? const []);
    breakfast = m['breakfast'] == true;
    imageUrl = it?.imageUrl;
  }

  @override
  void dispose() {
    for (final c in [title, description, price, oldPrice, stock, hall, minutes, genre, rating, beds, guests, size, view, cls, seats, transmission, year, fuel, time]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = ref.read(apiClientProvider).baseUrl;
    final isNew = it == null;
    final priceLabel = switch (kind) { 'showtime' => 'سعر التذكرة (ر.س)', 'room' => 'سعر الليلة (ر.س)', 'car' => 'سعر اليوم (ر.س)', _ => 'السعر (ر.س)' };
    final stockLabel = switch (kind) { 'showtime' => 'عدد المقاعد لكل عرض', 'room' => 'عدد الغرف من هذا النوع', 'car' => 'عدد السيارات المتاحة', _ => 'الكمية المتاحة (اتركه فارغاً لكمية مفتوحة)' };
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(isNew ? _addLabel(widget.biz.category) : 'تعديل: ${it!.title}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 12),
        Row(children: [
          InkWell(
            onTap: uploading ? null : _upload,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 84, height: 84,
              decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(16), image: imageUrl != null ? DecorationImage(image: NetworkImage(imageUrl!.startsWith('http') ? imageUrl! : '$base$imageUrl'), fit: BoxFit.cover) : null),
              alignment: Alignment.center,
              child: uploading ? const CircularProgressIndicator() : imageUrl == null ? const Icon(Icons.add_photo_alternate_outlined, color: Joy.textMuted) : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: TextField(controller: title, decoration: InputDecoration(labelText: switch (kind) { 'showtime' => 'اسم الفيلم', 'room' => 'اسم الغرفة', 'car' => 'السيارة (الطراز والسنة)', _ => 'اسم المنتج' }))),
        ]),
        const SizedBox(height: 10),
        TextField(controller: description, maxLines: 2, decoration: const InputDecoration(labelText: 'الوصف')),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: priceLabel))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: stock, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: stockLabel, labelStyle: const TextStyle(fontSize: 12)))),
        ]),
        if (kind == 'product') ...[
          const SizedBox(height: 10),
          TextField(controller: oldPrice, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'السعر قبل الخصم (اختياري، لعرض شارة "عرض")')),
        ],
        if (kind == 'showtime') ...[
          const SizedBox(height: 14),
          const Text('مواعيد العرض اليومية', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final t in times) InputChip(label: Text(t, style: const TextStyle(fontFamily: AppTheme.bodyFont)), onDeleted: () => setState(() => times.remove(t)))]),
          Row(children: [
            Expanded(child: TextField(controller: time, keyboardType: TextInputType.datetime, decoration: const InputDecoration(hintText: 'وقت بصيغة 24 ساعة مثل 19:30'), onSubmitted: (_) => _addTime())),
            IconButton(onPressed: _addTime, icon: const Icon(Icons.add_circle_outline_rounded, color: Joy.primary)),
            IconButton(tooltip: 'اختيار من الساعة', onPressed: () async {
              final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 19, minute: 30));
              if (t == null) return;
              setState(() { final s = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'; if (!times.contains(s)) { times.add(s); times.sort(); } });
            }, icon: const Icon(Icons.schedule_rounded, color: Joy.primary)),
          ]),
          Row(children: [
            Expanded(child: TextField(controller: hall, decoration: const InputDecoration(labelText: 'الصالة'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: minutes, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المدة (دقيقة)'))),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: genre, decoration: const InputDecoration(labelText: 'النوع', hintText: 'أكشن، عائلي…'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: rating, decoration: const InputDecoration(labelText: 'التصنيف العمري', hintText: 'G, PG12, PG15, R18'))),
          ]),
        ],
        if (kind == 'room') ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: beds, decoration: const InputDecoration(labelText: 'الأسرّة', hintText: 'سرير كينغ'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: guests, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'أقصى عدد نزلاء'))),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: size, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المساحة (م²)'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: view, decoration: const InputDecoration(labelText: 'الإطلالة', hintText: 'البحر، المدينة'))),
          ]),
          SwitchListTile(contentPadding: EdgeInsets.zero, value: breakfast, onChanged: (v) => setState(() => breakfast = v), title: const Text('شامل الإفطار')),
        ],
        if (kind == 'car') ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: cls, decoration: const InputDecoration(labelText: 'الفئة', hintText: 'اقتصادية، دفع رباعي…'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: seats, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المقاعد'))),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: transmission, decoration: const InputDecoration(labelText: 'ناقل الحركة'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: year, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'سنة الصنع'))),
          ]),
          const SizedBox(height: 10),
          TextField(controller: fuel, decoration: const InputDecoration(labelText: 'الوقود', hintText: 'بنزين، كهرباء، هجين')),
        ],
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: FilledButton.icon(onPressed: busy ? null : _save, icon: const Icon(Icons.save_outlined), label: Text(isNew ? 'إضافة' : 'حفظ'))),
          if (!isNew) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: busy ? null : () async {
                final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: const Text('إخفاء العنصر؟'), content: const Text('يختفي من الكتالوج وتبقى الطلبات السابقة عليه.'), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('تراجع')), FilledButton(style: FilledButton.styleFrom(backgroundColor: Joy.danger), onPressed: () => Navigator.pop(d, true), child: const Text('إخفاء'))]));
                if (ok != true) return;
                try {
                  await ref.read(apiClientProvider).deleteBizItem(widget.biz.id, it!.id);
                  invalidateBizAll(ref, widget.biz.id);
                  if (context.mounted) Navigator.pop(context);
                } catch (e) { if (context.mounted) toast(context, ownerErrText(e), error: true); }
              },
              icon: const Icon(Icons.visibility_off_outlined, size: 18, color: Joy.danger),
              label: const Text('إخفاء', style: TextStyle(color: Joy.danger)),
            ),
          ],
        ]),
      ]),
    );
  }

  void _addTime() {
    final v = time.text.trim().replaceAll('٫', ':').replaceAll('.', ':');
    final ok = RegExp(r'^([01]?\d|2[0-3]):[0-5]\d$').hasMatch(v);
    if (!ok) { toast(context, 'اكتب الوقت بصيغة 19:30', error: true); return; }
    final norm = v.length == 4 ? '0$v' : v;
    setState(() { if (!times.contains(norm)) { times.add(norm); times.sort(); } time.clear(); });
  }

  Future<void> _upload() async {
    try {
      final img = await pickImage();
      if (img == null) return;
      setState(() => uploading = true);
      final up = await ref.read(apiClientProvider).uploadMedia(img.bytes, contentType: img.mime, fileName: img.name);
      if (mounted) setState(() => imageUrl = up.url);
    } catch (e) {
      if (mounted) toast(context, ownerErrText(e), error: true);
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> _save() async {
    if (title.text.trim().isEmpty) { toast(context, 'اكتب العنوان', error: true); return; }
    final p = parseSar(price.text);
    if (p <= 0 && kind != 'product') { toast(context, 'اكتب سعراً صحيحاً', error: true); return; }
    if (kind == 'showtime' && times.isEmpty) { toast(context, 'أضف موعد عرض واحداً على الأقل', error: true); return; }
    int? intOf(TextEditingController c) => int.tryParse(c.text.trim().replaceAll(RegExp(r'[^0-9]'), ''));
    final meta = <String, dynamic>{
      if (kind == 'product' && parseSar(oldPrice.text) > p) 'oldPrice': parseSar(oldPrice.text),
      if (kind == 'showtime') ...{'times': times, 'hall': hall.text.trim(), 'minutes': intOf(minutes) ?? 120, 'genre': genre.text.trim(), 'rating': rating.text.trim()},
      if (kind == 'room') ...{'beds': beds.text.trim(), 'guests': intOf(guests) ?? 2, 'size': intOf(size), 'view': view.text.trim(), 'breakfast': breakfast},
      if (kind == 'car') ...{'cls': cls.text.trim(), 'seats': intOf(seats) ?? 5, 'transmission': transmission.text.trim(), 'year': intOf(year), 'fuel': fuel.text.trim()},
    };
    final body = <String, dynamic>{'kind': kind, 'title': title.text.trim(), 'description': description.text.trim(), 'price': p, 'stock': stock.text.trim().isEmpty ? null : intOf(stock), 'meta': meta, 'imageUrl': imageUrl};
    setState(() => busy = true);
    try {
      final api = ref.read(apiClientProvider);
      if (it == null) {
        await api.createBizItem(widget.biz.id, body);
      } else {
        await api.updateBizItem(widget.biz.id, it!.id, body);
      }
      invalidateBizAll(ref, widget.biz.id);
      if (mounted) { Navigator.pop(context); toast(context, it == null ? 'أُضيف إلى الكتالوج' : 'حُفظ'); }
    } catch (e) {
      if (mounted) toast(context, ownerErrText(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}
