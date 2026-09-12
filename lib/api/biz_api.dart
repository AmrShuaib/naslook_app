import 'biz_models.dart';
import 'client.dart';
import 'models.dart';

/// مسارات إضافة الدوائر التجارية (server/business.js).
extension BizApi on ApiClient {
  Future<List<Biz>> businessCircles({BizCategory? category, BBox? bbox, String q = '', bool following = false}) async => asList(await getList('/biz', query: {
        if (category != null) 'category': category.key,
        if (bbox != null) 'bbox': bbox.query,
        if (q.isNotEmpty) 'q': q,
        if (following) 'following': '1',
      })).map(Biz.fromJson).toList();
  Future<Biz> businessCircle(String id) async => Biz.fromJson(await get('/biz/$id'));
  Future<void> followBiz(String id) => post('/biz/$id/follow', const {});
  Future<void> unfollowBiz(String id) => delete('/biz/$id/follow', body: const {});
  Future<void> reviewBiz(String id, {required int rating, String text = ''}) => post('/biz/$id/reviews', {'rating': rating, 'text': text});
  Future<BizOrder> orderBiz(String id, {required String itemId, int qty = 1, DateTime? startAt, DateTime? endAt, int? guests, String note = ''}) async =>
      BizOrder.fromJson(await post('/biz/$id/orders', {
        'itemId': itemId,
        'qty': qty,
        if (startAt != null) 'startAt': startAt.toUtc().toIso8601String(),
        if (endAt != null) 'endAt': endAt.toUtc().toIso8601String(),
        if (guests != null) 'guests': guests,
        'note': note,
      }));
  Future<List<BizOrder>> myBizOrders() async => asList(await getList('/biz/orders/mine')).map(BizOrder.fromJson).toList();
  Future<void> cancelBizOrder(String id) => post('/biz/orders/$id/cancel', const {});

  // ---- لوحة صاحب النشاط
  Future<MyBusinesses> myBusinesses() async => MyBusinesses.fromJson(await get('/biz/mine'));
  Future<Biz> createBiz(Map<String, dynamic> body) async => Biz.fromJson(await post('/biz', body));
  Future<Biz> updateBiz(String id, Map<String, dynamic> body) async => Biz.fromJson(await patch_('/biz/$id', body));
  Future<String> claimBiz(String id, {String note = ''}) async => (await post('/biz/$id/claim', {'note': note}))['status']?.toString() ?? 'pending';
  Future<List<BizClaim>> bizClaims() async => asList(await getList('/biz/claims')).map(BizClaim.fromJson).toList();
  Future<void> decideClaim(String id, String userId, {required bool approve}) => post('/biz/$id/claims/$userId/${approve ? 'approve' : 'reject'}', const {});
  Future<void> verifyBiz(String id, bool verified) => post('/biz/$id/verify', {'verified': verified});
  Future<BizItem> createBizItem(String id, Map<String, dynamic> body) async => BizItem.fromJson(await post('/biz/$id/items', body));
  Future<BizItem> updateBizItem(String id, String itemId, Map<String, dynamic> body) async => BizItem.fromJson(await patch_('/biz/$id/items/$itemId', body));
  Future<void> deleteBizItem(String id, String itemId) => delete('/biz/$id/items/$itemId', body: const {});
  Future<List<BizOrder>> bizOrders(String id, {String? status, String q = ''}) async =>
      asList(await getList('/biz/$id/orders', query: {if (status != null && status.isNotEmpty) 'status': status, if (q.isNotEmpty) 'q': q})).map(BizOrder.fromJson).toList();
  Future<BizOrder> checkinBiz(String id, {String? code, String? orderId}) async => BizOrder.fromJson(await post('/biz/$id/checkin', {if (code != null) 'code': code, if (orderId != null) 'orderId': orderId}));
  Future<void> ownerCancelOrder(String id, String orderId) => post('/biz/$id/orders/$orderId/cancel', const {});
  Future<BizStats> bizStats(String id) async => BizStats.fromJson(await get('/biz/$id/stats'));
  Future<BizPost> createBizPost(String id, Map<String, dynamic> body) async => BizPost.fromJson(await post('/biz/$id/posts', body));
  Future<BizPost> updateBizPost(String id, String postId, Map<String, dynamic> body) async => BizPost.fromJson(await patch_('/biz/$id/posts/$postId', body));
  Future<void> deleteBizPost(String id, String postId) => delete('/biz/$id/posts/$postId', body: const {});
  Future<void> replyBizReview(String id, String userId, String text) => post('/biz/$id/reviews/$userId/reply', {'text': text});
  Future<BizTeam> bizTeam(String id) async => BizTeam.fromJson(await get('/biz/$id/team'));
  Future<void> addBizStaff(String id, String userId, {String role = 'staff'}) => post('/biz/$id/team', {'userId': userId, 'role': role});
  Future<void> removeBizStaff(String id, String userId) => delete('/biz/$id/team/$userId', body: const {});
  Future<void> transferBiz(String id, String userId) => post('/biz/$id/transfer', {'userId': userId});
}
