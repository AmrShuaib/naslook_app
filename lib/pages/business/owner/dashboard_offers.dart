import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/biz_api.dart';
import '../../../api/biz_models.dart';
import '../../../api/commerce_models.dart';
import '../../../core/app_theme.dart';
import '../../../state/app_state.dart';
import '../../../state/biz_providers.dart';
import '../../../ui/widgets.dart';
import '../business_page.dart' show dayLabel, shortDate;
import '../offers_page.dart' show offerWhen;
import 'business_editor.dart' show ownerErrText;

/// تبويب العروض في لوحة المالك: القوالب بثلاث ضغطات، إحصاءات كل عرض، وإجراءات «أنهِ الآن» و«كرّر العرض».
class OffersTab extends ConsumerWidget {
  final Biz biz;
  const OffersTab({super.key, required this.biz});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(manageOffersProvider(biz.id));
    return Scaffold(
      backgroundColor: Joy.bg,
      floatingActionButton: biz.canManage
          ? FloatingActionButton.extended(key: const Key('offer-new'), onPressed: () => openOfferTemplates(context, biz, page.valueOrNull?.templates ?? const []), backgroundColor: Joy.primary, foregroundColor: Joy.primaryOn, icon: const Icon(Icons.local_offer_outlined), label: const Text('عرض جديد'))
          : null,
      body: page.when(
        data: (m) {
          final live = m.offers.where((o) => o.state == 'active').toList();
          final upcoming = m.offers.where((o) => o.state == 'upcoming').toList();
          final past = m.offers.where((o) => o.state == 'ended' || o.state == 'off').toList();
          final uses = m.offers.fold(0, (n, o) => n + (o.stats?.uses ?? 0));
          final discount = m.offers.fold(0, (n, o) => n + (o.stats?.discount ?? 0));
          final revenue = m.offers.fold(0, (n, o) => n + (o.stats?.revenue ?? 0));
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(manageOffersProvider(biz.id)),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
              children: [
                Row(children: [
                  _Stat('الأعضاء', '${m.members}', Icons.group_outlined),
                  _Stat('استخدامات', '$uses', Icons.confirmation_number_outlined),
                  _Stat('خصومات', money(discount), Icons.savings_outlined),
                  _Stat('مبيعات بعرض', money(revenue), Icons.payments_outlined),
                ]),
                const SizedBox(height: 6),
                if (m.offers.isEmpty)
                  const EmptyState(icon: Icons.local_offer_outlined, title: 'لا عروض بعد', subtitle: 'ابدأ بقالب جاهز: ساعة هادئة، أول طلب، أو مكافأة الرواد. يصل العرض لأعضاء دائرتك حسب تنبيهاتهم ويُطبّق تلقائياً على طلباتهم.'),
                if (live.isNotEmpty) ...[
                  const SectionTitle('السارية'),
                  for (final o in live) _ManageOfferCard(biz: biz, offer: o),
                ],
                if (upcoming.isNotEmpty) ...[
                  const SectionTitle('القادمة'),
                  for (final o in upcoming) _ManageOfferCard(biz: biz, offer: o),
                ],
                if (past.isNotEmpty) ...[
                  const SectionTitle('المنتهية والمتوقفة'),
                  for (final o in past) _ManageOfferCard(biz: biz, offer: o),
                ],
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(manageOffersProvider(biz.id))),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _Stat(this.label, this.value, this.icon);
  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          margin: const EdgeInsets.only(left: 6, bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(color: Joy.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: Joy.line)),
          child: Column(children: [
            Icon(icon, size: 18, color: Joy.primary),
            const SizedBox(height: 4),
            FittedBox(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
            Text(label, style: const TextStyle(color: Joy.textMuted, fontSize: 10.5)),
          ]),
        ),
      );
}

class _ManageOfferCard extends ConsumerWidget {
  final Biz biz;
  final BizOffer offer;
  const _ManageOfferCard({required this.biz, required this.offer});

  Future<void> _act(BuildContext context, WidgetRef ref, String action) async {
    final api = ref.read(apiClientProvider);
    try {
      switch (action) {
        case 'edit':
          await openOfferEditor(context, biz, offer: offer);
          return;
        case 'end':
          final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: const Text('إنهاء العرض الآن؟'), content: const Text('يتوقف العرض فوراً ويبقى في قسم المنتهية للأعضاء 30 يوماً.'), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('تراجع')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('أنهِ الآن'))]));
          if (ok != true) return;
          await api.updateOffer(biz.id, offer.id, {'endNow': true});
          if (context.mounted) toast(context, 'انتهى العرض');
        case 'toggle':
          await api.updateOffer(biz.id, offer.id, {'active': !offer.active});
          if (context.mounted) toast(context, offer.active ? 'أُوقف العرض' : 'أُعيد تفعيل العرض');
        case 'dup':
          final created = await api.duplicateOffer(biz.id, offer.id);
          if (context.mounted) toast(context, 'كُرّر العرض «${created.title}» ويمكنك تعديل موعده');
        case 'delete':
          final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: const Text('حذف العرض؟'), content: const Text('إن كان قد استُخدم يُؤرشف بدل الحذف حفاظاً على السجل.'), actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('تراجع')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('حذف'))]));
          if (ok != true) return;
          await api.deleteOffer(biz.id, offer.id);
          if (context.mounted) toast(context, 'حُذف العرض');
      }
      invalidateBizAll(ref, biz.id);
    } catch (e) {
      if (context.mounted) toast(context, ownerErrText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = offer;
    final s = o.stats ?? const OfferStats();
    final stateColor = switch (o.state) { 'active' => Joy.success, 'upcoming' => Joy.primary, _ => Joy.textMuted };
    final stateLabel = switch (o.state) { 'active' => 'ساري', 'upcoming' => 'قادم', 'ended' => 'منتهٍ', _ => 'متوقف' };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: JoyCard(
        key: Key('manage-offer-${o.id}'),
        onTap: biz.canManage ? () => _act(context, ref, 'edit') : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: stateColor.withValues(alpha: .12), borderRadius: BorderRadius.circular(999)), child: Text(stateLabel, style: TextStyle(color: stateColor, fontSize: 10.5, fontWeight: FontWeight.w700))),
            const SizedBox(width: 6),
            Text(o.kindLabel, style: const TextStyle(color: Joy.textMuted, fontSize: 11.5)),
            if (o.membersOnly) const Text(' · للأعضاء', style: TextStyle(color: Joy.textMuted, fontSize: 11.5)),
            const SizedBox(width: 8),
            Expanded(child: Text(offerWhen(o), textAlign: TextAlign.end, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 11.5))),
            if (biz.canManage)
              PopupMenuButton<String>(
                key: Key('offer-menu-${o.id}'),
                tooltip: 'إجراءات',
                padding: EdgeInsets.zero,
                iconSize: 20,
                onSelected: (a) => _act(context, ref, a),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('تعديل')),
                  if (o.state == 'active') const PopupMenuItem(value: 'end', child: Text('أنهِ الآن')),
                  if (o.state != 'ended') PopupMenuItem(value: 'toggle', child: Text(o.active ? 'إيقاف مؤقت' : 'تفعيل')),
                  const PopupMenuItem(value: 'dup', child: Text('كرّر العرض')),
                  const PopupMenuItem(value: 'delete', child: Text('حذف', style: TextStyle(color: Joy.danger))),
                ],
              ),
          ]),
          const SizedBox(height: 6),
          Text(o.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
          Text([o.valueLabel, if (o.conditionLabel.isNotEmpty) o.conditionLabel].join(' · '), style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
          const SizedBox(height: 8),
          Wrap(spacing: 14, runSpacing: 4, children: [
            _Mini(Icons.visibility_outlined, '${s.views} مشاهدة'),
            _Mini(Icons.confirmation_number_outlined, '${s.uses} استخدام'),
            _Mini(Icons.savings_outlined, 'خصم ${money(s.discount)}'),
            _Mini(Icons.payments_outlined, 'مبيعات ${money(s.revenue)}'),
            if (s.sent > 0) _Mini(Icons.card_giftcard_rounded, '${s.sent} إرسال'),
            if (s.rewards > 0) _Mini(Icons.emoji_events_outlined, '${s.rewards} مكافأة'),
          ]),
        ]),
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Mini(this.icon, this.text);
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14, color: Joy.textMuted), const SizedBox(width: 3), Text(text, style: const TextStyle(color: Joy.textMuted, fontSize: 11.5))]);
}

