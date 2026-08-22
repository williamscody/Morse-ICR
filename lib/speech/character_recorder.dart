import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import 'utterance_endpointer.dart';

/// Thrown when [recordCharacterClip] can't record because microphone
/// permission has been denied.
class MicPermissionDenied implements Exception {}

/// Thrown when [recordCharacterClip] never detects speech within
/// [maxDuration] -- the learner didn't speak, spoke too quietly to
/// cross [UtteranceEndpointer]'s threshold, or started too late.
class NoSpeechDetected implements Exception {}

/// Records a raw PCM16 clip of the learner speaking a single character
/// (morse_icr_spec.md section 38's enrollment step), trimmed to the
/// actual utterance via [UtteranceEndpointer] rather than a fixed
/// duration -- at the same 16kHz mono format confirmed clean by
/// Milestone 13 step 1's on-device capture spike.
///
/// Originally recorded a blind fixed 1.5s window regardless of actual
/// word length. On-device data (Milestone 13, 2026-08-21) showed that
/// was more than a performance problem: untrimmed references dominated
/// by silence padding were winning DTW comparisons they shouldn't have
/// (short spoken forms like "a"/"bee" acting as false-positive
/// attractors for unrelated characters at a 40-character enrollment).
/// [endpointer] defaults to a longer [UtteranceEndpointer.hangoverDuration]
/// than live recognition uses -- enrollment happens once per character
/// and isn't time-critical, so it's worth being more conservative about
/// not clipping the word's tail.
Future<Uint8List> recordCharacterClip({
  Duration maxDuration = const Duration(milliseconds: 4000),
  UtteranceEndpointer? endpointer,
}) async {
  final recorder = AudioRecorder();
  final localEndpointer =
      endpointer ??
      UtteranceEndpointer(hangoverDuration: const Duration(milliseconds: 500));
  StreamSubscription<Uint8List>? subscription;
  try {
    if (!await recorder.hasPermission()) throw MicPermissionDenied();
    const sampleRate = 16000;
    final stream = await recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
      ),
    );

    final completer = Completer<Uint8List>();
    subscription = stream.listen((chunk) {
      if (completer.isCompleted) return;
      final utterance = localEndpointer.addChunk(
        chunk,
        pcm16ChunkDuration(chunk, sampleRate: sampleRate),
      );
      if (utterance != null) completer.complete(utterance);
    });

    return await completer.future.timeout(
      maxDuration,
      onTimeout: () => throw NoSpeechDetected(),
    );
  } finally {
    await subscription?.cancel();
    await recorder.stop();
    await recorder.dispose();
  }
}
