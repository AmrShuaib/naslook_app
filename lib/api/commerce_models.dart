import 'models.dart';

String money(int halalas) {
  final v = halalas / 100;
  final s = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  return '$s ر.س';
}

/// يحوّل نص مبلغ بالريال (بأرقام عربية أو هندية، بفاصلة أو نقطة) إلى هللات؛ 0 إن كان غير صالح أو سالباً.
int parseSar(String? text) {
  if (text == null) return 0;
  const east = '٠١٢٣٤٥٦٧٨٩', persian = '۰۱۲۳۴۵۶۷۸۹';
  final b = StringBuffer();
  for (final r in text.trim().runes) {
    final ch = String.fromCharCode(r);
    final i = east.indexOf(ch), j = persian.indexOf(ch);
    if (i >= 0) {
      b.write(i);
    } else if (j >= 0) {
      b.write(j);
    } else if (ch == '٫' || ch == '،' || ch == ',') {
      b.write('.');
    } else if (ch == '٬' || ch.trim().isEmpty) {
      continue; // فاصل آلاف أو مسافة
    } else {
      b.write(ch);
    }
  }
  final v = double.tryParse(b.toString().replaceAll(RegExp(r'[^0-9.\-]'), '')) ?? 0;
  return v.isFinite && v > 0 ? (v * 100).round() : 0;
}

/// أقصى شحن تجريبي في المرة الواحدة (بالهللة) كما في الخادم.
const int maxTopupHalalas = 10000000;

