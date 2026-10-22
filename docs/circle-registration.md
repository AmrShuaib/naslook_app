# تسجيل الدوائر الموثّقة: ست خطوات، نظام اكتمال واحد، توثيق الكيان، والدائرة المتنقلة

قرار المالك (21 أكتوبر 2026): الدائرة تظهر على الخريطة **فور** إكمال التسجيل بست خطوات، **الشعار إلزامي**، و**البيع والحجز وربط الدفع لا تُفتح إلا بعد اعتماد** سجل تجاري أو وثيقة عمل حر (يدوياً من لوحة الإدارة الآن، وآلياً عبر «وثقة» لاحقاً). نظام اكتمال واحد يقود كل دائرة إلى الكمال، وأصحاب العمل الحر بلا مقر يحصلون على **دائرة متنقلة** بنطاق خدمة ودبوس «هنا اليوم» مؤقت بدل دبوس ثابت.

هذا الملف يصف الجانب الخادمي (هذه الحزمة الأولى). واجهات التطبيق (معالج التسجيل، صفحة التوثيق، بطاقة الاكتمال في لوحة الدائرة، قسم التوثيقات في الإدارة) في حزمتين موازيتين تبنيان على العقد نفسه.

## الملفات

| الملف | الدور |
|---|---|
| `server/business.js` | الأعمدة الجديدة في `biz`، الفئات الست الجديدة، الإنشاء الموحّد `naslifeBizCreate`، حقول المخرجات الجديدة، الموقع الفعلي وتغطية النطاق في `GET /biz`، بوابة البيع في الطلبات، اتساق المفتاح القديم `POST /biz/:id/verify` |
| `server/biz_onboard.js` (جديد، مسجّل آخر `register.txt` بعد `offers.js`) | فحص التكرار، التسجيل، الاكتمال، التوثيق (الإرسال وقائمة الإدارة والقرار)، دبوس «هنا اليوم»، و`naslifeBizOwnersNear` |
| `server/row.js` | النوع السادس `circle` في الصف |
| `server/market_plus.js` | خطّاف «أبحث عن» يُخبر أصحاب الدوائر المتنقلة التي يغطي نطاقها موقع الطلب |
| `server/test/harness_biz_onboard.mjs` | حزمة الاختبار (نحو 190 فحصاً) |

لا جداول جديدة: كل شيء أعمدة على `biz` تُضاف بـ `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` في `business.js`.

## الأعمدة الجديدة في `biz`

| العمود | النوع | المعنى |
|---|---|---|
| `presence` | `TEXT NOT NULL DEFAULT 'fixed'` | `fixed` مقر ثابت، `mobile` دائرة متنقلة |
| `service_area` | `JSONB` | للمتنقلة: `{lat, lng, radiusKm (2..50), districts: [..≤10]}`؛ **المركز الفعلي هو `lat/lng` الدائرة نفسها** (مصدر واحد) وJSONB يحمل نصف القطر والأحياء |
| `entity_kind` | `TEXT` | `cr` سجل تجاري أو `freelance` وثيقة عمل حر |
| `entity_number` | `TEXT` | رقم السجل (10 أرقام) أو الوثيقة (8–20 حرفاً/رقماً) |
| `verification` | `JSONB NOT NULL DEFAULT '{}'` | `{status: none|pending|approved|rejected, docUrl, submittedAt, submittedBy, reviewedBy, reviewedAt, reason}` |
| `verified_at` | `TIMESTAMPTZ` | وقت الاعتماد |
| `phone_verified` | `BOOLEAN NOT NULL DEFAULT false` | توثيق الجوال (مؤجّل: «قريباً») |
| `owner_role` | `TEXT` | ما اختاره المسجِّل: `owner` أو `manager` (المسجِّل يصبح `owner_id` في الحالتين) |
| `here` | `JSONB` | دبوس «هنا اليوم»: `{lat, lng, until, setAt}` |
| `registered_at` | `TIMESTAMPTZ` | وقت التسجيل بالمسار الجديد |

العمود القديم `verified` صار **مرآة** لـ `verification.status === 'approved'`: الاعتماد يجعله `true` والرفض أو السحب `false`. المفتاح القديم `POST /biz/:id/verify {verified}` ما زال يعمل ويكتب الحالة (`approved` عند التشغيل، `none` عند الإطفاء مع `reviewedBy/At`).

### المرآة محفوظة في القاعدة: المشغّل `biz_verified_mirror` والترحيل

المرآة لا تعتمد على كل كاتب (لوحة الإدارة في `admin.js` تقلب `verified` وحده عبر `POST /adminapi/biz/:id {verified}`)، بل على مشغّل `BEFORE INSERT OR UPDATE` على `biz` ينشئه `business.js` عند كل إقلاع في استعلام مستقل بعد كتلة المخطط (`CREATE OR REPLACE FUNCTION` ثم `DROP TRIGGER IF EXISTS` + `CREATE TRIGGER`؛ تعثّره يُسجَّل تحذيراً `biz_verified_mirror: …` ولا يعطّل إضافة الدوائر، ومساراتها تكتب العمودين معاً على كل حال):

| ما تغيّر في الصف | ما يفعله المشغّل |
|---|---|
| `verification` (أي مسار يكتب الحالة: الإرسال، الاعتماد، الرفض، المفتاح القديم) | `verified = (status = 'approved')`، و`verified_at` يُضبط عند الاعتماد (إن كان فارغاً) ويُمسح عند غيره |
| `verified` وحده إلى `true` (لوحة الإدارة، أو أي `UPDATE biz SET verified=true`) | `status = 'approved'`، `reviewedAt = now()`، `reason = null`، `verified_at = COALESCE(verified_at, now())` |
| `verified` وحده إلى `false` | `status = 'none'`، `reviewedAt = now()`، `reason = null`، `verified_at = NULL` (كالمفتاح القديم: سحب بلا سبب رفض) |
| إدراج صف بحالة في `verification` | الحالة هي المصدر (التسجيل يدرج `{status: none}`) |
| تعديل لا يمسّ العمودين | لا شيء، إلا إن كان الصف متناقضاً أصلاً فيُشفى بالقاعدة نفسها |

فلا تخرج دائرة `verified:true / canSell:false / verificationStatus:'none'` من أي مسار، ولوحة الإدارة الحالية تفتح البيع وتغلقه مثل مسار القرار الجديد (الفارق: لا إشعار للمالك ولا `reviewedBy`؛ القرار يُسجَّل في `admin_audit` بفعل `biz.update`). الأفضل أن تستدعي اللوحة مسار القرار الجديد ليصل الإشعار، لكن ذلك ليس شرطاً للاتساق.

