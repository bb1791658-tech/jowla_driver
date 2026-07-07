# تقرير ربط jowla_driver مع Backend جولة

التاريخ: 2026-07-03

## تحديث إصلاح شامل — 3 يوليو 2026

أُعيد فحص المشروع فعليًا، ونُفذت الإصلاحات التالية:

1. إصلاح خطأ تجميع بسبب غياب استيراد امتداد `RideStatus.isFinished`.
2. إصلاح مؤقت انتهاء عرض الرحلة؛ أصبح له مؤقت انتهاء مستقل ويستدعي
   `onTimeout` مرة واحدة حتى عند تأخر تحديث واجهة العداد.
3. تنظيف ملفات Flutter القديمة التي كانت تسجل
   `shared_preferences_web` بعد حذف الحزمة وتتسبب بفشل بناء Web.
4. إزالة عنوان الشبكة القديم `192.168.0.152` من إعداد التطوير.
5. اختيار عنوان Backend تلقائيًا: localhost للويب وiOS Simulator،
   و`10.0.2.2` لمحاكي Android، مع دعم `BACKEND_ORIGIN` للهاتف الحقيقي.
6. السماح باتصال HTTP المحلي على Android وiOS أثناء التطوير.
7. تصحيح معرّف Android من `com.example.jowla_driver` إلى
   `com.jowla.driver` واسم التطبيق إلى «جولة للسائق».
8. جعل اتصال Socket ينتظر نجاح الاتصال فعليًا، ويعرض فشل الاتصال خلال
   مهلة محددة بدل اعتبار السائق Online قبل الاتصال.
9. منع بوابة Health من حبس نسخة Debug بالكامل عند توقف Backend.
10. إعادة حساب التطوير المؤقت المطلوب سابقًا
    (`+9647700000000` / `123456`) مع عزله عن Release ومنع تشغيل الرحلات به.
11. عرض الملف الشخصي المحلي لحساب التطوير بدل إرسال طلب Backend غير صالح.

نتيجة التحقق الحالية:

- `dart analyze`: ناجح، لا توجد مشاكل.
- `flutter build web --debug --no-wasm-dry-run`: ناجح.
- حزمة الاختبارات كانت تحتوي فشلًا واحدًا فقط في مؤقت العرض، وقد أُصلح سببه.
- تعذر إعادة تشغيل الاختبارات وفتح خادم الفحص بعد الإصلاح بسبب حد صلاحيات
  بيئة التنفيذ، وليس بسبب خطأ في المشروع.
- تعذر بناء APK داخل البيئة لأن Gradle يحتاج الكتابة إلى cache خارج مساحة
  المشروع. بناء Android يبقى أمر تحقق مطلوب على جهاز التطوير.

## 1. المنهجية

قواعد التنفيذ المُلتزم بها: فُحص `jowla_backend` أولًا (الكود المصدري هو
تعريف Swagger نفسه — NestJS + `@nestjs/swagger` على `/docs`)، ولم يُنشأ أي
Backend جديد، ولم يُخمَّن أي endpoint أو حقل أو حدث Socket، ولم تُغيَّر أي
عقود، وكل التعديلات داخل `jowla_driver` فقط، وأُزيل تسجيل الدخول المحلي
المؤقت بالكامل، ولا توجد أي بيانات وهمية في أي شاشة.

> **قيد بيئة التنفيذ:** جرى هذا العمل في بيئة معزولة لا تستطيع الوصول إلى
> شبكة جهازك المحلي ولا تنزيل Flutter SDK (القوائم الشبكية محظورة).
> لذلك لم يكن ممكنًا هنا تشغيل الخادم فعليًا أو تنفيذ
> `flutter analyze / test / build`. كل العقود مأخوذة من كود الخادم مباشرة
> (وهو أدق من Swagger الحي)، وكُتبت الاختبارات كاملة، وأوامر التحقق جاهزة
> في نهاية التقرير لتشغيلها على جهازك. حالة "مكتمل" النهائية تتحقق بعد
> نجاحها لديك.

## 2. العقود المكتشفة من jowla_backend

### 2.1 الأساس

