import 'client.dart';
import 'models.dart';

/// عنصر في قائمة الأمنيات (server/wishlist.js): مرجع لعرض في السوق أو منتج/خدمة دائرة تجارية أو فعالية أو منشور،
/// أو أمنية حرة كتبها المستخدم. البيانات المرجعية تأتي من مصدرها في الخادم.
class WishItem {
  final String id, kind, title, subtitle, note;
  final String? refId, imageUrl, bizId;
  final int? price;
  final bool done, available;
  final DateTime? createdAt;
  const WishItem({
    required this.id, required this.kind, required this.title, this.subtitle = '', this.note = '', this.refId, this.imageUrl, this.bizId,
    this.price, this.done = false, this.available = true, this.createdAt,
  });

  factory WishItem.fromJson(Map m) => WishItem(
        id: m['id'].toString(), kind: m['kind']?.toString() ?? 'custom', title: m['title']?.toString() ?? '', subtitle: m['subtitle']?.toString() ?? '',
        note: m['note']?.toString() ?? '', refId: m['refId']?.toString(), imageUrl: m['imageUrl']?.toString(), bizId: m['bizId']?.toString(),
        price: m['price'] is num ? (m['price'] as num).toInt() : null, done: m['done'] == true, available: m['available'] != false,
        createdAt: m['createdAt'] == null ? null : DateTime.tryParse(m['createdAt'].toString()),
      );

  /// مفتاح التطابق مع الأزرار: النوع والمرجع.
  String get key => '$kind:${refId ?? id}';
  bool get isCustom => kind == 'custom';
  String get kindLabel => wishKinds[kind] ?? 'أمنية';

  WishItem copyWith({bool? done, String? note}) => WishItem(
        id: id, kind: kind, title: title, subtitle: subtitle, note: note ?? this.note, refId: refId, imageUrl: imageUrl, bizId: bizId, price: price,
        done: done ?? this.done, available: available, createdAt: createdAt);
}

/// أنواع الأمنيات وتسمياتها (ترتيب شرائح التصفية).
const wishKinds = {'market': 'السوق', 'item': 'خدمات ومنتجات', 'event': 'فعاليات', 'post': 'منشورات', 'biz': 'دوائر تجارية', 'custom': 'أمنياتي الحرة'};

extension WishlistApi on ApiClient {
  Future<List<WishItem>> wishlist() async => asList(await getList('/wishlist')).map(WishItem.fromJson).toList();

  /// إضافة مرجع (يعيد العنصر القائم إن كان محفوظاً) أو أمنية حرة بعنوان وملاحظة وسعر اختياريين.
  Future<WishItem> addWish({required String kind, String? refId, String? title, String? note, int? price}) async => WishItem.fromJson(await post('/wishlist', {
        'kind': kind,
        if (refId != null) 'refId': refId,
        if (title != null) 'title': title,
        if (note != null) 'note': note,
        if (price != null) 'price': price,
      }));

  Future<WishItem> updateWish(String id, {bool? done, String? note, String? title, int? price, bool clearPrice = false}) async =>
      WishItem.fromJson(await patch_('/wishlist/$id', {
        if (done != null) 'done': done,
        if (note != null) 'note': note,
        if (title != null) 'title': title,
        if (price != null || clearPrice) 'price': price,
      }));

  Future<void> removeWish(String id) => delete('/wishlist/$id');
}
