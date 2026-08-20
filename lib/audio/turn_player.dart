/// Precise offsets within one rendered "turn" buffer -- a character's
/// Morse tone, a recognition-time silent gap, and (if available) the
/// spoken answer, all rendered into one continuous buffer (morse_icr
/// project memory: the pre-mix architecture).
///
/// All durations are relative to the start of the turn (when playback
/// was told to begin). [TrainingEngine] uses [morseEnd] and
/// [answerStart] to evaluate whether a learner's response arrived within
/// the "beat the computer" window (morse_icr_spec.md section 7), and
/// [totalDuration] to pace the loop before generating the next turn.
class TurnTiming {
  const TurnTiming({
    required this.morseEnd,
    required this.answerStart,
    required this.totalDuration,
    required this.hasAnswer,
  });

  /// When the Morse tone segment ends and the recognition-time silence
  /// begins.
  final Duration morseEnd;

  /// When the recognition-time silence ends. Equal to [totalDuration]
  /// when [hasAnswer] is false -- the turn simply ends there, with no
  /// spoken answer baked in.
  final Duration answerStart;

  /// The full rendered turn's duration.
  final Duration totalDuration;

  /// Whether a spoken answer was actually baked into this turn -- false
  /// when the answer wasn't cached (or the caller asked to omit it, e.g.
  /// Voice turned off), in which case [TrainingEngine] falls back to
  /// live-announcing the answer once the recognition-time gap elapses.
  final bool hasAnswer;
}

/// Anything that can render and play one training "turn" -- a
/// character's Morse tone, a recognition-time silent gap, and (if
/// available) the spoken answer -- as one continuous buffer.
///
/// Lets the training engine drive playback without depending on the
/// concrete [package:just_audio]-backed engine, so the loop can be
/// tested without real audio (morse_icr_spec.md section 7: the
/// audio/timing engine should be testable independently).
abstract class TurnPlayer {
  /// Renders [character]'s turn at [wpm] with [recognitionTime] of
  /// baked-in silence, including the spoken answer if [includeAnswer] is
  /// true and one is cached, and plays it.
  Future<TurnTiming> playTurn(
    String character,
    double wpm,
    Duration recognitionTime, {
    required bool includeAnswer,
  });

  /// Renders [character]'s turn ahead of time, without starting
  /// playback, so a later [playPrepared] call can skip that rendering
  /// and setup cost. Optional: implementations that don't support
  /// preparing ahead can leave this as the default no-op --
  /// [playPrepared] returning null then tells callers nothing was
  /// prepared, so they fall back to [playTurn].
  Future<void> prepareTurn(
    String character,
    double wpm,
    Duration recognitionTime, {
    required bool includeAnswer,
  }) async {}

  /// Plays whatever [prepareTurn] most recently rendered, if it's still
  /// valid. Returns null (having played nothing) when there's nothing
  /// usable prepared, so callers know to fall back to [playTurn] instead.
  Future<TurnTiming?> playPrepared() async => null;

  /// Discards whatever [prepareTurn] most recently rendered, without
  /// playing it. Implementations that don't support preparing ahead can
  /// leave this as the default no-op.
  Future<void> cancelPrepared() async {}

  /// Immediately pauses whatever is currently playing. [TrainingEngine]
  /// calls this as the first step of stopping a session, before the
  /// caller goes on to tear down the shared audio session -- a turn's
  /// own [playTurn]/[playPrepared] call can still be genuinely in
  /// progress at that moment (Stop is no longer only ever observed in
  /// the gap between turns), and deactivating the audio session out from
  /// under still-in-flight playback can leave it hung forever rather
  /// than resolving normally. Implementations that don't hold onto
  /// in-flight playback between calls can leave this as the default
  /// no-op.
  Future<void> stopPlayback() async {}
}
