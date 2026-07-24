import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config/app_config.dart';
import '../errors/app_exception.dart';
import '../storage/session_store.dart';

class RealtimeEvent {
  const RealtimeEvent(this.name, this.payload);

  final String name;
  final Map<String, dynamic> payload;
}

/// واجهة قناة Socket.IO القابلة للاستبدال في الاختبارات.
abstract interface class RealtimeService {
  /// أحداث عروض الرحلات: ride:offer:new (websocket.gateway.emitRideOffer).
  Stream<Map<String, dynamic>> get offers;

  /// انتهاء العروض: ride:offer:expired بأسباب من Backend:
  /// server_timeout | accepted_by_other_driver | ride_cancelled | driver_rejected.
  Stream<Map<String, dynamic>> get offerExpirations;

  /// أحداث حالة الرحلة الموجهة لغرفة السائق.
  Stream<RealtimeEvent> get rideEvents;

  /// تحديثات عروض المقاعد. الحمولة إشارة فقط؛ REST يبقى مصدر الحقيقة.
  Stream<RealtimeEvent> get intercityEvents;

  /// رسائل الرحلة وحالات وإشارات المكالمة الموجهة للمستخدم الحالي.
  Stream<RealtimeEvent> get communicationEvents;

  /// تحديثات ملف السائق التي يرسلها الأدمن أو الخادم.
  Stream<Map<String, dynamic>> get driverUpdates;

  /// يبث عند كل اتصال ناجح (يشمل إعادة الاتصال) لإعادة المزامنة عبر REST.
  Stream<void> get connections;

  bool get isConnected;

  Future<void> connect();

  /// إرسال الموقع عبر حدث driver:location:update
  /// بالحمولة {lat, lng, heading?, speed?} (UpdateDriverLocationDto).
  void sendLocation({
    required double lat,
    required double lng,
    double? heading,
    double? speed,
  });

  void sendCallSignal({
    required String callId,
    required String kind,
    required Map<String, dynamic> payload,
  });

  void disconnect();

  void dispose();
}

class SocketRealtimeService implements RealtimeService {
  SocketRealtimeService(this._sessionStore);

  /// أحداث حالة الرحلة كما يبثها websocket.gateway.ts لغرفة السائق.
  static const rideEventNames = <String>[
    'ride:status:changed',
    'ride:driver:arrived',
    'ride:started',
    'ride:paused',
    'ride:resumed',
    'ride:completed',
    'ride:cancelled',
  ];

  static const intercityEventNames = <String>[
    'intercity:offer:created',
    'intercity:offer:updated',
    'intercity:offer:removed',
    'intercity:offer:full',
    'intercity:booking:updated',
    'intercity:booking:cancelled',
  ];

  final SessionStore _sessionStore;
  final _offers = StreamController<Map<String, dynamic>>.broadcast();
  final _offerExpirations = StreamController<Map<String, dynamic>>.broadcast();
  final _rideEvents = StreamController<RealtimeEvent>.broadcast();
  final _intercityEvents = StreamController<RealtimeEvent>.broadcast();
  final _communicationEvents = StreamController<RealtimeEvent>.broadcast();
  final _driverUpdates = StreamController<Map<String, dynamic>>.broadcast();
  final _connections = StreamController<void>.broadcast();
  io.Socket? _socket;

  @override
  Stream<Map<String, dynamic>> get offers => _offers.stream;

  @override
  Stream<Map<String, dynamic>> get offerExpirations => _offerExpirations.stream;

  @override
  Stream<RealtimeEvent> get rideEvents => _rideEvents.stream;

  @override
  Stream<RealtimeEvent> get intercityEvents => _intercityEvents.stream;

  @override
  Stream<RealtimeEvent> get communicationEvents => _communicationEvents.stream;

  @override
  Stream<Map<String, dynamic>> get driverUpdates => _driverUpdates.stream;

  @override
  Stream<void> get connections => _connections.stream;

  @override
  bool get isConnected => _socket?.connected ?? false;

  @override
  Future<void> connect() async {
    if (_socket?.connected ?? false) return;
    disconnect();
    final token = await _sessionStore.readAccessToken();
    if (token == null || token.isEmpty) {
      throw const AppException('لا توجد جلسة صالحة للاتصال بخدمة الرحلات.');
    }

    // socket-auth.service.ts يقرأ التوكن من handshake.auth.token
    // أو من ترويسة Authorization: Bearer.
    final socket = io.io(
      AppConfig.realtimeUrl,
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .disableAutoConnect()
          .enableReconnection()
          .setAuth({'token': token})
          .setExtraHeaders({'Authorization': 'Bearer $token'})
          .build(),
    );
    socket.on('ride:offer:new', (data) => _offers.add(_asMap(data)));
    socket.on(
      'ride:offer:expired',
      (data) => _offerExpirations.add(_asMap(data)),
    );
    socket.on('driver:updated', (data) => _driverUpdates.add(_asMap(data)));
    for (final eventName in rideEventNames) {
      socket.on(eventName, (data) {
        _rideEvents.add(RealtimeEvent(eventName, _asMap(data)));
      });
    }
    for (final eventName in intercityEventNames) {
      socket.on(eventName, (data) {
        _intercityEvents.add(RealtimeEvent(eventName, _asMap(data)));
      });
    }
    for (final eventName in const [
      'chat:message:new',
      'call:incoming',
      'call:state',
      'call:signal',
    ]) {
      socket.on(eventName, (data) {
        _communicationEvents.add(RealtimeEvent(eventName, _asMap(data)));
      });
    }
    final connection = Completer<void>();
    var connectionAnnounced = false;
    void announceConnection() {
      if (connectionAnnounced) return;
      connectionAnnounced = true;
      _connections.add(null);
      if (!connection.isCompleted) connection.complete();
    }

    socket.on('connected', (_) => announceConnection());
    socket.onConnect((_) {
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        // بعض بيئات Socket.IO لا ترسل حدث connected المخصص. هذا بديل
        // مؤجل، مع منع بث اتصالين وما يسببه من طلبات REST مكررة.
        if (socket.connected) announceConnection();
      });
    });
    socket.onDisconnect((_) => connectionAnnounced = false);
    socket.onConnectError((error) {
      if (!connection.isCompleted) {
        connection.completeError(
          AppException(
            'تعذر الاتصال بخدمة الرحلات. '
            '${AppConfig.backendConnectionHint} التفاصيل: $error',
          ),
        );
      }
    });
    _socket = socket..connect();
    try {
      await connection.future.timeout(const Duration(seconds: 12));
    } catch (_) {
      disconnect();
      rethrow;
    }
  }

  @override
  void sendLocation({
    required double lat,
    required double lng,
    double? heading,
    double? speed,
  }) {
    final socket = _socket;
    if (socket == null || !socket.connected) return;
    socket.emit('driver:location:update', {
      'lat': lat,
      'lng': lng,
      'heading': ?heading,
      'speed': ?speed,
    });
  }

  @override
  void sendCallSignal({
    required String callId,
    required String kind,
    required Map<String, dynamic> payload,
  }) {
    _socket?.emit('call:signal', {
      'callId': callId,
      'kind': kind,
      'payload': payload,
    });
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return const {};
  }

  @override
  void disconnect() {
    _socket?.dispose();
    _socket = null;
  }

  @override
  void dispose() {
    disconnect();
    _offers.close();
    _offerExpirations.close();
    _rideEvents.close();
    _intercityEvents.close();
    _communicationEvents.close();
    _driverUpdates.close();
    _connections.close();
  }
}
