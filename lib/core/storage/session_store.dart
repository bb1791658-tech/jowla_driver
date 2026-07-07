import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../features/auth/domain/models/driver_session.dart';

/// واجهة تخزين مفاتيح آمنة قابلة للاستبدال في الاختبارات.
abstract interface class SecureKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  const FlutterSecureKeyValueStore(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class SessionStore {
  SessionStore(this._storage);

  static const _accessTokenKey = 'jowla_access_token';
  static const _refreshTokenKey = 'jowla_refresh_token';
  static const _driverProfileKey = 'jowla_driver_profile';
  static const _installationIdKey = 'jowla_installation_id';

  final SecureKeyValueStore _storage;

  Future<String?> readAccessToken() => _storage.read(_accessTokenKey);

  Future<String?> readRefreshToken() => _storage.read(_refreshTokenKey);

  Future<DriverSession?> readSession() async {
    final values = await Future.wait([
      _storage.read(_accessTokenKey),
      _storage.read(_refreshTokenKey),
      _storage.read(_driverProfileKey),
    ]);
    final accessToken = values[0];
    final refreshToken = values[1];
    final profileJson = values[2];
    if (accessToken == null ||
        accessToken.isEmpty ||
        refreshToken == null ||
        refreshToken.isEmpty ||
        profileJson == null ||
        profileJson.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(profileJson);
      if (decoded is! Map<String, dynamic>) return null;
      final driver = DriverProfile.fromJson(decoded);
      if (driver.id.isEmpty) return null;
      return DriverSession(
        accessToken: accessToken,
        refreshToken: refreshToken,
        driver: driver,
      );
    } on FormatException {
      return null;
    }
  }

  Future<void> saveSession(DriverSession session) {
    return Future.wait([
      _storage.write(_accessTokenKey, session.accessToken),
      _storage.write(_refreshTokenKey, session.refreshToken),
      _storage.write(_driverProfileKey, jsonEncode(session.driver.toJson())),
    ]);
  }

  Future<void> updateTokens({
    required String accessToken,
    required String refreshToken,
  }) {
    return Future.wait([
      _storage.write(_accessTokenKey, accessToken),
      _storage.write(_refreshTokenKey, refreshToken),
    ]);
  }

  /// deviceKey المطلوب في POST /auth/otp/verify (بين 8 و200 محرفًا).
  /// يبقى ثابتًا حتى بعد تسجيل الخروج ليُعرّف هذا التثبيت لدى الخادم.
  Future<String> getOrCreateInstallationId() async {
    final existing = await _storage.read(_installationIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final created = _uuidV4();
    await _storage.write(_installationIdKey, created);
    return created;
  }

  Future<void> clearSession() {
    return Future.wait([
      _storage.delete(_accessTokenKey),
      _storage.delete(_refreshTokenKey),
      _storage.delete(_driverProfileKey),
    ]);
  }

  String _uuidV4() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0'));
    final value = hex.join();
    return '${value.substring(0, 8)}-'
        '${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-'
        '${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }
}
