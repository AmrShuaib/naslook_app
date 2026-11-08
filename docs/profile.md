# الملف الشخصي v2: غلاف وتعريف صوتي/مرئي ومتابعة وخصوصية

قرارات المالك: الألوان تبقى على التركوازي الحالي؛ الملف يحصل على تعريف ذاتي **صوتي أو مرئي**؛ إعادة تصميم كاملة بأربع شاشات (زائر، مالك، تعديل، توثيق وتحكّم) على نمط النموذج الأولي.

الإضافة `server/profile_ext.js` (مسجّلة آخر `register.txt` بعد `layout.js`) تضيف فوق ملف النواة: غلاف، اسم ظاهر، مسمّى وظيفي، مدينة وحي، حتى ثلاثة روابط تواصل، تعريف صوتي (≤60 ثانية) أو مرئي (≤30 ثانية)، متابعة بين المستخدمين، إحصاءات زيارات سبعة أيام للمالك، إعدادات خصوصية، وفحص توفر اسم المستخدم. الحزمة: `NASLIFE_TEST_DB=naslife_test_profile server/test/run.sh harness_profile_v2.mjs` (تطبع `ALL PROFILE V2 TESTS PASSED`). الخادم الوهمي `tools/dev/mockapi.mjs` يحاكي المسارات نفسها في الذاكرة (`profileV2Route`؛ المستخدم `SA0000001` عيّنة كاملة بغلاف وروابط وتعريف صوتي 42 ثانية).

## الخادم

### الجداول (تُنشأ في `profile_ext.js`)

```sql
profile_ext (
  user_id TEXT PRIMARY KEY,
  cover_url TEXT,                              -- رابط وسائط الخادم فقط (مطلق)
  display_name TEXT NOT NULL DEFAULT '',       -- ≤40
  job_title TEXT NOT NULL DEFAULT '',          -- ≤40، يُعرض وسماً بجانب الاسم لحساب pro
  city TEXT NOT NULL DEFAULT '', district TEXT NOT NULL DEFAULT '',   -- ≤40
  links JSONB NOT NULL DEFAULT '[]',           -- حتى 3 من {kind, value}
  intro_kind TEXT, intro_url TEXT, intro_sec INT, intro_at TIMESTAMPTZ,   -- voice | video | NULL
  intro_visibility TEXT NOT NULL DEFAULT 'all',      -- all | friends
  msg_policy TEXT NOT NULL DEFAULT 'all',            -- all | friends | none
  show_online BOOLEAN NOT NULL DEFAULT true, show_city BOOLEAN NOT NULL DEFAULT true, show_friends BOOLEAN NOT NULL DEFAULT false,
  account_type TEXT,                                 -- personal | pro (النواة ترفض pro)
  follow_notify BOOLEAN NOT NULL DEFAULT true,       -- «إشعارات من أتابعهم» (7 نوفمبر 2026)
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now())
user_follows   (follower_id, user_id, created_at, PRIMARY KEY (follower_id, user_id))   -- فهرسان: (user_id, created_at DESC) و(follower_id, created_at DESC)
follow_notify_log (follower_id, author_id, last_at, PRIMARY KEY (follower_id, author_id)) -- آخر إشعار لحظة جديدة: حد مرة كل 6 ساعات
profile_views  (user_id, viewer_id, day DATE, PRIMARY KEY (user_id, viewer_id, day))   -- زيارة واحدة لكل زائر ويوم
profile_events (id BIGSERIAL, user_id, actor_id, kind, created_at)                     -- kind: message | share | follow | link
```

جداول النواة (`users`، `profiles`، `contacts`) تُقرأ فقط وتُكتشف أعمدتها عند الإقلاع عبر `information_schema` كما في `profile.js` و`admin.js`: اسم المستخدم (`nickname/name/handle/username`)، الصورة (`avatar_url/...`)، `created_at`، `login_verified`، و`profiles` بمفتاح `user_id` مع `bio` و`skills` و`is_public` و`account_type` إن وُجدت (وإلا يُكتشف جدول الملف بأعمدته). غياب أي جدول لا يُسقط الإضافة: تعيد أصفاراً و`null`. تُكتشف أيضاً `map_posts` و`market_reviews` و`market_orders` وجدول عضويات الدوائر (`vessel_members`/`memberships`/`circle_members`) وجدول الحضور (`presence`/`map_presence`) للإحصاءات والاتصال. `GET /profile/v2/status` يعرض ما اكتُشف.

### المسارات

