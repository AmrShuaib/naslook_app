import 'client.dart';
import 'commerce_models.dart' show money;
import 'models.dart' show asList, asMap;

// حجز الفنادق عبر Amadeus (server/hotels.js): دائرة فندقية مرتبطة بفندق حقيقي، عروض بأسعار اليوم، وحجز ببطاقة ضمان
// تُمرَّر إلى الفندق ولا تُخزَّن. التواريخ على السلك نص YYYY-MM-DD.

String _s(Map m, String k, [String d = '']) => m[k]?.toString() ?? d;
int _i(dynamic v, [int d = 0]) => v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? d;
double? _d(dynamic v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');
DateTime? _t(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

/// تاريخ بصيغة السلك YYYY-MM-DD (بلا وقت ولا منطقة زمنية).
String hotelDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// يقرأ تاريخ YYYY-MM-DD من الخادم كتاريخ محلي (null إن تعذّر).
DateTime? parseHotelDate(String? s) {
  if (s == null || s.length < 10) return null;
  final y = int.tryParse(s.substring(0, 4)), m = int.tryParse(s.substring(5, 7)), d = int.tryParse(s.substring(8, 10));
  if (y == null || m == null || d == null) return null;
  return DateTime(y, m, d);
}

/// ربط الدائرة بفندق لدى Amadeus (`GET /biz/:id/hotel`).
class HotelLink {
  final bool linked, configured;
  final String bizId, hotelId, hotelName, cityCode, env;
  const HotelLink({this.linked = false, this.configured = false, this.bizId = '', this.hotelId = '', this.hotelName = '', this.cityCode = '', this.env = ''});
  factory HotelLink.fromJson(Map m) => HotelLink(
        linked: m['linked'] == true, configured: m['configured'] == true, bizId: _s(m, 'bizId'), hotelId: _s(m, 'hotelId'), hotelName: _s(m, 'hotelName'), cityCode: _s(m, 'cityCode'), env: _s(m, 'env'));
  bool get isTest => env == 'test';
}

/// عرض غرفة واحدة من الفندق للتواريخ المطلوبة.
class HotelOffer {
  final String id, roomName, roomCode, bedType, description, boardType, currency, totalText, perNightText, cancelText, paymentType, paymentText;
  final int beds;
  /// بالهللات حين تكون العملة ريالاً، وإلا المبلغ كما ورد.
  final num total;
  final bool? refundable;
  final DateTime? cancelBy;
  const HotelOffer({
    required this.id, this.roomName = '', this.roomCode = '', this.bedType = '', this.beds = 0, this.description = '', this.boardType = '', this.total = 0, this.currency = 'SAR',
    this.totalText = '', this.perNightText = '', this.refundable, this.cancelBy, this.cancelText = '', this.paymentType = '', this.paymentText = '',
  });
  factory HotelOffer.fromJson(Map m) => HotelOffer(
        id: _s(m, 'id'), roomName: _s(m, 'roomName'), roomCode: _s(m, 'roomCode'), bedType: _s(m, 'bedType'), beds: _i(m['beds']), description: _s(m, 'description'), boardType: _s(m, 'boardType'),
        total: m['total'] is num ? m['total'] as num : num.tryParse(m['total']?.toString() ?? '') ?? 0, currency: _s(m, 'currency', 'SAR'), totalText: _s(m, 'totalText'), perNightText: _s(m, 'perNightText'),
        refundable: m['refundable'] is bool ? m['refundable'] as bool : null, cancelBy: _t(m['cancelBy']), cancelText: _s(m, 'cancelText'), paymentType: _s(m, 'paymentType'), paymentText: _s(m, 'paymentText'),
      );
  /// الإجمالي للعرض: نص الخادم، وإلا تنسيق محلي للريال.
  String get priceText => totalText.isNotEmpty ? totalText : currency == 'SAR' ? money(total.toInt()) : '$total $currency';
  /// «سرير مزدوج · سريران» أو ما توفّر منهما.
  String get bedsLine => [if (bedType.isNotEmpty) bedType, if (beds > 0) (beds == 1 ? 'سرير واحد' : beds == 2 ? 'سريران' : '$beds أسرّة')].join(' · ');
}

/// فندق العرض كما يعيده الخادم مع العروض.
class HotelInfo {
  final String hotelId, name, cityCode;
  const HotelInfo({this.hotelId = '', this.name = '', this.cityCode = ''});
  factory HotelInfo.fromJson(Map m) => HotelInfo(hotelId: _s(m, 'hotelId'), name: _s(m, 'name'), cityCode: _s(m, 'cityCode'));
}

/// رد `GET /biz/:id/hotel/offers`.
class HotelOffers {
  final HotelInfo hotel;
  final String checkIn, checkOut, currency, env;
  final int nights, adults, rooms;
  final bool available;
  final List<HotelOffer> offers;
  const HotelOffers({this.hotel = const HotelInfo(), this.checkIn = '', this.checkOut = '', this.nights = 0, this.adults = 0, this.rooms = 0, this.currency = 'SAR', this.env = '', this.available = false, this.offers = const []});
  factory HotelOffers.fromJson(Map m) => HotelOffers(
        hotel: HotelInfo.fromJson(asMap(m['hotel'])), checkIn: _s(m, 'checkIn'), checkOut: _s(m, 'checkOut'), nights: _i(m['nights']), adults: _i(m['adults']), rooms: _i(m['rooms']),
        currency: _s(m, 'currency', 'SAR'), env: _s(m, 'env'), available: m['available'] == true, offers: asList(m['offers']).map(HotelOffer.fromJson).toList());
}

/// حجز فندقي (رد الحجز وقائمة «حجوزاتي»).
class HotelBooking {
  final String id, bizId, bizName, hotelId, hotelName, orderId, confirmation, status, checkIn, checkOut, roomName, currency, totalText, guestName, guestEmail, cancelText, env;
  final int nights, adults, rooms;
  final num total;
  final bool upcoming;
  final DateTime? createdAt;
  const HotelBooking({
    required this.id, this.bizId = '', this.bizName = '', this.hotelId = '', this.hotelName = '', this.orderId = '', this.confirmation = '', this.status = '', this.checkIn = '', this.checkOut = '',
    this.nights = 0, this.adults = 0, this.rooms = 0, this.roomName = '', this.total = 0, this.currency = 'SAR', this.totalText = '', this.guestName = '', this.guestEmail = '', this.cancelText = '', this.env = '', this.upcoming = false, this.createdAt,
  });
  factory HotelBooking.fromJson(Map m) => HotelBooking(
        id: _s(m, 'id'), bizId: _s(m, 'bizId'), bizName: _s(m, 'bizName'), hotelId: _s(m, 'hotelId'), hotelName: _s(m, 'hotelName'), orderId: _s(m, 'orderId'), confirmation: _s(m, 'confirmation'), status: _s(m, 'status'),
        checkIn: _s(m, 'checkIn'), checkOut: _s(m, 'checkOut'), nights: _i(m['nights']), adults: _i(m['adults']), rooms: _i(m['rooms']), roomName: _s(m, 'roomName'),
        total: m['total'] is num ? m['total'] as num : num.tryParse(m['total']?.toString() ?? '') ?? 0, currency: _s(m, 'currency', 'SAR'), totalText: _s(m, 'totalText'), guestName: _s(m, 'guestName'), guestEmail: _s(m, 'guestEmail'),
        cancelText: _s(m, 'cancelText'), env: _s(m, 'env'), upcoming: m['upcoming'] == true, createdAt: _t(m['createdAt']));
  String get statusLabel => switch (status) { 'confirmed' => 'مؤكد', 'pending' => 'بانتظار التأكيد', 'failed' => 'لم يكتمل', 'cancelled' => 'ملغى', _ => status };
  String get priceText => totalText.isNotEmpty ? totalText : currency == 'SAR' ? money(total.toInt()) : '$total $currency';
  bool get isTest => env == 'test';
}

/// بطاقة الاختبار التي يعيدها الخادم في بيئة الاختبار فقط لتعبئة النموذج تلقائياً.
class HotelTestCard {
  final String vendorCode, number, expiry, holderName;
  const HotelTestCard({this.vendorCode = 'VI', this.number = '', this.expiry = '', this.holderName = ''});
  factory HotelTestCard.fromJson(Map m) => HotelTestCard(vendorCode: _s(m, 'vendorCode', 'VI'), number: _s(m, 'number'), expiry: _s(m, 'expiry'), holderName: _s(m, 'holderName'));
}

/// حالة خدمة الفنادق العامة (`GET /hotel/status`).
class HotelStatus {
  final bool ok, configured;
  final String env, source;
  final int linked;
  final HotelTestCard? testCard;
  const HotelStatus({this.ok = false, this.configured = false, this.env = '', this.source = '', this.linked = 0, this.testCard});
  factory HotelStatus.fromJson(Map m) => HotelStatus(
        ok: m['ok'] == true, configured: m['configured'] == true, env: _s(m, 'env'), source: _s(m, 'source'), linked: _i(m['linked']), testCard: m['testCard'] is Map ? HotelTestCard.fromJson(asMap(m['testCard'])) : null);
  bool get isTest => env == 'test';
}

/// إعدادات Amadeus من لوحة الإدارة (المعرّف والسر لا يُعادان؛ تلميح فقط).
class HotelAdminConfig {
  final bool configured, clientIdSet, secretSet, panelSet, envPresent;
  /// false حين لا يعرض الخادم مسار الفنادق أصلاً (الإضافة غير منشورة أو خطأ)؛ البطاقة تعرض «غير مفعّل» بلا رمي.
  final bool available;
  final String env, source, clientIdHint, secretHint, updatedBy;
  final int linked, bookings;
  final DateTime? updatedAt;
  const HotelAdminConfig({
    this.configured = false, this.env = 'test', this.source = '', this.clientIdSet = false, this.clientIdHint = '', this.secretSet = false, this.secretHint = '', this.panelSet = false, this.envPresent = false,
    this.updatedAt, this.updatedBy = '', this.linked = 0, this.bookings = 0, this.available = true,
  });
  factory HotelAdminConfig.fromJson(Map m) => HotelAdminConfig(
        configured: m['configured'] == true, env: _s(m, 'env', 'test').isEmpty ? 'test' : _s(m, 'env', 'test'), source: _s(m, 'source'), clientIdSet: m['clientIdSet'] == true, clientIdHint: _s(m, 'clientIdHint'),
        secretSet: m['secretSet'] == true, secretHint: _s(m, 'secretHint'), panelSet: m['panelSet'] == true, envPresent: m['envPresent'] == true, updatedAt: _t(m['updatedAt']), updatedBy: _s(m, 'updatedBy'),
        linked: _i(m['linked']), bookings: _i(m['bookings']));
}

/// نتيجة فحص الاتصال بـ Amadeus.
class HotelTestResult {
  final bool ok;
  final String env, source, error, message;
  final int expiresIn;
  const HotelTestResult({this.ok = false, this.env = '', this.source = '', this.error = '', this.message = '', this.expiresIn = 0});
  factory HotelTestResult.fromJson(Map m) => HotelTestResult(ok: m['ok'] == true, env: _s(m, 'env'), source: _s(m, 'source'), error: _s(m, 'error'), message: _s(m, 'message'), expiresIn: _i(m['expiresIn']));
}

/// فندق من نتائج البحث في لوحة الإدارة.
class HotelSearchHit {
  final String hotelId, name;
  final double? lat, lng, distanceKm;
  const HotelSearchHit({required this.hotelId, this.name = '', this.lat, this.lng, this.distanceKm});
  factory HotelSearchHit.fromJson(Map m) => HotelSearchHit(hotelId: _s(m, 'hotelId'), name: _s(m, 'name'), lat: _d(m['lat']), lng: _d(m['lng']), distanceKm: _d(m['distanceKm']));
}

/// صف ربط دائرة بفندق في لوحة الإدارة.
class HotelLinkRow {
  final String bizId, bizName, hotelId, hotelName, cityCode;
  final DateTime? createdAt;
  const HotelLinkRow({required this.bizId, this.bizName = '', this.hotelId = '', this.hotelName = '', this.cityCode = '', this.createdAt});
  factory HotelLinkRow.fromJson(Map m) => HotelLinkRow(bizId: _s(m, 'bizId'), bizName: _s(m, 'bizName'), hotelId: _s(m, 'hotelId'), hotelName: _s(m, 'hotelName'), cityCode: _s(m, 'cityCode'), createdAt: _t(m['createdAt']));
}

/// مسارات إضافة الفنادق (server/hotels.js).
extension HotelApi on ApiClient {
  Future<HotelStatus> hotelStatus() async => HotelStatus.fromJson(await get('/hotel/status'));
  Future<HotelLink> bizHotel(String bizId) async => HotelLink.fromJson(await get('/biz/$bizId/hotel'));
  Future<HotelOffers> hotelOffers(String bizId, {required String checkIn, required String checkOut, int adults = 2, int rooms = 1}) async =>
      HotelOffers.fromJson(await get('/biz/$bizId/hotel/offers', query: {'checkIn': checkIn, 'checkOut': checkOut, 'adults': '$adults', 'rooms': '$rooms'}));
  /// البطاقة تُمرَّر إلى الفندق ضماناً ولا تُخزَّن لدينا.
  Future<HotelBooking> hotelBook(String bizId, {
    required String offerId, required String title, required String firstName, required String lastName, required String phone, required String email,
    required String vendorCode, required String cardNumber, required String expiry, required String holderName,
  }) async =>
      HotelBooking.fromJson(await post('/biz/$bizId/hotel/book', {
        'offerId': offerId,
        'guest': {'title': title, 'firstName': firstName.trim(), 'lastName': lastName.trim(), 'phone': phone.trim(), 'email': email.trim()},
        'card': {'vendorCode': vendorCode, 'number': cardNumber.replaceAll(RegExp(r'\s+'), ''), 'expiry': expiry.trim(), 'holderName': holderName.trim()},
      }));
  Future<List<HotelBooking>> myHotelBookings() async => asList(await getList('/hotel/bookings/mine')).map(HotelBooking.fromJson).toList();
  Future<HotelBooking> hotelBooking(String id) async => HotelBooking.fromJson(await get('/hotel/bookings/$id'));

  // ---- الإدارة: حقل غير مرسل يبقى، وحقل فارغ يُمسح
  Future<HotelAdminConfig> adminHotelConfig() async => HotelAdminConfig.fromJson(await get('/adminapi/hotels/config'));
  Future<HotelAdminConfig> adminSaveHotelConfig({String? clientId, String? clientSecret, String? env}) async => HotelAdminConfig.fromJson(await put('/adminapi/hotels/config', {
        if (clientId != null) 'clientId': clientId.trim(),
        if (clientSecret != null) 'clientSecret': clientSecret.trim(),
        if (env != null) 'env': env,
      }));
  Future<HotelTestResult> adminTestHotel() async => HotelTestResult.fromJson(await post('/adminapi/hotels/test', const {}));
  Future<List<HotelSearchHit>> adminHotelSearch({String? cityCode, String q = '', double? lat, double? lng, int? radiusKm}) async =>
      asList((await get('/adminapi/hotels/search', query: {if (cityCode != null) 'cityCode': cityCode.trim().toUpperCase(), 'q': q.trim(), if (lat != null && lng != null) ...{'lat': '$lat', 'lng': '$lng'}, if (radiusKm != null) 'radiusKm': '$radiusKm'}))['hotels'])
          .map(HotelSearchHit.fromJson).toList();
  Future<List<HotelLinkRow>> adminHotelLinks() async => asList(await getList('/adminapi/hotels/links')).map(HotelLinkRow.fromJson).toList();
  Future<HotelLink> linkHotel(String bizId, {required String hotelId, String? hotelName, String? cityCode}) async =>
      HotelLink.fromJson(await put('/biz/$bizId/hotel/link', {'hotelId': hotelId.trim(), if (hotelName != null && hotelName.isNotEmpty) 'hotelName': hotelName, if (cityCode != null && cityCode.isNotEmpty) 'cityCode': cityCode.trim().toUpperCase()}));
  Future<void> unlinkHotel(String bizId) => delete('/biz/$bizId/hotel/link');
}
