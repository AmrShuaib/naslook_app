# يولّد template_main.html: ثلاثة أنظمة للشاشات الرئيسية الخمس (الرئيسية، الخريطة، الدوائر، المحادثات، ماي سبيس)
# بالمحتوى الحقيقي للتطبيق (جدة). البناء: python3 build.py template_main.html > out.html
import json, pathlib
root = pathlib.Path(__file__).parent

# ---------- أيقونات (تُضاف إلى icons.json)
def svg(body, size=20, stroke=True, sw=2):
    if stroke:
        return f'<svg width="{size}" height="{size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round">{body}</svg>'
    return f'<svg width="{size}" height="{size}" viewBox="0 0 24 24" fill="currentColor">{body}</svg>'
ICONS = {
 'i-home': svg('<path d="M3 11l9-8 9 8"/><path d="M5 10v10h5v-6h4v6h5V10"/>', 22),
 'i-map': svg('<path d="M9 4L3 6v14l6-2 6 2 6-2V4l-6 2z"/><path d="M9 4v14"/><path d="M15 6v14"/>', 22),
 'i-groups': svg('<circle cx="9" cy="8" r="3.5"/><circle cx="17" cy="9" r="2.5"/><path d="M2.5 19a6.5 6.5 0 0 1 13 0"/><path d="M15 15.5a4.5 4.5 0 0 1 6.5 3.5"/>', 22),
 'i-chat': svg('<path d="M21 12a8 8 0 0 1-11.6 7.1L4 20l1-4.6A8 8 0 1 1 21 12z"/>', 22),
 'i-me': svg('<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>', 22),
 'i-search': svg('<circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/>', 18),
 'i-bell': svg('<path d="M6 16V11a6 6 0 0 1 12 0v5l2 2H4z"/><path d="M10 21h4"/>', 18),
 'i-cam': svg('<path d="M4 8h3l2-3h6l2 3h3v11H4z"/><circle cx="12" cy="13" r="3.5"/>', 22),
 'i-plus': svg('<path d="M12 5v14"/><path d="M5 12h14"/>', 22, sw=2.5),
 'i-pin': svg('<path d="M12 21s-7-6.2-7-11a7 7 0 0 1 14 0c0 4.8-7 11-7 11z"/><circle cx="12" cy="10" r="2.5"/>', 14),
 'i-heart': svg('<path d="M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.6-7 10-7 10z"/>', 18),
 'i-cmt': svg('<path d="M21 12a8 8 0 0 1-11.6 7.1L4 20l1-4.6A8 8 0 1 1 21 12z"/>', 18),
 'i-share': svg('<path d="M4 12v7a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-7"/><path d="M16 6l-4-4-4 4"/><path d="M12 2v13"/>', 18),
 'i-tag': svg('<path d="M20 12l-8 8-9-9V3h8z"/><circle cx="7.5" cy="7.5" r="1.5" fill="currentColor"/>', 22),
 'i-job': svg('<rect x="3" y="7" width="18" height="13" rx="2"/><path d="M9 7V5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2"/><path d="M3 12h18"/>', 22),
 'i-ticket': svg('<path d="M3 9a2 2 0 0 0 0 6v3h18v-3a2 2 0 0 1 0-6V6H3z"/><path d="M13 6v12"/>', 22),
 'i-cal': svg('<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18"/><path d="M8 3v4"/><path d="M16 3v4"/>', 22),
 'i-blog': svg('<rect x="4" y="3" width="16" height="18" rx="2"/><path d="M8 8h8"/><path d="M8 12h8"/><path d="M8 16h5"/>', 22),
 'i-bag': svg('<path d="M6 8h12l1 13H5z"/><path d="M9 8V6a3 3 0 0 1 6 0v2"/>', 22),
 'i-wallet': svg('<rect x="3" y="6" width="18" height="13" rx="2"/><path d="M3 10h18"/><circle cx="16.5" cy="14.5" r="1.2" fill="currentColor"/>', 22),
 'i-layers': svg('<path d="M12 3l9 5-9 5-9-5z"/><path d="M3 13l9 5 9-5"/>', 18),
 'i-list': svg('<path d="M8 6h13"/><path d="M8 12h13"/><path d="M8 18h13"/><circle cx="4" cy="6" r="1" fill="currentColor"/><circle cx="4" cy="12" r="1" fill="currentColor"/><circle cx="4" cy="18" r="1" fill="currentColor"/>', 18),
 'i-sliders': svg('<path d="M4 7h10"/><path d="M18 7h2"/><circle cx="16" cy="7" r="2"/><path d="M4 17h4"/><path d="M12 17h8"/><circle cx="10" cy="17" r="2"/>', 18),
 'i-clock': svg('<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>', 14),
 'i-mic': svg('<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0"/><path d="M12 18v3"/>', 14),
 'i-locate': svg('<circle cx="12" cy="12" r="3"/><path d="M12 2v3"/><path d="M12 19v3"/><path d="M2 12h3"/><path d="M19 12h3"/><circle cx="12" cy="12" r="8"/>', 18),
 'i-play': svg('<path d="M8 5.5v13a1 1 0 0 0 1.5.86l11-6.5a1 1 0 0 0 0-1.72l-11-6.5A1 1 0 0 0 8 5.5z"/>', 16, stroke=False),
 'i-shield': svg('<path d="M12 2l7 3v6c0 5-3.5 8.5-7 10-3.5-1.5-7-5-7-10V5z"/>', 22),
 'i-store': svg('<path d="M4 9l1-4h14l1 4"/><path d="M4 9a2.5 2.5 0 0 0 5 0 2.5 2.5 0 0 0 5 0 2.5 2.5 0 0 0 5 0 2.5 2.5 0 0 0 1 0"/><path d="M5 11v9h14v-9"/><path d="M10 20v-5h4v5"/>', 22),
 'i-tick': svg('<path d="M5 13l4 4L19 7"/>', 11, sw=3.5),
 'i-chev': svg('<path d="M15 6l-6 6 6 6"/>', 18),
 'i-hp': svg('<path d="M3 11l9-8 9 8"/><path d="M5 10v10h5v-6h4v6h5V10"/>', 32),
}

# ---------- خريطة جدة المرسومة (بحر غرباً، كورنيش، أحياء)
MAP = '''<svg class="base" viewBox="0 0 390 700" preserveAspectRatio="xMidYMid slice" aria-hidden="true">
<rect width="390" height="700" fill="#F1EFE8"/>
<path d="M0 0H118C150 110 88 250 128 372C160 462 96 600 138 700H0Z" fill="#D5E5F1"/>
<path d="M150 90C170 170 130 240 166 330C190 390 150 470 170 540C182 590 160 650 176 700" fill="none" stroke="#DCD9D0" stroke-width="11"/>
<path d="M150 90C170 170 130 240 166 330C190 390 150 470 170 540C182 590 160 650 176 700" fill="none" stroke="#fff" stroke-width="8"/>
<g stroke="#fff" stroke-width="6"><path d="M150 180H390"/><path d="M158 300H390"/><path d="M160 420H390"/><path d="M172 560H390"/><path d="M260 90V700"/><path d="M330 120V700"/></g>
<g stroke="#DCD9D0" stroke-width="1"><path d="M150 180H390"/><path d="M158 300H390"/><path d="M160 420H390"/><path d="M172 560H390"/><path d="M260 90V700"/><path d="M330 120V700"/></g>
<g fill="#E8E5DC"><rect x="178" y="196" width="66" height="88" rx="6"/><rect x="276" y="196" width="40" height="88" rx="6"/><rect x="180" y="318" width="64" height="86" rx="6"/><rect x="276" y="318" width="40" height="86" rx="6"/><rect x="346" y="318" width="40" height="86" rx="6"/><rect x="184" y="438" width="60" height="106" rx="6"/><rect x="276" y="438" width="40" height="106" rx="6"/><rect x="346" y="438" width="40" height="106" rx="6"/><rect x="190" y="578" width="54" height="110" rx="6"/><rect x="276" y="578" width="40" height="110" rx="6"/></g>
<ellipse cx="300" cy="140" rx="34" ry="22" fill="#DCE8D2"/>
<g font-family="Rubik,Tahoma,sans-serif" font-size="11" fill="#8A8F87"><text x="215" y="250">الشاطئ</text><text x="215" y="370">الحمراء</text><text x="222" y="500">الروضة</text><text x="228" y="640">التحلية</text><text x="40" y="330" fill="#7FA3BF">البحر الأحمر</text><text x="282" y="145" fill="#7A9A6C">حديقة</text></g>
</svg>'''

def pin(img, x, y, kind='', extra=''):
    k = f'<i class="k">@@{kind}@@</i>' if kind else ''
    return f'<span class="pin" style="right:{x}%;top:{y}%"{extra}><img src="@@{img}@@" alt="">{k}</span>'
def plabel(img, name, x, y):
    return f'<span class="plabel" style="right:{x}%;top:{y}%"><img src="@@{img}@@" alt="">{name}</span>'
PINS = (pin('p16', 78, 30, 'i-cam') + pin('p42', 40, 58) + pin('p274', 30, 79, 'i-play') + pin('p63', 62, 49, 'i-mic') + pin('avatar', 52, 66)
        + plabel('overdose', 'أوفردوز', 42, 68) + plabel('halfmillion', 'هاف مليون', 26, 36) + plabel('3brews', 'ثري بروز', 66, 60) + plabel('rawnah', 'رونة', 20, 50)
        + '<span class="me" style="right:56%;top:44%"></span>')

