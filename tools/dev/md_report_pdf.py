#!/usr/bin/env python3
"""تحويل تقرير Markdown عربي إلى PDF بغلاف (Chromium headless + خطوط المستودع).
الاستخدام: python3 tools/dev/md_report_pdf.py docs/reports/x.md docs/reports/x.pdf "العنوان" "سطر فرعي"
يحتاج: pip install markdown ، و Chromium في /opt/pw-browsers (بيئة الجلسة)."""
import sys, os, re, subprocess, html, pathlib
import markdown

src, out = sys.argv[1], sys.argv[2]
title = sys.argv[3] if len(sys.argv) > 3 else pathlib.Path(src).stem
sub = sys.argv[4] if len(sys.argv) > 4 else ""
root = pathlib.Path(__file__).resolve().parents[2]
fonts = root / "fonts"
md = open(src, encoding="utf-8").read()
body = markdown.markdown(md, extensions=["tables", "fenced_code", "sane_lists"])
# أقسام المستوى الثاني تبدأ صفحة جديدة
body = re.sub(r"<h2>", '<h2 class="sec">', body).replace('<h2 class="sec">', '<h2 class="sec first">', 1)
css = f"""
@font-face {{ font-family: 'Rubik'; src: url('file://{fonts}/Rubik-Regular.ttf'); font-weight: 400; }}
@font-face {{ font-family: 'Rubik'; src: url('file://{fonts}/Rubik-Medium.ttf'); font-weight: 500; }}
@font-face {{ font-family: 'Rubik'; src: url('file://{fonts}/Rubik-SemiBold.ttf'); font-weight: 600; }}
@font-face {{ font-family: 'Rubik'; src: url('file://{fonts}/Rubik-Bold.ttf'); font-weight: 700; }}
@font-face {{ font-family: 'Baloo'; src: url('file://{fonts}/BalooBhaijaan2-Bold.ttf'); font-weight: 700; }}
@page {{ size: A4; margin: 16mm 14mm 18mm 14mm;
  @bottom-center {{ content: "{html.escape(title)} · صفحة " counter(page); font-family: Rubik, sans-serif; font-size: 8pt; color: #8a8178; }} }}
@page :first {{ margin: 0; @bottom-center {{ content: none; }} }}
:root {{ --ink:#1f1b16; --muted:#6b6257; --teal:#0A6E78; --teal-soft:#E0F3F4; --sun:#F5B500; --sun-soft:#FFF4D6; --line:#e6e1d8; }}
* {{ box-sizing: border-box; }}
html, body {{ margin: 0; padding: 0; }}
body {{ font-family: Rubik, 'Noto Naskh Arabic', sans-serif; color: var(--ink); font-size: 10pt; line-height: 1.7; direction: rtl; text-align: right; }}
.content {{ padding: 0; }}
h1 {{ font-size: 20pt; color: var(--teal); margin: 0 0 10pt; }}
h2.sec {{ break-before: page; font-size: 16pt; color: var(--teal); margin: 0 0 8pt; padding-bottom: 5pt; border-bottom: 2px solid var(--teal); }}
h2.sec.first {{ break-before: auto; }}
h3 {{ font-size: 12pt; margin: 12pt 0 5pt; break-after: avoid; }}
h4 {{ font-size: 10.5pt; color: var(--teal); margin: 9pt 0 3pt; }}
p {{ margin: 0 0 6pt; }}
ul, ol {{ margin: 0 0 7pt; padding-right: 18pt; padding-left: 0; }}
li {{ margin-bottom: 2pt; }}
strong {{ font-weight: 600; }}
code {{ font-family: 'DejaVu Sans Mono', monospace; font-size: 8.3pt; direction: ltr; unicode-bidi: isolate; background: #f3f0ea; padding: 0 2pt; border-radius: 3pt; overflow-wrap: anywhere; }}
pre {{ direction: ltr; text-align: left; background: #f3f0ea; padding: 6pt; border-radius: 5pt; font-size: 8pt; white-space: pre-wrap; }}
table {{ width: 100%; border-collapse: collapse; margin: 5pt 0 9pt; font-size: 8.2pt; line-height: 1.45; }}
th, td {{ border: 1px solid var(--line); padding: 3.5pt 4pt; vertical-align: top; text-align: right; }}
th {{ background: var(--teal-soft); color: var(--teal); font-weight: 600; }}
tr {{ break-inside: avoid; }}
tbody tr:nth-child(even) td {{ background: #faf8f4; }}
hr {{ border: 0; border-top: 1px solid var(--line); margin: 10pt 0; }}
blockquote {{ border-right: 4px solid var(--teal); background: var(--teal-soft); padding: 6pt 9pt; margin: 6pt 0; border-radius: 5pt; }}
.cover {{ height: 297mm; padding: 26mm 22mm; background: linear-gradient(160deg,#0A6E78 0%,#0c5560 55%,#17323a 100%); color:#fff; display:flex; flex-direction:column; justify-content:space-between; break-after: page; }}
.cover .brand {{ font-family: Baloo, Rubik, sans-serif; font-size: 30pt; font-weight: 700; }}
.cover h1 {{ color:#fff; font-size: 26pt; line-height: 1.4; margin: 0 0 10pt; }}
.cover .sub {{ font-size: 13pt; opacity: .92; }}
.cover .meta {{ font-size: 11pt; opacity: .9; line-height: 1.9; }}
.body {{ padding: 0 2mm; }}
"""
cover = f"""<section class="cover"><div><div class="brand">ناس لايف</div></div>
<div><h1>{html.escape(title)}</h1><div class="sub">{html.escape(sub)}</div></div>
<div class="meta">إعداد: عمرو حسن شعيب · Amr Hassan Shuaib<br>شركة أريب الرقمية · Areeb Digital<br>naslife.app</div></section>"""
page = f'<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8"><title>{html.escape(title)}</title><style>{css}</style></head><body>{cover}<div class="body">{body}</div></body></html>'
tmp = pathlib.Path(out).with_suffix(".html")
tmp.write_text(page, encoding="utf-8")
chrome = "/opt/pw-browsers/chromium_headless_shell-1194/chrome-linux/headless_shell"
if not os.path.exists(chrome): chrome = "/opt/pw-browsers/chromium-1194/chrome-linux/chrome"
subprocess.run([chrome, "--headless", "--no-sandbox", "--disable-gpu", "--no-pdf-header-footer", f"--print-to-pdf={out}", "--virtual-time-budget=8000", f"file://{tmp.resolve()}"], check=True, capture_output=True)
tmp.unlink()
print(out, os.path.getsize(out), "bytes")
