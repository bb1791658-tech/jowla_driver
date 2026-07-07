import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/documents/presentation/documents_screen.dart';
import '../../features/home/presentation/driver_shell.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/trip/presentation/trip_screen.dart';
import '../../features/wallet/presentation/wallet_screen.dart';

final _routerRefreshProvider = Provider<_RouterRefresh>((ref) {
  final refresh = _RouterRefresh();
  ref.listen(authSessionProvider, (_, next) => refresh.notify());
  ref.onDispose(refresh.dispose);
  return refresh;
});

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ref.watch(_routerRefreshProvider);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authSessionProvider);
      if (auth.isLoading && auth.valueOrNull == null) {
        return state.matchedLocation == '/splash' ? null : '/splash';
      }
      final authenticated = auth.valueOrNull != null;
      final isLogin = state.matchedLocation == '/login';
      final isSplash = state.matchedLocation == '/splash';
      if (!authenticated && !isLogin) return '/login';
      if (authenticated && (isSplash || isLogin)) return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const _SplashScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/home', builder: (context, state) => const DriverShell()),
      GoRoute(path: '/trip', builder: (context, state) => const TripScreen()),
      GoRoute(
        path: '/documents',
        builder: (context, state) => const DocumentsScreen(),
      ),
      GoRoute(
        path: '/wallet',
        builder: (context, state) => const WalletScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
});

class _RouterRefresh extends ChangeNotifier {
  void notify() => notifyListeners();
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
