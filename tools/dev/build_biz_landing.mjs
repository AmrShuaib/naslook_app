// يولّد server/biz_landing_data.js: صفحة /business ونماذج التسجيل /business/register (مع سكربتها) من docs/reports/screens/naslife-business*.
// المصدر جزء صفحة (title + style + محتوى) كما يُنشر معاينةً؛ هنا نغلّفه بوثيقة كاملة للموقع الحي:
// نحذف خطوط Google (سياسة الأمان تمنعها) ونعرّف خطوط التطبيق من /assets/fonts، ونرفض أي سكربت لأن المضمّن منها محجوب.
// التشغيل: node tools/dev/build_biz_landing.mjs   ثم التزم server/biz_landing_data.js
import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), '../..');
const SRC = path.join(ROOT, 'docs/reports/screens');
const font = (fam, w, f) => `@font-face{font-family:'${fam}';font-weight:${w};font-display:swap;src:url('/assets/fonts/${f}') format('truetype')}`;
const FONTS = [font('Rubik', 400, 'Rubik-Regular.ttf'), font('Rubik', 500, 'Rubik-Medium.ttf'), font('Rubik', 700, 'Rubik-Bold.ttf'), font('Baloo Bhaijaan 2', '600 800', 'BalooBhaijaan2-Bold.ttf')].join('');
function doc(file, title, desc, script) {
  let s = fs.readFileSync(path.join(SRC, file), 'utf8');
  if (/<script/i.test(s)) throw new Error(file + ': الصفحة يجب أن تكون بلا سكربتات مضمّنة');
  s = s.replace(/<title>[\s\S]*?<\/title>/g, '').replace(/<meta[^>]*>/g, '').replace(/<link[^>]*>/g, '').trim();
  // الروابط إلى الموقع نفسه تصير نسبية (المصدر يكتبها كاملة ليعمل معاينةً خارج الموقع)
  s = s.replace(/href="https:\/\/naslife\.app\/(business[^"]*)"/g, 'href="/$1"');
  const ext = [...s.matchAll(/(?:src|href)="(https?:\/\/[^"]+)"/g)].map((m) => m[1]).filter((u) => !u.startsWith('https://naslife.app/'));
  if (ext.length) throw new Error(file + ': موارد خارجية: ' + ext.slice(0, 3).join(' , '));
  return '<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8">' +
    '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">' +
    '<meta name="robots" content="noindex,nofollow"><meta name="theme-color" content="#FFFFFF">' +
    `<title>${title}</title><meta name="description" content="${desc}">` +
    `<meta property="og:title" content="${title}"><meta property="og:description" content="${desc}"><meta property="og:type" content="website">` +
    '<link rel="icon" type="image/png" href="/favicon.png">' +
    `<style>${FONTS}</style></head><body>${s}${script ? `<script src="${script}"></script>` : ''}</body></html>`;
}
const html = doc('naslife-business.html', 'ناس لايف للأعمال · سجّل دائرتك', 'اجعل نشاطك أقرب إلى عملائه: دائرة لنشاطك على خريطة ناس لايف، بواجهة يراها عملاؤك ومكتب يديره فريقك.');
const reg = doc('naslife-business-register.html', 'تسجيل دائرة · ناس لايف للأعمال', 'نموذج تسجيل الدائرة للمنشآت بسجل تجاري ولأصحاب العمل الحر.', '/business/register.js');
const regJs = fs.readFileSync(path.join(SRC, 'naslife-business-register.js'), 'utf8');

const out = '// ملف مولَّد: لا تعدّله يدوياً. المصدر docs/reports/screens/naslife-business.html والمولّد tools/dev/build_biz_landing.mjs\n' +
  'export const HTML = ' + JSON.stringify(html) + ';\nexport const REGISTER_HTML = ' + JSON.stringify(reg) + ';\nexport const REGISTER_JS = ' + JSON.stringify(regJs) + ';\n';
fs.writeFileSync(path.join(ROOT, 'server/biz_landing_data.js'), out);
console.log('biz_landing_data.js', Math.round(out.length / 1024), 'KB');
