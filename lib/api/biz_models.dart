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

/// الأنواع التي تُحجز بموعد محدد (عرض سينمائي أو موعد عيادة أو خدمة).
bool isSlotKind(String kind) => kind == 'showtime' || kind == 'clinic';

/// أيام المواعيد بترقيم الخادم نفسه (0 = الأحد … 6 = السبت، كـ getUTCDay بتوقيت السعودية في business.js)،
/// مرتّبة للعرض من السبت إلى الجمعة.
const appointmentWeekdays = [(6, 'السبت'), (0, 'الأحد'), (1, 'الاثنين'), (2, 'الثلاثاء'), (3, 'الأربعاء'), (4, 'الخميس'), (5, 'الجمعة')];

/// وصف مختصر لأيام العمل: «كل الأيام» أو «الأحد – الخميس» أو أسماء الأيام متتالية بترتيب الأسبوع.
String workDaysLabel(List<int>? days) {
  if (days == null || days.isEmpty || days.toSet().length >= 7) return 'كل الأيام';
  final set = days.toSet();
  final ordered = [for (final (d, name) in appointmentWeekdays) if (set.contains(d)) name];
  // مدى متصل في ترتيب الأسبوع (السبت أولاً): يُختصر بأوله وآخره
  final idx = [for (final (i, (d, _)) in appointmentWeekdays.indexed) if (set.contains(d)) i];
  final contiguous = idx.length >= 3 && idx.last - idx.first == idx.length - 1;
  return contiguous ? '${ordered.first} – ${ordered.last}' : ordered.join('، ');
}

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
  university('university', 'جامعات', 'جامعة', Icons.school_rounded),
  // فئات التسجيل الذاتي (أكتوبر 2026): أي نشاط محلي يسجّل دائرته بنفسه
  shop('shop', 'متاجر', 'متجر', Icons.shopping_bag_rounded),
  services('services', 'خدمات وورش', 'خدمات وورش', Icons.handyman_rounded),
  salon('salon', 'صالونات وتجميل', 'صالون وتجميل', Icons.content_cut_rounded),
  clinic('clinic', 'عيادات', 'عيادة', Icons.medical_services_rounded),
  entertainment('entertainment', 'ترفيه', 'ترفيه', Icons.attractions_rounded),
  other('other', 'أخرى', 'أخرى', Icons.category_rounded);

  final String key;
  final String plural;
  final String label;
  final IconData icon;
  const BizCategory(this.key, this.plural, this.label, this.icon);

  static BizCategory of(String? key) => values.firstWhere((c) => c.key == key, orElse: () => BizCategory.brand);

  /// نوع العنصر الرئيسي في كتالوج هذه الفئة.
  String get itemKind => switch (this) { brand => 'product', cinema => 'showtime', hotel => 'room', carRental => 'car', hospital => 'clinic', airport => 'info', cafe => 'product', restaurant => 'product', company => 'info', university => 'info', shop => 'product', services => 'product', salon => 'clinic', clinic => 'clinic', entertainment => 'showtime', other => 'info' };
  String get catalogTitle => switch (this) { brand => 'المنتجات', cinema => 'العروض', hotel => 'الغرف', carRental => 'السيارات', hospital => 'العيادات والخدمات', airport => 'مرافق المطار والخدمات', cafe => 'القائمة', restaurant => 'القائمة', company => 'الخدمات والأقسام', university => 'الكليات والخدمات', shop => 'المنتجات', services => 'الخدمات', salon => 'الخدمات والمواعيد', clinic => 'العيادات والمواعيد', entertainment => 'الفعاليات والتذاكر', other => 'الخدمات' };
  String get actionLabel => switch (this) { brand => 'اشترِ', cinema => 'احجز تذاكر', hotel => 'احجز', carRental => 'احجز', hospital => 'احجز موعداً', airport => 'التفاصيل', cafe => 'اطلب', restaurant => 'اطلب', company => 'التفاصيل', university => 'التفاصيل', shop => 'اشترِ', services => 'اطلب', salon => 'احجز موعداً', clinic => 'احجز موعداً', entertainment => 'احجز تذاكر', other => 'التفاصيل' };
  String get orderNoun => switch (this) { brand => 'طلب', cinema => 'تذكرة', hotel => 'حجز فندقي', carRental => 'حجز سيارة', hospital => 'موعد', airport => 'طلب', cafe => 'طلب', restaurant => 'طلب', company => 'طلب', university => 'طلب', shop => 'طلب', services => 'طلب', salon => 'موعد', clinic => 'موعد', entertainment => 'تذكرة', other => 'طلب' };

  /// أنواع الأصناف التي يضيفها المالك (الأول هو الافتراضي): الصالون والخدمات يجمعان المواعيد والمنتجات.
  List<String> get itemKinds => switch (this) { salon => const ['clinic', 'product'], services => const ['product', 'clinic'], _ => [itemKind] };

  /// صنف الموعد (clinic) بلغة العيادة للمستشفى والعيادة، وبلغة الخدمة لغيرهما (صالون، خدمات وورش).
  bool get clinicWords => this == hospital || this == clinic;

  /// أيقونة صنف الموعد بحسب الفئة.
  IconData get appointmentIcon => switch (this) { salon => Icons.content_cut_rounded, services => Icons.handyman_outlined, _ => Icons.medical_services_outlined };
}

