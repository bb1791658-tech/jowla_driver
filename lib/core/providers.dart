import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'network/api_client.dart';
import 'services/backend_health_service.dart';
import 'services/location_service.dart';
import 'services/realtime_service.dart';
import 'services/session_events.dart';
import 'storage/session_store.dart';

final secureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  ),
);

final sessionStoreProvider = Provider<SessionStore>(
  (ref) => SessionStore(
    FlutterSecureKeyValueStore(ref.watch(secureStorageProvider)),
  ),
);

final sessionEventsProvider = Provider<SessionEvents>((ref) {
  final events = SessionEvents();
  ref.onDispose(events.dispose);
  return events;
});

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    ref.watch(sessionStoreProvider),
    ref.watch(sessionEventsProvider),
  ),
);

final backendHealthServiceProvider = Provider<BackendHealthService>(
  (ref) => BackendHealthService(),
);

final locationServiceProvider = Provider<LocationService>(
  (ref) => const LocationService(),
);

final realtimeServiceProvider = Provider<RealtimeService>((ref) {
  final service = SocketRealtimeService(ref.watch(sessionStoreProvider));
  ref.onDispose(service.dispose);
  return service;
});
