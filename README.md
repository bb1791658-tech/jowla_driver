# Jowla Driver — تطبيق السائق

تطبيق السائق لمنظومة **جولة**، مربوط بالكامل مع `jowla_backend` الحقيقي
(REST + Socket.IO). جميع العقود مأخوذة حرفيًا من كود الخادم وSwagger
(`/docs`) — لا توجد أي بيانات وهمية ولا تسجيل دخول محلي.

أصبحت البنية مهيأة كذلك للإشعارات عبر Firebase، ومحادثة الرحلة، والمكالمات
الصوتية داخل التطبيق عبر WebRTC. تبقى مفاتيح Firebase وMeta وTURN وشهادات
Apple إعدادات تشغيل تُملأ عند تجهيز الخادم والحسابات، من دون تغيير منطق
التطبيق.

## المتطلبات

1. تشغيل Backend مع Postgres/PostGIS وRedis:

   ```bash
   cd ../jowla_backend
   docker compose up -d          # قاعدة البيانات وRedis وMinIO
   npm run prisma:deploy && npm run prisma:seed
   npm run start:dev
   ```

2. التأكد من:
   - `GET /api/health` → `{"status":"ok"}`
   - Swagger على `/docs`
   - REST على `/api/v1`
   - Socket.IO namespace على `/realtime`

## التشغيل

يختار التطبيق العنوان المحلي الصحيح تلقائيًا:

- Web وiOS Simulator: `http://localhost:3000`
- Android Emulator: `http://10.0.2.2:3000`

على هاتف حقيقي مرر عنوان الحاسوب في الشبكة المحلية:

```bash
./tool/run_development.sh
# أو
flutter run --dart-define=BACKEND_ORIGIN=http://<host>:3000
```

### الدخول التطويري

مع `OTP_PROVIDER=mock` و`OTP_EXPOSE_MOCK_CODE=true` في `.env` الخادم،
يعيد طلب الرمز حقل `mockCode` ويعرضه التطبيق في شاشة OTP (وضع التطوير
فقط). السائق التجريبي المزروع بالبذور: `+9647700000001` (معتمد، خدمة تكسي).

لا توجد جلسة محلية أو بيانات رحلات بديلة: إذا توقف Backend تظهر بوابة
الاتصال، ويعود التطبيق تلقائيًا بعد نجاح فحص الصحة.

ملاحظة: تسجيل دخول السائق يتطلب صف Driver معتمدًا في قاعدة البيانات —
`accountType: DRIVER` يرفض بـ 403 إن لم يوجد حساب معتمد بهذا الرقم.

## التحقق

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

(لا يستخدم المشروع build_runner — لا توجد أكواد مولدة.)

كل طلب واتصال حي يبقى خلف Repository/Service بعقد واضح؛ لذلك يمكن تبديل
مزود الإشعارات أو التوجيه أو خادم TURN لاحقًا من الإعدادات والجهة الخلفية
دون إعادة كتابة الشاشات.

ملاحظة صيانة Android: ثُبّتت `package_info_plus` مؤقتًا على `9.0.1` لأن
WebRTC وMapLibre لم يكملا انتقال Flutter 3.44 إلى Kotlin المدمج. تُحدّث هذه
الحزم الثلاث معًا بعد اكتمال دعمها، وتمنع بوابة بناء Release دمج تركيبة غير
متوافقة.

الحد الأدنى لـiOS هو 15.0، وهو الحد المطلوب لإصدار Firebase المستخدم.

راجع [تقرير الربط الكامل](REPORT_INTEGRATION_AR.md) لتفاصيل العقود
المكتشفة والمشاكل التي أُصلحت وما لا يوفره Backend حاليًا.
