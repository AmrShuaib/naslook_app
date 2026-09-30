# يولّد template_calm.html: أربعة أنظمة مبتكرة بديلة للورقة السفلية، كلٌّ مبني على فكرة واحدة هادئة:
# أ «العدسة» (المسافة هي التحكم الوحيد)، ب «خط الوقت» (الزمن هو المحور)، ج «الأحياء» (الجغرافيا هي القائمة)،
# د «سطر واحد» (جملة واحدة في المرة). يعيد استخدام أيقونات make_main.py وخريطته وبياناته.
# البناء: python3 make_calm.py && python3 build.py template_calm.html > out.html
import json, pathlib
from make_main import (CSS, MAP, ICONS, MOMENTS, PLACES, OFFERS, PRODUCTS, CIRCLES_MINE, CIRCLES_DISC,
                       moment_cards, place_rows, offer_cards, product_cards, circle_rows, nav_pill, screen, svg)
root = pathlib.Path(__file__).parent

ICONS3 = {
 'i-x': svg('<path d="M6 6l12 12"/><path d="M18 6L6 18"/>', 18),
 'i-back': svg('<path d="M9 6l6 6-6 6"/>', 18),
 'i-pause': svg('<rect x="6" y="5" width="4" height="14" rx="1"/><rect x="14" y="5" width="4" height="14" rx="1"/>', 14, stroke=False),
 'i-playx': svg('<path d="M8 5.5v13a1 1 0 0 0 1.5.86l11-6.5a1 1 0 0 0 0-1.72l-11-6.5A1 1 0 0 0 8 5.5z"/>', 14, stroke=False),
 'i-ring': svg('<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="2.5" fill="currentColor"/>', 16),
}
ICONS.update(ICONS3)

# ---------- دبابيس بمعرّفات (لتمييزها من JS) ----------
PIN_DEFS = [('p16', 78, 30, 'i-cam', 'm1', 'فهد', 'الكورنيش'), ('p42', 40, 58, '', 'm2', 'سارة', 'الروضة'), ('p274', 30, 79, 'i-play', 'm3', 'نورة', 'التحلية'),
            ('p63', 62, 49, 'i-mic', 'm4', 'عبدالله', 'الحمراء'), ('avatar', 52, 66, '', 'm5', 'أنت', 'الروضة')]
LABEL_DEFS = [('overdose', 'أوفردوز', 42, 68, 'b1', 'الروضة'), ('halfmillion', 'هاف مليون', 26, 36, 'b2', 'الشاطئ'), ('3brews', 'ثري بروز', 66, 60, 'b3', 'الحمراء'), ('rawnah', 'رونة', 20, 50, 'b4', 'التحلية')]
ME = (56, 44)
def pins_html():
    out = []
    for img, x, y, kind, pid, _, _ in PIN_DEFS:
        k = f'<i class="k">@@{kind}@@</i>' if kind else ''
        out.append(f'<span class="pin" data-id="{pid}" style="right:{x}%;top:{y}%"><img src="@@{img}@@" alt="">{k}</span>')
    for img, name, x, y, pid, _ in LABEL_DEFS:
        out.append(f'<span class="plabel" data-id="{pid}" style="right:{x}%;top:{y}%"><img src="@@{img}@@" alt="">{name}</span>')
    out.append(f'<span class="me" data-id="me" style="right:{ME[0]}%;top:{ME[1]}%"></span>')
    return '<div class="pins">' + ''.join(out) + '</div>'
PINS = pins_html()
SEARCH = '<div class="top"><div class="search glass">@@i-search@@<span style="flex-grow:1">ابحث في جدة</span><span class="avm"><img src="@@avatar@@" alt=""></span></div></div>'

# ======================================================================
# أ · العدسة: دائرة حول موقعك؛ نصف قطرها هو التحكم الوحيد، وعلى حافتها عدّادات ما بداخلها
# ======================================================================
def A():
    focus = {
      'people': ('أشخاص ولحظات', f'<div class="grid3">{moment_cards(n=5)}</div>'),
      'circles': ('دوائر', circle_rows(CIRCLES_DISC[:3] + CIRCLES_MINE[:1], '<button class="btn sm soft">افتح</button>')),
      'offers': ('عروض', f'<div class="hs" style="flex-wrap:wrap;gap:10px">{offer_cards()}</div>'),
      'market': ('سوق', f'<div class="grid2">{product_cards(4)}</div>'),
    }
    panels = ''.join(f'<div class="focus" data-focus="{k}" hidden><div class="fhead"><b>{t}<small data-fsub></small></b><button class="ib" data-fclose aria-label="إغلاق">@@i-x@@</button></div><div class="scroll pad">{body}</div></div>' for k, (t, body) in focus.items())
    home = f'''<div class="map lensmap">{MAP}{PINS}{SEARCH}
      <div class="lens" style="right:{ME[0]}%;top:{ME[1]}%"></div>
      <button class="rim" data-rim="people" data-ang="300">@@i-me@@<b>0</b></button>
      <button class="rim" data-rim="circles" data-ang="30">@@i-groups@@<b>0</b></button>
      <button class="rim" data-rim="offers" data-ang="150">@@i-tag@@<b>0</b></button>
      <button class="rim" data-rim="market" data-ang="210">@@i-bag@@<b>0</b></button>
      <div class="lensbar"><span class="sum" data-sum></span>
        <div class="seg3 rad"><button data-r="86">٥٠٠ م</button><button class="on" data-r="150">١ كم</button><button data-r="250">٣ كم</button></div></div>
      {panels}</div>'''
    return screen('home', home, nav_pill('home'), 'abs')

