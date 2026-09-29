# تخصيص الشاشة الرئيسية: إخفاء الكتل وترتيبها واختيار تبويبات الشريط السفلي

الإضافة `server/layout.js` (مسجّلة آخر `register.txt` بعد `account_delete.js`) تحفظ لكل مستخدم تخطيطه الخاص للشاشة الرئيسية: أي كتل يخفيها، بأي ترتيب تظهر، وأي تبويبات يضعها في الشريط السفلي. الحزمة: `NASLIFE_TEST_DB=naslife_test_layout server/test/run.sh harness_layout.mjs`. الخادم الوهمي للتطوير (`tools/dev/mockapi.mjs`) يحاكي المسارات نفسها في الذاكرة.

## الخادم

### الجدول

```sql
user_layouts (
  user_id    TEXT PRIMARY KEY,
  layout     JSONB NOT NULL,          -- { order, hidden, nav, opts }
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now())
```

صف واحد لكل مستخدم؛ غيابه يعني «لم يخصّص شيئاً» فيعرض التطبيق الافتراضيات. يُحذف الصف مع حذف الحساب (`server/account_delete.js`) ومن `globalThis.naslifeLayoutDelete(userId)`.

### المعرّفات الثابتة (تطابق التطبيق)

| الثابت | القيمة |
|---|---|
| `BLOCK_IDS` (كل الكتل) | `announce, quick, around, trending, open, circles, feed, biz, jobs, market, events` |
| `DEFAULT_ORDER` | `announce, quick, around, trending, open, circles, feed, jobs, market, events, biz` |
| `DEFAULT_PINNED` (مثبّت: لا يُخفى ويبقى أولاً) | `announce` |
| `NAV_IDS` (تبويبات الشريط) | `home, circles, chats, me, market, offers, jobs, events` |
| `DEFAULT_NAV` | `home, circles, chats, me` |

قاعدة الشريط: `home` أولاً و`me` أخيراً دائماً، والطول من 3 إلى 6 (تبويب واحد على الأقل بينهما وأربعة على الأكثر).

### شكل التخطيط المحفوظ

```json
{
  "order":  ["announce", "market", "quick", "around", "trending", "open", "circles", "feed", "jobs", "events", "biz"],
  "hidden": ["trending", "biz"],
  "nav":    ["home", "market", "chats", "me"],
  "opts":   { "around": ["food", "cafe"] }
}
```

- `order` يحوي **كل** الكتل المعروفة مرة واحدة (المخفية تحتفظ بموضعها حتى تعود). `hidden` مجموعة جزئية منها. `opts` خيارات حرة لكل كتلة (مثل فلاتر «حولك») يفسّرها التطبيق.
- **التطبيع** يُطبَّق عند كل قراءة وكل حفظ: المجهول يُسقط بصمت (نسخة تطبيق أحدث لا تكسر الحفظ)، المكرر يُزال، المثبّت يوضع أولاً ويُحذف من `hidden`، الكتل المعروفة الناقصة تُلحَق بآخر `order` بترتيب الافتراضي (كتلة جديدة لا تضيع عند من خصّص شاشته قبلها)، والشريط يُجبر على البدء بـ`home` والانتهاء بـ`me` ويُكمَّل من الافتراضي إن قصُر ويُقصّ إن طال. شريط غائب في صف قديم = الشريط الافتراضي.

### المسارات

| المسار | التوثيق | الوظيفة |
|---|---|---|
| `GET /me/layout` | اختياري | `{ layout, defaults: { order, nav }, pinned, updatedAt }`. للضيف ولمن لم يخصّص: `layout: null` و`updatedAt: null`؛ وإلا التخطيط المحفوظ بعد التطبيع. |
| `PUT /me/layout` | مطلوب | الجسم `{ order?, hidden?, nav?, opts? }`. الحقول الواردة تحلّ محل نظيرتها المحفوظة والباقي يبقى (فتحفظ ورقة الشريط جزءها وحده). يُعيد `{ ok, layout, updatedAt }` بالتخطيط المطبَّع. Upsert على `user_id`. |
| `DELETE /me/layout` | مطلوب | يحذف الصف (إعادة الافتراضيات). `{ ok: true }` ولو لم يوجد صف. |
| `GET /layout/status` | عام | `{ ok, blocks: BLOCK_IDS, nav: NAV_IDS }` للفحص الحي. |

