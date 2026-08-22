import 'dart:typed_data';

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

  /// The enrolled character whose reference recording [queryPcm16] is
  /// closest to, or null if nothing enrolled is within [maxDistance].
  Future<String?> match(
    Uint8List queryPcm16, {
    double maxDistance = placeholderMaxDistance,
  }) async {
    final queryFeatures = extractMfcc(queryPcm16);
    if (queryFeatures.isEmpty) return null;

    String? bestCharacter;
    var bestDistance = double.infinity;
    for (final character in await _store.enrolledCharacters()) {
      final reference = await _store.loadRecording(character);
      if (reference == null) continue;
      final referenceFeatures = extractMfcc(reference);
      if (referenceFeatures.isEmpty) continue;

      final distance = dtwDistance(queryFeatures, referenceFeatures);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestCharacter = character;
      }
    }
    return bestDistance <= maxDistance ? bestCharacter : null;
  }
}
