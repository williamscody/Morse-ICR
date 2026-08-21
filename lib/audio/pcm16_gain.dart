import 'dart:typed_data';

/// Scales 16-bit PCM [samples] by [gain] (typically 0.0-1.0), clamping to
/// the valid Int16 range to avoid wraparound distortion if [gain] pushes
/// a sample past full scale. Returns a new list -- [samples] itself
/// (e.g. a cached TTS clip reused across many turns) is never mutated in
/// place.
///
/// Applying gain here, directly to the samples, rather than via the
/// audio player's own volume control, is what lets Morse volume and
/// Voice volume (morse_icr_spec.md section 35) be independent: both a
/// character's Morse tone and its spoken answer are spliced into one
/// combined buffer played by a single [AudioPlayer] (morse_icr project
/// memory: the pre-mix architecture), so a single player-level volume
/// couldn't apply a different level to each half of that same buffer.
Int16List scaleInt16Samples(Int16List samples, double gain) {
  if (gain == 1.0) return samples;
  final out = Int16List(samples.length);
  for (var i = 0; i < samples.length; i++) {
    out[i] = (samples[i] * gain).round().clamp(-32768, 32767);
  }
  return out;
}
