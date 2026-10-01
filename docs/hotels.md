# حجز الفنادق عبر Amadeus (`server/hotels.js`)

**القرار** (المالك، 1 أكتوبر 2026): تجربة ربط دائرة فندقية واحدة في جدة بفندق حقيقي لدى Amadeus Self-Service، فيحجز المستخدم غرفة من داخل ناس لايف بسعر وتوفر حقيقيين ويستلم رقم التأكيد في التطبيق، على نمط رحلة «واحد» المعتمدة (بطاقة ← شاشة اختيار ← تأكيد ← تذكرة). المال لا يمر عبر ناس لايف: بطاقة الضيف تُمرَّر إلى الفندق كضمان (Hotel Booking v2) والفندق هو من يحصّل، فلا تلامس التجربة قيود ساما على المحفظة.

**لماذا Amadeus**: تسجيل ذاتي ومفاتيح فورية، بيئة اختبار مجانية فيها الدورة كاملة (قائمة فنادق المدينة، عروض الغرف، الحجز بتأكيد)، والإنتاج بإضافة بطاقة دفع للحساب بلا شراكة ولا موافقة من الفندق. الطيران مؤجّل لأن إصدار التذاكر في الإنتاج يشترط مجمّع تذاكر.

## الخادم

إضافة مستقلة بجداولها الثلاثة: `hotel_settings` (المفاتيح من اللوحة)، `biz_hotel_links` (دائرة ← فندق Amadeus)، `hotel_bookings` (الحجوزات). سطر التسجيل `hotels.js` في `register.txt`.

### الإعدادات
- المفاتيح من لوحة الإدارة (`clientId`، `clientSecret`، `env` = `test`|`live`) ولها الأولوية على متغيرات البيئة `AMADEUS_CLIENT_ID`/`AMADEUS_CLIENT_SECRET`/`AMADEUS_ENV`. السر لا يُعاد أبداً (تلميح `ZyX…4321` فقط). الرمز (OAuth2 client_credentials) يُخزَّن في الذاكرة ويُجدَّد قبل انتهائه بدقيقة، ويسقط عند تغيير المفاتيح.
- بيئة الاختبار: `test.api.amadeus.com`، بطاقة تجريبية موثّقة (`TEST_CARD`: VI 4151289722471370 / 2028-08) يعيدها `/hotel/status` فيملأ التطبيق بها نموذج البطاقة. الإنتاج: `api.amadeus.com`.
- نداءات الشبكة عبر `globalThis.naslifeHotelFetch` (تُستبدل في الاختبار) أو `fetch`.

### المسارات العامة (الزائر مسموح)
- `GET /hotel/status` → `{ ok, configured, env, source, linked, testCard|null }`.
- `GET /biz/:id/hotel` → `{ linked:false }` أو `{ linked:true, bizId, hotelId, hotelName, cityCode, env, configured }`.
- `GET /biz/:id/hotel/offers?checkIn&checkOut&adults&rooms` → `{ hotel, checkIn, checkOut, nights, adults, rooms, currency:'SAR', env, available, offers:[…] }`. كل عرض مطبَّع عربياً: `roomName` (فئة Amadeus → «غرفة ديلوكس»، «جناح»…)، `bedType`، `beds`، `description`، `boardType` («مع الإفطار»…)، `total` (هللات حين العملة ريال، وإلا المبلغ كما هو)، `currency`، `totalText`، `perNightText`، `refundable`، `cancelBy`، `cancelText` («إلغاء مجاني حتى 12 أكتوبر» / «غير قابل للاسترداد» / «سياسة الإلغاء بحسب الفندق»)، `paymentType` (`guarantee`|`deposit`|`prepay`) و`paymentText`. أخطاء: 503 `hotel-disabled`، 404 `not-linked`، 400 `bad-dates` (مغادرة ≤ وصول، وصول في الماضي، أكثر من 30 ليلة)، 400 `bad-guests` (1–9)، 502 `provider-error`. ردّ Amadeus «لا توفر» (400 بأكواد 3664/1257/11226…) يعود 200 بقائمة فارغة و`available:false`.

