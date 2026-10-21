# النسخ الاحتياطي والاستعادة (`server/backup.sh`)

**لماذا**: فحص 24 سبتمبر 2026 (`docs/reports/naslife_audit_2026-09-24.md`، القسم 6) لم يجد أي `pg_dump` ولا نسخ للوسائط؛ قاعدة البيانات والوسائط وCaddy ونواة Node كلها على خادم واحد (`91.108.111.246`)، ونواة Node في `/opt/naslife/src` ليست في git (المستودع يحوي إضافات `server/*.js` فقط). فقدان القرص كان يعني فقدان كل شيء، ومعه مفتاح التشفير `/opt/naslife/ops/auth-key` الذي بدونه لا تُستعاد عبارات الاسترداد لأي حساب.

**ما يفعله النظام** (21 أكتوبر 2026):

1. مؤقّت systemd `naslife-backup.timer` يشغّل `/opt/naslife/ops/backup.sh` كل ليلة الساعة 03:30 بتوقيت الرياض (و`Persistent=true`: إن كان الخادم مطفأً وقتها يعوّضها عند الإقلاع).
2. السكربت يأخذ `pg_dump -Fc` من قاعدة الإنتاج إلى `/opt/naslife/backups/db/naslife-YYYYmmdd-HHMM.dump` ويكتب بصمته في `.sha256` بجانبه. يُحتفظ بنسخ 14 يوماً (`KEEP_DAYS`).
3. يأخذ لقطة من مجلد الوسائط إلى `/opt/naslife/backups/media/<طابع زمني>/` بـ `rsync --link-dest` (الملفات التي لم تتغير روابط صلبة إلى اللقطة السابقة فلا تستهلك مساحة)، مع رابط `latest` إلى أحدث لقطة. يُحتفظ بـ7 لقطات (`KEEP_MEDIA`).
4. ينسخ ملفات الإعداد إلى `/opt/naslife/backups/config/<طابع زمني>/`: `auth-key`، `/etc/caddy/Caddyfile`، نواة Node `/opt/naslife/src` مضغوطة بلا `node_modules`، ووحدات systemd `naslife.service` و`naslife-autodeploy.*`.
5. إن ضُبطت وجهة خارج الخادم في `/opt/naslife/ops/backup.env` يزامن إليها: مع `rclone` (Backblaze B2 ونحوه) يرفع `db/` و`config/` كما هما وشجرة وسائط **واحدة** هي أحدث لقطة إلى `media/` (rclone لا يعرف الروابط الصلبة، فلو رفع كل اللقطات لتكررت الوسائط 7 مرات ولرُفعت كاملة كل ليلة)؛ ومع `rsync` عبر ssh (صندوق تخزين) يرفع المجلد كله مرآةً مع حفظ الروابط الصلبة (`-H`) فلا يُنقل ولا يُخزَّن إلا ما تغيّر.
6. يكتب الحالة في `/opt/naslife/ops/backup/last.json` (ذرياً) ويضيف سطراً واحداً إلى `/opt/naslife/ops/backup/backup.log`. أي فشل يُكتب أيضاً بـ`ok:false` ونص الخطأ، ويخرج السكربت بغير صفر فتظهر الوحدة فاشلة في systemd.
7. مؤقّت ثانٍ `naslife-backup-drill.timer` يشغّل `backup.sh --drill` كل أحد 04:30: يستعيد أحدث نسخة في قاعدة مؤقتة `naslife_restore_drill`، يعدّ الجداول وصفوف `users` و`wallet_tx` و`market_orders` و`map_posts`، يقارن عدد المستخدمين بالقاعدة الحية، ثم يحذف القاعدة المؤقتة ويكتب النتيجة في مفتاح `drill` من `last.json`.
8. الإضافة `server/backups.js` تعرض `GET /adminapi/backups` (للمديرين) فتظهر بطاقة «النسخ الاحتياطي» في «نظرة عامة» لوحة الإدارة.

## التثبيت (مرة واحدة، من أي جهاز)

1. من PowerShell أو أي طرفية (علامات اقتباس مفردة وبلا `$`):

   ```
   ssh root@91.108.111.246 'curl -fsSL https://raw.githubusercontent.com/AmrShuaib/naslook_app/claude/intelligent-hypatia-owb3fk/server/install-backup.sh | bash'
   ```

