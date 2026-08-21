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

  // iOS only for now -- Android has no foreground-service/notification
  // plumbing set up for audio_service yet (a separate, already-tracked
  // gap: Android background survival, morse_icr project memory), and
  // audio_service needs AndroidManifest/MainActivity changes just to
  // avoid crashing there that this app doesn't have.
  if (Platform.isIOS) {
    trainingAudioHandler = await AudioService.init(
      builder: TrainingAudioHandler.new,
    );
  }

  runApp(const MorseIcrApp());
}
