import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../api/client.dart';
import '../../api/posts_api.dart';
import '../../api/row_api.dart';
import '../../core/app_theme.dart';

/// «واحد» بشكل البطاقة (النموذج أ): بطاقة مدمجة واحدة فوق الخريطة تُسحب جانبياً فتأتي التالية، وفوقها صف عدّاد بسهمين.
/// الودجة لا تعرف الخريطة: الأب يملك الفهرس ([index]) ويحرّك الخريطة عند تغيّره ([onIndex])، وزر البطاقة الوحيد يفتح
/// رحلة العنصر ([onAct]). الدوران حلقي: بعد الأخيرة تعود الأولى.
class RowDeck extends StatefulWidget {
  final List<RowItem> items;
  final int index;
  final ValueChanged<int> onIndex;
  final ValueChanged<RowItem> onAct;
  /// جلب الصف جارٍ: هيكل بطاقة بدل العناصر.
  final bool loading;
  /// رُتّب الصف بموقع المستخدم («الأقرب أولاً»)، وإلا بالأحدث.
  final bool located;
  const RowDeck({super.key, required this.items, required this.index, required this.onIndex, required this.onAct, this.loading = false, this.located = true});

  static const counterHeight = 30.0, gap = 6.0, cardHeight = 84.0;
  /// مسافة السحب التي تُبدّل البطاقة.
  static const swipeThreshold = 60.0;

  /// الارتفاع الذي تحجزه المجموعة فوق شريط التنقّل (تقديري مع تكبير النص حتى لا تغطي الأزرار العائمة).
  static double heightFor(BuildContext context) {
    final s = MediaQuery.textScalerOf(context).scale(1.0);
    return counterHeight + gap + math.max(cardHeight, 16 + 52 * s + 4);
  }

  @override
  State<RowDeck> createState() => _RowDeckState();
}

class _RowDeckState extends State<RowDeck> {
  double _dragX = 0;
  bool _dragging = false;
  /// جهة خروج البطاقة السابقة بالبكسل: -1 يساراً (التالي) و+1 يميناً (السابق)؛ الجديدة تدخل من الجهة المقابلة.
  int _dir = -1;

  int get _count => widget.items.length;
  int get _index => _count == 0 ? 0 : widget.index.clamp(0, _count - 1);

  void _go(int step, int dir) {
    if (_count == 0) return;
    _dir = dir;
    widget.onIndex((_index + step + _count) % _count);
  }

  void _onDragEnd(double width) {
    final dx = _dragX;
    setState(() {
      _dragging = false;
      _dragX = 0;
    });
    if (dx.abs() < RowDeck.swipeThreshold) return;
    // سحب لليسار = التالي (كما في النموذج)، والبطاقة تخرج بجهة السحب نفسها
    _go(dx < 0 ? 1 : -1, dx < 0 ? -1 : 1);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading && widget.items.isEmpty) return const _Skeleton();
    if (widget.items.isEmpty) return const _EmptyCard();
    final it = widget.items[_index];
    final n = widget.index.clamp(0, _count - 1) + 1;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: RowDeck.counterHeight,
        child: Row(children: [
          _Arrow(key: const Key('row-prev'), icon: Icons.chevron_right_rounded, tip: 'السابق', onTap: () => _go(-1, 1)),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(color: Joy.surface.withValues(alpha: .94), borderRadius: BorderRadius.circular(999), boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 8, offset: Offset(0, 2))]),
              child: Text('$n من $_count · ${widget.located ? 'الأقرب أولاً' : 'الأحدث أولاً'}', key: const Key('row-count'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
            ),
          ),
          const SizedBox(width: 6),
          _Arrow(key: const Key('row-next'), icon: Icons.chevron_left_rounded, tip: 'التالي', onTap: () => _go(1, -1)),
        ]),
      ),
      const SizedBox(height: RowDeck.gap),
      LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => setState(() => _dragging = true),
          onHorizontalDragUpdate: (d) => setState(() => _dragX += d.delta.dx),
          onHorizontalDragEnd: (_) => _onDragEnd(w),
          onHorizontalDragCancel: () => setState(() {
            _dragging = false;
            _dragX = 0;
          }),
          child: AnimatedSlide(
            // أثناء السحب تتبع البطاقة الإصبع فوراً، وعند الإفلات دون العتبة تعود إلى مكانها بنعومة
            offset: Offset(w == 0 ? 0 : _dragX / w, 0),
            duration: _dragging ? Duration.zero : const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) {
                final incoming = child.key == ValueKey('row-${it.pinKey}');
                // الخارجة تنزلق بعيداً بجهة السحب (تحريكها معكوس 1→0)، والداخلة تأتي من الجهة المقابلة
                final from = incoming ? Offset(-_dir * .4, 0) : Offset(_dir * 1.1, 0);
                return FadeTransition(opacity: anim, child: SlideTransition(position: Tween(begin: from, end: Offset.zero).animate(anim), child: child));
              },
              child: _Card(key: ValueKey('row-${it.pinKey}'), item: it, onAct: () => widget.onAct(it)),
            ),
          ),
        );
      }),
    ]);
  }
}

class _Arrow extends StatelessWidget {
  final IconData icon;
  final String tip;
  final VoidCallback onTap;
  const _Arrow({super.key, required this.icon, required this.tip, required this.onTap});
  @override
  Widget build(BuildContext context) => Tooltip(
        message: tip,
        child: Material(
          color: Joy.surface.withValues(alpha: .94),
          shape: const CircleBorder(),
          elevation: 2,
          shadowColor: Colors.black26,
          child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: SizedBox(width: RowDeck.counterHeight, height: RowDeck.counterHeight, child: Icon(icon, size: 20, color: Joy.text))),
        ),
      );
}

