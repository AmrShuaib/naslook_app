# يولّد template_flows.html: نموذج متكامل لنظام «واحد»: البطاقة المدمجة على الخريطة، وزرها يفتح الرحلة كاملة
# لكل نوع: تذكرة (فعالية)، شاهد (لحظة)، اطلب (سوق)، قدّم (وظيفة)، استخدم (عرض)، بكل الشاشات التي تليها حتى النهاية.
# البناء: python3 make_flows.py && python3 build.py template_flows.html > out.html
import json, pathlib, random
from make_main import CSS, MAP, ICONS, nav_pill, screen, svg
from make_calm import CSS3
from make_one import CSS4, ITEMS, PINS, POS, ME, search, card_html
root = pathlib.Path(__file__).parent

ICONS5 = {
 'i-chevl': svg('<path d="M9 6l6 6-6 6"/>', 20),
 'i-xw': svg('<path d="M6 6l12 12"/><path d="M18 6L6 18"/>', 20),
 'i-check': svg('<path d="M5 13l4 4L19 7"/>', 28, sw=3),
 'i-heart2': svg('<path d="M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.6-7 10-7 10z"/>', 22),
 'i-cmt2': svg('<path d="M21 12a8 8 0 0 1-11.6 7.1L4 20l1-4.6A8 8 0 1 1 21 12z"/>', 22),
 'i-share2': svg('<path d="M4 12v7a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-7"/><path d="M16 6l-4-4-4 4"/><path d="M12 2v13"/>', 22),
 'i-pin2': svg('<path d="M12 21s-7-6.2-7-11a7 7 0 0 1 14 0c0 4.8-7 11-7 11z"/><circle cx="12" cy="10" r="2.5"/>', 16),
 'i-cal2': svg('<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M3 10h18"/><path d="M8 3v4"/><path d="M16 3v4"/>', 16),
 'i-wallet2': svg('<rect x="3" y="6" width="18" height="13" rx="2"/><path d="M3 10h18"/><circle cx="16.5" cy="14.5" r="1.2" fill="currentColor"/>', 18),
 'i-send': svg('<path d="M22 2L11 13"/><path d="M22 2l-7 20-4-9-9-4z"/>', 18),
 'i-star': svg('<path d="M12 3l2.8 5.7 6.2.9-4.5 4.4 1.1 6.2L12 17.3 6.4 20.2l1.1-6.2L3 9.6l6.2-.9z"/>', 14, stroke=False),
 'i-minus': svg('<path d="M5 12h14"/>', 16, sw=2.5),
 'i-plus2': svg('<path d="M12 5v14"/><path d="M5 12h14"/>', 16, sw=2.5),
 'i-lock': svg('<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>', 14),
 'i-clock2': svg('<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>', 16),
 'i-truck': svg('<path d="M3 7h11v9H3z"/><path d="M14 10h4l3 3v3h-7z"/><circle cx="7" cy="18" r="1.8"/><circle cx="17" cy="18" r="1.8"/>', 18),
 'i-store2': svg('<path d="M4 9l1-4h14l1 4"/><path d="M5 11v9h14v-9"/><path d="M10 20v-5h4v5"/>', 18),
 'i-ticket2': svg('<path d="M3 9a2 2 0 0 0 0 6v3h18v-3a2 2 0 0 1 0-6V6H3z"/><path d="M13 6v12"/>', 18),
}
ICONS.update(ICONS5)
AR = str.maketrans('0123456789', '٠١٢٣٤٥٦٧٨٩')

# ---------- رمز QR شكلي (نمط حتمي بزوايا تحديد) ----------
def qr_svg(seed, size=150):
    rnd = random.Random(seed); n = 25; cell = size / n
    cells = []
    def finder(ox, oy):
        for y in range(7):
            for x in range(7):
                on = x in (0, 6) or y in (0, 6) or (2 <= x <= 4 and 2 <= y <= 4)
                if on: cells.append((ox + x, oy + y))
    finder(0, 0); finder(n - 7, 0); finder(0, n - 7)
    for y in range(n):
        for x in range(n):
            if (x < 8 and y < 8) or (x >= n - 8 and y < 8) or (x < 8 and y >= n - 8): continue
            if rnd.random() < 0.42: cells.append((x, y))
    rects = ''.join(f'<rect x="{x * cell:.1f}" y="{y * cell:.1f}" width="{cell + .3:.1f}" height="{cell + .3:.1f}"/>' for x, y in cells)
    return f'<svg viewBox="0 0 {size} {size}" width="{size}" height="{size}" fill="#111" aria-label="رمز QR"><rect width="{size}" height="{size}" fill="#fff"/>{rects}</svg>'

# ---------- عناصر الشاشات ----------
def pg(title, body, foot='', dark=False, close=False, sub=''):
    back = f'<button class="ib{" w" if dark else ""}" data-go="back" aria-label="{"إغلاق" if close else "رجوع"}">{"@@i-xw@@" if close else "@@i-chevl@@"}</button>'
    s = f'<span class="sub2">{sub}</span>' if sub else ''
    f = f'<div class="foot">{foot}</div>' if foot else ''
    return f'<div class="pg{" dark" if dark else ""}"><div class="phd">{back}<span class="ttl">{title}</span>{s}</div><div class="body">{body}</div>{f}</div>'
def kv(rows):
    return '<div class="kv">' + ''.join(f'<div class="row{" tot" if i == len(rows) - 1 and tot else ""}"><span>{k}</span><b>{v}</b></div>' for i, (k, v, tot) in enumerate([(r[0], r[1], r[2] if len(r) > 2 else False) for r in rows])) + '</div>'
def wallet_line(after):
    return f'<div class="wline">@@i-wallet2@@<div class="b"><span class="t">المحفظة · 2,340 ر.س</span><span class="d">بعد الدفع: {after} ر.س · الشحن عبر ميسر عند الحاجة</span></div><a href="#" class="lnk">شحن</a></div>'
def done_block(title, sub):
    return f'<div class="done"><span class="chk">@@i-check@@</span><b>{title}</b><span>{sub}</span></div>'
def seller(img, name, meta):
    return f'<div class="seller"><img src="@@{img}@@" alt=""><div class="b"><span class="t">{name}</span><span class="d">{meta}</span></div><button class="btn sm ghost">مراسلة</button></div>'

