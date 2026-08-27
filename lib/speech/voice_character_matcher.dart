import 'dart:typed_data';

import '../debug_log.dart';
import 'coefficient_weights.dart';
import 'dtw.dart';
import 'enrollment_store.dart';
import 'mfcc.dart';

/// DTW-distance cutoff for "close enough to count as a match"
/// (morse_icr_spec.md section 38: matched "if any element is close
/// enough").
///
/// Was 40.0 -- rescaled (2026-08-24) alongside [dtwDistance] switching
/// its normalization from `n + m` to `min(n, m)` (see that function's own
/// doc comment for why). For two same-length clips that switch exactly
/// doubles the reported distance (`min(n,n) = n = (n+n)/2`), and inflates
/// it further the more two clips' lengths differ -- this threshold moves
/// with it so "close enough" still means the same real-world thing it
/// did before, rather than every match starting to come back null.
const double placeholderMaxDistance = 80.0;

/// Matches a freshly-recorded clip against the learner's enrolled
/// reference recordings (morse_icr_spec.md section 38), via MFCC
/// feature extraction ([extractMfcc]) and dynamic time warping
/// ([dtwDistance]) against every take of every enrolled character,
/// keeping the closest take per character -- "best-of-N templates",
/// standard for a multi-exemplar nearest-template matcher. Moved from
/// one take per character to this (Milestone 13, 2026-08-22) after
/// on-device data showed a single take made matching sensitive to that
/// one recording's own noise (mic distance, background noise, momentary
/// vocal variation) rather than the character's actual acoustic
/// signature.
class VoiceCharacterMatcher {
  VoiceCharacterMatcher(this._store);

  final EnrollmentStore _store;

  // Reference clips don't change between matches within a session, but
  // [match] used to re-run MFCC extraction on every enrolled character
  // on every single call -- on-device profiling (Milestone 13,
  // 2026-08-21) found this was ~85% of total match cost at a
  // 40-character enrollment. Cached per character (one entry per
  // enrolled take), populated lazily on first use; [invalidateCache]
  // drops it so a session that starts after re-enrollment (via
  // Settings' "Personalize Recognition") doesn't keep matching against
  // stale features.
  final Map<String, List<MfccSequence>> _referenceFeatureCache = {};

  // Per-coefficient weights ([computeCoefficientWeights]), derived from
  // the whole enrollment and shared across every [match] call in a
  // session -- computed lazily (needs every enrolled character's
  // reference features, not just whichever [candidates] this particular
  // call is restricted to) and cached alongside them, since both are
  // invalidated by the same event (re-enrollment).
  List<double>? _coefficientWeights;
  bool _coefficientWeightsComputed = false;

  /// Drops any cached reference features -- call at the start of a new
  /// listening session so re-enrollment since the last one is reflected.
  void invalidateCache() {
    _referenceFeatureCache.clear();
    _coefficientWeights = null;
    _coefficientWeightsComputed = false;
  }

  Future<List<double>?> _weights() async {
    if (_coefficientWeightsComputed) return _coefficientWeights;
    final takesByCharacter = <String, List<MfccSequence>>{
      for (final character in await _store.enrolledCharacters())
        character: await _referenceFeaturesFor(character),
    };
    _coefficientWeights = computeCoefficientWeights(takesByCharacter);
    _coefficientWeightsComputed = true;
    return _coefficientWeights;
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
    final queryFeatures = extractMfcc(queryPcm16);
    if (queryFeatures.isEmpty) return null;
    final weights = await _weights();

    String? bestCharacter;
    var bestDistance = double.infinity;
    // Per-character best (not per-take) -- logged below so a mismatch
    // can be diagnosed against the *margin* between the winner and
    // whatever the "right" answer actually scored, not just which one
    // won (morse_icr project memory: distance logging was stripped
    // during Milestone 13 cleanup, then found to be needed again
    // 2026-08-24 investigating why a short spoken form like "e" never
    // wins even against a genuine, cleanly-recorded "e" query).
    final distanceByCharacter = <String, double>{};
    for (final character in await _store.enrolledCharacters()) {
      if (candidates != null && !candidates.contains(character)) continue;

      final referenceTakes = await _referenceFeaturesFor(character);
      if (referenceTakes.isEmpty) continue;

      // Best-of-N: this character's distance is however close its
      // *closest* enrolled take is, not an average -- a query only
      // needs to resemble one genuine take of a character, not all of
      // them (different takes legitimately vary in pace/emphasis).
      var characterBest = double.infinity;
      for (final referenceFeatures in referenceTakes) {
        final distance = dtwDistance(
          queryFeatures,
          referenceFeatures,
          weights: weights,
        );
        if (distance < characterBest) characterBest = distance;
      }
      distanceByCharacter[character] = characterBest;
      if (characterBest < bestDistance) {
        bestDistance = characterBest;
        bestCharacter = character;
      }
    }

    final ranked = distanceByCharacter.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    logDebug(
      'match: top candidates '
      '${ranked.take(4).map((e) => '${e.key}=${e.value.toStringAsFixed(2)}').join(', ')}',
    );

    return bestDistance <= maxDistance ? bestCharacter : null;
  }

  Future<List<MfccSequence>> _referenceFeaturesFor(String character) async {
    final cached = _referenceFeatureCache[character];
    if (cached != null) return cached;
    final takes = await _store.loadRecordings(character);
    final features = [for (final take in takes) extractMfcc(take)];
    _referenceFeatureCache[character] = features;
    return features;
  }
}
