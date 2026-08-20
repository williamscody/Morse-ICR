import 'dart:typed_data' show Int16List;

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

  /// Raw, mono, 16-bit-PCM/44100Hz samples of [character]'s pre-rendered
  /// answer, trimmed of trailing silence -- or null if nothing is cached
  /// for it (not yet pre-rendered, or pre-rendering failed on this
  /// device). [TurnAudioEngine] splices these directly into a combined
  /// per-turn buffer alongside the Morse tone and recognition-time
  /// silence (morse_icr project memory: the pre-mix architecture), so
  /// this must return promptly -- a synchronous cache lookup, not a
  /// render. Implementations that don't support pre-mixing can leave
  /// this as the default null -- [TrainingEngine] falls back to calling
  /// [speak] live once the recognition deadline lapses.
  Int16List? cachedSamplesFor(String character) => null;
}
