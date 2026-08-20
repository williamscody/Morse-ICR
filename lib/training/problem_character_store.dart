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
  /// nothing has ever been saved.
  Future<List<String>?> load();

  /// Persists [characters] as the problem-character set, overwriting
  /// whatever was saved before.
  Future<void> save(List<String> characters);
}
