/// Anything that can speak a single Morse character aloud as the
/// "computer voice" answer (morse_icr_spec.md section 28) when the
/// learner doesn't respond before the recognition deadline.
///
/// Lets the training engine trigger the announcement without depending
/// on a concrete text-to-speech implementation, so the loop can be
/// tested without real speech synthesis (section 26: the speech engine
/// is a separate component from the training engine).
abstract class AnswerSpeaker {
  Future<void> speak(String character);
}
