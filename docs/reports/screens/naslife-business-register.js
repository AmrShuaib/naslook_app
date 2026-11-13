// نماذج تسجيل الدائرة على /business/register: تسجيل حقيقي عبر مسارات الخادم نفسها التي يستخدمها التطبيق.
// التسلسل: حساب (جديد برمز تأكيد البريد، أو دخول بحساب قائم) ← رفع الشعار والوثيقة ← POST /biz/register ← طلب التوثيق.
// كل خطوة تُحفظ نتيجتها في الذاكرة فإعادة المحاولة بعد خطأ لا تكرر حساباً ولا دائرة. رمز الجلسة يبقى في الذاكرة فقط.
(function () {
  'use strict';
  var $ = function (id) { return document.getElementById(id); };
  var form = $('rg-form'); if (!form) return;
  // الفئات كما في الخادم (CATEGORIES) بأسمائها العربية
  var CATS = [['cafe', 'مقهى'], ['restaurant', 'مطعم'], ['shop', 'متجر'], ['services', 'خدمات وورش'], ['salon', 'صالون وتجميل'], ['clinic', 'عيادة'], ['hospital', 'مستشفى'], ['hotel', 'فندق'], ['car_rental', 'تأجير سيارات'], ['entertainment', 'ترفيه'], ['cinema', 'سينما'], ['brand', 'براند'], ['company', 'شركة'], ['university', 'جامعة'], ['other', 'أخرى']];
  $('rg-cats').innerHTML = CATS.map(function (c) { return '<label class="rg-chip"><input type="radio" name="category" value="' + c[0] + '">' + c[1] + '</label>'; }).join('');
  // وسط كل مدينة: موقع الدائرة حين لا يأذن المتصفح بالموقع (يُعدَّل لاحقاً من لوحة الدائرة)
  var CITY = { 'جدة': [21.5433, 39.1728], 'الدمام': [26.4207, 50.0888], 'الخبر': [26.2172, 50.1971], 'الظهران': [26.2886, 50.1140] };

  // نوع الصنف الافتراضي لكل فئة كما في الخادم (ITEM_KIND_OF)؛ المواعيد والعروض تحتاج أوقاتاً يومية
  var KIND = { cinema: 'showtime', hotel: 'room', car_rental: 'car', hospital: 'clinic', airport: 'info', salon: 'clinic', clinic: 'clinic', entertainment: 'showtime', other: 'info' };
  var kindOf = function () { return KIND[val('category')] || 'product'; };
  var slotted = function () { var k = kindOf(); return k === 'clinic' || k === 'showtime'; };
  var DAYS = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
  var state = { cover: null, coverUrl: null, coverOf: null, patched: false, items: [], warn: [], logo: null, doc: null, lat: null, lng: null, token: null, logoUrl: null, docUrl: null, logoOf: null, docOf: null, biz: null, verified: false, busy: false, pendingEmail: null };
  var val = function (n) { var e = form.elements[n]; return e ? String(e.value || '').trim() : ''; };
  var latin = function (s) { return String(s).replace(/[٠-٩]/g, function (d) { return '٠١٢٣٤٥٦٧٨٩'.indexOf(d); }).replace(/[۰-۹]/g, function (d) { return '۰۱۲۳۴۵۶۷۸۹'.indexOf(d); }); };
  // كما في normalizePhone بالخادم: يقبل 05XXXXXXXX و5XXXXXXXX و+9665XXXXXXXX
  var phone = function (v) { var m = /^(?:\+966|00966|966)?0?5(\d{8})$/.exec(latin(v).replace(/[\s\-().]/g, '')); return m ? '+9665' + m[1] : null; };
  var entity = function () { return val('entity') === 'freelance' ? 'freelance' : 'cr'; };
  var entNo = function () { return latin(val('entityNumber')).replace(/[\s\-]/g, ''); };
  var entOk = function () { return entity() === 'cr' ? /^\d{10}$/.test(entNo()) : /^[A-Za-z0-9]{8,20}$/.test(entNo()); };
  var later = function () { return $('rg-later').checked; };
  var hasAcc = function () { return val('acc') === 'login'; };
  var nick = function () { return val('nick').toLowerCase(); };
  var email = function () { return val('email').toLowerCase(); };

  var checks = {
    category: function () { return !!val('category'); },
    nameAr: function () { return val('nameAr').length >= 2; },
    logo: function () { return !!state.logo; },
    city: function () { return !!CITY[val('city')]; },
    phone: function () { return !!phone(val('phone')); },
    entityNumber: function () { return later() || entOk(); },
    doc: function () { return later() || !!state.doc; },
    nick: function () { return hasAcc() || /^[a-z0-9_]{3,25}$/.test(nick()); },
    email: function () { return hasAcc() ? val('email').length >= 3 : /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email()); },
    pass: function () { var n = form.elements.pass.value.length; return hasAcc() ? n >= 1 : n >= 8 && n <= 64; },
    agree: function () { return $('rg-agree').checked; },
    description: function () { var n = val('description').length; return n === 0 || n >= 20; },
    website: function () { return !val('website') || /^https?:\/\/[^\s]+\.[^\s]+$/.test(val('website')); }
  };
  // ساعات العمل بالصيغة التي يفهمها الخادم (parseHours): «يومياً 9:00 ص – 11:00 م» أو «السبت إلى الخميس …» أو «24 ساعة»
  function t12(v) { var m = /^(\d{2}):(\d{2})$/.exec(v || ''); if (!m) return null; var h = Number(m[1]), pm = h >= 12; return ((h % 12) || 12) + ':' + m[2] + (pm ? ' م' : ' ص'); }
  function hoursText() {
    var mode = val('hmode'); if (!mode) return '';
    if (mode === 'always') return '24 ساعة';
    var o = t12(val('hopen')), c = t12(val('hclose')); if (!o || !c) return '';
    return (mode === 'range' ? DAYS[Number(val('hfrom'))] + ' إلى ' + DAYS[Number(val('hto'))] : 'يومياً') + ' ' + o + ' – ' + c;
  }
  // ---- الأصناف: صفوف تُضاف وتُحذف؛ السعر يُكتب بالريال، والصنف بلا اسم يُتجاهل
  var itemSeq = 0;
  function addItem() {
    if (state.items.length >= 20) return;
    var id = ++itemSeq, it = { id: id, file: null, url: null, done: false }, el = document.createElement('div');
    el.className = 'rg-item'; el.dataset.id = id;
    el.innerHTML = '<label class="rg-drop" title="صورة الصنف"><input type="file" accept="image/png,image/jpeg,image/webp" aria-label="صورة الصنف"><span class="th doc"><svg class="i" aria-hidden="true"><use href="#r-img"/></svg></span></label>' +
      '<input class="rg-in t" maxlength="100" placeholder="اسم الصنف أو الخدمة" aria-label="اسم الصنف">' +
      '<input class="rg-in rg-ltr price" inputmode="decimal" maxlength="8" placeholder="السعر ر.س" aria-label="السعر بالريال">' +
      '<button type="button" class="x" aria-label="احذف الصنف">×</button>' +
      '<input class="rg-in wide d" maxlength="500" placeholder="وصف قصير (اختياري)" aria-label="وصف الصنف">' +
      '<input class="rg-in rg-ltr wide times" maxlength="60" placeholder="10:00, 16:00, 19:00" aria-label="أوقات المواعيد اليومية">' +
      '<label class="pv wide"><input type="checkbox" class="venue">الدفع في المكان (يُفتح بعد التوثيق)</label>';
    it.el = el; state.items.push(it); $('rg-items').appendChild(el);
    el.querySelector('.x').addEventListener('click', function () { state.items = state.items.filter(function (x) { return x !== it; }); el.remove(); sync(); });
    el.querySelector('input[type=file]').addEventListener('change', function (e) {
      var f = e.target.files && e.target.files[0]; if (!f || !/^image\/(png|jpeg|webp)$/.test(f.type) || f.size > 8 * 1024 * 1024) { it.file = null; return; }
      it.file = f; it.url = null; var th = el.querySelector('.th'); th.style.backgroundImage = 'url("' + URL.createObjectURL(f) + '")'; th.innerHTML = ''; sync();
    });
    sync();
    return it;
  }
  var itemData = function (it) {
    var q = function (c) { return String(it.el.querySelector(c).value || '').trim(); };
    var times = latin(q('.times')).split(/[,،\s]+/).map(function (t) { var m = /^(\d{1,2}):(\d{2})$/.exec(t); return m ? ('0' + m[1]).slice(-2) + ':' + m[2] : null; }).filter(function (t) { return t && /^([01]\d|2[0-3]):[0-5]\d$/.test(t); });
    // السعر يُكتب بالريال ويُرسل بالهللات (وحدة biz_items.price في الخادم والتطبيق)
    return { title: q('.t'), price: Math.max(0, Math.round((Number(latin(q('.price')).replace(/٫/g, '.').replace(/[^\d.]/g, '')) || 0) * 100)), description: q('.d'), times: times, venue: it.el.querySelector('.venue').checked };
  };
  var liveItems = function () { return state.items.filter(function (it) { return itemData(it).title; }); };
  // صف قرأناه من المنيو وسعره فارغ (لم يُقرأ ولم يكتبه المالك) لا يُرسل: كان سيُحفظ صنفاً مجانياً يُطلب. المجاني يُكتب 0 صراحة.
  var priceMissing = function (it) { return it.el.classList.contains('scanned') && kindOf() !== 'info' && !/\d/.test(latin(it.el.querySelector('.price').value)); };
  var rowOk = function (it) { var d = itemData(it); return d.title.length >= 2 && (!slotted() || d.times.length > 0) && !priceMissing(it); };
  var itemsOk = function () { return liveItems().every(rowOk); };
  var groups = { category: ['category'], identity: ['nameAr', 'logo'], place: ['city'], contact: ['phone'], verify: ['entityNumber', 'doc'], details: ['description', 'website'], account: ['nick', 'email', 'pass', 'agree'] };
  var field = function (k) { return form.querySelector('[data-f="' + k + '"]'); };

  function sync() {
    var fr = entity() === 'freelance', mob = val('presence') === 'mobile', acc = hasAcc();
    $('rg-ver-title').textContent = fr ? 'توثيق وثيقة العمل الحر' : 'توثيق السجل التجاري';
    $('rg-entno-lab').firstChild.nodeValue = fr ? 'رقم وثيقة العمل الحر ' : 'رقم السجل التجاري ';
    $('rg-entno').placeholder = fr ? 'FL-XXXXXXXX' : '1010XXXXXX';
    $('rg-entno').inputMode = fr ? 'text' : 'numeric';
    $('rg-entno-err').textContent = fr ? 'رقم الوثيقة من 8 إلى 20 حرفاً أو رقماً.' : 'رقم السجل التجاري عشرة أرقام.';
    $('rg-doc-lab').firstChild.nodeValue = fr ? 'صورة وثيقة العمل الحر ' : 'صورة السجل التجاري ';
    $('rg-ver').hidden = later();
    $('rg-radius-f').hidden = !mob;
    $('rg-loc-lab').firstChild.nodeValue = mob ? 'مركز نطاق خدمتك ' : 'موقع النشاط ';
    $('rg-locate').lastChild.nodeValue = mob ? 'موقعي الحالي مركزاً للنطاق' : 'أنا في المكان الآن';
    $('rg-radius-o').textContent = val('radiusKm') + ' كم';
    // الحساب: جديد (اسم مستخدم + بريد + كلمة سر) أو قائم (البريد أو اسم المستخدم + كلمة السر)
    field('nick').hidden = acc;
    $('rg-email-lab').firstChild.nodeValue = acc ? 'البريد أو اسم المستخدم ' : 'البريد الإلكتروني ';
    $('rg-email').placeholder = acc ? 'name@example.com' : 'name@example.com';
    $('rg-email-err').textContent = acc ? 'اكتب بريدك أو اسم المستخدم.' : 'اكتب بريداً إلكترونياً صحيحاً. يصلك عليه رمز تأكيد.';
    $('rg-pass').placeholder = acc ? 'كلمة سر حسابك' : '8 أحرف على الأقل';
    $('rg-pass-err').textContent = acc ? 'اكتب كلمة السر.' : 'كلمة السر من 8 إلى 64 حرفاً.';
    // بيانات الدائرة: الساعات والأصناف بحسب الفئة
    var hm = val('hmode'), sl = slotted(), k = kindOf();
    $('rg-hdays').hidden = hm !== 'range'; $('rg-htimes').hidden = !(hm === 'daily' || hm === 'range');
    $('rg-hprev').textContent = hoursText() ? 'ستظهر هكذا: ' + hoursText() : '';
    $('rg-items-lab').textContent = k === 'clinic' ? 'الخدمات والمواعيد' : k === 'showtime' ? 'العروض والتذاكر' : k === 'room' ? 'الغرف' : k === 'car' ? 'السيارات' : k === 'info' ? 'الخدمات والأقسام' : 'الأصناف';
    $('rg-item-add').textContent = '+ أضف ' + (k === 'product' ? 'صنفاً' : k === 'room' ? 'غرفة' : k === 'car' ? 'سيارة' : 'خدمة');
    state.items.forEach(function (it) {
      it.el.querySelector('.times').hidden = !sl; it.el.querySelector('.price').hidden = k === 'info'; it.el.querySelector('.pv').hidden = k === 'info';
      var d = itemData(it); it.el.classList.toggle('bad', it.el.classList.contains('bad') && !!d.title && !rowOk(it));
    });
    // المعاينة الجانبية
    var cat = CATS.filter(function (c) { return c[0] === val('category'); })[0];
    $('pv-name').textContent = val('nameAr') || 'اسم دائرتك';
    $('pv-cat').textContent = (cat ? cat[1] : 'نوع النشاط') + (val('city') ? ' · ' + val('city') : '');
    $('pv-pres').textContent = mob ? 'متنقلة · ' + val('radiusKm') + ' كم' : 'مكان ثابت';
    $('pv-ver').textContent = later() ? 'غير موثّقة بعد' : 'بانتظار التوثيق';
    Object.keys(groups).forEach(function (g) {
      var li = document.querySelector('#rg-steps [data-s="' + g + '"]');
      var okk = groups[g].every(function (k) { return checks[k](); });
      if (g === 'details') okk = okk && val('description').length >= 20 && !!hoursText() && liveItems().length >= 3 && itemsOk();
      li.classList.toggle('ok', okk);
      if (g === 'verify') li.textContent = later() ? 'التوثيق (لاحقاً)' : 'التوثيق';
    });
    // الخطأ يزول حال تصحيح الحقل
    Object.keys(checks).forEach(function (k) { var f = field(k); if (f && f.classList.contains('bad') && checks[k]()) f.classList.remove('bad'); });
  }

  function pick(input, thumb, title, key) {
    input.addEventListener('change', function () {
      var f = input.files && input.files[0];
      if (!f || !/^image\/(png|jpeg|webp)$/.test(f.type) || f.size > 8 * 1024 * 1024) { state[key] = null; title.textContent = f ? 'صورة PNG أو JPG حتى 8 م.ب' : title.textContent; sync(); return; }
      var url = URL.createObjectURL(f);
      thumb.style.backgroundImage = 'url("' + url + '")'; thumb.innerHTML = '';
      title.textContent = f.name.length > 28 ? f.name.slice(0, 25) + '…' : f.name;
      if (key === 'logo') { $('pv-logo').style.backgroundImage = 'url("' + url + '")'; $('pv-logo').innerHTML = ''; }
      state[key] = f; sync();
    });
  }
  pick($('rg-logo'), $('rg-logo-th'), $('rg-logo-t'), 'logo');
  pick($('rg-doc'), $('rg-doc-th'), $('rg-doc-t'), 'doc');
  pick($('rg-cover'), $('rg-cover-th'), $('rg-cover-t'), 'cover');
  $('rg-item-add').addEventListener('click', addItem);

  $('rg-locate').addEventListener('click', function () {
    var c = $('rg-coord'); c.hidden = false;
    var none = function () { state.lat = state.lng = null; c.textContent = 'تعذّر تحديد موقعك. سنضع الدائرة في وسط المدينة التي تختارها، وتعدّل موقعها لاحقاً من لوحتها.'; };
    if (!navigator.geolocation) return none();
    c.textContent = 'جارٍ تحديد موقعك…';
    navigator.geolocation.getCurrentPosition(function (p) { state.lat = p.coords.latitude; state.lng = p.coords.longitude; c.textContent = 'حُدد موقعك الحالي ✓'; }, none, { timeout: 10000, maximumAge: 60000, enableHighAccuracy: true });
  });

  // ---- الاتصال بالخادم
  var MSG = {
    'bad-email': 'البريد الإلكتروني غير صحيح.', 'invalid-nickname': 'اسم المستخدم: أحرف إنجليزية صغيرة وأرقام وشرطة سفلية، من 3 إلى 25.', 'weak-password': 'كلمة السر من 8 إلى 64 حرفاً.',
    'nickname-taken': 'اسم المستخدم محجوز. اختر غيره.', 'email-taken': 'هذا البريد مسجّل من قبل. اختر «لدي حساب» وادخل بكلمة سرّك.', 'too-many-attempts': 'محاولات كثيرة. انتظر قليلاً ثم أعد المحاولة.',
    'bad-credentials': 'البريد أو كلمة السر غير صحيحة.', 'invalid-credentials': 'البريد أو كلمة السر غير صحيحة.', 'bad-code': 'الرمز غير صحيح.', 'invalid-code': 'الرمز غير صحيح.', 'code-expired': 'انتهت صلاحية الرمز. اطلب رمزاً جديداً.', 'expired': 'انتهت صلاحية الرمز. اطلب رمزاً جديداً.',
    'unsupported-type': 'نوع الصورة غير مدعوم. استخدم PNG أو JPG.', 'media-storage-unavailable': 'رفع الصور متوقف مؤقتاً. حاول بعد قليل.', 'logo-required': 'الشعار إلزامي.',
    'bad-category': 'اختر نوع النشاط.', 'bad-name': 'اسم الدائرة غير صالح.', 'bad-location': 'الموقع خارج النطاق المدعوم.', 'bad-phone': 'رقم الجوال غير صحيح.', 'bad-radius': 'نطاق الخدمة من 2 إلى 50 كم.',
    'banned-words': 'في الاسم كلمة غير مسموحة.', 'suspended': 'هذا الحساب موقوف. راسل الدعم.', 'too-many': 'بلغ حسابك الحد الأعلى من الدوائر (20).',
    'ai-unavailable': 'قراءة المنيو غير مفعّلة الآن. أضف الأصناف يدوياً.', 'busy': 'الخدمة مشغولة اليوم. أضف الأصناف يدوياً أو أعد المحاولة غداً.', 'ai-failed': 'تعذّرت قراءة الصور. أعد المحاولة بعد قليل.', 'scan-failed': 'تعذّرت قراءة الصور. أعد المحاولة بعد قليل.',
    'ai-timeout': 'أخذت القراءة وقتاً طويلاً. أعد المحاولة بصورة أوضح أو بصور أقل.', 'rate-limited': 'قراءات كثيرة. انتظر عشر دقائق ثم أعد المحاولة.', 'scan-in-progress': 'قراءة سابقة ما زالت جارية. انتظر قليلاً.',
    'image-too-large': 'الصورة كبيرة جداً. اختر صورة أصغر.', 'too-many-images': 'أربع صور على الأكثر في القراءة الواحدة.', 'not-image': 'اختر صوراً بصيغة PNG أو JPG.', 'bad-image': 'تعذّر استخدام الصورة. اخترها من جديد.', 'image-not-found': 'تعذّر استخدام الصورة. اخترها من جديد.', 'image-expired': 'تعذّر استخدام الصورة. اخترها من جديد.',
    'bad-number': 'رقم الوثيقة غير صحيح.', 'doc-required': 'أرفق صورة الوثيقة.', 'network': 'تعذّر الاتصال. تحقق من الإنترنت ثم أعد المحاولة.'
  };
  function fail(code, status) { var e = new Error(code || 'error'); e.code = code || 'error'; e.status = status || 0; return e; }
  function call(method, url, body, raw) {
    var h = {}; if (state.token) h['x-token'] = state.token;
    var opt = { method: method, headers: h, credentials: 'omit', cache: 'no-store' };
    if (raw) { h['content-type'] = raw.type; opt.body = raw; } else if (body !== undefined) { h['content-type'] = 'application/json'; opt.body = JSON.stringify(body); }
    return fetch(url, opt).then(function (r) {
      return r.text().then(function (t) {
        var d = null; try { d = t ? JSON.parse(t) : {}; } catch (x) { d = {}; }
        if (!r.ok) { var e = fail(d && (d.error || d.code) || ('http-' + r.status), r.status); e.body = d; throw e; }
        d.__status = r.status; return d;
      });
    }, function () { throw fail('network'); });
  }
  var tokenOf = function (d) { return d && (d.token || (d.session && d.session.token) || (d.user && d.user.token)) || null; };
  var say = function (t) { $('rg-go-t').textContent = t; };
  var text = function (e) { return (e.code === 'rate-limited' && e.body && e.body.scope === 'day' && 'بلغت حد اليوم من قراءات المنيو. أضف الأصناف يدوياً أو أعد المحاولة غداً.') || MSG[e.code] || (e.status >= 500 ? 'حدث خطأ في الخادم. أعد المحاولة بعد قليل.' : 'تعذّر إكمال الخطوة (' + e.code + '). أعد المحاولة.'); };

  function login() {
    return call('POST', '/auth/login', { handle: hasAcc() ? val('email') : email(), password: form.elements.pass.value }).then(function (d) {
      state.token = tokenOf(d); if (!state.token) throw fail('no-session'); return true;
    });
  }
  // يعيد true حين توجد جلسة، و false حين ننتظر رمز البريد (تظهر بطاقة الرمز)
  function account() {
    if (state.token) return Promise.resolve(true);
    say('جارٍ تجهيز حسابك…');
    var askCode = function (mail) { state.pendingEmail = mail; showCode(mail); return false; };
    if (hasAcc()) return login().catch(function (e) { if (e.status === 403 && e.code === 'email-unverified') return askCode(e.body && e.body.email || val('email')); throw e; });
    return call('POST', '/auth/register', { email: email(), nickname: nick(), password: form.elements.pass.value, acceptTerms: true }).then(function (d) {
      if (d.pending) return askCode(d.email || email());
      state.token = tokenOf(d); if (!state.token) throw fail('no-session'); return true;
    });
  }
  function upload(file, urlKey, ofKey) {
    if (state[urlKey] && state[ofKey] === file) return Promise.resolve(state[urlKey]);
    return call('POST', '/chat/upload', undefined, file).then(function (d) { if (!d.url) throw fail('upload-failed'); state[urlKey] = d.url; state[ofKey] = file; return d.url; });
  }
  function create() {
    if (state.biz) return Promise.resolve(state.biz);
    var mob = val('presence') === 'mobile', c = CITY[val('city')];
    var body = { category: val('category'), nameAr: val('nameAr'), name: val('name'), logoUrl: state.logoUrl, presence: mob ? 'mobile' : 'fixed',
      lat: state.lat != null ? state.lat : c[0], lng: state.lng != null ? state.lng : c[1], phone: phone(val('phone')), role: val('role') === 'manager' ? 'manager' : 'owner',
      address: [val('address'), val('district'), val('city')].filter(Boolean).join('، '), hours: hoursText(), description: val('description') };
    if (mob) { body.radiusKm = Number(val('radiusKm')) || 15; if (val('district')) body.districts = [val('district')]; }
    return call('POST', '/biz/register', body).then(function (d) { if (!d.biz || !d.biz.id) throw fail('register-failed'); state.biz = d.biz; return d.biz; });
  }
  function verify() {
    if (later() || state.verified) return Promise.resolve();
    return upload(state.doc, 'docUrl', 'docOf').then(function (url) {
      return call('POST', '/biz/' + encodeURIComponent(state.biz.id) + '/verification', { entityKind: entity(), entityNumber: entNo(), docUrl: url });
    }).then(function () { state.verified = true; });
  }

  // بيانات الإكمال بعد إنشاء الدائرة: كل خطأ هنا يُسجَّل تنبيهاً ولا يلغي الدائرة ولا يوقف ما بعده
  function details() {
    var id = encodeURIComponent(state.biz.id), warn = function (t) { return function (e) { state.warn.push(t + ': ' + text(e)); }; };
    var p = Promise.resolve();
    if (!state.patched) p = p.then(function () {
      var up = state.cover ? upload(state.cover, 'coverUrl', 'coverOf').catch(warn('صورة الغلاف')) : Promise.resolve();
      return up.then(function () {
        var b = {}; if (val('sector')) b.sector = val('sector'); if (val('website')) b.website = val('website'); if (state.coverUrl) b.coverUrl = state.coverUrl;
        if (!Object.keys(b).length) { state.patched = true; return; }
        return call('PATCH', '/biz/' + id, b).then(function () { state.patched = true; }, warn('بيانات الدائرة'));
      });
    });
    liveItems().forEach(function (it) {
      p = p.then(function () {
        if (it.done) return;
        var d = itemData(it), k = kindOf();
        say('جارٍ إضافة «' + d.title + '»…');
        var img = it.file && !it.url ? call('POST', '/chat/upload', undefined, it.file).then(function (r) { it.url = r.url; }, function () {}) : Promise.resolve();
        return img.then(function () {
          var b = { title: d.title, description: d.description, price: k === 'info' ? 0 : d.price, payAtVenue: k !== 'info' && d.venue };
          if (it.url) b.imageUrl = it.url;
          if (slotted()) b.meta = { times: d.times };
          return call('POST', '/biz/' + id + '/items', b).then(function () { it.done = true; }, warn('«' + d.title + '»'));
        });
      });
    });
    return p;
  }

  function run() {
    if (state.busy || state.scanning) return; state.busy = true;
    var btn = $('rg-go'), sum = $('rg-sum'); btn.disabled = true; sum.classList.remove('on');
    var done = function () { state.busy = false; btn.disabled = false; say('أنشئ دائرتي'); };
    state.after = 'run';
    account().then(function (ok) {
      if (!ok) { done(); return; }
      // الإقرار بالعمر مكتوب في خانة الموافقة؛ يُحفظ للحساب حتى لا يُسأل ثانية عند أول بيع. فشله لا يوقف التسجيل
      call('POST', '/me/adult-attest', { confirm: true, source: 'app' }).catch(function () {});
      say('جارٍ رفع الشعار…');
      return upload(state.logo, 'logoUrl', 'logoOf').then(function () { say('جارٍ إنشاء الدائرة…'); return create(); }).then(function () {
        say('جارٍ إرسال طلب التوثيق…');
        return verify().then(function () { return null; }, function (e) { return e; }); // الدائرة أُنشئت: خطأ التوثيق يُعرض في شاشة النهاية ولا يعيدنا إلى النموذج
      }).then(function (verr) { state.warn = []; return details().then(function () { done(); finish(verr); }); });
    }).catch(function (e) {
      done(); sum.textContent = text(e); sum.classList.add('on');
      var map = { 'nickname-taken': 'nick', 'invalid-nickname': 'nick', 'email-taken': 'email', 'bad-email': 'email', 'weak-password': 'pass', 'bad-credentials': 'pass', 'invalid-credentials': 'pass', 'bad-phone': 'phone', 'bad-name': 'nameAr', 'banned-words': 'nameAr', 'logo-required': 'logo', 'unsupported-type': 'logo', 'bad-category': 'category' };
      var f = map[e.code] && field(map[e.code]); if (f) { f.classList.add('bad'); f.scrollIntoView({ block: 'center' }); } else sum.scrollIntoView({ block: 'center' });
    });
  }

  // ---- «صوّر المنيو» (docs/menu-scan.md): القراءة تحتاج جلسة، والجلسة في هذا النموذج تُنشأ عند الإرسال. فالزر يجهّز الحساب أولاً
  // (دخول أو حساب جديد برمز البريد) بالحقول نفسها في الخطوة 7، ثم يرفع الصور ويقرأها ويملأ صفوف الأصناف ليراجعها المالك قبل «أنشئ دائرتي».
  // لا يُنشأ صنف هنا: الصفوف تُرسل مع النموذج كأي صفوف كتبها بيده.
  var ACC = ['nick', 'email', 'pass', 'agree'];
  function scanSay(t, bad) { var m = $('rg-scan-msg'); m.hidden = !t; m.textContent = t || ''; m.classList.toggle('bad', !!bad); }
  function scanBusy(on) { state.scanning = on; $('rg-scan-lab').classList.toggle('off', on); $('rg-scan-in').disabled = on; $('rg-scan-go').disabled = on; $('rg-scan-t').textContent = on ? 'جارٍ قراءة المنيو…' : 'صوّر المنيو'; }
  // تصغير في المتصفح قبل الرفع (صور الجوال كبيرة)؛ إن تعذّر يُرفع الأصل والخادم يصغّره
  function shrink(file) {
    if (!window.createImageBitmap || file.size < 1500000) return Promise.resolve(file);
    return createImageBitmap(file).then(function (bmp) {
      var k = Math.min(1, 2000 / Math.max(bmp.width, bmp.height)), c = document.createElement('canvas');
      c.width = Math.round(bmp.width * k); c.height = Math.round(bmp.height * k);
      c.getContext('2d').drawImage(bmp, 0, 0, c.width, c.height);
      return new Promise(function (res) { c.toBlob(function (b) { res(b && b.size < file.size ? b : file); }, 'image/jpeg', 0.85); });
    }).catch(function () { return file; });
  }
  function fillRows(items) {
    // الصفوف الفارغة تُحذف أولاً حتى لا تأكل من حد الصفوف
    state.items.slice().forEach(function (it) { if (!itemData(it).title && !it.file) { state.items = state.items.filter(function (x) { return x !== it; }); it.el.remove(); } });
    var n = 0;
    items.forEach(function (x) {
      if (state.items.length >= 20) return;
      var it = addItem(); if (!it) return;
      it.el.querySelector('.t').value = x.title;
      it.el.querySelector('.price').value = x.priceKnown === false || !x.price ? '' : String(x.price % 100 ? (x.price / 100).toFixed(2) : x.price / 100);
      it.el.querySelector('.d').value = x.description || '';
      it.el.classList.add('scanned'); n++;
    });
    sync(); return n;
  }
  function scan() {
    var files = state.scanFiles || [];
    if (state.scanning || state.busy || !files.length) return;
    $('rg-scan-go').hidden = true;
    if (!state.token) {
      var bad = ACC.filter(function (k) { return !checks[k](); });
      if (bad.length) {
        ACC.forEach(function (k) { var f = field(k); if (f) f.classList.toggle('bad', bad.indexOf(k) >= 0); });
        scanSay('قراءة المنيو تحتاج حسابك. أكمل بيانات الحساب في الخطوة 7 ثم اضغط «اقرأ المنيو الآن».', true);
        $('rg-scan-go').hidden = false; field(bad[0]).scrollIntoView({ block: 'center' }); return;
      }
    }
    scanBusy(true); scanSay('جارٍ تجهيز حسابك…');
    var end = function () { scanBusy(false); say('أنشئ دائرتي'); };
    state.after = 'scan';
    account().then(function (ok) {
      if (!ok) { end(); scanSay('أكّد بريدك أولاً، ثم نقرأ المنيو.'); return; } // بطاقة الرمز ظاهرة؛ بعد التأكيد يعود إلى القراءة
      state.after = null; scanSay('جارٍ رفع الصور…');
      var urls = [], p = Promise.resolve();
      files.forEach(function (f) { p = p.then(function () { return shrink(f); }).then(function (b) { return call('POST', '/chat/upload', undefined, b); }).then(function (d) { if (!d.url) throw fail('upload-failed'); urls.push(d.url); }); });
      return p.then(function () { scanSay('جارٍ قراءة المنيو. قد تأخذ دقيقة…'); return call('POST', '/menu/scan', { images: urls }); }).then(function (d) {
        end(); state.scanFiles = [];
        var items = d.items || [], n = fillRows(items), warns = (d.warnings || []).map(function (w) { return w.message; }).filter(Boolean);
        if (!items.length) { scanSay(warns[0] || 'لم نجد أصنافاً في الصور. صوّر المنيو أقرب وبإضاءة أوضح.', true); return; }
        var t = n < items.length ? 'وجدنا ' + items.length + ' صنفاً وأضفنا ' + n + ' (الحد 20 صفاً هنا). أضف الباقي من لوحة الدائرة بعد التسجيل.' : 'أضفنا ' + n + ' من المنيو. راجعها وعدّلها قبل الإرسال.';
        if (slotted()) t += ' اكتب لكل خدمة أوقاتها اليومية.';
        scanSay([t].concat(warns).join(' '));
        var first = document.querySelector('.rg-item.scanned'); if (first) first.scrollIntoView({ block: 'center' });
      });
    }).catch(function (e) {
      end(); state.after = null; scanSay(text(e), true); $('rg-scan-go').hidden = false;
      var map = { 'nickname-taken': 'nick', 'invalid-nickname': 'nick', 'email-taken': 'email', 'bad-email': 'email', 'weak-password': 'pass', 'bad-credentials': 'pass', 'invalid-credentials': 'pass' };
      var f = map[e.code] && field(map[e.code]); if (f) { f.classList.add('bad'); f.scrollIntoView({ block: 'center' }); }
    });
  }
  $('rg-scan-in').addEventListener('change', function (e) {
    var all = Array.prototype.slice.call(e.target.files || []), ok = all.filter(function (f) { return /^image\/(png|jpeg|webp)$/.test(f.type) && f.size <= 20 * 1024 * 1024; });
    e.target.value = '';
    if (!all.length) return;
    if (!ok.length) { scanSay('اختر صوراً بصيغة PNG أو JPG حتى 20 م.ب.', true); return; }
    state.scanFiles = ok.slice(0, 4);
    scan();
  });
  $('rg-scan-go').addEventListener('click', scan);

  // ---- رمز تأكيد البريد
  function showCode(mail) {
    $('rg-code-mail').textContent = mail; $('rg-code-msg').textContent = ''; $('rg-code-in').value = '';
    form.hidden = true; $('rg-code').hidden = false; window.scrollTo(0, 0); $('rg-code-in').focus();
  }
  $('rg-code-form').addEventListener('submit', function (e) {
    e.preventDefault();
    var code = latin($('rg-code-in').value).replace(/\D/g, ''), msg = $('rg-code-msg'), b = $('rg-code-go');
    if (code.length < 4) { msg.textContent = 'اكتب الرمز الذي وصلك على بريدك.'; return; }
    b.disabled = true; msg.textContent = 'جارٍ التحقق…';
    call('POST', '/auth/verify', { email: state.pendingEmail, code: code }).then(function () { return login(); }).then(function () {
      b.disabled = false; $('rg-code').hidden = true; form.hidden = false;
      var next = state.after; state.after = null; if (next === 'scan') { $('rg-scan-lab').scrollIntoView({ block: 'center' }); scan(); } else run();
    }, function (err) { b.disabled = false; msg.textContent = text(err); });
  });
  $('rg-code-resend').addEventListener('click', function () {
    var msg = $('rg-code-msg');
    call('POST', '/auth/resend', { email: state.pendingEmail }).then(function () { msg.textContent = 'أرسلنا رمزاً جديداً.'; }, function (e) { msg.textContent = e.status === 429 ? 'انتظر دقيقة قبل طلب رمز جديد.' : text(e); });
  });
  $('rg-code-back').addEventListener('click', function () { $('rg-code').hidden = true; form.hidden = false; state.after = null; });

  function finish(verr) {
    var b = state.biz, link = location.origin + '/c/' + b.id;
    $('rg-done-name').textContent = b.nameAr || val('nameAr');
    var a = $('rg-done-link'); a.href = link; a.textContent = link.replace(/^https?:\/\//, '');
    $('rg-done-ver').textContent = later() ? 'التوثيق لاحقاً' : verr ? 'لم يُرسل طلب التوثيق' : 'طلب التوثيق أُرسل';
    $('rg-done-ver-s').textContent = later() ? 'أرسل الوثيقة من لوحة الدائرة متى شئت. وحتى ذلك يبقى البيع والحجز مقفلين.'
      : verr ? 'دائرتك أُنشئت، لكن تعذّر إرسال الوثيقة: ' + text(verr) + ' أرسلها من لوحة الدائرة في التطبيق.'
      : 'يراجع فريقنا ' + (entity() === 'freelance' ? 'وثيقة العمل الحر' : 'السجل التجاري') + '، ويصلك القرار في التطبيق. وبعد الاعتماد يُفتح البيع والحجز.';
    var n = state.items.filter(function (it) { return it.done; }).length, has = [val('description') && 'الوصف', hoursText() && 'ساعات العمل', state.coverUrl && 'الغلاف', n && (n + ' من الأصناف')].filter(Boolean);
    $('rg-done-data').textContent = has.length ? 'حُفظت بيانات الدائرة' : 'أكمل بيانات الدائرة';
    $('rg-done-data-s').textContent = (has.length ? 'حُفظ: ' + has.join('، ') + '. ' : '') + 'تعدّلها وتضيف عليها متى شئت من لوحة الدائرة في ناس لايف، من الجوال أو المتصفح.';
    var w = $('rg-done-warn'); w.hidden = !state.warn.length; w.textContent = state.warn.length ? 'لم يُحفظ: ' + state.warn.join(' · ') : '';
    form.hidden = true; $('rg-done').hidden = false; $('rg-done').focus(); window.scrollTo(0, 0);
  }

  form.addEventListener('input', sync); form.addEventListener('change', sync);
  form.addEventListener('submit', function (e) {
    e.preventDefault();
    var bad = Object.keys(checks).filter(function (k) { return !checks[k](); });
    Object.keys(checks).forEach(function (k) { var f = field(k); if (f) f.classList.toggle('bad', bad.indexOf(k) >= 0); });
    var badItems = liveItems().filter(function (it) { return !rowOk(it); });
    state.items.forEach(function (it) { it.el.classList.toggle('bad', badItems.indexOf(it) >= 0); });
    if (!bad.length && badItems.length) { var sm = $('rg-sum'); sm.textContent = priceMissing(badItems[0]) ? 'اكتب سعر كل صنف قرأناه من المنيو، أو 0 إن كان مجاناً.' : slotted() ? 'اكتب لكل خدمة وقتاً يومياً واحداً على الأقل، مثل 10:00.' : 'اسم الصنف حرفان على الأقل.'; sm.classList.add('on'); badItems[0].el.scrollIntoView({ block: 'center' }); return; }
    var sum = $('rg-sum');
    if (bad.length) {
      sum.textContent = bad.length === 1 ? 'بقي حقل واحد يحتاج تصحيحاً.' : 'بقيت ' + bad.length + ' حقول تحتاج تصحيحاً.'; sum.classList.add('on');
      var first = field(bad[0]); if (first) { first.scrollIntoView({ block: 'center' }); var inp = first.querySelector('input, select, button'); if (inp) inp.focus({ preventScroll: true }); }
      return;
    }
    run();
  });
  sync();
})();
