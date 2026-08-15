import 'package:flutter/material.dart';

import '../training/character_set.dart';
import 'widgets/stepped_int_control.dart';

/// Milestone 4: the basic training screen shell.
///
/// Provides character-speed control, recognition-time control,
/// character-set selection, and a start/stop toggle. Does not yet
/// generate characters (Milestone 5), run a recognition timer
/// (Milestone 6), or persist settings (Milestone 12).
class TrainingScreen extends StatefulWidget {
  const TrainingScreen({super.key});

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

  void _toggleTraining() {
    setState(() => _isTraining = !_isTraining);
  }

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
                    min: 40,
                    max: 150,
                    step: 1,
                    suffix: 'WPM',
                    enabled: !_isTraining,
                    onChanged: (v) => setState(() => _wpm = v),
                  ),
                  const SizedBox(height: 24),
                  SteppedIntControl(
                    label: 'Recognition Time',
                    value: _recognitionTimeMs,
                    min: 50,
                    max: 1000,
                    step: 1,
                    suffix: 'ms',
                    enabled: !_isTraining,
                    onChanged: (v) => setState(() => _recognitionTimeMs = v),
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
                  const SizedBox(height: 16),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _isTraining
                          ? Colors.red
                          : Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: _toggleTraining,
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
