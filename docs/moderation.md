# الإشراف على المحتوى والبلاغات والحظر (جاهزية App Store)

تشترط آبل (القاعدة 1.2) في أي تطبيق فيه محتوى من المستخدمين: فلتراً للمحتوى المسيء، ووسيلة للإبلاغ عنه، وحظر المستخدم المسيء، واستجابة سريعة للبلاغات مع إزالة المحتوى وطرد صاحبه. هذا الملف يشرح ما يقدمه الخادم لذلك وما على المالك ضبطه.

## الحظر بين المستخدمين

- جدول الحظر في النواة: `user_blocks(user_id, blocked_id)` إن وُجد وإلا جدول آخر فيه `block` (في الإنتاج اسمه `blocks`)، والاختيار في `server/safety.js` و`server/admin.js`. قبل هذا الإصلاح كان الاكتشاف يلتقط `inbox_blocked` (قائمة حظر البريد) فيتعطل الحظر كله في الإنتاج (`/safety/status` كان يعيد `blocks:false`).
- إن لم يوجد `user_blocks` يُبحث احتياطاً عن جدول آخر فيه `block` بترتيب أبجدي ثابت، مع استثناء `inbox_*` وجداول البلاغات، ويُعاد الفحص كل دقيقة إن لم يوجد شيء.
- `GET /safety/status` عام ويعيد فقط `{ok, blocks, words, threshold}` بلا أسماء جداول. اسم الجدول يظهر للإدارة في `GET /adminapi/overview` (`server.blocksTable`).
- الحظر يعمل في الاتجاهين (من حظرته ومن حظرك) ويُطبَّق على:
  - منشورات الخريطة (القائمة والرابط المباشر `GET /mapposts/:id` يعيد 404).
  - السوق: القائمة، العرض (404)، الصفحة الرئيسية، سبوت لايت، البازار، الأسئلة، التقييمات، طلبات «أبحث عن» وردودها، ملف البائع (404).
  - الدوائر: تقييمات الدائرة، ومساحة المجتمع (كانت موجودة).
  - الفعاليات: القوائم والتفاصيل (404).
  - البحث عن الأشخاص (ويخفي أيضاً أصحاب الملفات الخاصة `is_public=false` إلا عن أنفسهم، والضيف لا يبحث في النبذة).
  - الدردشة: `POST /chat/meta` و`POST /chat/react` يرفضان بـ 403 `blocked` بين طرفين بينهما حظر (الطرف الآخر من `peerId` في الطلب، أو كاتب الرسالة المقتبسة، أو جدول `messages` في النواة إن وُجد). طلبات المال في المحادثة كانت ترفض أصلاً، والدفع على طلب قائم يرفض الآن أيضاً.
  - إرسال كوبون لصديق يرفض بـ 403 `blocked`، ومن حساب موقوف بـ 403 `suspended`.

## فلتر الكلمات المحظورة

- قائمة افتراضية متواضعة من الشتائم الصريحة بالعربية والإنجليزية (`DEFAULT_BANNED` في `server/safety.js`) تعمل من اليوم الأول. تُطابَق **كلمةً كاملة** مع السوابق العربية الشائعة (و، ف، ب، ل، يا، ال)، فلا تُرفض «زبدة» أو «زبون» أو «class». الكلمات ذات المعنى العادي (كلب، حمار…) ليست فيها عمداً.
- قائمة الإدارة (`bannedWords` في الإعدادات) تبقى كما هي: مطابقة جزئية بعد التطبيع العربي، وتصل التطبيق من `GET /safety/words` للفحص المسبق.
- الإعداد `bannedWordsDefault` (افتراضياً `true`) يطفئ القائمة الافتراضية إن سببت رفضاً خاطئاً.
- الفحص (`globalThis.naslifeCheckText`) صار على كل مسارات الإنشاء والتعديل في المستودع، ومنها الجديدة: إنشاء الدائرة وتعديلها (الاسم، الوصف، القطاع، العنوان، الساعات، المميزات)، رد صاحب الدائرة على التقييم، أصناف الكتالوج إنشاءً وتعديلاً، تعديل خبر الدائرة، رد البائع على التقييم، إجابة السؤال، والفعاليات (العنوان والوصف والمكان وأسماء الفئات وأوصافها). الرد 400 `{error:"banned-words", word}`.
- **خارج المستودع**: رسائل الدردشة ومنشورات الدوائر وتعليقاتها والاسم والنبذة تملكها النواة؛ فحصها يحتاج تعديلاً في النواة (التطبيق يفحص مسبقاً فقط).

## الحساب الموقوف

`admin.js` يصدّر `globalThis.naslifeIsSuspended(uid)`. الحساب الموقوف يُرفض بـ 403 `suspended` عند: إنشاء دائرة، إنشاء فعالية، تقييم دائرة، تقييم طلب في السوق، سؤال على عرض، طلب «أبحث عن» والرد عليه، إرسال كوبون (إضافة إلى ما كان: منشورات الخريطة، المجتمع، الطلبات والتذاكر).

## البلاغات وأنواعها

