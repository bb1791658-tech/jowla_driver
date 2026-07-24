import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_paths.dart';
import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../domain/models/driver_wallet.dart';
import '../domain/wallet_repository.dart';

final walletRepositoryProvider = Provider<WalletRepository>(
  (ref) => BackendWalletRepository(ref.watch(apiClientProvider)),
);

class BackendWalletRepository implements WalletRepository {
  const BackendWalletRepository(this._client);

  final ApiClient _client;

  @override
  Future<DriverWallet> currentWallet() async {
    try {
      final response = await _client.dio.get<Map<String, dynamic>>(
        ApiPaths.driverWallet,
      );
      return DriverWallet.fromJson(response.data ?? const {});
    } catch (error) {
      throw ApiClient.mapError(error);
    }
  }
}
