# يولّد template_one.html: نظام «واحد»: شيء واحد في المرة، إيماءة واحدة، زر واحد، ولا شيء آخر على الشاشة.
# شكلان للإيماءة نفسها: «بطاقة» (الخريطة كاملة وبطاقة واحدة تُسحب جانبياً والخريطة تتبعها) و«شاشة» (كل شيء بملء الشاشة
# ويُسحب للأعلى، وخريطة مصغّرة تدلّ على الاتجاه)، وثالث يجمعهما بمفتاح واحد يتذكّره التطبيق ويحفظ موضع المستخدم في الصف.
# البناء: python3 make_one.py && python3 build.py template_one.html > out.html
import json, math, pathlib
from make_main import CSS, MAP, ICONS, nav_pill, screen, svg
from make_calm import PIN_DEFS, LABEL_DEFS, ME, pins_html, CSS3
root = pathlib.Path(__file__).parent

ICONS4 = {
 'i-nav': svg('<path d="M12 3l7 18-7-4-7 4z"/>', 14),
 'i-up': svg('<path d="M12 19V5"/><path d="M5 12l7-7 7 7"/>', 16),
 'i-left': svg('<path d="M15 6l-6 6 6 6"/>', 20),
 'i-right': svg('<path d="M9 6l6 6-6 6"/>', 20),
 'i-mapsm': svg('<path d="M9 4L3 6v14l6-2 6 2 6-2V4l-6 2z"/><path d="M9 4v14"/><path d="M15 6v14"/>', 16),
 'i-full': svg('<rect x="5" y="3" width="14" height="18" rx="2"/><path d="M9 17h6"/>', 16),
}
ICONS.update(ICONS4)
PINS = pins_html()

def search(toggle=False):
    tog = '<span class="tog" data-tog><button class="on" data-form="card" aria-label="بطاقة على الخريطة">@@i-mapsm@@</button><button data-form="full" aria-label="ملء الشاشة">@@i-full@@</button></span>' if toggle else ''
    return f'<div class="top"><div class="search glass">@@i-search@@<span style="flex-grow:1">ابحث في جدة</span>{tog}<span class="avm"><img src="@@avatar@@" alt=""></span></div></div>'

# ترتيب واحد ذكي: الأقرب أولاً مع تقديم ما ينتهي قريباً وما نُشر للتو
ITEMS = [
  {'pin': 'b1', 'img': 'p63', 'logo': 'overdose', 'kind': 'عرض', 'who': 'أوفردوز', 't': 'خصم ٢٠٪ على اللاتيه', 'd': 'الروضة · للأعضاء · ينتهي الليلة', 'dist': '٦٥٠ م', 'act': 'استخدم'},
  {'pin': 'm2', 'img': 'p184', 'logo': 'p26', 'kind': 'لحظة', 'who': 'سارة', 't': 'سارة في الروضة', 'd': 'قبل ٢٥ دقيقة · ١٢ إعجاباً', 'dist': '٨٠٠ م', 'act': 'شاهد'},
  {'pin': 'b2', 'img': 'p42', 'logo': 'halfmillion', 'kind': 'فعالية', 'who': 'هاف مليون', 't': 'بازار الحي', 'd': 'حديقة الشاطئ · اليوم ٥ م · ١٢ طاولة', 'dist': '٩٠٠ م', 'act': 'تذكرة'},
  {'pin': 'm1', 'img': 'p16', 'logo': 'avatar', 'kind': 'لحظة', 'who': 'فهد', 't': 'فهد على الكورنيش', 'd': 'قبل ١٢ دقيقة · ٢٤ إعجاباً', 'dist': '١.١ كم', 'act': 'شاهد'},
  {'pin': 'm4', 'img': 'p250', 'logo': 'p119', 'kind': 'سوق', 'who': 'عبدالله', 't': 'كاميرا فوجي X-T20', 'd': '2,650 ر.س · الحمراء · توصيل', 'dist': '١.٤ كم', 'act': 'اطلب'},
  {'pin': 'b3', 'img': 'p60', 'logo': '3brews', 'kind': 'وظيفة', 'who': 'ثري بروز', 't': 'يوظّف باريستا', 'd': 'دوام جزئي · ٤٬٥٠٠ ر.س · يطابق ملفك ٨٧٪', 'dist': '٢.١ كم', 'act': 'قدّم'},
  {'pin': 'm3', 'img': 'p274', 'logo': 'p154', 'kind': 'فيديو', 'who': 'نورة', 't': 'نورة في التحلية', 'd': 'قبل ساعة · ٠:٠٩', 'dist': '٣.٤ كم', 'act': 'شاهد'},
]
POS = {p[4]: (p[1], p[2]) for p in PIN_DEFS}
POS.update({l[4]: (l[2], l[3]) for l in LABEL_DEFS})
AR = str.maketrans('0123456789', '٠١٢٣٤٥٦٧٨٩')

