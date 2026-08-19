import 'dart:async';

import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../debug_log.dart';
import 'character_recognizer.dart';
import 'response_listener.dart';

/// Wraps package:speech_to_text to implement [ResponseListener]
/// (morse_icr_spec.md section 27).
///
/// Each platform listen session is time-limited by the OS (Android
/// especially, often on the order of ten seconds of silence) -- this
/// restarts listening automatically whenever a session ends on its own
/// while [startListening] is still supposed to be active, so
/// recognition stays live for the whole training session rather than
/// just its first several seconds.
class SpeechToTextResponseListener implements ResponseListener {
  SpeechToTextResponseListener({SpeechToText? speechToText})
    : _speechToText = speechToText ?? SpeechToText();

  final SpeechToText _speechToText;
  void Function(String character)? _onRecognized;
  bool _shouldBeListening = false;

  // The OS reports one growing transcript for an entire listen session
  // rather than one per character (confirmed on-device: consecutive
  // single-letter utterances arrive as "E", "EE", "EET", "EETF", ...
  // with no word-boundary spaces between them), which defeats
  // character_recognizer's whitespace-split matching for every
  // character after the first. [restart] checkpoints [_consumedText]
  // to whatever's been heard so far, so [_onResult] only matches the
  // text appended since the last character began -- a software-only
  // reset. An earlier version restarted the native session instead
  // (stop() + listen()) to get the same effect, but doing that
  // adjacent to flutter_tts speaking the answer raced the OS
  // AVAudioSession handoff between the two plugins and crashed the
  // app on-device.
  String _consumedText = '';
  String _lastFullText = '';

  @override
  Future<void> startListening(
    void Function(String character) onRecognized,
  ) async {
    _onRecognized = onRecognized;
    _shouldBeListening = true;
    final available = await _speechToText.initialize(onStatus: _onStatus);
    if (!available || !_shouldBeListening) return;
    await _listen();
  }

  @override
  Future<void> restart() async {
    _consumedText = _lastFullText;
  }

  @override
  Future<void> stopListening() async {
    _shouldBeListening = false;
    _onRecognized = null;
    await _speechToText.stop();
  }

  Future<void> _listen() async {
    if (!_shouldBeListening || _speechToText.isListening) return;
    _consumedText = '';
    _lastFullText = '';
    // On-device recognition skips the network round-trip to Apple's
    // servers that the (default) hybrid on-device/network mode can
    // take -- measured on-device, results otherwise arrived 700ms-1.5s
    // after the speech that produced them, well past any recognition
    // window a fast-paced training loop can afford to wait.
    await _speechToText.listen(
      onResult: _onResult,
      listenOptions: SpeechListenOptions(onDevice: true),
    );
  }

  // Restarts listening once the OS-imposed session limit ends a listen
  // session on its own -- without this, recognition would silently stop
  // working partway through a training session instead of covering it.
  void _onStatus(String status) {
    if (_shouldBeListening &&
        (status == SpeechToText.doneStatus ||
            status == SpeechToText.notListeningStatus)) {
      unawaited(_listen());
    }
  }

  // Runs on both partial and final results (package:speech_to_text
  // defaults to reporting partials) -- an unmatched result simply
  // doesn't call [_onRecognized], leaving listening to continue.
  //
  // A [SpeechRecognitionResult.isConfident] gate was tried here to
  // filter out ambient-noise false positives (short function words
  // like "a"/"I" getting hallucinated from silence, since those are
  // themselves valid single-character matches -- section 27) but had to
  // be reverted: on-device measurement showed it rejected *all* results,
  // including genuine correctly-spoken characters, not just noise --
  // consistent with `SpeechListenOptions(onDevice: true)` (see
  // [_listen]) reporting `confidence: 0.0` on iOS rather than the -1
  // "missing" sentinel [isConfident] treats as pass-through, since
  // Apple's on-device recognizer doesn't compute per-word confidence the
  // way its server-based path does. [logDebug] calls below capture
  // `confidence`/`resultType` on real device data before any further
  // filtering is attempted.
  void _onResult(SpeechRecognitionResult result) {
    final fullText = result.recognizedWords;
    _lastFullText = fullText;
    final newText = fullText.startsWith(_consumedText)
        ? fullText.substring(_consumedText.length)
        : fullText; // the OS revised earlier text -- treat it all as new
    logDebug(
      'heard "$newText" (full="$fullText" conf=${result.confidence} '
      'final=${result.finalResult})',
    );
    final character = characterForSpokenText(newText);
    if (character != null) {
      _consumedText = fullText;
      _onRecognized?.call(character);
    }
  }
}
