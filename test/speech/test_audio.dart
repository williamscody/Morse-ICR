import 'dart:math' as math;
import 'dart:typed_data';

/// Deterministic synthetic PCM16 clips standing in for real speech in
/// tests that can't use a real microphone -- see morse_icr_spec.md
/// section 38's own note that this recognizer's matching needs
/// real-voice investigation eventually, but the algorithm's plumbing
/// and discrimination behavior can be verified without it.
/// A mild upward chirp, not a pure constant tone -- cepstral mean
/// normalization (`mfcc.dart`) removes whatever's constant across a
/// clip's frames, so a perfectly steady tone collapses to near-zero
/// everywhere post-normalization (every 25ms frame is already nearly
/// identical to the clip's own mean) and stops being a meaningful
/// stand-in for a spoken character, which -- like real speech --
/// always varies somewhat frame to frame within a single word.
Uint8List sineWavePcm16(
  double frequencyHz, {
  double durationSeconds = 0.5,
  int sampleRate = 16000,
  double amplitude = 0.5,
}) {
  const sweepFraction = 0.3;
  final sampleCount = (durationSeconds * sampleRate).round();
  final bytes = ByteData(sampleCount * 2);
  var phase = 0.0;
  for (var i = 0; i < sampleCount; i++) {
    final t = i / sampleRate;
    final instantaneousFrequency =
        frequencyHz * (1 + sweepFraction * t / durationSeconds);
    phase += 2 * math.pi * instantaneousFrequency / sampleRate;
    final sample = amplitude * math.sin(phase);
    final intSample = (sample * 32767).round().clamp(-32768, 32767);
    bytes.setInt16(i * 2, intSample, Endian.little);
  }
  return bytes.buffer.asUint8List();
}

Uint8List whiteNoisePcm16({
  double durationSeconds = 0.5,
  int sampleRate = 16000,
  int seed = 1,
}) {
  final random = math.Random(seed);
  final sampleCount = (durationSeconds * sampleRate).round();
  final bytes = ByteData(sampleCount * 2);
  for (var i = 0; i < sampleCount; i++) {
    bytes.setInt16(i * 2, random.nextInt(65536) - 32768, Endian.little);
  }
  return bytes.buffer.asUint8List();
}
