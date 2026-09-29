# يولّد template_colors.html من template.html: لوحات ألوان (خلفية بيضاء دائماً) + التعريف الصوتي/المرئي.
import re, json, sys, pathlib
root = pathlib.Path(__file__).parent
s = (root / 'template.html').read_text(encoding='utf-8')

def rep(old, new, count=1):
    global s
    assert s.count(old) >= 1, 'anchor missing: ' + old[:80]
    if count == 1:
        assert s.count(old) == 1, 'anchor not unique (%d): %s' % (s.count(old), old[:80])
    s = s.replace(old, new) if count != 1 else s.replace(old, new, 1)

# ---- 1. ألوان الهوية → متغيرات
s = s.replace('#0A6E78', 'var(--a)').replace('#E0F3F4', 'var(--a-soft)').replace('#0F2D30', 'var(--a-ink)')
s = s.replace('var(--accent)', 'var(--a)')

# ---- 2. العنوان والرموز
rep('<title>نموذج بروفايل ناس لايف</title>', '<title>ألوان بروفايل ناس لايف</title>')
rep(""":root{
  --bg:#EEF1F2; --fg:#111111; --muted:#5F6B73; --line:#D9DEE2; --card:#FFFFFF; --accent:var(--a); --accent-soft:var(--a-soft); --sun:#FFD66B;
  --font-body:Rubik,"Segoe UI",Tahoma,sans-serif; --font-display:"Baloo Bhaijaan 2",Rubik,Tahoma,sans-serif;
}
@media (prefers-color-scheme: dark){ :root:not([data-theme="light"]){ --bg:#0F1315; --fg:#F1F3F4; --muted:#9AA6AE; --line:#273036; --card:#171C20; --accent:#5FC3CC; --accent-soft:#12383C; color-scheme:dark } }
:root[data-theme="dark"]{ --bg:#0F1315; --fg:#F1F3F4; --muted:#9AA6AE; --line:#273036; --card:#171C20; --accent:#5FC3CC; --accent-soft:#12383C; color-scheme:dark }""",
"""/* Layout: palette strip + 4-way screen switch on top, then phone frames. The phone screens are always white; only the accent family (--a, --a-soft, --a-ink) changes per palette. */
:root{
  --bg:#FFFFFF; --fg:#111111; --muted:#5F6B73; --line:#E3E7EA; --card:#FFFFFF; --sun:#FFD66B;
  --a:#0A6E78; --a-soft:#E0F3F4; --a-ink:#0F2D30;
  --font-body:Rubik,"Segoe UI",Tahoma,sans-serif; --font-display:"Baloo Bhaijaan 2",Rubik,Tahoma,sans-serif;
}
:root[data-p="teal"]{ --a:#0A6E78; --a-soft:#E0F3F4; --a-ink:#0F2D30 }
:root[data-p="coral"]{ --a:#BE3A1B; --a-soft:#FCE9E3; --a-ink:#5E1E12 }
:root[data-p="indigo"]{ --a:#3742C4; --a-soft:#E8EAFB; --a-ink:#1B2160 }
:root[data-p="emerald"]{ --a:#0F7A50; --a-soft:#E1F5EA; --a-ink:#0C3D28 }
:root[data-p="berry"]{ --a:#8E2A78; --a-soft:#F7E4F2; --a-ink:#3E0F34 }
:root[data-p="amber"]{ --a:#9E4F08; --a-soft:#FBEDDC; --a-ink:#4A2705 }
:root[data-p="sky"]{ --a:#0B67B3; --a-soft:#E2EFFB; --a-ink:#0E2F4F }
:root[data-p="charcoal"]{ --a:#1A1A1A; --a-soft:#F2F2F7; --a-ink:#111111 }
@media (prefers-color-scheme: dark){ :root:not([data-theme="light"]){ --bg:#0F1315; --fg:#F1F3F4; --muted:#9AA6AE; --line:#273036; --card:#171C20; color-scheme:dark } }
:root[data-theme="dark"]{ --bg:#0F1315; --fg:#F1F3F4; --muted:#9AA6AE; --line:#273036; --card:#171C20; color-scheme:dark }""")

# الشريحة المختارة تبقى ظاهرة على أي خلفية (لوحة الفحم في الوضع الداكن)
rep('.seg button.on{background:var(--a);color:#fff}', '.seg button.on{background:var(--a);color:#fff;box-shadow:0 0 0 1.5px var(--line)}')