# ======================================================================
# ب · خط الوقت: شريط زمني واحد أسفل الخريطة؛ كل شيء حولك حدث له وقت
# ======================================================================
TIMELINE = [
  {'pos': 4, 'pin': 'm1', 'kind': 'لحظة', 'img': 'p16', 't': 'فهد نشر لحظة على الكورنيش', 'd': 'قبل ١٢ دقيقة · ٢٤ إعجاباً', 'act': 'شاهد'},
  {'pos': 18, 'pin': 'm4', 'kind': 'صوت', 'img': 'p63', 't': 'عبدالله: تسجيل صوتي من الحمراء', 'd': 'قبل ساعتين · ٠:٤١', 'act': 'استمع'},
  {'pos': 36, 'pin': 'b1', 'kind': 'عرض', 'img': 'overdose', 't': 'خصم ٢٠٪ على اللاتيه ينتهي', 'd': 'أوفردوز · بعد ساعتين · ٦٥٠ م', 'act': 'استخدم'},
  {'pos': 58, 'pin': 'b2', 'kind': 'فعالية', 'img': 'halfmillion', 't': 'بازار الحي في حديقة الشاطئ', 'd': 'اليوم ٥ م · ١٢ طاولة · ٩٠٠ م', 'act': 'تذكرة'},
  {'pos': 76, 'pin': 'b3', 'kind': 'وظيفة', 'img': '3brews', 't': 'ثري بروز يوظّف باريستا', 'd': 'مقابلات اليوم ٧ م · يطابق ملفك ٨٧٪', 'act': 'قدّم'},
  {'pos': 94, 'pin': 'b4', 'kind': 'عرض', 'img': 'rawnah', 't': 'قهوة الصباح بـ ٩ ر.س', 'd': 'رونة · غداً حتى ١١ ص', 'act': 'ذكّرني'},
]
def B():
    dots = ''.join(f'<i class="dot" style="right:{it["pos"]}%" data-i="{i}"></i>' for i, it in enumerate(TIMELINE))
    home = f'''<div class="map">{MAP}{PINS}{SEARCH}
      <div class="tcard" data-tcard><img src="@@p16@@" alt="" data-timg><div class="b"><span class="k" data-tkind>لحظة</span><span class="t" data-tt></span><span class="d" data-td></span></div><button class="btn sm soft" data-tact>شاهد</button></div>
      <div class="tstrip" data-tstrip>
        <div class="ticks"><span>الآن</span><span>بعد ساعة</span><span>المساء</span><span>الليلة</span><span>غداً</span></div>
        <div class="line">{dots}<i class="handle" data-handle></i></div>
      </div></div>'''
    return screen('home', home, nav_pill('home'), 'abs')

# ======================================================================
# ج · الأحياء: الخريطة بلا دبابيس؛ الحي هو القائمة، ولمسه يقرّب ويفتح رزمة بطاقاته
# ======================================================================
DISTRICTS = [
  {'id': 'shati', 'name': 'الشاطئ', 'x': 32, 'y': 33, 'n': 12, 'imgs': ['p16', 'halfmillion'], 'cards': [
      ('p16', 'لحظة', 'فهد على الكورنيش', 'قبل ١٢ د · ٢٤ إعجاباً'), ('halfmillion', 'عرض', 'الفنجان السادس مجاناً', 'هاف مليون · للأعضاء'), ('p42', 'فعالية', 'بازار الحي الجمعة', 'حديقة الشاطئ · ٥ م')]},
  {'id': 'hamra', 'name': 'الحمراء', 'x': 62, 'y': 52, 'n': 8, 'imgs': ['p63', '3brews'], 'cards': [
      ('p63', 'صوت', 'عبدالله: تسجيل من الحمراء', 'قبل ساعتين · ٠:٤١'), ('3brews', 'وظيفة', 'ثري بروز يوظّف باريستا', 'دوام جزئي · ٤٬٥٠٠ ر.س'), ('p250', 'سوق', 'كاميرا فوجي X-T20', '2,650 ر.س · ٢ كم')]},
  {'id': 'rawda', 'name': 'الروضة', 'x': 44, 'y': 66, 'n': 15, 'imgs': ['overdose', 'p42'], 'cards': [
      ('overdose', 'عرض', 'خصم ٢٠٪ على اللاتيه', 'أوفردوز · حتى الليلة'), ('p42', 'لحظة', 'سارة في الروضة', 'قبل ٢٥ د'), ('avatar', 'دائرة', 'جيران الروضة', '١٢٤ عضواً · ٣ منشورات جديدة')]},
  {'id': 'tahlia', 'name': 'التحلية', 'x': 26, 'y': 80, 'n': 6, 'imgs': ['p274', 'rawnah'], 'cards': [
      ('p274', 'فيديو', 'نورة في التحلية', 'قبل ساعة · ٠:٠٩'), ('rawnah', 'عرض', 'قهوة الصباح بـ ٩ ر.س', 'رونة · حتى ١١ ص'), ('p119', 'سوق', 'ماك بوك إير M1', '2,900 ر.س')]},
]
def C():
    def faces(d): return ''.join(f'<img src="@@{i}@@" alt="">' for i in d['imgs'])
    pills = ''.join(f'<button class="dpill" data-d="{d["id"]}" style="right:{d["x"]}%;top:{d["y"]}%"><span class="st">{faces(d)}</span>{d["name"]}<b>{d["n"]}</b></button>' for d in DISTRICTS)
    stacks = ''.join(f'''<div class="dstack" data-stack="{d["id"]}" hidden><div class="dhead"><button class="ib" data-dback aria-label="رجوع">@@i-back@@</button><b>{d["name"]}<small>{d["n"]} الآن · الأقرب أولاً</small></b></div>
        <div class="cards">{''.join(f'<button class="scard" data-card><img src="@@{img}@@" alt=""><div class="b"><span class="k">{k}</span><span class="t">{t}</span><span class="d">{s}</span></div></button>' for img, k, t, s in d["cards"])}</div>
        <span class="hint">المس البطاقة لتقليب التالية · ٣ من {d["n"]}</span></div>''' for d in DISTRICTS)
    home = f'''<div class="dwrap"><div class="map dmap">{MAP}{PINS}{pills}</div>{SEARCH}{stacks}</div>'''
    return screen('home', home, nav_pill('home'), 'abs')

