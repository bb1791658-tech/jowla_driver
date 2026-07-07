# تقرير المرحلة الأولى — تطبيق Jowla Driver

تاريخ التقرير: 3 يوليو 2026

## ملخص التنفيذ

تم تحويل مشروع Flutter الابتدائي إلى أساس منظم لتطبيق السائق باستخدام:

- Clean Architecture وFeature First.
- Riverpod لإدارة الحالة والاعتماديات.
- GoRouter للتنقل وحماية المسارات بحسب الجلسة.
- Dio للاتصال المركزي بالـ Backend.
- Flutter Secure Storage لحفظ رموز الجلسة.
- Flutter Map وOpenStreetMap لعرض الخريطة.
- Geolocator لقراءة موقع السائق الحقيقي وسرعته واتجاهه.
- Socket.IO للاستماع إلى طلبات الرحلات.
- واجهة عربية RTL بخط Cairo واللون الأساسي `#017833`.

لم يتم إنشاء Backend أو قاعدة بيانات محلية أو بيانات تجريبية.

## الملفات المنشأة

### التطبيق والنواة

- `lib/app.dart`: إعداد التطبيق، RTL، اللغة العربية، الثيم والراوتر.
- `lib/core/config/app_config.dart`: جميع عناوين ومفاتيح عقود Backend القابلة
  للتمرير عبر `dart-define`.
- `lib/core/errors/app_exception.dart`: أخطاء التطبيق وفجوات عقود Backend.
- `lib/core/network/api_client.dart`: عميل Dio موحد مع إضافة access token.
- `lib/core/storage/session_store.dart`: حفظ access/refresh token بصورة آمنة.
- `lib/core/theme/app_theme.dart`: هوية جولة البصرية وخط Cairo.
- `lib/core/router/app_router.dart`: المسارات وحماية الشاشات الخاصة.
- `lib/core/services/location_service.dart`: الأذونات وتدفق الموقع الحقيقي.
- `lib/core/services/realtime_service.dart`: اتصال Socket.IO وطلبات الرحلات.

### المصادقة

- `lib/features/auth/domain/auth_repository.dart`
- `lib/features/auth/data/backend_auth_repository.dart`
- `lib/features/auth/application/auth_controller.dart`
- `lib/features/auth/presentation/splash_screen.dart`
- `lib/features/auth/presentation/login_screen.dart`

تم فصل UI عن Repository، وحفظ الرمز في Secure Storage، وتجهيز refresh token
مستقبليًا دون اختراع آلية تحديث غير موجودة في العقد.

### الرئيسية وطلبات الرحلات

- `lib/features/home/application/driver_home_controller.dart`
- `lib/features/home/presentation/home_screen.dart`
- `lib/features/home/presentation/driver_shell.dart`
- `lib/features/trip_requests/presentation/ride_request_sheet.dart`

تتضمن الخريطة، الموقع والسرعة والاتجاه، إعادة التموضع، زر الاتصال، الاستماع إلى
طلبات الرحلات، Bottom Sheet، عداد 30 ثانية، والقبول أو الرفض عبر أحداث الخادم
المهيأة.

### بقية الميزات

- `lib/features/earnings/presentation/earnings_screen.dart`
- `lib/features/notifications/presentation/notifications_screen.dart`
- `lib/features/profile/presentation/profile_screen.dart`
- `lib/features/documents/presentation/documents_screen.dart`
- `lib/features/wallet/presentation/wallet_screen.dart`
- `lib/features/settings/presentation/settings_screen.dart`
- `lib/features/trip/presentation/trip_screen.dart`
- `lib/shared/widgets/backend_empty_state.dart`

تم إنشاء الشاشات دون عرض أرقام أو حالات وهمية. تعرض الواجهات بوضوح أن البيانات
تنتظر عقد Backend حين لا يكون العقد متوفرًا.

## الملفات المعدلة

- `lib/main.dart`: تشغيل التطبيق داخل `ProviderScope`.
- `pubspec.yaml` و`pubspec.lock`: إضافة حزم Flutter المطلوبة والترجمة العربية.
- `android/app/src/main/AndroidManifest.xml`: أذونات الإنترنت والموقع.
- `ios/Runner/Info.plist`: سبب استخدام الموقع للمستخدم.
- `test/widget_test.dart`: استبدال اختبار العداد باختبار شاشة الدخول العربية.
- `README.md`: تعليمات التشغيل وإعداد العقود.
- ملفات تسجيل الإضافات المولدة من Flutter: تحديث تلقائي بحسب الحزم.

## ما لم يُنفذ وسبب ذلك

كان `http://localhost:3000` غير متاح أثناء التنفيذ، لذلك لم يمكن قراءة Swagger
أو عقود Socket. التزامًا بأن Backend هو المصدر الوحيد للحقيقة، لم يتم تخمين ما
يلي:

- مسارات وحقول WhatsApp OTP.
- أسماء حقول نماذج Driver وVehicle وTrip وRideRequest.
- قيم `TripStatus` و`DriverStatus` وطريقة تغييرها.
- حدث وحمولة إرسال موقع السائق دوريًا.
- حدث وحمولة تغيير Online/Offline في Backend.
- أحداث قبول ورفض الرحلة وحقول تفاصيل الطلب.
- مسارات الرحلة والتتبع والإيقاف والاستئناف والإنهاء والإلغاء.
- مسارات الأرباح والمحفظة والإشعارات والملف الشخصي.
- مسارات رفع المستندات وصيغة multipart وحالات المراجعة.
- الاتصال والمحادثة والطوارئ وسياسة الخصوصية.
- refresh token؛ تم تجهيز التخزين فقط.

لهذا السبب، لا يرسل التطبيق أي موقع أو حالة أو بيانات إلى مسار مخمّن. المصادقة
وطلبات الرحلات قابلة للتفعيل فور تمرير أسماء العقود الفعلية الموجودة في
`AppConfig`.

## نقاط تحتاج دعم Backend

1. تشغيل Backend وإتاحة `/docs` أو ملف OpenAPI.
2. توفير قائمة موثقة بأحداث Socket.IO وحمولاتها ومسار namespace/path.
3. تحديد طريقة مصادقة Socket (اسم مفتاح auth أو headers).
4. توثيق انتقالات حالات الرحلة المسموحة للسائق.
5. توثيق معدل وصيغة إرسال الموقع.
6. توثيق رفع المستندات وحدود الملفات وأنواعها.

## نتائج الجودة

- تحليل Dart/Flutter: لا توجد مشاكل.
- اختبارات Flutter: جميع الاختبارات ناجحة.
- بناء Web: ناجح.
- تشغيل فعلي في المتصفح: شاشة الدخول العربية ظهرت دون استثناءات جديدة.
- تم اكتشاف مشكلة غياب `MaterialLocalizations` أثناء الفحص الفعلي وإصلاحها
  بإضافة `flutter_localizations`.

ملاحظة: تظهر أداة Flutter تحذيرًا بأن `flutter_secure_storage` لا يدعم Swift
Package Manager على iOS/macOS حاليًا، وتحذيرات WebAssembly من إضافتي التخزين
والـ Socket. لا تؤثر هذه التحذيرات في بناء JavaScript الحالي أو Android/iOS
بالطريقة التقليدية، لكنها موثقة هنا دون إخفائها.
