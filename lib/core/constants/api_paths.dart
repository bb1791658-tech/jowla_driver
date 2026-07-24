/// مسارات REST كما هي معرفة في jowla_backend (Swagger /docs):
/// auth.controller.ts + drivers.controller.ts + rides.controller.ts.
abstract final class ApiPaths {
  static const requestOtp = '/auth/otp/request';
  static const verifyOtp = '/auth/otp/verify';
  static const refreshToken = '/auth/refresh';
  static const currentSession = '/auth/sessions/current';
  static const currentPushToken = '/auth/devices/current/push-token';

  static const driverProfile = '/drivers/me';
  static const driverWallet = '/drivers/me/wallet';

  static String driverLocation(String driverId) =>
      '/drivers/$driverId/location';

  static String driverAvailability(String driverId) =>
      '/drivers/$driverId/availability';

  static String driverActiveService(String driverId) =>
      '/drivers/$driverId/active-service';

  static const driverOffers = '/rides/driver/offers';
  static const driverCurrentRide = '/rides/driver/current';
  static const driverScheduledRides = '/rides/driver/scheduled';
  static const smartMapZones = '/maps/smart-zones';

  static const intercityDriverOffers = '/intercity/driver/offers';
  static const intercityDriverOfferPreview = '/intercity/driver/offers/preview';

  static String intercityDriverOffer(String offerId) =>
      '/intercity/driver/offers/$offerId';

  static String cancelIntercityDriverOffer(String offerId) =>
      '/intercity/driver/offers/$offerId/cancel';

  static String departIntercityDriverOffer(String offerId) =>
      '/intercity/driver/offers/$offerId/depart';

  static String completeIntercityDriverOffer(String offerId) =>
      '/intercity/driver/offers/$offerId/complete';

  static String ride(String rideId) => '/rides/$rideId';

  static String acceptOffer(String rideId, String offerId) =>
      '/rides/$rideId/offers/$offerId/accept';

  static String rejectOffer(String rideId, String offerId) =>
      '/rides/$rideId/offers/$offerId/reject';

  static String driverArrived(String rideId) => '/rides/$rideId/driver-arrived';

  static String startRide(String rideId) => '/rides/$rideId/start';

  static String pauseRide(String rideId) => '/rides/$rideId/pause';

  static String resumeRide(String rideId) => '/rides/$rideId/resume';

  static String completeRide(String rideId) => '/rides/$rideId/complete';

  static String cancelRide(String rideId) => '/rides/$rideId/cancel';

  static String rideChatMessages(String rideId) =>
      '/rides/$rideId/chat/messages';

  static String rideChatRead(String rideId) => '/rides/$rideId/chat/read';

  static String rideCalls(String rideId) => '/rides/$rideId/calls';

  static String callStatus(String callId) => '/calls/$callId/status';

  static const callIceServers = '/calls/ice-servers';
}
