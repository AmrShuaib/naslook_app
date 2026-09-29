import 'client.dart';
import '../core/home_layout.dart';

/// ردّ `GET /me/layout`: تخصيص المستخدم إن وُجد، والافتراضي والمثبّت من إعدادات الإدارة.
class HomeLayoutRemote {
  final Map<String, dynamic>? layout;
  final List<String> defaultOrder, defaultNav, pinned;
  final DateTime? updatedAt;
  const HomeLayoutRemote({this.layout, this.defaultOrder = homeDefaultOrder, this.defaultNav = navDefault, this.pinned = homeDefaultPinned, this.updatedAt});

  factory HomeLayoutRemote.fromJson(Map m) {
    final d = (m['defaults'] as Map?) ?? const {};
    List<String> ids(Object? v, List<String> fallback) => v is List && v.isNotEmpty ? [for (final e in v) e.toString()] : fallback;
    return HomeLayoutRemote(
      layout: m['layout'] is Map ? Map<String, dynamic>.from(m['layout'] as Map) : null,
      defaultOrder: ids(d['order'], homeDefaultOrder),
      defaultNav: ids(d['nav'], navDefault),
      pinned: m['pinned'] is List ? [for (final e in m['pinned'] as List) e.toString()] : homeDefaultPinned,
      updatedAt: m['updatedAt'] == null ? null : DateTime.tryParse(m['updatedAt'].toString()),
    );
  }
}

/// مسارات تخصيص الرئيسية (server/layout.js).
extension LayoutApi on ApiClient {
  Future<HomeLayoutRemote> homeLayout() async => HomeLayoutRemote.fromJson(await get('/me/layout'));
  Future<void> saveHomeLayout(HomeLayout l) => put('/me/layout', {'order': l.order, 'hidden': l.hidden, 'nav': l.nav, 'opts': l.opts});
  Future<void> deleteHomeLayout() => delete('/me/layout', body: const {});
}
