import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/speech/spoken_character.dart';

void main() {
  group('spokenTextFor', () {
    test('spells out letters explicitly rather than a bare character', () {
      expect(spokenTextFor('B'), 'bee');
      expect(spokenTextFor('Y'), 'why');
      expect(spokenTextFor('Z'), 'zee');
    });

    // A and E are the exceptions -- spelled-out alternatives ("ay",
    // "ee") were mispronounced on-device, so these stay as the bare
    // letter, which TTS engines pronounce correctly on their own.
    test('uses the bare letter for A and E', () {
      expect(spokenTextFor('A'), 'a');
      expect(spokenTextFor('E'), 'e');
    });

    test('accepts lowercase input for letters', () {
      expect(spokenTextFor('a'), 'a');
    });

    test('spells out digits explicitly rather than a bare numeral', () {
      expect(spokenTextFor('9'), 'nine');
      expect(spokenTextFor('0'), 'zero');
      expect(spokenTextFor('5'), 'five');
    });

    test('speaks punctuation with a friendly name', () {
      expect(spokenTextFor('.'), 'dot');
      expect(spokenTextFor(','), 'comma');
      expect(spokenTextFor('?'), 'question');
      expect(spokenTextFor('/'), 'slash');
    });

    // morse_icr_spec.md section 35: the learner can choose an alternate
    // spoken form for "." and "/".
    test('defaults to "dot" and "slash" when no preference is given', () {
      expect(spokenTextFor('.'), 'dot');
      expect(spokenTextFor('/'), 'slash');
    });

    test('speaks "." as "period" when speakPeriodAsDot is false', () {
      expect(spokenTextFor('.', speakPeriodAsDot: false), 'period');
    });

    test('speaks "/" as "stroke" when speakSlashAsStroke is true', () {
      expect(spokenTextFor('/', speakSlashAsStroke: true), 'stroke');
    });

    test('the period/slash preference does not affect other characters', () {
      expect(
        spokenTextFor('B', speakPeriodAsDot: false, speakSlashAsStroke: true),
        'bee',
      );
    });
  });
}
