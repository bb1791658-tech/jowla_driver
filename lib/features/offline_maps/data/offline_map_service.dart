import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre/maplibre.dart' as ml;

import '../../../core/config/app_config.dart';
import '../../../core/maps/runtime_environment.dart';
import '../domain/offline_governorate.dart';

final offlineMapServiceProvider = Provider<OfflineMapService>((ref) {
  final service = OfflineMapService();
  ref.onDispose(service.dispose);
  return service;
});

@immutable
class OfflineMapInstall {
  const OfflineMapInstall({
    required this.regionId,
    required this.governorateCode,
    required this.dataVersion,
  });

  final int regionId;
  final String governorateCode;
  final String dataVersion;

  bool get updateAvailable => dataVersion != AppConfig.mapDataVersion;
}

class OfflineMapService {
  static const maxStoredBytes = 1536 * 1024 * 1024;

  ml.OfflineManager? _manager;

  bool get isSupported =>
      !isFlutterTestEnvironment && ml.OfflineManager.isSupported;

  Future<List<OfflineMapInstall>> installed() async {
    if (!isSupported) return const [];
    final regions = await (await _getManager()).listOfflineRegions();
    return regions
        .map((region) {
          final code = region.metadata['jowla_governorate']?.toString();
          if (code == null || code.isEmpty) return null;
          return OfflineMapInstall(
            regionId: region.id,
            governorateCode: code,
            dataVersion:
                region.metadata['jowla_data_version']?.toString() ?? '',
          );
        })
        .whereType<OfflineMapInstall>()
        .toList(growable: false);
  }

  Stream<ml.DownloadProgress> download(
    OfflineGovernorate area, {
    required bool wifiOnly,
  }) async* {
    if (!isSupported) {
      throw UnsupportedError('التنزيل دون اتصال غير مدعوم على هذا الجهاز.');
    }
    if (wifiOnly) {
      final connectivity = await Connectivity().checkConnectivity();
      if (!connectivity.contains(ConnectivityResult.wifi) &&
          !connectivity.contains(ConnectivityResult.ethernet)) {
        throw StateError('اتصل بشبكة Wi-Fi لبدء تنزيل الخريطة.');
      }
    }

    final manager = await _getManager();
    final existing = await installed();
    for (final item in existing.where(
      (item) => item.governorateCode == area.code,
    )) {
      await manager.deleteRegion(regionId: item.regionId);
    }

    yield* manager.downloadRegion(
      mapStyleUrl: AppConfig.mapStyleUrl,
      bounds: ml.LngLatBounds(
        longitudeWest: area.west,
        longitudeEast: area.east,
        latitudeSouth: area.south,
        latitudeNorth: area.north,
      ),
      minZoom: 6,
      maxZoom: 14,
      pixelDensity: 1,
      metadata: {
        'jowla_governorate': area.code,
        'jowla_name_ar': area.arabicName,
        'jowla_data_version': AppConfig.mapDataVersion,
      },
    );
  }

  Future<void> delete(OfflineMapInstall install) async {
    if (!isSupported) return;
    await (await _getManager()).deleteRegion(regionId: install.regionId);
  }

  Future<void> clearCache() async {
    if (!isSupported) return;
    await (await _getManager()).clearAmbientCache();
  }

  Future<ml.OfflineManager> _getManager() async {
    final current = _manager;
    if (current != null) return current;
    final created = await ml.OfflineManager.createInstance();
    created.setOfflineTileCountLimit(amount: 250000);
    await created.setMaximumAmbientCacheSize(bytes: 200 * 1024 * 1024);
    _manager = created;
    return created;
  }

  void dispose() {
    _manager?.dispose();
    _manager = null;
  }
}
