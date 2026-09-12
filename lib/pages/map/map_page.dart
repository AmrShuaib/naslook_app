import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../api/biz_models.dart';
import '../../api/models.dart';
import '../../api/naslife_api.dart';
import '../../core/app_theme.dart';
import '../../core/location.dart';
import '../../state/app_state.dart';
import '../../state/biz_providers.dart';
import '../../state/providers.dart';
import '../../ui/profile_avatar.dart';
import '../../ui/widgets.dart';
import '../business/business_page.dart';
import '../chat/chat_thread_page.dart';
import 'map_cluster.dart';

/// مستوى التكبير الذي تبدأ عنده لوحة المنطقة بعرض المشاركات تفصيلياً.
const double kAreaListZoom = 13;

class MapPage extends ConsumerStatefulWidget {
  const MapPage({super.key});
  @override
  ConsumerState<MapPage> createState() => _MapPageState();
}

class _MapPageState extends ConsumerState<MapPage> {
  final _map = MapController();
  final _sheet = DraggableScrollableController();
  bool showPeople = true, showPins = true, showStories = true, showBusinesses = true;
  // فلاتر الأنشطة التجارية: مفتوح الآن، وفئات محددة (فارغة = الكل)
  bool openOnly = false;
  final Set<String> bizCats = {};
  Timer? _fetchDebounce, _frame;
  double _zoom = 13;
  LatLngBounds? _bounds;
  double _sheetFraction = _sheetInitial;
  bool _ready = false;

  static const _sheetMin = 0.11, _sheetInitial = 0.26, _sheetMax = 0.74;