**الترحيل عند النشر (قرار هذه الحزمة):** الدوائر التي وثّقها المدير بالمفتاح القديم قبل الحزمة (`verified=true` بلا `verification.status`) **تبقى معتمدة وتبيع** ولا تُغلق فجأة: جملة آمنة التكرار في كتلة المخطط `UPDATE biz SET verification = verification || '{"status":"approved"}', verified_at = COALESCE(verified_at, updated_at, created_at) WHERE verified AND NOT (verification ? 'status')` (تطابق صفراً من الصفوف بعد أول إقلاع). الحجة: توثيق المدير اليدوي هو الإجراء المعتمد الآن أصلاً، فالدائرة التي قبلها المدير لا تخسر ما كان مفتوحاً لها. إن أراد المالك إلزام هذه الدوائر برفع وثيقة، يسحب الاعتماد من اللوحة (المفتاح أو «رفض» بسبب) أو دفعة واحدة: `UPDATE biz SET verified=false WHERE verification->>'status'='approved' AND verification->>'docUrl' IS NULL` (المشغّل يحوّلها إلى `none` ويغلق البيع حتى الاعتماد من جديد).

## الفئات

`CATEGORIES` في `business.js` (مصدَّرة وعلى `globalThis.naslifeBizCategories`) صارت 16: القديمة `brand, cinema, hotel, car_rental, hospital, airport, cafe, restaurant, company, university` والجديدة `shop` (متجر)، `services` (خدمات وورش)، `salon` (صالون وتجميل)، `clinic` (عيادة)، `entertainment` (ترفيه)، `other` (أخرى). الأسماء العربية في `CATEGORY_AR` ونوع الصنف الافتراضي في `ITEM_KIND_OF`: `shop/services → product`، `salon/clinic → clinic` (مواعيد)، `entertainment → showtime`، `other → info`. `GET /biz?category=` والإنشاء القديم `POST /biz` يقبلان الجديدة.

## الخطوات الست والتحقق (`POST /biz/register`)

| # | الخطوة | الحقل | التحقق | الخطأ (400) |
|---|---|---|---|---|
| 1 | الفئة | `category` | من `CATEGORIES` | `bad-category` |
| 2 | الاسم | `nameAr` (2–60)، `name` لاتيني اختياري (يُستخدم للمعرّف؛ إن غاب فالعربي) | | `bad-name` |
| 3 | الشعار | `logoUrl` | **إلزامي**: رابط وسائط مرفوعة يبدأ بـ `/` أو `https://` (أو `http://` للتطوير) | `logo-required` |
| 4 | الحضور والموقع | `presence` (`fixed`/`mobile`)، `lat`/`lng` (الموقع، أو مركز النطاق للمتنقلة)، `radiusKm` (متنقلة فقط، 2..50، افتراضي 15، يُهمل للثابتة)، `districts` (حتى 10 أسماء، 40 حرفاً لكل اسم) | | `bad-presence`، `bad-location`، `bad-radius` |
| 5 | الجوال | `phone` | **إلزامي** جوال سعودي بأي صيغة (`05XXXXXXXX`، `5XXXXXXXX`، `+9665…`، `009665…`، `9665…`، بأرقام عربية أو لاتينية) ويُخزَّن `+9665XXXXXXXX` | `bad-phone` |
| 6 | الدور | `role` (`owner`/`manager`، افتراضي `owner`) | | `bad-role` |

اختيارياً تُقبل `hours` و`description` و`address` من البداية. الأخطاء الأخرى: 401 بلا جلسة، 403 `suspended`، 400 `banned-words` (فلتر `safety.js`)، 409 `too-many` (حد 20 دائرة للمستخدم، نفسه في `POST /biz`). الإنشاء يمر بالدالة الموحّدة `createBiz` في `business.js` (توليد المعرّف `biz-<slug>-<hex>`، الفلتر، الحد) المعروضة كـ `globalThis.naslifeBizCreate(uid, body, extra)`، فلا منطق مكرر.

النتيجة 200: `{ biz: bizOut (مع myRole: "owner")، completeness }`، والدائرة `active=true` و`verification={status:"none"}` و`registered_at=now()` وتظهر فوراً في `GET /biz`.

### فحص التكرار قبل التسجيل

`GET /biz/register/check?name=&lat=&lng=` (بجلسة) → `{ duplicates: [{ id, name, nameAr, category, distanceKm, ownerId, logoUrl }] }`: دوائر نشطة غير مخفية خلال **3 كم** اسمها مشابه بعد التطبيع العربي (`NORM`/`normQ` من `business.js`؛ احتواء في الاتجاهين، وتشابه ثلاثي `similarity > 0.45` إن كانت `pg_trgm` مثبّتة)، الأقرب أولاً، خمس على الأكثر. 400 `bad-query` إن كان الاسم أقصر من حرفين أو الموقع ناقصاً.

### خيارات التسجيل

`GET /biz/register/options` (عام) → الفئات بأسمائها العربية، الحضور، الأدوار، أنواع الكيان، حدود نصف القطر وساعات الدبوس، متطلبات الاكتمال، الأوزان، وروابط الاستعلام الرسمية.

## حقول المخرجات الجديدة (`bizOut`)

`presence`، `serviceArea` (`{lat, lng, radiusKm, districts}` أو `null`)، `here` (`{lat, lng, until}` ما دام `until` في المستقبل وإلا `null`)، `verificationStatus`، `canSell` (= معتمدة)، `tier`، `entityKind` (للمالك والمدير ومدير النظام فقط، وإلا `null`)، `phoneVerified`. **`lat/lng` في المخرجات هما الموقع الفعلي**: موقع دبوس «هنا اليوم» ما دام قائماً، وإلا موقع الدائرة (مركز النطاق للمتنقلة). رقم الكيان ووثيقته وسبب الرفض **لا يخرجان أبداً** للعامة؛ للطاقم عبر `GET /biz/:id/verification` وللإدارة عبر قائمتها.

## نظام الاكتمال

`GET /biz/:id/completeness` (المالك والمدير والموظف ومدير النظام) → `{ tier, percent, canSell, checks, next, verification }`.

### المستويات (تراكمية)

| المستوى | الشرط |
|---|---|
| `published` | مسجّلة |
| `complete` | ساعات العمل غير فارغة (للمتنقلة يكفي وجود `service_area`) **و** الوصف ≥ 20 حرفاً **و** الصور ≥ 3 (روابط **مميزة** من `logo_url` و`cover_url` و`biz_items.image_url` وصور `biz_posts` غير المخفية) **و** 3 أصناف نشطة على الأقل في `biz_items` |
| `verified` | مكتملة **و** `verification.status = approved` |
| `active` | موثّقة **و** صف نشط في `biz_offers` أُنشئ خلال 30 يوماً **و** منشور نشط غير مخفي في `biz_posts` خلال 30 يوماً |

`canSell` يعتمد على الاعتماد وحده (دائرة معتمدة غير مكتملة تبيع). المستوى يُحسب في `business.js` من أعمدة محسوبة في `LIST_SQL` (`photos_count`، `items_count`، `post30d`، `offer30d`) فيظهر في كل قائمة؛ جدول `biz_offers` ملك `offers.js` فيُفحص وجوده بـ `to_regclass` ولا يسقط الاستعلام إن غاب.

### النسبة (المجموع 100)

| الفحص | الوزن | يُحتسب |
|---|---|---|
| `logo` | 10 | وجود الشعار |
| `location` | 10 | إحداثيات صالحة |
| `phone` | 10 | وجود الجوال |
| `hours` | 10 | ساعات غير فارغة أو نطاق خدمة للمتنقلة |
| `description` | 10 | ≥ 20 حرفاً |
| `photos` | 15 | نسبياً: `15 × min(1, الصور/3)` مقرّباً |
| `catalog` | 15 | نسبياً: `15 × min(1, الأصناف/3)` مقرّباً |
| `entity` | 20 | الاعتماد فقط |

