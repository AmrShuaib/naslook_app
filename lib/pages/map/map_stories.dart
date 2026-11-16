import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../api/client.dart';
import '../../api/commerce_models.dart';
import '../../api/models.dart';
import '../../api/offers_map_api.dart';
import '../../api/posts_api.dart';
import '../../api/row_api.dart';
import '../../core/app_theme.dart';
import '../market/market_delivery.dart' show listingPriceText;
import 'map_cluster.dart';

/// من هذا التكبير فما فوق يحل شريط القصص محل بطاقة «الصف» في الرئيسية. أعلى من تكبير تتبّع البطاقة (15.5) عمداً:
/// البطاقة تبقى ما دامت الخريطة تتبعها، والشريط يظهر حين يقرّب المستخدم على منطقة (بيده أو بلمس مجموعة دبابيس).
const double kStoryZoom = 16.2;

/// نصف قطر دمج القصص المتراكبة على الشاشة في دائرة واحدة برقم.
const double kStoryMergePx = 26;

/// ما يُعرض من عنصر الخريطة في الشريط والشاشة العمودية، مهما كان مصدره (طبقة أو «الصف»).
class MapStory {
  final MapItem item;
  /// نوع التصفية ([mapFilterIds]) ومنه اللون والتسمية.
  final String kind;
  final String title, who, sub, act;
  /// صورة العرض (رابط وسائط أو `asset:`)؛ null = بطاقة لونية بالحرف الأول.
  final String? image;
  final bool video;
  const MapStory({required this.item, required this.kind, required this.title, this.who = '', this.sub = '', required this.act, this.image, this.video = false});

  Color get color => Joy.kindColor(kind);
  String get kindLabel => switch (kind) { 'offer' => 'عرض', 'event' => 'فعالية', 'job' => 'وظيفة', 'listing' => 'السوق', 'circle' => 'دائرة', _ => 'لحظة' };
  String get initial => title.trim().isEmpty ? '•' : title.trim().characters.first;

  /// الأشخاص والدبابيس القديمة ليست قصصاً (null). [logos]: شعار كل دائرة بمعرّفها، فعنصر الخريطة لا يحمله.
  static MapStory? of(MapItem it, {Map<String, String?> logos = const {}}) {
    final d = it.data;
    String? clean(String? u) => u == null || u.isEmpty ? null : u;
    if (d is RowItem) {
      final kind = rowFilterKind(d);
      return MapStory(item: it, kind: kind, title: d.title, who: d.who, sub: d.subtitle, act: d.act.isEmpty ? RowItem.defaultAct(d.kind) : d.act, image: clean(d.imageUrl) ?? (kind == 'moment' ? null : clean(d.logoUrl)), video: d.payload['kind'] == 'video');
    }
    switch (it.kind) {
      case MapItemKind.post:
        final p = d as MapPost;
        final media = p.kind == 'image' || p.kind == 'video' ? clean(p.mediaUrl) : null;
        return MapStory(item: it, kind: 'moment', title: p.summary, who: p.user.nickname, sub: p.placeName ?? '', act: 'شاهد', image: media, video: p.kind == 'video');
      case MapItemKind.story:
        final s = d as Story;
        return MapStory(item: it, kind: 'moment', title: it.subtitle, who: s.nickname, act: 'شاهد', image: s.type == 'image' ? clean(s.content) : null, video: s.type == 'video');
      case MapItemKind.listing:
        final l = d as Listing;
        return MapStory(item: it, kind: 'listing', title: l.title, who: l.seller.nickname, sub: [listingPriceText(l), if ((l.placeName ?? '').isNotEmpty) l.placeName!].join(' · '), act: 'اطلب', image: clean(l.imageUrl) ?? (l.images.isEmpty ? null : l.images.first));
      case MapItemKind.offer:
        final o = d as MapOffer;
        return MapStory(item: it, kind: 'offer', title: o.title, who: o.bizName, sub: o.endsLabel, act: 'استخدم', image: clean(o.logoUrl));
      case MapItemKind.business:
        final b = d as Business;
        return MapStory(item: it, kind: 'circle', title: b.name, sub: b.category, act: 'زيارة', image: clean(logos[b.id]));
      case MapItemKind.person || MapItemKind.pin || MapItemKind.event || MapItemKind.job:
        return null; // الفعالية والوظيفة بياناتهما RowItem دائماً وعولجتا أعلاه
    }
  }
}

