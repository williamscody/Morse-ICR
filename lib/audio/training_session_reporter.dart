/// Anything that can mirror the training loop's running/stopped state
/// into the OS media session (lock screen / Dynamic Island / Android
/// notification) and forward remote transport controls back to the
/// screen that owns [TrainingEngine].
///
/// Lets [TrainingScreen] report state changes without depending on the
/// concrete [package:audio_service]-backed handler, so tests can omit
/// it entirely (morse_icr_spec.md section 26: OS media-session
/// integration is a thin layer alongside the audio architecture's
/// components, not one of them).
abstract class TrainingSessionReporter {
  /// Call once a training session has actually started.
  void reportStarted();

  /// Call once a training session has actually stopped.
  void reportStopped();

  /// Invoked when the learner taps Stop from the lock screen, Control
  /// Center, Dynamic Island, or Android notification.
  set onStopRequested(void Function()? callback);

  /// Invoked when the learner taps Play from the lock screen/Control
  /// Center/notification -- only meaningful once a session has run at
  /// least once this launch, since that's the only place the character
  /// set/speed/recognition-time to resume with can come from.
  set onPlayRequested(void Function()? callback);
}
