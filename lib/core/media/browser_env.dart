import 'browser_env_stub.dart' if (dart.library.js_interop) 'browser_env_web.dart' as impl;

/// أين يعمل تطبيق الويب: كل بيئة لها طريق مختلف للسماح بالميكروفون، وبعضها يمنعه كلياً.
enum BrowserHost {
  /// متصفح داخلي لتطبيق آخر (واتساب، سناب، إنستغرام…): يمنع الميكروفون غالباً ولا إعداد له.
  inApp,

  /// مثبّت على الشاشة الرئيسية في آيفون: لا شريط عنوان، والإذن من إعدادات الجوال.
  iosStandalone,

  /// سفاري على آيفون.
  iosSafari,

  /// متصفح آخر على آيفون (كروم، فايرفوكس…): إذنه من إعدادات الجوال باسم المتصفح.
  iosOther,

  /// أندرويد وسطح المكتب.
  other,
}

const _inAppMarks = ['Instagram', 'FBAN', 'FBAV', 'FB_IAB', 'Snapchat', 'WhatsApp', 'Twitter', 'TikTok', 'musical_ly', 'BytedanceWebview', 'LinkedInApp', 'Line/'];
const _iosOtherMarks = ['CriOS', 'FxiOS', 'EdgiOS', 'OPiOS', 'DuckDuckGo'];

/// يصنّف البيئة من نص المتصفح (User-Agent) وحالة التثبيت على الشاشة الرئيسية. دالة خالصة لتُختبر بلا متصفح.
BrowserHost classifyBrowser(String ua, {required bool standalone}) {
  if (_inAppMarks.any(ua.contains)) return BrowserHost.inApp;
  final ios = ua.contains('iPhone') || ua.contains('iPad') || ua.contains('iPod');
  if (!ios) return BrowserHost.other;
  if (standalone) return BrowserHost.iosStandalone;
  if (_iosOtherMarks.any(ua.contains)) return BrowserHost.iosOther;
  return BrowserHost.iosSafari;
}

/// بيئة هذه الجلسة (خارج الويب: [BrowserHost.other]).
BrowserHost get browserHost => classifyBrowser(impl.userAgent, standalone: impl.standalone);

/// عنوان ورقة المساعدة بعد رفض الميكروفون.
String micDeniedTitle(BrowserHost h) => h == BrowserHost.inApp ? 'افتح ناس لايف في Safari' : 'الميكروفون غير مسموح';

/// خطوات السماح بالميكروفون بحسب البيئة.
String micDeniedHelp(BrowserHost h) => switch (h) {
      BrowserHost.inApp => 'فتحت ناس لايف من داخل تطبيق آخر، ومتصفحه الداخلي يمنع الميكروفون. اضغط زر القائمة (⋯) أو زر المشاركة واختر «فتح في Safari» أو «فتح في المتصفح»، ثم جرّب التسجيل من هناك.',
      BrowserHost.iosStandalone => 'افتح إعدادات الجوال ← التطبيقات ← Safari ← الميكروفون واختر «سؤال» أو «سماح» (في iOS الأقدم: الإعدادات ← Safari ← الميكروفون)، ثم أغلق ناس لايف تماماً وافتحه من جديد واضغط «سماح» حين يسألك.',
      BrowserHost.iosSafari => 'اضغط زر قائمة الصفحة (aA) في شريط العنوان ← إعدادات موقع الويب ← الميكروفون ← سماح، ثم أعد تحميل الصفحة وجرّب مجدداً.',
      BrowserHost.iosOther => 'افتح إعدادات الجوال ← اسم متصفحك ← فعّل الميكروفون، ثم عد وجرّب مجدداً. وإن بقي مرفوضاً فافتح naslife.app في Safari.',
      BrowserHost.other => 'اضغط الرمز بجانب عنوان الموقع (القفل أو رمز الإعدادات) ← الميكروفون ← سماح، ثم أعد تحميل الصفحة وجرّب مجدداً.',
    };
