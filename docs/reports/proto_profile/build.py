# يبني نماذج البروفايل التفاعلية (HTML واحد بصور مضمّنة) من القوالب.
# الاستخدام: python3 build.py template_colors.html > out.html
# الرموز @@name@@: صور من img/ (اسم الملف بلا امتداد) أو أيقونات SVG من icons.json.
import base64, json, pathlib, re, sys
root = pathlib.Path(__file__).parent
icons = json.loads((root / 'icons.json').read_text(encoding='utf-8'))
def asset(name):
    if name in icons: return icons[name]
    for ext, mime in (('.jpg', 'image/jpeg'), ('.png', 'image/png')):
        p = root / 'img' / (name + ext)
        if p.exists(): return 'data:' + mime + ';base64,' + base64.b64encode(p.read_bytes()).decode()
    raise SystemExit('missing asset: ' + name)
src = (root / sys.argv[1]).read_text(encoding='utf-8')
sys.stdout.write(re.sub(r'@@([a-z0-9-]+)@@', lambda m: asset(m.group(1)), src))