# ---------- بيانات مشتركة
MOMENTS = [('p16', 'avatar', 'الكورنيش', 'فهد', 'قبل ١٢ د', 'i-cam'), ('p42', 'p26', 'الروضة', 'سارة', 'قبل ٢٥ د', ''), ('p274', 'p154', 'التحلية', 'نورة', 'قبل ساعة', 'i-play'), ('p63', 'p119', 'الحمراء', 'عبدالله', 'قبل ساعتين', 'i-mic'), ('p184', 'p60', 'طريق مكة', 'ريان', 'قبل ٣ س', '')]
PLACES = [('overdose', 'أوفردوز', 'مقهى · الروضة', '٨ لحظات · مفتوح الآن', '٦٥٠ م'), ('halfmillion', 'هاف مليون', 'مقهى · الشاطئ', '٥ لحظات · خصم ٢٠٪', '١.٢ كم'), ('3brews', 'ثري بروز', 'مقهى · الحمراء', 'يوظّف باريستا', '٢.١ كم'), ('rawnah', 'رونة', 'مقهى · التحلية', 'مفتوح حتى ١٢', '٣.٤ كم')]
CIRCLES_MINE = [('avatar', 'جيران الشاطئ', '١٢٤ عضواً · ٣ منشورات جديدة'), ('p16', 'مصوّرو جدة', '٣٨٠ عضواً · نقاش حيّ الآن'), ('p244', 'استوديو فهد شوتس', 'دائرتك التجارية · ٥ رسائل')]
CIRCLES_DISC = [('overdose', 'أوفردوز', 'مقهى · ٢٬١٠٠ متابع · ٦٥٠ م'), ('halfmillion', 'هاف مليون', 'مقهى · ١٬٤٠٠ متابع · ١.٢ كم'), ('malaga', 'مالقا', 'مقهى · ٩٨٠ متابعاً · ٢.٨ كم'), ('s158', 'عشّاق القهوة المختصة', 'مجتمع · ٤٬٣٠٠ عضو')]
CHATS = [('p26', 'سارة م.', 'الصور جاهزة؟ أحتاجها قبل الخميس', 'قبل ٣ د', 2, True), ('overdose', 'أوفردوز', 'عرضك على اللاتيه ينتهي الليلة · بطاقة عرض', 'قبل ٢٠ د', 1, False), ('p119', 'عبدالله ر.', '✓✓ تم استلام الحامل، شكراً', 'أمس', 0, False), ('p154', 'نورة ح.', '@@i-mic@@ رسالة صوتية · ٠:١٢', 'أمس', 0, True), ('p60', 'ريان', 'موعد التصوير الجمعة ٥ م عند الكورنيش', 'الأحد', 0, False)]
PRODUCTS = [('p250', 'كاميرا فوجي X-T20', '2,650 ر.س', 'الشاطئ'), ('p60', 'حامل مانفروتو + حقيبة', '480 ر.س', 'توصيل'), ('p119', 'ماك بوك إير M1', '2,900 ر.س', 'الحمراء'), ('p26', 'طقم فلاتر ND', '220 ر.س', 'جديد')]

def moment_cards(items=MOMENTS, n=5):
    out = []
    for img, who, place, name, ago, kind in items[:n]:
        k = f'<i class="k">@@{kind}@@</i>' if kind else ''
        out.append(f'<div class="mcard"><img src="@@{img}@@" alt=""><img class="who" src="@@{who}@@" alt="">{k}<div class="ov"><b>{name}</b><span>@@i-pin@@{place} · {ago}</span></div></div>')
    return ''.join(out)
def place_rows(items=PLACES, n=4, btn=''):
    return ''.join(f'<div class="place"><img src="@@{img}@@" alt=""><div class="b"><span class="t">{n_}</span><span class="d">{cat}</span><span class="d"><span class="open">{meta}</span> · {dist}</span></div>{btn}</div>' for img, n_, cat, meta, dist in items[:n])
def circle_rows(items, btn):
    return ''.join(f'<div class="place"><img src="@@{img}@@" alt="" style="border-radius:999px"><div class="b"><span class="t">{n_}</span><span class="d">{d}</span></div>{btn}</div>' for img, n_, d in items)
def chat_rows(items=CHATS, big=False):
    out = []
    for img, name, msg, ago, unread, online in items:
        dot = '<i class="odot"></i>' if online else ''
        b = f'<span class="badge">{unread}</span>' if unread else ''
        out.append(f'<div class="chat{" big" if big else ""}"><span class="avw"><img src="@@{img}@@" alt="">{dot}</span><div class="b"><span class="t">{name}<small>{ago}</small></span><span class="d">{msg}</span></div>{b}</div>')
    return ''.join(out)
def product_cards(n=4):
    return ''.join(f'<div class="card"><img src="@@{img}@@" alt=""><div class="body"><span class="t">{t}</span><span class="price">{p}</span><span class="d muted" style="font-size:11.5px">{d}</span></div></div>' for img, t, p, d in PRODUCTS[:n])
JOBCARD = '''<div class="jobc"><span class="ic">@@i-job@@</span><div class="b"><span class="t">عرض وظيفي: باريستا · ثري بروز</span><span class="d">دوام جزئي · الحمراء · ٤٬٥٠٠ ر.س · يطابق ملفك ٨٧٪</span></div><button class="btn sm">افتح</button></div>'''
OFFERS = [('overdose', 'خصم ٢٠٪ على اللاتيه', 'أوفردوز · حتى الليلة', 'p63'), ('halfmillion', 'الفنجان السادس مجاناً', 'هاف مليون · للأعضاء', 'p42'), ('3brews', 'قهوة الصباح بـ ٩ ر.س', 'ثري بروز · حتى ١١ ص', 'p16')]
def offer_cards():
    return ''.join(f'<div class="ocard"><img src="@@{img}@@" alt=""><div class="ov"><img class="lg" src="@@{lg}@@" alt=""><b>{t}</b><span>{d}</span></div></div>' for lg, t, d, img in OFFERS)

# ---------- عناصر مشتركة
def topbar(title, right='', left=''):
    return f'<div class="tb"><div class="l">{left}</div><span class="ttl">{title}</span><div class="r">{right}</div></div>'
BELL = '<button class="ib" aria-label="الإشعارات">@@i-bell@@<i class="dot"></i></button>'
SEARCHB = '<button class="ib" aria-label="بحث">@@i-search@@</button>'
def chips(items, glass=False):
    g = ' glass' if glass else ''
    return '<div class="hrow">' + ''.join(f'<span class="ch{g}{" on" if on else ""}">{t}</span>' for t, on in items) + '</div>'
def sec(title, link='الكل', small=''):
    s = f'<small>{small}</small>' if small else ''
    return f'<div class="sec"><b>{title}{s}</b><a href="#">{link}</a></div>'
def nav_std(active, items):
    return '<nav class="nav">' + ''.join(f'<button data-nav="{k}"{" class=on" if k==active else ""}>@@{ic}@@{lbl}</button>' for k, ic, lbl in items) + '</nav>'
NAV5 = [('home', 'i-home', 'الرئيسية'), ('map', 'i-map', 'الخريطة'), ('circles', 'i-groups', 'الدوائر'), ('chats', 'i-chat', 'المحادثات'), ('me', 'i-me', 'ماي سبيس')]
def nav_pill(active):
    def b(k, ic, lbl): return f'<button data-nav="{k}"{" class=on" if k==active else ""}>@@{ic}@@<span>{lbl}</span></button>'
    return ('<nav class="nav pill">' + b('home', 'i-map', 'الخريطة') + b('circles', 'i-groups', 'الدوائر')
            + '<button class="c" aria-label="لحظة جديدة">@@i-cam@@</button>' + b('chats', 'i-chat', 'المحادثات') + b('me', 'i-me', 'ماي سبيس') + '</nav>')
def screen(key, body, nav, cls=''):
    return f'<div class="scr {cls}" data-scr="{key}"{"" if key=="home" else " hidden"}>{body}{nav}</div>'