### الحجز (حساب مطلوب)
- `POST /biz/:id/hotel/book` بجسم `{ offerId, guest:{title, firstName, lastName, phone, email}, card:{vendorCode, number, expiry:'YYYY-MM', holderName} }`. الخادم يفحص الضيف (400 `bad-guest`) والبطاقة محلياً (لون/Luhn، المورّد، الانتهاء؛ 400 `bad-card`) ثم يسعّر العرض من جديد (`GET /v3/shopping/hotel-offers/{id}`: زواله → 409 `offer-unavailable`) ثم يرسل الطلب `POST /v2/booking/hotel-orders`. الردّ يُحفظ في `hotel_bookings` **بلا بيانات البطاقة** (الحقل `raw` يحمل ردّ المزوّد فقط)، ويُرسل إشعار `hotel_booked`. الحالة `confirmed` حين يعيد المزوّد `CONFIRMED`، وإلا `pending`.
- `GET /hotel/bookings/mine`، `GET /hotel/bookings/:id` (صاحبه أو الإدارة). شكل الحجز: `{ id, bizId, bizName, hotelId, hotelName, orderId, confirmation, status, checkIn, checkOut, nights, adults, rooms, roomName, total, currency, totalText, guestName, guestEmail, cancelText, env, upcoming, createdAt }`.
- الإلغاء عن بُعد غير منفّذ في هذه التجربة (يتواصل الضيف مع الفندق برقم التأكيد؛ `cancelText` يبيّن السياسة).

### الربط والإدارة
- `PUT /biz/:id/hotel/link` `{ hotelId, hotelName?, cityCode? }` و`DELETE /biz/:id/hotel/link`: مالك الدائرة (`biz.owner_id`) أو الإدارة.
- `GET/PUT /adminapi/hotels/config` (قناع منسوخ → 400 `masked-key`، المفتاحان معاً → 400 `both-keys-required`، 400 `bad-env`)، `POST /adminapi/hotels/test` (يجلب رمزاً: `ok` أو `bad-credentials`/`provider-unreachable`/`provider-<status>`)، `GET /adminapi/hotels/search?cityCode=JED&q=` أو `?lat&lng&radiusKm` (قائمة فنادق Amadeus للربط)، `GET /adminapi/hotels/links`.

### الاختبار
`NASLIFE_TEST_DB=naslife_test_hotels server/test/run.sh harness_hotels.mjs` (118 فحصاً بخادم Amadeus وهمي عبر `naslifeHotelFetch`): الوحدات الخالصة (Luhn، تطبيع العرض بالريال والعملة الأجنبية وسياسات الإلغاء)، الحالة قبل المفاتيح وبعدها، إعدادات اللوحة وفحص الاتصال بأنواع الفشل، الربط (مالك/إدارة/غريب)، العروض (التواريخ، الضيوف، التطبيع، لا توفر، عطل المزوّد)، الحجز (ضيف 401، بيانات ناقصة، بطاقة خاطئة أو منتهية، نجاح بتأكيد وجسم الطلب v2، البطاقة لا تُخزَّن، الإشعار، 409 عند زوال العرض أو نفاد الغرف، 502 عند عطل، `pending`)، حجوزاتي، تجديد الرمز عند تغيّر المفاتيح، البحث والروابط والفك. الخادم الوهمي `tools/dev/mockapi.mjs` يربط `biz-hilton` بفندق تجريبي بعرضين (الجناح يعيد 409).

### خطوات المالك للتشغيل الفعلي
1. حساب على developers.amadeus.com (مجاني) → «My Self-Service Workspace» → تطبيق جديد → مفتاحا الاختبار (API Key = clientId، API Secret = clientSecret).
2. لوحة الإدارة → الإعدادات → «حجز الفنادق (Amadeus)» → أدخل المفتاحين والبيئة `test` → حفظ → «فحص الاتصال» يجب أن يعيد «متصل».
3. في البطاقة نفسها: ابحث بمدينة `JED` عن الفندق المطلوب واربطه بدائرته (مثل هيلتون جدة). تظهر في الدائرة بطاقة «احجز غرفة بأسعار اليوم».
4. جرّب الحجز من الهاتف بالبطاقة التجريبية المعبّأة تلقائياً. بيانات بيئة الاختبار محدودة ومن مخزون تجريبي، فبعض الفنادق تعيد «لا غرف متاحة»؛ جرّب فندقاً آخر من نتائج البحث.
5. للإنتاج: في حساب Amadeus أضف بطاقة دفع وانتقل إلى الإنتاج (مفتاحان جديدان)، ثم أدخلهما في اللوحة بالبيئة `live`. ملاحظة: في الإنتاج تمر بطاقة الضيف الحقيقية عبر خادمنا إلى Amadeus دون تخزين؛ قبل فتح ذلك للعامة يلزم تقييم التزام PCI (ترميز البطاقة من المتصفح أو صفحة دفع مستضافة).

## التطبيق
