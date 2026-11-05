import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/account_api.dart';
import '../api/client.dart';
import '../state/app_state.dart';
import '../ui/widgets.dart' show toast;
import 'app_theme.dart';
import 'platform.dart';
import 'require_account.dart';
import 'share/legal_links.dart';

/// إقرار «عمري 18 سنة فأكثر» قبل أول عملية مالية (قرار المالك، 5 نوفمبر 2026): شحن المحفظة، الشراء المدفوع (السوق، الدائرة،
/// التذكرة، الفندق) والبيع بمقابل (عرض مسعّر، فعالية بتذاكر مدفوعة). المجاني لا يمر من هنا. الخادم (server/legal_pages.js) هو الحكم:
/// يحفظ الإقرار ويرفض العملية المالية قبله بـ 403 adult-required، وما هنا يسأل قبل أن يملأ المستخدم شيئاً.

/// حالة الإقرار للحساب الحالي: null لم تُعرف بعد. تُعاد مع كل تبديل حساب لأن apiClientProvider نسخة جديدة لكل حساب.
final adultAttestedProvider = StateProvider<bool?>((ref) {
  ref.watch(apiClientProvider);
  return null;
});

/// مصدر الإقرار كما يحفظه الخادم.
String get _source => isIosNative ? 'ios' : isAndroidNative ? 'android' : kIsWeb ? 'web' : 'app';

/// يتأكد قبل فعل مالي أن الحساب أقرّ بأنه 18+؛ يعرض الورقة إن لم يقرّ بعد. يعيد true للمتابعة.
/// تعذّر معرفة الحالة (شبكة أو خادم أقدم) لا يحبس المستخدم: الخادم يرفض إن لزم، فيعرض المعالج العام الورقة نفسها.
Future<bool> requireAdult(BuildContext context, WidgetRef ref) async {
  if (!requireAccount(context)) return false;
  final state = ref.read(adultAttestedProvider.notifier);
  if (state.state == true) return true;
  final api = ref.read(apiClientProvider);
  bool? known;
  try {
    known = await api.adultAttested();
  } catch (_) {
    known = null;
  }
  if (known != false) {
    if (known == true) state.state = true;
    return true;
  }
  state.state = false;
  if (!context.mounted) return false;
  return _confirm(context, api, state);
}

/// الورقة ثم POST /me/adult-attest؛ true إن سُجّل الإقرار.
Future<bool> _confirm(BuildContext context, ApiClient api, StateController<bool?> state, {bool retry = false}) async {
  final ok = await AdultSheet.show(context, retry: retry);
  if (ok != true) return false;
  try {
    await api.attestAdult(source: _source);
    state.state = true;
    return true;
  } catch (e) {
    if (context.mounted) toast(context, e is ApiException ? e.message : 'تعذّر حفظ الإقرار، حاول مرة أخرى', error: true);
    return false;
  }
}

/// المعالج العام: رفض 403 adult-required من أي طلب (مسار لم يسأل قبله، أو حالة قديمة) يعرض الورقة نفسها، وبعد الإقرار يطلب إعادة المحاولة.
/// يثبّته غلاف التطبيق بعد الدخول (HomeShell) ويزيله عند الخروج.
class AdultGate {
  AdultGate._();
  static bool _showing = false;
  static void Function()? _installed;

  static void install(BuildContext context, WidgetRef ref) {
    final api = ref.read(apiClientProvider);
    final state = ref.read(adultAttestedProvider.notifier);
    void handler() => _handle(context, ref, api, state);
    _installed = handler;
    ApiClient.onAdultRequired = handler;
  }

  static void uninstall() {
    if (_installed != null && ApiClient.onAdultRequired == _installed) ApiClient.onAdultRequired = null;
    _installed = null;
  }

  static Future<void> _handle(BuildContext context, WidgetRef ref, ApiClient fallbackApi, StateController<bool?> fallbackState) async {
    if (_showing || !context.mounted) return;
    _showing = true;
    try {
      // الحساب قد تبدّل منذ التثبيت: نقرأ العميل والحالة الحاليين ما دام الغلاف قائماً
      final api = context.mounted ? ref.read(apiClientProvider) : fallbackApi;
      final state = context.mounted ? ref.read(adultAttestedProvider.notifier) : fallbackState;
      state.state = false;
      // رسالة الخطأ من الشاشة نفسها تظهر أولاً؛ الورقة بعد الإطار الحالي حتى لا تُفتح أثناء بناء
      await Future<void>.delayed(Duration.zero);
      if (!context.mounted) return;
      final ok = await _confirm(context, api, state, retry: true);
      if (ok && context.mounted) toast(context, 'تم تأكيد عمرك. أعد المحاولة الآن');
    } finally {
      _showing = false;
    }
  }

  /// للاختبارات: يعيد الحالة الداخلية.
  @visibleForTesting
  static void resetForTests() {
    _showing = false;
    uninstall();
  }
}

/// ورقة الإقرار: نص واضح ورابط الشروط وزر «أقر بأن عمري 18 سنة فأكثر». تعيد true عند الإقرار.
class AdultSheet extends StatelessWidget {
  /// جاءت بعد رفض الخادم عملية: تذكّر بإعادة المحاولة بعد الإقرار.
  final bool retry;
  const AdultSheet({super.key, this.retry = false});

  static Future<bool?> show(BuildContext context, {bool retry = false}) => showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => AdultSheet(retry: retry),
      );

  @override
  Widget build(BuildContext context) => SafeArea(
        key: const Key('adult-sheet'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Icon(Icons.verified_user_outlined, size: 40, color: Joy.primary),
            const SizedBox(height: 10),
            const Text('تأكيد العمر', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            const Text('شحن المحفظة والشراء والبيع بمقابل في ناس لايف لمن عمره 18 سنة فأكثر. نطلب هذا الإقرار مرة واحدة لحسابك، والإقرار غير الصحيح مخالفة لشروط الاستخدام.',
                textAlign: TextAlign.center, style: TextStyle(color: Joy.textMuted, height: 1.6)),
            if (retry)
              const Padding(
                key: Key('adult-retry-note'),
                padding: EdgeInsets.only(top: 8),
                child: Text('بعد التأكيد أعد المحاولة.', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            Center(child: TextButton(key: const Key('adult-terms'), onPressed: () => LegalLinks.open('terms'), child: const Text('شروط الاستخدام'))),
            FilledButton(
              key: const Key('adult-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('أقر بأن عمري 18 سنة فأكثر')),
            ),
            TextButton(key: const Key('adult-cancel'), onPressed: () => Navigator.of(context).pop(false), child: const Text('ليس الآن', style: TextStyle(color: Joy.textMuted))),
          ]),
        ),
      );
}

/// جسم عرض السوق مسعّر؟ (السعر أو أي خيار بسعر) — البيع بمقابل يحتاج الإقرار، والعرض المجاني لا.
bool listingBodyPriced(Map<String, dynamic> body) {
  final p = body['price'];
  if (p is num && p > 0) return true;
  final v = body['variants'];
  return v is List && v.any((x) => x is Map && x['price'] is num && (x['price'] as num) > 0);
}