/// قصص الإطار مجمّعة: الأقرب إلى [centerLat]/[centerLng] أولاً، وما يتراكب على الشاشة عند [zoom] (ضمن [mergePx])
/// مجموعة واحدة. الترتيب محدّد النتيجة حتى لا يتراقص الشريط مع كل إطار.
List<List<MapItem>> storyGroups(Iterable<MapItem> items, {required double zoom, required double centerLat, required double centerLng, double mergePx = kStoryMergePx}) {
  final c = projectToPixels(centerLat, centerLng, zoom);
  final pts = [for (final it in items) (it: it, p: projectToPixels(it.lat, it.lng, zoom))]
    ..sort((a, b) {
      final d = a.p.distanceTo(c).compareTo(b.p.distanceTo(c));
      return d != 0 ? d : a.it.key.compareTo(b.it.key);
    });
  final groups = <({math.Point<double> p, List<MapItem> items})>[];
  for (final e in pts) {
    final hit = groups.where((g) => g.p.distanceTo(e.p) <= mergePx).firstOrNull;
    if (hit != null) {
      hit.items.add(e.it);
    } else {
      groups.add((p: e.p, items: [e.it]));
    }
  }
  return [for (final g in groups) g.items];
}

/// المسافة نصاً: «650 م» أو «2.4 كم».
String storyDistance(double meters) => meters < 1000 ? '${math.max(50, (meters / 50).round() * 50)} م' : '${(meters / 1000).toStringAsFixed(1)} كم';

/// صورة قصة: شعار مضمّن (asset:) أو وسائط مرفوعة ([thumb] للمصغّر)، و[fallback] عند الغياب أو الخطأ.
Widget storyImage(String? url, {required Widget fallback, BoxFit fit = BoxFit.cover, bool thumb = true}) {
  if (url == null) return fallback;
  if (url.startsWith('asset:')) return Image.asset('assets/${url.substring(6)}', fit: fit, errorBuilder: (_, __, ___) => fallback);
  return Image.network(mediaUrl(thumb ? thumbUrl(url) : url), fit: fit, errorBuilder: (_, __, ___) => fallback);
}

/// شريط القصص المصغّر أسفل الخريطة: دائرة لكل موضع في الإطار، والمتراكب دائرة واحدة بعدده.
class StoryStrip extends StatelessWidget {
  final List<List<MapItem>> groups;
  final Map<String, String?> logos;
  /// لمسة على دائرة: فهرس مجموعتها.
  final ValueChanged<int> onOpen;
  const StoryStrip({super.key, required this.groups, required this.onOpen, this.logos = const {}});

  static const height = 116.0;

  @override
  Widget build(BuildContext context) {
    final total = groups.fold<int>(0, (n, g) => n + g.length);
    return Container(
      key: const Key('map-stories'),
      height: height,
      decoration: BoxDecoration(color: Joy.surface, borderRadius: BorderRadius.circular(24), boxShadow: const [BoxShadow(color: Color(0x3325272A), blurRadius: 18, offset: Offset(0, 6))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 0),
          child: Row(children: [
            const Expanded(child: Text('في هذا الإطار', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, height: 1.2))),
            Text('$total في ${groups.length} مكان', key: const Key('map-stories-count'), style: const TextStyle(color: Joy.textMuted, fontSize: 11.5, height: 1.2)),
          ]),
        ),
        Expanded(
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            itemCount: groups.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => _Ring(key: Key('map-story-$i'), items: groups[i], logos: logos, onTap: () => onOpen(i)),
          ),
        ),
      ]),
    );
  }
}

class _Ring extends StatelessWidget {
  final List<MapItem> items;
  final Map<String, String?> logos;
  final VoidCallback onTap;
  const _Ring({super.key, required this.items, required this.logos, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = MapStory.of(items.first, logos: logos)!;
    final many = items.length > 1;
    final letter = Container(color: s.color, alignment: Alignment.center, child: Text(s.initial, textScaler: TextScaler.noScaling, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20, height: 1)));
    return Semantics(
      button: true,
      label: many ? '${items.length} منشورات هنا' : '${s.kindLabel}: ${s.title}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 64,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Stack(clipBehavior: Clip.none, children: [
              Container(
                width: 58,
                height: 58,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(shape: BoxShape.circle, color: s.color),
                child: Container(
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                  child: ClipOval(child: storyImage(s.image, fallback: letter)),
                ),
              ),
              if (many)
                PositionedDirectional(
                  bottom: -3,
                  end: -4,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 21),
                    height: 21,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: Joy.text, borderRadius: BorderRadius.circular(11), border: Border.all(color: Colors.white, width: 2)),
                    child: Text('${items.length}', textScaler: TextScaler.noScaling, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11, height: 1)),
                  ),
                ),
            ]),
            const SizedBox(height: 3),
            Text(many ? '${items.length} هنا' : s.title, maxLines: 1, overflow: TextOverflow.ellipsis, textScaler: TextScaler.noScaling, style: const TextStyle(fontSize: 10.5, color: Joy.textMuted, height: 1.3)),
          ]),
        ),
      ),
    );
  }
}

