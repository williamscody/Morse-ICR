/// Anything that can listen for the learner saying a character aloud
/// and report recognized characters back (morse_icr_spec.md section 27:
/// "the architecture should allow the speech-recognition implementation
/// to be replaced or improved later").
///
/// Lets the training screen drive listening without depending on a
/// concrete speech-recognition plugin, so it can be tested without a
/// real microphone (section 7: microphone input and speech recognition
/// are concerns kept separate from Morse generation/timing/scoring).
abstract class ResponseListener {
  /// Starts listening, calling [onRecognized] with a matched character
  /// (morse_icr_spec.md section 27's matching, not the raw transcript)
  /// each time one is recognized. May be called more than once per
  /// listening session, e.g. once per speech-recognition partial/final
  /// result -- callers decide what to do with an unmatched or repeated
  /// recognition.
  Future<void> startListening(void Function(String character) onRecognized);

  /// Marks a new character's start, so only speech heard from this
  /// point on is matched against it. Speech-recognition engines report
  /// a growing transcript across an entire listen session
  /// (morse_icr_spec.md section 27); without this checkpoint per
  /// character, later characters get appended onto earlier speech and
  /// can never match on their own. Deliberately does not restart the
  /// underlying listening session itself -- doing that adjacent to the
  /// computer's own spoken announcement raced the OS audio session
  /// handoff between speech recognition and text-to-speech and crashed
  /// the app on-device.
  Future<void> restart();

  /// Stops listening. No-op if not currently listening.
  Future<void> stopListening();
}