2. السكربت ينزّل `backup.sh` من الفرع المكتوب في `/opt/naslife/ops/branch`، يثبّت `rsync` إن غاب، يكتب `/opt/naslife/ops/backup.env` من قالب (إن لم يكن موجوداً)، يكتب الوحدات والمؤقّتين ويفعّلهما، ويشغّل أول نسخة فوراً.
3. المتوقع في النهاية سطر مثل `status ok=true dump=/opt/naslife/backups/db/naslife-20261021-1130.dump (38.2 MB) media=1840 files config=6 offsite=none/false` ثم جدول `list-timers` بموعدي التشغيل التاليين، ثم `BACKUP INSTALLED`.
4. افتح لوحة الإدارة ← نظرة عامة ← بطاقة «النسخ الاحتياطي»: يجب أن تقول «آخر نسخة قبل أقل من ساعة …» مع تلميح كهرماني «لا نسخة خارج الخادم» حتى تُضبط الخطوة التالية.
5. إعادة تشغيل أمر التثبيت آمنة (يحدّث السكربت والوحدات ولا يلمس `backup.env` الموجود).

اكتشاف القاعدة تلقائي: `DATABASE_URL` من بيئة وحدة `naslife` في systemd، ثم `/opt/naslife/.env` أو `/opt/naslife/src/.env`، وإلا `sudo -u postgres` على أول قاعدة اسمها يبدأ بـ`naslife`. إن أخطأ (البطاقة تقول «فشلت آخر نسخة» بنص خطأ اتصال) اكتب `DATABASE_URL=` صراحةً في `backup.env`.

## نسخة خارج الخادم (مهم: بدونها تبقى النسخ على القرص نفسه)

ملف الإعداد `/opt/naslife/ops/backup.env` (صلاحيات 600، لا يُوضع في المستودع). اختر طريقة واحدة:

### الطريقة أ: rclone إلى Backblaze B2 (الأرخص؛ نحو 6 دولارات لكل تيرابايت شهرياً)

1. في حساب Backblaze: أنشئ Bucket خاصاً باسم مثل `naslife-backups`، ثم Application Key مقيّداً بهذا الـBucket فقط (احفظ `keyID` و`applicationKey`؛ المفتاح لا يُعرض مرة ثانية).
2. على الخادم ثبّت rclone:

   ```
   curl -fsSL https://rclone.org/install.sh | bash
   ```

3. أنشئ الوجهة بلا أسئلة تفاعلية (استبدل القيمتين):

   ```
   rclone config create b2 b2 account KEY_ID key APPLICATION_KEY
   rclone lsd b2:
   ```

   يجب أن يظهر اسم الـBucket.
4. في `/opt/naslife/ops/backup.env` اكتب:

   ```
   BACKUP_RCLONE_REMOTE=b2:naslife-backups
   ```

5. شغّل نسخة يدوية للتحقق: `/opt/naslife/ops/backup.sh` ثم `rclone lsd b2:naslife-backups`. يجب أن تظهر ثلاثة مجلدات: `db` (كل نسخ القاعدة المحفوظة) و`config` (مجموعات الإعداد) و`media` (شجرة وسائط واحدة = أحدث لقطة؛ كل ليلة لا يُرفع إلا ما تغيّر فيها). البطاقة تصبح «خارج الخادم: نعم». حجم الـBucket يقارب حجم الوسائط مرة واحدة زائد نسخ القاعدة والإعداد.
6. تنبيه: المجلد يحوي `auth-key` ونسخة القاعدة بكل بياناتها، فالـBucket يجب أن يبقى خاصاً. لتشفير إضافي قبل الرفع أنشئ وجهة `crypt` فوق `b2` في rclone واجعل `BACKUP_RCLONE_REMOTE` تشير إليها.

### الطريقة ب: rsync عبر ssh إلى Hetzner Storage Box (أو أي خادم ssh)

1. في لوحة Hetzner فعّل SSH على الصندوق، وخذ اسم المستخدم والمضيف (مثل `u123456@u123456.your-storagebox.de`، المنفذ 23).
2. على الخادم أنشئ مفتاحاً بلا كلمة سر وانسخه إلى الصندوق:

   ```
   ssh-keygen -t ed25519 -N '' -f /root/.ssh/id_ed25519
   ssh-copy-id -p 23 -s u123456@u123456.your-storagebox.de
   ssh -p 23 u123456@u123456.your-storagebox.de 'mkdir -p naslife-backups && ls'
   ```