/// «الخريطة عمودياً»: كل ما على الخريطة منشوراً بعد منشور، واحد يملأ الشاشة ويُسحب للأعلى للتالي.
/// تُغلق بقيمة [MapItem] حين يضغط المستخدم الخريطة الصغيرة، فتنتقل الخريطة إلى مكانه.
class MapVerticalPage extends StatefulWidget {
  /// بالترتيب المعروض (الأقرب أولاً أو ترتيب الشريط).
  final List<MapItem> items;
  final int initial;
  final Map<String, String?> logos;
  /// النقطة التي تُحسب منها المسافة (موقع المستخدم أو مركز الخريطة)؛ null = بلا مسافة.
  final LatLng? origin;
  /// قالب بلاطات الخريطة الصغيرة؛ null = دائرة بأيقونة.
  final String? tilesUrl;
  /// زر الفعل: رحلة العنصر القائمة كما يفتحها دبّوسه.
  final ValueChanged<MapItem> onOpen;
  const MapVerticalPage({super.key, required this.items, required this.onOpen, this.initial = 0, this.logos = const {}, this.origin, this.tilesUrl});

  static Future<MapItem?> open(BuildContext context, {required List<MapItem> items, required ValueChanged<MapItem> onOpen, int initial = 0, Map<String, String?> logos = const {}, LatLng? origin, String? tilesUrl}) =>
      Navigator.of(context).push<MapItem>(MaterialPageRoute(builder: (_) => MapVerticalPage(items: items, onOpen: onOpen, initial: initial, logos: logos, origin: origin, tilesUrl: tilesUrl)));

  @override
  State<MapVerticalPage> createState() => _MapVerticalPageState();
}

class _MapVerticalPageState extends State<MapVerticalPage> {
  late final List<MapStory> _all = [for (final it in widget.items) if (MapStory.of(it, logos: widget.logos) case final s?) s];
  late List<MapStory> _list = _all;
  late int _index = _all.isEmpty ? 0 : widget.initial.clamp(0, _all.length - 1);
  late PageController _pages = PageController(initialPage: _index);
  String _filter = 'all';

  void _setFilter(String id) {
    if (id == _filter) return;
    final old = _pages;
    setState(() {
      _filter = id;
      _list = id == 'all' ? _all : [for (final s in _all) if (s.kind == id) s];
      _index = 0;
      // متحكم جديد: القائمة تبدّلت فتبدأ من أولها
      _pages = PageController();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kinds = [for (final id in mapFilterIds) if (id == 'all' || _all.any((s) => s.kind == id)) id];
    final top = MediaQuery.viewPaddingOf(context).top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        key: const Key('map-vertical'),
        backgroundColor: const Color(0xFF111214),
        body: Stack(children: [
          if (_list.isEmpty)
            const Center(child: Text('لا شيء منشور هنا بعد', style: TextStyle(color: Colors.white70)))
          else
            PageView.builder(
              key: ValueKey('mv-pages-$_filter'),
              controller: _pages,
              scrollDirection: Axis.vertical,
              itemCount: _list.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => _StoryCard(story: _list[i], origin: widget.origin, tilesUrl: widget.tilesUrl, onOpen: () => widget.onOpen(_list[i].item), onMap: () => Navigator.of(context).pop(_list[i].item)),
            ),
          // خط التقدّم الجانبي
          if (_list.length > 1)
            PositionedDirectional(
              start: 5,
              top: top + 110,
              bottom: 150,
              child: IgnorePointer(
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                  alignment: Alignment.topCenter,
                  child: FractionallySizedBox(heightFactor: (_index + 1) / _list.length, child: Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)))),
                ),
              ),
            ),
          Positioned(
            top: top + 8,
            left: 10,
            right: 10,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                _RoundBtn(key: const Key('mv-back'), icon: Icons.arrow_forward_rounded, tip: 'رجوع إلى الخريطة', onTap: () => Navigator.of(context).pop()),
                const SizedBox(width: 8),
                const Expanded(child: Text('حولك الآن', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17, shadows: _shadow))),
                if (_list.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(999)),
                    child: Text('${_index + 1} من ${_list.length}', key: const Key('mv-count'), style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ),
              ]),
              const SizedBox(height: 8),
              if (kinds.length > 2)
                SizedBox(
                  height: 32,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: kinds.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (_, i) {
                      final id = kinds[i], on = id == _filter;
                      return GestureDetector(
                        key: Key('mv-chip-$id'),
                        onTap: () => _setFilter(id),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 13),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: on ? Colors.white : Colors.black38, borderRadius: BorderRadius.circular(16)),
                          child: Text(mapFilterLabel(id), style: TextStyle(color: on ? Joy.text : Colors.white, fontWeight: on ? FontWeight.w700 : FontWeight.w500, fontSize: 12.5)),
                        ),
                      );
                    },
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

