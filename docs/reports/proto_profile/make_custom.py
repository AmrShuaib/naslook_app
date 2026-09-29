# يولّد template_custom.html: ثلاثة نماذج لتخصيص الرئيسية (إخفاء الأقسام وإعادة ترتيبها وشريط التنقّل)
# بحالة واحدة مشتركة بين الهواتف الثلاثة. البناء: python3 build.py template_custom.html > out.html
import json, pathlib
from make_main import (CSS, ICONS, MAP, PINS, PLACES, CIRCLES_MINE, moment_cards, place_rows, circle_rows, product_cards, offer_cards, JOBCARD, sec, root)

EXTRA_ICONS = {
 'i-more': '<svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><circle cx="5" cy="12" r="2"/><circle cx="12" cy="12" r="2"/><circle cx="19" cy="12" r="2"/></svg>',
 'i-grip': '<svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><circle cx="9" cy="6" r="1.6"/><circle cx="15" cy="6" r="1.6"/><circle cx="9" cy="12" r="1.6"/><circle cx="15" cy="12" r="1.6"/><circle cx="9" cy="18" r="1.6"/><circle cx="15" cy="18" r="1.6"/></svg>',
 'i-eye-off': '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 3l18 18"/><path d="M10.6 10.6a3 3 0 0 0 4.2 4.2"/><path d="M9.9 5.1A10 10 0 0 1 12 5c6 0 9.5 7 9.5 7a15 15 0 0 1-3.2 3.9"/><path d="M6.6 6.6A15 15 0 0 0 2.5 12s3.5 7 9.5 7a10 10 0 0 0 3.4-.6"/></svg>',
 'i-eye': '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/></svg>',
 'i-up': '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 19V5"/><path d="M6 11l6-6 6 6"/></svg>',
 'i-down': '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 5v14"/><path d="M6 13l6 6 6-6"/></svg>',
 'i-pinned': '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 17v5"/><path d="M8 3h8l-1 7 3 3H6l3-3z"/></svg>',
 'i-lock': '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/></svg>',
 'i-reset': '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12a9 9 0 1 0 3-6.7"/><path d="M3 4v5h5"/></svg>',
 'i-x': '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round"><path d="M6 6l12 12"/><path d="M18 6L6 18"/></svg>',
 'i-minus': '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3.5" stroke-linecap="round"><path d="M5 12h14"/></svg>',
 'i-tune': '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h10"/><path d="M18 7h2"/><circle cx="16" cy="7" r="2"/><path d="M4 17h4"/><path d="M12 17h8"/><circle cx="10" cy="17" r="2"/></svg>',
}

# ---------- الأقسام القابلة للتخصيص (المحتوى الحقيقي من نموذج «المدينة»)
QA = ''.join(f'<button><span class="ic">@@{ic}@@</span>{t}</button>' for ic,t in [('i-map','الخريطة'),('i-groups','الدوائر'),('i-bag','السوق'),('i-tag','العروض'),('i-job','الوظائف'),('i-cal','الفعاليات'),('i-ticket','التذاكر'),('i-blog','المدونة')])
BLOCKS = [
 ('quick', 'الاختصارات', 'i-hp', '٨ اختصارات', f'<div class="qa">{QA}</div>', ['إظهار ٤ فقط', 'ترتيب حسب الاستخدام']),
 ('offers', 'عروض اليوم', 'i-tag', '١٢ عرضاً قريباً', f'<div class="hs">{offer_cards()}</div>', ['مقاهٍ فقط', 'دوائري فقط', 'الأقرب أولاً']),
 ('near', 'دوائر قريبة منك', 'i-groups', 'الأقرب أولاً', place_rows(PLACES, 3, '<button class="btn sm soft">متابعة</button>'), ['مفتوح الآن فقط', 'خلال ٢ كم']),
 ('moments', 'لحظات حولك', 'i-cam', '٤٦ شخصاً · ١٢ لحظة', f'<div class="hs">{moment_cards(n=5)}</div>', ['الأصدقاء فقط', 'فيديو فقط', 'بلا صوت']),
 ('trend', 'الأماكن الرائجة اليوم', 'i-pin', '٧ أماكن', '<div class="hs">' + ''.join(f'<div class="pcard"><img src="@@{img}@@" alt="" style="width:44px;height:44px;border-radius:12px"><b>{n}</b><small>{meta}</small><small style="color:#111">{dist}</small></div>' for img,n,_,meta,dist in PLACES) + '</div>', []),
 ('jobs', 'وظائف جديدة', 'i-job', 'تطابق ملفك', f'<div style="padding:0 14px">{JOBCARD}</div>', ['المطابقة فوق ٨٠٪ فقط', 'دوام جزئي']),
 ('market', 'من السوق', 'i-bag', '٤ إعلانات', f'<div class="grid2" style="padding:0 14px">{product_cards(2)}</div>', ['فئاتي المفضلة', 'قريب مني']),
 ('events', 'فعاليات قريبة', 'i-cal', 'هذا الأسبوع', '<div class="hs">' + ''.join(f'<div class="ocard" style="width:170px;height:100px"><img src="@@{img}@@" alt=""><div class="ov"><b>{t}</b><span>{d}</span></div></div>' for img,t,d in [('s158','بازار الشاطئ','الجمعة ٥ م · الحديقة'),('p57','جولة البلد التاريخية','السبت ٦ م · مجاناً'),('p274','معرض تصوير الشارع','الأحد · التحلية')]) + '</div>', ['مجانية فقط']),
 ('circles', 'آخر ما في دوائرك', 'i-groups', '٣ منشورات جديدة', circle_rows(CIRCLES_MINE[:2], '<span class="badge">٣</span>'), []),
 ('people', 'أشخاص حولك الآن', 'i-me', '٤٦ ظاهرون', '<div class="hs" style="gap:12px">' + ''.join(f'<div class="ring{" new" if i<2 else ""}"><img src="@@{img}@@" alt=""><span>{n}</span></div>' for i,(img,n) in enumerate([('avatar','فهد'),('p26','سارة'),('p154','نورة'),('p119','عبدالله'),('p60','ريان'),('p37','منال')])) + '</div>', ['الأصدقاء فقط']),
 ('blog', 'جديد ناس لايف', 'i-blog', 'التحديثات والأخبار', '<div class="place"><span class="ic2" style="width:48px;height:48px;border-radius:12px;background:var(--a-soft);color:var(--a)">@@i-blog@@</span><div class="b"><span class="t">التوظيف وصل إلى الدوائر</span><span class="d">عرض وظيفي يصلك في الخاص إن طابق ملفك · قبل يومين</span></div>@@i-chev@@</div>', []),
]
TEMPLATES = ''.join(f'<template id="blk-{id}" data-title="{t}" data-icon="{ic}" data-meta="{m}" data-opts="{"|".join(opts)}">{body}</template>' for id,t,ic,m,body,opts in BLOCKS)
NAV_CANDIDATES = [('home','i-home','الرئيسية',True),('map','i-map','الخريطة',False),('circles','i-groups','الدوائر',False),('chats','i-chat','المحادثات',False),('me','i-me','ماي سبيس',True),('market','i-bag','السوق',False),('offers','i-tag','العروض',False),('jobs','i-job','الوظائف',False),('events','i-cal','الفعاليات',False)]

