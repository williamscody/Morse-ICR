import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import 'utterance_endpointer.dart';

/// Thrown when [recordCharacterTakes] can't record because microphone
/// permission has been denied.
class MicPermissionDenied implements Exception {}

/// Thrown when [recordCharacterTakes] goes [maxDurationPerTake] without
/// detecting a take's speech -- the learner didn't speak, spoke too
/// quietly to cross [UtteranceEndpointer]'s threshold, or started too
/// late.
class NoSpeechDetected implements Exception {}

/// Records [count] consecutive raw PCM16 takes of the learner speaking a
/// single character (morse_icr_spec.md section 38's multi-take
/// enrollment step), each trimmed to its own utterance via
/// [UtteranceEndpointer] -- at the same 16kHz mono format confirmed
/// clean by Milestone 13 step 1's on-device capture spike.
///
/// One continuous microphone stream/recorder session covers every take,
/// rather than starting and stopping a fresh one per take. On-device
/// testing (Milestone 13, 2026-08-22) found the per-take
/// stop-then-restart approach unreliable: immediately after the first
/// take's recorder was torn down, the second take's speech sometimes
/// went undetected entirely, needing the learner to speak it twice
/// before it registered -- consistent with iOS's audio session needing
/// a moment to settle right after a stop() before a fresh startStream()
/// reliably captures from the very first moment. A single continuous
/// stream, segmented into [count] utterances by one shared
/// [UtteranceEndpointer] instance, sidesteps that recorder-churn
/// entirely. [onTakeRecorded], if given, fires with the 1-based take
/// number the moment each one is captured -- real-time confirmation of
/// what's actually been recorded so far, for a UI to surface live
/// rather than the learner only finding out once every take is done.
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
/// not clipping a take's tail.
Future<List<Uint8List>> recordCharacterTakes(
  int count, {
  Duration maxDurationPerTake = const Duration(milliseconds: 4000),
  UtteranceEndpointer? endpointer,
  void Function(int takeNumber)? onTakeRecorded,
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

    final takes = <Uint8List>[];
    // Reassigned after every completed take (see below) -- always
    // resolved by whichever take is currently being waited on. Safe
    // without extra locking: Dart's single-threaded event loop can
    // never run the listener callback and this function's own
    // continuation at the same time, so there's no window for a chunk
    // event to complete the wrong completer.
    var completer = Completer<void>();
    subscription = stream.listen((chunk) {
      final utterance = localEndpointer.addChunk(
        chunk,
        pcm16ChunkDuration(chunk, sampleRate: sampleRate),
      );
      if (utterance != null) {
        takes.add(utterance);
        onTakeRecorded?.call(takes.length);
        if (!completer.isCompleted) completer.complete();
      }
    });

    for (var take = 0; take < count; take++) {
      await completer.future.timeout(
        maxDurationPerTake,
        onTimeout: () => throw NoSpeechDetected(),
      );
      completer = Completer<void>();
    }
    return takes;
  } finally {
    await subscription?.cancel();
    await recorder.stop();
    await recorder.dispose();
  }
}
