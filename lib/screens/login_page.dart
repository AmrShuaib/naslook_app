import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/client.dart';
import '../core/require_account.dart';
import '../core/share/legal_links.dart';
import '../state/app_state.dart';

enum _Mode { login, register, forgot, reset }

/// حالة فحص توفر اسم المستخدم أثناء الكتابة.
enum _NickStatus { idle, checking, available, taken }

/// شاشة الدخول والتسجيل بالبريد الإلكتروني وكلمة السر (بدون تشفير من جهة العميل)، مع استعادة كلمة السر
/// برمز يصل بالبريد. الدخول يقبل البريد أو اسم المستخدم للحسابات القديمة.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _handle = TextEditingController(), _email = TextEditingController(), _nickname = TextEditingController(), _pin = TextEditingController(), _code = TextEditingController();
  _Mode _mode = _Mode.login;
  bool _showPin = false, _localBusy = false;
  // الموافقة على الشروط وسياسة الخصوصية إلزامية لإنشاء حساب (شرط متاجر التطبيقات للمحتوى من المستخدمين)
  bool _terms = false;
  _NickStatus _nickStatus = _NickStatus.idle;
  Timer? _nickTimer;
  int _nickSeq = 0;

  static const _primary = Color(0xFF1565C0);

  @override
  void initState() {
    super.initState();
    // «أنشئ حساباً» من تبويب الزائر: نبدأ على التسجيل ثم نعيد المفتاح (لا يُعدَّل مزوّد أثناء البناء)
    if (ref.read(loginStartsRegisterProvider)) {
      _mode = _Mode.register;
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) ref.read(loginStartsRegisterProvider.notifier).state = false; });
    }
  }

  /// التصفّح بلا حساب: الخريطة والأماكن والسوق والفعاليات، والأفعال تطلب الدخول عند الحاجة.
  void _browseAsGuest() {
    ref.read(guestWantsLoginProvider.notifier).state = false;
    ref.read(guestBrowseProvider.notifier).state = true;
  }

  @override
  void dispose() {
    _nickTimer?.cancel();
    for (final c in [_handle, _email, _nickname, _pin, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isRegister => _mode == _Mode.register;

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), backgroundColor: error ? Colors.red[700] : null));
  }

  void _switch(_Mode m) {
    ref.read(appStateProvider.notifier).clearError();
    _formKey.currentState?.reset();
    setState(() { _mode = m; _showPin = false; });
  }

  String _err(Object e) => e is ApiException ? e.message : 'حدث خطأ غير متوقع';

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final notifier = ref.read(appStateProvider.notifier);
    final pin = _pin.text.trim();
    switch (_mode) {
      case _Mode.login:
        final ok = await notifier.login(_handle.text.trim().toLowerCase(), pin);
        if (!ok) _showStateError();
      case _Mode.register:
        if (!_terms) { _toast('يلزم الموافقة على شروط الاستخدام وسياسة الخصوصية', error: true); return; }
        final ok = await notifier.register(_nickname.text.trim().toLowerCase(), pin, email: _email.text.trim().toLowerCase(), acceptTerms: true);
        if (!ok) _showStateError();
      case _Mode.forgot:
        await _sendCode();
      case _Mode.reset:
        final ok = await notifier.resetPassword(email: _email.text.trim().toLowerCase(), code: _code.text.trim(), password: pin);
        if (!ok) _showStateError();
    }
  }

  void _showStateError() {
    if (!mounted) return;
    final error = ref.read(appStateProvider).error;
    if (error != null) _toast(error, error: true);
  }

  /// يطلب رمز الاستعادة ثم ينتقل إلى خطوة إدخال الرمز وكلمة السر الجديدة.
  Future<void> _sendCode() async {
    setState(() => _localBusy = true);
    try {
      await ref.read(apiClientProvider).forgotPassword(_email.text);
      _toast('إن كان البريد مسجّلاً لدينا فسيصلك رمز خلال دقيقة');
      if (mounted) setState(() { _mode = _Mode.reset; _code.clear(); _pin.clear(); });
    } catch (e) {
      _toast(_err(e), error: true);
    } finally {
      if (mounted) setState(() => _localBusy = false);
    }
  }

  // قواعد الخادم: اسم المستخدم [a-z0-9_] من 3 إلى 25 فريد، وكلمة السر 8 خانات على الأقل عند التسجيل
  static final _nickRe = RegExp(r'^[a-z0-9_]{3,25}$');
  static const _nickMax = 25;

  /// يفحص توفر اسم المستخدم بعد توقف الكتابة (400 مللي ثانية) ويتجاهل نتائج الفحوص الأقدم.
  void _onNicknameChanged(String v) {
    _nickTimer?.cancel();
    final s = v.trim().toLowerCase();
    if (!_nickRe.hasMatch(s)) { if (_nickStatus != _NickStatus.idle) setState(() => _nickStatus = _NickStatus.idle); return; }
    setState(() => _nickStatus = _NickStatus.checking);
    final seq = ++_nickSeq;
    _nickTimer = Timer(const Duration(milliseconds: 400), () async {
      bool? ok;
      try { ok = await ref.read(apiClientProvider).nicknameAvailable(s); } catch (_) { ok = null; }
      if (!mounted || seq != _nickSeq) return;
      setState(() => _nickStatus = ok == null ? _NickStatus.idle : ok ? _NickStatus.available : _NickStatus.taken);
    });
  }
  static final _emailRe = RegExp(r'^[a-z0-9][a-z0-9._%+-]{0,63}@[a-z0-9.-]+\.[a-z]{2,}$');
  static const _pinMin = 8;

  String? _validateHandle(String? v) {
    final s = (v ?? '').trim().toLowerCase();
    if (s.isEmpty) return 'أدخل البريد أو اسم المستخدم';
    if (s.contains('@')) return _emailRe.hasMatch(s) ? null : 'صيغة البريد غير صحيحة';
    if (s.length < 3) return 'اسم المستخدم 3 خانات على الأقل';
    if (!_nickRe.hasMatch(s)) return 'حروف إنجليزية صغيرة وأرقام و _ فقط، بلا مسافات';
    return null;
  }

  String? _validateEmail(String? v) {
    final s = (v ?? '').trim().toLowerCase();
    if (s.isEmpty) return 'أدخل البريد الإلكتروني';
    if (!_emailRe.hasMatch(s)) return 'صيغة البريد غير صحيحة';
    return null;
  }

  String? _validateNickname(String? v) {
    final s = (v ?? '').trim().toLowerCase();
    if (s.isEmpty) return 'أدخل اسم المستخدم';
    if (s.length < 3) return 'اسم المستخدم يجب أن يكون 3 خانات على الأقل';
    if (s.length > _nickMax) return 'اسم المستخدم يجب ألا يتجاوز $_nickMax حرفاً';
    if (!_nickRe.hasMatch(s)) return 'حروف إنجليزية صغيرة وأرقام و _ فقط، بلا مسافات';
    if (_nickStatus == _NickStatus.taken) return 'هذا الاسم مستخدم، اختر غيره';
    return null;
  }

  String? _validatePin(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'أدخل كلمة السر';
    if ((_isRegister || _mode == _Mode.reset) && s.length < _pinMin) return 'كلمة السر يجب أن تكون $_pinMin خانات على الأقل';
    if (s.length > 64) return 'كلمة السر طويلة جداً';
    return null;
  }

  String? _validateCode(String? v) {
    final s = (v ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (s.length != 6) return 'الرمز مكوّن من 6 أرقام';
    return null;
  }

  InputDecoration _dec(String label, IconData icon, {String? helper, Widget? suffix}) => InputDecoration(
        labelText: label, helperText: helper, helperMaxLines: 2, errorMaxLines: 2, prefixIcon: Icon(icon), suffixIcon: suffix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );

  Widget _emailField({required Key key, bool autofocus = false, bool last = false}) => TextFormField(
        key: key, controller: _email, autofocus: autofocus, autofillHints: const [AutofillHints.email], textInputAction: last ? TextInputAction.done : TextInputAction.next,
        onFieldSubmitted: last ? (_) => _submit() : null,
        keyboardType: TextInputType.emailAddress, autocorrect: false, textDirection: TextDirection.ltr,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_@.+-]')), LengthLimitingTextInputFormatter(80)],
        validator: _validateEmail, decoration: _dec('البريد الإلكتروني', Icons.alternate_email_rounded),
      );

  Widget _pinField({required Key key, String? helper, String label = 'كلمة السر', bool last = true, List<String>? hints}) => TextFormField(
        key: key, controller: _pin, obscureText: !_showPin, keyboardType: TextInputType.visiblePassword,
        inputFormatters: [LengthLimitingTextInputFormatter(64)], autofillHints: hints ?? const [AutofillHints.password],
        textInputAction: last ? TextInputAction.done : TextInputAction.next, onFieldSubmitted: last ? (_) => _submit() : null, validator: _validatePin,
        decoration: _dec(label, Icons.lock, helper: helper, suffix: IconButton(icon: Icon(_showPin ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _showPin = !_showPin))),
      );

  List<Widget> _fields() => switch (_mode) {
        _Mode.login => [
            TextFormField(
              key: const Key('login-handle'), controller: _handle, autofillHints: const [AutofillHints.username, AutofillHints.email], textInputAction: TextInputAction.next,
              keyboardType: TextInputType.emailAddress, autocorrect: false, textDirection: TextDirection.ltr,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_@.+-]')), LengthLimitingTextInputFormatter(80)],
              validator: _validateHandle, decoration: _dec('البريد أو اسم المستخدم', Icons.person),
            ),
            const SizedBox(height: 20),
            _pinField(key: const Key('login-password')),
            Align(alignment: AlignmentDirectional.centerStart, child: TextButton(key: const Key('login-forgot'), onPressed: () => _switch(_Mode.forgot), child: const Text('نسيت كلمة السر؟', style: TextStyle(color: _primary)))),
          ],
        _Mode.register => [
            _emailField(key: const Key('reg-email')),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('reg-nickname'), controller: _nickname, autofillHints: const [AutofillHints.newUsername], textInputAction: TextInputAction.next,
              keyboardType: TextInputType.visiblePassword, autocorrect: false, textDirection: TextDirection.ltr,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_]')), LengthLimitingTextInputFormatter(_nickMax)],
              onChanged: _onNicknameChanged,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: _validateNickname,
              decoration: _dec(
                'اسم المستخدم', Icons.badge_outlined,
                helper: switch (_nickStatus) { _NickStatus.available => 'متاح', _NickStatus.taken => 'هذا الاسم مستخدم، اختر غيره', _NickStatus.checking => 'جارٍ التحقق…', _NickStatus.idle => 'فريد، يظهر للآخرين: حروف إنجليزية صغيرة وأرقام و _ (3 إلى 25)' },
                suffix: switch (_nickStatus) {
                  _NickStatus.available => const Icon(Icons.check_circle_rounded, key: Key('nick-available'), color: Color(0xFF1FA35A)),
                  _NickStatus.taken => const Icon(Icons.cancel_rounded, key: Key('nick-taken'), color: Color(0xFFD23B3B)),
                  _NickStatus.checking => const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
                  _NickStatus.idle => null,
                },
              ),
            ),
            const SizedBox(height: 16),
            _pinField(key: const Key('reg-password'), helper: '8 خانات على الأقل، حروف أو أرقام أو رموز', hints: const [AutofillHints.newPassword]),
            const SizedBox(height: 10),
            _termsRow(),
          ],
        _Mode.forgot => [
            const Text('اكتب بريدك المسجّل وسنرسل إليه رمزاً من 6 أرقام لتعيين كلمة سر جديدة.', style: TextStyle(color: Colors.black54, height: 1.5)),
            const SizedBox(height: 16),
            _emailField(key: const Key('forgot-email'), autofocus: true, last: true),
          ],
        _Mode.reset => [
            Text('أرسلنا الرمز إلى ${_email.text.trim().toLowerCase()}. صالح لمدة 15 دقيقة.', style: const TextStyle(color: Colors.black54, height: 1.5)),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('reset-code'), controller: _code, autofocus: true, keyboardType: TextInputType.number, textDirection: TextDirection.ltr, textAlign: TextAlign.center,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)], autofillHints: const [AutofillHints.oneTimeCode],
              style: const TextStyle(fontSize: 22, letterSpacing: 6, fontWeight: FontWeight.w700), validator: _validateCode, decoration: _dec('رمز التأكيد', Icons.pin_outlined),
            ),
            const SizedBox(height: 16),
            _pinField(key: const Key('reset-password'), label: 'كلمة السر الجديدة', helper: '8 خانات على الأقل', hints: const [AutofillHints.newPassword]),
            Align(alignment: AlignmentDirectional.centerStart, child: TextButton(key: const Key('reset-resend'), onPressed: _localBusy ? null : _sendCode, child: const Text('لم يصلك؟ إعادة الإرسال', style: TextStyle(color: _primary)))),
          ],
      };

  /// مربع الموافقة مع رابطي الشروط والخصوصية (يُفتحان داخل التطبيق).
  Widget _termsRow() => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(key: const Key('reg-terms'), value: _terms, onChanged: (v) => setState(() => _terms = v ?? false)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                const Text('أوافق على ', style: TextStyle(height: 1.5)),
                _link('شروط الاستخدام', 'terms', const Key('reg-terms-link')),
                const Text(' و', style: TextStyle(height: 1.5)),
                _link('سياسة الخصوصية', 'privacy', const Key('reg-privacy-link')),
                const Text('، وأتعهد بعدم نشر أي محتوى مسيء. لا تسامح مع المحتوى المسيء أو المستخدمين المسيئين.', style: TextStyle(height: 1.5, fontSize: 12.5, color: Colors.black54)),
              ]),
            ),
          ),
        ],
      );

  Widget _link(String label, String page, Key key) => InkWell(
        key: key,
        onTap: () => LegalLinks.open(page),
        child: Text(label, style: const TextStyle(color: _primary, fontWeight: FontWeight.w700, decoration: TextDecoration.underline, height: 1.5)),
      );

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(appStateProvider.select((s) => s.busy)) || _localBusy;
    final title = switch (_mode) { _Mode.login => 'تسجيل الدخول', _Mode.register => 'إنشاء حساب جديد', _Mode.forgot => 'استعادة كلمة السر', _Mode.reset => 'كلمة سر جديدة' };
    final action = switch (_mode) { _Mode.login => 'دخول', _Mode.register => 'إنشاء الحساب', _Mode.forgot => 'إرسال الرمز', _Mode.reset => 'تعيين كلمة السر' };

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFEEF2F7),
        body: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('NASLIFE', style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: _primary, letterSpacing: 2)),
                    const SizedBox(height: 40),
                    Container(
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, 6))]),
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _formKey,
                        child: AutofillGroup(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 20),
                              ..._fields(),
                              const SizedBox(height: 24),
                              ElevatedButton(
                                key: const Key('auth-submit'),
                                style: ElevatedButton.styleFrom(backgroundColor: _primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                onPressed: busy ? null : _submit,
                                child: busy
                                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                                    : Text(action, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_mode == _Mode.login || _mode == _Mode.register)
                      TextButton(
                        key: const Key('auth-toggle'),
                        onPressed: busy ? null : () => _switch(_isRegister ? _Mode.login : _Mode.register),
                        child: Text(_isRegister ? 'لديك حساب؟ تسجيل الدخول' : 'ليس لديك حساب؟ إنشاء حساب جديد', style: const TextStyle(color: _primary)),
                      )
                    else
                      TextButton(key: const Key('auth-back'), onPressed: busy ? null : () => _switch(_Mode.login), child: const Text('العودة إلى تسجيل الدخول', style: TextStyle(color: _primary))),
                    if (_mode == _Mode.login)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          const Text('بالدخول أنت توافق على ', style: TextStyle(fontSize: 12.5, color: Colors.black54, height: 1.5)),
                          _link('الشروط', 'terms', const Key('login-terms-link')),
                          const Text(' و', style: TextStyle(fontSize: 12.5, color: Colors.black54, height: 1.5)),
                          _link('سياسة الخصوصية', 'privacy', const Key('login-privacy-link')),
                        ]),
                      ),
                    const SizedBox(height: 4),
                    TextButton.icon(
                      key: const Key('login-browse-guest'),
                      onPressed: busy ? null : _browseAsGuest,
                      icon: const Icon(Icons.explore_outlined, size: 20, color: _primary),
                      label: const Text('تصفّح بدون حساب', style: TextStyle(color: _primary, fontWeight: FontWeight.w700, fontSize: 15)),
                    ),
                    TextButton.icon(key: const Key('login-support'), onPressed: () => LegalLinks.open('support'), icon: const Icon(Icons.support_agent_rounded, size: 18, color: Colors.black54), label: const Text('الدعم والمساعدة', style: TextStyle(color: Colors.black54))),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
