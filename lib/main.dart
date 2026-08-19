import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'audio/audio_session_setup.dart';

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

  runApp(const MorseIcrApp());
}
