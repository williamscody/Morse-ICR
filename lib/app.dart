import 'package:flutter/material.dart';

import 'audio/training_session_reporter.dart';
import 'screens/training_screen.dart';

/// Root widget for Morse ICR.
class MorseIcrApp extends StatelessWidget {
  /// [audioReporter] is null when there's no real OS media session to
  /// mirror state into (e.g. widget tests); production always supplies
  /// the [TrainingAudioHandler] created in `main.dart`.
  const MorseIcrApp({super.key, this.audioReporter});

  final TrainingSessionReporter? audioReporter;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Morse ICR',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: TrainingScreen(audioReporter: audioReporter),
    );
  }
}
