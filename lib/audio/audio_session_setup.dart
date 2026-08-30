import 'package:audio_session/audio_session.dart';

/// Configures the app's single shared audio session for Morse tone and
/// TTS playback (main.dart's original comment: neither just_audio nor
/// flutter_tts touch AVAudioSession/AudioManager themselves, so this is
/// the sole thing governing the shared session's category/attributes).
///
/// Called once at cold start, and again whenever the app returns to the
/// foreground -- iOS can silently leave the session deactivated or on
/// the wrong category after backgrounding (originally traced to the
/// general-purpose speech_to_text engine's own category churn still
/// being mid-flight when backgrounded, per morse_icr_spec.md section 27;
/// that engine was later replaced, but this reconfiguration hasn't been
/// re-verified as unnecessary, so it stays).
/// A cold start after force-quitting always reconfigures from scratch
/// and masks the problem; an ordinary Home-button background/resume --
/// which keeps the process alive since UIBackgroundModes includes
/// "audio" -- does not, unless something reapplies it on resume.
Future<void> configureAudioSession() async {
  final session = await AudioSession.instance;
  await session.configure(
    const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      // Android has no equivalent of avAudioSessionCategory (ignored
      // there) -- these are its own fields, needed so Android requests
      // proper exclusive audio focus for this session instead of
      // whatever audio_session's bare platform defaults are (section 42,
      // Android background audio). AndroidAudioFocusGainType already
      // defaults to `.gain` (exclusive) even when unset; contentType/
      // usage don't have a meaningful default, so those are set
      // explicitly. `music`/`media` is the standard pairing for an app
      // whose own playback is the primary content, matching
      // AudioSessionConfiguration's own built-in `.music()` recipe.
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.music,
        usage: AndroidAudioUsage.media,
      ),
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
/// Speech recognition requires this (morse_icr_spec.md section 27): the
/// active listener keeps the mic listening continuously through the
/// computer's own spoken announcement, and on-device testing confirmed
/// that with the built-in speaker, the phone reliably re-hears its own
/// TTS voice through open air and credits it as the learner's spoken
/// response -- indistinguishable from a genuine response by timing
/// alone, since both arrive within the same post-announcement window.
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
