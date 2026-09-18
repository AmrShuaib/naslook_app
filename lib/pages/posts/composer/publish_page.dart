import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../api/biz_api.dart';
import '../../../api/biz_models.dart';
import '../../../api/chat_tools_api.dart';
import '../../../api/client.dart' show mediaUrl;
import '../../../api/commerce_api.dart';
import '../../../api/commerce_models.dart';
import '../../../api/community_api.dart';
import '../../../api/posts_api.dart';
import '../../../core/app_theme.dart';
import '../../../core/media/filters.dart';
import '../../../state/app_state.dart';
import '../../../state/biz_providers.dart';
import '../../../state/posts_providers.dart';
import '../../../ui/widgets.dart';
import '../../market/market_page.dart' show invalidateMarket;
import '../overlay_canvas.dart';
import 'composer_draft.dart';
import 'text_board.dart' show contrastTextColor;

/// نتيجة النشر: المنشور على الخريطة (إن كانت الوجهة الخريطة) وأين نُشر.
class PublishOutcome {
  final Destination destination;
  final MapPost? post;
  final String? bizId;
  final String? listingId;
  const PublishOutcome(this.destination, {this.post, this.bizId, this.listingId});
}

/// دوائر يستطيع المستخدم النشر فيها: التي يملكها أو يديرها والتي انضم إليها.
final publishCirclesProvider = FutureProvider<List<Biz>>((ref) async {
  final api = ref.watch(apiClientProvider);
  final mine = (await ref.watch(myBusinessesProvider.future)).circles;
  List<Biz> joined = const [];
  try { joined = await api.businessCircles(following: true); } catch (_) { joined = const []; }
  final seen = <String>{};
  return [for (final b in [...mine, ...joined]) if (seen.add(b.id)) b];
});

/// شاشة النشر: تجيب عن ثلاثة أسئلة فقط: ماذا أقول، أين يظهر، كم يبقى. التفاصيل الاحترافية مطوية، والمسودة تُحفظ تلقائياً.
/// اختيار «السوق» يحوّلها إلى نموذج عرض قصير، واختيار «دائرة» يعرض دوائرك. تعيد [PublishOutcome] أو null عند الرجوع.
class PublishPage extends ConsumerStatefulWidget {
  final ComposerDraft draft;
  const PublishPage({super.key, required this.draft});
  @override
  ConsumerState<PublishPage> createState() => _PublishPageState();
}

class _PublishPageState extends ConsumerState<PublishPage> {
  ComposerDraft get d => widget.draft;
  late final caption = TextEditingController(text: d.caption);
  late final lstTitle = TextEditingController(text: d.listingTitle.isNotEmpty ? d.listingTitle : d.title);
  late final lstPrice = TextEditingController(text: d.listingPrice.isNotEmpty ? d.listingPrice : d.price);
  bool busy = false;
  bool published = false;

  bool get editingExisting => d.editing != null;

  @override
  void dispose() {
    _syncDraft();
    if (!published && !editingExisting) _saveDraft();
    caption.dispose();
    lstTitle.dispose();
    lstPrice.dispose();
    super.dispose();
  }

  void _syncDraft() {
    d.caption = caption.text.trim();
    d.listingTitle = lstTitle.text.trim();
    d.listingPrice = lstPrice.text.trim();
  }

