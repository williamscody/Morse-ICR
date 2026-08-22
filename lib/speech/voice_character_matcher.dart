import 'dart:typed_data';

import '../debug_log.dart';
import 'dtw.dart';
import 'enrollment_store.dart';
import 'mfcc.dart';

/// Placeholder DTW-distance cutoff for "close enough to count as a
/// match" (morse_icr_spec.md section 38: matched "if any element is
/// close enough"). Not validated against real speech -- section 38 is
/// explicit that the matching threshold needs on-device investigation,
/// the same way `character_recognizer.dart` flags its own matching as a
/// first attempt rather than a finished design. Step 4 tunes this
/// against Bill's actual voice once this is wired into real captured
/// audio.
const double placeholderMaxDistance = 40.0;

/// Matches a freshly-recorded clip against the learner's enrolled
/// reference recordings (morse_icr_spec.md section 38), via MFCC
/// feature extraction ([extractMfcc]) and dynamic time warping
/// ([dtwDistance]) against every enrolled character.
class VoiceCharacterMatcher {
  VoiceCharacterMatcher(this._store);

  final EnrollmentStore _store;

  // Reference clips don't change between matches within a session, but
  // [match] used to re-run MFCC extraction on every enrolled character
  // on every single call -- on-device profiling (Milestone 13,
  // 2026-08-21) found this was ~85% of total match cost at a
  // 40-character enrollment. Cached per character, populated lazily on
  // first use; [invalidateCache] drops it so a session that starts
  // after re-enrollment (via Settings' "Personalize Recognition")
  // doesn't keep matching against stale features.
  final Map<String, List<List<double>>> _referenceFeatureCache = {};

  /// Drops any cached reference features -- call at the start of a new
  /// listening session so re-enrollment since the last one is reflected.
  void invalidateCache() {
    _referenceFeatureCache.clear();
  }

  /// The enrolled character whose reference recording [queryPcm16] is
  /// closest to, or null if nothing enrolled is within [maxDistance].
  ///
  /// [candidates], when given, restricts comparison to that subset of
  /// enrolled characters -- e.g. the active training set, rather than
  /// every character ever enrolled. Training a character set never asks
  /// about characters outside it (morse_icr_spec.md section 27), so
  /// comparing against the rest only adds false-positive risk (and DTW
  /// cost) for candidates that could never be a valid answer anyway.
  /// Defaults to matching against everything enrolled.
  Future<String?> match(
    Uint8List queryPcm16, {
    double maxDistance = placeholderMaxDistance,
    Set<String>? candidates,
  }) async {
    final queryMfccStopwatch = Stopwatch()..start();
    final queryFeatures = extractMfcc(queryPcm16);
    queryMfccStopwatch.stop();
    if (queryFeatures.isEmpty) return null;

    String? bestCharacter;
    var bestDistance = double.infinity;
    var referenceCount = 0;
    var referenceMfccMicros = 0;
    var dtwMicros = 0;
    final loopStopwatch = Stopwatch()..start();
    for (final character in await _store.enrolledCharacters()) {
      if (candidates != null && !candidates.contains(character)) continue;

      final refMfccStopwatch = Stopwatch()..start();
      final referenceFeatures = await _referenceFeaturesFor(character);
      refMfccStopwatch.stop();
      referenceMfccMicros += refMfccStopwatch.elapsedMicroseconds;
      if (referenceFeatures == null || referenceFeatures.isEmpty) continue;
      referenceCount++;

      final dtwStopwatch = Stopwatch()..start();
      final distance = dtwDistance(queryFeatures, referenceFeatures);
      dtwStopwatch.stop();
      dtwMicros += dtwStopwatch.elapsedMicroseconds;

      if (distance < bestDistance) {
        bestDistance = distance;
        bestCharacter = character;
      }
    }
    loopStopwatch.stop();
    // Milestone 13 diagnostic-only (2026-08-21): breaks down match()'s
    // cost so a slow match at a large active/enrolled set (e.g. a full
    // A-Z pass) can be attributed to query MFCC extraction, reference
    // MFCC extraction, or DTW itself, rather than guessed at from the
    // single aggregate "match took Xms" VoiceResponseListener already
    // logs. Remove once the resulting optimization work lands.
    logDebug(
      'voice: match breakdown -- n=$referenceCount '
      'queryMfcc=${queryMfccStopwatch.elapsedMilliseconds}ms '
      'refMfcc=${referenceMfccMicros ~/ 1000}ms '
      'dtw=${dtwMicros ~/ 1000}ms '
      'loop=${loopStopwatch.elapsedMilliseconds}ms '
      'bestDistance=${bestDistance.toStringAsFixed(1)} -> $bestCharacter',
    );
    // Milestone 13 diagnostic-only (2026-08-21): delta coefficients
    // showed no effect on accuracy after being added -- checking
    // whether they're numerically drowned out by the (much larger-
    // magnitude) static coefficients in DTW's unweighted per-frame
    // Euclidean distance, which would make them a near no-op despite
    // being computed correctly. Remove once weighting is decided.
    logDebug(
      'voice: feature magnitude -- static=${_averageAbsMagnitude(queryFeatures, 0, mfccStaticCoefficientCount).toStringAsFixed(3)} '
      'delta=${_averageAbsMagnitude(queryFeatures, mfccStaticCoefficientCount, queryFeatures.first.length).toStringAsFixed(3)}',
    );
    return bestDistance <= maxDistance ? bestCharacter : null;
  }

  double _averageAbsMagnitude(List<List<double>> frames, int start, int end) {
    var sum = 0.0;
    var count = 0;
    for (final frame in frames) {
      for (var i = start; i < end; i++) {
        sum += frame[i].abs();
        count++;
      }
    }
    return count == 0 ? 0 : sum / count;
  }

  Future<List<List<double>>?> _referenceFeaturesFor(String character) async {
    final cached = _referenceFeatureCache[character];
    if (cached != null) return cached;
    final reference = await _store.loadRecording(character);
    if (reference == null) return null;
    final features = extractMfcc(reference);
    _referenceFeatureCache[character] = features;
    return features;
  }
}