const _shadow = [Shadow(color: Color(0x99000000), blurRadius: 6)];

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final String tip;
  final VoidCallback onTap;
  const _RoundBtn({super.key, required this.icon, required this.tip, required this.onTap});
  @override
  Widget build(BuildContext context) => Tooltip(
        message: tip,
        child: Material(
          color: Colors.black38,
          shape: const CircleBorder(),
          child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: SizedBox(width: 40, height: 40, child: Icon(icon, color: Colors.white, size: 20))),
        ),
      );
}

class _StoryCard extends StatelessWidget {
  final MapStory story;
  final LatLng? origin;
  final String? tilesUrl;
  final VoidCallback onOpen, onMap;
  const _StoryCard({required this.story, required this.origin, required this.tilesUrl, required this.onOpen, required this.onMap});

  @override
  Widget build(BuildContext context) {
    final s = story, it = s.item, o = origin;
    final dist = o == null ? null : storyDistance(const Distance().as(LengthUnit.Meter, o, LatLng(it.lat, it.lng)));
    final plain = DecoratedBox(
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [s.color, const Color(0xFF111214)])),
      child: Center(child: Text(s.initial, textScaler: TextScaler.noScaling, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 120, height: 1))),
    );
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return Stack(fit: StackFit.expand, children: [
      if (s.image == null)
        plain
      else ...[
        // خلفية من الصورة نفسها معتمة تملأ الشاشة، وفوقها الصورة كاملة بلا قص
        Opacity(opacity: .35, child: storyImage(s.image, fallback: const SizedBox.shrink())),
        storyImage(s.image, fallback: plain, fit: BoxFit.contain, thumb: s.video),
      ],
      const IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: [0, .22, .5, 1], colors: [Color(0xB3000000), Color(0x00000000), Color(0x00000000), Color(0xD9000000)])),
        ),
      ),
      if (s.video) const Center(child: IgnorePointer(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 64))),
      PositionedDirectional(
        start: 16,
        end: 86,
        bottom: bottom + 20,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
            decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(999), border: s.kind == 'circle' ? Border.all(color: Colors.white38) : null),
            child: Text(s.video ? '${s.kindLabel} · فيديو' : s.kindLabel, style: TextStyle(color: s.kind == 'offer' ? const Color(0xFF3A2A00) : Colors.white, fontWeight: FontWeight.w700, fontSize: 11.5)),
          ),
          const SizedBox(height: 6),
          Text(s.title, key: const Key('mv-title'), maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 21, height: 1.35, shadows: _shadow)),
          if (s.who.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(s.who, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13, shadows: _shadow))),
          if (s.sub.isNotEmpty || dist != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text([if (s.sub.isNotEmpty) s.sub, if (dist != null) 'يبعد $dist'].join(' · '), key: const Key('mv-sub'), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12.5, shadows: _shadow)),
            ),
          const SizedBox(height: 10),
          FilledButton(
            key: const Key('mv-act'),
            onPressed: onOpen,
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Joy.text, minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 24), shape: const StadiumBorder(), textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            child: Text(s.act),
          ),
        ]),
      ),
      // الخريطة الصغيرة: مكان المنشور، ولمستها تعيد إلى الخريطة عنده
      PositionedDirectional(
        end: 12,
        bottom: bottom + 22,
        child: Semantics(
          button: true,
          label: 'على الخريطة',
          child: GestureDetector(
            key: const Key('mv-map'),
            behavior: HitTestBehavior.opaque,
            onTap: onMap,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2.5), boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 12, offset: Offset(0, 4))]),
                child: ClipOval(
                  child: Stack(fit: StackFit.expand, children: [
                    if (tilesUrl == null)
                      const ColoredBox(color: Color(0xFFE9ECE6))
                    else
                      IgnorePointer(
                        child: FlutterMap(
                          options: MapOptions(initialCenter: LatLng(it.lat, it.lng), initialZoom: 15, interactionOptions: const InteractionOptions(flags: InteractiveFlag.none)),
                          children: [TileLayer(urlTemplate: tilesUrl!, userAgentPackageName: 'app.naslife')],
                        ),
                      ),
                    Center(child: Container(width: 14, height: 14, decoration: BoxDecoration(shape: BoxShape.circle, color: s.color, border: Border.all(color: Colors.white, width: 2)))),
                  ]),
                ),
              ),
              const SizedBox(height: 3),
              const Text('على الخريطة', style: TextStyle(color: Colors.white, fontSize: 10.5, shadows: _shadow)),
            ]),
          ),
        ),
      ),
    ]);
  }
}
