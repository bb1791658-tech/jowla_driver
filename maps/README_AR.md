# منصة خرائط جولة المحلية — العراق

هذه المنصة تشغّل خريطة العراق ومسارات السيارات والبحث عن العناوين دون
الاعتماد على Google Maps أو خوادم OSM العامة. التطبيق يستخدم نمطًا نهاريًا
فقط، وتبقى نسبة البيانات ظاهرة للمستخدم.

## الخدمات

- MapLibre Vector Style:
  `http://localhost:8080/styles/day/style.json`
- Vector TileJSON:
  `http://localhost:8080/data/iraq.json`
- OSRM Route/Nearest/Match:
  `http://localhost:5001`
- Nominatim المحلي للعراق:
  `http://localhost:7070`

تمر خدمة البحث عبر بوابة Nginx بحد افتراضي قدره 5 طلبات في الثانية لكل
عنوان IP مع سماح بدفعة قصيرة، ولا يُكشف منفذ Nominatim الداخلي مباشرة.

تُخدم البلاطات والخطوط العربية والرموز من الجهاز نفسه. لا يحتوي التطبيق أو
إعداد الخادم على نمط ليلي.

تعيد البوابة كتابة أصل الروابط داخل style وTileJSON تلقائيًا إلى اسم المضيف
الذي طلبه الهاتف، لذلك لا يبقى `localhost` داخل التصميم المستلم. عند وضع
Reverse Proxy أمام Nginx يجب تمرير `Host` و`X-Forwarded-Proto` كما هما.

## التشغيل لأول مرة

```bash
./maps/bootstrap.sh
```

ينزّل السكربت:

1. Shortbread MBTiles للعراق من Geofabrik.
2. تصميم VersaTiles النهاري.
3. الخطوط العربية والرموز اللازمة محليًا.
4. ملف OSM PBF للعراق ويبني فهرس OSRM للسيارات.

ثم يشغّل نسختين زرقاء وخضراء من TileServer GL وOSRM خلف بوابة Nginx ثابتة.
وجود النسختين يسمح بتبديل البيانات لاحقًا دون قطع الخدمة.

## البحث المحلي عن العناوين

بعد اكتمال الخطوة السابقة شغّل:

```bash
./maps/bootstrap_geocoding.sh
```

يستورد Nominatim بيانات العراق إلى قاعدة مستقلة. قد تستغرق أول عملية استيراد
عدة دقائق أو أكثر حسب الجهاز، بينما تبقى البلاطات والمسارات عاملة. لمتابعة
التقدم:

```bash
docker compose -f maps/docker-compose.yml logs -f geocoding
```

اختبار البحث بعد ظهور `Import finished`:

```bash
curl 'http://localhost:7070/search?q=بغداد&format=jsonv2&countrycodes=iq'
```

واختبار البحث العكسي:

```bash
curl 'http://localhost:7070/reverse?lat=33.3152&lon=44.3661&format=jsonv2&accept-language=ar'
```

## التحديث الذري دون انقطاع

```bash
./maps/update_map_data.sh
```

يبني السكربت إصدارًا جديدًا داخل `maps/data/releases` ولا يغير الإصدار
الحالي أثناء التنزيل أو بناء OSRM. بعد فحص MBTiles والنمط وخدمتي البلاطات
والمسارات على المسار غير النشط، يبدّل Nginx إليه لحظيًا ثم يغيّر مؤشر
`maps/data/current`. تبقى النسخة السابقة عاملة للرجوع السريع.

يمكن جدولة السكربت أسبوعيًا أو شهريًا على خادم الإنتاج. لا تحذف إصدارًا
قديمًا قبل مراقبة الإصدار الجديد. تحديث Nominatim عملية مستقلة لأنه يملك
قاعدة PostgreSQL خاصة.

يسجل السكربت كل محاولة في `maps/data/update-history.log`. ولإرسال تنبيه JSON
عند الفشل اضبط `MAP_UPDATE_ALERT_WEBHOOK` بعنوان مستقبِل التنبيهات في بيئة
الخادم؛ لا يُرسل شيء خارجي عند تركه فارغًا.

## النقل إلى خادم الإنتاج

انسخ مجلد `maps` وبيانات الإصدار الحالي إلى الخادم، ثم:

```bash
docker compose -f maps/docker-compose.yml up -d
docker compose -f maps/docker-compose.yml --profile geocoding up -d geocoding
```

اضبط في تطبيق Flutter:

- `MAP_ORIGIN=https://maps.example.com`
- `ROAD_ROUTE_BASE_URL=https://routing.example.com`
- `GEOCODING_BASE_URL=https://search.example.com`
- `MAP_DATA_VERSION=<release-id>`

في الإنتاج يجب:

- وضع TLS وقيود معدل الطلبات أمام الخدمات.
- تغيير `NOMINATIM_PASSWORD` وعدم استخدام القيمة المحلية الافتراضية.
- تحديث `TILESERVER_GL_ALLOWED_HOSTS` إلى أسماء النطاقات الفعلية.
- مراقبة زمن الاستجابة، أخطاء تحميل البلاطات، مساحة القرص وذاكرة PostgreSQL.
- إبقاء النص `© OpenStreetMap • Geofabrik • VersaTiles` ظاهرًا.

## مصدر البيانات والترخيص

- بيانات الطرق والأماكن: OpenStreetMap عبر Geofabrik.
- مخطط البلاطات: VersaTiles Shortbread.
- التصميم والخطوط والرموز: VersaTiles.
- التوجيه والمطابقة: OSRM.
- البحث والعكس الجغرافي: Nominatim.

الملفات المولدة والكبيرة مستثناة من Git، ويمكن إعادة إنشائها بالسكربتات.