# ---------- الرحلات الخمس ----------
def flow_ticket():
    s1 = pg('بازار الحي', f'''
      <div class="hero"><img src="@@p42@@" alt=""><span class="tag">فعالية · اليوم</span></div>
      <div class="meta"><img class="lg" src="@@halfmillion@@" alt=""><div class="b"><span class="t">هاف مليون <small>· ينظّم</small></span><span class="d">@@i-cal2@@ اليوم ٥ م إلى ١٠ م &nbsp; @@i-pin2@@ حديقة الشاطئ · ٩٠٠ م</span></div></div>
      <div class="facts"><div><b>١٥</b><small>ر.س للتذكرة</small></div><div><b>١٢</b><small>طاولة</small></div><div><b>٤٨</b><small>ذاهب</small></div></div>
      <div class="going"><span class="pile"><img src="@@p26@@" alt=""><img src="@@p154@@" alt=""><img src="@@p60@@" alt=""></span><span>سارة ونورة وريان و٤٥ آخرون ذاهبون</span></div>
      <p class="txt">بازار أسبوعي لمنتجات الحي: قهوة، حلويات، حرف يدوية، وركن للأطفال. التذكرة تشمل مشروباً من هاف مليون.</p>
      <div class="opt-row"><span>عدد التذاكر</span><span class="stepper"><button data-step="-1">@@i-minus@@</button><b data-qty>١</b><button data-step="1">@@i-plus2@@</button></span></div>''',
      foot='<button class="btn wide" data-go="next">احجز · <span data-total>١٥</span> ر.س</button>')
    s2 = pg('تأكيد الحجز', f'''
      {kv([('الفعالية', 'بازار الحي · اليوم ٥ م'), ('التذاكر', '<span data-qty2>١</span> × ١٥ ر.س'), ('الإجمالي', '<span data-total2>١٥</span> ر.س', True)])}
      {wallet_line('<span data-after>2,325</span>')}
      <p class="fine">@@i-lock@@ الدفع من المحفظة الداخلية، والتذكرة تُلغى مجاناً حتى ساعة قبل الموعد.</p>''',
      foot='<button class="btn wide" data-go="next">ادفع من المحفظة</button>')
    s3 = pg('تذكرتك', f'''
      <div class="ticket"><div class="tk-top"><b>بازار الحي</b><span>اليوم ٥ م · حديقة الشاطئ</span></div>
        <div class="tk-qr">{qr_svg(11)}</div>
        <div class="tk-code"><span>رمز الدخول</span><b>NL-7F3K</b></div>
        <div class="tk-foot"><span><span data-qty3>١</span> تذكرة · صالحة</span><span class="ok">مدفوعة</span></div></div>
      <div class="acts2"><button class="btn sm ghost">@@i-cal2@@ أضف إلى التقويم</button><button class="btn sm ghost">@@i-share2@@ شارك</button></div>
      <p class="fine">تجدها دائماً في ماي سبيس ← تذاكري. سيصلك تذكير قبل الموعد بساعة.</p>''',
      foot='<button class="btn wide" data-go="done">العودة إلى الخريطة</button>', close=True)
    return [s1, s2, s3]

def flow_view():
    s1 = f'''<div class="pg dark viewer"><img class="full" src="@@p16@@" alt="">
      <div class="v-top"><button class="ib w" data-go="back" aria-label="إغلاق">@@i-xw@@</button><div class="who"><img src="@@avatar@@" alt=""><div class="b"><b>فهد الغامدي</b><span>@@i-pin2@@ الكورنيش · قبل ١٢ دقيقة</span></div></div></div>
      <div class="v-bottom"><p class="cap">غروب اليوم من الكورنيش 🌅 مين جرّب عدسة ٣٥ مم بالليل؟</p>
        <div class="v-acts"><button data-like>@@i-heart2@@<span data-likes>٢٤</span></button><button data-comment>@@i-cmt2@@<span data-cmts>٣</span></button><button>@@i-share2@@<span>شارك</span></button><button data-go="back">@@i-pin2@@<span>على الخريطة</span></button></div>
        <div class="comments" data-comments hidden><div class="c"><img src="@@p26@@" alt=""><span><b>سارة</b> الإضاءة خرافية 😍</span></div><div class="c"><img src="@@p119@@" alt=""><span><b>عبدالله</b> وين بالضبط؟</span></div></div>
        <div class="composer" data-composer hidden><input placeholder="اكتب تعليقاً…" data-cinput><button class="send" data-csend aria-label="إرسال">@@i-send@@</button></div>
      </div></div>'''
    return [s1]

def flow_order():
    s1 = pg('كاميرا فوجي X-T20', f'''
      <div class="gallery"><img class="big" src="@@p250@@" alt=""><div class="thumbs"><img src="@@p250@@" alt=""><img src="@@p60@@" alt=""><img src="@@p26@@" alt=""></div></div>
      <div class="price-row"><b>2,650 <small>ر.س</small></b><span class="pill">مستعمل · حالة ممتازة</span></div>
      <p class="txt">مع عدسة ١٨-٥٥ وبطاريتين وحقيبة. عدّاد الغالق ٤٬٢٠٠. السبب: ترقية. المعاينة ممكنة في الحمراء.</p>
      {seller('p119', 'عبدالله ر.', '@@i-star@@ ٤.٨ · ١٢ عملية مكتملة · يرد خلال دقائق')}
      <div class="opts" data-opts><button class="opt on" data-opt="pickup">@@i-store2@@<div class="b"><span class="t">استلام من الحمراء</span><span class="d">١.٤ كم · اتفقا على الوقت في المحادثة</span></div><b>مجاني</b></button>
        <button class="opt" data-opt="courier">@@i-truck@@<div class="b"><span class="t">توصيل بمندوب</span><span class="d">خلال ٣ ساعات · يتابعه التطبيق</span></div><b>٢٠ ر.س</b></button></div>''',
      foot='<button class="btn wide" data-go="next">اطلب · <span data-ototal>2,650</span> ر.س</button>')
    s2 = pg('تأكيد الطلب', f'''
      {kv([('السلعة', 'كاميرا فوجي X-T20'), ('الاستلام', '<span data-oway>استلام من الحمراء · مجاني</span>'), ('الإجمالي', '<span data-ototal2>2,650</span> ر.س', True)])}
      {wallet_line('<span data-oafter>-310</span>')}
      <div class="escrow">@@i-lock@@<div class="b"><span class="t">المبلغ يُحجز في المحفظة</span><span class="d">لا يصل للبائع إلا بعد تأكيدك الاستلام برمز الاستلام. خلاف؟ الدعم يتوسّط.</span></div></div>
      <p class="fine" data-short hidden>رصيدك لا يكفي: اشحن ٣١٠ ر.س عبر ميسر ثم أكمل، أو اختر الاستلام الذاتي.</p>''',
      foot='<button class="btn wide" data-go="next" data-paybtn>احجز المبلغ وأكّد الطلب</button>')
    s3 = pg('طلبك #١٠٤٨', f'''
      {done_block('تم تأكيد طلبك', 'أُبلغ عبدالله الآن، والمبلغ محجوز لديك حتى الاستلام')}
      <div class="tl"><div class="st on"><i></i><span>مؤكّد</span></div><div class="st"><i></i><span>البائع يجهّز</span></div><div class="st"><i></i><span>في الطريق / جاهز</span></div><div class="st"><i></i><span>تم الاستلام</span></div></div>
      <div class="codebox"><span>رمز الاستلام · أعطه للبائع عند التسلّم</span><b>٤٨٢١</b></div>
      <div class="acts2"><button class="btn sm ghost">مراسلة عبدالله</button><button class="btn sm ghost">طلباتي</button></div>''',
      foot='<button class="btn wide" data-go="done">العودة إلى الخريطة</button>', close=True)
    return [s1, s2, s3]

