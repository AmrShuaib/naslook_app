// أسماء الدوائر على الخريطة: وضع بلا تداخل بترتيب الأولوية، مواضع بديلة حول النقطة، حدّ أقصى بحسب التكبير، وحجم الخط،
// وعدم تغطية نقاط الدوائر الأخرى، وتجاهل ما خرج عن الشاشة، وعرض الطبقة داخل FlutterMap بهالة بيضاء.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:naslook/api/models.dart';
import 'package:naslook/pages/map/map_cluster.dart';
import 'package:naslook/pages/map/map_labels.dart';

double _w(String t, double fs) => t.length * fs * .6;
LabelCandidate _c(String k, double x, double y, {double pr = 0, String? text}) => LabelCandidate(key: k, text: text ?? k, at: Offset(x, y), dot: 17, priority: pr);

void main() {
  const screen = Size(400, 800);

  test('labels never overlap each other or any dot; higher priority wins the spot', () {
    final placed = placeLabels([_c('low', 200, 300, pr: 1, text: 'مقهى الشارع'), _c('high', 200, 312, pr: 5, text: 'برو 92')], screen: screen, fontSize: 12, budget: 10, measure: _w);
    expect(placed.map((p) => p.c.key).toList(), ['high', 'low'], reason: 'الأعلى أولوية يُوضع أولاً');
    for (var i = 0; i < placed.length; i++) {
      for (var j = i + 1; j < placed.length; j++) {
        expect(placed[i].rect.overlaps(placed[j].rect), isFalse);
      }
      for (final dot in [const Offset(200, 300), const Offset(200, 312)]) {
        expect(placed[i].rect.overlaps(Rect.fromCircle(center: dot, radius: 8.5)), isFalse, reason: 'الاسم لا يغطي نقطة دائرة');
      }
    }
    expect(placed.first.side, 'below');
    expect(placed.last.side, isNot('below'), reason: 'المكان تحت النقطة محجوز فيُجرَّب موضع آخر');
  });

  test('falls back through right, left and above before giving up', () {
    // نقطة «ب» تقع حيث كان اسم «أ» سيُكتب تحتها، فيُدفع اسم «أ» إلى اليمين ويبقى اسم «ب» تحتها
    final placed = placeLabels([_c('a', 200, 400, pr: 9, text: 'أ'), _c('b', 200, 419, pr: 8, text: 'ب')], screen: screen, fontSize: 12, budget: 10, measure: _w);
    expect(placed.map((p) => '${p.c.key}:${p.side}').toList(), ['a:right', 'b:below']);
    // مرشّح يُحاصَر من كل الجهات فيُخفى بدل أن يتداخل
    final crowded = placeLabels([
      _c('c', 200, 400, pr: 9, text: 'مركز'),
      _c('below', 200, 430, pr: 8, text: 'تحت'),
      _c('right', 240, 400, pr: 7, text: 'يمين'),
      _c('left', 160, 400, pr: 6, text: 'يسار'),
      _c('above', 200, 370, pr: 5, text: 'فوق'),
    ], screen: screen, fontSize: 12, budget: 10, measure: _w);
    expect(crowded.length, lessThan(5));
    expect(crowded.map((p) => p.c.key), isNot(contains('c')), reason: 'النقاط الأربع حوله تحجز المواضع كلها فيُخفى اسمه');
    for (var i = 0; i < crowded.length; i++) {
      for (var j = i + 1; j < crowded.length; j++) {
        expect(crowded[i].rect.overlaps(crowded[j].rect), isFalse);
      }
    }
  });

  test('budget and font follow the zoom; off-screen candidates are ignored', () {
    expect(labelBudget(10), 0);
    expect(labelBudget(13), 16);
    expect(labelBudget(16), 80);
    expect(labelFontSize(12), 11);
    expect(labelFontSize(16.5), 13);
    final many = [for (var i = 0; i < 20; i++) _c('k$i', 40.0 + i * 15, 100.0 + i * 30, pr: 20 - i.toDouble())];
    final placed = placeLabels(many, screen: screen, fontSize: 11, budget: 5, measure: _w);
    expect(placed.length, 5);
    expect(placed.map((p) => p.c.key).toList(), ['k0', 'k1', 'k2', 'k3', 'k4']);
    expect(placeLabels([_c('out', -200, -200), _c('in', 100, 100)], screen: screen, fontSize: 11, budget: 5, measure: _w).map((p) => p.c.key).toList(), ['in']);
    expect(placeLabels([_c('x', 100, 100)], screen: screen, fontSize: 11, budget: 0, measure: _w), isEmpty);
  });

  test('priority: verified first, then followers; category colors differ', () {
    const a = Business(id: 'a', name: 'قهوة', category: 'c', description: '', followers: 500);
    const b = Business(id: 'b', name: 'مطعم طويل الاسم جداً', category: 'c', description: '', verified: true, followers: 10);
    expect(businessPriority(b), greaterThan(businessPriority(a)));
    expect(labelColorFor('cafe'), isNot(labelColorFor('hotel')));
  });

  testWidgets('label layer renders circle names inside FlutterMap with a white halo and opens the item on tap', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final items = [
      MapItem.business(const Business(id: 'brew', name: 'برو 92', category: 'مقهى', description: '', lat: 21.5433, lng: 39.1728, verified: true, followers: 40, kind: 'cafe'))!,
      MapItem.business(const Business(id: 'over', name: 'أوفردوز', category: 'مقهى', description: '', lat: 21.5420, lng: 39.1760, followers: 12, kind: 'cafe'))!,
      MapItem.person(const Presence(id: 'SA2', nickname: 'sara', lat: 21.544, lng: 39.170, online: true, title: '')),
    ];
    MapItem? tapped;
    await tester.pumpWidget(MaterialApp(
      home: FlutterMap(
        options: const MapOptions(initialCenter: LatLng(21.5433, 39.1728), initialZoom: 15),
        children: [MapLabelLayer(items: items, dot: 22, onTap: (it) => tapped = it)],
      ),
    ));
    await tester.pump();
    expect(find.text('برو 92'), findsNWidgets(2), reason: 'طبقتان: هالة بيضاء ثم النص الملون');
    expect(find.text('أوفردوز'), findsNWidgets(2));
    expect(find.text('sara'), findsNothing, reason: 'الأشخاص بلا أسماء على الخريطة');
    final halo = tester.widgetList<Text>(find.text('برو 92')).first;
    expect(halo.style!.foreground!.style, PaintingStyle.stroke);
    await tester.tap(find.byKey(const ValueKey('label-business:brew')));
    await tester.pump();
    expect(tapped?.id, 'brew');
  });
}
