import 'dart:math' as math;

/// Dynamic-time-warping distance between two MFCC feature sequences
/// (morse_icr_spec.md section 38), each a list of per-frame coefficient
/// vectors. Standard O(n·m) DTW over per-frame Euclidean distance,
/// normalized by `min(a.length, b.length)` so clips of different
/// durations stay comparable.
///
/// Normalized by `n + m` (combined length) until 2026-08-24. On-device
/// data that day (25WPM/700ms, the vowel-letter spoken forms A/E/I/O/U/Y)
/// found that formula systematically disadvantaged the shortest clips in
/// the vocabulary: the same absolute per-frame noise gets divided by a
/// *smaller* denominator for a short query/reference pair than a longer
/// one, inflating a short character's own self-distance more than a
/// longer character's -- letting a longer, merely-similar-sounding
/// competitor's normalized distance come out lower even when the short
/// character is genuinely what was said. Confirmed directly in that
/// session's logged candidate distances: "E" and "O" (both short, no
/// leading consonant) lost repeatedly to "A" (same cluster, but with
/// on-device data suggesting slightly more robust templates), including
/// two losses by margins of 0.30 and 0.05 in a metric that otherwise
/// ranges into the teens and twenties -- effectively noise-level ties
/// resolved by the length bias, not genuine acoustic difference.
/// Dividing by `min(n, m)` instead removes that asymmetry: it's the
/// warping-path-length equivalent of comparing "cost per frame of the
/// *shorter* clip" rather than diluting it across the combined length of
/// both, so a short reference's own noise no longer costs it more than a
/// long one's does.
///
/// [weights], when given (see [computeCoefficientWeights]), scales each
/// coefficient's contribution to the per-frame distance -- a coefficient
/// that's unreliable (varies a lot even between two takes of the same
/// character) contributes less than one that reliably separates
/// characters while staying stable within one. Omitted, every
/// coefficient counts equally (plain Euclidean distance), the original
/// behavior.
///
/// Returns `double.infinity` if either sequence is empty -- nothing to
/// compare, so nothing can match.
double dtwDistance(
  List<List<double>> a,
  List<List<double>> b, {
  List<double>? weights,
}) {
  final n = a.length;
  final m = b.length;
  if (n == 0 || m == 0) return double.infinity;

  final cost = List.generate(
    n + 1,
    (_) => List<double>.filled(m + 1, double.infinity),
  );
  cost[0][0] = 0;
  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      final step = math.min(
        cost[i - 1][j],
        math.min(cost[i][j - 1], cost[i - 1][j - 1]),
      );
      cost[i][j] = _euclideanDistance(a[i - 1], b[j - 1], weights) + step;
    }
  }
  return cost[n][m] / math.min(n, m);
}

double _euclideanDistance(List<double> a, List<double> b, List<double>? weights) {
  var sum = 0.0;
  for (var i = 0; i < a.length; i++) {
    final diff = a[i] - b[i];
    final weight = weights == null ? 1.0 : weights[i];
    sum += weight * diff * diff;
  }
  return math.sqrt(sum);
}
