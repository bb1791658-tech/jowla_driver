import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

/// بوابة الإقلاع: لا يعمل التطبيق قبل نجاح GET /api/health.
final appStartupControllerProvider =
    AsyncNotifierProvider<AppStartupController, void>(AppStartupController.new);

class AppStartupController extends AsyncNotifier<void> {
  @override
  Future<void> build() {
    return ref.read(backendHealthServiceProvider).checkHealth();
  }

  Future<void> retry() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(backendHealthServiceProvider).checkHealth(),
    );
  }
}
