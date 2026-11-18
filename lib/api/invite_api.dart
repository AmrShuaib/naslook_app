import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/invite_ref.dart';
import '../state/app_state.dart';
import 'client.dart';

/// بطاقة دعوتي (server/invite.js): رمزي الثابت، رابط صفحة الترحيب الذي يحمله رمز QR، وعدد من سجّلوا بها.
class InviteInfo {
  final String code, url;
  final int joined;
  const InviteInfo({required this.code, required this.url, this.joined = 0});

  factory InviteInfo.fromJson(Map m) => InviteInfo(code: '${m['code'] ?? ''}', url: '${m['url'] ?? ''}', joined: (m['joined'] as num?)?.toInt() ?? 0);
}

extension InviteApi on ApiClient {
  Future<InviteInfo> myInvite() async => InviteInfo.fromJson(await get('/me/invite'));

  /// يعيد اسم الداعي، أو null إن كانت الدعوة محتسبة من قبل.
  Future<String?> acceptInvite(String code) async {
    final m = await post('/invite/accept', {'code': code});
    if (m['already'] == true) return null;
    final i = m['inviter'];
    final name = i is Map ? '${i['name'] ?? i['nickname'] ?? ''}' : '';
    return name.isEmpty ? null : name;
  }
}

final myInviteProvider = FutureProvider.autoDispose<InviteInfo>((ref) => ref.watch(apiClientProvider).myInvite());

/// بعد أول دخول: إن جاء هذا الجهاز من بطاقة دعوة يُرسل رمزها مرة واحدة. يعيد اسم الداعي للترحيب، أو null.
/// رفض الخادم (رمز مجهول، حساب قديم، دعوة النفس) يمسح الرمز؛ انقطاع الشبكة يبقيه للمحاولة القادمة.
Future<String?> acceptPendingInvite(ApiClient api) async {
  final code = await InviteRef.pending();
  if (code == null) return null;
  try {
    final name = await api.acceptInvite(code);
    await InviteRef.clear();
    return name;
  } on ApiException catch (e) {
    if (!e.isNetwork && e.statusCode < 500) await InviteRef.clear();
    return null;
  } catch (_) {
    return null;
  }
}
