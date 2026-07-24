import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jowla_driver/core/errors/app_exception.dart';
import 'package:jowla_driver/core/providers.dart';
import 'package:jowla_driver/core/services/backend_health_service.dart';
import 'package:jowla_driver/core/startup/app_startup_controller.dart';

class _FakeBackendHealthService extends BackendHealthService {
  var isHealthy = true;
  var calls = 0;

  @override
  Future<void> checkHealth() async {
    calls++;
    if (!isHealthy) {
      throw const AppException('الخادم غير متاح للاختبار.');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('يوقف التطبيق عند سقوط الخادم ويعيده بعد نجاح الفحص', () async {
    final health = _FakeBackendHealthService();
    final container = ProviderContainer(
      overrides: [backendHealthServiceProvider.overrideWithValue(health)],
    );
    addTearDown(container.dispose);

    await container.read(appStartupControllerProvider.future);
    expect(container.read(appStartupControllerProvider).hasValue, isTrue);

    health.isHealthy = false;
    container.read(backendAvailabilityEventsProvider).reportUnavailable();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(appStartupControllerProvider).hasError, isTrue);

    health.isHealthy = true;
    await container.read(appStartupControllerProvider.notifier).retry();

    expect(container.read(appStartupControllerProvider).hasValue, isTrue);
    expect(health.calls, greaterThanOrEqualTo(3));
  });
}
