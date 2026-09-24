# رفع ناس لايف إلى App Store

دليل المالك لرفع نسخة iOS الأولى، مع ما أُنجز في الكود ليتوافق مع إرشادات مراجعة أبل، وملاحظات المراجِع بالإنجليزية جاهزة للنسخ. آخر تحديث: 24 سبتمبر 2026.

## ما أُنجز في الكود

| إرشاد أبل | التنفيذ |
|---|---|
| 2.1 اكتمال التطبيق | نسخة أصلية تعمل على الآيفون: الكاميرا، المعرض، تسجيل الصوت وتشغيله، الفيديو، المشاركة، الموقع، وإعادة الاتصال عند العودة للتطبيق. المراجِع خارج السعودية يرى جدة بدل خريطة فارغة (`lib/core/location.dart`). |
| 2.3 البيانات الوصفية والأذونات | المعرّف `app.naslife`، الاسم «ناس لايف»، آيفون فقط وعمودي، نصوص الأذونات بالعربية، `ITSAppUsesNonExemptEncryption=false`، أيقونة بلا شفافية، دورة حياة المشاهد (UIScene). |
| 5.1.1(i) سياسة الخصوصية | https://naslife.app/privacy وبيان الخصوصية `ios/Runner/PrivacyInfo.xcprivacy`. |
| 5.1.1(v) حذف الحساب | ماي سبيس ← الحساب ← حذف الحساب (`docs/account-deletion.md`). |
| 5.1.1 التصفح بلا حساب | زر «تصفّح بدون حساب» في شاشة الدخول: الخريطة والأماكن والسوق والفعاليات بلا تسجيل، والحساب يُطلب فقط عند النشر أو الشراء أو المراسلة. على iOS يبدأ التطبيق في وضع التصفح. |
| 1.2 محتوى المستخدمين | موافقة على الشروط عند التسجيل وللحاليين، بند «لا تسامح مع المحتوى المسيء»، فلتر كلمات، زر إبلاغ بأسباب جاهزة على كل محتوى، حظر المستخدم من المنشور والملف، قائمة بلاغات المحتوى في لوحة الإدارة (إخفاء، استعادة، رفض، إيقاف صاحب المحتوى)، ووسيلة تواصل منشورة (`docs/moderation.md`). |
| 3.1.1 المشتريات داخل التطبيق | «سبوت لايت» إعلان رقمي فلا يُعرض شراؤه في نسخة iOS، والخادم يرفضه بترويسة `x-naslife-client: ios/...`. شحن المحفظة بالبطاقة والشحن التجريبي والتحويل بين المستخدمين وطلبات المال في الدردشة مخفية على iOS ومرفوضة من الخادم. |
| 3.1.3(e) السلع المادية | السوق والطلبات والتذاكر والحجوزات سلع وخدمات تُستهلك خارج التطبيق، فتبقى على المحفظة وميسر. |
| 4.8 تسجيل الدخول بأبل | غير مطلوب: لا يوجد دخول بحسابات طرف ثالث. |

**مؤجّل إلى ما بعد القبول**: الإشعارات الفورية عبر APNs (تحتاج مفتاح .p8 من حساب أبل)، وبيع «سبوت لايت» عبر مشتريات أبل.

## خطوات المالك بالترتيب

1. **حساب Apple Developer** باسم الشركة (يحتاج رقم D-U-N-S). بعد القبول أنشئ التطبيق في App Store Connect:
   - Bundle ID: `app.naslife`، SKU: `naslife-ios`، اللغة الأساسية: العربية.
   - الاسم «ناس لايف» (إن كان محجوزاً: «ناس لايف – Naslife»).
   - التصنيف: Social Networking، والثانوي Lifestyle.
2. **Codemagic**: سجّل في codemagic.io بحساب GitHub وأضف المستودع `AmrShuaib/naslook_app`. سيبني `ios-unsigned` عند كل دفع (`codemagic.yaml`). بعد حساب أبل:
   - أنشئ مفتاح API في App Store Connect (Users and Access ← Integrations) وأضفه في Codemagic باسم `naslife_asc`.
   - فعّل التوقيع التلقائي لـ `app.naslife`.
   - ضع رقم التطبيق الرقمي (Apple ID) مكان `0000000000` في `APP_STORE_APPLE_ID`.
   - شغّل `ios-testflight`.
