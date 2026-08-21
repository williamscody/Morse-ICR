import 'training_session_record.dart';

/// Persists the training log (morse_icr_spec.md section 23: "Training
/// session records") across app launches, in entry order (oldest first
/// -- [TrainingLogScreen] displays newest first, but that's a display
/// concern, not a storage one).
///
/// Lets [TrainingScreen] and [TrainingLogScreen] read/write the log
/// without depending on a concrete storage mechanism, so both can be
/// tested without touching the real filesystem (morse_icr project
/// testing convention: plugin-backed classes get an interface and a
/// hand-written fake, no mocking library) -- the same pattern
/// [ProblemCharacterStore] and [CountdownTimerStore] already established.
abstract class TrainingLogStore {
  /// The persisted log, oldest first, or an empty list if nothing has
  /// ever been saved.
  Future<List<TrainingSessionRecord>> load();

  /// Persists [records], overwriting whatever was saved before.
  Future<void> save(List<TrainingSessionRecord> records);
}
