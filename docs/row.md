# «الصف» (row): الرئيسية المعتمدة بنظام «واحد» وبطاقة واحدة على الخريطة

قرار المالك (1 أكتوبر 2026): الرئيسية خريطة كاملة وبطاقة مدمجة واحدة في الأسفل تُسحب جانبياً، والخريطة تتبع كل بطاقة، والنقر على دبّوس يقفز بالبطاقة إليه. لا ورقة سفلية ولا رقائق ولا أقسام ولا تخصيص ولا اختيار لأقسام الشريط. المرجع البصري: `docs/reports/proto_profile/make_flows.py` و`make_one.py` (الشكل أ). قسم الخادم (`server/row.js`) يكتبه وكيل الخادم في هذا الملف.

## التطبيق

### الملفات

| الملف | الدور |
|---|---|
| `lib/api/row_api.dart` | `RowItem` (الحقول كما في عقد `/row`، `fromJson` متسامح، `pinKey` مفتاح الدبّوس بصيغة `MapItem.key`، `kindLabel`، فعل افتراضي لكل نوع)، `RowFeed{items, located}`، و`extension RowApi on ApiClient { rowNear(lat, lng, radiusKm: 15, limit: 30) }` |
| `lib/state/row_providers.dart` | `rowProvider` (FutureProvider) يقرأ `userLocationProvider` كما يفعل `offersNearProvider`؛ لا يتبع حدود الخريطة عمداً حتى لا يُعاد الجلب مع كل حركة |
| `lib/pages/home/row_deck.dart` | `RowDeck({items, index, onIndex, onAct, loading, located})`: صف العدّاد وبطاقة واحدة، الانزلاق والسحب والحالة الفارغة وهيكل التحميل، و`rowKindColor/rowKindIcon` |
| `lib/pages/map/map_page.dart` | `MapPage(home: true)`: بحث وجرس فوق الخريطة، البطاقة فوق شريط التنقّل، تتبع الكاميرا، إبراز الدبّوس، النقر على الدبّوس، رحلات الأفعال. `MapPage()` غير الرئيسي يحتفظ بالرقائق ولوحة المنطقة كما كانت |
| `lib/pages/map/map_cluster.dart` | نوعان جديدان `MapItemKind.event` و`MapItemKind.job`، `MapItem.row(RowItem)`، و`unprojectPixels` لحساب إزاحة المركز |
| `lib/core/nav_provider.dart` | الأقسام الأربعة الثابتة (`navTabs`، `navTabIds`، `navTabMeta`) و`openNavTab` |
| `lib/pages/circles/post_card.dart` | `PostCard` (بطاقة منشور الدائرة) نُقلت من `home_page.dart` المحذوف لأن صفحتي الدوائر تستخدمانها |

### السلوك

