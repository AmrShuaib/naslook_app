import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_state.dart';

/// شاشة الدخول/التسجيل بالنك نيم + الرقم السري (بدون تشفير من جهة العميل).
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _nickname = TextEditingController();
  final _pin = TextEditingController();
  bool _isRegister = false;
  bool _showPin = false;

  static const _primary = Color(0xFF1565C0);

  @override
  void dispose() {
    _nickname.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final notifier = ref.read(appStateProvider.notifier);
    final nickname = _nickname.text.trim();
    final pin = _pin.text.trim();
    final ok = _isRegister
        ? await notifier.register(nickname, pin)
        : await notifier.login(nickname, pin);
    if (!ok && mounted) {
      final error = ref.read(appStateProvider).error;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.red[700]),
        );
      }
    }
  }

  String? _validateNickname(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'أدخل النك نيم';
    if (s.length < 3) return 'النك نيم يجب أن يكون 3 أحرف على الأقل';
    if (s.length > 30) return 'النك نيم طويل جداً';
    return null;
  }

  String? _validatePin(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'أدخل الرقم السري';
    if (s.length < 4) return 'الرقم السري يجب أن يكون 4 أحرف أو أرقام على الأقل';
    if (s.length > 64) return 'الرقم السري طويل جداً';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(appStateProvider.select((s) => s.busy));

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
                    const Text(
                      'NASLIFE',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: _primary,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 40),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 12,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _formKey,
                        child: AutofillGroup(
                          child: Column(
                            children: [
                              Text(
                                _isRegister ? 'إنشاء حساب جديد' : 'تسجيل الدخول',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 20),
                              TextFormField(
                                controller: _nickname,
                                enabled: !busy,
                                autofillHints: const [AutofillHints.username],
                                textInputAction: TextInputAction.next,
                                validator: _validateNickname,
                                decoration: InputDecoration(
                                  labelText: 'النك نيم',
                                  prefixIcon: const Icon(Icons.person),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              TextFormField(
                                controller: _pin,
                                enabled: !busy,
                                obscureText: !_showPin,
                                keyboardType: TextInputType.visiblePassword,
                                inputFormatters: [
                                  LengthLimitingTextInputFormatter(64),
                                ],
                                autofillHints: const [AutofillHints.password],
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _submit(),
                                validator: _validatePin,
                                decoration: InputDecoration(
                                  labelText: 'الرقم السري',
                                  prefixIcon: const Icon(Icons.lock),
                                  suffixIcon: IconButton(
                                    icon: Icon(_showPin
                                        ? Icons.visibility_off
                                        : Icons.visibility),
                                    onPressed: () =>
                                        setState(() => _showPin = !_showPin),
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 30),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _primary,
                                    foregroundColor: Colors.white,
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: busy ? null : _submit,
                                  child: busy
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Text(
                                          _isRegister ? 'إنشاء الحساب' : 'دخول',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () {
                              ref.read(appStateProvider.notifier).clearError();
                              setState(() => _isRegister = !_isRegister);
                            },
                      child: Text(
                        _isRegister
                            ? 'لديك حساب؟ تسجيل الدخول'
                            : 'ليس لديك حساب؟ إنشاء حساب جديد',
                        style: const TextStyle(color: _primary),
                      ),
                    ),
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
