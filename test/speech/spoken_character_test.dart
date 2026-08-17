import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/speech/spoken_character.dart';

void main() {
  group('spokenTextFor', () {
    test('spells out letters explicitly rather than a bare character', () {
      expect(spokenTextFor('A'), 'ay');
      expect(spokenTextFor('Y'), 'why');
      expect(spokenTextFor('Z'), 'zee');
    });

    test('accepts lowercase input for letters', () {
      expect(spokenTextFor('a'), 'ay');
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
  });
}
