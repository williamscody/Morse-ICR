import 'dart:math' as math;

/// Selects random characters from an active character set.
///
/// Uniform random selection, independent from call to call -- weighted
/// and problem-character-biased selection are future work per
/// morse_icr_spec.md section 15.
///
/// Previously avoided immediately repeating the last selection, per an
/// earlier version of section 15. Reverted (Milestone 13, 2026-08-22):
/// on-device use showed that rule visibly distorting output at small
/// active-set sizes -- a 2-character focus set, for instance, was
/// forced into perfect strict alternation (H, S, H, S, ...) every
/// single time, which reads as far less random than genuine uniform
/// selection actually is, not more.
class CharacterSelector {
  CharacterSelector({math.Random? random}) : _random = random ?? math.Random();

  final math.Random _random;

  /// Returns a uniformly random character from [characters].
  ///
  /// Throws [ArgumentError] if [characters] is empty.
  String next(List<String> characters) {
    if (characters.isEmpty) {
      throw ArgumentError('Cannot select from an empty character set');
    }
    return characters[_random.nextInt(characters.length)];
  }
}
