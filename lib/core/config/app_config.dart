import 'package:flutter/foundation.dart';

/// إعدادات التطبيق. جميع العقود مأخوذة حرفيًا من jowla_backend:
/// - البادئة العامة: api + إصدار URI v1 (src/main.ts).
/// - فحص الصحة: GET /api/health يرجع {status: 'ok'} (monitoring.controller.ts).
/// - Socket.IO: namespace ‏/realtime مع مسار socket.io الافتراضي
///   (websocket.gateway.ts: @WebSocketGateway({ namespace: '/realtime' })).
abstract final class AppConfig {
  /// حساب واجهة محلي محصور في نسخ Debug. لا يدخل في أي نسخة Release.
  static const devWhatsappPhone = String.fromEnvironment(
    'DEV_WHATSAPP_PHONE',
    defaultValue: '+9647700000000',
  );
  static const devOtpCode = String.fromEnvironment(
    'DEV_OTP_CODE',
    defaultValue: '123456',
  );
  static const enableLocalDevAuth = bool.fromEnvironment(
    'ENABLE_LOCAL_DEV_AUTH',
    defaultValue: false,
  );
  static const devDriverId = 'debug-driver';

  static String get backendOrigin {
    const configured = String.fromEnvironment('BACKEND_ORIGIN');
    if (configured.isNotEmpty) return configured;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:3000';
    }
    return 'http://localhost:3000';
  }

  static String get apiBaseUrl {
    const configured = String.fromEnvironment('API_BASE_URL');
    return configured.isEmpty ? '$backendOrigin/api/v1' : configured;
  }

  static String get realtimeUrl => '$backendOrigin/realtime';
  static String get healthUrl => '$backendOrigin/api/health';

  static const mapTileUrlTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  static const roadRouteBaseUrl = String.fromEnvironment(
    'ROAD_ROUTE_BASE_URL',
    defaultValue: 'https://router.project-osrm.org',
  );

  /// موقع تطوير ثابت داخل الجبايش لتجاوز قيود GPS في المحاكي فقط عند تفعيله
  /// صراحة عبر dart-define. يبقى معطلاً افتراضياً.
  static const enableDevFixedLocation = bool.fromEnvironment(
    'ENABLE_DEV_FIXED_LOCATION',
    defaultValue: false,
  );
  static final devFixedLatitude =
      double.tryParse(const String.fromEnvironment('DEV_FIXED_LATITUDE')) ??
      30.965209;
  static final devFixedLongitude =
      double.tryParse(const String.fromEnvironment('DEV_FIXED_LONGITUDE')) ??
      46.9938377;

  /// Backend يشترط أن يكون آخر موقع للسائق أحدث من
  /// driver_location_freshness_seconds (القيمة الافتراضية 120 ثانية في
  /// settings.service.ts) حتى يدخل في المطابقة. لا يفرض Backend معدل إرسال
  /// أدق من ذلك، لذلك نرسل عند التحرك (كل 10 أمتار) مع نبضة دورية كل 20
  /// ثانية لضمان البقاء ضمن نافذة الحداثة بهامش أمان واسع.
  static const locationHeartbeat = Duration(seconds: 20);
  static const locationDistanceFilterMeters = 10;
}
