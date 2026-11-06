import '../../api/client.dart';

bool pushSupported() => false;
String pushPermission() => 'default';
Future<bool> pushIsSubscribed() async => false;
Future<bool> pushSubscribe(ApiClient api) async => false;
Future<void> pushUnsubscribe(ApiClient api) async {}
Future<Map<String, dynamic>?> pushGrantedSubscription() async => null;
Future<({String? endpoint, bool dropped})> pushDropLocal() async => (endpoint: null, dropped: true);
void pushListenOpens(bool Function(String url) onOpen) {}
