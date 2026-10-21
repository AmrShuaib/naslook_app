# تسجيل الدائرة الموثّق — جهة التطبيق (صاحب النشاط)

**القرار** (المالك، أكتوبر 2026): أي نشاط محلي يسجّل دائرته بنفسه في ست خطوات وتظهر على الخريطة **فوراً**؛ الشعار إلزامي؛ البيع والحجز وربط الدفع تُفتح فقط بعد توثيق **سجل تجاري** أو **وثيقة العمل الحر** (يدوياً من لوحة الإدارة الآن، وتلقائياً عبر واثق لاحقاً)؛ نظام اكتمال واحد يقود كل دائرة إلى الاكتمال؛ والمستقل بلا مقر يحصل على **دائرة متنقلة** بنطاق خدمة ودبوس مؤقت «هنا اليوم» بدل الدبوس الثابت.

هذا الملف يصف جهة التطبيق (المسار 2 من الحزمة). الخادم (`server/biz_onboard.js`، المسار 1) ولوحة الإدارة (المسار 3) في ملفاتهما. العقد المشترك مكرّر هنا باختصار حيث يلزم.

## الشاشات والمفاتيح

### معالج التسجيل `lib/pages/business/register_circle_page.dart`
`RegisterCirclePage` (`openRegisterCircle(context)`): سؤال واحد في كل شاشة، شريط تقدّم «1 من 6» (`reg-progress`)، سهم رجوع (`reg-back`؛ من الخطوة الأولى يغلق المعالج)، قائمة قابلة للتمرير مع لوحة المفاتيح بمقاس 390×844، وزر سفلي ثابت `reg-next` (في الخطوة الأخيرة `reg-submit`).

| الخطوة | المحتوى | المفاتيح |
|---|---|---|
| 1 نوع النشاط | بطاقات كل الفئات بأيقوناتها (الشائعة أولاً: مقهى، مطعم، متجر، خدمات وورش، صالون وتجميل، عيادة، ترفيه، ثم براند، فندق، تأجير سيارات، سينما، مستشفى، شركة، جامعة، مطار، أخرى) | `reg-cat-<key>` |
| 2 الاسم | الاسم العربي (2–60) واللاتيني اختياري. بعد 600 مللي ثانية من آخر حرف يُستدعى `GET /biz/register/check?name&lat&lng` (موقع الجهاز إن توفر). التكرارات تظهر تحت «هل هذه دائرتك؟» بطاقة لكل دائرة؛ بلا مالك → زر «هذه دائرتي، استلمها» يفتح حوار الاستلام الموجود (`askText` بنص مسبق) ثم `claimBiz` وينهي المعالج بصفحة «طلبك قيد المراجعة» (`reg-claimed`)؛ ولها مالك → «لها مالك» وقفل. | `reg-name`، `reg-name-latin`، `reg-dup-<id>`، `reg-claim-<id>`، `reg-claimed-close` |
| 3 الشعار (إلزامي) | من الجهاز أو الكاميرا (`pickImage` → `uploadMedia`)، معاينة، و«التالي» معطّل حتى يُرفع | `reg-logo-preview`، `reg-logo-pick`، `reg-logo-camera`، `reg-logo-required` |
| 4 الحضور | «مكان ثابت» / «أذهب إلى العميل». الثابت: «أنا في المكان الآن» (`DeviceLocation.current`) + بطاقة ملخص الإحداثيات + «تعديل على الخريطة» (صفحة خريطة تُبنى عند الطلب). المتنقل: المركز = موقع الجهاز تلقائياً (أو جدة)، شريط نطاق 2–50 كم (افتراضي 15)، أحياء اختيارية (حتى 10). | `reg-presence-fixed`، `reg-presence-mobile`، `reg-locate`، `reg-point`، `reg-map-edit`، `reg-loc-error`، `reg-radius`، `reg-radius-label`، `reg-district`، `reg-district-add`، `reg-district-<name>` |
| 5 الجوال | حقل واحد بتحقق سعودي (05XXXXXXXX، 5XXXXXXXX، +9665…، 009665…، والأرقام العربية تُقبل) وخطأ مضمّن «رقم جوال سعودي غير صحيح»؛ يُرسل بصيغة `+9665XXXXXXXX` | `reg-phone` |
| 6 الصفة | «صاحب النشاط» / «مدير مفوض» + ملخص ثم «سجّل الدائرة» → `POST /biz/register` | `reg-role-owner`، `reg-role-manager`، `reg-submit` |
| جاهزة | «دائرتك جاهزة وتظهر على الخريطة الآن»، رمز QR ورابط `/c/<id>` مع زر مشاركة (`shareLink`)، وثلاثة مخارج: «أكمل بيانات الدائرة» (اللوحة)، «وثّق دائرتك لتبدأ البيع» (صفحة التوثيق)، «اكتفيت الآن» | `reg-done`، `reg-qr`، `reg-link`، `reg-share`، `reg-done-dashboard`، `reg-done-verify`، `reg-done-close` |

