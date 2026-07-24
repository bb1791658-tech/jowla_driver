import 'package:flutter_test/flutter_test.dart';
import 'package:jowla_driver/core/services/place_name_service.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('طلب البحث بلا موقع يبقى محصورًا داخل صندوق العراق', () {
    final request = PlaceSearchRequest.from(' بغداد ');

    expect(request.query, 'بغداد');
    expect(request.viewbox, '38.7936,37.3809,48.5759,29.0612');
  });

  test('تقريب موقع البحث يسمح بإعادة استخدام نتيجة الذاكرة المؤقتة', () {
    final first = PlaceSearchRequest.from(
      'الكرادة',
      near: const LatLng(33.3152, 44.3661),
    );
    final close = PlaceSearchRequest.from(
      'الكرادة',
      near: const LatLng(33.3169, 44.3680),
    );

    expect(first, close);
    expect(first.viewbox, isNot(contains('38.7936')));
  });
}
