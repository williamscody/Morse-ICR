import 'package:flutter/material.dart';

import 'screens/training_screen.dart';

/// Root widget for Morse ICR.
class MorseIcrApp extends StatelessWidget {
  const MorseIcrApp({super.key});

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
      home: const TrainingScreen(),
    );
  }
}
