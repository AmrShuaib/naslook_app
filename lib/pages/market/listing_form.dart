// نموذج العرض (إنشاء أو تعديل) كصفحة كاملة: حتى ٨ صور، نوع، تصنيف وفرعي، عنوان ووصف وسعر، حالة، توصيل، مخزون،
// خيارات بأسعار، أوقات الخدمة، مكان ومدينة، وحفظ كمسودة أو جدولة النشر.
import 'package:flutter/material.dart';

import '../../api/commerce_models.dart';
import '../../core/app_theme.dart';
import '../../core/media/pick_image.dart';
import '../../api/client.dart';
import '../../ui/widgets.dart';

class ListingDraft {
  final String title, description, kind, category, placeName, city, status;
  final String? subcategory, condition;
  final int price;
  final int? stock;
  final bool delivery;
  final List<Variant> variants;
  final Availability? availability;
  final DateTime? publishAt;
  final List<String> existingImages;
  final List<PickedImage> newImages;
  const ListingDraft({required this.title, required this.description, required this.kind, required this.category, this.subcategory, this.condition, required this.price, this.stock, this.delivery = false, this.variants = const [], this.availability, this.publishAt,
      this.placeName = '', this.city = '', this.status = 'active', this.existingImages = const [], this.newImages = const []});
  /// الحقول التي يرسلها التطبيق للخادم (الصور تُضاف بعد الرفع)
  Map<String, dynamic> toBody() => {
        'title': title, 'description': description, 'kind': kind, 'category': category, 'subcategory': subcategory, 'condition': condition, 'price': price, 'stock': stock, 'delivery': delivery,
        'variants': [for (final v in variants) v.toJson()], 'availability': availability?.toJson(), 'placeName': placeName, 'city': city, 'status': status, 'publishAt': publishAt?.toUtc().toIso8601String(),
      };
  /// ما يُتاح للتعديل في ملف الصور: القائمة المتبقية من الروابط القديمة فقط
  bool get removedImages => existingImages.isEmpty;
}

String _priceText(int halalas) => halalas % 100 == 0 ? '${halalas ~/ 100}' : (halalas / 100).toStringAsFixed(2);

/// يفتح النموذج ويعيد المسودة أو null عند الإلغاء
Future<ListingDraft?> showListingForm(BuildContext context, {Listing? initial}) => Navigator.of(context).push<ListingDraft>(MaterialPageRoute(builder: (_) => ListingFormPage(initial: initial), fullscreenDialog: true));

class ListingFormPage extends StatefulWidget {
  final Listing? initial;
  const ListingFormPage({super.key, this.initial});
  @override
  State<ListingFormPage> createState() => _ListingFormPageState();
}

class _ListingFormPageState extends State<ListingFormPage> {
  late final title = TextEditingController(text: widget.initial?.title ?? '');
  late final desc = TextEditingController(text: widget.initial?.description ?? '');
  late final price = TextEditingController(text: widget.initial == null ? '' : _priceText(widget.initial!.price));
  late final place = TextEditingController(text: widget.initial?.placeName ?? '');
  late final city = TextEditingController(text: widget.initial?.city ?? '');
  late final stock = TextEditingController(text: widget.initial?.stock == null ? '' : '${widget.initial!.stock}');
  late String kind = widget.initial?.kind ?? 'product';
  late String category = marketCategories.containsKey(widget.initial?.category) ? widget.initial!.category : 'other';
  late String? sub = widget.initial?.subcategory;
  late String? condition = widget.initial?.condition;
  late bool delivery = widget.initial?.delivery ?? false;
  late List<String> existing = [...?widget.initial?.images];
  final picked = <PickedImage>[];
  late List<Variant> variants = [...?widget.initial?.variants];
  late Availability? availability = widget.initial?.availability;
  DateTime? publishAt;
  bool advanced = false;

  @override
  void dispose() { for (final c in [title, desc, price, place, city, stock]) { c.dispose(); } super.dispose(); }

  int get imageCount => existing.length + picked.length;

  Future<void> _addImage() async {
    if (imageCount >= 8) { toast(context, 'الحد ٨ صور'); return; }
    final p = await pickImage();
    if (p != null && mounted) setState(() => picked.add(p));
  }