`POST /safety/report {targetType, targetId, reason}`. عند بلوغ حدّ المبلّغين المختلفين (`reportThreshold`، افتراضياً 3) يُخفى المحتوى تلقائياً، ويُشعَر صاحبه، ويُشعَر المديرون.

| النوع | المعرّف | الإخفاء | يختفي من |
|---|---|---|---|
| `post` | منشور الخريطة | `map_posts.status='blocked'` | الخريطة والرابط |
| `listing` | عرض السوق | `market_listings.status='blocked'` | السوق |
| `community` | منشور مساحة الدائرة | `biz_community_posts.hidden` | المساحة |
| `community-reply` | رد في المساحة | `biz_community_replies.hidden` | الخيط |
| `vessel-post` | منشور دائرة (النواة) | `vessel_post_mod` | `GET /posts/hidden` |
| `vessel-comment` | تعليق دائرة (النواة) | `vessel_comment_mod` (جديد) | `GET /posts/hidden?kind=comment` |
| `listing-question` | سؤال على عرض | `market_questions.hidden` | الأسئلة (يراه كاتبه) |
| `listing-review` | `order_id` التقييم | `market_reviews.hidden` | التقييمات ومتوسط العرض وشارات البائع |
| `wanted` | طلب «أبحث عن» | `market_wanted.status='blocked'` | القائمة والتفاصيل؛ صاحبه لا يعيد فتحه |
| `wanted-reply` | رد على طلب | `market_wanted_replies.hidden` | الردود |
| `biz` | معرّف الدائرة | `biz.hidden=true` و`active=false` | القوائم والصفحة؛ المالك لا يعيد تفعيلها (403 `moderated`) |
| `biz-review` | `<bizId>:<userId>` | `biz_reviews.hidden` | صفحة الدائرة ومتوسط تقييمها |
| `biz-post` | خبر/عرض الدائرة | `biz_posts.hidden` | صفحة الدائرة (عمود مستقل عن `active` فلا يعيده المالك) |
| `event` | فعالية | `events.hidden` | القوائم والتفاصيل والبحث وشراء التذاكر (يراها المضيف) |

أنواع إشعار الصاحب: القديمة كما هي (`post_blocked`، `listing_hidden`، `community_hidden`، `vessel_post_hidden`) والجديدة `content_hidden` مع `data.targetType` و`data.targetId`، و`content_restored` عند الإعادة.

**تعليقات الدوائر في النواة**: `vessel_mod.js` يكتشف جدول التعليقات (`comments` أو `post_comments` أو `vessel_comments` بعمودي `post_id` والكاتب) لقراءة الكاتب والنص؛ إن لم يجده يُقبل البلاغ بلا صاحب. التطبيق يجب أن يُخفي التعليقات التي يعيدها `GET /posts/hidden?kind=comment` (مع `post=` أو `vessel=` اختيارياً).

## طابور الإشراف (للإدارة)

- `GET /adminapi/moderation?status=open|all&type=<نوع>`: بلاغات المحتوى مجمّعة لكل عنصر: عدد المبلّغين، الأسباب، أول وآخر بلاغ، الصاحب (معرّف واسم وصورة)، العنوان ونص مختصر ورابط وسائط للمعاينة، الحالة (`visible` أو `hidden` أو `missing`)، ومعرّفات للفتح (`bizId`، `listingId`، `wantedId`، `vesselId`، `parentId`)، وآخر إجراء. «مفتوح» = لا إجراء بعد آخر بلاغ. يعيد أيضاً `open` (العدد) و`types` و`actions`.
- `POST /adminapi/moderation/:type/:id {action, note}`:
  - `dismiss`: يُغلق البلاغ بلا تغيير.
  - `hide`: يُخفي المحتوى ويُشعر صاحبه.
  - `restore`: يعيد إظهاره ويُشعر صاحبه.
  - `suspend-owner`: يوقف صاحب المحتوى (يُقرأ من المحتوى نفسه، **لا من جسم الطلب**) ويُخفي المحتوى. لا يُوقف مديراً (403 `owner-is-admin`) ولا المدير نفسه.
- الصلاحية: مدير النظام، أو عضو فريق بصلاحية `reports.view` للقراءة و`reports.act` للإجراء (`server/team.js`).
- كل إجراء يُسجَّل في `content_report_actions` وفي سجل الإدارة `admin_audit` (`moderation.<action>`، الهدف `<type>:<id>`).
- `GET /adminapi/overview` يعيد `reports.contentOpen` (عدد بلاغات المحتوى المفتوحة).

## بلاغات المستخدمين والرسائل (جدول النواة)

- `admin.js` و`notify.js` يثبّتان جدول النواة `reports` للبلاغات عن المستخدمين والرسائل (قبل ذلك كان الاكتشاف غير الحتمي يلتقط `content_reports` في الإنتاج فتختفي بلاغات المستخدمين).
- `POST /adminapi/reports/:id/action` يأخذ المستهدف من **صف البلاغ** (أول عمود فيه معرّف مستخدم صالح)، ولا يقبل `targetId` من الطلب؛ بلاغ غير موجود 404، والإيقاف بلا مستهدف 409 `no-target`.
- `notify.js` يراقب المصدرين: `reports` (إشعار `report_new`) و`content_reports` (إشعار `content_reports_new`)، لكل منهما مؤشر وقت مستقل في `notify_state`. `GET /notify/status` يعيد `reports.sources`.