def flow_apply():
    s1 = pg('باريستا · ثري بروز', f'''
      <div class="meta"><img class="lg" src="@@3brews@@" alt=""><div class="b"><span class="t">ثري بروز <small>· مقهى مختص</small></span><span class="d">@@i-pin2@@ الحمراء · ٢.١ كم &nbsp; @@i-clock2@@ دوام جزئي مسائي</span></div></div>
      <div class="facts"><div><b>٤٬٥٠٠</b><small>ر.س شهرياً</small></div><div><b>٥</b><small>أيام أسبوعياً</small></div><div><b>٨٧٪</b><small>يطابق ملفك</small></div></div>
      <div class="match"><span class="t">لماذا يطابقك</span><div class="chips"><span class="ch on">خبرة قهوة مختصة</span><span class="ch on">الحمراء قريبة</span><span class="ch on">متاح مساءً</span><span class="ch">لاتيه آرت</span></div></div>
      <p class="txt">نبحث عن باريستا يحب الضيافة لفرعنا في الحمراء، ٦ ساعات مساءً. تدريب أسبوعين مدفوع.</p>
      <div class="note">@@i-lock@@ هويتك مخفية عن الدائرة حتى تجيب على أسئلة الفرز، ثم تُكشف تلقائياً.</div>''',
      foot='<button class="btn wide" data-go="next">قدّم الآن</button>')
    s2 = pg('أسئلة الفرز', f'''
      <div class="q"><span class="t">١ · هل لديك خبرة في القهوة المختصة؟</span><div class="chips" data-q="1"><button class="ch">نعم، أكثر من سنة</button><button class="ch">أقل من سنة</button><button class="ch">لا</button></div></div>
      <div class="q"><span class="t">٢ · متاح للدوام المسائي من ٤ إلى ١٠؟</span><div class="chips" data-q="2"><button class="ch">نعم</button><button class="ch">أحياناً</button><button class="ch">لا</button></div></div>
      <div class="q"><span class="t">٣ · متى تستطيع البدء؟</span><input class="inp" placeholder="مثلاً: الأسبوع القادم" data-q3></div>
      <p class="fine">إجاباتك تذهب لمدير التوظيف فقط مع ملف التوظيف الخاص بك، لا ملفك العام.</p>''',
      foot='<button class="btn wide" data-go="next" data-submit disabled>أرسل الإجابات</button>', sub='٣ أسئلة · دقيقة واحدة')
    s3 = pg('تم التقديم', f'''
      {done_block('وصل طلبك إلى ثري بروز', 'كُشفت هويتك لمدير التوظيف، وستصلك الإجابة في «الطلبات» بالمحادثات')}
      <div class="reqcard"><img src="@@3brews@@" alt=""><div class="b"><span class="t">باريستا · ثري بروز</span><span class="d">قُدّم الآن · بانتظار المراجعة · يُحدَّث هنا</span></div><span class="pill">جديد</span></div>
      <div class="acts2"><button class="btn sm ghost">افتح المحادثات</button><button class="btn sm ghost">عروض التوظيف</button></div>''',
      foot='<button class="btn wide" data-go="done">العودة إلى الخريطة</button>', close=True)
    return [s1, s2, s3]

def flow_redeem():
    s1 = pg('خصم ٢٠٪ على اللاتيه', f'''
      <div class="hero"><img src="@@p63@@" alt=""><span class="tag">عرض · ينتهي الليلة</span></div>
      <div class="meta"><img class="lg" src="@@overdose@@" alt=""><div class="b"><span class="t">أوفردوز <small>· مقهى مختص</small></span><span class="d">@@i-pin2@@ الروضة · ٦٥٠ م &nbsp; @@i-clock2@@ حتى ١١:٥٩ م</span></div></div>
      <div class="member" data-member><span class="chk-sm">@@i-check@@</span><div class="b"><span class="t">أنت عضو في دائرة أوفردوز</span><span class="d">العرض للأعضاء · مرة واحدة لكل عضو</span></div></div>
      {kv([('الخصم', '٢٠٪ على أي لاتيه'), ('الشرط', 'للأعضاء · في الفرع'), ('يُستخدم', 'مرة واحدة · حتى الليلة')])}
      <p class="txt">كيف يعمل: المس «استخدم الآن» أمام الكاشير فيظهر رمز لعشر دقائق، والكاشير يمسحه أو يكتبه.</p>''',
      foot='<button class="btn wide" data-go="next">استخدم الآن</button>')
    s2 = pg('رمز الاستخدام', f'''
      <div class="ticket redeem"><div class="tk-top"><b>خصم ٢٠٪ على اللاتيه</b><span>أوفردوز · الروضة</span></div>
        <div class="tk-qr">{qr_svg(23)}</div>
        <div class="tk-code"><span>أو اكتب الرمز</span><b>LATTE-20</b></div>
        <div class="tk-foot"><span>@@i-clock2@@ ينتهي خلال <b data-count>١٠:٠٠</b></span><span class="ok">جاهز</span></div></div>
      <p class="fine">أظهر الشاشة للكاشير. إن انتهى الوقت أعد المحاولة بلا خسارة.</p>''',
      foot='<button class="btn wide" data-go="next">الكاشير أكّد · تم الاستخدام</button>', sub='أظهره للكاشير')
    s3 = pg('تم', f'''
      {done_block('استخدمت العرض', 'وفّرت ٤ ر.س على اللاتيه · سُجّل في عروضي')}
      <div class="loyal"><span class="t">ولاء أوفردوز</span><div class="bar"><i style="width:80%"></i></div><span class="d">٤ من ٥ فناجين · الفنجان القادم مجاني</span></div>
      <div class="acts2"><button class="btn sm ghost">@@i-star@@ قيّم أوفردوز</button><button class="btn sm ghost">عروضي</button></div>''',
      foot='<button class="btn wide" data-go="done">العودة إلى الخريطة</button>', close=True)
    return [s1, s2, s3]