| المسار | التوثيق | الوظيفة |
|---|---|---|
| `GET /profile/v2/status` | عام | `{ok:true, ...}` مع الجداول المكتشفة |
| `GET /profiles/:id/v2` | اختياري | ملف المستخدم كما يراه الزائر؛ `:id` معرّف (`SA0000002`) أو اسم مستخدم بلا حساسية للحالة (يُقبل `@` في أوله). زائر مسجّل غير المالك يُسجَّل في `profile_views` مرة في اليوم. مجهول → 404 |
| `GET /profiles/:id/can-message` | مطلوب | فحص «من يراسلني» قبل أول رسالة → `{ok, reason:'friends-only'|'nobody'|'blocked'|null}` (القاعدة أدناه؛ `blocked` للحاظر وحده)؛ بلا جلسة 401، ومجهول 404 |
| `GET /me/profile/v2` | مطلوب | الكائن نفسه للمالك + `settings` + `completion` |
| `PUT /me/profile/v2` | مطلوب | تعديل أي من `displayName, accountType (personal|pro), jobTitle, city, district, coverUrl, links, msgPolicy, showOnline, showCity, showFriends, followNotify, introVisibility`؛ يعيد كائن `GET /me/profile/v2` |
| `PUT /me/profile/intro` | مطلوب | `{kind:'voice'|'video', url, sec}` → `{ok, intro}`؛ يضبط `intro_at=now()` ويحذف الملف القديم عبر `naslifeMediaDelete` إن توفّر |
| `DELETE /me/profile/intro` | مطلوب | يمسح التعريف → `{ok:true}` |
| `POST /profiles/:id/follow` / `DELETE` | مطلوب | `{ok, following, followers}`؛ متابعة النفس → 400 `self`؛ متكرر بلا أثر |
| `GET /profiles/:id/followers?limit=30&before=` / `following` | اختياري | `{items:[{id, nickname, displayName, avatarUrl, isFollowing, isMe}], next, total}` الأحدث متابعةً أولاً (الحد 1..100)؛ `next` مؤشر معتم يُعاد في `before` (القسم «قائمتا المتابعة» أدناه)؛ الملف الخاص 403 `private` لغير صاحبه ومن أضافهم |
| `GET /me/following/ids` | مطلوب | `{ids}`: من أتابعهم ومن أضفتهم إلى جهات اتصالي (حتى 5000، بلا طرفي حظر)، لإدراج اللحظات الحيّة في «أتابعهم» (`docs/row.md`) |
| `POST /profiles/:id/event` | اختياري | `{kind:'message'|'share'|'link'}` → `{ok:true}`؛ أفعال المالك على ملفه تُهمل؛ نوع مجهول → 400 `bad-kind` |
| `GET /me/profile/stats` | مطلوب | `{visits7, visits7Prev, messages7, follows7, shares7, links7, series:[{day:'YYYY-MM-DD', visits}]}` سبعة أيام من الأقدم إلى الأحدث (أيام Postgres `current_date`) |
| `GET /handles/check?nickname=` | عام | `{valid, available, reason:'short'|'chars'|'taken'|null}` |

### كائن الملف

```json
{ "id": "SA0000001", "nickname": "Fahad", "displayName": "فهد العتيبي", "avatarUrl": "…", "coverUrl": "…",
  "bio": "…", "accountType": "personal|pro", "jobTitle": "مصوّر", "city": "جدة", "district": "الشاطئ",
  "links": [{ "kind": "instagram", "value": "fahad", "url": "https://instagram.com/fahad" }],
  "intro": { "kind": "voice", "url": "…", "sec": 42, "at": "…" },
  "stats": { "posts": 2, "followers": 1, "following": 0, "circles": 0, "ratingAvg": 4.5, "ratingCount": 2, "completedOrders": 3, "friends": 1 },
  "trust": { "emailVerified": true, "phoneVerified": false, "memberSince": "…", "respondsFast": null },
  "flags": { "isMe": false, "isFollowing": false, "isFriend": true, "canMessage": true, "messageReason": null, "online": null, "isPrivate": false, "blocked": false, "showFriends": true },
  "memberSince": "…" }
```

- `stats.posts` = منشورات الخريطة النشطة غير المنتهية **التي يراها الزائر** (قاعدة رؤية اللحظات نفسها `naslifeMomentVisibleSql` بشكل الصف الواحد، فيطابق العدد ما يفتحه في تبويب المنشورات؛ لصاحب الملف كلها)؛ `friends` = صفوف `contacts` للمستخدم؛ `ratingAvg` (منزلة عشرية) و`ratingCount` من `market_reviews` بالبائع؛ `completedOrders` = طلبات `market_orders` بالحالة `completed/delivered/done`؛ `circles` = عضويات الدوائر إن وُجد جدولها وإلا 0.
- `trust.emailVerified` من `users.login_verified`؛ `phoneVerified` ثابت `false`؛ `respondsFast` ثابت `null` حالياً.
- `flags.online`: `null` إن أطفأ المستخدم `show_online` أو لا جدول حضور؛ وإلا متصل = تحديث خلال خمس دقائق.
- لصاحب الملف يُضاف: `settings: {msgPolicy, showOnline, showCity, showFriends, introVisibility, followNotify}` و`completion: {pct, steps:[{id, done, label}]}` بسبع خطوات `avatar, cover, bio, links, intro, email, skills` و`pct` = المنجز/7 مقرّباً إلى أقرب 5.

### الفحص عند الحفظ

- النصوص القصيرة (`displayName, jobTitle, city, district`) تُشذّب ويجب ألا تتجاوز 40 حرفاً؛ غير ذلك 400 `{error:'bad-field', field}`.
- `coverUrl`: `null` أو `''` يمسح الغلاف؛ وإلا يجب أن يطابق قاعدة الوسائط `^(https?://host)?/chat/media/<اسم>$` (نفس قاعدة صورة الحساب) ويُخزَّن مطلقاً على الأصل العام (`PUBLIC_BASE_URL` أو مضيف الطلب بلا `www.`).
- `links`: مصفوفة حتى 3 عناصر `{kind, value}` بأنواع `instagram | x | tiktok | snapchat | website | other`. للشبكات تُشذَّب القيمة إلى اسم المستخدم فقط: تُزال `@` الأولى وبادئة `https?://(www.)?(instagram|x|twitter|tiktok|snapchat).com/` و`add/` وما بعد أول `/` أو `?`، ويجب أن تطابق `[A-Za-z0-9._-]{1,120}`. للموقع تُشذَّب فقط (بلا مسافات، ≤120). الرابط القياسي في الرد: `instagram.com/<v>`، `x.com/<v>`، `tiktok.com/@<v>`، `snapchat.com/add/<v>`، والموقع كما هو مع `https://` إن غابت.
- `msgPolicy` ∈ `all|friends|none`، `introVisibility` ∈ `all|friends`، والمفاتيح الأربعة `showOnline/showCity/showFriends/followNotify` منطقية.
- التعريف: `url` بقاعدة الوسائط، `sec` عدد صحيح 1..60 للصوت و1..30 للفيديو؛ غير ذلك 400 `{error:'bad-intro'}`.
- اسم المستخدم: `^[a-z0-9._]{3,20}$` بعد التحويل لحروف صغيرة (`short` لأقل من 3، `chars` لغير ذلك)؛ الأسماء `naslife, admin, support, jeddah, dammam` والأسماء الموجودة (بلا حساسية للحالة) والأسماء المحذوفة المحجوزة 90 يوماً (`globalThis.naslifeNickReserved`) → `taken`.