# ======================================================================
# د · سطر واحد: الخريطة وجملة واحدة تتبدّل بهدوء؛ لمسها يفتحها، ولا شيء آخر على الشاشة
# ======================================================================
WHISPERS = [
  {'pin': 'b1', 'img': 'overdose', 'txt': 'عرض أوفردوز على اللاتيه ينتهي الليلة، وهو على بعد ٦٥٠ م', 'title': 'خصم ٢٠٪ على اللاتيه', 'sub': 'أوفردوز · الروضة · للأعضاء · ينتهي بعد ساعتين', 'act': 'استخدم العرض'},
  {'pin': 'm1', 'img': 'p16', 'txt': 'فهد نشر لحظة على الكورنيش قبل ١٢ دقيقة', 'title': 'لحظة فهد على الكورنيش', 'sub': 'صورة · ٢٤ إعجاباً · ٣ تعليقات', 'act': 'شاهد اللحظة'},
  {'pin': 'b3', 'img': '3brews', 'txt': 'ثري بروز يبحث عن باريستا، وملفك يطابق ٨٧٪', 'title': 'عرض وظيفي: باريستا', 'sub': 'دوام جزئي · الحمراء · ٤٬٥٠٠ ر.س · مقابلات اليوم', 'act': 'قدّم الآن'},
  {'pin': 'b2', 'img': 'halfmillion', 'txt': 'بازار الحي اليوم ٥ م في حديقة الشاطئ، ٣ من أصدقائك ذاهبون', 'title': 'بازار الحي', 'sub': 'حديقة الشاطئ · ٥ م · ١٢ طاولة · سارة ونورة وريان', 'act': 'احجز تذكرة'},
  {'pin': 'm4', 'img': 'p63', 'txt': 'عبدالله ترك تسجيلاً صوتياً من الحمراء', 'title': 'تسجيل صوتي · ٠:٤١', 'sub': 'عبدالله · الحمراء · قبل ساعتين', 'act': 'استمع'},
]
def D():
    home = f'''<div class="map">{MAP}{PINS}{SEARCH}
      <div class="wcard" data-wcard hidden><img src="@@overdose@@" alt="" data-wimg><div class="b"><span class="t" data-wtitle></span><span class="d" data-wsub></span><div class="acts"><button class="btn sm" data-wact></button><button class="btn sm ghost" data-wnext>التالي</button></div></div></div>
      <button class="whisper" data-whisper><img src="@@overdose@@" alt="" data-wimg2><span class="txt" data-wtxt></span><span class="pp" data-wpause>@@i-pause@@</span><i class="prog" data-wprog></i></button>
      </div>'''
    return screen('home', home, nav_pill('home'), 'abs')