# ======================================================================
# النموذج أ · الخريطة أولاً
# ======================================================================
def A():
    home = f'''<div class="map">{MAP}{PINS}
      <div class="top"><div class="search glass">@@i-search@@<span style="flex-grow:1">ابحث في جدة: أشخاص، دوائر، سوق</span><span class="avm"><img src="@@avatar@@" alt=""></span></div>
        {chips([('لحظات ١٢', True), ('دوائر', False), ('عروض ٣', False), ('وظائف ١', False), ('أصدقاء ٤', False)], glass=True)}</div>
      <button class="fabm" style="bottom:214px" aria-label="موقعي">@@i-locate@@</button>
      <button class="fabm" style="bottom:258px" aria-label="الطبقات">@@i-layers@@</button>
      <div class="sheet" style="height:300px">
        <span class="hd"></span>
        <div class="sec"><b>حولك الآن<small>٤٦ شخصاً · ١٢ لحظة · ٣ عروض</small></b><a href="#">قائمة</a></div>
        <div class="hs">{moment_cards(n=5)}</div>
      </div></div>'''
    mapx = f'''<div class="map">{MAP}{PINS}
      <div class="top"><div class="search glass">@@i-search@@<span style="flex-grow:1">مقاهٍ مفتوحة الآن</span>@@i-sliders@@</div>
        {chips([('الكل', False), ('مقاهٍ ١٤', True), ('مطاعم', False), ('مستشفيات', False), ('سوق', False), ('وظائف', False)], glass=True)}</div>
      <div class="sheet" style="height:62%">
        <span class="hd"></span>
        <div class="sec"><b>١٤ مقهى قريباً<small>الأقرب أولاً</small></b><a href="#">خريطة</a></div>
        {place_rows(PLACES, 4, '<span class="dist">@@i-pin@@</span>')}
        <div class="place"><img src="@@malaga@@" alt=""><div class="b"><span class="t">مالقا</span><span class="d">مقهى · أبحر</span><span class="d"><span class="open">مفتوح الآن</span> · ٤.١ كم</span></div></div>
      </div></div>'''
    circles = f'''{topbar('الدوائر', SEARCHB + BELL)}
      <div class="scroll pad">
        <div class="hs rings">{''.join(f'<div class="ring{" new" if i<3 else ""}"><img src="@@{img}@@" alt=""><span>{n}</span></div>' for i,(img,n,_) in enumerate(CIRCLES_MINE + [CIRCLES_DISC[0], CIRCLES_DISC[2]]))}<div class="ring add"><span class="pl">@@i-plus@@</span><span>جديدة</span></div></div>
        {sec('آخر ما في دوائرك', 'الكل')}
        <div class="post"><div class="au"><img src="@@p16@@" alt=""><div class="b"><span class="t">مصوّرو جدة <small>· فهد · قبل ٤٠ د</small></span><span class="d">دائرة عامة · ٣٨٠ عضواً</span></div></div><div class="im"><img src="@@p244@@" alt=""><span class="cap">مين جرّب عدسة ٣٥ مم على الكورنيش بالليل؟ عندي ٣ لقطات</span></div><div class="acts"><span>@@i-heart@@ ٢٤</span><span>@@i-cmt@@ ٩</span><span>@@i-share@@</span></div></div>
        <div class="post"><div class="au"><img src="@@avatar@@" alt=""><div class="b"><span class="t">جيران الشاطئ <small>· سارة · قبل ساعة</small></span><span class="d">دائرة خاصة · ١٢٤ عضواً</span></div></div><p class="txt">بازار الحي الجمعة ٥ م في الحديقة، من يشارك بطاولة يسجّل هنا 👇</p><div class="acts"><span>@@i-heart@@ ٥٧</span><span>@@i-cmt@@ ٢١</span><span>@@i-share@@</span></div></div>
        {sec('اكتشف حولك', 'الكل')}
        <div class="hs">{''.join(f'<div class="pcard"><img src="@@{img}@@" alt="" style="width:44px;height:44px;border-radius:999px"><b>{n}</b><small>{d}</small><button class="btn sm soft" style="align-self:flex-start">انضم</button></div>' for img,n,d in CIRCLES_DISC)}</div>
      </div>'''
    chats = f'''{topbar('المحادثات', '<button class="ib" aria-label="محادثة جديدة">@@i-plus@@</button>', SEARCHB)}
      <div class="scroll pad">
        {chips([('الكل ٥', True), ('رسائل', False), ('الطلبات ٣', False), ('التوظيف ١', False)])}
        {JOBCARD}
        {chat_rows()}
        <div class="reqrow"><span class="stack"><img src="@@p37@@" alt=""><img src="@@p57@@" alt=""><img src="@@p184@@" alt=""></span><div class="b"><span class="t">٣ طلبات مراسلة</span><span class="d">من غير الأصدقاء · اقبل أو تجاهل</span></div>@@i-chev@@</div>
      </div>'''
    me = f'''{topbar('ماي سبيس', '<button class="ib" aria-label="الإعدادات">@@i-sliders@@</button>' + BELL)}
      <div class="scroll pad">
        <div class="mehead"><img src="@@avatar@@" alt=""><div class="b"><span class="t">فهد الغامدي <i class="vm">@@i-tick@@</i></span><span class="d">@fahad.shots · مصوّر · جدة</span><span class="d" style="color:var(--a);font-weight:600">عرض ملفي العام</span></div><span class="intro-pill">@@i-play@@ ٠:٤٢</span></div>
        <div class="wallet"><div style="display:flex;justify-content:space-between;align-items:center"><span style="font-size:12.5px;opacity:.85">المحفظة</span><span style="font-size:12px;opacity:.85">آخر عملية: +٣٥٠ ر.س</span></div><span class="bal">2,340 <small>ر.س</small></span><div class="qs"><button>شحن</button><button>تحويل</button><button>تذاكري</button></div></div>
        <div class="tiles">{''.join(f'<button><span class="ic">@@{ic}@@</span><b>{t}</b><small>{d}</small></button>' for ic,t,d in [('i-cal','حجوزاتي وطلباتي','٣ هذا الأسبوع'),('i-cam','منشوراتي','٩ نشطة'),('i-bag','عروضي في السوق','٤ إعلانات'),('i-store','نشاطي التجاري','دائرتك'),('i-job','التوظيف','عرض جديد'),('i-heart','أمنياتي','١٢ عنصراً')])}</div>
        <div class="list">{''.join(f'<button><span class="ic2">@@{ic}@@</span><div class="body"><span class="t">{t}</span><span class="d">{d}</span></div>@@i-chev@@</button>' for ic,t,d in [('i-shield','الخصوصية والأمان','المحظورون والمكتومون'),('i-bell','الإشعارات','الكل مفعّل'),('i-blog','التحديثات والأخبار','مدونة ناس لايف')])}</div>
      </div>'''
    return (screen('home', home, nav_pill('home'), 'abs') + screen('map', mapx, nav_pill('home'), 'abs')
            + screen('circles', circles, nav_pill('circles'), 'abs') + screen('chats', chats, nav_pill('chats'), 'abs') + screen('me', me, nav_pill('me'), 'abs'))

