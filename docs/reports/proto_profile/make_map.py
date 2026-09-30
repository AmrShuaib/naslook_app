# يولّد template_map.html: أربع طرق بديلة لـ«الورقة السفلية» فوق الخريطة (ما يحمل أقسام الرئيسية):
# أ بطاقات أفقية تتبدّل بطبقة، ب زر خريطة/قائمة، ج قسمة ثابتة بتبويبات، د الرئيسية قائمة والخريطة بطاقة.
# يعيد استخدام أيقونات make_main.py وخريطته وبياناته. البناء: python3 make_map.py && python3 build.py template_map.html > out.html
import json, pathlib
from make_main import (CSS, MAP, PINS, ICONS, MOMENTS, PLACES, OFFERS, PRODUCTS, CIRCLES_MINE, CIRCLES_DISC, JOBCARD,
                       moment_cards, place_rows, offer_cards, product_cards, circle_rows, chips, sec, nav_pill, topbar, screen, BELL, SEARCHB, svg)
root = pathlib.Path(__file__).parent

ICONS2 = {
 'i-expand': svg('<path d="M4 9V4h5"/><path d="M20 15v5h-5"/><path d="M4 4l6 6"/><path d="M20 20l-6-6"/>', 18),
 'i-collapse': svg('<path d="M10 4v6H4"/><path d="M14 20v-6h6"/><path d="M4 20l6-6"/><path d="M20 4l-6 6"/>', 18),
 'i-arrow': svg('<path d="M5 12h14"/><path d="M13 6l6 6-6 6"/>', 18),
}
ICONS.update(ICONS2)

# ---------- بطاقات المسارات الأفقية (أ) وبطاقات القسمة (ج)
def near_cards():
    out = []
    for i, (img, who, place, name, ago, kind) in enumerate(MOMENTS[:5]):
        k = f'<i class="k">@@{kind}@@</i>' if kind else ''
        out.append(f'<button class="rc" data-pin="{i}"><img src="@@{img}@@" alt="">{k}<div class="b"><span class="t">{name}<img class="who" src="@@{who}@@" alt=""></span><span class="d">@@i-pin@@{place} · {ago}</span></div></button>')
    return ''.join(out)
def offer_rail():
    return ''.join(f'<button class="rc"><img src="@@{img}@@" alt=""><div class="b"><span class="t">{t}</span><span class="d"><img class="who" src="@@{lg}@@" alt="" style="margin:0 0 0 4px">{d}</span></div></button>' for lg, t, d, img in OFFERS)
def circle_rail():
    return ''.join(f'<button class="rc"><img src="@@{img}@@" alt="" style="border-radius:999px;width:52px;height:52px;margin:8px"><div class="b"><span class="t">{n}</span><span class="d">{d}</span></div></button>' for img, n, d in CIRCLES_DISC[:3] + CIRCLES_MINE[:1])
def market_rail():
    return ''.join(f'<button class="rc"><img src="@@{img}@@" alt=""><div class="b"><span class="t">{t}</span><span class="d"><b style="color:var(--a)">{p}</b> · {d}</span></div></button>' for img, t, p, d in PRODUCTS)
RAILS = {'near': ('حولك الآن', '٤٦ شخصاً · ١٢ لحظة', near_cards()), 'offers': ('عروض اليوم', '٣ عروض قريبة', offer_rail()), 'circles': ('دوائر قريبة', 'انضم بلمسة', circle_rail()), 'market': ('من السوق', 'الأقرب إليك', market_rail())}

def seg_layers(active='near', glass=True):
    items = [('near', 'حولك'), ('offers', 'عروض'), ('circles', 'دوائر'), ('market', 'سوق')]
    return f'<div class="seg4{" glass" if glass else ""}">' + ''.join(f'<button data-layer="{k}"{" class=on" if k==active else ""}>{t}</button>' for k, t in items) + '</div>'