3. في `/opt/naslife/ops/backup.env`:

   ```
   BACKUP_SSH_TARGET=u123456@u123456.your-storagebox.de:naslife-backups
   BACKUP_SSH_OPTS=-p 23
   ```

4. شغّل `/opt/naslife/ops/backup.sh` وتأكد أن البطاقة تقول «خارج الخادم: نعم». الصندوق يحوي مرآة كاملة لمجلد النسخ (`db/` و`media/<اللقطات>` و`config/`)، والروابط الصلبة بين اللقطات تُعاد على الصندوق بفضل `rsync -H` فالمساحة هناك تقارب المحلية لا سبعة أضعافها.

إن فشلت المزامنة لاحقاً تبقى النسخة المحلية سليمة (`ok:true`) لكن السكربت يخرج بالرمز 2 والبطاقة تعرض «فشل النسخ خارج الخادم: …» بنص الخطأ.

### مثال كامل لـ `backup.env`

```
# نسخة خارج الخادم (واحدة فقط)
BACKUP_RCLONE_REMOTE=b2:naslife-backups
BACKUP_SSH_TARGET=
#BACKUP_SSH_OPTS=-p 23
# الاحتفاظ
KEEP_DAYS=14
KEEP_MEDIA=7
# يُضبطان فقط إن فشل الاكتشاف التلقائي
#MEDIA_DIR=/opt/naslife/media
#DATABASE_URL=postgres://naslife:secret@127.0.0.1:5432/naslife
```

## قراءة البطاقة في لوحة الإدارة

- «لم يُثبَّت بعد …» (كهرماني): لا يوجد ملف حالة؛ نفّذ أمر التثبيت أعلاه.
- «آخر نسخة قبل N ساعة · قاعدة البيانات X م.ب · الوسائط N ملفاً · خارج الخادم: نعم/لا»: كل شيء سليم. العدد أسفلها هو نسخ القاعدة المحفوظة على الخادم (المفترض 14 بعد أسبوعين).
- نص أحمر «فشلت آخر نسخة (…): …»: آخر تشغيل فشل، والنص هو خطأ الخطوة (مثل `pg_dump failed … database does not exist`). راجع السجل أدناه.
- نص أحمر «آخر نسخة ناجحة قديمة»: لم تنجح نسخة خلال 30 ساعة (المؤقّت متوقف أو الخادم كان مطفأً). افحص المؤقّتات.
- سطر التمرين: «ناجح قبل N يوماً» (رمادي)، يصبح كهرمانياً بعد 10 أيام بلا تمرين، وأحمر إن فشل التمرين مع سببه (مثلاً `users mismatch`).
- تلميح كهرماني «لا نسخة خارج الخادم»: `backup.env` بلا وجهة بعد.

## الاستعادة خطوة بخطوة (على خادم جديد أو بعد فقدان البيانات)

التحضير على الخادم الجديد: Ubuntu مع Postgres 16 وNode وCaddy، ثم جلب النسخ من الوجهة الخارجية إن لم تكن على القرص. من rclone (الوجهة تحوي شجرة وسائط واحدة هي أحدث لقطة، فتُستعاد مباشرة إلى مجلد الوسائط وتُتخطى الخطوة 4 أدناه):

```
mkdir -p /opt/naslife/backups /opt/naslife/media
rclone sync b2:naslife-backups/db /opt/naslife/backups/db
rclone sync b2:naslife-backups/config /opt/naslife/backups/config
rclone sync b2:naslife-backups/media /opt/naslife/media
```

أو من صندوق ssh (مرآة كاملة؛ `-H` يعيد الروابط الصلبة بين اللقطات):

```
rsync -azH -e 'ssh -p 23' u123456@u123456.your-storagebox.de:naslife-backups/ /opt/naslife/backups/
```

1. اختر النسخة وتحقق من سلامتها:

   ```
   ls -lt /opt/naslife/backups/db | head
   cd /opt/naslife/backups/db && sha256sum -c naslife-20261021-0330.dump.sha256
   ```

2. أوقف التطبيق والنشر التلقائي حتى لا يكتب أحد في القاعدة أثناء الاستعادة:

   ```
   systemctl stop naslife naslife-autodeploy.timer
   ```