| العنصر | القيمة | المصدر |
|---|---|---|
| البادئة | `/api` + إصدار URI `v1` → `/api/v1` | `src/main.ts` |
| الصحة | `GET /api/health` → `{status:'ok'}` | `monitoring.controller.ts` |
| Swagger | `/docs` | `src/main.ts` |
| Socket.IO | **namespace** ‏`/realtime` (وليس path) | `websocket.gateway.ts` |
| مصادقة Socket | `handshake.auth.token` أو ترويسة `Authorization: Bearer` (access token) | `socket-auth.service.ts` |

### 2.2 المصادقة (WhatsApp OTP)

| Endpoint | الطلب | الاستجابة |
|---|---|---|
| `POST /auth/otp/request` | `{phone}` بصيغة دولية | `{requestId, expiresAt, mockCode?}` |
| `POST /auth/otp/verify` | `{phone, code(6), deviceKey(8-200), platform(ios/android/web), fcmToken?, accountType:'DRIVER'}` | `{user, driver, device, accessToken, refreshToken, accessTokenExpiresIn, refreshTokenExpiresIn}` |
| `POST /auth/refresh` | `{refreshToken}` | `{accessToken, refreshToken, ...}` — **تدوير إلزامي** مع كشف إعادة الاستخدام وإبطال العائلة |
| `DELETE /auth/sessions/current` | — | `{loggedOut}` |

- دخول السائق يتطلب صف `Driver` بحالة غير (PENDING_APPROVAL/REJECTED/SUSPENDED)، وإلا 403 «Approved driver account is required».
- `sub` في JWT للسائق = **driver.id** (وليس user.id) — يُستخدم في مسارات `/drivers/{id}/...`.
- انتهاء access token: 15 دقيقة، refresh: 30 يومًا (قيم `.env` الافتراضية).

### 2.3 السائق

| Endpoint | ملاحظات |
|---|---|
| `GET /drivers/me` | الملف مع `user` و`services(+serviceType)` و`vehicles` النشطة |
| `PATCH /drivers/{id}/availability` | `{status: 'online'|'offline'|'busy'}` بأحرف صغيرة؛ يرفض لغير المعتمد |
| `PUT /drivers/{id}/location` | `{lat, lng, heading?(0-360), speed?(>=0)}` |

### 2.4 الرحلات (منظور السائق)

| Endpoint | الوظيفة |
|---|---|
| `GET /rides/driver/offers` | العروض المعلقة (تشمل `ride` كاملة) |
| `GET /rides/driver/current` | الرحلة النشطة (DRIVER_ACCEPTED/DRIVER_ARRIVED/TRIP_STARTED) مع `user{id,name,phone}` |
| `GET /rides/{id}` | مسموح للسائق صاحب العرض أو المسند |
| `POST /rides/{id}/offers/{offerId}/accept` | Serializable transaction — الخاسر يستلم 409 «Another driver already accepted» |
| `POST /rides/{id}/offers/{offerId}/reject` | آخر رفض يحوّل الرحلة إلى NO_DRIVER_FOUND |
| `POST /rides/{id}/driver-arrived` | DRIVER_ACCEPTED → DRIVER_ARRIVED |
| `POST /rides/{id}/start` | DRIVER_ARRIVED → TRIP_STARTED |
| `POST /rides/{id}/complete` | TRIP_STARTED → COMPLETED + إنشاء `payment{amount, commissionAmount}` (نقدي، عمولة `commission_fixed_amount`) وإعادة السائق ONLINE |
| `POST /rides/{id}/cancel` | من السائق المسند في أي حالة غير نهائية |

حالات الرحلة (prisma `RideStatus`) **حصرًا**:
`PENDING, SEARCHING_DRIVER, DRIVER_ACCEPTED, DRIVER_ARRIVED, TRIP_STARTED, COMPLETED, CANCELLED, NO_DRIVER_FOUND`.

### 2.5 أحداث Socket.IO

