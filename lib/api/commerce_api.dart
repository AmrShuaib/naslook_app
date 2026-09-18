import 'client.dart';
import 'commerce_models.dart';
import 'models.dart';

/// مسارات إضافة التجارة (server/commerce.js وserver/market_plus.js).
extension CommerceApi on ApiClient {
  Future<Wallet> wallet() async => Wallet.fromJson(await get('/wallet'));
  Future<List<WalletTx>> walletTransactions({DateTime? before}) async =>
      asList(await getList('/wallet/transactions', query: {if (before != null) 'before': before.toUtc().toIso8601String()})).map(WalletTx.fromJson).toList();
  Future<void> walletTopup(int halalas) => post('/wallet/topup', {'amount': halalas});
  Future<void> walletTransfer(String to, int halalas, {String note = ''}) => post('/wallet/transfer', {'to': to, 'amount': halalas, 'note': note});

  Future<List<Event>> events({BBox? bbox, bool mine = false, String? vessel}) async =>
      asList(await getList('/events', query: {if (bbox != null) 'bbox': bbox.query, if (mine) 'mine': '1', if (vessel != null) 'vessel': vessel})).map(Event.fromJson).toList();
  Future<Event> event(String id) async => Event.fromJson(await get('/events/$id'));
  Future<Event> createEvent(Map<String, dynamic> body) async => Event.fromJson(await post('/events', body));
  Future<List<Ticket>> buyTickets(String eventId, String tierId, int qty) async {
    final data = await post('/events/$eventId/tickets', {'tierId': tierId, 'qty': qty});
    return asList(data['data']).map(Ticket.fromJson).toList();
  }
  Future<List<Ticket>> tickets() async => asList(await getList('/tickets')).map(Ticket.fromJson).toList();
  Future<Map<String, dynamic>> checkin(String eventId, String code) => post('/events/$eventId/checkin', {'code': code});
  Future<void> cancelEvent(String id) => post('/events/$id/cancel', const {});

  // ---- السوق: بحث وعروض
  Future<List<Listing>> market({BBox? bbox, String q = '', String? category, String? sub, String? kind, int? min, int? max, bool delivery = false, String? condition, String? sort, double? lat, double? lng, int? radiusKm, String? seller, bool spotlight = false, int? limit, int? offset}) async =>
      asList(await getList('/market', query: {
        if (bbox != null) 'bbox': bbox.query, 'q': q, if (category != null) 'category': category, if (sub != null) 'sub': sub, if (kind != null) 'kind': kind, if (min != null) 'min': '$min', if (max != null) 'max': '$max',
        if (delivery) 'delivery': '1', if (condition != null) 'condition': condition, if (sort != null) 'sort': sort, if (lat != null && lng != null) ...{'lat': '$lat', 'lng': '$lng'}, if (radiusKm != null) 'radius': '$radiusKm',
        if (seller != null) 'seller': seller, if (spotlight) 'spotlight': '1', if (limit != null) 'limit': '$limit', if (offset != null) 'offset': '$offset',
      })).map(Listing.fromJson).toList();
  Future<MarketHome> marketHome({double? lat, double? lng}) async => MarketHome.fromJson(await get('/market/home', query: {if (lat != null && lng != null) ...{'lat': '$lat', 'lng': '$lng'}}));
  Future<List<Listing>> myListings() async => asList(await getList('/market/mine')).map(Listing.fromJson).toList();
  Future<Listing> listing(String id) async => Listing.fromJson(await get('/market/$id'));
  Future<Listing> createListing(Map<String, dynamic> body) async => Listing.fromJson(await post('/market', body));
  Future<void> hideListing(String id) => delete('/market/$id');
  /// تعديل عرضي: النصوص والسعر والصور والخيارات والمخزون، أو status: active|hidden|draft.
  Future<Listing> updateListing(String id, Map<String, dynamic> patch) async => Listing.fromJson(await patch_('/market/$id', patch));
  Future<void> bumpListing(String id) => post('/market/$id/bump', const {});
  Future<void> viewListing(String id) => post('/market/$id/view', const {});

