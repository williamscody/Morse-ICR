import 'dart:math' as math;

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

    test('draws uniformly at random, including immediate repeats -- no '
        'anti-repeat bias', () {
      // A fixed seed makes this deterministic rather than flaky: with
      // Dart's PRNG and this seed, drawing from a 2-character set
      // produces at least one immediate repeat within the first 20
      // draws. If a future change reintroduces repeat-avoidance, this
      // starts failing (drawing indefinitely, or -- if repeat-
      // avoidance is added back with a fallback -- simply never
      // seeing consecutive equal values).
      final selector = CharacterSelector(random: math.Random(1));
      const characters = ['A', 'B'];

      final draws = [for (var i = 0; i < 20; i++) selector.next(characters)];

      var sawImmediateRepeat = false;
      for (var i = 1; i < draws.length; i++) {
        if (draws[i] == draws[i - 1]) sawImmediateRepeat = true;
      }
      expect(sawImmediateRepeat, isTrue);
    });

    test('cycles through the set in order when randomOrder is false', () {
      final selector = CharacterSelector()..randomOrder = false;
      const characters = ['A', 'B', 'C'];

      expect(
        [for (var i = 0; i < 7; i++) selector.next(characters)],
        ['A', 'B', 'C', 'A', 'B', 'C', 'A'],
      );
    });

    test('switching randomOrder back on resumes random draws', () {
      final selector = CharacterSelector(random: math.Random(1))
        ..randomOrder = false;
      const characters = ['A', 'B'];

      selector.next(characters);
      selector.randomOrder = true;

      for (var i = 0; i < 20; i++) {
        expect(characters, contains(selector.next(characters)));
      }
    });
  });
}