### قواعد الخصوصية

- **الملف الخاص** (`profiles.is_public=false`): لغير الصديق وغير المالك يعود كائن مختصر بـ200 لا 403: `{id, nickname, displayName, avatarUrl, coverUrl, flags:{isPrivate:true, ...}, stats:{}}`.
- **الصداقة** (`flags.isFriend`، 6 نوفمبر 2026) = صاحب الملف أضاف الزائر إلى جهات اتصاله (`hasContact(owner, viewer)`). تعريف واحد يفتح الملف الخاص والتعريف «للأصدقاء» ولحظات الملف الخاص والمراسلة بسياسة `friends`: من أضاف صاحب ملف خاص من طرفه وحده (طلب لم يُقبل) يأخذ الكائن المختصر كالغريب، فلا نبذة ولا عدد منشورات يشمل لحظات لا يفتحها. (قبلها كان الملف يفتح بصف في `contacts` بأي اتجاه، فيرى صاحب الطلب المعلّق الملف كاملاً وعدداً للمنشورات وتبويب لحظات فارغاً.)
- **التعريف**: يظهر للجميع عند `all`، وعند `friends` للأصدقاء والمالك فقط (`intro: null` لغيرهم).
- **المراسلة** («من يراسلني»، `flags.canMessage` و`flags.messageReason` و`GET /profiles/:id/can-message` بقاعدة واحدة `messageGate`): المالك دائماً مسموح؛ زوج محظور (`naslifeIsBlocked` بأي اتجاه) → ممنوع حتى مع `all`، والسبب `blocked` لمن حظر فقط (`naslifeHasBlocked`) و`nobody` للمحظور حتى لا يكشف له الملف ولا الفحص أنه حُظر (`flags.blocked` يبقى false)؛ `all` → الجميع؛ من كتب لي صاحب الحساب سابقاً → مسموح أياً كانت السياسة (الرد لا يُمنع)؛ `friends` → من أضافه **صاحب الحساب** إلى جهات اتصاله (طلب الصداقة من طرف واحد لا يكفي، كـ`isFriend` أعلاه)؛ علاقة منصة مسجّلة في `globalThis.naslifeMessageAllow` (مرشح أجاب وفريق التوظيف، أطراف طلب سوق أو حجز دائرة قائم أو حديث؛ التفاصيل في `docs/chat.md` القسم 4) → مسموح أياً كانت السياسة؛ وإلا `friends-only` أو `nobody`. الضيف مسموح عند `all` فقط. جدول رسائل النواة يُكتشف عند الإقلاع (`messages` ثم `direct_messages/dm_messages/chat_messages` بمرسل `sender_id/from_id/user_id/author_id` ومستلم `recipient_id/to_id/receiver_id/peer_id`، ويظهر في `GET /profile/v2/status` كـ`messages`)؛ بدونه يبقى استثناء الرد في التطبيق وحده (آخر 50 رسالة محمّلة؛ انظر `docs/chat.md` القسم 4). فشل فحص الحظر لا يقفل أحداً. `globalThis.naslifeCanMessage(caller, target)` للإضافات الأخرى.
- **حدود الضمان**: الإرسال مسار النواة `POST /messages` ولا تستطيع الإضافات حراسته (أبناء `app.register` مغلّفون)، فالضمان في التطبيق وفي هذا الفحص المسبق كما في `docs/chat.md` القسم 4؛ عميل يرسل مباشرة إلى النواة يتجاوزه.
- **المدينة والحي** تُفرَّغان لغير المالك عند `show_city=false`.
- **الأصدقاء**: `stats.friends` يعود 0 لغير المالك عند `show_friends=false`، و`flags.showFriends` يخبر التطبيق هل يعرض الخانة.
- **الاتصال** يُخفى (`null`) عند `show_online=false`.
- **قائمتا المتابعة** (7 نوفمبر 2026، تقرير النواقص القسم 2 البند 1 والبند «قائمة متابِعيّ ومن أتابعهم»): عامتان للملف العام (والضيف يراهما)، وللملف الخاص لصاحبه ولمن أضافهم صاحبه فقط (تعريف الصديق الواحد) وإلا 403 `private`؛ طرفا حظر (أي اتجاه) لا يرى أحدهما قائمتي الآخر (403 `private` أيضاً حتى لا يعرف المحظور)؛ ومن حظرهم المشاهد أو حظروه لا يظهرون في أي قائمة يراها (`total` يبقى العدد كله كما في الملف). الترتيب الأحدث متابعةً أولاً ثم المعرّف تنازلياً، والمؤشر `next` = `"<created_at بالميكروثانية>~<المعرّف>"` لآخر صف (يُقارن صفاً `(created_at, id) <` بترتيب الفرز نفسه، فمتابعات تتشارك الزمن لا تسقط ولا تتكرر)؛ قيمة غير مفهومة تبدأ من الأول. لكل شخص `isFollowing` (المشاهد يتابعه) و`isMe` و`displayName`. العملاء الأقدم (`limit=50` و`items` وحدها) يعملون كما كانوا.
- **الإشعار**: عند أول متابعة من مستخدم يُرسل للمتابَع `{kind:'profile_follow', title:'<nickname> يتابعك', data:{userId:<المتابِع>}}` مرة واحدة لكل متابع (سجل `profile_events` بنوع `follow` يمنع التكرار عند إلغاء المتابعة وإعادتها).

