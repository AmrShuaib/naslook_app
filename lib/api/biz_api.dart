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
}
