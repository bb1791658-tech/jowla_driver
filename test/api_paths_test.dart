import 'package:flutter_test/flutter_test.dart';
import 'package:jowla_driver/core/constants/api_paths.dart';

void main() {
  test('المسارات تطابق عقود jowla_backend المنشورة في Swagger', () {
    expect(ApiPaths.requestOtp, '/auth/otp/request');
    expect(ApiPaths.verifyOtp, '/auth/otp/verify');
    expect(ApiPaths.refreshToken, '/auth/refresh');
    expect(ApiPaths.currentSession, '/auth/sessions/current');
    expect(ApiPaths.driverProfile, '/drivers/me');
    expect(ApiPaths.driverWallet, '/drivers/me/wallet');
    expect(ApiPaths.driverLocation('d1'), '/drivers/d1/location');
    expect(ApiPaths.driverAvailability('d1'), '/drivers/d1/availability');
    expect(ApiPaths.driverActiveService('d1'), '/drivers/d1/active-service');
    expect(ApiPaths.driverOffers, '/rides/driver/offers');
    expect(ApiPaths.driverCurrentRide, '/rides/driver/current');
    expect(ApiPaths.driverScheduledRides, '/rides/driver/scheduled');
    expect(ApiPaths.intercityDriverOffers, '/intercity/driver/offers');
    expect(ApiPaths.intercityDriverOffer('o1'), '/intercity/driver/offers/o1');
    expect(ApiPaths.ride('r1'), '/rides/r1');
    expect(ApiPaths.acceptOffer('r1', 'o1'), '/rides/r1/offers/o1/accept');
    expect(ApiPaths.rejectOffer('r1', 'o1'), '/rides/r1/offers/o1/reject');
    expect(ApiPaths.driverArrived('r1'), '/rides/r1/driver-arrived');
    expect(ApiPaths.startRide('r1'), '/rides/r1/start');
    expect(ApiPaths.pauseRide('r1'), '/rides/r1/pause');
    expect(ApiPaths.resumeRide('r1'), '/rides/r1/resume');
    expect(ApiPaths.completeRide('r1'), '/rides/r1/complete');
    expect(ApiPaths.cancelRide('r1'), '/rides/r1/cancel');
  });
}