- **لحظات الملف الخاص** (6 نوفمبر 2026، الخطأ 2 في القسم 5 من `docs/reports/naslife_gaps_2026-11-05.md`): وعد مفتاح «ملف عام» في `privacy_control_page.dart` («غير العام يخفي منشوراتك عن غير الأصدقاء») صار حقيقياً للحظات الخريطة. صاحب الملف غير العام (`is_public=false` في `users` أو في جدول الملف، كما يقرؤه `coreProfile`) لا يرى لحظاته إلا هو وأصدقاؤه، والإدارة للإشراف. **الصديق هنا بتعريف «من يراسلني» نفسه** (`hasContact`): من أضافه صاحب الملف إلى جهات اتصاله؛ إضافة الطرف الآخر وحده (طلب غير مقبول) لا تفتح شيئاً، وهو `isFriend` نفسه الذي يفتح الملف الخاص. بلا عمود الخصوصية في النواة = الجميع عامّ (السلوك السابق)، وبلا جدول جهات الاتصال = لا أصدقاء. إن غابت هذه القاعدة (الإضافة غير مسجّلة، أو تعثّرت قبل نشرها) فاحتياط `map_posts.js` **مغلق** لا «الجميع عامّ»: لحظة الملف الخاص لصاحبها وحده حتى تعود. التطبيق والمسارات في `docs/moments.md` «من يرى اللحظة».

### إشعار المتابِعين بلحظة جديدة (7 نوفمبر 2026)

`map_posts.js` يستدعي بعد إدراج اللحظة والبث الحي `globalThis.naslifeNotifyFollowers(row)` (سطر واحد، لا ينتظره النشر). الدالة في `profile_ext.js` تحسب المستلمين وتحجز الحد في استعلام واحد:

- من **يتابع** الناشر (`user_follows`) و**يرى اللحظة** بقاعدة الرؤية الواحدة (`naslifeMomentVisibleSql` بشكل الصف الواحد، المشاهد = `f.follower_id`): لحظة «الأصدقاء» تصل من أضافهم الناشر فقط، ولحظات الملف الخاص كذلك؛ اللحظة نشطة غير منتهية.
- لا يصل من حظره الناشر أو حظر الناشر (`naslifeBlockedIds` في الاتجاهين)، ولا من أطفأ «إشعارات من أتابعهم» (`profile_ext.follow_notify = false`)، ولا الناشر نفسه.
- **مرة لكل ناشر ومتابِع كل 6 ساعات**: `INSERT INTO follow_notify_log ... ON CONFLICT DO UPDATE ... WHERE last_at <= now() - 6h RETURNING` فلحظتان معاً لا ترسلان إشعارين، ولحظة لا يراها المتابِع (للأصدقاء) لا تستهلك دوره.
- الإشعار `{kind:'follow_moment', title:'لحظة جديدة من <الاسم الظاهر أو النك نيم>', body:<التعليق حتى 100 حرف، أو العنوان، أو «صورة/فيديو/تسجيل صوتي/لحظة»>, data:{postId, userId, nickname}}` يفتح اللحظة (`docs/notifications.md`).
- **دفعات متتالية**: المستلمون (حتى 5000) يُرسل إليهم 100 في كل نداء لـ`naslifeNotify` بمهلة 250 م.ث بين الدفعات (`followNotifyChunk`/`followNotifyPauseMs` في خيارات الإضافة)، لأن `notify.js` يدرج صفاً لكل مستلم ويطلق لكلٍّ دفعاً للمتصفح لا ينتظره (استعلام اشتراكات ثم اتصال HTTPS)، فنداء واحد بآلاف المتابِعين كان يملأ مجمّع القاعدة المشترك ويفتح آلاف الاتصالات معاً. النشر لا ينتظر شيئاً من ذلك.
- الحزمة: `harness_follow_feed.mjs` (من يرى ومن لا يرى، الحظر بالاتجاهين، الإيقاف وإعادة التفعيل، الحد وأنه لا يُستهلك بلحظة لا تُرى، الملف الخاص، النص الاحتياطي، المعرّف غير الصالح، و250 متابِعاً في ثلاث دفعات متتالية).

### المساعدات العامة والحذف