# ---- 3. أنماط جديدة: شريط اللوحات، بطاقة التعريف، الموجة، التسجيل
rep('[hidden]{display:none!important}', """[hidden]{display:none!important}
/* palette strip: one mini header per palette, all on white */
.pal{display:flex;gap:10px;overflow-x:auto;padding:2px 2px 6px;scrollbar-width:thin}
.pal button{flex:none;width:158px;border:1.5px solid var(--line);border-radius:16px;background:#fff;color:#111;padding:10px 10px 8px;display:flex;flex-direction:column;gap:7px;cursor:pointer;font-family:var(--font-body);text-align:right;transition:box-shadow .15s,border-color .15s}
.pal button.on{border-color:var(--pa);box-shadow:0 0 0 2px var(--pa)}
.pal button:focus-visible{outline:2px solid var(--pa);outline-offset:2px}
.pal .top{display:flex;align-items:center;justify-content:space-between;gap:6px}
.pal img{width:34px;height:34px;border-radius:999px;object-fit:cover;display:block}
.pal .fb{height:26px;padding:0 10px;border-radius:999px;background:var(--pa);color:#fff;font:700 11.5px var(--font-body);display:inline-flex;align-items:center}
.pal .nm{display:flex;align-items:center;gap:4px;font:800 13.5px var(--font-display)}
.pal .nm i{width:14px;height:14px;border-radius:999px;background:var(--pa);display:inline-flex;align-items:center;justify-content:center;color:#fff}
.pal .ch{display:inline-flex;align-items:center;gap:4px;font-size:10.5px;font-weight:500;color:var(--pi);background:var(--ps);padding:3px 8px;border-radius:999px;align-self:flex-start}
.pal .mini{display:flex;align-items:center;gap:6px;border:1px solid #EEF0F2;border-radius:999px;padding:3px 8px 3px 3px}
.pal .mini i{width:18px;height:18px;border-radius:999px;background:var(--pa);display:inline-flex;align-items:center;justify-content:center;flex:none}
.pal .mini b{display:flex;gap:1.5px;align-items:center;height:12px}
.pal .mini b i{width:2px;border-radius:2px;background:var(--pa);opacity:.75}
.pal .lbl{display:flex;justify-content:space-between;align-items:center;font-size:12px;color:#5F6B73;border-top:1px solid #EEF0F2;padding-top:6px;margin-top:1px}
.pal .lbl b{font-weight:700;color:#111}
.pal .lbl code{font:500 10.5px ui-monospace,Menlo,monospace;color:#8A949B;direction:ltr}
/* self-introduction card (voice or video) */
.intro{display:flex;align-items:center;gap:10px;border:1px solid #E5E5EA;border-radius:16px;padding:8px 10px 8px 8px;background:#fff}
.intro .play{width:44px;height:44px;border-radius:999px;border:0;background:var(--a);color:#fff;display:inline-flex;align-items:center;justify-content:center;cursor:pointer;flex:none}
.intro .body{flex-grow:1;min-width:0;display:flex;flex-direction:column;gap:4px}
.intro .t{font-size:13.5px;font-weight:700;display:flex;align-items:center;gap:6px}
.intro .d{font-size:12px;color:#6B7280;font-variant-numeric:tabular-nums}
.intro .more{border:0;background:transparent;color:var(--a);font:600 12.5px var(--font-body);cursor:pointer;padding:0;flex:none}
.wave{display:flex;align-items:center;gap:2px;height:26px}
.wave i{flex:1 1 0;min-width:2px;border-radius:2px;background:#D1D5DB;height:30%;transition:background .1s}
.wave i.on{background:var(--a)}
.intro.playing .wave i.on{animation:bob 1s ease-in-out infinite}
.intro.playing .wave i.on:nth-child(3n){animation-delay:.2s}.intro.playing .wave i.on:nth-child(3n+1){animation-delay:.4s}
@keyframes bob{0%,100%{transform:scaleY(1)}50%{transform:scaleY(.6)}}
.vid{position:relative;border-radius:16px;overflow:hidden;background:#111;aspect-ratio:16/9;max-width:100%}
.vid img{width:100%;height:100%;object-fit:cover;display:block;opacity:.92}
.vid .play{position:absolute;inset:0;margin:auto;width:52px;height:52px;border-radius:999px;border:0;background:rgba(255,255,255,.92);color:#111;display:inline-flex;align-items:center;justify-content:center;cursor:pointer}
.vid.playing .play{background:rgba(17,17,17,.55);color:#fff;width:40px;height:40px}
.vid .cap{position:absolute;right:10px;bottom:8px;left:10px;display:flex;justify-content:space-between;align-items:center;color:#fff;font-size:12px;font-weight:600;text-shadow:0 1px 4px rgba(0,0,0,.6);font-variant-numeric:tabular-nums}
.vid .bar{position:absolute;left:0;right:0;bottom:0;height:3px;background:rgba(255,255,255,.3)}
.vid .bar i{display:block;height:100%;width:0;background:var(--a)}
.vid .mute{position:absolute;top:8px;left:8px;width:28px;height:28px;border-radius:999px;border:0;background:rgba(17,17,17,.55);color:#fff;display:inline-flex;align-items:center;justify-content:center}
.recbox{display:flex;flex-direction:column;gap:10px;border:1.5px solid #E5E5EA;border-radius:14px;padding:12px}
.recbox.empty{border-style:dashed;align-items:center;text-align:center;gap:8px}
.recbtn{width:64px;height:64px;border-radius:999px;border:0;background:var(--a);color:#fff;display:inline-flex;align-items:center;justify-content:center;cursor:pointer;box-shadow:0 6px 18px rgba(0,0,0,.18)}
.recbtn.rec{background:#D23B3B;animation:pulse 1.2s ease-in-out infinite}
@keyframes pulse{0%,100%{box-shadow:0 0 0 0 rgba(210,59,59,.35)}50%{box-shadow:0 0 0 12px rgba(210,59,59,0)}}
.recrow{display:flex;gap:8px;flex-wrap:wrap}
.cam{position:relative;border-radius:14px;overflow:hidden;background:#0b0b0b;aspect-ratio:16/9;max-width:100%;display:flex;align-items:center;justify-content:center;color:#fff}
.cam img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;opacity:.55;filter:saturate(.6)}
.cam .rectag{position:absolute;top:10px;right:10px;display:inline-flex;align-items:center;gap:6px;background:rgba(17,17,17,.6);border-radius:999px;padding:4px 10px;font-size:12px;font-weight:700;font-variant-numeric:tabular-nums}
.cam .rectag i{width:8px;height:8px;border-radius:999px;background:#FF3B30;animation:blink 1s steps(2) infinite}
@keyframes blink{50%{opacity:.2}}
.cam .stop{position:relative;width:56px;height:56px;border-radius:999px;border:3px solid #fff;background:transparent;display:inline-flex;align-items:center;justify-content:center;cursor:pointer}
.cam .stop i{width:22px;height:22px;border-radius:5px;background:#FF3B30}
.kind2{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px}
.kind2 button{height:58px;border-radius:12px;border:1.5px solid #E5E5EA;background:#fff;display:flex;align-items:center;gap:10px;padding:0 12px;cursor:pointer;font-family:var(--font-body);text-align:right;color:#111}
.kind2 button.on{border-color:var(--a);background:var(--a-soft)}
.kind2 button .ico{width:34px;height:34px;border-radius:10px;background:#F2F2F7;display:inline-flex;align-items:center;justify-content:center;flex:none;color:#374151}
.kind2 button.on .ico{background:var(--a);color:#fff}
.kind2 .tt{display:flex;flex-direction:column;gap:1px;min-width:0}
.kind2 .tt b{font-size:13.5px}.kind2 .tt small{font-size:11px;color:#6B7280}
.demo{display:flex;align-items:center;gap:8px;font-size:12.5px;color:var(--muted)}
.demo .seg3{display:inline-grid;grid-template-columns:repeat(2,minmax(0,1fr));width:190px;background:var(--card);border:1px solid var(--line)}
.demo .seg3 button{height:32px;font-size:12.5px;color:var(--muted)}
.demo .seg3 button.on{background:var(--a);color:#fff;box-shadow:none}
@media (prefers-reduced-motion: reduce){ .intro.playing .wave i.on,.recbtn.rec,.cam .rectag i{animation:none} }""")

