# Jowla Driver — تطبيق السائق

تطبيق السائق لمنظومة **جولة**، مربوط بالكامل مع `jowla_backend` الحقيقي
(REST + Socket.IO). جميع العقود مأخوذة حرفيًا من كود الخادم وSwagger
(`/docs`) — لا توجد أي بيانات وهمية ولا تسجيل دخول محلي.

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

عند توقف Backend يمكن فحص الواجهة في Debug بالحساب المحلي المؤقت:
`+9647700000000` والرمز `123456`. هذا المسار محجوب كليًا في Release،
ولا يرسل أو يستقبل رحلات.

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

راجع [تقرير الربط الكامل](REPORT_INTEGRATION_AR.md) لتفاصيل العقود
المكتشفة والمشاكل التي أُصلحت وما لا يوفره Backend حاليًا.
