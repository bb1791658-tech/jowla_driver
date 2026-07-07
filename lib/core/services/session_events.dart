import 'dart:async';

/// بث انتهاء الجلسة عندما يفشل تجديد التوكن نهائيًا.
class SessionEvents {
  final _expiredController = StreamController<void>.broadcast();

  Stream<void> get expired => _expiredController.stream;

  void notifyExpired() => _expiredController.add(null);

  void dispose() => _expiredController.close();
}
