import 'package:flutter/material.dart';

import 'widgets/stepped_int_control.dart';

// 2026-08-31: "Personalize Recognition" opened voice enrollment for the
// on-device, enrollment-trained (DTW/MFCC) recognizer -- irrelevant now
// that production Speech Recognition is the general-purpose
// package:speech_to_text engine (morse_icr project memory: Milestone
// 13), which needs no per-learner enrollment. Hidden rather than
// deleted, along with [onOpenVoiceSetup] going unused below, in case
// the enrollment-based engine is revisited later.
const bool _personalizeRecognitionEnabled = false;

/// Settings previously inline on [TrainingScreen]'s main form, moved
/// here to keep that screen focused on the training controls
/// themselves. Local state mirrors every widget parameter so this
/// screen renders correctly the moment it's pushed, but every change is
/// reported back via the matching `on...Changed` callback so
/// [TrainingScreen] -- which still owns the real setting, persists it,
/// and applies it to any live session -- stays the source of truth.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.voiceEnabled,
    required this.voicePreparing,
    required this.recognitionEnabled,
    required this.speakPeriodAsDot,
    required this.speakSlashAsStroke,
    required this.morsePitchHz,
    required this.morseVolumePercent,
    required this.voiceVolumePercent,
    required this.randomCharacterOrder,
    required this.onVoiceChanged,
    required this.onRecognitionChanged,
    required this.onOpenVoiceSetup,
    required this.onSpeakPeriodAsDotChanged,
    required this.onSpeakSlashAsStrokeChanged,
    required this.onMorsePitchChanged,
    required this.onMorseVolumeChanged,
    required this.onVoiceVolumeChanged,
    required this.onRandomCharacterOrderChanged,
  });

  final bool voiceEnabled;
  final bool voicePreparing;
  final bool recognitionEnabled;
  final bool speakPeriodAsDot;
  final bool speakSlashAsStroke;
  final int morsePitchHz;
  final int morseVolumePercent;
  final int voiceVolumePercent;
  final bool randomCharacterOrder;
  final ValueChanged<bool> onVoiceChanged;
  final ValueChanged<bool> onRecognitionChanged;
  final VoidCallback onOpenVoiceSetup;
  final ValueChanged<bool> onSpeakPeriodAsDotChanged;
  final ValueChanged<bool> onSpeakSlashAsStrokeChanged;
  final ValueChanged<int> onMorsePitchChanged;
  final ValueChanged<int> onMorseVolumeChanged;
  final ValueChanged<int> onVoiceVolumeChanged;
  final ValueChanged<bool> onRandomCharacterOrderChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _voiceEnabled = widget.voiceEnabled;
  late bool _recognitionEnabled = widget.recognitionEnabled;
  late bool _speakPeriodAsDot = widget.speakPeriodAsDot;
  late bool _speakSlashAsStroke = widget.speakSlashAsStroke;
  late int _morsePitchHz = widget.morsePitchHz;
  late int _morseVolumePercent = widget.morseVolumePercent;
  late int _voiceVolumePercent = widget.voiceVolumePercent;
  late bool _randomCharacterOrder = widget.randomCharacterOrder;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Voice',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Transform.scale(
                        scale: 0.8,
                        child: Switch(
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          value: _voiceEnabled,
                          onChanged: (value) {
                            setState(() => _voiceEnabled = value);
                            widget.onVoiceChanged(value);
                          },
                        ),
                      ),
                    ],
                  ),
                  if (widget.voicePreparing) ...[
                    const SizedBox(height: 4),
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
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Speech Recognition',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Transform.scale(
                        scale: 0.8,
                        child: Switch(
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          value: _recognitionEnabled,
                          onChanged: (value) {
                            setState(() => _recognitionEnabled = value);
                            widget.onRecognitionChanged(value);
                          },
                        ),
                      ),
                    ],
                  ),
                  if (_personalizeRecognitionEnabled) ...[
                    const SizedBox(height: 12),
                    // Opens voice enrollment (morse_icr_spec.md section
                    // 38): recognition is matched against the learner's
                    // own enrolled recordings, so this is where they're
                    // made/redone. Placed directly under the Speech
                    // Recognition toggle it configures, per Bill's
                    // decision -- not a generic settings item.
                    OutlinedButton(
                      onPressed: widget.onOpenVoiceSetup,
                      child: const Text('Personalize Recognition'),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Speak "." as',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 6),
                            SegmentedButton<bool>(
                              showSelectedIcon: false,
                              style: SegmentedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                              segments: const [
                                ButtonSegment(
                                  value: false,
                                  label: Text('Period'),
                                ),
                                ButtonSegment(value: true, label: Text('Dot')),
                              ],
                              selected: {_speakPeriodAsDot},
                              onSelectionChanged: (selection) {
                                final value = selection.first;
                                setState(() => _speakPeriodAsDot = value);
                                widget.onSpeakPeriodAsDotChanged(value);
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Speak "/" as',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 6),
                            SegmentedButton<bool>(
                              showSelectedIcon: false,
                              style: SegmentedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                              segments: const [
                                ButtonSegment(
                                  value: false,
                                  label: Text('Slash'),
                                ),
                                ButtonSegment(
                                  value: true,
                                  label: Text('Stroke'),
                                ),
                              ],
                              selected: {_speakSlashAsStroke},
                              onSelectionChanged: (selection) {
                                final value = selection.first;
                                setState(() => _speakSlashAsStroke = value);
                                widget.onSpeakSlashAsStrokeChanged(value);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SteppedIntControl(
                    label: 'Morse Pitch',
                    value: _morsePitchHz,
                    min: 400,
                    max: 1000,
                    step: 10,
                    suffix: 'Hz',
                    onChanged: (value) {
                      setState(() => _morsePitchHz = value);
                      widget.onMorsePitchChanged(value);
                    },
                  ),
                  const SizedBox(height: 14),
                  SteppedIntControl(
                    label: 'Morse Volume',
                    value: _morseVolumePercent,
                    min: 0,
                    max: 100,
                    step: 5,
                    suffix: '%',
                    onChanged: (value) {
                      setState(() => _morseVolumePercent = value);
                      widget.onMorseVolumeChanged(value);
                    },
                  ),
                  const SizedBox(height: 14),
                  SteppedIntControl(
                    label: 'Voice Volume',
                    value: _voiceVolumePercent,
                    min: 0,
                    max: 100,
                    step: 5,
                    suffix: '%',
                    onChanged: (value) {
                      setState(() => _voiceVolumePercent = value);
                      widget.onVoiceVolumeChanged(value);
                    },
                  ),
                  const SizedBox(height: 18),
                  // Diagnostic toggle: off gives a repeatable, predictable
                  // character sequence instead of a random draw, so an
                  // accuracy issue under investigation can be isolated
                  // from random-order noise.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Random Character Order',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Transform.scale(
                        scale: 0.8,
                        child: Switch(
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          value: _randomCharacterOrder,
                          onChanged: (value) {
                            setState(() => _randomCharacterOrder = value);
                            widget.onRandomCharacterOrderChanged(value);
                          },
                        ),
                      ),
                    ],
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