3. **إعدادات المنصة من لوحة الإدارة قبل الإرسال**:
   - `supportEmail`: بريد دعم حقيقي يُرد عليه (مثل support@areebd.sa) وأنشئ صندوقه في Google Workspace.
   - أطفئ «الشحن التجريبي» (`testTopup`) واخفض `maxTopup`.
   - قرّر مفتاحي «التحويل بين المستخدمين» و«المدفوعات في الدردشة» (يفضَّل إطفاؤهما حتى يُحسم المسار التنظيمي في `CLAUDE.md`).
4. **حساب المراجِع** (ليس حساب المؤسس):
   - أنشئ حساباً جديداً باسم مثل `applereview` وكلمة سر قوية، وأكّد بريده.
   - اشحن محفظته من الإدارة بمبلغ صغير (مسار الإضافة اليدوية للرصيد، لا الشحن التجريبي) ليجرب الشراء من السوق.
   - من حساب ثانٍ: انشر قرب جدة منشوراً على الخريطة، وعرضاً في السوق، ومنشوراً وتعليقاً في دائرة، حتى يجرّب المراجِع الإبلاغ والحظر.
   - لا يُكتب اسم الحساب ولا كلمة سره في المستودع؛ تُكتب في App Store Connect فقط.
5. **الصفحات القانونية**: مراجعة مستشار قانوني للنصوص، وإضافة رقم السجل التجاري والعنوان الوطني (`server/legal_content.js`، ثم ارفع `LEGAL_VERSION`).
6. **TestFlight**: ثبّت النسخة على آيفون حقيقي وافحص القائمة أدناه.
7. **الإرسال للمراجعة** مع ملاحظات المراجِع وتسجيل شاشة قصير (التطبيق بالعربية فقط، والتسجيل يوفر على المراجِع التخمين).

## بيانات الصفحة في App Store Connect

| الحقل | القيمة |
|---|---|
| Privacy Policy URL | https://naslife.app/privacy |
| Support URL | https://naslife.app/support |
| Marketing URL | https://naslife.app |
| Copyright | 2026 Areeb Digital |
| Export compliance | لا تشفير غير معفى (مضبوط في Info.plist) |
| لقطات الشاشة | آيفون 6.9 إنش (1320×2868)؛ أبل تصغّرها للمقاسات الأخرى |

### ملصق الخصوصية (App Privacy)

يطابق `PrivacyInfo.xcprivacy` وصفحة الخصوصية. لكل نوع: **مرتبط بالمستخدم**، **لا يُستخدم للتتبع**، والغرض **App Functionality** فقط.

| الفئة | النوع |
|---|---|
| Contact Info | Email Address، Name |
| Identifiers | User ID |
| Location | Precise Location |
| User Content | Photos or Videos، Audio Data، Emails or Text Messages، Customer Support، Other User Content |
| Purchases | Purchase History |
| Usage Data | Product Interaction |

- التتبع (Tracking): لا. لا حاجة لنافذة ATT.
- بيانات البطاقة لا يجمعها التطبيق (صفحة ميسر المستضافة، والشحن بالبطاقة مخفي على iOS أصلاً).
- عند إضافة الإشعارات لاحقاً: أضف Device ID إن خُزّن رمز الجهاز مرتبطاً بالحساب.

### التصنيف العمري

أجب بصدق في الاستبيان: محتوى من المستخدمين **نعم**، الرسائل والدردشة **نعم**، الإعلانات **لا** (سبوت لايت إعلانات داخلية من البائعين، اذكرها إن سُئلت عن الترويج)، الوصول غير المقيّد للويب **لا**، الألعاب القائمة على الحظ **لا**.

**قرار مطلوب منك**: الشروط الحالية تقول 13 سنة فأكثر، و18 للمحفظة والسوق، والتطبيق لا يتحقق من العمر. إن أعطى الاستبيان تصنيفاً أعلى من 13 نرفع الحد في الشروط ليطابقه. ويُستحسن إضافة إقرار «عمري 18 سنة فأكثر» قبل أول عملية في المحفظة أو السوق.

## فحص TestFlight على جهاز حقيقي

