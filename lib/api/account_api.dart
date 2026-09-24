import 'client.dart';

/// مانع أو تنبيه عند حذف الحساب (server/account_delete.js).
class DeletionItem {
  final String code;
  final int count;
  const DeletionItem(this.code, this.count);
  factory DeletionItem.fromJson(Map m) => DeletionItem(m['code']?.toString() ?? '', (m['count'] as num?)?.toInt() ?? 1);

  /// وصف عربي لما يمنع الحذف أو ينبّه إليه.
  String get label => switch (code) {
        'open-orders' => 'لديك طلبات مفتوحة في السوق ($count). أكملها أو ألغها أولاً',
        'courier-orders' => 'أنت مندوب على طلبات لم تُسلَّم ($count)',
        'hosted-events' => 'لديك فعاليات قادمة بيعت تذاكرها ($count). ألغها واسترد للمشترين أولاً',
        'bookings' => 'لديك حجوزات قادمة ($count). ألغها أولاً',
        'circle-bookings' => 'لدى دائرتك حجوزات قادمة من عملاء ($count)',
        'pending-payment' => 'لديك عملية دفع قيد الإتمام. انتظر دقائق ثم حاول',
        'wallet-debt' => 'رصيد محفظتك سالب. سدّده أولاً',
        'wallet-balance' => 'في محفظتك رصيد، سنعيده إلى وسيلة الدفع الأصلية خلال 30 يوماً إن أكدت الحذف',
        'staff-account' => 'حسابك ضمن فريق الإدارة. يلزم إزالته من الفريق أولاً',
        'platform-account' => 'حساب المنصة لا يُحذف',
        'tickets' => 'لديك تذاكر صالحة لفعاليات قادمة ($count) ستُفقد',
        'listings' => 'عروضك في السوق ($count) ستُخفى',
        'circles' => 'دوائرك ($count) ستُعطَّل أو تعود بلا مالك',
        'offers' => 'عروض الدوائر التي لم تستخدمها ($count) ستنتهي',
        _ => code,
      };
}

/// ما يعرضه الخادم قبل حذف الحساب.
class DeletionPreview {
  final bool canDelete, hasRecovery;
  final List<DeletionItem> blockers, warnings;
  final int balance; // بالهللات
  final String confirmWord;
  final int refundDays;
  const DeletionPreview({required this.canDelete, required this.hasRecovery, required this.blockers, required this.warnings, required this.balance, required this.confirmWord, required this.refundDays});
  factory DeletionPreview.fromJson(Map m) => DeletionPreview(
        canDelete: m['canDelete'] == true,
        hasRecovery: m['hasRecovery'] == true,
        blockers: [for (final x in (m['blockers'] as List? ?? const [])) if (x is Map) DeletionItem.fromJson(x)],
        warnings: [for (final x in (m['warnings'] as List? ?? const [])) if (x is Map) DeletionItem.fromJson(x)],
        balance: (m['balance'] as num?)?.toInt() ?? 0,
        confirmWord: m['confirmWord']?.toString() ?? 'حذف',
        refundDays: (m['refundDays'] as num?)?.toInt() ?? 30,
      );
}

extension AccountApi on ApiClient {
  Future<DeletionPreview> deletionPreview() async => DeletionPreview.fromJson(await get('/me/account/delete/preview'));

  /// يحذف الحساب نهائياً؛ [refund] مطلوبة إن كان في المحفظة رصيد. يعيد حالة الحذف: done أو pending_refund.
  Future<String> deleteAccount({required String password, required String confirm, bool refund = false, String reason = ''}) async {
    final r = await post('/me/account/delete', {'password': password, 'confirm': confirm, 'refund': refund, if (reason.isNotEmpty) 'reason': reason});
    return r['status']?.toString() ?? 'done';
  }

  /// هل يلزم المستخدم أن يوافق على النسخة الحالية من الشروط والخصوصية؟ يعيد رقم النسخة إن لزم، وnull إن لم يلزم.
  Future<String?> pendingConsent() async {
    final r = await get('/legal/consent');
    return r['needs'] == true ? r['version']?.toString() : null;
  }

  Future<void> acceptConsent(String version, {String source = 'app'}) => post('/legal/consent', {'version': version, 'source': source});
}
