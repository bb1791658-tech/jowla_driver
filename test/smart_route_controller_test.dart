import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jowla_driver/core/services/road_route_service.dart';
import 'package:jowla_driver/core/services/smart_route_controller.dart';
import 'package:latlong2/latlong.dart';

class _FakeRoadRouteService extends RoadRouteService {
  _FakeRoadRouteService() : super(client: Dio());

  var calls = 0;

  @override
  Future<RoadRoute?> routeDetails(RoadRouteRequest request) async {
    calls += 1;
    return RoadRoute(
      points: [request.start, request.end],
      distanceMeters: 10000,
      durationSeconds: 900,
    );
  }
}

void main() {
  test('المسافة من خط المسار تميز السير عليه عن الانحراف الحقيقي', () {
    const path = [LatLng(33, 44), LatLng(33, 45)];

    final onRoad = SmartRouteController.distanceFromPathMeters(
      const LatLng(33.0001, 44.5),
      path,
    );
    final offRoad = SmartRouteController.distanceFromPathMeters(
      const LatLng(33.01, 44.5),
      path,
    );

    expect(onRoad, lessThan(20));
    expect(offRoad, greaterThan(1000));
  });

  test('لا يعيد حساب المسار إلا بعد ثلاث قراءات انحراف متتالية', () async {
    final service = _FakeRoadRouteService();
    final controller = SmartRouteController(
      service,
      rerouteCooldown: Duration.zero,
    );
    const target = LatLng(33, 45);

    await controller.update(
      current: const LatLng(33, 44),
      target: target,
      accuracyMeters: 5,
    );
    expect(service.calls, 1);

    await controller.update(
      current: const LatLng(33.010, 44.20),
      target: target,
      accuracyMeters: 5,
    );
    await controller.update(
      current: const LatLng(33.011, 44.21),
      target: target,
      accuracyMeters: 5,
    );
    expect(service.calls, 1);

    await controller.update(
      current: const LatLng(33.012, 44.22),
      target: target,
      accuracyMeters: 5,
    );
    expect(service.calls, 2);
    expect(controller.lastRefreshReason, RouteRefreshReason.deviated);
    controller.dispose();
  });

  test('ETA يضيف أثر ساعة الذروة ويعرض مجال ثقة', () {
    const route = RoadRoute(
      points: [LatLng(33, 44), LatLng(33, 45)],
      distanceMeters: 12000,
      durationSeconds: 1200,
    );
    final normal = TravelTimeEstimator.estimate(
      route: route,
      localDeparture: DateTime(2026, 7, 23, 11),
    );
    final peak = TravelTimeEstimator.estimate(
      route: route,
      localDeparture: DateTime(2026, 7, 23, 16),
    );

    expect(peak.expected, greaterThan(normal.expected));
    expect(peak.minimum, lessThan(peak.expected));
    expect(peak.maximum, greaterThan(peak.expected));
  });
}
