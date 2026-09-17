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

/// الأنواع التي تُحجز بموعد محدد (عرض سينمائي أو عيادة).
bool isSlotKind(String kind) => kind == 'showtime' || kind == 'clinic';

/// فئات الدوائر التجارية وتخصصها.
enum BizCategory {
  brand('brand', 'براندات', 'براند عالمي', Icons.storefront_rounded),
  cinema('cinema', 'سينما', 'سينما', Icons.local_movies_rounded),
  hotel('hotel', 'فنادق', 'فندق', Icons.hotel_rounded),
  carRental('car_rental', 'تأجير سيارات', 'تأجير سيارات', Icons.directions_car_rounded),
  hospital('hospital', 'مستشفيات', 'مستشفى', Icons.local_hospital_rounded),
  airport('airport', 'مطارات', 'مطار', Icons.flight_takeoff_rounded),
  cafe('cafe', 'مقاهٍ مختصة', 'مقهى مختص', Icons.coffee_rounded),
  restaurant('restaurant', 'مطاعم', 'مطعم', Icons.restaurant_rounded),
  company('company', 'شركات كبرى', 'شركة', Icons.corporate_fare_rounded),
  university('university', 'جامعات', 'جامعة', Icons.school_rounded);

  final String key;
  final String plural;
  final String label;
  final IconData icon;
  const BizCategory(this.key, this.plural, this.label, this.icon);

  static BizCategory of(String? key) => values.firstWhere((c) => c.key == key, orElse: () => BizCategory.brand);

  /// نوع العنصر الرئيسي في كتالوج هذه الفئة.
  String get itemKind => switch (this) { brand => 'product', cinema => 'showtime', hotel => 'room', carRental => 'car', hospital => 'clinic', airport => 'info', cafe => 'product', restaurant => 'product', company => 'info', university => 'info' };
  String get catalogTitle => switch (this) { brand => 'المنتجات', cinema => 'العروض', hotel => 'الغرف', carRental => 'السيارات', hospital => 'العيادات والخدمات', airport => 'مرافق المطار والخدمات', cafe => 'القائمة', restaurant => 'القائمة', company => 'الخدمات والأقسام', university => 'الكليات والخدمات' };
  String get actionLabel => switch (this) { brand => 'اشترِ', cinema => 'احجز تذاكر', hotel => 'احجز', carRental => 'احجز', hospital => 'احجز موعداً', airport => 'التفاصيل', cafe => 'اطلب', restaurant => 'اطلب', company => 'التفاصيل', university => 'التفاصيل' };
  String get orderNoun => switch (this) { brand => 'طلب', cinema => 'تذكرة', hotel => 'حجز فندقي', carRental => 'حجز سيارة', hospital => 'موعد', airport => 'طلب', cafe => 'طلب', restaurant => 'طلب', company => 'طلب', university => 'طلب' };
}