  void _submit(String status) {
    if (title.text.trim().length < 3) { toast(context, 'اكتب عنواناً واضحاً', error: true); return; }
    final p = parseSar(price.text);
    if (variants.isEmpty && p <= 0 && price.text.trim().isNotEmpty && price.text.trim() != '0') { toast(context, 'السعر غير صالح', error: true); return; }
    Navigator.pop(context, ListingDraft(
      title: title.text.trim(), description: desc.text.trim(), kind: kind, category: category, subcategory: sub, condition: kind == 'product' ? condition : null, price: variants.isNotEmpty ? variants.map((v) => v.price).reduce((a, b) => a < b ? a : b) : p,
      stock: variants.isNotEmpty || stock.text.trim().isEmpty ? null : int.tryParse(stock.text.trim()), delivery: delivery, variants: variants, availability: kind == 'service' ? availability : null, publishAt: publishAt,
      placeName: place.text.trim(), city: city.text.trim(), status: status, existingImages: existing, newImages: picked,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final subs = marketSubcategories[category] ?? const {};
    final editing = widget.initial != null;
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: Text(editing ? 'تعديل العرض' : 'عرض جديد'), actions: [
        if (!editing) TextButton(key: const Key('lf-draft'), onPressed: () => _submit('draft'), child: const Text('حفظ كمسودة')),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
        // الصور
        SizedBox(height: 96, child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final (i, u) in existing.indexed) _Thumb(onRemove: () => setState(() => existing.removeAt(i)), cover: i == 0, child: Image.network(thumbUrl(u), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.image_outlined, color: Joy.textMuted))),
          for (final (i, p) in picked.indexed) _Thumb(onRemove: () => setState(() => picked.removeAt(i)), cover: existing.isEmpty && i == 0, child: Image.memory(p.bytes, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: Joy.textMuted))),
          if (imageCount < 8) InkWell(key: const Key('lf-add-image'), onTap: _addImage, borderRadius: BorderRadius.circular(14), child: Container(width: 92, margin: const EdgeInsets.only(left: 8), decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(14)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.add_photo_alternate_outlined, color: Joy.textMuted), const SizedBox(height: 4), Text(imageCount == 0 ? 'إضافة صورة' : 'صورة أخرى', style: const TextStyle(fontSize: 11.5, color: Joy.textMuted))]))),
        ])),
        Padding(padding: const EdgeInsets.only(top: 4, bottom: 10), child: Text(imageCount == 0 ? 'الصور الواضحة تضاعف الطلبات. حتى ٨ صور، والأولى هي الغلاف.' : '$imageCount من ٨ صور · الأولى هي الغلاف', style: const TextStyle(color: Joy.textMuted, fontSize: 12))),
        // النوع
        Row(children: [for (final (k, l) in [('product', 'منتج'), ('service', 'خدمة')]) Padding(padding: const EdgeInsets.only(left: 8), child: ChoiceChip(key: Key('lf-kind-$k'), label: Text(l, style: TextStyle(color: kind == k ? Joy.primaryOn : Joy.text)), selected: kind == k, onSelected: (_) => setState(() => kind = k), showCheckmark: false, selectedColor: Joy.primary))]),
        const SizedBox(height: 12),
        TextField(key: const Key('lf-title'), controller: title, decoration: const InputDecoration(labelText: 'العنوان', hintText: 'مثال: كيك عيد ميلاد بتصميم خاص'), autofocus: !editing, maxLength: 100),
        const SizedBox(height: 4),
        TextField(key: const Key('lf-desc'), controller: desc, maxLines: 4, decoration: const InputDecoration(labelText: 'الوصف', hintText: 'التفاصيل، المقاسات، مدة التجهيز، ما يشمله السعر…'), maxLength: 2000),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(key: const Key('lf-category'), initialValue: category, decoration: const InputDecoration(labelText: 'التصنيف'), items: [for (final e in marketCategories.entries) DropdownMenuItem(value: e.key, child: Text(e.value))], onChanged: (v) => setState(() { category = v ?? 'other'; sub = null; })),
        if (subs.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Wrap(spacing: 6, runSpacing: 6, children: [for (final e in subs.entries) ChoiceChip(key: Key('lf-sub-${e.key}'), label: Text(e.value, style: const TextStyle(fontSize: 12)), selected: sub == e.key, showCheckmark: false, selectedColor: Joy.primarySoft, visualDensity: VisualDensity.compact, onSelected: (_) => setState(() => sub = sub == e.key ? null : e.key))])),
        const SizedBox(height: 12),
        if (variants.isEmpty) TextField(key: const Key('lf-price'), controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'السعر (ر.س)', hintText: '0 = مجاناً')),
        if (kind == 'product') ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: [for (final e in marketConditions.entries) ChoiceChip(key: Key('lf-cond-${e.key}'), label: Text(e.value), selected: condition == e.key, showCheckmark: false, selectedColor: Joy.primarySoft, onSelected: (_) => setState(() => condition = condition == e.key ? null : e.key))]),
        ],
        SwitchListTile(key: const Key('lf-delivery'), contentPadding: EdgeInsets.zero, value: delivery, onChanged: (v) => setState(() => delivery = v), title: const Text('التوصيل متاح'), subtitle: const Text('يظهر في الفلاتر ويطمئن المشتري', style: TextStyle(fontSize: 12))),
        const Divider(height: 24),
        // متقدم: مخزون وخيارات ومواعيد ومكان وجدولة
        InkWell(onTap: () => setState(() => advanced = !advanced), child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [const Text('خيارات إضافية', style: TextStyle(fontWeight: FontWeight.w700)), const Spacer(), Icon(advanced ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: Joy.textMuted)]))),
        if (advanced || variants.isNotEmpty || availability != null) ...[
          if (kind == 'product') ...[
            if (variants.isEmpty) TextField(key: const Key('lf-stock'), controller: stock, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الكمية المتوفرة (اتركه فارغاً إن كان غير محدود)')),
            const SizedBox(height: 10),
            _VariantsEditor(variants: variants, onChanged: (v) => setState(() => variants = v)),
          ],
          if (kind == 'service') _AvailabilityEditor(value: availability, onChanged: (v) => setState(() => availability = v)),
          const SizedBox(height: 10),
          TextField(key: const Key('lf-place'), controller: place, decoration: const InputDecoration(labelText: 'الحي أو مكان الاستلام (اختياري)')),
          const SizedBox(height: 10),
          TextField(key: const Key('lf-city'), controller: city, decoration: const InputDecoration(labelText: 'المدينة (اختياري)')),
          if (!editing) ...[
            const SizedBox(height: 10),
            ListTile(key: const Key('lf-schedule'), contentPadding: EdgeInsets.zero, leading: const Icon(Icons.schedule_rounded, color: Joy.textMuted), title: Text(publishAt == null ? 'نشر الآن' : 'يُنشر ${clockOf(publishAt)} ${publishAt!.day}/${publishAt!.month}'), subtitle: const Text('اضغط لجدولة النشر في وقت لاحق', style: TextStyle(fontSize: 12)),
              trailing: publishAt == null ? null : IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => setState(() => publishAt = null)),
              onTap: () async {
                final now = DateTime.now();
                final d = await showDatePicker(context: context, initialDate: now, firstDate: now, lastDate: now.add(const Duration(days: 60))); if (d == null || !context.mounted) return;
                final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1)))); if (t == null) return;
                setState(() => publishAt = DateTime(d.year, d.month, d.day, t.hour, t.minute));
              }),
          ],
        ],
        const SizedBox(height: 18),
        FilledButton(key: const Key('lf-submit'), onPressed: () => _submit(widget.initial?.status == 'draft' ? 'active' : (widget.initial?.status ?? 'active')), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)), child: Text(editing ? (widget.initial!.status == 'draft' ? 'نشر' : 'حفظ') : (publishAt == null ? 'نشر' : 'جدولة النشر'))),
      ]),
    );
  }
}