1. التشغيل الأول بلا حساب: يفتح وضع التصفح، والخريطة والسوق والفعاليات تعمل.
2. التسجيل: مربع الموافقة على الشروط إلزامي، والروابط تفتح داخل التطبيق.
3. الأذونات: الكاميرا والميكروفون والصور والموقع تظهر بنصوصها العربية، ورفضها لا يعطل التطبيق ويعرض طريقة التفعيل من الإعدادات.
4. النشر: صورة بالكاميرا، صورة من المعرض، فيديو، ملاحظة صوتية تُسجَّل وتُسمع.
5. الدردشة: رسالة، صورة، صوت، صوت التنبيه لا يقطع موسيقى الجهاز، وإعادة الاتصال بعد الخروج من التطبيق والعودة.
6. الإبلاغ عن منشور وعرض وتعليق، وحظر مستخدم، وظهور البلاغ في لوحة الإدارة.
7. السوق: لا يظهر أي زر لشراء سبوت لايت، والمحفظة تعرض الرصيد والسجل فقط، ولا أوامر /pay و/send و/split في الدردشة.
8. حذف حساب تجريبي من ماي سبيس ← الحساب ← حذف الحساب.
9. تكبير الخط من إعدادات الجهاز: النصوص لا تتداخل.

## App Review notes (English, paste into App Store Connect)

```
Naslife is a local social and marketplace app for Jeddah and Dammam, Saudi Arabia. The interface is Arabic only; a short screen recording is attached.

Demo account
  Username/email: <demo account email>
  Password: <demo password>
The account has a small wallet balance so the marketplace purchase flow can be tested. No two-factor step.

Browsing without an account
  The app opens in guest mode on iOS: map, places, marketplace and events work without signing in.
  An account is only requested to post, message, order or buy a ticket.
  Outside Saudi Arabia the map and feeds show Jeddah, because content is local to Jeddah and Dammam.

Account deletion (5.1.1(v))
  Bottom tab "ماي سبيس" (My Space) > section "الحساب" (Account) > "حذف الحساب" (Delete account).
  Type the confirmation word "حذف", enter the password, and confirm. Deletion takes effect immediately.

User-generated content (1.2)
  - Users accept the Terms (zero tolerance for objectionable content and abusive users) when they register.
  - Report: the "⋯" menu on any post, listing, comment, review, circle, event or profile > "إبلاغ" (Report), then pick a reason.
  - Block: the "⋯" menu on a post or profile > "حظر" (Block). Blocked users' content disappears for both sides.
  - A profanity filter rejects offensive words on posts, listings, comments and reviews.
  - Reports are reviewed within 24 hours in our admin moderation queue; content reported by several users is hidden automatically, and offending accounts are suspended.
  - Contact: My Space > "تواصل معنا" (Contact us), and https://naslife.app/support

Payments (3.1)
  - Marketplace orders, event tickets and bookings are physical goods and services delivered outside the app (3.1.3(e)).
  - No digital goods or services are sold in the iOS app. Paid promotion ("Spotlight") is not offered on iOS.
  - The iOS app does not offer wallet top-up by card, transfers between users, or payment requests in chat.

Location
  Location is used to show nearby content. Sharing your live position on the map is off by default and only turned on by the user.

Privacy policy: https://naslife.app/privacy
Support: https://naslife.app/support
```

قبل اللصق: ضع بيانات حساب المراجِع، وتأكد أن كل مسار مذكور يعمل في نسخة TestFlight نفسها.

## ملاحظات تقنية

- الترويسة `x-naslife-client: ios/<version>` تُرسل من النسخة الأصلية فقط (لا من الويب)، والخادم يبني عليها حراسات المال في `server/market_b.js` و`server/chat_cards.js` و`server/commerce.js`.
- فحص الكلمات في رسائل الدردشة ومنشورات الدوائر وتعليقاتها يجري في التطبيق قبل الإرسال، لأن هذه المسارات في النواة خارج المستودع. تعميمه على الخادم يحتاج تعديلاً في النواة.
- البناء: `flutter build ios --release --no-codesign` للتحقق، و`flutter build ipa` للرفع (Codemagic يفعل الاثنين).
- الأيقونات تُولَّد من `tools/brand/` ولا تُحرَّر يدوياً.
