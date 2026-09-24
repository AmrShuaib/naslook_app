import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/account_api.dart';
import '../../api/client.dart';
import '../../api/commerce_models.dart' show money;
import '../../core/app_theme.dart';
import '../../core/share/legal_links.dart';
import '../../state/app_state.dart';
import '../../ui/widgets.dart';

final deletionPreviewProvider = FutureProvider.autoDispose<DeletionPreview>((ref) => ref.watch(apiClientProvider).deletionPreview());

/// حذف الحساب من داخل التطبيق (شرط متاجر التطبيقات): يعرض ما يمنع الحذف الآن، وما سيُحذف وما يُحفظ نظاماً،
/// ثم يطلب كتابة كلمة التأكيد وكلمة السر. بعد الحذف يُسجَّل الخروج من هذا الجهاز.
class DeleteAccountPage extends ConsumerStatefulWidget {
  const DeleteAccountPage({super.key});

  @override
  ConsumerState<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends ConsumerState<DeleteAccountPage> {
  final _confirm = TextEditingController(), _password = TextEditingController();
  bool _ack = false, _refund = false, _busy = false, _showPw = false;

  @override
  void initState() {
    super.initState();
    for (final c in [_confirm, _password]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _confirm.dispose();
    _password.dispose();
    super.dispose();
  }

  void _toast(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m), backgroundColor: error ? Joy.danger : null));
  }

  Future<void> _delete(DeletionPreview p) async {
    setState(() => _busy = true);
    try {
      final status = await ref.read(apiClientProvider).deleteAccount(password: _password.text, confirm: _confirm.text.trim(), refund: _refund);
      if (!mounted) return;
      final msg = status == 'pending_refund' ? 'حُذف حسابك. سيُعاد رصيدك إلى وسيلة الدفع خلال ${p.refundDays} يوماً' : 'حُذف حسابك. شكراً لأنك كنت معنا';
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).popUntil((r) => r.isFirst);
      await ref.read(appStateProvider.notifier).logout();
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    } on ApiException catch (e) {
      final code = e.body is Map ? (e.body as Map)['error']?.toString() : null;
      if (code == 'blocked') ref.invalidate(deletionPreviewProvider);
      _toast(switch (code) {
        'bad-password' => 'كلمة السر غير صحيحة',
        'confirm-mismatch' => 'اكتب كلمة «${p.confirmWord}» كما هي',
        'blocked' => 'لا يمكن الحذف الآن، راجع ما يلزم إنهاؤه أولاً',
        _ => e.message,
      }, error: true);
    } catch (_) {
      _toast('تعذّر الحذف، حاول مرة أخرى', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = ref.watch(deletionPreviewProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('حذف الحساب')),
      body: preview.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: ErrorState(e, onRetry: () => ref.invalidate(deletionPreviewProvider))),
        data: (p) {
          final blocked = p.blockers.isNotEmpty;
          final needsRefund = p.balance > 0;
          final ready = !blocked && _ack && _confirm.text.trim() == p.confirmWord && _password.text.isNotEmpty && (!needsRefund || _refund) && !_busy;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              JoyCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                  Row(children: [Icon(Icons.warning_amber_rounded, color: Joy.danger), SizedBox(width: 8), Expanded(child: Text('الحذف نهائي ولا يمكن التراجع عنه', style: TextStyle(fontWeight: FontWeight.w700, color: Joy.danger)))]),
                  SizedBox(height: 10),
                  Text('سيُحذف فوراً:', style: TextStyle(fontWeight: FontWeight.w600)),
                  _Bullet('بريدك واسم المستخدم وصورتك وملفك الشخصي'),
                  _Bullet('منشوراتك وعروضك وتعليقاتك (تُخفى الآن وتُمسح خلال 30 يوماً)'),
                  _Bullet('متابعاتك وتنبيهاتك وعمليات البحث المحفوظة واشتراك الإشعارات'),
                  _Bullet('جلسات الدخول على كل أجهزتك'),
                  SizedBox(height: 8),
                  Text('ما يُحفظ نظاماً:', style: TextStyle(fontWeight: FontWeight.w600)),
                  _Bullet('السجلات المالية (المحفظة والطلبات والمدفوعات) بمعرّف لا يدل عليك'),
                  _Bullet('الرسائل التي وصلت لغيرك، ويظهر اسمك فيها «مستخدم محذوف»'),
                ]),
              ),
              if (blocked) ...[
                const SizedBox(height: 12),
                JoyCard(
                  key: const Key('del-blockers'),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('قبل الحذف يلزم إنهاء ما يلي:', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    for (final b in p.blockers) Padding(key: Key('del-blocker-${b.code}'), padding: const EdgeInsets.only(top: 6), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.block_rounded, size: 18, color: Joy.danger), const SizedBox(width: 6), Expanded(child: Text(b.label))])),
                  ]),
                ),
              ],
              if (p.warnings.isNotEmpty) ...[
                const SizedBox(height: 12),
                JoyCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final w in p.warnings)
                      Padding(key: Key('del-warning-${w.code}'), padding: const EdgeInsets.only(top: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.info_outline_rounded, size: 18, color: Joy.warning), const SizedBox(width: 6), Expanded(child: Text(w.code == 'wallet-balance' ? 'في محفظتك ${money(p.balance)}. سنعيده إلى وسيلة الدفع الأصلية خلال ${p.refundDays} يوماً' : w.label))])),
                  ]),
                ),
              ],
              const SizedBox(height: 16),
              if (needsRefund)
                CheckboxListTile(
                  key: const Key('del-refund'),
                  value: _refund,
                  onChanged: blocked ? null : (v) => setState(() => _refund = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: Text('أطلب استرداد رصيدي (${money(p.balance)}) وحذف حسابي'),
                ),
              CheckboxListTile(
                key: const Key('del-ack'),
                value: _ack,
                onChanged: blocked ? null : (v) => setState(() => _ack = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: const Text('فهمت أن الحذف نهائي'),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('del-confirm'),
                controller: _confirm,
                enabled: !blocked,
                decoration: InputDecoration(labelText: 'اكتب «${p.confirmWord}» للتأكيد', border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('del-password'),
                controller: _password,
                enabled: !blocked,
                obscureText: !_showPw,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: 'كلمة السر',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(icon: Icon(_showPw ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _showPw = !_showPw)),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                key: const Key('del-submit'),
                style: FilledButton.styleFrom(backgroundColor: Joy.danger, padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: ready ? () => _delete(p) : null,
                icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.delete_forever_rounded),
                label: const Text('حذف حسابي نهائياً'),
              ),
              const SizedBox(height: 14),
              TextButton(key: const Key('del-help'), onPressed: () => LegalLinks.open('support#delete-account'), child: const Text('لا تستطيع الحذف؟ تواصل مع الدعم')),
            ],
          );
        },
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('•  ', style: TextStyle(color: Joy.textMuted)), Expanded(child: Text(text, style: const TextStyle(color: Joy.textMuted, height: 1.5)))]),
      );
}
