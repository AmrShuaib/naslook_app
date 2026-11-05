import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/media/audio_setup.dart';
import 'core/media/video_view.dart';
import 'core/media/voice_player.dart';
import 'core/share/share_links.dart';
import 'state/admin_providers.dart';
import 'state/notify_providers.dart';

/// Naslife v2 — الدخول بالنك نيم + الرقم السري عبر خادم Node/Fastify.
/// لا يوجد اعتماد على Firebase في هذه النسخة.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  captureAdminMode();
  capturePendingNotification();
  capturePendingLink();
  // جلسة الصوت على iOS/Android فقط (لا تعمل على الويب)؛ لا ننتظرها حتى لا تؤخر أول إطار
  unawaited(configureAudioSession());
  // الويب: أول لمسة في التطبيق تفتح عناصر فيديو اللحظات وعنصر <audio> لطبقتها الصوتية (سفاري iOS) فتبدأ أول لحظة بصوتها
  // حين تُفتح بلمسة، ولو فُتح العارض بعد انتظار شبكة (المحفوظات، بطاقة #post في المحادثة): pointerup اللمسة يسبق الانتظار
  VideoView.prepareSound();
  VoicePlayer.prepareSound();
  runApp(const ProviderScope(child: MainApp()));
}