# ---------- أ · بطاقة: الخريطة كاملة وبطاقة واحدة في الأسفل؛ السحب الجانبي هو الإيماءة الوحيدة والخريطة تتبع
def deck_html(with_search=True):
    it = ITEMS[0]
    return f'''<div class="map onemap"><div class="cam" data-cam>{MAP}{PINS}</div>{search() if with_search else ''}
      <div class="deck" data-deck>
        <div class="cnt"><button class="arr" data-prev aria-label="السابق">@@i-right@@</button><span data-cnt>١ من ٧ · الأقرب أولاً</span><button class="arr" data-next aria-label="التالي">@@i-left@@</button></div>
        <div class="dwin"><div class="dcard" data-dcard>
          <img class="ph" src="@@{it['img']}@@" alt="" data-oimg>
          <div class="b"><span class="k"><img src="@@{it['logo']}@@" alt="" data-ologo><span data-okind>{it['kind']} · {it['who']}</span><em data-odist>{it['dist']}</em></span><span class="t" data-ot>{it['t']}</span><span class="d" data-od>{it['d']}</span></div>
          <button class="btn sm" data-oact>{it['act']}</button>
        </div></div>
        <span class="swh">اسحب البطاقة للتالي · أو المس أي دبّوس</span>
      </div></div>'''
def A():
    return screen('home', deck_html(True), nav_pill('home'), 'abs')

# ---------- ب · شاشة: كل شيء بملء الشاشة ويُسحب للأعلى؛ خريطة مصغّرة تدلّ على الاتجاه والمسافة
def mini(pin):
    px, py = POS[pin]; mx, my = ME
    dx, dy = (mx - px), (py - my)      # right% يزيد نحو اليسار
    n = math.hypot(dx, dy) or 1
    x, y = 36 + dx / n * 24, 36 + dy / n * 24
    return f'''<svg viewBox="0 0 72 72" width="72" height="72" aria-hidden="true"><circle cx="36" cy="36" r="34" fill="rgba(255,255,255,.92)"/><circle cx="36" cy="36" r="24" fill="none" stroke="#E5E7EB" stroke-dasharray="3 3"/><line x1="36" y1="36" x2="{x:.1f}" y2="{y:.1f}" stroke="#0A6E78" stroke-width="2" stroke-linecap="round"/><circle cx="36" cy="36" r="4.5" fill="#1E88FF" stroke="#fff" stroke-width="2"/><circle cx="{x:.1f}" cy="{y:.1f}" r="5.5" fill="#0A6E78" stroke="#fff" stroke-width="2"/></svg>'''
def feed_html(with_search=True):
    secs = []
    for i, it in enumerate(ITEMS):
        secs.append(f'''<section class="fitem" data-fi="{i}"><img class="bg" src="@@{it['img']}@@" alt=""><div class="shade"></div>
          <div class="mini">{mini(it['pin'])}<b>{it['dist']}</b></div>
          <div class="info"><span class="k"><img src="@@{it['logo']}@@" alt="">{it['kind']} · {it['who']}</span><b>{it['t']}</b><span class="d">{it['d']}</span><button class="btn">{it['act']}</button></div>
          <span class="fcnt">{str(i + 1).translate(AR)} من ٧</span></section>''')
    return f'''<div class="feed" data-feed>{''.join(secs)}</div>{search() if with_search else ''}<span class="uph" data-uph>@@i-up@@ اسحب للأعلى</span>'''