3. استعد القاعدة في قاعدة جديدة ثم بدّل الأسماء (أسلم من الاستعادة فوق القاعدة الحالية):

   ```
   sudo -u postgres createdb naslife_restored
   sudo -u postgres pg_restore --no-owner --no-privileges -d naslife_restored < /opt/naslife/backups/db/naslife-20261021-0330.dump
   sudo -u postgres psql -c 'ALTER DATABASE naslife RENAME TO naslife_old'
   sudo -u postgres psql -c 'ALTER DATABASE naslife_restored RENAME TO naslife'
   ```

   إن كان التطبيق يتصل بدور غير `postgres` (انظر `DATABASE_URL` في بيئة الوحدة) أعطه الملكية:

   ```
   sudo -u postgres psql -d naslife -c 'ALTER DATABASE naslife OWNER TO naslife_app; REASSIGN OWNED BY postgres TO naslife_app'
   ```

   (استبدل `naslife_app` باسم الدور الفعلي.) على خادم جديد لا توجد قاعدة `naslife` أصلاً فأنشئها مباشرة باسم `naslife` وتخطَّ إعادة التسمية.
4. استعد الوسائط من أحدث لقطة (أو لقطة أقدم باسمها):

   ```
   mkdir -p /opt/naslife/media
   rsync -a /opt/naslife/backups/media/latest/ /opt/naslife/media/
   ```

   (المسار الفعلي للوسائط هو `media.source` في `last.json`؛ إن كان غيره فاستعد إليه.)
5. استعد الإعداد من `/opt/naslife/backups/config/<أحدث مجلد>/`:
   - `auth-key` ← `/opt/naslife/ops/auth-key` ثم `chmod 600`. بدونه لا تعمل استعادة الحسابات بالبريد ولا تغيير كلمة السر.
   - `Caddyfile` ← `/etc/caddy/Caddyfile` ثم `caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile` و`systemctl reload caddy` (وإن فُقدت كتلة `naslife.app` فـ`server/restore-caddy.sh` يعيدها).
   - `src.tar.gz` ← `tar -xzf src.tar.gz -C /opt/naslife` ثم `cd /opt/naslife/src && npm ci --omit=dev` (الحزم لم تُنسخ).
   - `naslife.service` و`naslife-autodeploy.service` و`naslife-autodeploy.timer` ← `/etc/systemd/system/` ثم `systemctl daemon-reload`. راجع في `naslife.service` قيمة `DATABASE_URL` والمنفذ.
6. شغّل التطبيق وتحقق:

   ```
   systemctl start naslife
   curl -fsS http://127.0.0.1:4000/health
   curl -sS https://naslife.app/settings/public
   ```

7. أعد تفعيل النشر التلقائي والنسخ: `systemctl start naslife-autodeploy.timer naslife-backup.timer naslife-backup-drill.timer`، ثم شغّل `/opt/naslife/ops/backup.sh` يدوياً وتأكد من بطاقة الإدارة.
8. بعد التأكد أياماً احذف القاعدة القديمة: `sudo -u postgres dropdb naslife_old`.

## التمرين الأسبوعي

- يعمل تلقائياً كل أحد 04:30 (ساعة بعد النسخة الليلية). يدوياً: `/opt/naslife/ops/backup.sh --drill`.
- ينجح حين تُستعاد النسخة بلا أخطاء وتوجد جداول وعدد المستخدمين المستعاد قريب من الحي (الفرق المسموح 2% أو 10 مستخدمين أيهما أكبر، لأن مستخدمين قد يسجّلوا أو يحذفوا حساباتهم بين النسخة والتمرين).
- النتيجة في مفتاح `drill` من `last.json` وفي سطر التمرين في البطاقة، وتُحذف قاعدة التمرين دائماً (حتى عند الفشل) ما دام اسمها اجتاز الحارس أدناه.
- الحارس: قبل أي `dropdb` يتحقق السكربت أن `DRILL_DB` ليس فارغاً ولا اسم القاعدة الحية ولا قاعدة نظام (`postgres`/`template*`)، ويفشل برسالة `DRILL_DB equals the live database` دون أن يلمس شيئاً (مسار الفشل لا يحذف قاعدة التمرين إلا بعد اجتياز الحارس). وكخط دفاع ثانٍ يتصل `createdb`/`dropdb` عبر القاعدة الحية (`--maintenance-db`) في كل الأوضاع فيرفض Postgres بدوره حذف القاعدة المفتوحة. خطأ مطبعي مثل `DRILL_DB=naslife` في `backup.env` آمن إذن.
- لو فشل التمرين بـ`pg_restore` (مثلاً امتداد يحتاج صلاحيات) فهذا تحذير حقيقي: النسخة قد لا تُستعاد عند الحاجة؛ أصلح السبب قبل الاعتماد عليها.

