/// Explicit spoken forms for every character the trainer can announce
/// (morse_icr_spec.md section 28's "computer voice"), and reused by
/// character_recognizer.dart to help match the learner's own spoken
/// responses back to a character (section 27) -- public so that
/// reverse lookup doesn't duplicate, and risk drifting from, these
/// spellings.
///
/// Letters and digits are spelled out in full rather than handed to the
/// TTS engine as a bare token (e.g. "y" or "9") and left to its own
/// letter-name/numeral expansion. Individual spellings are chosen by
/// on-device listening test -- real dictionary words (e.g. "bee", "gee")
/// render more reliably than made-up phonetic spellings (e.g. the
/// original "ee" for E and "jee" for G both came out garbled).
const Map<String, String> spokenNames = {
  '.': 'dot',
  ',': 'comma',
  '?': 'question',
  '/': 'slash',
  'A': 'a',
  'B': 'bee',
  'C': 'see',
  'D': 'dee',
  'E': 'e',
  'F': 'eff',
  'G': 'gee',
  'H': 'aitch',
  'I': 'eye',
  'J': 'jay',
  'K': 'kay',
  'L': 'el',
  'M': 'em',
  'N': 'en',
  'O': 'oh',
  'P': 'pee',
  'Q': 'cue',
  'R': 'are',
  'S': 'ess',
  'T': 'tee',
  'U': 'you',
  'V': 'vee',
  'W': 'double-u',
  'X': 'ex',
  'Y': 'why',
  'Z': 'zee',
  '0': 'zero',
  '1': 'one',
  '2': 'two',
  '3': 'three',
  '4': 'four',
  '5': 'five',
  '6': 'six',
  '7': 'seven',
  '8': 'eight',
  '9': 'nine',
};

/// Returns the text-to-speech input for [character].
///
/// "." and "/" are the two punctuation characters section 35 lets the
/// learner choose an alternate spoken form for -- "Dot" vs "Period", and
/// "Slash" vs "Stroke" -- special-cased here rather than in [spokenNames]
/// itself, since that map doubles as the reverse-lookup table
/// [character_recognizer.dart] uses to recognize whichever form the
/// learner says regardless of which one the computer currently speaks.
String spokenTextFor(
  String character, {
  bool speakPeriodAsDot = true,
  bool speakSlashAsStroke = false,
}) {
  final upper = character.toUpperCase();
  if (upper == '.') return speakPeriodAsDot ? 'dot' : 'period';
  if (upper == '/') return speakSlashAsStroke ? 'stroke' : 'slash';
  return spokenNames[upper] ?? character;
}
