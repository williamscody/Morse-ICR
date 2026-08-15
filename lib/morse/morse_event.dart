import 'morse_code.dart';
import 'morse_timing.dart';

/// A single element of a Morse character's audio envelope: the tone is
/// either on (dit/dah) or off (intra-character gap) for
/// [durationSeconds].
class MorseElement {
  const MorseElement({required this.toneOn, required this.durationSeconds});

  final bool toneOn;
  final double durationSeconds;
}

/// Builds the ordered tone-on/tone-off elements representing [character]
/// at the given [wpm].
///
/// Deliberately excludes inter-character and word gaps: those are
/// controlled by the training engine's recognition-time logic (section 6),
/// not baked into a single character's audio clip.
List<MorseElement> morseElementsForCharacter(String character, double wpm) {
  final pattern = morsePatternFor(character);
  final timing = MorseTiming(wpm);
  final elements = <MorseElement>[];

  for (var i = 0; i < pattern.length; i++) {
    final symbol = pattern[i];
    final onDuration = symbol == '.' ? timing.ditSeconds : timing.dahSeconds;
    elements.add(MorseElement(toneOn: true, durationSeconds: onDuration));

    final isLastSymbol = i == pattern.length - 1;
    if (!isLastSymbol) {
      elements.add(
        MorseElement(
          toneOn: false,
          durationSeconds: timing.intraCharacterGapSeconds,
        ),
      );
    }
  }

  return elements;
}