  // ---- الطلبات بمراحلها
  Future<Map<String, dynamic>> order(String listingId, int qty, {String note = '', String? variant, String? coupon, DateTime? slot}) =>
      post('/market/$listingId/order', {'qty': qty, 'note': note, if (variant != null) 'variant': variant, if (coupon != null && coupon.isNotEmpty) 'coupon': coupon, if (slot != null) 'slot': slot.toUtc().toIso8601String()});
  Future<List<Order>> orders() async => asList(await getList('/market/orders')).map(Order.fromJson).toList();
  Future<Order> orderDetail(String id) async => Order.fromJson(await get('/market/orders/$id'));
  Future<void> orderStage(String id, String stage) => post('/market/orders/$id/stage', {'stage': stage});
  Future<void> deliverOrder(String id) => post('/market/orders/$id/deliver', const {});
  Future<void> confirmOrder(String id, {String? code}) => post('/market/orders/$id/confirm', {if (code != null) 'code': code});
  Future<void> cancelOrder(String id) => post('/market/orders/$id/cancel', const {});
  Future<void> disputeOrder(String id, String reason) => post('/market/orders/$id/dispute', {'reason': reason});
  Future<void> reviewOrder(String id, int rating, String text) => post('/market/orders/$id/review', {'rating': rating, 'text': text});
  Future<void> replyReview(String orderId, String text) => post('/market/reviews/$orderId/reply', {'text': text});
  Future<List<MarketReview>> listingReviews(String id) async => asList(await getList('/market/$id/reviews')).map(MarketReview.fromJson).toList();
  String invoiceUrl(String orderId) => '${ApiClient.mediaBase}/market/orders/$orderId/invoice?token=${Uri.encodeComponent(token ?? '')}';

  // ---- البائعون
  Future<SellerProfile> seller(String id) async => SellerProfile.fromJson(await get('/market/sellers/$id'));
  Future<void> followSeller(String id) => post('/market/sellers/$id/follow', const {});
  Future<void> unfollowSeller(String id) => delete('/market/sellers/$id/follow');
  Future<SellerDashboard> sellerStats() async => SellerDashboard.fromJson(await get('/market/seller/stats'));

  // ---- أسئلة وأجوبة
  Future<List<MarketQuestion>> questions(String listingId) async => asList(await getList('/market/$listingId/questions')).map(MarketQuestion.fromJson).toList();
  Future<MarketQuestion> askQuestion(String listingId, String text) async => MarketQuestion.fromJson(await post('/market/$listingId/questions', {'text': text}));
  Future<void> answerQuestion(String qid, String text) => post('/market/questions/$qid/answer', {'text': text});

  // ---- طلبات المشترين
  Future<List<Wanted>> wanted({String? category, double? lat, double? lng, bool mine = false}) async =>
      asList(await getList('/market/wanted', query: {if (category != null) 'category': category, if (lat != null && lng != null) ...{'lat': '$lat', 'lng': '$lng'}, if (mine) 'mine': '1'})).map(Wanted.fromJson).toList();
  Future<Wanted> createWanted(Map<String, dynamic> body) async => Wanted.fromJson(await post('/market/wanted', body));
  Future<Wanted> wantedDetail(String id) async => Wanted.fromJson(await get('/market/wanted/$id'));
  Future<void> replyWanted(String id, {String text = '', int? price, String? listingId}) => post('/market/wanted/$id/replies', {'text': text, if (price != null) 'price': price, if (listingId != null) 'listingId': listingId});
  Future<void> closeWanted(String id) => patch_('/market/wanted/$id', {'status': 'closed'});

  // ---- كوبونات وتنبيهات
  Future<List<Coupon>> coupons() async => asList(await getList('/market/coupons')).map(Coupon.fromJson).toList();
  Future<Coupon> createCoupon(Map<String, dynamic> body) async => Coupon.fromJson(await post('/market/coupons', body));
  Future<void> setCouponActive(String code, bool active) => patch_('/market/coupons/$code', {'active': active});
  Future<Map<String, dynamic>> checkCoupon({required String seller, required String code, required int total}) => get('/market/coupons/check', query: {'seller': seller, 'code': code, 'total': '$total'});
  Future<List<MarketAlert>> marketAlerts() async => asList(await getList('/market/alerts')).map(MarketAlert.fromJson).toList();
  Future<MarketAlert> createMarketAlert(Map<String, dynamic> body) async => MarketAlert.fromJson(await post('/market/alerts', body));
  Future<void> deleteMarketAlert(String id) => delete('/market/alerts/$id');

