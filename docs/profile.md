# الملف الشخصي v2: غلاف وتعريف صوتي/مرئي ومتابعة وخصوصية

قرارات المالك: الألوان تبقى على التركوازي الحالي؛ الملف يحصل على تعريف ذاتي **صوتي أو مرئي**؛ إعادة تصميم كاملة بأربع شاشات (زائر، مالك، تعديل، توثيق وتحكّم) على نمط النموذج الأولي.

الإضافة `server/profile_v2.js` (مسجّلة آخر `register.txt` بعد `layout.js`) تضيف فوق ملف النواة: غلاف، اسم ظاهر، مسمّى وظيفي، مدينة وحي، حتى ثلاثة روابط تواصل، تعريف صوتي (≤60 ثانية) أو مرئي (≤30 ثانية)، متابعة بين المستخدمين، إحصاءات زيارات سبعة أيام للمالك، إعدادات خصوصية، وفحص توفر اسم المستخدم. الحزمة: `NASLIFE_TEST_DB=naslife_test_profile server/test/run.sh harness_profile_v2.mjs` (تطبع `ALL PROFILE V2 TESTS PASSED`). الخادم الوهمي `tools/dev/mockapi.mjs` يحاكي المسارات نفسها في الذاكرة (`profileV2Route`؛ المستخدم `SA0000001` عيّنة كاملة بغلاف وروابط وتعريف صوتي 42 ثانية).

## الخادم

### الجداول (تُنشأ في `profile_v2.js`)

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
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now())
user_follows   (follower_id, user_id, created_at, PRIMARY KEY (follower_id, user_id))
profile_views  (user_id, viewer_id, day DATE, PRIMARY KEY (user_id, viewer_id, day))   -- زيارة واحدة لكل زائر ويوم
profile_events (id BIGSERIAL, user_id, actor_id, kind, created_at)                     -- kind: message | share | follow | link
```

جداول النواة (`users`، `profiles`، `contacts`) تُقرأ فقط وتُكتشف أعمدتها عند الإقلاع عبر `information_schema` كما في `profile.js` و`admin.js`: اسم المستخدم (`nickname/name/handle/username`)، الصورة (`avatar_url/...`)، `created_at`، `login_verified`، و`profiles` بمفتاح `user_id` مع `bio` و`skills` و`is_public` و`account_type` إن وُجدت (وإلا يُكتشف جدول الملف بأعمدته). غياب أي جدول لا يُسقط الإضافة: تعيد أصفاراً و`null`. تُكتشف أيضاً `map_posts` و`market_reviews` و`market_orders` وجدول عضويات الدوائر (`vessel_members`/`memberships`/`circle_members`) وجدول الحضور (`presence`/`map_presence`) للإحصاءات والاتصال. `GET /profile/v2/status` يعرض ما اكتُشف.

### المسارات

| المسار | التوثيق | الوظيفة |
|---|---|---|
| `GET /profile/v2/status` | عام | `{ok:true, ...}` مع الجداول المكتشفة |
| `GET /profiles/:id/v2` | اختياري | ملف المستخدم كما يراه الزائر؛ `:id` معرّف (`SA0000002`) أو اسم مستخدم بلا حساسية للحالة (يُقبل `@` في أوله). زائر مسجّل غير المالك يُسجَّل في `profile_views` مرة في اليوم. مجهول → 404 |
| `GET /me/profile/v2` | مطلوب | الكائن نفسه للمالك + `settings` + `completion` |
| `PUT /me/profile/v2` | مطلوب | تعديل أي من `displayName, jobTitle, city, district, coverUrl, links, msgPolicy, showOnline, showCity, showFriends, introVisibility`؛ يعيد كائن `GET /me/profile/v2` |
| `PUT /me/profile/intro` | مطلوب | `{kind:'voice'|'video', url, sec}` → `{ok, intro}`؛ يضبط `intro_at=now()` ويحذف الملف القديم عبر `naslifeMediaDelete` إن توفّر |
| `DELETE /me/profile/intro` | مطلوب | يمسح التعريف → `{ok:true}` |
| `POST /profiles/:id/follow` / `DELETE` | مطلوب | `{ok, following, followers}`؛ متابعة النفس → 400 `self`؛ متكرر بلا أثر |
| `GET /profiles/:id/followers?limit=50` / `following` | عام | `{items:[{id, nickname, avatarUrl}]}` الأحدث أولاً (الحد 1..100) |
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
  "flags": { "isMe": false, "isFollowing": false, "isFriend": true, "canMessage": true, "online": null, "isPrivate": false, "blocked": false, "showFriends": true },
  "memberSince": "…" }
```