/// دائرة تجارية (براند/سينما/فندق/تأجير سيارات/مستشفى/مطار).
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
  /// مفتوح الآن بتوقيت السعودية (null إن لم تُفهم ساعات العمل)، والمسافة بالكيلومتر من موقع المستخدم إن مُرِّر، والعنصر المطابق لكلمة البحث.
  final bool? openNow;
  final double? distanceKm;
  final String? matchedItem;
  /// عدد العروض السارية وأقرب انتهاء (من server/offers.js).
  final int offers;
  final DateTime? offerEndsAt;

  const Biz({
    required this.id, required this.name, this.nameAr = '', required this.category, this.sector = '', this.description = '', required this.lat, required this.lng,
    this.address = '', this.hours = '', this.phone, this.website, this.colorHex, this.highlights = const [], this.verified = false, this.official = false,
    this.following = false, this.followers = 0, this.rating, this.ratingCount = 0, this.minPrice, this.itemsCount = 0, this.items = const [], this.reviews = const [], this.myOrders = const [],
    this.posts = const [], this.logoUrl, this.coverUrl, this.ownerId, this.myRole, this.active = true, this.views = 0, this.createdAt, this.openNow, this.distanceKm, this.matchedItem, this.offers = 0, this.offerEndsAt,
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
        openNow: m['openNow'] is bool ? m['openNow'] as bool : null, distanceKm: _d(m['distanceKm']), matchedItem: m['matchedItem']?.toString(), offers: _i(m['offers']), offerEndsAt: _t(m['offerEndsAt']),
      );

  /// نص المسافة: «850 م» أو «3.2 كم».
  String? get distanceLabel {
    final d = distanceKm;
    if (d == null) return null;
    return d < 1 ? '${(d * 1000).round()} م' : '${d.toStringAsFixed(d < 10 ? 1 : 0)} كم';
  }

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
  /// عدد مشاركات وردود المجتمع التي تقتبس هذا المنتج.
  final int discussions;
  /// عرض سعر فعّال على هذا العنصر (deal) إن وُجد.
  final ItemDeal? deal;
  const BizItem({required this.id, required this.bizId, required this.kind, required this.title, this.description = '', required this.price, this.unit = 'item', this.stock, this.meta = const {}, this.imageUrl, this.slots = const [], this.active = true, this.sort = 0, this.discussions = 0, this.deal});
  factory BizItem.fromJson(Map m) => BizItem(
        id: m['id'].toString(), bizId: m['bizId']?.toString() ?? '', kind: m['kind']?.toString() ?? 'product', title: m['title']?.toString() ?? '', description: m['description']?.toString() ?? '',
        price: _i(m['price']), unit: m['unit']?.toString() ?? 'item', stock: m['stock'] == null ? null : _i(m['stock']), meta: _m(m['meta']), imageUrl: m['imageUrl']?.toString(),
        slots: asList(m['slots']).map(Showtime.fromJson).toList(), active: m['active'] != false, sort: _i(m['sort']), discussions: _i(m['discussions']), deal: m['deal'] is Map ? ItemDeal.fromJson(_m(m['deal'])) : null,
      );
  int? get oldPrice => deal != null ? price : (meta['oldPrice'] == null ? null : _i(meta['oldPrice']));
  /// السعر الذي يدفعه المستخدم فعلاً: سعر العرض إن وُجد.
  int get payPrice => deal?.price ?? price;
  bool get isOffer => deal != null || (oldPrice != null && oldPrice! > price);
  String get unitLabel => switch (unit) { 'night' => 'لليلة', 'day' => 'لليوم', 'ticket' => 'للتذكرة', 'visit' => 'للزيارة', _ => '' };
  bool get isFree => price == 0;
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
/// عرض سعر فعّال على عنصر.
class ItemDeal {
  final String id, title;
  final int price;
  final bool membersOnly;
  final DateTime? endsAt;
  const ItemDeal({required this.id, required this.title, required this.price, this.membersOnly = false, this.endsAt});
  factory ItemDeal.fromJson(Map m) => ItemDeal(id: m['id'].toString(), title: m['title']?.toString() ?? '', price: _i(m['price']), membersOnly: m['membersOnly'] == true, endsAt: _t(m['endsAt']));
}

/// عرض طُبّق على طلب.
class OrderOffer {
  final String id, kind, title;
  final int discount, before;
  const OrderOffer({required this.id, this.kind = 'coupon', this.title = '', this.discount = 0, this.before = 0});
  factory OrderOffer.fromJson(Map m) => OrderOffer(id: m['id'].toString(), kind: m['kind']?.toString() ?? 'coupon', title: m['title']?.toString() ?? '', discount: _i(m['discount']), before: _i(m['before']));
}

class BizOrder {
  final String id, bizId, itemId, kind, status, code, note, title, bizName;
  final BizCategory category;
  final int qty, units, total;
  final DateTime? startAt, endAt, createdAt;
  final Map<String, dynamic> meta;
  final bool cancellable;
  final Person? customer;
  final OrderOffer? offer;
  const BizOrder({this.offer,
    required this.id, required this.bizId, required this.itemId, required this.kind, required this.status, required this.code, this.note = '', this.title = '', this.bizName = '',
    this.category = BizCategory.brand, this.qty = 1, this.units = 1, required this.total, this.startAt, this.endAt, this.createdAt, this.meta = const {}, this.cancellable = false, this.customer,
  });
  factory BizOrder.fromJson(Map m) => BizOrder(
        id: m['id'].toString(), bizId: m['bizId']?.toString() ?? '', itemId: m['itemId']?.toString() ?? '', kind: m['kind']?.toString() ?? 'product', status: m['status']?.toString() ?? 'confirmed',
        code: m['code']?.toString() ?? '', note: m['note']?.toString() ?? '', title: m['title']?.toString() ?? '', bizName: (m['bizNameAr']?.toString().isNotEmpty == true ? m['bizNameAr'] : m['bizName'])?.toString() ?? '',
        category: BizCategory.of(m['category']?.toString()), qty: _i(m['qty']), units: _i(m['units']), total: _i(m['total']), startAt: _t(m['startAt']), endAt: _t(m['endAt']), createdAt: _t(m['createdAt']),
        meta: _m(m['meta']), cancellable: m['cancellable'] == true, customer: m['customer'] is Map ? Person.fromJson(_m(m['customer'])) : null, offer: m['offer'] is Map ? OrderOffer.fromJson(_m(m['offer'])) : null,
      );

  String get statusLabel => switch (status) { 'confirmed' => 'مؤكد', 'used' => 'مستخدم', 'cancelled' => 'ملغى', _ => status };
  String get kindLabel => switch (kind) { 'showtime' => 'تذاكر سينما', 'clinic' => 'موعد عيادة', 'room' => 'حجز فندقي', 'car' => 'حجز سيارة', _ => 'طلب شراء' };
  bool get upcoming => status == 'confirmed' && (startAt == null || startAt!.isAfter(DateTime.now().subtract(const Duration(hours: 6))));

  /// وصف مختصر للكمية والمدة: "3 تذاكر" أو "غرفتان × ليلتان".
  String get summary => switch (kind) {
        'showtime' => '$qty ${qty == 1 ? 'تذكرة' : 'تذاكر'}',
        'clinic' => 'موعد لشخص واحد',
        'room' => '$qty ${qty == 1 ? 'غرفة' : 'غرف'} × $units ${units == 1 ? 'ليلة' : 'ليالٍ'}',
        'car' => '$units ${units == 1 ? 'يوم' : 'أيام'}',
        _ => '$qty × ${money(total ~/ (qty == 0 ? 1 : qty))}',
      };
}


// ------------------------------------------------------------------ العروض (server/offers.js)

/// قيمة العرض: percent | amount | price | free_item بالهللات.
class OfferValue {
  final String type;
  final int amount;
  const OfferValue({this.type = 'percent', this.amount = 0});
  factory OfferValue.fromJson(Map m) => OfferValue(type: m['type']?.toString() ?? 'percent', amount: _i(m['amount']));
  Map<String, dynamic> toJson() => {'type': type, if (type != 'free_item') 'amount': amount};
}

class OfferGrant {
  final String id, reason;
  final Person? from;
  final DateTime? expiresAt;
  const OfferGrant({required this.id, this.reason = 'transfer', this.from, this.expiresAt});
  factory OfferGrant.fromJson(Map m) => OfferGrant(id: m['id'].toString(), reason: m['reason']?.toString() ?? 'transfer', from: m['from'] is Map ? Person.fromJson(_m(m['from'])) : null, expiresAt: _t(m['expiresAt']));
}

class LoyaltyProgress {
  final int every, count, total;
  const LoyaltyProgress({this.every = 10, this.count = 0, this.total = 0});
  factory LoyaltyProgress.fromJson(Map m) => LoyaltyProgress(every: _i(m['every']), count: _i(m['count']), total: _i(m['total']));
}

class OfferStats {
  final int views, uses, discount, revenue, sent, rewards;
  const OfferStats({this.views = 0, this.uses = 0, this.discount = 0, this.revenue = 0, this.sent = 0, this.rewards = 0});
  factory OfferStats.fromJson(Map m) => OfferStats(views: _i(m['views']), uses: _i(m['uses']), discount: _i(m['discount']), revenue: _i(m['revenue']), sent: _i(m['sent']), rewards: _i(m['rewards']));
}

class OfferBizRef {
  final String id, name;
  final String? logoUrl, category;
  const OfferBizRef({required this.id, this.name = '', this.logoUrl, this.category});
  factory OfferBizRef.fromJson(Map m) => OfferBizRef(id: m['id'].toString(), name: m['name']?.toString() ?? '', logoUrl: m['logoUrl']?.toString(), category: m['category']?.toString());
}

/// عرض من دائرة: deal | coupon | checkin | loyalty مع أهلية المشاهد.
class BizOffer {
  final String id, bizId, kind, title, description, state;
  final OfferValue value;
  final String? itemId, itemTitle, template, lockedReason, note, via;
  final int? itemPrice, left;
  final Map<String, dynamic> conditions;
  final bool membersOnly, transferable, active, eligible, usedByMe, canSend;
  final DateTime? startsAt, endsAt, createdAt;
  final OfferGrant? grant;
  final LoyaltyProgress? loyalty;
  final OfferStats? stats;
  final OfferBizRef? biz;
  const BizOffer({required this.id, required this.bizId, required this.kind, required this.title, this.description = '', this.state = 'active', this.value = const OfferValue(), this.itemId, this.itemTitle, this.template, this.lockedReason, this.note, this.via, this.itemPrice, this.left, this.conditions = const {}, this.membersOnly = true, this.transferable = true, this.active = true, this.eligible = false, this.usedByMe = false, this.canSend = false, this.startsAt, this.endsAt, this.createdAt, this.grant, this.loyalty, this.stats, this.biz});
  factory BizOffer.fromJson(Map m) => BizOffer(
        id: m['id'].toString(), bizId: m['bizId']?.toString() ?? '', kind: m['kind']?.toString() ?? 'coupon', title: m['title']?.toString() ?? '', description: m['description']?.toString() ?? '', state: m['state']?.toString() ?? 'active',
        value: m['value'] is Map ? OfferValue.fromJson(_m(m['value'])) : const OfferValue(), itemId: m['itemId']?.toString(), itemTitle: m['itemTitle']?.toString(), template: m['template']?.toString(),
        lockedReason: m['lockedReason']?.toString(), note: m['note']?.toString(), via: m['via']?.toString(), itemPrice: m['itemPrice'] == null ? null : _i(m['itemPrice']), left: m['left'] == null ? null : _i(m['left']),
        conditions: _m(m['conditions']), membersOnly: m['membersOnly'] == true, transferable: m['transferable'] == true, active: m['active'] != false, eligible: m['eligible'] == true, usedByMe: m['usedByMe'] == true, canSend: m['canSend'] == true,
        startsAt: _t(m['startsAt']), endsAt: _t(m['endsAt']), createdAt: _t(m['createdAt']), grant: m['grant'] is Map ? OfferGrant.fromJson(_m(m['grant'])) : null,
        loyalty: m['loyalty'] is Map ? LoyaltyProgress.fromJson(_m(m['loyalty'])) : null, stats: m['stats'] is Map ? OfferStats.fromJson(_m(m['stats'])) : null, biz: m['biz'] is Map ? OfferBizRef.fromJson(_m(m['biz'])) : null,
      );
  String get kindLabel => switch (kind) { 'deal' => 'سعر خاص', 'coupon' => 'كوبون', 'checkin' => 'لمن هنا الآن', 'loyalty' => 'مكافأة الرواد', _ => kind };
  /// سطر القيمة: «خصم 20٪» أو «10 ر.س خصم» أو «كورتادو بـ 10 ر.س» أو «كورتادو مجاني».
  String get valueLabel => switch (value.type) {
        'percent' => 'خصم ${value.amount}٪',
        'amount' => 'خصم ${(value.amount / 100).round()} ر.س',
        'price' => '${itemTitle ?? 'المنتج'} بـ ${(value.amount / 100).round()} ر.س',
        'free_item' => '${itemTitle ?? 'منتج'} مجاناً',
        _ => title,
      };
  /// شرط واحد في سطر (بلا فقرات).
  String get conditionLabel {
    final parts = <String>[];
    if (conditions['firstOrder'] == true) parts.add('لأول طلب');
    if (conditions['minTotal'] != null) parts.add('لطلب من ${(_i(conditions['minTotal']) / 100).round()} ر.س');
    if (kind == 'checkin') parts.add('وأنت في المكان');
    if (kind == 'loyalty') parts.add('كل ${_i(conditions['every'])} طلبات مستلمة');
    if (left != null) parts.add('بقي $left');
    if (membersOnly && kind != 'loyalty') parts.add('للأعضاء');
    return parts.join(' · ');
  }
  bool get endingSoon => endsAt != null && endsAt!.difference(DateTime.now()).inHours < 2;
  String get lockedLabel => switch (lockedReason) { 'members' => 'للأعضاء · انضم لتستخدمه', 'used' => 'استخدمته', 'used-today' => 'استخدمته اليوم', 'sold-out' => 'نفدت الكمية', 'loyalty' => 'يُفتح بالطلبات', 'first-order' => 'لأول طلب فقط', 'ended' => 'انتهى', 'upcoming' => 'يبدأ لاحقاً', _ => '' };
}

class BizOffersPage {
  final String bizId;
  final bool member;
  final String? notify;
  final List<BizOffer> active, upcoming, past;
  const BizOffersPage({this.bizId = '', this.member = false, this.notify, this.active = const [], this.upcoming = const [], this.past = const []});
  factory BizOffersPage.fromJson(Map m) => BizOffersPage(bizId: m['bizId']?.toString() ?? '', member: m['member'] == true, notify: m['notify']?.toString(), active: asList(m['active']).map(BizOffer.fromJson).toList(), upcoming: asList(m['upcoming']).map(BizOffer.fromJson).toList(), past: asList(m['past']).map(BizOffer.fromJson).toList());
}

class OfferUse {
  final String id, offerId, title, kind;
  final int amount;
  final int? orderTotal;
  final String? orderId, orderCode, itemTitle;
  final DateTime? usedAt;
  final OfferBizRef biz;
  const OfferUse({required this.id, required this.offerId, this.title = '', this.kind = 'coupon', this.amount = 0, this.orderTotal, this.orderId, this.orderCode, this.itemTitle, this.usedAt, required this.biz});
  factory OfferUse.fromJson(Map m) => OfferUse(id: m['id'].toString(), offerId: m['offerId']?.toString() ?? '', title: m['title']?.toString() ?? '', kind: m['kind']?.toString() ?? 'coupon', amount: _i(m['amount']), orderTotal: m['orderTotal'] == null ? null : _i(m['orderTotal']), orderId: m['orderId']?.toString(), orderCode: m['orderCode']?.toString(), itemTitle: m['itemTitle']?.toString(), usedAt: _t(m['usedAt']), biz: OfferBizRef.fromJson(_m(m['biz'])));
}

/// عروضي: المتاح الآن من دوائري، المستخدم مع التوفير، والمنتهي خلال 30 يوماً.
class MyOffers {
  final List<BizOffer> active, expired;
  final List<OfferUse> used;
  final int savingsMonth, savingsTotal, uses;
  const MyOffers({this.active = const [], this.expired = const [], this.used = const [], this.savingsMonth = 0, this.savingsTotal = 0, this.uses = 0});
  factory MyOffers.fromJson(Map m) { final s = _m(m['savings']); return MyOffers(active: asList(m['active']).map(BizOffer.fromJson).toList(), expired: asList(m['expired']).map(BizOffer.fromJson).toList(), used: asList(m['used']).map(OfferUse.fromJson).toList(), savingsMonth: _i(s['month']), savingsTotal: _i(s['total']), uses: _i(s['uses'])); }
}

class OfferTemplate {
  final String id, name, kind, hint;
  final OfferValue value;
  final int? hours, days;
  final Map<String, dynamic> conditions;
  final bool membersOnly, transferable, needsItem;
  const OfferTemplate({required this.id, required this.name, required this.kind, this.hint = '', this.value = const OfferValue(), this.hours, this.days, this.conditions = const {}, this.membersOnly = true, this.transferable = true, this.needsItem = false});
  factory OfferTemplate.fromJson(Map m) => OfferTemplate(id: m['id'].toString(), name: m['name']?.toString() ?? '', kind: m['kind']?.toString() ?? 'coupon', hint: m['hint']?.toString() ?? '', value: m['value'] is Map ? OfferValue.fromJson(_m(m['value'])) : const OfferValue(), hours: m['hours'] == null ? null : _i(m['hours']), days: m['days'] == null ? null : _i(m['days']), conditions: _m(m['conditions']), membersOnly: m['membersOnly'] != false, transferable: m['transferable'] != false, needsItem: m['needsItem'] == true);
}

class ManageOffers {
  final List<BizOffer> offers;
  final List<OfferTemplate> templates;
  final int members;
  const ManageOffers({this.offers = const [], this.templates = const [], this.members = 0});
  factory ManageOffers.fromJson(Map m) => ManageOffers(offers: asList(m['offers']).map(BizOffer.fromJson).toList(), templates: asList(m['templates']).map(OfferTemplate.fromJson).toList(), members: _i(m['members']));
}
