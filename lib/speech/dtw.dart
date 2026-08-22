import 'dart:math' as math;

/// Dynamic-time-warping distance between two MFCC feature sequences
/// (morse_icr_spec.md section 38), each a list of per-frame coefficient
/// vectors. Standard O(n·m) DTW over per-frame Euclidean distance,
/// normalized by path length (`a.length + b.length`) so clips of
/// different durations stay comparable.
///
/// Returns `double.infinity` if either sequence is empty -- nothing to
/// compare, so nothing can match.
double dtwDistance(List<List<double>> a, List<List<double>> b) {
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
      cost[i][j] = _euclideanDistance(a[i - 1], b[j - 1]) + step;
    }
  }
  return cost[n][m] / (n + m);
}

double _euclideanDistance(List<double> a, List<double> b) {
  var sum = 0.0;
  for (var i = 0; i < a.length; i++) {
    final diff = a[i] - b[i];
    sum += diff * diff;
  }
  return math.sqrt(sum);
}
