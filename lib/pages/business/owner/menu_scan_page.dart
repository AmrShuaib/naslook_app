import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/biz_api.dart';
import '../../../api/biz_models.dart';
import '../../../api/chat_tools_api.dart';
import '../../../api/client.dart';
import '../../../api/commerce_models.dart';
import '../../../api/menu_scan_api.dart';
import '../../../core/app_theme.dart';
import '../../../core/media/pick_image.dart';
import '../../../state/app_state.dart';
import '../../../state/biz_providers.dart';
import '../../../ui/widgets.dart';
import 'business_editor.dart' show ownerErrText;

/// حد الصور في القراءة الواحدة كما في الخادم (LIMITS.maxImages).
const menuScanMaxImages = 4;

/// يحلّل «10:00, 16:30» (بأرقام عربية أو هندية وفواصل عربية) إلى أوقات يومية مطبّعة مرتبة بلا تكرار.
List<String> parseDailyTimes(String text) {
  const east = '٠١٢٣٤٥٦٧٨٩', persian = '۰۱۲۳۴۵۶۷۸۹';
  final latin = StringBuffer();
  for (final r in text.runes) {
    final ch = String.fromCharCode(r);
    final i = east.indexOf(ch), j = persian.indexOf(ch);
    latin.write(i >= 0 ? '$i' : j >= 0 ? '$j' : ch);
  }
  final out = <String>{};
  for (final t in latin.toString().split(RegExp(r'[,،;\s]+'))) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(t);
    if (m == null) continue;
    final h = int.parse(m[1]!), min = int.parse(m[2]!);
    if (h > 23 || min > 59) continue;
    out.add('${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}');
  }
  return out.toList()..sort();
}

/// مسودة صنف في شاشة المراجعة: يحرّرها المالك قبل الإضافة.
class _Draft {
  final int id;
  final String section;
  final TextEditingController title, price, description;
  bool selected = true;
  String? error;
  _Draft(this.id, ScannedItem it)
      : section = it.section,
        title = TextEditingController(text: it.title),
        // السعر غير المقروء يبقى فارغاً ليكتبه المالك، لا صفراً يبدو مقصوداً
        price = TextEditingController(text: it.priceKnown ? (it.price / 100).toStringAsFixed(it.price % 100 == 0 ? 0 : 2) : ''),
        description = TextEditingController(text: it.description);
  void dispose() {
    title.dispose();
    price.dispose();
    description.dispose();
  }
}

/// «صوّر المنيو»: يصوّر المالك قائمته فتُقرأ أصنافها، ثم يراجعها ويعدّلها ويختار ما يضاف إلى الكتالوج.
/// لا يُحفظ شيء قبل «أضف المحدد»، والإضافة عبر POST /biz/:id/items صنفاً صنفاً.
class MenuScanPage extends ConsumerStatefulWidget {
  final Biz biz;
  const MenuScanPage({super.key, required this.biz});
  @override
  ConsumerState<MenuScanPage> createState() => _MenuScanPageState();
}

class _MenuScanPageState extends ConsumerState<MenuScanPage> {
  final List<PickedImage> images = [];
  final List<_Draft> drafts = [];
  /// مسودات خرجت من القائمة: تُتلف متحكماتها مع الصفحة لا فوراً، فحقولها قد تكون ما زالت مرسومة في هذا الإطار.
  final List<_Draft> _gone = [];
  List<String> warnings = const [];
  final times = TextEditingController();
  late String kind = widget.biz.category.itemKinds.first;
  bool picking = false, scanning = false, adding = false, scanned = false;
  String? scanError;
  int _seq = 0, added = 0, addDone = 0, addTotal = 0;

  bool get slotted => kind == 'showtime' || kind == 'clinic';
  bool get clinicWords => widget.biz.category.clinicWords;
  int get selectedCount => drafts.where((d) => d.selected).length;

  @override
  void dispose() {
    times.dispose();
    for (final d in [...drafts, ..._gone]) {
      d.dispose();
    }
    super.dispose();
  }

