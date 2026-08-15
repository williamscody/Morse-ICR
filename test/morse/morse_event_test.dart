import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/morse/morse_event.dart';
import 'package:morse_icr/morse/morse_timing.dart';

void main() {
  test('character K (-.-) produces dah, gap, dit, gap, dah', () {
    final elements = morseElementsForCharacter('K', 90);
    final timing = MorseTiming(90);

    expect(elements.length, 5);

    expect(elements[0].toneOn, true);
    expect(elements[0].durationSeconds, closeTo(timing.dahSeconds, 1e-9));

    expect(elements[1].toneOn, false);
    expect(
      elements[1].durationSeconds,
      closeTo(timing.intraCharacterGapSeconds, 1e-9),
    );

    expect(elements[2].toneOn, true);
    expect(elements[2].durationSeconds, closeTo(timing.ditSeconds, 1e-9));

    expect(elements[3].toneOn, false);
    expect(
      elements[3].durationSeconds,
      closeTo(timing.intraCharacterGapSeconds, 1e-9),
    );

    expect(elements[4].toneOn, true);
    expect(elements[4].durationSeconds, closeTo(timing.dahSeconds, 1e-9));
  });

  test('single-symbol character E has no gaps', () {
    final elements = morseElementsForCharacter('E', 90);
    expect(elements.length, 1);
    expect(elements[0].toneOn, true);
  });

  test('character does not end with a trailing gap', () {
    final elements = morseElementsForCharacter('S', 90); // ...
    expect(elements.last.toneOn, true);
  });
}