### التحقق (`400 { error: "bad-layout" }`)

- `order`/`hidden`/`nav` إن وُجدت: مصفوفات نصوص، كل معرّف يطابق `^[a-z0-9_-]{1,32}$`، بحد 40 عنصراً.
- `nav` إن وُجد يجب أن يحوي `home` و`me` (الموضع يُصحَّح تلقائياً).
- `opts` إن وُجد: كائن بحد 40 مفتاحاً، كل مفتاح معرّف صالح وقيمته مصفوفة بحد 10 نصوص كل منها 40 حرفاً على الأكثر (تُقصّ الفراغات والفارغ يُسقط).
- المعرّفات المجهولة ليست خطأ: تُسقط بصمت. الجسم غير الكائن (مصفوفة أو نص) خطأ.
- بلا توثيق: `401 { error: "auth" }` على `PUT` و`DELETE`.

### الافتراضيات ومفاتيح الإدارة

تُقرأ من `globalThis.naslifeSettings` (لوحة الإدارة، `POST /adminapi/settings`؛ لا تظهر في `/settings/public`):

| المفتاح | الافتراضي | المعنى |
|---|---|---|
| `homeLayoutOrder` | `""` | معرّفات كتل مفصولة بفواصل؛ فارغ = `DEFAULT_ORDER`. المجهول يُسقط والناقص يُلحَق بترتيب `DEFAULT_ORDER`. |
| `homeLayoutPinned` | `"announce"` | الكتل المثبّتة مفصولة بفواصل؛ فارغ = لا شيء مثبّت (عندها يمكن إخفاء الإعلانات). |

القيمتان نصوص بحد 400 حرف من `[a-z0-9_,\s-]` فقط وإلا `400 bad-layout`. `defaults()` في الإضافة = `{ order: [المثبّت، ثم ترتيب الإعدادات، ثم ما نقص من DEFAULT_ORDER], nav: DEFAULT_NAV }` و`pinned()` تُصدَّران للاختبار مع `normalise()`.

## التطبيق

### نظام «الخريطة أولاً»

- الخريطة هي التبويب الأول والرئيسية معاً (`MapPage(home: true)` في `HomeShell.pageOf`): فوقها بحث زجاجي بصورة الحساب (`home-search`) وجرس التنبيهات (`home-bell`) ثم شرائح الطبقات، وتحتها الورقة السفلية `_AreaPanel` التي تعرض عناصر المنطقة ثم أقسام الرئيسية القابلة للتخصيص، وتُفتح حتى ٩٢٪ من الشاشة لتُقرأ كصفحة.
- شريط التنقّل كبسولة عائمة `lib/ui/joy_nav_bar.dart`: «الخريطة» أولاً و«ماي سبيس» آخراً وبينهما قسمان يختارهما المستخدم، وزر الكاميرا في الوسط يفتح المنشئ (`composePostHere`). الصفحات غير الخريطة تُحجز أسفلها `JoyNavBar.inset` حتى لا يختفي محتواها خلف الكبسولة (`extendBody: true`).
- الانتقال إلى تبويب بالاسم: `openNavTab(ref, 'circles')` في `home_page.dart` (يفتح التبويب إن كان في الشريط)، وصفحة الدائرة تعود إلى الخريطة بالفهرس 0، وماي سبيس بالفهرس الأخير.
- الأقسام المستقلة في الشريط (السوق، العروض، الوظائف، الفعاليات) تعرض شريطها العلوي الخاص (`HomeShell.ownBar`).

### الأقسام

