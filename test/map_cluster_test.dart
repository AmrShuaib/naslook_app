import 'package:flutter_test/flutter_test.dart';

import 'package:naslook/api/models.dart';
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