- `globalThis.naslifeProfileExt(uid)` → صف `profile_ext` أو `null`.
- `globalThis.naslifeAuthorVisibleSql(authorExpr, viewerExpr, { single, publicWhen })` → شرط SQL منطقي واحد «هل يرى `viewerExpr` محتوى `authorExpr`؟» (صاحبه، أو ملف عام، أو صديق بالتعريف أعلاه)، مغلّف بـ`COALESCE(..., false)` فيصلح في `WHERE` وفي `SELECT ... AS visible`. `publicWhen` (اختياري، 6 نوفمبر 2026) شرط SQL على الصف نفسه يقيّد فرع «الملف العام» وحده: `صاحبه OR (publicWhen AND ملف عام) OR صديق`؛ عليه يبني «الجمهور» لكل لحظة في `map_posts.js` (`publicWhen` = `p.audience = 'all'`)، ومعه يعمل فحص الأصدقاء حتى بلا عمود خصوصية في النواة. الدالة تحمل العلامة `publicWhen = true` فلا يمرّر `map_posts.js` الشرط إلا لقاعدة تفهمه (وإلا احتياطه المغلق). التعبيران نصيان (`p.user_id` و`$1::text`؛ `NULL` للضيف). **شكلان** للقاعدة نفسها:
  - **القوائم** (الافتراضي): استعلامات فرعية غير مرتبطة بالصف: معرّفات أصحاب الملفات الخاصة (`users` ثم جدول الملف بـ`UNION ALL`) ومن أضافوا المشاهد، فيحسبها Postgres مرة لكل استعلام (`hashed SubPlan` في `EXPLAIN`) لا لكل صف، وتبقى كلفتها المقدّرة صغيرة مع آلاف اللحظات.
  - **صف واحد** (`{ single: true }`): فحوص مفاتيح مرتبطة بالصف (`EXISTS` على `users.id` ومفتاح جدول الملف وزوج `contacts(user_id, contact_id)`)، فقراءة لحظة واحدة (`/mapposts/:id`، الإعجاب، التفاعلات، كل عنصر في «محفوظاتي» حتى 300 في الطلب و5000 في الكنس، بطاقة المحادثة، رابط المشاركة، عدّ منشورات الملف) لا تمسح جدول الملفات كله في كل نداء. لا يُستعمل للقوائم: Postgres يقدّر الشكل المرتبط بفحص لكل صف فتكبر الكلفة المقدّرة مع عدد اللحظات حتى تتجاوز عتبة JIT (`jit_above_cost`) فيُترجم الاستعلام عند كل طلب.

  فحص جهات الاتصال آخر الشرط فلا يُقيَّم إلا لصف صاحبه خاص، والأسماء المستعارة الداخلية `vis_u/vis_p/vis_c` حتى لا تحجب اسماً مستعاراً في الاستعلام الخارجي. بلا عمود الخصوصية يعيد `($viewer IS NULL OR TRUE)` (يذكر المعامل حتى لا يرفض Postgres معاملاً مرسلاً غير مستعمل). العمود غير النصي (uuid/رقم) يُحوَّل نصاً عند الإقلاع. **تُنشر المساعدات الأربعة أول الإقلاع**، بعد اكتشاف جداول النواة مباشرة وقبل جداول الإضافة ومساراتها، فتعثّر ما بعدها لا يترك المنصة على الاحتياط؛ والإضافة غير مغلّفة بـ`try/catch` فتعثّرها يُفشل الإقلاع ويتراجع النشر التلقائي.
- `globalThis.naslifeIsPublic(uid)` → `true/false` (`true` بلا عمود خصوصية؛ خطأ القاعدة يُرمى ليقرر المستدعي، والبث الحي يغلق عند الشك).
- `globalThis.naslifeFriendIds(uid)` → من أضافهم المستخدم إلى جهات اتصاله (حتى 5000)، بالتعريف نفسه.
- `globalThis.naslifePrivacyStatus` → `{ privacy, friends }`: هل وُجد عمود الخصوصية وجدول جهات الاتصال.
- ميزة «الجمهور» لكل لحظة (6 نوفمبر 2026، الافتراضي «الأصدقاء» بقرار المالك) تبني فوق هذه في `map_posts.js` (`naslifeMomentVisibleSql` بخيار `publicWhen`، و`momentAudience` بـ`naslifeIsPublic` و`naslifeFriendIds`). لحظة «الأصدقاء» لا يراها إلا صاحبها ومن أضافهم ولو كان ملفه عاماً، والملف الخاص يبقى لأصدقائه وحدهم مهما كان الجمهور. عدّ «المنشورات» في الملف (`stats.posts`) يمر بالقاعدة نفسها فيعدّ لكل مشاهد ما يفتحه، وبلا `map_posts.js` (نادر) يمرّر `publicWhen` بنفسه إن وُجد عمود `audience`. التفاصيل في `docs/moments.md` «جمهور اللحظة».
- `globalThis.naslifeFollowFeedIds(uid)` → من أتابعهم ∪ من أضفتهم (حتى 5000، بلا نفسي ولا طرفي حظر)؛ تقرؤه «أتابعهم» في `row.js` و`GET /me/following/ids`.
- `globalThis.naslifeNotifyFollowers(post)` → إشعار المتابِعين أعلاه؛ يعيد معرّفات من أُرسل إليهم.
- `globalThis.naslifeProfileV2Delete(uid)` → يحذف `profile_ext` و`user_follows` (الجانبان) و`profile_views` (الجانبان) و`profile_events` (الجانبان) و`follow_notify_log` (الجانبان)؛ يعيد `true/false`.
- `server/account_delete.js` يمسح الجداول الخمسة نفسها مباشرة داخل معاملة الحذف الناعم (بجانب `user_layouts`) عند وجودها، ومنها `follow_notify_log` من الجانبين؛ هذا هو مسار الحذف الفعلي، و`naslifeProfileV2Delete` مساعد لا يستدعيه الإنتاج (تختبره الحزم وحدها)، فأي جدول جديد للملف يُضاف إلى `account_delete.js` و`harness_account_delete.mjs`.

## التطبيق

إعادة تصميم ملف المستخدم بأربع شاشات على النموذج التفاعلي `docs/reports/proto_profile/template.html` (و`template_colors.html` الذي أضاف «عرّف بنفسك»)، بلوحة الألوان الحالية (`Joy`، فيروزي على أبيض). الخادم في `server/profile_ext.js` وعقده في تقرير التصميم؛ التطبيق يعمل بملف النواة وحده حين يغيب v2 على الخادم (404) فلا تنكسر أي شاشة.

