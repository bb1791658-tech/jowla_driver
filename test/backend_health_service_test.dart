import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jowla_driver/core/config/app_config.dart';
import 'package:jowla_driver/core/services/backend_health_service.dart';

Future<HttpServer> _healthServer({Duration delay = Duration.zero}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  unawaited(
    server.forEach((request) async {
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      request.response
        ..headers.contentType = ContentType.json
        ..write('{"status":"ok","service":"jowla-api"}');
      await request.response.close();
    }),
  );
  return server;
}

void main() {
  tearDown(AppConfig.resetResolvedBackendOrigin);

  test(
    'uses the first healthy backend without waiting for slow candidates',
    () async {
      final slow = await _healthServer(delay: const Duration(seconds: 2));
      final fast = await _healthServer();
      addTearDown(() async {
        await slow.close(force: true);
        await fast.close(force: true);
      });

      final slowOrigin = 'http://${slow.address.host}:${slow.port}';
      final fastOrigin = 'http://${fast.address.host}:${fast.port}';
      final service = BackendHealthService(
        originCandidates: [slowOrigin, fastOrigin],
      );

      final stopwatch = Stopwatch()..start();
      await service.checkHealth();
      stopwatch.stop();

      expect(AppConfig.backendOrigin, fastOrigin);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    },
  );
}
