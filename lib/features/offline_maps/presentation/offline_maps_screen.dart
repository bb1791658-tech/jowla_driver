import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre/maplibre.dart' as ml;

import '../../../core/providers.dart';
import '../data/offline_map_service.dart';
import '../domain/offline_governorate.dart';

class OfflineMapsScreen extends ConsumerStatefulWidget {
  const OfflineMapsScreen({super.key});

  @override
  ConsumerState<OfflineMapsScreen> createState() => _OfflineMapsScreenState();
}

class _OfflineMapsScreenState extends ConsumerState<OfflineMapsScreen> {
  static const _wifiOnlyKey = 'offline_maps_wifi_only';

  final _installed = <String, OfflineMapInstall>{};
  final _storedBytes = <String, int>{};
  String? _downloadingCode;
  ml.DownloadProgress? _progress;
  bool _wifiOnly = true;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final storage = ref.read(secureStorageProvider);
    final wifiValue = await storage.read(key: _wifiOnlyKey);
    final installs = await ref.read(offlineMapServiceProvider).installed();
    final bytes = <String, int>{};
    for (final area in OfflineGovernorate.all) {
      bytes[area.code] =
          int.tryParse(
            await storage.read(key: 'offline_map_bytes_${area.code}') ?? '',
          ) ??
          0;
    }
    if (!mounted) return;
    setState(() {
      _wifiOnly = wifiValue != 'false';
      _installed
        ..clear()
        ..addEntries(
          installs.map((item) => MapEntry(item.governorateCode, item)),
        );
      _storedBytes
        ..clear()
        ..addAll(bytes);
      _loading = false;
    });
  }

  Future<void> _setWifiOnly(bool value) async {
    setState(() => _wifiOnly = value);
    await ref
        .read(secureStorageProvider)
        .write(key: _wifiOnlyKey, value: value.toString());
  }

  Future<void> _download(OfflineGovernorate area) async {
    final otherStoredBytes = _storedBytes.entries
        .where((entry) => entry.key != area.code)
        .fold<int>(0, (sum, entry) => sum + entry.value);
    if (otherStoredBytes + area.estimatedDownloadBytes >
        OfflineMapService.maxStoredBytes) {
      setState(() {
        _error =
            'لا توجد مساحة ضمن حد الخرائط البالغ 1.5 غ.ب. '
            'احذف محافظة منزّلة ثم حاول مجددًا.';
      });
      return;
    }
    setState(() {
      _downloadingCode = area.code;
      _progress = null;
      _error = null;
    });
    try {
      await for (final progress
          in ref
              .read(offlineMapServiceProvider)
              .download(area, wifiOnly: _wifiOnly)) {
        if (!mounted) return;
        setState(() => _progress = progress);
        if (progress.downloadCompleted) {
          await ref
              .read(secureStorageProvider)
              .write(
                key: 'offline_map_bytes_${area.code}',
                value: progress.loadedBytes.toString(),
              );
        }
      }
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) {
        setState(() {
          _downloadingCode = null;
          _progress = null;
        });
      }
    }
  }

  Future<void> _delete(OfflineGovernorate area) async {
    final install = _installed[area.code];
    if (install == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('حذف خريطة ${area.arabicName}؟'),
        content: const Text(
          'سيبقى عرض الخريطة عبر الشبكة متاحًا، ويمكن تنزيل المحافظة مجددًا.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(offlineMapServiceProvider).delete(install);
    await ref
        .read(secureStorageProvider)
        .delete(key: 'offline_map_bytes_${area.code}');
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(offlineMapServiceProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('خرائط دون اتصال')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                if (!service.isSupported)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Text(
                        'التنزيل دون اتصال متاح على هواتف Android وiPhone.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else ...[
                  Card(
                    child: SwitchListTile(
                      value: _wifiOnly,
                      onChanged: _downloadingCode == null ? _setWifiOnly : null,
                      secondary: const Icon(Icons.wifi_rounded),
                      title: const Text('التنزيل عبر Wi-Fi فقط'),
                      subtitle: const Text(
                        'موصى به لتقليل استهلاك بيانات الهاتف.',
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'اختر المحافظة',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'الحد الإجمالي 1.5 غ.ب، والحجم المعروض قبل التنزيل تقديري.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (_error != null)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(_error!),
                      ),
                    ),
                  for (final area in OfflineGovernorate.all)
                    _OfflineAreaCard(
                      area: area,
                      install: _installed[area.code],
                      storedBytes: _storedBytes[area.code] ?? 0,
                      isDownloading: _downloadingCode == area.code,
                      progress: _downloadingCode == area.code
                          ? _progress
                          : null,
                      disabled:
                          _downloadingCode != null &&
                          _downloadingCode != area.code,
                      onDownload: () => _download(area),
                      onDelete: () => _delete(area),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _downloadingCode == null
                        ? () async {
                            await service.clearCache();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'تم تنظيف ذاكرة الخريطة المؤقتة.',
                                  ),
                                ),
                              );
                            }
                          }
                        : null,
                    icon: const Icon(Icons.cleaning_services_outlined),
                    label: const Text('تنظيف الذاكرة المؤقتة'),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 14),
                    child: Text(
                      'الخرائط نهارية ومحصورة بالعراق. '
                      '© OpenStreetMap • Geofabrik • VersaTiles',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _OfflineAreaCard extends StatelessWidget {
  const _OfflineAreaCard({
    required this.area,
    required this.install,
    required this.storedBytes,
    required this.isDownloading,
    required this.progress,
    required this.disabled,
    required this.onDownload,
    required this.onDelete,
  });

  final OfflineGovernorate area;
  final OfflineMapInstall? install;
  final int storedBytes;
  final bool isDownloading;
  final ml.DownloadProgress? progress;
  final bool disabled;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final installed = install != null;
    final updateAvailable = install?.updateAvailable ?? false;
    final loaded = progress?.loadedBytes ?? storedBytes;
    final totalTiles = progress?.totalTiles ?? 0;
    final loadedTiles = progress?.loadedTiles ?? 0;
    final ratio = totalTiles <= 0
        ? null
        : (loadedTiles / totalTiles).clamp(0.0, 1.0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  installed ? Icons.offline_pin_rounded : Icons.map_outlined,
                  color: installed
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        area.arabicName,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        isDownloading
                            ? 'جار التنزيل • ${_formatBytes(loaded)}'
                            : updateAvailable
                            ? 'يتوفر تحديث جديد'
                            : installed
                            ? 'متاحة دون اتصال • ${_formatBytes(storedBytes)}'
                            : 'غير منزّلة • تقديريًا ${_formatBytes(area.estimatedDownloadBytes)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (installed && !isDownloading)
                  IconButton(
                    tooltip: 'حذف',
                    onPressed: disabled ? null : onDelete,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                FilledButton.tonal(
                  onPressed: disabled || isDownloading ? null : onDownload,
                  child: Text(
                    updateAvailable
                        ? 'تحديث'
                        : installed
                        ? 'إعادة تنزيل'
                        : 'تنزيل',
                  ),
                ),
              ],
            ),
            if (isDownloading) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(value: ratio),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return 'الحجم يُحسب عند التنزيل';
  final megabytes = bytes / (1024 * 1024);
  if (megabytes < 1024) return '${megabytes.toStringAsFixed(1)} م.ب';
  return '${(megabytes / 1024).toStringAsFixed(2)} غ.ب';
}

String _friendlyError(Object error) {
  final text = error.toString();
  if (text.contains('Wi-Fi')) return 'اتصل بشبكة Wi-Fi ثم حاول مجددًا.';
  return 'تعذر تنزيل الخريطة. تحقق من الاتصال وخادم الخرائط ثم حاول مجددًا.';
}