  void _onMapEvent(MapEvent e) {
    // تحديث فوري (مُخفَّف لإطار واحد) للتجميع ولوحة المنطقة
    _frame ??= Timer(const Duration(milliseconds: 40), () {
      _frame = null;
      if (!mounted) return;
      setState(() {
        _zoom = _map.camera.zoom;
        _bounds = _map.camera.visibleBounds;
        _ready = true;
      });
    });
    // جلب البيانات للحدود الجديدة بعد استقرار الحركة
    _fetchDebounce?.cancel();
    _fetchDebounce = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final b = _map.camera.visibleBounds;
      ref.read(bboxProvider.notifier).state = BBox(b.west, b.south, b.east, b.north);
    });
  }

  @override
  void initState() {
    super.initState();
    _sheet.addListener(() {
      if (!_sheet.isAttached) return;
      final f = _sheet.size;
      if ((f - _sheetFraction).abs() > 0.004) setState(() => _sheetFraction = f);
    });
    Future.microtask(() async {
      final gps = await DeviceLocation.current(precise: false);
      if (gps != null && mounted && ref.read(myPresenceProvider).value?.lat == null) _map.move(gps, 14);
    });
  }

  @override
  void dispose() {
    _fetchDebounce?.cancel();
    _frame?.cancel();
    _sheet.dispose();
    super.dispose();
  }

  List<MapItem> _collect() {
    final people = ref.watch(presenceProvider).value ?? const <Presence>[];
    final pins = ref.watch(pinsProvider).value ?? const <Pin>[];
    final stories = ref.watch(storiesProvider).value ?? const <Story>[];
    final businesses = ref.watch(businessesProvider).value ?? const <Business>[];
    final circles = ref.watch(mapBizProvider).value ?? const <Biz>[];
    final seen = <String>{};
    final out = <MapItem>[];
    void add(MapItem? i) {
      if (i != null && seen.add(i.key)) out.add(i);
    }

    if (showPeople) {
      for (final p in people) {
        add(MapItem.person(p));
      }
    }
    if (showStories) {
      for (final s in stories) {
        add(MapItem.story(s));
      }
    }
    if (showPins) {
      for (final p in pins) {
        add(MapItem.pin(p));
      }
    }
    if (showBusinesses) {
      for (final c in circles) {
        if (openOnly && c.openNow != true) continue;
        if (bizCats.isNotEmpty && !bizCats.contains(c.category.key)) continue;
        add(MapItem.business(c.toBusiness()));
      }
      // متاجر النواة القديمة بلا ساعات عمل أو فئة معروفة: تظهر فقط دون فلاتر
      if (!openOnly && bizCats.isEmpty) {
        for (final b in businesses) {
          add(MapItem.business(b));
        }
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(mapFocusProvider, (_, next) {
      if (next == null) return;
      ref.read(mapFocusProvider.notifier).state = null;
      try {
        _map.move(LatLng(next.lat, next.lng), 16.5);
      } catch (_) {}
    });
    final mine = ref.watch(myPresenceProvider).value;
    final loading = ref.watch(presenceProvider).isLoading || ref.watch(storiesProvider).isLoading || ref.watch(pinsProvider).isLoading || ref.watch(businessesProvider).isLoading;
    final items = _collect();
    final clusters = clusterItems(items, zoom: _zoom);
    final b = _bounds;
    final visible = b == null ? items : itemsInBounds(items, minLat: b.south, minLng: b.west, maxLat: b.north, maxLng: b.east);
    final panelItems = sortForPanel(visible);

    final markers = <Marker>[
      for (final c in clusters)
        if (c.isSingle)
          Marker(
            point: LatLng(c.first.lat, c.first.lng),
            width: _markerBox(c.first.kind),
            height: _markerBox(c.first.kind),
            child: _ItemMarker(item: c.first, onTap: () => _showItem(c.first)),
          )
        else
          Marker(
            point: LatLng(c.lat, c.lng),
            width: 56,
            height: 56,
            child: _ClusterBubble(cluster: c, onTap: () => _openCluster(c)),
          ),
    ];

    return LayoutBuilder(builder: (context, box) {
      final sheetPx = (_sheetFraction.clamp(0, 1) * box.maxHeight);
      final controlsHidden = _sheetFraction > 0.45;
      return Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: mine?.lat != null ? LatLng(mine!.lat!, mine.lng!) : const LatLng(21.5433, 39.1728),
            initialZoom: 13,
            minZoom: 3,
            maxZoom: 18,
            onMapEvent: _onMapEvent,
            onLongPress: (_, latlng) => _hereMenu(latlng),
            onMapReady: () => _onMapEvent(MapEventMoveEnd(camera: _map.camera, source: MapEventSource.mapController)),
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
          ),
          children: [
            // البلاطات تُمرَّر عبر خادم Naslife نفسه (server/tiles.js) فلا تحتاج مصادر خارجية
            TileLayer(urlTemplate: '${ref.read(apiClientProvider).baseUrl}/tiles/{z}/{x}/{y}.png', userAgentPackageName: 'app.naslife'),
            MarkerLayer(markers: markers),
            const SimpleAttributionWidget(source: Text('© OpenStreetMap contributors', style: TextStyle(fontSize: 10))),
          ],
        ),
        // شريط التصفية
        Positioned(
          top: 10,
          left: 12,
          right: 12,
          child: Row(children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _chip('أشخاص', Icons.person_rounded, showPeople, () => setState(() => showPeople = !showPeople)),
                  _chip('لحظات', Icons.auto_awesome_rounded, showStories, () => setState(() => showStories = !showStories)),
                  _chip('دبابيس', Icons.push_pin_rounded, showPins, () => setState(() => showPins = !showPins)),
                  _chip('متاجر', Icons.storefront_rounded, showBusinesses, () => setState(() => showBusinesses = !showBusinesses)),
                  if (showBusinesses) ...[
                    _chip('مفتوح الآن', Icons.schedule_rounded, openOnly, () => setState(() => openOnly = !openOnly)),
                    for (final c in BizCategory.values)
                      _chip(c.plural, c.icon, bizCats.contains(c.key), () => setState(() => bizCats.contains(c.key) ? bizCats.remove(c.key) : bizCats.add(c.key))),
                  ],
                ]),
              ),
            ),
            if (loading) const Padding(padding: EdgeInsets.only(left: 8), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
          ]),
        ),
        // أزرار التحكم تطفو فوق لوحة المنطقة
        AnimatedPositioned(
          duration: const Duration(milliseconds: 120),
          left: 12,
          bottom: sheetPx + 12,
          child: IgnorePointer(
            ignoring: controlsHidden,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: controlsHidden ? 0 : 1,
              child: Column(children: [
                _fab(Icons.my_location_rounded, _goToMe, tip: 'موقعي'),
                const SizedBox(height: 8),
                _fab(Icons.refresh_rounded, _refresh, tip: 'تحديث'),
                const SizedBox(height: 8),
                _fab(mine?.visible == true ? Icons.visibility_rounded : Icons.visibility_off_rounded, _togglePresence, filled: mine?.visible == true, tip: mine?.visible == true ? 'إخفاء موقعي' : 'إظهار موقعي'),
              ]),
            ),
          ),
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 120),
          right: 12,
          bottom: sheetPx + 12,
          child: IgnorePointer(
            ignoring: controlsHidden,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: controlsHidden ? 0 : 1,
              child: FilledButton.icon(
                onPressed: () async {
                  final gps = await DeviceLocation.current();
                  if (gps != null) _map.move(gps, 16);
                  if (mounted) _hereMenu(gps ?? _map.camera.center);
                },
                icon: const Icon(Icons.add_location_alt_rounded),
                label: const Text('هنا الآن'),
              ),
            ),
          ),
        ),
        // لوحة مشاركات المنطقة
        Positioned.fill(
          child: DraggableScrollableSheet(
            controller: _sheet,
            initialChildSize: _sheetInitial,
            minChildSize: _sheetMin,
            maxChildSize: _sheetMax,
            snap: true,
            snapSizes: const [_sheetInitial],
            builder: (context, scroll) => _AreaPanel(
              scroll: scroll,
              items: panelItems,
              total: items.length,
              zoom: _zoom,
              ready: _ready,
              onZoomIn: () => _map.move(_map.camera.center, math.max(_zoom + 2, kAreaListZoom + 1)),
              onSelect: _focus,
              onExpand: () => _sheet.animateTo(_sheetMax, duration: const Duration(milliseconds: 220), curve: Curves.easeOut),
              onCollapse: () => _sheet.animateTo(_sheetInitial, duration: const Duration(milliseconds: 220), curve: Curves.easeOut),
              expanded: _sheetFraction > 0.5,
            ),
          ),
        ),
      ]);
    });
  }

  static double _markerBox(MapItemKind k) => k == MapItemKind.person ? 40 : 30;

  void _refresh() {
    ref.invalidate(presenceProvider);
    ref.invalidate(pinsProvider);
    ref.invalidate(storiesProvider);
    ref.invalidate(businessesProvider);
  }

  /// يقرّب الخريطة إلى العنصر ويفتح تفاصيله.
  void _focus(MapItem item) {
    _sheet.animateTo(_sheetInitial, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    _map.move(LatLng(item.lat, item.lng), math.max(_zoom, 16));
    _showItem(item);
  }

  void _openCluster(MapCluster c) {
    final bb = c.bounds;
    final tiny = (bb.maxLat - bb.minLat) < 0.0004 && (bb.maxLng - bb.minLng) < 0.0004;
    if (tiny || _zoom >= 17.5) {
      _sheet.animateTo(_sheetInitial, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      _map.move(LatLng(c.lat, c.lng), math.max(_zoom, 16));
      _listSheet(c.items, title: 'عند هذه النقطة · ${c.count}');
      return;
    }
    final sheetPx = _sheet.isAttached ? _sheet.pixels : 0.0;
    _map.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds(LatLng(bb.minLat, bb.minLng), LatLng(bb.maxLat, bb.maxLng)),
      padding: EdgeInsets.fromLTRB(48, 88, 48, sheetPx + 48),
      maxZoom: 17.5,
    ));
  }

  Widget _chip(String label, IconData icon, bool on, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(left: 8),
        child: FilterChip(
          selected: on,
          onSelected: (_) => onTap(),
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
          avatar: Icon(icon, size: 15, color: on ? Joy.primaryOn : Joy.textMuted),
          label: Text(label, style: TextStyle(color: on ? Joy.primaryOn : Joy.text, fontWeight: on ? FontWeight.w600 : FontWeight.w500, fontSize: 13)),
          backgroundColor: Joy.surface,
          selectedColor: Joy.primary,
          side: BorderSide(color: on ? Joy.primary : Joy.control),
          elevation: 2,
          shadowColor: const Color(0x33784614),
        ),
      );

  Widget _fab(IconData icon, VoidCallback onTap, {bool filled = false, String? tip}) => Tooltip(
        message: tip ?? '',
        child: Material(
          color: filled ? Joy.primary : Joy.surface,
          shape: const CircleBorder(side: BorderSide(color: Joy.line)),
          elevation: 2,
          child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: SizedBox(width: 44, height: 44, child: Icon(icon, size: 22, color: filled ? Joy.primaryOn : Joy.text))),
        ),
      );

  Future<void> _goToMe() async {
    final gps = await DeviceLocation.current();
    if (gps == null) {
      if (mounted) toast(context, 'لم يُسمح بالوصول إلى موقعك؛ فعّل الموقع للمتصفح ثم أعد المحاولة');
      return;
    }
    _map.move(gps, 16);
  }

  Future<void> _togglePresence() async {
    final api = ref.read(apiClientProvider);
    final cur = ref.read(myPresenceProvider).value;
    try {
      if (cur?.visible == true) {
        await api.setPresence(visible: false);
        if (mounted) toast(context, 'أُخفي موقعك من الخريطة');
      } else if (cur?.lat != null) {
        await api.setPresence(visible: true);
        if (mounted) toast(context, 'أصبحت ظاهراً على الخريطة');
      } else {
        if (mounted) toast(context, 'اضغط مطوّلاً على الخريطة لتحديد مكانك أولاً');
        return;
      }
      ref.invalidate(myPresenceProvider);
      ref.invalidate(presenceProvider);
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  Future<void> _hereMenu(LatLng at) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(padding: EdgeInsets.fromLTRB(20, 16, 20, 6), child: Align(alignment: AlignmentDirectional.centerStart, child: Text('عند هذه النقطة', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)))),
          ListTile(leading: const Icon(Icons.person_pin_circle_rounded, color: Joy.primary), title: const Text('أنا هنا الآن'), subtitle: const Text('اظهر لأصدقائك على الخريطة'), onTap: () => Navigator.pop(context, 'me')),
          ListTile(leading: const Icon(Icons.auto_awesome_rounded, color: Joy.sunText), title: const Text('لحظة'), subtitle: const Text('تظهر 24 ساعة لمن حولك'), onTap: () => Navigator.pop(context, 'story')),
          ListTile(leading: const Icon(Icons.push_pin_rounded, color: Joy.accent), title: const Text('دبوس'), subtitle: const Text('ملاحظة أو تقييم لمكان'), onTap: () => Navigator.pop(context, 'pin')),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    final api = ref.read(apiClientProvider);
    try {
      if (choice == 'me') {
        final title = await askText(context, title: 'ماذا تفعل الآن؟', hint: 'قهوة على الكورنيش…', confirm: 'اظهر', maxLines: 1);
        if (title == null) return;
        await api.setPresence(lat: at.latitude, lng: at.longitude, title: title, visible: true);
        ref.invalidate(myPresenceProvider);
        ref.invalidate(presenceProvider);
        if (mounted) toast(context, 'أصبحت ظاهراً هنا');
      } else if (choice == 'story') {
        final text = await askText(context, title: 'لحظة جديدة', hint: 'ماذا يحدث هنا؟', confirm: 'نشر');
        if (text == null || text.isEmpty) return;
        await api.postStory(text: text, lat: at.latitude, lng: at.longitude);
        ref.invalidate(storiesProvider);
        if (mounted) toast(context, 'نُشرت لحظتك');
      } else if (choice == 'pin') {
        final text = await askText(context, title: 'دبوس جديد', hint: 'ملاحظة عن هذا المكان', confirm: 'تثبيت');
        if (text == null || text.isEmpty) return;
        await api.dropPin(lat: at.latitude, lng: at.longitude, text: text);
        ref.invalidate(pinsProvider);
        if (mounted) toast(context, 'ثُبّت الدبوس');
      }
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
  }

  // ---------------------------------------------------------------- التفاصيل

  void _sheetOf(Widget child) => showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (_) => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), child: child)),
      );

  void _listSheet(List<MapItem> items, {required String title}) => showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .6),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17))),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [
                    for (final it in sortForPanel(items))
                      _ItemRow(item: it, onTap: () {
                        Navigator.pop(ctx);
                        _showItem(it);
                      }),
                  ],
                ),
              ),
            ]),
          ),
        ),
      );

  void _showItem(MapItem item) {
    switch (item.kind) {
      case MapItemKind.person:
        _showPerson(item.data as Presence);
      case MapItemKind.story:
        _showStory(item.data as Story);
      case MapItemKind.pin:
        _showPin(item.data as Pin);
      case MapItemKind.business:
        _showBusiness(item.data as Business);
    }
  }

  void _showPerson(Presence p) {
    final person = Person(id: p.id, nickname: p.nickname, avatarUrl: p.avatarUrl, online: p.online);
    _sheetOf(Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        ProfileAvatar(person: person, size: 56, online: p.online),
        const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            onTap: () => openProfile(context, person),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.me ? '${p.nickname} (أنت)' : p.nickname, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
              Text('${p.online ? 'متصل الآن' : 'غير متصل'} · ${timeAgo(p.updatedAt)}', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
            ]),
          ),
        ),
      ]),
      if (p.title.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(p.title, style: const TextStyle(fontSize: 15))),
      const SizedBox(height: 14),
      if (!p.me)
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadPage(peer: person)));
              },
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              label: const Text('مراسلة'),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              openProfile(context, person);
            },
            icon: const Icon(Icons.person_outline_rounded, size: 18),
            label: const Text('الملف'),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () async {
              try {
                await ref.read(apiClientProvider).addContact(p.id);
                ref.invalidate(contactsProvider);
                if (mounted) {
                  Navigator.pop(context);
                  toast(context, 'أُضيف ${p.nickname} إلى أصدقائك');
                }
              } catch (e) {
                if (mounted) toast(context, e.toString(), error: true);
              }
            },
            child: const Text('إضافة'),
          ),
        ]),
    ]));
  }

  void _showStory(Story s) {
    final person = Person(id: s.userId, nickname: s.nickname, avatarUrl: s.avatarUrl);
    final isMe = ref.read(appStateProvider).user?.id == s.userId;
    _sheetOf(Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        ProfileAvatar(person: person, size: 44, ring: true),
        const SizedBox(width: 10),
        Expanded(
          child: InkWell(
            onTap: () => openProfile(context, person),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.nickname, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              Text('لحظة · ${timeAgo(s.createdAt)}', style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
            ]),
          ),
        ),
        if (!isMe)
          IconButton(
            tooltip: 'مراسلة',
            onPressed: () {
              Navigator.pop(context);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadPage(peer: person)));
            },
            icon: const Icon(Icons.chat_bubble_outline_rounded, color: Joy.primary),
          ),
      ]),
      const SizedBox(height: 12),
      if (s.type == 'image' && s.content.startsWith('http'))
        ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.network(s.content, fit: BoxFit.cover, height: 220, width: double.infinity, errorBuilder: (_, __, ___) => const SizedBox.shrink()))
      else
        Text(s.content, style: const TextStyle(fontSize: 17, height: 1.6)),
      if (s.caption.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(s.caption, style: const TextStyle(color: Joy.textMuted))),
    ]));
  }

  void _showPin(Pin p) {
    final person = Person(id: p.ownerId, nickname: p.ownerNickname, avatarUrl: p.ownerAvatar);
    _sheetOf(Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        ProfileAvatar(person: person, size: 40),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.placeName?.isNotEmpty == true ? p.placeName! : p.ownerNickname, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            InkWell(onTap: () => openProfile(context, person), child: Text('${p.ownerNickname} · ${timeAgo(p.createdAt)}', style: const TextStyle(color: Joy.textMuted, fontSize: 12))),
          ]),
        ),
        if (p.rating != null) Row(children: [for (var i = 0; i < p.rating!; i++) const Icon(Icons.star_rounded, size: 16, color: Joy.warning)]),
      ]),
      const SizedBox(height: 10),
      Text(p.content, style: const TextStyle(fontSize: 15, height: 1.6)),
    ]));
  }

  void _showBusiness(Business b) => _sheetOf(Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Avatar(name: b.name, size: 48, radius: 14),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Flexible(child: Text(b.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17))), if (b.verified) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.verified_rounded, color: Joy.primary, size: 18))]),
              Text('${b.category} · ${b.followers} متابع', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
            ]),
          ),
        ]),
        if (b.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(b.description, maxLines: 3, overflow: TextOverflow.ellipsis)),
        if (b.kind != null) ...[
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              openBusiness(context, b.id);
            },
            icon: const Icon(Icons.login_rounded),
            label: Text(switch (b.kind) { 'cinema' => 'دخول الدائرة وحجز التذاكر', 'hotel' => 'دخول الدائرة وحجز غرفة', 'car_rental' => 'دخول الدائرة وحجز سيارة', _ => 'دخول الدائرة والشراء' }),
          ),
        ],
      ]));
}