# ---------- محتوى «القائمة» الكاملة (تُستخدم في ب و د): أقسام الرئيسية كصفحة عادية
def home_list(with_mapcard=False, pad=True):
    mapcard = ''
    if with_mapcard:
        mapcard = f'''<button class="mapcard" data-open="map"><div class="mapstrip map" style="margin:0;height:150px;border-radius:0;flex:none">{MAP}{PINS}</div>
          <div class="mc-ov"><div class="b"><span class="t">حولك الآن</span><span class="d">٤٦ شخصاً · ١٢ لحظة · ٣ عروض · ٦٥٠ م لأقرب مقهى</span></div><span class="go">افتح الخريطة @@i-arrow@@</span></div></button>'''
    return f'''<div class="scroll{" pad" if pad else ""}">
        {mapcard}
        {sec('لحظات حولك', 'الكل', '١٢ الآن')}<div class="hs">{moment_cards(n=5)}</div>
        {sec('عروض اليوم', 'الكل', '٣ قريبة')}<div class="hs">{offer_cards()}</div>
        {sec('مفتوح الآن حولك', 'الكل', 'الأقرب أولاً')}{place_rows(PLACES, 3, '<button class="btn sm soft">افتح</button>')}
        {sec('دوائرك', 'الكل')}{circle_rows(CIRCLES_MINE, '<span class="dist">@@i-chev@@</span>')}
        {sec('من السوق', 'الكل')}<div class="grid2">{product_cards(2)}</div>
        {sec('وظائف جديدة', 'الكل')}{JOBCARD}
      </div>'''

# ======================================================================
# أ · بطاقات أفقية: الخريطة كاملة، طبقة واحدة في المرة، مسار بطاقات أسفلها بلا سحب عمودي
# ======================================================================
def A():
    rails = ''.join(f'<div class="rail" data-rail="{k}"{"" if k=="near" else " hidden"}><div class="sec"><b>{t}<small>{s}</small></b><a href="#">قائمة</a></div><div class="hs">{cards}</div></div>' for k, (t, s, cards) in RAILS.items())
    home = f'''<div class="map">{MAP}{PINS}
      <div class="top"><div class="search glass">@@i-search@@<span style="flex-grow:1">ابحث في جدة</span><span class="avm"><img src="@@avatar@@" alt=""></span></div>
        <div style="padding:0 14px">{seg_layers()}</div></div>
      <button class="fabm" style="bottom:262px" aria-label="موقعي">@@i-locate@@</button>
      <div class="rails">{rails}</div></div>'''
    return screen('home', home, nav_pill('home'), 'abs')

# ======================================================================
# ب · زر خريطة/قائمة: وضعان كاملان يتبادلان بزر عائم واحد، بلا ورقة
# ======================================================================
def B():
    home = f'''<div class="mode" data-mode="map">
      <div class="map">{MAP}{PINS}
        <div class="top"><div class="search glass">@@i-search@@<span style="flex-grow:1">ابحث في جدة</span><span class="avm"><img src="@@avatar@@" alt=""></span></div>
          {chips([('الكل', True), ('أشخاص', False), ('دوائر', False), ('سوق', False), ('مفتوح الآن', False)], glass=True)}</div>
        <button class="fabm" style="bottom:150px" aria-label="موقعي">@@i-locate@@</button>
        <div class="peek"><img src="@@overdose@@" alt=""><div class="b"><span class="t">أوفردوز <small>· ٦٥٠ م</small></span><span class="d">مقهى · مفتوح الآن · ٨ لحظات · خصم ٢٠٪</span></div><button class="btn sm soft">افتح</button></div>
        <button class="fabc" data-toggle="list">@@i-list@@ القائمة</button>
      </div></div>
      <div class="mode" data-mode="list" hidden>
      {topbar('<span class="brand">ناس لايف</span><span class="sub2">جدة · الشاطئ</span>', BELL, SEARCHB)}
      {home_list()}
      <button class="fabc dark" data-toggle="map">@@i-map@@ الخريطة</button>
      </div>'''
    return screen('home', home, nav_pill('home'), 'abs')

