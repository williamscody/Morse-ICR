/// Data-driven Morse code table.
///
/// Initial coverage is A-Z and 0-9 (morse_icr_spec.md section 14).
/// Punctuation and other sets can be added here later without touching
/// the timing, audio, or training engines.
const Map<String, String> morseCodeTable = {
  'A': '.-', 'B': '-...', 'C': '-.-.', 'D': '-..', 'E': '.',
  'F': '..-.', 'G': '--.', 'H': '....', 'I': '..', 'J': '.---',
  'K': '-.-', 'L': '.-..', 'M': '--', 'N': '-.', 'O': '---',
  'P': '.--.', 'Q': '--.-', 'R': '.-.', 'S': '...', 'T': '-',
  'U': '..-', 'V': '...-', 'W': '.--', 'X': '-..-', 'Y': '-.--',
  'Z': '--..',
  '0': '-----', '1': '.----', '2': '..---', '3': '...--', '4': '....-',
  '5': '.....', '6': '-....', '7': '--...', '8': '---..', '9': '----.',
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
