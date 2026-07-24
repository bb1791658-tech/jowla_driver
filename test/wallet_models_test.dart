import 'package:flutter_test/flutter_test.dart';
import 'package:jowla_driver/features/wallet/domain/models/driver_wallet.dart';

void main() {
  test('DriverWallet يفك رصيد السائق من الباك اند', () {
    final wallet = DriverWallet.fromJson({
      'balance': '12500.00',
      'currency': 'IQD',
      'updatedAt': '2026-07-09T10:00:00.000Z',
    });

    expect(wallet.balance, 12500);
    expect(wallet.currency, 'IQD');
    expect(wallet.updatedAt, isNotNull);
  });

  test('DriverWallet يقبل أسماء حقول بديلة للرصيد', () {
    expect(DriverWallet.fromJson({'currentBalance': 7000}).balance, 7000);
    expect(DriverWallet.fromJson({'availableBalance': '8000'}).balance, 8000);
  });
}
