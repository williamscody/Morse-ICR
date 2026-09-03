import 'package:flutter/material.dart';

import '../speech/tts_voice_option.dart';
import 'widgets/stepped_int_control.dart';

// The value a "Voice" dropdown item uses to mean "no preference -- pick
// automatically" (see [TtsAnswerSpeaker._bestAvailableVoice]), matching
// [AppSettings.selectedVoiceName]'s own empty-string default. Distinct
// from any real voice's key (see [_voiceKey]), which always has a "|".
const _autoVoiceKey = '';

// A [TtsVoiceOption]'s stable dropdown key -- name alone isn't unique
// across locales (the same voice name could theoretically appear for
// more than one), so this pairs it with locale.
String _voiceKey(TtsVoiceOption voice) => '${voice.name}|${voice.locale}';

// The label a "Voice" dropdown item shows -- just the name for a plain
// "default"-quality voice (nothing to distinguish it from another of the
// same name, in practice there won't be one), else the name plus its
// quality tier exactly as iOS's own Settings > Accessibility > Spoken
// Content > Voices screen labels it (e.g. "Nathan (Enhanced)") so a
// learner can match this picker's list against that screen's.
String _voiceLabel(TtsVoiceOption voice) {
  if (voice.quality == 'default') return voice.name;
  final quality = voice.quality.isEmpty
      ? voice.quality
      : voice.quality[0].toUpperCase() + voice.quality.substring(1);
  // Some installed voices' own `name` already bakes in the quality
  // suffix -- confirmed on-device (2026-09-02): an Enhanced "Nathan"
  // reports its `name` as literally "Nathan (Enhanced)", not just
  // "Nathan", while `quality` is *also* separately "enhanced".
  // Appending unconditionally doubled it to "Nathan (Enhanced)
  // (Enhanced)", long enough to wrap and, worse, to force the whole
  // [DropdownButton] wide enough to crush the "Speech Voice" label next
  // to it down to almost no width at all (Bill, on-device: label text
  // rendering one letter per line). Skip the append when the name
  // already ends with it.
  if (voice.name.toLowerCase().endsWith('($quality)'.toLowerCase())) {
    return voice.name;
  }
  return '${voice.name} ($quality)';
}

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
    required this.voiceOptions,
    required this.selectedVoiceName,
    required this.selectedVoiceLocale,
    required this.onVoiceChanged,
    required this.onRecognitionChanged,
    required this.onOpenVoiceSetup,
    required this.onSpeakPeriodAsDotChanged,
    required this.onSpeakSlashAsStrokeChanged,
    required this.onMorsePitchChanged,
    required this.onMorseVolumeChanged,
    required this.onVoiceVolumeChanged,
    required this.onRandomCharacterOrderChanged,
    required this.onSpeechVoiceChanged,
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

  /// Every English-locale voice [TtsAnswerSpeaker.availableVoices]
  /// reports installed on this device -- empty until it's finished
  /// resolving (mirrors [voicePreparing]'s own "not ready yet" window),
  /// in which case the picker below just shows "Auto".
  final List<TtsVoiceOption> voiceOptions;

  /// Section 35's "Voice" picker selection -- both empty means "Auto"
  /// (see [AppSettings.selectedVoiceName]'s own doc comment).
  final String selectedVoiceName;
  final String selectedVoiceLocale;
  final ValueChanged<bool> onVoiceChanged;
  final ValueChanged<bool> onRecognitionChanged;
  final VoidCallback onOpenVoiceSetup;
  final ValueChanged<bool> onSpeakPeriodAsDotChanged;
  final ValueChanged<bool> onSpeakSlashAsStrokeChanged;
  final ValueChanged<int> onMorsePitchChanged;
  final ValueChanged<int> onMorseVolumeChanged;
  final ValueChanged<int> onVoiceVolumeChanged;
  final ValueChanged<bool> onRandomCharacterOrderChanged;

  /// Reports a new "Voice" picker selection -- both arguments empty
  /// together means "Auto".
  final void Function(String name, String locale) onSpeechVoiceChanged;

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
  late String _selectedVoiceName = widget.selectedVoiceName;
  late String _selectedVoiceLocale = widget.selectedVoiceLocale;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // [Expanded] rather than a bare [Text] -- at a
                      // narrow-enough width (an iPhone mini/SE-class
                      // screen, ~390 logical points, this
                      // [ConstrainedBox]'s own 480 max width never
                      // actually applies) the longest of these three
                      // toggle labels ("Random Character Order," below)
                      // has nowhere to go but past the [Switch] and off
                      // the edge of the screen without this -- wrapping
                      // to a second line instead costs nothing here since
                      // every label is short enough not to need it in
                      // practice.
                      Expanded(
                        child: Text(
                          'Voice',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
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
                  const SizedBox(height: 12),
                  // Which installed voice actually speaks (2026-09-02) --
                  // added after Bill found changing the OS's own Settings
                  // > Accessibility > Spoken Content > Voices default had
                  // no effect here: [TtsAnswerSpeaker] always
                  // self-selects the first Enhanced/Premium English voice
                  // it finds, a tie [_bestAvailableVoice] breaks by list
                  // order rather than the learner's own preference (two
                  // same-tier voices, e.g. Samantha and Nathan both
                  // "Enhanced," aren't distinguishable by quality alone).
                  // This picker lets a learner override that pick
                  // directly, labeled to match iOS's own Voices screen
                  // (see [_voiceLabel]) so the two are easy to line up.
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Speech Voice',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      // [Expanded] + [isExpanded] together, rather than
                      // letting the button size itself -- a bare
                      // [DropdownButton] claims whatever width its
                      // *widest* item needs (not just the currently
                      // selected one), regardless of how little of that
                      // width the Row actually has to spare; a single
                      // long voice name/quality label was enough to
                      // crush the "Speech Voice" label above down to
                      // almost nothing (Bill, on-device: text rendering
                      // one letter per line). Constraining it to a fixed
                      // share of the row instead means a long label just
                      // truncates with an ellipsis in the closed button,
                      // never squeezes its neighbor.
                      Expanded(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value:
                              widget.voiceOptions.any(
                                (voice) =>
                                    voice.name == _selectedVoiceName &&
                                    voice.locale == _selectedVoiceLocale,
                              )
                              ? '$_selectedVoiceName|$_selectedVoiceLocale'
                              : _autoVoiceKey,
                          items: [
                            const DropdownMenuItem(
                              value: _autoVoiceKey,
                              child: Text('Auto'),
                            ),
                            for (final voice in widget.voiceOptions)
                              DropdownMenuItem(
                                value: _voiceKey(voice),
                                child: Text(
                                  _voiceLabel(voice),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (key) {
                            if (key == null) return;
                            final voice = widget.voiceOptions
                                .cast<TtsVoiceOption?>()
                                .firstWhere(
                                  (voice) => _voiceKey(voice!) == key,
                                  orElse: () => null,
                                );
                            setState(() {
                              _selectedVoiceName = voice?.name ?? '';
                              _selectedVoiceLocale = voice?.locale ?? '';
                            });
                            widget.onSpeechVoiceChanged(
                              voice?.name ?? '',
                              voice?.locale ?? '',
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // See the "Voice" row's own [Expanded] comment above.
                      Expanded(
                        child: Text(
                          'Speech Recognition',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
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
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                      // See the "Voice" row's own [Expanded] comment above
                      // -- this is the longest of the three labels, and
                      // the one that actually overflowed at an iPhone
                      // mini/SE-class width before this fix (Bill,
                      // 2026-09-02, on a `flutter test` probe at 390pt
                      // wide: "A RenderFlex overflowed by 65 pixels on the
                      // right").
                      Expanded(
                        child: Text(
                          'Random Character Order',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
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
