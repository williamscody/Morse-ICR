import 'package:audio_session/audio_session.dart';

/// Configures the app's single shared AVAudioSession for Morse tone and
/// TTS playback (main.dart's original comment: neither just_audio nor
/// flutter_tts touch AVAudioSession themselves, so this is the sole
/// thing governing the shared session's category).
///
/// Called once at cold start, and again whenever the app returns to the
/// foreground -- iOS can silently leave the session deactivated or on
/// the wrong category after backgrounding (most plausibly via
/// [SpeechToTextResponseListener]'s own category churn still being
/// mid-flight when backgrounded, per morse_icr_spec.md section 27).
/// A cold start after force-quitting always reconfigures from scratch
/// and masks the problem; an ordinary Home-button background/resume --
/// which keeps the process alive since UIBackgroundModes includes
/// "audio" -- does not, unless something reapplies it on resume.
Future<void> configureAudioSession() async {
  final session = await AudioSession.instance;
  await session.configure(
    const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
    ),
  );
}

/// Activates the shared AVAudioSession -- call when training starts.
Future<void> activateAudioSession() async {
  final session = await AudioSession.instance;
  await session.setActive(true);
}

/// Deactivates the shared AVAudioSession -- call when training stops.
Future<void> deactivateAudioSession() async {
  final session = await AudioSession.instance;
  await session.setActive(false);
}

/// True if audio is currently routing somewhere other than the device's
/// own built-in speaker/earpiece -- wired headphones/headset, Bluetooth,
/// or a USB/dock audio accessory.
///
/// Speech recognition requires this (morse_icr_spec.md section 27):
/// [SpeechToTextResponseListener] keeps the mic listening continuously
/// through the computer's own spoken announcement, and on-device testing
/// confirmed that with the built-in speaker, the phone reliably re-hears
/// its own TTS voice through open air and credits it as the learner's
/// spoken response -- indistinguishable from a genuine response by
/// timing alone, since both arrive within the same ASR-lag window.
/// Headphones route audio into the ear instead of the room, removing
/// that acoustic path entirely regardless of wired/Bluetooth latency.
Future<bool> hasNonSpeakerAudioOutput() async {
  final session = await AudioSession.instance;
  final outputs = await session.getDevices(includeInputs: false);
  return outputs.any(
    (device) =>
        device.type != AudioDeviceType.builtInSpeaker &&
        device.type != AudioDeviceType.builtInEarpiece,
  );
}