FLOWS = {'تذكرة': ('ticket', flow_ticket()), 'شاهد': ('view', flow_view()), 'اطلب': ('order', flow_order()), 'قدّم': ('apply', flow_apply()), 'استخدم': ('redeem', flow_redeem())}
FLOW_META = [
  ('ticket', 'تذكرة', 'فعالية: بازار الحي', ['تفاصيل الفعالية وعدد التذاكر', 'تأكيد الدفع من المحفظة', 'التذكرة برمز QR'], 'محجوز'),
  ('view', 'شاهد', 'لحظة: فهد على الكورنيش', ['العارض بملء الشاشة: إعجاب، تعليق، مشاركة، الموقع'], 'شوهد'),
  ('order', 'اطلب', 'سوق: كاميرا فوجي', ['السلعة والبائع وطريقة الاستلام', 'تأكيد الطلب وحجز المبلغ', 'الطلب بمراحله ورمز الاستلام'], 'مطلوب'),
  ('apply', 'قدّم', 'وظيفة: باريستا في ثري بروز', ['الوظيفة ولماذا تطابقك', 'أسئلة الفرز الثلاثة', 'تم التقديم وبطاقة الطلب'], 'قدّمت'),
  ('redeem', 'استخدم', 'عرض: خصم ٢٠٪ في أوفردوز', ['العرض وشرط العضوية', 'رمز الاستخدام بعدّاد', 'تم، ووفّرت، وولاؤك'], 'مستخدَم'),
]

def phone():
    it = ITEMS[0]
    home = f'''<div class="map onemap"><div class="cam" data-cam>{MAP}{PINS}</div>{search()}
      <div class="deck" data-deck>
        <div class="cnt"><button class="arr" data-prev aria-label="السابق">@@i-right@@</button><span data-cnt>١ من ٧ · الأقرب أولاً</span><button class="arr" data-next aria-label="التالي">@@i-left@@</button></div>
        {card_html(it)}
      </div></div>
      <div class="stack" data-stack></div>'''
    return screen('home', home, nav_pill('home'), 'abs')

TEMPLATES = ''.join(f'<template data-flow="{key}" data-step="{i}">{s}</template>' for name, (key, steps) in FLOWS.items() for i, s in enumerate(steps))

