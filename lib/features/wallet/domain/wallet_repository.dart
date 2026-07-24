import 'models/driver_wallet.dart';

abstract interface class WalletRepository {
  /// GET /drivers/me/wallet — الرصيد الحالي كما يحسبه الباك اند.
  Future<DriverWallet> currentWallet();
}