# ======================================================================
# النموذج ب · الموجز
# ======================================================================
def B():
    def feedpost(img, who, name, place, ago, cap, likes, cmts, kind=''):
        k = f'<i class="k">@@{kind}@@</i>' if kind else ''
        return f'<div class="post"><div class="au"><img src="@@{who}@@" alt=""><div class="b"><span class="t">{name}</span><span class="d">@@i-pin@@ {place} · {ago}</span></div><span class="ch" style="height:28px">متابعة</span></div><div class="im"><img src="@@{img}@@" alt="">{k}<span class="cap">{cap}</span></div><div class="acts"><span>@@i-heart@@ {likes}</span><span>@@i-cmt@@ {cmts}</span><span>@@i-share@@</span><span style="margin-inline-start:auto;color:var(--a);font-weight:600">مراسلة</span></div></div>'
    home = f'''<div class="tb"><div class="l"><button class="ib" aria-label="لحظة جديدة" style="background:var(--a);color:#fff">@@i-cam@@</button></div><span class="ttl" style="display:flex;flex-direction:column;align-items:center;line-height:1.1"><span>مساء الخير، فهد</span><small class="sub2">جدة · ٤٦ شخصاً حولك · ١٢ لحظة</small></span><div class="r">{BELL}</div></div>
      <div class="scroll" style="gap:16px;padding-bottom:20px">
        <div class="mapstrip">{MAP}{PINS}<div class="cta">@@i-map@@ افتح الخريطة الحية</div></div>
        {chips([('الأقرب', True), ('الأحدث', False), ('فيديو', False), ('صوت', False), ('أصدقائي', False)])}
        {feedpost('p16', 'avatar', 'فهد الغامدي', 'الكورنيش', 'قبل ١٢ د', 'غروب اليوم من صخور الكورنيش', '١٢٨', '١٤', 'i-cam')}
        {sec('الأماكن الرائجة اليوم', 'الكل')}
        <div class="hs">{''.join(f'<div class="pcard"><img src="@@{img}@@" alt="" style="width:44px;height:44px;border-radius:12px"><b>{n}</b><small>{meta}</small><small style="color:#111">{dist}</small></div>' for img,n,_,meta,dist in PLACES)}</div>
        {feedpost('p274', 'p154', 'نورة ح.', 'التحلية', 'قبل ساعة', 'شارع التحلية بعد المطر، فيديو ١٥ ث', '٨٦', '٧', 'i-play')}
        <div class="circ-card"><div class="sec" style="padding:0"><b>آخر ما في دوائرك</b><a href="#">الكل</a></div>{circle_rows(CIRCLES_MINE[:2], '<span class="badge">٣</span>')}</div>
        {feedpost('p42', 'p26', 'سارة م.', 'الروضة · أوفردوز', 'قبل ٢٥ د', 'أفضل طاولة للعمل عندهم، والواي فاي سريع', '٤١', '٥')}
      </div>'''
    mapx = f'''<div class="map">{MAP}{PINS}
      <div class="top"><div class="seg3 glass" style="margin:0 14px"><button class="on">خريطة</button><button>قائمة</button><button>أصدقاء</button></div>
        {chips([('لحظات', True), ('دوائر', False), ('عروض', False), ('وظائف', False)], glass=True)}</div>
      <button class="fabm" style="bottom:150px" aria-label="موقعي">@@i-locate@@</button>
      <div class="sheet" style="height:138px;padding-bottom:0"><span class="hd"></span>{sec('الأقرب إليك', 'قائمة', '٦٥٠ م')}{place_rows(PLACES, 1, '<button class="btn sm soft">افتح</button>')}</div></div>'''
    circles = f'''{topbar('الدوائر', '<button class="btn sm">دائرة جديدة</button>', SEARCHB)}
      <div class="scroll" style="gap:14px;padding-bottom:20px">
        {sec('دوائري', 'ترتيب', '٦')}
        <div class="grid2" style="padding:0 14px">{''.join(f'<div class="ccover"><img src="@@{cov}@@" alt=""><div class="ov"><img class="lg" src="@@{lg}@@" alt=""><b>{n}</b><span>{d}</span></div>{("<span class=nb>"+nb+"</span>") if nb else ""}</div>' for cov,lg,n,d,nb in [('p244','avatar','جيران الشاطئ','١٢٤ عضواً','٣ جديدة'),('p16','p16','مصوّرو جدة','٣٨٠ عضواً','نقاش حيّ'),('p42','overdose','أوفردوز','مقهى · الروضة',''),('s158','p244','فهد شوتس','دائرتك',''),])}</div>
        {sec('اكتشف حولك', 'الكل')}
        {circle_rows(CIRCLES_DISC, '<button class="btn sm soft">انضم</button>')}
      </div>'''
    chats = f'''{topbar('المحادثات', '<button class="ib" aria-label="محادثة جديدة">@@i-plus@@</button>')}
      <div class="scroll" style="gap:10px;padding-bottom:20px">
        <div class="search">@@i-search@@ ابحث في الرسائل والأشخاص</div>
        <div class="reqrow"><span class="stack"><img src="@@p37@@" alt=""><img src="@@p57@@" alt=""><img src="@@p184@@" alt=""></span><div class="b"><span class="t">طلبات المراسلة · ٣</span><span class="d">أول رسالة من غير الأصدقاء تصل هنا</span></div>@@i-chev@@</div>
        {chat_rows(big=True)}
        {sec('التوظيف', 'الكل')}
        {JOBCARD}
      </div>'''
    me = f'''<div class="scroll" style="padding-bottom:20px">
        <div class="cover"><img src="@@cover@@" alt=""><div class="tbo"><span class="ttl">ماي سبيس</span><div>{BELL}<button class="ib" aria-label="الإعدادات">@@i-sliders@@</button></div></div></div>
        <div class="mehead big"><img src="@@avatar@@" alt=""><div class="b"><span class="t">فهد الغامدي <i class="vm">@@i-tick@@</i> <span class="tag">مصوّر</span></span><span class="d">@fahad.shots · جدة · حي الشاطئ</span></div><button class="btn sm ghost">تعديل</button></div>
        <div class="intro" style="margin:0 14px"><button class="play" aria-label="تشغيل">@@i-play@@</button><div class="body"><span class="t">تعريفي الصوتي</span><div class="wave">{''.join('<i style="height:%d%%"></i>' % h for h in [30,55,80,45,70,95,40,60,85,35,50,75,45,65,90,40,55,30,60,80,45,70,35,50])}</div><span class="d">٠:٤٢ · ٨٦ استماعاً هذا الأسبوع</span></div></div>
        <div class="stats" style="margin:0 14px"><div class="stat"><b>128</b><small>منشور</small></div><div class="stat"><b>1,212</b><small>متابِع</small></div><div class="stat"><b>4.9</b><small>٤٧ تقييماً</small></div><div class="stat"><b>2,340</b><small>ر.س محفظة</small></div></div>
        {sec('نشاطي')}
        <div class="list plain">{''.join(f'<button><span class="ic2">@@{ic}@@</span><div class="body"><span class="t">{t}</span><span class="d">{d}</span></div>@@i-chev@@</button>' for ic,t,d in [('i-cam','منشوراتي على الخريطة','٩ نشطة · مسودّتان'),('i-cal','حجوزاتي وطلباتي','جلسة الخميس ٤:٣٠'),('i-heart','قائمة أمنياتي','١٢ عنصراً · انخفض سعر واحد')])}</div>
        {sec('التجارة')}
        <div class="list plain">{''.join(f'<button><span class="ic2">@@{ic}@@</span><div class="body"><span class="t">{t}</span><span class="d">{d}</span></div>@@i-chev@@</button>' for ic,t,d in [('i-wallet','المحفظة','2,340 ر.س · شحن وتحويل'),('i-bag','عروضي وطلباتي في السوق','٤ إعلانات · طلب بانتظار التأكيد'),('i-store','نشاطي التجاري','استوديو فهد شوتس'),('i-job','التوظيف','أبحث عن عمل · عرض جديد')])}</div>
        {sec('الإعدادات')}
        <div class="list plain">{''.join(f'<button><span class="ic2">@@{ic}@@</span><div class="body"><span class="t">{t}</span><span class="d">{d}</span></div>@@i-chev@@</button>' for ic,t,d in [('i-shield','الخصوصية والأمان','من يراسلني · المحظورون'),('i-bell','الإشعارات','الكل مفعّل')])}</div>
      </div>'''
    return (screen('home', home, nav_std('home', NAV5)) + screen('map', mapx, nav_std('map', NAV5)) + screen('circles', circles, nav_std('circles', NAV5))
            + screen('chats', chats, nav_std('chats', NAV5)) + screen('me', me, nav_std('me', NAV5)))

# ======================================================================
# النموذج ج · المدينة
# ======================================================================
def C():
    qa = ''.join(f'<button><span class="ic">@@{ic}@@</span>{t}</button>' for ic,t in [('i-map','الخريطة'),('i-groups','الدوائر'),('i-bag','السوق'),('i-tag','العروض'),('i-job','الوظائف'),('i-cal','الفعاليات'),('i-ticket','التذاكر'),('i-blog','المدونة')])
    home = f'''<div class="tb"><div class="l">{BELL}<button class="ib" aria-label="جديد" style="background:var(--a);color:#fff">@@i-plus@@</button></div><span class="ttl brand">ناس لايف</span><div class="r loc">@@i-pin@@ جدة · الشاطئ</div></div>
      <div class="scroll" style="gap:16px;padding-bottom:20px">
        <div class="search">@@i-search@@ ابحث عن أشخاص ودوائر وأنشطة ومنتجات</div>
        <div class="qa">{qa}</div>
        {sec('عروض اليوم', 'الكل', '١٢ قريباً')}
        <div class="hs">{offer_cards()}</div>
        {sec('دوائر قريبة منك', 'الكل')}
        {place_rows(PLACES, 3, '<button class="btn sm soft">متابعة</button>')}
        {sec('لحظات حولك', 'الخريطة', '٤٦ شخصاً')}
        <div class="hs">{moment_cards(n=5)}</div>
        {sec('وظائف جديدة', 'الكل')}
        <div style="padding:0 14px">{JOBCARD}</div>
        {sec('من السوق', 'الكل')}
        <div class="grid2" style="padding:0 14px">{product_cards(2)}</div>
      </div>'''
    mapx = f'''<div class="map">{MAP}{PINS}
      <div class="top"><div class="search glass">@@i-search@@<span style="flex-grow:1">ابحث في الخريطة</span>@@i-sliders@@</div>
        {chips([('الكل', True), ('مقاهٍ', False), ('مطاعم', False), ('مستشفيات', False), ('سوق', False), ('وظائف', False), ('فعاليات', False)], glass=True)}</div>
      <button class="fabm" style="bottom:168px" aria-label="موقعي">@@i-locate@@</button>
      <div class="sheet" style="height:236px"><span class="hd"></span>{sec('حولك الآن', 'قائمة ٢٣', '٤٦ شخصاً · ١٢ لحظة')}<div class="hs">{moment_cards(n=5)}</div></div></div>'''
    circles = f'''{topbar('الدوائر', SEARCHB + '<button class="ib" aria-label="دائرة جديدة">@@i-plus@@</button>')}
      {chips([('الكل', True), ('مقاهٍ', False), ('مطاعم', False), ('مستشفيات', False), ('شركات', False), ('مجتمعات', False), ('جامعات', False)])}
      <div class="scroll" style="gap:12px;padding:12px 0 20px">
        {sec('دوائري', 'الكل', '٦')}
        <div class="hs rings">{''.join(f'<div class="ring"><img src="@@{img}@@" alt=""><span>{n}</span></div>' for img,n,_ in CIRCLES_MINE)}<div class="ring add"><span class="pl">@@i-plus@@</span><span>جديدة</span></div></div>
        {sec('قريبة منك', 'ترتيب: الأقرب')}
        {place_rows(PLACES, 4, '<button class="btn sm soft">متابعة</button>')}
        {circle_rows([CIRCLES_DISC[3]], '<button class="btn sm soft">انضم</button>')}
      </div>'''
    chats = f'''{topbar('المحادثات', '<button class="ib" aria-label="محادثة جديدة">@@i-plus@@</button>', SEARCHB)}
      {chips([('الكل ٥', True), ('رسائل', False), ('الطلبات ٣', False), ('التوظيف ١', False), ('الدوائر', False)])}
      <div class="scroll" style="padding:8px 0 20px">
        {chat_rows()}
        {sec('الطلبات والتوظيف')}
        <div class="reqrow"><span class="stack"><img src="@@p37@@" alt=""><img src="@@p57@@" alt=""><img src="@@p184@@" alt=""></span><div class="b"><span class="t">٣ طلبات مراسلة</span><span class="d">من غير الأصدقاء</span></div>@@i-chev@@</div>
        {JOBCARD}
      </div>'''
    me = f'''{topbar('ماي سبيس', '<button class="ib" aria-label="الإعدادات">@@i-sliders@@</button>' + BELL)}
      <div class="scroll" style="gap:12px;padding-bottom:20px">
        <div class="mehead"><img src="@@avatar@@" alt=""><div class="b"><span class="t">فهد الغامدي <i class="vm">@@i-tick@@</i></span><span class="d">@fahad.shots · ملفي العام</span></div>@@i-chev@@</div>
        <div class="wallet"><div style="display:flex;justify-content:space-between;align-items:center"><span style="font-size:12.5px;opacity:.85">رصيد المحفظة</span><span class="ch" style="height:24px;background:rgba(255,255,255,.18);color:#fff;font-size:11px">شحن تجريبي مفعّل</span></div><span class="bal">2,340 <small>ر.س</small></span><div class="qs"><button>شحن</button><button>تحويل</button><button>تذاكري</button><button>الفواتير</button></div></div>
        <div class="tiles">{''.join(f'<button><span class="ic">@@{ic}@@</span><b>{t}</b><small>{d}</small></button>' for ic,t,d in [('i-cal','حجوزاتي وطلباتي','٣'),('i-bag','السوق','٤ إعلانات'),('i-cam','منشوراتي','٩'),('i-store','نشاطي التجاري','دائرة'),('i-job','التوظيف','١ جديد'),('i-heart','أمنياتي','١٢')])}</div>
        <div class="list">{''.join(f'<button><span class="ic2">@@{ic}@@</span><div class="body"><span class="t">{t}</span><span class="d">{d}</span></div>@@i-chev@@</button>' for ic,t,d in [('i-search','بحوثي المحفوظة','تنبيه عند جديد يطابق بحثك'),('i-shield','الخصوصية والأمان','المحظورون والمحادثات المكتومة'),('i-bell','الإشعارات','الكل مفعّل'),('i-blog','التحديثات والأخبار','مدونة ناس لايف'),('i-share','مشاركة حسابي','naslife.app/u/fahad.shots')])}</div>
      </div>'''
    return (screen('home', home, nav_std('home', NAV5)) + screen('map', mapx, nav_std('map', NAV5)) + screen('circles', circles, nav_std('circles', NAV5))
            + screen('chats', chats, nav_std('chats', NAV5)) + screen('me', me, nav_std('me', NAV5)))