def phone(cid, body):
    return f'<div class="phone"><div class="screen" data-model="{cid}">{body}</div></div>'
TOPBAR = '<div class="tb"><div class="l"><button class="ib" aria-label="الإشعارات">@@i-bell@@<i class="dot"></i></button>%s</div><span class="ttl brand">ناس لايف</span><div class="r loc">@@i-pin@@ جدة · الشاطئ</div></div>'
SEARCH = '<div class="search">@@i-search@@ ابحث عن أشخاص ودوائر وأنشطة ومنتجات</div>'
NAVBAR = '<nav class="nav" data-navbar></nav>'

model1 = phone('inline', TOPBAR % '' + '<div class="scroll" style="gap:16px" data-home="inline">' + SEARCH + '<div data-blocks></div><div class="tray" data-tray hidden></div></div>' + NAVBAR + '<div class="pop" data-pop hidden></div>')
model2 = phone('editor', '''<div class="tb"><div class="l"><button class="btn sm">حفظ</button></div><span class="ttl">تخصيص الرئيسية</span><div class="r"><button class="ib" aria-label="إغلاق">@@i-x@@</button></div></div>
  <div class="seg3" style="margin:0 14px" data-etabs><button class="on" data-etab="blocks">الأقسام</button><button data-etab="nav">شريط التنقّل</button><button data-etab="other">أخرى</button></div>
  <div class="scroll" style="gap:10px;padding-top:10px">
    <div data-epanel="blocks" style="display:flex;flex-direction:column;gap:10px">
      <p class="hint">اسحب من المقبض لإعادة الترتيب، وأطفئ ما لا تريد رؤيته. اضغط القسم لخيارات محتواه.</p>
      <div class="hrow" data-order-strip></div>
      <div class="elist" data-elist></div>
      <button class="btn ghost" style="margin:0 14px;height:42px;border-radius:12px;justify-content:center" data-reset>@@i-reset@@ استعادة الترتيب الافتراضي</button>
      <p class="hint">الأقسام الجديدة التي يضيفها التطبيق لاحقاً تظهر في آخر القائمة بوسم «جديد» ولا تُفقد.</p>
    </div>
    <div data-epanel="nav" hidden style="display:flex;flex-direction:column;gap:10px">
      <p class="hint">اختر حتى خمسة أقسام لشريط التنقّل السفلي ورتّبها. «الرئيسية» و«ماي سبيس» ثابتان في الطرفين.</p>
      <div class="navprev"><nav class="nav" data-navbar style="border:1px solid #E5E5EA;border-radius:14px;height:60px"></nav></div>
      <div class="elist" data-navlist></div>
      <p class="hint" data-navcount></p>
    </div>
    <div data-epanel="other" hidden style="display:flex;flex-direction:column;gap:12px">
      <p class="hint">التخصيص نفسه ينطبق على الشاشات الأخرى، وتُحفظ الخيارات مع الحساب.</p>
      <div class="sec"><b>ماي سبيس · البلاطات</b></div>
      <div class="elist" data-otherlist="me"></div>
      <div class="sec"><b>الخريطة · الطبقات الافتراضية</b></div>
      <div class="elist" data-otherlist="map"></div>
      <div class="sec"><b>المحادثات</b></div>
      <div class="elist" data-otherlist="chat"></div>
    </div>
  </div>''')