/// «HH:MM» بالتوقيت المحلي (لبطاقة «هنا اليوم حتى …»).
String clockLabel(DateTime t) {
  final l = t.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

/// نطاق خدمة الدائرة المتنقلة: مركز ونصف قطر بالكيلومتر وأحياء اختيارية.
class ServiceArea {
  final double lat, lng, radiusKm;
  final List<String> districts;
  const ServiceArea({required this.lat, required this.lng, this.radiusKm = 15, this.districts = const []});
  factory ServiceArea.fromJson(Map m) => ServiceArea(lat: _d(m['lat']) ?? 0, lng: _d(m['lng']) ?? 0, radiusKm: _d(m['radiusKm']) ?? 15, districts: _strings(m['districts']));
  /// «يخدم ضمن 15 كم».
  String get label => 'يخدم ضمن ${radiusKm % 1 == 0 ? radiusKm.toInt() : radiusKm} كم';
}

/// دبوس «هنا اليوم» المؤقت: موقع حتى ساعة محددة.
class HerePin {
  final double lat, lng;
  final DateTime until;
  const HerePin({required this.lat, required this.lng, required this.until});
  factory HerePin.fromJson(Map m) => HerePin(lat: _d(m['lat']) ?? 0, lng: _d(m['lng']) ?? 0, until: _t(m['until']) ?? DateTime.now());
  bool get active => until.isAfter(DateTime.now());
  /// «هنا اليوم حتى 18:00».
  String get label => 'هنا اليوم حتى ${clockLabel(until)}';
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
  /// التسجيل الموثّق (server/biz_onboard.js): الحضور (fixed|mobile)، نطاق الخدمة للمتنقلة، دبوس «هنا اليوم»،
  /// حالة التوثيق (none|pending|approved|rejected)، هل يُسمح بالبيع، الدرجة (published|complete|verified|active)،
  /// نوع الكيان (للفريق فقط)، وتوثيق الجوال.
  final String presence;
  final ServiceArea? serviceArea;
  final HerePin? here;
  final String verificationStatus, tier;
  final bool canSell, phoneVerified;
  final String? entityKind;
  /// الكيان النظامي للعامة بعد اعتماد التوثيق فقط (سجل تجاري أو وثيقة عمل حر ورقمها)؛ null قبله.
  final BizEntity? entity;

  const Biz({
    required this.id, required this.name, this.nameAr = '', required this.category, this.sector = '', this.description = '', required this.lat, required this.lng,
    this.address = '', this.hours = '', this.phone, this.website, this.colorHex, this.highlights = const [], this.verified = false, this.official = false,
    this.following = false, this.followers = 0, this.rating, this.ratingCount = 0, this.minPrice, this.itemsCount = 0, this.items = const [], this.reviews = const [], this.myOrders = const [],
    this.posts = const [], this.logoUrl, this.coverUrl, this.ownerId, this.myRole, this.active = true, this.views = 0, this.createdAt, this.openNow, this.distanceKm, this.matchedItem, this.offers = 0, this.offerEndsAt,
    this.presence = 'fixed', this.serviceArea, this.here, this.verificationStatus = 'none', this.tier = 'published', this.canSell = false, this.phoneVerified = false, this.entityKind,
    this.entity,
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
        presence: m['presence'] == 'mobile' ? 'mobile' : 'fixed', serviceArea: m['serviceArea'] is Map ? ServiceArea.fromJson(_m(m['serviceArea'])) : null, here: m['here'] is Map ? HerePin.fromJson(_m(m['here'])) : null,
        verificationStatus: m['verificationStatus']?.toString() ?? (m['verified'] == true ? 'approved' : 'none'), tier: m['tier']?.toString() ?? 'published',
        canSell: m['canSell'] is bool ? m['canSell'] as bool : m['verified'] == true, phoneVerified: m['phoneVerified'] == true, entityKind: m['entityKind']?.toString(),
        entity: BizEntity.tryParse(m['entity']),
      );

  bool get isMobile => presence == 'mobile';
  /// دبوس «هنا اليوم» ساري الآن.
  bool get hereActive => here?.active == true;
  String get tierLabel => tierLabelOf(tier);
  String get verificationLabel => verificationLabelOf(verificationStatus);

  /// نص المسافة: «850 م» أو «3.2 كم».
  String? get distanceLabel {
    final d = distanceKm;
    if (d == null) return null;
    return d < 1 ? '${(d * 1000).round()} م' : '${d.toStringAsFixed(d < 10 ? 1 : 0)} كم';
  }

  bool get isOwner => myRole == 'owner' || myRole == 'admin';
  bool get canManage => isOwner || myRole == 'manager';
  bool get canOperate => canManage || myRole == 'staff' || myRole == 'hr';
  /// التوظيف: المالك والمدير ودور «توظيف» (hr) يديرون العروض والمرشحين
  bool get canHire => canManage || myRole == 'hr';
  String get roleLabel => switch (myRole) { 'owner' => 'مالك', 'admin' => 'مدير النظام', 'manager' => 'مدير', 'staff' => 'موظف', 'hr' => 'توظيف', _ => '' };

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
  /// يقبل «احجز الآن وادفع في المكان» (يفعّله صاحب الدائرة لكل صنف؛ مطفأ افتراضياً).
  final bool payAtVenue;
  const BizItem({required this.id, required this.bizId, required this.kind, required this.title, this.description = '', required this.price, this.unit = 'item', this.stock, this.meta = const {}, this.imageUrl, this.slots = const [], this.active = true, this.sort = 0, this.discussions = 0, this.deal, this.payAtVenue = false});
  factory BizItem.fromJson(Map m) => BizItem(
        id: m['id'].toString(), bizId: m['bizId']?.toString() ?? '', kind: m['kind']?.toString() ?? 'product', title: m['title']?.toString() ?? '', description: m['description']?.toString() ?? '',
        price: _i(m['price']), unit: m['unit']?.toString() ?? 'item', stock: m['stock'] == null ? null : _i(m['stock']), meta: _m(m['meta']), imageUrl: m['imageUrl']?.toString(),
        slots: asList(m['slots']).map(Showtime.fromJson).toList(), active: m['active'] != false, sort: _i(m['sort']), discussions: _i(m['discussions']), deal: m['deal'] is Map ? ItemDeal.fromJson(_m(m['deal'])) : null,
        payAtVenue: m['payAtVenue'] == true,
      );
  /// الدفع في المكان متاح لهذا الصنف المدفوع.
  bool get venueOk => payAtVenue && price > 0;
  int? get oldPrice => deal != null ? price : (meta['oldPrice'] == null ? null : _i(meta['oldPrice']));
  /// السعر الذي يدفعه المستخدم فعلاً: سعر العرض إن وُجد.
  int get payPrice => deal?.price ?? price;
  bool get isOffer => deal != null || (oldPrice != null && oldPrice! > price);
  String get unitLabel => switch (unit) { 'night' => 'لليلة', 'day' => 'لليوم', 'ticket' => 'للتذكرة', 'visit' => 'للزيارة', _ => '' };
  bool get isFree => price == 0;
  bool get soldOut => kind == 'product' && stock != null && stock! <= 0;
  /// أيام عمل صنف الموعد كما حفظها المالك (0 = الأحد … 6 = السبت)؛ null = كل الأيام.
  List<int>? get workDays {
    final d = meta['days'];
    if (d is! List || d.isEmpty) return null;
    final out = [for (final v in d) if (v is num && v >= 0 && v <= 6) v.toInt()];
    return out.isEmpty ? null : out;
  }
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
  /// المال: المحجوز حتى الاستلام والمُحرَّر لمحفظة صاحب الدائرة والدفع في المكان.
  final BizMoney money;
  const BizStats({
    this.money = const BizMoney(),
    this.ordersTotal = 0, this.confirmed = 0, this.used = 0, this.cancelled = 0, this.ordersLast7 = 0, this.next24h = 0, this.customers = 0, this.followers = 0, this.reviews = 0, this.unanswered = 0, this.views = 0,
    this.revenueTotal = 0, this.revenueLast7 = 0, this.revenueLast30 = 0, this.rating, this.byKind = const [], this.daily = const [], this.topItems = const [],
  });
  factory BizStats.fromJson(Map m) {
    final o = _m(m['orders']), r = _m(m['revenue']);
    return BizStats(
      ordersTotal: _i(o['total']), confirmed: _i(o['confirmed']), used: _i(o['used']), cancelled: _i(o['cancelled']), ordersLast7: _i(o['last7']), next24h: _i(o['next24h']), customers: _i(o['customers']),
      revenueTotal: _i(r['total']), revenueLast7: _i(r['last7']), revenueLast30: _i(r['last30']), rating: _d(m['rating']), money: BizMoney.fromJson(_m(m['money'])),
      followers: _i(m['followers']), reviews: _i(m['reviews']), unanswered: _i(m['unanswered']), views: _i(m['views']),
      byKind: [for (final k in asList(m['byKind'])) (kind: k['kind']?.toString() ?? '', count: _i(k['count']), total: _i(k['total']))],
      daily: [for (final d in asList(m['daily'])) (day: DateTime.tryParse(d['day']?.toString() ?? '') ?? DateTime.now(), orders: _i(d['orders']), revenue: _i(d['revenue']))],
      topItems: [for (final t in asList(m['topItems'])) (itemId: t['itemId']?.toString() ?? '', title: t['title']?.toString() ?? '', count: _i(t['count']), total: _i(t['total']))],
    );
  }
}

/// مال الدائرة: المحجوز (ومنه المجمّد بنزاع) والمحرَّر، والدفع في المكان المستحق والمدفوع.
class BizMoney {
  final int held, disputed, released, venueDue, venuePaid, disputesOpen, noShows, holdDays;
  const BizMoney({this.held = 0, this.disputed = 0, this.released = 0, this.venueDue = 0, this.venuePaid = 0, this.disputesOpen = 0, this.noShows = 0, this.holdDays = 3});
  factory BizMoney.fromJson(Map m) => BizMoney(held: _i(m['held']), disputed: _i(m['disputed']), released: _i(m['released']), venueDue: _i(m['venueDue']), venuePaid: _i(m['venuePaid']),
      disputesOpen: _i(m['disputesOpen']), noShows: _i(m['noShows']), holdDays: m['holdDays'] == null ? 3 : _i(m['holdDays']));
  bool get isEmpty => held == 0 && released == 0 && venueDue == 0 && venuePaid == 0 && disputesOpen == 0;
}

class BizStaff {
  final Person user;
  final String role;
  final DateTime? since;
  const BizStaff({required this.user, required this.role, this.since});
  factory BizStaff.fromJson(Map m) => BizStaff(user: Person.fromJson(_m(m['user'])), role: m['role']?.toString() ?? 'staff', since: _t(m['since']));
  String get roleLabel => switch (role) { 'manager' => 'مدير', 'hr' => 'توظيف', _ => 'موظف' };
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
  /// wallet | at_venue | free
  final String payment;
  /// للدفع في المكان: هل أكّد صاحب الدائرة «تم الدفع»؟ (المحفظة والمجاني مدفوعان دائماً)
  final bool paid;
  /// للمدفوع من المحفظة: held (محجوز حتى الاستلام) | released | refunded | split | credited (طلب قديم قُيّد عند الشراء)
  final String? funds;
  final DateTime? paidAt, releaseAt, releasedAt, usedAt;
  final BizDispute? dispute;
  /// يستطيع العميل فتح «لدي مشكلة» على هذا الطلب الآن.
  final bool disputable;
  /// من يرى الطلب (GET /biz/orders/:id): customer | team | admin
  final String? viewer;
  /// مرات «لم يحضر» لهذا العميل في الدائرة (للفريق).
  final int? noShows;
  final Person? owner;
  const BizOrder({this.offer,
    required this.id, required this.bizId, required this.itemId, required this.kind, required this.status, required this.code, this.note = '', this.title = '', this.bizName = '',
    this.category = BizCategory.brand, this.qty = 1, this.units = 1, required this.total, this.startAt, this.endAt, this.createdAt, this.meta = const {}, this.cancellable = false, this.customer,
    this.payment = 'wallet', this.paid = true, this.funds, this.paidAt, this.releaseAt, this.releasedAt, this.usedAt, this.dispute, this.disputable = false, this.viewer, this.noShows, this.owner,
  });
  factory BizOrder.fromJson(Map m) => BizOrder(
        id: m['id'].toString(), bizId: m['bizId']?.toString() ?? '', itemId: m['itemId']?.toString() ?? '', kind: m['kind']?.toString() ?? 'product', status: m['status']?.toString() ?? 'confirmed',
        code: m['code']?.toString() ?? '', note: m['note']?.toString() ?? '', title: m['title']?.toString() ?? '', bizName: (m['bizNameAr']?.toString().isNotEmpty == true ? m['bizNameAr'] : m['bizName'])?.toString() ?? '',
        category: BizCategory.of(m['category']?.toString()), qty: _i(m['qty']), units: _i(m['units']), total: _i(m['total']), startAt: _t(m['startAt']), endAt: _t(m['endAt']), createdAt: _t(m['createdAt']),
        meta: _m(m['meta']), cancellable: m['cancellable'] == true, customer: m['customer'] is Map ? Person.fromJson(_m(m['customer'])) : null, offer: m['offer'] is Map ? OrderOffer.fromJson(_m(m['offer'])) : null,
        payment: m['payment']?.toString() ?? (_i(m['total']) > 0 ? 'wallet' : 'free'), paid: m['paid'] != false, funds: m['funds']?.toString(), paidAt: _t(m['paidAt']), releaseAt: _t(m['releaseAt']),
        releasedAt: _t(m['releasedAt']), usedAt: _t(m['usedAt']), dispute: m['dispute'] is Map ? BizDispute.fromJson(_m(m['dispute'])) : null, disputable: m['disputable'] == true,
        viewer: m['viewer']?.toString(), noShows: m['noShows'] == null ? null : _i(m['noShows']), owner: m['owner'] is Map ? Person.fromJson(_m(m['owner'])) : null,
      );

  String get statusLabel => switch (status) { 'confirmed' => 'مؤكد', 'used' => 'مستخدم', 'cancelled' => 'ملغى', 'no_show' => 'لم يحضر', _ => status };
  bool get atVenue => payment == 'at_venue';
  bool get fromWallet => payment == 'wallet';
  /// طلب دفع في المكان لم يُؤكَّد دفعه بعد (والطلب قائم).
  bool get venueUnpaid => atVenue && !paid && (status == 'confirmed' || status == 'used');
  bool get held => funds == 'held';
  bool get disputeOpen => dispute?.open == true;
  /// سطر الدفع كما يراه العميل.
  String get paymentLabel => switch (payment) {
        'at_venue' => paid ? 'دُفع في المكان' : 'الدفع في المكان: لم يُدفع بعد',
        'free' => 'مجاني',
        _ => switch (funds) {
            'held' => disputeOpen ? 'من المحفظة · المبلغ مجمّد حتى حسم النزاع' : 'من المحفظة · المبلغ محجوز حتى الاستلام',
            'refunded' => 'من المحفظة · استُرد المبلغ',
            'split' => 'من المحفظة · قُسم المبلغ',
            _ => 'من المحفظة',
          },
      };
  /// سطر المال كما يراه صاحب الدائرة.
  String get ownerMoneyLabel => switch (payment) {
        'at_venue' => paid ? 'دُفع في المكان' : 'الدفع في المكان: لم يُدفع بعد',
        'free' => 'مجاني',
        _ => switch (funds) {
            'held' => disputeOpen ? 'محجوز ومجمّد بنزاع' : releaseAt == null ? 'محجوز حتى الاستلام' : 'محجوز حتى الاستلام أو ${releaseAt!.day}/${releaseAt!.month}',
            'released' || 'credited' => 'في محفظتك',
            'refunded' => 'استُرد للعميل',
            'split' => 'قُسم مع العميل',
            _ => 'من المحفظة',
          },
      };
  String get kindLabel => switch (kind) { 'showtime' => 'تذاكر سينما', 'clinic' => category.clinicWords ? 'موعد عيادة' : 'موعد خدمة', 'room' => 'حجز فندقي', 'car' => 'حجز سيارة', _ => 'طلب شراء' };
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


/// نزاع «لدي مشكلة» على طلب دائرة: السبب والصور ورسائل الطرفين والإدارة وقرار الحسم.
class BizDispute {
  final String status, reason;
  final List<String> photos;
  final String? resolution, note;
  final List<BizDisputeMessage> messages;
  final DateTime? createdAt, resolvedAt;
  const BizDispute({required this.status, required this.reason, this.photos = const [], this.resolution, this.note, this.messages = const [], this.createdAt, this.resolvedAt});
  factory BizDispute.fromJson(Map m) => BizDispute(
        status: m['status']?.toString() ?? 'open', reason: m['reason']?.toString() ?? '', photos: [for (final p in asList(m['photos'])) p.toString()],
        resolution: m['resolution']?.toString(), note: m['note']?.toString(), messages: asList(m['messages']).map(BizDisputeMessage.fromJson).toList(),
        createdAt: _t(m['createdAt']), resolvedAt: _t(m['resolvedAt']),
      );
  bool get open => status == 'open';
  String get resolutionLabel => switch (resolution) { 'refund' => 'أُعيد المبلغ للعميل', 'release' => 'حُرّر المبلغ للدائرة', 'split' => 'قُسم المبلغ بين الطرفين', _ => 'قيد المراجعة' };
}

class BizDisputeMessage {
  /// customer | team | admin
  final String by, text;
  final DateTime? at;
  const BizDisputeMessage({required this.by, required this.text, this.at});
  factory BizDisputeMessage.fromJson(Map m) => BizDisputeMessage(by: m['by']?.toString() ?? 'customer', text: m['text']?.toString() ?? '', at: _t(m['at']));
  String get byLabel => switch (by) { 'team' => 'الدائرة', 'admin' => 'إدارة ناس لايف', _ => 'العميل' };
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


// ------------------------------------------------------------------ التسجيل الموثّق (server/biz_onboard.js)

/// يحوّل الأرقام العربية والفارسية إلى لاتينية (المستخدم يكتب ٠٥٥…).
String latinDigits(String s) {
  const ar = '٠١٢٣٤٥٦٧٨٩', fa = '۰۱۲۳۴۵۶۷۸۹';
  final b = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    final i = ar.contains(c) ? ar.indexOf(c) : fa.indexOf(c);
    b.write(i >= 0 ? '$i' : c);
  }
  return b.toString();
}

/// جوال سعودي بأي صيغة (05XXXXXXXX، 5XXXXXXXX، +9665…، 009665…) → `+9665XXXXXXXX`، أو null إن لم يكن صحيحاً.
String? normalizeSaudiMobile(String raw) {
  var s = latinDigits(raw).replaceAll(RegExp(r'[\s\-()]'), '');
  if (s.startsWith('+')) s = s.substring(1);
  if (s.startsWith('00')) s = s.substring(2);
  if (s.startsWith('966')) s = s.substring(3);
  if (s.startsWith('0')) s = s.substring(1);
  return RegExp(r'^5\d{8}$').hasMatch(s) ? '+966$s' : null;
}

String tierLabelOf(String tier) => switch (tier) { 'complete' => 'مكتملة', 'verified' => 'موثّقة', 'active' => 'نشطة', _ => 'منشورة' };
String verificationLabelOf(String status) => switch (status) { 'pending' => 'قيد المراجعة', 'approved' => 'موثّقة', 'rejected' => 'مرفوض', _ => 'غير موثّقة' };
/// الكيان النظامي المعتمد للدائرة كما يُعرض للعامة (server/business.js: entity).
class BizEntity {
  final String kind, number;
  const BizEntity(this.kind, this.number);
  static BizEntity? tryParse(Object? v) {
    if (v is! Map) return null;
    final k = v['kind']?.toString() ?? '', n = v['number']?.toString().trim() ?? '';
    return (k == 'cr' || k == 'freelance') && n.isNotEmpty ? BizEntity(k, n) : null;
  }
  /// «سجل تجاري رقم …» أو «وثيقة عمل حر رقم …».
  String get label => '${kind == 'cr' ? 'سجل تجاري' : 'وثيقة عمل حر'} رقم $number';
}

String entityKindLabel(String? kind) => switch (kind) { 'cr' => 'سجل تجاري', 'freelance' => 'وثيقة العمل الحر', _ => '—' };

/// حالة توثيق الدائرة كما تعود مع الاكتمال أو بعد الإرسال (السبب والمستند للفريق فقط).
class VerificationInfo {
  final String status;
  final String? entityKind, entityNumber, reason, docUrl;
  final DateTime? submittedAt, reviewedAt;
  const VerificationInfo({this.status = 'none', this.entityKind, this.entityNumber, this.reason, this.docUrl, this.submittedAt, this.reviewedAt});
  factory VerificationInfo.fromJson(Map m) => VerificationInfo(
        status: m['status']?.toString() ?? 'none', entityKind: m['entityKind']?.toString(), entityNumber: m['entityNumber']?.toString(),
        reason: (m['reason']?.toString().isNotEmpty == true) ? m['reason'].toString() : null, docUrl: m['docUrl']?.toString(), submittedAt: _t(m['submittedAt']), reviewedAt: _t(m['reviewedAt']),
      );
  bool get approved => status == 'approved';
  bool get pending => status == 'pending';
  bool get rejected => status == 'rejected';
  String get label => verificationLabelOf(status);
}

/// بنود قائمة الاكتمال: الأساسيات، الصور والكتالوج (لديك/المطلوب)، وحالة الكيان.
class CompletenessChecks {
  final bool logo, location, phone, hours, description, phoneVerified, offer30d, post30d;
  final int photosHave, photosNeed, catalogHave, catalogNeed;
  final String entityStatus;
  const CompletenessChecks({this.logo = false, this.location = false, this.phone = false, this.hours = false, this.description = false, this.phoneVerified = false, this.offer30d = false, this.post30d = false, this.photosHave = 0, this.photosNeed = 3, this.catalogHave = 0, this.catalogNeed = 3, this.entityStatus = 'none'});
  factory CompletenessChecks.fromJson(Map m) {
    final ph = _m(m['photos']), ca = _m(m['catalog']), en = _m(m['entity']);
    return CompletenessChecks(
      logo: m['logo'] == true, location: m['location'] == true, phone: m['phone'] == true, hours: m['hours'] == true, description: m['description'] == true,
      phoneVerified: m['phoneVerified'] == true, offer30d: m['offer30d'] == true, post30d: m['post30d'] == true,
      photosHave: _i(ph['have']), photosNeed: ph['need'] == null ? 3 : _i(ph['need']), catalogHave: _i(ca['have']), catalogNeed: ca['need'] == null ? 3 : _i(ca['need']), entityStatus: en['status']?.toString() ?? 'none',
    );
  }
  bool get photos => photosHave >= photosNeed;
  bool get catalog => catalogHave >= catalogNeed;
  bool get entity => entityStatus == 'approved';
}

/// الخطوة التالية المقترحة مع التبويب الذي تفتحه في اللوحة (profile|catalog|posts|offers|verify).
class NextStep {
  final String key, title, hint, tab;
  final int minutes;
  const NextStep({required this.key, required this.title, this.hint = '', this.tab = 'profile', this.minutes = 2});
  factory NextStep.fromJson(Map m) => NextStep(key: m['key']?.toString() ?? '', title: m['title']?.toString() ?? '', hint: m['hint']?.toString() ?? '', tab: m['tab']?.toString() ?? 'profile', minutes: m['minutes'] == null ? 2 : _i(m['minutes']));
}

/// اكتمال الدائرة: الدرجة والنسبة وقائمة البنود والخطوة التالية وحالة التوثيق (GET /biz/:id/completeness).
class Completeness {
  final String tier;
  final int percent;
  final bool canSell;
  final CompletenessChecks checks;
  final NextStep? next;
  final VerificationInfo verification;
  const Completeness({this.tier = 'published', this.percent = 0, this.canSell = false, this.checks = const CompletenessChecks(), this.next, this.verification = const VerificationInfo()});
  factory Completeness.fromJson(Map m) => Completeness(
        tier: m['tier']?.toString() ?? 'published', percent: _i(m['percent']).clamp(0, 100), canSell: m['canSell'] == true, checks: CompletenessChecks.fromJson(_m(m['checks'])),
        next: m['next'] is Map ? NextStep.fromJson(_m(m['next'])) : null, verification: VerificationInfo.fromJson(_m(m['verification'])),
      );
  String get tierLabel => tierLabelOf(tier);
}

/// دائرة مشابهة قريبة وُجدت أثناء التسجيل (GET /biz/register/check).
class RegisterDuplicate {
  final String id, name, nameAr;
  final BizCategory category;
  final double? distanceKm;
  final String? ownerId, logoUrl;
  const RegisterDuplicate({required this.id, this.name = '', this.nameAr = '', this.category = BizCategory.brand, this.distanceKm, this.ownerId, this.logoUrl});
  factory RegisterDuplicate.fromJson(Map m) => RegisterDuplicate(id: m['id'].toString(), name: m['name']?.toString() ?? '', nameAr: m['nameAr']?.toString() ?? '', category: BizCategory.of(m['category']?.toString()), distanceKm: _d(m['distanceKm']), ownerId: m['ownerId']?.toString(), logoUrl: m['logoUrl']?.toString());
  String get title => nameAr.isNotEmpty ? nameAr : name;
  /// بلا مالك: يمكن استلامها؛ ولها مالك: نخبر المسجّل أنها مملوكة.
  bool get claimable => ownerId == null || ownerId!.isEmpty;
  String? get distanceLabel => distanceKm == null ? null : (distanceKm! < 1 ? '${(distanceKm! * 1000).round()} م' : '${distanceKm!.toStringAsFixed(1)} كم');
}

class RegisterCheck {
  final List<RegisterDuplicate> duplicates;
  const RegisterCheck({this.duplicates = const []});
  factory RegisterCheck.fromJson(Map m) => RegisterCheck(duplicates: asList(m['duplicates']).map(RegisterDuplicate.fromJson).toList());
}

/// ما يعود به POST /biz/register: الدائرة (بدور المالك) واكتمالها الأولي.
class Registered {
  final Biz biz;
  final Completeness completeness;
  const Registered({required this.biz, required this.completeness});
  factory Registered.fromJson(Map m) => Registered(biz: Biz.fromJson(_m(m['biz'])), completeness: Completeness.fromJson(_m(m['completeness'])));
}
