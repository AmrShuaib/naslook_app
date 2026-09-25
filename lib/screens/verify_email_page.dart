import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_theme.dart';
import '../state/app_state.dart';

/// بوابة التأكيد: لا دخول قبل إدخال الرمز المرسل إلى البريد (عند التسجيل، أو عند دخول حساب لم يؤكد بريده).
/// بعد الرمز الصحيح يدخل التطبيق تلقائياً بكلمة السر المحفوظة في الذاكرة، أو يكمل بالجلسة القائمة.
class VerifyEmailPage extends ConsumerStatefulWidget {
  const VerifyEmailPage({super.key});

  static const resendSeconds = 60;

  @override
  ConsumerState<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends ConsumerState<VerifyEmailPage> {
  final _code = TextEditingController();
  // متحكم حوار «تغيير البريد» يعيش مع الصفحة: التخلص منه فور إغلاق الحوار يسقط أثناء حركة الإغلاق
  final _newEmail = TextEditingController();
  Timer? _timer;
  int _wait = 0;
  bool _resending = false;

  @override
  void initState() {
    super.initState();
    _code.addListener(() => setState(() {}));
    // أُرسل رمز للتو (تسجيل أو دخول): نبدأ العدّاد حتى لا يُطلب رمز ثانٍ قبل دقيقة؛ وإن لم يُرسل لأن آخر رمز حديث
    // يخبرنا الخادم بالثواني المتبقية
    final s = ref.read(appStateProvider);
    if (s.pendingCodeSent) {
      _startWait(VerifyEmailPage.resendSeconds);
    } else if (s.pendingRetryIn > 0) {
      _startWait(s.pendingRetryIn);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    _newEmail.dispose();
    super.dispose();
  }

  void _startWait(int seconds) {
    _timer?.cancel();
    setState(() => _wait = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _wait = _wait > 0 ? _wait - 1 : 0);
      if (_wait == 0) t.cancel();
    });
  }

  void _toast(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m), backgroundColor: error ? Colors.red[700] : null));
  }

  Future<void> _submit() async {
    final code = _code.text.trim();
    if (code.length != 6) return;
    final ok = await ref.read(appStateProvider.notifier).verifyPending(code);
    if (!mounted) return;
    if (!ok) {
      final err = ref.read(appStateProvider).error;
      if (err != null) _toast(err, error: true);
    }
  }

  Future<void> _resend() async {
    setState(() => _resending = true);
    final r = await ref.read(appStateProvider.notifier).resendPending();
    if (!mounted) return;
    setState(() => _resending = false);
    if (r.error == null) {
      _toast('أرسلنا رمزاً جديداً إلى بريدك');
      _startWait(VerifyEmailPage.resendSeconds);
    } else {
      _toast(r.error!, error: true);
      if (r.retryIn > 0) _startWait(r.retryIn);
    }
  }

  /// بريد خاطئ عند التسجيل: يطلب بريداً جديداً فيُستبدل ويصل رمز جديد.
  Future<void> _changeEmail() async {
    final ctrl = _newEmail..text = ref.read(appStateProvider).pendingEmail ?? '';
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تغيير البريد'),
        content: TextField(key: const Key('verify-new-email'), controller: ctrl, autofocus: true, keyboardType: TextInputType.emailAddress, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'البريد الصحيح', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('إلغاء')),
          FilledButton(key: const Key('verify-new-email-ok'), onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()), child: const Text('أرسل الرمز')),
        ],
      ),
    );
    if (email == null || email.isEmpty || !mounted) return;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) { _toast('صيغة البريد غير صحيحة', error: true); return; }
    final err = await ref.read(appStateProvider.notifier).changePendingEmail(email);
    if (!mounted) return;
    if (err != null) { _toast(err, error: true); return; }
    _code.clear();
    final sent = ref.read(appStateProvider).pendingCodeSent;
    _toast(sent ? 'أرسلنا الرمز إلى بريدك الجديد' : 'غُيّر البريد؛ اضغط «إعادة الإرسال» إن لم يصلك الرمز');
    if (sent) {
      _startWait(VerifyEmailPage.resendSeconds);
    } else {
      _timer?.cancel();
      setState(() => _wait = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStateProvider);
    final email = s.pendingEmail ?? '';
    final ready = _code.text.trim().length == 6 && !s.busy;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Icon(Icons.mark_email_read_outlined, size: 56, color: Joy.primary),
                const SizedBox(height: 16),
                const Text('أكّد بريدك للمتابعة', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text.rich(
                  TextSpan(children: [
                    const TextSpan(text: 'أرسلنا رمزاً من 6 أرقام إلى '),
                    TextSpan(text: email, style: const TextStyle(fontWeight: FontWeight.w700), semanticsLabel: email),
                    const TextSpan(text: '. أدخله هنا لتدخل حسابك.'),
                  ]),
                  key: const Key('verify-email'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black87, height: 1.6),
                ),
                if (!s.pendingCodeSent) ...[
                  const SizedBox(height: 8),
                  const Text('إن لم يصلك الرمز خلال دقيقة اضغط «إعادة الإرسال»، وتفقّد صندوق «غير المرغوب».', key: Key('verify-not-sent'), textAlign: TextAlign.center, style: TextStyle(color: Colors.black54, fontSize: 13)),
                ],
                const SizedBox(height: 24),
                TextField(
                  key: const Key('verify-code'),
                  controller: _code,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.ltr,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(fontSize: 26, letterSpacing: 8, fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(counterText: '', hintText: '••••••', border: OutlineInputBorder()),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('verify-submit'),
                  onPressed: ready ? _submit : null,
                  style: FilledButton.styleFrom(backgroundColor: Joy.primary, padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: s.busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('تأكيد ودخول', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 8),
                TextButton(
                  key: const Key('verify-resend'),
                  onPressed: _wait > 0 || _resending || s.busy ? null : _resend,
                  child: Text(_wait > 0 ? 'إعادة الإرسال بعد $_wait ث' : 'إعادة إرسال الرمز'),
                ),
                if (ref.read(appStateProvider.notifier).canChangePendingEmail)
                  TextButton(
                    key: const Key('verify-change-email'),
                    onPressed: s.busy ? null : _changeEmail,
                    child: const Text('البريد خاطئ؟ غيّره'),
                  ),
                TextButton(
                  key: const Key('verify-back'),
                  onPressed: s.busy ? null : () => ref.read(appStateProvider.notifier).cancelPending(),
                  child: const Text('الرجوع إلى شاشة الدخول', style: TextStyle(color: Colors.black54)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