  // ---- سبوت لايت
  Future<List<SpotlightItem>> spotlight() async => asList(await getList('/market/spotlight')).map(SpotlightItem.fromJson).toList();
  Future<void> spotlightClick(String id) => post('/market/spotlight/$id/click', const {});
  Future<Map<String, dynamic>> spotlightPrice() => get('/market/spotlight/price');
  Future<List<SpotlightMine>> spotlightMine() async => asList(await getList('/market/spotlight/mine')).map(SpotlightMine.fromJson).toList();
  Future<Map<String, dynamic>> buySpotlight(String listingId, int days) => post('/market/$listingId/spotlight', {'days': days});

  // ---- الإدارة
  Future<MarketAdminOverview> adminMarketOverview() async => MarketAdminOverview.fromJson(await get('/adminapi/market/overview'));
  Future<void> adminMarketPending(String id, {required bool approve, String note = ''}) => post('/adminapi/market/pending/$id', {'approve': approve, 'note': note});
  Future<void> adminMarketDispute(String id, {required String resolution, String note = ''}) => post('/adminapi/market/disputes/$id', {'resolution': resolution, 'note': note});
  Future<void> adminMarketSpotlight(String listingId, int days) => post('/adminapi/market/spotlight', {'listingId': listingId, 'days': days});
  Future<void> adminMarketStopSpotlight(String id) => delete('/adminapi/market/spotlight/$id');
  Future<void> adminMarketSellerFlags(String id, {required bool licensed, String note = ''}) => patch_('/adminapi/market/sellers/$id/flags', {'licensed': licensed, 'note': note});
  Future<List<Listing>> adminMarketListings({String status = '', String q = ''}) async => asList(await getList('/adminapi/market/listings', query: {'status': status, 'q': q})).map(Listing.fromJson).toList();
  Future<List<Order>> adminMarketOrders({String status = ''}) async => asList(await getList('/adminapi/market/orders', query: {'status': status})).map(Order.fromJson).toList();

  // ---- المرحلة (ب): مندوب توصيل، بازارات، بوابة دفع، ترقية البائع
  Future<Order> setCourier(String orderId, {required String nickname, String note = ''}) async => Order.fromJson(await post('/market/orders/$orderId/courier', {'nickname': nickname, 'note': note}));
  Future<Order> clearCourier(String orderId) async => Order.fromJson(await delete('/market/orders/$orderId/courier'));
  Future<List<Bazaar>> bazaars() async => asList(await getList('/market/bazaars')).map(Bazaar.fromJson).toList();
  Future<Bazaar> bazaar(String id, {double? lat, double? lng}) async => Bazaar.fromJson(await get('/market/bazaars/$id', query: {if (lat != null && lng != null) ...{'lat': '$lat', 'lng': '$lng'}}));
  Future<void> joinBazaar(String bazaarId, String listingId) => post('/market/bazaars/$bazaarId/join', {'listingId': listingId});
  Future<void> leaveBazaar(String bazaarId, String listingId) => delete('/market/bazaars/$bazaarId/join/$listingId');
  Future<List<Bazaar>> adminBazaars() async => asList(await getList('/adminapi/market/bazaars')).map(Bazaar.fromJson).toList();
  Future<Bazaar> adminCreateBazaar(Map<String, dynamic> body) async => Bazaar.fromJson(await post('/adminapi/market/bazaars', body));
  Future<Bazaar> adminPatchBazaar(String id, Map<String, dynamic> body) async => Bazaar.fromJson(await patch_('/adminapi/market/bazaars/$id', body));
  Future<PayConfig> payConfig() async => PayConfig.fromJson(await get('/pay/config'));
  /// يبدأ شحناً بالبطاقة ويعيد رابط صفحة الدفع التي يفتحها المتصفح
  Future<String> payTopup(int halalas) async => (await post('/pay/topup', {'amount': halalas}))['checkoutUrl'].toString();
  Future<List<PaymentRow>> myPayments() async => asList(await getList('/pay/mine')).map(PaymentRow.fromJson).toList();
  Future<UpgradePreview> upgradePreview() async => UpgradePreview.fromJson(await get('/market/seller/upgrade'));
  Future<String> upgradeSeller({required String nameAr, String description = '', String? category}) async => (await post('/market/seller/upgrade', {'nameAr': nameAr, 'description': description, if (category != null) 'category': category}))['bizId'].toString();
}
