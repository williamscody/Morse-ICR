import 'dart:io';

import 'package:flutter/services.dart';

/// Silences Android's on-device SpeechRecognizer per-utterance earcon for
/// the duration of a listening session -- there is no public
/// RecognizerIntent extra to suppress it, since the sound comes from
/// Google's recognition service itself, not from this app. Targets
/// STREAM_NOTIFICATION specifically: STREAM_MUSIC was tried first and
/// ruled out (it's the same stream this app's own just_audio playback
/// uses, so muting it silenced the Morse tone/TTS voice too, without
/// even stopping the chime -- see MainActivity.kt's own comment). No-op
/// on every other platform (iOS's speech APIs don't play this sound).
class RecognitionSoundMuter {
  static const _channel = MethodChannel('morse_icr/recognition_sound');

  static Future<void> mute() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('mute');
  }

  static Future<void> unmute() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('unmute');
  }
}