# ======================================================================
# ج · قسمة ثابتة: الخريطة في الأعلى بارتفاع ثابت، لوحة تبويبات في الأسفل، زر توسيع بدل السحب
# ======================================================================
def C():
    panels = {
      'near': f'''<div class="sec"><b>حولك الآن<small>٤٦ شخصاً · ١٢ لحظة</small></b><a href="#">الكل</a></div><div class="hs">{moment_cards(n=5)}</div>
                 {sec('مفتوح الآن', 'الكل', 'الأقرب أولاً')}{place_rows(PLACES, 4, '<button class="btn sm soft">افتح</button>')}''',
      'offers': f'''{sec('عروض اليوم', 'الكل', '٣ قريبة')}<div class="hs">{offer_cards()}</div>{sec('عروض دوائرك', '')}{place_rows(PLACES[:2], 2, '<button class="btn sm soft">استخدم</button>')}''',
      'circles': f'''{sec('دوائرك', 'الكل')}{circle_rows(CIRCLES_MINE, '<span class="dist">@@i-chev@@</span>')}{sec('اكتشف حولك', 'الكل')}{circle_rows(CIRCLES_DISC[:3], '<button class="btn sm soft">انضم</button>')}''',
      'market': f'''{sec('من السوق', 'الكل', 'الأقرب إليك')}<div class="grid2">{product_cards(4)}</div>''',
      'more': f'''{sec('وظائف جديدة', 'الكل')}{JOBCARD}{sec('فعاليات قريبة', 'الكل')}{place_rows([('malaga', 'بازار الحي', 'الجمعة ٥ م · حديقة الشاطئ', '١٢ طاولة', '٩٠٠ م'), ('3brews', 'ورشة لاتيه آرت', 'السبت ٧ م · ثري بروز', '٤ مقاعد', '٢.١ كم')], 2, '<button class="btn sm soft">تذكرة</button>')}''',
    }
    tabs = [('near', 'حولك'), ('offers', 'عروض'), ('circles', 'دوائر'), ('market', 'سوق'), ('more', 'المزيد')]
    tabbar = '<div class="ptabs">' + ''.join(f'<button data-ptab="{k}"{" class=on" if k=="near" else ""}>{t}</button>' for k, t in tabs) + '</div>'
    body = ''.join(f'<div class="pbody" data-pbody="{k}"{"" if k=="near" else " hidden"}>{v}</div>' for k, v in panels.items())
    home = f'''<div class="split">
      <div class="map mapc">{MAP}{PINS}
        <div class="top"><div class="search glass">@@i-search@@<span style="flex-grow:1">ابحث في جدة</span><span class="avm"><img src="@@avatar@@" alt=""></span></div></div>
        <button class="fabm loc" aria-label="موقعي">@@i-locate@@</button>
        <button class="fabm exp" data-expand aria-label="توسيع الخريطة">@@i-expand@@</button>
      </div>
      <div class="panel">{tabbar}<div class="scroll pad" style="gap:10px">{body}</div></div>
    </div>'''
    return screen('home', home, nav_pill('home'), 'abs')

# ======================================================================
# د · الرئيسية قائمة والخريطة بطاقة: الخريطة قسم من الرئيسية لا حاويتها؛ تُفتح كشاشة كاملة
# ======================================================================
def D():
    home = f'''<div class="mode" data-mode="list">
      {topbar('<span class="brand">ناس لايف</span><span class="sub2">جدة · الشاطئ</span>', BELL, SEARCHB)}
      {home_list(with_mapcard=True)}
      </div>
      <div class="mode" data-mode="map" hidden>
      <div class="map">{MAP}{PINS}
        <div class="top"><div class="search glass"><button class="ibx" data-open="list" aria-label="رجوع">@@i-arrow@@</button><span style="flex-grow:1">حولك الآن</span>@@i-sliders@@</div>
          {chips([('الكل', True), ('أشخاص', False), ('دوائر', False), ('عروض', False), ('سوق', False)], glass=True)}</div>
        <button class="fabm" style="bottom:150px" aria-label="موقعي">@@i-locate@@</button>
        <div class="peek"><img src="@@p16@@" alt=""><div class="b"><span class="t">فهد <small>· الكورنيش · قبل ١٢ د</small></span><span class="d">لحظة بالكاميرا · ٢٤ إعجاباً</span></div><button class="btn sm soft">افتح</button></div>
      </div></div>'''
    return screen('home', home, nav_pill('home'), 'abs')

