import 'package:intl/intl.dart';

String formatMinutes(int? minutes) =>
    minutes == null ? 'وقت الوصول' : '${formatNumber(minutes)} دقيقة';

String formatDistance(double km) {
  if (km < 1) {
    return '${formatNumber((km * 1000).round())} متر';
  }
  final value = km >= 10 ? km.round().toString() : km.toStringAsFixed(1);
  return '${formatNumberText(value)} كيلومتر';
}

/// تنسيق المبلغ بالدينار العراقي بأرقام عربية.
String formatIqd(double? amount) {
  if (amount == null) return 'السعر';
  return formatNumberText(
    NumberFormat.decimalPattern('ar_IQ').format(amount.round()),
  );
}

String formatNumber(num value) =>
    formatNumberText(NumberFormat.decimalPattern('ar_IQ').format(value));

String formatNumberText(String value) {
  const western = '0123456789.,';
  const eastern = '٠١٢٣٤٥٦٧٨٩٫٬';
  return value.split('').map((char) {
    final index = western.indexOf(char);
    return index == -1 ? char : eastern[index];
  }).join();
}