## السجلات والمؤقّتات

```
systemctl list-timers 'naslife-backup*'
tail -20 /opt/naslife/ops/backup/backup.log
cat /opt/naslife/ops/backup/last.json
journalctl -u naslife-backup -n 50 --no-pager
journalctl -u naslife-backup-drill -n 50 --no-pager
du -sh /opt/naslife/backups /opt/naslife/backups/*
```

- سطر السجل لكل تشغيل: `ok db=… bytes=… media=… config=… offsite=none/false kept=14/7 durationSec=…` أو `FAILED: <الخطوة> failed (exit N): <الخطأ>`.
- تشغيل يدوي في أي وقت: `/opt/naslife/ops/backup.sh` (آمن أثناء عمل التطبيق؛ قفل يمنع تشغيلين متزامنين).
- تحديث السكربت بعد تعديل `server/backup.sh` في المستودع: أعد أمر التثبيت نفسه.

## الاختبار

- خادم: `NASLIFE_TEST_DB=naslife_test_bk server/test/run.sh harness_backups.mjs`: الوحدة الخالصة والمسار (401/403/200، غياب الملف، ملف تالف، 40 ساعة، القائمة)، ثم السكربت الحقيقي في مجلد مؤقت (نسخة، sha256، لقطة وسائط، تمرين يطابق عدد المستخدمين ويحذف قاعدته، تدوير نسخة عمرها 20 يوماً وكنس بقايا `.dump.part`، فشل مع قاعدة غير موجودة بلا `.part` متبقٍّ، ملف البيئة). حارس التمرين يُجرَّب على قاعدة مستقلة لا يتصل بها أحد في وضع `url` وفي وضع `pgenv` (`systemctl` وهمي يعرض `PG*`): `DRILL_DB` = القاعدة الحية يفشل والقاعدة بجدولها باقية، واسم `postgres` يُرفض، وتمرين ناجح في وضع `pgenv`. في الحاوية لا `rsync` ولا `rclone`: لقطة الوسائط تصبح نسخة كاملة (ملاحظة في السجل)، والمزامنة خارج الخادم تُختبر بأداتين وهميتين تسجّلان الوسائط (rclone يرفع `db/` و`config/` ولقطة واحدة فقط؛ rsync عبر ssh يمرّر `-H`؛ فشل rclone يخرج بالرمز 2).
- تطبيق: `flutter test test/admin_backups_test.dart` (الحالات الثلاث للبطاقة وسطر التمرين وتلميح النسخ خارج الخادم).

## القرارات والمحاذير

- النسخة ليست مشفّرة على القرص (الخادم نفسه يحوي الأصل)؛ المجلد `/opt/naslife/backups` بصلاحيات 700 ونسخ القاعدة 600. التشفير خارج الخادم عبر `rclone crypt` اختياري.
- النسخة تُؤخذ من القاعدة الحية بلا إيقاف (`pg_dump` متسق بذاته)، ولقطة الوسائط ليست ذرية مع القاعدة: ملف رُفع في اللحظة نفسها قد يسبق صفّه أو يتأخر عنه بثوانٍ.
- `KEEP_DAYS` و`KEEP_MEDIA` يحكمان المساحة؛ القاعدة اليوم عشرات الميغابايت، والوسائط تنمو مع الروابط الصلبة بحجم ما يتغير فقط. خارج الخادم كذلك: rclone يحمل شجرة وسائط واحدة (أحدث لقطة فقط، فاللقطات الأقدم تبقى على الخادم وحده)، وrsync عبر ssh يحفظ الروابط الصلبة بـ`-H`.
- نسخة فشلت في منتصفها تُكتب في `naslife-<ts>.dump.part` ولا تُسمّى `.dump` إلا بعد النجاح؛ مسار الفشل يحذف `.part` فوراً، والتدوير يكنس أي بقايا `.part` من تشغيل أقدم.
- تمرين الاستعادة يتصل بالقاعدة ذاتها التي تؤخذ منها النسخة، وبحارس يمنع أن يكون اسم قاعدة التمرين فارغاً أو اسم القاعدة الحية أو قاعدة نظام، ولا يُستدعى `dropdb` قبل اجتيازه (التفاصيل في «التمرين الأسبوعي»).