- **الجلب**: `GET /row?lat&lng&radiusKm=15&limit=30` بموقع المستخدم (GPS ثم موقعه المحفوظ على الخريطة)، وبلا موقع يعيد الخادم الأحدث مع `located:false` فيقرأ العدّاد «الأحدث أولاً» بدل «الأقرب أولاً». الزائر يطلبه أيضاً (المسار عام).
- **البطاقة** (ارتفاع ٨٤): صورة ٦٨×٦٨ في البداية (الوسيط أو الشعار، وإلا مربع بلون النوع ورمزه)، سطر «النوع · الناشر» والمسافة في النهاية، عنوان عريض، وصف خافت، وزر واحد بالفعل الذي يرسله الخادم (`شاهد/استخدم/تذكرة/قدّم/اطلب`).
- **التبديل**: سهمان فوق البطاقة، أو سحب أفقي أكثر من ٦٠ بكسل (يساراً = التالي)؛ البطاقة الخارجة تنزلق بجهة السحب وتدخل التالية من الجهة المقابلة؛ الدوران حلقي (بعد الأخيرة الأولى).
- **تتبع الخريطة**: مع كل اختيار `_map.move` إلى تكبير `kRowFollowZoom = 15.5` ومركز أسفل الدبّوس بـ ٨٪ من ارتفاع الخريطة فيستقر الدبّوس عند نحو ٤٢٪ من الارتفاع فوق البطاقة. يُحسب بإسقاط ويب‑مركاتور (`projectToPixels`/`unprojectPixels`) لا بالكاميرا الحالية، فلا يعتمد على التكبير السابق.
- **الدبابيس**: عناصر الصف تُطابق دبابيس طبقات الخريطة بالمفتاح (`post:`/`offer:`/`listing:`)، فإن لم تشملها حدود الخريطة بعد يُضاف دبّوس احتياطي من عنصر الصف نفسه (بياناته `RowItem`) حتى يبقى للبطاقة المختارة دبّوس دائماً. الفعاليات والوظائف لا طبقة لهما فدبّوساهما من الصف فقط (`Icons.event` و`Icons.work`). المختار بحلقة خضراء أكبر (`map-pin-selected`) والبقية بشفافية ٦٠٪.
- **النقر على دبّوس**: إن كان من عناصر الصف يقفز بالبطاقة إليه؛ وإلا السلوك القديم (`_showItem`). دبّوس احتياطي بياناته `RowItem` يفتح رحلة البطاقة نفسها.
- **زر البطاقة** → الرحلات القائمة: لحظة → `PostViewerPage(posts: [MapPost.fromJson(payload)])` بلا طلب آخر؛ عرض → `CircleOffersPage(bizId: refId, title: who)`؛ فعالية → `EventDetailPage(eventId: refId)`؛ وظيفة → `JobPage(id: refId)`؛ سوق → `ListingPage(refId)`. هذه الصفحات قراءات عامة، و`JobPage` يحرس التقديم بنفسه.
- **الزائر**: `GuestShell` يعرض `MapPage(home: true, floatingNav: false)` (الشريط العادي لا يطفو فوق الخريطة فلا مسافة لكبسولة). الجرس لا يُجلب للزائر، والبحث والجرس يدعوان للدخول (`requireAccount`) لأن صفحتيهما تطلبان مسارات حساب.
- **الأزرار العائمة** (منشور جديد، موقعي، تحديث، إظهار موقعي، «هنا الآن») بقيت فوق البطاقة؛ «تحديث» يعيد جلب الصف أيضاً.
- **الشريط السفلي**: أربعة أقسام ثابتة (الخريطة، الدوائر، المحادثات، ماي سبيس) وكاميرا في الوسط؛ `HomeShell.pageOf` يعرف هذه الأربعة فقط.

### المفاتيح (Keys)

`row-prev`، `row-count` (نصه «N من M · الأقرب أولاً» أو «الأحدث أولاً»)، `row-next`، `row-card`، `row-dist`، `row-act`، `row-empty`، `row-skeleton`، `map-pin-selected`، وبقيت `home-search` و`home-bell`.

### ما أُزيل من التطبيق

- شاشة الرئيسية بالأقسام وتخصيصها كلها: `lib/pages/home/home_page.dart` (`HomePage`، `HomeBlock`، `showBlockMenu`، `HiddenBlocksTray`، `HomeEditList`، `homeBlockWidgets`، الاختصارات، شريط اللحظات، الأماكن الرائجة)، `home_blocks_more.dart`، `home_layout_page.dart`، `lib/core/home_layout.dart`، `lib/state/layout_providers.dart` (ومعه `navTabsProvider`)، `lib/api/layout_api.dart`.
- في وضع الرئيسية للخريطة: الرقائق، ورقة المنطقة، الأقسام داخلها، وضع التحرير (`home-edit`).
- بند «تخصيص الرئيسية» (`home-layout`) في ماي سبيس، وبطاقة «الرئيسية» في إعدادات الإدارة (`set-home-order`، `set-home-pinned`) وحقلا `AdminSettings.homeLayoutOrder/homeLayoutPinned` (الخادم يتجاهل غيابهما).
- اختبار `test/home_layout_test.dart`، واختبار بطاقة البث والأماكن الرائجة في الرئيسية من `test/feed_test.dart`.
- الخادم `server/layout.js` يبقى مسجّلاً خاملاً (لا يُلمس)؛ `docs/home-layout.md` تاريخي.

### الاختبارات

`test/row_deck_test.dart` (١٠ اختبارات): نموذج `RowItem`، الرئيسية تطلب `/row` وتعرض البطاقة الأولى بعدّادها ولا رقائق ولا ورقة وتتبع الكاميرا (التكبير والدبّوس عند ٤٢٪) والدبّوس المبرز ودبابيس الفعالية والوظيفة، السهمان والدوران الحلقي، السحب القصير والطويل، النقر على دبّوس وظيفة، الفعل لكل نوع من الأنواع الخمسة، الزائر يطلب `/row` ولا شيء خاصاً والجرس يدعوه للدخول، الحالة الفارغة ثم «الأحدث أولاً»، الودجة وحدها (هيكل التحميل والفهرس من الأب)، والشريط الثابت. وحُدّثت `guest_browse_test.dart` (قائمة السماح `/row`) و`jobs_public_test.dart` (لا حقول رئيسية في الإدارة) و`post_editor_test.dart` (موضع `PostCard`).