CSS5 = r'''
.stack{position:absolute;inset:0;pointer-events:none;z-index:8}
.pg{position:absolute;inset:0;background:#fff;color:#111;display:flex;flex-direction:column;transform:translateX(-100%);transition:transform .32s cubic-bezier(.2,.8,.2,1);pointer-events:auto;font-family:var(--font-body)}
.pg.in{transform:none}
.pg.dark{background:#111;color:#fff}
.pg .phd{display:flex;align-items:center;gap:8px;padding:10px 12px 6px;flex:none}
.pg .phd .ttl{font:800 18px var(--font-display);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;flex-grow:1}
.pg .phd .sub2{font-size:11.5px;color:#6B7280;flex:none}
.ib.w{background:rgba(17,17,17,.5);color:#fff}
.pg .body{flex:1 1 auto;min-height:0;overflow-y:auto;display:flex;flex-direction:column;gap:12px;padding:4px 16px 16px;scrollbar-width:none}
.pg .body::-webkit-scrollbar{display:none}
.pg .foot{flex:none;padding:10px 16px 16px;border-top:1px solid #F2F2F7;background:#fff;display:flex;gap:8px}
.btn.wide{flex:1;height:48px;font-size:15px;border-radius:14px}
.btn.wide:disabled{opacity:.45;cursor:not-allowed}
.hero{position:relative;height:160px;border-radius:16px;overflow:hidden;flex:none}
.hero img{width:100%;height:100%;object-fit:cover;display:block}
.hero .tag{position:absolute;top:10px;right:10px;background:rgba(255,255,255,.95);color:#111;font-size:11.5px;font-weight:700;padding:4px 9px;border-radius:999px}
.meta{display:flex;align-items:center;gap:10px}
.meta .lg{width:44px;height:44px;border-radius:12px;object-fit:cover}
.meta .b{display:flex;flex-direction:column;gap:2px;min-width:0}
.meta .t{font-size:15px;font-weight:800}.meta .t small{font-weight:500;color:#6B7280}
.meta .d{font-size:12px;color:#374151;display:flex;align-items:center;gap:4px;flex-wrap:wrap}
.facts{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px}
.facts div{border:1px solid #E5E5EA;border-radius:12px;padding:8px;display:flex;flex-direction:column;align-items:center;gap:1px}
.facts b{font:800 18px var(--font-display);color:var(--a)}.facts small{font-size:11px;color:#6B7280}
.going{display:flex;align-items:center;gap:8px;font-size:12.5px;color:#374151}
.going .pile{display:inline-flex}.going .pile img{width:24px;height:24px;border-radius:999px;border:2px solid #fff;object-fit:cover;margin-left:-8px}.going .pile img:first-child{margin-left:0}
.txt{margin:0;font-size:13.5px;line-height:1.65;color:#374151}
.opt-row{display:flex;justify-content:space-between;align-items:center;font-size:14px;font-weight:600}
.stepper{display:inline-flex;align-items:center;gap:12px;border:1px solid #E5E5EA;border-radius:999px;padding:3px}
.stepper button{width:30px;height:30px;border-radius:999px;border:0;background:#F2F2F7;color:#111;display:inline-flex;align-items:center;justify-content:center;cursor:pointer}
.stepper b{min-width:14px;text-align:center;font-size:15px}
.kv{display:flex;flex-direction:column;border:1px solid #E5E5EA;border-radius:14px;overflow:hidden}
.kv .row{display:flex;justify-content:space-between;align-items:center;padding:10px 12px;border-bottom:1px solid #F2F2F7;font-size:13.5px}
.kv .row span{color:#6B7280}.kv .row:last-child{border-bottom:0}
.kv .row.tot{background:#F9FAFB}.kv .row.tot b{font-size:15px;color:var(--a)}
.wline{display:flex;align-items:center;gap:10px;border-radius:14px;background:var(--a-soft);color:var(--a-ink);padding:10px 12px}
.wline .b{flex-grow:1;display:flex;flex-direction:column;gap:1px}.wline .t{font-size:13.5px;font-weight:700}.wline .d{font-size:11.5px}
.wline .lnk{color:var(--a);font-weight:700;font-size:13px;text-decoration:none}
.fine{margin:0;font-size:11.5px;color:#6B7280;line-height:1.6;display:flex;gap:5px;align-items:flex-start}
.ticket{border-radius:18px;background:#fff;border:1.5px solid #E5E5EA;overflow:hidden;display:flex;flex-direction:column;align-items:center;gap:8px;padding-bottom:12px;position:relative}
.ticket::before,.ticket::after{content:"";position:absolute;top:118px;width:18px;height:18px;border-radius:999px;background:#fff;border:1.5px solid #E5E5EA}
.ticket::before{right:-10px}.ticket::after{left:-10px}
.tk-top{width:100%;background:var(--a);color:#fff;padding:12px 14px;display:flex;flex-direction:column;gap:2px;box-sizing:border-box}
.tk-top b{font:800 17px var(--font-display)}.tk-top span{font-size:12px;opacity:.9}
.tk-qr{margin-top:10px}
.tk-code{display:flex;flex-direction:column;align-items:center;gap:2px}.tk-code span{font-size:11px;color:#6B7280}.tk-code b{font:800 22px var(--font-body);letter-spacing:2px}
.tk-foot{width:100%;display:flex;justify-content:space-between;padding:0 14px;box-sizing:border-box;font-size:12.5px;color:#374151;align-items:center}
.ok{background:#DCFCE7;color:#166534;font-weight:700;padding:3px 9px;border-radius:999px;font-size:11.5px}
.acts2{display:flex;gap:8px;flex-wrap:wrap}
.done{display:flex;flex-direction:column;align-items:center;gap:6px;text-align:center;padding:10px 0 4px}
.done .chk{width:64px;height:64px;border-radius:999px;background:var(--a);color:#fff;display:inline-flex;align-items:center;justify-content:center}
.done b{font:800 20px var(--font-display)}.done span{font-size:13px;color:#6B7280;line-height:1.5;max-width:30ch}
.chk-sm{width:26px;height:26px;border-radius:999px;background:#DCFCE7;color:#166534;display:inline-flex;align-items:center;justify-content:center;flex:none}
.chk-sm svg{width:16px;height:16px}
.seller{display:flex;align-items:center;gap:10px;border:1px solid #E5E5EA;border-radius:14px;padding:8px 10px}
.seller img{width:42px;height:42px;border-radius:999px;object-fit:cover}
.seller .b{flex-grow:1;display:flex;flex-direction:column;gap:1px;min-width:0}.seller .t{font-size:14px;font-weight:700}.seller .d{font-size:11.5px;color:#6B7280;display:flex;align-items:center;gap:3px}
.gallery{display:flex;flex-direction:column;gap:6px}
.gallery .big{width:100%;height:190px;object-fit:cover;border-radius:16px}
.gallery .thumbs{display:flex;gap:6px}.gallery .thumbs img{width:56px;height:56px;border-radius:10px;object-fit:cover;border:1.5px solid #E5E5EA}
.price-row{display:flex;justify-content:space-between;align-items:center}
.price-row b{font:800 24px var(--font-display);color:#111}.price-row b small{font:600 13px var(--font-body);color:#6B7280}
.pill{background:#F2F2F7;color:#374151;font-size:11.5px;font-weight:600;padding:4px 9px;border-radius:999px}
.opts{display:flex;flex-direction:column;gap:8px}
.opt{display:flex;align-items:center;gap:10px;border:1.5px solid #E5E5EA;border-radius:14px;padding:10px;background:#fff;text-align:right;cursor:pointer;font-family:var(--font-body);color:#111}
.opt.on{border-color:var(--a);background:var(--a-soft)}
.opt .b{flex-grow:1;display:flex;flex-direction:column;gap:1px;min-width:0}.opt .t{font-size:13.5px;font-weight:700}.opt .d{font-size:11.5px;color:#6B7280}
.opt>b{font-size:13px;color:var(--a)}
.escrow{display:flex;gap:10px;align-items:flex-start;border:1px solid #E5E5EA;border-radius:14px;padding:10px 12px}
.escrow .b{display:flex;flex-direction:column;gap:2px}.escrow .t{font-size:13.5px;font-weight:700}.escrow .d{font-size:11.5px;color:#6B7280;line-height:1.5}
.tl{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:4px;position:relative;padding-top:4px}
.tl::before{content:"";position:absolute;top:13px;right:12%;left:12%;height:2px;background:#E5E7EB}
.tl .st{display:flex;flex-direction:column;align-items:center;gap:6px;font-size:10.5px;color:#6B7280;text-align:center;position:relative}
.tl .st i{width:20px;height:20px;border-radius:999px;background:#fff;border:2px solid #E5E7EB;box-sizing:border-box}
.tl .st.on i{background:var(--a);border-color:var(--a)}.tl .st.on{color:var(--a);font-weight:700}
.codebox{display:flex;flex-direction:column;align-items:center;gap:4px;border:1.5px dashed #C7C7CC;border-radius:14px;padding:12px}
.codebox span{font-size:11.5px;color:#6B7280}.codebox b{font:800 30px var(--font-body);letter-spacing:6px;color:#111}
.match .t{font-size:13px;font-weight:700;display:block;margin-bottom:6px}
.chips{display:flex;flex-wrap:wrap;gap:6px}
.chips .ch{height:32px;padding:0 12px;border-radius:999px;border:1.5px solid #E5E5EA;background:#fff;color:#374151;font:600 12.5px var(--font-body);cursor:pointer;display:inline-flex;align-items:center;gap:4px}
.chips .ch.on{background:var(--a-soft);border-color:var(--a);color:var(--a-ink)}
.note{display:flex;gap:6px;align-items:flex-start;font-size:12px;color:#5A4200;background:#FFF4D6;border-radius:12px;padding:9px 11px;line-height:1.5}
.q{display:flex;flex-direction:column;gap:8px}.q .t{font-size:14px;font-weight:700}
.inp{height:42px;border:1.5px solid #E5E5EA;border-radius:12px;padding:0 12px;font:500 13.5px var(--font-body);width:100%;box-sizing:border-box}
.inp:focus{outline:2px solid var(--a);border-color:transparent}
.reqcard{display:flex;align-items:center;gap:10px;border:1.5px solid var(--a-soft);background:var(--a-soft);border-radius:14px;padding:10px}
.reqcard img{width:40px;height:40px;border-radius:10px;object-fit:cover}
.reqcard .b{flex-grow:1;display:flex;flex-direction:column;gap:1px;min-width:0}.reqcard .t{font-size:13.5px;font-weight:700;color:var(--a-ink)}.reqcard .d{font-size:11.5px;color:#374151}
.member{display:flex;align-items:center;gap:10px;border:1px solid #BBF7D0;background:#F0FDF4;border-radius:14px;padding:9px 11px}
.member .b{display:flex;flex-direction:column;gap:1px}.member .t{font-size:13.5px;font-weight:700;color:#14532D}.member .d{font-size:11.5px;color:#166534}
.loyal{display:flex;flex-direction:column;gap:6px;border:1px solid #E5E5EA;border-radius:14px;padding:10px 12px}
.loyal .t{font-size:13px;font-weight:700}.loyal .d{font-size:11.5px;color:#6B7280}
.loyal .bar{height:8px;border-radius:999px;background:#F2F2F7;overflow:hidden}.loyal .bar i{display:block;height:100%;background:var(--a);border-radius:999px}
/* العارض */
.viewer .full{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}
.v-top{position:absolute;top:10px;right:12px;left:12px;display:flex;align-items:center;gap:10px}
.v-top .who{display:flex;align-items:center;gap:8px}.v-top .who img{width:36px;height:36px;border-radius:999px;border:2px solid #fff;object-fit:cover}
.v-top .who .b{display:flex;flex-direction:column;gap:1px;color:#fff;text-shadow:0 1px 6px rgba(0,0,0,.5)}.v-top .who b{font-size:14px}.v-top .who span{font-size:11.5px;display:flex;align-items:center;gap:3px}
.v-bottom{position:absolute;right:0;left:0;bottom:0;padding:40px 16px 92px;background:linear-gradient(transparent,rgba(0,0,0,.75));display:flex;flex-direction:column;gap:10px}
.cap{margin:0;color:#fff;font-size:14px;line-height:1.5}
.v-acts{display:flex;gap:6px}
.v-acts button{flex:1;height:44px;border:0;border-radius:12px;background:rgba(255,255,255,.14);color:#fff;display:inline-flex;flex-direction:column;align-items:center;justify-content:center;gap:1px;font:600 10.5px var(--font-body);cursor:pointer;backdrop-filter:blur(6px)}
.v-acts button.on{color:#FF5A6E}
.comments{display:flex;flex-direction:column;gap:6px}
.comments .c{display:flex;align-items:center;gap:8px;color:#fff;font-size:12.5px}.comments .c img{width:24px;height:24px;border-radius:999px;object-fit:cover}
.composer{display:flex;gap:6px;align-items:center}
.composer input{flex:1;height:40px;border-radius:999px;border:0;padding:0 14px;font:500 13px var(--font-body);background:rgba(255,255,255,.95)}
.composer .send{width:40px;height:40px;border-radius:999px;border:0;background:var(--a);color:#fff;display:inline-flex;align-items:center;justify-content:center;cursor:pointer;transform:scaleX(-1)}
/* وسم «تم» على البطاقة */
.dcard .donetag{position:absolute;top:6px;right:6px;background:#DCFCE7;color:#166534;font-size:10.5px;font-weight:800;padding:3px 8px;border-radius:999px;box-shadow:0 1px 4px rgba(0,0,0,.2);z-index:2}
/* دليل الرحلات في الصفحة */
.guide{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:10px}
.g{border:1px solid var(--line);border-radius:14px;padding:12px 14px;display:flex;flex-direction:column;gap:8px;background:var(--card)}
.g .h{display:flex;align-items:center;justify-content:space-between;gap:8px}
.g .h b{font:800 16px var(--font-display);display:flex;align-items:center;gap:8px}
.g .h b i{width:26px;height:26px;border-radius:999px;background:var(--a);color:#fff;display:inline-flex;align-items:center;justify-content:center;font-style:normal;font-size:12px;font-weight:700}
.g .h small{color:var(--muted);font-size:12.5px}
.g .steps{display:flex;flex-direction:column;gap:4px}
.g .steps button{display:flex;align-items:center;gap:8px;border:0;background:transparent;color:var(--fg);font:500 13px var(--font-body);text-align:right;cursor:pointer;padding:5px 6px;border-radius:8px}
.g .steps button:hover{background:var(--a-soft)}
.g .steps button i{width:20px;height:20px;border-radius:999px;border:1.5px solid var(--a);color:var(--a);display:inline-flex;align-items:center;justify-content:center;font-style:normal;font-size:11px;font-weight:700;flex:none}
.g .end{font-size:12px;color:var(--muted)}
.g .end b{color:#166534;background:#DCFCE7;padding:2px 7px;border-radius:999px;font-size:11px}
.layout{display:flex;gap:26px;flex-wrap:wrap;align-items:flex-start;justify-content:center}
.layout .slot{width:min(390px,100%)}
.layout .side{flex:1 1 420px;max-width:760px;display:flex;flex-direction:column;gap:12px}
'''

