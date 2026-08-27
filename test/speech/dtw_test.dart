import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/speech/dtw.dart';

void main() {
  group('dtwDistance', () {
    test('identical sequences have zero distance', () {
      final sequence = [
        [1.0, 2.0],
        [3.0, 4.0],
        [5.0, 6.0],
      ];

      expect(dtwDistance(sequence, sequence), 0.0);
    });

    test('a uniform per-frame offset produces the expected normalized '
        'distance', () {
      // Every frame pair is distance 1 apart regardless of alignment, so
      // the cheapest monotonic path is the diagonal (3 cells, cost 1
      // each); normalizing by min(3, 3) gives 1.0.
      final a = [
        [0.0],
        [0.0],
        [0.0],
      ];
      final b = [
        [1.0],
        [1.0],
        [1.0],
      ];

      expect(dtwDistance(a, b), closeTo(1.0, 1e-9));
    });

    test('normalizing by the shorter sequence, not the combined length, '
        "doesn't penalize a short clip's own self-distance as much as a "
        'long one\'s for the same per-frame noise', () {
      // Two pairs with identical per-frame offset (distance 1 apart,
      // same as above) but different lengths -- under the old `n + m`
      // normalization the short pair scored *worse* (1/(2+2)=0.25) than
      // the long pair (1/(6+6)=0.083) for the exact same acoustic
      // mismatch, purely because it had fewer frames to dilute it across
      // (2026-08-24 on-device: this measurably favored longer competing
      // characters over a short one like "e" even against a genuine,
      // correctly-spoken query). Normalizing by min(n, m) instead gives
      // both pairs the identical 1.0 -- length no longer changes how
      // costly the same per-frame mismatch reads as.
      final short = [
        [0.0],
        [0.0],
      ];
      final shortOffset = [
        [1.0],
        [1.0],
      ];
      final long = [
        [0.0],
        [0.0],
        [0.0],
        [0.0],
        [0.0],
        [0.0],
      ];
      final longOffset = [
        [1.0],
        [1.0],
        [1.0],
        [1.0],
        [1.0],
        [1.0],
      ];

      expect(
        dtwDistance(short, shortOffset),
        closeTo(dtwDistance(long, longOffset), 1e-9),
      );
    });

    test('discriminates a near match from a far one', () {
      final reference = [
        [0.0],
        [1.0],
        [2.0],
        [3.0],
      ];
      // A time-stretched (repeated first frame) copy of the same
      // underlying sequence -- DTW should absorb the stretch and stay
      // close.
      final near = [
        [0.0],
        [0.0],
        [1.0],
        [2.0],
        [3.0],
      ];
      final far = [
        [10.0],
        [11.0],
        [12.0],
        [13.0],
      ];

      expect(
        dtwDistance(reference, near),
        lessThan(dtwDistance(reference, far)),
      );
    });

    test('weights scale each coefficient\'s contribution to the distance', () {
      final a = [
        [0.0, 0.0],
      ];
      final b = [
        [1.0, 1.0],
      ];

      // Unweighted: sqrt(1^2 + 1^2) = sqrt(2).
      expect(dtwDistance(a, b), closeTo(math.sqrt(2), 1e-9));

      // Zeroing out coefficient 1 entirely leaves only coefficient 0's
      // contribution.
      expect(
        dtwDistance(a, b, weights: [1.0, 0.0]),
        closeTo(1.0, 1e-9),
      );

      // Weighting coefficient 0 up and coefficient 1 down by the same
      // factor moves the distance in the expected direction rather than
      // just rescaling everything uniformly.
      expect(
        dtwDistance(a, b, weights: [4.0, 0.25]),
        closeTo(math.sqrt(4 * 1 + 0.25 * 1), 1e-9),
      );
    });

    test('an empty sequence never matches', () {
      final sequence = [
        [1.0, 2.0],
      ];

      expect(dtwDistance([], sequence), double.infinity);
      expect(dtwDistance(sequence, []), double.infinity);
    });
  });
}