// ------------------------------------------------------------------ العلامات

Color _kindColor(MapItemKind k) => switch (k) {
      MapItemKind.person => Joy.primary,
      MapItemKind.story => Joy.sun,
      MapItemKind.pin => Joy.accent,
      MapItemKind.business => Joy.primary,
    };

Color _kindOn(MapItemKind k) => switch (k) {
      MapItemKind.story => Joy.sunText,
      _ => Joy.primaryOn,
    };

IconData _kindIcon(MapItemKind k) => switch (k) {
      MapItemKind.person => Icons.person_rounded,
      MapItemKind.story => Icons.auto_awesome_rounded,
      MapItemKind.pin => Icons.push_pin_rounded,
      MapItemKind.business => Icons.storefront_rounded,
    };

String _kindLabel(MapItemKind k) => switch (k) {
      MapItemKind.person => 'شخص',
      MapItemKind.story => 'لحظة',
      MapItemKind.pin => 'دبوس',
      MapItemKind.business => 'متجر',
    };

const _markerShadow = [BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 1.5))];

/// علامة مصغّرة لعنصر واحد.
class _ItemMarker extends StatelessWidget {
  final MapItem item;
  final VoidCallback onTap;
  const _ItemMarker({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    Widget child;
    switch (item.kind) {
      case MapItemKind.person:
        final p = item.data as Presence;
        child = Container(
          decoration: BoxDecoration(shape: BoxShape.circle, color: Joy.surface, boxShadow: _markerShadow, border: Border.all(color: p.me ? Joy.primary : Joy.surface, width: 2)),
          padding: const EdgeInsets.all(1),
          child: Avatar(name: p.nickname, url: p.avatarUrl, size: 32, online: p.online),
        );
      case MapItemKind.story:
        final s = item.data as Story;
        child = Container(
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Joy.surface, boxShadow: _markerShadow),
          child: Avatar(name: s.nickname, url: s.avatarUrl, size: 20, ring: true),
        );
      case MapItemKind.pin:
        final p = item.data as Pin;
        child = _dot(p.type == 'review' ? Icons.star_rounded : Icons.push_pin_rounded, Joy.accent, Joy.accentOn);
      case MapItemKind.business:
        final b = item.data as Business;
        child = _dot(_bizIcon(b.kind), Joy.primary, Joy.primaryOn);
    }
    return Semantics(
      button: true,
      label: '${_kindLabel(item.kind)} ${item.title}',
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: Center(child: child)),
    );
  }

  static IconData _bizIcon(String? kind) => switch (kind) {
        'cinema' => Icons.local_movies_rounded,
        'hotel' => Icons.hotel_rounded,
        'car_rental' => Icons.directions_car_rounded,
        'brand' => Icons.local_mall_rounded,
        _ => Icons.storefront_rounded,
      };

  static Widget _dot(IconData icon, Color bg, Color fg) => Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(shape: BoxShape.circle, color: bg, border: Border.all(color: Joy.surface, width: 2), boxShadow: _markerShadow),
        child: Icon(icon, size: 13, color: fg),
      );
}

