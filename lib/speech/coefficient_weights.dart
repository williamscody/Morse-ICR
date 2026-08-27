import 'mfcc.dart';

/// Computes a per-coefficient weight for [dtwDistance] from a learner's
/// full enrollment (morse_icr project memory, 2026-08-24 vowel-letter
/// confusability investigation): `betweenClassVariance /
/// withinClassVariance` per MFCC dimension -- the simplified
/// diagonal-covariance form of Fisher's linear discriminant criterion.
///
/// Plain (unweighted) DTW treats every coefficient as equally
/// trustworthy. On-device data found that's not true: some coefficients
/// vary a lot between a learner's own several takes of the *same*
/// character (mic distance, pace, momentary noise) while others stay
/// consistent within a character but reliably differ *between*
/// characters. A coefficient that reliably separates characters while
/// staying stable across a single character's own takes should count
/// more in the distance calculation; one that's noisy even between two
/// takes of the same character is unreliable regardless of how much it
/// happens to separate characters on average, and should count less.
///
/// [takesByCharacter] holds each enrolled character's already-extracted
/// per-take [MfccSequence]s. Needs at least two characters, each with at
/// least two non-empty takes, to produce a meaningful result -- both
/// within-class variance (needs >=2 takes to measure "how much does one
/// character's own takes disagree") and between-class variance (needs
/// >=2 characters to measure "how much do different characters differ")
/// are otherwise undefined. Returns null in that case, letting the
/// caller fall back to unweighted (plain Euclidean) distance rather than
/// dividing by an unmeasurable variance.
List<double>? computeCoefficientWeights(
  Map<String, List<MfccSequence>> takesByCharacter,
) {
  // One summary vector per take: the mean of that take's own frames,
  // per coefficient -- condenses a variable-length utterance into a
  // single point so different takes (and different characters) can be
  // compared directly, independent of how many frames each happened to
  // have.
  final summariesByCharacter = <String, List<List<double>>>{};
  for (final entry in takesByCharacter.entries) {
    final summaries = [
      for (final take in entry.value)
        if (take.isNotEmpty) _meanVector(take),
    ];
    if (summaries.length >= 2) summariesByCharacter[entry.key] = summaries;
  }
  if (summariesByCharacter.length < 2) return null;

  final coefficientCount = summariesByCharacter.values.first.first.length;

  // Within-class variance: how much a single character's own takes
  // disagree with each other, per coefficient -- averaged across every
  // character with enough takes to measure it.
  final withinClass = List<double>.filled(coefficientCount, 0);
  for (final summaries in summariesByCharacter.values) {
    final variance = _variance(summaries);
    for (var i = 0; i < coefficientCount; i++) {
      withinClass[i] += variance[i];
    }
  }
  for (var i = 0; i < coefficientCount; i++) {
    withinClass[i] /= summariesByCharacter.length;
  }

  // Between-class variance: how much different characters' own typical
  // (mean-of-takes) values disagree with each other, per coefficient.
  final characterMeans = [
    for (final summaries in summariesByCharacter.values) _meanVector(summaries),
  ];
  final betweenClass = _variance(characterMeans);

  // Floor guards against a coefficient with genuinely zero within-class
  // variance (e.g. every take came out identical) producing an infinite
  // or NaN weight.
  const epsilon = 1e-6;
  final rawWeights = [
    for (var i = 0; i < coefficientCount; i++)
      betweenClass[i] / (withinClass[i] + epsilon),
  ];

  // Rescaled so the weights average to 1.0 -- redistributes how much
  // each coefficient counts rather than inflating or shrinking the
  // distance metric's overall scale, so a caller's existing
  // "close enough" threshold stays meaningful without needing to be
  // recalibrated every time enrollment changes.
  final averageWeight =
      rawWeights.reduce((sum, weight) => sum + weight) / coefficientCount;
  return [for (final weight in rawWeights) weight / averageWeight];
}

List<double> _meanVector(List<List<double>> vectors) {
  final count = vectors.first.length;
  final mean = List<double>.filled(count, 0);
  for (final vector in vectors) {
    for (var i = 0; i < count; i++) {
      mean[i] += vector[i];
    }
  }
  for (var i = 0; i < count; i++) {
    mean[i] /= vectors.length;
  }
  return mean;
}

List<double> _variance(List<List<double>> vectors) {
  final mean = _meanVector(vectors);
  final count = mean.length;
  final variance = List<double>.filled(count, 0);
  for (final vector in vectors) {
    for (var i = 0; i < count; i++) {
      final diff = vector[i] - mean[i];
      variance[i] += diff * diff;
    }
  }
  for (var i = 0; i < count; i++) {
    variance[i] /= vectors.length;
  }
  return variance;
}