# ======================================================================
CSS = r'''
/* Layout: concept switch + screen switch on top; three phones side by side (one at a time under 1250px). Phones are the app's own white UI; the accent family is the brand teal. */
:root{
  --bg:#FFFFFF; --fg:#111111; --muted:#5F6B73; --line:#E3E7EA; --card:#FFFFFF; --sun:#FFD66B;
  --a:#0A6E78; --a-soft:#E0F3F4; --a-ink:#0F2D30;
  --font-body:Rubik,"Segoe UI",Tahoma,sans-serif; --font-display:"Baloo Bhaijaan 2",Rubik,Tahoma,sans-serif;
}
@media (prefers-color-scheme: dark){ :root:not([data-theme="light"]){ --bg:#0F1315; --fg:#F1F3F4; --muted:#9AA6AE; --line:#273036; --card:#171C20; color-scheme:dark } }
:root[data-theme="dark"]{ --bg:#0F1315; --fg:#F1F3F4; --muted:#9AA6AE; --line:#273036; --card:#171C20; color-scheme:dark }
html,body{height:100%}
body{margin:0;background:var(--bg);color:var(--fg);font-family:var(--font-body);direction:rtl}
.wrap{max-width:1780px;margin:0 auto;padding-inline:16px;padding-block:14px 40px;display:flex;flex-direction:column;gap:14px}
header{display:flex;flex-direction:column;gap:10px}
h1{margin:0;font:800 26px/1.2 var(--font-display);text-wrap:balance}
.sub{margin:0;color:var(--muted);font-size:14px;line-height:1.6;max-width:75ch}
.seg{display:flex;gap:4px;background:var(--card);border:1px solid var(--line);border-radius:14px;padding:4px;overflow-x:auto;scrollbar-width:none}
.seg::-webkit-scrollbar{display:none}
.seg button{flex:1 0 auto;min-width:0;height:40px;padding:0 14px;border:0;border-radius:10px;background:transparent;color:var(--muted);font:600 14px var(--font-body);cursor:pointer;white-space:nowrap;display:inline-flex;align-items:center;gap:8px;justify-content:center}
.seg button.on{background:var(--a);color:#fff}
.seg button:focus-visible{outline:2px solid var(--a);outline-offset:2px}
.seg button i{width:22px;height:22px;border-radius:999px;background:rgba(0,0,0,.08);display:inline-flex;align-items:center;justify-content:center;font-style:normal;font-size:12px}
.seg button.on i{background:rgba(255,255,255,.22)}
.rowh{display:flex;gap:10px;align-items:center;flex-wrap:wrap}
.rowh .seg{flex:1 1 320px}
.rowh .seg.sc button{height:36px;font-size:13px}
.phones{display:flex;gap:26px;flex-wrap:wrap;justify-content:center;align-items:flex-start}
.slot{display:flex;flex-direction:column;gap:10px;width:min(390px,100%)}
.slot h2{margin:0;font:700 15px var(--font-body);color:var(--fg);display:flex;align-items:center;gap:8px}
.slot h2 span{width:26px;height:26px;border-radius:999px;background:var(--a);color:#fff;display:inline-flex;align-items:center;justify-content:center;font-size:13px;flex:none}
.slot h2 small{font-weight:500;color:var(--muted);font-size:13px}
.note{margin:0;font-size:13px;line-height:1.6;color:var(--muted)}
.phone{width:100%;height:790px;max-height:calc(100vh - 40px);border-radius:34px;background:#111;padding:10px;box-sizing:border-box;box-shadow:0 20px 50px rgba(0,0,0,.25)}
.screen{width:100%;height:100%;border-radius:26px;background:#fff;color:#111;overflow:hidden;display:flex;flex-direction:column;font-family:var(--font-body);direction:rtl;position:relative}
.scr{flex:1 1 auto;min-height:0;display:flex;flex-direction:column;position:relative}
.scroll{flex:1 1 auto;min-height:0;overflow-y:auto;overflow-x:hidden;display:flex;flex-direction:column;gap:12px;scrollbar-width:none;padding-bottom:16px}
.scroll::-webkit-scrollbar{display:none}
.scr.abs .scroll.pad{padding-bottom:92px}
@media (max-width:1250px){ .slot:not(.active){display:none} }
/* ---- app pieces (always white) */
.tb{flex:none;min-height:54px;display:flex;align-items:center;justify-content:space-between;padding:6px 14px;gap:8px}
.tb .l,.tb .r{display:flex;gap:6px;align-items:center;min-width:0}
.tb .ttl{font:800 20px var(--font-display);white-space:nowrap}
.tb .ttl.brand{color:var(--a)}
.tb .sub2{font:500 11.5px var(--font-body);color:#6B7280}
.tb .loc{font-size:12px;color:#374151;font-weight:600;gap:3px}
.ib{width:36px;height:36px;border-radius:999px;border:0;background:#F2F2F7;color:#111;display:inline-flex;align-items:center;justify-content:center;position:relative;cursor:pointer;flex:none}
.ib .dot{position:absolute;top:6px;right:8px;width:8px;height:8px;border-radius:999px;background:#D23B3B;border:1.5px solid #fff}
.btn{height:40px;padding:0 16px;border-radius:999px;border:0;background:var(--a);color:#fff;font:700 14px var(--font-body);cursor:pointer;display:inline-flex;align-items:center;gap:6px;white-space:nowrap;flex:none}
.btn.ghost{background:#fff;color:#111;border:1.5px solid #E5E5EA;font-weight:600}
.btn.soft{background:var(--a-soft);color:var(--a-ink)}
.btn.sm{height:32px;padding:0 12px;font-size:12.5px}
.search{height:42px;border-radius:999px;background:#F2F2F7;display:flex;align-items:center;gap:8px;padding:0 12px 0 8px;color:#6B7280;font-size:13.5px;margin:0 14px;flex:none}
.search.glass{background:rgba(255,255,255,.94);box-shadow:0 4px 14px rgba(0,0,0,.16);color:#374151;font-weight:500}
.avm{width:30px;height:30px;border-radius:999px;overflow:hidden;flex:none}.avm img{width:100%;height:100%;object-fit:cover;display:block}
.hrow{display:flex;gap:8px;overflow-x:auto;padding:0 14px;scrollbar-width:none;flex:none}
.hrow::-webkit-scrollbar{display:none}
.ch{flex:none;display:inline-flex;align-items:center;gap:5px;height:32px;padding:0 12px;border-radius:999px;background:#F2F2F7;color:#374151;font-size:12.5px;font-weight:500;white-space:nowrap}
.ch.on{background:var(--a);color:#fff}
.ch.glass{background:rgba(255,255,255,.95);box-shadow:0 2px 8px rgba(0,0,0,.14);color:#111}
.ch.glass.on{background:#111;color:#fff}
.sec{display:flex;justify-content:space-between;align-items:baseline;padding:0 14px;flex:none}
.sec b{font-size:15px;font-weight:700;display:flex;align-items:baseline;gap:8px}.sec a{font-size:12.5px;color:var(--a);font-weight:600;text-decoration:none}
.sec small{font-size:11.5px;color:#6B7280;font-weight:500}
.hs{display:flex;gap:10px;overflow-x:auto;padding:0 14px;scrollbar-width:none;flex:none}
.hs::-webkit-scrollbar{display:none}
.hs>*{flex:none}
.mcard{position:relative;width:124px;height:166px;border-radius:14px;overflow:hidden;background:#F2F2F7}
.mcard>img:first-child{width:100%;height:100%;object-fit:cover;display:block}
.mcard .who{position:absolute;top:8px;right:8px;width:26px;height:26px;border-radius:999px;border:2px solid #fff;object-fit:cover}
.mcard .k,.pin .k,.post .k{position:absolute;top:8px;left:8px;width:22px;height:22px;border-radius:999px;background:rgba(17,17,17,.6);color:#fff;display:inline-flex;align-items:center;justify-content:center}
.mcard .k svg,.pin .k svg,.post .k svg{width:12px;height:12px}
.mcard .ov{position:absolute;inset:auto 0 0 0;padding:28px 8px 8px;background:linear-gradient(transparent,rgba(0,0,0,.7));color:#fff;font-size:11px;display:flex;flex-direction:column;gap:2px}
.mcard .ov b{font-size:12px}.mcard .ov span{display:inline-flex;align-items:center;gap:3px;opacity:.9}
.place{display:flex;align-items:center;gap:10px;padding:6px 14px;flex:none}
.place img{width:48px;height:48px;border-radius:12px;object-fit:cover;background:#F2F2F7;flex:none}
.place .b{flex-grow:1;min-width:0;display:flex;flex-direction:column;gap:1px}
.place .t{font-size:14px;font-weight:600}.place .d{font-size:12px;color:#6B7280;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.open{color:#1FA35A;font-weight:600}
.dist{color:#6B7280;display:inline-flex}
.pcard{width:148px;border:1px solid #E5E5EA;border-radius:14px;padding:10px;display:flex;flex-direction:column;gap:5px;box-sizing:border-box}
.pcard b{font-size:13.5px}.pcard small{font-size:11.5px;color:#6B7280;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.post{display:flex;flex-direction:column;gap:8px;padding:0 14px;flex:none}
.post .au{display:flex;align-items:center;gap:8px}
.post .au img{width:36px;height:36px;border-radius:999px;object-fit:cover}
.post .au .b{flex-grow:1;min-width:0;display:flex;flex-direction:column}
.post .au .t{font-size:13.5px;font-weight:700}.post .au .t small{font-weight:400;color:#6B7280}.post .au .d{font-size:11.5px;color:#6B7280;display:inline-flex;align-items:center;gap:3px}
.post .im{border-radius:16px;overflow:hidden;aspect-ratio:4/3;background:#F2F2F7;position:relative;max-width:100%}
.post .im img{width:100%;height:100%;object-fit:cover;display:block}
.post .cap{position:absolute;inset:auto 0 0 0;padding:30px 12px 10px;background:linear-gradient(transparent,rgba(0,0,0,.7));color:#fff;font-size:13px;font-weight:500;line-height:1.4}
.post .txt{margin:0;font-size:14px;line-height:1.55}
.post .acts{display:flex;gap:16px;color:#374151;font-size:12.5px;align-items:center}
.post .acts span{display:inline-flex;align-items:center;gap:4px}
.circ-card{margin:0 14px;border:1px solid #E5E5EA;border-radius:16px;padding:12px 0 4px;display:flex;flex-direction:column;gap:6px;flex:none}
.circ-card .sec{padding:0 12px}
.grid2{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px;flex:none}
.card{display:flex;flex-direction:column;gap:6px;border:1px solid #E5E5EA;border-radius:14px;overflow:hidden}
.card img{width:100%;height:110px;object-fit:cover;display:block}
.card .body{padding:0 10px 10px;display:flex;flex-direction:column;gap:2px}
.card .t{font-size:13px;font-weight:600;line-height:1.3}
.price{font:700 14px var(--font-body);color:var(--a);font-variant-numeric:tabular-nums}
.muted{color:#6B7280}
.ocard{position:relative;width:200px;height:112px;border-radius:14px;overflow:hidden;background:#F2F2F7}
.ocard>img:first-child{width:100%;height:100%;object-fit:cover;display:block}
.ocard .ov{position:absolute;inset:0;padding:10px;background:linear-gradient(90deg,rgba(0,0,0,.05),rgba(0,0,0,.72));color:#fff;display:flex;flex-direction:column;justify-content:flex-end;gap:2px}
.ocard .ov b{font-size:13.5px}.ocard .ov span{font-size:11px;opacity:.9}
.ocard .lg{width:28px;height:28px;border-radius:8px;border:1.5px solid #fff;margin-bottom:auto;object-fit:cover}
.jobc{display:flex;align-items:center;gap:10px;border:1.5px solid var(--a-soft);background:var(--a-soft);border-radius:14px;padding:10px;flex:none;margin:0 14px}
.jobc .ic{width:40px;height:40px;border-radius:12px;background:#fff;color:var(--a);display:inline-flex;align-items:center;justify-content:center;flex:none}
.jobc .b{flex-grow:1;min-width:0;display:flex;flex-direction:column;gap:1px}
.jobc .t{font-size:13.5px;font-weight:700;color:var(--a-ink)}.jobc .d{font-size:11.5px;color:#374151;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.scroll .jobc{margin:0 14px}
.chat{display:flex;align-items:center;gap:12px;padding:8px 14px;flex:none}
.chat .avw{position:relative;flex:none}
.chat img{width:48px;height:48px;border-radius:999px;object-fit:cover;display:block}
.chat.big img{width:54px;height:54px}
.chat .odot{position:absolute;bottom:1px;left:1px;width:12px;height:12px;border-radius:999px;background:#1FA35A;border:2px solid #fff}
.chat .b{flex-grow:1;min-width:0;display:flex;flex-direction:column;gap:2px}
.chat .t{display:flex;justify-content:space-between;font-size:14px;font-weight:600;gap:8px}.chat .t small{font-weight:400;color:#6B7280;font-size:11.5px;flex:none}
.chat .d{font-size:12.5px;color:#6B7280;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;display:flex;align-items:center;gap:4px}
.badge{min-width:20px;height:20px;border-radius:999px;background:var(--a);color:#fff;font-size:11px;font-weight:700;display:inline-flex;align-items:center;justify-content:center;padding:0 6px;flex:none}
.reqrow{display:flex;align-items:center;gap:12px;margin:0 14px;padding:10px 12px;border:1px solid #E5E5EA;border-radius:14px;flex:none;color:#6B7280}
.reqrow .stack{display:inline-flex;flex:none}
.reqrow .stack img{width:30px;height:30px;border-radius:999px;border:2px solid #fff;object-fit:cover;margin-inline-start:-10px}
.reqrow .stack img:first-child{margin-inline-start:0}
.reqrow .b{flex-grow:1;min-width:0;display:flex;flex-direction:column;gap:1px}
.reqrow .t{font-size:13.5px;font-weight:600;color:#111}.reqrow .d{font-size:11.5px}
.rings{gap:14px;padding-block:4px}
.ring{display:flex;flex-direction:column;align-items:center;gap:5px;width:64px}
.ring img{width:58px;height:58px;border-radius:999px;object-fit:cover;border:2.5px solid #fff;box-shadow:0 0 0 2px #E5E5EA}
.ring.new img{box-shadow:0 0 0 2.5px var(--a)}
.ring span{font-size:11px;color:#374151;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:64px}
.ring .pl{width:58px;height:58px;border-radius:999px;border:1.5px dashed #C7C7CC;display:inline-flex;align-items:center;justify-content:center;color:#6B7280}
.mehead{display:flex;align-items:center;gap:12px;padding:4px 14px;flex:none}
.mehead img{width:56px;height:56px;border-radius:999px;object-fit:cover}
.mehead.big{padding:0 14px;margin-top:-30px;align-items:flex-end}
.mehead.big img{width:84px;height:84px;border:4px solid #fff}
.mehead .b{flex-grow:1;min-width:0;display:flex;flex-direction:column;gap:2px}
.mehead .t{font:800 17px var(--font-display);display:flex;align-items:center;gap:6px}.mehead .d{font-size:12.5px;color:#6B7280}
.vm{width:18px;height:18px;border-radius:999px;background:var(--a);color:#fff;display:inline-flex;align-items:center;justify-content:center;flex:none;font-style:normal}
.tag{font:600 11px var(--font-body);color:#5A4200;background:#FFF4D6;padding:3px 8px;border-radius:999px}
.intro-pill{display:inline-flex;align-items:center;gap:4px;height:30px;padding:0 10px;border-radius:999px;background:var(--a-soft);color:var(--a-ink);font-size:12px;font-weight:600;flex:none}
.wallet{margin:0 14px;border-radius:18px;background:var(--a);color:#fff;padding:14px;display:flex;flex-direction:column;gap:8px;flex:none}
.wallet .bal{font:800 30px/1.1 var(--font-display);font-variant-numeric:tabular-nums}.wallet .bal small{font:600 13px var(--font-body);opacity:.85}
.wallet .qs{display:flex;gap:8px;margin-top:2px}.wallet .qs button{flex:1;height:36px;border-radius:10px;border:0;background:rgba(255,255,255,.18);color:#fff;font:600 12.5px var(--font-body);cursor:pointer}
.tiles{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px;padding:0 14px;flex:none}
.tiles button{display:flex;flex-direction:column;gap:6px;align-items:flex-start;border:1px solid #E5E5EA;border-radius:14px;padding:10px;background:#fff;font-family:var(--font-body);text-align:right;cursor:pointer;min-width:0}
.tiles .ic{width:32px;height:32px;border-radius:10px;background:var(--a-soft);color:var(--a);display:inline-flex;align-items:center;justify-content:center}
.tiles b{font-size:12px;color:#111;line-height:1.25}.tiles small{font-size:11px;color:#6B7280}
.list{display:flex;flex-direction:column;border:1px solid #E5E5EA;border-radius:14px;overflow:hidden;margin:0 14px;flex:none}
.list.plain{border:0;border-radius:0;margin:0}
.list>*{display:flex;align-items:center;gap:12px;padding:11px 14px;border-bottom:1px solid #E5E5EA;color:#111;background:#fff;border-left:0;border-right:0;border-top:0;font-family:var(--font-body);text-align:right;cursor:pointer}
.list>*:last-child{border-bottom:0}
.list .body{flex-grow:1;display:flex;flex-direction:column;gap:1px;min-width:0}
.list .t{font-size:14px;font-weight:600}.list .d{font-size:12px;color:#6B7280;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.ic2{width:36px;height:36px;border-radius:10px;background:#F2F2F7;color:#374151;display:inline-flex;align-items:center;justify-content:center;flex:none}
.stats{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:6px;padding:10px 0;border-top:1px solid #E5E5EA;border-bottom:1px solid #E5E5EA;flex:none}
.stat{display:flex;flex-direction:column;align-items:center;gap:1px}
.stat b{font:700 17px var(--font-body);color:#111;font-variant-numeric:tabular-nums}.stat small{font-size:11.5px;color:#6B7280}
.cover{position:relative;height:150px;flex:none}
.cover>img{width:100%;height:100%;object-fit:cover;display:block}
.cover .tbo{position:absolute;top:10px;right:14px;left:14px;display:flex;justify-content:space-between;align-items:center}
.cover .tbo .ttl{font:800 20px var(--font-display);color:#fff;text-shadow:0 1px 6px rgba(0,0,0,.5)}
.cover .tbo div{display:flex;gap:6px}
.cover .ib{background:rgba(17,17,17,.5);color:#fff}
.intro{display:flex;align-items:center;gap:10px;border:1px solid #E5E5EA;border-radius:16px;padding:8px 10px 8px 8px;background:#fff;flex:none}
.intro .play{width:42px;height:42px;border-radius:999px;border:0;background:var(--a);color:#fff;display:inline-flex;align-items:center;justify-content:center;cursor:pointer;flex:none}
.intro .body{flex-grow:1;min-width:0;display:flex;flex-direction:column;gap:3px}
.intro .t{font-size:13.5px;font-weight:700}.intro .d{font-size:12px;color:#6B7280}
.wave{display:flex;align-items:center;gap:2px;height:22px}.wave i{flex:1 1 0;min-width:2px;border-radius:2px;background:#D1D5DB}
.qa{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:8px;padding:0 14px;flex:none}
.qa button{display:flex;flex-direction:column;align-items:center;gap:6px;border:0;background:transparent;font:500 11.5px var(--font-body);color:#111;cursor:pointer;padding:0}
.qa .ic{width:54px;height:54px;border-radius:16px;display:inline-flex;align-items:center;justify-content:center;background:var(--a-soft);color:var(--a)}
.ccover{position:relative;aspect-ratio:1;border-radius:16px;overflow:hidden;background:#F2F2F7;max-width:100%}
.ccover>img:first-child{width:100%;height:100%;object-fit:cover;display:block}
.ccover .ov{position:absolute;inset:0;padding:10px;background:linear-gradient(transparent 30%,rgba(0,0,0,.75));color:#fff;display:flex;flex-direction:column;justify-content:flex-end;gap:2px}
.ccover .ov b{font-size:13.5px}.ccover .ov span{font-size:11px;opacity:.9}
.ccover .lg{width:30px;height:30px;border-radius:999px;border:2px solid #fff;margin-bottom:auto;object-fit:cover}
.ccover .nb{position:absolute;top:8px;left:8px;font-size:10.5px;font-weight:700;color:#5A4200;background:#FFD66B;padding:3px 7px;border-radius:999px}
/* map */
.map{position:relative;flex:1 1 auto;min-height:0;overflow:hidden;background:#F1EFE8}
.map svg.base{position:absolute;inset:0;width:100%;height:100%}
.map .pin{position:absolute;width:40px;height:40px;transform:translate(50%,-50%)}
.map .pin img{width:40px;height:40px;border-radius:999px;border:2.5px solid #fff;box-shadow:0 2px 8px rgba(0,0,0,.28);object-fit:cover;display:block}
.map .pin .k{top:-6px;left:-6px;width:20px;height:20px;background:var(--a)}
.map .plabel{position:absolute;transform:translate(50%,-50%);display:flex;flex-direction:column;align-items:center;gap:2px;font-size:10.5px;font-weight:700;color:#1F2937;text-shadow:0 0 3px #fff,0 0 3px #fff,0 0 3px #fff;white-space:nowrap}
.map .plabel img{width:24px;height:24px;border-radius:7px;border:1.5px solid #fff;box-shadow:0 1px 4px rgba(0,0,0,.28);object-fit:cover}
.map .me{position:absolute;width:16px;height:16px;border-radius:999px;background:#1E88FF;border:3px solid #fff;box-shadow:0 0 0 8px rgba(30,136,255,.18);transform:translate(50%,-50%)}
.map .top{position:absolute;top:10px;right:0;left:0;display:flex;flex-direction:column;gap:8px}
.fabm{position:absolute;left:12px;width:40px;height:40px;border-radius:999px;border:0;background:#fff;color:#111;box-shadow:0 3px 10px rgba(0,0,0,.2);display:inline-flex;align-items:center;justify-content:center;cursor:pointer}
.sheet{position:absolute;right:0;left:0;bottom:0;background:#fff;border-radius:20px 20px 0 0;box-shadow:0 -6px 24px rgba(0,0,0,.16);display:flex;flex-direction:column;gap:10px;padding:8px 0 96px;box-sizing:border-box;overflow:hidden}
.scr:not(.abs) .sheet{padding-bottom:10px}
.sheet .hd{width:36px;height:4px;border-radius:999px;background:#D1D5DB;margin:0 auto;flex:none}
.mapstrip{position:relative;height:120px;margin:0 14px;border-radius:16px;overflow:hidden;flex:none;background:#F1EFE8}
.mapstrip .pin{width:28px;height:28px}.mapstrip .pin img{width:28px;height:28px}.mapstrip .plabel{font-size:9px}.mapstrip .plabel img{width:18px;height:18px}.mapstrip .pin .k{display:none}
.mapstrip .cta{position:absolute;bottom:8px;right:10px;display:inline-flex;align-items:center;gap:6px;height:30px;padding:0 12px;border-radius:999px;background:#111;color:#fff;font-size:12px;font-weight:600}
.seg3{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:4px;background:#F2F2F7;border-radius:12px;padding:4px;flex:none}
.seg3.glass{background:rgba(255,255,255,.95);box-shadow:0 4px 14px rgba(0,0,0,.16)}
.seg3 button{height:34px;border:0;border-radius:9px;background:transparent;color:#6B7280;font:600 13px var(--font-body);cursor:pointer}
.seg3 button.on{background:#111;color:#fff}
/* navs */
.nav{flex:none;height:64px;border-top:1px solid #E5E5EA;background:#fff;display:grid;grid-template-columns:repeat(5,minmax(0,1fr));align-items:center;padding:0 6px}
.nav button{border:0;background:transparent;display:flex;flex-direction:column;align-items:center;gap:2px;font:500 10.5px var(--font-body);color:#6B7280;cursor:pointer;padding:0}
.nav button.on{color:var(--a);font-weight:600}
.nav.pill{position:absolute;left:14px;right:14px;bottom:12px;height:60px;border:1px solid #E5E5EA;border-radius:999px;background:rgba(255,255,255,.97);box-shadow:0 10px 28px rgba(0,0,0,.2);padding:0 8px}
.nav.pill .c{width:52px;height:52px;border-radius:999px;background:var(--a);color:#fff;margin-top:-26px;box-shadow:0 8px 18px rgba(10,110,120,.4);justify-self:center;display:inline-flex;align-items:center;justify-content:center}
.nav.pill button span{font-size:10px}
/* compare table */
.cmp{width:100%;border-collapse:collapse;font-size:13.5px;min-width:640px}
.cmp th,.cmp td{border-bottom:1px solid var(--line);padding:10px 8px;text-align:right;vertical-align:top;line-height:1.55}
.cmp th{font-weight:700;color:var(--fg)}
.cmp thead th{color:var(--muted);font-weight:600;font-size:12.5px}
.cmp td b{color:var(--a)}
.tblwrap{overflow-x:auto;border:1px solid var(--line);border-radius:14px;padding:0 12px}
.reco{border:1px solid var(--line);border-radius:14px;padding:14px 16px;display:flex;flex-direction:column;gap:6px;font-size:14px;line-height:1.65}
.reco b{font-size:15px}
[hidden]{display:none!important}
@media (prefers-reduced-motion: reduce){ *{transition:none!important} }
'''

