# الملف الشخصي v2 — جهة التطبيق

إعادة تصميم ملف المستخدم بأربع شاشات على النموذج التفاعلي `docs/reports/proto_profile/template.html` (و`template_colors.html` الذي أضاف «عرّف بنفسك»)، بلوحة الألوان الحالية (`Joy`، فيروزي على أبيض). الخادم في `server/profile_v2.js` وعقده في تقرير التصميم؛ التطبيق يعمل بملف النواة وحده حين يغيب v2 على الخادم (404) فلا تنكسر أي شاشة.

## الملفات

| الملف | الدور |
|---|---|
| `lib/api/profile_v2_models.dart` | `ProfileV2` ومعه `ProfileLink` و`ProfileIntro` و`ProfileStats` و`ProfileTrust` و`ProfileFlags` و`ProfileSettings` و`CompletionStep`/`ProfileCompletion` و`ProfileStats7` و`HandleCheck` و`FollowResult`؛ كلها بـ`fromJson` متسامح، ومعها `profileCities` (جدة والدمام وأحياؤهما) و`monthYear`/`clockText`. |
| `lib/api/profile_v2_api.dart` | `extension ProfileV2Api on ApiClient`: `profileV2`، `myProfileV2`، `updateProfileV2`، `setIntro`، `deleteIntro`، `follow`/`unfollow`، `followers`/`following`، `profileEvent` (خلفي لا يفشل)، `profileStats7`، `checkHandle`. |
| `lib/state/profile_v2_providers.dart` | `profileV2Provider(idOrHandle)` و`myProfileV2Provider` (يعيدان null عند 404 أو ردّ بلا معرّف)، `profileStats7Provider`، `followersProvider`/`followingProvider`، `userPostsProvider` (بث الخريطة بمرشّح `authors`)، `sellerListingsProvider` (`/market?seller=`). |
| `lib/pages/profile/user_profile_page.dart` | شاشة ١ «ما يراه الزائر» (`UserProfilePage(person:)`، `openProfile()` كما كان). |
| `lib/pages/profile/edit_profile_page.dart` | شاشة ٣ «تعديل الملف» (`EditProfilePage`). |
| `lib/pages/profile/privacy_control_page.dart` | شاشة ٤ «التوثيق والتحكم» (`PrivacyControlPage`). |
| `lib/pages/profile/owner_cards.dart` | بطاقات شاشة ٢ في ماي سبيس (`OwnerProfileCards`): التعريف، اكتمال الملف، آخر 7 أيام. |
| `lib/pages/profile/intro_card.dart` | `ProfileIntroCard` (صوت/فيديو)، `IntroVoiceBar` (مشغّل مضغوط لرابط أو بايتات)، `IntroCallToAction` (الإطار المتقطّع). |
| `lib/pages/profile/profile_bits.dart` | قطع مشتركة: `CoverBox`، `CoverButton`، `ProfileChip`، `ChipGroup`، `StatCell`، `profileLinkIcon`. |
| `lib/pages/myspace/myspace_page.dart` | تعديلات صغيرة: زر التعديل يفتح `EditProfilePage`، صف «عرض ملفي العام» يفتح `UserProfilePage(person: me)`، «الخصوصية والأمان» يفتح `PrivacyControlPage` (وفيها المحظورون والمكتومون إلى `SafetyPage`)، و`OwnerProfileCards` تحت بطاقة الملف. حُذف مربع `_edit` القديم ودوال الصورة (انتقلت إلى شاشة التعديل). |

## الشاشات

