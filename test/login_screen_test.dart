import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jowla_driver/features/auth/data/backend_auth_repository.dart';
import 'package:jowla_driver/features/auth/presentation/login_screen.dart';

import 'support/fakes.dart';

Widget _app(FakeAuthRepository auth) => ProviderScope(
  overrides: [authRepositoryProvider.overrideWithValue(auth)],
  child: const MaterialApp(
    locale: Locale('ar', 'IQ'),
    supportedLocales: [Locale('ar', 'IQ')],
    localizationsDelegates: [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: LoginScreen(),
    ),
  ),
);

void main() {
  testWidgets('يقبل الرقم المحلي ويرسله للخادم بصيغة دولية', (tester) async {
    final auth = FakeAuthRepository();
    await tester.pumpWidget(_app(auth));

    expect(find.text('أهلًا بك كابتن'), findsOneWidget);
    expect(find.text('🇮🇶'), findsOneWidget);
    expect(find.text('+964'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '07701234567');
    await tester.tap(find.text('إرسال رمز واتساب'));
    await tester.pumpAndSettle();

    expect(find.text('تحقق من رقمك'), findsOneWidget);
    expect(auth.requestedPhones, ['+9647701234567']);
  });

  testWidgets('يقبل الأرقام العربية ويحولها قبل طلب OTP', (tester) async {
    final auth = FakeAuthRepository();
    await tester.pumpWidget(_app(auth));

    await tester.enterText(find.byType(TextFormField), '٠٧٧٠١٢٣٤٥٦٧');
    await tester.tap(find.text('إرسال رمز واتساب'));
    await tester.pumpAndSettle();

    expect(find.text('تحقق من رقمك'), findsOneWidget);
    expect(auth.requestedPhones, ['+9647701234567']);
  });

  testWidgets('يقبل لصق الرقم المعتمد كاملًا مع رمز البلد', (tester) async {
    final auth = FakeAuthRepository();
    await tester.pumpWidget(_app(auth));

    await tester.enterText(find.byType(TextFormField), '+9647700000001');
    await tester.tap(find.text('إرسال رمز واتساب'));
    await tester.pumpAndSettle();

    expect(find.text('تحقق من رقمك'), findsOneWidget);
    expect(auth.requestedPhones, ['+9647700000001']);
  });

  testWidgets('نجاح طلب الرمز ينقل إلى خطوة OTP ويعرض رمز التطوير', (
    tester,
  ) async {
    final auth = FakeAuthRepository();
    await tester.pumpWidget(_app(auth));

    await tester.enterText(find.byType(TextFormField), '7700000001');
    await tester.tap(find.text('إرسال رمز واتساب'));
    await tester.pumpAndSettle();

    expect(find.text('تحقق من رقمك'), findsOneWidget);
    // mockCode يظهر في وضع التطوير فقط (يرسله Backend عند
    // OTP_EXPOSE_MOCK_CODE=true) — لا يوجد أي تسجيل دخول محلي.
    expect(find.text('رمز التحقق للتطوير'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is SelectableText && widget.data == '123456',
      ),
      findsOneWidget,
    );
  });

  testWidgets('رمز أقصر من 6 أرقام يُرفض محليًا', (tester) async {
    final auth = FakeAuthRepository();
    await tester.pumpWidget(_app(auth));
    await tester.enterText(find.byType(TextFormField), '7700000001');
    await tester.tap(find.text('إرسال رمز واتساب'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), '123');
    await tester.tap(find.text('تسجيل الدخول'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('أدخل رمز التحقق المكوّن من 6 أرقام'),
      findsOneWidget,
    );
  });
}
