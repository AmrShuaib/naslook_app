import 'address_models.dart';
import 'client.dart';

/// دفتر العناوين (server/addresses.js): خاص بالمستخدم، حتى عشرة عناوين وأحدها افتراضي.
extension AddressesApi on ApiClient {
  Future<AddressBook> addresses() async => AddressBook.fromJson(await get('/me/addresses'));
  /// الحقول: label وdistrict (إلزاميان)، details وcity، lat/lng معاً، phone (جوال سعودي)، isDefault. 409 address-limit عند الحد.
  Future<SavedAddress> addAddress(Map<String, dynamic> body) async => SavedAddress.fromJson(await post('/me/addresses', body));
  Future<SavedAddress> updateAddress(String id, Map<String, dynamic> patch) async => SavedAddress.fromJson(await patch_('/me/addresses/$id', patch));
  Future<SavedAddress> setDefaultAddress(String id) async => SavedAddress.fromJson(await post('/me/addresses/$id/default', const {}));
  Future<void> deleteAddress(String id) => delete('/me/addresses/$id');
}