CSS3 = r'''
.map .pins{position:absolute;inset:0;transition:opacity .35s}
.map .pin,.map .plabel,.map .me{transition:opacity .3s,transform .3s}
.map .pin.dim,.map .plabel.dim{opacity:.28}
.map .pin.hi img{box-shadow:0 0 0 3px var(--a),0 2px 8px rgba(0,0,0,.28)}
.map .plabel.hi img{box-shadow:0 0 0 2.5px var(--a),0 1px 4px rgba(0,0,0,.28)}
.map .pin.hi,.map .plabel.hi{z-index:3}
@keyframes pulse{0%{box-shadow:0 0 0 0 rgba(10,110,120,.55)}100%{box-shadow:0 0 0 16px rgba(10,110,120,0)}}
.map .pin.pulse img,.map .plabel.pulse img{animation:pulse 1.6s ease-out infinite}
.avm img{width:28px;height:28px;border-radius:999px;object-fit:cover}
.grid2{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px;padding:0 14px;flex:none}
.grid3{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px;padding:0 14px;flex:none}
.grid3 .mcard{width:auto}
/* أ · العدسة */
.lens{position:absolute;width:calc(var(--r)*2);height:calc(var(--r)*2);border-radius:999px;transform:translate(50%,-50%);border:1.5px solid rgba(10,110,120,.55);box-shadow:0 0 0 1400px rgba(255,255,255,.62),inset 0 0 0 1px rgba(255,255,255,.6);transition:width .35s ease,height .35s ease;pointer-events:none;--r:150px}
.rim{position:absolute;transform:translate(50%,-50%);height:30px;padding:0 9px 0 7px;border-radius:999px;border:0;background:#fff;color:#111;box-shadow:0 3px 10px rgba(0,0,0,.16);display:inline-flex;align-items:center;gap:5px;font:600 12px var(--font-body);cursor:pointer;transition:right .35s ease,top .35s ease;z-index:4}
.rim svg{width:14px;height:14px;color:var(--a)}
.rim b{font-weight:700;color:var(--a);font-variant-numeric:tabular-nums}
.lensbar{position:absolute;right:14px;left:14px;bottom:92px;display:flex;flex-direction:column;gap:8px;align-items:stretch}
.lensbar .sum{align-self:center;font-size:12.5px;color:#374151;background:rgba(255,255,255,.96);padding:6px 12px;border-radius:999px;box-shadow:0 2px 8px rgba(0,0,0,.12);font-weight:500}
.seg3.rad{background:rgba(255,255,255,.96);box-shadow:0 4px 14px rgba(0,0,0,.14)}
.seg3.rad button.on{background:var(--a)}
.focus{position:absolute;inset:0;background:#fff;display:flex;flex-direction:column;z-index:6}
.fhead{display:flex;align-items:center;justify-content:space-between;padding:10px 14px 6px;flex:none}
.fhead b{font:800 20px var(--font-display);display:flex;flex-direction:column;gap:0}
.fhead small{font:500 12px var(--font-body);color:#6B7280}
/* ب · خط الوقت */
.tcard{position:absolute;right:14px;left:14px;bottom:176px;display:flex;align-items:center;gap:10px;background:rgba(255,255,255,.97);border-radius:16px;padding:8px 10px;box-shadow:0 8px 24px rgba(0,0,0,.16)}
.tcard img{width:48px;height:48px;border-radius:12px;object-fit:cover}
.tcard .b{flex-grow:1;min-width:0;display:flex;flex-direction:column;gap:1px}
.tcard .k{font-size:10.5px;font-weight:700;color:var(--a);text-transform:uppercase}
.tcard .t{font-size:13.5px;font-weight:700;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.tcard .d{font-size:11.5px;color:#6B7280;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.tstrip{position:absolute;right:14px;left:14px;bottom:92px;background:rgba(255,255,255,.97);border-radius:18px;padding:10px 14px 14px;box-shadow:0 8px 24px rgba(0,0,0,.16);display:flex;flex-direction:column;gap:10px;touch-action:none;user-select:none;cursor:pointer}
.tstrip .ticks{display:flex;justify-content:space-between;font-size:10.5px;color:#9CA3AF;font-weight:600}
.tstrip .line{position:relative;height:22px}
.tstrip .line::before{content:"";position:absolute;right:0;left:0;top:10px;height:2px;background:#E5E7EB;border-radius:2px}
.tstrip .dot{position:absolute;top:6px;width:10px;height:10px;border-radius:999px;background:#fff;border:2.5px solid var(--a);transform:translate(50%,0);box-sizing:border-box;transition:transform .2s}
.tstrip .dot.on{transform:translate(50%,-2px) scale(1.5);background:var(--a)}
.tstrip .handle{position:absolute;top:-4px;width:30px;height:30px;border-radius:999px;background:var(--a);box-shadow:0 4px 12px rgba(10,110,120,.4);transform:translate(50%,0);right:4%;transition:right .18s ease;opacity:.28}
/* ج · الأحياء */
.dwrap{position:absolute;inset:0;overflow:hidden}
.dwrap .top{position:absolute;top:10px;right:0;left:0;display:flex;flex-direction:column;gap:8px;z-index:5}
.dmap{position:absolute;inset:0;transform-origin:var(--ox,50%) var(--oy,50%);transition:transform .5s cubic-bezier(.2,.8,.2,1)}
.dmap.zoom{transform:scale(1.75)}
.dmap .pins{opacity:0}
.dmap.zoom .pins{opacity:1}
.dmap.zoom .pin,.dmap.zoom .plabel,.dmap.zoom .me{transform:translate(50%,-50%) scale(.57)}
.dmap.zoom .dpill{opacity:0;pointer-events:none}
.dpill{position:absolute;transform:translate(50%,-50%);height:40px;padding:0 12px 0 8px;border-radius:999px;border:0;background:#fff;color:#111;box-shadow:0 6px 18px rgba(0,0,0,.16);display:inline-flex;align-items:center;gap:8px;font:700 13.5px var(--font-body);cursor:pointer;transition:opacity .25s}
.dpill .st{display:inline-flex}.dpill .st img{width:24px;height:24px;border-radius:999px;border:2px solid #fff;object-fit:cover;margin-left:-8px}.dpill .st img:first-child{margin-left:0}
.dpill b{font-weight:700;color:var(--a);font-variant-numeric:tabular-nums}
.dstack{position:absolute;right:0;left:0;bottom:84px;display:flex;flex-direction:column;gap:10px;padding:0 14px;z-index:4}
.dhead{display:flex;align-items:center;gap:10px}
.dhead .ib{background:#fff;box-shadow:0 3px 10px rgba(0,0,0,.16)}
.dhead b{font:800 19px var(--font-display);color:#111;text-shadow:0 0 6px #fff,0 0 12px #fff;display:flex;flex-direction:column}
.dhead small{font:500 12px var(--font-body);color:#374151}
.cards{position:relative;height:132px}
.scard{position:absolute;right:0;left:0;top:0;display:flex;align-items:center;gap:10px;background:#fff;border:0;border-radius:16px;padding:10px;box-shadow:0 8px 24px rgba(0,0,0,.16);text-align:right;font-family:var(--font-body);cursor:pointer;transition:transform .35s cubic-bezier(.2,.8,.2,1),opacity .35s}
.scard img{width:58px;height:58px;border-radius:14px;object-fit:cover}
.scard .b{flex-grow:1;min-width:0;display:flex;flex-direction:column;gap:2px}
.scard .k{font-size:10.5px;font-weight:700;color:var(--a)}.scard .t{font-size:14px;font-weight:700;color:#111}.scard .d{font-size:11.5px;color:#6B7280}
.scard[data-pos="0"]{transform:translateY(0) scale(1);z-index:3}
.scard[data-pos="1"]{transform:translateY(12px) scale(.95);z-index:2;opacity:.9}
.scard[data-pos="2"]{transform:translateY(24px) scale(.9);z-index:1;opacity:.75}
.scard.out{transform:translateY(-30px) scale(.9);opacity:0;z-index:0}
.dstack .hint{align-self:center;font-size:11px;color:#6B7280;background:rgba(255,255,255,.9);padding:3px 10px;border-radius:999px}
/* د · سطر واحد */
.whisper{position:absolute;right:14px;left:14px;bottom:92px;height:52px;border:0;border-radius:999px;background:rgba(255,255,255,.97);box-shadow:0 8px 24px rgba(0,0,0,.16);display:flex;align-items:center;gap:10px;padding:0 8px 0 14px;cursor:pointer;overflow:hidden;font-family:var(--font-body);text-align:right}
.whisper img{width:36px;height:36px;border-radius:999px;object-fit:cover;flex:none}
.whisper .txt{flex-grow:1;min-width:0;font-size:13px;font-weight:500;color:#111;line-height:1.35;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
.whisper .pp{width:26px;height:26px;border-radius:999px;background:#F2F2F7;color:#374151;display:inline-flex;align-items:center;justify-content:center;flex:none}
.whisper .prog{position:absolute;right:0;bottom:0;height:3px;width:0;background:var(--a);border-radius:2px;transition:width 4.4s linear}
.whisper .prog.run{width:100%}
.wdots{position:absolute;left:0;right:0;bottom:80px;display:flex;justify-content:center;gap:4px}
.wdots i{width:5px;height:5px;border-radius:999px;background:rgba(17,17,17,.25)}
.wdots i.on{background:var(--a)}
.wcard{position:absolute;right:14px;left:14px;bottom:156px;display:flex;gap:12px;background:#fff;border-radius:18px;padding:12px;box-shadow:0 10px 30px rgba(0,0,0,.18)}
.wcard img{width:70px;height:70px;border-radius:14px;object-fit:cover;flex:none}
.wcard .b{flex-grow:1;min-width:0;display:flex;flex-direction:column;gap:3px}
.wcard .t{font-size:15px;font-weight:800;color:#111}.wcard .d{font-size:12px;color:#6B7280;line-height:1.4}
.wcard .acts{display:flex;gap:6px;margin-top:6px}
/* صفحة */
.rules{border:1px solid var(--line);border-radius:14px;padding:12px 16px;display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:8px 18px;font-size:13.5px;line-height:1.6}
.rules div{display:flex;gap:8px;align-items:flex-start}
.rules i{flex:none;width:20px;height:20px;border-radius:999px;background:var(--a);color:#fff;display:inline-flex;align-items:center;justify-content:center;font-style:normal;font-size:11px;font-weight:700;margin-top:2px}
'''