### الملفات

| الملف | الدور |
|---|---|
| `lib/api/profile_v2_models.dart` | `ProfileV2` ومعه `ProfileLink` و`ProfileIntro` و`ProfileStats` و`ProfileTrust` و`ProfileFlags` و`ProfileSettings` و`CompletionStep`/`ProfileCompletion` و`ProfileStats7` و`HandleCheck` و`FollowResult`؛ كلها بـ`fromJson` متسامح، ومعها `profileCities` (جدة والدمام وأحياؤهما) و`monthYear`/`clockText`. |
| `lib/api/profile_v2_api.dart` | `extension ProfileV2Api on ApiClient`: `profileV2`، `myProfileV2`، `updateProfileV2`، `setIntro`، `deleteIntro`، `follow`/`unfollow`، `followers`/`following`، `followPage` (صفحة `FollowPage` بالمؤشر)، `followFeedIds` (`GET /me/following/ids`)، `profileEvent` (خلفي لا يفشل)، `profileStats7`، `checkHandle`. |
| `lib/state/profile_v2_providers.dart` | `profileV2Provider(idOrHandle)` و`myProfileV2Provider` (يعيدان null عند 404 أو ردّ بلا معرّف)، `profileStats7Provider`، `followersProvider`/`followingProvider`، `userPostsProvider` (بث الخريطة بمرشّح `authors`)، `sellerListingsProvider` (`/market?seller=`). |
| `lib/pages/profile/user_profile_page.dart` | شاشة ١ «ما يراه الزائر» (`UserProfilePage(person:)`، `openProfile()` كما كان). |
| `lib/pages/profile/edit_profile_page.dart` | شاشة ٣ «تعديل الملف» (`EditProfilePage`). |
| `lib/pages/profile/privacy_control_page.dart` | شاشة ٤ «التوثيق والتحكم» (`PrivacyControlPage`). |
| `lib/pages/profile/owner_cards.dart` | بطاقات شاشة ٢ في ماي سبيس (`OwnerProfileCards`): التعريف، اكتمال الملف، آخر 7 أيام. |
| `lib/pages/profile/intro_card.dart` | `ProfileIntroCard` (صوت/فيديو)، `IntroVoiceBar` (مشغّل مضغوط لرابط أو بايتات)، `IntroCallToAction` (الإطار المتقطّع). |
| `lib/pages/profile/profile_bits.dart` | قطع مشتركة: `CoverBox`، `CoverButton`، `ProfileChip`، `ChipGroup`، `StatCell` (و`onTap` اختياري)، `profileLinkIcon`. |
| `lib/pages/profile/follow_list_page.dart` | `FollowListPage(userId:, name:, followers:)`: تبويبا «متابِعون» و«يتابع» (`follow-tab-followers`/`follow-tab-following`)، كل تبويب `FollowListView` بصفحاته (`followPage(before:)`) عند الاقتراب من النهاية أو بزر `follow-more`، صف لكل شخص (`follow-row-<id>`) يفتح ملفه، وزر متابعة متفائل (`follow-row-btn-<id>`: «متابعة»/«تتابعه»، لا يظهر لصفي ولا للضيف)، و«القائمة خاصة» (`follow-private`) عند 403، و«لا متابِعين بعد»/«لا يتابع أحداً بعد» (`follow-empty`). |
| `lib/pages/myspace/myspace_page.dart` | تعديلات صغيرة: زر التعديل يفتح `EditProfilePage`، صف «عرض ملفي العام» يفتح `UserProfilePage(person: me)`، «الخصوصية والأمان» يفتح `PrivacyControlPage` (وفيها المحظورون والمكتومون إلى `SafetyPage`)، و`OwnerProfileCards` تحت بطاقة الملف. حُذف مربع `_edit` القديم ودوال الصورة (انتقلت إلى شاشة التعديل). |

### الشاشات

