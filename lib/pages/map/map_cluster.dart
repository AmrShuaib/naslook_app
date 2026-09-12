import 'dart:math' as math;

import '../../api/models.dart';

/// نوع العنصر المعروض على الخريطة.
enum MapItemKind { person, story, pin, business }

/// عنصر موحّد على الخريطة (شخص/لحظة/دبوس/متجر) مع موقعه وصاحبه ووقته.
class MapItem {
  final MapItemKind kind;
  final String id;
  final double lat;
  final double lng;
  final String title;
  final String subtitle;
  final DateTime? at;
  final Person? author;
  final Object data;

  const MapItem({
    required this.kind,
    required this.id,
    required this.lat,
    required this.lng,
    required this.title,
    this.subtitle = '',
    this.at,
    this.author,
    required this.data,
  });

  String get key => '${kind.name}:$id';

  factory MapItem.person(Presence p) => MapItem(
        kind: MapItemKind.person,
        id: p.id,
        lat: p.lat,
        lng: p.lng,
        title: p.me ? '${p.nickname} (أنت)' : p.nickname,
        subtitle: p.title.isNotEmpty ? p.title : (p.online ? 'متصل الآن' : 'كان هنا'),
        at: p.updatedAt,
        author: Person(id: p.id, nickname: p.nickname, avatarUrl: p.avatarUrl, online: p.online),
        data: p,
      );

  static MapItem? story(Story s) {
    if (s.lat == null || s.lng == null) return null;
    return MapItem(
      kind: MapItemKind.story,
      id: s.id,
      lat: s.lat!,
      lng: s.lng!,
      title: s.nickname,
      subtitle: s.caption.isNotEmpty ? s.caption : (s.type == 'text' ? s.content : 'لحظة ${s.type == 'video' ? 'فيديو' : 'صورة'}'),
      at: s.createdAt,
      author: Person(id: s.userId, nickname: s.nickname, avatarUrl: s.avatarUrl),
      data: s,
    );
  }

  factory MapItem.pin(Pin p) => MapItem(
        kind: MapItemKind.pin,
        id: p.id,
        lat: p.lat,
        lng: p.lng,
        title: p.placeName?.isNotEmpty == true ? p.placeName! : p.ownerNickname,
        subtitle: p.content,
        at: p.createdAt,
        author: Person(id: p.ownerId, nickname: p.ownerNickname, avatarUrl: p.ownerAvatar),
        data: p,
      );

  static MapItem? business(Business b) {
    if (b.lat == null || b.lng == null) return null;
    return MapItem(
      kind: MapItemKind.business,
      id: b.id,
      lat: b.lat!,
      lng: b.lng!,
      title: b.name,
      subtitle: [b.category, if (b.followers > 0) '${b.followers} متابع'].join(' · '),
      data: b,
    );
  }
}

/// مجموعة عناصر متقاربة على الشاشة.
class MapCluster {
  final List<MapItem> items;
  final double lat;
  final double lng;
  const MapCluster(this.items, this.lat, this.lng);

  int get count => items.length;
  bool get isSingle => items.length == 1;
  MapItem get first => items.first;

  Map<MapItemKind, int> get counts {
    final m = <MapItemKind, int>{};
    for (final i in items) {
      m[i.kind] = (m[i.kind] ?? 0) + 1;
    }
    return m;
  }

  /// النوع الغالب داخل المجموعة (يُستخدم للون الفقاعة).
  MapItemKind get dominant {
    MapItemKind best = items.first.kind;
    var bestN = 0;
    counts.forEach((k, n) {
      if (n > bestN) {
        best = k;
        bestN = n;
      }
    });
    return best;
  }

  ({double minLat, double minLng, double maxLat, double maxLng}) get bounds {
    var minLat = items.first.lat, maxLat = items.first.lat, minLng = items.first.lng, maxLng = items.first.lng;
    for (final i in items) {
      if (i.lat < minLat) minLat = i.lat;
      if (i.lat > maxLat) maxLat = i.lat;
      if (i.lng < minLng) minLng = i.lng;
      if (i.lng > maxLng) maxLng = i.lng;
    }
    return (minLat: minLat, minLng: minLng, maxLat: maxLat, maxLng: maxLng);
  }
}

