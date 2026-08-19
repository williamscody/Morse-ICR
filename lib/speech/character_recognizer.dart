import '../training/character_set.dart';
import 'spoken_character.dart';

/// Multi-word phrasings, and single-word variants not already covered
/// by reversing [spokenNames], that a learner might plausibly say for
/// punctuation (morse_icr_spec.md section 35 anticipates both
/// "Period"/"Dot" and "Slash"/"Stroke" as valid phrasings for the
/// computer's own voice; the same tolerance is extended here to what
/// the learner might say, independent of which one the computer
/// currently uses).
const Map<String, String> _phraseAliases = {
  'period': '.',
  'stroke': '/',
  'question mark': '?',
};

final Map<String, String> _reverseSpokenNames = {
  for (final entry in spokenNames.entries) entry.value: entry.key,
};

final Set<String> _knownCharacters = {
  for (final list in characterSets.values) ...list,
};

/// Matches raw speech-to-text output against the trainer's known
/// character set (morse_icr_spec.md section 27), returning the
/// matched character or null if nothing matches.
///
/// Speech-recognition engines commonly transcribe a single spoken
/// letter/digit as the bare literal token itself (e.g. "a", "8"),
/// distinct from the words this app's own TTS is told to say for most
/// letters (e.g. "bee" for B) -- both are tried, per word, alongside
/// the phrase aliases above. Multi-word results (e.g. "the letter A") are scanned
/// word by word, returning the first match found; this is a first
/// attempt at reasonable tolerance, not a finished matching strategy --
/// section 27 flags speech-recognition matching as needing real
/// on-device investigation and tuning.
String? characterForSpokenText(String recognizedText) {
  final normalized = recognizedText.trim().toLowerCase();
  if (normalized.isEmpty) return null;

  final phraseMatch =
      _phraseAliases[normalized] ?? _reverseSpokenNames[normalized];
  if (phraseMatch != null) return phraseMatch;

  for (final word in normalized.split(RegExp(r'\s+'))) {
    final aliasMatch = _phraseAliases[word] ?? _reverseSpokenNames[word];
    if (aliasMatch != null) return aliasMatch;

    final literal = word.toUpperCase();
    if (_knownCharacters.contains(literal)) return literal;
  }
  return null;
}
