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
      // each); normalizing by (3 + 3) gives 0.5.
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

      expect(dtwDistance(a, b), closeTo(0.5, 1e-9));
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

    test('an empty sequence never matches', () {
      final sequence = [
        [1.0, 2.0],
      ];

      expect(dtwDistance([], sequence), double.infinity);
      expect(dtwDistance(sequence, []), double.infinity);
    });
  });
}
