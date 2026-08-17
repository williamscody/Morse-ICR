import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart' as audio_session;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
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

  // Configured once, app-wide -- package:just_audio (used by both the
  // Morse tone player and TtsAnswerSpeaker) never touches
  // AVAudioSession itself, so this is the sole thing governing the
  // shared session's category. Deliberately no mixWithOthers: iOS
  // treats mixWithOthers sessions as secondary/background audio, which
  // is a documented reason it withholds the lock screen/Dynamic Island
  // Now Playing card even from a correctly activated session.
  final session = await audio_session.AudioSession.instance;
  await session.configure(
    const audio_session.AudioSessionConfiguration(
      avAudioSessionCategory: audio_session.AVAudioSessionCategory.playback,
    ),
  );

  final audioHandler = await AudioService.init(
    builder: () => TrainingAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.morse_icr.channel.audio',
      androidNotificationChannelName: 'Morse Training',
      androidNotificationOngoing: true,
    ),
  );

  runApp(MorseIcrApp(audioReporter: audioHandler));
}