`checks` يعيد أيضاً `photos: {have, need: 3}`، `catalog: {have, need: 3}`، `entity: {status}`، `phoneVerified`، `offer30d`، `post30d`.

### الخطوة التالية

`next` = أول فحص غير محقق بالترتيب: `logo → location → phone → hours → description → photos → catalog → entity → offer30d → post30d`، أو `null` حين لا يبقى شيء. كل خطوة `{ key, title, hint, minutes, tab }` بالعربية و`tab` من `profile | catalog | posts | offers | verify` يفتحه التطبيق في لوحة الدائرة. خطوة الصور توجّه إلى `profile` (الغلاف أولاً) ثم إلى `catalog` بعد وجود غلاف؛ خطوة الكيان عنوانها «قيد المراجعة» في الانتظار و«أعد رفع وثيقة الكيان» مع سبب الرفض تلميحاً بعد الرفض. `phoneVerified` ليس خطوة (مؤجّل).

`verification` = `{ status, entityKind, reason, submittedAt, reviewedAt }`.

## التوثيق

### الإرسال (مالك/مدير)

`POST /biz/:id/verification { entityKind: cr|freelance, entityNumber, docUrl }` → `{ status: "pending", verification: {..., entityNumber, docUrl} }`.

- `cr`: 10 أرقام (الأرقام العربية تُحوَّل والشرطات والمسافات تُزال)؛ `freelance`: 8–20 حرفاً/رقماً لاتينياً. وإلا 400 `bad-number`؛ نوع آخر 400 `bad-entity`؛ الوثيقة إلزامية (رابط مرفوع) وإلا 400 `doc-required`.
- 409 `already-approved` إن كانت معتمدة. بعد الرفض (أو أثناء الانتظار) يجوز الإرسال من جديد فيستبدل الطلب ويمسح السبب.
- يكتب `entity_kind`، `entity_number`، `verification={status:pending, docUrl, submittedAt, submittedBy}`، `verified=false`، ويُخبر المديرين (`kind: biz_verification`, `data: {bizId}`).

`GET /biz/:id/verification` (مالك/مدير/مدير النظام) → الحالة والنوع والرقم والوثيقة والسبب والأوقات و`canSell` و`lookupUrl`.

### الإدارة

- `GET /adminapi/biz/verifications?status=pending|approved|rejected|all` (افتراضي `pending`؛ `all` = الثلاث بلا `none`) → `[{ bizId, name, nameAr, category, logoUrl, presence, ownerId, owner: {id, nickname, avatarUrl}, entityKind, entityNumber, docUrl, submittedAt, status, reason, reviewedAt, reviewedBy, lookupUrl }]` الأحدث إرسالاً أولاً، حتى 200.
- `lookupUrl`: للسجل التجاري صفحة «الاستعلام عن بيانات السجل التجاري» في وزارة التجارة `https://mc.gov.sa/ar/eservices/Pages/ServiceDetails.aspx?sID=91`، ولوثيقة العمل الحر صفحة التحقق في منصة العمل الحر `https://freelance.sa/certificate-validation`. تُستبدلان من إعدادات المنصة بالمفتاحين `crLookupUrl` و`freelanceLookupUrl` (`platform_settings` عبر `admin.js`).
- `POST /adminapi/biz/:id/verification/approve` → `{ ok, status: "approved" }`: يكتب `status=approved`، `reviewedBy/At`، `verified=true`، `verified_at=now()`، يُخبر المالك (`kind: biz_verified`, `data: {bizId}`)، ويسجّل `biz.verification.approve` في سجل الإدارة عبر `globalThis.naslifeAudit` إن وُجد. الاعتماد جائز حتى بلا إرسال سابق (توثيق يدوي).
- `POST /adminapi/biz/:id/verification/reject { reason }` → `{ ok, status: "rejected" }`: السبب إلزامي 3–300 حرفاً (400 `bad-reason`)، ويحتاج طلباً معلّقاً أو اعتماداً يُسحب (409 `not-pending`)؛ يكتب السبب و`verified=false`، يُخبر المالك (`kind: biz_verification_rejected`, `data: {bizId, reason}`)، ويسجّل `biz.verification.reject`.
- 403 `admin-only` لغير المدير، 400 `bad-decision`، 404 `not-found`.

### الإشعارات التي يوجّهها التطبيق

`biz_verification` (للمديرين → قسم توثيقات الدوائر في الإدارة)، `biz_verified` و`biz_verification_rejected` (للمالك → لوحة الدائرة، صفحة التوثيق).

## بوابة البيع

في `POST /biz/:id/orders` (`business.js`): بعد تطبيق العروض، إن كان المجموع > 0 والدائرة بلا مالك → 409 `no-owner` (كما كان)، وإن لم تكن معتمدة → **403 `not-verified`** بلا أي قيد في المحفظة. الأصناف المجانية (المجموع صفر) تبقى قابلة للطلب. التطبيق يعرض «هذه الدائرة لم تُوثَّق بعد فلا يمكن الطلب منها الآن». سحب الاعتماد (المفتاح القديم أو الرفض) يغلق البيع من جديد.

## الدائرة المتنقلة

- **نطاق الخدمة**: مركزه `lat/lng` الدائرة ونصف قطره `service_area.radiusKm` (افتراضي 15 كم). في `GET /biz` مع `lat&lng` تُدرج الدائرة المتنقلة التي يغطي نطاقها النقطة (هافرساين ≤ `radiusKm`) **ولو خارج `bbox`**، وتحمل `distanceKm` إلى مركزها.
- **دبوس «هنا اليوم»**: `POST /biz/:id/here { lat, lng, hours (1..12، افتراضي 4) }` (المالك والمدير والموظف، **للمتنقلة فقط** وإلا 409 `not-mobile`؛ 400 `bad-location`/`bad-hours`) → `{ here: {lat, lng, until} }`؛ `DELETE /biz/:id/here` → `{ ok }`. ما دام `until` في المستقبل:
  - `GET /biz` مع `bbox` يدرج الدائرة إن كان **الدبوس** داخل الحدود ويعيدها عند موقعه (`lat/lng` و`here`)، ولا يدرجها بموقعها الأصلي؛ `GET /biz/:id` يعيد الموقع الفعلي كذلك؛ عند الانتهاء يعود كل شيء إلى المركز بلا تدخل.
  - **الصف** (`row.js`): النوع السادس `circle` لكل دائرة نشطة غير مخفية بدبوس قائم داخل نصف القطر: `{ kind: "circle", id, refId: biz.id, title: nameAr||name, subtitle: "هنا اليوم حتى HH:MM · <الفئة بالعربية>", imageUrl: logoUrl, lat, lng (الدبوس), distanceKm, at: setAt, endsAt: until, act: "زيارة", cta: "زيارة", payload: { here: true, until } }`. `KINDS` و`ACT` و`TABLES` (`circle → biz`) و`/row/status` تعرفه.