/// ورقة القوالب: ثلاث ضغطات بدل نموذج طويل، مع خيار البدء من الصفر.
Future<void> openOfferTemplates(BuildContext context, Biz biz, List<OfferTemplate> templates) async {
  final picked = await showModalBottomSheet<OfferTemplate?>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .85),
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        children: [
          const Text('ابدأ بقالب', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(height: 4),
          const Text('تُملأ القيم والمدة والشروط تلقائياً ويمكنك تعديل أي شيء قبل النشر.', style: TextStyle(color: Joy.textMuted, fontSize: 12.5)),
          const SizedBox(height: 10),
          for (final t in templates)
            ListTile(
              key: Key('tpl-${t.id}'),
              contentPadding: EdgeInsets.zero,
              leading: Container(width: 42, height: 42, decoration: BoxDecoration(color: Joy.primarySoft, borderRadius: BorderRadius.circular(12)), child: Icon(_tplIcon(t.kind), color: Joy.primary)),
              title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(t.hint, style: const TextStyle(fontSize: 12, color: Joy.textMuted)),
              trailing: const Icon(Icons.chevron_left_rounded, color: Joy.textMuted),
              onTap: () => Navigator.pop(ctx, t),
            ),
          const Divider(),
          ListTile(
            key: const Key('tpl-blank'),
            contentPadding: EdgeInsets.zero,
            leading: Container(width: 42, height: 42, decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.edit_outlined, color: Joy.textMuted)),
            title: const Text('من الصفر', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('اختر النوع والقيمة والشروط بنفسك', style: TextStyle(fontSize: 12, color: Joy.textMuted)),
            onTap: () => Navigator.pop(ctx, const OfferTemplate(id: '', name: '', kind: 'coupon', value: OfferValue(type: 'percent', amount: 10), days: 7)),
          ),
        ],
      ),
    ),
  );
  if (picked == null || !context.mounted) return;
  await openOfferEditor(context, biz, template: picked);
}

