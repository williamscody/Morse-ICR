import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/audio/pcm16_gain.dart';

void main() {
  group('scaleInt16Samples', () {
    test('scales every sample by the given gain', () {
      final samples = Int16List.fromList([1000, -1000, 2000, -2000]);

      final scaled = scaleInt16Samples(samples, 0.5);

      expect(scaled, [500, -500, 1000, -1000]);
    });

    test('gain of 1.0 returns the same instance unchanged', () {
      final samples = Int16List.fromList([1000, -1000]);

      final scaled = scaleInt16Samples(samples, 1.0);

      expect(identical(scaled, samples), isTrue);
    });

    test('gain of 0.0 silences every sample', () {
      final samples = Int16List.fromList([32767, -32768, 500]);

      final scaled = scaleInt16Samples(samples, 0.0);

      expect(scaled, [0, 0, 0]);
    });

    test('clamps rather than wraps around when gain pushes past full scale', () {
      final samples = Int16List.fromList([30000, -30000]);

      final scaled = scaleInt16Samples(samples, 2.0);

      expect(scaled, [32767, -32768]);
    });

    test('does not mutate the original samples', () {
      final samples = Int16List.fromList([1000, 2000]);

      scaleInt16Samples(samples, 0.5);

      expect(samples, [1000, 2000]);
    });
  });
}
