import 'media.dart';

bool get available => false;
Future<PickedMedia?> pick(String kind) async => throw UnsupportedError('WebMedia is web-only');
VoiceRecorder createRecorder() => throw UnsupportedError('VoiceRecorder is web-only');