IconData _tplIcon(String kind) => switch (kind) { 'deal' => Icons.sell_outlined, 'checkin' => Icons.near_me_outlined, 'loyalty' => Icons.emoji_events_outlined, _ => Icons.confirmation_number_outlined };

Future<void> openOfferEditor(BuildContext context, Biz biz, {BizOffer? offer, OfferTemplate? template}) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .92),
      builder: (_) => _OfferEditor(biz: biz, offer: offer, template: template),
    );

class _OfferEditor extends ConsumerStatefulWidget {
  final Biz biz;
  final BizOffer? offer;
  final OfferTemplate? template;
  const _OfferEditor({required this.biz, this.offer, this.template});
  @override
  ConsumerState<_OfferEditor> createState() => _OfferEditorState();
}

class _OfferEditorState extends ConsumerState<_OfferEditor> {
  late final TextEditingController title, description, amount, minTotal, perUser, total, every, radius;
  late String kind, valueType;
  String? itemId;
  bool membersOnly = true, transferable = true, firstOrder = false, busy = false;
  DateTime? startsAt, endsAt;
  BizOffer? get o => widget.offer;
  OfferTemplate? get t => widget.template;

  static const kinds = [('deal', 'سعر خاص', Icons.sell_outlined), ('coupon', 'كوبون', Icons.confirmation_number_outlined), ('checkin', 'لمن هنا الآن', Icons.near_me_outlined), ('loyalty', 'مكافأة الرواد', Icons.emoji_events_outlined)];
  List<(String, String)> get valueTypes => switch (kind) {
        'deal' => const [('percent', 'نسبة ٪'), ('amount', 'مبلغ'), ('price', 'سعر ثابت لمنتج')],
        'loyalty' => const [('free_item', 'منتج مجاني'), ('percent', 'نسبة ٪'), ('amount', 'مبلغ')],
        _ => const [('percent', 'نسبة ٪'), ('amount', 'مبلغ'), ('free_item', 'منتج مجاني')],
      };