#### ١ الزائر (`UserProfilePage`)
- غلاف (`profile-cover`: الصورة أو تدرّج فيروزي) وفوقه رجوع ومشاركة (`share-profile`، تسجّل حدث `share`) وإدارة الحساب للمدير (`admin-user`) وقائمة المزيد (`profile-menu` → `profile-report`/`profile-block`/`profile-unblock`). الصورة تتداخل مع حافة الغلاف.
- الاسم المعروض (وإلا النك نيم) + علامة التوثيق الزرقاء (`verified-mark`) + وسم المسمى (`job-tag` للمحترف) ثم `@nickname · المدينة · الحي · متصل الآن`. العلامة الزرقاء **محجوزة لتوثيق الهوية** (تظهر عند `trust.phoneVerified`، الثابت `false` حتى يُبنى توثيق الجوال/نفاذ)؛ تأكيد البريد وحده لا يضعها (6 نوفمبر 2026، فجوة 8: الزائر كان يفهمها توثيق هوية).
- شارة «محظور» (`blocked-banner` + `unblock-btn`) كما كانت.
- الأزرار: «مراسلة» (`message-btn`، تسجّل حدث `message` ثم تفتح المحادثة) أو بديلها (`message-off`) حين `canMessage=false` بنص السبب: «لا يستقبل رسائل من غير الأصدقاء»، أو «لا يستقبل رسائل جديدة» (`nobody`)، أو «حظرت هذا الشخص» (`blocked`، للحاظر وحده)، أو «بانتظار قبول طلب الصداقة» حين `friends-only` والزائر أضاف صاحب الملف إلى جهات اتصاله (فيصير زر الصداقة «طلب مُرسل» بدل «صديق» حتى لا يقول الملف «صديق» و«غير الأصدقاء» معاً)؛ «متابعة/تتابعه» (`follow-btn`، متفائلة، تعيد الحالة عند الخطأ)؛ «إضافة صديق/صديق» (`friend-btn`). لصاحب الحساب: «تعديل الملف» (`edit-profile-btn`) مع «هذا ملفك كما يراه الزوار».
- النبذة (`profile-bio`)، الروابط (`profile-link-N`، تفتح خارجياً عبر `url_launcher` وتسجّل حدث `link`؛ `profileLinkOpenOverride` للاختبارات)، بطاقة «<الاسم> يعرّف بنفسه» (`intro-card`، `intro-play`؛ الفيديو يبدّل الملصق بـ`VideoView` في `intro-video`).
- صف الأرقام (`stats-row`: منشور، متابِعون `stat-followers`، يتابع `stat-following`، التقييم، دوائر)؛ «متابِعون» و«يتابع» يفتحان `FollowListPage` على تبويبهما، وبعد العودة يُعاد جلب الملف (متابعات من داخل القائمة تغيّر أرقامه). المتابعة من الملف أو القائمة تستدعي `onFollowChanged` لتحديث «أتابعهم» في «اللحظات». وشارات الثقة («بريد مؤكد» بأيقونة بريد `email-confirmed`، يرد سريعاً، N طلباً مكتملاً، عضو منذ).
- ست تبويبات كرقائق (`tab-posts|market|services|circles|reviews|about`): المنشورات شبكة مصغّرات (`posts-grid`) تفتح العارض، أو العدد وزر «عرض على الخريطة» (`posts-fallback`) إن تعذّر الجلب؛ السوق شبكة `ListingCard` (`market-grid`)؛ الخدمات `offerings` من ملف النواة (`userProfileProvider` بقي كما هو)؛ الدوائر عدد فقط الآن؛ التقييمات ملخّص المتوسط والعدد؛ عنه: المهارات والهوايات ويبحث عن + نوع الحساب والمدينة وعضو منذ والرقم SA («يظهر للأصدقاء فقط» لغير الصديق).
- الملف الخاص (v2 `isPrivate` بلا `isFriend`، أو رفض النواة 403/404): الرأس والأزرار ثم حالة «ملف خاص» (`private-state`) بلا أرقام ولا تبويبات، ونصها «تفاصيل هذا المستخدم ولحظاته تظهر لأصدقائه فقط». من أضاف صاحب الملف الخاص ولم يضفه صاحبه: زر الصداقة «طلب مُرسل» والنص «تظهر تفاصيله ولحظاته بعد أن يقبل طلب صداقتك» (لا «صديق» بجانب «لأصدقائه فقط»)؛ «بانتظار قبول طلب الصداقة» مكان زر المراسلة يبقى لسياسة `friends-only` وحدها. ومن أضافه صاحبه (`isFriend`) يرى الملف كاملاً بأرقامه وتبويباته. الزائر بلا حساب: بطاقة الدخول كما كانت (`guest-profile-card`، `guest-profile-login`) ولا تُطلب أي مسارات حساب.

#### ٢ صاحب الحساب (ماي سبيس)
تحت بطاقة الملف (`owner-cards`، تظهر فقط حين يردّ `/me/profile/v2`): بطاقة التعريف مع «تغيير» (`intro-change`) أو الدعوة المتقطّعة «عرّف بنفسك بصوتك أو بفيديو» (`intro-cta`)؛ «اكتمال الملف N٪» (`completion-card`) بشريط وخطوات (`completion-<id>`؛ الخطوة تفتح التعديل، و`email` تفتح التوثيق والتحكم)؛ «آخر 7 أيام» (`stats7-row`: زيارات الملف مع نسبة التغيّر، رسائل من الملف، متابعون جدد).

#### ٣ تعديل الملف (`EditProfilePage`)
- «إلغاء» (`edit-cancel`) و«حفظ» (`edit-save`) في الشريط. الغلاف (`edit-cover` يرفع ويعرض فوراً ويُحفظ مع «حفظ»، `edit-cover-remove`) والصورة (`edit-avatar`/`edit-avatar-remove`: رفع ثم `POST /profile/avatar` فوراً وتحديث الجلسة كما في المسار القديم).
- الاسم المعروض (`edit-name`)، اسم المستخدم (`edit-handle`، فحص `GET /handles/check` بعد 400ms، النتيجة في `handle-status`: «متاح» أو السبب؛ عند الحفظ يُرسل `PATCH /me` إن كان متاحاً وإن رفضته النواة تظهر رسالة لطيفة ويكمل الحفظ)، النبذة (`edit-bio`، عدّاد 160).
- «عرّف بنفسك»: بطاقتا نمط (`intro-voice`/`intro-video`). الصوت: `intro-record` يبدأ `VoiceRecordSession` بمؤقّت حي (`intro-timer`) يتوقف عند 60 ثانية، `intro-stop`، ثم معاينة `intro-preview-play` و«إعادة التسجيل» (`intro-rerecord`) و«اعتماد» (`intro-use`: `uploadMedia` ثم `PUT /me/profile/intro`). الفيديو: `intro-video-camera`/`intro-video-gallery` عبر `pickVideo` (حتى 30 ثانية؛ المدة المجهولة تُمرَّر 30 ويتحقق الخادم). التعريف المحفوظ يظهر ببطاقته مع «إعادة التسجيل/التصوير» (`intro-replace`) و«حذف» (`intro-delete`).
- نوع الحساب (`acct-personal`/`acct-pro`) والمسمى المهني (`edit-job`) للمحترف؛ المدينة والحي (`edit-city`/`edit-district` من `profileCities`)؛ المهارات رقائق مع حذف و«+ إضافة» (`skill-add`، حتى 8)؛ الروابط حتى 3 (`link-kind-N`، `link-value-N`، `link-remove-N`، `link-add`)؛ الرقم SA ثابت.
- الحفظ: `PUT /me/profile` (bio, skills, hobbies, lookingFor) ثم `PUT /me/profile/v2` (displayName, accountType, jobTitle, city, district, coverUrl, links)؛ 404 من v2 لا يُفشل الحفظ. نوع الحساب في `profile_ext.account_type` لا في النواة (5 نوفمبر 2026): `PUT /me/profile` في النواة يرفض `pro` بالخطأ `bad-account-type` فكان الحفظ المهني يفشل كله؛ القراءة تقدّم قيمة `profile_ext` ثم عمود النواة.