CSS2 = r'''
/* أ: مسارات أفقية */
.seg4{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:4px;background:#F2F2F7;border-radius:12px;padding:4px;flex:none}
.seg4.glass{background:rgba(255,255,255,.95);box-shadow:0 4px 14px rgba(0,0,0,.16)}
.seg4 button{height:34px;border:0;border-radius:9px;background:transparent;color:#6B7280;font:600 13px var(--font-body);cursor:pointer}
.seg4 button.on{background:#111;color:#fff}
.rails{position:absolute;right:0;left:0;bottom:84px;display:flex;flex-direction:column;gap:8px}
.rail{display:flex;flex-direction:column;gap:8px}
.rail .sec b{color:#111;text-shadow:0 0 4px #fff,0 0 8px #fff}
.rc{flex:none;width:150px;border:0;border-radius:16px;background:rgba(255,255,255,.97);box-shadow:0 6px 18px rgba(0,0,0,.18);display:flex;flex-direction:column;overflow:hidden;text-align:right;padding:0;cursor:pointer;font-family:var(--font-body);position:relative}
.rc>img:first-child{width:100%;height:78px;object-fit:cover;display:block}
.rc .k{position:absolute;top:6px;left:6px;width:22px;height:22px;border-radius:999px;background:rgba(17,17,17,.6);color:#fff;display:inline-flex;align-items:center;justify-content:center}
.rc .k svg{width:12px;height:12px}
.rc .b{display:flex;flex-direction:column;gap:2px;padding:7px 9px 9px}
.rc .t{font-size:12.5px;font-weight:700;color:#111;display:flex;align-items:center;justify-content:space-between;gap:6px}
.rc .who{width:20px;height:20px;border-radius:999px;object-fit:cover;border:1.5px solid #fff;box-shadow:0 0 0 1px #E5E5EA}
.rc .d{font-size:11px;color:#6B7280;display:flex;align-items:center;gap:3px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.rc.hi{outline:2.5px solid var(--a);outline-offset:-2.5px}
.map .pin.hi img{box-shadow:0 0 0 3px var(--a),0 2px 8px rgba(0,0,0,.28)}
/* ب و د: وضعان */
.mode{position:absolute;inset:0;display:flex;flex-direction:column}
.mode>.map{position:absolute;inset:0}
.fabc{position:absolute;left:50%;transform:translateX(-50%);bottom:92px;height:42px;padding:0 18px;border-radius:999px;border:0;background:#111;color:#fff;font:700 13.5px var(--font-body);display:inline-flex;align-items:center;gap:8px;box-shadow:0 8px 22px rgba(0,0,0,.28);cursor:pointer;z-index:2}
.fabc.dark{background:var(--a);box-shadow:0 8px 22px rgba(10,110,120,.4)}
.peek{position:absolute;right:14px;left:14px;bottom:146px;display:flex;align-items:center;gap:10px;background:rgba(255,255,255,.97);border-radius:16px;padding:8px 10px;box-shadow:0 8px 24px rgba(0,0,0,.18)}
.peek img{width:46px;height:46px;border-radius:12px;object-fit:cover}
.peek .b{flex-grow:1;min-width:0;display:flex;flex-direction:column;gap:1px}
.peek .t{font-size:13.5px;font-weight:700}.peek .t small{font-weight:500;color:#6B7280}
.peek .d{font-size:11.5px;color:#6B7280;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.mode[data-mode=list] .tb{border-bottom:1px solid #F2F2F7}
.brand{font:800 20px var(--font-display);color:var(--a)}
.tb .ttl .sub2{margin-inline-start:8px}
.ibx{width:30px;height:30px;border-radius:999px;border:0;background:#F2F2F7;color:#111;display:inline-flex;align-items:center;justify-content:center;cursor:pointer;flex:none;transform:scaleX(-1)}
.grid2{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px;padding:0 14px;flex:none}
/* ج: قسمة ثابتة */
.split{position:absolute;inset:0;display:flex;flex-direction:column}
.split .map.mapc{flex:0 0 42%;transition:flex-basis .28s ease}
.split.full .map.mapc{flex-basis:calc(100% - 0px)}
.split .panel{flex:1 1 auto;min-height:0;display:flex;flex-direction:column;background:#fff;border-top:1px solid #E5E5EA}
.split.full .panel{display:none}
.split .fabm.loc{bottom:12px}
.split .fabm.exp{bottom:12px;left:auto;right:12px}
.split.full .fabm{bottom:92px}
.ptabs{display:flex;gap:2px;padding:6px 10px 0;border-bottom:1px solid #E5E5EA;flex:none}
.ptabs button{flex:1;height:38px;border:0;background:transparent;color:#6B7280;font:600 13px var(--font-body);cursor:pointer;border-bottom:2.5px solid transparent;margin-bottom:-1px}
.ptabs button.on{color:var(--a);border-bottom-color:var(--a)}
.pbody{display:flex;flex-direction:column;gap:10px}
/* د: بطاقة الخريطة */
.mapcard{position:relative;margin:0 14px;border:0;border-radius:18px;overflow:hidden;padding:0;background:#F1EFE8;flex:none;cursor:pointer;text-align:right;font-family:var(--font-body);box-shadow:0 6px 18px rgba(0,0,0,.12)}
.mapcard .mapstrip{pointer-events:none}
.mapcard .mapstrip .pin{width:30px;height:30px}.mapcard .mapstrip .pin img{width:30px;height:30px}
.mc-ov{display:flex;align-items:center;gap:10px;padding:10px 12px;background:#fff}
.mc-ov .b{flex-grow:1;min-width:0;display:flex;flex-direction:column;gap:1px}
.mc-ov .t{font-size:14.5px;font-weight:700;color:#111}.mc-ov .d{font-size:11.5px;color:#6B7280;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.mc-ov .go{flex:none;display:inline-flex;align-items:center;gap:4px;height:32px;padding:0 12px;border-radius:999px;background:var(--a);color:#fff;font-size:12px;font-weight:700}
.dist{color:#9CA3AF;display:inline-flex}
.avm img{width:28px;height:28px;border-radius:999px;object-fit:cover}
'''

