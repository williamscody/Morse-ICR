import 'package:flutter/foundation.dart';

/// Temporary diagnostic logging for hard on-device bugs -- `--release`
/// builds on this project's test device have no readable console
/// output (see project memory: no Dart VM service in AOT release
/// builds, and no working device-console tooling either), so
/// [entries] backs an on-screen copyable log instead of relying on
/// [debugPrint] alone. Remove once whatever's being investigated is
/// confirmed fixed on-device.
final ValueNotifier<List<String>> debugLogEntries = ValueNotifier([]);

// 2026-08-30: on-device diagnostic logging turned off now that Milestone
// 13's speech-recognition timing work is done -- Bill asked for it off
// and the on-screen panel hidden. Left as a flip-able flag (not deleted)
// since the next hard-to-diagnose on-device bug will want this back.
//
// 2026-09-02: turned back on, then off again the same day -- confirmed
// the AirPods loud-voice bug fixed (a hung live-speak() call wedging the
// TTS queue) and the missing iOS lock-screen controls resolved (a stuck
// per-app mediaremoted registration, cleared by rebooting the device;
// not a code bug at all). Flip back on for the next hard-to-diagnose
// on-device bug.
const bool _loggingEnabled = false;

void logDebug(String message) {
  if (!_loggingEnabled) return;
  final now = DateTime.now();
  final timestamp =
      '${now.hour.toString().padLeft(2, '0')}:'
      '${now.minute.toString().padLeft(2, '0')}:'
      '${now.second.toString().padLeft(2, '0')}.'
      '${now.millisecond.toString().padLeft(3, '0')}';
  final line = '$timestamp $message';
  debugPrint('[morse_icr] $line');
  debugLogEntries.value = [...debugLogEntries.value, line];
}
