import 'package:flutter/material.dart';

import 'audio/morse_audio_engine.dart';

/// Root widget for Morse ICR.
///
/// Milestone 1 established the app shell. Milestone 2 adds a temporary
/// audio-verification screen so the Morse audio engine can be confirmed
/// on real devices; it is replaced by the real training screen in a
/// later milestone.
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

/// Temporary home screen used to verify the Morse audio engine on
/// device. Replaced by the real training screen in a later milestone.
class HomePlaceholderScreen extends StatefulWidget {
  const HomePlaceholderScreen({super.key});

  @override
  State<HomePlaceholderScreen> createState() => _HomePlaceholderScreenState();
}

class _HomePlaceholderScreenState extends State<HomePlaceholderScreen> {
  final _audioEngine = MorseAudioEngine();
  double _wpm = 90;

  static const _sampleCharacters = ['E', 'A', 'K', '5', 'Q'];

  @override
  void dispose() {
    _audioEngine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Morse ICR',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Milestone 2: audio engine verification',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            Text('${_wpm.round()} WPM'),
            SizedBox(
              width: 280,
              child: Slider(
                value: _wpm,
                min: 40,
                max: 150,
                divisions: 110,
                label: '${_wpm.round()} WPM',
                onChanged: (value) => setState(() => _wpm = value),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              children: [
                for (final char in _sampleCharacters)
                  ElevatedButton(
                    onPressed: () =>
                        _audioEngine.playCharacter(char, _wpm),
                    child: Text('Play $char'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
