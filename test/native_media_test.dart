// أدوات الوسائط الأصلية: مسار التسجيل المؤقت (m4a/AAC)، الملفات المؤقتة وحذفها، أنواع الصوت، وأخطاء أذونات image_picker.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

import 'package:naslook/core/media/native_io.dart';
import 'package:naslook/core/media/permissions.dart';
import 'package:naslook/core/media/voice_record.dart';

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('naslife_media_test');
    tempDirOverride = () async => tmp.path;
  });
  tearDown(() {
    tempDirOverride = null;
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('native voice recording writes AAC to a real .m4a path under the temp dir', () async {
    final a = await nativeVoicePath();
    final b = await nativeVoicePath();
    expect(a, isNotEmpty, reason: 'record على iOS يفشل بمسار فارغ');
    expect(a, startsWith(tmp.path));
    expect(a, endsWith('.m4a'));
    expect(a, isNot(b), reason: 'كل تسجيل في ملف مستقل');
    expect(nativeVoiceConfig.encoder, AudioEncoder.aacLc);
    expect(nativeVoiceConfig.numChannels, 1);
  });

  test('temp files are written and deleted quietly', () async {
    final path = await writeTempFile([1, 2, 3], prefix: 'vp', ext: 'm4a');
    expect(File(path).readAsBytesSync(), [1, 2, 3]);
    await deleteQuietly(path);
    expect(File(path).existsSync(), isFalse);
    await deleteQuietly(path); // حذف ملف غير موجود لا يرمي
    await deleteQuietly(null);
  });

  test('audio mime and extension map both ways', () {
    expect(audioExt('audio/mp4'), 'm4a');
    expect(audioExt('audio/mpeg'), 'mp3');
    expect(audioExt('audio/wav'), 'wav');
    expect(audioExt('audio/webm;codecs=opus'), 'webm');
    expect(audioMimeOfExt('m4a'), 'audio/mp4');
    expect(audioMimeOfExt('ogg'), 'audio/ogg');
  });

  test('image_picker access-denied errors become MediaPermissionDenied', () {
    final cam = mapPickerError(PlatformException(code: 'camera_access_denied'), camera: true);
    expect(cam, isA<MediaPermissionDenied>().having((e) => e.what, 'what', 'camera'));
    final photos = mapPickerError(PlatformException(code: 'photo_access_denied'), camera: false);
    expect(photos, isA<MediaPermissionDenied>().having((e) => e.what, 'what', 'photos'));
    expect(photos.toString(), contains('الإعدادات'));
    final other = PlatformException(code: 'multiple_request');
    expect(mapPickerError(other, camera: false), same(other), reason: 'الأخطاء الأخرى كما هي');
  });

  test('isNativeMobile is false on the test host unless overridden', () {
    expect(isNativeMobile, isFalse);
    nativeMobileOverride = true;
    addTearDown(() => nativeMobileOverride = null);
    expect(isNativeMobile, isTrue);
  });
}