model3 = phone('jiggle', '<div class="tb"><div class="l"><button class="ib" aria-label="الإشعارات">@@i-bell@@<i class="dot"></i></button><button class="btn sm ghost" data-edit-toggle>@@i-tune@@ تعديل</button></div><span class="ttl brand">ناس لايف</span><div class="r loc">@@i-pin@@ جدة · الشاطئ</div></div><div class="editbar" data-editbar hidden><span>اسحب لإعادة الترتيب، واضغط (−) للإخفاء</span><button class="btn sm" data-edit-toggle>تم</button></div>'
                 + '<div class="scroll" style="gap:16px" data-home="jiggle">' + SEARCH + '<div data-blocks></div><div class="tray" data-tray hidden></div></div>' + NAVBAR)

CSS2 = CSS + r'''
/* customization prototypes */
.blk{position:relative;display:flex;flex-direction:column;gap:10px;flex:none}
.blk .sec{align-items:center}
.blk .more{border:0;background:transparent;color:#6B7280;width:30px;height:30px;border-radius:999px;display:inline-flex;align-items:center;justify-content:center;cursor:pointer;margin-inline-start:6px}
.blk .more:hover{background:#F2F2F7}
.blk.pinned .sec b::after{content:"مثبّت";font-size:10.5px;font-weight:600;color:#5A4200;background:#FFF4D6;padding:2px 7px;border-radius:999px;margin-inline-start:6px}
.blk .newtag{font-size:10.5px;font-weight:700;color:#5A4200;background:#FFD66B;padding:2px 7px;border-radius:999px;margin-inline-start:6px}
.pop{position:absolute;z-index:5;min-width:190px;background:#fff;border:1px solid #E5E5EA;border-radius:14px;box-shadow:0 12px 30px rgba(0,0,0,.18);padding:6px;display:flex;flex-direction:column}
.pop button{display:flex;align-items:center;gap:10px;height:40px;padding:0 10px;border:0;background:transparent;border-radius:9px;font:500 13.5px var(--font-body);color:#111;cursor:pointer;text-align:right}
.pop button:hover{background:#F2F2F7}
.pop button[disabled]{color:#B0B6BC;cursor:default}
.pop button.danger{color:#D23B3B}
.pop .sep{height:1px;background:#E5E5EA;margin:4px 6px}
.tray{margin:0 14px;border:1.5px dashed #C7C7CC;border-radius:14px;padding:10px 12px;display:flex;flex-direction:column;gap:8px;flex:none}
.tray .t{font-size:13px;font-weight:600;color:#374151;display:flex;align-items:center;gap:6px}
.tray .chips{display:flex;gap:6px;flex-wrap:wrap}
.tray .chips button{display:inline-flex;align-items:center;gap:4px;height:30px;padding:0 10px;border-radius:999px;border:1px solid #E5E5EA;background:#fff;font:500 12.5px var(--font-body);color:#111;cursor:pointer}
.tray .chips button svg{color:var(--a)}
.hint{margin:0 14px;font-size:12px;line-height:1.55;color:#6B7280}
.elist{display:flex;flex-direction:column;margin:0 14px;border:1px solid #E5E5EA;border-radius:14px;overflow:hidden;background:#fff}
.erow{display:flex;align-items:center;gap:10px;padding:8px 10px 8px 12px;border-bottom:1px solid #E5E5EA;background:#fff;position:relative;user-select:none;-webkit-user-select:none}
.erow:last-child{border-bottom:0}
.erow .hnd{width:30px;height:36px;display:inline-flex;align-items:center;justify-content:center;color:#9CA3AF;cursor:grab;touch-action:none;flex:none;border-radius:8px}
.erow .hnd:active{cursor:grabbing}
.erow .eic{width:34px;height:34px;border-radius:10px;background:var(--a-soft);color:var(--a);display:inline-flex;align-items:center;justify-content:center;flex:none}
.erow .b{flex-grow:1;min-width:0;display:flex;flex-direction:column;gap:1px}
.erow .b b{font-size:13.5px;font-weight:600}.erow .b small{font-size:11.5px;color:#6B7280;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.erow.off .eic{background:#F2F2F7;color:#9CA3AF}.erow.off .b b{color:#9CA3AF}
.erow.locked .hnd{visibility:hidden}
.erow .lk{color:#9CA3AF;display:inline-flex;margin-inline-end:4px}
.erow.drag{box-shadow:0 10px 24px rgba(0,0,0,.18);z-index:3;border-radius:12px;border-bottom:0;background:#fff}
.erow .opts{flex-basis:100%;display:flex;gap:6px;flex-wrap:wrap;padding:6px 0 2px 0}
.erow .opts .ch{height:28px;font-size:11.5px}
.erow.open{flex-wrap:wrap}
.sw{appearance:none;-webkit-appearance:none;width:44px;height:26px;border-radius:999px;background:#C7C7CC;position:relative;cursor:pointer;flex:none;margin:0;transition:background .15s}
.sw::after{content:"";position:absolute;top:3px;left:3px;width:20px;height:20px;border-radius:999px;background:#fff;box-shadow:0 1px 3px rgba(0,0,0,.25);transition:transform .15s}
.sw:checked{background:var(--a)}.sw:checked::after{transform:translateX(18px)}
.sw[disabled]{opacity:.5;cursor:default}
.navprev{margin:0 14px}
.navprev .nav{padding:0}
.editbar{display:flex;align-items:center;justify-content:space-between;gap:10px;margin:0 14px 4px;padding:8px 10px 8px 12px;border-radius:12px;background:var(--a-soft);color:var(--a-ink);font-size:12.5px;font-weight:500;flex:none}
/* jiggle mode: blocks collapse to rows */
.jig .blk{margin:0 14px;border:1.5px solid var(--a);border-radius:14px;padding:6px 8px 6px 8px;gap:0;background:#fff;flex-direction:row;align-items:center;user-select:none;-webkit-user-select:none}
.jig .blk .body{display:none}
.jig .blk .sec{flex-grow:1;min-width:0;padding:0 6px}
.jig .blk .sec a,.jig .blk .more{display:none}
.jig .blk .hnd{width:30px;height:36px;display:inline-flex;align-items:center;justify-content:center;color:#9CA3AF;cursor:grab;touch-action:none;flex:none}
.jig .blk .rm{width:24px;height:24px;border-radius:999px;border:0;background:#D23B3B;color:#fff;display:inline-flex;align-items:center;justify-content:center;cursor:pointer;flex:none}
.jig .blk.drag{box-shadow:0 10px 24px rgba(0,0,0,.2);z-index:3}
.jig .blk .thumb{width:40px;height:40px;border-radius:10px;object-fit:cover;flex:none;margin-inline-end:2px}
.blk .body{display:contents}
.blk .hnd,.blk .rm,.blk .thumb{display:none}
.jig .blk .hnd,.jig .blk .rm{display:inline-flex}
.jig .blk .thumb{display:block}
.jig .search{opacity:.5}
.summary{display:flex;gap:8px;flex-wrap:wrap;align-items:center;font-size:13px;color:var(--muted)}
.summary b{color:var(--fg)}
.summary button{display:inline-flex;align-items:center;gap:6px;height:34px;padding:0 12px;border-radius:999px;border:1px solid var(--line);background:var(--card);color:var(--fg);font:600 12.5px var(--font-body);cursor:pointer}
.how{border:1px solid var(--line);border-radius:14px;padding:14px 16px;display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:14px;font-size:13.5px;line-height:1.6}
.how b{display:block;font-size:14px;margin-bottom:4px}
'''

