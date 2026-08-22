/// The training character sets supported by the initial prototype
/// (morse_icr_spec.md section 14). Multiple sets can be active at once
/// (e.g. Letters + Numbers); data-driven so additional sets can be added
/// without changing the training engine.
///
/// [words] is a placeholder for a future whole-word recognition mode
/// (a different training mechanism from single-character sets, not yet
/// implemented) -- it deliberately contributes no characters.
enum CharacterSetType { letters, numbers, punctuation, words }

const List<String> _letters = [
  'A',
  'B',
  'C',
  'D',
  'E',
  'F',
  'G',
  'H',
  'I',
  'J',
  'K',
  'L',
  'M',
  'N',
  'O',
  'P',
  'Q',
  'R',
  'S',
  'T',
  'U',
  'V',
  'W',
  'X',
  'Y',
  'Z',
];

const List<String> _numbers = [
  '0',
  '1',
  '2',
  '3',
  '4',
  '5',
  '6',
  '7',
  '8',
  '9',
];

const List<String> _punctuation = ['.', ',', '?', '/'];

const Map<CharacterSetType, List<String>> characterSets = {
  CharacterSetType.letters: _letters,
  CharacterSetType.numbers: _numbers,
  CharacterSetType.punctuation: _punctuation,
  CharacterSetType.words: [],
};

extension CharacterSetTypeLabel on CharacterSetType {
  String get label => switch (this) {
    CharacterSetType.letters => 'A-Z',
    CharacterSetType.numbers => '0-9',
    CharacterSetType.punctuation => 'Punct',
    CharacterSetType.words => 'Word',
  };
}

/// Flattens the characters from all [selectedTypes] into a single list,
/// in a stable order (letters, then numbers, then punctuation) with no
/// duplicates.
List<String> charactersForSelection(Set<CharacterSetType> selectedTypes) {
  final result = <String>[];
  for (final type in CharacterSetType.values) {
    if (selectedTypes.contains(type)) {
      result.addAll(characterSets[type]!);
    }
  }
  return result;
}

/// The full common Morse character set in one view (morse_icr_spec.md
/// section 12) -- letters, numbers, and section 39's minimum punctuation
/// set -- for UI that presents every character at once rather than by
/// character-set-type selection (e.g. [ProblemCharacterKeyboard],
/// `EnrollmentScreen`).
final List<String> allCharacters = [
  ...characterSets[CharacterSetType.letters]!,
  ...characterSets[CharacterSetType.numbers]!,
  ...characterSets[CharacterSetType.punctuation]!,
];
