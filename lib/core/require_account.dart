import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/client.dart';
import '../state/app_state.dart';
import 'app_theme.dart';
import 'platform.dart';

/// الزائر طلب شاشة الدخول (من شريط الزائر أو دعوة الدخول أو تبويب «حسابي»).
final guestWantsLoginProvider = StateProvider<bool>((ref) => false);

/// شاشة الدخول تبدأ على «إنشاء حساب» (زر «أنشئ حساباً» في تبويب الزائر).
final loginStartsRegisterProvider = StateProvider<bool>((ref) => false);

/// تصفّح بلا حساب. افتراضي على iOS الأصلي: أبل (5.1.1) لا تسمح بفرض التسجيل على ما لا يحتاج حساباً؛
/// وعلى الويب تبقى شاشة الدخول أولاً مع زر «تصفّح بدون حساب».
final guestBrowseProvider = StateProvider<bool>((ref) => isIosNative);

/// يتأكد أن للمستخدم حساباً قبل فتح شاشة تسبق أي طلب (المحرّر، المحادثة، الطلب، الحجز، شراء التذاكر، أدوات البائع).
/// للزائر يعرض دعوة الدخول ويعيد false؛ بقية الأفعال تكفيها دعوة الدخول التي يفتحها رفض الخادم (401).
bool requireAccount(BuildContext context) {
  final c = ProviderScope.containerOf(context, listen: false);
  // «جارٍ التحميل» ليس زائراً: لا نعترض قبل أن تُعرف الجلسة
  if (c.read(appStateProvider).status != AuthStatus.signedOut) return true;
  final prompt = ApiClient.onUnauthorized;
  if (prompt != null) {
    prompt();
  } else {
    final nav = Navigator.of(context);
    showSignInPrompt(context, onLogin: () {
      nav.popUntil((r) => r.isFirst);
      c.read(guestWantsLoginProvider.notifier).state = true;
    });
  }
  return false;
}

/// ورقة «هذا يحتاج حساباً» بزر دخول (تستخدمها واجهة الزائر ورفض الخادم 401).
Future<void> showSignInPrompt(BuildContext context, {required VoidCallback onLogin}) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('هذا يحتاج حساباً', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('سجّل الدخول أو أنشئ حساباً في ثوانٍ لتشارك وتطلب وتتابع.', style: TextStyle(color: Joy.textMuted, height: 1.5)),
          const SizedBox(height: 14),
          FilledButton(
            key: const Key('guest-login-sheet'),
            onPressed: () {
              Navigator.pop(ctx);
              onLogin();
            },
            child: const Text('سجّل الدخول'),
          ),
        ]),
      ),
    );
