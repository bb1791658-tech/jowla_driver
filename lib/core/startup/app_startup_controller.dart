import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

/// بوابة الإقلاع: لا يعمل التطبيق قبل نجاح GET /api/health.
final appStartupControllerProvider =
    AsyncNotifierProvider<AppStartupController, void>(AppStartupController.new);

class AppStartupController extends AsyncNotifier<void>
    with WidgetsBindingObserver {
  static const _healthyMinimumInterval = Duration(seconds: 90);
  static const _healthyJitterSeconds = 60;
  static const _unavailableRetryInterval = Duration(seconds: 6);

  StreamSubscription<void>? _availabilitySubscription;
  Timer? _probeTimer;
  Future<void>? _activeProbe;
  var _isDisposed = false;

  @override
  Future<void> build() async {
    WidgetsBinding.instance.addObserver(this);
    _availabilitySubscription = ref
        .read(backendAvailabilityEventsProvider)
        .unavailable
        .listen((_) => unawaited(_probe()));
    ref.onDispose(() {
      _isDisposed = true;
      _probeTimer?.cancel();
      _availabilitySubscription?.cancel();
      WidgetsBinding.instance.removeObserver(this);
    });

    try {
      await ref.read(backendHealthServiceProvider).checkHealth();
      _scheduleHealthyProbe();
    } catch (_) {
      _scheduleUnavailableProbe();
      rethrow;
    }
  }

  Future<void> retry() async {
    state = const AsyncLoading();
    await _probe();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_probe());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _probeTimer?.cancel();
    }
  }

  Future<void> _probe() async {
    final active = _activeProbe;
    if (active != null) return active;
    _probeTimer?.cancel();
    final probe = _performProbe();
    _activeProbe = probe;
    try {
      await probe;
    } finally {
      if (identical(_activeProbe, probe)) _activeProbe = null;
    }
  }

  Future<void> _performProbe() async {
    try {
      await ref.read(backendHealthServiceProvider).checkHealth();
      if (_isDisposed) return;
      state = const AsyncData(null);
      _scheduleHealthyProbe();
    } catch (error, stackTrace) {
      if (_isDisposed) return;
      state = AsyncError(error, stackTrace);
      _scheduleUnavailableProbe();
    }
  }

  void _scheduleHealthyProbe() {
    if (_isDisposed) return;
    final jitter = Random.secure().nextInt(_healthyJitterSeconds + 1);
    _schedule(_healthyMinimumInterval + Duration(seconds: jitter));
  }

  void _scheduleUnavailableProbe() => _schedule(_unavailableRetryInterval);

  void _schedule(Duration delay) {
    _probeTimer?.cancel();
    _probeTimer = Timer(delay, () => unawaited(_probe()));
  }
}
