import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/router/app_navigator.dart';
import 'core/startup/app_startup_controller.dart';
import 'core/theme/app_theme.dart';
import 'shared/screens/backend_gate_screen.dart';
import 'features/communications/presentation/communication_navigation_bridge.dart';

class JowlaDriverApp extends ConsumerWidget {
  const JowlaDriverApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startup = ref.watch(appStartupControllerProvider);
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
        themeMode: ThemeMode.light,
        scaffoldMessengerKey: rootScaffoldMessengerKey,
        routerConfig: routerConfig,
        builder: (context, child) => rtl(
          context,
          CommunicationNavigationBridge(
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      );
    }
    return MaterialApp(
      title: 'جولة للسائق',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'IQ'),
      supportedLocales: supportedLocales,
      localizationsDelegates: localizationsDelegates,
      theme: AppTheme.light,
      themeMode: ThemeMode.light,
      home: home,
      builder: rtl,
    );
  }
}
