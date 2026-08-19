import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/speech/character_recognizer.dart';
import 'package:morse_icr/training/character_set.dart';

void main() {
  group('characterForSpokenText', () {
    test('matches every letter and digit by its bare literal token', () {
      for (final letter in characterSets[CharacterSetType.letters]!) {
        expect(characterForSpokenText(letter), letter);
        expect(characterForSpokenText(letter.toLowerCase()), letter);
      }
      for (final digit in characterSets[CharacterSetType.numbers]!) {
        expect(characterForSpokenText(digit), digit);
      }
    });

    test('matches every letter and digit by its TTS spoken form', () {
      expect(characterForSpokenText('bee'), 'B');
      expect(characterForSpokenText('zee'), 'Z');
      expect(characterForSpokenText('zero'), '0');
      expect(characterForSpokenText('nine'), '9');
    });

    test('matches punctuation aliases', () {
      expect(characterForSpokenText('dot'), '.');
      expect(characterForSpokenText('period'), '.');
      expect(characterForSpokenText('comma'), ',');
      expect(characterForSpokenText('question'), '?');
      expect(characterForSpokenText('question mark'), '?');
      expect(characterForSpokenText('slash'), '/');
      expect(characterForSpokenText('stroke'), '/');
    });

    test('is case-insensitive and tolerates surrounding whitespace', () {
      expect(characterForSpokenText('  Kay  '), 'K');
      expect(characterForSpokenText('DOT'), '.');
    });

    test('scans multi-word results and matches the first known word', () {
      expect(characterForSpokenText('the letter A'), 'A');
      expect(characterForSpokenText('um kay'), 'K');
    });

    test('returns null for unrecognized input', () {
      expect(characterForSpokenText('gibberish'), isNull);
      expect(characterForSpokenText(''), isNull);
      expect(characterForSpokenText('   '), isNull);
    });
  });
}
