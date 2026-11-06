import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../core/app_theme.dart';
import '../core/location.dart';
import '../state/app_state.dart';
import 'widgets.dart';

/// اختيار نقطة على الخريطة بملء الشاشة: ضغطة تضع الدبوس، و«موقعي» ينقله إلى موقع الجهاز، و«تأكيد الموقع» يعيده.
/// منتقٍ واحد مشترك: معالج تسجيل الدوائر (register_circle_page.dart) وإنشاء الفعالية (event_create_page.dart)، حتى لا تتباعد نسختان.
class MapPickPage extends ConsumerStatefulWidget {
  final LatLng initial;
  final String title;
  const MapPickPage({super.key, required this.initial, this.title = 'حدّد الموقع'});

  /// يفتح المنتقي ويعيد النقطة المؤكدة، أو null إن رجع المستخدم بلا تأكيد.
  static Future<LatLng?> open(BuildContext context, {LatLng? initial, String title = 'حدّد الموقع'}) =>
      Navigator.of(context).push<LatLng>(MaterialPageRoute(builder: (_) => MapPickPage(initial: initial ?? DeviceLocation.lastBrowse ?? DeviceLocation.jeddah, title: title)));

  @override
  ConsumerState<MapPickPage> createState() => _MapPickPageState();
}

class _MapPickPageState extends ConsumerState<MapPickPage> {
  late LatLng point = widget.initial;
  final _map = MapController();

  @override
  Widget build(BuildContext context) {
    final base = ref.read(apiClientProvider).baseUrl;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), actions: [
        TextButton.icon(
          key: const Key('map-pick-me'),
          onPressed: () async {
            final g = await DeviceLocation.current();
            if (g == null) {
              if (context.mounted) toast(context, 'لم يُسمح بالوصول إلى الموقع');
              return;
            }
            setState(() => point = g);
            _map.move(g, 16);
          },
          icon: const Icon(Icons.my_location_rounded, size: 18),
          label: const Text('موقعي'),
        ),
      ]),
      body: FlutterMap(
        key: const Key('map-pick-map'),
        mapController: _map,
        options: MapOptions(initialCenter: point, initialZoom: 15, onTap: (_, p) => setState(() => point = p), interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate)),
        children: [
          TileLayer(urlTemplate: '$base/tiles/{z}/{x}/{y}.png', userAgentPackageName: 'app.naslife'),
          MarkerLayer(markers: [Marker(point: point, width: 40, height: 40, child: const Icon(Icons.location_on_rounded, color: Joy.accent, size: 40))]),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('map-pick-confirm'),
        onPressed: () => Navigator.of(context).pop(point),
        backgroundColor: Joy.primary,
        foregroundColor: Joy.primaryOn,
        icon: const Icon(Icons.check_rounded),
        label: const Text('تأكيد الموقع'),
      ),
    );
  }
}
