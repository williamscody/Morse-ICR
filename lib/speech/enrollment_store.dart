import 'dart:typed_data';

/// Persists the learner's enrolled reference recordings (morse_icr_spec.md
/// section 38): one short PCM16 clip per character, captured during
/// enrollment and later matched against at recognition time.
///
/// Lets the enrollment UI and the future recognizer read/write recordings
/// without depending on a concrete storage mechanism, so both can be
/// tested without touching the real filesystem (morse_icr project
/// testing convention: plugin-backed classes get an interface and a
/// hand-written fake, no mocking library).
abstract class EnrollmentStore {
  /// Characters that currently have a saved reference recording.
  Future<Set<String>> enrolledCharacters();

  /// Persists [pcm16] as [character]'s reference recording, overwriting
  /// whatever was saved before -- how re-enrollment (morse_icr_spec.md
  /// section 38) replaces a single character's clip.
  Future<void> saveRecording(String character, Uint8List pcm16);

  /// The saved reference recording for [character], or null if it has
  /// never been enrolled.
  Future<Uint8List?> loadRecording(String character);
}