page = f'''<title>الشاشات الرئيسية لناس لايف</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Rubik:wght@400;500;600;700&family=Baloo+Bhaijaan+2:wght@600;700;800&display=swap">
<style>{CSS}</style>
<div class="wrap">
  <header>
    <h1>الشاشات الرئيسية لناس لايف</h1>
    <p class="sub">ثلاثة أنظمة للشاشات الخمس نفسها (الرئيسية، الخريطة، الدوائر، المحادثات، ماي سبيس) بالمحتوى الحقيقي للتطبيق في جدة. يختلف بينها ما يفتح عليه المستخدم أولاً، وشكل التنقّل، وكثافة المعلومات. شريط التنقّل داخل الهاتف يعمل، وتبديل الشاشة ينعكس على النماذج الثلاثة معاً للمقارنة. اختر نموذجاً وسأنفّذه في التطبيق.</p>
    <div class="rowh">
      <div class="seg" id="seg" role="tablist" aria-label="النماذج">
        <button class="on" data-go="a" role="tab"><i>أ</i>الخريطة أولاً</button>
        <button data-go="b" role="tab"><i>ب</i>الموجز</button>
        <button data-go="c" role="tab"><i>ج</i>المدينة</button>
      </div>
      <div class="seg sc" id="segScr" role="tablist" aria-label="الشاشة">
        <button class="on" data-scrall="home">الرئيسية</button><button data-scrall="map">الخريطة</button><button data-scrall="circles">الدوائر</button><button data-scrall="chats">المحادثات</button><button data-scrall="me">ماي سبيس</button>
      </div>
    </div>
  </header>

  <div class="phones">
    <section class="slot active" id="s-a">
      <h2><span>أ</span>الخريطة أولاً <small>· المدينة الحيّة كواجهة</small></h2>
      <div class="phone"><div class="screen" data-concept="a">{A()}</div></div>
      <p class="note">الرئيسية هي الخريطة نفسها: بحث زجاجي، طبقات (لحظات، دوائر، عروض، وظائف، أصدقاء)، وورقة سفلية «حولك الآن» تُسحب لتصبح قائمة. شريط تنقّل عائم بأربعة أقسام وزر كاميرا مرتفع في الوسط للحظة جديدة. الدوائر بحلقات «جديد» ثم آخر المنشورات. يناسب من يريد أن يشعر التطبيق بأنه «جدة الآن».</p>
    </section>
    <section class="slot" id="s-b">
      <h2><span>ب</span>الموجز <small>· لحظات المدينة كخلاصة</small></h2>
      <div class="phone"><div class="screen" data-concept="b">{B()}</div></div>
      <p class="note">الرئيسية موجز اجتماعي: تحية وحالة المدينة، شريط خريطة صغير، ثم لحظات كبيرة الصورة مع الكاتب والمكان وأزرار تفاعل، وبينها الأماكن الرائجة ودوائرك. الخريطة تبويب مستقل بمفتاح خريطة/قائمة. الدوائر ببطاقات غلاف، وماي سبيس بغلاف وتعريف صوتي. يناسب من يريد محتوى يُقرأ ويُتصفّح كإنستغرام محلي.</p>
    </section>
    <section class="slot" id="s-c">
      <h2><span>ج</span>المدينة <small>· بوابة خدمات المدينة</small></h2>
      <div class="phone"><div class="screen" data-concept="c">{C()}</div></div>
      <p class="note">الرئيسية بوابة: بحث، ثماني اختصارات (الخريطة، الدوائر، السوق، العروض، الوظائف، الفعاليات، التذاكر، المدونة)، ثم صفوف أفقية: عروض اليوم، دوائر قريبة، لحظات، وظائف، السوق. الخريطة بفلاتر تصنيف. الدوائر بتبويبات (مقاهٍ، مطاعم، مستشفيات…) ومسافة وحالة الفتح. ماي سبيس ببطاقة محفظة أولاً. يناسب التوسّع التجاري (فنادق، سينما، براندات) والمستخدم الذي يأتي لقضاء حاجة.</p>
    </section>
  </div>

  <div class="tblwrap"><table class="cmp">
    <thead><tr><th>المعيار</th><th>أ · الخريطة أولاً</th><th>ب · الموجز</th><th>ج · المدينة</th></tr></thead>
    <tbody>
      <tr><th>ما يفتح أولاً</th><td>الخريطة الحيّة وورقة «حولك الآن»</td><td>موجز لحظات كبيرة الصورة</td><td>بحث واختصارات وصفوف خدمات</td></tr>
      <tr><th>التنقّل</th><td>شريط عائم بأربعة أقسام + كاميرا في الوسط</td><td>شريط قياسي بخمسة أقسام، الكاميرا في الأعلى</td><td>شريط قياسي بخمسة أقسام، «+» في الأعلى</td></tr>
      <tr><th>هوية التطبيق</th><td><b>مكاني</b>: «ما يحدث حولي الآن»</td><td><b>اجتماعي</b>: «ماذا نشر الناس في جدة»</td><td><b>خدمي</b>: «ماذا أقضي من ناس لايف»</td></tr>
      <tr><th>كثافة الشاشة الأولى</th><td>منخفضة (الخريطة تتنفّس)</td><td>متوسطة (بطاقة واحدة في المرة)</td><td>عالية (كل الأقسام في نظرة)</td></tr>
      <tr><th>مكان السوق والعروض والوظائف</th><td>طبقات على الخريطة وفي الورقة</td><td>مدمجة في الموجز وفي ماي سبيس</td><td>اختصارات وصفوف مستقلة في الرئيسية</td></tr>
      <tr><th>الأنسب لـ</th><td>الإطلاق في جدة والدمام حيث الكثافة عالية والمحتوى مكاني</td><td>نمو المحتوى اليومي وإبقاء المستخدم أطول</td><td>التوسّع التجاري (فنادق، سينما، براندات) والزائر الذي يريد خدمة محددة</td></tr>
      <tr><th>أثر التنفيذ</th><td>إعادة بناء الرئيسية والخريطة معاً وشريط تنقّل جديد (أكبر)</td><td>رئيسية جديدة + تعديلات محدودة على الباقي (متوسط)</td><td>رئيسية جديدة وتبويبات في الدوائر والخريطة (متوسط)</td></tr>
    </tbody>
  </table></div>

  <div class="reco">
    <b>توصيتي</b>
    <span>«أ · الخريطة أولاً» هو الأصدق لفكرة ناس لايف (منشورات على خريطة المدينة) والأكثر تميّزاً عن المنافسين، بشرط ألا تُخفى التجارة: طبقات العروض والوظائف والسوق تبقى ظاهرة كشرائح في الأعلى وفي الورقة. إن كانت الأولوية القادمة توسّع الدوائر التجارية (فنادق وسينما وبراندات) فـ«ج · المدينة» يستوعبها أسرع. ويمكن الدمج: رئيسية «أ» مع اختصارات «ج» في أعلى الورقة السفلية.</span>
  </div>
</div>

<script>
(function(){{
  var slots = {{a:'s-a', b:'s-b', c:'s-c'}};
  function go(id){{
    Object.keys(slots).forEach(function(k){{ document.getElementById(slots[k]).classList.toggle('active', k===id); }});
    document.querySelectorAll('#seg button').forEach(function(b){{ b.classList.toggle('on', b.getAttribute('data-go')===id); }});
    if (window.innerWidth <= 1250) window.scrollTo({{top:0, behavior:'smooth'}});
    try {{ localStorage.setItem('nl-main-concept', id); }} catch(e){{}}
  }}
  document.querySelectorAll('#seg button').forEach(function(b){{ b.addEventListener('click', function(){{ go(b.getAttribute('data-go')); }}); }});
  try {{ var sv = localStorage.getItem('nl-main-concept'); if (sv && slots[sv]) go(sv); }} catch(e){{}}

  // الشاشة الحالية مشتركة بين النماذج الثلاثة حتى تُقارن الشاشة نفسها
  function showScreen(key){{
    document.querySelectorAll('.scr').forEach(function(s){{ s.hidden = s.getAttribute('data-scr') !== key; }});
    document.querySelectorAll('[data-nav]').forEach(function(b){{
      var k = b.getAttribute('data-nav'); b.classList.toggle('on', k===key || (k==='home' && key==='map' && b.closest('.nav.pill')));
    }});
    document.querySelectorAll('#segScr button').forEach(function(b){{ b.classList.toggle('on', b.getAttribute('data-scrall')===key); }});
    document.querySelectorAll('.scroll').forEach(function(s){{ s.scrollTop = 0; }});
    try {{ localStorage.setItem('nl-main-screen', key); }} catch(e){{}}
  }}
  document.addEventListener('click', function(e){{
    var n = e.target.closest('[data-nav]'); if (n) {{ showScreen(n.getAttribute('data-nav')); return; }}
    var s = e.target.closest('[data-scrall]'); if (s) showScreen(s.getAttribute('data-scrall'));
  }});
  try {{ var ss = localStorage.getItem('nl-main-screen'); if (ss) showScreen(ss); }} catch(e){{}}
}})();
</script>
'''

if __name__ == '__main__':
    icons_path = root / 'icons.json'
    icons = json.loads(icons_path.read_text(encoding='utf-8')); icons.update(ICONS)
    icons_path.write_text(json.dumps(icons, ensure_ascii=False, indent=1), encoding='utf-8')
    (root / 'template_main.html').write_text(page, encoding='utf-8')
    print('template_main.html', len(page))