# ---- 4. الرأس: العنوان، الوصف، شريط اللوحات
rep("""    <h1>نموذج بروفايل ناس لايف</h1>
    <p class="sub">أربع شاشات بحجم الآيفون بألوان التطبيق وخطوطه. الشخصية: فهد الغامدي، مصوّر في جدة. التبويبات والأزرار تعمل، والشاشات مترابطة (تعديل الملف، التوثيق، «كزائر»).</p>""",
"""    <h1>ألوان بروفايل ناس لايف</h1>
    <p class="sub">النموذج نفسه بثماني لوحات ألوان، والخلفية بيضاء في كلها؛ يتغيّر لون الهوية فقط (الأزرار والروابط والشرائح وعلامة التوثيق). الجديد: «عرّف بنفسك» تسجيل صوتي حتى ٦٠ ثانية أو فيديو حتى ٣٠ ثانية يظهر أعلى الملف، ويُسجَّل من شاشة التعديل. اختر لوحة، ثم تنقّل بين الشاشات الأربع.</p>
    <div class="pal" id="pal" role="radiogroup" aria-label="لوحة الألوان">
      <!--PAL-->
    </div>""")

pal = [('teal','بحر جدة','#0A6E78','#E0F3F4','#0F2D30','الحالية'),
       ('coral','مرجان','#BE3A1B','#FCE9E3','#5E1E12','دافئ'),
       ('indigo','نيلي','#3742C4','#E8EAFB','#1B2160','تقني'),
       ('emerald','زمرد','#0F7A50','#E1F5EA','#0C3D28','هادئ'),
       ('berry','توت','#8E2A78','#F7E4F2','#3E0F34','مميّز'),
       ('amber','رمال','#9E4F08','#FBEDDC','#4A2705','ترابي'),
       ('sky','سماء','#0B67B3','#E2EFFB','#0E2F4F','واضح'),
       ('charcoal','فحم','#1A1A1A','#F2F2F7','#111111','بسيط')]