جسم التسجيل: `{ category, nameAr, name?, logoUrl, presence, lat, lng, radiusKm? (متنقل)، districts? (متنقل)، phone, role }`. بعد النجاح تُبطل `myBusinessesProvider` و`mapBizProvider` و`bizListProvider`.

### صفحة التوثيق `lib/pages/business/owner/verify_circle_page.dart`
`VerifyCirclePage(bizId)` (`openVerifyCircle`): تقرأ `bizCompletenessProvider(id)` (يسكن هنا لأن `biz_providers.dart` خارج نطاق هذا المسار) وتعرض بحسب `verification.status`:
- **none** → النموذج: رقاقتا نوع الكيان مع سطر لكل منهما (`verify-kind-cr`، `verify-kind-freelance`)، حقل الرقم (`verify-number`؛ سجل تجاري 10 أرقام، عمل حر 8–20 حرفاً/رقماً، الأرقام العربية تُحوَّل)، صورة المستند (`verify-doc-pick`، `verify-doc-camera`، `verify-doc-preview`؛ إلزامية)، و`verify-submit` معطّل حتى يصح الرقم ويُرفع المستند → `POST /biz/:id/verification { entityKind, entityNumber, docUrl }`.
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
- `circles_page.dart`: لافتة `register-banner` «هل تملك نشاطاً؟ سجّل دائرتك في دقيقتين» أعلى تبويب «اكتشف»، وزر `register-mine` «سجّل نشاطك» في الحالة الفارغة لتبويب «دوائري».
- `my_businesses_page.dart`: الزر العائم `my-biz-register` يفتح المعالج (المحرّر القديم `business_editor.dart` يبقى للتعديل من اللوحة).
- `notify_open.dart`: `biz_verified` و`biz_verification_rejected` → `VerifyCirclePage` للدائرة (أيقونتان ولونان خاصان؛ `biz_verification` للإدارة أيقونة فقط، وجهتها في مسار الإدارة).

## النماذج `lib/api/biz_models.dart`
- `BizCategory` يكسب `shop` (متجر)، `services` (خدمات وورش)، `salon` (صالون وتجميل)، `clinic` (عيادة)، `entertainment` (ترفيه)، `other` (أخرى) بأنواع عناصر product/product/clinic/clinic/showtime/info؛ `of(مجهول)` ما زال يعود إلى `brand`. الثلاث `switch` الحصرية (`_itemNoun` في اللوحة، `_addLabel` في الكتالوج، تلميح القطاع في المحرّر) أُكملت.
- `Biz` يكسب `presence` (fixed|mobile)، `serviceArea` (`ServiceArea{lat,lng,radiusKm,districts}` ولها `label`)، `here` (`HerePin{lat,lng,until}` ولها `active` و`label`)، `verificationStatus`، `canSell`، `tier`، `entityKind`، `phoneVerified`؛ ومساعدات `isMobile`، `hereActive`، `tierLabel`، `verificationLabel`. القيم الافتراضية تجعل الردود القديمة (بلا هذه الحقول) تُقرأ كما كانت (`canSell` يرث `verified`).
- جديد: `Completeness{tier, percent, canSell, checks: CompletenessChecks, next: NextStep?, verification: VerificationInfo}`، `VerificationInfo{status, entityKind, entityNumber?, reason?, docUrl?, submittedAt, reviewedAt}`، `RegisterCheck{duplicates: [RegisterDuplicate{id,name,nameAr,category,distanceKm,ownerId,logoUrl}]}`، `Registered{biz, completeness}`.
- مساعدات: `normalizeSaudiMobile`، `latinDigits`، `clockLabel`، `tierLabelOf`، `verificationLabelOf`، `entityKindLabel`.