  /// المسودة النصية فقط (بلا وسائط): تُستعاد عند فتح المحرّر التالي
  Future<void> _saveDraft() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(composerDraftKey, '${d.destination.name}|${d.ttlHours}|${d.tag}|${d.ctaType ?? ''}|${d.caption.replaceAll('|', ' ')}');
    } catch (_) { /* لا شيء */ }
  }

  static Future<void> clearDraft() async {
    try { (await SharedPreferences.getInstance()).remove(composerDraftKey); } catch (_) { /* لا شيء */ }
  }

  // ---------------------------------------------------------------- النشر
  Future<void> _publish() async {
    _syncDraft();
    if (d.destination == Destination.circle && d.circleId == null) return toast(context, 'اختر الدائرة التي تنشر فيها', error: true);
    if (d.destination == Destination.market) {
      if (d.listingTitle.isEmpty) return toast(context, 'اكتب عنوان العرض', error: true);
      if (d.isText || d.isVideo && d.video == null) return toast(context, 'عرض السوق يحتاج صورة واحدة على الأقل', error: true);
    }
    if (d.destination == Destination.map && d.isText && d.overlays.every((o) => o.isSticker) && d.caption.isEmpty && d.voice == null) return toast(context, 'أضف نصاً أو تعليقاً أو تسجيلاً', error: true);
    if (d.ctaType == 'link' && d.ctaValue.isNotEmpty && !d.ctaValue.startsWith('http')) return toast(context, 'الرابط يجب أن يبدأ بـ https://', error: true);
    setState(() => busy = true);
    try {
      final api = ref.read(apiClientProvider);
      // ١. الوسائط: الغلاف يُخبز بالفلتر والقصّ، وبقية اللقطات كما هي، والفيديو والصوت كما هما
      final urls = <String>[];
      final cover = d.coverShot;
      if (cover != null) {
        final baked = await bakePhoto(cover.bytes, filter: filterById(d.filter), adjust: d.adjust, frame: d.frame, name: cover.name, mime: cover.mime);
        urls.add((await api.uploadMedia(baked.bytes, contentType: baked.mime, fileName: baked.name)).url);
        for (final (i, s) in d.shots.indexed) {
          if (i == d.cover) continue;
          urls.add((await api.uploadMedia(s.bytes, contentType: s.mime, fileName: s.name)).url);
        }
      }
      String? videoUrl;
      if (d.video != null) videoUrl = (await api.uploadMedia(d.video!.bytes, contentType: d.video!.mime, fileName: d.video!.name)).url;
      String? audioUrl;
      final v = d.voice;
      if (v != null) audioUrl = (await api.uploadMedia(v.bytes, contentType: v.mime, fileName: v.name)).url;
      // ٢. الوجهة
      PublishOutcome out;
      switch (d.destination) {
        case Destination.map:
          final mediaUrl = d.isVideo ? (videoUrl ?? d.editing?.mediaUrl) : d.isText ? null : (urls.isNotEmpty ? urls.first : d.editing?.mediaUrl);
          final fields = {
            'caption': d.caption, 'overlays': [for (final o in d.overlays) o.toJson()], 'bg': d.board, 'placeName': d.placeName, 'ttlHours': d.ttlHours,
            'tag': d.tag, 'title': d.title, 'price': d.price.isEmpty ? null : ((double.tryParse(d.price.replaceAll('،', '.')) ?? 0) * 100).round(),
            'cta': d.ctaType == null || (d.ctaType != 'chat' && d.ctaValue.isEmpty) ? null : {'type': d.ctaType, 'value': d.ctaValue, 'label': d.ctaLabel},
            'audioUrl': audioUrl ?? (v == null ? null : d.editing?.audioUrl), 'audioSec': v?.duration.inSeconds ?? (v == null ? null : d.editing?.audioSec),
          };
          final MapPost post;
          if (editingExisting) {
            post = await api.updatePost(d.editing!.id, {...fields, if (urls.isNotEmpty || videoUrl != null) 'mediaUrl': mediaUrl});
          } else {
            post = await api.createPost({'kind': d.kind, 'mediaUrl': mediaUrl, 'lat': d.lat, 'lng': d.lng, 'durationSec': d.isVideo ? d.videoSec : null, ...fields});
          }
          invalidatePosts(ref);
          out = PublishOutcome(Destination.map, post: post);
        case Destination.circle:
          final text = [d.caption, ...d.overlays.where((o) => !o.isSticker && o.font != 'badge').map((o) => o.text)].where((s) => s.isNotEmpty).join('\n');
          final topic = switch (d.template) { 'question' => 'question', 'alert' => 'alert', _ => urls.isNotEmpty && text.isEmpty ? 'photo' : 'general' };
          final p = await api.communityPost(d.circleId!, topic: topic, text: text, images: [...urls, if (videoUrl != null) videoUrl], audio: audioUrl, audioMs: v?.duration.inMilliseconds);
          out = PublishOutcome(Destination.circle, bizId: d.circleId, listingId: p.id);
        case Destination.market:
          final l = await api.createListing({
            'title': d.listingTitle, 'description': d.caption, 'kind': d.listingKind, 'category': d.listingCategory, 'price': ((double.tryParse(d.listingPrice.replaceAll('،', '.')) ?? 0) * 100).round(),
            'delivery': d.delivery, 'images': urls, if (urls.isNotEmpty) 'imageUrl': urls.first, 'lat': d.lat, 'lng': d.lng, 'placeName': d.placeName, 'status': 'active',
          });
          invalidateMarket(ref);
          out = PublishOutcome(Destination.market, listingId: l.id);
      }
      published = true;
      await clearDraft();
      if (!mounted) return;
      toast(context, switch (d.destination) { Destination.map => editingExisting ? 'حُفظت التعديلات' : 'نُشر على الخريطة', Destination.circle => 'نُشر في مجتمع ${d.circleName ?? 'الدائرة'}', Destination.market => 'نُشر عرضك في السوق' });
      Navigator.pop(context, out);
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        final s = e.toString();
        toast(context, s.contains('suspended') ? 'حسابك موقوف ولا يمكنه النشر' : s.contains('banned-words') ? 'النص يحتوي كلمة غير مسموحة' : s.contains('contact-in-text') ? 'لا تكتب أرقام جوال أو روابط في العرض' : s, error: true);
      }
    }
  }

  // ---------------------------------------------------------------- التفاصيل الاحترافية
  Future<void> _proSheet() async {
    final title = TextEditingController(text: d.title), price = TextEditingController(text: d.price), ctaValue = TextEditingController(text: d.ctaValue), ctaLabel = TextEditingController(text: d.ctaLabel);
    var tag = d.tag; var ctaType = d.ctaType; var ttl = d.ttlHours;
    await showModalBottomSheet<void>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [Expanded(child: Text('تفاصيل احترافية', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17))), Text('اختيارية · تظهر على المنشور', style: TextStyle(color: Joy.textMuted, fontSize: 12.5))]),
          const SizedBox(height: 14),
          const Text('نوع المنشور', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [for (final e in postTags.entries) ChoiceChip(key: Key('tag-${e.key}'), label: Text(e.value), selected: tag == e.key, showCheckmark: false, selectedColor: Joy.primary, labelStyle: TextStyle(color: tag == e.key ? Colors.white : Joy.text, fontSize: 13), side: BorderSide.none, onSelected: (_) => setSheet(() => tag = e.key))]),
          const SizedBox(height: 14),
          TextField(key: const Key('pro-title'), controller: title, decoration: const InputDecoration(labelText: 'العنوان', hintText: 'مثال: كيك تخرج بتصميم خاص')),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(key: const Key('pro-price'), controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'السعر', suffixText: 'ر.س'))),
            const SizedBox(width: 10),
            Expanded(child: DropdownButtonFormField<int>(key: const Key('pro-ttl'), initialValue: ttl, decoration: const InputDecoration(labelText: 'ينتهي بعد'), items: [for (final (h, l) in postTtlOptions) DropdownMenuItem(value: h, child: Text(l))], onChanged: (v) => setSheet(() => ttl = v ?? 24))),
          ]),
          const SizedBox(height: 14),
          const Text('زر الإجراء', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ChoiceChip(key: const Key('cta-none'), label: const Text('بدون'), selected: ctaType == null, showCheckmark: false, selectedColor: Joy.primary, labelStyle: TextStyle(color: ctaType == null ? Colors.white : Joy.text, fontSize: 13), side: BorderSide.none, onSelected: (_) => setSheet(() => ctaType = null)),
            for (final e in postCtaTypes.entries) ChoiceChip(key: Key('cta-${e.key}'), label: Text(e.value), selected: ctaType == e.key, showCheckmark: false, selectedColor: Joy.primary, labelStyle: TextStyle(color: ctaType == e.key ? Colors.white : Joy.text, fontSize: 13), side: BorderSide.none, onSelected: (_) => setSheet(() => ctaType = e.key)),
          ]),
          if (ctaType != null && ctaType != 'chat') Padding(padding: const EdgeInsets.only(top: 10), child: TextField(key: const Key('cta-value'), controller: ctaValue, keyboardType: ctaType == 'link' ? TextInputType.url : (ctaType == 'whatsapp' || ctaType == 'call') ? TextInputType.phone : TextInputType.text, decoration: InputDecoration(labelText: switch (ctaType) { 'link' => 'الرابط', 'whatsapp' => 'رقم واتساب', 'call' => 'رقم الهاتف', 'biz' => 'معرّف الدائرة', _ => 'معرّف العرض' }, hintText: switch (ctaType) { 'link' => 'https://…', 'whatsapp' || 'call' => '05xxxxxxxx', _ => '' }))),
          if (ctaType != null) Padding(padding: const EdgeInsets.only(top: 10), child: TextField(controller: ctaLabel, decoration: const InputDecoration(labelText: 'نص الزر (اختياري)'))),
          const SizedBox(height: 6),
          const Text('«مراسلة» يفتح محادثة معك داخل ناس لايف، ولا يحتاج رقماً', style: TextStyle(color: Joy.textMuted, fontSize: 12)),
          const SizedBox(height: 16),
          FilledButton(key: const Key('pro-save'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: Joy.text), onPressed: () => Navigator.pop(ctx), child: const Text('حفظ والعودة')),
        ])),
      )),
    );
    if (!mounted) return;
    setState(() {
      d.tag = tag; d.ctaType = ctaType; d.ttlHours = ttl;
      d.title = title.text.trim(); d.price = price.text.trim(); d.ctaValue = ctaValue.text.trim(); d.ctaLabel = ctaLabel.text.trim();
    });
  }

  Future<void> _editPlace() async {
    final v = await askText(context, title: 'اسم المكان', hint: 'الحي أو المكان (اختياري)', initial: d.placeName, confirm: 'حفظ', maxLines: 1);
    if (v == null || !mounted) return;
    setState(() => d.placeName = v.trim());
  }

  // ---------------------------------------------------------------- البناء
  @override
  Widget build(BuildContext context) {
    final me = ref.watch(appStateProvider.select((s) => s.user));
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: Text(editingExisting ? 'حفظ التعديلات' : 'نشر'), leading: IconButton(key: const Key('pub-back'), icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.pop(context))),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
        // المعاينة والتعليق
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _thumb(),
          const SizedBox(width: 12),
          Expanded(child: TextField(key: const Key('pub-caption'), controller: caption, maxLines: 3, maxLength: 500, buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null, decoration: const InputDecoration(labelText: 'تعليق (اختياري)', hintText: 'اكتب شيئاً قصيراً…', alignLabelWithHint: true))),
        ]),
        const SizedBox(height: 20),
        if (!editingExisting) ...[
          const Text('أين يظهر؟', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
          const SizedBox(height: 10),
          Row(children: [
            _dest(Destination.map, Icons.map_outlined, 'الخريطة', 'عند موقعك'),
            const SizedBox(width: 10),
            _dest(Destination.circle, Icons.storefront_outlined, 'دائرة', d.circleName ?? 'اختر دائرة'),
            const SizedBox(width: 10),
            _dest(Destination.market, Icons.shopping_bag_outlined, 'السوق', 'كعرض للبيع', enabled: !d.isText),
          ]),
          const SizedBox(height: 20),
        ],
        switch (d.destination) {
          Destination.map => _mapOptions(me?.nickname ?? ''),
          Destination.circle => _circleOptions(),
          Destination.market => _marketOptions(),
        },
        const SizedBox(height: 24),
        FilledButton(key: const Key('pub-go'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)), onPressed: busy ? null : _publish, child: Text(busy ? 'جارٍ النشر…' : editingExisting ? 'حفظ' : switch (d.destination) { Destination.map => 'نشر الآن', Destination.circle => 'نشر في الدائرة', Destination.market => 'نشر العرض' })),
        const SizedBox(height: 8),
        if (!editingExisting) const Center(child: Text('يُحفظ تعليقك وإعداداتك تلقائياً كمسودة حتى تنشر', style: TextStyle(color: Joy.textMuted, fontSize: 12))),
      ]),
    );
  }

  Widget _thumb() {
    Widget inner;
    if (d.isText) {
      inner = Container(color: colorFromHex(d.board, Colors.white), padding: const EdgeInsets.all(6), alignment: Alignment.center, child: Text(d.overlays.where((o) => !o.isSticker && o.font != 'badge').map((o) => o.text).join(' '), maxLines: 4, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(color: colorFromHex(contrastTextColor(d.board)), fontSize: 10, fontWeight: FontWeight.w700)));
    } else if (d.isVideo) {
      inner = const ColoredBox(color: Color(0xFF14181C), child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 32));
    } else if (d.coverShot != null) {
      final cf = colorFilterFor(filterById(d.filter), d.adjust);
      Widget img = Image.memory(d.coverShot!.bytes, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF14181C)));
      if (cf != null) img = ColorFiltered(colorFilter: cf, child: img);
      inner = img;
    } else if (d.editing?.mediaUrl != null) {
      inner = Image.network(mediaUrl(d.editing!.mediaUrl!), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF14181C)));
    } else {
      inner = const ColoredBox(color: Color(0xFF14181C));
    }
    return Stack(children: [
      Container(width: 76, height: 108, clipBehavior: Clip.antiAlias, decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: Joy.surface2), child: inner),
      Positioned(bottom: 6, right: 6, child: Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(999)), child: Text(d.isText ? 'نص' : d.isVideo ? 'فيديو' : d.shots.length > 1 ? '${d.shots.length} صور' : 'صورة', style: const TextStyle(color: Colors.white, fontSize: 10.5)))),
      if (d.voice != null) const Positioned(top: 6, right: 6, child: Icon(Icons.mic_rounded, size: 16, color: Colors.white)),
    ]);
  }

  Widget _dest(Destination v, IconData icon, String label, String sub, {bool enabled = true}) {
    final on = d.destination == v;
    return Expanded(
      child: InkWell(
        key: Key('dest-${v.name}'),
        onTap: enabled ? () => setState(() => d.destination = v) : () => toast(context, 'عرض السوق يحتاج صورة؛ التقط صورة أولاً'),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 84,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: on ? Joy.primary : Joy.line, width: 2), color: on ? Joy.primarySoft : Joy.surface),
          child: Opacity(opacity: enabled ? 1 : .45, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 22, color: on ? Joy.primary : Joy.textMuted),
            const SizedBox(height: 3),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
            Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 11)),
          ])),
        ),
      ),
    );
  }

  Widget _mapOptions(String nick) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('المدة على الخريطة', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [for (final (h, l) in postTtlOptions) ChoiceChip(key: Key('ttl-$h'), label: Text(l), selected: d.ttlHours == h, showCheckmark: false, selectedColor: Joy.primary, labelStyle: TextStyle(color: d.ttlHours == h ? Colors.white : Joy.text, fontSize: 13), side: BorderSide.none, onSelected: (_) => setState(() => d.ttlHours = h))]),
        const SizedBox(height: 18),
        JoyCard(
          key: const Key('pub-pro'), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), onTap: _proSheet,
          child: Row(children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: Joy.sunSoft, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.bolt_rounded, color: Joy.sunText, size: 20)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('تفاصيل احترافية', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              Text(d.hasPro ? [postTags[d.tag], if (d.title.isNotEmpty) d.title, if (d.price.isNotEmpty) '${d.price} ر.س', if (d.ctaType != null) postCtaTypes[d.ctaType]].join(' · ') : 'نوع المنشور، سعر، زر إجراء', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
            ])),
            const Icon(Icons.chevron_left_rounded, color: Joy.textMuted),
          ]),
        ),
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.place_outlined, size: 18, color: Joy.textMuted), const SizedBox(width: 8),
          Expanded(child: Text(d.placeName.isNotEmpty ? d.placeName : 'عند موقعك الحالي', style: const TextStyle(fontSize: 13.5))),
          TextButton(key: const Key('pub-place'), onPressed: _editPlace, child: const Text('تغيير')),
        ]),
      ]);

  Widget _circleOptions() {
    final circles = ref.watch(publishCirclesProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('في أي دائرة؟', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
      const SizedBox(height: 8),
      circles.when(
        data: (list) => list.isEmpty
            ? const Text('لم تنضم إلى أي دائرة بعد. انضم إلى دائرة من الخريطة أو قائمة الدوائر ثم عد للنشر فيها.', style: TextStyle(color: Joy.textMuted, fontSize: 13))
            : Wrap(spacing: 8, runSpacing: 8, children: [
                for (final b in list)
                  ChoiceChip(
                    key: Key('circle-${b.id}'), label: Text(b.nameAr.isNotEmpty ? b.nameAr : b.name), selected: d.circleId == b.id, showCheckmark: false, selectedColor: Joy.primary,
                    labelStyle: TextStyle(color: d.circleId == b.id ? Colors.white : Joy.text, fontSize: 13), side: BorderSide.none,
                    onSelected: (_) => setState(() { d.circleId = b.id; d.circleName = b.nameAr.isNotEmpty ? b.nameAr : b.name; }),
                  ),
              ]),
        loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))),
        error: (e, _) => ErrorState(e, onRetry: () => ref.invalidate(publishCirclesProvider)),
      ),
      const SizedBox(height: 10),
      const Text('يُنشر في مساحة مجتمع الدائرة بالصور والتعليق والتسجيل الصوتي، ويُخطر أعضاؤها حسب إعداداتهم.', style: TextStyle(color: Joy.textMuted, fontSize: 12.5)),
    ]);
  }

  Widget _marketOptions() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (d.shots.length > 1) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text('${d.shots.length} من 8 صور · الأولى هي الغلاف', style: const TextStyle(color: Joy.textMuted, fontSize: 12))),
        TextField(key: const Key('lst-title'), controller: lstTitle, decoration: const InputDecoration(labelText: 'العنوان', hintText: 'مثال: كيك تخرج بتصميم خاص'), maxLength: 100, buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(key: const Key('lst-price'), controller: lstPrice, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'السعر', suffixText: 'ر.س', hintText: '0 = مجاناً'))),
          const SizedBox(width: 10),
          Expanded(child: DropdownButtonFormField<String>(key: const Key('lst-kind'), initialValue: d.listingKind, decoration: const InputDecoration(labelText: 'النوع'), items: const [DropdownMenuItem(value: 'product', child: Text('منتج')), DropdownMenuItem(value: 'service', child: Text('خدمة'))], onChanged: (v) => setState(() => d.listingKind = v ?? 'product'))),
        ]),
        const SizedBox(height: 14),
        const Text('التصنيف', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final e in marketCategories.entries) ChoiceChip(key: Key('lst-cat-${e.key}'), label: Text(e.value), selected: d.listingCategory == e.key, showCheckmark: false, selectedColor: Joy.primary, labelStyle: TextStyle(color: d.listingCategory == e.key ? Colors.white : Joy.text, fontSize: 13), side: BorderSide.none, onSelected: (_) => setState(() => d.listingCategory = e.key))]),
        const SizedBox(height: 12),
        SwitchListTile(key: const Key('lst-delivery'), contentPadding: EdgeInsets.zero, value: d.delivery, onChanged: (v) => setState(() => d.delivery = v), title: const Text('التوصيل متاح', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)), subtitle: const Text('يظهر في الفلاتر ويطمئن المشتري', style: TextStyle(fontSize: 12))),
        const Text('المخزون والخيارات والمواعيد والكوبونات تضيفها متى شئت من صفحة العرض بعد النشر.', style: TextStyle(color: Joy.textMuted, fontSize: 12.5, height: 1.6)),
      ]);
}

const composerDraftKey = 'composer.draft.v2';

/// يقرأ المسودة النصية المحفوظة (إن وُجدت) ويطبّقها على مسودة جديدة.
Future<void> restoreComposerDraft(ComposerDraft d) async {
  try {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(composerDraftKey);
    if (s == null) return;
    final parts = s.split('|');
    if (parts.length < 5) return;
    d.destination = Destination.values.firstWhere((x) => x.name == parts[0], orElse: () => Destination.map);
    d.ttlHours = int.tryParse(parts[1]) ?? 24;
    d.tag = postTags.containsKey(parts[2]) ? parts[2] : 'moment';
    d.ctaType = parts[3].isEmpty ? null : parts[3];
    d.caption = parts.sublist(4).join('|');
  } catch (_) { /* لا شيء */ }
}
