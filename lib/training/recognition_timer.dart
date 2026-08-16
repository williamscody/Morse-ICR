import 'dart:async';

/// Models the recognition-time countdown between the end of a Morse
/// character's playback and the computer announcing the answer
/// (morse_icr_spec.md section 6, section 29). Callers are responsible
/// for calling [start] exactly when Morse playback ends -- this class
/// has no notion of playback and will happily start too early if misused.
///
/// If the learner responds before the deadline, callers should [cancel]
/// the timer so [onExpired] never fires for that character (Milestone 8
/// will wire this to the learner's actual response). If nothing cancels
/// it in time, [onExpired] fires exactly once, signaling a miss.
class RecognitionTimer {
  Timer? _timer;

  /// Whether a countdown is currently in progress.
  bool get isRunning => _timer != null;

  /// Starts a countdown of [duration], calling [onExpired] if [cancel]
  /// isn't called first. Starting again while already running cancels
  /// the previous countdown without invoking its callback.
  void start(Duration duration, void Function() onExpired) {
    cancel();
    _timer = Timer(duration, () {
      _timer = null;
      onExpired();
    });
  }

  /// Cancels the running countdown, if any, preventing [onExpired] from
  /// firing. No-op if not running.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
