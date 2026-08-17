import 'package:flutter/material.dart';

import '../audio/morse_audio_engine.dart';
import '../speech/answer_speaker.dart';
import '../speech/tts_answer_speaker.dart';
import '../training/character_set.dart';
import '../training/training_engine.dart';
import 'widgets/stepped_int_control.dart';

/// Milestone 7: the training screen wired to the character-generation
/// loop, recognition timer, and computer-voice answer.
///
/// Provides character-speed control, recognition-time control,
/// character-set selection, and a start/stop toggle that drives
/// [TrainingEngine], which announces each character via [AnswerSpeaker]
/// once its recognition deadline lapses. Nothing yet gates that
/// announcement on a learner response (Milestone 8) or scores it
/// (Milestone 9); persistence is still Milestone 12.
class TrainingScreen extends StatefulWidget {
  /// [trainingEngine] and [answerSpeaker] let tests substitute fakes so
  /// they don't have to exercise the real [MorseAudioEngine] platform
  /// plugin or real text-to-speech; production code always omits them
  /// and gets the real implementations.
  const TrainingScreen({
    super.key,
    TrainingEngine? trainingEngine,
    AnswerSpeaker? answerSpeaker,
  }) : _injectedTrainingEngine = trainingEngine,
       _injectedAnswerSpeaker = answerSpeaker;

  final TrainingEngine? _injectedTrainingEngine;
  final AnswerSpeaker? _injectedAnswerSpeaker;

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
  bool _voiceEnabled = true;
  bool _voicePreparing = false;

  MorseAudioEngine? _audioEngine;
  late final TrainingEngine _trainingEngine;
  late final AnswerSpeaker _answerSpeaker;

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
    _answerSpeaker = widget._injectedAnswerSpeaker ?? TtsAnswerSpeaker();
    final answerSpeaker = _answerSpeaker;
    if (answerSpeaker is TtsAnswerSpeaker) {
      // Pre-rendering every character's spoken word (section 36) takes
      // a moment, most noticeably right after the learner installs a
      // higher-quality voice -- surface that instead of leaving early
      // announcements silently slow or missing.
      _voicePreparing = true;
      answerSpeaker.ready.whenComplete(() {
        if (mounted) setState(() => _voicePreparing = false);
      });
    }
    _trainingEngine.onCharacterGenerated = (_) {
      if (mounted) setState(() => _charactersPlayed++);
    };
    // The Voice switch is the sole authority on whether the computer
    // speaks -- checked at the moment the deadline expires, not when
    // training started, so toggling it mid-session takes effect
    // immediately. Voice recognition/scoring is not a factor here and
    // is out of scope until Milestone 8/9.
    _trainingEngine.onRecognitionTimeout = (character) {
      if (!_voiceEnabled) return Future<void>.value();
      return _answerSpeaker.speak(character);
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Voice',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Switch(
                        value: _voiceEnabled,
                        onChanged: (value) =>
                            setState(() => _voiceEnabled = value),
                      ),
                    ],
                  ),
                  if (_voicePreparing) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Preparing voice…',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
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