def B():
    return screen('home', feed_html(True), nav_pill('home'), 'abs')

# ---------- ج · الاثنان بمفتاح واحد في شريط البحث؛ الصف واحد والموضع محفوظ عند التبديل
def C():
    home = f'''<div class="mode" data-mode="card">{deck_html(False)}</div><div class="mode" data-mode="full" hidden>{feed_html(False)}</div>{search(toggle=True)}'''
    return screen('home', home, nav_pill('home'), 'abs')

CSS4 = r'''
/* أ · بطاقة */
.onemap{overflow:hidden}
.cam{position:absolute;inset:0;transform-origin:50% 50%;transition:transform .55s cubic-bezier(.2,.8,.2,1);will-change:transform}
.cam .pin,.cam .plabel,.cam .me{transform:translate(50%,-50%) scale(.68)}
.cam .pin.hi{z-index:3}
.cam .pin.hi img{box-shadow:0 0 0 4px var(--a),0 2px 10px rgba(0,0,0,.3)}
.cam .plabel.hi img{box-shadow:0 0 0 3px var(--a),0 1px 4px rgba(0,0,0,.3)}
.cam .pin.dim,.cam .plabel.dim{opacity:.55}
.deck{position:absolute;right:14px;left:14px;bottom:88px;display:flex;flex-direction:column;gap:8px;align-items:stretch}
.cnt{display:flex;align-items:center;justify-content:space-between;color:#374151;font-size:12px;font-weight:600}
.cnt span{background:rgba(255,255,255,.94);padding:5px 12px;border-radius:999px;box-shadow:0 2px 8px rgba(0,0,0,.12)}
.arr{width:34px;height:34px;border-radius:999px;border:0;background:rgba(255,255,255,.94);color:#111;box-shadow:0 2px 8px rgba(0,0,0,.14);display:inline-flex;align-items:center;justify-content:center;cursor:pointer}
.dwin{overflow:hidden;border-radius:20px}
.dcard{display:flex;flex-direction:column;background:#fff;border-radius:20px;box-shadow:0 12px 32px rgba(0,0,0,.2);overflow:hidden;touch-action:pan-y;user-select:none;cursor:grab;transition:transform .32s cubic-bezier(.2,.8,.2,1),opacity .32s}
.dcard.drag{transition:none;cursor:grabbing}
.dcard.outl{transform:translateX(-110%) rotate(-3deg);opacity:0}
.dcard.outr{transform:translateX(110%) rotate(3deg);opacity:0}
.dcard.inl{transform:translateX(-40%);opacity:0}
.dcard.inr{transform:translateX(40%);opacity:0}
.dcard .ph{width:100%;height:118px;object-fit:cover;display:block}
.dcard .b{display:flex;flex-direction:column;gap:3px;padding:10px 14px 6px}
.dcard .k{display:flex;align-items:center;gap:6px;font-size:12px;color:#6B7280;font-weight:600}
.dcard .k img{width:20px;height:20px;border-radius:999px;object-fit:cover}
.dcard .k em{font-style:normal;margin-right:auto;color:var(--a);font-weight:700}
.dcard .t{font:800 18px var(--font-display);color:#111}
.dcard .d{font-size:12.5px;color:#374151}
.dcard .btn{margin:6px 14px 14px;align-self:flex-start}
.swh{align-self:center;font-size:11px;color:#6B7280;background:rgba(255,255,255,.9);padding:3px 10px;border-radius:999px}
/* ب · شاشة */
.feed{position:absolute;inset:0;overflow-y:auto;scroll-snap-type:y mandatory;scrollbar-width:none;background:#111}
.feed::-webkit-scrollbar{display:none}
.fitem{position:relative;height:100%;scroll-snap-align:start;scroll-snap-stop:always;overflow:hidden}
.fitem .bg{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}
.fitem .shade{position:absolute;inset:0;background:linear-gradient(rgba(0,0,0,.25),transparent 30%,transparent 45%,rgba(0,0,0,.78))}
.fitem .mini{position:absolute;top:70px;left:14px;display:flex;flex-direction:column;align-items:center;gap:4px}
.fitem .mini b{font-size:12px;color:#fff;background:rgba(0,0,0,.45);padding:3px 9px;border-radius:999px;font-weight:700}
.fitem .info{position:absolute;right:16px;left:16px;bottom:120px;display:flex;flex-direction:column;gap:6px;color:#fff}
.fitem .info .k{display:flex;align-items:center;gap:7px;font-size:13px;font-weight:600;opacity:.95}
.fitem .info .k img{width:26px;height:26px;border-radius:999px;border:2px solid #fff;object-fit:cover}
.fitem .info b{font:800 26px/1.2 var(--font-display);text-shadow:0 1px 8px rgba(0,0,0,.4);text-wrap:balance}
.fitem .info .d{font-size:13.5px;opacity:.92;line-height:1.5}
.fitem .info .btn{align-self:flex-start;margin-top:6px;background:#fff;color:#111}
.fitem .fcnt{position:absolute;top:70px;right:14px;font-size:12px;color:#fff;background:rgba(0,0,0,.45);padding:4px 10px;border-radius:999px;font-weight:600}
.uph{position:absolute;left:50%;transform:translateX(-50%);bottom:86px;display:inline-flex;align-items:center;gap:5px;font-size:11.5px;color:#fff;background:rgba(0,0,0,.45);padding:4px 11px;border-radius:999px;pointer-events:none;transition:opacity .4s}
.uph.gone{opacity:0}
.scr>.top{position:absolute;top:10px;right:0;left:0;display:flex;flex-direction:column;gap:8px;z-index:5}
/* ج · المفتاح */
.mode{position:absolute;inset:0}
.mode>.map{position:absolute;inset:0}
.tog{display:inline-flex;gap:2px;background:#F2F2F7;border-radius:999px;padding:2px;flex:none}
.tog button{width:30px;height:28px;border:0;border-radius:999px;background:transparent;color:#6B7280;display:inline-flex;align-items:center;justify-content:center;cursor:pointer}
.tog button.on{background:#111;color:#fff}
/* صفحة */
.gone-list{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:6px 16px;font-size:13.5px;line-height:1.6;border:1px solid var(--line);border-radius:14px;padding:12px 16px}
.gone-list div{display:flex;gap:8px;align-items:center}
.gone-list i{flex:none;width:18px;height:18px;border-radius:999px;background:#FDE8E8;color:#B42318;display:inline-flex;align-items:center;justify-content:center;font-style:normal;font-size:11px;font-weight:800}
.gone-list .keep i{background:var(--a-soft);color:var(--a)}
'''

