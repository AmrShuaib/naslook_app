# Naslife (naslook_app)

تطبيق **Naslife** بواجهة Flutter (ويب أولاً) وخادم Node/Fastify يعمل على `https://naslife.app`.

## البنية

| المسار | الوصف |
| --- | --- |
| `lib/` | تطبيق Flutter: الدخول بالنك نيم + الرقم السري، الرئيسية، الخريطة، الدوائر، المحادثات، ماي سبيس، المحفظة، الفعاليات والتذاكر، السوق |
| `lib/api/` | عميل HTTP/WebSocket لخادم Naslife (`client.dart`, `naslife_api.dart`, `commerce_api.dart`) |
| `server/tiles.js` | إضافة Fastify تمرّر بلاطات OpenStreetMap عبر الخادم مع تخزين مؤقت |
| `server/commerce.js` | إضافة Fastify للتجارة: المحفظة، الفعاليات والتذاكر، السوق (تنشئ جداولها بنفسها) |
| `server/register.txt` | أسطر تسجيل الإضافات التي تُدرج في `src/index.js` على الخادم |
| `server/autodeploy.sh` | يعمل على الخادم بمؤقّت systemd كل دقيقتين ويسحب التحديثات من GitHub |
| `server/install-autodeploy.sh` | تثبيت/تحديث النشر التلقائي على الخادم (آمن للتكرار) |
| `.github/workflows/deploy.yml` | يبني الويب عند كل push ويدفعه إلى فرع `webapp-build` ثم ينشر عبر SSH إن وُجد السر |

على الخادم: الكود في `/opt/naslife/src`، الملفات الثابتة في `/opt/naslife/webapp`، الخدمة `naslife` (systemd).

## التطوير محلياً

```bash
flutter pub get
flutter analyze
flutter run -d chrome            # يتجه إلى https://naslife.app تلقائياً
flutter build web --release      # الناتج في build/web
```

يمكن توجيه التطبيق لخادم آخر عبر `--dart-define=NASLIFE_API_BASE=https://...`.

## النشر

النشر آلي بالكامل بعد الإعداد الأول:

1. كل `push` إلى فرع العمل يشغّل GitHub Actions: `flutter analyze` ثم `flutter build web` ثم دفع الناتج إلى فرع `webapp-build`.
2. الخادم يسحب `webapp-build` وإضافات `server/*.js` كل دقيقتين عبر `autodeploy.sh` ويعيد تشغيل الخدمة عند تغيّر إضافات الخادم.

### الإعداد الأول على الخادم (مرة واحدة)

اختر إحدى الطريقتين:

**أ) سر في GitHub (موصى به):** أضف السر `NASLIFE_SSH_KEY_B64` (المفتاح الخاص بصيغة base64) في
`Settings → Secrets and variables → Actions`، ثم شغّل سير العمل من تبويب Actions أو ادفع أي تعديل.
سير العمل سيثبّت النشر التلقائي على الخادم ويتحقق من الموقع.

**ب) يدوياً من جهازك (PowerShell أو Terminal):**

```
ssh root@91.108.111.246 "curl -fsSL https://raw.githubusercontent.com/AmrShuaib/naslook_app/claude/intelligent-hypatia-owb3fk/server/install-autodeploy.sh | NASLIFE_BRANCH=claude/intelligent-hypatia-owb3fk bash"
```

بعدها كل تحديث يصل للخادم خلال دقيقتين دون تدخل. للتحقق:

```
curl -s https://naslife.app/health          # حالة الخادم
curl -s -o /dev/null -w "%{http_code}\n" https://naslife.app/wallet   # 401 = إضافة التجارة مسجّلة
```

### الرفع اليدوي المباشر

`./deploy.sh` يبني ويرفع `build/web` مباشرة إلى الخادم عبر `scp` (يحتاج مفتاح SSH على جهازك).