- `stats.posts` = منشورات الخريطة النشطة غير المنتهية؛ `friends` = صفوف `contacts` للمستخدم؛ `ratingAvg` (منزلة عشرية) و`ratingCount` من `market_reviews` بالبائع؛ `completedOrders` = طلبات `market_orders` بالحالة `completed/delivered/done`؛ `circles` = عضويات الدوائر إن وُجد جدولها وإلا 0.
- `trust.emailVerified` من `users.login_verified`؛ `phoneVerified` ثابت `false`؛ `respondsFast` ثابت `null` حالياً.
- `flags.online`: `null` إن أطفأ المستخدم `show_online` أو لا جدول حضور؛ وإلا متصل = تحديث خلال خمس دقائق.
- لصاحب الملف يُضاف: `settings: {msgPolicy, showOnline, showCity, showFriends, introVisibility}` و`completion: {pct, steps:[{id, done, label}]}` بسبع خطوات `avatar, cover, bio, links, intro, email, skills` و`pct` = المنجز/7 مقرّباً إلى أقرب 5.

### الفحص عند الحفظ

- النصوص القصيرة (`displayName, jobTitle, city, district`) تُشذّب ويجب ألا تتجاوز 40 حرفاً؛ غير ذلك 400 `{error:'bad-field', field}`.
- `coverUrl`: `null` أو `''` يمسح الغلاف؛ وإلا يجب أن يطابق قاعدة الوسائط `^(https?://host)?/chat/media/<اسم>$` (نفس قاعدة صورة الحساب) ويُخزَّن مطلقاً على الأصل العام (`PUBLIC_BASE_URL` أو مضيف الطلب بلا `www.`).
- `links`: مصفوفة حتى 3 عناصر `{kind, value}` بأنواع `instagram | x | tiktok | snapchat | website | other`. للشبكات تُشذَّب القيمة إلى اسم المستخدم فقط: تُزال `@` الأولى وبادئة `https?://(www.)?(instagram|x|twitter|tiktok|snapchat).com/` و`add/` وما بعد أول `/` أو `?`، ويجب أن تطابق `[A-Za-z0-9._-]{1,120}`. للموقع تُشذَّب فقط (بلا مسافات، ≤120). الرابط القياسي في الرد: `instagram.com/<v>`، `x.com/<v>`، `tiktok.com/@<v>`، `snapchat.com/add/<v>`، والموقع كما هو مع `https://` إن غابت.
- `msgPolicy` ∈ `all|friends|none`، `introVisibility` ∈ `all|friends`، والمفاتيح الثلاثة `showOnline/showCity/showFriends` منطقية.
- التعريف: `url` بقاعدة الوسائط، `sec` عدد صحيح 1..60 للصوت و1..30 للفيديو؛ غير ذلك 400 `{error:'bad-intro'}`.
- اسم المستخدم: `^[a-z0-9._]{3,20}$` بعد التحويل لحروف صغيرة (`short` لأقل من 3، `chars` لغير ذلك)؛ الأسماء `naslife, admin, support, jeddah, dammam` والأسماء الموجودة (بلا حساسية للحالة) والأسماء المحذوفة المحجوزة 90 يوماً (`globalThis.naslifeNickReserved`) → `taken`.

### قواعد الخصوصية

- **الملف الخاص** (`profiles.is_public=false`): لغير الصديق وغير المالك يعود كائن مختصر بـ200 لا 403: `{id, nickname, displayName, avatarUrl, coverUrl, flags:{isPrivate:true, ...}, stats:{}}`.
- **الصداقة** = صف في `contacts` بأي اتجاه بين الزائر وصاحب الملف.
- **التعريف**: يظهر للجميع عند `all`، وعند `friends` للأصدقاء والمالك فقط (`intro: null` لغيرهم).
- **المراسلة** (`flags.canMessage`): `all` → الجميع؛ `friends` → الأصدقاء؛ `none` → لا أحد؛ المالك دائماً `true`.
- **المدينة والحي** تُفرَّغان لغير المالك عند `show_city=false`.
- **الأصدقاء**: `stats.friends` يعود 0 لغير المالك عند `show_friends=false`، و`flags.showFriends` يخبر التطبيق هل يعرض الخانة.
- **الاتصال** يُخفى (`null`) عند `show_online=false`.
- المتابعون والمتابَعون قوائم عامة.
- **الإشعار**: عند أول متابعة من مستخدم يُرسل للمتابَع `{kind:'profile_follow', title:'<nickname> يتابعك', data:{userId:<المتابِع>}}` مرة واحدة لكل متابع (سجل `profile_events` بنوع `follow` يمنع التكرار عند إلغاء المتابعة وإعادتها).

### المساعدات العامة والحذف

- `globalThis.naslifeProfileExt(uid)` → صف `profile_ext` أو `null`.
- `globalThis.naslifeProfileV2Delete(uid)` → يحذف `profile_ext` و`user_follows` (الجانبان) و`profile_views` (الجانبان) و`profile_events` (الجانبان)؛ يعيد `true/false`.
- `server/account_delete.js` يمسح الجداول الأربعة مباشرة داخل معاملة الحذف الناعم (بجانب `user_layouts`) عند وجودها.

## التطبيق

(يُكمل من جانب التطبيق)
