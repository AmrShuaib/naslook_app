# الصفحات القانونية والموافقة

## الصفحات العامة (`server/legal_pages.js` + `server/legal_content.js`)

| الرابط | المحتوى |
|---|---|
| https://naslife.app/privacy | سياسة الخصوصية: البيانات التي يجمعها الكود فعلاً، المعالِجون (ميسر، مزوّد البريد، الاستضافة، Anthropic في صندوق الدعم فقط)، الاحتفاظ، الحذف (`#delete-account`)، الحقوق، الأعمار |
| https://naslife.app/terms | شروط الاستخدام مع بند «لا تسامح مطلقاً مع المحتوى المسيء أو المستخدمين المسيئين» (شرط أبل 1.2)، الإشراف ومراجعة البلاغات خلال 24 ساعة، السوق والمحفظة، أنظمة المملكة |
| https://naslife.app/support | التواصل، الإبلاغ (`#report`)، الحظر (`#block`)، حذف الحساب (`#delete-account`)، المدفوعات |

- عربية مع قسم إنجليزي `#en` للمراجِع، بلا أي سكربت (ترويسة CSP في Caddy تمنع السكربتات المضمّنة).
- بريد الدعم من إعداد المنصة `supportEmail` وإلا `support@naslife.app`، ومعرّف الدعم في الدردشة من `supportHandle`.
- أي تعديل جوهري في النص: ارفع `LEGAL_VERSION` في `legal_content.js` فيُطلب من كل المستخدمين الموافقة مجدداً.
- النص مسودة تحتاج مراجعة مستشار قانوني (نظام حماية البيانات الشخصية، مدد الاحتفاظ المالية، صياغة المحفظة) وإضافة رقم السجل التجاري والعنوان الوطني.

## الموافقة

- التسجيل: مربع إلزامي `reg-terms` في `lib/screens/login_page.dart`، ويُرسل `acceptTerms: true` فيسجّل `auth_alias.js` الموافقة في `legal_consents`.
- المستخدمون الحاليون: `GET /legal/consent` يعيد `needs: true` فتظهر ورقة الموافقة مرة واحدة (`lib/pages/myspace/consent_sheet.dart`): موافقة أو تسجيل خروج. `POST /legal/consent {version}` يسجّلها.
- شاشة الدخول: روابط الشروط والخصوصية ورابط «الدعم والمساعدة».
- ماي سبيس ← «عن ناس لايف»: تواصل معنا، سياسة الخصوصية، شروط الاستخدام (تُفتح داخل التطبيق على iOS عبر `LegalLinks`).

## في App Store Connect

- Privacy Policy URL: `https://naslife.app/privacy`
- Support URL: `https://naslife.app/support`