DATA = {'items': ITEMS, 'pos': POS, 'me': ME, 'flows': {name: key for name, (key, _) in FLOWS.items()}, 'ends': {m[0]: m[4] for m in FLOW_META}}

JS = r'''
(function(){
  var D = __DATA__;
  var AR = '٠١٢٣٤٥٦٧٨٩'; function ar(n){ return String(n).replace(/\d/g, function(d){ return AR[+d]; }); }
  var root = document.querySelector('[data-concept=flows]');
  var map = root.querySelector('.map'), cam = root.querySelector('[data-cam]'), card = root.querySelector('[data-dcard]'), stack = root.querySelector('[data-stack]');
  var items = D.items, i = 0, srcs = {}, done = {};
  root.querySelectorAll('.pin img,.plabel img').forEach(function(im){ srcs[im.parentNode.getAttribute('data-id')] = im.src; });

  // ---- البطاقة على الخريطة (كما في نظام «واحد»)
  function focus(pin){
    var W = map.clientWidth, H = map.clientHeight, p = D.pos[pin], S = 1.5; if (!W || !H) return;
    var px = W - W*p[0]/100, py = H*p[1]/100, cx = W/2, cy = H/2;
    cam.style.transform = 'translate('+(W/2 - cx - (px - cx)*S)+'px,'+(H*0.42 - cy - (py - cy)*S)+'px) scale('+S+')';
    root.querySelectorAll('.pin,.plabel').forEach(function(e){ var on = e.getAttribute('data-id')===pin; e.classList.toggle('hi', on); e.classList.toggle('dim', !on); });
  }
  function fill(){
    var it = items[i];
    root.querySelector('[data-okind]').textContent = it.kind + ' · ' + it.who;
    root.querySelector('[data-odist]').textContent = it.dist; root.querySelector('[data-ot]').textContent = it.t; root.querySelector('[data-od]').textContent = it.d; root.querySelector('[data-oact]').textContent = it.act;
    root.querySelector('[data-oimg]').src = ASSETS[it.img] || root.querySelector('[data-oimg]').src;
    root.querySelector('[data-ologo]').src = ASSETS[it.logo] || srcs[it.pin] || root.querySelector('[data-ologo]').src;
    root.querySelector('[data-cnt]').textContent = ar(i+1) + ' من ' + ar(items.length) + ' · الأقرب أولاً';
    var tag = card.querySelector('.donetag'); if (tag) tag.remove();
    if (done[i]) { var t = document.createElement('span'); t.className = 'donetag'; t.textContent = '✓ ' + done[i]; card.appendChild(t); }
    focus(it.pin);
  }
  var busy = false;
  function goTo(j, dir){
    if (busy) return; busy = true; j = (j + items.length) % items.length;
    card.classList.remove('drag'); card.style.transform = ''; card.classList.add(dir < 0 ? 'outl' : 'outr');
    setTimeout(function(){ i = j; fill(); card.classList.remove('outl', 'outr'); card.classList.add('drag'); card.classList.add(dir < 0 ? 'inr' : 'inl'); void card.offsetWidth; card.classList.remove('drag');
      requestAnimationFrame(function(){ card.classList.remove('inl', 'inr'); setTimeout(function(){ busy = false; }, 320); }); }, 300);
  }
  root.querySelector('[data-next]').addEventListener('click', function(){ goTo(i+1, -1); });
  root.querySelector('[data-prev]').addEventListener('click', function(){ goTo(i-1, 1); });
  var sx = null, dx = 0;
  card.addEventListener('pointerdown', function(e){ if (e.target.closest('button')) return; sx = e.clientX; dx = 0; card.classList.add('drag'); card.setPointerCapture(e.pointerId); });
  card.addEventListener('pointermove', function(e){ if (sx===null) return; dx = e.clientX - sx; card.style.transform = 'translateX('+dx+'px) rotate('+(dx/40)+'deg)'; });
  function up(){ if (sx===null) return; sx = null; card.classList.remove('drag'); if (Math.abs(dx) > 60) goTo(dx < 0 ? i+1 : i-1, dx < 0 ? -1 : 1); else card.style.transform = ''; }
  card.addEventListener('pointerup', up); card.addEventListener('pointercancel', up);
  root.querySelectorAll('.pin,.plabel').forEach(function(p){ p.addEventListener('click', function(){ var id = p.getAttribute('data-id'); var j = -1; items.forEach(function(it, k){ if (it.pin===id && j<0) j = k; }); if (j >= 0 && j !== i) goTo(j, j > i ? -1 : 1); }); });
  fill(); window.addEventListener('resize', fill); setTimeout(fill, 350);

  // ---- محرّك الشاشات: دفع وإرجاع فوق الخريطة
  var open = null, step = 0, timers = [];
  function tpl(flow, s){ var t = document.querySelector('template[data-flow="'+flow+'"][data-step="'+s+'"]'); return t ? t.innerHTML : null; }
  function push(flow, s){
    var html = tpl(flow, s); if (!html) return;
    var wrap = document.createElement('div'); wrap.innerHTML = html; var el = wrap.firstElementChild; el.setAttribute('data-step', s);
    stack.appendChild(el); void el.offsetWidth; el.classList.add('in');
    wire(flow, s, el); open = flow; step = s;
  }
  function pop(){ var pages = stack.querySelectorAll('.pg'); var el = pages[pages.length - 1]; if (!el) return; el.classList.remove('in'); setTimeout(function(){ el.remove(); }, 320); step = Math.max(0, step - 1); if (!pages.length || pages.length === 1) open = null; }
  function closeAll(mark){
    timers.forEach(clearInterval); timers = [];
    if (mark && open) { done[i] = D.ends[open]; }
    stack.querySelectorAll('.pg').forEach(function(el){ el.classList.remove('in'); setTimeout(function(){ el.remove(); }, 320); });
    open = null; step = 0; fill();
  }
  stack.addEventListener('click', function(e){
    var b = e.target.closest('[data-go]'); if (!b) return;
    var g = b.getAttribute('data-go');
    if (g === 'back') pop(); else if (g === 'next') push(open, step + 1); else if (g === 'done') closeAll(true);
  });
  root.querySelector('[data-oact]').addEventListener('click', function(){ var it = items[i]; var flow = D.flows[it.act]; if (flow) push(flow, 0); });
  // الدليل: فتح رحلة من خطوة معيّنة
  document.querySelectorAll('[data-open-flow]').forEach(function(b){ b.addEventListener('click', function(){
    var flow = b.getAttribute('data-open-flow'), s = +b.getAttribute('data-open-step');
    var j = -1; items.forEach(function(it, k){ if (D.flows[it.act] === flow && j < 0) j = k; });
    closeAll(false); if (j >= 0) { i = j; fill(); }
    for (var q = 0; q <= s; q++) push(flow, q);
    if (window.innerWidth <= 1250) window.scrollTo({top:0, behavior:'smooth'});
  }); });

  // ---- التفاعلات الصغيرة داخل الشاشات
  var qty = 1, way = 'pickup';
  function wire(flow, s, el){
    if (flow === 'ticket' && s === 0) { qty = 1; el.querySelectorAll('[data-step]').forEach(function(b){ b.addEventListener('click', function(){ qty = Math.min(4, Math.max(1, qty + (+b.getAttribute('data-step')))); el.querySelector('[data-qty]').textContent = ar(qty); el.querySelector('[data-total]').textContent = ar(qty * 15); }); }); }
    if (flow === 'ticket' && s === 1) { el.querySelector('[data-qty2]').textContent = ar(qty); el.querySelector('[data-total2]').textContent = ar(qty * 15); el.querySelector('[data-after]').textContent = (2340 - qty * 15).toLocaleString('en-US'); }
    if (flow === 'ticket' && s === 2) { el.querySelector('[data-qty3]').textContent = ar(qty); }
    if (flow === 'view') {
      var liked = false, likes = 24, cm = 3;
      el.querySelector('[data-like]').addEventListener('click', function(){ liked = !liked; likes += liked ? 1 : -1; el.querySelector('[data-likes]').textContent = ar(likes); el.querySelector('[data-like]').classList.toggle('on', liked); });
      el.querySelector('[data-comment]').addEventListener('click', function(){ var c = el.querySelector('[data-comments]'), p = el.querySelector('[data-composer]'); c.hidden = !c.hidden; p.hidden = c.hidden; if (!p.hidden) el.querySelector('[data-cinput]').focus(); });
      el.querySelector('[data-csend]').addEventListener('click', function(){ var inp = el.querySelector('[data-cinput]'); var v = inp.value.trim(); if (!v) return; var d = document.createElement('div'); d.className = 'c'; d.innerHTML = '<img src="' + ASSETS['avatar'] + '" alt=""><span><b>أنت</b> </span>'; d.querySelector('span').appendChild(document.createTextNode(v)); el.querySelector('[data-comments]').appendChild(d); inp.value = ''; cm += 1; el.querySelector('[data-cmts]').textContent = ar(cm); });
    }
    if (flow === 'order' && s === 0) { way = 'pickup'; el.querySelectorAll('[data-opt]').forEach(function(b){ b.addEventListener('click', function(){ way = b.getAttribute('data-opt'); el.querySelectorAll('[data-opt]').forEach(function(x){ x.classList.toggle('on', x===b); }); el.querySelector('[data-ototal]').textContent = way === 'courier' ? '2,670' : '2,650'; }); }); }
    if (flow === 'order' && s === 1) { var total = way === 'courier' ? 2670 : 2650; el.querySelector('[data-oway]').textContent = way === 'courier' ? 'توصيل بمندوب · ٢٠ ر.س' : 'استلام من الحمراء · مجاني'; el.querySelector('[data-ototal2]').textContent = total.toLocaleString('en-US'); var after = 2340 - total; el.querySelector('[data-oafter]').textContent = after.toLocaleString('en-US'); el.querySelector('[data-short]').hidden = after >= 0; var pb = el.querySelector('[data-paybtn]'); if (after < 0) { pb.textContent = 'اشحن ' + ar(-after) + ' ر.س ثم أكّد'; pb.addEventListener('click', function(){ /* في النموذج: الشحن ناجح فوراً */ }, {once:true}); } }
    if (flow === 'apply' && s === 1) {
      var ans = {}; var btn = el.querySelector('[data-submit]');
      function check(){ btn.disabled = !(ans[1] && ans[2] && el.querySelector('[data-q3]').value.trim()); }
      el.querySelectorAll('[data-q] .ch').forEach(function(c){ c.addEventListener('click', function(){ var q = c.parentNode.getAttribute('data-q'); ans[q] = c.textContent; c.parentNode.querySelectorAll('.ch').forEach(function(x){ x.classList.toggle('on', x===c); }); check(); }); });
      el.querySelector('[data-q3]').addEventListener('input', check);
    }
    if (flow === 'redeem' && s === 1) { var left = 600; var t = setInterval(function(){ left -= 1; if (left < 0) { clearInterval(t); return; } var m = Math.floor(left / 60), sec = left % 60; var n = el.querySelector('[data-count]'); if (n) n.textContent = ar((m < 10 ? '0' : '') + m + ':' + (sec < 10 ? '0' : '') + sec); }, 1000); timers.push(t); }
  }
})();
'''