### ١ الزائر (`UserProfilePage`)
- غلاف (`profile-cover`: الصورة أو تدرّج فيروزي) وفوقه رجوع ومشاركة (`share-profile`، تسجّل حدث `share`) وإدارة الحساب للمدير (`admin-user`) وقائمة المزيد (`profile-menu` → `profile-report`/`profile-block`/`profile-unblock`). الصورة تتداخل مع حافة الغلاف.
- الاسم المعروض (وإلا النك نيم) + علامة التوثيق (`verified-mark` عند `trust.emailVerified`) + وسم المسمى (`job-tag` للمحترف) ثم `@nickname · المدينة · الحي · متصل الآن`.
- شارة «محظور» (`blocked-banner` + `unblock-btn`) كما كانت.
- الأزرار: «مراسلة» (`message-btn`، تسجّل حدث `message` ثم تفتح المحادثة) أو بديلها «لا يستقبل رسائل من غير الأصدقاء» (`message-off`) حين `canMessage=false`؛ «متابعة/تتابعه» (`follow-btn`، متفائلة، تعيد الحالة عند الخطأ)؛ «إضافة صديق/صديق» (`friend-btn`). لصاحب الحساب: «تعديل الملف» (`edit-profile-btn`) مع «هذا ملفك كما يراه الزوار».
- النبذة (`profile-bio`)، الروابط (`profile-link-N`، تفتح خارجياً عبر `url_launcher` وتسجّل حدث `link`؛ `profileLinkOpenOverride` للاختبارات)، بطاقة «<الاسم> يعرّف بنفسه» (`intro-card`، `intro-play`؛ الفيديو يبدّل الملصق بـ`VideoView` في `intro-video`).
- صف الأرقام (`stats-row`: منشور، متابِع، التقييم، دوائر) وشارات الثقة (بريد موثّق، يرد سريعاً، N طلباً مكتملاً، عضو منذ).
- ست تبويبات كرقائق (`tab-posts|market|services|circles|reviews|about`): المنشورات شبكة مصغّرات (`posts-grid`) تفتح العارض، أو العدد وزر «عرض على الخريطة» (`posts-fallback`) إن تعذّر الجلب؛ السوق شبكة `ListingCard` (`market-grid`)؛ الخدمات `offerings` من ملف النواة (`userProfileProvider` بقي كما هو)؛ الدوائر عدد فقط الآن؛ التقييمات ملخّص المتوسط والعدد؛ عنه: المهارات والهوايات ويبحث عن + نوع الحساب والمدينة وعضو منذ والرقم SA («يظهر للأصدقاء فقط» لغير الصديق).
- الملف الخاص (v2 `isPrivate` أو رفض النواة 403/404): الرأس والأزرار ثم حالة «ملف خاص» (`private-state`) بلا تبويبات. الزائر بلا حساب: بطاقة الدخول كما كانت (`guest-profile-card`، `guest-profile-login`) ولا تُطلب أي مسارات حساب.

### ٢ صاحب الحساب (ماي سبيس)
تحت بطاقة الملف (`owner-cards`، تظهر فقط حين يردّ `/me/profile/v2`): بطاقة التعريف مع «تغيير» (`intro-change`) أو الدعوة المتقطّعة «عرّف بنفسك بصوتك أو بفيديو» (`intro-cta`)؛ «اكتمال الملف N٪» (`completion-card`) بشريط وخطوات (`completion-<id>`؛ الخطوة تفتح التعديل، و`email` تفتح التوثيق والتحكم)؛ «آخر 7 أيام» (`stats7-row`: زيارات الملف مع نسبة التغيّر، رسائل من الملف، متابعون جدد).