DATA = {'items': [{'pin': it['pin'], 'img': it['img'], 'logo': it['logo'], 'kind': it['kind'], 'who': it['who'], 't': it['t'], 'd': it['d'], 'dist': it['dist'], 'act': it['act']} for it in ITEMS], 'pos': POS, 'me': ME}

JS = r'''
(function(){
  var D = __DATA__;
  var slots = {a:'s-a', b:'s-b', c:'s-c'};
  function go(id){
    Object.keys(slots).forEach(function(k){ document.getElementById(slots[k]).classList.toggle('active', k===id); });
    document.querySelectorAll('#seg button').forEach(function(b){ b.classList.toggle('on', b.getAttribute('data-go')===id); });
    if (window.innerWidth <= 1250) window.scrollTo({top:0, behavior:'smooth'});
    try { localStorage.setItem('nl-one-concept', id); } catch(e){}
    setTimeout(function(){ window.dispatchEvent(new Event('resize')); }, 60);   // الخريطة المخفية تعيد التركيز بعد الظهور
  }
  document.querySelectorAll('#seg button').forEach(function(b){ b.addEventListener('click', function(){ go(b.getAttribute('data-go')); }); });
  var saved = null; try { saved = localStorage.getItem('nl-one-concept'); } catch(e){}
  if (saved && slots[saved]) go(saved);
  var AR = '٠١٢٣٤٥٦٧٨٩'; function ar(n){ return String(n).replace(/\d/g, function(d){ return AR[+d]; }); }

  // ---- البطاقة على الخريطة (تُستخدم في أ و ج)
  function initDeck(root, slotId){
    var map = root.querySelector('.map'), cam = root.querySelector('[data-cam]'), card = root.querySelector('[data-dcard]');
    var S = 1.5, i = 0, srcs = {};
    root.querySelectorAll('.pin img,.plabel img').forEach(function(im){ srcs[im.parentNode.getAttribute('data-id')] = im.src; });
    function focus(pin){
      var W = map.clientWidth, H = map.clientHeight, p = D.pos[pin];
      if (!W || !H) return;
      var px = W - W*p[0]/100, py = H*p[1]/100, cx = W/2, cy = H/2, tx = W/2, ty = H*0.33;
      var dx = tx - cx - (px - cx)*S, dy = ty - cy - (py - cy)*S;
      cam.style.transform = 'translate('+dx+'px,'+dy+'px) scale('+S+')';
      root.querySelectorAll('.pin,.plabel').forEach(function(e){ var on = e.getAttribute('data-id')===pin; e.classList.toggle('hi', on); e.classList.toggle('dim', !on); });
    }
    function fill(){
      var it = D.items[i];
      root.querySelector('[data-okind]').textContent = it.kind + ' · ' + it.who;
      root.querySelector('[data-odist]').textContent = it.dist; root.querySelector('[data-ot]').textContent = it.t; root.querySelector('[data-od]').textContent = it.d; root.querySelector('[data-oact]').textContent = it.act;
      root.querySelector('[data-oimg]').src = ASSETS[it.img] || root.querySelector('[data-oimg]').src;
      root.querySelector('[data-ologo]').src = ASSETS[it.logo] || srcs[it.pin] || root.querySelector('[data-ologo]').src;
      root.querySelector('[data-cnt]').textContent = ar(i+1) + ' من ' + ar(D.items.length) + ' · الأقرب أولاً';
      focus(it.pin);
    }
    var busy = false;
    function goTo(j, dir){
      if (busy) return; busy = true;
      j = (j + D.items.length) % D.items.length;
      card.classList.remove('drag'); card.style.transform = '';
      card.classList.add(dir < 0 ? 'outl' : 'outr');
      setTimeout(function(){
        i = j; fill();
        card.classList.remove('outl', 'outr'); card.classList.add('drag'); card.classList.add(dir < 0 ? 'inr' : 'inl');
        void card.offsetWidth; card.classList.remove('drag');
        requestAnimationFrame(function(){ card.classList.remove('inl', 'inr'); setTimeout(function(){ busy = false; }, 320); });
      }, 300);
    }
    root.querySelector('[data-next]').addEventListener('click', function(){ goTo(i+1, -1); });
    root.querySelector('[data-prev]').addEventListener('click', function(){ goTo(i-1, 1); });
    var sx = null, dx = 0;
    card.addEventListener('pointerdown', function(e){ sx = e.clientX; dx = 0; card.classList.add('drag'); card.setPointerCapture(e.pointerId); });
    card.addEventListener('pointermove', function(e){ if (sx===null) return; dx = e.clientX - sx; card.style.transform = 'translateX('+dx+'px) rotate('+(dx/40)+'deg)'; });
    function up(){ if (sx===null) return; sx = null; card.classList.remove('drag');
      if (Math.abs(dx) > 60) goTo(dx < 0 ? i+1 : i-1, dx < 0 ? -1 : 1); else card.style.transform = ''; }
    card.addEventListener('pointerup', up); card.addEventListener('pointercancel', up);
    root.querySelectorAll('.pin,.plabel').forEach(function(p){ p.addEventListener('click', function(){
      var id = p.getAttribute('data-id'); var j = -1; D.items.forEach(function(it, k){ if (it.pin===id && j<0) j = k; });
      if (j >= 0 && j !== i) goTo(j, j > i ? -1 : 1);
    }); });
    document.addEventListener('keydown', function(e){ if (!document.getElementById(slotId).classList.contains('active') || root.offsetParent===null) return; if (e.key==='ArrowLeft') goTo(i+1, -1); if (e.key==='ArrowRight') goTo(i-1, 1); });
    fill(); window.addEventListener('resize', function(){ focus(D.items[i].pin); }); setTimeout(function(){ focus(D.items[i].pin); }, 350);
    return { index: function(){ return i; }, jump: function(j){ i = (j + D.items.length) % D.items.length; fill(); }, refocus: function(){ focus(D.items[i].pin); } };
  }
  // ---- ملء الشاشة (تُستخدم في ب و ج)
  function initFeed(root){
    var feed = root.querySelector('[data-feed]'), hint = root.querySelector('[data-uph]');
    feed.addEventListener('scroll', function(){ hint.classList.toggle('gone', feed.scrollTop > 40); }, {passive:true});
    return { index: function(){ return Math.round(feed.scrollTop / (feed.clientHeight || 1)); }, show: function(j){ feed.scrollTop = j * feed.clientHeight; hint.classList.toggle('gone', j > 0); } };
  }

  var a = document.querySelector('[data-concept=a]'); if (a) initDeck(a, 's-a');
  var b = document.querySelector('[data-concept=b]'); if (b) initFeed(b);

  // ---- ج · المفتاح: شكلان على الصف نفسه، والموضع محفوظ، والاختيار يُتذكّر
  var c = document.querySelector('[data-concept=c]');
  if (c) {
    var cardMode = c.querySelector('[data-mode=card]'), fullMode = c.querySelector('[data-mode=full]');
    var deck = initDeck(cardMode, 's-c'), feed = initFeed(fullMode);
    function form(f){
      c.querySelectorAll('[data-form]').forEach(function(x){ x.classList.toggle('on', x.getAttribute('data-form')===f); });
      if (f === 'full') { var j = deck.index(); fullMode.hidden = false; cardMode.hidden = true; feed.show(j); }
      else { var k = feed.index(); cardMode.hidden = false; fullMode.hidden = true; deck.jump(k); requestAnimationFrame(function(){ deck.refocus(); }); }
      try { localStorage.setItem('nl-one-form', f); } catch(e){}
    }
    c.querySelectorAll('[data-form]').forEach(function(x){ x.addEventListener('click', function(){ form(x.getAttribute('data-form')); }); });
    var sf = null; try { sf = localStorage.getItem('nl-one-form'); } catch(e){}
    if (sf === 'full') form('full');
  }
})();
'''

