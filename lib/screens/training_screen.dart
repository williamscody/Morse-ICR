import 'package:flutter/material.dart';

import '../audio/morse_audio_engine.dart';
import '../training/character_set.dart';
import '../training/training_engine.dart';
import 'widgets/stepped_int_control.dart';

/// Milestone 5: the training screen wired to the character-generation
/// loop.
///
/// Provides character-speed control, recognition-time control,
/// character-set selection, and a start/stop toggle that drives
/// [TrainingEngine]. Does not yet run a recognition timer (Milestone 6),
/// announce answers (Milestone 7), or persist settings (Milestone 12).
class TrainingScreen extends StatefulWidget {
  /// [trainingEngine] lets tests substitute a fake audio player so they
  /// don't have to exercise the real [MorseAudioEngine] platform plugin;
  /// production code always omits it and gets the real engine.
  const TrainingScreen({super.key, TrainingEngine? trainingEngine})
    : _injectedTrainingEngine = trainingEngine;

  final TrainingEngine? _injectedTrainingEngine;

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  int _wpm = 90;
  int _recognitionTimeMs = 500;
  final Set<CharacterSetType> _selectedCharacterSets = {
    CharacterSetType.letters,
  };
  bool _isTraining = false;
  int _charactersPlayed = 0;

  MorseAudioEngine? _audioEngine;
  late final TrainingEngine _trainingEngine;

  @override
  void initState() {
    super.initState();
    if (widget._injectedTrainingEngine != null) {
      _trainingEngine = widget._injectedTrainingEngine!;
    } else {
      final audioEngine = MorseAudioEngine();
      _audioEngine = audioEngine;
      _trainingEngine = TrainingEngine(audioPlayer: audioEngine);
    }
    _trainingEngine.onCharacterGenerated = (_) {
      if (mounted) setState(() => _charactersPlayed++);
    };
  }

  @override
  void dispose() {
    _trainingEngine.stop();
    _audioEngine?.dispose();
    super.dispose();
  }

  Future<void> _toggleTraining() async {
    if (_isTraining) {
      await _trainingEngine.stop();
      if (!mounted) return;
      setState(() => _isTraining = false);
      return;
    }

    final characters = charactersForSelection(_selectedCharacterSets);
    if (characters.isEmpty) return;

    setState(() {
      _isTraining = true;
      _charactersPlayed = 0;
    });
    _trainingEngine.start(
      characters: characters,
      wpm: _wpm.toDouble(),
      recognitionTime: Duration(milliseconds: _recognitionTimeMs),
    );
  }

  bool get _hasSelectedCharacters =>
      charactersForSelection(_selectedCharacterSets).isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Morse ICR')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SteppedIntControl(
                    label: 'Character Speed',
                    value: _wpm,
                    min: 15,
                    max: 150,
                    step: 1,
                    suffix: 'WPM',
                    onChanged: (v) {
                      setState(() => _wpm = v);
                      _trainingEngine.updateSettings(wpm: v.toDouble());
                    },
                  ),
                  const SizedBox(height: 24),
                  SteppedIntControl(
                    label: 'Recognition Time',
                    value: _recognitionTimeMs,
                    min: 50,
                    max: 1000,
                    step: 1,
                    suffix: 'ms',
                    onChanged: (v) {
                      setState(() => _recognitionTimeMs = v);
                      _trainingEngine.updateSettings(
                        recognitionTime: Duration(milliseconds: v),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Character Set',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final type in CharacterSetType.values)
                        FilterChip(
                          label: Text(type.label),
                          showCheckmark: false,
                          selected: _selectedCharacterSets.contains(type),
                          onSelected: _isTraining
                              ? null
                              : (selected) {
                                  setState(() {
                                    if (selected) {
                                      _selectedCharacterSets.add(type);
                                    } else {
                                      _selectedCharacterSets.remove(type);
                                    }
                                  });
                                },
                        ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Text(
                    _isTraining ? 'Training…' : 'Idle',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (_isTraining) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Characters played: $_charactersPlayed',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _isTraining
                          ? Colors.red
                          : Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: _isTraining || _hasSelectedCharacters
                        ? _toggleTraining
                        : null,
                    child: Text(_isTraining ? 'Stop' : 'Start'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