- **«أبحث عن»** (`POST /market/wanted` في `market_plus.js`): إضافةً إلى بائعي التصنيف القريبين، يُخبَر أصحاب الدوائر المتنقلة النشطة غير المخفية التي يغطي نطاقها موقع الطلب (`kind: market_wanted`, نفس الحمولة) عبر `globalThis.naslifeBizOwnersNear(lat, lng)` التي تصدّرها `biz_onboard.js` (حتى 50 مالكاً، بلا تكرار، ولا يُخبَر صاحب الطلب نفسه).
- لحظات العمل: تُنشر من المنشئ كأي لحظة على الخريطة (لا تغيير خادمي هنا).

## جدول المسارات

| المسار | من | الرد |
|---|---|---|
| `GET /biz/register/options` | عام | الخيارات |
| `GET /biz/register/check?name&lat&lng` | جلسة | `{ duplicates }` |
| `POST /biz/register` | جلسة غير موقوفة | `{ biz, completeness }` |
| `GET /biz/:id/completeness` | طاقم الدائرة/مدير النظام | الاكتمال |
| `GET /biz/:id/verification` | مالك/مدير/مدير النظام | ما أُرسل |
| `POST /biz/:id/verification` | مالك/مدير | `{ status, verification }` |
| `GET /adminapi/biz/verifications?status=` | مدير النظام | القائمة |
| `POST /adminapi/biz/:id/verification/approve\|reject` | مدير النظام | `{ ok, status }` |
| `POST /biz/:id/here` / `DELETE /biz/:id/here` | طاقم الدائرة المتنقلة | `{ here }` / `{ ok }` |
| `GET /biz/onboard/status` | عام | `{ ok, categories, trgm, lookup }` |
| `POST /biz/:id/verify {verified}` (قديم) | مدير النظام | `{ ok }` ويكتب الحالة |
| `POST /adminapi/biz/:id {verified}` (`admin.js`، لوحة الإدارة) | مدير النظام | `{ ok }`؛ المشغّل `biz_verified_mirror` يكتب الحالة و`verified_at` |

## ما تتشاركه الإضافات على `globalThis`

`naslifeBizCategories` (المجموعة)، `naslifeBizCreate(uid, body, extra)`، `naslifeBizLoadFull(id, uid)` (صف بالأعمدة المحسوبة)، `naslifeBizOut(row, extra)`، `naslifeBizHelpers` (`verStatus, verOf, hereOf, tierOf, isComplete, hoursOk, serviceAreaOf, canManage, canOperate, canOwn, roleFor, isAdmin, isSuspended, CATEGORY_AR`)، و`naslifeBizOwnersNear(lat, lng)` من `biz_onboard.js`.

## الاختبار

```
NASLIFE_TEST_DB=naslife_test_reg server/test/run.sh harness_biz_onboard.mjs
```

تغطي: وحدات الجوال والفئات والأوزان، كل رمز خطأ في التسجيل، المسار السعيد الثابت والمتنقل، فحص التكرار (قريب نعم، 10 كم لا)، المستويات الأربعة والنسبة والخطوة التالية خطوة خطوة، أخطاء إرسال التوثيق وإخفاء بيانات الكيان، قائمة الإدارة وتجاوز رابط الاستعلام والرفض والاعتماد والإشعارات والسجل وإعادة الإرسال، بوابة البيع قبل الاعتماد وبعده وبعد السحب، المفتاح القديم، مفتاح لوحة الإدارة `POST /adminapi/biz/:id {verified}` (تُسجَّل `admin.js` في الحزمة: الإطفاء يغلق الطلبات المدفوعة والتشغيل يفتحها والمخرجات متسقة والسجل `biz.update`)، المشغّل من الجهتين وثبات التعديلات غير المتعلقة، الترحيل عند الإقلاع (صف قديم `verified` بلا حالة يُعاد تشغيل `business.js` عليه فيُعتمد ويبيع، والمرفوضة وغير الموثّقة لا تُمسّ، والتكرار آمن)، دبوس «هنا اليوم» (أخطاؤه، أثره على `GET /biz` و`GET /biz/:id` والصف، انتهاؤه ومسحه)، تغطية النطاق، خطّاف «أبحث عن»، الفئات الجديدة وأنواع أصنافها، وحد الـ20.

حزم أثّرت فيها بوابة البيع فعُدّلت بسطر اعتماد قبل الطلبات المدفوعة: `harness.mjs`، `harness_offers.mjs`، `harness_chat_cards.mjs`، `harness_notify.mjs`.

## ملاحظات ومؤجّلات

- `POST /adminapi/biz/:id {verified}` في `admin.js` ما زال يقلب العمود `verified` وحده (الملف خارج هذه الحزمة)، والمشغّل `biz_verified_mirror` يكمل الحالة و`verified_at` فيبقى الاتساق وبوابة البيع صحيحين؛ ما ينقصه فقط إشعار المالك (`biz_verified` / `biz_verification_rejected`) وسبب الرفض، فالأفضل أن تستدعي اللوحة `POST /adminapi/biz/:id/verification/approve|reject` (حزمة الإدارة).
- توثيق الجوال (`phone_verified`) مؤجّل كما في الملف الشخصي.
- «وثقة» للتحقق الآلي من السجل التجاري لاحقاً: يكفي أن يستدعي مسار الاعتماد نفسه.

## جهة التطبيق (صاحب النشاط)

**القرار** (المالك، أكتوبر 2026): أي نشاط محلي يسجّل دائرته بنفسه في ست خطوات وتظهر على الخريطة **فوراً**؛ الشعار إلزامي؛ البيع والحجز وربط الدفع تُفتح فقط بعد توثيق **سجل تجاري** أو **وثيقة العمل الحر** (يدوياً من لوحة الإدارة الآن، وتلقائياً عبر واثق لاحقاً)؛ نظام اكتمال واحد يقود كل دائرة إلى الاكتمال؛ والمستقل بلا مقر يحصل على **دائرة متنقلة** بنطاق خدمة ودبوس مؤقت «هنا اليوم» بدل الدبوس الثابت.

هذا الملف يصف جهة التطبيق (المسار 2 من الحزمة). الخادم (`server/biz_onboard.js`، المسار 1) ولوحة الإدارة (المسار 3) في ملفاتهما. العقد المشترك مكرّر هنا باختصار حيث يلزم.

### الشاشات والمفاتيح

### معالج التسجيل `lib/pages/business/register_circle_page.dart`
`RegisterCirclePage` (`openRegisterCircle(context)`): سؤال واحد في كل شاشة، شريط تقدّم «1 من 6» (`reg-progress`)، سهم رجوع (`reg-back`؛ من الخطوة الأولى يغلق المعالج)، قائمة قابلة للتمرير مع لوحة المفاتيح بمقاس 390×844، وزر سفلي ثابت `reg-next` (في الخطوة الأخيرة `reg-submit`).