DATA = {'pins': [[p[4], p[1], p[2]] for p in PIN_DEFS] + [[l[4], l[2], l[3]] for l in LABEL_DEFS], 'me': ME, 'timeline': TIMELINE, 'districts': [{'id': d['id'], 'x': d['x'], 'y': d['y']} for d in DISTRICTS], 'whispers': WHISPERS}

JS = r'''
(function(){
  var D = __DATA__;
  var slots = {a:'s-a', b:'s-b', c:'s-c', d:'s-d'};
  function go(id){
    Object.keys(slots).forEach(function(k){ document.getElementById(slots[k]).classList.toggle('active', k===id); });
    document.querySelectorAll('#seg button').forEach(function(b){ b.classList.toggle('on', b.getAttribute('data-go')===id); });
    if (window.innerWidth <= 1250) window.scrollTo({top:0, behavior:'smooth'});
    try { localStorage.setItem('nl-calm-concept', id); } catch(e){}
  }
  document.querySelectorAll('#seg button').forEach(function(b){ b.addEventListener('click', function(){ go(b.getAttribute('data-go')); }); });
  var saved = null; try { saved = localStorage.getItem('nl-calm-concept'); } catch(e){}
  if (saved && slots[saved]) go(saved);
  function ar(n){ return String(n).replace(/\d/g, function(d){ return '٠١٢٣٤٥٦٧٨٩'[+d]; }); }
  function setHi(root, ids, cls){ root.querySelectorAll('.pin,.plabel').forEach(function(p){ p.classList.toggle(cls||'hi', ids.indexOf(p.getAttribute('data-id'))>=0); }); }

  // ---- أ · العدسة
  (function(){
    var root = document.querySelector('[data-concept=a]'); if(!root) return;
    var map = root.querySelector('.map'), lens = root.querySelector('.lens');
    var kinds = {people:['m1','m2','m3','m4','m5'], circles:['b1','b2','b3','b4'], offers:['b1','b2','b4'], market:['m2','m4','m5']};
    var r = 150;
    function center(){ var w = map.clientWidth, h = map.clientHeight; return {x: w - w*D.me[0]/100, y: h*D.me[1]/100, w:w, h:h}; }
    function apply(){
      var c = center(); lens.style.setProperty('--r', r+'px');
      var inside = {};
      D.pins.forEach(function(p){ var x = c.w - c.w*p[1]/100, y = c.h*p[2]/100; var d = Math.hypot(x-c.x, y-c.y); inside[p[0]] = d <= r; });
      root.querySelectorAll('.pin,.plabel').forEach(function(p){ p.classList.toggle('dim', !inside[p.getAttribute('data-id')]); });
      var counts = {};
      Object.keys(kinds).forEach(function(k){ counts[k] = kinds[k].filter(function(id){ return inside[id]; }).length; });
      root.querySelectorAll('.rim').forEach(function(b){
        var k = b.getAttribute('data-rim'), a = (+b.getAttribute('data-ang')) * Math.PI/180;
        b.querySelector('b').textContent = ar(counts[k]);
        var x = c.x + r*Math.cos(a), y = c.y + r*Math.sin(a);
        b.style.right = (c.w - x) + 'px'; b.style.top = y + 'px';
      });
      var lbl = r<100 ? '٥٠٠ م' : r<200 ? '١ كم' : '٣ كم';
      root.querySelector('[data-sum]').textContent = 'ضمن '+lbl+': '+ar(counts.people)+' أشخاص · '+ar(counts.circles)+' دوائر · '+ar(counts.offers)+' عروض · '+ar(counts.market)+' في السوق';
      root.querySelectorAll('[data-fsub]').forEach(function(s){ s.textContent = 'ضمن '+lbl+' من موقعك'; });
    }
    root.querySelectorAll('[data-r]').forEach(function(b){ b.addEventListener('click', function(){ r = +b.getAttribute('data-r'); root.querySelectorAll('[data-r]').forEach(function(x){ x.classList.toggle('on', x===b); }); apply(); }); });
    root.querySelectorAll('.rim').forEach(function(b){ b.addEventListener('click', function(){ var k = b.getAttribute('data-rim'); root.querySelectorAll('[data-focus]').forEach(function(f){ f.hidden = f.getAttribute('data-focus')!==k; }); }); });
    root.querySelectorAll('[data-fclose]').forEach(function(b){ b.addEventListener('click', function(){ root.querySelectorAll('[data-focus]').forEach(function(f){ f.hidden = true; }); }); });
    apply(); window.addEventListener('resize', apply); setTimeout(apply, 300);
  })();

  // ---- ب · خط الوقت
  (function(){
    var root = document.querySelector('[data-concept=b]'); if(!root) return;
    var strip = root.querySelector('[data-tstrip]'), handle = root.querySelector('[data-handle]'), line = strip.querySelector('.line');
    var cur = -1;
    function show(i){
      if (i===cur) return; cur = i; var it = D.timeline[i];
      root.querySelector('[data-timg]').src = root.querySelector('[data-img="'+it.img+'"]') ? '' : root.querySelector('[data-timg]').src;
      root.querySelector('[data-tkind]').textContent = it.kind; root.querySelector('[data-tt]').textContent = it.t; root.querySelector('[data-td]').textContent = it.d; root.querySelector('[data-tact]').textContent = it.act;
      var src = imgs[it.img]; if (src) root.querySelector('[data-timg]').src = src;
      strip.querySelectorAll('.dot').forEach(function(d, j){ d.classList.toggle('on', j===i); });
      setHi(root, [it.pin]); handle.style.right = it.pos + '%';
    }
    var imgs = {};
    root.querySelectorAll('.pin img,.plabel img').forEach(function(im){ var id = im.parentNode.getAttribute('data-id'); imgs[id] = im.src; });
    // ربط معرّف الصورة باسم الملف عبر الدبابيس المعروفة
    var byImg = {p16:'m1', p63:'m4', overdose:'b1', halfmillion:'b2', '3brews':'b3', rawnah:'b4'};
    Object.keys(byImg).forEach(function(k){ imgs[k] = imgs[byImg[k]]; });
    function pick(clientX){
      var rc = line.getBoundingClientRect(); var pct = (rc.right - clientX) / rc.width * 100; pct = Math.max(0, Math.min(100, pct));
      var best = 0, bd = 1e9; D.timeline.forEach(function(it, i){ var d = Math.abs(it.pos - pct); if (d < bd) { bd = d; best = i; } });
      show(best);
    }
    var down = false;
    strip.addEventListener('pointerdown', function(e){ down = true; pick(e.clientX); });
    strip.addEventListener('pointermove', function(e){ if (down) pick(e.clientX); });
    window.addEventListener('pointerup', function(){ down = false; });
    strip.querySelectorAll('.dot').forEach(function(d){ d.addEventListener('click', function(e){ e.stopPropagation(); show(+d.getAttribute('data-i')); }); });
    show(0);
  })();

  // ---- ج · الأحياء
  (function(){
    var root = document.querySelector('[data-concept=c]'); if(!root) return;
    var map = root.querySelector('.dmap');
    function open(id){
      var d = D.districts.filter(function(x){ return x.id===id; })[0]; if(!d) return;
      map.style.setProperty('--ox', (100 - d.x) + '%'); map.style.setProperty('--oy', d.y + '%'); map.classList.add('zoom');
      root.querySelectorAll('[data-stack]').forEach(function(s){ s.hidden = s.getAttribute('data-stack')!==id; });
    }
    function close(){ map.classList.remove('zoom'); root.querySelectorAll('[data-stack]').forEach(function(s){ s.hidden = true; }); }
    root.querySelectorAll('.dpill').forEach(function(b){ b.addEventListener('click', function(){ open(b.getAttribute('data-d')); }); });
    root.querySelectorAll('[data-dback]').forEach(function(b){ b.addEventListener('click', close); });
    root.querySelectorAll('.cards').forEach(function(c){
      var cards = Array.prototype.slice.call(c.querySelectorAll('.scard'));
      function layout(){ cards.forEach(function(x, i){ x.setAttribute('data-pos', i); }); }
      layout();
      cards.forEach(function(x){ x.addEventListener('click', function(){
        if (x !== cards[0]) return;
        x.classList.add('out');
        setTimeout(function(){ cards.push(cards.shift()); x.classList.remove('out'); layout(); }, 300);
      }); });
    });
  })();

  // ---- د · سطر واحد
  (function(){
    var root = document.querySelector('[data-concept=d]'); if(!root) return;
    var i = 0, timer = null, paused = false;
    var imgs = {}; root.querySelectorAll('.pin img,.plabel img').forEach(function(im){ imgs[im.parentNode.getAttribute('data-id')] = im.src; });
    var prog = root.querySelector('[data-wprog]'), card = root.querySelector('[data-wcard]');
    function render(){
      var w = D.whispers[i];
      root.querySelector('[data-wtxt]').textContent = w.txt;
      root.querySelector('[data-wimg2]').src = imgs[w.pin] || root.querySelector('[data-wimg2]').src;
      root.querySelector('[data-wimg]').src = imgs[w.pin] || root.querySelector('[data-wimg]').src;
      root.querySelector('[data-wtitle]').textContent = w.title; root.querySelector('[data-wsub]').textContent = w.sub; root.querySelector('[data-wact]').textContent = w.act;
      setHi(root, [w.pin], 'pulse');
      prog.classList.remove('run'); void prog.offsetWidth; if (!paused) prog.classList.add('run');
    }
    function next(){ i = (i+1) % D.whispers.length; render(); }
    function start(){ stop(); if (!paused) timer = setInterval(next, 4500); }
    function stop(){ if (timer) clearInterval(timer); timer = null; }
    root.querySelector('[data-whisper]').addEventListener('click', function(e){
      if (e.target.closest('[data-wpause]')) { paused = !paused; root.querySelector('[data-wpause]').innerHTML = paused ? __PLAY__ : __PAUSE__; if (paused) { stop(); prog.classList.remove('run'); } else { render(); start(); } return; }
      card.hidden = !card.hidden; if (!card.hidden) { paused = true; stop(); prog.classList.remove('run'); root.querySelector('[data-wpause]').innerHTML = __PLAY__; }
    });
    root.querySelector('[data-wnext]').addEventListener('click', function(){ next(); });
    render(); start();
  })();
})();
'''
JS = JS.replace('__DATA__', json.dumps(DATA, ensure_ascii=False)).replace('__PLAY__', json.dumps(ICONS['i-playx'])).replace('__PAUSE__', json.dumps(ICONS['i-pause']))