page = f'''<title>تخصيص الرئيسية في ناس لايف</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Rubik:wght@400;500;600;700&family=Baloo+Bhaijaan+2:wght@600;700;800&display=swap">
<style>{CSS2}</style>
{TEMPLATES}
<div class="wrap">
  <header>
    <h1>تخصيص الرئيسية في ناس لايف</h1>
    <p class="sub">كل مستخدم يخفي الأقسام التي لا تهمّه ويرتّب البلوكات وشريط التنقّل كما يريد. ثلاثة أساليب للتخصيص نفسه على حالة واحدة مشتركة: ما تغيّره في أي هاتف يظهر فوراً في الهاتفين الآخرين، ويُحفظ على جهازك. السحب حقيقي من المقبض.</p>
    <div class="rowh">
      <div class="seg" id="seg" role="tablist" aria-label="النماذج">
        <button class="on" data-go="inline" role="tab"><i>١</i>قائمة على القسم</button>
        <button data-go="editor" role="tab"><i>٢</i>شاشة التخصيص</button>
        <button data-go="jiggle" role="tab"><i>٣</i>وضع التحرير</button>
      </div>
      <div class="summary"><span data-summary></span><button data-reset>@@i-reset@@ استعادة الافتراضي</button></div>
    </div>
  </header>

  <div class="phones">
    <section class="slot active" id="s-inline">
      <h2><span>١</span>قائمة على القسم <small>· أخفّ الطرق</small></h2>
      {model1}
      <p class="note">زر «⋯» بجانب عنوان كل قسم (ضغطة مطوّلة في التطبيق) يفتح: نقل لأعلى، نقل لأسفل، تثبيت في الأعلى، إخفاء القسم. المخفي يتجمّع في صندوق «أقسام مخفية» أسفل الصفحة ليُستعاد بضغطة. لا شاشة إضافية، والمستخدم يكتشفه أثناء الاستخدام.</p>
    </section>
    <section class="slot" id="s-editor">
      <h2><span>٢</span>شاشة التخصيص <small>· الأكمل</small></h2>
      {model2}
      <p class="note">تُفتح من «تخصيص» في ماي سبيس أو من زر التعديل. قائمة بكل الأقسام بمقبض سحب ومفتاح إظهار، وخيارات محتوى داخل القسم (مثلاً: لحظات الأصدقاء فقط، عروض المقاهي فقط). تبويب «شريط التنقّل» يختار خمسة أقسام ويرتّبها، و«أخرى» يمتدّ إلى ماي سبيس والخريطة والمحادثات.</p>
    </section>
    <section class="slot" id="s-jiggle">
      <h2><span>٣</span>وضع التحرير <small>· كما في شاشة الآيفون</small></h2>
      {model3}
      <p class="note">زر «تعديل» في الأعلى يحوّل الرئيسية نفسها إلى وضع تحرير: الأقسام تنطوي إلى صفوف بصورة مصغّرة، تُسحب من مقبضها في مكانها، وزر (−) يخفيها، ثم «تم». المستخدم يرى النتيجة في السياق نفسه.</p>
    </section>
  </div>

  <div class="how">
    <div><b>ما يُحفظ</b>لكل مستخدم `home_layout` واحد: ترتيب الأقسام، المخفي منها، خيارات محتوى كل قسم، وأقسام شريط التنقّل. يُخزَّن على الخادم فيتزامن بين الويب والآيفون، ويُصدَّر مع بيانات الحساب.</div>
    <div><b>الافتراضي من الإدارة</b>لوحة الإدارة تحدّد الترتيب الافتراضي للجميع، وأقساماً «مثبّتة» لا تُخفى (مثل الإعلانات المهمة)، وتستطيع تجربة ترتيب مختلف لمدينة أو شريحة.</div>
    <div><b>القواعد</b>الأقسام الجديدة تظهر آخر القائمة بوسم «جديد» ولا تُفقد. صندوق «أقسام مخفية» يبقى ظاهراً حتى لا يضيع شيء. «استعادة الافتراضي» بضغطة. الرئيسية والماي سبيس ثابتان في شريط التنقّل.</div>
    <div><b>التنفيذ</b>أسلوب ١ و٣ يُنفَّذان على الشاشة نفسها بمكوّن واحد (قائمة أقسام قابلة للترتيب)، وأسلوب ٢ شاشة مستقلة. الأفضل الجمع: ١ للاكتشاف السريع + ٢ للتحكم الكامل، وهو ما أوصي به.</div>
  </div>
</div>

<script>
(function(){{
  var slots = {{inline:'s-inline', editor:'s-editor', jiggle:'s-jiggle'}};
  function go(id){{
    Object.keys(slots).forEach(function(k){{ document.getElementById(slots[k]).classList.toggle('active', k===id); }});
    document.querySelectorAll('#seg button').forEach(function(b){{ b.classList.toggle('on', b.getAttribute('data-go')===id); }});
    if (window.innerWidth <= 1250) window.scrollTo({{top:0, behavior:'smooth'}});
  }}
  document.querySelectorAll('#seg button').forEach(function(b){{ b.addEventListener('click', function(){{ go(b.getAttribute('data-go')); }}); }});

  // ---- الحالة المشتركة
  var TPL = {{}}; var ORDER0 = [];
  document.querySelectorAll('template[id^="blk-"]').forEach(function(t){{ var id = t.id.slice(4); ORDER0.push(id); TPL[id] = {{title:t.getAttribute('data-title'), icon:t.getAttribute('data-icon'), meta:t.getAttribute('data-meta'), opts:(t.getAttribute('data-opts')||'').split('|').filter(Boolean), el:t}}; }});
  var ICON = {{}}; document.querySelectorAll('template[id^="blk-"]').forEach(function(t){{}});
  var NAVS = {json.dumps([{'id':i,'icon':ic,'label':l,'locked':lk} for i,ic,l,lk in NAV_CANDIDATES], ensure_ascii=False)};
  var NAVICON = {json.dumps({i: ICONS[ic] for i,ic,l,lk in NAV_CANDIDATES}, ensure_ascii=False)};
  var BLKICON = {json.dumps({id: ICONS[ic] for id,t,ic,m,b,o in BLOCKS}, ensure_ascii=False)};
  var OTHER = {{
    me: [['wallet','المحفظة',true],['bookings','حجوزاتي وطلباتي',true],['posts','منشوراتي',true],['market','عروضي في السوق',true],['biz','نشاطي التجاري',false],['jobs','التوظيف',true],['wish','أمنياتي',true],['blog','التحديثات والأخبار',false]],
    map: [['moments','لحظات',true],['circles','دوائر',true],['offers','عروض',true],['jobs','وظائف',false],['friends','أصدقاء',true],['market','سوق',false]],
    chat: [['requests','تبويب الطلبات',true],['jobs','تبويب التوظيف',true],['sound','صوت الرسائل',true],['preview','معاينة الرسالة في القائمة',true]]
  }};
  var DEF = {{ order: ORDER0.slice(), hidden: [], pinned: [], opts: {{}}, nav: ['home','map','circles','chats','me'], other: {{}} }};
  var state = JSON.parse(JSON.stringify(DEF));
  try {{ var s = JSON.parse(localStorage.getItem('nl-custom-v1') || 'null'); if (s && s.order) {{ state = s; ORDER0.forEach(function(id){{ if (state.order.indexOf(id) < 0) {{ state.order.push(id); state.fresh = (state.fresh||[]).concat([id]); }} }}); }} }} catch(e){{}}
  function save(){{ try {{ localStorage.setItem('nl-custom-v1', JSON.stringify(state)); }} catch(e){{}} }}
  function visible(){{ return state.order.filter(function(id){{ return state.hidden.indexOf(id) < 0; }}); }}

  // ---- الرئيسية (نموذج ١ و٣)
  function blockEl(id, model){{
    var t = TPL[id]; var s = document.createElement('section'); s.className = 'blk' + (state.pinned.indexOf(id)>=0 ? ' pinned' : ''); s.setAttribute('data-id', id);
    var thumb = t.el.content.querySelector('img'); var th = thumb ? '<img class="thumb" src="'+thumb.getAttribute('src')+'" alt="">' : '<span class="thumb eic" style="display:none"></span>';
    var isNew = (state.fresh||[]).indexOf(id) >= 0;
    s.innerHTML = '<span class="hnd" aria-label="اسحب لإعادة الترتيب">@@i-grip@@</span>' + th + '<div class="sec"><b>' + t.title + (isNew ? '<span class="newtag">جديد</span>' : '') + '<small>' + t.meta + '</small></b><a href="#">الكل</a>' + (model==='inline' ? '<button class="more" data-more="'+id+'" aria-label="خيارات القسم">@@i-more@@</button>' : '') + '</div>' + '<button class="rm" data-rm="'+id+'" aria-label="إخفاء">@@i-minus@@</button>';
    var body = document.createElement('div'); body.className = 'body'; body.appendChild(t.el.content.cloneNode(true)); s.appendChild(body);
    return s;
  }}
  function renderHomes(){{
    document.querySelectorAll('[data-home]').forEach(function(h){{
      var model = h.getAttribute('data-home'); var box = h.querySelector('[data-blocks]'); box.innerHTML = '';
      box.style.display = 'flex'; box.style.flexDirection = 'column'; box.style.gap = '16px';
      visible().forEach(function(id){{ box.appendChild(blockEl(id, model)); }});
      var tray = h.querySelector('[data-tray]');
      if (state.hidden.length) {{ tray.hidden = false; tray.innerHTML = '<span class="t">@@i-eye-off@@ أقسام مخفية (' + state.hidden.length + ')</span><div class="chips">' + state.hidden.map(function(id){{ return '<button data-show="'+id+'">@@i-eye@@ ' + TPL[id].title + '</button>'; }}).join('') + '</div>'; }}
      else {{ tray.hidden = true; tray.innerHTML = ''; }}
    }});
  }}
  // ---- شريط التنقّل
  function renderNavs(){{
    document.querySelectorAll('[data-navbar]').forEach(function(n){{
      n.style.gridTemplateColumns = 'repeat(' + state.nav.length + ',minmax(0,1fr))';
      n.innerHTML = state.nav.map(function(id, i){{ var c = NAVS.filter(function(x){{ return x.id===id; }})[0]; return '<button' + (i===0 ? ' class="on"' : '') + '>' + NAVICON[id] + c.label + '</button>'; }}).join('');
    }});
  }}
  // ---- شاشة التخصيص
  function renderEditor(){{
    var list = document.querySelector('[data-elist]'); list.innerHTML = '';
    state.order.forEach(function(id){{
      var t = TPL[id], off = state.hidden.indexOf(id) >= 0, r = document.createElement('div');
      r.className = 'erow' + (off ? ' off' : '') + (state.openOpt===id ? ' open' : ''); r.setAttribute('data-id', id);
      var opts = t.opts.length ? '<div class="opts">' + t.opts.map(function(o){{ var on = (state.opts[id]||[]).indexOf(o) >= 0; return '<span class="ch' + (on ? ' on' : '') + '" data-opt="'+id+'" data-val="'+o+'">' + o + '</span>'; }}).join('') + '</div>' : '';
      r.innerHTML = '<span class="hnd">@@i-grip@@</span><span class="eic">' + BLKICON[id] + '</span><div class="b" data-openopt="'+id+'"><b>' + t.title + (state.pinned.indexOf(id)>=0 ? ' <span class="tag">مثبّت</span>' : '') + '</b><small>' + t.meta + (t.opts.length ? ' · ' + t.opts.length + ' خيارات' : '') + '</small></div><input class="sw" type="checkbox" data-toggle="'+id+'"' + (off ? '' : ' checked') + ' aria-label="إظهار ' + t.title + '">' + (state.openOpt===id ? opts : '');
      list.appendChild(r);
    }});
    var strip = document.querySelector('[data-order-strip]');
    strip.innerHTML = visible().map(function(id, i){{ return '<span class="ch on" style="height:26px;font-size:11px">' + (i+1) + ' · ' + TPL[id].title + '</span>'; }}).join('') || '<span class="ch" style="height:26px;font-size:11px">لا أقسام ظاهرة</span>';
    // nav editor
    var nl = document.querySelector('[data-navlist]'); nl.innerHTML = '';
    var ordered = state.nav.map(function(id){{ return NAVS.filter(function(x){{ return x.id===id; }})[0]; }}).concat(NAVS.filter(function(x){{ return state.nav.indexOf(x.id) < 0; }}));
    ordered.forEach(function(c){{
      var on = state.nav.indexOf(c.id) >= 0, r = document.createElement('div');
      r.className = 'erow' + (on ? '' : ' off') + (c.locked ? ' locked' : ''); r.setAttribute('data-nav-id', c.id);
      r.innerHTML = '<span class="hnd">@@i-grip@@</span><span class="eic">' + NAVICON[c.id] + '</span><div class="b"><b>' + c.label + '</b><small>' + (c.locked ? 'ثابت' : (on ? 'في الشريط' : 'غير ظاهر')) + '</small></div>' + (c.locked ? '<span class="lk">@@i-lock@@</span>' : '') + '<input class="sw" type="checkbox" data-navtoggle="'+c.id+'"' + (on ? ' checked' : '') + (c.locked || (!on && state.nav.length >= 5) ? ' disabled' : '') + ' aria-label="' + c.label + '">';
      nl.appendChild(r);
    }});
    document.querySelector('[data-navcount]').textContent = state.nav.length + ' من ٥ · ' + (state.nav.length >= 5 ? 'أطفئ قسماً لتضيف غيره' : 'يمكنك إضافة ' + (5 - state.nav.length));
    // other lists
    document.querySelectorAll('[data-otherlist]').forEach(function(ol){{
      var g = ol.getAttribute('data-otherlist'); ol.innerHTML = OTHER[g].map(function(x){{
        var key = g + ':' + x[0]; var on = (key in state.other) ? state.other[key] : x[2];
        return '<label class="erow' + (on ? '' : ' off') + '" style="cursor:pointer"><span class="eic">@@i-eye@@</span><div class="b"><b>' + x[1] + '</b></div><input class="sw" type="checkbox" data-other="' + key + '"' + (on ? ' checked' : '') + '></label>';
      }}).join('');
    }});
  }}
  function renderSummary(){{
    var n = ORDER0.length, h = state.hidden.length;
    document.querySelector('[data-summary]').innerHTML = '<b>' + visible().length + '</b> أقسام ظاهرة · <b>' + h + '</b> مخفية · شريط التنقّل <b>' + state.nav.length + '</b> أقسام · محفوظ على هذا الجهاز';
  }}
  function render(){{ renderHomes(); renderNavs(); renderEditor(); renderSummary(); save(); }}

  // ---- أفعال
  function move(id, dir){{ var i = state.order.indexOf(id); var vis = visible(); var vi = vis.indexOf(id); var j = vi + dir; if (j < 0 || j >= vis.length) return; var other = vis[j]; var oi = state.order.indexOf(other); state.order.splice(i, 1); state.order.splice(oi, 0, id); render(); }}
  function hide(id){{ if (state.hidden.indexOf(id) < 0) state.hidden.push(id); state.pinned = state.pinned.filter(function(x){{ return x!==id; }}); render(); }}
  function show(id){{ state.hidden = state.hidden.filter(function(x){{ return x!==id; }}); state.fresh = (state.fresh||[]).filter(function(x){{ return x!==id; }}); render(); }}
  function pin(id){{ state.order = [id].concat(state.order.filter(function(x){{ return x!==id; }})); state.pinned = [id]; render(); }}
  function reset(){{ state = JSON.parse(JSON.stringify(DEF)); render(); }}
  document.querySelectorAll('[data-reset]').forEach(function(b){{ b.addEventListener('click', reset); }});

  // نموذج ١: قائمة منبثقة على القسم
  var pop = document.querySelector('[data-pop]'), popFor = null;
  function closePop(){{ pop.hidden = true; popFor = null; }}
  document.addEventListener('click', function(e){{
    var m = e.target.closest('[data-more]');
    if (m) {{
      var id = m.getAttribute('data-more'), vis = visible(), i = vis.indexOf(id), screen = m.closest('.screen'), r = m.getBoundingClientRect(), sr = screen.getBoundingClientRect();
      pop.innerHTML = '<button data-act="up"' + (i===0 ? ' disabled' : '') + '>@@i-up@@ نقل لأعلى</button><button data-act="down"' + (i===vis.length-1 ? ' disabled' : '') + '>@@i-down@@ نقل لأسفل</button><button data-act="pin">@@i-pinned@@ تثبيت في الأعلى</button><div class="sep"></div><button data-act="hide" class="danger">@@i-eye-off@@ إخفاء القسم</button>';
      pop.style.top = (r.bottom - sr.top + 4) + 'px'; pop.style.right = (sr.right - r.right) + 'px'; pop.hidden = false; popFor = id; e.stopPropagation(); return;
    }}
    var a = e.target.closest('[data-act]');
    if (a && popFor) {{ var act = a.getAttribute('data-act'), id2 = popFor; closePop(); if (act==='up') move(id2, -1); if (act==='down') move(id2, 1); if (act==='pin') pin(id2); if (act==='hide') hide(id2); return; }}
    if (!e.target.closest('[data-pop]')) closePop();
    var sh = e.target.closest('[data-show]'); if (sh) {{ show(sh.getAttribute('data-show')); return; }}
    var rm = e.target.closest('[data-rm]'); if (rm) {{ hide(rm.getAttribute('data-rm')); return; }}
    var et = e.target.closest('[data-edit-toggle]'); if (et) {{ var sc = et.closest('.screen'); var on = sc.classList.toggle('jig'); sc.querySelector('[data-editbar]').hidden = !on; return; }}
    var tab = e.target.closest('[data-etab]'); if (tab) {{ var k = tab.getAttribute('data-etab'); document.querySelectorAll('[data-etab]').forEach(function(b){{ b.classList.toggle('on', b===tab); }}); document.querySelectorAll('[data-epanel]').forEach(function(p){{ p.hidden = p.getAttribute('data-epanel') !== k; }}); return; }}
    var oo = e.target.closest('[data-openopt]'); if (oo && !e.target.closest('input')) {{ var oid = oo.getAttribute('data-openopt'); state.openOpt = state.openOpt===oid ? null : oid; renderEditor(); return; }}
    var op = e.target.closest('[data-opt]'); if (op) {{ var bid = op.getAttribute('data-opt'), v = op.getAttribute('data-val'); var arr = state.opts[bid] || []; state.opts[bid] = arr.indexOf(v) >= 0 ? arr.filter(function(x){{ return x!==v; }}) : arr.concat([v]); render(); return; }}
  }});
  document.addEventListener('change', function(e){{
    var t = e.target.closest('[data-toggle]'); if (t) {{ t.checked ? show(t.getAttribute('data-toggle')) : hide(t.getAttribute('data-toggle')); return; }}
    var n = e.target.closest('[data-navtoggle]'); if (n) {{ var id = n.getAttribute('data-navtoggle'); if (n.checked) {{ if (state.nav.length < 5) state.nav.splice(state.nav.length - 1, 0, id); }} else state.nav = state.nav.filter(function(x){{ return x!==id; }}); render(); return; }}
    var o = e.target.closest('[data-other]'); if (o) {{ state.other[o.getAttribute('data-other')] = o.checked; render(); }}
  }});

  // ---- السحب لإعادة الترتيب (مؤشر واحد، يعمل باللمس والفأرة)
  function sortable(getContainer, itemSel, onDrop){{
    document.addEventListener('pointerdown', function(e){{
      var h = e.target.closest('.hnd'); if (!h) return; var item = h.closest(itemSel); if (!item) return; var box = getContainer(item); if (!box) return;
      e.preventDefault(); var scrollBox = item.closest('.scroll'), pid = e.pointerId;
      var r0 = item.getBoundingClientRect(), offset = e.clientY - r0.top; item.classList.add('drag');
      // نحرّك الجيران حول العنصر المسحوب بدل تحريكه هو، حتى لا يفقد التقاط المؤشر عند إعادة إدراجه في الشجرة
      function onMove(ev){{
        if (ev.pointerId !== pid) return; var y = ev.clientY;
        var sibs = Array.prototype.filter.call(box.children, function(c){{ return c !== item && c.matches(itemSel); }});
        for (var i = 0; i < sibs.length; i++) {{ var r = sibs[i].getBoundingClientRect(); var mid = r.top + r.height/2; var before = item.compareDocumentPosition(sibs[i]) & Node.DOCUMENT_POSITION_PRECEDING;
          if (before && y < mid) {{ box.insertBefore(sibs[i], item.nextSibling); break; }}
          if (!before && y > mid) {{ box.insertBefore(sibs[i], item); break; }} }}
        item.style.transform = ''; var r1 = item.getBoundingClientRect(); item.style.transform = 'translateY(' + (y - offset - r1.top) + 'px)';
        if (scrollBox) {{ var sr = scrollBox.getBoundingClientRect(); if (y < sr.top + 40) scrollBox.scrollTop -= 8; else if (y > sr.bottom - 40) scrollBox.scrollTop += 8; }}
      }}
      function onUp(ev){{ if (ev.pointerId !== pid) return; item.classList.remove('drag'); item.style.transform = '';
        document.removeEventListener('pointermove', onMove); document.removeEventListener('pointerup', onUp); document.removeEventListener('pointercancel', onUp);
        onDrop(Array.prototype.filter.call(box.children, function(c){{ return c.matches(itemSel); }}).map(function(c){{ return c.getAttribute('data-id') || c.getAttribute('data-nav-id'); }})); }}
      document.addEventListener('pointermove', onMove); document.addEventListener('pointerup', onUp); document.addEventListener('pointercancel', onUp);
    }});
  }}
  sortable(function(item){{ return item.closest('[data-elist]') || item.closest('.jig [data-blocks]'); }}, '.erow[data-id], .blk[data-id]', function(ids){{
    if (ids.length === state.order.length) state.order = ids; else {{ var hiddenIds = state.order.filter(function(id){{ return ids.indexOf(id) < 0; }}); state.order = ids.concat(hiddenIds); }}
    render();
  }});
  sortable(function(item){{ return item.closest('[data-navlist]'); }}, '.erow[data-nav-id]', function(ids){{
    var picked = ids.filter(function(id){{ return state.nav.indexOf(id) >= 0 && id !== 'home' && id !== 'me'; }});
    state.nav = ['home'].concat(picked, ['me']); render();
  }});
  render();
}})();
</script>
'''

if __name__ == '__main__':
    icons_path = root / 'icons.json'
    icons = json.loads(icons_path.read_text(encoding='utf-8')); icons.update(ICONS); icons.update(EXTRA_ICONS)
    icons_path.write_text(json.dumps(icons, ensure_ascii=False, indent=1), encoding='utf-8')
    (root / 'template_custom.html').write_text(page, encoding='utf-8')
    print('template_custom.html', len(page))
