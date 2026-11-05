import '../../api/client.dart';

bool pushSupported() => false;
String pushPermission() => 'default';
Future<bool> pushIsSubscribed() async => false;
Future<bool> pushSubscribe(ApiClient api) async => false;
Future<void> pushUnsubscribe(ApiClient api) async {}
Future<void> pushResubscribeIfGranted(ApiClient api) async {}
Future<void> pushSignOut(ApiClient? api, {required Duration serverTimeout}) async {}
void pushListenOpens(bool Function(String url) onOpen) {}
