import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/startup/app_startup_controller.dart';
import 'core/theme/app_theme.dart';
import 'shared/screens/backend_gate_screen.dart';

class JowlaDriverApp extends ConsumerWidget {
  const JowlaDriverApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startup = ref.watch(appStartupControllerProvider);
    // في التطوير لا تحبس الواجهة خلف فحص الصحة؛ تبقى طلبات البيانات الحقيقية
    // مرتبطة بالخادم، بينما يمكن اختبار التنقل وحساب التطوير عند توقفه.
    if (kDebugMode) {
      return _buildApp(routerConfig: ref.watch(appRouterProvider));
    }
    return startup.when(
      data: (_) => _buildApp(routerConfig: ref.watch(appRouterProvider)),
      loading: () => _buildApp(home: const BackendLoadingScreen()),
      error: (error, _) => _buildApp(
        home: BackendUnavailableScreen(
          message: error.toString(),
          onRetry: () =>
              ref.read(appStartupControllerProvider.notifier).retry(),
        ),
      ),
    );
  }

  Widget _buildApp({RouterConfig<Object>? routerConfig, Widget? home}) {
    const localizationsDelegates = [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ];
    const supportedLocales = [Locale('ar', 'IQ')];
    Widget rtl(BuildContext context, Widget? child) => Directionality(
      textDirection: TextDirection.rtl,
      child: child ?? const SizedBox.shrink(),
    );
    if (routerConfig != null) {
      return MaterialApp.router(
        title: 'جولة للسائق',
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar', 'IQ'),
        supportedLocales: supportedLocales,
        localizationsDelegates: localizationsDelegates,
        theme: AppTheme.light,
        routerConfig: routerConfig,
        builder: rtl,
      );
    }
    return MaterialApp(
      title: 'جولة للسائق',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'IQ'),
      supportedLocales: supportedLocales,
      localizationsDelegates: localizationsDelegates,
      theme: AppTheme.light,
      home: home,
      builder: rtl,
    );
  }
}
