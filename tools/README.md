# أدوات النشر والفحص

- `publish_bundle.sh "رسالة"`: يدفع `build/web` إلى فرع `webapp-build` عبر worktree في `.wb/`؛ الخادم يسحبه خلال دقيقتين. ابنِ أولاً: `flutter build web --release --pwa-strategy=none -o build/web`.
- `verify_live.sh` و`verify_market2.sh` و`verify_market_b.sh` و`verify_profile_fix.sh`: فحوص حية بـ curl على naslife.app. تحتاج `NASLIFE_TOKEN` (رمز جلسة حساب المؤسس، يُرسل في الترويسة `x-token`). لا تكتب الرمز في أي ملف.
- `dev/`: خوادم محلية وهمية (`serve.sh` + `mockapi.mjs`)، بناء نسخة وهمية وإنتاجية (`build_both.sh`)، جلب صور البذور وصفحات المصغّرات، ولقطات شاشة عبر Chromium (`probe*.mjs`، `shot*.mjs`). تكتب مخرجاتها في `.scratch/` (أو `NASLIFE_SCRATCH`).
