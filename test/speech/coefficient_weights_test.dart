import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/speech/coefficient_weights.dart';
import 'package:morse_icr/speech/mfcc.dart';

MfccSequence _take(List<double> frame) => [frame];

void main() {
  group('computeCoefficientWeights', () {
    test('returns null with fewer than two characters', () {
      final result = computeCoefficientWeights({
        'A': [
          _take([1, 1]),
          _take([1.1, 1]),
        ],
      });

      expect(result, isNull);
    });

    test(
      'returns null when no character has at least two non-empty takes',
      () {
        final result = computeCoefficientWeights({
          'A': [
            _take([1, 1]),
          ],
          'B': [
            _take([5, 5]),
          ],
        });

        expect(result, isNull);
      },
    );

    test('ignores empty takes rather than treating them as data points', () {
      final result = computeCoefficientWeights({
        'A': [
          [],
          _take([1, 1]),
          _take([1.1, 1]),
        ],
        'B': [
          _take([5, 5]),
          _take([5.1, 5]),
        ],
      });

      // Would have returned null (only 1 real take for A) if the empty
      // take had counted toward the >=2-takes requirement.
      expect(result, isNotNull);
    });

    test(
      'weights a coefficient higher when it separates characters while '
      "staying consistent within each character's own takes, and lower "
      'when it varies just as much within a character as between them',
      () {
        // Coefficient 0: A's takes are ~1, B's are ~5 -- large between-
        // class difference, tiny within-class spread. Reliable.
        // Coefficient 1: both characters hover around 3, with within-
        // class spread as large as the between-class difference.
        // Unreliable -- doesn't actually separate A from B.
        final result = computeCoefficientWeights({
          'A': [
            _take([1.0, 2.0]),
            _take([1.0, 4.0]),
          ],
          'B': [
            _take([5.0, 2.0]),
            _take([5.0, 4.0]),
          ],
        });

        expect(result, isNotNull);
        expect(result![0], greaterThan(result[1]));
      },
    );

    test('the returned weights average to 1.0, preserving the overall '
        "distance scale a caller's threshold was calibrated against", () {
      final result = computeCoefficientWeights({
        'A': [
          _take([1.0, 2.0, 100.0]),
          _take([1.0, 2.1, 100.0]),
        ],
        'B': [
          _take([9.0, 2.0, 100.0]),
          _take([9.0, 1.9, 100.0]),
        ],
      });

      expect(result, isNotNull);
      final average = result!.reduce((sum, w) => sum + w) / result.length;
      expect(average, closeTo(1.0, 1e-9));
    });

    test('a coefficient with zero within-class variance across every '
        "character doesn't produce an infinite or NaN weight", () {
      final result = computeCoefficientWeights({
        'A': [
          _take([1.0]),
          _take([1.0]),
        ],
        'B': [
          _take([5.0]),
          _take([5.0]),
        ],
      });

      expect(result, isNotNull);
      expect(result!.single.isFinite, isTrue);
    });
  });
}
