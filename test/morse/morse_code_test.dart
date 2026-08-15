import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/morse/morse_code.dart';

void main() {
  const expected = {
    'A': '.-', 'B': '-...', 'C': '-.-.', 'D': '-..', 'E': '.',
    'F': '..-.', 'G': '--.', 'H': '....', 'I': '..', 'J': '.---',
    'K': '-.-', 'L': '.-..', 'M': '--', 'N': '-.', 'O': '---',
    'P': '.--.', 'Q': '--.-', 'R': '.-.', 'S': '...', 'T': '-',
    'U': '..-', 'V': '...-', 'W': '.--', 'X': '-..-', 'Y': '-.--',
    'Z': '--..',
    '0': '-----', '1': '.----', '2': '..---', '3': '...--', '4': '....-',
    '5': '.....', '6': '-....', '7': '--...', '8': '---..', '9': '----.',
    '.': '.-.-.-', ',': '--..--', '?': '..--..', '/': '-..-.',
  };

  group('morsePatternFor', () {
    expected.forEach((char, pattern) {
      test('$char encodes to $pattern', () {
        expect(morsePatternFor(char), pattern);
      });
    });

    test('lowercase input is accepted', () {
      expect(morsePatternFor('a'), '.-');
    });

    test('unknown character throws ArgumentError', () {
      expect(() => morsePatternFor('@'), throwsArgumentError);
    });
  });
}
