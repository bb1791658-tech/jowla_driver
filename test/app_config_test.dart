import 'package:flutter_test/flutter_test.dart';
import 'package:jowla_driver/core/config/app_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('إعداد التطوير يحمّل عناوين Backend من الأصل المرفق', () async {
    await AppConfig.initialize();

    expect(
      AppConfig.backendOriginCandidates,
      contains('http://192.168.0.151:3000'),
    );
    expect(
      AppConfig.healthUrlForOrigin(AppConfig.backendOriginCandidates.first),
      'http://192.168.0.151:3000/api/health',
    );
    expect(
      AppConfig.mapTileUrlTemplate,
      'http://192.168.0.151:8080/styles/day/{z}/{x}/{y}.png',
    );
    expect(
      AppConfig.mapStyleUrl,
      'http://192.168.0.151:8080/styles/day/style.json',
    );
    expect(AppConfig.mapDataVersion, 'iraq-2026-07');
    expect(AppConfig.roadRouteBaseUrl, 'http://192.168.0.151:5001');
    expect(AppConfig.geocodingBaseUrl, 'http://192.168.0.151:7070');
  });
}