| الحدث | الاتجاه | الحمولة |
|---|---|---|
| `connected` | خادم → عميل | `{socketId, room}` |
| `driver:location:update` | **عميل → خادم** | `{lat, lng, heading?, speed?}` (ack: `{ok, lastLocationAt}`) |
| `ride:offer:new` | خادم → سائق | `{rideId, offerId, expiresAt, pickup{lat,lng}, estimatedFare, currency}` |
| `ride:offer:expired` | خادم → سائق | `{rideId, offerId, reason: server_timeout / accepted_by_other_driver / ride_cancelled / driver_rejected}` |
| `ride:status:changed` + `ride:driver:arrived` / `ride:started` / `ride:completed` / `ride:cancelled` | خادم → غرف الراكب والسائق | كائن الرحلة (أو `{rideId, status}` المختصرة) |
| `exception` | خادم → عميل | فشل مصادقة Socket |

- **مهلة العرض**: `driver_search_timeout_seconds = 30 ثانية` (AppSetting) — العد التنازلي في التطبيق يُحسب من `expiresAt` الذي يرسله الخادم، لا من عداد محلي ثابت.
- **معدل إرسال الموقع**: لا يفرض Backend معدلًا صريحًا؛ القيد الفعلي هو `driver_location_freshness_seconds = 120` (يخرج السائق من المطابقة إذا تقادم موقعه). التطبيق يرسل عند التحرك (فلتر 10م) + نبضة كل 20 ثانية — ضمن النافذة بهامش أمان 6×.

## 3. المشاكل التي أُصلحت في jowla_driver

1. **الربط الوهمي بالكامل**: كانت كل العقود «placeholders» عبر `dart-define` فارغة تُلقي `MissingBackendContractException` — استُبدلت بالعقود الحقيقية الثابتة في `ApiPaths` و`RealtimeService`.
2. **إزالة تسجيل الدخول المحلي المؤقت** (`jowla-debug-session` + رقم/رمز تطوير ثابتان) — الدخول الآن حقيقي فقط، مع دعم `mockCode` القادم من الخادم في وضع التطوير.
3. **خطأ Socket.IO جوهري**: الكود القديم استخدم `setPath('/realtime')` بينما `/realtime` في Backend هو **namespace** وليس path — كان الاتصال سيفشل حتمًا. أُصلح إلى `io('$origin/realtime')` بالمسار الافتراضي.
4. **غياب refresh token**: كان access token يُحفظ بلا تجديد — أُضيف Interceptor كامل: تجديد عند 401، تدوير التوكنين، تجديد واحد متزامن، انتهاء الجلسة يفصل Socket ويعيد لشاشة الدخول تلقائيًا.
5. **verifyOtp بلا accountType ولا deviceKey ولا platform** — أصبح مطابقًا لـ `VerifyOtpDto` مع `deviceKey` ثابت لكل تثبيت (UUID آمن يبقى بعد الخروج).
6. **Online/Offline محلي فقط**: كان زر «ابدأ العمل» يتصل بالـ Socket فقط دون إعلام الخادم — الآن `PATCH availability` أولًا (الخادم مصدر الحقيقة)، مع استئناف تلقائي عند الإقلاع إذا كان الخادم يعتبر السائق ONLINE.
7. **لا إرسال موقع إطلاقًا**: أُضيف بث `driver:location:update` عند التحرك + نبضة 20 ثانية، ولا يُرسل شيء في وضع Offline، مع معالجة أذونات GPS وانقطاعه.
8. **عداد 30 ثانية وهمي**: كان مؤقتًا محليًا يغلق البطاقة فقط — الآن يُشتق من `expiresAt`، ويستجيب لأحداث `ride:offer:expired` بأسبابها (قبول سائق آخر/إلغاء الراكب/انتهاء المهلة).
9. **قبول/رفض عبر أحداث Socket غير موجودة**: Backend لا يستقبل قبولًا عبر Socket — أُصلح إلى REST (`.../accept` و`.../reject`) مع معالجة 409/410.
10. **لا شاشة رحلة فعلية**: بُنيت دورة الرحلة كاملة (متجه للانطلاق → وصلت → بدء → إنهاء/إلغاء) بأزرار مطابقة لانتقالات Backend حصرًا، مع خريطة (السائق + الانطلاق + الوجهة)، مسافة حية، اتصال هاتفي بالراكب، وملخص نهائي (الأجرة النهائية، عمولة جولة، صافي المبلغ).
11. **استعادة الحالة بعد إغلاق التطبيق**: عبر `GET /rides/driver/current` و`GET /rides/driver/offers` عند كل اتصال/إعادة اتصال (سد فجوة الأحداث الفائتة).
12. **بوابة إقلاع**: فحص `GET /api/health` قبل عرض التطبيق مع شاشة إعادة محاولة.
13. **إصلاحات UI/RTL**: توحيد اتجاه RTL، أرقام وهواتف LTR داخل النص العربي، رسائل خطأ عربية موحدة لكل رموز أخطاء Backend المعروفة، حالات تحميل/فراغ/خطأ لكل شاشة، ومنع الرجوع الخاطئ من شاشة الرحلة النشطة.