### ٣ تعديل الملف (`EditProfilePage`)
- «إلغاء» (`edit-cancel`) و«حفظ» (`edit-save`) في الشريط. الغلاف (`edit-cover` يرفع ويعرض فوراً ويُحفظ مع «حفظ»، `edit-cover-remove`) والصورة (`edit-avatar`/`edit-avatar-remove`: رفع ثم `POST /profile/avatar` فوراً وتحديث الجلسة كما في المسار القديم).
- الاسم المعروض (`edit-name`)، اسم المستخدم (`edit-handle`، فحص `GET /handles/check` بعد 400ms، النتيجة في `handle-status`: «متاح» أو السبب؛ عند الحفظ يُرسل `PATCH /me` إن كان متاحاً وإن رفضته النواة تظهر رسالة لطيفة ويكمل الحفظ)، النبذة (`edit-bio`، عدّاد 160).
- «عرّف بنفسك»: بطاقتا نمط (`intro-voice`/`intro-video`). الصوت: `intro-record` يبدأ `VoiceRecordSession` بمؤقّت حي (`intro-timer`) يتوقف عند 60 ثانية، `intro-stop`، ثم معاينة `intro-preview-play` و«إعادة التسجيل» (`intro-rerecord`) و«اعتماد» (`intro-use`: `uploadMedia` ثم `PUT /me/profile/intro`). الفيديو: `intro-video-camera`/`intro-video-gallery` عبر `pickVideo` (حتى 30 ثانية؛ المدة المجهولة تُمرَّر 30 ويتحقق الخادم). التعريف المحفوظ يظهر ببطاقته مع «إعادة التسجيل/التصوير» (`intro-replace`) و«حذف» (`intro-delete`).
- نوع الحساب (`acct-personal`/`acct-pro`) والمسمى المهني (`edit-job`) للمحترف؛ المدينة والحي (`edit-city`/`edit-district` من `profileCities`)؛ المهارات رقائق مع حذف و«+ إضافة» (`skill-add`، حتى 8)؛ الروابط حتى 3 (`link-kind-N`، `link-value-N`، `link-remove-N`، `link-add`)؛ الرقم SA ثابت.
- الحفظ: `PUT /me/profile` (bio, skills, hobbies, lookingFor, accountType) ثم `PUT /me/profile/v2` (displayName, jobTitle, city, district, coverUrl, links)؛ 404 من v2 لا يُفشل الحفظ.

### ٤ التوثيق والتحكم (`PrivacyControlPage`)
درجة التوثيق (البريد من `trust.emailVerified`، الجوال والهوية «قريباً»)؛ من يراسلني (`msg-policy` مقسّم: الجميع/الأصدقاء/لا أحد → `msgPolicy`)؛ ما يظهر في ملفي (`show-online`، `show-city`، `intro-visibility` all↔friends، `show-friends`، والرقم SA للأصدقاء دائماً، و`profile-public` عبر `updateProfile({'isPublic'})` في النواة)؛ الأمان (`safety-blocked` و`safety-muted` إلى `SafetyPage` بعدد كل منهما، والأجهزة «قريباً»). التغييرات متفائلة وتُعاد عند الخطأ.

## مسار الوسائط
التسجيل الصوتي عبر `VoiceRecordSession` (MediaRecorder على الويب، `record` إلى m4a على الجوال) → `uploadMedia(bytes, contentType, fileName)` إلى `/chat/upload` (يحوّل الصوت والفيديو على الخادم) → `setIntro(kind, url, sec)` بالرابط النسبي `/chat/media/...`. الفيديو عبر `pickVideo(gallery:, maxDuration: 30s)` ثم الرفع ثم `setIntro`. العرض: `IntroVoiceBar` فوق `VoicePlayer` (play داخل حدث اللمس لأجل iOS)، والفيديو `VideoView(url:)` بعد لمس الملصق.

## الاختبارات
`test/profile_v2_test.dart` (MockClient، `VoiceRecordSession.factoryOverride`، `VoicePlayer.factoryOverride`، `VideoView.factoryOverride`، `profileLinkOpenOverride`، `pickImageOverride`): النماذج؛ الزائر (العرض الكامل، المتابعة POST/DELETE مع العدّاد المتفائل، الرابط والحدث، التبويبات الست، `canMessage=false`، الملف الخاص، غياب v2، ملفي)؛ التعديل (الحفظ وأجسام PUT، فحص الاسم بعد 400ms، التسجيل الصوتي حتى `PUT /me/profile/intro` والحذف، الصورة)؛ التوثيق والتحكم (كل مفتاح ومفتاح النواة)؛ ماي سبيس (البطاقات الثلاث والصفوف الجديدة، الدعوة بلا تعريف، ولا شيء إضافي بلا v2). `test/user_profile_test.dart` عُدّل ليختار التبويبين «عنه» و«الخدمات» بدل توقّع كل شيء في شاشة واحدة، و`test/profile_market_test.dart` يمرّ على شاشة التعديل الجديدة بنصوصه نفسها.
