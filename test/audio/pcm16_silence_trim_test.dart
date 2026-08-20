import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/audio/pcm16_silence_trim.dart';

void main() {
  group('trimTrailingSilence', () {
    test('trims trailing near-silence beyond the margin', () {
      final samples = Int16List.fromList([
        5000, 6000, 5000, // loud
        0, 0, 0, 0, 0, // trailing near-silence
      ]);

      final trimmed = trimTrailingSilence(
        samples,
        thresholdAmplitude: 328,
        marginSamples: 1,
      );

      expect(trimmed, [5000, 6000, 5000, 0]);
    });

    test('leaves loud audio all the way to the end untouched', () {
      final samples = Int16List.fromList([5000, 6000, 5000]);

      final trimmed = trimTrailingSilence(samples, marginSamples: 0);

      expect(trimmed, samples);
    });

    test('returns the original samples unchanged when entirely silent', () {
      final samples = Int16List.fromList([0, 0, 0, 0]);

      final trimmed = trimTrailingSilence(samples);

      expect(trimmed, samples);
    });

    test('keeps samples at or below the threshold amplitude in the middle '
        'of loud audio', () {
      final samples = Int16List.fromList([5000, 100, 5000, 0, 0, 0]);

      final trimmed = trimTrailingSilence(
        samples,
        thresholdAmplitude: 328,
        marginSamples: 0,
      );

      expect(trimmed, [5000, 100, 5000]);
    });

    test('margin never extends past the end of the original samples', () {
      final samples = Int16List.fromList([5000, 0, 0]);

      final trimmed = trimTrailingSilence(
        samples,
        thresholdAmplitude: 328,
        marginSamples: 100,
      );

      expect(trimmed, samples);
    });
  });
}
