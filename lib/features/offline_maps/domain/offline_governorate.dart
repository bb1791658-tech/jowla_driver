import 'dart:math' as math;

import '../../intercity/domain/models/iraqi_governorate.dart';

class OfflineGovernorate {
  const OfflineGovernorate({
    required this.governorate,
    required this.west,
    required this.south,
    required this.east,
    required this.north,
  });

  final IraqiGovernorate governorate;
  final double west;
  final double south;
  final double east;
  final double north;

  String get code => governorate.code;
  String get arabicName => governorate.arabicName;

  /// تقدير محافظ قبل التنزيل؛ الحجم الفعلي يبقى معتمدًا على كثافة المباني
  /// والطرق في بيانات الإصدار الحالي ويُستبدل بالعدد الحقيقي بعد التنزيل.
  int get estimatedDownloadBytes {
    final midLatitude = (north + south) / 2 * math.pi / 180;
    final widthKm = (east - west).abs() * 111.32 * math.cos(midLatitude);
    final heightKm = (north - south).abs() * 110.57;
    final estimate = widthKm * heightKm * 2000;
    return estimate.round().clamp(25 * 1024 * 1024, 600 * 1024 * 1024);
  }

  static final all = IraqiGovernorate.values
      .map(_fromGovernorate)
      .toList(growable: false);

  static OfflineGovernorate byCode(String code) =>
      all.firstWhere((item) => item.code == code);

  static OfflineGovernorate _fromGovernorate(IraqiGovernorate governorate) {
    final bounds = switch (governorate) {
      IraqiGovernorate.anbar => (38.79, 30.95, 44.85, 35.25),
      IraqiGovernorate.erbil => (43.20, 35.45, 46.20, 37.38),
      IraqiGovernorate.basra => (46.35, 29.06, 48.58, 31.35),
      IraqiGovernorate.babylon => (43.45, 31.65, 45.35, 33.40),
      IraqiGovernorate.baghdad => (43.90, 32.85, 44.95, 33.75),
      IraqiGovernorate.halabja => (45.55, 34.95, 46.45, 35.85),
      IraqiGovernorate.duhok => (42.25, 36.35, 44.35, 37.38),
      IraqiGovernorate.diyala => (44.25, 32.95, 46.10, 35.20),
      IraqiGovernorate.dhiQar => (45.15, 30.25, 47.25, 32.10),
      IraqiGovernorate.sulaymaniyah => (44.45, 34.45, 46.75, 36.55),
      IraqiGovernorate.salahAlDin => (42.25, 33.45, 45.20, 35.80),
      IraqiGovernorate.qadisiyyah => (44.25, 30.85, 46.05, 32.65),
      IraqiGovernorate.karbala => (43.10, 31.65, 44.70, 33.15),
      IraqiGovernorate.kirkuk => (43.10, 34.45, 45.45, 36.10),
      IraqiGovernorate.maysan => (45.90, 30.95, 47.95, 33.05),
      IraqiGovernorate.muthanna => (43.65, 29.06, 47.45, 31.85),
      IraqiGovernorate.najaf => (42.75, 29.75, 45.85, 32.45),
      IraqiGovernorate.nineveh => (40.95, 34.75, 44.55, 37.38),
      IraqiGovernorate.wasit => (44.35, 31.35, 47.15, 33.75),
    };
    return OfflineGovernorate(
      governorate: governorate,
      west: bounds.$1,
      south: bounds.$2,
      east: bounds.$3,
      north: bounds.$4,
    );
  }
}