| الخطوة | المحتوى | المفاتيح |
|---|---|---|
| 1 نوع النشاط | بطاقات كل الفئات بأيقوناتها (الشائعة أولاً: مقهى، مطعم، متجر، خدمات وورش، صالون وتجميل، عيادة، ترفيه، ثم براند، فندق، تأجير سيارات، سينما، مستشفى، شركة، جامعة، مطار، أخرى) | `reg-cat-<key>` |
| 2 الاسم | الاسم العربي (2–60) واللاتيني اختياري. بعد 600 مللي ثانية من آخر حرف يُستدعى `GET /biz/register/check?name&lat&lng` (الموقع إن كان معروفاً من قبل أو الإذن ممنوحاً؛ لا يظهر حوار إذن الموقع هنا، فطلبه في خطوة الحضور حيث يُشرح سببه، وبلا موقع يفحص الخادم الاسم وحده). التكرارات تظهر تحت «هل هذه دائرتك؟» بطاقة لكل دائرة؛ بلا مالك → زر «هذه دائرتي، استلمها» يفتح حوار الاستلام الموجود (`askText` بنص مسبق) ثم `claimBiz` وينهي المعالج بصفحة «طلبك قيد المراجعة» (`reg-claimed`)؛ ولها مالك → «لها مالك» وقفل. | `reg-name`، `reg-name-latin`، `reg-dup-<id>`، `reg-claim-<id>`، `reg-claimed-close` |
| 3 الشعار (إلزامي) | من الجهاز أو الكاميرا (`pickImage` → `uploadMedia`)، معاينة، و«التالي» معطّل حتى يُرفع | `reg-logo-preview`، `reg-logo-pick`، `reg-logo-camera`، `reg-logo-required` |
| 4 الحضور | «مكان ثابت» / «أذهب إلى العميل». الثابت: «أنا في المكان الآن» (`DeviceLocation.current`) + بطاقة ملخص الإحداثيات + «تعديل على الخريطة» (صفحة خريطة تُبنى عند الطلب). المتنقل: المركز = موقع الجهاز تلقائياً (أو جدة)، شريط نطاق 2–50 كم (افتراضي 15)، أحياء اختيارية (حتى 10). | `reg-presence-fixed`، `reg-presence-mobile`، `reg-locate`، `reg-point`، `reg-map-edit`، `reg-loc-error`، `reg-radius`، `reg-radius-label`، `reg-district`، `reg-district-add`، `reg-district-<name>` |
| 5 الجوال | حقل واحد بتحقق سعودي (05XXXXXXXX، 5XXXXXXXX، +9665…، 009665…، والأرقام العربية تُقبل) وخطأ مضمّن «رقم جوال سعودي غير صحيح»؛ يُرسل بصيغة `+9665XXXXXXXX` | `reg-phone` |
| 6 الصفة | «صاحب النشاط» / «مدير مفوض» + ملخص ثم «سجّل الدائرة» → `POST /biz/register` | `reg-role-owner`، `reg-role-manager`، `reg-submit` |
| جاهزة | «دائرتك جاهزة وتظهر على الخريطة الآن»، رمز QR ورابط `/c/<id>` مع زر مشاركة (`shareLink`)، وثلاثة مخارج: «أكمل بيانات الدائرة» (اللوحة)، «وثّق دائرتك لتبدأ البيع» (صفحة التوثيق)، «اكتفيت الآن» | `reg-done`، `reg-qr`، `reg-link`، `reg-share`، `reg-done-dashboard`، `reg-done-verify`، `reg-done-close` |

جسم التسجيل: `{ category, nameAr, name?, logoUrl, presence, lat, lng, radiusKm? (متنقل)، districts? (متنقل)، phone, role }`. بعد النجاح تُبطل `myBusinessesProvider` و`mapBizProvider` و`bizListProvider`.

### صفحة التوثيق `lib/pages/business/owner/verify_circle_page.dart`
`VerifyCirclePage(bizId)` (`openVerifyCircle`): تقرأ `bizCompletenessProvider(id)` (يسكن هنا لأن `biz_providers.dart` خارج نطاق هذا المسار) وتعرض بحسب `verification.status`:
- **none** → النموذج: رقاقتا نوع الكيان مع سطر لكل منهما (`verify-kind-cr`، `verify-kind-freelance`)، حقل الرقم (`verify-number`؛ سجل تجاري 10 أرقام، عمل حر 8–20 حرفاً/رقماً، الأرقام العربية تُحوَّل والمسافات والشرطات تُزال فـ«FL-12345678» يُقبل ويُرسل `FL12345678`، والسبب يظهر تحت الحقل أثناء الكتابة لأن الزر معطّل حينها)، صورة المستند (`verify-doc-pick`، `verify-doc-camera`، `verify-doc-preview`؛ إلزامية)، و`verify-submit` معطّل حتى يصح الرقم ويُرفع المستند → `POST /biz/:id/verification { entityKind, entityNumber, docUrl }`.
- **pending** → `verify-pending` «قيد المراجعة من الإدارة، عادةً خلال يوم عمل» مع النوع وتاريخ الإرسال.
- **approved** → `verify-approved` «دائرتك موثّقة» مع النوع وتاريخ القرار.
- **rejected** → `verify-rejected` مع «السبب: …» وزر «أعد الإرسال» (`verify-resubmit`) يُظهر النموذج وزره «أعد الإرسال».

`invalidateCompleteness(ref, id)` تبطل الاكتمال وكل ما يخص الدائرة (`invalidateBizAll`).

### لوحة التحكم `business_dashboard_page.dart`
- أعلى «نظرة عامة»: بطاقة الاكتمال `completeness-card`: رقاقة الدرجة (`completeness-tier`: منشورة/مكتملة/موثّقة/نشطة)، شريط ونسبة (`completeness-percent`)، سطر كهرماني `completeness-locked` «البيع والحجز مقفلان حتى التوثيق» حين `canSell=false`، بطاقة الخطوة التالية `completeness-next` «الخطوة التالية: <title> · <minutes> دقيقة» وزرها `completeness-go` يفتح التبويب (`BusinessDashboardPage.tabIndexFor`: catalog=2، offers=3، posts=4، profile=7) أو صفحة التوثيق (`verify`)، وقائمة بنود بعلامات (الشعار، الموقع، الجوال، ساعات العمل أو نطاق الخدمة للمتنقلة، الوصف، الصور n/3، الكتالوج n/3، التوثيق). تُخفى صامتة إن فشل الجلب (خادم قديم).
- لافتة `here-active` «أنت هنا حتى HH:MM» مع «إنهاء» (`here-end-inline`) أثناء سريان الدبوس.
- إجراءات سريعة: `here-today` («أنا هنا اليوم» أو «أنت هنا حتى …») تفتح ورقة بساعات (`here-h-2/4/6/8/12`) وزر `here-set` → `DeviceLocation.current` → `POST /biz/:id/here { lat, lng, hours }`؛ وأثناء السريان تعرض `here-until` و«إنهاء» `here-end` → `DELETE /biz/:id/here`. الزر ظاهر للمتنقلة والثابتة (مقهى في بازار). و`verify-entry` «التوثيق» يفتح صفحة التوثيق.
- تبويب «الملف»: سطرا «التوثيق» و«الحضور» وزر `profile-verify`.

