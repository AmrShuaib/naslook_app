// سلوك نماذج تسجيل الدائرة على /business/register (معاينة قبل الاعتماد): تبديل النموذج بين السجل التجاري والعمل الحر،
// معاينة حيّة للدائرة، والتحقق بالقواعد التي يطبقها الخادم نفسه (biz_onboard.js). لا يُرسل شيء إلى الخادم.
(function () {
  'use strict';
  var $ = function (id) { return document.getElementById(id); };
  var form = $('rg-form'); if (!form) return;
  // الفئات كما في الخادم (CATEGORIES) بأسمائها العربية
  var CATS = [['cafe', 'مقهى'], ['restaurant', 'مطعم'], ['shop', 'متجر'], ['services', 'خدمات وورش'], ['salon', 'صالون وتجميل'], ['clinic', 'عيادة'], ['hospital', 'مستشفى'], ['hotel', 'فندق'], ['car_rental', 'تأجير سيارات'], ['entertainment', 'ترفيه'], ['cinema', 'سينما'], ['brand', 'براند'], ['company', 'شركة'], ['university', 'جامعة'], ['other', 'أخرى']];
  $('rg-cats').innerHTML = CATS.map(function (c) { return '<label class="rg-chip"><input type="radio" name="category" value="' + c[0] + '">' + c[1] + '</label>'; }).join('');

  var state = { logo: false, doc: false, lat: null, lng: null };
  var val = function (n) { var e = form.elements[n]; return e ? String(e.value || '').trim() : ''; };
  var latin = function (s) { return String(s).replace(/[٠-٩]/g, function (d) { return '٠١٢٣٤٥٦٧٨٩'.indexOf(d); }).replace(/[۰-۹]/g, function (d) { return '۰۱۲۳۴۵۶۷۸۹'.indexOf(d); }); };
  // كما في normalizePhone بالخادم: يقبل 05XXXXXXXX و5XXXXXXXX و+9665XXXXXXXX
  var phone = function (v) { var m = /^(?:\+966|00966|966)?0?5(\d{8})$/.exec(latin(v).replace(/[\s\-().]/g, '')); return m ? '+9665' + m[1] : null; };
  var entity = function () { return val('entity') === 'freelance' ? 'freelance' : 'cr'; };
  var entNo = function () { return latin(val('entityNumber')).replace(/[\s\-]/g, ''); };
  var entOk = function () { return entity() === 'cr' ? /^\d{10}$/.test(entNo()) : /^[A-Za-z0-9]{8,20}$/.test(entNo()); };
  var later = function () { return $('rg-later').checked; };

  var checks = {
    category: function () { return !!val('category'); },
    nameAr: function () { return val('nameAr').length >= 2; },
    logo: function () { return state.logo; },
    location: function () { return state.lat != null; },
    city: function () { return !!val('city'); },
    phone: function () { return !!phone(val('phone')); },
    entityNumber: function () { return later() || entOk(); },
    doc: function () { return later() || state.doc; },
    nick: function () { return val('nick').length >= 2; },
    email: function () { return /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(val('email')); },
    pass: function () { return form.elements.pass.value.length >= 8; },
    agree: function () { return $('rg-agree').checked; }
  };
  var groups = { category: ['category'], identity: ['nameAr', 'logo'], place: ['location', 'city'], contact: ['phone'], verify: ['entityNumber', 'doc'], account: ['nick', 'email', 'pass', 'agree'] };
  var field = function (k) { return form.querySelector('[data-f="' + k + '"]'); };

  function sync() {
    var fr = entity() === 'freelance', mob = val('presence') === 'mobile';
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
      if (!f || !/^image\//.test(f.type)) { state[key] = false; sync(); return; }
      var url = URL.createObjectURL(f); // معاينة محلية فقط؛ لا يُرفع الملف
      thumb.style.backgroundImage = 'url("' + url + '")'; thumb.innerHTML = '';
      title.textContent = f.name.length > 28 ? f.name.slice(0, 25) + '…' : f.name;
      if (key === 'logo') { $('pv-logo').style.backgroundImage = 'url("' + url + '")'; $('pv-logo').innerHTML = ''; }
      state[key] = true; sync();
    });
  }
  pick($('rg-logo'), $('rg-logo-th'), $('rg-logo-t'), 'logo');
  pick($('rg-doc'), $('rg-doc-th'), $('rg-doc-t'), 'doc');

  $('rg-locate').addEventListener('click', function () {
    var c = $('rg-coord');
    var set = function (lat, lng, note) { state.lat = lat; state.lng = lng; c.hidden = false; c.textContent = 'حُدد الموقع ✓ ' + note; sync(); };
    // في المعاينة: إن تعذّر الموقع (رفض الإذن أو متصفح بلا دعم) نضع وسط جدة مثالاً حتى تكتمل التجربة
    var demo = function () { set(21.5433, 39.1728, '(موقع تجريبي: جدة)'); };
    if (!navigator.geolocation) return demo();
    c.hidden = false; c.textContent = 'جارٍ تحديد موقعك…';
    navigator.geolocation.getCurrentPosition(function (p) { set(p.coords.latitude, p.coords.longitude, ''); }, demo, { timeout: 8000, maximumAge: 60000 });
  });

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
    sum.classList.remove('on');
    $('rg-done-ver').textContent = later() ? 'التوثيق لاحقاً' : 'مراجعة التوثيق';
    $('rg-done-ver-s').textContent = later() ? 'ترسل الوثيقة من لوحة الدائرة متى شئت. وحتى ذلك يبقى البيع والحجز مقفلين.' : 'يراجع فريقنا ' + (entity() === 'freelance' ? 'وثيقة العمل الحر' : 'السجل التجاري') + '، وبعد الاعتماد يُفتح البيع والحجز.';
    form.hidden = true; $('rg-done').hidden = false; $('rg-done').focus(); window.scrollTo(0, 0);
  });
  $('rg-again').addEventListener('click', function () { $('rg-done').hidden = true; form.hidden = false; window.scrollTo(0, 0); });
  sync();
})();
