import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/auth_controller.dart';

/// تسجيل الدخول عبر OTP.
/// Backend يتحقق من الرقم بصيغة دولية (IsPhoneNumber في auth.dto.ts)،
/// لذلك يحوّل التطبيق الأرقام العراقية المحلية إلى صيغة +964... قبل الإرسال.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _otp = TextEditingController();

  @override
  void dispose() {
    _phone.dispose();
    _otp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(loginControllerProvider);
    final isPhone = state.step == AuthStep.phone;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const CircleAvatar(
                      radius: 38,
                      child: Icon(Icons.local_taxi_rounded, size: 42),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      isPhone ? 'أهلًا بك كابتن' : 'تحقق من رقمك',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isPhone
                          ? 'أدخل رقم الهاتف المعتمد في جولة'
                          : 'أدخل رمز التحقق الخاص بالرقم ${state.phone}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 28),
                    if (!isPhone && state.mockCode != null) ...[
                      Material(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                        child: ListTile(
                          leading: const Icon(Icons.developer_mode_rounded),
                          title: const Text('رمز التحقق للتطوير'),
                          subtitle: SelectableText(
                            state.mockCode!,
                            textDirection: TextDirection.ltr,
                          ),
                          trailing: TextButton(
                            onPressed: () => _otp.text = state.mockCode!,
                            child: const Text('استخدام'),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (isPhone)
                      TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          hintText: '7701234567',
                          prefixIcon: _IraqDialCodePrefix(),
                        ),
                        validator: (value) {
                          if (_normalizePhone(value) == null) {
                            return 'أدخل رقمًا عراقيًا صحيحًا، مثال 7701234567 أو 07701234567';
                          }
                          return null;
                        },
                      )
                    else
                      TextFormField(
                        controller: _otp,
                        keyboardType: TextInputType.number,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.center,
                        maxLength: 6,
                        decoration: const InputDecoration(
                          hintText: '• • • • • •',
                          prefixIcon: Icon(Icons.lock_rounded),
                          counterText: '',
                        ),
                        validator: (value) {
                          if (!RegExp(
                            r'^\d{6}$',
                          ).hasMatch(value?.trim() ?? '')) {
                            return 'أدخل رمز التحقق المكوّن من 6 أرقام';
                          }
                          return null;
                        },
                      ),
                    if (state.error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        state.error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: state.isLoading ? null : _submit,
                      child: state.isLoading
                          ? const SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(isPhone ? 'إرسال رمز واتساب' : 'تسجيل الدخول'),
                    ),
                    if (!isPhone)
                      TextButton(
                        onPressed: state.isLoading
                            ? null
                            : () {
                                _otp.clear();
                                ref
                                    .read(loginControllerProvider.notifier)
                                    .changePhone();
                              },
                        child: const Text('تغيير رقم الهاتف'),
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final controller = ref.read(loginControllerProvider.notifier);
    final state = ref.read(loginControllerProvider);
    if (state.step == AuthStep.phone) {
      final phone = _normalizePhone(_phone.text)!;
      await controller.requestOtp(phone);
    } else {
      // نجاح التحقق يحدّث authSessionProvider والراوتر يعيد التوجيه
      // تلقائيًا إلى /home عبر redirect.
      await controller.verifyOtp(_otp.text.trim());
    }
  }
}

class _IraqDialCodePrefix extends StatelessWidget {
  const _IraqDialCodePrefix();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(start: 12, end: 10),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('🇮🇶', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(width: 6),
        Text(
          '+964',
          textDirection: TextDirection.ltr,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

String? _normalizePhone(String? value) {
  var phone = _normalizeDigits(
    value ?? '',
  ).replaceAll(RegExp(r'[\s\-\(\)]'), '').trim();
  if (phone.isEmpty) return null;

  if (phone.startsWith('+964')) {
    phone = phone.substring(4);
  } else if (phone.startsWith('00964')) {
    phone = phone.substring(5);
  } else if (phone.startsWith('964')) {
    phone = phone.substring(3);
  } else if (RegExp(r'^07\d{9}$').hasMatch(phone)) {
    phone = phone.substring(1);
  }

  return RegExp(r'^7\d{9}$').hasMatch(phone) ? '+964$phone' : null;
}

String _normalizeDigits(String value) {
  const arabicZero = 0x0660;
  const persianZero = 0x06F0;
  return value.runes.map((rune) {
    if (rune >= arabicZero && rune <= arabicZero + 9) {
      return String.fromCharCode(0x30 + rune - arabicZero);
    }
    if (rune >= persianZero && rune <= persianZero + 9) {
      return String.fromCharCode(0x30 + rune - persianZero);
    }
    return String.fromCharCode(rune);
  }).join();
}
