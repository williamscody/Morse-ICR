import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import 'enrollment_store.dart';
import 'file_enrollment_store.dart';
import 'response_listener.dart';
import 'utterance_endpointer.dart';
import 'voice_character_matcher.dart';

/// Implements [ResponseListener] (morse_icr_spec.md section 38) using
/// the enrollment-trained [VoiceCharacterMatcher] instead of
/// `package:speech_to_text`: one continuous raw-PCM16 mic stream (same
/// `pcm16bits`/16000Hz/mono capture proven in Milestone 13 steps 1-2),
/// segmented into individual utterances by [UtteranceEndpointer], each
/// matched against the learner's enrolled recordings.
///
/// Not yet wired in as `TrainingScreen`'s production listener (that's
/// step 5) -- this class exists to be tried on-device via a temporary
/// debug trigger first.
class VoiceResponseListener implements ResponseListener {
  VoiceResponseListener({
    VoiceCharacterMatcher? matcher,
    EnrollmentStore? enrollmentStore,
    UtteranceEndpointer? endpointer,
  }) : _matcher =
           matcher ??
           VoiceCharacterMatcher(enrollmentStore ?? FileEnrollmentStore()),
       _endpointer = endpointer ?? UtteranceEndpointer();

  final VoiceCharacterMatcher _matcher;
  final UtteranceEndpointer _endpointer;
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _subscription;
  void Function(String character)? _onRecognized;

  @override
  Future<void> startListening(
    void Function(String character) onRecognized,
  ) async {
    _onRecognized = onRecognized;
    if (!await _recorder.hasPermission()) return;
    _endpointer.reset();
    const sampleRate = 16000;
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
      ),
    );
    _subscription = stream.listen(_onChunk);
  }

  @override
  Future<void> restart() async {
    _endpointer.reset();
  }

  @override
  Future<void> stopListening() async {
    _onRecognized = null;
    await _subscription?.cancel();
    _subscription = null;
    await _recorder.stop();
  }

  void _onChunk(Uint8List chunk) {
    final utterance = _endpointer.addChunk(chunk, _chunkDuration(chunk));
    if (utterance != null) unawaited(_matchAndReport(utterance));
  }

  Future<void> _matchAndReport(Uint8List utterance) async {
    final character = await _matcher.match(utterance);
    if (character != null) _onRecognized?.call(character);
  }

  // PCM16 mono at 16kHz: 2 bytes per sample, 16000 samples per second.
  Duration _chunkDuration(Uint8List chunk) {
    final sampleCount = chunk.length ~/ 2;
    return Duration(microseconds: sampleCount * 1000000 ~/ 16000);
  }
}
