import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/morse/morse_code.dart';
import 'package:morse_icr/training/character_set.dart';

void main() {
  const characterBackedTypes = [
    CharacterSetType.letters,
    CharacterSetType.numbers,
    CharacterSetType.punctuation,
  ];

  group('characterSets', () {
    for (final type in characterBackedTypes) {
      test('${type.label} is non-empty', () {
        expect(characterSets[type], isNotEmpty);
      });

      test('${type.label} contains only encodable characters', () {
        for (final char in characterSets[type]!) {
          expect(
            () => morsePatternFor(char),
            returnsNormally,
            reason: '$char in ${type.label} has no Morse pattern',
          );
        }
      });
    }

    test('words is an empty placeholder for a future training mode', () {
      expect(characterSets[CharacterSetType.words], isEmpty);
      expect(CharacterSetType.words.label, 'Word');
    });

    test('letters has exactly A-Z', () {
      expect(characterSets[CharacterSetType.letters], hasLength(26));
    });

    test('numbers has exactly 0-9', () {
      expect(characterSets[CharacterSetType.numbers], hasLength(10));
    });

    test('punctuation is exactly . , ? /', () {
      expect(characterSets[CharacterSetType.punctuation], ['.', ',', '?', '/']);
    });

    test('labels match the abbreviated on-screen button text', () {
      expect(CharacterSetType.letters.label, 'A-Z');
      expect(CharacterSetType.numbers.label, '0-9');
      expect(CharacterSetType.punctuation.label, 'Punct');
    });
  });

  group('charactersForSelection', () {
    test('returns only the selected set when one type is chosen', () {
      final result = charactersForSelection({CharacterSetType.numbers});
      expect(result, characterSets[CharacterSetType.numbers]);
    });

    test('combines multiple selected sets with no duplicates', () {
      final result = charactersForSelection({
        CharacterSetType.letters,
        CharacterSetType.numbers,
      });
      expect(result, hasLength(36));
      expect(result.toSet(), hasLength(36));
    });

    test('words contributes no characters even when selected', () {
      final result = charactersForSelection({
        CharacterSetType.letters,
        CharacterSetType.words,
      });
      expect(result, characterSets[CharacterSetType.letters]);
    });

    test('returns empty list when nothing is selected', () {
      expect(charactersForSelection({}), isEmpty);
    });
  });
}
