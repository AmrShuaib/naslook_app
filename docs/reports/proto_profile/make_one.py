# يولّد template_one.html: نظام «واحد»: شيء واحد في المرة، إيماءة واحدة، زر واحد، ولا شيء آخر على الشاشة.
# أ «بطاقة» مدمجة صغيرة على خريطة كاملة تُسحب جانبياً والخريطة تتبعها، ب «شاشة» بملء الشاشة تُسحب للأعلى ببوصلة مصغّرة،
# ج الاثنان بمفتاح يتذكّره التطبيق ويحفظ الموضع، د «مناطق حرارية» حين تكثر المشاركات: بطاقات المناطق أولاً ثم ما بداخلها (مثال حي).
# البناء: python3 make_one.py && python3 build.py template_one.html > out.html
import json, math, pathlib, random
from make_main import CSS, MAP, ICONS, nav_pill, screen, svg
from make_calm import PIN_DEFS, LABEL_DEFS, ME, CSS3
root = pathlib.Path(__file__).parent

ICONS4 = {
 'i-up': svg('<path d="M12 19V5"/><path d="M5 12l7-7 7 7"/>', 16),
 'i-left': svg('<path d="M15 6l-6 6 6 6"/>', 18),
 'i-right': svg('<path d="M9 6l6 6-6 6"/>', 18),
 'i-mapsm': svg('<path d="M9 4L3 6v14l6-2 6 2 6-2V4l-6 2z"/><path d="M9 4v14"/><path d="M15 6v14"/>', 16),
 'i-full': svg('<rect x="5" y="3" width="14" height="18" rx="2"/><path d="M9 17h6"/>', 16),
 'i-fire': svg('<path d="M12 22c-4 0-7-3-7-7 0-3 2-5 3-7 0 2 1 3 2 3 0-4 2-6 4-8 0 3 1 4 3 6 2 2 2 4 2 6 0 4-3 7-7 7z"/>', 14, stroke=False),
 'i-zones': svg('<circle cx="7" cy="8" r="3.5"/><circle cx="16" cy="15" r="4.5"/><circle cx="17" cy="6" r="2"/>', 16),
}
ICONS.update(ICONS4)

# ---------- المناطق (مراكز الكثافة) ومعرّف المنطقة لكل دبّوس
ZONES = [
  {'id': 'rawda', 'name': 'الروضة', 'x': 44, 'y': 66, 'n': 64, 'offers': 12, 'events': 3, 'dist': '٦٥٠ م', 'img': 'p63'},
  {'id': 'shati', 'name': 'الشاطئ', 'x': 32, 'y': 33, 'n': 48, 'offers': 7, 'events': 2, 'dist': '١.٢ كم', 'img': 'p16'},
  {'id': 'hamra', 'name': 'الحمراء', 'x': 62, 'y': 52, 'n': 31, 'offers': 5, 'events': 1, 'dist': '٩٠٠ م', 'img': 'p60'},
  {'id': 'tahlia', 'name': 'التحلية', 'x': 26, 'y': 80, 'n': 33, 'offers': 4, 'events': 1, 'dist': '٣.٤ كم', 'img': 'p274'},
]
def zone_of(x, y):
    return min(ZONES, key=lambda z: math.hypot(z['x'] - x, z['y'] - y))['id']
def pins_html():
    out = []
    for img, x, y, kind, pid, _, _ in PIN_DEFS:
        k = f'<i class="k">@@{kind}@@</i>' if kind else ''
        out.append(f'<span class="pin" data-id="{pid}" data-zone="{zone_of(x, y)}" style="right:{x}%;top:{y}%"><img src="@@{img}@@" alt="">{k}</span>')
    for img, name, x, y, pid, _ in LABEL_DEFS:
        out.append(f'<span class="plabel" data-id="{pid}" data-zone="{zone_of(x, y)}" style="right:{x}%;top:{y}%"><img src="@@{img}@@" alt="">{name}</span>')
    out.append(f'<span class="me" data-id="me" style="right:{ME[0]}%;top:{ME[1]}%"></span>')
    return '<div class="pins">' + ''.join(out) + '</div>'
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
for it in ITEMS: it['zone'] = zone_of(*POS[it['pin']])
AR = str.maketrans('0123456789', '٠١٢٣٤٥٦٧٨٩')

