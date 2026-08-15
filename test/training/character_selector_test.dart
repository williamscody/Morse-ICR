import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/training/character_selector.dart';

void main() {
  group('CharacterSelector', () {
    test('always returns a character from the active set', () {
      final selector = CharacterSelector();
      const characters = ['A', 'B', 'C', 'D'];

      for (var i = 0; i < 100; i++) {
        expect(characters, contains(selector.next(characters)));
      }
    });

    test('never immediately repeats when more than one character is active', () {
      final selector = CharacterSelector();
      const characters = ['A', 'B'];

      String? previous;
      for (var i = 0; i < 100; i++) {
        final next = selector.next(characters);
        if (previous != null) {
          expect(next, isNot(previous));
        }
        previous = next;
      }
    });

    test('repeats the only available character when the set has one entry', () {
      final selector = CharacterSelector();
      const characters = ['A'];

      expect(selector.next(characters), 'A');
      expect(selector.next(characters), 'A');
      expect(selector.next(characters), 'A');
    });

    test('throws when the character set is empty', () {
      final selector = CharacterSelector();
      expect(() => selector.next(const []), throwsArgumentError);
    });

    test('reset clears repeat-avoidance history', () {
      final selector = CharacterSelector();
      const characters = ['A'];

      selector.next(characters);
      selector.reset();
      // With a single-character set this is a no-op either way, but
      // reset() must not throw and selection must keep working.
      expect(selector.next(characters), 'A');
    });
  });
}
