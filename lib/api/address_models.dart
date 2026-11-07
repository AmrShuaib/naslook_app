import 'models.dart';

double? _d(dynamic v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');

/// عنوان توصيل: في دفتر «عناويني» (بمعرّف) أو نسخته المحفوظة على طلب السوق (بلا معرّف).
class DeliveryAddress {
  final String label, district, details;
  final String? city, phone;
  final double? lat, lng;
  const DeliveryAddress({required this.label, required this.district, this.details = '', this.city, this.phone, this.lat, this.lng});
  factory DeliveryAddress.fromJson(Map m) => DeliveryAddress(
        label: m['label']?.toString() ?? '', district: m['district']?.toString() ?? '', details: m['details']?.toString() ?? '',
        city: (m['city']?.toString() ?? '').isEmpty ? null : m['city'].toString(), phone: (m['phone']?.toString() ?? '').isEmpty ? null : m['phone'].toString(),
        lat: _d(m['lat']), lng: _d(m['lng']),
      );
  bool get hasPoint => lat != null && lng != null;
  /// سطر واحد للبطاقات: الحي والمدينة ثم التفاصيل
  String get line => [district, if (city != null) city!, if (details.isNotEmpty) details].join('، ');
  /// الجوال بصيغة محلية للعرض (+9665… → 05…)
  String? get localPhone => phone == null ? null : (phone!.startsWith('+966') ? '0${phone!.substring(4)}' : phone);
}

class SavedAddress extends DeliveryAddress {
  final String id;
  final bool isDefault;
  const SavedAddress({required this.id, required super.label, required super.district, super.details, super.city, super.phone, super.lat, super.lng, this.isDefault = false});
  factory SavedAddress.fromJson(Map m) {
    final a = DeliveryAddress.fromJson(m);
    return SavedAddress(id: m['id']?.toString() ?? '', label: a.label, district: a.district, details: a.details, city: a.city, phone: a.phone, lat: a.lat, lng: a.lng, isDefault: m['isDefault'] == true);
  }
}

class AddressBook {
  final List<SavedAddress> items;
  final int max;
  const AddressBook({this.items = const [], this.max = 10});
  factory AddressBook.fromJson(Map m) => AddressBook(
        items: [for (final a in (m['items'] is List ? m['items'] as List : const [])) if (a is Map) SavedAddress.fromJson(asMap(a))],
        max: m['max'] is num ? (m['max'] as num).toInt() : 10,
      );
  bool get full => items.length >= max;
  SavedAddress? get preferred => items.where((a) => a.isDefault).firstOrNull ?? items.firstOrNull;
}

/// تسميات جاهزة في نموذج العنوان (والمستخدم يكتب غيرها)
const addressLabelPresets = ['البيت', 'العمل', 'بيت الأهل'];