bars = ''.join('<i style="height:%dpx"></i>' % h for h in [4,7,11,6,9,12,5,8,10,4,7,9])
cards = []
for key, name, a, soft, ink, mood in pal:
    cards.append(f'''      <button role="radio" aria-checked="{'true' if key=='teal' else 'false'}" data-p="{key}" style="--pa:{a};--ps:{soft};--pi:{ink}"{' class="on"' if key=='teal' else ''}>
        <div class="top"><img src="@@avatar@@" alt=""><span class="fb">متابعة</span></div>
        <span class="nm">فهد الغامدي<i><svg width="9" height="9" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"><path d="M5 13l4 4L19 7"/></svg></i></span>
        <span class="ch">@@check@@بريد وجوال موثّقان</span>
        <span class="mini"><i><svg width="9" height="9" viewBox="0 0 24 24" fill="#fff"><path d="M8 5v14l11-7z"/></svg></i><b>{bars}</b></span>
        <span class="lbl"><b>{name}</b><span>{mood}</span><code>{a}</code></span>
      </button>''')
rep('      <!--PAL-->', '\n'.join(cards))

# ---- 5. شاشة الزائر: بطاقة التعريف بعد الروابط، وتبديل تجريبي تحت الهاتف
intro_visitor = """            <div class="intro" id="vIntroVoice" data-intro="voice">
              <button class="play" data-play="v" aria-label="تشغيل التعريف الصوتي">@@play@@</button>
              <div class="body"><span class="t">فهد يعرّف بنفسه<span class="tag" style="font-size:10.5px;padding:2px 7px">صوت</span></span><div class="wave" aria-hidden="true"></div><span class="d"><span data-pos="v">0:00</span> / <span data-dur="v">0:42</span> · سُجّل قبل أسبوعين</span></div>
              <button class="more" data-tabgo="about">عنه</button>
            </div>
            <div class="vid" id="vIntroVideo" data-intro="video" hidden>
              <img src="@@p274@@" alt="فيديو تعريفي: فهد في شارع التحلية ليلاً">
              <button class="mute" aria-label="كتم الصوت">@@mute@@</button>
              <button class="play" data-play="v" aria-label="تشغيل الفيديو التعريفي">@@play@@</button>
              <div class="cap"><span>فهد يعرّف بنفسه · فيديو</span><span><span data-pos="v">0:00</span> / <span data-dur="v">0:28</span></span></div>
              <div class="bar"><i data-bar="v"></i></div>
            </div>
"""
rep("""            <div class="stats">
              <button class="stat" data-tabgo="posts"><b>128</b><small>منشور</small></button>""",
intro_visitor + """            <div class="stats">
              <button class="stat" data-tabgo="posts"><b>128</b><small>منشور</small></button>""")
rep("""      <p class="note">غلاف وصورة واسم واسم مستخدم وعلامة توثيق، مدينة وحي، نبذة وروابط، أرقام، أزرار متابعة ومراسلة ومشاركة، شريط الثقة، ثم ست تبويبات. جرّب زر «متابعة» والتبويبات.</p>""",
"""      <div class="demo"><span>نوع التعريف في النموذج:</span><div class="seg3" id="demoKind"><button class="on" data-kind="voice">صوت ٠:٤٢</button><button data-kind="video">فيديو ٠:٢٨</button></div></div>
      <p class="note">تحت النبذة بطاقة «فهد يعرّف بنفسه»: صوت بموجة وزر تشغيل، أو فيديو أفقي قصير يعمل صامتاً حتى يُضغط. اضغط التشغيل لتجربة التقدّم. الباقي كما كان: التوثيق، الأرقام، شريط الثقة، وست تبويبات.</p>""")

# ---- 6. شاشة صاحب الحساب: البطاقة قبل اكتمال الملف + خطوة التعريف
intro_owner = """            <div class="intro" id="oIntroVoice" data-intro="voice">
              <button class="play" data-play="o" aria-label="تشغيل تعريفي الصوتي">@@play@@</button>
              <div class="body"><span class="t">تعريفي الصوتي<span class="tag" style="font-size:10.5px;padding:2px 7px">صوت</span></span><div class="wave" aria-hidden="true"></div><span class="d"><span data-pos="o">0:00</span> / <span data-dur="o">0:42</span> · ٨٦ استماعاً هذا الأسبوع</span></div>
              <button class="more" data-go="edit">تغيير</button>
            </div>
            <div class="vid" id="oIntroVideo" data-intro="video" hidden>
              <img src="@@p274@@" alt="فيديوي التعريفي">
              <button class="mute" aria-label="كتم الصوت">@@mute@@</button>
              <button class="play" data-play="o" aria-label="تشغيل الفيديو التعريفي">@@play@@</button>
              <div class="cap"><span>تعريفي · ١٣٤ مشاهدة</span><span><span data-pos="o">0:00</span> / <span data-dur="o">0:28</span></span></div>
              <div class="bar"><i data-bar="o"></i></div>
            </div>
            <button class="intro" id="oIntroEmpty" data-go="edit" hidden style="border-style:dashed;cursor:pointer;text-align:right;font-family:var(--font-body)">
              <span class="play" style="background:var(--a-soft);color:var(--a)">@@mic@@</span>
              <span class="body"><span class="t">عرّف بنفسك بصوتك أو بفيديو</span><span class="d">٦٠ ثانية صوت أو ٣٠ ثانية فيديو · يرفع الثقة والرسائل من ملفك</span></span>
              @@chev@@
            </button>
"""
rep("""            <div class="done">
              <div style="display:flex;justify-content:space-between;align-items:center"><span style="font-size:13.5px;font-weight:700">اكتمال الملف <span id="pct">50</span>٪</span><span id="left" style="font-size:12px">خطوتان متبقيتان</span></div>
              <div style="height:8px;background:rgba(90,66,0,.15);border-radius:999px;overflow:hidden"><div id="pctbar" style="width:50%;height:100%;background:#875C0A;border-radius:999px;transition:width .2s"></div></div>""",
intro_owner + """            <div class="done">
              <div style="display:flex;justify-content:space-between;align-items:center"><span style="font-size:13.5px;font-weight:700">اكتمال الملف <span id="pct">60</span>٪</span><span id="left" style="font-size:12px">خطوتان متبقيتان</span></div>
              <div style="height:8px;background:rgba(90,66,0,.15);border-radius:999px;overflow:hidden"><div id="pctbar" style="width:60%;height:100%;background:#875C0A;border-radius:999px;transition:width .2s"></div></div>""")
