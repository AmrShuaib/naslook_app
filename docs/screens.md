# معرض التصاميم الخاص (`/screens`)

صفحة على `https://naslife.app/screens` تجمع نماذج التصميم التي يناقشها المالك، كل نسخة في تبويب، ولا تُفتح إلا برقم سري.

## للمالك
1. سجّل الدخول بحساب المدير في naslife.app.
2. افتح `naslife.app/screens/admin` من المتصفح نفسه، واكتب رقماً من 6 إلى 12 خانة، ثم «احفظ الرقم».
3. شارك الرابط `naslife.app/screens` مع الرقم لمن تريد.
4. تغيير الرقم من الصفحة نفسها يُخرج كل من دخل بالرقم القديم.

## الحماية
- الرقم لا يُكتب في المستودع ولا يُعاد من الخادم؛ يُخزَّن مجزّأً (scrypt) في جدول `screens_access`.
- الدخول كعكة موقّعة (HttpOnly، Secure، مسارها `/screens`) لسبعة أيام.
- 8 محاولات خاطئة من عنوان واحد تقفله ربع ساعة.
- الصفحات وملفات JS الخاصة بها لا تُقدَّم بلا دخول، وكلها `no-store` و`noindex`.

## التحديث
- المصادر: `docs/reports/screens/*.html` (كل نموذج صفحة مكتفية).
- `node tools/dev/build_screens.mjs` يولّد `server/screens_data.js` (يفصل CSS وHTML وJS لأن CSP يمنع السكربت المضمّن وخطوط Google).
- لإضافة تبويب: ضع الملف في المجلد وأضف سطره في `TABS` داخل المولّد.

## الفحص
- `server/test/run.sh harness_screens.mjs` (35 فحصاً).
- `cd server/test && node --import ./db_env.mjs screens_browser.mjs`: المحتوى الحقيقي في Chromium تحت CSP الحي.
