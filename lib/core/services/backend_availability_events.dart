import 'dart:async';

/// قناة داخلية خفيفة لإبلاغ بوابة التطبيق بفشل الوصول إلى الخادم.
///
/// لا تعتمد الواجهة على أخطاء كل شاشة على حدة؛ عند فشل اتصال شبكي فعلي
/// تطلب البوابة فحص الصحة، وتوقف التطبيق إذا لم يعد الخادم متاحًا.
class BackendAvailabilityEvents {
  final _unavailable = StreamController<void>.broadcast(sync: true);

  Stream<void> get unavailable => _unavailable.stream;

  void reportUnavailable() {
    if (!_unavailable.isClosed) _unavailable.add(null);
  }

  void dispose() => _unavailable.close();
}