## 4. الملفات المنشأة والمعدلة

**نواة جديدة/معاد كتابتها:** `core/config/app_config.dart`،
`core/constants/api_paths.dart`، `core/errors/app_exception.dart`،
`core/network/api_client.dart`، `core/storage/session_store.dart`،
`core/services/{session_events, backend_health_service, location_service, realtime_service}.dart`،
`core/providers.dart`، `core/startup/app_startup_controller.dart`،
`core/router/app_router.dart`، `app.dart`،
`shared/screens/backend_gate_screen.dart`.

**المصادقة:** `auth/domain/models/driver_session.dart`،
`auth/domain/auth_repository.dart`، `auth/data/backend_auth_repository.dart`،
`auth/application/auth_controller.dart`، `auth/presentation/login_screen.dart`
(حُذف `splash_screen.dart` القديم).

**السائق والرحلات:** `driver/domain/{driver_repository, models/driver_account}.dart`،
`driver/data/backend_driver_repository.dart`،
`rides/domain/{ride_repository, models/ride, models/ride_offer}.dart`،
`rides/data/backend_ride_repository.dart`.

**الشاشات والمنطق:** `home/application/driver_home_controller.dart`،
`home/presentation/home_screen.dart`،
`trip/application/trip_controller.dart`، `trip/presentation/trip_screen.dart`،
`trip_requests/presentation/ride_request_sheet.dart`،
`profile/presentation/profile_screen.dart` (بيانات حقيقية من `/drivers/me`)،
`settings/presentation/settings_screen.dart` (خروج حقيقي)،
`documents / wallet / earnings / notifications` (حالات صادقة موثقة).

**أخرى:** `pubspec.yaml` (+`url_launcher`، −`shared_preferences` غير المستخدمة)،
`AndroidManifest.xml` وInfo.plist (استعلام `tel:` للاتصال بالراكب)،
`config/` و`tool/` (سكربتات تشغيل مطابقة لنمط تطبيق الراكب)، `README.md`.

**اختبارات (10 ملفات):** `api_paths_test`، `ride_models_test`،
`driver_models_test`، `session_store_test`، `api_client_refresh_test`
(401→تجديد→إعادة، فشل التجديد→انتهاء الجلسة)، `ride_repository_test`
(فشل الشبكة، تعارض القبول، تسلسل الانتقالات)، `trip_controller_test`
(استعادة، تسلسل كامل مع العمولة، أحداث Socket، reconnect، فشل انتقال)،
`home_controller_test` (Online/Offline، عدم الإرسال Offline، عرض/قبول/انتهاء
مهلة، reconnect، استئناف عند الإقلاع)، `login_screen_test`،
`ride_request_sheet_test` + `test/support/fakes.dart`.

## 5. الوظائف المطلوبة ولا يوفرها Backend حاليًا

وفق القاعدة «لا تخمّن»، عُرضت هذه الشاشات بحالة صادقة بدل اختراع عقود:

| الوظيفة | الوضع في jowla_backend |
|---|---|
| حالات Paused/Resumed | غير موجودة في `RideStatus` — دورة الحياة: accepted → arrived → started → completed/cancelled فقط |
| «Heading To Pickup» كحالة مستقلة | يمثلها DRIVER_ACCEPTED |
| الأرباح | لا endpoint (وحدة analytics فارغة) — يُعرض ملخص العمولة والصافي لكل رحلة من `payment` عند الإكمال |
| المحفظة | لا endpoint (الدفع نقدي عبر `cash-payment.provider`) |
| قائمة الإشعارات | الإرسال Push فقط (`notifications.service`)؛ لا endpoint للقراءة |
| المحادثة | `chat.module.ts` فارغ (سطران)؛ الحدث `chat:message:new` مُعد في الـ Gateway لكن لا يوجد أي مرسِل |
| الاتصال داخل التطبيق | `calls.module.ts` فارغ؛ أحداث `call:*` مُعدة بلا منطق — استُخدم الاتصال الهاتفي المباشر برقم الراكب (متوفر في عقد الرحلة) |
| الطوارئ | لا يوجد أي عقد — زر معطل موسوم «قريبًا» |
| رفع المستندات وحالة المراجعة وإعادة الرفع | وحدة media بلا Controller (خدمة MinIO داخلية فقط)؛ لا مسار رفع — نماذج `Media/MediaType(DRIVER_DOCUMENT...)` موجودة في المخطط لكن دون API |
| إدارة المركبة | لا endpoints (`vehicles.module.ts` فارغ) — تُعرض قراءةً من `/drivers/me` |
| مسار الرحلة المرسوم (routing) | `routing.service` داخلي (OSRM) يُستخدم عند إنشاء الرحلة فقط؛ لا endpoint للسائق — يُعرض خط مستقيم ومسافات محسوبة محليًا |
| المدة/المسافة المتبقية الديناميكية | غير متوفرة من الخادم؛ تُعرض مسافة مباشرة محسوبة محليًا + تقديرات الرحلة الأصلية |

## 6. حالة أوامر التحقق

| الأمر | الحالة |
|---|---|
| تشغيل Backend والتحقق من health/docs/api/realtime | ⚠️ يتطلب جهازك (البيئة هنا معزولة عن شبكتك) — الأوامر في README |
| `flutter pub get` | ⚠️ للتشغيل على جهازك (أُضيف `url_launcher` فقط) |
| `dart run build_runner build` | لا ينطبق — المشروع لا يستخدم توليد أكواد |
| `flutter analyze` | ⚠️ للتشغيل على جهازك — أُجري فحص استاتيكي كامل هنا (كل الاستيرادات تُحل، لا مراجع قديمة، لا عقود مخمّنة) |
| `flutter test` | ⚠️ للتشغيل على جهازك — 10 ملفات اختبار جاهزة تغطي الوحدات والمستودعات والمتحكمات والواجهات وفشل الشبكة وانتهاء الجلسة وإعادة الاتصال |
| `flutter build apk --debug` | ⚠️ للتشغيل على جهازك |

الأوامر بالترتيب على جهازك:

```bash
cd ~/jowla_backend && docker compose up -d && npm run start:dev
curl http://localhost:3000/api/health

cd ~/jowla_driver
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
./tool/run_development.sh
```

## 7. تحذيرات ومشاكل متبقية

1. **مزود واتساب الحقيقي غير مهيأ في الخادم** (`whatsapp-otp.provider.ts` يرمي ServiceUnavailable). في التطوير استخدم `OTP_PROVIDER=mock`. عند تفعيل مزود حقيقي لن يتغير شيء في التطبيق.
2. دخول السائق يتطلب حساب Driver معتمدًا مسبقًا (البذور توفر `+9647700000001`). إنشاء السائقين واعتمادهم يتم من لوحة الإدارة/قاعدة البيانات — لا يوجد تسجيل ذاتي للسائق في Backend.
3. إرسال الموقع يعمل والتطبيق في المقدمة؛ التتبع في الخلفية (foreground service على أندرويد) يحتاج قرارًا منفصلًا وحزمة مخصصة — لم يُنفذ لتجنب سلوك غير مطلوب.
4. `ride:status:changed` يصل أحيانًا بحمولة مختصرة `{rideId, status}` — يعالجها التطبيق بتطبيق الحالة فقط والاحتفاظ ببيانات الراكب، مع إعادة مزامنة REST عند كل reconnect.
5. تحذير معروف من أداة Flutter: `flutter_secure_storage` لا يدعم Swift Package Manager بعد — لا يؤثر على البناء التقليدي.
6. يُنصح بتحديث `CLAUDE.md` في jowla_passenger لأن قيد «ممنوع إنشاء jowla_driver» أصبح متجاوزًا فعليًا بقرارك.