  @override
  void initState() {
    super.initState();
    final c = o?.conditions ?? t?.conditions ?? const {};
    kind = o?.kind ?? t?.kind ?? 'coupon';
    valueType = o?.value.type ?? t?.value.type ?? 'percent';
    final amt = o?.value.amount ?? t?.value.amount ?? 0;
    title = TextEditingController(text: o?.title ?? (t != null && t!.id.isNotEmpty ? _tplTitle(t!) : ''));
    description = TextEditingController(text: o?.description ?? '');
    amount = TextEditingController(text: amt == 0 ? '' : valueType == 'percent' ? '$amt' : _sar(amt));
    minTotal = TextEditingController(text: c['minTotal'] == null ? '' : _sar(_int(c['minTotal'])));
    perUser = TextEditingController(text: c['perUser']?.toString() ?? '');
    total = TextEditingController(text: c['total']?.toString() ?? '');
    every = TextEditingController(text: c['every']?.toString() ?? '10');
    radius = TextEditingController(text: c['radiusM']?.toString() ?? '300');
    firstOrder = c['firstOrder'] == true;
    itemId = o?.itemId;
    membersOnly = o?.membersOnly ?? t?.membersOnly ?? kind != 'deal';
    transferable = o?.transferable ?? t?.transferable ?? kind != 'loyalty';
    startsAt = o?.startsAt;
    endsAt = o?.endsAt ?? (t == null ? null : t!.hours != null ? DateTime.now().add(Duration(hours: t!.hours!)) : t!.days != null ? DateTime.now().add(Duration(days: t!.days!)) : null);
    if (!valueTypes.any((v) => v.$1 == valueType)) valueType = valueTypes.first.$1;
  }

  static String _tplTitle(OfferTemplate t) => switch (t.id) { 'happy_hour' => 'ساعة هادئة · خصم ${t.value.amount}٪', 'first_order' => 'خصم ${t.value.amount}٪ على أول طلب', 'here_now' => 'خصم ${t.value.amount}٪ لمن هنا الآن', 'product_week' => 'منتج الأسبوع', 'limited_coupon' => 'كوبون ${_sar(t.value.amount)} ر.س لأول ${t.conditions['total'] ?? 50}', 'loyalty' => 'مكافأة الرواد', _ => t.name };
  static String _sar(int h) => h % 100 == 0 ? '${h ~/ 100}' : (h / 100).toStringAsFixed(2);
  static int _int(Object? v) => v is int ? v : int.tryParse(v.toString()) ?? 0;

