# عقد Backend لخدمة بين المحافظات — تطبيق السائق

هذا العقد يكمل عقد تطبيق الراكب. جميع المسارات تحت `/api/v1` وتتطلب جلسة
سائق معتمد لخدمة `intercity`. الخادم هو المصدر الوحيد للمقاعد والحجوزات
والحالات. يسمح مسار النشر المباشر للسائق باختيار السعر وعدد المقاعد دون حدود
تجارية أو معاينة إلزامية؛ وتبقى مصادقة هوية السائق وسلامة الحجز فقط.

## أنواع الخدمة وحالات الرحلة

- عروض المقاعد: `intercity_seat`.
- السيارة الكاملة: `intercity_full_vehicle`.
- حالات العرض: `open`، `full`، `departed`، `cancelled`، `completed`.
- دورة السيارة الكاملة وفق `RideStatus`: `PENDING`، `SEARCHING_DRIVER`،
  `DRIVER_ACCEPTED`، `DRIVER_ARRIVED`، `TRIP_STARTED`، `TRIP_PAUSED`،
  `COMPLETED`، `CANCELLED`، `NO_DRIVER_FOUND`. يقبل التطبيق أيضًا بعض
  الأسماء القديمة المتكافئة عند قراءة الردود فقط خلال مرحلة الترحيل.

## معاينة عرض المقاعد

`POST /intercity/driver/offers/preview`

يستقبل النقطتين والمحافظتين و`departureAt` بصيغة UTC و`totalSeats` و
`pricePerSeatDinars`. يتحقق الخادم من اعتماد السائق وسعة مركبته واختلاف
المحافظتين والموعد، ثم يعيد:

```json
{
  "data": {
    "previewId": "preview-id",
    "expiresAt": "2026-07-19T14:10:00Z",
    "minimumPriceDinars": 20000,
    "maximumPriceDinars": 35000,
    "distanceMeters": 360000,
    "durationSeconds": 14400,
    "expectedGrossDinars": 100000,
    "cancellationPolicy": "نص عربي صادر من الخادم"
  }
}
```

لا يحسب التطبيق المبلغ المتوقع إذا غاب عن الرد.

## إنشاء العرض

`POST /intercity/driver/offers` مع `Idempotency-Key` اختياري وحقول الرحلة.
حقل `previewId` اختياري للتوافق فقط. ينشئ الخادم العرض ذريًا ويعيد العرض
الكامل المؤكد، ثم يبث `intercity:offer:created` للمشتركين في مسار الرحلة.

## قراءة وإدارة عروض السائق

- `GET /intercity/driver/offers`: جميع عروض السائق القادمة والسابقة.
- `GET /intercity/driver/offers/{offerId}`: أحدث نسخة مع الحجوزات التي يسمح
  بعرضها للسائق.
- `PATCH /intercity/driver/offers/{offerId}`: يتطلب `version` و`previewId`
  جديدًا، ويطبق الخادم قواعد منع التعديل الضار بالحجوزات.
- `POST /intercity/driver/offers/{offerId}/cancel`.
- `POST /intercity/driver/offers/{offerId}/depart`.
- `POST /intercity/driver/offers/{offerId}/complete`.

كل رد عرض يتضمن على الأقل عقد تطبيق الراكب، ويضيف:

```json
{
  "durationSeconds": 14400,
  "bookings": [{
    "id": "booking-id",
    "passenger": {"id": "user-id", "displayName": "الاسم المسموح"},
    "seatCount": 2,
    "totalPriceDinars": 50000,
    "paymentMethod": "cash",
    "status": "confirmed",
    "cancelUntil": "2026-07-19T13:00:00Z"
  }],
  "expectedGrossDinars": 100000,
  "dueAmountDinars": 50000,
  "cancellationPolicy": "نص عربي",
  "canEdit": true,
  "canCancel": true,
  "canDepart": false,
  "canComplete": false
}
```

لا يرسل الخادم رقم هاتف الراكب داخل حجز المقعد إلا إذا أضيفت صلاحية صريحة
إلى العقد. تحدد حقول `can*` قرارات الواجهة؛ ولا يستنتجها التطبيق من ساعته.

## السيارة الكاملة المجدولة

الطلب الفوري يدخل `GET /rides/driver/offers` و`ride:offer:new` الحاليين.
يجب أن تتضمن الرحلة `serviceTypeCode: intercity_full_vehicle` و`quoteId`
والسعر المثبت والمسافة والمدة. الرحلات المجدولة المؤكدة تقرأ عبر:

`GET /rides/driver/scheduled`

ويعيد كل عنصر عقد الرحلة العام مع `scheduledAt` UTC و`canStart`. لا يبدأ
التطبيق التوجه أو الرحلة حتى يعيد الخادم `canStart: true` وتصبح الرحلة هي
`GET /rides/driver/current`.

## Socket.IO وإعادة المزامنة

يدعم Gateway:

- `intercity:offer:created`
- `intercity:offer:updated`
- `intercity:offer:removed`
- `intercity:offer:full`
- `intercity:booking:updated`
- `intercity:booking:cancelled`

تُعامل الأحداث كإشعار لإعادة جلب REST، ولا يخصم التطبيق مقعدًا أو يعيده من
الحمولة. عند كل اتصال أو إعادة اتصال يعيد التطبيق جلب عروض السائق والرحلات
المجدولة والعرض المفتوح، ثم يستبدل حالته بالنسخة الأحدث من الخادم.

## النشر الفوري

يشترك تطبيق الراكب في غرفة Socket.IO بحسب المحافظة وتاريخ المغادرة. بعد حفظ
الرحلة يبث الخادم الحدث مباشرة، فيعيد التطبيق جلب القائمة ويعرض الرحلة دون
انتظار تحديث يدوي. تبقى استجابة REST هي المصدر النهائي عند إعادة الاتصال.