/// فقاعة تجميع تعرض عدد العناصر المتقاربة.
class _ClusterBubble extends StatelessWidget {
  final MapCluster cluster;
  final VoidCallback onTap;
  const _ClusterBubble({required this.cluster, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final n = cluster.count;
    final size = n >= 100 ? 48.0 : (n >= 10 ? 42.0 : 36.0);
    final color = _kindColor(cluster.dominant);
    final textColor = cluster.dominant == MapItemKind.story ? Joy.sunText : color;
    return Semantics(
      button: true,
      label: '$n عناصر متقاربة',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: Container(
            width: size + 10,
            height: size + 10,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: .18)),
            alignment: Alignment.center,
            child: Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Joy.surface, border: Border.all(color: color, width: 2.5), boxShadow: _markerShadow),
              child: Text('$n', style: TextStyle(fontWeight: FontWeight.w800, fontSize: n >= 100 ? 13 : 14, color: textColor, height: 1)),
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ لوحة المنطقة

class _AreaPanel extends StatelessWidget {
  final ScrollController scroll;
  final List<MapItem> items;
  final int total;
  final double zoom;
  final bool ready;
  final bool expanded;
  final VoidCallback onZoomIn, onExpand, onCollapse;
  final ValueChanged<MapItem> onSelect;
  const _AreaPanel({
    required this.scroll,
    required this.items,
    required this.total,
    required this.zoom,
    required this.ready,
    required this.expanded,
    required this.onZoomIn,
    required this.onExpand,
    required this.onCollapse,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final zoomedIn = zoom >= kAreaListZoom;
    final counts = <MapItemKind, int>{};
    for (final i in items) {
      counts[i.kind] = (counts[i.kind] ?? 0) + 1;
    }
    return Container(
      decoration: const BoxDecoration(
        color: Joy.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: Joy.line)),
        boxShadow: [BoxShadow(color: Color(0x1F000000), blurRadius: 14, offset: Offset(0, -3))],
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView(
        controller: scroll,
        padding: EdgeInsets.zero,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: expanded ? onCollapse : onExpand,
            child: Column(children: [
              const SizedBox(height: 8),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Joy.control, borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
                child: Row(children: [
                  const Icon(Icons.explore_outlined, size: 20, color: Joy.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      !ready ? 'حول هذه المنطقة' : (zoomedIn ? 'في هذه المنطقة' : 'حول هذه المنطقة'),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                  ),
                  if (items.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(color: Joy.primarySoft, borderRadius: BorderRadius.circular(999)),
                      child: Text('${items.length}', style: const TextStyle(color: Joy.primary, fontWeight: FontWeight.w700, fontSize: 12.5)),
                    ),
                  Icon(expanded ? Icons.expand_more_rounded : Icons.expand_less_rounded, color: Joy.textMuted),
                ]),
              ),
              if (counts.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                  child: Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final k in MapItemKind.values)
                      if ((counts[k] ?? 0) > 0) _CountChip(kind: k, count: counts[k]!),
                  ]),
                ),
              const Divider(height: 1, color: Joy.line),
            ]),
          ),
          if (!zoomedIn)
            _Hint(
              icon: Icons.zoom_in_map_rounded,
              title: items.isEmpty ? 'قرّب الخريطة لاستكشاف منطقة' : 'قرّب الخريطة لعرض مشاركات المنطقة',
              body: items.isEmpty ? 'حرّك الخريطة أو قرّبها؛ ستظهر هنا اللحظات والدبابيس والأشخاص في المنطقة المرئية.' : 'عند التقريب تُعرض اللحظات والدبابيس والأشخاص هنا مرتّبةً من الأحدث.',
              action: FilledButton.tonalIcon(onPressed: onZoomIn, icon: const Icon(Icons.zoom_in_rounded, size: 18), label: const Text('قرّب هنا')),
            )
          else if (items.isEmpty)
            _Hint(
              icon: Icons.location_searching_rounded,
              title: total == 0 ? 'لا مشاركات هنا بعد' : 'لا مشاركات ضمن هذه المنطقة',
              body: 'اضغط مطوّلاً على أي نقطة في الخريطة لتضيف لحظة أو دبوساً أو تظهر لأصدقائك.',
            )
          else
            for (var i = 0; i < items.length; i++) _ItemRow(item: items[i], onTap: () => onSelect(items[i]), divider: i < items.length - 1),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final MapItemKind kind;
  final int count;
  const _CountChip({required this.kind, required this.count});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: Joy.surface2, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_kindIcon(kind), size: 13, color: kind == MapItemKind.story ? Joy.sunText : _kindColor(kind)),
          const SizedBox(width: 4),
          Text('$count ${_kindLabel(kind)}', style: const TextStyle(fontSize: 12, color: Joy.text, fontWeight: FontWeight.w600)),
        ]),
      );
}