Map<String, dynamic> _m(dynamic v) => asMap(v);
DateTime? _t(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
int _i(dynamic v) => v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;

class Wallet {
  final int balance;
  final int points;
  final int upcomingTickets;
  final bool testTopup;
  final List<WalletTx> recent;
  const Wallet({required this.balance, required this.points, required this.upcomingTickets, required this.testTopup, required this.recent});
  factory Wallet.fromJson(Map m) => Wallet(
        balance: _i(m['balance']), points: _i(m['points']), upcomingTickets: _i(m['upcomingTickets']), testTopup: m['testTopup'] == true,
        recent: asList(m['recent']).map(WalletTx.fromJson).toList(),
      );
}

class WalletTx {
  final String id;
  final String kind;
  final int amount;
  final Person? peer;
  final String? ref;
  final String? note;
  final DateTime? createdAt;
  const WalletTx({required this.id, required this.kind, required this.amount, this.peer, this.ref, this.note, this.createdAt});
  factory WalletTx.fromJson(Map m) => WalletTx(
        id: m['id'].toString(), kind: m['kind']?.toString() ?? '', amount: _i(m['amount']),
        peer: m['peer'] is Map ? Person.fromJson(_m(m['peer'])) : null, ref: m['ref']?.toString(), note: m['note']?.toString(), createdAt: _t(m['createdAt']),
      );
  bool get positive => amount > 0;
  String get label => switch (kind) {
        'topup' => 'شحن', 'credit' => 'إضافة رصيد', 'debit' => 'خصم', 'transfer_in' => 'تحويل وارد', 'transfer_out' => 'تحويل صادر',
        'ticket' => 'تذاكر', 'ticket_sale' => 'بيع تذاكر', 'market' => 'شراء من السوق', 'market_sale' => 'بيع في السوق',
        'refund' => 'استرداد', 'refund_out' => 'إعادة مبلغ', 'biz' => 'شراء أو حجز', 'biz_refund' => 'استرداد حجز', 'biz_sale' => 'مبيعات دائرتك', 'biz_refund_out' => 'استرداد لعميل', _ => kind };
}

class TicketTier {
  final String id, name, description;
  final int price, quantity, sold, left;
  const TicketTier({required this.id, required this.name, required this.description, required this.price, required this.quantity, required this.sold, required this.left});
  factory TicketTier.fromJson(Map m) => TicketTier(id: m['id'].toString(), name: m['name']?.toString() ?? '', description: m['description']?.toString() ?? '', price: _i(m['price']), quantity: _i(m['quantity']), sold: _i(m['sold']), left: _i(m['left']));
}

class Event {
  final String id, title, description;
  final Person host;
  final String? vesselId, placeName;
  final DateTime? startsAt, endsAt;
  final double? lat, lng;
  final bool cancelled, isHost;
  final int going, myTickets;
  final List<TicketTier> tiers;
  const Event({required this.id, required this.title, required this.description, required this.host, this.vesselId, this.placeName, this.startsAt, this.endsAt, this.lat, this.lng, this.cancelled = false, this.isHost = false, this.going = 0, this.myTickets = 0, this.tiers = const []});
  factory Event.fromJson(Map m) => Event(
        id: m['id'].toString(), title: m['title']?.toString() ?? '', description: m['description']?.toString() ?? '', host: Person.fromJson(_m(m['host'])),
        vesselId: m['vesselId']?.toString(), placeName: m['placeName']?.toString(), startsAt: _t(m['startsAt']), endsAt: _t(m['endsAt']),
        lat: (m['lat'] as num?)?.toDouble(), lng: (m['lng'] as num?)?.toDouble(), cancelled: m['cancelled'] == true, isHost: m['isHost'] == true,
        going: _i(m['going']), myTickets: _i(m['myTickets']), tiers: asList(m['tiers']).map(TicketTier.fromJson).toList(),
      );
  int get minPrice => tiers.isEmpty ? 0 : tiers.map((t) => t.price).reduce((a, b) => a < b ? a : b);
}

class Ticket {
  final String id, code, status, eventId, title, tier;
  final int paid;
  final DateTime? startsAt, createdAt, usedAt;
  final String? placeName;
  const Ticket({required this.id, required this.code, required this.status, required this.eventId, required this.title, required this.tier, required this.paid, this.startsAt, this.createdAt, this.usedAt, this.placeName});
  factory Ticket.fromJson(Map m) => Ticket(id: m['id'].toString(), code: m['code']?.toString() ?? '', status: m['status']?.toString() ?? 'valid', eventId: m['eventId'].toString(), title: m['title']?.toString() ?? '', tier: m['tier']?.toString() ?? '', paid: _i(m['paid']), startsAt: _t(m['startsAt']), createdAt: _t(m['createdAt']), usedAt: _t(m['usedAt']), placeName: m['placeName']?.toString());
  bool get upcoming => status == 'valid' && (startsAt == null || startsAt!.isAfter(DateTime.now().subtract(const Duration(hours: 6))));
}

class Variant {
  final String name;
  final int price;
  final int? stock;
  const Variant({required this.name, required this.price, this.stock});
  factory Variant.fromJson(Map m) => Variant(name: m['name']?.toString() ?? '', price: _i(m['price']), stock: m['stock'] == null ? null : _i(m['stock']));
  Map<String, dynamic> toJson() => {'name': name, 'price': price, 'stock': stock};
}

/// أوقات الخدمة الأسبوعية: أيام (٠ الأحد … ٦ السبت) ومن/إلى بصيغة HH:mm ومدة الموعد
class Availability {
  final List<int> days;
  final String from, to;
  final int slotMinutes;
  const Availability({required this.days, required this.from, required this.to, this.slotMinutes = 60});
  factory Availability.fromJson(Map m) => Availability(days: [for (final d in asListDyn(m['days'])) _i(d)], from: m['from']?.toString() ?? '09:00', to: m['to']?.toString() ?? '21:00', slotMinutes: m['slotMinutes'] == null ? 60 : _i(m['slotMinutes']));
  Map<String, dynamic> toJson() => {'days': days, 'from': from, 'to': to, 'slotMinutes': slotMinutes};
}

List<dynamic> asListDyn(dynamic v) => v is List ? v : const [];

class Listing {
  final String id, kind, category, title, description, status;
  final Person seller;
  final int price;
  final String? imageUrl, placeName, subcategory, condition, city;
  final List<String> images;
  final double? lat, lng, distanceKm, ratingAvg, sellerRating;
  final bool mine, delivery, spotlight;
  final int? stock;
  final int sold, views, ratingCount, sellerRatingCount;
  final List<Variant> variants;
  final Availability? availability;
  final List<String> sellerBadges;
  final DateTime? createdAt, updatedAt, publishAt, bumpedAt, spotlightUntil;
  const Listing({required this.id, required this.kind, required this.category, required this.title, required this.description, required this.status, required this.seller, required this.price, this.imageUrl, this.placeName, this.subcategory, this.condition, this.city,
      this.images = const [], this.lat, this.lng, this.distanceKm, this.ratingAvg, this.sellerRating, this.mine = false, this.delivery = false, this.spotlight = false, this.stock, this.sold = 0, this.views = 0, this.ratingCount = 0, this.sellerRatingCount = 0,
      this.variants = const [], this.availability, this.sellerBadges = const [], this.createdAt, this.updatedAt, this.publishAt, this.bumpedAt, this.spotlightUntil});
  factory Listing.fromJson(Map m) => Listing(
        id: m['id'].toString(), kind: m['kind']?.toString() ?? 'product', category: m['category']?.toString() ?? 'other', title: m['title']?.toString() ?? '', description: m['description']?.toString() ?? '',
        status: m['status']?.toString() ?? 'active', seller: Person.fromJson(_m(m['seller'])), price: _i(m['price']), imageUrl: m['imageUrl']?.toString(), placeName: m['placeName']?.toString(),
        subcategory: m['subcategory']?.toString(), condition: m['condition']?.toString(), city: m['city']?.toString(), images: [for (final u in asListDyn(m['images'])) if (u != null && u.toString().isNotEmpty) u.toString()],
        lat: (m['lat'] as num?)?.toDouble(), lng: (m['lng'] as num?)?.toDouble(), distanceKm: (m['distanceKm'] as num?)?.toDouble(), ratingAvg: (m['ratingAvg'] as num?)?.toDouble(), sellerRating: (m['sellerRating'] as num?)?.toDouble(),
        mine: m['mine'] == true, delivery: m['delivery'] == true, spotlight: m['spotlight'] == true, stock: m['stock'] == null ? null : _i(m['stock']), sold: _i(m['sold']), views: _i(m['views']), ratingCount: _i(m['ratingCount']), sellerRatingCount: _i(m['sellerRatingCount']),
        variants: [for (final v in asListDyn(m['variants'])) if (v is Map) Variant.fromJson(v)], availability: m['availability'] is Map ? Availability.fromJson(_m(m['availability'])) : null,
        sellerBadges: [for (final b in asListDyn(m['sellerBadges'])) b.toString()], createdAt: _t(m['createdAt']), updatedAt: _t(m['updatedAt']), publishAt: _t(m['publishAt']), bumpedAt: _t(m['bumpedAt']), spotlightUntil: _t(m['spotlightUntil']),
      );
  bool get outOfStock => variants.isEmpty ? stock == 0 : variants.every((v) => v.stock == 0);
  bool get isService => kind == 'service';
  String get subcategoryLabel => marketSubcategories[category]?[subcategory] ?? '';
}

class Order {
  final String id, listingId, title, status, note;
  final String? imageUrl, kind, code, variant, coupon, disputeStatus, disputeReason, disputeNote;
  final int qty, total, discount;
  final int? commission;
  final Person buyer, seller;
  /// مندوب التوصيل الذي عيّنه البائع (اختياري) وملاحظته له
  final Person? courier;
  final String courierNote;
  final bool mineAsSeller, mineAsCourier, reviewed;
  final DateTime? createdAt, updatedAt, slot, deliveredAt, completedAt;
  const Order({required this.id, required this.listingId, required this.title, required this.status, required this.note, this.imageUrl, this.kind, this.code, this.variant, this.coupon, this.disputeStatus, this.disputeReason, this.disputeNote,
      required this.qty, required this.total, this.discount = 0, this.commission, required this.buyer, required this.seller, this.courier, this.courierNote = '', required this.mineAsSeller, this.mineAsCourier = false, this.reviewed = false, this.createdAt, this.updatedAt, this.slot, this.deliveredAt, this.completedAt});
  factory Order.fromJson(Map m) => Order(
        id: m['id'].toString(), listingId: m['listingId'].toString(), title: m['title']?.toString() ?? '', status: m['status']?.toString() ?? '', note: m['note']?.toString() ?? '', imageUrl: m['imageUrl']?.toString(), kind: m['kind']?.toString(),
        code: m['code']?.toString(), variant: m['variant']?.toString(), coupon: m['coupon']?.toString(), disputeStatus: m['disputeStatus']?.toString(), disputeReason: m['disputeReason']?.toString(), disputeNote: m['disputeNote']?.toString(),
        qty: _i(m['qty']), total: _i(m['total']), discount: _i(m['discount']), commission: m['commission'] == null ? null : _i(m['commission']), buyer: Person.fromJson(_m(m['buyer'])), seller: Person.fromJson(_m(m['seller'])),
        courier: m['courier'] is Map ? Person.fromJson(_m(m['courier'])) : null, courierNote: m['courierNote']?.toString() ?? '', mineAsCourier: m['mineAsCourier'] == true,
        mineAsSeller: m['mineAsSeller'] == true, reviewed: m['reviewed'] == true, createdAt: _t(m['createdAt']), updatedAt: _t(m['updatedAt']), slot: _t(m['slot']), deliveredAt: _t(m['deliveredAt']), completedAt: _t(m['completedAt']),
      );
  bool get open => const {'paid', 'preparing', 'on_the_way', 'delivered'}.contains(status);
  /// دوري في الطلب: بائع أو مشترٍ أو مندوب
  bool get mineAsBuyer => !mineAsSeller && !mineAsCourier;
  bool get done => status == 'completed';
}

class SpotlightItem {
  final String id;
  final DateTime? endsAt;
  final Listing listing;
  const SpotlightItem({required this.id, this.endsAt, required this.listing});
  factory SpotlightItem.fromJson(Map m) => SpotlightItem(id: m['id'].toString(), endsAt: _t(m['endsAt']), listing: Listing.fromJson(_m(m['listing'])));
}

class SpotlightMine {
  final String id, listleId, title, status;
  final String? imageUrl;
  final int days, paid, views, clicks;
  final bool granted;
  final DateTime? startsAt, endsAt;
  const SpotlightMine({required this.id, required this.listleId, required this.title, required this.status, this.imageUrl, required this.days, required this.paid, required this.views, required this.clicks, this.granted = false, this.startsAt, this.endsAt});
  factory SpotlightMine.fromJson(Map m) => SpotlightMine(id: m['id'].toString(), listleId: m['listingId'].toString(), title: m['title']?.toString() ?? '', status: m['status']?.toString() ?? '', imageUrl: m['imageUrl']?.toString(), days: _i(m['days']), paid: _i(m['paid']), views: _i(m['views']), clicks: _i(m['clicks']), granted: m['granted'] == true, startsAt: _t(m['startsAt']), endsAt: _t(m['endsAt']));
}

class MarketHome {
  final List<SpotlightItem> spotlight;
  final List<Listing> popular, nearby;
  final List<Bazaar> bazaars;
  final Map<String, int> categories;
  final int wantedOpen, spotlightPricePerDay;
  final double commissionPct;
  const MarketHome({this.spotlight = const [], this.popular = const [], this.nearby = const [], this.bazaars = const [], this.categories = const {}, this.wantedOpen = 0, this.spotlightPricePerDay = 0, this.commissionPct = 0});
  factory MarketHome.fromJson(Map m) => MarketHome(
        spotlight: asList(m['spotlight']).map(SpotlightItem.fromJson).toList(), popular: asList(m['popular']).map(Listing.fromJson).toList(), nearby: asList(m['nearby']).map(Listing.fromJson).toList(),
        bazaars: asList(m['bazaars']).map(Bazaar.fromJson).toList(),
        categories: {for (final e in _m(m['categories']).entries) e.key: _i(e.value)}, wantedOpen: _i(m['wantedOpen']), spotlightPricePerDay: _i(m['spotlightPricePerDay']), commissionPct: (m['commissionPct'] as num?)?.toDouble() ?? 0,
      );
}

/// بازار موسمي تنشئه الإدارة وينضم إليه البائعون بعروضهم
class Bazaar {
  final String id, title, description, city, state;
  final String? bannerUrl, category;
  final DateTime? startsAt, endsAt;
  final bool active;
  final int listings, mine;
  final List<Listing> items;
  const Bazaar({required this.id, required this.title, this.description = '', this.city = '', this.state = 'live', this.bannerUrl, this.category, this.startsAt, this.endsAt, this.active = true, this.listings = 0, this.mine = 0, this.items = const []});
  factory Bazaar.fromJson(Map m) => Bazaar(
        id: m['id'].toString(), title: m['title']?.toString() ?? '', description: m['description']?.toString() ?? '', city: m['city']?.toString() ?? '', state: m['state']?.toString() ?? 'live', bannerUrl: m['bannerUrl']?.toString(), category: m['category']?.toString(),
        startsAt: _t(m['startsAt']), endsAt: _t(m['endsAt']), active: m['active'] != false, listings: _i(m['listings']), mine: _i(m['mine']), items: asList(m['items']).map(Listing.fromJson).toList(),
      );
  bool get live => state == 'live';
  bool get upcoming => state == 'upcoming';
  String get stateLabel => switch (state) { 'live' => 'جارٍ الآن', 'upcoming' => 'قريباً', _ => 'انتهى' };
}

/// إعدادات بوابة الدفع كما يعلنها الخادم (مفعّلة فقط عند وجود مفاتيح المزوّد)
class PayConfig {
  final bool enabled;
  final String provider, currency;
  final List<String> methods;
  final int min, max;
  const PayConfig({this.enabled = false, this.provider = '', this.currency = 'SAR', this.methods = const [], this.min = 0, this.max = 0});
  factory PayConfig.fromJson(Map m) => PayConfig(enabled: m['enabled'] == true, provider: m['provider']?.toString() ?? '', currency: m['currency']?.toString() ?? 'SAR', methods: asList(m['methods']).map((e) => e.toString()).toList(), min: _i(m['min']), max: _i(m['max']));
}

class PaymentRow {
  final String id, status, description;
  final int amount;
  final DateTime? createdAt, paidAt;
  const PaymentRow({required this.id, required this.status, required this.amount, this.description = '', this.createdAt, this.paidAt});
  factory PaymentRow.fromJson(Map m) => PaymentRow(id: m['id'].toString(), status: m['status']?.toString() ?? '', amount: _i(m['amount']), description: m['description']?.toString() ?? '', createdAt: _t(m['createdAt']), paidAt: _t(m['paidAt']));
}

/// معاينة ترقية البائع إلى دائرة أعمال
class UpgradePreview {
  final bool eligible;
  final int listings, completed;
  final String suggestedName, suggestedCategory, city, address;
  final String? marketCategory, upgradedBizId;
  final int upgradedItems;
  const UpgradePreview({this.eligible = false, this.listings = 0, this.completed = 0, this.suggestedName = '', this.suggestedCategory = 'brand', this.city = '', this.address = '', this.marketCategory, this.upgradedBizId, this.upgradedItems = 0});
  factory UpgradePreview.fromJson(Map m) => UpgradePreview(
        eligible: m['eligible'] == true, listings: _i(m['listings']), completed: _i(m['completed']), suggestedName: m['suggestedName']?.toString() ?? '', suggestedCategory: m['suggestedCategory']?.toString() ?? 'brand', city: m['city']?.toString() ?? '', address: m['address']?.toString() ?? '',
        marketCategory: m['marketCategory']?.toString(), upgradedBizId: m['upgraded'] is Map ? _m(m['upgraded'])['bizId']?.toString() : null, upgradedItems: m['upgraded'] is Map ? _i(_m(m['upgraded'])['items']) : 0,
      );
}

class MarketReview {
  final String orderId, listingId, text;
  final String? listingTitle, reply;
  final int rating;
  final Person buyer;
  final DateTime? createdAt, replyAt;
  const MarketReview({required this.orderId, required this.listingId, required this.text, this.listingTitle, this.reply, required this.rating, required this.buyer, this.createdAt, this.replyAt});
  factory MarketReview.fromJson(Map m) => MarketReview(orderId: m['orderId'].toString(), listingId: m['listingId'].toString(), text: m['text']?.toString() ?? '', listingTitle: m['listingTitle']?.toString(), reply: m['reply']?.toString(), rating: _i(m['rating']), buyer: Person.fromJson(_m(m['buyer'])), createdAt: _t(m['createdAt']), replyAt: _t(m['replyAt']));
}

class SellerStats {
  final double? ratingAvg, responseHours;
  final int ratingCount, completed, activeListings;
  const SellerStats({this.ratingAvg, this.responseHours, this.ratingCount = 0, this.completed = 0, this.activeListings = 0});
  factory SellerStats.fromJson(Map m) => SellerStats(ratingAvg: (m['ratingAvg'] as num?)?.toDouble(), responseHours: (m['responseHours'] as num?)?.toDouble(), ratingCount: _i(m['ratingCount']), completed: _i(m['completed']), activeListings: _i(m['activeListings']));
}

class SellerProfile {
  final Person seller;
  final String bio;
  final DateTime? memberSince;
  final int followers;
  final bool following, mine;
  final SellerStats stats;
  final List<String> badges;
  final List<Listing> listings;
  final List<MarketReview> reviews;
  const SellerProfile({required this.seller, this.bio = '', this.memberSince, this.followers = 0, this.following = false, this.mine = false, this.stats = const SellerStats(), this.badges = const [], this.listings = const [], this.reviews = const []});
  factory SellerProfile.fromJson(Map m) => SellerProfile(seller: Person.fromJson(_m(m['seller'])), bio: m['bio']?.toString() ?? '', memberSince: _t(m['memberSince']), followers: _i(m['followers']), following: m['following'] == true, mine: m['mine'] == true,
      stats: SellerStats.fromJson(_m(m['stats'])), badges: [for (final b in asListDyn(m['badges'])) b.toString()], listings: asList(m['listings']).map(Listing.fromJson).toList(), reviews: asList(m['reviews']).map(MarketReview.fromJson).toList());
}

class MarketQuestion {
  final String id, listingId, text;
  final String? answer;
  final Person user;
  final DateTime? createdAt, answeredAt;
  const MarketQuestion({required this.id, required this.listingId, required this.text, this.answer, required this.user, this.createdAt, this.answeredAt});
  factory MarketQuestion.fromJson(Map m) => MarketQuestion(id: m['id'].toString(), listingId: m['listingId'].toString(), text: m['text']?.toString() ?? '', answer: m['answer']?.toString(), user: Person.fromJson(_m(m['user'])), createdAt: _t(m['createdAt']), answeredAt: _t(m['answeredAt']));
}

class WantedReply {
  final String id, text;
  final Person seller;
  final int? price;
  final String? listingId, listingTitle, imageUrl;
  final bool mine;
  final DateTime? createdAt;
  const WantedReply({required this.id, required this.text, required this.seller, this.price, this.listingId, this.listingTitle, this.imageUrl, this.mine = false, this.createdAt});
  factory WantedReply.fromJson(Map m) => WantedReply(id: m['id'].toString(), text: m['text']?.toString() ?? '', seller: Person.fromJson(_m(m['seller'])), price: m['price'] == null ? null : _i(m['price']), listingId: m['listingId']?.toString(), listingTitle: m['listingTitle']?.toString(), imageUrl: m['imageUrl']?.toString(), mine: m['mine'] == true, createdAt: _t(m['createdAt']));
}

class Wanted {
  final String id, title, description, category, status;
  final String? subcategory, placeName, city;
  final Person user;
  final int? budgetMin, budgetMax;
  final double? lat, lng, distanceKm;
  final int replies;
  final bool mine;
  final DateTime? createdAt;
  final List<WantedReply> replyList;
  const Wanted({required this.id, required this.title, required this.description, required this.category, required this.status, this.subcategory, this.placeName, this.city, required this.user, this.budgetMin, this.budgetMax, this.lat, this.lng, this.distanceKm, this.replies = 0, this.mine = false, this.createdAt, this.replyList = const []});
  factory Wanted.fromJson(Map m) => Wanted(id: m['id'].toString(), title: m['title']?.toString() ?? '', description: m['description']?.toString() ?? '', category: m['category']?.toString() ?? 'other', status: m['status']?.toString() ?? 'open', subcategory: m['subcategory']?.toString(), placeName: m['placeName']?.toString(), city: m['city']?.toString(),
      user: Person.fromJson(_m(m['user'])), budgetMin: m['budgetMin'] == null ? null : _i(m['budgetMin']), budgetMax: m['budgetMax'] == null ? null : _i(m['budgetMax']), lat: (m['lat'] as num?)?.toDouble(), lng: (m['lng'] as num?)?.toDouble(), distanceKm: (m['distanceKm'] as num?)?.toDouble(),
      replies: _i(m['replies']), mine: m['mine'] == true, createdAt: _t(m['createdAt']), replyList: asList(m['replyList']).map(WantedReply.fromJson).toList());
}

class Coupon {
  final String code;
  final int? percent, amount, maxUses;
  final int minTotal, used;
  final bool active;
  final DateTime? expiresAt;
  const Coupon({required this.code, this.percent, this.amount, this.maxUses, this.minTotal = 0, this.used = 0, this.active = true, this.expiresAt});
  factory Coupon.fromJson(Map m) => Coupon(code: m['code']?.toString() ?? '', percent: m['percent'] == null ? null : _i(m['percent']), amount: m['amount'] == null ? null : _i(m['amount']), maxUses: m['maxUses'] == null ? null : _i(m['maxUses']), minTotal: _i(m['minTotal']), used: _i(m['used']), active: m['active'] != false, expiresAt: _t(m['expiresAt']));
  String get label => percent != null ? '$percent٪' : money(amount ?? 0);
}

class MarketAlert {
  final String id;
  final String? category, subcategory, q;
  final double? lat, lng;
  final int radiusKm;
  const MarketAlert({required this.id, this.category, this.subcategory, this.q, this.lat, this.lng, this.radiusKm = 25});
  factory MarketAlert.fromJson(Map m) => MarketAlert(id: m['id'].toString(), category: m['category']?.toString(), subcategory: m['subcategory']?.toString(), q: m['q']?.toString(), lat: (m['lat'] as num?)?.toDouble(), lng: (m['lng'] as num?)?.toDouble(), radiusKm: m['radiusKm'] == null ? 25 : _i(m['radiusKm']));
}

class TopListing {
  final String id, title, status;
  final String? imageUrl;
  final int views, views7, sold, revenue;
  const TopListing({required this.id, required this.title, required this.status, this.imageUrl, this.views = 0, this.views7 = 0, this.sold = 0, this.revenue = 0});
  factory TopListing.fromJson(Map m) => TopListing(id: m['id'].toString(), title: m['title']?.toString() ?? '', status: m['status']?.toString() ?? '', imageUrl: m['imageUrl']?.toString(), views: _i(m['views']), views7: _i(m['views7']), sold: _i(m['sold']), revenue: _i(m['revenue']));
}

class SellerDashboard {
  final int todayOrders, todayRevenue, weekOrders, weekRevenue, monthOrders, monthRevenue, monthNet, pending, awaitingConfirm, disputed, views7, followers, spotlightActive, ratingCount;
  final double conversionPct;
  final double? ratingAvg, responseHours;
  final List<String> badges;
  final Map<String, int> listings;
  final List<TopListing> top;
  const SellerDashboard({this.todayOrders = 0, this.todayRevenue = 0, this.weekOrders = 0, this.weekRevenue = 0, this.monthOrders = 0, this.monthRevenue = 0, this.monthNet = 0, this.pending = 0, this.awaitingConfirm = 0, this.disputed = 0, this.views7 = 0, this.followers = 0, this.spotlightActive = 0, this.ratingCount = 0, this.conversionPct = 0, this.ratingAvg, this.responseHours, this.badges = const [], this.listings = const {}, this.top = const []});
  factory SellerDashboard.fromJson(Map m) => SellerDashboard(
        todayOrders: _i(_m(m['today'])['orders']), todayRevenue: _i(_m(m['today'])['revenue']), weekOrders: _i(_m(m['week'])['orders']), weekRevenue: _i(_m(m['week'])['revenue']), monthOrders: _i(_m(m['month'])['orders']), monthRevenue: _i(_m(m['month'])['revenue']), monthNet: _i(_m(m['month'])['net']),
        pending: _i(m['pending']), awaitingConfirm: _i(m['awaitingConfirm']), disputed: _i(m['disputed']), views7: _i(m['views7']), followers: _i(m['followers']), spotlightActive: _i(m['spotlightActive']), ratingCount: _i(_m(m['rating'])['count']), conversionPct: (m['conversionPct'] as num?)?.toDouble() ?? 0,
        ratingAvg: (_m(m['rating'])['avg'] as num?)?.toDouble(), responseHours: (m['responseHours'] as num?)?.toDouble(), badges: [for (final b in asListDyn(m['badges'])) b.toString()], listings: {for (final e in _m(m['listings']).entries) e.key: _i(e.value)}, top: asList(m['top']).map(TopListing.fromJson).toList(),
      );
}

class MarketAdminOverview {
  final Map<String, int> listings;
  final int ordersOpen, disputesOpen, gmv30, commission30, orders30, basket, spotlightRevenue30, spotlightActive, spotlightPricePerDay;
  final double cancelRatePct, commissionPct;
  final List<({Person seller, int orders, int revenue})> topSellers;
  final List<({String category, int active, bool stale})> categories;
  final List<({String city, int orders})> cities;
  final List<Listing> pending;
  final List<Order> disputes;
  const MarketAdminOverview({this.listings = const {}, this.ordersOpen = 0, this.disputesOpen = 0, this.gmv30 = 0, this.commission30 = 0, this.orders30 = 0, this.basket = 0, this.spotlightRevenue30 = 0, this.spotlightActive = 0, this.spotlightPricePerDay = 0, this.cancelRatePct = 0, this.commissionPct = 0, this.topSellers = const [], this.categories = const [], this.cities = const [], this.pending = const [], this.disputes = const []});
  factory MarketAdminOverview.fromJson(Map m) => MarketAdminOverview(
        listings: {for (final e in _m(m['listings']).entries) e.key: _i(e.value)}, ordersOpen: _i(m['ordersOpen']), disputesOpen: _i(m['disputesOpen']), gmv30: _i(m['gmv30']), commission30: _i(m['commission30']), orders30: _i(m['orders30']), basket: _i(m['basket']),
        spotlightRevenue30: _i(_m(m['spotlight'])['revenue30']), spotlightActive: _i(_m(m['spotlight'])['active']), spotlightPricePerDay: _i(_m(m['spotlight'])['pricePerDay']), cancelRatePct: (m['cancelRatePct'] as num?)?.toDouble() ?? 0, commissionPct: (m['commissionPct'] as num?)?.toDouble() ?? 0,
        topSellers: [for (final t in asList(m['topSellers'])) (seller: Person.fromJson(_m(t['seller'])), orders: _i(t['orders']), revenue: _i(t['revenue']))],
        categories: [for (final c in asList(m['categories'])) (category: c['category'].toString(), active: _i(c['active']), stale: c['stale'] == true)], cities: [for (final c in asList(m['cities'])) (city: c['city']?.toString() ?? '', orders: _i(c['orders']))],
        pending: asList(m['pending']).map(Listing.fromJson).toList(), disputes: asList(m['disputes']).map(Order.fromJson).toList(),
      );
}

const marketCategories = {
  'coffee': 'قهوة', 'food': 'طعام', 'photo': 'تصوير', 'gifts': 'هدايا', 'handmade': 'أعمال يدوية', 'delivery': 'توصيل', 'services': 'خدمات', 'other': 'أخرى',
};
/// مرآة server/market_taxonomy.js
const marketSubcategories = <String, Map<String, String>>{
  'coffee': {'beans': 'حبوب ومحاصيل', 'tools': 'أدوات تخمير', 'drinks': 'مشروبات جاهزة', 'workshops': 'ورش وتدريب'},
  'food': {'meals': 'وجبات وولائم', 'sweets': 'حلويات وكيك', 'pastries': 'معجنات', 'dates': 'تمور', 'subscriptions': 'اشتراكات وجبات', 'catering': 'ضيافة ومناسبات'},
  'photo': {'products': 'تصوير منتجات', 'events': 'مناسبات وأعراس', 'portraits': 'بورتريه وعائلي', 'editing': 'تعديل ومونتاج', 'prints': 'طباعة ولوحات', 'drone': 'تصوير جوي'},
  'gifts': {'boxes': 'بوكسات', 'flowers': 'ورد', 'perfume': 'عطور وعود', 'personalized': 'هدايا بالاسم', 'corporate': 'هدايا شركات'},
  'handmade': {'crochet': 'كروشيه وتطريز', 'candles': 'شموع', 'resin': 'ريزن', 'pottery': 'فخار وسيراميك', 'jewelry': 'إكسسوارات', 'art': 'لوحات وفن'},
  'delivery': {'parcels': 'طرود ومشاوير', 'groceries': 'بقالة وصيدلية', 'airport': 'مطار وسفر', 'moving': 'نقل أثاث', 'pets': 'حيوانات أليفة'},
  'services': {'maintenance': 'صيانة منزلية', 'education': 'تعليم ودروس', 'beauty': 'تجميل وحناء', 'design': 'تصميم وسوشيال', 'cars': 'سيارات', 'fitness': 'لياقة وتغذية', 'tech': 'أجهزة وتقنية', 'cleaning': 'تنظيف', 'tailoring': 'خياطة', 'events': 'تنظيم مناسبات'},
  'other': {'clothing': 'ملابس وعبايات', 'plants': 'نباتات', 'books': 'كتب', 'electronics': 'إلكترونيات', 'furniture': 'أثاث', 'misc': 'متنوع'},
};
const marketConditions = {'new': 'جديد', 'used': 'مستعمل'};
const marketSorts = {'near': 'الأقرب', 'new': 'الأحدث', 'cheap': 'الأرخص', 'expensive': 'الأغلى', 'popular': 'الأكثر طلباً', 'rated': 'الأعلى تقييماً'};
const sellerBadgeLabels = {'verified': 'موثّق', 'trusted': 'بائع موثوق', 'top': 'الأعلى تقييماً', 'fast': 'سريع الرد', 'licensed': 'مرخّص'};
const orderStatusLabels = {'paid': 'مؤكَّد', 'preparing': 'قيد التحضير', 'on_the_way': 'في الطريق', 'delivered': 'تم التسليم', 'completed': 'مكتمل', 'cancelled': 'ملغى', 'refunded': 'مسترد', 'disputed': 'نزاع'};
const orderStages = ['paid', 'preparing', 'on_the_way', 'delivered', 'completed'];
const weekdayLabels = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
