/// A snapshot of which character (if any) a response window was open
/// for, and whether it was open, captured at a specific moment --
/// carried alongside a matched character into [ResponseCallback] so the
/// receiver can judge "on time" against that earlier moment (e.g. speech
/// onset) rather than against whenever recognition eventually finishes
/// resolving what was said. See `TrainingEngine.captureResponseWindow`
/// and `TrainingEngine.submitResponse`'s `at` parameter (Milestone 13,
/// 2026-08-22): recognition latency shouldn't be able to eat into a
/// recognitionTime budget it never actually needed for the timing
/// decision itself.
typedef ResponseWindowSnapshot = ({String? character, bool windowOpen});

/// Reports a matched character, optionally alongside the
/// [ResponseWindowSnapshot] captured when the response actually started
/// (not necessarily when recognition of it finished). `at` is omitted by
/// a listener implementation with no separate onset moment to hook (only
/// ever getting a finished result), in which case the receiver falls
/// back to judging against live state at call time.
typedef ResponseCallback =
    void Function(String character, {ResponseWindowSnapshot? at});

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
  Future<void> startListening(ResponseCallback onRecognized);

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

/// Mixed into a [ResponseListener] implementation that can detect speech
/// onset separately from when recognition of it finishes, so it can
/// supply [ResponseCallback]'s `at` parameter. [TrainingScreen] wires
/// [captureResponseWindow] to `TrainingEngine.captureResponseWindow` via
/// an `is OnsetDetectingResponseListener` check -- one shared hook point
/// for every implementation that supports it, rather than a separate
/// `is SomeSpecificListener` branch per implementation (2026-08-26: was
/// about to become two before this was pulled out).
mixin OnsetDetectingResponseListener {
  ResponseWindowSnapshot Function()? captureResponseWindow;

  /// Called (by the same `TrainingScreen` wiring as
  /// [captureResponseWindow]) the instant a new turn's response window
  /// opens -- lets an implementation re-arm onset detection at this
  /// boundary rather than only ever on genuine acoustic silence, which
  /// back-to-back rapid answers may not reliably provide between turns
  /// (see `TrainingEngine.onResponseWindowOpened`'s own doc comment for
  /// the on-device data behind this, 2026-08-28). Default no-op: only
  /// [SpeechToTextResponseListener] currently needs this;
  /// [VoiceResponseListener] arms onset per-turn through its own
  /// `UtteranceEndpointer` mechanism already.
  void armForNewTurn() {}
}
