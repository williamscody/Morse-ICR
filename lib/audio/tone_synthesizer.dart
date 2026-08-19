import 'dart:math' as math;
import 'dart:typed_data';

import '../morse/morse_event.dart';
import 'pcm16_wav.dart';

/// Renders a sequence of [MorseElement]s into a 16-bit PCM mono WAV
/// buffer at [frequencyHz].
///
/// Each tone-on segment gets a short raised-cosine amplitude ramp at its
/// start and end ([rampSeconds]) to avoid audible clicks at the sharp
/// edges of a pure on/off envelope. The ramp is clamped to a quarter of
/// the segment's own duration, so it stays negligible even at very high
/// WPM (e.g. a 150 WPM dit is only 8ms).
class ToneSynthesizer {
  const ToneSynthesizer({
    this.sampleRate = 44100,
    this.frequencyHz = 600,
    this.amplitude = 0.6,
    this.rampSeconds = 0.002,
  });

  final int sampleRate;
  final double frequencyHz;
  final double amplitude;
  final double rampSeconds;

  Uint8List synthesizeWav(List<MorseElement> elements) {
    final samples = _renderSamples(elements);
    return pcm16WavBytes(samples, sampleRate: sampleRate);
  }

  Int16List _renderSamples(List<MorseElement> elements) {
    final segmentSampleCounts = elements
        .map((e) => (e.durationSeconds * sampleRate).round())
        .toList();
    final totalSamples = segmentSampleCounts.fold<int>(0, (a, b) => a + b);
    final out = Int16List(totalSamples);

    var sampleIndex = 0;
    var phase = 0.0;
    final phaseIncrement = 2 * math.pi * frequencyHz / sampleRate;

    for (var e = 0; e < elements.length; e++) {
      final element = elements[e];
      final segmentSamples = segmentSampleCounts[e];
      final ramp = element.toneOn
          ? math.min(rampSeconds, element.durationSeconds / 4)
          : 0.0;
      final rampSamples = (ramp * sampleRate).round();

      for (var i = 0; i < segmentSamples; i++) {
        if (!element.toneOn) {
          out[sampleIndex++] = 0;
          continue;
        }

        double envelope;
        if (rampSamples > 0 && i < rampSamples) {
          envelope = 0.5 - 0.5 * math.cos(math.pi * i / rampSamples);
        } else if (rampSamples > 0 && i >= segmentSamples - rampSamples) {
          final fromEnd = segmentSamples - i;
          envelope = 0.5 - 0.5 * math.cos(math.pi * fromEnd / rampSamples);
        } else {
          envelope = 1.0;
        }

        final value = amplitude * envelope * math.sin(phase);
        out[sampleIndex++] = (value * 32767).round().clamp(-32768, 32767);

        phase += phaseIncrement;
        if (phase > 2 * math.pi) phase -= 2 * math.pi;
      }
    }

    return out;
  }
}