page = f'''<title>بدائل الورقة السفلية</title>
<meta name="description" content="أربع طرق لعرض أقسام الرئيسية فوق خريطة ناس لايف بلا ورقة تُسحب: مسارات أفقية، زر خريطة/قائمة، قسمة ثابتة، أو الخريطة كبطاقة.">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Rubik:wght@400;500;600;700&family=Baloo+Bhaijaan+2:wght@600;700;800&display=swap">
<style>{CSS}{CSS2}</style>
<div class="wrap">
  <header>
    <h1>بدائل الورقة السفلية على الخريطة</h1>
    <p class="sub">اليوم تحمل «ورقة» تُسحب من أسفل الخريطة كل أقسام الرئيسية (12 قسماً)، فتتنافس مع الخريطة على الشاشة ويلتبس السحب بين تحريك الخريطة وتمرير القائمة. هذه أربع طرق مغايرة بالمحتوى الحقيقي نفسه؛ كلٌّ منها يجيب عن السؤال «أين تعيش الأقسام إذا لم تكن في ورقة؟». الأزرار داخل الهواتف تعمل: بدّل الطبقات في أ، والوضع في ب ود، والتبويبات والتوسيع في ج.</p>
    <div class="rowh">
      <div class="seg" id="seg" role="tablist" aria-label="النماذج">
        <button class="on" data-go="a" role="tab"><i>أ</i>مسارات أفقية</button>
        <button data-go="b" role="tab"><i>ب</i>زر خريطة/قائمة</button>
        <button data-go="c" role="tab"><i>ج</i>قسمة ثابتة</button>
        <button data-go="d" role="tab"><i>د</i>الخريطة بطاقة</button>
      </div>
    </div>
  </header>

  <div class="phones">
    <section class="slot active" id="s-a">
      <h2><span>أ</span>مسارات أفقية <small>· طبقة واحدة في المرة</small></h2>
      <div class="phone"><div class="screen" data-concept="a">{A()}</div></div>
      <p class="note">الخريطة كاملة دائماً. مفتاح رباعي في الأعلى (حولك، عروض، دوائر، سوق) يبدّل مسار بطاقات أفقياً في الأسفل، ولمس بطاقة يُبرز دبّوسها. لا سحب عمودي إطلاقاً: التمرير الأفقي للبطاقات والعمودي للخريطة لا يتعارضان. الأقسام الأخرى (وظائف، فعاليات، دوائرك) تنتقل إلى تبويباتها أو إلى «قائمة». كما في خرائط قوقل وسناب ماب.</p>
    </section>
    <section class="slot" id="s-b">
      <h2><span>ب</span>زر خريطة/قائمة <small>· وضعان كاملان</small></h2>
      <div class="phone"><div class="screen" data-concept="b">{B()}</div></div>
      <p class="note">وضعان لا ثالث لهما: خريطة كاملة ببطاقة «الأقرب» صغيرة، وقائمة كاملة هي الرئيسية العادية بأقسامها. زر واحد عائم يبدّل بينهما ويتذكّر التطبيق آخر وضع. أبسط ما يمكن شرحه للمستخدم، وكل أقسام الرئيسية والتخصيص تبقى كما هي في وضع القائمة. كما في Airbnb وZillow.</p>
    </section>
    <section class="slot" id="s-c">
      <h2><span>ج</span>قسمة ثابتة <small>· بلا سحب، بتبويبات</small></h2>
      <div class="phone"><div class="screen" data-concept="c">{C()}</div></div>
      <p class="note">الخريطة تأخذ 42٪ من الشاشة والباقي لوحة ثابتة بتبويبات (حولك، عروض، دوائر، سوق، المزيد). لا شيء يُسحب: الخريطة تتحرّك في مساحتها واللوحة تتمرّر في مساحتها، وزر التوسيع يجعل الخريطة كاملة ويعيدها. يحتفظ بأكبر قدر من المحتوى مع خريطة دائمة الحضور، على حساب خريطة أصغر.</p>
    </section>
    <section class="slot" id="s-d">
      <h2><span>د</span>الخريطة بطاقة <small>· الرئيسية قائمة</small></h2>
      <div class="phone"><div class="screen" data-concept="d">{D()}</div></div>
      <p class="note">نعكس العلاقة: الرئيسية قائمة عادية والخريطة بطاقة حيّة في أعلاها تفتح الخريطة الكاملة بلمسة. الخريطة تصير أداة تُستدعى عند الحاجة لا حاوية لكل شيء، وتبقى ملء الشاشة حين تُفتح مع بطاقة «الأقرب» فقط. كما في أوبر إيتس وكريم. أقلها التزاماً بفكرة «الخريطة أولاً».</p>
    </section>
  </div>

  <div class="tblwrap"><table class="cmp">
    <thead><tr><th>المعيار</th><th>أ · مسارات أفقية</th><th>ب · زر خريطة/قائمة</th><th>ج · قسمة ثابتة</th><th>د · الخريطة بطاقة</th></tr></thead>
    <tbody>
      <tr><th>حجم الخريطة</th><td>كاملة دائماً</td><td>كاملة في وضعها</td><td>42٪ ثابتة، وكاملة بزر</td><td>بطاقة، وكاملة عند الفتح</td></tr>
      <tr><th>الإيماءات</th><td>أفقي للبطاقات، الخريطة حرّة</td><td>لا تعارض إطلاقاً</td><td>كل منطقة تتمرّر وحدها</td><td>لا تعارض إطلاقاً</td></tr>
      <tr><th>أين تذهب الأقسام الـ12</th><td>4 طبقات هنا والباقي في تبويباته</td><td>كلها في وضع القائمة كما هي</td><td>5 تبويبات، «المزيد» يجمع الباقي</td><td>كلها في القائمة تحت بطاقة الخريطة</td></tr>
      <tr><th>التخصيص الحالي</th><td>يقتصر على ترتيب الطبقات</td><td>يبقى كما هو</td><td>يبقى داخل كل تبويب</td><td>يبقى كما هو</td></tr>
      <tr><th>الازدحام</th><td><b>الأقل</b>: شيء واحد في المرة</td><td>منخفض في الخريطة، كما هو في القائمة</td><td>متوسط</td><td>كما القائمة الحالية</td></tr>
      <tr><th>هوية «الخريطة أولاً»</th><td><b>الأقوى</b></td><td>قوية</td><td>متوسطة</td><td>ضعيفة</td></tr>
      <tr><th>أثر التنفيذ</th><td>متوسط: شريط طبقات ومسارات جديدة</td><td><b>الأصغر</b>: الرئيسية القديمة + زر</td><td>متوسط: لوحة تبويبات</td><td>صغير: بطاقة خريطة في الرئيسية</td></tr>
    </tbody>
  </table></div>

  <div class="reco">
    <b>توصيتي</b>
    <span>«أ · مسارات أفقية» يحل مشكلة الازدحام والالتباس معاً ويبقي هوية الخريطة، لأن المستخدم يرى طبقة واحدة في المرة ويقرّر بنفسه ما التالي. وإن أردت أقل تغيير وأوضح سلوك فـ«ب» ينفَّذ في يوم واحد ويعيد الرئيسية القديمة كوضع قائمة. ويمكن الجمع: مسارات «أ» على الخريطة، وزر «القائمة» من «ب» لمن يريد كل الأقسام دفعة واحدة.</span>
  </div>
</div>

<script>
(function(){{
  var slots = {{a:'s-a', b:'s-b', c:'s-c', d:'s-d'}};
  function go(id){{
    Object.keys(slots).forEach(function(k){{ document.getElementById(slots[k]).classList.toggle('active', k===id); }});
    document.querySelectorAll('#seg button').forEach(function(b){{ b.classList.toggle('on', b.getAttribute('data-go')===id); }});
    if (window.innerWidth <= 1250) window.scrollTo({{top:0, behavior:'smooth'}});
    try {{ localStorage.setItem('nl-map-concept', id); }} catch(e){{}}
  }}
  document.querySelectorAll('#seg button').forEach(function(b){{ b.addEventListener('click', function(){{ go(b.getAttribute('data-go')); }}); }});
  var saved = null; try {{ saved = localStorage.getItem('nl-map-concept'); }} catch(e){{}}
  if (saved && slots[saved]) go(saved);

  // أ: الطبقات والمسارات وإبراز الدبوس
  var a = document.querySelector('[data-concept=a]');
  a.querySelectorAll('[data-layer]').forEach(function(b){{ b.addEventListener('click', function(){{
    var k = b.getAttribute('data-layer');
    a.querySelectorAll('[data-layer]').forEach(function(x){{ x.classList.toggle('on', x===b); }});
    a.querySelectorAll('[data-rail]').forEach(function(r){{ r.hidden = r.getAttribute('data-rail')!==k; }});
  }}); }});
  var pins = a.querySelectorAll('.map .pin');
  a.querySelectorAll('.rc[data-pin]').forEach(function(c){{ c.addEventListener('click', function(){{
    var i = +c.getAttribute('data-pin');
    a.querySelectorAll('.rc').forEach(function(x){{ x.classList.toggle('hi', x===c); }});
    pins.forEach(function(p, j){{ p.classList.toggle('hi', j===i); }});
  }}); }});

  // ب و د: تبديل الوضع
  ['b','d'].forEach(function(id){{
    var s = document.querySelector('[data-concept='+id+']');
    function mode(m){{ s.querySelectorAll('[data-mode]').forEach(function(x){{ x.hidden = x.getAttribute('data-mode')!==m; }}); }}
    s.querySelectorAll('[data-toggle],[data-open]').forEach(function(b){{ b.addEventListener('click', function(ev){{ ev.preventDefault(); mode(b.getAttribute('data-toggle')||b.getAttribute('data-open')); }}); }});
  }});

  // ج: التبويبات والتوسيع
  var c = document.querySelector('[data-concept=c]');
  c.querySelectorAll('[data-ptab]').forEach(function(b){{ b.addEventListener('click', function(){{
    var k = b.getAttribute('data-ptab');
    c.querySelectorAll('[data-ptab]').forEach(function(x){{ x.classList.toggle('on', x===b); }});
    c.querySelectorAll('[data-pbody]').forEach(function(x){{ x.hidden = x.getAttribute('data-pbody')!==k; }});
  }}); }});
  var split = c.querySelector('.split'), exp = c.querySelector('[data-expand]');
  exp.addEventListener('click', function(){{
    var full = split.classList.toggle('full');
    exp.innerHTML = full ? {json.dumps(ICONS['i-collapse'])} : {json.dumps(ICONS['i-expand'])};
    exp.setAttribute('aria-label', full ? 'تصغير الخريطة' : 'توسيع الخريطة');
  }});
}})();
</script>
'''

if __name__ == '__main__':
    icons_path = root / 'icons.json'
    icons = json.loads(icons_path.read_text(encoding='utf-8'))
    icons.update(ICONS2)
    icons_path.write_text(json.dumps(icons, ensure_ascii=False, indent=1), encoding='utf-8')
    (root / 'template_map.html').write_text(page, encoding='utf-8')
