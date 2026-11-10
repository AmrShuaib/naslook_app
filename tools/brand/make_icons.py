"""يولّد أيقونات التطبيق من رمز الشعار (فقاعة المحادثة والأشخاص، بلا كلمة Naslife) بقرار المالك في 10 نوفمبر 2026.

الأصل: tools/brand/naslife_symbol.png (الرمز مقصوصاً من شعار المالك على أبيض).
التشغيل (يحتاج Pillow): python tools/brand/make_icons.py
المخرجات: أيقونات الويب (العادية والقابلة للقص maskable)، أيقونات iOS كلها من Contents.json (بلا شفافية كما تشترط أبل)،
أيقونات أندرويد، وtools/brand/app_icon_1024.png.
"""
import json
import os

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
SRC = os.path.join(ROOT, 'tools', 'brand', 'naslife_symbol.png')
WHITE = (255, 255, 255)

# نسبة الرمز من عرض الأيقونة: العادية تترك هامشاً لقناع الزوايا، والقابلة للقص داخل الدائرة الآمنة (80%)،
# والأيقونة الصغيرة جداً (favicon) أكبر حتى تُقرأ خطوطها
REGULAR, MASKABLE, TINY = 0.74, 0.56, 0.92


def icon(size, frac):
    sym = Image.open(SRC).convert('RGB')
    w, h = sym.size
    scale = frac * size / max(w, h)
    nw, nh = max(1, round(w * scale)), max(1, round(h * scale))
    # التصغير على مرحلتين أنعم للمقاسات الصغيرة
    small = sym.resize((nw * 4, nh * 4), Image.LANCZOS).resize((nw, nh), Image.LANCZOS) if size < 128 else sym.resize((nw, nh), Image.LANCZOS)
    canvas = Image.new('RGB', (size, size), WHITE)
    canvas.paste(small, ((size - nw) // 2, (size - nh) // 2))
    return canvas


def save(img, rel):
    path = os.path.join(ROOT, rel)
    img.save(path, optimize=True)
    print(f'{rel} {img.size[0]}')


def main():
    save(icon(32, TINY), 'web/favicon.png')
    save(icon(192, REGULAR), 'web/icons/Icon-192.png')
    save(icon(512, REGULAR), 'web/icons/Icon-512.png')
    save(icon(192, MASKABLE), 'web/icons/Icon-maskable-192.png')
    save(icon(512, MASKABLE), 'web/icons/Icon-maskable-512.png')
    save(icon(1024, REGULAR), 'tools/brand/app_icon_1024.png')

    ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    with open(os.path.join(ROOT, ios, 'Contents.json'), encoding='utf-8') as f:
        images = json.load(f)['images']
    done = set()
    for im in images:
        name = im.get('filename')
        if not name or name in done:
            continue
        done.add(name)
        px = round(float(im['size'].split('x')[0]) * int(im['scale'].rstrip('x')))
        save(icon(px, REGULAR), f'{ios}/{name}')

    for d, px in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
        save(icon(px, REGULAR), f'android/app/src/main/res/mipmap-{d}/ic_launcher.png')


if __name__ == '__main__':
    main()
