/// مسارات REST كما هي معرفة في jowla_backend (Swagger /docs):
/// auth.controller.ts + drivers.controller.ts + rides.controller.ts.
abstract final class ApiPaths {
  static const requestOtp = '/auth/otp/request';
  static const verifyOtp = '/auth/otp/verify';
  static const refreshToken = '/auth/refresh';
  static const currentSession = '/auth/sessions/current';

  static const driverProfile = '/drivers/me';

  static String driverLocation(String driverId) =>
      '/drivers/$driverId/location';

  static String driverAvailability(String driverId) =>
      '/drivers/$driverId/availability';

  static const driverOffers = '/rides/driver/offers';
  static const driverCurrentRide = '/rides/driver/current';

  static String ride(String rideId) => '/rides/$rideId';

  static String acceptOffer(String rideId, String offerId) =>
      '/rides/$rideId/offers/$offerId/accept';

  static String rejectOffer(String rideId, String offerId) =>
      '/rides/$rideId/offers/$offerId/reject';

  static String driverArrived(String rideId) => '/rides/$rideId/driver-arrived';

  static String startRide(String rideId) => '/rides/$rideId/start';

  static String completeRide(String rideId) => '/rides/$rideId/complete';

  static String cancelRide(String rideId) => '/rides/$rideId/cancel';
}