`lib/core/home_layout.dart` يعرّف الأقسام (`homeBlocks`) والترتيب الافتراضي (`homeDefaultOrder`) والمثبّت (`announce`) وأقسام الشريط (`navTabs`، `navMiddleSlots = 2`)، والنموذج `HomeLayout` بعملياته: `hide/show/move/toTop/reorder/withNav/toggleOpt/reset` و`normalized` التي تحذف المجهول وتضيف الناقص آخر القائمة وتثبّت طرفي الشريط.

| المعرّف | القسم | المصدر |
|---|---|---|
| `announce` | إعلان المنصة (مثبّت، يظهر عند وجود إعلان) | `publicSettingsProvider` |
| `quick` | الاختصارات (الدوائر، السوق، العروض، الوظائف، الفعاليات، المحفظة، براندات، بث المدينة) | ثابت |
| `around` | لحظات حولك + بطاقة بث المدينة (خيار «الأصدقاء فقط») | `storiesProvider`، `recentPostsProvider` |
| `trending` | الأماكن الرائجة اليوم | `trendingPlacesProvider` |
| `open` | مفتوح الآن حولك | `discoverProvider` |
| `circles` | دوائرك | `myVesselsProvider` |
| `feed` | آخر ما في دوائرك (خيار «نصوص فقط») | `feedProvider` |
| `biz` | الدوائر التجارية | ثابت |
| `jobs` | وظائف جديدة | `jobsListProvider` |
| `market` | من السوق (القريب ثم الرائج) | `marketHomeProvider` |
| `events` | فعاليات قريبة | `eventsProvider` |

`homeBlockWidgets(context, ref)` في `lib/pages/home/home_page.dart` يبني الأقسام الظاهرة بترتيب المستخدم داخل `HomeBlock` (عنوان، إجراء «الكل»، زر «⋯»)، ثم `HiddenBlocksTray` إن وُجد مخفي. القسم الذي لا محتوى له الآن لا يُعرض (لا عنوان فارغاً). الأقسام الجديدة التي لم تكن في ترتيب المستخدم المحفوظ توسم «جديد» حتى يلمسها.

### التخصيص (النموذجان ١ و٢)

- **قائمة على القسم**: زر «⋯» (`block-menu-<id>`) يفتح ورقة: نقل لأعلى، نقل لأسفل، تثبيت في الأعلى، إخفاء القسم، تخصيص الرئيسية. المخفي يتجمّع في «أقسام مخفية» (`hidden-tray`، شرائح `show-<id>`).
- **شاشة التخصيص** `lib/pages/home/home_layout_page.dart` (من ماي سبيس `home-layout` أو من قائمة القسم): تبويب «الأقسام» بقائمة قابلة للسحب (`ReorderableListView`، المقبض `layout-drag-<id>`)، مفتاح إظهار (`layout-switch-<id>`)، وخيارات محتوى للقسم (`layout-opt-<id>-<opt>`)؛ وتبويب «شريط التنقّل» بمعاينة الكبسولة ومفاتيح (`nav-switch-<id>`) بحد قسمين والطرفان ثابتان؛ و«استعادة الافتراضي» (`layout-reset`).
- **الحالة** `lib/state/layout_providers.dart`: `homeLayoutProvider` يقرأ من الجهاز فوراً (`SharedPreferences` بالمفتاح `home_layout_v1`) ثم من `GET /me/layout`؛ تخصيص الحساب يتقدّم على الجهاز، وإن لم يكن للحساب تخصيص يُرفع تخصيص الجهاز. كل تعديل يُحفظ محلياً ويُدفع بـ `PUT /me/layout` بعد ٦٠٠ مللي ثانية، و«استعادة الافتراضي» تحذف السطر بـ `DELETE`. الزائر يحتفظ بتخصيصه على جهازه.

### الاختبارات

`test/home_layout_test.dart`: النموذج (التطبيع والحركات)، الرئيسية (الترتيب، الإخفاء إلى الصندوق والاستعادة، النقل، المزامنة مع الخادم)، أولوية تخصيص الحساب ووسم «جديد»، شاشة التخصيص (المفاتيح والخيارات واختيار الشريط والاستعادة)، وكبسولة التنقّل (الكاميرا في الوسط والشارات).