rep("""                <button class="step" data-done="أضفت رابط إنستغرام" data-todo="أضف رابطاً واحداً على الأقل"><span class="ck"></span><span>أضف رابطاً واحداً على الأقل</span></button>""",
"""                <div id="introStep" style="display:flex;align-items:center;gap:8px"><span class="ck y">@@tick@@</span><span id="introStepText">تعريف صوتي مسجّل</span></div>
                <button class="step" data-done="أضفت رابط إنستغرام" data-todo="أضف رابطاً واحداً على الأقل"><span class="ck"></span><span>أضف رابطاً واحداً على الأقل</span></button>""")
rep("""      <p class="note">الرأس نفسه مع «تعديل الملف» و«كزائر»، اكتمال الملف بخطوات (اضغط الخطوتين)، إحصاءات آخر ٧ أيام، والتبويبات بأدوات الإدارة: مشاهدات كل منشور، مسودّات، طلب بانتظار التأكيد، الحجز القادم، وتقييم بلا ردّ.</p>""",
"""      <p class="note">بطاقة التعريف مع عدد الاستماعات أو المشاهدات وزر «تغيير»، وإن حُذف التعريف تظهر دعوة لإضافته وتصبح خطوة في اكتمال الملف (خمس خطوات الآن). الباقي: إحصاءات ٧ أيام والتبويبات بأدوات الإدارة.</p>""")