class _Thumb extends StatelessWidget {
  final Widget child; final VoidCallback onRemove; final bool cover;
  const _Thumb({required this.child, required this.onRemove, this.cover = false});
  @override
  Widget build(BuildContext context) => Container(width: 92, margin: const EdgeInsets.only(left: 8), clipBehavior: Clip.antiAlias, decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(14)), child: Stack(fit: StackFit.expand, children: [
        child,
        Positioned(top: 4, left: 4, child: InkWell(onTap: onRemove, child: Container(padding: const EdgeInsets.all(3), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(999)), child: const Icon(Icons.close_rounded, size: 14, color: Colors.white)))),
        if (cover) Positioned(bottom: 4, right: 4, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(999)), child: const Text('الغلاف', style: TextStyle(color: Colors.white, fontSize: 10)))),
      ]));
}

/// خيارات (مقاس، لون، نكهة…) بأسعار ومخزون اختياري
class _VariantsEditor extends StatelessWidget {
  final List<Variant> variants; final ValueChanged<List<Variant>> onChanged;
  const _VariantsEditor({required this.variants, required this.onChanged});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Text('خيارات بأسعار مختلفة', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)), const Spacer(), TextButton.icon(key: const Key('lf-add-variant'), onPressed: () => _edit(context, null), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('إضافة خيار'))]),
        for (final (i, v) in variants.indexed)
          ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(v.name), subtitle: Text('${money(v.price)}${v.stock != null ? ' · المتوفر ${v.stock}' : ''}'), trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _edit(context, i)), IconButton(icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Joy.danger), onPressed: () => onChanged([...variants]..removeAt(i)))])),
        if (variants.isEmpty) const Text('مثال: مقاس S بـ ٣٠٠ ومقاس M بـ ٣٢٠. عند إضافة خيارات يصبح السعر من الخيار.', style: TextStyle(color: Joy.textMuted, fontSize: 12)),
      ]);
  Future<void> _edit(BuildContext context, int? index) async {
    final v = index == null ? null : variants[index];
    final name = TextEditingController(text: v?.name ?? ''), price = TextEditingController(text: v == null ? '' : _priceText(v.price)), stock = TextEditingController(text: v?.stock == null ? '' : '${v!.stock}');
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: Text(v == null ? 'خيار جديد' : 'تعديل الخيار'), content: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(key: const Key('lf-variant-name'), controller: name, decoration: const InputDecoration(labelText: 'الاسم (مثال: مقاس M)'), autofocus: true),
      TextField(key: const Key('lf-variant-price'), controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'السعر (ر.س)')),
      TextField(controller: stock, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الكمية (اختياري)')),
    ]), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(key: const Key('lf-variant-save'), onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ'))]));
    if (ok != true || name.text.trim().isEmpty) return;
    final nv = Variant(name: name.text.trim(), price: parseSar(price.text), stock: stock.text.trim().isEmpty ? null : int.tryParse(stock.text.trim()));
    final list = [...variants]; if (index == null) { list.add(nv); } else { list[index] = nv; }
    onChanged(list);
  }
}