class _Hint extends StatelessWidget {
  final IconData icon;
  final String title, body;
  final Widget? action;
  const _Hint({required this.icon, required this.title, required this.body, this.action});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 36, height: 36, decoration: const BoxDecoration(color: Joy.primarySoft, shape: BoxShape.circle), child: Icon(icon, color: Joy.primary, size: 20)),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
          ]),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(color: Joy.textMuted, fontSize: 13.5, height: 1.5)),
          if (action != null) Padding(padding: const EdgeInsets.only(top: 10), child: action),
        ]),
      );
}

/// صف عنصر في لوحة المنطقة: صورة صاحبه (تفتح ملفه) وشارة نوعه، وعنوان ووصف ووقت.
class _ItemRow extends StatelessWidget {
  final MapItem item;
  final VoidCallback onTap;
  final bool divider;
  const _ItemRow({required this.item, required this.onTap, this.divider = true});

  @override
  Widget build(BuildContext context) {
    final author = item.author;
    final leading = Stack(clipBehavior: Clip.none, children: [
      if (author != null && author.id.isNotEmpty)
        ProfileAvatar(person: author, size: 46, ring: item.kind == MapItemKind.story, online: item.kind == MapItemKind.person && author.online)
      else if (item.kind == MapItemKind.business)
        Avatar(name: item.title, size: 46, radius: 14)
      else
        Avatar(name: item.title, size: 46),
      PositionedDirectional(
        end: -3,
        bottom: -3,
        child: Container(
          width: 19,
          height: 19,
          decoration: BoxDecoration(color: _kindColor(item.kind), shape: BoxShape.circle, border: Border.all(color: Joy.surface, width: 2)),
          child: Icon(_kindIcon(item.kind), size: 10, color: _kindOn(item.kind)),
        ),
      ),
    ]);
    return ListRow(
      leading: leading,
      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      subtitle: item.subtitle.isEmpty ? null : Text(item.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Joy.textMuted, fontSize: 13)),
      trailing: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        if (item.at != null) Text(timeAgo(item.at), style: const TextStyle(color: Joy.textMuted, fontSize: 11.5)),
        const SizedBox(height: 2),
        const Icon(Icons.near_me_outlined, size: 16, color: Joy.control),
      ]),
      onTap: onTap,
      divider: divider,
    );
  }
}
