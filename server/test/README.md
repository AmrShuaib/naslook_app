# اختبارات إضافات الخادم

كل ملف `harness_*.mjs` يحمّل إضافة أو أكثر من `server/*.js` داخل Fastify حقيقي على Postgres 16 محلي ويستدعي المسارات بـ `fastify.inject` ويطبع `OK`/`FAIL` لكل حالة، وينتهي بـ `ALL OK` أو عدد الإخفاقات.

- المتطلبات: Node 22، Postgres 16 محلي على 127.0.0.1 بالمستخدم `postgres` وكلمة المرور `pg`، وقاعدة `naslife_test` (يُنشئها `run.sh` إن لم توجد).
- التشغيل: `server/test/run.sh harness_market_b.mjs` أو `server/test/run.sh all`.
- `harness_posts.mjs` و`harness_market_b.mjs` و`harness_admin.mjs` هي الأكثر استخداماً عند تعديل السوق والمدفوعات والمنشورات.
- `fake_smtp.mjs` خادم SMTP وهمي تستخدمه اختبارات البريد، و`blog_local.mjs` يشغّل المدونة محلياً.
- الإضافات تُحمَّل بمسارات نسبية (`../commerce.js`)، فلا تنقل المجلد خارج `server/`.
- الجلسات المتوازية تتصادم على `naslife_test` (كل حزمة تحذف جداولها). `NASLIFE_TEST_DB=naslife_test_x server/test/run.sh all` يوجّه كل `pg.Pool` إلى قاعدة مستقلة عبر `db_env.mjs`، والسجلات في `/tmp/naslife_test_x/`.
- `harness_moderation.mjs` (طابور الإشراف وأنواع البلاغ والحظر) و`harness_guest.mjs` (تصفح الضيف وحراسة iOS ومفاتيح المال). التفاصيل في `docs/moderation.md`.
