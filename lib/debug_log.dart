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
//
// 2026-09-08: turned back on, then off again the same day -- first real
// Android device session (Moto G Play 2024) start to finish. Surfaced
// and fixed several real bugs this uncovered: the missing INTERNET
// permission (just_audio's local loopback proxy couldn't open a socket
// at all, so no audio ever played); TtsAnswerSpeaker's per-character
// cache file name using Object.hash/String.hashCode, which Dart
// randomizes per isolate, so every launch silently missed its own
// previous cache and re-synthesized all ~40 answer characters from
// scratch (~10s of no spoken answers or working Stop button); the
// missing BLUETOOTH_CONNECT permission speech_to_text's own native
// Bluetooth SCO handling needs (see AndroidManifest.xml); and a
// recognition restart-storm (error_client on every attempt, no cooldown
// between retries) now throttled in speech_to_text_response_listener.dart.
// See [[project_android_real_device_audio_bugs]] and
// [[project_android_bluetooth_recognition]] for the full writeup,
// including what's still open (onset-detection calibration for this
// specific Bluetooth-headset+phone-mic combo).
//
// 2026-09-10: turned back on, then off again the same day -- continued
// the recognition investigation above. Confirmed the error_client
// restart-storm is specific to on-device recognition (onDevice: true):
// switching to network mode produced zero error_client and the first
// genuine in-window onset (windowOpen: true) seen in this whole
// investigation, but introduced a new regression instead (a turn's
// play() reporting "completed" ~17ms after being issued instead of its
// real ~1.5s duration -- audible as chopped-off Morse tones), so
// reverted back to onDevice: true rather than trade one bug for
// another. See [[project_android_bluetooth_recognition]]'s update for
// the full detail. Still open.
//
// 2026-09-10 (later the same day): flipped on again, then off again --
// concluded the investigation above. Forked speech_to_text locally
// (third_party/speech_to_text) to fix the recognizer-reuse bug behind
// error_client, then switched Android to network-mode recognition
// (fixing the chopped-Morse-tone regression along the way -- just_audio
// was auto-pausing on the recognizer's own audio-focus request; see
// handleInterruptions: false on every AudioPlayer this app constructs).
// That got the whole pipeline working cleanly -- onset detection
// correctly caught in-window responses -- but real transcription
// accuracy for rapid, isolated single characters stayed too low to be
// usable, even after also trying more inter-character spacing (Extra
// Gap). Concluded this is a genuine accuracy ceiling of Android speech
// recognition for this app's use case, not a fixable bug. Speech
// Recognition is now disabled outright on Android (see
// SettingsScreen's Switch and TrainingScreen's _recognitionEnabled) --
// see [[project_android_bluetooth_recognition]] for the full writeup.
//
// 2026-09-10 (still later): flipped on, then off again -- continued
// investigating a separate, still-unresolved bug (a per-character
// stepped volume fade-in on Android playback, confirmed on both wired
// and Bluetooth output). Ruled out audio focus, this app's own
// setVolume() calls, and just_audio's own processingState/buffering
// timing (TurnAudioEngine._watchProcessingState, left in place --
// still an open investigation, not concluded) as the cause. A
// pause()-skip experiment made things measurably worse and was
// reverted. Bill is thinking about how to proceed; see
// [[project_android_bluetooth_recognition]]'s last section.
//
// 2026-09-10 (still later): flipped back on -- a sharper symptom report
// (sequential A-Z mode skipping straight from C to F) traced to a real
// bug in TrainingEngine._runLoop: a failed prepareTurn() silently
// abandoned its character instead of retrying it, because
// CharacterSelector.next() has no way to "give back" a character once
// drawn. Fixed (see that file's prepareFuture.catchError). That skip
// turned out to be a red herring anyway (same behavior confirmed on iOS,
// by design -- see [[project_android_bluetooth_recognition]]), but the
// fix is real and stays.
//
// 2026-09-11: turned off again -- the actual first-turn audio bug this
// logging was chasing is now confirmed fixed on-device (retuned 20Hz/
// 750ms primer + TurnAudioEngine.markSessionStart firing it on every
// Start/Resume, not just app launch). See
// [[project_android_bluetooth_recognition]] for the full resolution.
//
// 2026-09-13: turned back on, then off again -- investigated an
// iOS-only "some characters have a longer response gap" report
// (specifically digits 3-7). Screen-recording, speech-recognition, and
// stale-TTS-cache theories were all raised and disproven in turn.
// Concluded: not an app bug -- direct waveform inspection showed
// "three/four/five/six/seven" (all fricative-initial: th-/f-/f-/s-/s-)
// depart from true silence at the *same* elapsed time as every other
// character, just with a more gradual amplitude ramp, which is what a
// naive amplitude-threshold audio analysis was misreading as a longer
// gap. recognitionTimeMs is accurate and consistent for every
// character. See [[project_response_time_gap_investigation]] for the
// full writeup. [trimLeadingSilence] and TtsAnswerSpeaker's
// `_cacheFormatVersion` are real, unrelated improvements from this
// investigation and stay regardless.
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