### الصفحة العامة `business_page.dart`
شارات في الترويسة: `badge-verified` «موثّق»، `badge-mobile` «متنقل · يخدم ضمن N كم»، `badge-here` «هنا اليوم حتى HH:MM». للمتنقلة يحل `info-service-area` («يخدم ضمن N كم · الأحياء») محل سطر العنوان، ويظهر `info-here` أثناء الدبوس. `bizErrText('not-verified')` = «هذه الدائرة لم تُوثَّق بعد فلا يمكن الطلب منها الآن».

### مداخل أخرى
- `circles_page.dart`: لافتة `register-banner` «هل تملك نشاطاً؟ سجّل دائرتك في دقيقتين» أعلى تبويب «اكتشف»، وزر `register-mine` «سجّل نشاطك» في الحالة الفارغة لتبويب «دوائري». ومنذ 22 أكتوبر 2026 الزر العائم `circles-fab` «دائرة جديدة» يفتح أولاً ورقة «ما نوع الدائرة؟» (`new-circle-biz` إلى المعالج، `new-circle-community` إلى ورقة «دائرة مجتمع جديدة») لأن المالك أنشأ دائرة مجتمع وهو يقصد نشاطه؛ وفي مقطع «تجارية» يصبح الزر «سجّل نشاطك» إلى المعالج مباشرة.
- `my_businesses_page.dart`: الزر العائم `my-biz-register` يفتح المعالج (المحرّر القديم `business_editor.dart` يبقى للتعديل من اللوحة).
- `notify_open.dart`: `biz_verified` و`biz_verification_rejected` → `VerifyCirclePage` للدائرة (أيقونتان ولونان خاصان؛ `biz_verification` للإدارة أيقونة فقط، وجهتها في مسار الإدارة).

### النماذج `lib/api/biz_models.dart`
- `BizCategory` يكسب `shop` (متجر)، `services` (خدمات وورش)، `salon` (صالون وتجميل)، `clinic` (عيادة)، `entertainment` (ترفيه)، `other` (أخرى) بأنواع عناصر product/product/clinic/clinic/showtime/info؛ `of(مجهول)` ما زال يعود إلى `brand`. الثلاث `switch` الحصرية (`_itemNoun` في اللوحة، `_addLabel` في الكتالوج، تلميح القطاع في المحرّر) أُكملت.
- `Biz` يكسب `presence` (fixed|mobile)، `serviceArea` (`ServiceArea{lat,lng,radiusKm,districts}` ولها `label`)، `here` (`HerePin{lat,lng,until}` ولها `active` و`label`)، `verificationStatus`، `canSell`، `tier`، `entityKind`، `phoneVerified`؛ ومساعدات `isMobile`، `hereActive`، `tierLabel`، `verificationLabel`. القيم الافتراضية تجعل الردود القديمة (بلا هذه الحقول) تُقرأ كما كانت (`canSell` يرث `verified`).
- جديد: `Completeness{tier, percent, canSell, checks: CompletenessChecks, next: NextStep?, verification: VerificationInfo}`، `VerificationInfo{status, entityKind, entityNumber?, reason?, docUrl?, submittedAt, reviewedAt}`، `RegisterCheck{duplicates: [RegisterDuplicate{id,name,nameAr,category,distanceKm,ownerId,logoUrl}]}`، `Registered{biz, completeness}`.
- مساعدات: `normalizeSaudiMobile`، `latinDigits`، `clockLabel`، `tierLabelOf`، `verificationLabelOf`، `entityKindLabel`.

### الواجهة `lib/api/biz_api.dart` (`BizOnboardApi`)
`registerCheck(name, lat, lng)`، `registerBiz(body)`، `bizCompleteness(id)`، `submitVerification(id, entityKind, entityNumber, docUrl)`، `setHere(id, lat, lng, hours)`، `clearHere(id)`.

### تحويل الأخطاء
`registerErrText`: bad-category «اختر نوع النشاط»، bad-name «اكتب اسماً عربياً من حرفين إلى 60 حرفاً»، logo-required «الشعار إلزامي…»، bad-presence، bad-location «حدّد موقع الدائرة»، bad-radius «نطاق الخدمة بين 2 و50 كم»، bad-phone «رقم الجوال غير صحيح؛ اكتبه بصيغة 05XXXXXXXX»، bad-role، too-many «وصلت إلى الحد الأقصى من الدوائر (20)»، suspended. `registerErrStep` يعيد المعالج إلى خطوة الحقل المرفوض. `verifyErrText`: already-approved، bad-entity-kind، bad-entity-number، doc-required، forbidden. الكود يُقرأ من `body.error` ومن النص معاً.

### الخادم الوهمي `tools/dev/mockapi.mjs`
كتلة واحدة `// ---- circle registration (app)` بعد سطر توجيه الفنادق: فحص التكرار من بذرة الدوائر ضمن 3 كم، التسجيل بكل أكواد التحقق (الدائرة تُدفع إلى `SEED`/`OWNED` فتظهر في `/biz` و`/biz/mine`)، الاكتمال محسوباً بالأوزان نفسها، التوثيق (قيد المراجعة بلا قرار؛ القرار من كتلة الإدارة حين تُضاف)، و«هنا اليوم». الحالة على `globalThis.__regState`.

### الاختبارات
- `test/register_circle_test.dart` (8): النماذج والتطبيع؛ المسار الثابت كاملاً (يؤكد الجسم: الفئة، الاسم، الشعار المرفوع، الموقع، الجوال `+966…`، الصفة) وصفحة النجاح ثم اللوحة؛ المسار المتنقل (المركز من الجهاز، النطاق 15، الأحياء)؛ الشعار يمنع المتابعة؛ التكرار → الاستلام → «طلبك قيد المراجعة»؛ التحقق (جوال خاطئ مضمّن، اسم قصير، خطأ خادم يعود إلى خطوته)؛ لافتة الدوائر والحالة الفارغة؛ زر «نشاطي التجاري».
- `test/circle_completeness_test.dart` (7): بطاقة الاكتمال وزر الخطوة يبدّل التبويب أو يفتح التوثيق؛ صفحة التوثيق (البوابات، الجسم، الحالات الثلاث، إعادة الإرسال)؛ ورقة «هنا اليوم» والحالة السارية والإنهاء؛ شارات الصفحة العامة ونطاق الخدمة وخطأ «لم تُوثَّق»؛ توجيه الإشعارات.
- كلا الملفين بـ `MockClient` ومفاتيح `Key`، مع `DeviceLocation.override` و`pickImageOverride`.

### ما بقي
- توثيق الجوال برسالة نصية (`phoneVerified` يُعرض فقط؛ لا مزوّد SMS بعد).
- التحقق التلقائي من السجل التجاري ووثيقة العمل الحر عبر واثق (الآن يدوي من لوحة الإدارة، مسار 3).
- صفحة الخريطة في المعالج تُبنى عند الطلب فقط؛ لم تُغطَّ باختبار ودجات (بلاطات الخريطة شبكية).
- التحقق الحي على naslife.app ولقطات المالك بعد دمج المسارات الثلاثة ونشر الخادم.

## الخريطة والصف ولوحة الإدارة

