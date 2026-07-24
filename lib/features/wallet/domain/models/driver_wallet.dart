import '../../../rides/domain/models/ride.dart';

class DriverWallet {
  const DriverWallet({
    required this.balance,
    this.currency = 'IQD',
    this.updatedAt,
  });

  factory DriverWallet.fromJson(Map<String, dynamic> json) {
    final balance =
        asDouble(json['balance']) ??
        asDouble(json['currentBalance']) ??
        asDouble(json['availableBalance']) ??
        asDouble(json['amount']);
    if (balance == null) {
      throw const FormatException('استجابة رصيد السائق غير مكتملة');
    }
    return DriverWallet(
      balance: balance,
      currency: json['currency']?.toString() ?? 'IQD',
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }

  final double balance;
  final String currency;
  final DateTime? updatedAt;
}
