import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../api/models.dart';
import '../../api/naslife_api.dart';
import '../../core/app_theme.dart';
import '../../core/location.dart';
import '../../state/app_state.dart';
import '../../state/providers.dart';
import '../../ui/widgets.dart';
import '../chat/chat_thread_page.dart';

class MapPage extends ConsumerStatefulWidget {
  const MapPage({super.key});
  @override
  ConsumerState<MapPage> createState() => _MapPageState();
}

class _MapPageState extends ConsumerState<MapPage> {
  final _map = MapController();
  bool showPeople = true, showPins = true, showStories = true, showBusinesses = true;
  Timer? _debounce;

  void _onMoved() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      final b = _map.camera.visibleBounds;
      ref.read(bboxProvider.notifier).state = BBox(b.west, b.south, b.east, b.north);
    });
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final gps = await DeviceLocation.current(precise: false);
      if (gps != null && mounted && ref.read(myPresenceProvider).value?.lat == null) _map.move(gps, 14);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final people = ref.watch(presenceProvider).value ?? const <Presence>[];
    final pins = ref.watch(pinsProvider).value ?? const <Pin>[];
    final stories = ref.watch(storiesProvider).value ?? const <Story>[];
    final businesses = ref.watch(businessesProvider).value ?? const <Business>[];
    final mine = ref.watch(myPresenceProvider).value;

    final markers = <Marker>[
      if (showPeople)
        for (final p in people)
          Marker(
            point: LatLng(p.lat, p.lng), width: 46, height: 46,
            child: GestureDetector(
              onTap: () => _showPerson(p),
              child: Container(
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Joy.surface, width: 2), boxShadow: [BoxShadow(color: p.me ? Joy.primary : Joy.primary.withValues(alpha: .35), blurRadius: 0, spreadRadius: 1.5)]),
                child: Avatar(name: p.nickname, url: p.avatarUrl, size: 42, online: p.online),
              ),
            ),
          ),
      if (showStories)
        for (final s in stories.where((s) => s.lat != null && s.lng != null))
          Marker(
            point: LatLng(s.lat!, s.lng!), width: 34, height: 34,
            child: GestureDetector(
              onTap: () => _showStory(s),
              child: Container(decoration: BoxDecoration(shape: BoxShape.circle, color: Joy.sun, border: Border.all(color: Joy.surface, width: 2)), child: const Icon(Icons.auto_awesome_rounded, size: 16, color: Joy.sunText)),
            ),
          ),
      if (showPins)
        for (final p in pins)
          Marker(
            point: LatLng(p.lat, p.lng), width: 34, height: 34,
            child: GestureDetector(
              onTap: () => _showPin(p),
              child: Container(decoration: BoxDecoration(shape: BoxShape.circle, color: Joy.accent, border: Border.all(color: Joy.surface, width: 2)), child: Icon(p.type == 'review' ? Icons.star_rounded : Icons.push_pin_rounded, size: 16, color: Joy.accentOn)),
            ),
          ),
      if (showBusinesses)
        for (final b in businesses.where((b) => b.lat != null && b.lng != null))
          Marker(
            point: LatLng(b.lat!, b.lng!), width: 34, height: 34,
            child: GestureDetector(
              onTap: () => _showBusiness(b),
              child: Container(decoration: BoxDecoration(shape: BoxShape.circle, color: Joy.primary, border: Border.all(color: Joy.surface, width: 2)), child: const Icon(Icons.storefront_rounded, size: 16, color: Joy.primaryOn)),
            ),
          ),
    ];

    return Stack(children: [
      FlutterMap(
        mapController: _map,
        options: MapOptions(
          initialCenter: mine?.lat != null ? LatLng(mine!.lat!, mine.lng!) : const LatLng(21.5433, 39.1728),
          initialZoom: 13,
          onMapEvent: (e) => _onMoved(),
          onLongPress: (_, latlng) => _hereMenu(latlng),
          onMapReady: _onMoved,
        ),
        children: [
          // البلاطات تُمرَّر عبر خادم Naslife نفسه (server/tiles.js) فلا تحتاج مصادر خارجية
          TileLayer(urlTemplate: '${ref.read(apiClientProvider).baseUrl}/tiles/{z}/{x}/{y}.png', userAgentPackageName: 'app.naslife'),
          MarkerLayer(markers: markers),
          const SimpleAttributionWidget(source: Text('© OpenStreetMap contributors', style: TextStyle(fontSize: 10))),
        ],
      ),
      Positioned(
        top: 12, left: 16, right: 16,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _chip('أشخاص', Icons.person_rounded, showPeople, () => setState(() => showPeople = !showPeople)),
            _chip('لحظات', Icons.auto_awesome_rounded, showStories, () => setState(() => showStories = !showStories)),
            _chip('دبابيس', Icons.push_pin_rounded, showPins, () => setState(() => showPins = !showPins)),
            _chip('متاجر', Icons.storefront_rounded, showBusinesses, () => setState(() => showBusinesses = !showBusinesses)),
          ]),
        ),
      ),
      Positioned(
        left: 16, bottom: 16,
        child: Column(children: [
          _fab(Icons.my_location_rounded, _goToMe),
          const SizedBox(height: 8),
          _fab(Icons.refresh_rounded, () {
            ref.invalidate(presenceProvider);
            ref.invalidate(pinsProvider);
            ref.invalidate(storiesProvider);
            ref.invalidate(businessesProvider);
          }),
          const SizedBox(height: 8),
          _fab(mine?.visible == true ? Icons.visibility_rounded : Icons.visibility_off_rounded, _togglePresence, filled: mine?.visible == true),
        ]),
      ),
      Positioned(
        right: 16, bottom: 16,
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
    ]);
  }

  Widget _chip(String label, IconData icon, bool on, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(left: 8),
        child: FilterChip(
          selected: on, onSelected: (_) => onTap(), showCheckmark: false,
          avatar: Icon(icon, size: 16, color: on ? Joy.primaryOn : Joy.textMuted),
          label: Text(label, style: TextStyle(color: on ? Joy.primaryOn : Joy.text, fontWeight: on ? FontWeight.w600 : FontWeight.w500)),
          backgroundColor: Joy.surface,
          selectedColor: Joy.primary,
          side: BorderSide(color: on ? Joy.primary : Joy.control),
          elevation: 2,
          shadowColor: const Color(0x33784614),
        ),
      );

  Widget _fab(IconData icon, VoidCallback onTap, {bool filled = false}) => Material(
        color: filled ? Joy.primary : Joy.surface,
        shape: const CircleBorder(side: BorderSide(color: Joy.line)),
        elevation: 2,
        child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: SizedBox(width: 48, height: 48, child: Icon(icon, color: filled ? Joy.primaryOn : Joy.text))),
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

  void _sheet(Widget child) => showModalBottomSheet(context: context, builder: (_) => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 20), child: child)));

  void _showPerson(Presence p) => _sheet(Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Avatar(name: p.nickname, url: p.avatarUrl, size: 56, online: p.online),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.me ? '${p.nickname} (أنت)' : p.nickname, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            Text('${p.online ? 'متصل الآن' : 'غير متصل'} · ${timeAgo(p.updatedAt)}', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
          ])),
        ]),
        if (p.title.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(p.title, style: const TextStyle(fontSize: 15))),
        const SizedBox(height: 14),
        if (!p.me)
          Row(children: [
            Expanded(child: FilledButton.icon(onPressed: () { Navigator.pop(context); Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatThreadPage(peer: Person(id: p.id, nickname: p.nickname, avatarUrl: p.avatarUrl)))); }, icon: const Icon(Icons.chat_bubble_outline_rounded), label: const Text('مراسلة'))),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: () async {
              try {
                await ref.read(apiClientProvider).addContact(p.id);
                ref.invalidate(contactsProvider);
                if (mounted) { Navigator.pop(context); toast(context, 'أُضيف ${p.nickname} إلى أصدقائك'); }
              } catch (e) { if (mounted) toast(context, e.toString(), error: true); }
            }, child: const Text('إضافة')),
          ]),
      ]));

  void _showStory(Story s) => _sheet(Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Avatar(name: s.nickname, url: s.avatarUrl, size: 44, ring: true), const SizedBox(width: 10), Text(s.nickname, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)), const Spacer(), Text(timeAgo(s.createdAt), style: const TextStyle(color: Joy.textMuted, fontSize: 12))]),
        const SizedBox(height: 12),
        Text(s.content, style: const TextStyle(fontSize: 17, height: 1.6)),
      ]));

  void _showPin(Pin p) => _sheet(Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Avatar(name: p.ownerNickname, url: p.ownerAvatar, size: 40),
          const SizedBox(width: 10),
          Expanded(child: Text(p.placeName ?? p.ownerNickname, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
          if (p.rating != null) Row(children: [for (var i = 0; i < p.rating!; i++) const Icon(Icons.star_rounded, size: 16, color: Joy.warning)]),
        ]),
        const SizedBox(height: 10),
        Text(p.content, style: const TextStyle(fontSize: 15, height: 1.6)),
        const SizedBox(height: 4),
        Text('${p.ownerNickname} · ${timeAgo(p.createdAt)}', style: const TextStyle(color: Joy.textMuted, fontSize: 12)),
      ]));

  void _showBusiness(Business b) => _sheet(Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Avatar(name: b.name, size: 48, radius: 14),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Flexible(child: Text(b.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17))), if (b.verified) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.verified_rounded, color: Joy.primary, size: 18))]),
            Text('${b.category} · ${b.followers} متابع', style: const TextStyle(color: Joy.textMuted, fontSize: 12.5)),
          ])),
        ]),
        if (b.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(b.description)),
      ]));
}
