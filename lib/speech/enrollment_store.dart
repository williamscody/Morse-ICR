import 'dart:typed_data';

/// Persists the learner's enrolled reference recordings (morse_icr_spec.md
/// section 38): multiple short PCM16 takes per character, captured during
/// enrollment and later matched against at recognition time.
///
/// Lets the enrollment UI and the recognizer read/write recordings
/// without depending on a concrete storage mechanism, so both can be
/// tested without touching the real filesystem (morse_icr project
/// testing convention: plugin-backed classes get an interface and a
/// hand-written fake, no mocking library).
///
/// One take per character was the original design; moved to multiple
/// (Milestone 13, 2026-08-22) after on-device data showed a single take
/// makes DTW matching sensitive to that one recording's own noise (mic
/// distance, background noise, momentary vocal variation) rather than
/// the character's actual acoustic signature -- comparing a query
/// against several takes and keeping the closest is the standard fix
/// for a small multi-exemplar template matcher.
abstract class EnrollmentStore {
  /// Characters that currently have at least one saved take.
  Future<Set<String>> enrolledCharacters();

  /// Persists [pcm16Takes] as [character]'s reference recordings,
  /// replacing whatever was saved before -- how re-enrollment
  /// (morse_icr_spec.md section 38) replaces a character's takes.
  Future<void> saveRecordings(String character, List<Uint8List> pcm16Takes);

  /// The saved reference takes for [character], in the order they were
  /// enrolled, or an empty list if it has never been enrolled.
  Future<List<Uint8List>> loadRecordings(String character);
}
