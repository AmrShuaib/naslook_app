// حارس روابط الوسائط على التطبيق الأصلي: الخادم يعيد مسارات نسبية (/chat/media/…)، وعلى iOS لا أصل للصفحة تُحلّ عليه،
// فـ Image.network('/chat/media/x.jpg') يرمي «No host specified». كل صورة شبكية يجب أن تمر عبر mediaUrl/thumbUrl.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:naslook/api/client.dart';

/// معاملات أولى مقبولة: دوال التحويل إلى رابط مطلق، أو نص يبدأ بأصل مطلق.
final _allowedArg = RegExp(r'''^(mediaUrl\(|thumbUrl\(|_api\.media\(|api\.media\(|'https?:|"https?:|'\$base|'\$\{base)''');

/// استثناءات موثّقة: المعامل رابط مطلق مسبقاً.
const _allowed = <String>{
  // widget.mediaUrl في فقاعة المحادثة مبني بـ _api.media() عند إنشاء الفقاعة
  'lib/pages/chat/chat_thread_page.dart: Image.network(url)',
};

void main() {
  test('every Image.network / NetworkImage in lib/ resolves relative server paths', () {
    final offenders = <String>[];
    final call = RegExp(r'(Image\.network|NetworkImage)\(\s*');
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final src = f.readAsStringSync();
      for (final m in call.allMatches(src)) {
        final rest = src.substring(m.end);
        if (_allowedArg.hasMatch(rest)) continue;
        final arg = rest.split(RegExp(r'[,)]')).first.trim();
        final id = '${f.path.replaceAll(r'\', '/')}: ${m.group(1)}($arg)';
        if (_allowed.contains(id)) continue;
        final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
        offenders.add('$id  (line $line)');
      }
    }
    expect(offenders, isEmpty, reason: 'غلّف الرابط بـ mediaUrl() أو thumbUrl() حتى يعمل على iOS');
  });

  test('mediaUrl and thumbUrl turn server paths into absolute URLs on the given base', () {
    const base = 'https://naslife.app';
    const path = '/chat/media/ab12cd-0123456789abcdef01234567.jpg';
    expect(mediaUrl(path, base: base), '$base$path');
    expect(Uri.parse(mediaUrl(path, base: base)).hasAuthority, isTrue);
    expect(Uri.parse(thumbUrl(path, base: base)).host, 'naslife.app');
    expect(mediaUrl('https://cdn.example.com/x.png', base: base), 'https://cdn.example.com/x.png', reason: 'الروابط الخارجية كما هي');
  });
}
