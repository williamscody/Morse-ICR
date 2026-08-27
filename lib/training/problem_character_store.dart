/// Persists the learner's manually-entered problem-character set
/// (morse_icr_spec.md section 11) across app launches.
///
/// Lets [ProblemCharacterKeyboard] and [TrainingScreen] read/write the
/// set without depending on a concrete storage mechanism, so both can be
/// tested without touching the real filesystem (morse_icr project
/// testing convention: plugin-backed classes get an interface and a
/// hand-written fake, no mocking library).
abstract class ProblemCharacterStore {
  /// The persisted problem-character set, in entry order -- or null if
  /// nothing has ever been saved. Only ever written by the learner's own
  /// selection in [ProblemCharacterKeyboard] -- [TrainingScreen]'s own
  /// missed-character auto-detection (morse_icr_spec.md section 39)
  /// writes [saveAutoFlagged] instead, deliberately never this, so a
  /// character can't silently join what actually trains next (and what
  /// [ProblemCharacterKeyboard]'s "Focus (n active)" count reflects)
  /// without the learner having actually picked it (2026-08-26: an
  /// earlier version did merge auto-detected characters in here, which
  /// on-device testing found confusing in two ways at once -- the count
  /// no longer matched what was visibly selected, and a character that
  /// was silently pre-selected this way needed two taps to actually
  /// select, since the first tap deselected the invisible existing
  /// selection).
  Future<List<String>?> load();

  /// Persists [characters] as the problem-character set, overwriting
  /// whatever was saved before.
  Future<void> save(List<String> characters);

  /// The subset of characters flagged for review from a training
  /// session's missed characters (morse_icr_spec.md section 39) --
  /// surfaced by [ProblemCharacterKeyboard] but not selected there (see
  /// [load]'s own doc comment for why); tapping a chip clears its flag
  /// regardless of whether the tap selects or deselects it. Empty if
  /// nothing is currently flagged.
  Future<Set<String>> loadAutoFlagged();

  /// Persists [characters] as the auto-flagged subset outright,
  /// overwriting whatever was saved before -- [TrainingScreen] merges
  /// onto [loadAutoFlagged]'s previous result itself first (the same
  /// load-then-save pattern [saveScores] uses), so flags accumulate
  /// across sessions until the learner actually reviews them in
  /// [ProblemCharacterKeyboard], rather than a later session's own
  /// auto-detection silently clearing an earlier one nobody's seen yet.
  Future<void> saveAutoFlagged(Set<String> characters);

  /// The learner's persisted per-character "win" score: how many times
  /// each character has ever been spoken back correctly during training,
  /// accumulated across every session (not reset per session, unlike
  /// [TrainingScreen]'s own in-session hit/miss tally). A character never
  /// answered correctly -- including one never trained at all -- is
  /// absent rather than present with 0, so callers should treat a
  /// missing key as zero. Drives [ProblemCharacterKeyboard]'s heat-map
  /// chip coloring.
  Future<Map<String, int>> loadScores();

  /// Persists [scores] outright, overwriting whatever was saved before --
  /// callers merge onto [loadScores]'s previous result themselves first,
  /// the same load-then-save pattern [save] already uses for the
  /// character list itself.
  Future<void> saveScores(Map<String, int> scores);

  /// The learner's persisted per-character attempt count: how many times
  /// each character has ever been trained (correctly or not), accumulated
  /// across every session the same way [loadScores] accumulates -- so
  /// `loadScores()[c] / loadAttempts()[c]` is that character's all-time
  /// accuracy. A character never attempted is absent rather than present
  /// with 0, same convention as [loadScores]. Added 2026-08-31 alongside
  /// [ProblemCharacterKeyboard]'s "X% Correct" summary; a character
  /// scored before this existed has no attempt entry to match it, so it
  /// can't contribute to that percentage until trained again.
  Future<Map<String, int>> loadAttempts();

  /// Persists [attempts] outright, the same load-then-save pattern
  /// [saveScores] uses.
  Future<void> saveAttempts(Map<String, int> attempts);
}
