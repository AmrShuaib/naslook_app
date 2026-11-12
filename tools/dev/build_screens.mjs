// يولّد server/screens_data.js (محتوى معرض التصاميم على /screens) من نماذج HTML في docs/reports/screens/.
// كل نموذج صفحة مكتفية بذاتها (title + style + محتوى + script). هنا نفصلها: CSS، HTML، وJS في ملف مستقل،
// لأن سياسة الأمان في الموقع الحي تمنع السكربتات المضمّنة، ونحذف خطوط Google (ممنوعة أيضاً؛ الخطوط من التطبيق).
// التشغيل: node tools/dev/build_screens.mjs   ثم التزم server/screens_data.js
import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), '../..');
const SRC = path.join(ROOT, 'docs/reports/screens');
// ترتيب التبويبات
const TABS = [
  ['v3', 'النسخة الثالثة', 'الحل الوسط · منشورات الناس والمحادثات', 'naslife-v3.html'],
  ['more', 'شاشات إضافية', '15 شاشة · الاكتشاف ومكتبي ومساحتي والترحيب', 'naslife-more.html'],
  ['calm', 'النسخة الهادئة', '13 شاشة · أزرق واحد وأبيض غالب', 'naslife-screens.html'],
  ['vivid', 'النسخة القوية', '13 شاشة · حضور أكبر للألوان', 'naslife-screens-vivid.html'],
  ['shell', 'الهيكل', 'هاتف يعمل · الشريط والفلاتر ومساحتي ومكتبي', 'naslife-shell.html'],
  ['buy', 'الشراء من اللحظة', 'زر الفعل والورقة فوق الفيديو', 'moment-actions.html'],
  ['feed', 'التغذية العمودية', 'ستة أشكال للتغذية', 'vertical-feed.html'],
];

const pages = TABS.map(([id, title, sub, file]) => {
  let s = fs.readFileSync(path.join(SRC, file), 'utf8');
  let css = '', js = '';
  s = s.replace(/<style>([\s\S]*?)<\/style>/g, (_, c) => { css += c + '\n'; return ''; });
  s = s.replace(/<script(\s[^>]*)?>([\s\S]*?)<\/script>/g, (m, attrs, c) => { if (/type="application\/json"/.test(attrs || '')) return m; js += c + '\n'; return ''; });
  s = s.replace(/<title>[\s\S]*?<\/title>/g, '').replace(/<meta[^>]*>/g, '').replace(/<link[^>]*>/g, '');
  if (/<script(?![^>]*application\/json)/.test(s)) throw new Error(file + ': بقي سكربت مضمّن');
  return { id, title, sub, css, html: s.trim(), js };
});

const out = '// ملف مولَّد: لا تعدّله يدوياً. المصدر docs/reports/screens/ والمولّد tools/dev/build_screens.mjs\n' +
  'export const PAGES = ' + JSON.stringify(pages) + ';\n';
fs.writeFileSync(path.join(ROOT, 'server/screens_data.js'), out);
console.log(pages.map((p) => `${p.id} html=${Math.round(p.html.length / 1024)}K js=${Math.round(p.js.length / 1024)}K`).join(' | '), '| total', Math.round(out.length / 1024), 'KB');
