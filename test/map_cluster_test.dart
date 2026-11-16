import 'package:flutter_test/flutter_test.dart';

import 'package:naslook/api/models.dart';
import 'package:naslook/api/row_api.dart';
import 'package:naslook/pages/map/map_cluster.dart';

MapItem _pin(String id, double lat, double lng, {Duration? ago}) => MapItem.pin(Pin(
      id: id, ownerId: 'SA1', ownerNickname: 'x', lat: lat, lng: lng, type: 'note', content: 'c',
      createdAt: ago == null ? null : DateTime.now().subtract(ago),
    ));

void main() {
  group('clusterItems', () {
    test('groups items that overlap on screen and keeps distant ones apart', () {
      // نقطتان على بعد ~30 متراً ونقطة ثالثة على بعد ~3 كم
      final items = [_pin('a', 21.5000, 39.2000), _pin('b', 21.5002, 39.2001), _pin('c', 21.5300, 39.2000)];
      final z13 = clusterItems(items, zoom: 13);
      expect(z13.length, 2);
      expect(z13.firstWhere((c) => !c.isSingle).count, 2);
      expect(z13.firstWhere((c) => c.isSingle).first.id, 'c');
    });

    test('separates near items when zoomed in far enough', () {
      // ~120 متراً: تُجمع عند 13 وتنفصل عند 17
      final items = [_pin('a', 21.5000, 39.2000), _pin('b', 21.5010, 39.2005)];
      expect(clusterItems(items, zoom: 13).length, 1);
      expect(clusterItems(items, zoom: 17).length, 2);
    });

    test('is deterministic regardless of input order', () {
      final a = [_pin('a', 21.50, 39.20), _pin('b', 21.5001, 39.2001), _pin('c', 21.52, 39.22), _pin('d', 21.5201, 39.2201)];
      final r1 = clusterItems(a, zoom: 12).map((c) => c.items.map((i) => i.id).join(',')).toList();
      final r2 = clusterItems(a.reversed, zoom: 12).map((c) => c.items.map((i) => i.id).join(',')).toList();
      expect(r1, r2);
      expect(r1.length, 2);
    });

    test('exposes counts, dominant kind and bounds', () {
      final s = MapItem.story(const Story(id: 's', userId: 'u', nickname: 'n', type: 'text', content: 'c', caption: '', lat: 21.5001, lng: 39.2001))!;
      final c = clusterItems([_pin('a', 21.5, 39.2), _pin('b', 21.5002, 39.2002), s], zoom: 12).single;
      expect(c.count, 3);
      expect(c.counts[MapItemKind.pin], 2);
      expect(c.counts[MapItemKind.story], 1);
      expect(c.dominant, MapItemKind.pin);
      expect(c.bounds.minLat, 21.5);
      expect(c.bounds.maxLng, 39.2002);
    });

    test('radius shrinks with zoom', () {
      expect(clusterRadiusFor(10) > clusterRadiusFor(14), isTrue);
      expect(clusterRadiusFor(14) > clusterRadiusFor(17), isTrue);
    });
  });

  group('groupPins (home map)', () {
    test('merges crowded pins, keeps the shown card pin and people alone, and orders clusters first and the kept pin last', () {
      final me = MapItem.person(const Presence(id: 'SA9', nickname: 'sara', lat: 21.5001, lng: 39.2001));
      // أربعة متلاصقة (~20 م) واحد منها بطاقة الصف المعروضة، وشخص بينها، ودبّوس بعيد
      final items = [_pin('a', 21.5000, 39.2000), _pin('b', 21.5001, 39.2000), _pin('c', 21.5000, 39.2001), _pin('sel', 21.5001, 39.2001), me, _pin('far', 21.5300, 39.2000)];
      final g = groupPins(items, zoom: 14, keepKey: 'pin:sel');
      expect(g.length, 4);
      expect(g[0].count, 3, reason: 'المجموعة أولاً');
      expect(g[0].items.map((i) => i.id).toSet(), {'a', 'b', 'c'});
      expect(g[1].first.id, 'far');
      expect(g[2].first.kind, MapItemKind.person, reason: 'صورة الصديق لا تدخل دائرة برقم');
      expect(g.last.isSingle, isTrue);
      expect(g.last.first.id, 'sel', reason: 'المختار آخراً فيُرسم فوق الجميع');
      // مركز المجموعة متوسط عناصرها
      expect(g[0].lat, closeTo((21.5000 + 21.5001 + 21.5000) / 3, 1e-9));
      // بلا مختار: الأربعة مجموعة واحدة
      expect(groupPins(items, zoom: 14).first.count, 4);
    });

    test('the same pins separate when zoomed in, and a custom radius is honoured', () {
      // ~110 م بين المتجاورين
      final items = [_pin('a', 21.500, 39.200), _pin('b', 21.501, 39.200), _pin('c', 21.502, 39.200)];
      expect(groupPins(items, zoom: 12).single.count, 3);
      expect(groupPins(items, zoom: 16).length, 3);
      expect(groupPins(items, zoom: 16).every((c) => c.isSingle), isTrue);
      expect(groupPins(items, zoom: 16, radiusPx: 400).single.count, 3);
      expect(groupPins(const [], zoom: 12), isEmpty);
    });

    test('filter kinds: row kinds map to their chips, layer pins to theirs, people and legacy pins only under «الكل»', () {
      expect(mapFilterIds, ['all', 'moment', 'offer', 'event', 'listing', 'circle', 'job']);
      expect([for (final id in mapFilterIds) mapFilterLabel(id)], ['الكل', 'لحظات', 'عروض', 'فعاليات', 'السوق', 'دوائر', 'وظائف']);
      expect(rowFilterKind(const RowItem(kind: 'job', id: 'j')), 'job');
      expect(rowFilterKind(const RowItem(kind: 'hologram', id: 'h')), 'moment', reason: 'نوع غير معروف بطاقته «لحظة»');
      final ev = MapItem.row(const RowItem(kind: 'event', id: 'e', lat: 21.5, lng: 39.2))!;
      final biz = MapItem.business(const Business(id: 'b', name: 'n', category: 'c', description: '', lat: 21.5, lng: 39.2))!;
      final person = MapItem.person(const Presence(id: 'SA9', nickname: 'sara', lat: 21.5, lng: 39.2));
      expect(mapFilterKind(ev), 'event');
      expect(mapFilterKind(biz), 'circle');
      expect(mapFilterKind(_pin('a', 21.5, 39.2)), isNull);
      expect(mapFilterKind(person), isNull);
      expect(mapFilterAllows('all', person), isTrue);
      expect(mapFilterAllows('circle', person), isFalse);
      expect(mapFilterAllows('circle', biz), isTrue);
      expect(mapFilterAllows('event', biz), isFalse);
    });
  });

  test('MapItem.story and business need coordinates', () {
    expect(MapItem.story(const Story(id: 's', userId: 'u', nickname: 'n', type: 'text', content: 'c', caption: '')), isNull);
    expect(MapItem.business(const Business(id: 'b', name: 'n', category: 'c', description: '')), isNull);
    expect(MapItem.business(const Business(id: 'b', name: 'n', category: 'c', description: '', lat: 1, lng: 2))!.kind, MapItemKind.business);
  });

  test('sortForPanel puts newest first and timeless items last', () {
    final biz = MapItem.business(const Business(id: 'b', name: 'متجر', category: 'c', description: '', lat: 21.5, lng: 39.2))!;
    final old = _pin('old', 21.5, 39.2, ago: const Duration(hours: 5));
    final fresh = _pin('fresh', 21.5, 39.2, ago: const Duration(minutes: 1));
    final sorted = sortForPanel([biz, old, fresh]);
    expect(sorted.map((i) => i.id).toList(), ['fresh', 'old', 'b']);
  });

  test('itemsInBounds filters by the visible box', () {
    final items = [_pin('in', 21.5, 39.2), _pin('out', 21.9, 39.2)];
    final r = itemsInBounds(items, minLat: 21.4, minLng: 39.1, maxLat: 21.6, maxLng: 39.3);
    expect(r.map((i) => i.id).toList(), ['in']);
  });

  test('person item carries an author for the profile page', () {
    final p = MapItem.person(const Presence(id: 'SA2', nickname: 'sara', lat: 1, lng: 2, online: true, title: 'قهوة'));
    expect(p.author?.id, 'SA2');
    expect(p.subtitle, 'قهوة');
    expect(p.key, 'person:SA2');
  });
}
