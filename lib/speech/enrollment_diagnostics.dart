import 'dart:math' as math;
import 'dart:typed_data';

import '../debug_log.dart';
import 'enrollment_store.dart';
import 'mfcc.dart';
import 'utterance_endpointer.dart' show pcm16ChunkDuration;

/// Diagnostic-only (Milestone 13, 2026-08-23): logs structural stats for
/// every saved take of [characters] -- duration, peak/RMS amplitude, MFCC
/// frame count, and average static-coefficient magnitude -- so an
/// on-device confusion found via `VoiceCharacterMatcher` (e.g. F
/// consistently matching as S) can be checked against a concrete
/// recording-level cause (an unusually short/quiet/differently-shaped
/// take) rather than guessed at from match distances alone. Remove once
/// the current investigation concludes.
Future<void> logEnrollmentDiagnostics(
  EnrollmentStore store,
  Set<String> characters,
) async {
  for (final character in characters) {
    final takes = await store.loadRecordings(character);
    if (takes.isEmpty) {
      logDebug('enrollment diag: $character -- not enrolled');
      continue;
    }
    for (var index = 0; index < takes.length; index++) {
      final take = takes[index];
      final samples = _decodeSamples(take);
      final peak = samples.fold<int>(0, (m, s) => s.abs() > m ? s.abs() : m);
      final rms = samples.isEmpty
          ? 0.0
          : math.sqrt(
              samples.fold<double>(0, (sum, s) => sum + s * s) /
                  samples.length,
            );
      final mfcc = extractMfcc(take);
      final staticMag = _averageStaticMagnitude(mfcc);
      logDebug(
        'enrollment diag: $character take $index -- '
        'durationMs=${pcm16ChunkDuration(take).inMilliseconds} '
        'frames=${mfcc.length} peak=$peak rms=${rms.toStringAsFixed(0)} '
        'staticMag=${staticMag.toStringAsFixed(2)}',
      );
    }
  }
}

List<int> _decodeSamples(Uint8List pcm16) {
  final byteData = ByteData.sublistView(pcm16);
  final sampleCount = pcm16.length ~/ 2;
  return [
    for (var i = 0; i < sampleCount; i++)
      byteData.getInt16(i * 2, Endian.little),
  ];
}

double _averageStaticMagnitude(List<List<double>> frames) {
  if (frames.isEmpty) return 0;
  var sum = 0.0;
  var count = 0;
  for (final frame in frames) {
    for (var i = 0; i < mfccStaticCoefficientCount; i++) {
      sum += frame[i].abs();
      count++;
    }
  }
  return count == 0 ? 0 : sum / count;
}