جزء من حزمة «تسجيل الدوائر الموثّقة» (أكتوبر 2026). هذا الملف يغطي الجانب الثالث منها: كيف تظهر الدائرة المتنقلة ودبّوس «هنا اليوم» على الخريطة والصف، وكيف يراجع المدير طلبات التوثيق ويقرّر فيها، وعدّادات التوثيق في «نظرة عامة». التسجيل نفسه والاكتمال (`server/biz_onboard.js` وشاشات `lib/pages/business/`) موثّقان في ملفيهما.

### القرارات التي يبني عليها هذا الجزء

- الدائرة تظهر على الخريطة فور تسجيلها؛ **البيع والحجز وربط الدفع بعد التوثيق فقط** (سجل تجاري أو وثيقة عمل حر) ويقرّره المدير يدوياً من اللوحة الآن، وآلياً عبر وثّق لاحقاً.
- صاحب العمل الحر بلا مقر يسجّل **دائرة متنقلة**: منطقة خدمة (مركز ونصف قطر 2–50 كم وأحياء) بدل دبّوس ثابت، ودبّوس مؤقت «هنا اليوم» حين يقف في مكان.

### الخريطة (`lib/pages/map/map_page.dart`)

قواعد الرسم لكل دائرة يعيدها `GET /biz` ضمن حدود الخريطة:

| الحالة | ما يُرسم |
|---|---|
| `presence: mobile` مع `serviceArea` وبلا دبّوس مؤقت ساري | **قرص شفاف** (`CircleLayer`، مفتاحه `map-service-areas`) عند المركز بنصف القطر بالأمتار (`radiusKm × 1000`، `useRadiusInMeter`)، بلون الدوائر بشفافية 10٪ وحدّ 38٪، **بلا دبّوس**. |
| `here` ساري (`until` في المستقبل) — ثابتة أو متنقلة | دبّوس الدائرة المعتاد **عند موقع الدبّوس المؤقت** لا موقع الدائرة، مع **شارة ساعة** صغيرة في زاويته (`map-here-badge`) وتلميح «هنا اليوم حتى HH:MM» بالتوقيت المحلي (`hereUntilLabel`). المتنقلة تحتفظ بقرصها أيضاً. |
| `here` منتهٍ أو غائب، ودائرة ثابتة | الدبّوس المعتاد عند موقع الدائرة (لا تغيير). |

- اللمس: الدبّوس المؤقت يفتح ورقة الدائرة كأي دبّوس (ومنها «دخول الدائرة»)، ولمسة داخل القرص تفعل الشيء نفسه عبر `hitNotifier` الطبقة؛ خارج الأقراص يفشل اختبار اللمس فيبقى سحب الخريطة كما هو، والدبابيس فوق الأقراص تفوز باللمسة. في الرئيسية إن كانت الدائرة في «الصف» تقفز البطاقة إليها بدل فتح الورقة.
- **الدبّوس الاحتياطي من الصف**: بطاقة `circle` في الصف تضيف دبّوس دائرة بمفتاح طبقة الدوائر نفسه (`business:<id>`) ونهاية الدبّوس من `payload.until`، فإن كانت الدائرة ضمن الحدود يفوز دبّوس الطبقة (لا تكرار)، وإلا يبقى للبطاقة دبّوس يُبرز عند اختيارها.
- التجميع والأسماء (`map_cluster.dart`، `map_labels.dart`) لم يُمسّا: الدبّوس المؤقت عنصر `business` عادي يحمل `Business` بموقع الدبّوس، فتظهر تسميته وتُحتسب في اللوحة كالمعتاد.

### قراءة الحضور (`BizPresence` و`mapCirclesProvider`)

نموذج `Biz` في `lib/api/biz_models.dart` تملكه حزمة التسجيل، فحضور الدائرة يُقرأ هنا من JSON الخام لطلب `/biz` إلى نموذج صغير `BizPresence` (`id`، `mobile`، `area {lat,lng,radiusKm}`، `here {lat,lng,until}`)؛ الثابتة بلا دبّوس مؤقت لا تُحفظ. الخريطة تطلب `/biz?bbox=` **مرة واحدة** لكل تغيير في الحدود عبر `mapCirclesProvider` (في `map_page.dart`) الذي يحلّل الحمولة نفسها إلى `MapCircles {circles: List<Biz>, presence: Map<String, BizPresence>}`؛ فلا طلب ثانٍ للحضور، ولا إطار تصل فيه قائمة جديدة مع حضور قديم (كان يضع دبّوساً عند مركز المتنقلة قبل القرص، أو عند موقع الدائرة الأصلي قبل القفز إلى «هنا اليوم»). زر «تحديث» يعيد جلبه. **ملاحظة للمدمج**: الخريطة لم تعد تقرأ `mapBizProvider` في `lib/state/biz_providers.dart`، فتبطيل `invalidateBizAll` له لا يصل إلى الخريطة الآن (تتحدّث الدوائر عند تغيّر الحدود أو زر «تحديث»)؛ عند دمج حزمة التسجيل يُجعل `mapBizProvider` مشتقاً من `mapCirclesProvider` (أو يُنقل الأخير إلى `biz_providers.dart`) فيعود تعديل الدائرة من لوحتها يحدّث الخريطة فوراً، وعند إضافة `presence/serviceArea/here` إلى `Biz` يُحذف `BizPresence` ويُقرأ الحضور من `Biz`.

### الصف (`lib/api/row_api.dart`، `lib/pages/home/row_deck.dart`)

- نوع جديد `circle` من `server/row.js` للدوائر ذات دبّوس مؤقت ساري ضمن نصف القطر: `{ kind: "circle", id, refId: biz.id, title, subtitle: "هنا اليوم حتى HH:MM · <الفئة>", imageUrl: logoUrl, lat, lng, distanceKm, act: "زيارة", payload: { here: true, until } }`.
- البطاقة: اسم النوع «هنا اليوم»، الشعار صورتها (`imageUrl` أو `logoUrl` احتياطاً)، السطر الثاني والمسافة كالمعتاد، الزر «زيارة» يفتح صفحة الدائرة (`openBusiness`). `pinKey` للدائرة `business:<refId>` حتى يُبرز دبّوس الطبقة.
- **نوع غير معروف** (مستقبلي) لا يُسقط الصف: بطاقة افتراضية بتسمية «لحظة» وزر «شاهد» ولون اللحظة، وزرها لا يفعل شيئاً.

### الإدارة: قسم «التوثيق» (`lib/pages/admin/admin_biz.dart`)

صفحة الدوائر صارت قسمين بزر مقسّم (`biz-segments`): «الدوائر» (القائمة وطلبات الملكية كما كانت) و«التوثيق». القسم المفتوح في `adminBizSegmentProvider` حتى تفتحه بطاقة النظرة العامة مباشرة.

طابور التوثيق (`GET /adminapi/biz/verifications?status=`) بفلاتر بانتظار القرار / موثّقة / مرفوضة / الكل (`verif-filter-<status>`). كل بطاقة (`verif-row-<bizId>`):

