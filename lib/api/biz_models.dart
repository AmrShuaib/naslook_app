import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import 'commerce_models.dart';
import 'models.dart';

Map<String, dynamic> _m(dynamic v) => asMap(v);
DateTime? _t(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
int _i(dynamic v) => v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;
double? _d(dynamic v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');
/// قائمة نصوص (asList في models.dart تحوّل العناصر إلى خرائط، فلا تصلح للنصوص).
List<String> _strings(dynamic v) => v is List ? v.map((e) => e.toString()).where((e) => e.isNotEmpty && e != '{}').toList() : const [];

/// فئات الدوائر التجارية وتخصصها.
enum BizCategory {
  brand('brand', 'براندات', 'براند عالمي', Icons.storefront_rounded),
  cinema('cinema', 'سينما', 'سينما', Icons.local_movies_rounded),
  hotel('hotel', 'فنادق', 'فندق', Icons.hotel_rounded),
  carRental('car_rental', 'تأجير سيارات', 'تأجير سيارات', Icons.directions_car_rounded);

  final String key;
  final String plural;
  final String label;
  final IconData icon;
  const BizCategory(this.key, this.plural, this.label, this.icon);

  static BizCategory of(String? key) => values.firstWhere((c) => c.key == key, orElse: () => BizCategory.brand);

  /// نوع العنصر الرئيسي في كتالوج هذه الفئة.
  String get itemKind => switch (this) { brand => 'product', cinema => 'showtime', hotel => 'room', carRental => 'car' };
  String get catalogTitle => switch (this) { brand => 'المنتجات', cinema => 'العروض', hotel => 'الغرف', carRental => 'السيارات' };
  String get actionLabel => switch (this) { brand => 'اشترِ', cinema => 'احجز تذاكر', hotel => 'احجز', carRental => 'احجز' };
  String get orderNoun => switch (this) { brand => 'طلب', cinema => 'تذكرة', hotel => 'حجز فندقي', carRental => 'حجز سيارة' };
}

/// دائرة تجارية (براند/سينما/فندق/تأجير سيارات).
class Biz {
  final String id, name, nameAr, sector, description, address, hours;
  final BizCategory category;
  final double lat, lng;
  final String? phone, website, colorHex;
  final List<String> highlights;
  final bool verified, official, following;
  final int followers, ratingCount, itemsCount;
  final double? rating;
  final int? minPrice;
  final List<BizItem> items;
  final List<BizReview> reviews;
  final List<BizOrder> myOrders;
  final List<BizPost> posts;
  final String? logoUrl, coverUrl, ownerId, myRole;
  final bool active;
  final int views;
  final DateTime? createdAt;

  const Biz({
    required this.id, required this.name, this.nameAr = '', required this.category, this.sector = '', this.description = '', required this.lat, required this.lng,
    this.address = '', this.hours = '', this.phone, this.website, this.colorHex, this.highlights = const [], this.verified = false, this.official = false,
    this.following = false, this.followers = 0, this.rating, this.ratingCount = 0, this.minPrice, this.itemsCount = 0, this.items = const [], this.reviews = const [], this.myOrders = const [],
    this.posts = const [], this.logoUrl, this.coverUrl, this.ownerId, this.myRole, this.active = true, this.views = 0, this.createdAt,
  });

  factory Biz.fromJson(Map m) => Biz(
        id: m['id'].toString(), name: m['name']?.toString() ?? '', nameAr: m['nameAr']?.toString() ?? '', category: BizCategory.of(m['category']?.toString()),
        sector: m['sector']?.toString() ?? '', description: m['description']?.toString() ?? '', lat: _d(m['lat']) ?? 0, lng: _d(m['lng']) ?? 0,
        address: m['address']?.toString() ?? '', hours: m['hours']?.toString() ?? '', phone: m['phone']?.toString(), website: m['website']?.toString(), colorHex: m['color']?.toString(),
        highlights: _strings(m['highlights']), verified: m['verified'] == true, official: m['official'] == true, following: m['following'] == true,
        followers: _i(m['followers']), rating: _d(m['rating']), ratingCount: _i(m['ratingCount']), minPrice: m['minPrice'] == null ? null : _i(m['minPrice']), itemsCount: _i(m['itemsCount']),
        items: asList(m['items']).map(BizItem.fromJson).toList(), reviews: asList(m['reviews']).map(BizReview.fromJson).toList(), myOrders: asList(m['myOrders']).map(BizOrder.fromJson).toList(),
        posts: asList(m['posts']).map(BizPost.fromJson).toList(), logoUrl: m['logoUrl']?.toString(), coverUrl: m['coverUrl']?.toString(), ownerId: m['ownerId']?.toString(), myRole: m['myRole']?.toString(),
        active: m['active'] != false, views: _i(m['views']), createdAt: _t(m['createdAt']),
      );

  bool get isOwner => myRole == 'owner' || myRole == 'admin';
  bool get canManage => isOwner || myRole == 'manager';
  bool get canOperate => canManage || myRole == 'staff';
  String get roleLabel => switch (myRole) { 'owner' => 'مالك', 'admin' => 'مدير النظام', 'manager' => 'مدير', 'staff' => 'موظف', _ => '' };

  /// الاسم المعروض: العربي إن وُجد.
  String get title => nameAr.isNotEmpty ? nameAr : name;
  Color get color {
    final h = colorHex?.replaceFirst('#', '');
    if (h == null || h.length != 6) return Joy.primary;
    return Color(int.parse('FF$h', radix: 16));
  }

  /// لون النص فوق لون العلامة.
  Color get onColor => color.computeLuminance() > 0.5 ? Joy.text : Colors.white;

  /// تمثيل الدائرة كعنصر خريطة (للتوافق مع طبقة المتاجر).
  Business toBusiness() => Business(id: id, name: title, category: sector.isNotEmpty ? sector : category.label, description: description, lat: lat, lng: lng, verified: verified, followers: followers, kind: category.key);
}

/// عنصر في الكتالوج: منتج أو عرض سينمائي أو غرفة أو سيارة.
class BizItem {
  final String id, bizId, kind, title, description, unit;
  final int price;
  final int? stock;
  final Map<String, dynamic> meta;
  final String? imageUrl;
  final List<Showtime> slots;
  final bool active;
  final int sort;
  const BizItem({required this.id, required this.bizId, required this.kind, required this.title, this.description = '', required this.price, this.unit = 'item', this.stock, this.meta = const {}, this.imageUrl, this.slots = const [], this.active = true, this.sort = 0});
  factory BizItem.fromJson(Map m) => BizItem(
        id: m['id'].toString(), bizId: m['bizId']?.toString() ?? '', kind: m['kind']?.toString() ?? 'product', title: m['title']?.toString() ?? '', description: m['description']?.toString() ?? '',
        price: _i(m['price']), unit: m['unit']?.toString() ?? 'item', stock: m['stock'] == null ? null : _i(m['stock']), meta: _m(m['meta']), imageUrl: m['imageUrl']?.toString(),
        slots: asList(m['slots']).map(Showtime.fromJson).toList(), active: m['active'] != false, sort: _i(m['sort']),
      );
  int? get oldPrice => meta['oldPrice'] == null ? null : _i(meta['oldPrice']);
  bool get isOffer => oldPrice != null && oldPrice! > price;
  String get unitLabel => switch (unit) { 'night' => 'لليلة', 'day' => 'لليوم', 'ticket' => 'للتذكرة', _ => '' };
  bool get soldOut => kind == 'product' && stock != null && stock! <= 0;
}

class Showtime {
  final DateTime startsAt;
  final int seatsLeft;
  const Showtime({required this.startsAt, required this.seatsLeft});
  factory Showtime.fromJson(Map m) => Showtime(startsAt: _t(m['startsAt']) ?? DateTime.now(), seatsLeft: _i(m['seatsLeft']));
}

class BizReview {
  final Person user;
  final int rating;
  final String text;
  final DateTime? createdAt, replyAt;
  final bool mine;
  final String? reply;
  const BizReview({required this.user, required this.rating, this.text = '', this.createdAt, this.mine = false, this.reply, this.replyAt});
  factory BizReview.fromJson(Map m) => BizReview(user: Person.fromJson(_m(m['user'])), rating: _i(m['rating']), text: m['text']?.toString() ?? '', createdAt: _t(m['createdAt']), mine: m['mine'] == true, reply: (m['reply']?.toString().isNotEmpty == true) ? m['reply'].toString() : null, replyAt: _t(m['replyAt']));
}

/// خبر أو عرض تنشره الدائرة.
class BizPost {
  final String id, bizId, kind, title, body;
  final String? imageUrl;
  final DateTime? startsAt, endsAt, createdAt;
  final bool active;
  const BizPost({required this.id, required this.bizId, required this.kind, required this.title, this.body = '', this.imageUrl, this.startsAt, this.endsAt, this.createdAt, this.active = true});
  factory BizPost.fromJson(Map m) => BizPost(id: m['id'].toString(), bizId: m['bizId']?.toString() ?? '', kind: m['kind']?.toString() ?? 'news', title: m['title']?.toString() ?? '', body: m['body']?.toString() ?? '', imageUrl: m['imageUrl']?.toString(), startsAt: _t(m['startsAt']), endsAt: _t(m['endsAt']), createdAt: _t(m['createdAt']), active: m['active'] != false);
  bool get isOffer => kind == 'offer';
  bool get expired => endsAt != null && endsAt!.isBefore(DateTime.now());
}

/// إحصاءات الدائرة لصاحبها.
class BizStats {
  final int ordersTotal, confirmed, used, cancelled, ordersLast7, next24h, customers, followers, reviews, unanswered, views;
  final int revenueTotal, revenueLast7, revenueLast30;
  final double? rating;
  final List<({String kind, int count, int total})> byKind;
  final List<({DateTime day, int orders, int revenue})> daily;
  final List<({String itemId, String title, int count, int total})> topItems;
  const BizStats({
    this.ordersTotal = 0, this.confirmed = 0, this.used = 0, this.cancelled = 0, this.ordersLast7 = 0, this.next24h = 0, this.customers = 0, this.followers = 0, this.reviews = 0, this.unanswered = 0, this.views = 0,
    this.revenueTotal = 0, this.revenueLast7 = 0, this.revenueLast30 = 0, this.rating, this.byKind = const [], this.daily = const [], this.topItems = const [],
  });
  factory BizStats.fromJson(Map m) {
    final o = _m(m['orders']), r = _m(m['revenue']);
    return BizStats(
      ordersTotal: _i(o['total']), confirmed: _i(o['confirmed']), used: _i(o['used']), cancelled: _i(o['cancelled']), ordersLast7: _i(o['last7']), next24h: _i(o['next24h']), customers: _i(o['customers']),
      revenueTotal: _i(r['total']), revenueLast7: _i(r['last7']), revenueLast30: _i(r['last30']), rating: _d(m['rating']),
      followers: _i(m['followers']), reviews: _i(m['reviews']), unanswered: _i(m['unanswered']), views: _i(m['views']),
      byKind: [for (final k in asList(m['byKind'])) (kind: k['kind']?.toString() ?? '', count: _i(k['count']), total: _i(k['total']))],
      daily: [for (final d in asList(m['daily'])) (day: DateTime.tryParse(d['day']?.toString() ?? '') ?? DateTime.now(), orders: _i(d['orders']), revenue: _i(d['revenue']))],
      topItems: [for (final t in asList(m['topItems'])) (itemId: t['itemId']?.toString() ?? '', title: t['title']?.toString() ?? '', count: _i(t['count']), total: _i(t['total']))],
    );
  }
}

class BizStaff {
  final Person user;
  final String role;
  final DateTime? since;
  const BizStaff({required this.user, required this.role, this.since});
  factory BizStaff.fromJson(Map m) => BizStaff(user: Person.fromJson(_m(m['user'])), role: m['role']?.toString() ?? 'staff', since: _t(m['since']));
  String get roleLabel => role == 'manager' ? 'مدير' : 'موظف';
}

class BizTeam {
  final Person? owner;
  final List<BizStaff> staff;
  const BizTeam({this.owner, this.staff = const []});
  factory BizTeam.fromJson(Map m) => BizTeam(owner: m['owner'] is Map ? Person.fromJson(_m(m['owner'])) : null, staff: asList(m['staff']).map(BizStaff.fromJson).toList());
}

class BizClaim {
  final String bizId, name, status, note;
  final Person? user;
  final DateTime? createdAt;
  const BizClaim({required this.bizId, required this.name, this.status = 'pending', this.note = '', this.user, this.createdAt});
  factory BizClaim.fromJson(Map m) => BizClaim(bizId: m['bizId']?.toString() ?? '', name: m['name']?.toString() ?? '', status: m['status']?.toString() ?? 'pending', note: m['note']?.toString() ?? '', user: m['user'] is Map ? Person.fromJson(_m(m['user'])) : null, createdAt: _t(m['createdAt']));
  String get statusLabel => switch (status) { 'approved' => 'مقبول', 'rejected' => 'مرفوض', _ => 'قيد المراجعة' };
}

/// دوائري: ما أملكه أو أعمل فيه، وطلبات الملكية.
class MyBusinesses {
  final List<Biz> circles;
  final List<BizClaim> claims;
  final bool admin;
  const MyBusinesses({this.circles = const [], this.claims = const [], this.admin = false});
  factory MyBusinesses.fromJson(Map m) => MyBusinesses(circles: asList(m['circles']).map(Biz.fromJson).toList(), claims: asList(m['claims']).map(BizClaim.fromJson).toList(), admin: m['admin'] == true);
}

/// طلب شراء أو حجز لدى دائرة تجارية.
class BizOrder {
  final String id, bizId, itemId, kind, status, code, note, title, bizName;
  final BizCategory category;
  final int qty, units, total;
  final DateTime? startAt, endAt, createdAt;
  final Map<String, dynamic> meta;
  final bool cancellable;
  final Person? customer;
  const BizOrder({
    required this.id, required this.bizId, required this.itemId, required this.kind, required this.status, required this.code, this.note = '', this.title = '', this.bizName = '',
    this.category = BizCategory.brand, this.qty = 1, this.units = 1, required this.total, this.startAt, this.endAt, this.createdAt, this.meta = const {}, this.cancellable = false, this.customer,
  });
  factory BizOrder.fromJson(Map m) => BizOrder(
        id: m['id'].toString(), bizId: m['bizId']?.toString() ?? '', itemId: m['itemId']?.toString() ?? '', kind: m['kind']?.toString() ?? 'product', status: m['status']?.toString() ?? 'confirmed',
        code: m['code']?.toString() ?? '', note: m['note']?.toString() ?? '', title: m['title']?.toString() ?? '', bizName: (m['bizNameAr']?.toString().isNotEmpty == true ? m['bizNameAr'] : m['bizName'])?.toString() ?? '',
        category: BizCategory.of(m['category']?.toString()), qty: _i(m['qty']), units: _i(m['units']), total: _i(m['total']), startAt: _t(m['startAt']), endAt: _t(m['endAt']), createdAt: _t(m['createdAt']),
        meta: _m(m['meta']), cancellable: m['cancellable'] == true, customer: m['customer'] is Map ? Person.fromJson(_m(m['customer'])) : null,
      );

  String get statusLabel => switch (status) { 'confirmed' => 'مؤكد', 'used' => 'مستخدم', 'cancelled' => 'ملغى', _ => status };
  String get kindLabel => switch (kind) { 'showtime' => 'تذاكر سينما', 'room' => 'حجز فندقي', 'car' => 'حجز سيارة', _ => 'طلب شراء' };
  bool get upcoming => status == 'confirmed' && (startAt == null || startAt!.isAfter(DateTime.now().subtract(const Duration(hours: 6))));

  /// وصف مختصر للكمية والمدة: "3 تذاكر" أو "غرفتان × ليلتان".
  String get summary => switch (kind) {
        'showtime' => '$qty ${qty == 1 ? 'تذكرة' : 'تذاكر'}',
        'room' => '$qty ${qty == 1 ? 'غرفة' : 'غرف'} × $units ${units == 1 ? 'ليلة' : 'ليالٍ'}',
        'car' => '$units ${units == 1 ? 'يوم' : 'أيام'}',
        _ => '$qty × ${money(total ~/ (qty == 0 ? 1 : qty))}',
      };
}