#### ٤ التوثيق والتحكم (`PrivacyControlPage`)
درجة التوثيق (البريد من `trust.emailVerified` ويُكتب «مؤكد» بأيقونة بريد لا علامة توثيق، الجوال والهوية «قريباً»)؛ من يراسلني (`msg-policy` مقسّم: الجميع/الأصدقاء/لا أحد → `msgPolicy`)؛ ما يظهر في ملفي (`show-online`، `show-city`، `intro-visibility` all↔friends، `show-friends`، والرقم SA للأصدقاء دائماً، و`profile-public` عبر `updateProfile({'isPublic'})` في النواة)؛ الإشعارات: «إشعارات من أتابعهم» (`follow-notify` → `followNotify`؛ هنا لأن قسم «الإشعارات» في ماي سبيس يخص اشتراك هذا المتصفح ولا شاشة لإعدادات كل نوع)؛ الأمان (`safety-blocked` و`safety-muted` إلى `SafetyPage` بعدد كل منهما، والأجهزة «قريباً»). التغييرات متفائلة وتُعاد عند الخطأ.

### مسار الوسائط
التسجيل الصوتي عبر `VoiceRecordSession` (MediaRecorder على الويب، `record` إلى m4a على الجوال) → `uploadMedia(bytes, contentType, fileName)` إلى `/chat/upload` (يحوّل الصوت والفيديو على الخادم) → `setIntro(kind, url, sec)` بالرابط النسبي `/chat/media/...`. الفيديو عبر `pickVideo(gallery:, maxDuration: 30s)` ثم الرفع ثم `setIntro`. العرض: `IntroVoiceBar` فوق `VoicePlayer` (play داخل حدث اللمس لأجل iOS)، والفيديو `VideoView(url:)` بعد لمس الملصق.

### الاختبارات
`test/profile_v2_test.dart` (MockClient، `VoiceRecordSession.factoryOverride`، `VoicePlayer.factoryOverride`، `VideoView.factoryOverride`، `profileLinkOpenOverride`، `pickImageOverride`): النماذج؛ الزائر (العرض الكامل، المتابعة POST/DELETE مع العدّاد المتفائل، الرابط والحدث، التبويبات الست، `canMessage=false`، الملف الخاص، الملف الخاص لمن أضافه من طرفه فقط «طلب مُرسل» بلا أرقام ولا تبويبات، والملف الخاص لمن أضافه صاحبه كاملاً، غياب v2، ملفي)؛ التعديل (الحفظ وأجسام PUT، فحص الاسم بعد 400ms، التسجيل الصوتي حتى `PUT /me/profile/intro` والحذف، الصورة)؛ التوثيق والتحكم (كل مفتاح ومفتاح النواة)؛ ماي سبيس (البطاقات الثلاث والصفوف الجديدة، الدعوة بلا تعريف، ولا شيء إضافي بلا v2). `test/message_gate_test.dart`: فحص «من يراسلني» قبل أول رسالة في المحادثة و«محادثة جديدة» وإعادة التوجيه (التفاصيل في `docs/chat.md` القسم 4). `test/user_profile_test.dart` عُدّل ليختار التبويبين «عنه» و«الخدمات» بدل توقّع كل شيء في شاشة واحدة، و`test/profile_market_test.dart` يمرّ على شاشة التعديل الجديدة بنصوصه نفسها.

`test/follow_feed_test.dart` (7 نوفمبر 2026): قائمتا المتابعة (الصفحات بالمؤشر، التبويب المختار، المتابعة وإلغاؤها من الصف، صفي بلا زر، «القائمة خاصة»، الفراغ)، رقما الملف يفتحان القائمتين، ومفتاح «إشعارات من أتابعهم»؛ ومعها رقاقة «أتابعهم» (`docs/row.md`): تغيّر جهات الاتصال يجدّد المعرّفات فتُدرج لحظة الصديق الجديد ولا تُدرج لحظة من أُزيل وتزول بطاقته في مكانها، وإلغاء متابعة الوحيد الذي أتابعه يفرغ القائمة في مكانها ويدعو إلى المتابعة.

الخادم: `server/test/harness_follow_feed.mjs` (القوائم والإشعار و«أتابعهم»)، و`server/test/harness_profile_v2.mjs` يغطي فوق ما سبق من أضاف صاحب الملف من طرفه فقط (التعريف «للأصدقاء» مخفي عنه، والملف الخاص مختصر بلا أرقام مع وجود لحظة نشطة)، وعدد منشورات الصديقة وصاحبة الملف = اللحظة التي تفتحانها؛ و`harness_private_moments.mjs` يطابق عدد منشورات الملف بما تفتحه الصديقة في `/mapposts/feed?authors=` (التفاصيل في `docs/moments.md` «الاختبار»).