if __name__ == '__main__':
    import base64
    assets = {}
    for key in {it['img'] for it in ITEMS} | {it['logo'] for it in ITEMS} | {'avatar'}:
        for ext, mime in (('.jpg', 'image/jpeg'), ('.png', 'image/png')):
            p = root / 'img' / (key + ext)
            if p.exists(): assets[key] = 'data:' + mime + ';base64,' + base64.b64encode(p.read_bytes()).decode()
    js = 'var ASSETS = ' + json.dumps(assets) + ';\n' + JS.replace('__DATA__', json.dumps(DATA, ensure_ascii=False))
    guide = ''.join(f'''<div class="g"><div class="h"><b><i>{n + 1}</i>{act}</b><small>{what}</small></div>
      <div class="steps">{''.join(f'<button data-open-flow="{key}" data-open-step="{k}"><i>{k + 1}</i>{t}</button>' for k, t in enumerate(steps))}</div>
      <span class="end">النهاية: العودة إلى الخريطة والبطاقة موسومة <b>✓ {end}</b></span></div>''' for n, (key, act, what, steps, end) in enumerate(FLOW_META))
    page = f'''<title>رحلات البطاقة</title>
<meta name="description" content="نموذج متكامل لنظام «واحد» في ناس لايف: زر البطاقة يفتح الرحلة كاملة لكل نوع: تذكرة، شاهد، اطلب، قدّم، استخدم، بكل شاشاتها حتى النهاية.">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Rubik:wght@400;500;600;700&family=Baloo+Bhaijaan+2:wght@600;700;800&display=swap">
<style>{CSS}{CSS3}{CSS4}{CSS5}</style>
<div class="wrap">
  <header>
    <h1>رحلات البطاقة: من الزر إلى النهاية</h1>
    <p class="sub">الهاتف يعمل بالكامل: اسحب البطاقات، والمس زر البطاقة فتُفتح رحلته فوق الخريطة شاشةً بعد شاشة حتى النهاية، ثم تعود إلى الخريطة والبطاقة موسومة بما أنجزت. خمس رحلات لخمسة أنواع: تذكرة الفعالية، مشاهدة اللحظة، طلب السلعة، التقديم على الوظيفة، واستخدام العرض. كل الرحلات تتبع القاعدة نفسها: شاشة تفاصيل واحدة، خطوة تأكيد واحدة إن كان هناك مال، ثم شاشة نتيجة واحدة. الدليل على اليسار يفتح أي خطوة مباشرة.</p>
  </header>
  <div class="layout">
    <section class="slot active" id="s-flows">
      <div class="phone"><div class="screen" data-concept="flows">{phone()}</div></div>
      <p class="note">الدفع كله من المحفظة الداخلية (الشحن عبر ميسر عند الحاجة). في السوق يُحجز المبلغ ولا يصل للبائع إلا بعد تأكيد الاستلام برمز الاستلام. في التوظيف تُكشف الهوية بعد أسئلة الفرز كما قرّرت. في العرض يظهر رمز لعشر دقائق ويؤكّده الكاشير. في نسخة iOS تُخفى المبالغ والمحفظة ويبقى ما عداها.</p>
    </section>
    <div class="side">
      <div class="guide">{guide}</div>
      <div class="reco"><b>ما يوحّد الرحلات الخمس</b><span>زر واحد على البطاقة بصيغة فعل، ثم على الأكثر ثلاث شاشات: تفاصيل، تأكيد، نتيجة. الرجوع دائماً في أعلى اليمين، والفعل الرئيسي دائماً زر عريض أسفل الشاشة، ولا قوائم ولا تبويبات داخل الرحلة. ما يحتاج مالاً يمرّ بشاشة تأكيد تُظهر رصيد المحفظة وما بعده، وما لا يحتاج مالاً يصل إلى النتيجة في خطوتين. النتيجة دائماً شيء يُحتفظ به: تذكرة، طلب برمز، بطاقة طلب توظيف، رمز استخدام.</span></div>
    </div>
  </div>
</div>
{TEMPLATES}
<script>{js}</script>
'''
    icons_path = root / 'icons.json'
    icons = json.loads(icons_path.read_text(encoding='utf-8'))
    icons.update(ICONS5)
    icons_path.write_text(json.dumps(icons, ensure_ascii=False, indent=1), encoding='utf-8')
    (root / 'template_flows.html').write_text(page, encoding='utf-8')