# ---- 7. شاشة التعديل: قسم «عرّف بنفسك» بعد النبذة
edit_block = """          <div class="field" style="gap:8px" id="introField">
            <div style="display:flex;justify-content:space-between;align-items:center"><span class="lb">عرّف بنفسك بصوتك أو بفيديو</span><span class="muted" style="font-size:12px">اختياري · يظهر أعلى ملفك</span></div>
            <div class="kind2" id="introKind">
              <button data-kind="voice" class="on"><span class="ico">@@mic@@</span><span class="tt"><b>تسجيل صوتي</b><small>حتى ٦٠ ثانية</small></span></button>
              <button data-kind="video"><span class="ico">@@cam@@</span><span class="tt"><b>فيديو قصير</b><small>حتى ٣٠ ثانية · أفقي</small></span></button>
            </div>
            <!-- voice: recorded -->
            <div class="recbox" id="voiceHave">
              <div class="intro" style="border:0;padding:0">
                <button class="play" data-play="e" aria-label="استماع">@@play@@</button>
                <div class="body"><span class="t">تعريفي الصوتي</span><div class="wave" aria-hidden="true"></div><span class="d"><span data-pos="e">0:00</span> / <span data-dur="e">0:42</span></span></div>
              </div>
              <div class="recrow"><button class="btn sm ghost" data-act="rerec">@@mic@@إعادة التسجيل</button><button class="btn sm ghost" data-act="del" style="color:#D23B3B;border-color:#F3C9C9">حذف</button></div>
            </div>
            <!-- voice: empty -->
            <div class="recbox empty" id="voiceEmpty" hidden>
              <button class="recbtn" data-act="rec" aria-label="ابدأ التسجيل">@@mic@@</button>
              <span style="font-size:13.5px;font-weight:600">اضغط للتسجيل</span>
              <span class="muted" style="font-size:12px">من أنت، وماذا تقدّم، وأين تعمل. حتى ٦٠ ثانية.</span>
            </div>
            <!-- voice: recording -->
            <div class="recbox" id="voiceRec" hidden style="align-items:center;gap:10px">
              <span style="display:inline-flex;align-items:center;gap:8px;font:700 22px var(--font-body);font-variant-numeric:tabular-nums"><i style="width:10px;height:10px;border-radius:999px;background:#D23B3B;display:inline-block"></i><span id="recTime">0:00</span><span class="muted" style="font-size:12px;font-weight:500">/ 1:00</span></span>
              <div class="wave" id="recWave" style="width:100%;height:32px" aria-hidden="true"></div>
              <button class="recbtn rec" data-act="stop" aria-label="إيقاف التسجيل"><svg width="22" height="22" viewBox="0 0 24 24" fill="#fff"><rect x="6" y="6" width="12" height="12" rx="2"/></svg></button>
              <span class="muted" style="font-size:12px">يتوقف تلقائياً عند الدقيقة</span>
            </div>
            <!-- video: recorded -->
            <div class="recbox" id="videoHave" hidden>
              <div class="vid" style="border-radius:12px">
                <img src="@@p274@@" alt="الفيديو التعريفي">
                <button class="play" data-play="e" aria-label="معاينة">@@play@@</button>
                <div class="cap"><span>فيديوي التعريفي</span><span><span data-pos="e">0:00</span> / <span data-dur="e">0:28</span></span></div>
                <div class="bar"><i data-bar="e"></i></div>
              </div>
              <div class="recrow"><button class="btn sm ghost" data-act="rerec">@@cam@@إعادة التصوير</button><button class="btn sm ghost" data-act="pick">من الاستوديو</button><button class="btn sm ghost" data-act="del" style="color:#D23B3B;border-color:#F3C9C9">حذف</button></div>
            </div>
            <!-- video: empty -->
            <div class="recbox empty" id="videoEmpty" hidden>
              <button class="recbtn" data-act="rec" aria-label="ابدأ التصوير">@@cam@@</button>
              <span style="font-size:13.5px;font-weight:600">صوّر فيديو قصيراً</span>
              <span class="muted" style="font-size:12px">أفقي، حتى ٣٠ ثانية، بالكاميرا الأمامية. أو <button data-act="pick" style="border:0;background:transparent;padding:0;color:var(--a);font:600 12px var(--font-body);cursor:pointer">اختر من الاستوديو</button></span>
            </div>
            <!-- video: recording -->
            <div class="cam" id="videoRec" hidden>
              <img src="@@avatar@@" alt="">
              <span class="rectag"><i></i><span id="camTime">0:00</span> / 0:30</span>
              <button class="stop" data-act="stop" aria-label="إيقاف التصوير"><i></i></button>
            </div>
            <span class="muted" style="font-size:11.5px">يُراجَع آلياً قبل الظهور (كلمات ممنوعة وضجيج)، ويمكن قصره على الأصدقاء من «التوثيق والتحكم».</span>
          </div>
"""
rep("""          <div class="field">
            <span class="lb">نوع الحساب</span>""", edit_block + """          <div class="field">
            <span class="lb">نوع الحساب</span>""")
rep("""      <p class="note">الاسم المعروض، اسم المستخدم مع فحص التوفر الحي (جرّب كتابة fahad أو أحرف عربية)، النبذة بعدّاد ١٦٠، نوع الحساب شخصي/مهني، المدينة والحي، المهارات، الروابط. الرقم SA ثابت.</p>""",
"""      <p class="note">الجديد «عرّف بنفسك»: اختر صوتاً أو فيديو، جرّب «حذف» ثم «اضغط للتسجيل» فيعدّ المؤقّت ويتوقف عند الحد، ثم «استماع». ما تسجّله هنا ينعكس في شاشتي الزائر وصاحب الحساب. الباقي: الاسم، اسم المستخدم مع فحص التوفر، النبذة، نوع الحساب، المدينة والحي، المهارات، الروابط.</p>""")

# ---- 8. شاشة التوثيق والتحكم: صف التعريف
rep("""              <label><div class="body"><span class="t">المدينة والحي</span><span class="d">جدة · حي الشاطئ</span></div><input class="sw" type="checkbox" checked aria-label="إظهار المدينة والحي"></label>""",
"""              <label><div class="body"><span class="t">المدينة والحي</span><span class="d">جدة · حي الشاطئ</span></div><input class="sw" type="checkbox" checked aria-label="إظهار المدينة والحي"></label>
              <label><div class="body"><span class="t">التعريف الصوتي أو المرئي</span><span class="d" id="introPrivHint">للجميع · أطفئه ليظهر للأصدقاء فقط</span></div><input class="sw" id="introPriv" type="checkbox" checked aria-label="إظهار التعريف للجميع"></label>""")