if __name__ == '__main__':
    import base64
    # الصور كقاموس داخل الصفحة حتى تبدّل بطاقة «أ» صورتها دون لمس الرموز
    assets = {}
    for it in ITEMS:
        for key in (it['img'], it['logo']):
            for ext, mime in (('.jpg', 'image/jpeg'), ('.png', 'image/png')):
                p = root / 'img' / (key + ext)
                if p.exists(): assets[key] = 'data:' + mime + ';base64,' + base64.b64encode(p.read_bytes()).decode()
    js = 'var ASSETS = ' + json.dumps(assets) + ';\n' + JS.replace('__DATA__', json.dumps(DATA, ensure_ascii=False))
    page = '''<title>نظام واحد</title>
<meta name="description" content="نظام «واحد» لخريطة ناس لايف: شيء واحد في المرة، إيماءة واحدة، زر واحد، ولا شيء آخر على الشاشة. شكلان: بطاقة تُسحب جانبياً وشاشة تُسحب للأعلى، ومفتاح يجمعهما.">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Rubik:wght@400;500;600;700&family=Baloo+Bhaijaan+2:wght@600;700;800&display=swap">
<style>__CSS__</style>
<div class="wrap">
  <header>
    <h1>نظام «واحد»</h1>
    <p class="sub">أبسط ما يمكن أن يكون عليه التطبيق: شيء واحد في المرة، إيماءة واحدة يعرفها كل من أمسك هاتفاً، زر واحد، ولا شيء آخر على الشاشة سوى البحث. لا ورقة ولا رقائق ولا أقسام ولا تخصيص ولا مرشّحات ولا تبويبات؛ الترتيب واحد ذكي: الأقرب أولاً، مع تقديم ما ينتهي قريباً وما نُشر للتو. العروض والوظائف والسوق واللحظات والفعاليات كلها بطاقات متساوية في الصف نفسه. الشكلان الأولان هما النظام نفسه بإيماءتين مختلفتين، والثالث يترك للمستخدم اختيار الإيماءة بمفتاح واحد في شريط البحث.</p>
    <div class="gone-list">
      <div><i>×</i><span>الورقة السفلية</span></div><div><i>×</i><span>صف الرقائق</span></div><div><i>×</i><span>الأقسام الـ12</span></div>
      <div><i>×</i><span>شاشة التخصيص ووضع التحرير</span></div><div><i>×</i><span>تبويبات الملف والدائرة من الرئيسية</span></div><div><i>×</i><span>مفاتيح الطبقات</span></div>
      <div class="keep"><i>✓</i><span>البحث</span></div><div class="keep"><i>✓</i><span>الخريطة أو الصورة</span></div><div class="keep"><i>✓</i><span>بطاقة واحدة وزر واحد</span></div>
    </div>
    <div class="rowh">
      <div class="seg" id="seg" role="tablist" aria-label="الأشكال">
        <button class="on" data-go="a" role="tab"><i>أ</i>بطاقة · سحب جانبي</button>
        <button data-go="b" role="tab"><i>ب</i>شاشة · سحب للأعلى</button>
        <button data-go="c" role="tab"><i>ج</i>الاثنان بمفتاح</button>
      </div>
    </div>
  </header>

  <div class="phones">
    <section class="slot active" id="s-a">
      <h2><span>أ</span>بطاقة <small>· الخريطة كاملة وبطاقة واحدة تتبعها الخريطة</small></h2>
      <div class="phone"><div class="screen" data-concept="a">__A__</div></div>
      <p class="note">الخريطة كاملة وبطاقة واحدة في الأسفل. اسحب البطاقة يميناً أو يساراً فتأتي التالية وتنزلق الخريطة بهدوء إلى دبّوسها وتُبرزه وتخفّف الباقي. المس أي دبّوس فتقفز إليه البطاقة. عدّاد صغير «٣ من ٧» ليعرف المستخدم أين هو، وزر واحد على البطاقة بحسب نوعها: استخدم، شاهد، تذكرة، اطلب، قدّم. هذا كل شيء؛ لا يوجد ما يُتعلَّم.</p>
    </section>
    <section class="slot" id="s-b">
      <h2><span>ب</span>شاشة <small>· كل شيء بملء الشاشة، والخريطة بوصلة صغيرة</small></h2>
      <div class="phone"><div class="screen" data-concept="b">__B__</div></div>
      <p class="note">الإيماءة الأكثر رسوخاً في أيدي الناس: اسحب للأعلى. كل عنصر يملأ الشاشة بصورته، وبوصلة صغيرة في الزاوية تدلّ على اتجاهه عنك ومسافته، وزر واحد. الخريطة الكاملة تُفتح من البوصلة أو من تبويبها عند الحاجة فقط. الأنسب لمن يفتح التطبيق ليتسلّى بما حوله، والأسهل تعلّماً على الإطلاق، على حساب أن الخريطة لم تعد أول ما يُرى.</p>
    </section>
    <section class="slot" id="s-c">
      <h2><span>ج</span>الاثنان بمفتاح <small>· المستخدم يختار الإيماءة، والتطبيق يتذكّر</small></h2>
      <div class="phone"><div class="screen" data-concept="c">__C__</div></div>
      <p class="note">الشكلان على الصف نفسه، ومفتاح صغير برمزين في شريط البحث يبدّل بينهما. الموضع محفوظ عند التبديل: إن كنت على البطاقة الثالثة فستفتح الشاشة الثالثة، والعكس. الاختيار يُحفظ في الحساب فلا يُسأل المستخدم شيئاً عند الدخول، والافتراضي للجميع «بطاقة» لأنه يُبقي الخريطة أول ما يُرى. جرّب: اسحب بطاقتين ثم بدّل المفتاح.</p>
    </section>
  </div>

  <div class="tblwrap"><table class="cmp">
    <thead><tr><th>المعيار</th><th>أ · بطاقة</th><th>ب · شاشة</th><th>ج · الاثنان بمفتاح</th></tr></thead>
    <tbody>
      <tr><th>الإيماءة</th><td>سحب جانبي (أو لمس دبّوس)</td><td>سحب للأعلى</td><td>ما يختاره المستخدم</td></tr>
      <tr><th>ما على الشاشة</th><td>خريطة، بطاقة، عدّاد، بحث</td><td>صورة، بوصلة، بطاقة، بحث</td><td>الشكل المختار + مفتاح برمزين</td></tr>
      <tr><th>وقت التعلّم</th><td>ثوانٍ</td><td><b>صفر</b></td><td>ثوانٍ، والمفتاح لا يحتاج شرحاً</td></tr>
      <tr><th>هوية الخريطة</th><td><b>كاملة</b></td><td>بوصلة صغيرة</td><td>كاملة افتراضياً</td></tr>
      <tr><th>العروض والوظائف والسوق</th><td colspan="3">بطاقات متساوية في الصف نفسه بالترتيب الذكي، بلا أقسام ولا طبقات</td></tr>
      <tr><th>ما يحتاجه الخادم</th><td colspan="2">مسار واحد: «الصف» بحدّ ٣٠ عنصراً من كل الأنواع</td><td>المسار نفسه + حفظ الاختيار في إعدادات الحساب (موجودة)</td></tr>
      <tr><th>أثر التنفيذ</th><td>صغير</td><td>صغير</td><td>صغير + يومان للشكل الثاني والمفتاح والاختبارات</td></tr>
      <tr><th>الخطر</th><td>لا شيء يُذكر</td><td>الخريطة تختفي من الانطباع الأول</td><td>شكلان يُختبران ويُصانان معاً</td></tr>
    </tbody>
  </table></div>

  <div class="reco">
    <b>توصيتي</b>
    <span>نعم، التخيير ممكن بلا عودة إلى الازدحام بشرطين: مفتاح واحد في مكان واحد لا يُسأل عنه المستخدم عند الدخول، وافتراضي واحد للجميع هو «بطاقة». الصف والبطاقات والزر واحدة في الشكلين فلا تتضاعف الشاشات، وتبقى كلفة الشكل الثاني يومين تقريباً. وبعد شهر من الإطلاق تخبرنا الأرقام أيهما يُستخدم، فإن هجر الناس أحدهما نحذفه ونعود إلى شكل واحد.</span>
  </div>
</div>

<script>__JS__</script>
'''
    page = page.replace('__CSS__', CSS + CSS3 + CSS4).replace('__A__', A()).replace('__B__', B()).replace('__C__', C()).replace('__JS__', js)
    icons_path = root / 'icons.json'
    icons = json.loads(icons_path.read_text(encoding='utf-8'))
    icons.update(ICONS4)
    icons_path.write_text(json.dumps(icons, ensure_ascii=False, indent=1), encoding='utf-8')
    (root / 'template_one.html').write_text(page, encoding='utf-8')