## الواجهة `lib/api/biz_api.dart` (`BizOnboardApi`)
`registerCheck(name, lat, lng)`، `registerBiz(body)`، `bizCompleteness(id)`، `submitVerification(id, entityKind, entityNumber, docUrl)`، `setHere(id, lat, lng, hours)`، `clearHere(id)`.

## تحويل الأخطاء
`registerErrText`: bad-category «اختر نوع النشاط»، bad-name «اكتب اسماً عربياً من حرفين إلى 60 حرفاً»، logo-required «الشعار إلزامي…»، bad-presence، bad-location «حدّد موقع الدائرة»، bad-radius «نطاق الخدمة بين 2 و50 كم»، bad-phone «رقم الجوال غير صحيح؛ اكتبه بصيغة 05XXXXXXXX»، bad-role، too-many «وصلت إلى الحد الأقصى من الدوائر (20)»، suspended. `registerErrStep` يعيد المعالج إلى خطوة الحقل المرفوض. `verifyErrText`: already-approved، bad-entity-kind، bad-entity-number، doc-required، forbidden. الكود يُقرأ من `body.error` ومن النص معاً.

## الخادم الوهمي `tools/dev/mockapi.mjs`
كتلة واحدة `// ---- circle registration (app)` بعد سطر توجيه الفنادق: فحص التكرار من بذرة الدوائر ضمن 3 كم، التسجيل بكل أكواد التحقق (الدائرة تُدفع إلى `SEED`/`OWNED` فتظهر في `/biz` و`/biz/mine`)، الاكتمال محسوباً بالأوزان نفسها، التوثيق (قيد المراجعة بلا قرار؛ القرار من كتلة الإدارة حين تُضاف)، و«هنا اليوم». الحالة على `globalThis.__regState`.

## الاختبارات
- `test/register_circle_test.dart` (8): النماذج والتطبيع؛ المسار الثابت كاملاً (يؤكد الجسم: الفئة، الاسم، الشعار المرفوع، الموقع، الجوال `+966…`، الصفة) وصفحة النجاح ثم اللوحة؛ المسار المتنقل (المركز من الجهاز، النطاق 15، الأحياء)؛ الشعار يمنع المتابعة؛ التكرار → الاستلام → «طلبك قيد المراجعة»؛ التحقق (جوال خاطئ مضمّن، اسم قصير، خطأ خادم يعود إلى خطوته)؛ لافتة الدوائر والحالة الفارغة؛ زر «نشاطي التجاري».
- `test/circle_completeness_test.dart` (7): بطاقة الاكتمال وزر الخطوة يبدّل التبويب أو يفتح التوثيق؛ صفحة التوثيق (البوابات، الجسم، الحالات الثلاث، إعادة الإرسال)؛ ورقة «هنا اليوم» والحالة السارية والإنهاء؛ شارات الصفحة العامة ونطاق الخدمة وخطأ «لم تُوثَّق»؛ توجيه الإشعارات.
- كلا الملفين بـ `MockClient` ومفاتيح `Key`، مع `DeviceLocation.override` و`pickImageOverride`.

## ما بقي
- توثيق الجوال برسالة نصية (`phoneVerified` يُعرض فقط؛ لا مزوّد SMS بعد).
- التحقق التلقائي من السجل التجاري ووثيقة العمل الحر عبر واثق (الآن يدوي من لوحة الإدارة، مسار 3).
- صفحة الخريطة في المعالج تُبنى عند الطلب فقط؛ لم تُغطَّ باختبار ودجات (بلاطات الخريطة شبكية).
- التحقق الحي على naslife.app ولقطات المالك بعد دمج المسارات الثلاثة ونشر الخادم.
