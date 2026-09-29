# التوظيف: ربط دوائر الأعمال بالباحثين عن عمل

الإضافة `server/jobs.js` (مسجّلة بعد `offers.js`) مع واجهات في `lib/pages/jobs/` (المستخدم والعام)، `lib/pages/business/owner/` (الدائرة)، و`lib/pages/admin/admin_jobs.dart`. النماذج والعميل في `lib/api/jobs_models.dart` و`lib/api/jobs_api.dart`. الحزمة: `server/test/run.sh harness_jobs.mjs`.

## قرارات المالك (٢٩ سبتمبر ٢٠٢٦)

| القرار | الاختيار |
|---|---|
| من ينشر | كل دوائر الأعمال (لا قصر على الشركات)، بلا موافقة مسبقة افتراضياً (`jobsRequireApproval` في الإعدادات يفعّلها) |
| بيانات الباحث | ملف توظيف مستقل وخاص (`job_profiles`) لا يظهر في الملف العام |
| قناة الوصول | بطاقة في تبويب «الطلبات» بالدردشة + إشعار (لا رسائل من الخادم في النواة) |
| كشف الهوية | بعد إجابة المرشح على أسئلة الفرز (قبل ذلك الدائرة ترى «مرشح #N» ودرجة المطابقة فقط) |
| المرسِل في المحادثة | عضو فريق بدور «توظيف» (`hr`) أو المالك، والمحادثة تُفتح من جهاز المرشح بعد الإجابة |
| التسعير | مجاني مع حد للعروض النشطة (`jobsFreeActive` = ٣)، وباقة `pro` تمنحها الإدارة الآن (بلا حد + تصدير CSV) |
| الذكاء الاصطناعي | صياغة العرض والمتطلبات وأسئلة الفرز فقط؛ لا ترتيب ولا رفض للمرشحين |
| النطاق | المراحل الثلاث: الملف والعرض والمطابقة والبطاقة والأسئلة واللوحة، ثم اللوحة الاحترافية، ثم الوظائف العامة والتقديم بلا دعوة |

لا رسوم على الباحث عن عمل أبداً. رسوم النشر خدمة رقمية فتُخفى عبارات الترقية في نسخة iOS.

## الجداول

- `job_profiles`: للمستخدم (المفتاح `user_id`): `active`، `titles[]`، `fields[]`، `city`، `districts[]`، `types[]`، `experience_years`، `education`، `skills[]`، `languages[]`، `salary_min/max`، `availability`، `summary`، `cv_url/cv_name`.
- `jobs`: العرض: الدائرة، المنشئ، المسؤول (`assignee_id`)، المسمّى (عربي/إنجليزي)، القسم، الوصف، `requirements {must, nice}`، `skills[]`، المدينة والحي، النوع (`full|part|remote|intern|shift|freelance`)، الخبرة الدنيا، المؤهل، الراتب وإظهاره، الشواغر، الموعد النهائي، الحالة (`draft|pending|open|paused|closed|filled`)، `public`، `questions` (حتى ١٠: `text|yesno|choice|number`)، المشاهدات، `draft_source` (`ai|template|manual`).
- `job_matches`: البطاقة/الترشيح (فريد على العرض والمستخدم): الدرجة والأسباب، المصدر (`match|apply`)، الحالة (`sent|viewed|accepted|declined|later|answered|withdrawn|expired`)، المرحلة (`new|screening|answered|interview|offer|hired|rejected`)، الرقم التسلسلي `seq` (لتسمية المرشح المجهول)، الإجابات، المسؤول.
- `job_notes` (ملاحظة وتقييم ١–٥ لكل عضو)، `job_events` (سجل زمني)، `job_interviews` (موعد ووضع `onsite|call|video` ومكان وحالة وتذكير)، `job_plans` (الباقة لكل دائرة).

## المطابقة

`scoreMatch(job, profile)` تعيد درجة ٠–١ وأسباباً عربية. الأوزان: المسمّى ٠٫٣ (تطابق كامل أو نسبة كلمات مشتركة بعد تطبيع عربي: حذف التشكيل، توحيد الألف والتاء المربوطة والياء)، المهارات ٠٫٢٥، المدينة ٠٫١٥ (عن بُعد = ١)، نوع الدوام ٠٫١، الخبرة ٠٫٠٨، الراتب ٠٫٠٦، المجال ٠٫٠٦. الحد الأدنى `jobsMinScore` (٠٫٤٥).

عند النشر (`open`) يُطابق العرض فوراً: يستبعد فريق الدائرة ومن طابقناهم ومن حظرهم المنشئ، يحترم حد المستخدم الأسبوعي (`jobsWeeklyCap` = ٥ بطاقات)، وسقف العرض (٢٠ × الشواغر، حتى ١٠٠). كل بطاقة تُنشئ صف `job_matches` بحالة `sent` وإشعار `job_offer`. المسح الدوري (كل ٣٠ دقيقة، `JOBS_SWEEP_MS`) يعيد المطابقة للعروض المفتوحة (ملفات جديدة)، يغلق ما تجاوز موعده، ينهي البطاقات الأقدم من ٢١ يوماً، ويذكّر بالمقابلات قبل ٢٤ ساعة. `POST /adminapi/jobs/sweep` يشغّله يدوياً.

المعاينة قبل النشر (`preview-match`) تعيد أعداداً فقط (قوي ≥ ٠٫٧٥، جيد ≥ الحد، ضعيف) بلا هويات.

## رحلة المستخدم

1. ماي سبيس ← «أبحث عن عمل»: يملأ الملف ويفعّل «متاح للعروض». `PUT /jobs/profile`.
2. تصله بطاقة في «الطلبات» بالدردشة وإشعار: `GET /jobs/inbox`. يفتحها (`GET /jobs/offers/:matchId` تعلّمها `viewed`)، ثم «أقبل» أو «لا يناسبني» (بسبب اختياري) أو «لاحقاً».
3. القبول (`POST .../accept`) يُخطر فريق التوظيف بمرشح مجهول ويعيد أسئلة الفرز. بلا أسئلة يُعدّ «أجاب» فوراً.
4. الإجابات (`POST .../answers` بقائمة `{id, value}`؛ الإلزامية تُتحقق، الأنواع تُحوَّل) تكشف هويته للدائرة وتُخطر المسؤول، وتعيد `chatWith` فيفتح التطبيق المحادثة معه ويرسل بطاقة `#job/<id>`.
5. «عروض التوظيف» ← «طلباتي» (`GET /jobs/mine`) تعرض المراحل والمقابلات، ويمكن الانسحاب (`withdraw`).
6. التقديم بلا دعوة على وظيفة عامة: `POST /jobs/:id/apply` (يحتاج ملف توظيف؛ يُعدّ قبولاً ثم الأسئلة).

## رحلة الدائرة

- لوحة الدائرة ← «التوظيف»: `GET /biz/:id/manage/jobs` (العروض بعدّاداتها، الباقة، الفريق، الأدوار، `aiAvailable`).
- المنشئ: `POST /biz/:id/manage/jobs/draft` بمسمّى ونقاط ونوع → مسودة كاملة. المصدر `ai` عبر `globalThis.naslifeAskClaude` (مفتاح Anthropic في إعدادات صندوق البريد بلوحة الإدارة، النموذج الافتراضي `claude-opus-5-5`، جهد `medium`، والرد JSON فقط)، وإلا `template` محلي من `templateDraft()`. المسودة لا تُحفظ حتى الحفظ الصريح.
- الحفظ والنشر: `POST /biz/:id/manage/jobs` (مع `publish: true` اختياري)، `PATCH`, `publish`, `pause`, `close` (`filled`)، `duplicate`, `DELETE` (مسودة فقط). حد الباقة المجانية يرد `402 plan-limit`. مع `jobsRequireApproval` تُنشر بحالة `pending` حتى موافقة الإدارة.
- المرشحون: `GET .../candidates?stage=` (مجهولون حتى الإجابة)، `GET .../candidates/:matchId` (الملف والإجابات والملاحظات والسجل)، `PATCH` (المرحلة والإسناد؛ المراحل المتقدمة ترفض قبل الكشف `409 not-revealed`، وتُخطر المرشح `job_stage`؛ التعيين يملأ العرض تلقائياً عند اكتمال الشواغر)، الملاحظات (`notes`)، المقابلات (`interviews` مع إشعار وتذكير)، الإحصاءات (`stats`: القمع ومتوسط أيام الإجابة وساعات المشاهدة وأسباب الرفض)، التصدير (`export` CSV بـ BOM، باقة pro فقط `402 pro-required`).
- الفريق: دور `hr` («توظيف») في `POST /biz/:id/team`؛ يدير التوظيف دون بقية اللوحة (`Biz.canHire`).

## العام والإدارة

- `GET /jobs?q&city&type&bizId` (المنشورة والعامة، مع `mine` للمسجّل)، `GET /jobs/:id` (الأسئلة لصاحب ترشيح أو لفريق الدائرة فقط)، `GET /biz/:id/jobs`، `GET /jobs/hiring` (الدوائر التي توظّف لرقاقة الخريطة). بطاقة الدردشة `#job/<id>` في `chat_cards.js`.
- الإعدادات (`admin.js`): `jobsEnabled`، `jobsFreeActive`، `jobsWeeklyCap`، `jobsMinScore`، `jobsRequireApproval`؛ `jobsEnabled` يظهر في `/settings/public`.
- `GET /adminapi/jobs?status=`، `POST /adminapi/jobs/:id/approve|close`، `GET/PUT /adminapi/jobs/plans/:bizId` (`plan: free|pro`, `months`).

## الإشعارات

`job_offer` (للمستخدم: عرض جديد)، `job_accept` و`job_answers` و`job_apply` (لفريق التوظيف، `manage: true`)، `job_stage` (للمرشح عند مقابلة/عرض/تعيين/اعتذار، وللفريق عند الانسحاب)، `job_interview` (للطرفين: موعد وتذكير وإلغاء)، `job_review` (للفريق مع `manage: true`: موافقة الإدارة أو إغلاقها أو تفعيل الباقة؛ وللمشرفين بلا `manage` عند انتظار الموافقة، ويفتح قسم التوظيف في لوحة الإدارة).

## اعتبارات

- لا سؤال عن الدين أو الحالة الاجتماعية في أسئلة الفرز، ولا تمييز في الصياغة؛ المحرك موجَّه بذلك في نص النظام، والفريق يعدّل المسودة قبل النشر.
- السيرة الذاتية تُرفع عبر `/chat/upload` وتُحذف مع الحساب (`account_delete.js` يحذف صفوف المستخدم في الجداول العامة؛ أضف `job_profiles` و`job_matches` هناك إن لم تُشمل تلقائياً).
- الحظر: لا تُرسل بطاقة إلى من حظره منشئ العرض.

## ملفات التطبيق

- المستخدم: `lib/pages/jobs/job_profile_page.dart` (أبحث عن عمل، رفع السيرة PDF عبر `/chat/upload`، على الويب فقط الآن)، `job_offers_page.dart` (الواردة/طلباتي وبطاقة `JobOfferCard`)، `job_offer_page.dart` (العرض، القبول، الأسئلة، سحب الطلب، فتح المحادثة مع بطاقة `#job/<id>` في حقل الكتابة)، قسم «التوظيف» أعلى تبويب «الطلبات» في `lib/pages/chat/chats_page.dart`، صفَّا ماي سبيس، `lib/state/jobs_providers.dart`، الشارة في `unreadCountProvider`.
- الدائرة: تبويب «التوظيف» في `business_dashboard_page.dart` (`BusinessDashboardPage.jobsTab`)، `dashboard_jobs.dart` (الباقة والإحصاءات والقائمة)، `job_editor_page.dart` (المحرك ثم النموذج الكامل والمعاينة والنشر)، `job_candidates_page.dart`، `job_candidate_page.dart`، `job_stats_page.dart` (القمع والتصدير)، `job_actions.dart`، `lib/state/biz_jobs_providers.dart`، دور «توظيف» في `dashboard_reviews_team.dart`.
- العام والإدارة: `lib/pages/jobs/jobs_page.dart` (القائمة والفلاتر و`JobsEntryCard` في صفحة الدائرة)، `job_page.dart` (الوظيفة والتقديم والمشاركة)، رقاقة «وظائف» في الخريطة وقائمة الدوائر، `lib/pages/admin/admin_jobs.dart` وقسم الإعدادات في `admin_settings.dart`، `lib/state/jobs_public_providers.dart`.
- الروابط العميقة للإشعارات في `lib/core/notify_open.dart`، وبطاقة `#job` في `chat_cards.dart` تفتح صفحة الوظيفة.

## الاختبار

- الخادم: `server/test/run.sh harness_jobs.mjs` (١٧٤ فحصاً: الوحدات الخالصة، الملفات، المحرك بمحاكاة Claude ثم القالب، النشر والمطابقة والحدود، الصندوق والقبول والأسئلة وكشف الهوية، التقديم، اللوحة والمقابلات والتذكير والإحصاءات والتصدير، الإدارة والمسح).
- التطبيق: `flutter test test/jobs_user_test.dart test/jobs_circle_test.dart test/jobs_public_test.dart`.
- الخادم التجريبي: `tools/dev/mockapi.mjs` فيه ثلاث كتل `jobs (user|circle|public+admin)`.

## المؤجّل

- رفع السيرة الذاتية من الجوال الأصلي (يحتاج حزمة اختيار ملفات)، رسالة الخادم من روبوت في الخاص (تحتاج مساراً في النواة)، الدفع للباقة من المحفظة (الإدارة تمنحها الآن)، وترجمة الواجهة.