const _cardShadow = [BoxShadow(color: Color(0x33000000), blurRadius: 28, offset: Offset(0, 10))];

BoxDecoration _cardBox() => BoxDecoration(color: Joy.surface, borderRadius: BorderRadius.circular(18), boxShadow: _cardShadow);

/// البطاقة المدمجة: صورة ٦٨ في البداية، سطر النوع·الناشر والمسافة في النهاية، عنوان، وصف، وزر واحد بالفعل.
class _Card extends StatelessWidget {
  final RowItem item;
  final VoidCallback onAct;
  const _Card({super.key, required this.item, required this.onAct});

  @override
  Widget build(BuildContext context) {
    final color = rowKindColor(item.kind);
    return Container(
      key: const Key('row-card'),
      constraints: const BoxConstraints(minHeight: RowDeck.cardHeight),
      padding: const EdgeInsets.all(8),
      decoration: _cardBox(),
      child: Row(children: [
        _Thumb(item: item, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (item.logoUrl != null)
                ClipOval(child: SizedBox(width: 16, height: 16, child: Image.network(thumbUrl(item.logoUrl!), fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(rowKindIcon(item.kind), size: 13, color: color))))
              else
                Icon(rowKindIcon(item.kind), size: 13, color: color),
              const SizedBox(width: 5),
              Expanded(child: Text(item.who.isEmpty ? item.kindLabel : '${item.kindLabel} · ${item.who}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Joy.textMuted))),
              if (item.distanceKm != null) Padding(padding: const EdgeInsetsDirectional.only(start: 6), child: Text(distanceText(item.distanceKm), key: const Key('row-dist'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Joy.primary))),
            ]),
            const SizedBox(height: 2),
            Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: AppTheme.displayFont, fontSize: 15, fontWeight: FontWeight.w800, height: 1.25, color: Joy.text)),
            const SizedBox(height: 2),
            Text(item.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Color(0xFF374151))),
          ]),
        ),
        const SizedBox(width: 8),
        FilledButton(
          key: const Key('row-act'),
          onPressed: onAct,
          style: FilledButton.styleFrom(minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 13), visualDensity: VisualDensity.compact, tapTargetSize: MaterialTapTargetSize.shrinkWrap, textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          child: Text(item.act),
        ),
      ]),
    );
  }
}

/// صورة البطاقة: الوسيط أو الشعار، وإلا مربع بلون النوع ورمزه (الفعاليات والوظائف بلا صور).
class _Thumb extends StatelessWidget {
  final RowItem item;
  final Color color;
  const _Thumb({required this.item, required this.color});
  @override
  Widget build(BuildContext context) {
    final fallback = Container(width: 68, height: 68, color: color.withValues(alpha: .14), child: Icon(rowKindIcon(item.kind), color: color, size: 28));
    final url = item.imageUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(width: 68, height: 68, child: url == null ? fallback : Image.network(thumbUrl(url), fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback)),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard();
  @override
  Widget build(BuildContext context) => Container(
        key: const Key('row-empty'),
        constraints: const BoxConstraints(minHeight: RowDeck.cardHeight),
        padding: const EdgeInsets.all(8),
        decoration: _cardBox(),
        child: Row(children: [
          Container(width: 68, height: 68, decoration: BoxDecoration(color: Joy.primarySoft, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.auto_awesome_rounded, color: Joy.primary, size: 28)),
          const SizedBox(width: 10),
          const Expanded(child: Text('لا شيء حولك الآن… جرّب أن تنشر لحظة', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Joy.text, height: 1.5))),
        ]),
      );
}

/// هيكل البطاقة أثناء الجلب بالشكل نفسه حتى لا تقفز الخريطة.
class _Skeleton extends StatelessWidget {
  const _Skeleton();
  @override
  Widget build(BuildContext context) {
    Widget bar(double w, double h) => Container(width: w, height: h, decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(6)));
    return Container(
      key: const Key('row-skeleton'),
      constraints: const BoxConstraints(minHeight: RowDeck.cardHeight),
      padding: const EdgeInsets.all(8),
      decoration: _cardBox(),
      child: Row(children: [
        Container(width: 68, height: 68, decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(14))),
        const SizedBox(width: 10),
        Expanded(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [bar(90, 10), const SizedBox(height: 8), bar(160, 14), const SizedBox(height: 8), bar(120, 10)])),
        const SizedBox(width: 8),
        Container(width: 64, height: 34, decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(999))),
      ]),
    );
  }
}

/// لون النوع على البطاقة ودبّوسه (الفعالية بنفسجية والوظيفة زرقاء كتصنيفات المنشورات).
Color rowKindColor(String kind) => switch (kind) {
      'offer' => Joy.sunText,
      'event' => const Color(0xFF6A1B9A),
      'job' => const Color(0xFF1565C0),
      'listing' => const Color(0xFF00897B),
      _ => Joy.accent,
    };

IconData rowKindIcon(String kind) => switch (kind) {
      'offer' => Icons.local_offer_rounded,
      'event' => Icons.event_rounded,
      'job' => Icons.work_rounded,
      'listing' => Icons.shopping_bag_rounded,
      _ => Icons.auto_awesome_rounded,
    };