page = '''<title>أنظمة هادئة بديلة للورقة</title>
<meta name="description" content="أربعة أنظمة مبتكرة بديلة للورقة السفلية فوق خريطة ناس لايف: العدسة، خط الوقت، الأحياء، وسطر واحد. كلٌّ منها يبني الشاشة على فكرة واحدة.">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Rubik:wght@400;500;600;700&family=Baloo+Bhaijaan+2:wght@600;700;800&display=swap">
<style>__CSS__</style>
<div class="wrap">
  <header>
    <h1>أنظمة هادئة بديلة للورقة</h1>
    <p class="sub">أربعة أنظمة لا تقلّد الورقة ولا تقلّد التطبيقات المعروفة. كلٌّ منها يبني شاشة الخريطة على فكرة واحدة فقط، فلا رقائق ولا قوائم ولا سحب عمودي: في «العدسة» المسافة هي التحكم الوحيد، وفي «خط الوقت» الزمن هو المحور، وفي «الأحياء» الحيّ هو القائمة، وفي «سطر واحد» جملة واحدة في المرة. كلها تعمل: بدّل نصف القطر والمس عدّادات الحافة في أ، اسحب على الشريط في ب، المس حيّاً ثم قلّب البطاقات في ج، وانتظر الجملة أو المسها في د.</p>
    <div class="rules">
      <div><i>١</i><span>شيء واحد يتحرّك على الشاشة في المرة، والباقي ساكن.</span></div>
      <div><i>٢</i><span>لا صف رقائق ولا قوائم فوق الخريطة؛ البحث وحده في الأعلى.</span></div>
      <div><i>٣</i><span>عنصر تحكّم واحد لكل نظام، والباقي يستجيب له.</span></div>
      <div><i>٤</i><span>الخريطة كاملة دائماً، والمحتوى يتنفّس فوقها بلا ورقة.</span></div>
    </div>
    <div class="rowh">
      <div class="seg" id="seg" role="tablist" aria-label="النماذج">
        <button class="on" data-go="a" role="tab"><i>أ</i>العدسة</button>
        <button data-go="b" role="tab"><i>ب</i>خط الوقت</button>
        <button data-go="c" role="tab"><i>ج</i>الأحياء</button>
        <button data-go="d" role="tab"><i>د</i>سطر واحد</button>
      </div>
    </div>
  </header>

  <div class="phones">
    <section class="slot active" id="s-a">
      <h2><span>أ</span>العدسة <small>· المسافة هي التحكم الوحيد</small></h2>
      <div class="phone"><div class="screen" data-concept="a">__A__</div></div>
      <p class="note">دائرة حول موقعك تُبقي ما بداخلها واضحاً وتُخفّف ما خارجها. التحكم الوحيد هو نصف القطر (٥٠٠ م، ١ كم، ٣ كم)، وعلى حافة الدائرة أربعة عدّادات تُحدَّث تلقائياً: أشخاص، دوائر، عروض، سوق. لمس عدّاد يفتح شاشة مركّزة لما بداخل الدائرة فقط ثم تعود. الأقسام الـ12 كلها تصير «ما ضمن هذه المسافة»، ولا معنى لترتيبها أو إخفائها.</p>
    </section>
    <section class="slot" id="s-b">
      <h2><span>ب</span>خط الوقت <small>· الزمن هو المحور</small></h2>
      <div class="phone"><div class="screen" data-concept="b">__B__</div></div>
      <p class="note">كل ما حولك حدث له وقت: لحظة نُشرت قبل دقائق، عرض ينتهي بعد ساعتين، بازار في الخامسة، مقابلة في السابعة، عرض غداً صباحاً. شريط زمني واحد أسفل الخريطة من «الآن» إلى «غداً»، اسحب عليه فتظهر بطاقة واحدة ويُبرَز دبّوسها. هذا يوحّد اللحظات والعروض والفعاليات والوظائف والسوق في محور واحد بلا أقسام أصلاً، ويجيب عن السؤال الحقيقي: «ماذا يحدث الآن، وماذا بعد؟».</p>
    </section>
    <section class="slot" id="s-c">
      <h2><span>ج</span>الأحياء <small>· الحيّ هو القائمة</small></h2>
      <div class="phone"><div class="screen" data-concept="c">__C__</div></div>
      <p class="note">الخريطة بلا دبابيس إطلاقاً؛ عليها أربع كبسولات للأحياء بعدد ما فيها ووجوه من فيها. لمس حيّ يقرّب الخريطة إليه ويفتح رزمة بطاقاته (لحظات وعروض ودوائر وسوق الحيّ نفسه) تُقلَّب بلمسة، والرجوع يبعّد الخريطة. التسلسل هنا جغرافي كما يفكّر أهل جدة: «وش فيه بالروضة؟». لا تظهر أي تفاصيل قبل أن يختار المستخدم مكاناً.</p>
    </section>
    <section class="slot" id="s-d">
      <h2><span>د</span>سطر واحد <small>· جملة واحدة في المرة</small></h2>
      <div class="phone"><div class="screen" data-concept="d">__D__</div></div>
      <p class="note">أهدأ ما يمكن: الخريطة وجملة واحدة مكتوبة بلغة الناس تتبدّل كل بضع ثوانٍ («عرض أوفردوز ينتهي الليلة وهو على بعد ٦٥٠ م»)، ودبّوسها ينبض على الخريطة. لمس الجملة يفتح بطاقتها بفعل واحد، وزر إيقاف صغير لمن يريد التأمل. الأقسام الـ12 تصير مصدراً للجمل مرتّبةً بالأهمية والقرب، لا أقساماً يراها المستخدم. يناسب من يفتح التطبيق ليعرف «ما الجديد حولي» في ثوانٍ.</p>
    </section>
  </div>

  <div class="tblwrap"><table class="cmp">
    <thead><tr><th>المعيار</th><th>أ · العدسة</th><th>ب · خط الوقت</th><th>ج · الأحياء</th><th>د · سطر واحد</th></tr></thead>
    <tbody>
      <tr><th>الفكرة الواحدة</th><td>المسافة</td><td>الزمن</td><td>المكان</td><td>الأهمية</td></tr>
      <tr><th>عنصر التحكم</th><td>نصف القطر</td><td>مقبض على الشريط</td><td>لمس الحيّ</td><td>لا شيء (أو إيقاف)</td></tr>
      <tr><th>الهدوء البصري</th><td>عالٍ: الخارج يخفت</td><td>عالٍ: بطاقة واحدة</td><td><b>الأعلى</b>: لا دبابيس قبل الاختيار</td><td><b>الأعلى</b>: جملة واحدة</td></tr>
      <tr><th>مصير الأقسام الـ12</th><td>أربعة عدّادات وشاشات مركّزة</td><td>تذوب في محور واحد</td><td>رزمة لكل حيّ</td><td>مصدر للجمل فقط</td></tr>
      <tr><th>يُبرز التجارة</th><td>نعم (عروض وسوق عدّادان)</td><td>نعم (العروض بانتهائها والوظائف بمقابلاتها)</td><td>نعم داخل الحيّ</td><td>نعم بترتيب الأهمية</td></tr>
      <tr><th>ما يحتاجه الخادم</th><td>استعلام بنصف قطر (موجود)</td><td>وقت لكل عنصر (موجود لكل الأنواع)</td><td>عدّادات لكل حيّ (جديد، بسيط)</td><td>ترتيب بالأهمية (جديد، متوسط)</td></tr>
      <tr><th>الخطر</th><td>مدينة قليلة الكثافة تعطي أصفاراً</td><td>عناصر بلا وقت واضح تُفتعل لها أوقات</td><td>الحيّ الفارغ يُحبط</td><td>الجملة الرديئة تفقد الثقة سريعاً</td></tr>
      <tr><th>أثر التنفيذ</th><td>متوسط</td><td>متوسط</td><td>متوسط إلى كبير (تقريب سلس)</td><td><b>صغير</b></td></tr>
    </tbody>
  </table></div>

  <div class="reco">
    <b>توصيتي</b>
    <span>«ب · خط الوقت» هو الأكثر أصالة والأقرب لروح ناس لايف: يذيب الأقسام كلها في سؤال واحد «ماذا يحدث الآن وماذا بعد؟» ويُبرز العروض والفعاليات والوظائف تلقائياً لأن لها أوقاتاً. وأهدأها للعين «د · سطر واحد» وينفَّذ في أيام. ويمكن الجمع بينهما بلا ازدحام: الشريط الزمني للتصفّح، والجملة الواحدة كحالة افتراضية حين لا يلمس المستخدم شيئاً. «أ» و«ج» أقوى حين تكثر البيانات في الحيّ، فأقترح تأجيلهما إلى ما بعد نمو المحتوى.</span>
  </div>
</div>

<script>__JS__</script>
'''
page = page.replace('__CSS__', CSS + CSS3).replace('__A__', A()).replace('__B__', B()).replace('__C__', C()).replace('__D__', D()).replace('__JS__', JS)

if __name__ == '__main__':
    icons_path = root / 'icons.json'
    icons = json.loads(icons_path.read_text(encoding='utf-8'))
    icons.update(ICONS3)
    icons_path.write_text(json.dumps(icons, ensure_ascii=False, indent=1), encoding='utf-8')
    (root / 'template_calm.html').write_text(page, encoding='utf-8')