/// أوقات الخدمة: الأيام ومن/إلى ومدة الموعد
class _AvailabilityEditor extends StatelessWidget {
  final Availability? value; final ValueChanged<Availability?> onChanged;
  const _AvailabilityEditor({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final v = value;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SwitchListTile(key: const Key('lf-availability'), contentPadding: EdgeInsets.zero, value: v != null, onChanged: (on) => onChanged(on ? const Availability(days: [0, 1, 2, 3, 4], from: '16:00', to: '22:00', slotMinutes: 60) : null), title: const Text('حجز بموعد'), subtitle: const Text('يختار المشتري موعداً من أوقاتك ولا يتكرر الحجز', style: TextStyle(fontSize: 12))),
      if (v != null) ...[
        Wrap(spacing: 6, runSpacing: 6, children: [for (var d = 0; d < 7; d++) FilterChip(label: Text(weekdayLabels[d], style: const TextStyle(fontSize: 12)), selected: v.days.contains(d), showCheckmark: false, selectedColor: Joy.primarySoft, visualDensity: VisualDensity.compact, onSelected: (on) { final days = {...v.days}; on ? days.add(d) : days.remove(d); onChanged(Availability(days: days.toList()..sort(), from: v.from, to: v.to, slotMinutes: v.slotMinutes)); })]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _timeField(context, 'من', v.from, (t) => onChanged(Availability(days: v.days, from: t, to: v.to, slotMinutes: v.slotMinutes)))), const SizedBox(width: 8),
          Expanded(child: _timeField(context, 'إلى', v.to, (t) => onChanged(Availability(days: v.days, from: v.from, to: t, slotMinutes: v.slotMinutes)))), const SizedBox(width: 8),
          Expanded(child: DropdownButtonFormField<int>(initialValue: v.slotMinutes, decoration: const InputDecoration(labelText: 'المدة', isDense: true), items: const [30, 45, 60, 90, 120, 180].map((m) => DropdownMenuItem(value: m, child: Text('$m د'))).toList(), onChanged: (m) => onChanged(Availability(days: v.days, from: v.from, to: v.to, slotMinutes: m ?? 60)))),
        ]),
      ],
    ]);
  }
  Widget _timeField(BuildContext context, String label, String hm, ValueChanged<String> set) => InkWell(
        onTap: () async { final p = hm.split(':'); final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: int.tryParse(p[0]) ?? 9, minute: int.tryParse(p[1]) ?? 0)); if (t != null) set('${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'); },
        child: InputDecorator(decoration: InputDecoration(labelText: label, isDense: true), child: Text(hm)),
      );
}
