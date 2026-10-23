// رفع الوسائط (lib/api/chat_tools_api.dart): مهلة الفيديو خمس دقائق لأن الخادم يرمّزه في طابور، ولا إعادة رفع تلقائية عند
// المهلة (كانت ترفع 30 م.ب مرة ثانية وتبدأ ترميزاً ثانياً بجانب الأول)؛ الإعادة بلا x-file-name فقط حين يرفض المتصفح الترويسة فوراً.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:naslook/api/chat_tools_api.dart';
import 'package:naslook/api/client.dart';

void main() {
  final bytes = Uint8List.fromList(List.filled(64, 1));

  test('video uploads wait five minutes, other media three', () {
    expect(uploadTimeoutFor('video/mp4'), const Duration(minutes: 5));
    expect(uploadTimeoutFor('video/quicktime', fileName: 'clip.mov'), const Duration(minutes: 5));
    expect(uploadTimeoutFor('application/octet-stream', fileName: 'clip.MOV'), const Duration(minutes: 5));
    expect(uploadTimeoutFor('image/jpeg', fileName: 'p.jpg'), const Duration(minutes: 3));
    expect(uploadTimeoutFor('audio/webm'), const Duration(minutes: 3));
  });

  test('only an immediate network failure counts as a header rejection', () {
    const rejected = ApiException(0, 'تعذر الاتصال بالخادم: Type error');
    expect(isHeaderRejection(rejected, const Duration(milliseconds: 20)), isTrue);
    expect(isHeaderRejection(rejected, const Duration(seconds: 40)), isFalse, reason: 'انقطاع بعد إرسال الجسم قد يكون وصل الخادم');
    expect(isHeaderRejection(const ApiException(0, 'انتهت مهلة الاتصال بالخادم'), Duration.zero), isFalse);
    expect(isHeaderRejection(const ApiException(500, 'خطأ'), Duration.zero), isFalse);
  });

  test('header rejected by the browser: retried once without x-file-name', () async {
    final names = <String?>[];
    final api = ApiClient(
      baseUrl: 'https://test.local',
      httpClient: MockClient((req) async {
        names.add(req.headers['x-file-name']);
        if (req.headers.containsKey('x-file-name')) throw http.ClientException('Type error', req.url);
        return http.Response(jsonEncode({'url': '/chat/media/a.jpg', 'type': 'image/jpeg', 'kind': 'image', 'size': 64}), 200);
      }),
    );
    final up = await api.uploadMedia(bytes, contentType: 'image/jpeg', fileName: 'صورة.jpg');
    expect(up.url, '/chat/media/a.jpg');
    expect(names, ['file.jpg', null]);
  });

  testWidgets('a slow video encode times out after five minutes without a second upload', (tester) async {
    var calls = 0;
    final api = ApiClient(
      baseUrl: 'https://test.local',
      httpClient: MockClient((req) {
        calls++;
        return Completer<http.Response>().future; // الخادم ما زال يرمّز
      }),
    );
    Object? error;
    var done = false;
    unawaited(api.uploadMedia(bytes, contentType: 'video/mp4', fileName: 'clip.mp4').then((_) => done = true, onError: (Object e) {
      error = e;
      done = true;
    }));
    await tester.pump(const Duration(minutes: 4));
    expect(done, isFalse, reason: 'ثلاث دقائق لا تكفي رفع الفيديو وترميزه');
    await tester.pump(const Duration(minutes: 1, seconds: 1));
    expect(done, isTrue);
    expect(error, isA<ApiException>().having((e) => e.isNetwork, 'isNetwork', isTrue));
    await tester.pump(const Duration(minutes: 6));
    expect(calls, 1, reason: 'لا إعادة رفع تلقائية بعد المهلة');
  });

  test('a late network failure is not retried either', () async {
    var calls = 0;
    final api = ApiClient(
      baseUrl: 'https://test.local',
      httpClient: MockClient((req) async {
        calls++;
        throw http.ClientException('Load failed', req.url);
      }),
    );
    // المهلة الحقيقية (Stopwatch) لا تتقدم في الوقت الوهمي، فنحاكي فشلاً «متأخراً» بالدالة نفسها
    expect(isHeaderRejection(const ApiException(0, 'تعذر الاتصال بالخادم: Load failed'), const Duration(seconds: 30)), isFalse);
    // وفشل فوري بلا اسم ملف لا يُعاد أصلاً (لا ترويسة لإسقاطها)
    await expectLater(api.uploadMedia(bytes, contentType: 'video/mp4'), throwsA(isA<ApiException>()));
    expect(calls, 1);
  });
}
