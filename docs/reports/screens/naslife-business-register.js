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

  var state = { logo: null, doc: null, lat: null, lng: null, token: null, logoUrl: null, docUrl: null, logoOf: null, docOf: null, biz: null, verified: false, busy: false, pendingEmail: null };
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
    agree: function () { return $('rg-agree').checked; }
  };
  var groups = { category: ['category'], identity: ['nameAr', 'logo'], place: ['city'], contact: ['phone'], verify: ['entityNumber', 'doc'], account: ['nick', 'email', 'pass', 'agree'] };
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
    // المعاينة الجانبية
    var cat = CATS.filter(function (c) { return c[0] === val('category'); })[0];
    $('pv-name').textContent = val('nameAr') || 'اسم دائرتك';
    $('pv-cat').textContent = (cat ? cat[1] : 'نوع النشاط') + (val('city') ? ' · ' + val('city') : '');
    $('pv-pres').textContent = mob ? 'متنقلة · ' + val('radiusKm') + ' كم' : 'مكان ثابت';
    $('pv-ver').textContent = later() ? 'غير موثّقة بعد' : 'بانتظار التوثيق';
    Object.keys(groups).forEach(function (g) {
      var li = document.querySelector('#rg-steps [data-s="' + g + '"]');
      li.classList.toggle('ok', groups[g].every(function (k) { return checks[k](); }));
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
  var text = function (e) { return MSG[e.code] || (e.status >= 500 ? 'حدث خطأ في الخادم. أعد المحاولة بعد قليل.' : 'تعذّر إكمال الخطوة (' + e.code + '). أعد المحاولة.'); };

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
      address: [val('district'), val('city')].filter(Boolean).join('، ') };
    if (mob) { body.radiusKm = Number(val('radiusKm')) || 15; if (val('district')) body.districts = [val('district')]; }
    return call('POST', '/biz/register', body).then(function (d) { if (!d.biz || !d.biz.id) throw fail('register-failed'); state.biz = d.biz; return d.biz; });
  }
  function verify() {
    if (later() || state.verified) return Promise.resolve();
    return upload(state.doc, 'docUrl', 'docOf').then(function (url) {
      return call('POST', '/biz/' + encodeURIComponent(state.biz.id) + '/verification', { entityKind: entity(), entityNumber: entNo(), docUrl: url });
    }).then(function () { state.verified = true; });
  }

  function run() {
    if (state.busy) return; state.busy = true;
    var btn = $('rg-go'), sum = $('rg-sum'); btn.disabled = true; sum.classList.remove('on');
    var done = function () { state.busy = false; btn.disabled = false; say('أنشئ دائرتي'); };
    account().then(function (ok) {
      if (!ok) { done(); return; }
      // الإقرار بالعمر مكتوب في خانة الموافقة؛ يُحفظ للحساب حتى لا يُسأل ثانية عند أول بيع. فشله لا يوقف التسجيل
      call('POST', '/me/adult-attest', { confirm: true, source: 'app' }).catch(function () {});
      say('جارٍ رفع الشعار…');
      return upload(state.logo, 'logoUrl', 'logoOf').then(function () { say('جارٍ إنشاء الدائرة…'); return create(); }).then(function () {
        say('جارٍ إرسال طلب التوثيق…');
        return verify().then(function () { return null; }, function (e) { return e; }); // الدائرة أُنشئت: خطأ التوثيق يُعرض في شاشة النهاية ولا يعيدنا إلى النموذج
      }).then(function (verr) { done(); finish(verr); });
    }).catch(function (e) {
      done(); sum.textContent = text(e); sum.classList.add('on');
      var map = { 'nickname-taken': 'nick', 'invalid-nickname': 'nick', 'email-taken': 'email', 'bad-email': 'email', 'weak-password': 'pass', 'bad-credentials': 'pass', 'invalid-credentials': 'pass', 'bad-phone': 'phone', 'bad-name': 'nameAr', 'banned-words': 'nameAr', 'logo-required': 'logo', 'unsupported-type': 'logo', 'bad-category': 'category' };
      var f = map[e.code] && field(map[e.code]); if (f) { f.classList.add('bad'); f.scrollIntoView({ block: 'center' }); } else sum.scrollIntoView({ block: 'center' });
    });
  }

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
      b.disabled = false; $('rg-code').hidden = true; form.hidden = false; run();
    }, function (err) { b.disabled = false; msg.textContent = text(err); });
  });
  $('rg-code-resend').addEventListener('click', function () {
    var msg = $('rg-code-msg');
    call('POST', '/auth/resend', { email: state.pendingEmail }).then(function () { msg.textContent = 'أرسلنا رمزاً جديداً.'; }, function (e) { msg.textContent = e.status === 429 ? 'انتظر دقيقة قبل طلب رمز جديد.' : text(e); });
  });
  $('rg-code-back').addEventListener('click', function () { $('rg-code').hidden = true; form.hidden = false; });

  function finish(verr) {
    var b = state.biz, link = location.origin + '/c/' + b.id;
    $('rg-done-name').textContent = b.nameAr || val('nameAr');
    var a = $('rg-done-link'); a.href = link; a.textContent = link.replace(/^https?:\/\//, '');
    $('rg-done-ver').textContent = later() ? 'التوثيق لاحقاً' : verr ? 'لم يُرسل طلب التوثيق' : 'طلب التوثيق أُرسل';
    $('rg-done-ver-s').textContent = later() ? 'أرسل الوثيقة من لوحة الدائرة متى شئت. وحتى ذلك يبقى البيع والحجز مقفلين.'
      : verr ? 'دائرتك أُنشئت، لكن تعذّر إرسال الوثيقة: ' + text(verr) + ' أرسلها من لوحة الدائرة في التطبيق.'
      : 'يراجع فريقنا ' + (entity() === 'freelance' ? 'وثيقة العمل الحر' : 'السجل التجاري') + '، ويصلك القرار في التطبيق. وبعد الاعتماد يُفتح البيع والحجز.';
    form.hidden = true; $('rg-done').hidden = false; $('rg-done').focus(); window.scrollTo(0, 0);
  }

  form.addEventListener('input', sync); form.addEventListener('change', sync);
  form.addEventListener('submit', function (e) {
    e.preventDefault();
    var bad = Object.keys(checks).filter(function (k) { return !checks[k](); });
    Object.keys(checks).forEach(function (k) { var f = field(k); if (f) f.classList.toggle('bad', bad.indexOf(k) >= 0); });
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