## مفاتيح المال وعميل iOS

عميل iOS الأصلي يرسل الترويسة `x-naslife-client: ios/<version>`. الخادم يطبّق:

| المسار | في iOS | المفتاح العام |
|---|---|---|
| `POST /market/:id/spotlight` | 403 `iap-required` (منتج رقمي يحتاج مشتريات آبل) | — |
| `GET /market/spotlight/price` | `purchasable:false` (و`spotlightPurchasable` في `/market/home`) | — |
| `POST /wallet/topup` (الشحن التجريبي) | 403 `unavailable` لغير المدير | `testTopup` |
| `POST /wallet/transfer` | 403 `unavailable` | `transfersEnabled` |
| `POST /chat/requests` (مبلغ، تقسيم، إرسال) و`POST /chat/requests/:id/pay` | 403 `unavailable` (الموعد مسموح) | `chatPaymentsEnabled` |
| `POST /events` بفئة مدفوعة | يحتاج `placeName` أو `lat/lng` وإلا 400 `place-required` (للجميع) | — |

`transfersEnabled` و`chatPaymentsEnabled` افتراضياً `true` (السلوك الحي الحالي)، وتُضبط من `POST /adminapi/settings`، وتُعاد في `GET /settings/public` مع `supportEmail`.

## تصفح الضيف

مراجِع المتجر يجب أن يرى المحتوى قبل التسجيل. صارت هذه القراءات تعمل بلا جلسة: `GET /market`، `/market/:id`، `/market/home`، `/market/spotlight`، `/market/:id/reviews`، `/market/:id/questions`، `/market/sellers/:id`، `/market/bazaars`، `/market/bazaars/:id`، `/events`، `/events/:id`. تبقى 401 للكتابة والقوائم الشخصية (`/events?mine=1`، `/market/mine`، الطلبات، المحفظة، `/market/wanted`، `/market/spotlight/price`…). مشاهدات سبوت لايت لا تُحسب للضيف.

## ما على المالك ضبطه

1. **بريد الدعم**: `supportEmail` من إعدادات الإدارة (مثلاً `support@areebd.sa`) حتى يظهر في التطبيق وفي App Store Connect.
2. **قرار مفاتيح المال**: هل يبقى التحويل بين المستخدمين (`transfersEnabled`) والدفع داخل المحادثة (`chatPaymentsEnabled`) مفعّلين على الويب؟ التوصية التنظيمية (تقرير المحفظة) إطفاء التحويل بين المستخدمين. في iOS هما مطفآن دائماً.
3. **إطفاء الشحن التجريبي** (`testTopup`) قبل أي مدفوعات حقيقية.
4. **مراجعة القائمة الافتراضية** للكلمات المحظورة وإكمالها بقائمة الإدارة، وإبقاء حدّ البلاغات 3 أو تعديله.
5. **من يراقب طابور الإشراف يومياً**: الشروط تعد بمعالجة البلاغات خلال 24 ساعة. يمكن منح موظف دور «مشرف محتوى» (صلاحيتا `reports.view` و`reports.act`).
6. **تأكيد جدولي النواة** على الخادم بعد النشر: `GET /adminapi/overview` يجب أن يعيد `server.blocksTable = "user_blocks"` و`server.reportsTable = "reports"`، و`GET /safety/status` يجب أن يعيد `blocks: true`.
7. **النواة**: فحص الكلمات المحظورة ورفض الحساب الموقوف ورفض الرسائل بين طرفين بينهما حظر على الرسائل ومنشورات الدوائر وتعليقاتها والنبذة، لأنها خارج المستودع.

## الاختبارات

- `server/test/harness_safety.mjs`: انحدار الحظر (ينشئ `inbox_blocked` قبل تسجيل `safety.js`)، الحالة العامة بلا أسماء جداول، القائمة الافتراضية، الرابط المباشر للمنشور بين طرفين بينهما حظر.
- `server/test/harness_moderation.mjs`: الأنواع الجديدة والإخفاء التلقائي والإشعارات، الطابور وإجراءاته والصلاحيات والتدقيق، الفلتر والإيقاف على المسارات، تصفية المحظورين، تثبيت `reports` والمستهدف من الصف، مراقبة المصدرين.
- `server/test/harness_guest.mjs`: قراءات الضيف و401، مشاهدات سبوت لايت، حراسة iOS، `transfersEnabled`، `supportEmail`.
- `server/test/harness_chat_cards.mjs` (الحظر في meta/react ومفاتيح المال في المحادثة) و`harness_offers.mjs` (الكوبون بين طرفين بينهما حظر).
- للجلسات المتوازية: `NASLIFE_TEST_DB=naslife_test_x server/test/run.sh all` يوجّه الحزم إلى قاعدة مستقلة (`server/test/db_env.mjs`).
