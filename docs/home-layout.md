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

(يُكمل من جانب التطبيق)
