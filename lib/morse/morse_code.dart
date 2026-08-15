/// Data-driven Morse code table.
///
/// Initial coverage is A-Z, 0-9, and a small set of common punctuation
/// (morse_icr_spec.md sections 12 and 14). Additional characters can be
/// added here later without touching the timing, audio, or training
/// engines.
const Map<String, String> morseCodeTable = {
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

/// Returns the dit/dah pattern for [character] (case-insensitive).
/// Throws [ArgumentError] if the character is not in the table.
String morsePatternFor(String character) {
  final pattern = morseCodeTable[character.toUpperCase()];
  if (pattern == null) {
    throw ArgumentError('No Morse pattern for character "$character"');
  }
  return pattern;
}
