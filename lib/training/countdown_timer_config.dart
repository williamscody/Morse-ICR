/// Immutable snapshot of the training screen's three countdown-timer
/// memory slots (morse_icr_spec.md section 9) and which one, if any, is
/// the active timer that auto-stops training when it reaches zero.
///
/// Deliberately generic duration presets rather than the spec's full
/// Session A/B/C cycle (section 8) -- no character-set binding or
/// automatic sequencing yet; see morse_icr project memory for why this
/// scope was chosen for Milestone 9.
class CountdownTimerConfig {
  const CountdownTimerConfig({
    this.slotSeconds = const [null, null, null],
    this.selectedSlot,
  });

  /// Each memory's stored duration in whole seconds, or null if that
  /// memory has never been stored, or was cleared. Always length 3 --
  /// indices 0/1/2 correspond to the on-screen labels "1"/"2"/"3".
  final List<int?> slotSeconds;

  /// Which memory (0, 1, or 2) is the active timer, or null if no timer
  /// limits training -- the default, and the same as training's
  /// previously-unlimited behavior.
  final int? selectedSlot;

  /// The active timer's configured duration, or null if no timer is
  /// selected, or the selected memory has never been stored.
  Duration? get selectedDuration {
    final slot = selectedSlot;
    if (slot == null) return null;
    final seconds = slotSeconds[slot];
    if (seconds == null) return null;
    return Duration(seconds: seconds);
  }
}

/// Formats [duration] as "MM:SS" (morse_icr_spec.md section 9: "Display
/// remaining time"), rounding down to the whole second and clamping
/// negative durations to zero rather than rendering a negative sign.
String formatCountdown(Duration duration) {
  final totalSeconds = duration.inSeconds.clamp(0, 99 * 60 + 59);
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}