# ---------- البطاقة المدمجة الصغيرة (أفقية: صورة ٦٨ بكسل، سطران، زر) حتى تبقى الخريطة أوسع
def card_html(it):
    return f'''<div class="dwin"><div class="dcard" data-dcard>
          <img class="ph" src="@@{it['img']}@@" alt="" data-oimg>
          <div class="b"><span class="k"><img src="@@{it['logo']}@@" alt="" data-ologo><span data-okind>{it['kind']} · {it['who']}</span><em data-odist>{it['dist']}</em></span><span class="t" data-ot>{it['t']}</span><span class="d" data-od>{it['d']}</span></div>
          <button class="btn sm" data-oact>{it['act']}</button>
        </div></div>'''
def deck_html(with_search=True, heat=False):
    it = ITEMS[0]
    cnt_text = '١ من ٧ · الأقرب أولاً'
    back = '<button class="arr back" data-back hidden aria-label="رجوع إلى المناطق">@@i-zones@@</button>'
    return f'''<div class="map onemap{' heatmap' if heat else ''}"><div class="cam" data-cam>{MAP}{heat_layer() if heat else ''}{PINS}</div>{search() if with_search else ''}
      <div class="deck" data-deck>
        <div class="cnt">{back}<button class="arr" data-prev aria-label="السابق">@@i-right@@</button><span data-cnt>{cnt_text}</span><button class="arr" data-next aria-label="التالي">@@i-left@@</button></div>
        {card_html(it)}
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

# ---------- د · المناطق الحرارية: طبقة كثافة (بقع حرارية ونقاط المشاركات) وبطاقات المناطق أولاً
def heat_layer():
    rnd = random.Random(7)
    dots = []
    for z in ZONES:
        for _ in range(z['n'] // 2):
            # توزيع متجمّع حول مركز المنطقة
            dx = (rnd.random() + rnd.random() + rnd.random() - 1.5) * 9
            dy = (rnd.random() + rnd.random() + rnd.random() - 1.5) * 7
            dots.append(f'<i class="hd" style="right:{z["x"] + dx:.1f}%;top:{z["y"] + dy:.1f}%"></i>')
    blobs = ''.join(f'<i class="blob" data-blob="{z["id"]}" style="right:{z["x"]}%;top:{z["y"]}%;--s:{90 + z["n"] * 1.6:.0f}px"></i>' for z in ZONES)
    labels = ''.join(f'<button class="zl" data-zl="{z["id"]}" style="right:{z["x"]}%;top:{z["y"] - 9}%">@@i-fire@@{z["name"]}<b data-zn="{z["id"]}">{str(z["n"]).translate(AR)}</b></button>' for z in ZONES)
    return f'<div class="heat" data-heat>{blobs}<div class="hdots" data-hdots>{"".join(dots)}</div>{labels}</div>'
def D():
    return screen('home', deck_html(True, heat=True), nav_pill('home'), 'abs')

CSS4 = r'''
/* أ · بطاقة مدمجة صغيرة */
.onemap{overflow:hidden}
.cam{position:absolute;inset:0;transform-origin:50% 50%;transition:transform .55s cubic-bezier(.2,.8,.2,1);will-change:transform}
.cam .pin,.cam .plabel,.cam .me{transform:translate(50%,-50%) scale(.68)}
.cam .pin.hi{z-index:3}
.cam .pin.hi img{box-shadow:0 0 0 4px var(--a),0 2px 10px rgba(0,0,0,.3)}
.cam .plabel.hi img{box-shadow:0 0 0 3px var(--a),0 1px 4px rgba(0,0,0,.3)}
.cam .pin.dim,.cam .plabel.dim{opacity:.55}
.deck{position:absolute;right:12px;left:12px;bottom:86px;display:flex;flex-direction:column;gap:6px;align-items:stretch}
.cnt{display:flex;align-items:center;justify-content:space-between;gap:6px;color:#374151;font-size:11.5px;font-weight:600}
.cnt span{flex-grow:1;text-align:center;background:rgba(255,255,255,.94);padding:4px 10px;border-radius:999px;box-shadow:0 2px 8px rgba(0,0,0,.12);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.arr{flex:none;width:30px;height:30px;border-radius:999px;border:0;background:rgba(255,255,255,.94);color:#111;box-shadow:0 2px 8px rgba(0,0,0,.14);display:inline-flex;align-items:center;justify-content:center;cursor:pointer}
.arr.back{background:var(--a);color:#fff}
.dwin{overflow:hidden;border-radius:18px}
.dcard{display:flex;align-items:center;gap:10px;background:#fff;border-radius:18px;box-shadow:0 10px 28px rgba(0,0,0,.2);padding:8px;touch-action:pan-y;user-select:none;cursor:grab;transition:transform .32s cubic-bezier(.2,.8,.2,1),opacity .32s}
.dcard.drag{transition:none;cursor:grabbing}
.dcard.outl{transform:translateX(-110%) rotate(-3deg);opacity:0}
.dcard.outr{transform:translateX(110%) rotate(3deg);opacity:0}
.dcard.inl{transform:translateX(-40%);opacity:0}
.dcard.inr{transform:translateX(40%);opacity:0}
.dcard .ph{width:68px;height:68px;border-radius:14px;object-fit:cover;display:block;flex:none}
.dcard .b{flex-grow:1;min-width:0;display:flex;flex-direction:column;gap:2px}
.dcard .k{display:flex;align-items:center;gap:5px;font-size:11px;color:#6B7280;font-weight:600;white-space:nowrap;overflow:hidden}
.dcard .k img{width:16px;height:16px;border-radius:999px;object-fit:cover;flex:none}
.dcard .k em{font-style:normal;margin-right:auto;color:var(--a);font-weight:700;flex:none}
.dcard .t{font:800 15px/1.25 var(--font-display);color:#111;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.dcard .d{font-size:11.5px;color:#374151;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.dcard .btn{flex:none;height:34px;padding:0 13px;font-size:12.5px}
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
/* د · المناطق الحرارية */
.heat{position:absolute;inset:0;transition:opacity .45s}
.heatmap.in .heat{opacity:0;pointer-events:none}
.blob{position:absolute;width:var(--s);height:var(--s);transform:translate(50%,-50%);border-radius:999px;pointer-events:none;background:radial-gradient(circle,rgba(255,72,40,.50) 0%,rgba(255,140,40,.30) 34%,rgba(255,205,90,.14) 58%,transparent 72%);mix-blend-mode:multiply;transition:width .6s ease,height .6s ease,filter .3s}
.blob.hi{filter:saturate(1.4) contrast(1.1)}
.hdots{position:absolute;inset:0;pointer-events:none}
.hd{position:absolute;width:5px;height:5px;border-radius:999px;background:rgba(190,36,20,.6);transform:translate(50%,-50%)}
@keyframes pop{0%{transform:translate(50%,-50%) scale(0)}55%{transform:translate(50%,-50%) scale(2.6)}100%{transform:translate(50%,-50%) scale(1)}}
.hd.pop{animation:pop .7s ease-out;background:#C2410C}
.zl{position:absolute;transform:translate(50%,-50%);display:inline-flex;align-items:center;gap:5px;height:28px;padding:0 10px 0 8px;border:0;border-radius:999px;background:rgba(255,255,255,.96);color:#111;box-shadow:0 3px 10px rgba(0,0,0,.16);font:700 12px var(--font-body);cursor:pointer;z-index:2}
.zl svg{color:#EA580C}
.zl b{color:#C2410C;font-variant-numeric:tabular-nums}
.zl.hi{outline:2px solid #EA580C;outline-offset:-2px}
.heatmap .pins .pin,.heatmap .pins .plabel{opacity:0;pointer-events:none;transition:opacity .4s}
.heatmap.in .pins .pin.show,.heatmap.in .pins .plabel.show{opacity:1;pointer-events:auto}
.heatmap.in .pins .pin.show.dim,.heatmap.in .pins .plabel.show.dim{opacity:.55}
.live{display:inline-flex;align-items:center;gap:5px}
.live i{width:7px;height:7px;border-radius:999px;background:#DC2626;animation:beat 1.4s ease-in-out infinite}
@keyframes beat{0%,100%{transform:scale(1);opacity:1}50%{transform:scale(1.5);opacity:.55}}
.dcard .fire{position:absolute;right:8px;top:8px;width:22px;height:22px;border-radius:999px;background:#fff;color:#EA580C;display:inline-flex;align-items:center;justify-content:center;box-shadow:0 1px 4px rgba(0,0,0,.2)}
.dcard{position:relative}
/* صفحة */
.gone-list{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:6px 16px;font-size:13.5px;line-height:1.6;border:1px solid var(--line);border-radius:14px;padding:12px 16px}
.gone-list div{display:flex;gap:8px;align-items:center}
.gone-list i{flex:none;width:18px;height:18px;border-radius:999px;background:#FDE8E8;color:#B42318;display:inline-flex;align-items:center;justify-content:center;font-style:normal;font-size:11px;font-weight:800}
.gone-list .keep i{background:var(--a-soft);color:var(--a)}
'''

DATA = {'items': ITEMS, 'pos': POS, 'me': ME, 'zones': ZONES}

JS = r'''
(function(){
  var D = __DATA__;
  var slots = {a:'s-a', b:'s-b', c:'s-c', d:'s-d'};
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

  // ---- مجموعة بطاقات على خريطة: عناصر قابلة للتبديل (صف الأقرب، أو المناطق، أو ما بداخل منطقة)
  function makeDeck(root, slotId, cfg){
    var map = root.querySelector('.map'), cam = root.querySelector('[data-cam]'), card = root.querySelector('[data-dcard]');
    var items = cfg.items.slice(), i = 0, srcs = {};
    root.querySelectorAll('.pin img,.plabel img').forEach(function(im){ srcs[im.parentNode.getAttribute('data-id')] = im.src; });
    function camTo(p, S, ty){
      var W = map.clientWidth, H = map.clientHeight; if (!W || !H) return;
      var px = W - W*p[0]/100, py = H*p[1]/100, cx = W/2, cy = H/2, tx = W/2;
      var dx = tx - cx - (px - cx)*S, dy = H*ty - cy - (py - cy)*S;
      cam.style.transform = 'translate('+dx+'px,'+dy+'px) scale('+S+')';
    }
    function focusPin(pin, S){
      camTo(D.pos[pin], S || 1.5, 0.42);
      root.querySelectorAll('.pin,.plabel').forEach(function(e){ var on = e.getAttribute('data-id')===pin; e.classList.toggle('hi', on); e.classList.toggle('dim', !on); });
    }
    function fill(){
      var it = items[i];
      root.querySelector('[data-okind]').textContent = it.kind + ' · ' + it.who;
      root.querySelector('[data-odist]').textContent = it.dist; root.querySelector('[data-ot]').textContent = it.t; root.querySelector('[data-od]').textContent = it.d; root.querySelector('[data-oact]').textContent = it.act;
      root.querySelector('[data-oimg]').src = ASSETS[it.img] || root.querySelector('[data-oimg]').src;
      var lg = root.querySelector('[data-ologo]'); lg.src = ASSETS[it.logo] || srcs[it.pin] || lg.src; lg.hidden = !(it.logo);
      root.querySelector('[data-cnt]').innerHTML = cfg.label(i, items.length, it);
      cfg.onFocus(it, focusPin, camTo);
    }
    var busy = false;
    function goTo(j, dir){
      if (busy || items.length < 2) return; busy = true;
      j = (j + items.length) % items.length;
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
    root.querySelector('[data-oact]').addEventListener('click', function(){ if (cfg.onAct) cfg.onAct(items[i]); });
    var sx = null, dx = 0;
    card.addEventListener('pointerdown', function(e){ if (e.target.closest('button')) return; sx = e.clientX; dx = 0; card.classList.add('drag'); card.setPointerCapture(e.pointerId); });
    card.addEventListener('pointermove', function(e){ if (sx===null) return; dx = e.clientX - sx; card.style.transform = 'translateX('+dx+'px) rotate('+(dx/40)+'deg)'; });
    function up(){ if (sx===null) return; sx = null; card.classList.remove('drag');
      if (Math.abs(dx) > 60) goTo(dx < 0 ? i+1 : i-1, dx < 0 ? -1 : 1); else card.style.transform = ''; }
    card.addEventListener('pointerup', up); card.addEventListener('pointercancel', up);
    root.querySelectorAll('.pin,.plabel').forEach(function(p){ p.addEventListener('click', function(){
      var id = p.getAttribute('data-id'); var j = -1; items.forEach(function(it, k){ if (it.pin===id && j<0) j = k; });
      if (j >= 0 && j !== i) goTo(j, j > i ? -1 : 1);
    }); });
    document.addEventListener('keydown', function(e){ if (!document.getElementById(slotId).classList.contains('active') || root.offsetParent===null) return; if (e.key==='ArrowLeft') goTo(i+1, -1); if (e.key==='ArrowRight') goTo(i-1, 1); });
    fill(); window.addEventListener('resize', function(){ fill(); }); setTimeout(fill, 350);
    return { index: function(){ return i; }, jump: function(j){ i = (j + items.length) % items.length; fill(); }, refocus: fill,
             setItems: function(list, start){ items = list.slice(); i = start || 0; fill(); } };
  }
  var baseCfg = { items: D.items, label: function(i, n){ return ar(i+1) + ' من ' + ar(n) + ' · الأقرب أولاً'; }, onFocus: function(it, focusPin){ focusPin(it.pin, 1.5); } };

  // ---- ملء الشاشة (تُستخدم في ب و ج)
  function initFeed(root){
    var feed = root.querySelector('[data-feed]'), hint = root.querySelector('[data-uph]');
    feed.addEventListener('scroll', function(){ hint.classList.toggle('gone', feed.scrollTop > 40); }, {passive:true});
    return { index: function(){ return Math.round(feed.scrollTop / (feed.clientHeight || 1)); }, show: function(j){ feed.scrollTop = j * feed.clientHeight; hint.classList.toggle('gone', j > 0); } };
  }

  var a = document.querySelector('[data-concept=a]'); if (a) makeDeck(a, 's-a', baseCfg);
  var b = document.querySelector('[data-concept=b]'); if (b) initFeed(b);

  // ---- ج · المفتاح: شكلان على الصف نفسه، والموضع محفوظ، والاختيار يُتذكّر
  var c = document.querySelector('[data-concept=c]');
  if (c) {
    var cardMode = c.querySelector('[data-mode=card]'), fullMode = c.querySelector('[data-mode=full]');
    var deck = makeDeck(cardMode, 's-c', baseCfg), feed = initFeed(fullMode);
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

  // ---- د · المناطق الحرارية: بطاقات المناطق أولاً، ثم ما بداخل المنطقة؛ ومشاركات جديدة تصل حيّاً
  var d = document.querySelector('[data-concept=d]');
  if (d) {
    var map = d.querySelector('.map'), zones = D.zones.map(function(z){ return Object.assign({}, z); }), level = 'zones', curZone = null;
    function total(){ return zones.reduce(function(s, z){ return s + z.n; }, 0); }
    function zoneCard(z){ return { pin: null, img: z.img, logo: null, kind: 'منطقة نشطة', who: z.name, t: ar(z.n) + ' مشاركة الآن', d: ar(z.offers) + ' عروض · ' + ar(z.events) + ' فعاليات · لحظات وسوق', dist: z.dist, act: 'استعرض', zone: z }; }
    function zoneCards(){ return zones.slice().sort(function(x, y){ return y.n - x.n; }).map(zoneCard); }
    var hdeck = makeDeck(d, 's-d', {
      items: zoneCards(),
      label: function(i, n, it){ return level === 'zones' ? '<span class="live"><i></i>مباشر</span> · ' + ar(zones.length) + ' مناطق نشطة · ' + ar(total()) + ' مشاركة الآن' : it.zoneName + ' · ' + ar(i+1) + ' من ' + ar(n) + ' · ' + ar(curZone.n) + ' مشاركة'; },
      onFocus: function(it, focusPin, camTo){
        if (level === 'zones') { camTo([it.zone.x, it.zone.y], 1.08, 0.40); d.querySelectorAll('[data-blob],[data-zl]').forEach(function(e){ e.classList.toggle('hi', (e.getAttribute('data-blob') || e.getAttribute('data-zl')) === it.zone.id); }); }
        else focusPin(it.pin, 2.1);
      },
      onAct: function(it){ if (level === 'zones') enter(it.zone); }
    });
    function enter(z){
      level = 'items'; curZone = z; map.classList.add('in');
      d.querySelectorAll('.pin,.plabel').forEach(function(p){ p.classList.toggle('show', p.getAttribute('data-zone') === z.id); });
      d.querySelector('[data-back]').hidden = false;
      var list = D.items.filter(function(it){ return it.zone === z.id; }).map(function(it){ return Object.assign({ zoneName: z.name }, it); });
      hdeck.setItems(list, 0);
    }
    function leave(){
      level = 'zones'; map.classList.remove('in'); d.querySelector('[data-back]').hidden = true;
      var keep = curZone ? curZone.id : null; var cards = zoneCards(); var start = 0; cards.forEach(function(c, k){ if (c.zone.id === keep) start = k; });
      hdeck.setItems(cards, start);
    }
    d.querySelector('[data-back]').addEventListener('click', leave);
    d.querySelectorAll('[data-zl]').forEach(function(b){ b.addEventListener('click', function(){ var z = zones.filter(function(x){ return x.id === b.getAttribute('data-zl'); })[0]; if (level === 'zones') { var cards = zoneCards(); var k = 0; cards.forEach(function(c, q){ if (c.zone.id === z.id) k = q; }); hdeck.jump(k); } else enter(z); }); });
    // بث حي: مشاركة جديدة كل ثانيتين في منطقة بحسب نشاطها، تظهر كنقطة تنبض ويكبر لهيب المنطقة ويُحدَّث العدّاد والبطاقة
    var dotsBox = d.querySelector('[data-hdots]');
    setInterval(function(){
      var r = Math.random() * total(), z = zones[0]; for (var q = 0; q < zones.length; q++) { r -= zones[q].n; if (r <= 0) { z = zones[q]; break; } }
      z.n += 1;
      var dot = document.createElement('i'); dot.className = 'hd pop';
      var g = function(){ return (Math.random() + Math.random() + Math.random() - 1.5); };
      dot.style.right = (z.x + g() * 9) + '%'; dot.style.top = (z.y + g() * 7) + '%';
      dotsBox.appendChild(dot); if (dotsBox.children.length > 220) dotsBox.removeChild(dotsBox.firstChild);
      d.querySelector('[data-zn="' + z.id + '"]').textContent = ar(z.n);
      d.querySelector('[data-blob="' + z.id + '"]').style.setProperty('--s', (90 + z.n * 1.6) + 'px');
      if (level === 'zones') { var cards = zoneCards(); hdeck.setItems(cards, Math.min(hdeck.index(), cards.length - 1)); }
      else if (curZone === z) hdeck.refocus();
    }, 2000);
  }
})();
'''

if __name__ == '__main__':
    import base64
    # الصور كقاموس داخل الصفحة حتى تبدّل البطاقة صورتها دون لمس الرموز
    assets = {}
    for key in {it['img'] for it in ITEMS} | {it['logo'] for it in ITEMS} | {z['img'] for z in ZONES}:
        for ext, mime in (('.jpg', 'image/jpeg'), ('.png', 'image/png')):
            p = root / 'img' / (key + ext)
            if p.exists(): assets[key] = 'data:' + mime + ';base64,' + base64.b64encode(p.read_bytes()).decode()
    js = 'var ASSETS = ' + json.dumps(assets) + ';\n' + JS.replace('__DATA__', json.dumps(DATA, ensure_ascii=False))
    page = '''<title>نظام واحد</title>
<meta name="description" content="نظام «واحد» لخريطة ناس لايف: شيء واحد في المرة، إيماءة واحدة، زر واحد. بطاقة مدمجة صغيرة على الخريطة، شاشة تُسحب للأعلى، مفتاح يجمعهما، ومناطق حرارية حين تكثر المشاركات.">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Rubik:wght@400;500;600;700&family=Baloo+Bhaijaan+2:wght@600;700;800&display=swap">
<style>__CSS__</style>
<div class="wrap">
  <header>
    <h1>نظام «واحد»</h1>
    <p class="sub">أبسط ما يمكن أن يكون عليه التطبيق: شيء واحد في المرة، إيماءة واحدة يعرفها كل من أمسك هاتفاً، زر واحد، ولا شيء آخر على الشاشة سوى البحث. لا ورقة ولا رقائق ولا أقسام ولا تخصيص ولا مرشّحات ولا تبويبات؛ الترتيب واحد ذكي: الأقرب أولاً، مع تقديم ما ينتهي قريباً وما نُشر للتو. البطاقة المدمجة صارت صغيرة أفقية فتأخذ أقل من خُمس الشاشة وتبقى الخريطة واسعة. وحين تكثر المشاركات في منطقة ما، يتحوّل الصف تلقائياً إلى «مناطق حرارية»: بطاقة لكل منطقة ساخنة، ثم ما بداخلها.</p>
    <div class="gone-list">
      <div><i>×</i><span>الورقة السفلية</span></div><div><i>×</i><span>صف الرقائق</span></div><div><i>×</i><span>الأقسام الـ12</span></div>
      <div><i>×</i><span>شاشة التخصيص ووضع التحرير</span></div><div><i>×</i><span>تبويبات الملف والدائرة من الرئيسية</span></div><div><i>×</i><span>مفاتيح الطبقات</span></div>
      <div class="keep"><i>✓</i><span>البحث</span></div><div class="keep"><i>✓</i><span>الخريطة أو الصورة</span></div><div class="keep"><i>✓</i><span>بطاقة واحدة وزر واحد</span></div>
    </div>
    <div class="rowh">
      <div class="seg" id="seg" role="tablist" aria-label="الأشكال">
        <button class="on" data-go="a" role="tab"><i>أ</i>بطاقة مدمجة</button>
        <button data-go="b" role="tab"><i>ب</i>شاشة · سحب للأعلى</button>
        <button data-go="c" role="tab"><i>ج</i>الاثنان بمفتاح</button>
        <button data-go="d" role="tab"><i>د</i>مناطق حرارية · حيّ</button>
      </div>
    </div>
  </header>

  <div class="phones">
    <section class="slot active" id="s-a">
      <h2><span>أ</span>بطاقة مدمجة <small>· صغيرة أفقية، والخريطة تأخذ الشاشة</small></h2>
      <div class="phone"><div class="screen" data-concept="a">__A__</div></div>
      <p class="note">بطاقة أفقية بارتفاع ٨٤ بكسل: صورة صغيرة وسطران وزر. مع شريط العدّاد تأخذ أقل من خُمس الشاشة، فالخريطة واسعة والدبّوس المختار يظهر في وسطها. اسحب البطاقة يميناً أو يساراً فتأتي التالية وتنزلق الخريطة إلى دبّوسها. المس أي دبّوس فتقفز إليه البطاقة. لا شيء آخر.</p>
    </section>
    <section class="slot" id="s-b">
      <h2><span>ب</span>شاشة <small>· كل شيء بملء الشاشة، والخريطة بوصلة صغيرة</small></h2>
      <div class="phone"><div class="screen" data-concept="b">__B__</div></div>
      <p class="note">الإيماءة الأكثر رسوخاً في أيدي الناس: اسحب للأعلى. كل عنصر يملأ الشاشة بصورته، وبوصلة صغيرة في الزاوية تدلّ على اتجاهه عنك ومسافته، وزر واحد. الخريطة الكاملة تُفتح من البوصلة أو من تبويبها عند الحاجة فقط.</p>
    </section>
    <section class="slot" id="s-c">
      <h2><span>ج</span>الاثنان بمفتاح <small>· المستخدم يختار الإيماءة، والتطبيق يتذكّر</small></h2>
      <div class="phone"><div class="screen" data-concept="c">__C__</div></div>
      <p class="note">الشكلان على الصف نفسه، ومفتاح صغير برمزين في شريط البحث يبدّل بينهما. الموضع محفوظ عند التبديل، والاختيار يُحفظ في الحساب، والافتراضي للجميع «بطاقة». جرّب: اسحب بطاقتين ثم بدّل المفتاح.</p>
    </section>
    <section class="slot" id="s-d">
      <h2><span>د</span>مناطق حرارية <small>· مثال حيّ حين تكثر المشاركات</small></h2>
      <div class="phone"><div class="screen" data-concept="d">__D__</div></div>
      <p class="note">حين يتجاوز ما حولك حداً (مثلاً ٤٠ مشاركة في مجال الرؤية) لا نعرض دبابيس متراكبة، بل طبقة حرارة: بقع تكبر مع الكثافة ونقاط للمشاركات وكبسولة لكل منطقة بعددها. البطاقات تصير بطاقات مناطق مرتّبة بالأسخن: «الروضة · ٦٤ مشاركة الآن · ١٢ عروض · ٣ فعاليات»، وزرها «استعرض» يقرّب الخريطة إلى المنطقة ويبدّل الصف إلى ما بداخلها بالبطاقة الصغيرة نفسها، وزر الرجوع يعيد المناطق. المثال حيّ: كل ثانيتين تصل مشاركة جديدة في منطقة بحسب نشاطها، فتنبض نقطة ويكبر لهيبها ويتحدّث العدّاد والبطاقة أمامك.</p>
    </section>
  </div>

  <div class="tblwrap"><table class="cmp">
    <thead><tr><th>المعيار</th><th>أ · بطاقة مدمجة</th><th>ب · شاشة</th><th>ج · الاثنان بمفتاح</th><th>د · مناطق حرارية</th></tr></thead>
    <tbody>
      <tr><th>الإيماءة</th><td>سحب جانبي (أو لمس دبّوس)</td><td>سحب للأعلى</td><td>ما يختاره المستخدم</td><td>السحب الجانبي نفسه + «استعرض» و«رجوع»</td></tr>
      <tr><th>ما على الشاشة</th><td>خريطة، بطاقة صغيرة، عدّاد، بحث</td><td>صورة، بوصلة، بطاقة، بحث</td><td>الشكل المختار + مفتاح</td><td>خريطة حرارية، كبسولات المناطق، بطاقة صغيرة</td></tr>
      <tr><th>نصيب الخريطة من الشاشة</th><td><b>نحو ٨٠٪</b></td><td>بوصلة صغيرة</td><td>كما أ أو ب</td><td>نحو ٨٠٪</td></tr>
      <tr><th>متى يظهر</th><td>دائماً</td><td>باختيار المستخدم</td><td>باختيار المستخدم</td><td>تلقائياً عند الكثافة، ويختفي تحتها</td></tr>
      <tr><th>العروض والوظائف والسوق</th><td colspan="4">بطاقات متساوية في الصف نفسه بالترتيب الذكي، وفي «د» تُعدّ داخل بطاقة المنطقة</td></tr>
      <tr><th>ما يحتاجه الخادم</th><td colspan="3">مسار «الصف» بحدّ ٣٠ عنصراً من كل الأنواع (+ حفظ الاختيار في ج)</td><td>مسار «المناطق»: تجميع شبكي بالعدد والأنواع لحدود الخريطة (استعلام واحد)</td></tr>
      <tr><th>أثر التنفيذ</th><td>صغير</td><td>صغير</td><td>صغير + يومان</td><td>متوسط: طبقة حرارة ومسار تجميع ومستويان للصف</td></tr>
    </tbody>
  </table></div>

  <div class="reco">
    <b>توصيتي</b>
    <span>«أ» بالبطاقة المدمجة الصغيرة أساساً للجميع، و«د» يعمل فوقه تلقائياً لا كخيار: حين يزدحم مجال الرؤية تظهر المناطق أولاً، وحين يقترب المستخدم أو يقلّ المحتوى تعود البطاقات مباشرة. بهذا يبقى للمستخدم إيماءة واحدة وبطاقة واحدة في الحالتين، وتصبح الكثافة ميزة تُرى لا فوضى دبابيس. و«ج» إن أردت تخيير الناس بين الإيماءتين بالشروط التي ذكرتها.</span>
  </div>
</div>

<script>__JS__</script>
'''
    page = page.replace('__CSS__', CSS + CSS3 + CSS4).replace('__A__', A()).replace('__B__', B()).replace('__C__', C()).replace('__D__', D()).replace('__JS__', js)
    icons_path = root / 'icons.json'
    icons = json.loads(icons_path.read_text(encoding='utf-8'))
    icons.update(ICONS4)
    icons_path.write_text(json.dumps(icons, ensure_ascii=False, indent=1), encoding='utf-8')
    (root / 'template_one.html').write_text(page, encoding='utf-8')