/// إسقاط ويب-مركاتور إلى بكسلات العالم عند مستوى تكبير معيّن (بلاطة 256 بكسل).
math.Point<double> projectToPixels(double lat, double lng, double zoom) {
  final scale = 256.0 * math.pow(2.0, zoom);
  final x = (lng + 180.0) / 360.0 * scale;
  final phi = lat.clamp(-85.05112878, 85.05112878) * math.pi / 180.0;
  final y = (1.0 - math.log(math.tan(phi) + 1.0 / math.cos(phi)) / math.pi) / 2.0 * scale;
  return math.Point(x, y);
}

/// نصف قطر التجميع المناسب بالبكسل لمستوى التكبير: تجميع واسع عند التصغير،
/// وعند التقريب الشديد يُدمج فقط ما يتراكب فعلياً.
double clusterRadiusFor(double zoom) {
  if (zoom >= 16.5) return 14;
  if (zoom >= 15) return 26;
  if (zoom >= 13) return 40;
  return 56;
}

/// يجمع العناصر المتقاربة على الشاشة (بالبكسل) في مجموعات.
/// الخوارزمية حريصة ومحددة النتيجة: تُرتَّب العناصر ثم يُلحق كل عنصر بأقرب
/// مجموعة قائمة ضمن [radiusPx]، وإلا يبدأ مجموعة جديدة.
List<MapCluster> clusterItems(Iterable<MapItem> items, {required double zoom, double? radiusPx}) {
  final r = radiusPx ?? clusterRadiusFor(zoom);
  final sorted = items.toList()
    ..sort((a, b) {
      final c = b.lat.compareTo(a.lat);
      return c != 0 ? c : a.lng.compareTo(b.lng);
    });
  final clusters = <_Acc>[];
  for (final it in sorted) {
    final p = projectToPixels(it.lat, it.lng, zoom);
    _Acc? best;
    var bestD = double.infinity;
    for (final c in clusters) {
      final d = c.center.distanceTo(p);
      if (d <= r && d < bestD) {
        best = c;
        bestD = d;
      }
    }
    if (best == null) {
      clusters.add(_Acc(it, p));
    } else {
      best.add(it, p);
    }
  }
  return [for (final c in clusters) MapCluster(List.unmodifiable(c.items), c.lat, c.lng)];
}

class _Acc {
  final items = <MapItem>[];
  double sx = 0, sy = 0, slat = 0, slng = 0;
  _Acc(MapItem first, math.Point<double> p) {
    add(first, p);
  }
  void add(MapItem it, math.Point<double> p) {
    items.add(it);
    sx += p.x;
    sy += p.y;
    slat += it.lat;
    slng += it.lng;
  }

  math.Point<double> get center => math.Point(sx / items.length, sy / items.length);
  double get lat => slat / items.length;
  double get lng => slng / items.length;
}

/// ترتيب عناصر المنطقة للعرض في اللوحة: الأحدث أولاً، والمتاجر (بلا وقت) آخراً.
List<MapItem> sortForPanel(Iterable<MapItem> items) {
  final list = items.toList();
  list.sort((a, b) {
    final ta = a.at, tb = b.at;
    if (ta == null && tb == null) return a.title.compareTo(b.title);
    if (ta == null) return 1;
    if (tb == null) return -1;
    return tb.compareTo(ta);
  });
  return list;
}

/// العناصر الواقعة داخل الحدود المرئية.
List<MapItem> itemsInBounds(Iterable<MapItem> items, {required double minLat, required double minLng, required double maxLat, required double maxLng}) =>
    [for (final i in items) if (i.lat >= minLat && i.lat <= maxLat && i.lng >= minLng && i.lng <= maxLng) i];
