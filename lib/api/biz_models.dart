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

  const Biz({
    required this.id, required this.name, this.nameAr = '', required this.category, this.sector = '', this.description = '', required this.lat, required this.lng,
    this.address = '', this.hours = '', this.phone, this.website, this.colorHex, this.highlights = const [], this.verified = false, this.official = false,
    this.following = false, this.followers = 0, this.rating, this.ratingCount = 0, this.minPrice, this.itemsCount = 0, this.items = const [], this.reviews = const [], this.myOrders = const [],
  });

  factory Biz.fromJson(Map m) => Biz(
        id: m['id'].toString(), name: m['name']?.toString() ?? '', nameAr: m['nameAr']?.toString() ?? '', category: BizCategory.of(m['category']?.toString()),
        sector: m['sector']?.toString() ?? '', description: m['description']?.toString() ?? '', lat: _d(m['lat']) ?? 0, lng: _d(m['lng']) ?? 0,
        address: m['address']?.toString() ?? '', hours: m['hours']?.toString() ?? '', phone: m['phone']?.toString(), website: m['website']?.toString(), colorHex: m['color']?.toString(),
        highlights: _strings(m['highlights']), verified: m['verified'] == true, official: m['official'] == true, following: m['following'] == true,
        followers: _i(m['followers']), rating: _d(m['rating']), ratingCount: _i(m['ratingCount']), minPrice: m['minPrice'] == null ? null : _i(m['minPrice']), itemsCount: _i(m['itemsCount']),
        items: asList(m['items']).map(BizItem.fromJson).toList(), reviews: asList(m['reviews']).map(BizReview.fromJson).toList(), myOrders: asList(m['myOrders']).map(BizOrder.fromJson).toList(),
      );

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
  const BizItem({required this.id, required this.bizId, required this.kind, required this.title, this.description = '', required this.price, this.unit = 'item', this.stock, this.meta = const {}, this.imageUrl, this.slots = const []});
  factory BizItem.fromJson(Map m) => BizItem(
        id: m['id'].toString(), bizId: m['bizId']?.toString() ?? '', kind: m['kind']?.toString() ?? 'product', title: m['title']?.toString() ?? '', description: m['description']?.toString() ?? '',
        price: _i(m['price']), unit: m['unit']?.toString() ?? 'item', stock: m['stock'] == null ? null : _i(m['stock']), meta: _m(m['meta']), imageUrl: m['imageUrl']?.toString(),
        slots: asList(m['slots']).map(Showtime.fromJson).toList(),
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
  final DateTime? createdAt;
  final bool mine;
  const BizReview({required this.user, required this.rating, this.text = '', this.createdAt, this.mine = false});
  factory BizReview.fromJson(Map m) => BizReview(user: Person.fromJson(_m(m['user'])), rating: _i(m['rating']), text: m['text']?.toString() ?? '', createdAt: _t(m['createdAt']), mine: m['mine'] == true);
}

/// طلب شراء أو حجز لدى دائرة تجارية.
class BizOrder {
  final String id, bizId, itemId, kind, status, code, note, title, bizName;
  final BizCategory category;
  final int qty, units, total;
  final DateTime? startAt, endAt, createdAt;
  final Map<String, dynamic> meta;
  final bool cancellable;
  const BizOrder({
    required this.id, required this.bizId, required this.itemId, required this.kind, required this.status, required this.code, this.note = '', this.title = '', this.bizName = '',
    this.category = BizCategory.brand, this.qty = 1, this.units = 1, required this.total, this.startAt, this.endAt, this.createdAt, this.meta = const {}, this.cancellable = false,
  });
  factory BizOrder.fromJson(Map m) => BizOrder(
        id: m['id'].toString(), bizId: m['bizId']?.toString() ?? '', itemId: m['itemId']?.toString() ?? '', kind: m['kind']?.toString() ?? 'product', status: m['status']?.toString() ?? 'confirmed',
        code: m['code']?.toString() ?? '', note: m['note']?.toString() ?? '', title: m['title']?.toString() ?? '', bizName: (m['bizNameAr']?.toString().isNotEmpty == true ? m['bizNameAr'] : m['bizName'])?.toString() ?? '',
        category: BizCategory.of(m['category']?.toString()), qty: _i(m['qty']), units: _i(m['units']), total: _i(m['total']), startAt: _t(m['startAt']), endAt: _t(m['endAt']), createdAt: _t(m['createdAt']),
        meta: _m(m['meta']), cancellable: m['cancellable'] == true,
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
