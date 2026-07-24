import '../../rides/domain/models/ride.dart';
import 'models/intercity_offer.dart';
import 'models/intercity_offer_draft.dart';

abstract interface class IntercityDriverRepository {
  Future<List<IntercityTripOffer>> offers();

  Future<IntercityTripOffer> offer(String offerId);

  Future<IntercityOfferPreview> preview(IntercityOfferDraft draft);

  Future<IntercityTripOffer> create({
    required IntercityOfferDraft draft,
    IntercityOfferPreview? preview,
    required String idempotencyKey,
  });

  Future<IntercityTripOffer> update({
    required String offerId,
    required IntercityOfferDraft draft,
    required IntercityOfferPreview preview,
    required int version,
  });

  Future<IntercityTripOffer> cancel(String offerId);

  Future<IntercityTripOffer> depart(String offerId);

  Future<IntercityTripOffer> complete(String offerId);

  Future<List<Ride>> scheduledFullVehicleRides();
}
