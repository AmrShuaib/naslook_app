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

## ما تتشاركه الإضافات على `globalThis`

`naslifeBizCategories` (المجموعة)، `naslifeBizCreate(uid, body, extra)`، `naslifeBizLoadFull(id, uid)` (صف بالأعمدة المحسوبة)، `naslifeBizOut(row, extra)`، `naslifeBizHelpers` (`verStatus, verOf, hereOf, tierOf, isComplete, hoursOk, serviceAreaOf, canManage, canOperate, canOwn, roleFor, isAdmin, isSuspended, CATEGORY_AR`)، و`naslifeBizOwnersNear(lat, lng)` من `biz_onboard.js`.

## الاختبار

```
NASLIFE_TEST_DB=naslife_test_reg server/test/run.sh harness_biz_onboard.mjs
```

تغطي: وحدات الجوال والفئات والأوزان، كل رمز خطأ في التسجيل، المسار السعيد الثابت والمتنقل، فحص التكرار (قريب نعم، 10 كم لا)، المستويات الأربعة والنسبة والخطوة التالية خطوة خطوة، أخطاء إرسال التوثيق وإخفاء بيانات الكيان، قائمة الإدارة وتجاوز رابط الاستعلام والرفض والاعتماد والإشعارات والسجل وإعادة الإرسال، بوابة البيع قبل الاعتماد وبعده وبعد السحب، المفتاح القديم، دبوس «هنا اليوم» (أخطاؤه، أثره على `GET /biz` و`GET /biz/:id` والصف، انتهاؤه ومسحه)، تغطية النطاق، خطّاف «أبحث عن»، الفئات الجديدة وأنواع أصنافها، وحد الـ20.

حزم أثّرت فيها بوابة البيع فعُدّلت بسطر اعتماد قبل الطلبات المدفوعة: `harness.mjs`، `harness_offers.mjs`، `harness_chat_cards.mjs`، `harness_notify.mjs`.

## ملاحظات ومؤجّلات

- `PATCH /adminapi/biz/:id {verified}` في `admin.js` ما زال يقلب العمود `verified` وحده دون `verification.status` (الملف خارج هذه الحزمة)؛ ينبغي توجيهه إلى مسار القرار الجديد.
- توثيق الجوال (`phone_verified`) مؤجّل كما في الملف الشخصي.
- «وثقة» للتحقق الآلي من السجل التجاري لاحقاً: يكفي أن يستدعي مسار الاعتماد نفسه.