# ---- 9. السكربت: اللوحات، الحالة المشتركة للتعريف، الاكتمال
rep("""  // completion steps
  var steps = document.querySelectorAll('.step'), pct = document.getElementById('pct'), bar = document.getElementById('pctbar'), left = document.getElementById('left');
  steps.forEach(function(s){ s.addEventListener('click', function(){
    var on = s.classList.toggle('y'); var ck = s.querySelector('.ck'); ck.classList.toggle('y', on);
    ck.innerHTML = on ? '<svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"><path d="M5 13l4 4L19 7"/></svg>' : '';
    s.lastElementChild.textContent = on ? s.getAttribute('data-done') : s.getAttribute('data-todo');
    var n = 2 + document.querySelectorAll('.step.y').length; pct.textContent = n*25; bar.style.width = (n*25)+'%';
    left.textContent = n===4 ? 'اكتمل ملفك' : (n===3 ? 'خطوة واحدة متبقية' : 'خطوتان متبقيتان');
  }); });""",
"""  // palettes: the phones stay white; only --a/--a-soft/--a-ink change
  var palBtns = document.querySelectorAll('#pal button');
  function setPal(p){
    document.documentElement.setAttribute('data-p', p);
    palBtns.forEach(function(b){ var on = b.getAttribute('data-p')===p; b.classList.toggle('on', on); b.setAttribute('aria-checked', on ? 'true' : 'false'); });
    try { localStorage.setItem('nl-proto-pal', p); } catch(e){}
  }
  palBtns.forEach(function(b){ b.addEventListener('click', function(){ setPal(b.getAttribute('data-p')); }); });
  try { var sp = localStorage.getItem('nl-proto-pal'); if (sp && document.querySelector('#pal [data-p="'+sp+'"]')) setPal(sp); else setPal('teal'); } catch(e){ setPal('teal'); }

  // completion steps (5 items: photo+cover+bio, verification, intro, link, portfolio)
  var steps = document.querySelectorAll('.step'), pct = document.getElementById('pct'), bar = document.getElementById('pctbar'), left = document.getElementById('left');
  var TICK = '<svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"><path d="M5 13l4 4L19 7"/></svg>';
  function updateCompletion(){
    var n = 2 + (intro.has ? 1 : 0) + document.querySelectorAll('.step.y').length; pct.textContent = n*20; bar.style.width = (n*20)+'%';
    var leftN = 5 - n; left.textContent = leftN===0 ? 'اكتمل ملفك' : (leftN===1 ? 'خطوة واحدة متبقية' : (leftN===2 ? 'خطوتان متبقيتان' : leftN+' خطوات متبقية'));
  }
  steps.forEach(function(s){ s.addEventListener('click', function(){
    var on = s.classList.toggle('y'); var ck = s.querySelector('.ck'); ck.classList.toggle('y', on);
    ck.innerHTML = on ? TICK : '';
    s.lastElementChild.textContent = on ? s.getAttribute('data-done') : s.getAttribute('data-todo');
    updateCompletion();
  }); });

  // self-introduction: one shared state drives the visitor card, the owner card and the edit screen
  var intro = { kind:'voice', has:true, sec:{voice:42, video:28} };
  var playing = null; // {who, timer, pos}
  function mmss(n){ n = Math.round(n); return Math.floor(n/60)+':'+('0'+(n%60)).slice(-2); }
  function buildWave(el, n){ if (el.childElementCount) return; var seed = 7; for (var i=0;i<n;i++){ seed = (seed*9301+49297)%233280; var h = 25 + Math.round((seed/233280)*70); var b = document.createElement('i'); b.style.height = h+'%'; el.appendChild(b); } }
  document.querySelectorAll('.wave').forEach(function(w){ buildWave(w, w.id==='recWave' ? 40 : 30); });
  function stopPlay(){
    if (!playing) return; clearInterval(playing.timer);
    document.querySelectorAll('[data-play]').forEach(function(b){ b.innerHTML = PLAY; });
    document.querySelectorAll('.intro.playing,.vid.playing').forEach(function(x){ x.classList.remove('playing'); });
    document.querySelectorAll('.wave i.on').forEach(function(i){ i.classList.remove('on'); });
    document.querySelectorAll('[data-pos]').forEach(function(p){ p.textContent = '0:00'; });
    document.querySelectorAll('[data-bar]').forEach(function(p){ p.style.width = '0'; });
    playing = null;
  }
  var PLAY = document.querySelector('[data-play]').innerHTML;
  var PAUSE = '<svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="5" width="4" height="14" rx="1"/><rect x="14" y="5" width="4" height="14" rx="1"/></svg>';
  function tickPlay(){
    playing.pos += 1; var dur = intro.sec[intro.kind]; var f = playing.pos / dur;
    var box = playing.box;
    box.querySelectorAll('[data-pos]').forEach(function(p){ p.textContent = mmss(playing.pos); });
    var wave = box.querySelector('.wave'); if (wave) { var bars = wave.children; for (var i=0;i<bars.length;i++) bars[i].classList.toggle('on', i/bars.length < f); }
    var bar = box.querySelector('[data-bar]'); if (bar) bar.style.width = (f*100)+'%';
    if (playing.pos >= dur) stopPlay();
  }
  document.addEventListener('click', function(e){
    var b = e.target.closest('[data-play]'); if (!b) return;
    var box = b.closest('.intro, .vid');
    if (playing && playing.box === box) { stopPlay(); return; }
    stopPlay();
    playing = { box: box, pos: 0, timer: setInterval(tickPlay, 1000) };
    box.classList.add('playing'); b.innerHTML = PAUSE;
  });
  function renderIntro(){
    stopPlay();
    var v = intro.kind==='voice', has = intro.has;
    document.getElementById('vIntroVoice').hidden = !(has && v);
    document.getElementById('vIntroVideo').hidden = !(has && !v);
    document.getElementById('oIntroVoice').hidden = !(has && v);
    document.getElementById('oIntroVideo').hidden = !(has && !v);
    document.getElementById('oIntroEmpty').hidden = has;
    document.querySelectorAll('[data-dur]').forEach(function(d){ d.textContent = mmss(intro.sec[intro.kind]); });
    document.querySelectorAll('#introKind button').forEach(function(x){ x.classList.toggle('on', x.getAttribute('data-kind')===intro.kind); });
    document.querySelectorAll('#demoKind button').forEach(function(x){ x.classList.toggle('on', x.getAttribute('data-kind')===intro.kind); });
    document.getElementById('voiceHave').hidden = !(v && has);
    document.getElementById('voiceEmpty').hidden = !(v && !has);
    document.getElementById('videoHave').hidden = !(!v && has);
    document.getElementById('videoEmpty').hidden = !(!v && !has);
    document.getElementById('voiceRec').hidden = true; document.getElementById('videoRec').hidden = true;
    var st = document.getElementById('introStep'), ck = st.querySelector('.ck');
    ck.classList.toggle('y', has); ck.innerHTML = has ? TICK : '';
    document.getElementById('introStepText').textContent = has ? (v ? 'تعريف صوتي مسجّل' : 'فيديو تعريفي مرفوع') : 'أضف تعريفاً صوتياً أو مرئياً';
    updateCompletion();
  }
  document.querySelectorAll('#introKind button, #demoKind button').forEach(function(b){ b.addEventListener('click', function(){ intro.kind = b.getAttribute('data-kind'); intro.has = true; intro.sec = {voice:42, video:28}; renderIntro(); }); });
  var recTimer = null, recSec = 0;
  function stopRec(){ clearInterval(recTimer); recTimer = null; intro.has = true; intro.sec[intro.kind] = Math.max(1, recSec); renderIntro(); }
  document.addEventListener('click', function(e){
    var b = e.target.closest('[data-act]'); if (!b) return;
    var act = b.getAttribute('data-act'), v = intro.kind==='voice';
    if (act==='del') { intro.has = false; renderIntro(); }
    if (act==='pick') { intro.has = true; intro.sec.video = 24; renderIntro(); }
    if (act==='rec' || act==='rerec') {
      stopPlay(); recSec = 0; var limit = v ? 60 : 30;
      ['voiceHave','voiceEmpty','videoHave','videoEmpty'].forEach(function(id){ document.getElementById(id).hidden = true; });
      document.getElementById(v ? 'voiceRec' : 'videoRec').hidden = false;
      var t = document.getElementById(v ? 'recTime' : 'camTime'); t.textContent = '0:00';
      var rw = document.getElementById('recWave'); Array.prototype.forEach.call(rw.children, function(i){ i.classList.remove('on'); });
      recTimer = setInterval(function(){
        recSec += 1; t.textContent = mmss(recSec);
        if (v) { var bars = rw.children; for (var i=0;i<bars.length;i++) bars[i].classList.toggle('on', i < recSec*bars.length/limit); }
        if (recSec >= limit) stopRec();
      }, 1000);
    }
    if (act==='stop') stopRec();
  });
  var ip = document.getElementById('introPriv');
  ip.addEventListener('change', function(){ document.getElementById('introPrivHint').textContent = ip.checked ? 'للجميع · أطفئه ليظهر للأصدقاء فقط' : 'للأصدقاء فقط · الزوار يرون النبذة المكتوبة'; });
  renderIntro();""")

# ---- 10. رموز جديدة تُحلّ عند البناء
extra = {
 'play': '<svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5.5v13a1 1 0 0 0 1.5.86l11-6.5a1 1 0 0 0 0-1.72l-11-6.5A1 1 0 0 0 8 5.5z"/></svg>',
 'mic': '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0"/><path d="M12 18v3"/></svg>',
 'cam': '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="7" width="13" height="10" rx="2"/><path d="M16 11l5-3v8l-5-3z"/></svg>',
 'mute': '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M11 5L6 9H3v6h3l5 4z"/><path d="M22 9l-6 6"/><path d="M16 9l6 6"/></svg>',
 'tick': '<svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"><path d="M5 13l4 4L19 7"/></svg>',
}
# الأيقونات الجديدة محفوظة في icons.json؛ البناء عبر build.py
icons_path = root / 'icons.json'
icons = json.loads(icons_path.read_text(encoding='utf-8')); icons.update(extra)
icons_path.write_text(json.dumps(icons, ensure_ascii=False, indent=1), encoding='utf-8')
(root / 'template_colors.html').write_text(s, encoding='utf-8')
print('template_colors.html', len(s))
