import 'dart:math' as math;
import 'dart:typed_data';

/// Deterministic synthetic PCM16 clips standing in for real speech in
/// tests that can't use a real microphone -- see morse_icr_spec.md
/// section 38's own note that this recognizer's matching needs
/// real-voice investigation eventually, but the algorithm's plumbing
/// and discrimination behavior can be verified without it.
Uint8List sineWavePcm16(
  double frequencyHz, {
  double durationSeconds = 0.5,
  int sampleRate = 16000,
  double amplitude = 0.5,
}) {
  final sampleCount = (durationSeconds * sampleRate).round();
  final bytes = ByteData(sampleCount * 2);
  for (var i = 0; i < sampleCount; i++) {
    final sample =
        amplitude * math.sin(2 * math.pi * frequencyHz * i / sampleRate);
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
