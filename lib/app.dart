import 'package:flutter/material.dart';

/// Root widget for Morse ICR.
///
/// Milestone 1 only establishes the app shell. Training screens, audio,
/// and persistence are added in later milestones per morse_icr_spec.md.
class MorseIcrApp extends StatelessWidget {
  const MorseIcrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Morse ICR',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomePlaceholderScreen(),
    );
  }
}

/// Temporary minimal home screen. Replaced by the real training screen
/// in a later milestone.
class HomePlaceholderScreen extends StatelessWidget {
  const HomePlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(
          'Morse ICR',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      ),
    );
  }
}
