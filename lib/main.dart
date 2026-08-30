import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'audio/audio_session_setup.dart';
import 'audio/training_audio_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Portrait only -- the training screen's layout isn't designed for
  // landscape, and rotating mid-session would be a distraction from
  // the audio-only recognition task. iOS/Android also get a native
  // portrait-only declaration (Info.plist/AndroidManifest.xml) so the
  // constraint holds before Dart even starts.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await configureAudioSession();

  // iOS and Android only -- audio_service needs real platform-side
  // plumbing (AndroidManifest service/receiver, MainActivity extending
  // AudioServiceActivity) that only those two platforms have (section 42,
  // Android background audio); left off desktop/web, which this project
  // keeps buildable but doesn't target.
  if (Platform.isIOS || Platform.isAndroid) {
    trainingAudioHandler = await AudioService.init(
      builder: TrainingAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelName: 'Morse ICR training',
        androidNotificationChannelDescription:
            'Shows while a training session is running or paused, with '
            'Play/Pause controls.',
        // A Pause (unlike a Stop) doesn't end the session -- keeping the
        // service in the foreground through it, rather than dropping to
        // a lower-priority state Android is free to reclaim, is what
        // makes Resume from the lock screen reliable. The tradeoff: the
        // notification stays persistent (non-swipeable) through Pause
        // too, not just while actively training.
        androidStopForegroundOnPause: false,
      ),
    );
  }

  runApp(const MorseIcrApp());
}
