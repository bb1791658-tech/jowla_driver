import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';

@pragma('vm:entry-point')
Future<void> jowlaDriverFirebaseBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: JowlaDriverFirebaseOptions.current);
  }
}

abstract interface class PushTokenSource {
  Stream<String> get tokenRefreshes;
  Stream<Map<String, dynamic>> get notificationOpens;

  Future<Map<String, dynamic>?> takeInitialOpen();
  Future<String?> requestToken();
  Future<void> dispose();
}

class DisabledPushTokenSource implements PushTokenSource {
  const DisabledPushTokenSource();

  @override
  Stream<String> get tokenRefreshes => const Stream.empty();

  @override
  Stream<Map<String, dynamic>> get notificationOpens => const Stream.empty();

  @override
  Future<Map<String, dynamic>?> takeInitialOpen() async => null;

  @override
  Future<String?> requestToken() async => null;

  @override
  Future<void> dispose() async {}
}

class FirebasePushTokenSource implements PushTokenSource {
  final _opens = StreamController<Map<String, dynamic>>.broadcast();
  StreamSubscription<RemoteMessage>? _openedSubscription;
  Future<void>? _initialization;
  Map<String, dynamic>? _initialOpen;

  @override
  Stream<String> get tokenRefreshes =>
      FirebaseMessaging.instance.onTokenRefresh;

  @override
  Stream<Map<String, dynamic>> get notificationOpens => _opens.stream;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: JowlaDriverFirebaseOptions.current);
    }
    FirebaseMessaging.onBackgroundMessage(jowlaDriverFirebaseBackgroundHandler);
    _openedSubscription ??= FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => _opens.add(Map<String, dynamic>.from(message.data)),
    );
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      _initialOpen = Map<String, dynamic>.from(initial.data);
    }
  }

  @override
  Future<Map<String, dynamic>?> takeInitialOpen() async {
    await initialize();
    final value = _initialOpen;
    _initialOpen = null;
    return value;
  }

  @override
  Future<String?> requestToken() async {
    await initialize();
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied ||
        settings.authorizationStatus == AuthorizationStatus.notDetermined) {
      return null;
    }
    return FirebaseMessaging.instance.getToken(
      vapidKey: kIsWeb ? AppConfig.firebaseWebVapidKey : null,
    );
  }

  @override
  Future<void> dispose() async {
    await _openedSubscription?.cancel();
    await _opens.close();
  }
}

abstract final class JowlaDriverFirebaseOptions {
  static FirebaseOptions get current => FirebaseOptions(
    apiKey: AppConfig.firebaseApiKey,
    appId: AppConfig.firebaseAppId,
    messagingSenderId: AppConfig.firebaseMessagingSenderId,
    projectId: AppConfig.firebaseProjectId,
    authDomain: AppConfig.firebaseAuthDomain,
    storageBucket: AppConfig.firebaseStorageBucket,
    iosBundleId: 'com.jowla.driver',
  );
}
