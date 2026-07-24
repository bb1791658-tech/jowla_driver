import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// إعدادات التطبيق. جميع العقود مأخوذة حرفيًا من jowla_backend:
/// - البادئة العامة: api + إصدار URI v1 (src/main.ts).
/// - فحص الصحة: GET /api/health يرجع {status: 'ok'} (monitoring.controller.ts).
/// - Socket.IO: namespace ‏/realtime مع مسار socket.io الافتراضي
///   (websocket.gateway.ts: @WebSocketGateway({ namespace: '/realtime' })).
abstract final class AppConfig {
  static var _developmentConfig = const <String, String>{};
  static String? _resolvedBackendOrigin;

  static Future<void> initialize() async {
    if (kReleaseMode) return;
    try {
      final rawConfig = await rootBundle.loadString('config/development.json');
      final decoded = jsonDecode(rawConfig);
      if (decoded is! Map) return;
      _developmentConfig = decoded.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    } catch (_) {
      _developmentConfig = const {};
    }
  }

  static List<String> get backendOriginCandidates {
    const configured = String.fromEnvironment('BACKEND_ORIGIN');
    if (configured.isNotEmpty) return [_normalizeOrigin(configured)];

    final development = _developmentConfig['BACKEND_ORIGIN'];
    if (development != null && development.isNotEmpty) {
      return [_normalizeOrigin(development)];
    }

    const configuredOrigins = String.fromEnvironment('BACKEND_ORIGINS');
    final developmentOrigins = _developmentConfig['BACKEND_ORIGINS'];
    final origins = configuredOrigins.isEmpty
        ? developmentOrigins
        : configuredOrigins;
    final parsedOrigins = _splitOrigins(origins);
    if (parsedOrigins.isNotEmpty) return parsedOrigins;

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return const ['http://10.0.2.2:3000', 'http://localhost:3000'];
    }
    return const ['http://localhost:3000'];
  }

  static String get backendOrigin {
    return _resolvedBackendOrigin ?? backendOriginCandidates.first;
  }

  static String get apiBaseUrl {
    const configured = String.fromEnvironment('API_BASE_URL');
    return configured.isEmpty ? '$backendOrigin/api/v1' : configured;
  }

  static String get realtimeUrl => '$backendOrigin/realtime';
  static String get healthUrl => '$backendOrigin/api/health';
  static String healthUrlForOrigin(String origin) =>
      '${_normalizeOrigin(origin)}/api/health';
  static void useBackendOrigin(String origin) =>
      _resolvedBackendOrigin = _normalizeOrigin(origin);
  @visibleForTesting
  static void resetResolvedBackendOrigin() => _resolvedBackendOrigin = null;
  static String get backendConnectionHint =>
      'العنوان المستخدم: $backendOrigin. إذا كان التطبيق على هاتف حقيقي '
      'فتأكد أن الهاتف والحاسوب على نفس الشبكة واستخدم عنوان الحاسوب داخل '
      'الشبكة المحلية.';

  static String get mapOrigin {
    const configured = String.fromEnvironment('MAP_ORIGIN');
    if (configured.isNotEmpty) return _normalizeOrigin(configured);

    final development = _developmentConfig['MAP_ORIGIN'];
    if (development != null && development.isNotEmpty) {
      return _normalizeOrigin(development);
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8080';
    }
    return 'http://localhost:8080';
  }

  static String get mapTileUrlTemplate =>
      '$mapOrigin/styles/day/{z}/{x}/{y}.png';

  /// نمط MapLibre المتجهي النهاري. لا يستخدم التطبيق نمطًا ليليًا.
  static String get mapStyleUrl => '$mapOrigin/styles/day/style.json';

  static String get mapDataVersion {
    const configured = String.fromEnvironment('MAP_DATA_VERSION');
    if (configured.isNotEmpty) return configured;
    return _developmentConfig['MAP_DATA_VERSION'] ?? 'iraq-shortbread-v1';
  }

  static String get roadRouteBaseUrl {
    const configured = String.fromEnvironment('ROAD_ROUTE_BASE_URL');
    if (configured.isNotEmpty) return _normalizeOrigin(configured);

    final development = _developmentConfig['ROAD_ROUTE_BASE_URL'];
    if (development != null && development.isNotEmpty) {
      return _normalizeOrigin(development);
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:5001';
    }
    return 'http://localhost:5001';
  }

  static String get geocodingBaseUrl {
    const configured = String.fromEnvironment('GEOCODING_BASE_URL');
    if (configured.isNotEmpty) return _normalizeOrigin(configured);

    final development = _developmentConfig['GEOCODING_BASE_URL'];
    if (development != null && development.isNotEmpty) {
      return _normalizeOrigin(development);
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:7070';
    }
    return 'http://localhost:7070';
  }

  static bool get pushNotificationsEnabled => _boolConfig(
    const String.fromEnvironment('PUSH_NOTIFICATIONS_ENABLED'),
    'PUSH_NOTIFICATIONS_ENABLED',
  );

  static String get firebaseApiKey => _configValue(
    const String.fromEnvironment('FIREBASE_API_KEY'),
    'FIREBASE_API_KEY',
  );

  static String get firebaseAppId => _configValue(
    const String.fromEnvironment('FIREBASE_APP_ID'),
    'FIREBASE_APP_ID',
  );

  static String get firebaseMessagingSenderId => _configValue(
    const String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
    'FIREBASE_MESSAGING_SENDER_ID',
  );

  static String get firebaseProjectId => _configValue(
    const String.fromEnvironment('FIREBASE_PROJECT_ID'),
    'FIREBASE_PROJECT_ID',
  );

  static String? get firebaseAuthDomain => _optionalConfigValue(
    const String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
    'FIREBASE_AUTH_DOMAIN',
  );

  static String? get firebaseStorageBucket => _optionalConfigValue(
    const String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
    'FIREBASE_STORAGE_BUCKET',
  );

  static String? get firebaseWebVapidKey => _optionalConfigValue(
    const String.fromEnvironment('FIREBASE_WEB_VAPID_KEY'),
    'FIREBASE_WEB_VAPID_KEY',
  );

  /// Backend يشترط أن يكون آخر موقع للسائق أحدث من
  /// driver_location_freshness_seconds (القيمة الافتراضية 120 ثانية في
  /// settings.service.ts) حتى يدخل في المطابقة. لا يفرض Backend معدل إرسال
  /// أدق من ذلك، لذلك نرسل عند التحرك (كل 10 أمتار) مع نبضة دورية كل 20
  /// ثانية لضمان البقاء ضمن نافذة الحداثة بهامش أمان واسع.
  static const locationHeartbeat = Duration(seconds: 20);
  static const locationDistanceFilterMeters = 10;

  static void validateProduction() {
    if (!kReleaseMode) return;
    const backend = String.fromEnvironment('BACKEND_ORIGIN');
    const mapOrigin = String.fromEnvironment('MAP_ORIGIN');
    const geocoding = String.fromEnvironment('GEOCODING_BASE_URL');
    const routeService = String.fromEnvironment('ROAD_ROUTE_BASE_URL');
    final missing = <String>[
      if (backend.isEmpty) 'BACKEND_ORIGIN',
      if (mapOrigin.isEmpty) 'MAP_ORIGIN',
      if (geocoding.isEmpty) 'GEOCODING_BASE_URL',
      if (routeService.isEmpty) 'ROAD_ROUTE_BASE_URL',
      if (const bool.fromEnvironment('PUSH_NOTIFICATIONS_ENABLED')) ...<String>[
        if (const String.fromEnvironment('FIREBASE_API_KEY').isEmpty)
          'FIREBASE_API_KEY',
        if (const String.fromEnvironment('FIREBASE_APP_ID').isEmpty)
          'FIREBASE_APP_ID',
        if (const String.fromEnvironment(
          'FIREBASE_MESSAGING_SENDER_ID',
        ).isEmpty)
          'FIREBASE_MESSAGING_SENDER_ID',
        if (const String.fromEnvironment('FIREBASE_PROJECT_ID').isEmpty)
          'FIREBASE_PROJECT_ID',
      ],
    ];
    if (missing.isNotEmpty) {
      throw StateError(
        'Missing production configuration: ${missing.join(', ')}',
      );
    }
    for (final entry in <String, String>{
      'BACKEND_ORIGIN': backend,
      'MAP_ORIGIN': mapOrigin,
      'GEOCODING_BASE_URL': geocoding,
      'ROAD_ROUTE_BASE_URL': routeService,
    }.entries) {
      if (!entry.value.startsWith('https://')) {
        throw StateError('${entry.key} must use HTTPS in production.');
      }
    }
  }

  static bool _boolConfig(String configured, String key) {
    final value = configured.isEmpty ? _developmentConfig[key] : configured;
    return value?.toLowerCase() == 'true';
  }

  static String _configValue(String configured, String key) =>
      configured.isEmpty ? _developmentConfig[key] ?? '' : configured;

  static String? _optionalConfigValue(String configured, String key) {
    final value = _configValue(configured, key).trim();
    return value.isEmpty ? null : value;
  }

  static List<String> _splitOrigins(String? origins) {
    final seen = <String>{};
    return (origins ?? '')
        .split(',')
        .map(_normalizeOrigin)
        .where((origin) => origin.isNotEmpty && seen.add(origin))
        .toList(growable: false);
  }

  static String _normalizeOrigin(String origin) {
    return origin.trim().replaceFirst(RegExp(r'/+$'), '');
  }
}