  @override
  void dispose() {
    for (final c in [title, description, amount, minTotal, perUser, total, every, radius]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get needsItem => valueType == 'price' || valueType == 'free_item';

  @override
  Widget build(BuildContext context) {
    final items = widget.biz.items.where((i) => i.kind == 'product' || i.kind == 'service' || i.kind == 'clinic').toList();
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(o == null ? 'عرض جديد' : 'تعديل العرض', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        if (t != null && t!.id.isNotEmpty) Text('قالب: ${t!.name}', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final (k, label, icon) in kinds)
            ChoiceChip(
              key: Key('kind-$k'),
              avatar: Icon(icon, size: 16, color: kind == k ? Joy.primaryOn : Joy.textMuted),
              label: Text(label, style: TextStyle(color: kind == k ? Joy.primaryOn : Joy.text)),
              selected: kind == k,
              showCheckmark: false,
              selectedColor: Joy.primary,
              onSelected: o != null
                  ? null
                  : (_) => setState(() {
                        kind = k;
                        if (!valueTypes.any((v) => v.$1 == valueType)) valueType = valueTypes.first.$1;
                        membersOnly = k != 'deal';
                        transferable = k != 'loyalty';
                      }),
            ),
        ]),
        const SizedBox(height: 6),
        Text(switch (kind) { 'deal' => 'سعر يظهر مباشرة على القائمة ويُطبّق على كل من يطلب (أو الأعضاء فقط).', 'coupon' => 'خصم للأعضاء يظهر في محفظتهم ويُطبّق تلقائياً على الطلب.', 'checkin' => 'يُفتح فقط لمن يطلب وهو داخل نطاق المكان.', _ => 'مكافأة تُمنح تلقائياً كل عدد من الطلبات المستلمة.' }, style: const TextStyle(color: Joy.textMuted, fontSize: 12, height: 1.5)),
        const SizedBox(height: 10),
        TextField(key: const Key('offer-title'), controller: title, decoration: const InputDecoration(labelText: 'العنوان', hintText: 'خصم 20٪ على كل المشروبات')),
        const SizedBox(height: 10),
        TextField(controller: description, maxLines: 2, decoration: const InputDecoration(labelText: 'وصف قصير (اختياري)')),
        const SizedBox(height: 12),
        const Text('القيمة', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final (v, label) in valueTypes)
            ChoiceChip(key: Key('value-$v'), label: Text(label, style: TextStyle(color: valueType == v ? Joy.primaryOn : Joy.text)), selected: valueType == v, showCheckmark: false, selectedColor: Joy.primary, onSelected: (_) => setState(() => valueType = v)),
        ]),
        if (valueType != 'free_item') ...[
          const SizedBox(height: 8),
          TextField(key: const Key('offer-amount'), controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: switch (valueType) { 'percent' => 'النسبة ٪', 'amount' => 'قيمة الخصم بالريال', _ => 'السعر الخاص بالريال' })),
        ],
        if (needsItem || kind == 'deal') ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            key: const Key('offer-item'),
            initialValue: itemId,
            decoration: InputDecoration(labelText: needsItem ? 'المنتج' : 'المنتج (اختياري: كل القائمة إن تُرك)'),
            items: [
              if (!needsItem) const DropdownMenuItem<String?>(value: null, child: Text('كل القائمة')),
              for (final it in items) DropdownMenuItem<String?>(value: it.id, child: Text('${it.title} · ${money(it.price)}', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => itemId = v),
          ),
        ],
        const SizedBox(height: 12),
        const Text('الشروط', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        if (kind == 'loyalty')
          TextField(key: const Key('offer-every'), controller: every, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'كل كم طلباً مستلماً؟ (2 إلى 50)'))
        else ...[
          Row(children: [
            Expanded(child: TextField(key: const Key('offer-min'), controller: minTotal, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'حد أدنى (ر.س)'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(key: const Key('offer-peruser'), controller: perUser, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'مرات لكل عضو'))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(key: const Key('offer-total'), controller: total, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'عدد إجمالي (اختياري)'))),
            if (kind == 'checkin') ...[
              const SizedBox(width: 8),
              Expanded(child: TextField(key: const Key('offer-radius'), controller: radius, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'نطاق المكان (متر)'))),
            ],
          ]),
          SwitchListTile(contentPadding: EdgeInsets.zero, value: firstOrder, onChanged: (v) => setState(() => firstOrder = v), title: const Text('لأول طلب من الدائرة فقط', style: TextStyle(fontSize: 14))),
        ],
        if (kind != 'loyalty') SwitchListTile(key: const Key('offer-members'), contentPadding: EdgeInsets.zero, value: membersOnly, onChanged: (v) => setState(() => membersOnly = v), title: const Text('للأعضاء فقط', style: TextStyle(fontSize: 14)), subtitle: Text(membersOnly ? 'يراه الجميع ويستخدمه من انضم إلى الدائرة' : 'يستخدمه أي زائر يطلب من الدائرة', style: const TextStyle(fontSize: 11.5))),
        if (kind == 'coupon' || kind == 'checkin') SwitchListTile(contentPadding: EdgeInsets.zero, value: transferable, onChanged: (v) => setState(() => transferable = v), title: const Text('يمكن إرساله لصديق', style: TextStyle(fontSize: 14))),
        const SizedBox(height: 8),
        const Text('المدة', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        if (kind != 'loyalty' || endsAt != null)
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (label, d) in [('ساعتان', const Duration(hours: 2)), ('اليوم', null), ('3 أيام', const Duration(days: 3)), ('أسبوع', const Duration(days: 7)), ('شهر', const Duration(days: 30))])
              ActionChip(
                key: Key('dur-$label'),
                label: Text(label, style: const TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() {
                  final now = DateTime.now();
                  startsAt = null;
                  endsAt = d == null ? DateTime(now.year, now.month, now.day, 23, 59) : now.add(d);
                }),
              ),
          ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('offer-start'),
              onPressed: () async {
                final now = DateTime.now();
                final d = await showDatePicker(context: context, firstDate: DateTime(now.year, now.month, now.day), lastDate: now.add(const Duration(days: 365)), initialDate: startsAt ?? now, helpText: 'يبدأ العرض');
                if (d == null || !context.mounted) return;
                final tm = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(startsAt ?? now));
                setState(() => startsAt = DateTime(d.year, d.month, d.day, tm?.hour ?? 0, tm?.minute ?? 0));
              },
              icon: const Icon(Icons.play_arrow_outlined, size: 18),
              label: Text(startsAt == null ? 'يبدأ الآن' : 'يبدأ ${_when(startsAt!)}', overflow: TextOverflow.ellipsis),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('offer-end'),
              onPressed: () async {
                final now = DateTime.now();
                final d = await showDatePicker(context: context, firstDate: DateTime(now.year, now.month, now.day), lastDate: now.add(const Duration(days: 90)), initialDate: endsAt ?? now.add(const Duration(days: 7)), helpText: 'ينتهي العرض');
                if (d == null || !context.mounted) return;
                final tm = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(endsAt ?? DateTime(now.year, now.month, now.day, 23, 59)));
                setState(() => endsAt = DateTime(d.year, d.month, d.day, tm?.hour ?? 23, tm?.minute ?? 59));
              },
              icon: const Icon(Icons.event_outlined, size: 18),
              label: Text(endsAt == null ? (kind == 'loyalty' ? 'بلا نهاية' : 'حدّد النهاية') : 'ينتهي ${_when(endsAt!)}', overflow: TextOverflow.ellipsis),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        SizedBox(width: double.infinity, child: FilledButton.icon(key: const Key('offer-save'), onPressed: busy ? null : _save, icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check_rounded), label: Text(o == null ? 'نشر العرض' : 'حفظ'))),
        if (o == null) const Padding(padding: EdgeInsets.only(top: 6), child: Text('يصل التنبيه لأعضاء دائرتك حسب اختيارهم، ويظهر العرض في محفظتهم.', style: TextStyle(color: Joy.textMuted, fontSize: 11.5))),
      ]),
    );
  }

  int _halalas(String s) => ((double.tryParse(s.trim().replaceAll('٫', '.')) ?? 0) * 100).round();

  /// «اليوم 23:59» أو «غداً 09:00» أو «3 أكتوبر».
  static String _when(DateTime t) {
    final d = dayLabel(t);
    if (d == 'اليوم' || d == 'غداً') return '$d ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return shortDate(t);
  }

  Future<void> _save() async {
    if (title.text.trim().length < 2) {
      toast(context, 'اكتب عنوان العرض', error: true);
      return;
    }
    if (needsItem && itemId == null) {
      toast(context, 'اختر المنتج', error: true);
      return;
    }
    final amt = valueType == 'percent' ? (int.tryParse(amount.text.trim()) ?? 0) : _halalas(amount.text);
    if (valueType != 'free_item' && amt <= 0) {
      toast(context, 'اكتب قيمة الخصم', error: true);
      return;
    }
    if (kind != 'loyalty' && endsAt == null) {
      toast(context, 'حدّد موعد انتهاء العرض', error: true);
      return;
    }
    final conditions = <String, dynamic>{
      if (kind == 'loyalty') 'every': int.tryParse(every.text.trim()) ?? 10,
      if (kind != 'loyalty' && _halalas(minTotal.text) > 0) 'minTotal': _halalas(minTotal.text),
      if (kind != 'loyalty' && (int.tryParse(perUser.text.trim()) ?? 0) > 0) 'perUser': int.tryParse(perUser.text.trim()),
      if (kind != 'loyalty' && (int.tryParse(total.text.trim()) ?? 0) > 0) 'total': int.tryParse(total.text.trim()),
      if (kind == 'checkin') 'radiusM': int.tryParse(radius.text.trim()) ?? 300,
      if (kind != 'loyalty' && firstOrder) 'firstOrder': true,
    };
    final body = <String, dynamic>{
      'kind': kind,
      'title': title.text.trim(),
      'description': description.text.trim(),
      'value': {'type': valueType, if (valueType != 'free_item') 'amount': amt},
      'itemId': itemId,
      'conditions': conditions,
      'membersOnly': kind == 'loyalty' ? true : membersOnly,
      'transferable': kind == 'loyalty' ? false : transferable,
      'startsAt': startsAt?.toUtc().toIso8601String(),
      'endsAt': endsAt?.toUtc().toIso8601String(),
      if (t != null && t!.id.isNotEmpty) 'template': t!.id,
    };
    setState(() => busy = true);
    try {
      final api = ref.read(apiClientProvider);
      if (o == null) {
        await api.createOffer(widget.biz.id, body);
      } else {
        await api.updateOffer(widget.biz.id, o!.id, body);
      }
      invalidateBizAll(ref, widget.biz.id);
      if (mounted) {
        Navigator.pop(context);
        toast(context, o == null ? 'نُشر العرض ووصل أعضاء دائرتك' : 'حُفظ العرض');
      }
    } catch (e) {
      if (mounted) toast(context, ownerErrText(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}
