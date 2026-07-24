import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_paths.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../../rides/domain/models/ride.dart';
import '../domain/intercity_driver_repository.dart';
import '../domain/models/intercity_offer.dart';
import '../domain/models/intercity_offer_draft.dart';

final intercityDriverRepositoryProvider = Provider<IntercityDriverRepository>(
  (ref) => BackendIntercityDriverRepository(ref.watch(apiClientProvider)),
);

class BackendIntercityDriverRepository implements IntercityDriverRepository {
  const BackendIntercityDriverRepository(this._client);

  final ApiClient _client;

  @override
  Future<List<IntercityTripOffer>> offers() async {
    try {
      final response = await _client.dio.get<Map<String, dynamic>>(
        ApiPaths.intercityDriverOffers,
      );
      final json = response.data ?? const {};
      final data = json['data'];
      final values = data is List
          ? data
          : data is Map
          ? data['offers'] ?? data['items']
          : json['offers'] ?? json['items'];
      if (values is! List) return const [];
      return [
        for (final item in values.whereType<Map>())
          IntercityTripOffer.fromJson(Map<String, dynamic>.from(item)),
      ];
    } catch (error) {
      throw ApiClient.mapError(error);
    }
  }

  @override
  Future<IntercityTripOffer> offer(String offerId) =>
      _offerCall(() => _client.dio.get(ApiPaths.intercityDriverOffer(offerId)));

  @override
  Future<IntercityOfferPreview> preview(IntercityOfferDraft draft) async {
    try {
      final response = await _client.dio.post<Map<String, dynamic>>(
        ApiPaths.intercityDriverOfferPreview,
        data: draft.toJson(),
      );
      return IntercityOfferPreview.fromJson(response.data ?? const {});
    } on FormatException {
      throw const AppException('استجابة معاينة العرض غير مكتملة.');
    } catch (error) {
      throw ApiClient.mapError(error);
    }
  }

  @override
  Future<IntercityTripOffer> create({
    required IntercityOfferDraft draft,
    IntercityOfferPreview? preview,
    required String idempotencyKey,
  }) => _offerCall(
    () => _client.dio.post(
      ApiPaths.intercityDriverOffers,
      data: draft.toJson(
        previewId: preview?.id.isNotEmpty == true ? preview!.id : null,
      ),
      options: Options(headers: {'Idempotency-Key': idempotencyKey}),
    ),
  );

  @override
  Future<IntercityTripOffer> update({
    required String offerId,
    required IntercityOfferDraft draft,
    required IntercityOfferPreview preview,
    required int version,
  }) => _offerCall(
    () => _client.dio.patch(
      ApiPaths.intercityDriverOffer(offerId),
      data: {
        ...draft.toJson(previewId: preview.id),
        'version': version,
      },
    ),
  );

  @override
  Future<IntercityTripOffer> cancel(String offerId) => _offerCall(
    () => _client.dio.post(ApiPaths.cancelIntercityDriverOffer(offerId)),
  );

  @override
  Future<IntercityTripOffer> depart(String offerId) => _offerCall(
    () => _client.dio.post(ApiPaths.departIntercityDriverOffer(offerId)),
  );

  @override
  Future<IntercityTripOffer> complete(String offerId) => _offerCall(
    () => _client.dio.post(ApiPaths.completeIntercityDriverOffer(offerId)),
  );

  @override
  Future<List<Ride>> scheduledFullVehicleRides() async {
    try {
      final response = await _client.dio.get<dynamic>(
        ApiPaths.driverScheduledRides,
      );
      final json = response.data;
      final values = json is List
          ? json
          : json is Map
          ? json['data'] ?? json['rides'] ?? json['items']
          : null;
      if (values is! List) return const [];
      return [
        for (final item in values.whereType<Map>())
          Ride.fromJson(Map<String, dynamic>.from(item)),
      ];
    } catch (error) {
      throw ApiClient.mapError(error);
    }
  }

  Future<IntercityTripOffer> _offerCall(
    Future<Response<dynamic>> Function() request,
  ) async {
    try {
      final response = await request();
      if (response.data is! Map) {
        throw const AppException('استجابة عرض بين المحافظات غير مكتملة.');
      }
      return IntercityTripOffer.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on FormatException {
      throw const AppException('استجابة عرض بين المحافظات غير مكتملة.');
    } catch (error) {
      throw ApiClient.mapError(error);
    }
  }
}