1. الشعار والاسم وحالة الطلب (`verif-status-<bizId>`)، الفئة · الحضور (موقع ثابت / دائرة متنقلة) · المالك، ووقت التقديم.
2. نوع الكيان ورقمه (`verif-entity-<bizId>`: «سجل تجاري: 4030…» أو «وثيقة عمل حر: …») قابل للتحديد، وزر نسخ (`verif-copy-<bizId>`).
3. مصغّرة المستند (`verif-doc-<bizId>`) تفتح الصورة كاملة بتكبير (`verif-doc-view`).
4. «استعلام رسمي» (`verif-lookup-<bizId>`) يفتح `lookupUrl` من الخادم في متصفح خارجي: صفحة الاستعلام عن السجل التجاري لدى وزارة التجارة للسجل، وصفحة التحقق من وثيقة العمل الحر للوثيقة؛ ثابتان في `biz_onboard.js` ويقبلان التجاوز من إعدادات المنصة `crLookupUrl` / `freelanceLookupUrl`. الاختبارات تعترض الفتح بـ `LegalLinks.openOverride`.
5. للمعلّقة فقط: **«مطابق»** (`verif-approve-<bizId>`) يعتمد فوراً، و**«مرفوض»** (`verif-reject-<bizId>`) يطلب سبباً إلزامياً (3–300 حرفاً؛ الفارغ يُرفض محلياً برسالة) ويرسله. القرار `POST /adminapi/biz/:id/verification/approve|reject` يعدّل `verification.status` و`biz.verified` ويُشعر المالك (`biz_verified` / `biz_verification_rejected` مع السبب) ويُسجَّل في سجل الإجراءات. بعد القرار تُعاد قراءة الطابور والنظرة العامة وقائمة الدوائر وتفاصيل الدائرة، مع رسالة نجاح. `409 already-approved` → «هذه الدائرة موثّقة أصلاً».

زر «توثيق / سحب التوثيق» القديم في بطاقة الدائرة بقي ويكتب الحالة نفسها من الخادم.

### النظرة العامة: بطاقة «توثيق بانتظار القرار»

- البطاقة (`tile-verifications`) تعرض عدد الطلبات المعلّقة بلون كهرماني حين يكون أكبر من صفر، وتلميحاً بمستويات الاكتمال «منشورة · مكتملة · موثّقة · نشطة»، ولمسها يفتح قسم «التوثيق» في الدوائر.
- الخادم (`server/admin.js`، `GET /adminapi/overview`): `circles.pendingVerifications` و`circles.tiers {published, complete, verified, active}` تُحسب عند الطلب بعد فحص `information_schema` لعمود `biz.verification` (وجداول `biz_offers`/`biz_posts`/`biz_items`)؛ قبل وصول العمود تعود أصفاراً بلا خطأ. **المستويات تقريبية** حتى يُشارَك حساب الاكتمال الدقيق من `biz_onboard.js`: منشورة = نشطة غير مخفية؛ مكتملة = ساعات (أو منطقة خدمة للمتنقلة) ووصف ≥ 20 حرفاً و3 عناصر نشطة (بلا شرط الصور الثلاث)؛ موثّقة = مكتملة ومعتمدة (`verification.status = approved` أو `verified`)؛ نشطة = موثّقة وعرض نشط ومنشور خلال 30 يوماً.

### الخادم الوهمي (`tools/dev/mockapi.mjs`)

كتلة «circle presence + verification queue (stream 3)» بعد دالة الفنادق وسطر تحويل بعد تحويل الفنادق: ستاربكس «هنا اليوم» ست ساعات عند الكورنيش، ونايكي دائرة متنقلة بمنطقة 6 كم حول الزهراء؛ الحقول تُحقن في ردود `GET /biz` و`GET /adminapi/overview` دون لمس دوالهما، وبطاقة `circle` تُضاف أول «الصف» (سطر واحد في `rowItems`). طابور التوثيق في الذاكرة بأربعة طلبات (معلّقان وموثّق ومرفوض) مع `409 already-approved` و`400 reason-required`.

### الاختبارات

- `test/map_presence_test.dart`: تحليل `BizPresence`، نص التلميح، القرص بنصف قطر 5000 م بلا دبّوس للمتنقلة، الدبّوس عند موقع «هنا اليوم» بشارة وتلميح، تجاهل الدبّوس المنتهي، طلب `/biz` واحد لكل حدود، وصول القائمة والحضور في الإطار نفسه من حمولة محجوزة (بلا دبّوس عند مركز المتنقلة أو موقع الدائرة الأصلي)، لمس الدبّوس والقرص يفتح ورقة الدائرة، وفي الرئيسية فوز دبّوس الطبقة على الاحتياطي ثم الاحتياطي حين تغيب الطبقة.
- `test/row_deck_test.dart`: تحليل `circle` ونوع غير معروف، بطاقة «هنا اليوم» وزر «زيارة» يفتح صفحة الدائرة، والبطاقة الافتراضية للنوع غير المعروف.
- `test/admin_verifications_test.dart`: القائمة والحقول، «مطابق»، «مرفوض» بسبب إلزامي (الحمولة)، الاستعلام الرسمي عبر البديل، النسخ، الفلاتر، وبطاقة النظرة العامة وتحويلها إلى القسم.
- `server/test/harness_admin_overview.mjs` (`NASLIFE_TEST_DB=naslife_test_regmap server/test/run.sh harness_admin_overview.mjs`): الحقول بأصفار قبل العمود، ثم العدّ والمستويات بعد إضافته، واعتماد معلّقة ينقلها إلى الموثّقة، والمخفية ليست منشورة.

### ملاحظات الدمج

- `BizPresence` في `map_page.dart` و`adminBizCategoryLabel` في `admin_biz.dart` (أسماء الفئات الست الجديدة) تكراران مؤقتان لما يجب أن يعيش في `biz_models.dart`؛ عند دمج حزمة التسجيل تُقرأ الحقول من `Biz` وتُستخدم `BizCategory.of(key).label` وتُحذف النسختان. و`mapBizProvider` في `biz_providers.dart` صار بلا قارئ: يُشتق من `mapCirclesProvider` حتى يصل `invalidateBizAll` إلى الخريطة (انظر «قراءة الحضور»).
- `RowItem.pinKey` للنوع `circle` يعتمد على أن `refId` هو معرّف الدائرة كما في العقد.
- مسارات الإشعارات `biz_verification` (للمدير → قسم التوثيق) و`biz_verified` / `biz_verification_rejected` (للمالك → لوحة الدائرة) تُضاف في `lib/core/notify_open.dart` من حزمة التسجيل؛ القسم جاهز عبر `adminBizSegmentProvider = 'verifications'`.

## ما فُعل عند الدمج (21 أكتوبر 2026)

1. الخريطة تقرأ الحضور من نموذج `Biz` نفسه (`BizPresence.fromBiz`) و`mapCirclesProvider` مشتق من `mapBizProvider`، فطلب `/biz` واحد لكل تغيير حدود و`invalidateBizAll` يحدّث الخريطة فور تعديل الدائرة من لوحتها.
2. أسماء الفئات في الإدارة من `BizCategory.of(key).label` بعد إضافة الفئات الست إلى التعداد.
3. إشعار `biz_verification` للمشرف يفتح قسم الدوائر على مقطع «التوثيق» مباشرة (`openNotification` يضبط `adminBizSegmentProvider`)، و`biz_verified`/`biz_verification_rejected` يفتحان صفحة التوثيق في لوحة الدائرة.
