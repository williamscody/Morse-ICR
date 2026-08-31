import 'package:flutter/material.dart';

import 'screens/training_screen.dart';

/// A rich teal seed -- evokes a waveform/signal-scope glow appropriate
/// to an audio-training app, and sits far enough from the Start/Stop
/// button's fixed green/red (morse_icr_spec.md section 24's "basic
/// result/status") on the color wheel to read as a distinct accent
/// rather than competing with it. Material 3's `ColorScheme.fromSeed`
/// derives a full, contrast-checked tonal palette (primary/secondary/
/// tertiary/surface/error, each with "container" and "on" variants)
/// from this one color -- the recommended way to get a cohesive scheme
/// without hand-picking a dozen individual colors.
const _seedColor = Color(0xFF00897B);

/// Root widget for Morse ICR Trainer.
class MorseIcrApp extends StatelessWidget {
  const MorseIcrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Morse ICR Trainer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _seedColor),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      // Follows the device's own appearance setting rather than forcing
      // dark mode -- previously hardcoded, which meant a learner with
      // Light mode selected system-wide never saw it reflected here.
      themeMode: ThemeMode.system,
      home: const TrainingScreen(),
    );
  }
}
