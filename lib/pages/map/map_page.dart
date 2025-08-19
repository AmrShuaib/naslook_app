import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  late List<Marker> userMarkers;
  late List<Marker> circleMarkers;
  late List<Marker> eventMarkers;

  bool showUsers = true;
  bool showCircles = true;
  bool showEvents = true;

  @override
  void initState() {
    super.initState();
    final random = Random();
    userMarkers = List.generate(10, (index) {
      final lat = 24.7136 + random.nextDouble() * 0.1 - 0.05;
      final lng = 46.6753 + random.nextDouble() * 0.1 - 0.05;
      return Marker(
        point: LatLng(lat, lng),
        width: 50,
        height: 50,
        child: GestureDetector(
          onTap: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Text('نقطة $index'),
                content: Text('إحداثيات: ($lat, $lng)'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('إغلاق'),
                  ),
                ],
              ),
            );
          },
          child: const Icon(
            Icons.person_pin,
            color: Colors.deepPurple,
            size: 50,
          ),
        ),
      );
    });

    // تحديث أيقونة المستخدم "ميم سين"
    userMarkers.add(
      Marker(
        point: LatLng(21.4858, 39.1925),
        width: 50,
        height: 50,
        child: GestureDetector(
          onTap: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('ميم سين'),
                content: const Text('هذا المستخدم موجود في جدة.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('إغلاق'),
                  ),
                ],
              ),
            );
          },
          child: const Icon(Icons.star, color: Colors.blueAccent, size: 50),
        ),
      ),
    );

    circleMarkers = [
      Marker(
        point: LatLng(24.7236, 46.6853),
        width: 50,
        height: 50,
        child: GestureDetector(
          onTap: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('دائرة'),
                content: const Text('تفاصيل الدائرة هنا.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('إغلاق'),
                  ),
                ],
              ),
            );
          },
          child: const Icon(
            Icons.group_work,
            color: Colors.greenAccent,
            size: 50,
          ),
        ),
      ),
    ];

    eventMarkers = [
      Marker(
        point: LatLng(24.7336, 46.6953),
        width: 50,
        height: 50,
        child: GestureDetector(
          onTap: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('فعالية'),
                content: const Text('تفاصيل الفعالية هنا.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('إغلاق'),
                  ),
                ],
              ),
            );
          },
          child: const Icon(
            Icons.event_available,
            color: Colors.redAccent,
            size: 50,
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الخريطة التفاعلية'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() {
                if (value == 'users') showUsers = !showUsers;
                if (value == 'circles') showCircles = !showCircles;
                if (value == 'events') showEvents = !showEvents;
              });
            },
            itemBuilder: (context) => [
              CheckedPopupMenuItem(
                value: 'users',
                checked: showUsers,
                child: const Text('عرض المستخدمين'),
              ),
              CheckedPopupMenuItem(
                value: 'circles',
                checked: showCircles,
                child: const Text('عرض الدوائر'),
              ),
              CheckedPopupMenuItem(
                value: 'events',
                checked: showEvents,
                child: const Text('عرض الفعاليات'),
              ),
            ],
          ),
        ],
      ),
      body: FlutterMap(
        options: MapOptions(
          center: LatLng(21.4858, 39.1925), // تحديث المركز إلى جدة
          zoom: 12,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.naslook',
          ),
          if (showUsers) MarkerLayer(markers: userMarkers),
          if (showCircles) MarkerLayer(markers: circleMarkers),
          if (showEvents) MarkerLayer(markers: eventMarkers),
        ],
      ),
    );
  }
}
