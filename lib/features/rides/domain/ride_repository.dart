import 'models/ride.dart';
import 'models/ride_offer.dart';

abstract interface class RideRepository {
  /// GET /rides/driver/offers — العروض المعلقة غير المنتهية.
  Future<List<RideOffer>> pendingOffers();

  /// GET /rides/driver/current — الرحلة النشطة أو null.
  Future<Ride?> currentRide();

  /// GET /rides/{id}.
  Future<Ride> getRide(String rideId);

  /// POST /rides/{id}/offers/{offerId}/accept.
  Future<Ride> acceptOffer({required String rideId, required String offerId});

  /// POST /rides/{id}/offers/{offerId}/reject.
  Future<void> rejectOffer({required String rideId, required String offerId});

  /// POST /rides/{id}/driver-arrived.
  Future<Ride> driverArrived(String rideId);

  /// POST /rides/{id}/start.
  Future<Ride> startTrip(String rideId);

  /// POST /rides/{id}/complete — يرجع الرحلة مع payment
  /// (amount, commissionAmount) لعرض الملخص والعمولة والصافي.
  Future<Ride> completeTrip(String rideId);

  /// POST /rides/{id}/cancel.
  Future<Ride> cancelRide(String rideId);
}