  Future<void> _pick({required bool camera}) async {
    if (picking || images.length >= menuScanMaxImages) return;
    setState(() => picking = true);
    try {
      final img = await pickImage(camera: camera);
      if (img != null && mounted) setState(() => images.add(img));
    } catch (e) {
      if (mounted && !handlePermissionError(context, e)) toast(context, 'تعذّر فتح ${camera ? 'الكاميرا' : 'الصور'}', error: true);
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> _scan() async {
    if (images.isEmpty || scanning) return;
    setState(() {
      scanning = true;
      scanError = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final urls = <String>[];
      for (final img in images) {
        urls.add((await api.uploadMedia(img.bytes, contentType: img.mime, fileName: img.name)).url);
      }
      final res = await api.scanMenu(urls);
      if (!mounted) return;
      setState(() {
        _gone.addAll(drafts);
        drafts
          ..clear()
          ..addAll([for (final it in res.items) _Draft(_seq++, it)]);
        warnings = res.warnings;
        scanned = true;
        added = 0;
      });
    } catch (e) {
      if (mounted) setState(() => scanError = menuScanErrText(e));
    } finally {
      if (mounted) setState(() => scanning = false);
    }
  }

  String _addErr(Object e) {
    final s = e.toString();
    final code = e is ApiException ? (e.body?['error'] ?? '').toString() : '';
    if (code == 'banned-words') return 'في الاسم أو الوصف كلمة غير مسموحة';
    if (code == 'too-many') return 'بلغ الكتالوج حده الأقصى (300 صنف)';
    if (code == 'bad-days') return 'اختر يوم عمل واحداً على الأقل';
    if (e is ApiException && e.isNetwork) return 'تعذّر الاتصال';
    return ownerErrText(s);
  }

  Future<void> _add() async {
    if (adding) return;
    final chosen = drafts.where((d) => d.selected).toList();
    if (chosen.isEmpty) {
      toast(context, 'حدّد صنفاً واحداً على الأقل', error: true);
      return;
    }
    final dayTimes = parseDailyTimes(times.text);
    if (slotted && dayTimes.isEmpty) {
      toast(context, 'اكتب وقتاً يومياً واحداً على الأقل، مثل 10:00', error: true);
      return;
    }
    setState(() {
      adding = true;
      addDone = 0;
      addTotal = chosen.length;
      for (final d in drafts) {
        d.error = null;
      }
    });
    final api = ref.read(apiClientProvider);
    var ok = 0;
    String? stopped;
    for (final d in chosen) {
      final title = d.title.text.trim();
      final p = kind == 'info' ? 0 : parseSar(d.price.text);
      String? err;
      if (title.length < 2) {
        err = 'اكتب اسم الصنف';
      } else if (kind != 'info' && !RegExp(r'[0-9٠-٩۰-۹]').hasMatch(d.price.text)) {
        // سعر لم يُقرأ ولم يكتبه المالك: لا يُحفظ صنفاً مجانياً يُطلب. المجاني يُكتب 0 صراحة.
        err = 'اكتب السعر، أو 0 إن كان مجاناً';
      } else if (p <= 0 && (kind == 'showtime' || kind == 'room' || kind == 'car')) {
        err = 'اكتب سعراً صحيحاً';
      }
      if (err == null) {
        // القيم الافتراضية كما في محرّر الصنف: المالك يعدّل كل صنف لاحقاً من الكتالوج
        final meta = <String, dynamic>{
          if (kind == 'showtime') ...{'times': dayTimes, 'minutes': 120},
          if (kind == 'clinic') ...{'times': dayTimes, 'minutes': clinicWords ? 20 : 30, 'days': clinicWords ? [0, 1, 2, 3, 4] : [0, 1, 2, 3, 4, 5, 6]},
        };
        try {
          await api.createBizItem(widget.biz.id, {'kind': kind, 'title': title, 'description': d.description.text.trim(), 'price': p, 'meta': meta});
          ok++;
          drafts.remove(d);
          _gone.add(d);
        } catch (e) {
          err = _addErr(e);
          final code = e is ApiException ? (e.body?['error'] ?? '').toString() : '';
          // أخطاء لا تخص صنفاً بعينه: لا معنى لتكرارها على الباقي
          if (code == 'too-many' || code == 'forbidden' || code == 'suspended' || (e is ApiException && (e.isNetwork || e.statusCode == 401))) stopped = err;
        }
      }
      if (err != null) d.error = err;
      if (!mounted) return;
      setState(() => addDone++);
      if (stopped != null) break;
    }
    if (ok > 0) invalidateBizAll(ref, widget.biz.id);
    if (!mounted) return;
    setState(() {
      adding = false;
      added += ok;
    });
    final left = drafts.where((d) => d.selected).length;
    if (left == 0 && ok > 0 && drafts.isEmpty) {
      Navigator.pop(context);
      toast(context, 'أُضيف $ok إلى الكتالوج');
    } else if (stopped != null) {
      toast(context, ok > 0 ? 'أُضيف $ok ثم توقفت الإضافة: $stopped' : 'توقفت الإضافة: $stopped', error: true);
    } else if (left > 0) {
      toast(context, ok > 0 ? 'أُضيف $ok. لم يُضف $left، راجعها ثم أعد المحاولة.' : 'لم يُضف $left. راجعها ثم أعد المحاولة.', error: true);
    } else {
      toast(context, 'أُضيف $ok إلى الكتالوج');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Joy.bg,
      appBar: AppBar(title: Text(scanned ? 'راجع الأصناف' : 'صوّر المنيو')),
      body: SafeArea(child: scanned ? _review() : _capture()),
      // شريط الإضافة في bottomNavigationBar حتى تظهر رسائل الخطأ فوقه لا عليه
      bottomNavigationBar: scanned && drafts.isNotEmpty ? SafeArea(child: _addBar()) : null,
    );
  }

  // ---- المرحلة الأولى: اختيار الصور والقراءة
  Widget _capture() {
    final full = images.length >= menuScanMaxImages;
    return ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
      const Text('صوّر قائمة الأسعار أو اخترها من الصور. نقرأ الأصناف وأسعارها، ثم تراجعها وتختار ما يضاف.', style: TextStyle(fontSize: 14.5, height: 1.6)),
      const SizedBox(height: 12),
      // تنبيه الخصوصية قبل كل قراءة: الصور تغادر خوادمنا إلى مزوّد النموذج
      Container(
        key: const Key('menu-notice'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Joy.sunSoft, borderRadius: BorderRadius.circular(14)),
        child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline_rounded, size: 18, color: Joy.sunText),
          SizedBox(width: 8),
          Expanded(child: Text('تُرسل صور المنيو إلى Anthropic (مزوّد Claude) لقراءتها. لا تصوّر ما فيه بيانات شخصية.', style: TextStyle(color: Joy.sunText, fontSize: 13, height: 1.5))),
        ]),
      ),
      const SizedBox(height: 16),
      if (images.isNotEmpty)
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final (i, img) in images.indexed)
            Stack(key: Key('menu-image-$i'), clipBehavior: Clip.none, children: [
              ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.memory(img.bytes, width: 84, height: 84, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 84, height: 84, color: Joy.surface2, child: const Icon(Icons.image_outlined, color: Joy.textMuted)))),
              PositionedDirectional(
                top: -8, end: -8,
                child: IconButton.filled(
                  key: Key('menu-image-remove-$i'),
                  style: IconButton.styleFrom(backgroundColor: Joy.text, foregroundColor: Colors.white, minimumSize: const Size(26, 26), padding: EdgeInsets.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  onPressed: scanning ? null : () => setState(() => images.removeAt(i)),
                  icon: const Icon(Icons.close_rounded, size: 16),
                  tooltip: 'احذف الصورة',
                ),
              ),
            ]),
        ]),
      if (images.isNotEmpty) const SizedBox(height: 14),
      Row(children: [
        Expanded(child: OutlinedButton.icon(key: const Key('menu-pick-camera'), onPressed: full || scanning || picking ? null : () => _pick(camera: true), icon: const Icon(Icons.photo_camera_outlined), label: const Text('الكاميرا'))),
        const SizedBox(width: 10),
        Expanded(child: OutlinedButton.icon(key: const Key('menu-pick-gallery'), onPressed: full || scanning || picking ? null : () => _pick(camera: false), icon: const Icon(Icons.photo_library_outlined), label: const Text('الصور'))),
      ]),
      const SizedBox(height: 6),
      Text(full ? 'أربع صور على الأكثر في القراءة الواحدة.' : 'حتى أربع صور. صورة واضحة لكل صفحة من المنيو.', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
      if (scanError != null) ...[
        const SizedBox(height: 14),
        Container(
          key: const Key('menu-scan-error'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Joy.accentSoft, borderRadius: BorderRadius.circular(14)),
          child: Text(scanError!, style: const TextStyle(color: Joy.accent, fontWeight: FontWeight.w600)),
        ),
      ],
      const SizedBox(height: 18),
      FilledButton.icon(
        key: const Key('menu-scan-go'),
        onPressed: images.isEmpty || scanning ? null : _scan,
        icon: scanning ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.document_scanner_outlined),
        label: Text(scanning ? 'جارٍ قراءة المنيو…' : scanError != null ? 'أعد المحاولة' : 'اقرأ المنيو'),
      ),
      if (scanning) const Padding(padding: EdgeInsets.only(top: 8), child: Text('قد تأخذ القراءة دقيقة. ابقَ في هذه الصفحة.', textAlign: TextAlign.center, style: TextStyle(color: Joy.textMuted, fontSize: 12.5))),
    ]);
  }

  // ---- المرحلة الثانية: المراجعة والإضافة
  Widget _review() {
    if (drafts.isEmpty) {
      return EmptyState(
        icon: added > 0 ? Icons.check_circle_outline_rounded : Icons.search_off_rounded,
        title: added > 0 ? 'أُضيف $added إلى الكتالوج' : 'لم نجد أصنافاً',
        subtitle: added > 0 ? null : (warnings.isNotEmpty ? warnings.first : 'صوّر المنيو أقرب وبإضاءة أوضح.'),
        action: OutlinedButton(key: const Key('menu-rescan'), onPressed: () => setState(() { scanned = false; warnings = const []; }), child: const Text('صوّر من جديد')),
      );
    }
    final kinds = widget.biz.category.itemKinds;
    // قائمة مسطّحة: رأس لكل قسم عند أول ظهوره ثم أصنافه بترتيب القراءة
    final sections = <String>[];
    for (final d in drafts) {
      if (!sections.contains(d.section)) sections.add(d.section);
    }
    final rows = <Object>[];
    for (final s in sections) {
      if (s.isNotEmpty || sections.length > 1) rows.add(s);
      rows.addAll(drafts.where((d) => d.section == s));
    }
    final all = selectedCount == drafts.length;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: rows.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) return _reviewHead(kinds, all);
        final r = rows[i - 1];
        if (r is String) {
          return Padding(padding: const EdgeInsets.fromLTRB(4, 14, 4, 6), child: Text(r.isEmpty ? 'بلا قسم' : r, key: Key('menu-section-${r.isEmpty ? '-' : r}'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)));
        }
        return _row(r as _Draft);
      },
    );
  }

  Widget _addBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(color: Joy.surface, border: Border(top: BorderSide(color: Joy.line))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (adding) ...[
          LinearProgressIndicator(key: const Key('menu-add-progress'), value: addTotal == 0 ? null : addDone / addTotal),
          const SizedBox(height: 8),
        ],
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const Key('menu-add'),
            onPressed: adding || selectedCount == 0 ? null : _add,
            child: Text(adding ? 'جارٍ الإضافة $addDone من $addTotal…' : 'أضف المحدد ($selectedCount)'),
          ),
        ),
      ]),
    );
  }

  Widget _reviewHead(List<String> kinds, bool all) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('وجدنا ${drafts.length + added} صنفاً. عدّل ما يلزم، ثم أضف ما تريد. لا يُحفظ شيء قبل الإضافة.', style: const TextStyle(fontSize: 13.5, height: 1.5)),
      for (final w in warnings)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Joy.sunSoft, borderRadius: BorderRadius.circular(12)),
            child: Text(w, style: const TextStyle(color: Joy.sunText, fontSize: 12.5)),
          ),
        ),
      // الصالون والخدمات: الأصناف منتجات تُشترى أو خدمات بموعد (النوع لا يتغير بعد الإضافة)
      if (kinds.length > 1) ...[
        const SizedBox(height: 10),
        SegmentedButton<String>(
          key: const Key('menu-kind'),
          segments: [for (final k in kinds) ButtonSegment(value: k, label: Text(k == 'clinic' ? 'خدمات بموعد' : 'منتجات', key: Key('menu-kind-$k')))],
          selected: {kind},
          showSelectedIcon: false,
          onSelectionChanged: adding ? null : (v) => setState(() => kind = v.first),
        ),
      ],
      if (slotted) ...[
        const SizedBox(height: 10),
        Text(kind == 'showtime' ? 'أصناف هذه الدائرة تُحجز بموعد عرض. اكتب الأوقات اليومية مرة واحدة فتُطبَّق على كل ما تضيفه الآن، وتعدّل كل صنف لاحقاً من الكتالوج.' : 'هذه الأصناف تُحجز بموعد. اكتب الأوقات اليومية مرة واحدة فتُطبَّق على كل ما تضيفه الآن، وتعدّل أوقات كل صنف وأيامه لاحقاً من الكتالوج.', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5, height: 1.5)),
        const SizedBox(height: 6),
        TextField(key: const Key('menu-times'), controller: times, enabled: !adding, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'الأوقات اليومية', hintText: '10:00, 16:00, 19:00')),
      ],
      const SizedBox(height: 6),
      // Wrap لا Row: النص العربي العريض على جوال ضيق ينزل سطراً بدل أن يفيض
      Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
        TextButton(key: const Key('menu-select-all'), onPressed: adding || all ? null : () => setState(() { for (final d in drafts) { d.selected = true; } }), child: const Text('تحديد الكل')),
        TextButton(key: const Key('menu-select-none'), onPressed: adding || selectedCount == 0 ? null : () => setState(() { for (final d in drafts) { d.selected = false; } }), child: const Text('إلغاء التحديد')),
        Text('$selectedCount من ${drafts.length}', key: const Key('menu-selected-count'), style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
      ]),
    ]);
  }

  Widget _row(_Draft d) {
    final info = kind == 'info';
    return Padding(
      key: Key('menu-item-${d.id}'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(4, 8, 4, 10),
        decoration: BoxDecoration(color: Joy.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: d.error != null ? Joy.danger : Joy.line)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Checkbox(key: Key('menu-item-check-${d.id}'), value: d.selected, onChanged: adding ? null : (v) => setState(() => d.selected = v ?? false)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 3, child: TextField(key: Key('menu-item-title-${d.id}'), controller: d.title, enabled: !adding, maxLength: 100, decoration: const InputDecoration(labelText: 'الاسم', counterText: '', isDense: true))),
                if (!info) ...[
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: TextField(key: Key('menu-item-price-${d.id}'), controller: d.price, enabled: !adding, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'السعر (ر.س)', isDense: true))),
                ],
              ]),
              const SizedBox(height: 6),
              TextField(key: Key('menu-item-desc-${d.id}'), controller: d.description, enabled: !adding, maxLength: 500, decoration: const InputDecoration(labelText: 'الوصف (اختياري)', counterText: '', isDense: true)),
              if (d.error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('لم يُضف: ${d.error}', key: Key('menu-item-error-${d.id}'), style: const TextStyle(color: Joy.danger, fontSize: 12.5, fontWeight: FontWeight.w600))),
            ]),
          ),
          IconButton(key: Key('menu-item-remove-${d.id}'), onPressed: adding ? null : () => setState(() { drafts.remove(d); _gone.add(d); }), icon: const Icon(Icons.delete_outline_rounded, color: Joy.textMuted), tooltip: 'احذف من القائمة'),
        ]),
      ),
    );
  }
}
